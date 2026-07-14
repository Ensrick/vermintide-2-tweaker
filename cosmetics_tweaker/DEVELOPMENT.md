# Cosmetics Tweaker — Development Notes

Detailed technical reference for the `cosmetics_tweaker` mod. Read alongside `CHANGELOG.md` (version-by-version history) and `TODO.md` (open work).

## Module map (v0.9.79-dev Phase 3 OOP split)

`cosmetics_tweaker.lua` is still the primary file (~9,090 lines) — this is an
IN-PROGRESS decomposition (OOP_REFACTOR_PLAN WS5), not a finished one. Phase 1
carved out the three cleanest self-contained concerns; Phase 2 carved out the
render-path scale/grip apply layer; Phase 3 carved out the glow apply subsystem.
The LA-bridge + husk, the HeroWindowItemCustomization offhand-picker UI suite, the
wire-safety senders, the per-peer glow broadcast RPC layer, and the render-path
HOOKS themselves all still live in the entry file, pending later phases (run in
fresh sessions). Note the split carried forward from Phase 2 and extended in Phase 3:
the render HOOKS (`create_equipment` / `_spawn_item_post` /
`LootItemUnitPreviewer.spawn_units`) stay in the entry, but the scale/grip apply
helpers (Phase 2) and the glow apply / owner-peer helpers (Phase 3) they call moved
to `_cos_render.lua` / `_cos_glow.lua` and are invoked via `mod._cos.*`.

