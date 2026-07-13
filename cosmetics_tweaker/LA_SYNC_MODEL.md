# Loremaster's Armoury — Network/Sync Reference

Sourced from a read-only audit of `C:\Users\danjo\source\repos\Loremasters-Armoury\` (snapshot dated Apr 29 2026 on disk; no live verification against Workshop bundle).

> LA doc ownership map (issue #432): THIS doc owns LA's own internals + the §6
> bridge gotcha catalogue. The bridge end-to-end architecture lives in
> `docs/CROSS_MOD_ARCHITECTURE.md` "Loremaster's Armoury Bridge"; the sync-state
> invariants/audit in `docs/LA_SYNC_CORE_AUDIT.md`; dependency rows in
> `MOD_DEPENDENCIES.md`.

---

## 1. LA's net-sync architecture

**LA does NOT synchronize weapon/shield/hat visuals between peers.** There is no LA-defined RPC, no VMF shared-state table, no broadcast of the user's chosen skin keyed by peer/career.

### Evidence

- **Only two RPC hooks exist**, both *intercepting vanilla RPCs* for the LA pickup-quest system, not custom messages:
  - `scripts/mods/Loremasters-Armoury/rpc_hooks/hooks.lua:7` — hooks `NetworkTransmit.send_rpc_server` to short-circuit `rpc_generic_interaction_request` and `rpc_spawn_pickup_with_physics` when the unit is an LA quest pickup (book/crate/gem). No new RPC is registered.
  - `scripts/mods/Loremasters-Armoury/rpc_hooks/new_rpc_funcs.lua:1-198` — the table of intercept handlers. Every entry returns to the vanilla RPC pipeline; none broadcasts.
  - The only `send_rpc_*` LA *originates* anywhere is for a quest-boss explosion (`buffs/halescourge_boss_debuff.lua:99,101,104`) — gameplay, not cosmetics.
- **No `SimpleHuskInventoryExtension`, `HuskAttachmentExtension`, or any `Husk*` cosmetic hook exists** in the entire `scripts/` tree (grep returns zero matches). The `NetworkLookup.husks[...] = 1` writes at `utils/hooks.lua:1137` and `achievements/quest_letters.lua:151-153` are aliasing LA's quest *interactor unit* paths into vanilla's husk-spawn lookup index 1 ("overloading the 1 key so the netlookup tables aren't different across users" — author's comment line 1135). They are NOT husk extensions for cosmetic items.

### How "sync" actually works in LA

LA's visual changes are driven entirely by **per-user VMF dropdown settings** (`Loremasters-Armoury_data.lua:24-345`: `setting_id = "weapons"`, `"hats"`, `"armor"`, plus dynamic `shield_sub_choice` widgets). The `mod.update(dt)` loop in `Loremasters-Armoury.lua:42-215` polls `mod.SKIN_CHANGED` every frame and calls `mod.re_apply_illusion(Armoury_key, skin, unit)` against the *local* `level_world`, `character_preview`, or `armory_preview` world.

The pipeline ends in **`mod.apply_new_skin_from_texture` (`utils/funcs.lua:59-113`)** which walks `Unit.num_meshes` / `Mesh.material` and calls `Material.set_texture(mat, slot, path)` — a **shared-resource write** on the underlying material asset. There is no peer broadcast. Every machine sees only the skins its own LA settings selected for whichever weapon-skin key (`es_1h_sword_skin_02` etc.) the *local LA-using player* maps Armoury_key onto.

### Side-effect: same skin key = same visual on all clients running LA

Because LA *also* mutates the global tables `WeaponSkins.skins[skin].right_hand_unit`, `.inventory_icon`, `ItemMasterList[skin].unit`, and `NetworkLookup.inventory_packages[<custom>] = NetworkLookup.inventory_packages[<vanilla>]` (forward+reverse) — see `utils/funcs.lua:118-152`, `swap_units_new` — clients running LA who happen to have *the same Armoury_key selected for the same skin* will see the same custom mesh because vanilla equip RPCs send the *skin name* (e.g. `es_1h_sword_skin_02`), which each LA client then locally rewrites to the LA unit/material. **Clients with different LA selections see different meshes for the same remote player.** Clients without LA loaded see the vanilla skin.

### Smell: GameSession.create_game_object hook returns a fake go_id

`utils/hooks.lua:1688-1694` — `mod:hook(GameSession, "create_game_object", function(func, self, ...) if not self then return math.random(400, 500) end return func(self, ...) end)` — labelled "temp fix for clients errors when using mod". This is a sign that LA's NetworkLookup hijacks (forward+reverse rewrites) cause occasional GameSession failures on clients; the workaround papers over them.

---

## 2. Per-player visuals

**LA itself supports only one skin choice per (player, weapon-skin-key) — and that choice is the local viewer's choice.** There is no architecture for "player A wears red Reiland shield, player B wears blue Reiland shield, visible to each other".

### Architectural blockers

1. **All paint goes through `Material.set_texture` on shared materials.** See `funcs.lua:38, 41, 44, 49`. Per `reference_la_offhand_paint.md`, this is the same pitfall cosmetics_tweaker hit and pivoted away from (v0.7.84 → v0.8.18) to `Unit.set_texture_for_materials`. LA never made that pivot. Two units sharing the same material asset cannot display different textures.
2. **Global mutation of vanilla skin tables.** `funcs.lua:104-110` writes `WeaponSkins.skins[skin]['inventory_icon']` and `ItemMasterList[skin]['inventory_icon']` directly. Per-player visual variance would require these to be *not* mutated and an instance-only path to be taken — which LA does not have.
3. **Drive signal is `mod:get(skin)` (a single VMF setting key per skin).** There is no per-player, per-peer, or per-career-instance dimension. The viewer's setting decides what every "skinX equipped" mesh looks like, regardless of which character/peer is wearing it.
4. **`GearUtils.apply_material_settings` (the safe per-unit instance override path)** is used only for the LA quest-reward sword (`utils/hooks.lua:100, 106, 915, 980`, `achievements/sword_enchantment.lua:95`) and is gated on `Unit.get_data(child, "use_vanilla_glow")`. It is NOT used for the main weapon-skin paint pipeline.

### What this means for cosmetics_tweaker

If cosmetics_tweaker wants "each player picks their own LA skin, every peer sees that exact choice on that player", that requirement is **not satisfiable by piggybacking on LA's selection state**. LA writes globally; whatever the *viewer* picked is what the *viewer* sees on everyone. The only way to give that capability is to author it from scratch on top of cosmetics_tweaker's own VMF shared-state plumbing — and pivot away from `Material.set_texture` to `Unit.set_texture_for_materials` (which cosmetics_tweaker already does in `_la_bridge.lua`'s `_paint_offhand_textures_locally`).

---

## 3. Husk-spawn pipeline

**There is no LA-specific husk hook.** Husk weapons spawn via vanilla `SimpleHuskInventoryExtension` paths, which read the (possibly LA-mutated) `WeaponSkins.skins[skin].right_hand_unit` / `_3p`. If the vanilla path was rewritten by LA's `swap_units_new` (`utils/funcs.lua:118-152`) to LA's custom unit path, the husk will spawn the LA mesh.

### Package load flow

LA pre-loads its master package at mod boot via the `.mod` file:

```
-- Loremasters-Armoury.mod:
packages = { "resource_packages/Loremasters-Armoury/Loremasters-Armoury" }
```

This master package globs `materials/*`, `units/*`, `textures/*` (per LA's compile output documented in `reference_la_custom_mesh_pattern.md` Part 5). All unit data is in memory before any equip happens — there is no on-demand load path.

LA additionally pre-loads a handful of vanilla packages via `Managers.package:load(..., "global")` (`Loremasters-Armoury.lua:14-21`): Morris common packages and `wpn_brw_flaming_sword_01_t2` / `_3p`.

### PackageManager hooks (silencer pattern)

LA hooks `PackageManager.load` / `unload` / `has_loaded` (`utils/hooks.lua:270-295`) to silently no-op on its own unit paths (`pacakge_tisch` built at line 260-268 from `SKIN_LIST[k].new_units[1]` / `[1]_3p` for every `kind = "unit"` skin). `has_loaded` returns `true` for those paths. This means **vanilla code calling `package:load(<LA's custom unit path>)` no-ops successfully and `has_loaded` reports loaded** — the data is already mapped via the master glob. See `reference_la_custom_mesh_pattern.md` Part 2.

### NetworkLookup.inventory_packages aliasing

`swap_units_new` (`funcs.lua:118-152`) and `swap_units_old` (`funcs.lua:154-190`) write the custom path → vanilla index forward AND set the reverse `[vanilla_index] = custom_path` direction. This is a **destructive hijack** — once activated, the engine's reverse network lookup for that index returns the LA path globally, for that session. Cross-cross-ref `feedback_vt2_strict_lookup_rawget.md`: NetworkLookup tables have strict metatables; LA bypasses by direct subscript.

### Crash window

A remote player wearing an LA skin **does not** require the local viewer to load anything extra IF:
- the local viewer has LA loaded AND
- the local viewer's master package supplies the LA unit (always, since glob).

A remote player wearing an LA skin **WILL** crash a viewer who has not run `Loremasters-Armoury`'s master package — `World.spawn_unit` will fail because the LA unit data was never bundled. **In practice this means: LA being a host-only mod is unsafe — non-LA clients joining an LA host will fault when an LA-wearing player spawns near them** (no protection has been authored; LA assumes everyone loaded LA). This is the inverse of the issue in `reference_la_offhand_paint.md` where the user pre-loads via `Managers.package:load(path, "cosmetics_tweaker", nil, false)` synchronously to defend.

### Hooks that do touch husk-style spawn

- `mod:hook_safe(World, "link_unit", ...)` (`utils/hooks.lua:96-109`) — applies vanilla material settings (glow) when a unit's `Unit.get_data(unit, "use_vanilla_glow")` data block is non-nil. Fires on every world.link_unit call (including husk attachment), but only acts on units that LA's compile-time `.unit` data marked as glowable. This is LA's safe path.
- `mod:hook(AttachmentUtils, 'link', ...)` (`utils/hooks.lua:112-165`) — when a unit being attached matches LA's `SKIN_LIST[Armoury_key].new_units[1]` OR has unit_data `(skin_name + hand_unit)` matching, queue it for re-paint via `mod.level_queue`. This fires for both first-person and husk attachments, so a husk weapon that resolved to an LA mesh gets re-painted. But the paint primitive is still the shared-material `Material.set_texture`.

---

## 4. Material/glow application

### Two distinct paint paths exist in LA

| Path | API | Scope | File:line |
|---|---|---|---|
| **Main skin paint** | `Material.set_texture(Mesh.material(unit_mesh, j), slot, path)` | SHARED — mutates the underlying material asset globally for that frame and afterwards | `utils/funcs.lua:38, 41, 44, 49` |
| **Quest-reward glow** | `GearUtils.apply_material_settings(unit, WeaponMaterialSettingsTemplates[glow])` | INSTANCE — vanilla path uses `Unit.set_texture_for_materials` per-unit (see `gear_utils.lua:150`) | `utils/hooks.lua:100, 106, 915, 980`; `achievements/sword_enchantment.lua:95` |

### The shared-material problem in LA's main path

`funcs.lua:33-53` walks meshes and calls `Material.set_texture(mat, diff_slot, new_diff)` where `mat = Mesh.material(mesh, j)`. In Stingray, `Mesh.material(...)` returns the *shared material instance* baked into the unit's compiled bundle. Writing through it mutates every unit referencing the same compiled material. LA "works" only because:
- The frame-rate update loop (`Loremasters-Armoury.lua:42-215`) re-applies skins continuously, so if any other unit overwrote the texture, LA stomps back next frame.
- Every LA-using viewer mutates the same global slot to the same value, so there's no perceptible per-frame flicker between users (only against vanilla / non-LA-aware mods).

### What LA cannot do (because of the shared-material commitment)

- Two units sharing one material → two different paints in the same frame.
- A non-mutating texture preview (everything visible inherits the LA bind).
- Restore to vanilla without engine reload — `Material.reset_texture` doesn't exist and `Material.get_texture` doesn't exist in this engine build (per `reference_la_offhand_paint.md` "Engine APIs that matter"), so the original binding cannot be snapshotted.

### Settings_id wiring

The dropdown widgets feed `mod:get(skin)` → which the update loop reads to decide which Armoury_key to apply per registered skin (`Loremasters-Armoury.lua:46-51`). `mod.SKIN_CHANGED` is the bookkeeping table tracking whether each skin currently has an active LA texture/model swap (so that going back to default can be detected and partially undone — see `funcs.lua:236-279` `re_apply_illusion`).

---

## 5. Gaps — what LA does NOT support that cosmetics_tweaker may want

| Gap | LA state | Implication for cosmetics_tweaker |
|---|---|---|
| **Per-player visual choice visible to peers** | Unsupported. Single VMF setting per (viewer, skin); applies globally locally. | Cannot pull this from LA. Would need cosmetics_tweaker-owned VMF shared-state, keyed by `peer_id` + career, broadcast on equip / late-join. |
| **Per-unit instance painting** | Unsupported on the main path. LA uses shared-material writes. | cosmetics_tweaker already uses `Unit.set_texture_for_materials` in `_la_bridge.lua` (the right pattern). When integrating with LA's selections, do NOT call LA's `apply_new_skin_from_texture` — it's globally mutating. Cosmetics_tweaker's memo already enshrines this: `reference_la_offhand_paint.md` "NEVER call LA.apply_new_skin_from_texture for offhand". |
| **Restore-on-deselect** | Unsupported. Once `Material.set_texture` writes, the original binding is unrecoverable until engine reload. | Anything cosmetics_tweaker drives through LA's path is one-way until restart. Use instance paints to retain reversibility. |
| **kind="unit" mesh swap on a remote (non-LA) viewer** | Unsupported. LA's mesh data is in LA's master package; a non-LA-loaded viewer cannot spawn the unit. | If cosmetics_tweaker is a sibling mod relying on LA being present, document the dependency. If LA is absent, gracefully fall back to no-mesh-swap (kind="texture" still works for vanilla-mesh skins). |
| **kind="unit" in customization-preview world** | LA does not handle the LootItemUnitPreviewer null-material case. | cosmetics_tweaker already documents this fix in `reference_la_kind_unit_pipeline.md` (per-context `Unit.set_all_materials` before paint). LA gets away with it because LA only paints in `level_world`, `character_preview`, `armory_preview` — not `LootItemUnitPreviewer`'s world. |
| **Husk safety on non-LA clients** | Unsupported. No guard on remote-peer cosmetic data. | If cosmetics_tweaker drives "host has LA on, client doesn't", and the host's equip RPC re-routes through LA's mutated `WeaponSkins.skins[...].right_hand_unit`, the client will crash on spawn. Need cosmetics_tweaker-side gating: never broadcast / never rewrite skin tables when an LA-only unit path would result. |
| **Late-joiner sync** | Unsupported by LA (no broadcast to sync). | cosmetics_tweaker needs its own VMF shared-state pub-sub for late-joiners. Cross-ref `reference_ct_graph_snapshot_rpc.md` for the host-broadcast + client-overwrite + late-arrival-reapply pattern. |
| **String cap on VMF RPCs (500 chars)** | Not a concern for LA (no RPCs). | For cosmetics_tweaker: any per-player table broadcast must respect `reference_vmf_rpc_string_cap.md` STRING_MAX=500; chunk large payloads. |
| **Gated registration drift across peers** | LA pre-registers everything unconditionally at mod boot. | cosmetics_tweaker must do the same for any NetworkLookup additions — cross-ref `feedback_vt2_gated_registration_diverges.md`. Don't gate registration on a per-user toggle. |

---

## 6. cosmetics_tweaker's LA bridge — gotcha catalogue

cosmetics_tweaker reuses LA's `SKIN_LIST` data to drive its own per-instance picker, but does its own paint via `Unit.set_texture_for_materials` (NOT `Material.set_texture`) and its own per-context spawn handling. The following are crash modes and quiet-failure modes burned into the bridge across versions.

### 6.1 LA icon keys ≠ game `item_type` — alias before bucketing

When parsing LA `SKIN_LIST` `variant.icons` to drive per-weapon-type fanout in `_la_bridge.lua` / `_offhand_options`, the prefix extracted from each icon key (`<weapon_type>_skin_*`) is NOT guaranteed to match the game's `ItemMasterList[item].item_type` value the picker queries at runtime.

**Confirmed cases:**
- `es_sword_shield_breton_skin_*` (LA) → `es_1h_sword_shield_breton` (game item_type). LA omits the `_1h_` infix that the game's IML uses for the Bret 1h family.

If buckets are built by the icon-extracted prefix without translation, the pool builds under a key the game never queries. Log shows `[LA bridge] <wrong_key> offhand pool: N entries` AND `[LA paint] skip: no _offhand_selection for <correct_key>` simultaneously. Picker stays empty even though the data is "there." Cost 1 round-trip integrating Bret-authored LA shields (v0.8.21 → v0.8.22).

**How to apply:**
- Maintain `_LA_WEAPON_TYPE_ALIAS` in `_la_bridge.lua` translating LA-icon prefixes to game item_types.
- Apply via a `_normalize_weapon_type(wt)` helper in BOTH the icon-driven fanout loop AND `_LA_EXTRA_WEAPON_TYPES` lookup, so adding entries to either side never silently misses.
- When adding to `_LA_EXTRA_WEAPON_TYPES`, use the **game item_type** form directly. Cross-check by running `/la_offhand_dump` — `weapons=[...]` column should match the same item_type strings printed in `[LA bridge] <key> offhand pool:` registration log lines AND in-game `[LA paint] skip: no _offhand_selection for <key>` lines.
- When the next mismatch surfaces (likely a Kerillian or Bardin shield variant), add a row to `_LA_WEAPON_TYPE_ALIAS` rather than relying on memory.

### 6.2 LA hats: `kind="texture"` requires explicit `apply_new_skin_from_texture` on receivers

LA `SKIN_LIST` entries with `swap_hand = "hat"` come in two flavours:

**`kind = "unit"`** — fully custom mesh. `new_units[1]` points to a custom `.unit` file. `textures` may be empty. Visually correct after `create_attachment(slot_name, item_data)` alone — the mesh carries its own baked material.

**`kind = "texture"`** — vanilla mesh, recoloured. `new_units[1]` points to an EXISTING VANILLA hat unit (`is_vanilla_unit = true`). `textures[1]` points to an LA-shipped diffuse (e.g. `textures/Kruber_Grail_Knight_Helm/Pureheart/Kruber_Pureheart_helm_white_diffuse`). `create_attachment` alone gets the MESH right but the texture stays vanilla → user sees the right HAT in the WRONG COLOUR.

For `kind = "texture"`, AFTER `create_attachment` you MUST also call:

```lua
LA_BRIDGE._bridge_active = true
pcall(la.apply_new_skin_from_texture, armoury_key, world, vanilla_key, owner_unit)
LA_BRIDGE._bridge_active = false
```

The `_bridge_active` bracket signals our managed-apply context so LA's apply gate (`_la_bridge.lua`) doesn't reject the call. `owner_unit` is the wearer's `player_unit` (3P body); LA internally walks attachments to find the hat mesh and writes the texture via `Material.set_texture`.

**Why LA's own pipeline doesn't need this:** LA hooks the local equip flow and queues the hat unit in `mod.level_queue`. `LA.mod.update(dt)` iterates the queue and calls `apply_new_skin_from_texture(armoury_key, world, skin, unit)` per entry. That works for LOCALLY-equipped hats. But cosmetics_tweaker's `cos_la_apply` receiver path on REMOTE husks does NOT enter LA's queue — it calls `create_attachment` directly. So texture-variant hats appear in vanilla colours on peers unless cosmetics_tweaker explicitly calls `apply_new_skin_from_texture` on the receiver side.

**Burned v0.9.0-dev → v0.9.0.2-hotfix.** User equipped white Grail Knight Pureheart hat; emit + receive worked end-to-end (`applied=true`); user still saw default colour. Fix added `apply_new_skin_from_texture` to the `kind="hat"` receiver branch, mirroring `kind="armor"` and `kind="illusion"`.

**Enumeration:** grep LA's `skin_list.lua` for `kind = "texture"` entries to find all hats that need the paint call. Texture-paint hats: `Kruber_Pureheart_helm_white/red/blue/...`, `Kruber_Hippogryph_helm_white/red/...`. Custom-mesh hats: `Kruber_Goldcrown_helm`, etc. — these still work with `create_attachment` alone.

### 6.3 Custom-mesh shields (kind="unit") through the offhand picker — unsupported via LA helpers

LA's custom-mesh shields (`kind="unit"` entries in `Loremasters-Armoury/scripts/mods/Loremasters-Armoury/skin_list.lua`, e.g. `Kruber_empire_shield_basic2`, `Kerillian_elf_shield_basic_Avelorn01_mesh`) **cannot be safely exposed through cosmetics_tweaker's offhand picker by calling LA's helpers**. v0.8.11–v0.8.13 attempted three increasingly invasive integrations; all crashed.

**Why:**
1. The engine spawns the LA `.unit` fine (LA's resource_package globs `unit/material/texture = ["*/*"]`), but binding the materials requires LA's `swap_units_new` (`Loremasters-Armoury/scripts/mods/Loremasters-Armoury/utils/funcs.lua:118`) to alias `NetworkLookup.inventory_packages` AND mutate `WeaponSkins.skins[skin][hand]` — without that bookkeeping the mesh shows as magenta.
2. Calling LA's `mod.re_apply_illusion(armoury_key, skin, unit)` from outside its `mod.update` loop conflicts with that loop's own iteration. LA reads `mod:get(skin)` every tick and re-runs the same path with the persisted setting. Combined with stale `changed_model`/`changed_texture` flags, the next `swap_units_new` call (ours OR theirs) reads `inventory_packages[<la_path>.."_3p"]` against a strict `__index` that `error()`s on miss → instant crash. User crash GUID `60180105-bd15-49f2-9fa6-9f70dd851846`: `Table inventory_packages does not contain key: units/empire_shield/Kruber_Empire_shield02_mesh_3p` after the user clicked one LA option then another.
3. Every read of `NetworkLookup.inventory_packages` must use `rawget`. LA's helpers don't, so we can't safely call them — even pcall-guarded — without first wrapping every reference.

