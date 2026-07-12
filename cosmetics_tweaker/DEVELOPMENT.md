# Cosmetics Tweaker — Development Notes

Detailed technical reference for the `cosmetics_tweaker` mod. Read alongside `CHANGELOG.md` (version-by-version history) and `TODO.md` (open work).

## Module map (v0.9.77-dev Phase 1 OOP split)

`cosmetics_tweaker.lua` is still the primary file (~9,700 lines) — this is an
IN-PROGRESS decomposition (OOP_REFACTOR_PLAN WS5), not a finished one. Phase 1
carved out the three cleanest self-contained concerns; the glow subsystem,
LA-bridge + husk, the HeroWindowItemCustomization offhand-picker UI suite, the
wire-safety senders, and the render-path hooks all still live in the entry file,
pending later phases (run in fresh sessions).

**Shared namespace `mod._cos`** (the event_tweaker `mod._evt` pattern,
PROJECT_STANDARDS § 2.2a) carries cross-module state. It is created in the entry
manifest (just after the `_flush_log` helper) and populated with the handles the
`_cos_*` modules consume BEFORE they are `mod:dofile`'d: `U` (the `_cosmetic_unlocks`
map), `LA_BRIDGE`, `flush_log`, `skin_requires_unowned_dlc`, `custom_skin_keys`
(shared with the wire-safety senders + regression suite), `custom_illusions` (shared
with the offhand force-loader), and `apply_cosmetic_unlocks` (exported by the unlocks
module for the entry's lifecycle callbacks). `mod:dofile` is NOT a singleton, so
modules never dofile each other — each is dofile'd exactly once from the manifest.

| Module | Owns / public surface (on `mod._cos` unless noted) |
|---|---|
| `cosmetics_tweaker.lua` (entry) | MOD_VERSION (launcher parses it here — never move it), the load banner/echo, the top embed manifest (`_la_prefix_embedded`, `_material_hijack_embedded`, `_moreitemslibrary_embedded`, `_cosmetic_unlocks`=`U`, `_la_bridge`, `_tpe`, `_glow_picker`, `_la_persistence`, `_la_okri`, `_ui_dump`, `_diag_probe`), the `mod._cos` namespace setup + `_cos_*` manifest, the mod-wide lifecycle callbacks (`on_game_state_changed`/`on_setting_changed`/`on_disabled`/`on_unload`), and everything not yet extracted: render-path hooks, glow, LA-bridge integration + husk, offhand picker + customization UI, the #421 wire-safety senders, the #282 MH release lifecycle, and the `/cos_regression_test` suite. |
| `_cos_diagnostics.lua` | Read-only dump/probe chat commands (`/flush_log`, `/dump_glows`, `/dump_skin_rarities`, `/dump_all_names`, `/check_vmf`, `/probe_hat`, `/probe_cosmetics`). Reads `mod._cos.flush_log`; no exports. |
| `_cos_illusions.lua` | Custom weapon-illusion + LA shield skin injection into `ItemMasterList`/`WeaponSkins`/`NetworkLookup` (`_custom_illusions`, `_la_shield_skin_specs`), the `get_unlocked_weapon_skins` unlock hook, the `_G.Localize` display-name hook. Populates `mod._cos.custom_skin_keys`; exports `mod._cos.custom_illusions`. |
| `_cos_unlocks.lua` | Per-career cosmetic unlocks (`apply_cosmetic_unlocks` + `_CHARACTER_CAREERS`), Unlock-All portrait frames, vanilla-unobtainable cosmetic grants, the two `PlayFabMirrorAdventure` hooks, `/frames_status` + `/cosmetics_status`. Exports `mod._cos.apply_cosmetic_unlocks`. |

Pre-existing `_*.lua` modules (`_la_bridge`, `_material_hijack_embedded[_anim]`,
`_moreitemslibrary_embedded`, `_cosmetic_unlocks`, `_tpe`, `_glow_picker`,
`_la_persistence`, `_la_okri`, `_ui_dump`, `_diag_probe`, `_la_prefix_embedded`)
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
- **Anything touching glow, the LA bridge/husk, the offhand picker, the wire-safety
  senders, or the render paths** → still in `cosmetics_tweaker.lua` until a later
  phase extracts them; grep ALL files for an existing hook on the `(Class, method)`
  before adding one (VMF drops the second — NON-NEGOTIABLE 8).
- **New cross-module value** → export onto `mod._cos` in the owning module (which must
  be earlier in the manifest than its consumers) and localize it at the consumer's top.

## Independent offhand (shield) illusion picker

The two-row picker on the weapon customization screen lets the user pick a shield independent of the weapon illusion. Vanilla shield options have `unit` set; LA (Loremaster's Armoury) options have `la_armoury_key`, `vanilla_skin`, and `intended_unit`.

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
1. **Sync load only.** `Managers.package:load(path, "cosmetics_tweaker", nil, false)`. Async returns immediately and races the user's Apply click. Sync blocks via `ResourcePackage.load + flush` (see `foundation/scripts/managers/package/package_manager.lua:80-86`) — for one shield package the hitch is unnoticeable.
2. **Load both halves.** `<unit_path>` AND `<unit_path>_3p`. The in-game body needs both; the customization preview only needs 3p.
3. **Defensive gate.** `_override_package_ready(unit_path)` in the `BackendUtils.get_item_units` hook verifies both packages via `Managers.package:has_loaded(...)` before applying the override.

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

## Known limitations
- LA `kind="unit"` variants (custom-mesh Empire basic shields, the elf `_mesh` variants, etc.) are not exposed — needs LA-package-load integration to register their meshes for on-demand spawning.
- The `_equip_skin_by_item` map is per-previewer with weak keys; if a previewer is reused across different equipped items without `equip_item` being called for each slot, has_skin may report stale data. Hasn't reproduced in practice.

## Cross-mod dependencies
- **Loremaster's Armoury** (steamcommunity / `dalokraff/Loremasters-Armoury`): texture variants used by the LA bridge in the offhand picker.
- **MoreItemsLibrary**: registers LA's hat/armor clones as separate inventory items (different feature; not used for offhand).
- **Material-Hijack** (planned): for Purified-outfit dirt removal and other texture swap features.