**Shared namespace `mod._cos`** (the event_tweaker `mod._evt` pattern,
PROJECT_STANDARDS § 2.2a) carries cross-module state. It is created in the entry
manifest (just after the `_flush_log` helper) and populated with the handles the
`_cos_*` modules consume BEFORE they are `mod:dofile`'d: `U` (the `_cosmetic_unlocks`
map), `LA_BRIDGE`, `flush_log`, `skin_requires_unowned_dlc`, `custom_skin_keys`
(shared with the wire-safety senders + regression suite), `custom_illusions` (shared
with the offhand force-loader), and `apply_cosmetic_unlocks` (exported by the unlocks
module for the entry's lifecycle callbacks). Phase 2 added `is_unit`, `scale_units`,
`offset_units`, and `apply_unit_path_scale_hand` (exported by `_cos_render`): the render
hooks in the entry call the apply helpers via `mod._cos.*`, and the entry keeps an
`is_unit` alias for the LA-paint + glow-dump code that still lives there. Phase 3 added
`apply_glow_override` and `glow_owner_peer_for_unit` (exported by `_cos_glow`): the same
three render hooks call them via `mod._cos.*` for the per-equip glow paint. `_cos_glow`
also owns the init of the `mod._glow_by_peer` per-peer cache and the
`mod._unit_to_backend_id` weak map; the per-peer glow broadcast RPC layer that stays in
the entry reads/writes `mod._glow_by_peer` through a byte-identical entry-local alias.
`mod:dofile` is NOT a singleton, so modules never dofile each other — each is dofile'd
exactly once from the manifest.

| Module | Owns / public surface (on `mod._cos` unless noted) |
|---|---|
| `cosmetics_tweaker.lua` (entry) | MOD_VERSION (launcher parses it here — never move it), the load banner/echo, the top embed manifest (`_la_prefix_embedded`, `_material_hijack_embedded`, `_moreitemslibrary_embedded`, `_cosmetic_unlocks`=`U`, `_la_bridge`, `_tpe`, `_glow_picker`, `_la_persistence`, `_la_okri`, `_ui_dump`, `_cos_diag_lasync`), the `mod._cos` namespace setup + `_cos_*` manifest, the mod-wide lifecycle callbacks (`on_game_state_changed`/`on_setting_changed`/`on_disabled`/`on_unload`), and everything not yet extracted: the render-path HOOKS (`create_equipment` / `_spawn_item_post` / `spawn_units`; their scale/grip apply helpers moved to `_cos_render` in Phase 2 and their glow apply/owner-peer helpers to `_cos_glow` in Phase 3), the per-peer glow broadcast RPC layer + `/glow_status`+`/glow_trace` commands (the glow APPLY pipeline moved to `_cos_glow`), LA-bridge integration + husk, offhand picker + customization UI, the #421 wire-safety senders, the #282 MH release lifecycle, and the `/cos_regression_test` suite. |
| `_cos_diagnostics.lua` | Read-only dump/probe chat commands (`/flush_log`, `/dump_glows`, `/dump_skin_rarities`, `/dump_all_names`, `/check_vmf`, `/probe_hat`, `/probe_cosmetics`). Reads `mod._cos.flush_log`; no exports. |
| `_cos_illusions.lua` | Custom weapon-illusion + LA shield skin injection into `ItemMasterList`/`WeaponSkins`/`NetworkLookup` (`_custom_illusions`, `_la_shield_skin_specs`), the `get_unlocked_weapon_skins` unlock hook, the `_G.Localize` display-name hook. Populates `mod._cos.custom_skin_keys`; exports `mod._cos.custom_illusions`. |
| `_cos_unlocks.lua` | Per-career cosmetic unlocks (`apply_cosmetic_unlocks` + `_CHARACTER_CAREERS`), Unlock-All portrait frames, vanilla-unobtainable cosmetic grants, the two `PlayFabMirrorAdventure` hooks, `/frames_status` + `/cosmetics_status`. Exports `mod._cos.apply_cosmetic_unlocks`. |
| `_cos_render.lua` | Render-path weapon scale/grip apply layer (v0.9.78-dev Phase 2): the two visual-override data tables (`_unit_path_scale_overrides` + `_breton_sword_thiccc`, empty `_weapon_grip_offsets`) and the resolve/apply helpers (`_resolve_for_career`, `_resolve_render_unit_path`, `_resolve_factor`, `_apply_unit_path_scale_hand`, `_scale_units`, `_offset_units`), plus the `_is_unit` liveness primitive. Exports `mod._cos.{is_unit, scale_units, offset_units, apply_unit_path_scale_hand}`; reads nothing off `mod._cos`. The render HOOKS that drive these stay in the entry. |
| `_cos_glow.lua` | Weapon glow APPLY subsystem (v0.9.79-dev Phase 3): the `_COLOR_PRESETS` table, the shader-variable brightness/group maps (`_GLOW_VAR_BRIGHTNESS` + `_GLOW_GROUP_COLOR_SETTING`), the per-peer glow read helpers (`_glow_get` family), `_glow_owner_peer_for_unit`, `_apply_glow_to_unit` / `_apply_glow_override`, `mod._reapply_glow_on_wielded`, the template-mutation apply hook (`_hook_apply_with_template_mutation` on `GearUtils`/`CosmeticUtils`/`_G.apply_material_settings`) + `mod._try_install_flow_glow_hook`, the `_cosmetics_tweaker_glow` `MaterialSettingsTemplate` + its `GearUtils.spawn_inventory_unit` injection hook. Captures `mod._cos.is_unit`; inits `mod._glow_by_peer` + `mod._unit_to_backend_id`; reads `mod._per_item_glow_runtime` (owned by `_glow_picker`). Exports `mod._cos.{apply_glow_override, glow_owner_peer_for_unit}`. The three render HOOKS that drive the paint, the per-peer glow broadcast RPC layer, and `/glow_status`+`/glow_trace` stay in the entry. |
| `_cos_offhand_preload_lifecycle.lua` | Pure generation-scoped ownership/readiness ledger for #565 async offhand packages. It has no engine or mod dependencies so shared-handle callbacks retained after unload can be reproduced offline. The entry owns all PackageManager calls and bounded diagnostics. |
| `_cos_weapon_pose_policy.lua` / `_cos_weapon_poses.lua` | #485 pure authored-pose catalog plus the local modded-realm SocialWheelUI adapter. Replaces only the gathered pose rows; never grants backend ownership or mutates ItemMasterList. Missing-parent fallback is bounded diagnostics pending compatibility proof. |
| `_la_shield_parity.lua` | Pure #266 availability policy: the single complete Kruber native/CWV shield item-type catalogue and its weapon-agnostic fan-out helper. `_la_bridge.lua` consumes it; it owns no render or engine surface. |

Pre-existing `_*.lua` modules (`_la_bridge`, `_material_hijack_embedded[_anim]`,
`_moreitemslibrary_embedded`, `_cosmetic_unlocks`, `_tpe`, `_glow_picker`,
`_la_persistence`, `_la_okri`, `_ui_dump`, `_cos_diag_lasync`, `_cos_offhand_preload_lifecycle`, `_la_shield_parity`, `_la_prefix_embedded`)
predate this split and are captured as entry locals by the top manifest — leave
their internals alone.

### Where new code goes

- **New diagnostic dump/probe command** → `_cos_diagnostics.lua`. Route through
  engine `printf` / `mod:info` (users run with mod logs OFF), `_flush_log` at the end.
- **New custom illusion / weapon-skin or LA-shield injection** →
  `_cos_illusions.lua`. Register the key into `mod._cos.custom_skin_keys` so the
  wire-safety senders null it on the wire.
- **New hat/skin/frame unlock or backend-mirror grant** → `_cos_unlocks.lua`; walk the
  DLC three-places checklist (`mod._cos.skin_requires_unowned_dlc`) before any
  `_unlocked_*` write.
- **New weapon-model scale or grip-offset override** → `_cos_render.lua`. Add a
  `_unit_path_scale_overrides` entry (keyed by unit-path substring) or a
  `_weapon_grip_offsets` entry (keyed by item name + career prefix); the render hooks
  in the entry already call `mod._cos.scale_units` / `.offset_units` per equip, so no
  new call site is needed. Need a liveness check? use `mod._cos.is_unit`.
- **New glow color/shader-variable/preset or glow apply-path change** → `_cos_glow.lua`.
  Register a new variable in `_GLOW_VAR_BRIGHTNESS` (+ `_GLOW_GROUP_COLOR_SETTING` for a
  new component) per GLOW_SYSTEM §9; the three render hooks in the entry already call
  `mod._cos.apply_glow_override`, so no new call site is needed. Glow SYNC/RPC changes
  (per-peer `cos_glow_apply` broadcast) and the `/glow_status`+`/glow_trace` commands
  stay in the entry.
- **Anything touching the LA bridge/husk, the offhand picker, the wire-safety senders,
  the per-peer glow broadcast RPC layer, or the render-path HOOKS** → still in
  `cosmetics_tweaker.lua` until a later phase extracts them (the render hooks' scale/grip
  apply helpers already live in `_cos_render.lua` and their glow apply helpers in
  `_cos_glow.lua`); grep ALL files for an existing hook on the `(Class, method)` before
  adding one (VMF drops the second — NON-NEGOTIABLE 8).
- **New cross-module value** → export onto `mod._cos` in the owning module (which must
  be earlier in the manifest than its consumers) and localize it at the consumer's top.

## Independent offhand (shield) illusion picker

The two-row picker on the weapon customization screen lets the user pick a shield independent of the weapon illusion. Vanilla shield options have `unit` set; LA (Loremaster's Armoury) options have `la_armoury_key`, `vanilla_skin`, and `intended_unit`.

### Dual-weapon ownership contract (#583)

Dual weapons reuse the same per-backend/per-hand substrate without pretending
the offhand is a shield. Vanilla's normal illusion row is the sole owner of the
main/right hand. Cosmetics adds one left/offhand row sourced from that family's
exact hand column; `Follow Main Illusion` stores no override. Native definitions
are available at Cosmetics load, while CWV's seven generated dual families are
built lazily after CWV registers its string-keyed skins.

The native reference is `scripts/settings/dlcs/bless/weapon_skins_bless.lua`:
the `wh_dual_hammer_skin_*` records carry both hand fields and
`wh_dual_hammer_skins` supplies the rarity buckets. The owning item type is
`wh_dual_hammer` in `item_master_list_bless.lua`. Do not infer hand meshes from
display names or inventory icons; source the authored hand field.

Committed direct meshes persist as `offhands[backend_id][left_hand_unit].unit_path`.
Restore and remote husk application accept the path only when it remains in the
current item type's compatible left-hand pool. A salvaged item, removed variant,
wrong hand, missing package, or mismatched family yields to the normal paired
illusion. Network commits reuse `cos_la_apply`'s additive `offhand_unit` field:
one last-choice queue entry per backend item and hand, host-authoritative cache,
transition rebroadcast, and the existing acknowledged/bounded hot-join pull.

### Render paths
LA paint and mesh override must apply on three independent render paths:

| Path | Hook target | Skin signal | Notes |
|------|-------------|-------------|-------|
| Customization preview | `LootItemUnitPreviewer:spawn_units` (`mod:hook`, NOT `hook_safe`) | `item.skin` set | `self._spawned_units` is assigned by the *caller* AFTER `spawn_units` returns; capture the returned `units` array directly |
| In-game body | `GearUtils.create_equipment` | `result.skin` set | spawns both 1p and 3p halves |
| Inventory/equipment menu character preview | `HeroPreviewer:_spawn_item` and `MenuWorldPreviewer:_spawn_item` (via `_spawn_item_post`) | `_equip_skin_by_item[previewer][item_name]` populated by `equip_item` hook | `item_name` is the WEAPON master key (not a skin entry) — we MUST capture the `skin` arg from `equip_item` for has_skin to work |

### Mesh resolution (`intended_unit`)
For LA options, the target mesh comes from `variant.new_units[1]` in LA's SKIN_LIST. This is the **only** reliable source — texture-path regex and lex-sorted icon keys both produced visibly wrong meshes in earlier versions.

| variant kind | `new_units` | `is_vanilla_unit` | Action |
|--------------|-------------|-------------------|--------|
| `texture` | set | `true` | Use `new_units[1]` as `intended_unit`. Vanilla mesh + LA texture paint. |
| `texture` | nil | n/a | `intended_unit = nil`. Don't override mesh; LA's diffuse paints onto whichever shield the user's current illusion provides. (Bret/GK pure-texture variants.) |
| `unit` | set | n/a | **Filtered out** of the picker. Points to LA's custom-authored mesh files (e.g. `units/empire_shield/...`) with no standalone package; spawning crashes `world.spawn_unit`. Restoring requires hooking LA's package-load bootstrap. |

### Package preload (critical — was the recurring crash source)
1p and 3p meshes are **separate packages** in vanilla VT2 (confirmed by `WeaponUtils.get_weapon_packages` and LA's bootstrap, which loads both halves explicitly).

When the user picks an offhand override, our `BackendUtils.get_item_units` hook sets `result.left_hand_unit` to a path whose package may not be in the equipped skin's package chain. The engine asserts if the unit isn't loaded.

Rules:
1. **Async, non-prioritized load only.** `Managers.package:load(path, "cosmetics_tweaker_offhand", callback, true, false)`. The 1P+3P `Application.can_get` gate keeps an override hidden until the units are spawnable, so there is no reason to block startup with `ResourcePackage.flush`.
2. **Load both halves.** `<unit_path>` AND `<unit_path>_3p`. The in-game body needs both; the customization preview only needs 3p.
3. **Defensive gate.** `_override_package_ready(unit_path)` in the `BackendUtils.get_item_units` hook verifies both units via `Application.can_get("unit", ...)` before applying the override.
4. **Generation-scoped callback.** Vanilla retains callbacks on a shared in-flight package when our reference unloads but another owner remains. Invalidate the lifecycle generation before unloading; a callback with the dead token must never recreate readiness state. Never mutate PackageManager's private callback table.
5. **One owned reference per path.** Dedupe before `load`, release the exact sorted ownership snapshot once on mod unload, and keep detailed late-callback/release-failure diagnostics capped at four rows.

### `has_skin` gate (don't mutate base templates)
The `BackendUtils.get_item_units` mesh override and the LA paint must both skip when no illusion is equipped — applying overrides to the base weapon template would leak LA visuals onto items the user didn't customize.

Per render path:
- `BackendUtils.get_item_units` hook: gate on `resolved_skin` (the `skin` arg, fall back to `Managers.backend:get_interface("items"):get_skin(backend_id)`).
- Customization preview: `item.skin ~= nil` OR `item_data.item_type == "weapon_skin"`.
- In-game body: `result.skin ~= nil`.
- Inventory character preview: `item_data.item_type == "weapon_skin"` OR `_equip_skin_by_item[previewer][item_name]` populated.

### NEVER call `LA.apply_new_skin_from_texture` for offhand
LA's apply function mutates `WeaponSkins.skins[skin].inventory_icon` and `ItemMasterList[skin].inventory_icon` **permanently**. Once we trigger it, vanilla inventory icons leak LA heraldics globally. Use the local re-implementation `_paint_offhand_textures_locally(unit, variant)` in `_la_bridge.lua` — it only touches the supplied unit's mesh materials via `Material.set_texture(mat, slot, path)` using the shield slot hashes:
- diff: `texture_map_c0ba2942`
- pack: `texture_map_0205ba86`
- norm: `texture_map_59cd86b9`

LA uses different slots for `swap_hand="armor"` (`texture_map_64cc5eb8` / `_861dbfdc` / `_abb81538`) and 1p fps units. For shield 3p paint these slots are correct.

### Auto-select on customization screen open
`_setup_illusions` resolves the currently-equipped illusion's `left_hand_unit` and matches it against the picker pool. The skin lookup chain is:
1. `item.skin` (BackendItem field)
2. `Managers.backend:get_interface("items"):get_skin(item.backend_id)` — vanilla-crafted weapons often hit this fallback (item.skin is nil)
3. `WeaponSkins.default_skins[item.key]`
4. `item_data.left_hand_unit` (template default)

Any stored `_offhand_selection` whose mesh no longer matches the rendered shield is discarded — the picker always reflects what's visible. Without this, cycling main-hand illusions visually swapped the shield too.

### Diagnostic commands
- `/la_offhand_dump` — each LA shield variant → resolved `intended_unit`, source (`new_units` / `no_override` / `unresolved`), texture path, icon keys.
- `/offhand_debug` — dumps the picker pool and current `_offhand_selection`.
- `[LA paint]` lines in `Console.log` — shows where the paint flow stopped (gate / variant lookup / paint call).

### Weapon identity before LA paint

Every offhand or weapon-illusion replay must prove that the stored entry belongs to the currently wielded item before touching a hand unit. Resolve the active slot from `inventory._equipment.wielded_slot`; `inventory.wielded_slot` is only a compatibility fallback for the husk extension and is absent on the local-owner extension. Match offhand entries by the wielded item's template/name/key/item type. Only the illusion path may additionally match a cosmetic slot key. An unresolved or different wielded item is a restrictive skip, never permission to paint: the pending queue or next-wield reconcile retries the matching weapon. `/cos_regression_test` check `cos_la_weapon_identity_gate_local_wearer` locks this #514 invariant.

## Known limitations
- LA `kind="unit"` variants (custom-mesh Empire basic shields, the elf `_mesh` variants, etc.) are not exposed — needs LA-package-load integration to register their meshes for on-demand spawning.
- The `_equip_skin_by_item` map is per-previewer with weak keys; if a previewer is reused across different equipped items without `equip_item` being called for each slot, has_skin may report stale data. Hasn't reproduced in practice.

## Cross-mod dependencies
- **Loremaster's Armoury** (steamcommunity / `dalokraff/Loremasters-Armoury`): texture variants used by the LA bridge in the offhand picker.
- **MoreItemsLibrary**: registers LA's hat/armor clones as separate inventory items (different feature; not used for offhand).
- **Material-Hijack** (planned): for Purified-outfit dirt removal and other texture swap features.
