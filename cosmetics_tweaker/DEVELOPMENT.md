# Cosmetics Tweaker — Development Notes

Detailed technical reference for the `cosmetics_tweaker` mod. Read alongside `CHANGELOG.md` (version-by-version history) and `TODO.md` (open work).

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
- `cos la_offhand_dump` — each LA shield variant → resolved `intended_unit`, source (`new_units` / `no_override` / `unresolved`), texture path, icon keys.
- `cos offhand_debug` — dumps the picker pool and current `_offhand_selection`.
- `[LA paint]` lines in `Console.log` — shows where the paint flow stopped (gate / variant lookup / paint call).

## Known limitations
- LA `kind="unit"` variants (custom-mesh Empire basic shields, the elf `_mesh` variants, etc.) are not exposed — needs LA-package-load integration to register their meshes for on-demand spawning.
- The `_equip_skin_by_item` map is per-previewer with weak keys; if a previewer is reused across different equipped items without `equip_item` being called for each slot, has_skin may report stale data. Hasn't reproduced in practice.

## Cross-mod dependencies
- **Loremaster's Armoury** (steamcommunity / `dalokraff/Loremasters-Armoury`): texture variants used by the LA bridge in the offhand picker.
- **MoreItemsLibrary**: registers LA's hat/armor clones as separate inventory items (different feature; not used for offhand).
- **Material-Hijack** (planned): for Purified-outfit dirt removal and other texture swap features.