**How to apply:**
- `_la_bridge._is_supported_variant` rejects `kind="unit"` and `kind="texture" + new_units && !is_vanilla_unit` for the LA-helper path. Don't relax this without first solving (1)+(2).
- `kind="texture" + is_vanilla_unit` and pure paint-overs (no `new_units`) are safe and stay exposed.
- A real fix needs either (a) suspending LA's `mod.update` for skins we manage so its tick can't race ours, or (b) reimplementing `swap_units_new`/`swap_units_old` end-to-end with `rawget`/`rawset` and our own per-skin state machine, no LA function calls.
- The Bret-skin mesh-wrapping guard in `BackendUtils.get_item_units` (drop the mesh override when `resolved_skin` matches `_breton_` and selection has `la_armoury_key`) is unrelated and stays.

**cosmetics_tweaker's own kind="unit" pipeline (without calling LA helpers)** is described in 6.4 — it bypasses LA's funcs entirely.

### 6.4 LA kind="unit" via cosmetics_tweaker's own swap (offhand picker, row-2)

cosmetics_tweaker ships its own kind="unit" pipeline that doesn't go through LA's helpers. Recipe and failure-mode catalogue:

**What `kind="unit"` means in LA's `SKIN_LIST`:**
- **`kind="texture"`** — reuses a vanilla mesh, swaps textures via `Material.set_texture` / `Unit.set_texture_for_materials`. Works everywhere without special handling. Examples: Ostermark01, Kotbs.
- **`kind="unit"`** — ships a custom FBX mesh bundled in LA's `Loremasters-Armoury.package` (which globs `materials/*` / `units/*` / `textures/*`). The mesh's compiled `.unit` uses a `mat_to_use = "<vanilla path>"` directive at source time to inherit a shader graph — LA's bundle has no standalone `.material` file. Example: Kruber_empire_shield_basic1 (Reiland).

