# Loremaster's Armoury — Network/Sync Reference

Sourced from a read-only audit of `C:\Users\danjo\source\repos\Loremasters-Armoury\` (snapshot dated Apr 29 2026 on disk; no live verification against Workshop bundle).

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