**Why kind="unit" is hard in the customization preview:**

`_apply_la_offhand_to_units` runs from THREE call sites:
1. **`GearUtils.create_equipment`** — in-game (mission body)
2. **`MenuWorldPreviewer/HeroPreviewer._spawn_item`** — inventory mannequin
3. **`LootItemUnitPreviewer.spawn_units`** — customization preview (the row-2 picker)

In (1) and (2), the LA mesh spawns with its `mat_to_use` material correctly resolved at engine level (and LA's own `HeroPreviewer._spawn_item_unit` hook re-paints the inventory mannequin after ours). In (3), the previewer's per-world resource graph is narrow: the material reference resolves to `#ID[00000000]` (Stingray's null sentinel) at spawn time. `Unit.set_texture_for_materials` then AVs at offset 0x8 walking meshes and dereferencing the null material's variable table.

Loading more packages does NOT fix this (v0.8.39 confirmed). Per-world material scope is the issue, not absence of the shader graph.

**The fix: per-context material swap.** In `_paint_offhand_textures_locally(unit, variant, armoury_key, context)`:
- For `context == "loot_previewer"`: call `Unit.set_all_materials(unit, parent_path)` to explicitly bind the vanilla material (the one LA's `mat_to_use` referenced). Engine binds the real material instead of `#ID[00000000]`. Then run `Unit.set_texture_for_materials` to paint LA's textures onto the now-real slots.
- For `context == "ingame"` or `"hero_previewer"`: early-return. The vanilla rendering path already handles those correctly; running the swap there OVERWRITES correct bindings and breaks scale (v0.8.47 regression).

`context` is threaded from the three call sites → `_apply_la_offhand_to_units` → `LA_BRIDGE.apply_offhand_to_unit` → `_paint_offhand_textures_locally`.

**Recipe for adding a new `kind="unit"` shield.** All three tables live in `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_bridge.lua`:

1. **`_LA_KIND_UNIT_TEXTURES[armoury_key]`** — manually extracted texture paths from the LA source `.unit` file's `colors / normals / MABs` blocks. SKIN_LIST entries for kind="unit" have no `textures` array.
   ```lua
   _LA_KIND_UNIT_TEXTURES = {
       Kruber_empire_shield_basic1 = {
           diff = "textures/Kruber_empire_shield_basic1/Kruber_empire_shield_basic1_diffuse",
           pack = "textures/Kruber_empire_shield_basic1/Kruber_empire_shield_basic1_combined",
           norm = "textures/Kruber_empire_shield_basic1/Kruber_empire_shield_basic1_normal",
       },
   }
   ```

2. **`M.la_kind_unit_parent_packages[armoury_key]`** — vanilla parent material path from LA `.unit`'s `mat_to_use` directive.
   ```lua
   M.la_kind_unit_parent_packages = {
       Kruber_empire_shield_basic1 = "units/weapons/player/wpn_empire_handgun_02_t2/wpn_empire_handgun_02_t2",
   }
   ```

3. **(Optional)** `M.la_kind_unit_preview_scale[armoury_key]` — per-shield override for the preview-only scale multiplier (defaults to `M.la_kind_unit_preview_scale_default = 2.0`). Only the customization-preview unit is scaled; in-game and inventory rendering are unaffected.

**Failure-mode catalogue (each one cost a version):**
- **v0.8.27** — Don't `Managers.package:load` LA's main package globally. LA has internal broken references that surface as fatal `[Engine Error]: Resource '#ID[...]' was not found` outside pcall.
- **v0.8.34 / v0.8.43** — Don't paint kind="unit" without first establishing a real material binding. Both crashed at AV 0x8 (GUIDs `a739e6e5`, `45a2a017`).
- **v0.8.39 / v0.8.40** — Parent-package preload via `LootItemUnitPreviewer.load_package` hook makes the shader graph globally loaded but does NOT fix per-world material binding. Necessary for the v0.8.47+ swap to find the parent material, but insufficient on its own.
- **v0.8.47** — Don't run the material swap in `"ingame"` or `"hero_previewer"` contexts. Overwriting correct material bindings with the handgun material causes massive in-game scale (different renderable metadata). Gate by call site, not by attempting to detect "is material null".

**Engine APIs that matter (v0.8.46 surface dump):**
- `Unit.set_all_materials(unit, material_path)` — replaces every material on the unit. Use for kind="unit" where the LA mesh has 1 mesh / 1 material slot.
- `Unit.set_material(unit, slot_name, material_path)` — per-slot replacement. Need to know the slot name; vanilla uses arbitrary strings (`"slot1"`, named slot like `"shield"`, or the renderable name).
- `Unit.set_local_scale(unit, node_index, Vector3(s,s,s))` — preview-only scaling.
- `Material.set_texture(mat, slot_hash, path)` — already used by `_la_bridge.lua` for kind="texture" painting.
- `Material.has_variable`, `Material.get_texture` — **DO NOT EXIST** in this engine build (v0.8.45 probe silently fell through). Don't gate logic on them.
- `Material.num_parameters / parameter_name / parameter_type` — exist but trigger a Stingray `resource_manager.cpp` fault that bypasses pcall. **Never call these** — see `cosmetics_tweaker.lua:435-438` memo.

Working baseline: v0.8.48 + v0.8.49 (2026-05-12). Reiland is the canonical first kind="unit" shipped. Future shields just need the three table entries — the per-context swap, scale, and paint pipeline handles the rest.

### 6.5 LA offhand paint pipeline (vanilla-mesh shields)

The independent offhand (shield) illusion picker in cosmetics_tweaker spans three render paths and several non-obvious traps. Settled architecture as of v0.7.84+:

**Three render paths.** Each must apply both the mesh override AND the LA texture paint:
1. **Customization preview** — `LootItemUnitPreviewer:spawn_units`. Hooked with `mod:hook` (NOT `hook_safe`) so we can capture the returned `units` array directly; `self._spawned_units` is only assigned in the *caller* (`_on_packages_loaded`) AFTER `spawn_units` returns. Use `units[1]` (left/shield) and `units[2]` (right/weapon).
2. **In-game body** — `GearUtils.create_equipment` hook. `result.left_unit_3p` / `.left_unit_1p` are the spawned shield units. Read `result.skin` to gate on has_skin.
3. **Inventory/equipment menu character preview** — `HeroPreviewer:_spawn_item` and `MenuWorldPreviewer:_spawn_item` (both routed through a `_spawn_item_post` hook). `item_name` here is the **WEAPON master key** (e.g. `es_breton_sword`), NOT a skin entry — `item_data.item_type == "weapon_skin"` returns false. Capture the `skin` arg from `equip_item` into a per-previewer map (`_equip_skin_by_item`, weak keys) and read it back in `_spawn_item_post` to set has_skin.

**Mesh resolution (`intended_unit`).** `variant.new_units[1]` from LA's SKIN_LIST is the source of truth. Don't try to derive from texture-path regex or icon keys — both produced visibly wrong meshes earlier.
- `kind = "texture"` + `new_units` + `is_vanilla_unit = true` → use `new_units[1]` as `intended_unit`. Examples: `Kruber_empire_shield_hero1_Ostermark01` → `wpn_es_deus_shield_03`.
- `kind = "texture"` + no `new_units` → `intended_unit = nil`. Don't override the mesh; LA's diffuse paints onto the user's current shield. Works for the 5 Bret/GK pure-texture variants (`Kruber_Grail_Knight_Bastonne02`, `Kruber_bret_shield_basic*`, `Kruber_bret_shield_hero1_Alberic01`).
- `kind = "unit"` → see 6.3 / 6.4 for handling. Roughly half of LA's Kruber shield variants (the basic Empire ones) are filtered from the LA-helper path.

**Package preload (critical — was the recurring crash source).** Vanilla VT2 packages 1p and 3p meshes **separately**. LA's own bootstrap proves it:
```
Managers.package:load("units/.../wpn_X",      "global")
Managers.package:load("units/.../wpn_X_3p",   "global")
```
And `WeaponUtils.get_weapon_packages` confirms: `packages[#packages+1] = unit_name` AND `packages[#packages+1] = unit_name .. "_3p"` are queued separately.

When the user picks an offhand option, our `BackendUtils.get_item_units` hook overrides `result.left_hand_unit` to a unit whose package may not be in the equipped skin's load chain. The engine asserts in `world.spawn_unit` if the package isn't fully loaded. Three rules:
1. **Sync load** — `Managers.package:load(path, "cosmetics_tweaker", nil, false)`. Async (`true`) returns immediately and the load completes "later"; if the user clicks Apply before async completes, crash. Sync blocks (`ResourcePackage.load + flush`, see `foundation/scripts/managers/package/package_manager.lua:80-86`) — the hitch is unnoticeable for one shield package.
2. **Load BOTH halves** — `<unit_path>` and `<unit_path>_3p`. The in-game body needs both; the customization preview only needs 3p.
3. **Defensive `_override_package_ready` gate in the hook** — verify both packages are loaded via `Managers.package:has_loaded(...)` before applying the override.

**NEVER call LA.apply_new_skin_from_texture for offhand.** LA's apply mutates `WeaponSkins.skins[skin].inventory_icon` and `ItemMasterList[skin].inventory_icon` permanently. Once we trigger it, inventory grid icons leak LA heraldics globally. Use the local re-implementation `_paint_offhand_textures_locally(unit, variant)` in `_la_bridge.lua`.

**Paint primitive: `Unit.set_texture_for_materials`, NOT `Material.set_texture` (v0.8.18 fix).** The original implementation used `Material.set_texture(Mesh.material(unit_mesh, j), slot, path)` — that mutates the SHARED material baked into the vanilla shield's compiled bundle. Every other unit referencing that material (other shield illusions, the inventory mannequin, the customization preview) inherited the LA texture, and once LA's package was unloaded those leaked bindings flipped to the engine's missing-asset magenta. Caused 8+ user-reported "magenta on default shield" / "wrong texture on a different shield" issues across v0.7.84–v0.8.16 that were patched surface-level instead of fixing the primitive.

The vanilla-VT2 way to bind a texture per unit is `Unit.set_texture_for_materials(unit, slot_name, texture_path)` — used by `gear_utils.lua:150` (MaterialSettingsTemplates), `cosmetic_utils.lua:72`, `flow_callbacks_foundation.lua:939`, `outline_system.lua:666`. The engine sets up a per-unit override; the shared material is never written. Unit destruction (re-equip) drops the override automatically.

Shield slot hashes (3p):
- diff: `texture_map_c0ba2942`
- pack: `texture_map_0205ba86`
- norm: `texture_map_59cd86b9`

(LA uses different slots for `swap_hand="armor"` (`texture_map_64cc5eb8` / `_861dbfdc` / `_abb81538`) and 1p fps units; for shield 3p these are correct.)

**Limitation of the new path:** `Unit.set_texture_for_materials` applies to all materials on the unit — no `skip_meshes` / `textures_other_mesh` per-mesh granularity. The first focused-triage candidate (`Kruber_empire_shield_hero1_Ostermark01`) has empty `skip_meshes` so it works. Future LA shields with non-empty skip_meshes need a per-mesh fallback (re-introduce `Mesh.material(...)` iteration but use `Mesh.set_texture_for_materials` if the engine exposes it, OR clone material per-unit via whatever cloning primitive Stingray exposes).

**Auto-select on customization screen open.** `_setup_illusions` resolves the equipped illusion via `Managers.backend:get_interface("items"):get_skin(item.backend_id)` (vanilla-crafted weapons sometimes have `item.skin = nil` on the BackendItem) → looks up `WeaponSkins.skins[skin].left_hand_unit` → finds the option in our pool whose `unit` or `intended_unit` matches → auto-selects. Stale `_offhand_selection` entries whose mesh no longer matches the rendered shield are discarded so the picker always reflects what's visible.

**`item_data.backend_id` resolution chain (v0.7.101).** `BackendUtils.get_item_units` is called from `GearUtils.create_equipment` with `(item_data, nil, nil, career_name)` — the explicit backend_id and skin args are nil. Vanilla resolves via `item_data.backend_id` internally (`backend_utils.lua:156`: `local backend_id = item_data.backend_id or backend_id`). Our hook MUST mirror this — check `item_data.backend_id` as a third fallback after the explicit args. Without it, the hook bails at `has_skin=false` for every in-game equip and (a) the user's row-2 selection never reaches the player body, (b) we never get to re-route the spawn away from a runed-shield path the engine hasn't preloaded → `world.spawn_unit` "Unit not found" crash. Crash GUID 1a7b27db documented this.

**Known limitations:**
- LA `kind="unit"` variants (Empire basic 1/2/3 with custom heraldic shapes) handled via the cosmetics_tweaker-owned pipeline (6.4); LA-helper path stays filtered.
- Variants without `new_units` paint onto whatever the current illusion's shield mesh is, so heraldic UVs may not always match perfectly. Bret variants tested OK because all GK shields are visually similar.
- **Glow/runed/magic shield illusions show no LA paint** (confirmed v0.7.99 user testing 2026-05-06). Skins like `es_sword_shield_breton_skin_03_runed_01` use `wpn_emp_gk_shield_*_runed_01` meshes whose emissive material doesn't expose the standard `texture_map_c0ba2942` diffuse slot. `Material.set_texture` returns `ok=true` but no pixel changes — every LA option visually identical to equipped shield. LA's `icons` table per variant enumerates compatible skins (e.g. `Reynard01.icons.es_sword_shield_breton_skin_03_runed_01 = "kruber_bret_shield_basic1_reynard01_blueglow_icon"`, with separate `_blueglow` / `_purpleglow` icons for runed variants). We don't honor that table.
- **LA paint sticks across shield changes** (confirmed v0.7.99 user testing 2026-05-06). Material is shared — `Material.set_texture` mutates the asset in place, so any other shield mesh sharing that material file inherits the override globally until the engine reloads it. Can't reset (`Material.reset_texture` doesn't exist), can't snapshot original (`Material.get_texture` doesn't exist). LA's normal mode "fixes" this by re-painting every shield in the world every frame — we paint once at spawn.

**Diagnostic commands:**
- `/la_offhand_dump` — dumps each LA shield variant's resolution (intended_unit, source, texture path, icon keys).
- `/offhand_debug` — dumps the picker pool and current `_offhand_selection`.
- `[LA paint]` log lines from `_apply_la_offhand_to_units` show why paint was skipped or which unit it was applied to.

### 6.6 Offhand package force-preload (host's pick crashes clients otherwise)

**The bug.** When the user picks a cross-character shield mesh via cosmetics_tweaker's offhand picker (e.g. "GK Shield Blue" = `wpn_emp_gk_shield_03` from `_offhand_options.es_1h_sword_shield`) OR equips a cosmetics_tweaker custom illusion that references a non-default mesh (e.g. `ct_es_mace_gk_shield_01` whose `left_hand_unit = wpn_emp_gk_shield_03`), the HOST sees it fine but the CLIENT crashes the moment the host wields the item.

**Crash signature:**
```
[0] =[C]: in function spawn_unit
[1] @scripts/network/unit_spawner.lua:354: in function hook_chain
[3] @scripts/network/unit_spawner.lua:385: in function spawn_local_unit_with_extensions
[4] @scripts/unit_extensions/default_player_unit/inventory/gear_utils.lua:217: in function func
[7] @scripts/unit_extensions/default_player_unit/inventory/simple_husk_inventory_extension.lua:659: in function _wield_slot
[10] @scripts/entity_system/systems/inventory/inventory_system.lua:378
[11] @scripts/network/network_event_delegate.lua:52
<Error Context> RPC rpc_wield_equipment </Error Context>
unit_name = "units/weapons/player/wpn_emp_gk_shield_03/wpn_emp_gk_shield_03_3p"
```

**Why it happens.** Vanilla VT2 only preloads packages keyed off `right_hand_unit` / `left_hand_unit` of items in the player's INVENTORY. If a peer doesn't have an item that uses shield_03 in their loadout, shield_03's package never preloads on that peer.

When host equips a cosmetics_tweaker custom illusion / offhand-picker option that uses shield_03:
1. Host preloads sync via `_preload_offhand_package` (works on host).
2. Vanilla `ProfileSynchronizer` starts an **async** load on peers when the profile syncs.
3. ALSO vanilla `rpc_wield_equipment` fires from host to peer (synchronous).
4. Client's `SimpleHuskInventoryExtension._wield_slot` calls `BackendUtils.get_item_units` → gets shield_03 path → `GearUtils.spawn_inventory_unit` → engine `spawn_unit` → **CRASH** because the async load hasn't completed yet.

Race: synchronous wield RPC wins, package isn't ready, hard crash.

**The fix.** Bulk force-load at mod init on EVERY peer. Idempotent function `_force_load_all_offhand_packages()` walks three sources:

1. `_offhand_options[*]` — vanilla-mesh shield pool (lines 1574+; ~12 entries per character × 5 characters)
2. `LA_BRIDGE.la_offhand_options_by_weapon_type[*]` — LA shield variants
3. `_custom_illusions[*]` — cosmetics_tweaker-injected illusions like `ct_es_mace_gk_shield_01`

For each `opt.unit` / `opt.intended_unit` / `illusion.right_hand_unit` / `illusion.left_hand_unit`, calls `_preload_offhand_package(path)` which loads both `path` and `path .. "_3p"`. `_preloaded_offhand_packages` set dedups across calls. Total ~50 small packages.

Wired into `mod.update` once `_la_bridge_init_done = true` so LA pool is populated first. Function early-returns via `_force_loaded_all_offhand_done` after the first successful pass.

**Burned v0.9.0.3-hotfix → v0.9.0.4-hotfix** (2026-05-19). User's PC-B crashed mid-keep when PC-A equipped a Bret GK shield variant (`wpn_emp_gk_shield_03`). Crash dump captured.

Note: some custom unit paths require entries in `scripts/network_lookup/inventory_package_list.lua` to load at all; verify with `Application.can_get` first before adding to the force-load set.

### 6.7 Husk RPC race: `cos_la_apply` vs vanilla `rpc_create_attachment`

When host equips an LA `kind="texture"` hat (e.g. `Kruber_Hippogryph_helm_white`):

1. Host's `PlayerUnitAttachmentExtension.create_attachment` runs locally → calls `CosmeticUtils.update_cosmetic_slot` → cosmetics_tweaker's hook fires → `_send_la_apply` → host broadcasts `cos_la_apply` "all".
2. Host's `spawn_resynced_loadout` also sends `rpc_create_attachment` via `send_rpc_clients` for the vanilla item_id (cosmetics_tweaker substituted the name to vanilla for net-safety).

Both RPCs travel the same reliable channel. On a healthy network they arrive in send order. But for the FIRST hat-state delivery (hot_join_sync replay OR first-time equip of a new hat), the order can flip:

1. **Client receives `cos_la_apply` first** → cosmetics_tweaker's `_apply_la_on_unit kind="hat"` runs:
   - `ext._attachments.slots["slot_hat"] = nil` (teardown)
   - `ext:create_attachment("slot_hat", item_data)` with `item_data.unit = la_unit_path` → husk spawns LA mesh
   - `la.apply_new_skin_from_texture(...)` paints the LA texture on the LA mesh
   - Visual: LA-coloured hat. ✓
2. **Client receives vanilla `rpc_create_attachment` AFTER** → husk's `PlayerHuskAttachmentExtension.create_attachment` line 52-56 sees the LA unit as `old_slot_data` → `self:remove_attachment(slot_name)` destroys it (taking the painted material binding with it) → spawns the VANILLA hat unit (no `item_data.unit` override) → vanilla mesh, vanilla texture. ✗

Net result: client sees vanilla. User has to unequip + re-equip on host because the second equip cycle has only one RPC pair in flight, no late vanilla RPC follows cosmetics_tweaker's spawn.

**The fix (v0.9.0.9-hotfix).** Hook `PlayerHuskAttachmentExtension.create_attachment`. When the wearer's peer_id has a cached LA hat entry in `_la_equips_by_peer[wearer_peer]["slot_hat"]`, patch `item_data.unit = la_unit_path` BEFORE delegating to vanilla. Vanilla spawns the LA mesh. Then call `apply_new_skin_from_texture` on the just-spawned hat unit.

Idempotent: whichever RPC arrives second still produces the LA-textured hat as the final state.

Prerequisite: `_la_equips_by_peer` must be populated on CLIENTS, not just the host. The v0.9.0.7-hotfix mirror write in the broadcast receiver provides this.

**Generalizable pattern.** Any time cosmetics_tweaker spawns a unit via `ext:create_attachment` from a network-driven event, the same race can happen with vanilla `rpc_create_attachment`. The fix:
1. Maintain a per-peer cache of what cosmetic state should be applied (`_la_equips_by_peer`).
2. Hook the vanilla extension's spawn-side method (`create_attachment`).
3. In the hook, look up the cache by wearer peer, patch `item_data` in place, delegate, then paint.

Apply to other slots beyond `slot_hat` if similar races emerge for `slot_skin` (armor) or weapon-side equips. The v0.9.0.9 fix is hat-only as that was the observed bug.

Reminder: `PlayerHuskAttachmentExtension` is the husk-side parallel class to `PlayerUnitAttachmentExtension`; hook each separately (the `Simple*Extension` / `SimpleHusk*Extension` pattern applies across VT2 extension code).

### 6.8 `hook_safe` shadow: `_tpe.lua` reserves `SimpleHuskInventoryExtension.wield`

`cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_tpe.lua:511` registers:

```lua
mod:hook_safe(SimpleHuskInventoryExtension, "wield", ...)
```

Any LATER `mod:hook_safe("SimpleHuskInventoryExtension", "wield", ...)` registration ANYWHERE in cosmetics_tweaker.lua is **silently dropped** by VMF with:

```
WARNING (hook_safe): Attempting to rehook active hook [wield]
```

VMF's `hook_safe` does not chain — the framework drops the second registration and keeps the first (or vice versa depending on framework version; either way the second callback never fires).

**Symptom.** A re-paint / re-sync callback that "should" fire on every husk wield event silently never fires. No error, no warning visible to the user, just dead code. v0.9.0.5 burned: the per-wield LA-texture re-paint never ran on any user, because TPE's hook had already claimed the slot.

**The fix.** Either:
1. **Fold the callback into TPE's existing hook** — single hook_safe with a body that calls both TPE's logic and the new logic. Expose the new logic as a module-level function on `mod` so multiple files can share one registration.
2. **Hook a different method on the same class.** `_wield_slot` is called from inside `wield` and not multi-hooked. `mod:hook("SimpleHuskInventoryExtension", "_wield_slot", function(func, self, ...) ... end)` chains correctly (mod:hook with the wrap-and-call pattern does support chaining).
3. **Hook `wield_previous`, `add_equipment`, or another less-trafficked method** that gives the same lifecycle signal.

The v0.9.0.10 fix used option 2: moved the re-paint logic into the `_wield_slot` wrap that already existed (for husk-mesh-swap context setting). Runs after vanilla returns, when units are freshly spawned in the slots.

**Detection.** Boot log shows the warning explicitly:
```
[Lua] [MOD][VMF][WARNING] (hook_safe): Attempting to rehook active hook [wield]
```
Grep for this in boot logs after adding any new `hook_safe(SimpleHuskInventoryExtension, ...)` registration. Same rule applies to `destroy_slot` and `destroy` on the same class — audit each hook_safe registration whenever a new one is added.

See `HUSK_HOOK_FIRING_DIAGNOSIS.md` for the full diagnosis walkthrough that produced this rule.

### 6.9 Vanilla offhand mesh sync (#416) — the parallel store beside `_la_equips_by_peer`

The `cos_la_apply` sync (§6.7 and the whole LA store) is **armoury-key-centric**: every
store write, reconcile, paint and hot-join replay keys on `entry.armoury_key`. That
covers LA shields, but a per-hand **vanilla** shield / held-weapon unit pick
(`opt.unit` / `opt.intended_unit`, e.g. Stirland, Bretonnian, GK shields) carries no
`armoury_key`, so it had NO networked representation: the wearer saw it locally (via the
non-husk `BackendUtils.get_item_units` `_offhand_selection` override), but every peer's
husk spawned the wearer's BASE offhand (#416).

**Design (v0.9.82-dev): a parallel store, reusing the existing channel.**

- **Store:** `mod._offhand_mesh_by_peer[wearer_peer][slot_or_template][hand_field] = unit_path`.
  Deliberately SEPARATE from `_la_equips_by_peer` so the armoury-key machinery
  (reconcile / `_apply_la_on_unit` / `_ensure_offhand_mesh` / state replay) stays
  byte-for-byte untouched — a vanilla entry can never confuse an LA gate, and vice-versa.
- **Channel:** the SAME `cos_la_apply` / `cos_la_apply_req` / `cos_la_state_req` VMF mod
  RPCs. One ADDITIVE optional payload field `offhand_unit` (a unit-path STRING, or `""`
  = clear/revert-to-base). Handled by a branch placed BEFORE the `armoury_key` gate in
  each receiver, exactly like the `revert` branch. `COS_RPC_SCHEMA` is NOT bumped
  (additive-optional rule); old peers ignore the field.
- **Emit:** `mod._send_offhand_mesh` (routing cloned from `mod._send_la_revert`:
  host-short-circuit / client-request / deferred-queue). A committed vanilla offhand press
  queues a deferred `offhand_unit` message drained on Apply/screen-exit under the same
  `bid|hand` key as the LA emit, so **last-pick-wins across LA and vanilla presses**.
- **Recv:** `mod._store_offhand_mesh_recv` writes the parallel store and enforces
  per-`(wearer, slot, hand)` **mutual exclusion** vs the LA store in BOTH directions
  (a vanilla pick clears a same-hand LA entry; an LA pick clears a same-hand vanilla
  entry — the LA recv armoury store also nils the parallel hand). Then `mod._la_native_pulse`
  re-renders the wearer so the swap shows without a manual re-wield.
- **Husk apply:** the `BackendUtils.get_item_units` husk branch reads the parallel store
  AFTER the LA branch and forces each recorded hand's mesh, package-gated via
  `_override_package_ready` (`<unit>` + `<unit>_3p`) — a non-resident unit degrades to the
  base mesh, never the `World.spawn_unit` C-assert (§6.6 / #270 / #392 class).
- **Hot-join:** the `cos_la_state_req` reply replays the vanilla meshes too (reuses
  `cos_la_apply`); the disconnect purge drops the peer's parallel entries.

**Why this cannot crash a non-mod peer (the #421 floor).** The whole path is a VMF mod
RPC — VMF delivers it only to peers running cosmetics_tweaker, so a non-mod peer never
receives `offhand_unit` and simply renders the base offhand. `offhand_unit` is a plain
string; it is never a `NetworkLookup` index and never rides a vanilla RPC param, so no
modded key can reach a non-mod peer's strict `__index`. The §5/§31 sender-side null/
substitution on the vanilla RPCs is untouched.

**Remaining (not in the v0.9.82 slice):** `opt.vanilla_skin`-only opts (a paired vanilla
weapon_skin with no `opt.unit` mesh) are not networked (the store carries a unit path
only); the data-driven picker registration (CWV shields missing from the picker,
fix-direction #3) is separate; cross-session auto re-emit of a vanilla pick on rejoin
relies on the wearer re-Applying (in-session apply + hot-join are covered).

### 6.10 Deus-yield: weapon-side LA overrides are suppressed in Chaos Wastes (#518)

Deus (Chaos Wastes) weapons are GENERATED instances: `deus_weapon_generation.lua`
rolls `item.skin` per rarity at creation (`:246-249`) and re-rolls it on every
shrine upgrade (`:318-321`) — the skin change is the upgrade's visual feedback.
Because `create_item` clones the base item (`key = base_item`, same weapon
template, `:185-202`), the TEMPLATE-key namespace that committed offhand picks
are stored under (§6.9 / the EMIT-ON-EXIT dual-namespace write) matches every
CW-generated weapon, and the template-keyed re-apply paths repainted the keep's
LA pick over the rolled deus skin on every wield (issue #518).

**Rule (v0.9.88-dev):** `mod._la_deus_weapon_yield()` returns true only when
`Managers.mechanism:current_mechanism_name() == "deus"` **and** the current game-mode
key is `"deus"`. The mechanism alone is not an expedition boundary: vanilla assigns
`morris_hub`/Pilgrimage Chamber to `inn_deus`, route and shrine nodes to `map_deus`,
and only playable expedition nodes to `deus` (`deus_mechanism.lua:28-35,730-744`;
`deus_node_settings.lua:3-22`). The gate reads the live
`Managers.state.game_mode:game_mode_key()` (`game_mode_manager.lua:915-917`) with
`Managers.level_transition_handler:get_current_game_mode()` as its early-load fallback
(`level_transition_handler.lua:387-389`). If neither key is ready yet, the current
level uses vanilla's own classifier: `morris_hub` is hub, `dlc_morris_map` is map,
and every other deus level is ingame (`deus_mechanism.lua:49-59`). Weapon-side applies (kind
`offhand`/`illusion`, plus the §6.9 vanilla-mesh store and the live-body
`_offhand_selection` mesh/paint) consult it and YIELD only in actual missions;
hats/armor and staging-hub weapon cosmetics stay live.
Gates sit at: the `get_item_units` husk LA + vanilla branches, the live-body
`_offhand_selection` branch (create_equipment only; preview surfaces keep the
pick — they render the keep instance), `_apply_la_offhand_to_units` "ingame",
`_apply_la_on_unit` (terminal backstop, dedup'd `[la-state] DEUS-YIELD
suppressed` printf), the local `_wield_slot` re-apply, and `_la_reconcile`
(terminal reason `"deus-yield"`, treated like `"no-entry"` by the pending
drain). Stores/emits are NOT gated — state stays warm so LA re-asserts the
moment the context leaves an active `deus` game mode. A deduplicated
`[la-state] DEUS-YIELD bypass mechanism=deus game_mode=inn_deus` marker proves the
Pilgrimage exception. rt-check: `cos_la_deus_yield_active_mission_only`. Follow-up
(not shipped): inject LA variants
into the deus skin pools (`WeaponSkins.skin_combinations`) per the issue's
desired end state.

---

## Key file paths

- `C:\Users\danjo\source\repos\Loremasters-Armoury\Loremasters-Armoury.mod`
- `C:\Users\danjo\source\repos\Loremasters-Armoury\itemV2.cfg`
- `C:\Users\danjo\source\repos\Loremasters-Armoury\scripts\mods\Loremasters-Armoury\Loremasters-Armoury.lua` (update loop)
- `C:\Users\danjo\source\repos\Loremasters-Armoury\scripts\mods\Loremasters-Armoury\Loremasters-Armoury_data.lua` (VMF widget tree)
- `C:\Users\danjo\source\repos\Loremasters-Armoury\scripts\mods\Loremasters-Armoury\utils\funcs.lua` (paint primitive, swap_units_new/old, re_apply_illusion)
- `C:\Users\danjo\source\repos\Loremasters-Armoury\scripts\mods\Loremasters-Armoury\utils\hooks.lua` (hook surface, PackageManager silencer, NetworkLookup.husks alias)
- `C:\Users\danjo\source\repos\Loremasters-Armoury\scripts\mods\Loremasters-Armoury\rpc_hooks\hooks.lua` (vanilla-RPC intercept only)
- `C:\Users\danjo\source\repos\Loremasters-Armoury\scripts\mods\Loremasters-Armoury\rpc_hooks\new_rpc_funcs.lua` (quest pickup intercept table)
- `C:\Users\danjo\source\repos\Loremasters-Armoury\scripts\mods\Loremasters-Armoury\skin_list.lua` (SKIN_LIST data; 1765 lines)
