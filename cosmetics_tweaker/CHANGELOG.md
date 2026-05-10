# Cosmetics Tweaker — Changelog

> **Note:** the dynamic-portrait system (v0.7.0–v0.7.102 development line)
> was split out into the `dynamic_cosmetic_portraits` mod on 2026-05-06.
> Pre-split entries below remain the historical record of how the system
> was researched and stabilised; ongoing portrait work lives in
> `dynamic_cosmetic_portraits/CHANGELOG.md`.

## [2026-05-09 v0.8.38-dev]
### Experimental
- **Hypothesis: the v0.8.34 click-Reiland AV crash was post-spawn texture painting, not the spawn itself.** Logic: LA's own design only hooks `HeroPreviewer` for its painting queue (inventory mannequin), NOT `LootItemUnitPreviewer` (customization preview). LA relies on `swap_units_new`'s global `WeaponSkins.skins` mutation + NetworkLookup aliasing + the compiled `.unit`'s baked materials for the preview to render. Our path skipped `swap_units_new` to avoid the global side effects, but ALSO added our own per-unit `Unit.set_texture_for_materials` paint via the v0.8.32 `_LA_KIND_UNIT_TEXTURES` map. That paint may be the C++ AV trigger when the bundled mesh's materials aren't fully bound.
- v0.8.38 isolates the test: stamp `backend_id` unconditionally on `preview_item` (revert v0.8.36's conditional skip) so the previewer actually tries to spawn Reiland — but **skip texture painting for kind="unit" variants entirely** (early return in `_paint_offhand_textures_locally`). Mesh may render magenta or with un-bound textures; either is informative.
  - If preview now spawns Reiland's mesh without crashing → painting was the culprit; we look for a different paint timing or primitive.
  - If still crashes → the spawn itself is unsafe in the previewer's world; we revert and pursue a different path (e.g. mirror swap_units_new's NetworkLookup aliasing).
- Ostermark / Kotbs unchanged (kind="texture" + is_vanilla_unit; their paint still runs and they still display correctly).

## [2026-05-09 v0.8.36-dev]
### Fixed (regression from v0.8.34)
- **Clicking Reiland in the row-2 picker no longer C++-AV-crashes the engine.** GUID a739e6e5-0760-4faf-9d4d-266ed64dddc4. Root cause: v0.8.34 unconditionally stamped `backend_id` on `preview_item`, which made our `BackendUtils.get_item_units` hook fire correctly during the customization preview's spawn — for the FIRST TIME for `kind="unit"` LA bundled paths. In-game and inventory mannequin worlds spawn LA bundled meshes fine (broader resource scope, mesh + materials all bind), but `LootItemUnitPreviewer`'s background world can't safely spawn them and the engine null-derefs at C++ level (not Lua-recoverable). Earlier v0.8.32-33 builds didn't crash because the missing `backend_id` made our hook bail in the previewer, so Reiland's mesh was never actually spawned there.
- Conditional fix: stamp `backend_id` ONLY when the click's `override_unit` has a standalone package (`Application.can_get("package", path)` true). LA bundled meshes (engine-resident via LA's main package only, no standalone) skip the stamp. For those options the previewer's hook bail returns to v0.8.32-33 behaviour — preview shows the vanilla skin's native shield instead of the clicked LA mesh.
- Vanilla offhand options and `kind="texture" + is_vanilla_unit` LA options (Ostermark/Kotbs — `intended_unit` IS a vanilla mesh with a standalone package) keep the v0.8.34 preview-update behaviour. Clicking them still updates the customization preview live.
- The override still fires for `kind="unit"` LA shields in-game and on the inventory mannequin; only the customization preview is degraded. User Apply still results in the LA shield correctly equipped.
- Documented limitation: customization preview can't render `kind="unit"` LA bundled meshes. Investigation needed: probably resource-scope binding for LA's textures/materials in the previewer's world. Outside the safe edit window.

## [2026-05-09 v0.8.34-dev]
### Fixed
- **Customization preview now updates when you click a different row-2 shield option.** v0.8.32's per-backend-id keying was correct, but `_ct_on_offhand_pressed` constructed the preview item without `backend_id`, so when `_spawn_item_unit(preview_item, true)` triggered the new previewer, our `BackendUtils.get_item_units` hook got `backend_id=nil` and `item_data.backend_id=nil` (item_data is the IML SKIN entry, not a backend item). Hook bailed → no override → preview rendered the vanilla skin's native shield instead of the clicked option's shield. User observation: "every shield option again looks like the current one." Fix: stamp `self._item_backend_id` onto the preview_item so our hook can resolve the per-backend-id selection set by the click. Vanilla row-1 illusion preview is unaffected — it constructs its own item without backend_id, so our hook still correctly bails for those (showing the illusion's native shield, not the offhand override).

## [2026-05-09 v0.8.32-dev]
### Fixed
- **Cross-weapon leak: `_offhand_selection` re-keyed from `item_type` to `backend_id`.** Each weapon instance now has its own selection slot, so applying Reiland on the Bret weapon no longer surfaces it on a CWV imperial sword+shield (or any other weapon sharing the item_type via clone). All seven touch sites updated:
  - The selection table itself (now keyed by backend_id).
  - `_setup_illusions` auto-select read/write.
  - `_ct_on_offhand_pressed` write on click.
  - `BackendUtils.get_item_units` hook read (uses the existing `effective_backend_id` resolution chain).
  - `_apply_la_offhand_to_units` LA-paint pipeline read (signature extended to accept `backend_id_arg`; falls back to `item_data.backend_id` which vanilla stamps on equipment resync).
  - HeroPreviewer / MenuWorldPreviewer call site (now passes `stored_bid` from a new `_get_equip_backend_id` helper that mirrors the existing `_get_equip_skin` tracking).
  - LootItemUnitPreviewer call site (passes `item.backend_id` directly).
  - `_offhand_selection_backend_id` (the old stale-tracking map) removed — redundant under per-instance keying.
- **Customization preview missing texture for kind="unit" LA shields: explicit per-unit texture binding from a manual extraction of the source `.unit` file.** Investigation:
  1. LA's source `.unit` file (`units/empire_shield/Kruber_Empire_shield01_mesh.unit`) declares textures via `colors / normals / MABs` fields with paths like `textures/Kruber_empire_shield_basic1/Kruber_empire_shield_basic1_diffuse`. These textures live in LA's globally-loaded resource_package.
  2. LA's `utils/hooks.lua:270-295` hooks `PackageManager.load`/`unload`/`has_loaded` and silently swallows any load attempt for its own mesh paths. The customization preview's per-instance package load is therefore a no-op — LA's package is globally loaded but not per-previewer scoped, so the engine's material binding falls back to default (mesh-only no texture).
  3. Reiland's SKIN_LIST entry has NO `textures` array (it's `kind="unit"` and the textures are stored in the source `.unit` file only).
- New `_LA_KIND_UNIT_TEXTURES` table in `_la_bridge.lua` holds the manually-extracted texture paths per LA armoury_key. `_paint_offhand_textures_locally` now accepts `armoury_key` and falls back to this map when the variant's `textures` array is empty. Per-unit `Unit.set_texture_for_materials` (the v0.8.18 primitive) handles the binding regardless of world/scope. First entry: `Kruber_empire_shield_basic1`. As more `kind="unit"` shields are added to the focus gate, each gets one entry in the map (3 lines per shield).

### Test plan (full restart)
- Equip Kruber Bret longsword+shield → cosmetics menu → row-2 picker → Reiland.
- Apply. Expect Reiland mesh + textures correctly in:
  1. Customization preview (the new path — should now work).
  2. Inventory mannequin.
  3. In-game body.
- Equip a DIFFERENT weapon (modded imperial sword+shield, or any other Kruber shield weapon). Expect to NOT see Reiland on that weapon — selection is per-backend-instance now.
- Equip a SECOND Kruber shield weapon and select Ostermark. Both weapons should hold their own selection independently. Pop back to weapon A → still Reiland. Weapon B → still Ostermark.
- Note: in-memory only this round; selections lost on game restart. Disk persistence (via mod settings or backend mirror) is the next architectural round.

## [2026-05-09 v0.8.31-dev]
### Reverted
- **v0.8.30 LA-shield skin injection rolled back.** It registered LA shields as first-class row-1 skins, but applying a row-1 skin swaps the whole weapon visual (left+right bundled together). The user's "cosmetics_tweaker is where the shield and main weapon are changed separately" model rules that out — they want the row-2 offhand picker (independent shield selection) to keep working. Net of the rollback: `_register_all_la_shield_skins()` is commented out and `_merge_la_offhand_options()` is restored in `mod.update`, so LA shields surface in the offhand picker again. The skin-injection code stays in the file for future reference.
- The cross-weapon leak (Reiland appearing on a modded imperial weapon that shares item_type) and the customization-preview missing-texture issue both come back with this revert. They need a different design — most likely per-backend_id selection keying with backend-mirror persistence so the offhand pick is scoped to the specific weapon instance the user applied it to. Tracked as the next architectural round.

## [2026-05-09 v0.8.33-dev]
### Added
- **Advanced glow submenu (per-channel brightness multipliers).** New "Advanced: Per-Channel Brightness" sub-group under the existing Weapon Glow Override settings, exposing 7 numeric multipliers (range 0.0–5.0):
  - **Master Brightness ×** (default 1.0) — scales all channels uniformly
  - **Rune Emissive ×** (default 1.0) — drives themed Veteran (`_runed_02..06`) and Stylish loot-chest (`_runed_01`)
  - **Glow High ×** + **Glow Low ×** (default 1.0) — drive the lower part of the visible gradient on `_magic_*` weapons (per probe v0.8.22)
  - **Smoke High ×** + **Smoke Low ×** (default 1.0) — drive the upper part of the gradient
  - **Dots Particles ×** (default 0.0 / SKIP) — experimental; probe showed `color_dots` darkens Weavebound when high and has unclear effect on Shyish-Infused
- A multiplier of `0.0` SKIPS that channel entirely (no `Unit.set_vector3` call) — leaves whatever vanilla wrote (or doesn't write at all for non-templated meshes). For Shyish-Infused weapons, default `mult_dots = 0` preserves vanilla's color_dots = (8.35, 3.5, 7).
- `color_dots` added to the `_cosmetics_tweaker_glow` injected template so users can experiment with it on Weavebound/Stylish via the multiplier. Inert by default (mult 0).

### Math
- Effective per-channel brightness = `native_magnitude × master_mult × channel_mult`. User RGB is normalized so its max channel hits this effective value, preserving hue and tunable magnitude. Without per-channel scaling, multi-channel templates (versus has 5 channels at very different brightness) over-bloomed when set to a uniform user RGB (v0.8.29 bug).

## [2026-05-09 v0.8.30-dev]
### Architectural change (Phase 1 of LA-shield skin injection — REVERTED in 0.8.31)
- **LA shields now inject as first-class VT2 skins instead of runtime offhand-row-2 overrides.** New `_la_shield_skin_specs` table (above `_register_custom_illusions` in `cosmetics_tweaker.lua`) drives `_register_la_shield_skin(spec)`, which writes a real entry into `ItemMasterList`, `WeaponSkins.skins`, the appropriate `WeaponSkins.skin_combinations` tier, and `NetworkLookup.weapon_skins`. Same pipeline `_register_custom_illusions` already uses for the `ct_*` cross-character illusions — point `left_hand_unit` at LA's authored mesh path while inheriting `right_hand_unit / display_unit / template / can_wield` from the matching vanilla weapon's default skin.
- This eliminates two issues from v0.8.27/v0.8.28 testing:
  1. **Cross-weapon leak.** `_offhand_selection` was keyed by `item_type`; modded CWV variants sharing an `item_type` with a vanilla weapon picked up Reiland on their 3P body in inventory. Vanilla's apply pipeline writes `item.skin = skin_key` onto a specific backend item — application is per-weapon-instance with zero shared state.
  2. **Customization preview missing textures.** The previewer's `_load_item_units` calls `Managers.package:load(unit_path_3p, ...)` with the previewer's reference. For a vanilla skin (which the LA-injected skin now IS) this binds the matching weapon's full asset graph into the previewer's scope. The LA mesh still goes through our v0.8.12 `load_package` short-circuit (no standalone `.package` exists for LA's bundled meshes), but the *right hand* package and other matching-weapon assets DO load via the standard path, which drags in shared materials/shaders LA's compiled `.unit` references at compile time.
- Phase 1 spec: ONE entry — `la_kruber_empire_shield_basic1_breton`, the Reiland mesh registered as a skin for `es_1h_sword_shield_breton`. Validates the architecture across all four spawn paths (in-game body, inventory mannequin, customization preview, illusion browser) before extending to all 4 weapon types and the rest of the LA shield catalogue.
- Row-2 LA bridge merge (`_merge_la_offhand_options`) intentionally not called — leaving it would surface LA shields in two places simultaneously and re-introduce the cross-weapon leak. The vanilla-only row-2 picker (independent left swap with vanilla shields) still works for users who want it.
- The runtime `BackendUtils.get_item_units` override path keyed off `_offhand_selection` is still in place but dormant for LA shields (no LA entries are populated there now). It still serves the vanilla offhand picker.

### Test plan (full restart)
- Equip Kruber Bret longsword+shield → cosmetics menu → row-1 illusion grid should now contain a new entry: `Empire Shield 01 (LA)`.
- Apply it. Expect the LA mesh + textures to render correctly in:
  1. Customization preview itself.
  2. Illusion browser (LootItemUnitPreviewer post-apply).
  3. Inventory mannequin after returning to the inventory tab.
  4. In-game once you start a mission.
- Equip a different weapon (modded imperial sword+shield, or any other Kruber shield weapon). Expect to NOT see Reiland anywhere — the skin is per-weapon-instance, scoped to the specific Bret backend item.
- Tell me what's wrong if anything still goes wrong (preview / mannequin / in-game / cross-weapon).

## [2026-05-09 v0.8.29-dev]
### Changed
- **Glow override redesigned: per-family routing decoupled from color choice.** The user's preset choice now selects an RGB triple; the mod writes that triple to whichever shader variables drive emissive on the target weapon — no separate code paths per family. New design: `_COLOR_PRESETS[preset_key] = { r, g, b }` (just RGB) plus a fixed list of candidate variables (`rune_emissive_color`, `color_glow_high`, `color_glow_low`, `color_smoke_high`, `color_smoke_low`) written on every painted unit. Variables that don't exist on a given mesh silently no-op (verified empirically via `cos glow_scan` in v0.8.22).
- **Template-mutation hook now mutates EVERY vector3 variable in the template** to user RGB, not just `rune_emissive_color`. Covers any source-defined template — rune family (single channel), versus (5 channels), and any future template — without per-template knowledge.
- **`color_dots` (versus 5th channel) intentionally omitted** from the direct-paint variable list (probe showed minimal visible color contribution; possibly drives particle behaviour). Template-mutation path still mutates it as part of the versus template — that's fine because the visible contribution is minor.

### Added
- **"White" preset** in the dropdown (key `white_glow`, RGB {10, 10, 10}). Coverage now: White / Purple / Gold / Red / Green / Blue. Underlying preset keys preserved from older builds for save-data compatibility.
- **All four glow families now covered by one color picker** (probe-confirmed in v0.8.22):
  - `_runed_02..06` themed Veteran: rune_emissive_color via template mutation
  - `_runed_01` Stylish loot-chest white-glow (~160 weapons): rune_emissive_color via direct post-spawn paint
  - `_magic_02` Shyish-Infused (Versus rewards): 5 versus channels via template mutation on `versus`
  - `_magic_01` Weavebound (WoM Athanor): 4 versus channels via direct post-spawn paint (no vanilla template — direct write mandatory)
- `cos glow_status` now reports the active RGB alongside the preset key.

### Tooltip
- Updated `glow_override_enable` to clarify coverage spans all four glow families through one color picker.

## [2026-05-09 v0.8.22-dev]
### Added
- **Glow probe diagnostic suite** (`cos glow_dump`, `cos glow_probe <name>`, `cos glow_scan`, `cos glow_scan_stop`, `cos glow_restore`) — finds what shader uniform controls baked emissive on weapon meshes that don't go through the rune-emissive `MaterialSettingsTemplates` system (specifically Stylish `_runed_01` and Weavebound `_magic_01`). The scan sweeps ~63 candidate variable names with bright HDR red on the wielded weapon's units, flashing red on hit. Works because `Material.num_parameters` / `parameter_name` crashes Stingray (resource_manager.cpp:245, NOT pcall-recoverable) so direct enumeration is impossible — brute force is the only viable approach.

### Fixed
- **Vector3 frame-allocation gotcha (v0.8.20 → v0.8.22).** The original probe shipped with `local _GLOW_PROBE_HDR = Vector3(15, 0, 0)` cached at module load. Stingray Vector3 is frame-allocated; the storage is invalidated across frames. Every `pcall(Unit.set_vector3_for_materials, unit, name, cached_vec)` returned `false` because the cached Vector3 was no longer a valid argument. Symptom: scan reported `painted=0` on every candidate × every unit. v0.8.22 changed to `local function _probe_red() return Vector3(15, 0, 0) end` and the probe started actually painting. Same gotcha applies to any Stingray vector type — never cache `Vector3()` results across frames; reconstruct per call site.

### Empirical probe results
- **`_runed_02` (Veteran themed, e.g. purple_glow)**: red glow flash on candidate **#8 = `rune_emissive_color`**. Confirms the existing v0.8.16 template-mutation override pipeline targets the right variable for this family.
- **`_magic_02` (Shyish-Infused, Versus rewards)**: red glow flash on candidates **#50-53** (uniform red across the visible glow); **#54 (`color_dots`) minimal/unclear visible contribution**. Channels 50-53 are 4 of the 5 source-defined `versus` template channels.
- **`_magic_01` (Weavebound, WoM Athanor)** — Bretonnian longsword: SAME 5 versus channels respond, with empirically-mapped roles:
  - **50 `color_glow_high` + 51 `color_glow_low`** → drives the LOWER part of the visible gradient
  - **52 `color_smoke_high` + 53 `color_smoke_low`** → drives the UPPER part of the visible gradient
  - **54 `color_dots`** → went dark / minimal contribution (probably the small particle dots; minor color)
  - **Important consequence:** `_magic_01` mesh materials expose the same uniform names as `_magic_02` even though `_magic_01` has NO source-defined `material_settings_name` — vanilla never paints them, but the variables are there waiting to be written. Earlier I'd assumed Weavebound used a wholly different shader and required asset-level work — wrong; the variables are paintable from Lua, no asset work needed.
- **`_runed_01` (Stylish loot-chest white-glow)**: red glow flash on candidate **#8 = `rune_emissive_color`**. Clearing to (0,0,0) made the glow vanish entirely → the "white" appearance IS that variable set to a white HDR value, NOT a separate baked-in shader effect. Same variable as the themed `_runed_02..06` family. Earlier docs claimed Stylish "has no template-driven glow" — that was wrong. They have NO `material_settings_name` (so vanilla never paints them), but the mesh material exposes `rune_emissive_color` and the mesh's authored white default lives in there from somewhere (mesh asset default, likely). Our `Unit.set_vector3_for_materials` calls override it cleanly.

### Implementation plan derived from probe
With the Stylish probe added, all 4 weapon families are now probe-confirmed paintable. The redesign:

1. **Stop conflating "preset key" with "shader variable to write".** Current design: `_GLOW_PRESETS[preset_key] = { var = rgb }` — the user's preset choice (`purple_glow` / `golden_glow` / etc.) determines BOTH the color AND which variable gets written. New design: `_COLOR_PRESETS[preset_key] = { r, g, b }` (just an RGB) plus a per-weapon-family routing layer that decides which shader variable(s) to write. Lets one user choice drive every family appropriately.

2. **Per-family variable routing** (write the chosen RGB into):
   - **`_runed_02..06` (themed)**: `rune_emissive_color`. Already working via template mutation.
   - **`_runed_01` (Stylish)**: `rune_emissive_color`. Same variable. Vanilla never calls apply_material_settings here, so use the existing post-spawn `_apply_glow_override` path. Verify it's already firing for these — it should be.
   - **`_magic_02` (Shyish-Infused)**: 4 channels (`color_glow_high`, `color_glow_low`, `color_smoke_high`, `color_smoke_low`) — leave `color_dots` alone. Use template mutation on `MaterialSettingsTemplates.versus`.
   - **`_magic_01` (Weavebound)**: SAME 4 channels. No vanilla template — direct post-spawn paint via `_apply_glow_override`, with detection by unit_name suffix.

3. **Detect family per weapon** at paint time. Read the resolved unit_name (already available in `slot_data` and in the create_equipment result) and match the suffix:
   - `_runed_01` → Stylish
   - `_runed_02..06` → themed (template-driven)
   - `_magic_01` → Weavebound (no template, paint directly)
   - `_magic_02` → Shyish (template-driven via versus)
   - other → no glow override applies

4. **UI**: keep the simple 5-color dropdown (Purple / Gold / Red / Green / Blue) — the routing is invisible to the user. One color picker drives every weapon family. Add a "white" preset since loot-chest Stylish weapons are natively white and a no-op preset is meaningful for them. Versus preset doesn't need to come back as a separate user-facing choice — same color picker handles it.

### Open follow-ups
- Verify Stylish post-spawn paint actually fires (the user previously reported it didn't, but probe shows the variable is paintable — gate bug to find).
- Live re-paint (Phase 2 task — wield-event hook).
- Husks (Phase 2 task — peer player_units).
- Per-skin custom RGB picker on customization screen (Phase 2 task).

## [2026-05-09 v0.8.28-dev]
### Reverted
- **`LootItemUnitPreviewer.load_package` hook reverted to plain v0.8.12 short-circuit.** v0.8.26 (async per-previewer reference on LA's main package) didn't fix the texture-less customization preview; v0.8.27 (sync) crashed with `[Engine Error]: Resource '#ID[3ac73385950a26ea]' was not found` (GUID 930aff6f-7e47-4f72-a661-b8222e862fc2). The sync load forced the engine to resolve every resource in LA's package up front and one of them (a Stingray hash, undecodable from Lua) isn't actually in the loaded asset graph — async didn't surface it because the lookup never happened.
- Net state: `kind="unit"` LA shields (Reiland) render mesh+textures correctly **in-game** and on the **inventory mannequin**. The **customization preview** shows the mesh without textures. This is a documented limitation of the current approach; needs a different angle (probably related to the LA compiled `.unit` referencing vanilla material paths that are only in scope when the matching vanilla weapon is loaded). Reiland stays in the focus gate so in-game usage continues to work.

## [2026-05-09 v0.8.27-dev]
### Changed
- **`LootItemUnitPreviewer.load_package` hook re-ordered: per-previewer reference on LA's main package taken BEFORE flipping the gate, sync (`async=false`).** v0.8.26 took the reference async and flipped the gate first, so `_spawn_items` could race ahead of the package-scope binding and the unit rendered without textures (user confirmed v0.8.26 fix didn't help). Sync blocks until LA's package is fully bound to the previewer's reference scope before the gate opens. Added `[LA preview-load]` diagnostic gated on `mod:get("la_preview_trace")` so we can see in the log which path the hook took if textures still don't bind. If this still doesn't fix it, the issue is elsewhere (likely the LA compiled `.unit` references vanilla material paths that aren't in scope when only the shield is being previewed) and needs a different approach.

## [2026-05-09 v0.8.26-dev] (superseded by 0.8.27)
### Fixed (didn't actually fix)
- **`kind="unit"` LA shield now textures correctly in customization preview.** v0.8.25 wired up Reiland and it rendered correctly in-game and on the inventory mannequin, but the customization/illusion menu preview spawned the mesh without textures (just the bare mesh). Root cause: our `LootItemUnitPreviewer.load_package` short-circuit (added v0.8.12 for "no model at all" fix) flipped the loaded-flag and let the spawn proceed against LA's globally-loaded resource package — which works for the in-game body and the inventory mannequin (different worlds with broader resource scope) but doesn't bind LA's materials/textures into the previewer's per-instance resource scope. Fix: when the short-circuit fires for an LA-bundled path, ALSO call `Managers.package:load(_LA_MAIN_PACKAGE, "LootItemUnitPreviewer<id>", nil, true)` to take a per-previewer reference. Tracked per-previewer in a weak-keyed map so we only register once per previewer instance. The package is already globally loaded by VMF, so this is a refcount bump that ties LA's assets to the previewer's lifetime — the engine then binds materials properly when the unit spawns.

## [2026-05-09 v0.8.25-dev]
### Added
- **First `kind="unit"` LA custom-mesh shield: `Kruber_empire_shield_basic1` (Empire shield 01 / Reiland-style).** New architectural class — LA's own authored mesh, not a recolor of a vanilla shield. Three pieces wired in `_la_bridge.lua`:
  1. `_is_supported_variant` now accepts `kind="unit"` if both halves of `variant.new_units` pass `Application.can_get("unit", path)` (engine-resident check). Anything the engine can't actually spawn still skips silently.
  2. `_register_la_path_in_network_lookup(path)` adds bidirectional entries (`string→idx, idx→string`) to `NetworkLookup.inventory_packages` via `rawset`, bypassing the strict `__index` that crashed the older integration attempts (GUID 60180105). Called for both `new_units[1]` (1p) and `new_units[2]` (_3p) of every kind="unit" variant during `build_offhand_options`. Idempotent.
  3. `_LA_EXTRA_WEAPON_TYPES` and `_LA_FOCUS_KEYS` extended to include `Kruber_empire_shield_basic1` (Bret extra + focus). Icons table covers sword/mace/deus already.
- We don't call any LA helpers in this path. `BackendUtils.get_item_units` returns the LA mesh path; the previewer's package-load short-circuit (v0.8.12) flips the loaded-flag immediately because LA's mesh is engine-resident; the texture binds from the compiled `.unit`'s embedded material slots (Reiland has no `textures` array, so the per-unit paint pass is a no-op).

### Test plan (full restart)
- Equip Kruber Bret longsword+shield → cosmetics → expect Ostermark01, Kotbs01, AND `Empire Shield Basic1 (LA)` (or however it humanizes).
- Same for sword+shield, mace+shield, deus spear+shield.
- Apply Reiland → expect a different shield SHAPE (Empire shield 01 mesh, not deus shield) with its embedded materials. No magenta. No leak onto adjacent shields in the inventory mannequin.
- `cos la_offhand_dump` after a full equip: Reiland line should show `1p=true 3p=true` (engine-resident).
- If a sync-time crash hits in MP, capture the GUID + missing-key message and we'll add the relevant rawset for whichever NetworkLookup table it points to.

## [2026-05-08 v0.8.24-dev]
### Added
- **Kotbs01 added to focus gate.** `_LA_FOCUS_KEYS` now `{ Ostermark01 = true, Kotbs01 = true }`. Same architecture as Ostermark (kind="texture", is_vanilla_unit=true, intended_unit=`wpn_es_deus_shield_03`); appears on Kruber's sword+shield, mace+shield, deus spear+shield (icon-driven) and Bret longsword+shield (via the v0.8.21 `_LA_EXTRA_WEAPON_TYPES` extras + v0.8.22 alias). No new routing, just visibility.

### Test plan
- Restart VT2.
- For each of Kruber's 4 shield weapons (sword+shield, mace+shield, Bret longsword+shield, deus spear+shield): cosmetics menu → expect Ostermark01 AND Kotbs01 both visible. Apply each → expect deus shield mesh + their respective heraldry texture, no magenta, no leak.

## [2026-05-08 v0.8.23-dev]
### Changed
- **Focus gate at picker-display time.** Per the "one shield at a time" working policy: registration data (icon parsing, `_LA_EXTRA_WEAPON_TYPES`, `_LA_WEAPON_TYPE_ALIAS`) stays intact for every LA shield, but `_merge_la_offhand_options` only surfaces shields whose `armoury_key` is in `_LA_FOCUS_KEYS`. Currently set to `{ Kruber_empire_shield_hero1_Ostermark01 = true }`. Widening to the next focus shield (or removing the gate entirely once all are verified) is a one-line edit at the top of `_merge_la_offhand_options` in `cosmetics_tweaker.lua`. Set to nil/empty table to surface every LA shield.
- This intentionally preserves all the v0.8.19/v0.8.21/v0.8.22 fanout fixes (icon-driven, item_type alias, manual extras) — those are background plumbing that needs to be correct so that flipping the focus gate exposes a working picker. The gate just controls *visibility*, not the underlying routing.

### Test plan
- Restart VT2.
- Equip Kruber Bret longsword+shield → cosmetics menu → expect ONLY `Empire Shield Hero1 Ostermark01 (LA)` in the LA section. Nothing else from the LA bridge.
- Equip Kruber mace+shield → same: only Ostermark01 from LA. (Vanilla offhands are unaffected.)
- Apply Ostermark01 on Bret → expect the deus shield mesh + Ostermark texture combo, identical to mace+shield.

## [2026-05-08 v0.8.22-dev]
### Fixed
- **Bret-weapon LA shields were silently invisible.** Dump showed `es_sword_shield_breton offhand pool: 7 entries`, but the in-game log showed `[LA paint] skip: no _offhand_selection for es_1h_sword_shield_breton`. Naming gap: LA's icon keys use `es_sword_shield_breton_skin_*` (no `_1h_` infix) but the game's actual `ItemMasterList[item].item_type` for the Bret weapon is `es_1h_sword_shield_breton`. v0.8.19's icon-driven fanout bucketed every Bret LA shield (Bastonne, Reynard, Luidhard, Lothar, Alberic, plus the v0.8.21 Ostermark/Kotbs extras) into a pool the game never queried. The picker showed only vanilla Bret shield options because the LA pool was unreachable.
- Added `_LA_WEAPON_TYPE_ALIAS` in `_la_bridge.lua` to translate LA's icon-derived weapon_type to the game's item_type. Currently one entry: `es_sword_shield_breton -> es_1h_sword_shield_breton`. Applied via `_normalize_weapon_type()` in both the icon-driven fanout AND the `_LA_EXTRA_WEAPON_TYPES` map (which I already updated to use the canonical game item_type, but the alias is the safety net so future entries can use either form).
- Re-running `cos la_offhand_dump` after this build should show `es_1h_sword_shield_breton` (with `_1h_`) as the pool key, with all 7 entries (5 Bret-authored + Ostermark + Kotbs).

### Test plan
- Restart VT2 fully.
- Equip Kruber Bret longsword+shield → cosmetics menu → expect to see all 7 LA shields in the picker now: Bastonne02, Reynard01, Luidhard01, Lothar01, Alberic01, Ostermark01, Kotbs01.
- Apply Bastonne02 / Reynard01 / etc. (pure-paint Bret shields) → expect Bret shield silhouette + Bret-authored heraldry texture.
- Apply Ostermark01 / Kotbs01 → expect deus shield mesh + Empire heraldry texture (same combo as on mace+shield).
- If something is still wrong, name the exact LA shield + skin combo and what you see.

## [2026-05-08 v0.8.21-dev]
### Added
- **`_LA_EXTRA_WEAPON_TYPES` map (`_la_bridge.lua`)** for opting individual LA shields into weapon types that aren't in their `icons` table. v0.8.19's icon-driven fanout was correct as a default but excluded Ostermark from Bret longsword+shield, which the user explicitly wants — they want the LA combo (deus shield mesh + Ostermark texture) on the Bret weapon, the same combo as on mace+shield. The map is a per-variant additive override.
- Initial entries:
  - `Kruber_empire_shield_hero1_Ostermark01 = { es_sword_shield_breton = true }`
  - `Kruber_empire_shield_hero1_Kotbs01     = { es_sword_shield_breton = true }`
- These two LA shields will now also appear on Bret longsword+shield. Their `intended_unit = wpn_es_deus_shield_03` triggers the BackendUtils.get_item_units mesh-override path so the deus shield mesh is rendered (matching the texture's UVs) instead of the Bret shield mesh. The texture binds via the v0.8.18 per-unit `Unit.set_texture_for_materials` path so there's no shared-material leak onto adjacent shields.
- Adding more LA shields to other weapon types is one entry per shield in this map, on a one-shield-at-a-time basis as we walk the catalogue and decide what should appear where.

### Test plan (this build, on a fresh game restart)
- Restart VT2 to clear any shared-material residue.
- Equip Kruber's Bret longsword+shield → cosmetics menu → expect Ostermark01 and Kotbs01 in the LA section alongside the Bret-authored variants (Bastonne02, Reynard01, Luidhard01, Lothar01, Alberic01).
- Apply Ostermark01 → expect deus shield mesh + Ostermark texture, no magenta, no leak onto adjacent shields. Same combo as on mace+shield.
- Run `cos la_offhand_dump` and confirm `Kruber_empire_shield_hero1_Ostermark01` lists `es_sword_shield_breton` in its weapons column alongside `es_1h_mace_shield`, `es_1h_sword_shield`, `es_deus_01`.

## [2026-05-08 v0.8.19-dev]
### Changed (architectural)
- **No more whitelist. No more per-character LA fan-out. LA shields appear ONLY on the weapon types LA's own `icons` table actually authored them for.** This was the structural mistake under the "Ostermark wraps wrong on Bret" report. The previous fan-out (`_la_character_weapon_pools`) gave Kruber's whole LA pool to every shield-bearing weapon Kruber has, which painted Empire-shield textures (UVs authored for `wpn_es_deus_shield_03`) onto Bret shield UVs and produced the wrong-wrap.
- New flow in `_la_bridge.lua`:
  - For each LA SKIN_LIST entry with `swap_hand="left_hand_unit"`, parse its `icons` table. Each icon key is a vanilla skin key of form `<weapon_type>_skin_<...>` (e.g. `es_1h_mace_shield_skin_03`, `es_sword_shield_breton_skin_01`). The prefix before `_skin_` is the weapon type LA targeted.
  - The variant joins `M.la_offhand_options_by_weapon_type[wt]` for each weapon type in its icons table — and only those.
  - LA SKIN_LIST entries WITHOUT an `icons` table are skipped (no authoring metadata to drive routing).
- New flow in `cosmetics_tweaker.lua`:
  - `_la_character_weapon_pools` and the `_LA_KEY_WHITELIST` are gone.
  - `_offhand_options.es_1h_mace_shield`, `es_1h_sword_shield_breton`, `es_deus_01`, `dr_1h_hammer_shield`, `wh_hammer_shield` are now SHALLOW COPIES of their alias targets, not the same table reference. LA fan-out can append per-weapon-type without bleeding across.
  - `_merge_la_offhand_options` reads `LA_BRIDGE.la_offhand_options_by_weapon_type[weapon_key]` directly. No character-level indirection, no `seen_lists` dedupe.
  - The Bret-mesh guard in `BackendUtils.get_item_units` is removed. It was a bandaid for the cross-pollination that this build prevents at the source: LA Empire shields (Ostermark, Kotbs) won't appear on Bret weapons at all, so we never need to drop their `intended_unit` override.
- The v0.8.18 per-unit `Unit.set_texture_for_materials` paint primitive stays in place — it kills the shared-material leak class.
- `cos la_offhand_dump` now prints each variant's `weapon_types` list so you can verify which weapon types each LA shield will surface in.
- `kind="unit"` LA variants remain filtered (separate problem; needs LA `swap_units_new` integration with `rawget`/`rawset` accessors per `feedback_la_custom_mesh_unsupported.md`).

### Test plan (this build, on a fresh game restart)
- Restart VT2 to clear shared-material residue from earlier sessions.
- Kruber mace+shield → expect Ostermark01, Kotbs01, and other Empire LA shields whose `icons` include `es_1h_mace_shield_skin_*`. The deus-shield mesh is correct.
- Kruber Bret longsword+shield → expect Bastonne02, Reynard01, Luidhard01, Lothar01, Alberic01 (Bret-authored pure-paint variants). Bret silhouette stays, Bret-authored UVs.
- Kruber sword+shield → Empire LA pool again (Ostermark, Kotbs, etc.).
- Pick an LA option on weapon A → in-game shield only changes on weapon A. Adjacent shields in inventory should not magenta or wrong-texture. Pick Default → re-equip yields a clean vanilla shield.
- If something is still wrong, name the exact weapon type + LA shield + skin combo so we can pinpoint.

## [2026-05-08 v0.8.18-dev]
### Fixed (root cause)
- **Switched LA shield paint from shared-material `Material.set_texture` to per-unit `Unit.set_texture_for_materials`.** This was the architectural mistake underlying every "magenta-on-default" / "wrong texture on a different shield" report since LA bridge integration began. The old path called `Material.set_texture(mat, slot, path)` against materials returned by `Mesh.material(unit_mesh, j)` — those materials are the SHARED material instances baked into the vanilla shield's compiled bundle, so painting one shield's LA texture actually rebound the slot for every unit referencing that material (other shield illusions, the inventory mannequin, the customization preview). One click leaked across the entire UI, and once an LA texture was unloaded (or any package reload occurred) every leaked binding flipped to the engine's missing-asset magenta. The fix uses the same primitive vanilla VT2 uses everywhere it does per-cosmetic texture binding (`gear_utils.lua:150`, `cosmetic_utils.lua:72`, `flow_callbacks_foundation.lua:939`, `outline_system.lua:666`): `Unit.set_texture_for_materials(unit, slot_name, texture_path)`. The engine sets up a per-unit material override; the shared material is never written to. When the unit is destroyed (next re-equip) the override drops with it.
- **Limitation:** `Unit.set_texture_for_materials` doesn't have a per-mesh exclusion equivalent of LA's `skip_meshes` / `textures_other_mesh`. The new `_paint_offhand_textures_locally` logs a warning when those nuance fields are set on the variant. The first focused-triage candidate (`Kruber_empire_shield_hero1_Ostermark01`) has empty `skip_meshes`, so this isn't a problem for the current round; if a later LA shield in the whitelist has skip_meshes we'll need a per-mesh fallback path. Old per-mesh implementation kept inline as `_legacy_paint_offhand_textures_via_shared_material` for reference (delete after verification).
- **No code change required for selecting Default to "revert".** Because each spawn now applies its overrides per-unit (or doesn't, when no LA option is selected), the next re-equip naturally produces a clean unit with no leftover LA binding. The vanilla material itself was never mutated.

### Test plan (this build, on a fresh game restart)
- **Restart VT2 fully** so the shared-material state from earlier sessions is wiped out. Without a clean restart you'll see leaked magenta from prior versions even though this build never writes to a shared material.
- Equip Kruber's mace+shield → cosmetics menu → ONE LA option visible ("Empire Shield Hero1 Ostermark01 (LA)") + all vanilla mace+shield options.
- Apply Ostermark01 on a vanilla Empire mace skin → expect deus-shield mesh + Ostermark heraldry texture, no magenta.
- Equip Kruber's Bret longsword+shield → same ONE LA option visible.
- Apply Ostermark01 on a Bret skin → expect Bret silhouette + Ostermark texture overlay (UV-imperfect, since LA authored the texture for deus shield UVs).
- After applying, click Default → re-equip should produce a clean vanilla shield. No magenta on Default. No magenta on any other shield in the inventory mannequin or illusion browser.
- If still seeing magenta, capture the precise combination (which mace skin / which shield it leaked onto) so we can pinpoint whether it's a different leak or the shared-material residue.

## [2026-05-07 v0.8.16-dev]
### Fixed
- **Glow override now lands on FIRST PERSON weapons.** Verified in-game by user. v0.8.4–v0.8.15 reliably painted 3p but never visually changed 1p, even though the v0.8.5 `[GLOW-trace]` proved every `Unit.set_vector3_for_materials` call returned `ok=true` on the 1p unit. User confirmed vanilla 1P glow IS paintable (deep_crimson skin glows red in 1P with override off), so it wasn't a 1P-shader-doesn't-have-the-variable limit. Switched mechanism from "let vanilla apply, then overlay" (`hook_safe`) to "mutate the global `MaterialSettingsTemplates[name]` table BEFORE vanilla reads it, restore after" (`hook` with template mutation). Same trick NoGlow uses to zero emissive. Vanilla itself becomes the only writer to the unit's materials, so whatever was rejecting our second write on 1p is no longer in play. Applies to all three apply_material_settings copies (`GearUtils`, `_G`, `CosmeticUtils`). User must apply a new cosmetic / re-equip the weapon to trigger a respawn for the override to take effect — live re-paint was removed in v0.8.10 because walking spawned units to repaint destabilised adjacent unit state.

### Changed
- **Focused-triage scope: one LA shield at a time.** Per user request, the LA picker is now narrowed to a single shield until each is fully verified. v0.8.15's broad exposure caused too many simultaneous failure modes (mesh-wrapping issues, magenta from shared-material texture leaks, sticky paint from previous selections) for any of them to be diagnosed in isolation.
- Whitelist in `_la_bridge.lua`: `_LA_KEY_WHITELIST` set to `{ Kruber_empire_shield_hero1_Ostermark01 = true }`. Build_offhand_options now requires the LA key to be in this set in addition to passing `_is_supported_variant`. Other LA keys are excluded from the picker but the iteration code is intact — adding the next shield is a one-line edit.
- Kruber fan-out narrowed to `{ "es_1h_mace_shield", "es_1h_sword_shield_breton" }`. `es_1h_sword_shield` and `es_deus_01` excluded for this round even though Ostermark01's `icons` table covers them; we'll re-enable once mace+breton is verified.
- Other characters' (Kerillian/Bardin/Saltzpyre) fan-out tables unchanged in shape, but the whitelist filter empties their LA pools too — so their pickers show vanilla offhands only this round.
- The Bret-mesh wrapping guard from v0.8.13 (drop the `intended_unit` override when `resolved_skin` matches `_breton_` AND selection has `la_armoury_key`) stays in place.
### Test plan (this build, on a fresh game restart)
- **Restart VT2 fully.** The shared-material texture leak documented in `reference_la_offhand_paint.md` persists across in-session reloads — only a fresh game start clears stale LA texture bindings. Without this, you'll see leaked magenta from earlier sessions and won't be able to attribute behaviour to this build.
- Equip Kruber's mace+shield → cosmetics menu → expect ONE LA option labeled "Empire Shield Hero1 Ostermark01 (LA)" (or similar) plus all vanilla mace+shield options. Confirm vanilla options still all present and unchanged.
- Apply Ostermark01 on a vanilla Empire mace skin → expect a deus-shield-shape painted with Ostermark heraldry (`is_vanilla_unit=true` swaps the mesh to `wpn_es_deus_shield_03`).
- Equip Kruber's Bret longsword+shield → cosmetics menu → expect the same ONE LA option to appear here too.
- Apply Ostermark01 on a Bret skin → expect the Bret shield silhouette with Ostermark texture overlaid (UV fit imperfect because LA authored the texture for the deus shield UVs, but the Bret silhouette is correct).
- Click Default after applying → expect to revert to whatever the underlying skin's native shield is.
- Document anything else (magenta, missing textures, wrong mesh) in detail per combo so we can fix surgically.

## [2026-05-07 v0.8.15-dev]
### Reverted
- **`kind="unit"` LA custom-mesh shields filtered out again; `re_apply_illusion` integration removed.** The v0.8.13 attempt to invoke LA's `re_apply_illusion` from our offhand handler crashed at `network_lookup.lua:2514` with `Table inventory_packages does not contain key: units/empire_shield/Kruber_Empire_shield02_mesh_3p` (user crash 60180105-bd15-49f2-9fa6-9f70dd851846). Two architectural barriers, neither fixable by surface-level patching:
  1. **State-machine race with LA's `mod.update` loop.** LA iterates `SKIN_CHANGED` every frame and calls `re_apply_illusion(mod:get(skin), skin, unit)` on each entry. If our setting and LA's persisted setting disagree, our `swap_units_new` and LA's `swap_units_old` (or vice-versa) interleave with stale `changed_model` flags, leaving `WeaponSkins.skins[skin][hand]` pointing at an LA path that wasn't aliased on this run. The next `swap_units_new` call (ours OR theirs) reads `inventory_packages[<la_path>.."_3p"]` and crashes against the strict `__index`.
  2. **`NetworkLookup.inventory_packages.__index` is fatal on miss.** Every LA call path that goes through `swap_units_new`/`swap_units_old` does naked reads against this table. Per `feedback_vt2_strict_lookup_rawget.md`, anything we do to that table must use `rawget`/`rawset`. Calling LA's pre-existing helpers means we can't swap in safe accessors without wrapping each helper.
- A safe integration would need to either (a) take ownership of LA's update loop for the affected skins (suspend its `re_apply_illusion` calls while ours are in flight), or (b) replicate `swap_units_new` end-to-end with our own state machine and `rawget`/`rawset` accessors. Both are substantial; deferred until there's a focused session for it.
- The Bret-skin mesh-wrapping fix from v0.8.13 is preserved (`kind="texture"` Empire variants still drop the mesh swap on Bret skins; LA's paint overlay handles the texture).
- `cos la_offhand_dump` retains the `1p=<bool> 3p=<bool> pkg=<bool>` triage columns from v0.8.12.

## [2026-05-07 v0.8.13-dev]
### Fixed
- **Bret skin no longer wraps LA texture onto the wrong shield mesh.** LA's `kind="texture"` Empire-shield variants (Ostermark, Kotbs, etc.) declare `new_units = wpn_es_deus_shield_03` AND list `es_sword_shield_breton_skin_*` keys in their `icons` table, meaning LA expects them to apply on Bret skins as well — but the mesh swap forces the Bret weapon to render the deus-shield model with LA heraldry painted onto it. User reported the texture wraps incorrectly. Added a guard in `BackendUtils.get_item_units`: when the resolved skin contains `_breton_` AND the selection has an `la_armoury_key` (so this is one of our LA bridge entries, not a vanilla swap), drop the mesh override. The LA paint pass still runs, overlaying the texture on whatever Bret shield the skin already provides. UV fit isn't perfect (LA authored the texture for the deus shield), but the silhouette is now correctly Bretonian.
### Added
- **`kind="unit"` LA shields integrate with LA's swap pipeline.** v0.8.11+ exposed LA's custom-mesh shields in the picker, but they rendered magenta because our override path (just rewriting `result.left_hand_unit`) skipped LA's `swap_units_new` step that aliases `NetworkLookup.inventory_packages` and mutates `WeaponSkins.skins[skin][hand]` — the bookkeeping the engine relies on to bind LA's compiled materials. Added `_ct_apply_la_unit_swap` (file-local, forward-defined per `feedback_lua_forward_reference.md`): when the user clicks a `kind="unit"` LA option, we call `LA.re_apply_illusion(armoury_key, skin, original_unit)` which internally invokes `swap_units_new` + `re_equip_weapons`. Tracking table `_la_active_unit_swap_by_skin` records the active swap per skin so a subsequent click on a different option (texture variant or default) issues a `re_apply_illusion("default", ...)` revert before installing the new one — prevents LA's `changed_model` flag from blocking re-application and keeps `WeaponSkins` mutations balanced. Texture-only and default options remain on the existing override path (no LA pipeline call needed).

## [2026-05-07 v0.8.12-dev]
### Fixed
- **LA custom-mesh shields now actually render in the customization preview.** v0.8.11 made `kind="unit"` LA variants appear in the picker, but selecting one showed "no model at all" — the slot went empty. Root cause: vanilla shields ship as standalone `units/.../wpn_xxx.package` files, so `LootItemUnitPreviewer.load_package` -> `Managers.package:load(unit_path_3p, ...)` succeeds and fires `_on_load_complete`, flipping `self._loaded_packages[path] = true`. The previewer's spawn gate (`loot_item_unit_previewer.lua:511`) only proceeds to `World.spawn_unit` after that flag flips. LA bundles every custom shield mesh into one big `resource_packages/Loremasters-Armoury/Loremasters-Armoury` package — there is no per-unit standalone `.package`. So `Managers.package:load("units/Kerillian_elf_shield/<...>_3p", ...)` phantom-succeeds without firing the callback, the gate stays closed forever, and `World.spawn_unit` never runs. VMF auto-loads each mod's main package on register, so LA's custom meshes ARE engine-resident — just not via the `package`-id lookup the previewer is doing. Fix: hook `LootItemUnitPreviewer.load_package`; when `Application.can_get("unit", path)` is true AND `Application.can_get("package", path)` is false (engine has the unit, but there's no standalone package), short-circuit by setting `_packages_to_load[path] = true` and `_loaded_packages[path] = true` so `_spawn_items` proceeds straight to `World.spawn_unit`. The unit spawn then resolves against LA's globally-loaded resource package. Vanilla weapons are unaffected because their paths satisfy both can_get checks; we only short-circuit the bundled-into-larger-package case. Also extended `cos la_offhand_dump` to print per-variant `1p=<bool> 3p=<bool> pkg=<bool>` so future "no model" reports can be triaged in one command.

## [2026-05-07 v0.8.11-dev]
### Added
- **Custom-mesh LA shields now appear in the picker.** Previously `_la_bridge._is_supported_variant` rejected every `kind="unit"` SKIN_LIST entry — LA's own authored 3D shield meshes (Caledor, Chrace, Eaglegate, Eataine, Griffongate, KarakNorn, Kotbs/Ostermark spear+round variants, etc.) — because an early "Unit not found" crash in v0.7.92 made me skip them wholesale. Re-enabled them: LA's resource_package includes `unit = ["units/*"]` so all of LA's `.unit` files are engine-resident as soon as LA finishes loading, and the runtime gate in `BackendUtils.get_item_units` (`_override_package_ready` -> `Application.can_get("unit", path)` AND its `_3p` sibling) will silently skip the override for any mesh the engine genuinely can't spawn. So we get every custom-mesh shield exposed, with a per-spawn safety net for the rare case where one isn't actually engine-resident. For `kind="unit"` variants without a `textures` table, LA's `apply_new_skin_from_texture` early-outs at the `if mod.SKIN_LIST[Armoury_key].textures` check, so no paint is applied — the visual change comes purely from the mesh swap, which is the right behaviour for a custom-mesh variant.

## [2026-05-07 v0.8.10-dev]
### Removed
- **Live glow re-paint reverted.** v0.8.7's `mod._refresh_glow` (and the v0.8.9 `cos repaint_glow` chat command) walked `ScriptUnit.extension(local_player_unit, "inventory_system")._equipment.slots` and painted every `right_unit_1p / right_unit_3p / left_unit_1p / left_unit_3p`. Worked for the wielded slot but destabilised adjacent units — user reported that after running the repaint, pressing X (inspect) made hand meshes disappear and 1P state break, only recoverable by switching characters. Root cause not pinned (likely the engine doesn't tolerate `set_vector3_for_materials` on currently-invisible / sheathed 1P units), and I don't have enough data to fix it safely. Removed the function, the command, and the `mod.on_setting_changed` glow dispatch. The hook on `GearUtils.apply_material_settings` (v0.8.4+) is unaffected and still paints any newly-spawned weapon at equip time. Net effect for the user: changing the override or preset now takes effect on the NEXT weapon equip / spawn rather than instantly. To re-add live updates safely, the future approach is to hook the wield event and paint only the weapon at the moment it becomes visible.

## [2026-05-07 v0.8.8-dev]
### Changed
- **Glow override presets renamed to plain colors.** Settings dropdown now reads "Purple / Gold / Red / Green / Blue" instead of the lore names ("Weave-Forged / Geheimnisnacht Dawn / Skulls / Sister of the Thorn / Bitter Dreams"). Underlying preset keys (`purple_glow`, `golden_glow`, `deep_crimson`, `life_green`, `lileath`) unchanged so saved user settings carry over. The Versus / Shyish-Infused preset (5-channel `color_glow_high/low`, `color_smoke_high/low`, `color_dots`) was REMOVED from the dropdown — it drives a different shader path and the user reports it doesn't visibly affect Shyish-Infused weapons via the rune-emissive overlay. Tracked: Weavebound (`magic` rarity, `_magic_01` mesh, baked swirl shader) and Shyish-Infused (`versus` template) likely need their own toggle / probe-driven approach if they're tunable at all. The `versus` entry in `_GLOW_PRESETS` is left in place so the code can still be invoked from a future per-skin UI; it's just not user-facing right now.

### Fixed
- **Apply now works when only the offhand was changed.** Previously, clicking an LA shield without first changing the primary illusion enabled the Apply button but did nothing — the user had to make a primary-row change to "kick" Apply into running. Root cause: vanilla's craft loop (`_handle_input` → `_craft(self._material_items, ...)`) is a no-op when `_material_items` is empty, and `_ct_on_offhand_pressed` never seeded it. Fix: when handling an offhand click, if `_material_items` is empty, look up the currently-effective skin's backend id via `Managers.backend:get_interface("items"):get_weapon_skin_from_skin_key(...)` (which will mint a fake id via our existing `_fake_skin_backend_ids` machinery if the skin isn't in the player's owned set) and push it into `_material_items`. Also flip `_skin_dirty = true` so the post-craft state transition runs `_present_item`. The craft itself is a no-op skin re-apply (same skin in, same skin out), but the ensuing `_apply_weapon_skin_craft_complete → _set_loadout_item` path triggers a weapon re-spawn — and that re-spawn is what our `BackendUtils.get_item_units` hook needs to pull in the new offhand selection.

## [2026-05-07 v0.8.7-dev]
### Added
- **Live glow override re-paint.** Toggling `glow_override_enable` or switching `glow_override_preset` now immediately repaints the local player's currently-spawned weapon units — no re-equip needed. Mechanism: `mod.on_setting_changed` dispatches into `mod._refresh_glow`, which walks `ScriptUnit.extension(local_player_unit, "inventory_system")._equipment.slots` (same access pattern as `cos probe_hat`), and for each `right_unit_1p` / `right_unit_3p` / `left_unit_1p` / `left_unit_3p` slot field either overlays the chosen preset or, when the toggle has just been turned OFF, restores the skin's native template via vanilla `GearUtils.apply_material_settings(unit, WeaponSkins.skins[skin_key].material_settings_name)`. Stylish (`_runed_01`, no template) skins can't be restored — but they also weren't being painted, so that's a no-op. New chat command `cos repaint_glow` triggers the same walk manually for diagnostics. Forward-reference safety: `_refresh_glow` is attached to `mod` rather than declared as a bare local so the early `mod.on_setting_changed` callback can dispatch through a runtime table lookup (per `feedback_lua_forward_reference.md`). Husks (other players' 3p weapons) NOT covered yet — they live on a different inventory extension. Tracked as follow-up.

## [2026-05-06 v0.8.6-dev]
### Changed
- **Glow override 1P verified working; stripped diagnostic logging.** v0.8.5 added a `[GLOW-trace]` line per `GearUtils.apply_material_settings` call (~6 lines per equip). With user testing on console-2026-05-07-00.25.35.log: every call lands on a live `userdata` unit (alive_ok=true, alive=true) for both 3p and 1p paths, and `Unit.set_vector3_for_materials` returns `ok=true` for each. The hook works as designed. v0.8.6 keeps the hook-safe overlay but gates the trace behind `mod:get("glow_trace")` (off by default; same pattern as `cos_thiccc_trace` and `apply_trace`). User confirmed 1P glow now follows the chosen preset.

## [2026-05-06 v0.8.5-dev]
### Added
- **`[GLOW-trace]` diagnostic logging** on every `GearUtils.apply_material_settings` invocation — unconditional in this build to investigate the "1P glow override doesn't paint" report after v0.8.4. Logs template name, unit type, `Unit.alive` status, and per-variable `set_vector3_for_materials` ok/err. Verified the hook pipeline is sound; trace gated behind toggle in v0.8.6.

## [2026-05-06 v0.8.0] — Dynamic portraits split out
### Removed
- The dynamic-portrait system moved into the standalone
  `dynamic_cosmetic_portraits` mod (Workshop 3721036701, private). Removed
  ~570 lines covering `_PORTRAIT_MATERIALS`, `_hat_portrait_map`,
  `_skin_portrait_map`, state vars, `_collect_all_guis`,
  `_check_portrait_materials_ready`, `_get_kruber_merc_*_key`,
  `_restore/_sync_portrait_settings`, the `portrait_diag` /
  `portrait_dump` / `test_portrait` commands, and the `UnitFrameUI:draw`
  hook. The orphan `_get_hat_item_key_for_unit` helper was deleted.
- Removed the `dynamic_portraits` setting widget + `custom_gui_textures`
  block from `cosmetics_tweaker_data.lua`, plus the matching localization
  entries.
- Removed 30 portrait `material =` and 30 `texture =` declarations from
  `cosmetics_tweaker.package`.
- Moved 90 asset files (30 `.material` + 30 `.png` + 30 `.texture`) and
  `CHARACTER_COSMETIC_CATALOG.md` into the new mod.

### Kept
- The `NewsFeedUI:draw` hot-reload safety hook stayed here — it protects
  illusion / LA bridge atlases, not portrait materials.

## [2026-05-06 v0.8.4-dev]
### Fixed
- **Glow override now lands on first-person weapons.** v0.8.1's `create_equipment` post-hook only painted 3p reliably; 1p stayed the template's original color. Replaced the post-spawn paint with a `hook_safe` on `GearUtils.apply_material_settings` itself — vanilla calls this for both 3p AND 1p weapon units inside `spawn_inventory_unit` (gear_utils.lua:198 + 270), as well as ammo units, projectile dummies, pickups, and the loot-item previewer. Same trick `NoGlow` uses to zero out emissive. Verified test path: equipping a Veteran skin with `purple_glow` then switching the override preset to Crimson now turns BOTH the keep mannequin's blade and the wielded first-person blade red on the next equip. Known caveat (separate issue): skins that don't already have a `material_settings_name` (Stylish `_runed_01` items) still don't take the override — vanilla never calls `apply_material_settings` on them, so this hook never fires for them. Fix path is to also paint at spawn time when no template was set, but that requires understanding why our v0.8.1 post-spawn paint silently no-ops on Stylish materials — separate investigation.

## [2026-05-06 v0.8.3-dev]
### Changed
- **Gated `[apply-trace]` logging behind `mod:get("apply_trace")` toggle.** v0.8.2 added per-event trace lines on `_enable_craft_button` and `_on_illusion_index_pressed` to investigate the "Apply doesn't update the weapon" report. The trace did its job (verified Apply now commits correctly — 4 successful `Applied illusion` events in console-2026-05-06-19.06.33), but at ~50 lines per customization session it drowns out other diagnostics. Now off by default; enable via mod settings file when needed. No widget — same pattern as `cos_thiccc_trace`.

## [2026-05-06 v0.8.2-dev]
### Added
- **`[apply-trace]` diagnostic logging** on `_enable_craft_button` and `_on_illusion_index_pressed` to investigate user report "the weapon doesn't get updated when I hit apply". Pre-fix log analysis (console-2026-05-06-18.50.02 covering 3 customization sessions): zero `Applied illusion` events, backend-resolved skin remained `skin_01` throughout, suggesting Apply was either greyed-out at click time OR never clicked. Trace will surface: every craft-button enable/disable transition with `_skin_dirty` + `_current_recipe_name` + `eac-untrusted` state; every illusion pick with `picked_skin` vs `current_skin`/`default_skin` and the `differs` boolean that gates vanilla's `_skin_dirty = true`. Once the user repros, this pinpoints whether Apply was greyed (no `enable=true` log) or fired without committing (enable=true but no `Applied illusion`).

## [2026-05-06 v0.8.1-dev]
### Added
- **Weapon Glow Override (Phase 1)** — new settings group under "Weapon & Item Appearance". Master toggle `glow_override_enable` plus a 6-option preset dropdown (Purple / Gold / Crimson / Green / Lileath / Versus). When enabled, every spawned weapon has the chosen preset's material variables applied — `rune_emissive_color` (vector3) for the 5 rune templates, or the 5-channel `color_glow_high/low`, `color_smoke_high/low`, `color_dots` set for Versus. Templates verbatim from `weapon_material_settings_templates.lua`. Engine silently no-ops on materials that don't expose the variable, so the override is safe to call universally — only runed/versus-capable meshes change visually. Hooked into all three render paths (`GearUtils.create_equipment` for in-game, `HeroPreviewer/MenuWorldPreviewer._spawn_item` for inventory mannequin, `LootItemUnitPreviewer.spawn_units` for the illusion browser). Phase 1 is global only — per-skin customization comes in Phase 2 once Phase 1 proves the substrate.

## [2026-05-06 v0.7.102-dev]
### Fixed
- **Pending row-1 illusion was reverted to the last-Applied skin every time the user clicked a shield in row-2.** `_ct_on_offhand_pressed` re-resolved the skin via `self:_get_item(backend_id)` → `item.skin` / `items_iface:get_skin(backend_id)` / `WeaponSkins.default_skins`. All three return the BACKEND-stored skin — i.e. the LAST APPLIED illusion. So if the user picked a new row-1 illusion (which only updates `_skin_dirty` and the customization-preview previewer, not the backend) and then clicked a shield in row-2, our respawn discarded the pending row-1 pick and re-rendered with the previously-Applied illusion. **Fix:** read `self._previewer._item.data` and `._previewer._item.skin` first (vanilla `_on_illusion_index_pressed` writes the pending selection there) and only fall back to backend resolution when the previewer isn't initialized yet.

## [2026-05-06 v0.7.101-dev]
### Fixed
- **Crash on Apply with runed/glowy Bret illusion (`Unit not found #ID[f3ec09a279311ac8]` at `world.spawn_unit`)** — GUID 1a7b27db-e813-467d-87f3-6bc0efd9c472. Root cause: `BackendUtils.get_item_units` is called from `GearUtils.create_equipment` with `backend_id=nil, skin=nil` and relies on `item_data.backend_id` (which vanilla stamps onto item_data during loadout resync) to internally resolve the equipped illusion. **Our hook only consulted the explicit `backend_id` arg**, so it bailed at the `has_skin=false` gate for every in-game equip — the user's row-2 selection never applied to the player body, AND we never had a chance to redirect away from a runed-shield path whose package the engine hadn't preloaded. Fix: mirror vanilla's resolution chain — check `item_data.backend_id` as a third fallback after the explicit args. With this, in-game spawns now consistently see the user's offhand selection and route to a preloaded shield mesh, eliminating the `_runed_01` resource-not-found crash. Crash trace verified at console-2026-05-06-04.53.08 line 6926: trying to spawn `wpn_emp_gk_shield_02_runed_01_3p` AFTER LootItemUnitPreviewer had unloaded that package at 05:11:25.073, while `_offhand_selection["es_1h_sword_shield_breton"] = "Empire Shield (Gold)"` (`unit = wpn_emp_gk_shield_05`, both 1p+3p preloaded at 05:11:30) was sitting unused.

### Documented limitations (carry-forward)
- **LA texture paint is invisible on `_magic_*` / `_runed_*` Bret illusions** — confirmed empirically via the v0.7.99 log. The glow-emissive material variants don't expose the standard shield diffuse slot hash (`texture_map_c0ba2942`), so `Material.set_texture` returns `ok=true` but no pixel changes — every LA option visually looks identical to the equipped shield. LA's own `icons` table enumerates compatibility per LA variant (e.g. `Reynard01.icons.es_sword_shield_breton_skin_03_runed_01` = a *bluegrlow* icon variant); we currently don't honor it. To restore visible paint on glow shields we'd need to either (a) filter LA options by `icons` compatibility, (b) force a mesh swap to a compatible non-glow vanilla shield before painting (re-introducing the v0.7.86-disabled override path with safer mesh choices), or (c) drive a per-frame re-paint loop the way LA's normal mode does. Not in this release.
- **LA paint "sticks" across shield changes — switching to a different shield (vanilla or LA) keeps showing the previous LA texture.** This is the shared-material-instance problem: VT2/Stingray's `Material.set_texture` mutates the material asset in place, and shield meshes that share a material file inherit the override globally. We can't reset textures from Lua (no `Material.reset_texture` in VT2), and we can't snapshot originals (no `Material.get_texture` either). LA itself "solves" this by re-painting every shield in the world every frame — we don't, and only paint at spawn time. Future fix candidates: per-frame re-paint loop; per-unit material cloning via `World.create_material`; or restore-on-deselect by remembering a known vanilla diffuse texture per shield mesh. Not in this release.

### UX clarification on Apply for row-2-only changes
- **Apply only commits row-1 (illusion) changes** — that's vanilla `HeroWindowItemCustomization._skin_dirty` behaviour gating `_apply_weapon_skin_craft_complete`. Row-2 offhand selections are stored in `_offhand_selection` the moment the button is clicked and apply on the next item spawn (in-game equip, mannequin re-render). With v0.7.101's `item_data.backend_id` fix, the in-game body and mannequin now reliably reflect row-2 changes on the next spawn — but **Apply itself doesn't trigger a respawn for row-2-only changes**. Forcing an immediate mannequin refresh from row-2 click would require reaching the parent HeroView's previewer instance from inside `HeroWindowItemCustomization`. Tracked as TODO. Workaround for now: close customization (Back) → mannequin re-renders with the new row-2 selection.

## [2026-05-06 v0.7.100-dev]
### Fixed
- **`Unlock All Portrait Frames` toggle never injected anything** (silent no-op since the feature shipped in v0.7.0-dev). Root cause: the hook targeted `PlayFabMirrorBase` but the runtime instance is `PlayFabMirrorAdventure`. VT2's foundation `class()` helper at `foundation/scripts/util/class.lua:51-57` defines inheritance by **copying** parent methods into the child table at class-definition time — there is no `__index` chain to the base. So `mod:hook("PlayFabMirrorBase", "_create_fake_inventory_items", ...)` registered correctly but wrapped a function value the runtime instance never dispatches to. Verified empirically against `console-2026-05-06-02.40.42.log`: VMF logged `Hooking '_create_fake_inventory_items' from [PlayFabMirrorBase]` at mod load (02:41:12.686), well before PlayFab login at 02:41:22, but the in-game `cos frames_status` diagnostic reported `inject hook fired 0 time(s)` even with the toggle on and modded realm detected. **Fix:** re-targeted both hooks to `PlayFabMirrorAdventure`. Added a more reliable pre-hook on `_create_fake_inventory_items` that mutates the `fake_inventory_items` parameter to inject all frame keys *before* the original mints fake backend IDs — this is the actual gate that registers items into `_inventory_items` (the table the UI's `get_filtered_items("slot_type == frame")` reads). The companion safe hook on `get_unlocked_cosmetics` keeps the table in sync for later UI re-queries. DLC ownership still respected via `_skin_requires_unowned_dlc`. Toggle still requires a full restart to take effect (the gate runs once at PlayFab login). Memory note: `feedback_vt2_class_hook_derived.md`. Diagnostic command `cos frames_status` retained.
- **LA shield paint not visible on the inventory loadout mannequin for vanilla-crafted Bretonnian sword & shield** ("Apply seems to do nothing", "all LA shield options look like the equipped shield"). Root cause: vanilla `equip_item` is called with `skin=nil` for vanilla-crafted Bret weapons because the applied illusion is stored only on the backend `BackendItem` object, not passed through the call chain. Vanilla relies on `BackendUtils.get_item_units` to resolve the skin internally during spawn — but our `_store_equip_skin` hook was caching the literal `nil` arg, so `_spawn_item_post`'s `has_skin` gate failed and LA paint was skipped on the mannequin. **Fix:** `_store_equip_skin` now falls back to `Managers.backend:get_interface("items"):get_skin(backend_id)` when the passed `skin` is nil, mirroring the same resolution chain `_setup_illusions` and `_ct_on_offhand_pressed` already use. Now logs `[LA preview] backend-resolved skin for X: Y` whenever the fallback fires, so future regressions are visible. The customization-screen preview (`LootItemUnitPreviewer`) and in-game body (`GearUtils.create_equipment`) were already painting correctly — only the inventory mannequin path was broken. Verified against console-2026-05-06-02.40.42 log: `[LA paint] skip: has_skin=false` repeating after `equip_item key=es_sword_shield_breton ... skin=nil`.

### Note on Apply button UX
The `Apply` button in the customization screen only commits the row-1 (illusion) selection — that's vanilla behaviour, not a bug. Row-2 offhand selections are stored in `_offhand_selection` the moment the button is clicked and applied on the next item spawn (mannequin re-render, in-game equip). Before this fix, the user-facing symptom on Bret weapons was that the mannequin re-rendered after Apply but never showed the LA paint, making it look like Apply ignored the shield change. With the backend-resolve fix the mannequin now paints correctly on the first re-render after Apply, so the row-1+row-2 changes appear together as the user expects.

## [2026-05-05 v0.7.98-dev]
### Fixed
- **Imperial Longsword (cwv) was being thinned in the inventory character preview** despite the v0.7.87 unit-path migration and the v0.7.90 `cwv_variant` gate. Root cause: the menu hook resolved per-hand paths via `item_data.right_hand_unit` + a separate `info.skin_name` -> `WeaponSkins.skins[skin].right_hand_unit` lookup, which was redundant with what vanilla `equip_item` had already computed. Vanilla calls `BackendUtils.get_item_units` once and stores the resolved per-hand path on each `spawn_data` entry as `unit_name` — that's the only truth source for "what unit IS rendered in this slot right now". Switched both menu hooks (`HeroPreviewer/MenuWorldPreviewer._spawn_item` and `LootItemUnitPreviewer.spawn_units`) to read paths straight from `spawn_data[i].unit_name`. Side-effects: dropped the `cwv_variant` defence-in-depth gate (no longer needed — a cwv item's `unit_name` is always its variant model and can't accidentally match a base-weapon pattern); dropped the now-unused skin-resolution branch on the LootItem path. The GearUtils in-game hook keeps `_resolve_render_unit_path` because it doesn't have a pre-resolved spawn_data array — it gets `result.skin` from the spawn result and looks up the rendered path itself.

## [2026-05-05 v0.7.95-dev]
### Removed
- **"Elven Spear" / "Elven Spear (Exotic)" cosmetic options on Kruber's spear & shield** (`ct_es_deus_we_01/02`). Cross-character (Wood Elf models on a Kruber weapon) — same no-cross-character rule that drove the v0.7.94 Kerillian-side removal.

## [2026-05-05 v0.7.94-dev]
### Removed
- **"Empire Spear & Shield" cosmetic options on Kerillian's spear & shield** (`ct_we_spear_shield_es_01/02/03`). These violated the no-cross-character rule (Empire models on a Wood Elf weapon). Reverting per user.

### Changed
- **"Elven Spear & Shield" illusions on Kruber's spear & shield (`ct_es_deus_we_01/02`) now swap only the spear**, not the shield. Removed `left_hand_unit` from both entries and renamed to "Elven Spear" / "Elven Spear (Exotic)". Picking one in the row-1 illusion picker leaves the shield untouched, so the user's row-2 offhand selection (or the base weapon's default shield) stays in place. Fixes the "equipping the spear model also changes the shield" report — the bundled `left_hand_unit` was forcing both swaps in one click.

## [2026-05-01 v0.7.90-dev]
### Fixed
- **Bretonian thiccc was leaking onto cwv Imperial Longsword in the inventory character preview** (regression introduced by v0.7.87's unit-path migration plus the `_spawn_item_post` slot-walk bug fixed in v0.7.88). Added an explicit `not item_data.cwv_variant` gate to `_spawn_item_post` AND to the `LootItemUnitPreviewer.spawn_units` hook for symmetry with the GearUtils path. Unit-path matching alone *should* exclude cwv variants (their models don't contain `wpn_emp_gk_sword_`), but the gate is defence-in-depth — guarantees no future model collision can cause cwv items to be scaled by a base-weapon override even accidentally.
- Hidden debug toggle: `mod:get("cos_thiccc_trace")` enables `[thiccc]` log lines on each menu apply (item name, skin, resolved right/left paths). No widget — set via mod settings file when needed.

## [2026-05-01 v0.7.88-dev]
### Fixed
- **Character preview in inventory wasn't applying any scale to the Bretonian Longsword** (regression from v0.7.87). `_spawn_item_post` was iterating `self._equipment_units` by numeric `slot_index` and trying to read `_item_info_by_slot[slot_index]`, but `_item_info_by_slot` is keyed by string slot_type (`"melee"` / `"ranged"`). The lookup always returned nil so the per-slot info was never resolved. Now walk `_item_info_by_slot` directly and bridge to `_equipment_units` via `info.spawn_data[1].slot_index`.

## [2026-05-01 v0.7.87-dev]
### Changed
- **Migrated `_weapon_scale_overrides` (item-name-keyed) → `_unit_path_scale_overrides` (model-path-keyed).** The old schema scaled any item whose `item_data.name` matched a registered key (e.g. `es_bastard_sword`). This collided with character_weapon_variants items, which inherit `name = "es_bastard_sword"` from their base via `table.clone` — even with the v0.7.84 `cwv_variant` gate, the gate on the GearUtils hook didn't cover the menu paths that match by `item_name` parameter (the cwv item key, which doesn't match the base name). The new schema matches against the actual model unit path resolved through skin/item, so cwv variants (Imperial Longsword loads `wpn_2h_sword_*`, Helmgart Watchsword loads `wpn_greatsword`) are intrinsically excluded — they don't load the Bretonian model.
- New helpers: `_resolve_render_unit_path(item_data, skin, hand_field)` mirrors `BackendUtils.get_item_units` resolution (skin path takes precedence), `_resolve_factor(factor)` normalizes function/table/number factors into a Vector3, `_apply_unit_path_scale_hand(unit_3p, unit_1p, path, hand_label)` is the per-hand apply primitive.
- `_unit_path_scale_overrides` schema:
  ```
  { pattern = <substring>, factor = <function|{x,y,z}|number>, hand = "right"|"left"|nil }
  ```
- `_weapon_grip_offsets` is unchanged (still item-name-keyed) and currently empty. Grip-offset runs only in-game per `feedback_grip_offset_sign.md`. See DEVELOPMENT.md "Weapon Scale Overrides" for the full schema documentation.

## [2026-05-01 v0.7.86-dev]
### Changed
- **Disabled mesh override for LA shield variants** (deferred fix): even with sync preload, `can_get("unit", ...)`, and `has_loaded()` gates, swapping `left_hand_unit` to LA's declared `new_units[1]` (e.g. `wpn_es_deus_shield_03` for Imperial Hero Ostermark/Kotbs) consistently crashed `World.spawn_unit` with "Unit not found #ID[9405eeb80a227a76]" across v0.7.81–v0.7.85. The `_3p` variant of those deus shield meshes doesn't appear to be reliably available in keep contexts (LA's flow assumes the user has a CW weapon equipped, which loads the deus shield packages — our flow has no such guarantee). `Application.can_get("unit", path)` returned true but the actual `World.spawn_unit` still asserted, suggesting `can_get` checks resource registry availability rather than spawn-readiness.
- All LA shield variants now paint LA textures onto the user's currently-equipped shield mesh (same as the Bret pure-texture variants did successfully). UVs may not match perfectly when an Imperial Hero variant authored for the deus shield shape lands on a Bret GK shield, but it's a survivable visual mismatch vs. a hard crash.
- **TODO** (tracked in `_la_bridge.lua` `_resolve_intended_unit` doc-comment): identify which resource_package actually owns the deus shield 3p variants. Once known, either preload it on demand at customization screen open, OR filter affected LA variants out of the picker pool when their packages aren't engine-resident.

## [2026-05-01 v0.7.85-dev]
### Fixed
- **Crash on Apply with Imperial LA shields (real root cause)**: LA's `Kruber_empire_shield_hero1_*` variants target `wpn_es_deus_shield_03`, which has NO standalone `units/.../wpn_es_deus_shield_03.package` file — the deus shield meshes live INSIDE `resource_packages/levels/dlcs/morris/wastes_common`, which LA loads at boot. Calling `Managers.package:load("units/.../wpn_es_deus_shield_03", ...)` on a non-existent package_name still wrote `self._packages[path]` (because `Application.resource_package` returns a handle anyway and `ResourcePackage.load` runs without erroring) — `has_loaded` then lied, the override fired, and `World.spawn_unit` asserted because the unit isn't actually in the resource manager. **Fix:** preload now uses `Application.can_get("unit", path)` to check whether the unit is engine-resident from ANY source (resource_package or standalone) before attempting to load. The defensive `_override_package_ready` gate also switched to `Application.can_get("unit", ...)`. Together these handle both packaging styles correctly.
- **LA selection reset after Apply**: clicking Apply rebuilt the customization screen with the new skin → `_setup_illusions` re-fired → the v0.7.79 stale-mesh-mismatch check discarded the user's LA selection because the new skin's `left_hand_unit` no longer matches the LA `intended_unit`. **Fix:** track `_offhand_selection_backend_id[weapon_key]` per selection. Only discard when the screen reopens for a DIFFERENT item (different backend_id) of the same item_type. Reload-after-Apply keeps the same backend_id, so the user's pick persists. Mesh mismatch alone no longer wipes the selection.

### Addressed (from REVIEW_AGGREGATE.md, 2026-05-01)
- **rawget audit (review item 9)**: replaced 7 unguarded `ItemMasterList[<dynamic_key>]` lookups with `rawget`. Sites: `_get_weapon_skin_from_skin_key` hook (3 lookups, lines ~1600), `register_custom_illusion` matching_weapon (line 1460), `_get_weapon_key_from_item` (line 1982), `_setup_illusions` item.key fallback (line 2001), `BackendUtils.get_item_units` matching_item_key (line 2257), `_resolve_item_type` matching_item_key (line 2361), `_spawn_item_post` item_name (line 2490), `LootItemUnitPreviewer.spawn_units` weapon_key (line 2615). Per CLAUDE.md, `ItemMasterList.__index` Crashifies on unknown keys; rawget bypasses the metamethod.
- **Custom illusion `_description` shadowed by `_name` (review item)**: `_custom_loc[skin_key .. "_description"] = illusion.display_name` made the Localize hook return the title text for description tooltips, hiding the descriptive entries in `cosmetics_tweaker_localization.lua`. Removed the override; description keys now fall through to the vanilla localizer.
- **Captured-but-unused `orig_hook` in `_fixup_server_clones`**: deleted.

### Notes on remaining REVIEW_AGGREGATE items
The aggregate review covers all 7 mods; this version addresses the cosmetics_tweaker high/medium-priority items plus the user's active offhand-picker bugs. Other mods' items (weapon_tweaker forward-reference at line 256, enemy_tweaker breed registration timing, chaos_wastes potion weight renormalization, ANTIGRAVITY.md banner, doc drift) need separate per-mod sessions and are tracked in `REVIEW_AGGREGATE.md`'s recommended fix order.

## [2026-05-01 v0.7.84-dev]
### Fixed
- **Equipment menu's character preview showed the default (un-painted) shield**: the inventory/loadout view's character preview uses `HeroPreviewer:_spawn_item(item_name, spawn_data)` — `item_name` is the WEAPON master key (e.g. `es_breton_sword`, item_type = `es_1h_sword_shield_breton`), not a skin entry. Our existing `has_skin` gate (`item_data.item_type == "weapon_skin"`) returned false here even though the player HAS an illusion equipped (set via `equip_item(..., skin, ...)`), so `_apply_la_offhand_to_units` was skipped on this path. Now hook `HeroPreviewer:equip_item` (mirroring the existing `MenuWorldPreviewer:equip_item` hook) to capture the `skin` arg into a per-previewer-per-item map (`_equip_skin_by_item`, weak keys on previewer). `_spawn_item_post` reads back the stored skin — if non-empty, has_skin is true and the LA paint runs. Base weapons hovered in the inventory grid hit neither the weapon_skin item_type nor a stored skin → pass-through unchanged, matching the "we add options on top of illusions, never mutate base templates" rule.

## [2026-05-01 v0.7.83-dev]
### Fixed
- **Crash on Apply (root cause: async preload race)**: previous preloads called `Managers.package:load(path, ref, nil, true)` with `async=true`, returning immediately while the load happened in the background. If the user hit Apply before the load completed, `BackendUtils.get_item_units` returned an override path the engine couldn't spawn yet → assertion in `world.spawn_unit`. Switched to **synchronous** load (`async=false`, the VT2 default — `ResourcePackage.load + flush` blocks until ready). One shield package is small; the hitch is unnoticeable. Verified against `foundation/scripts/managers/package/package_manager.lua:80-86`. Wrapped in pcall to swallow "package not found" errors for paths that don't exist on the user's install.
- **Defensive package-loaded gate in `BackendUtils.get_item_units` hook**: even with sync preload, an `_override_package_ready(unit_path)` check now verifies BOTH 1p and 3p packages are fully loaded before applying the override. If not, we skip the override (logs the skip). Belt-and-suspenders against future regressions and unknown paths.
- **Extra diagnostic logging** in `_apply_la_offhand_to_units`: now logs why the LA paint is skipped (no bridge / no world / has_skin=false / no item_type / no selection) and reports paint success/failure per unit. Use this to diagnose the "Bret LA shields not visually changing" report — share the `[LA paint]` lines from `Console.log` so we can see exactly where the flow stops.

## [2026-05-01 v0.7.82-dev]
### Fixed
- **Crash on Apply (still happening after v0.7.81 preload)**: the v0.7.81 preload only loaded the base unit path. Vanilla VT2 packages the 1p and 3p meshes in SEPARATE packages — LA's own bootstrap proves it (`Managers.package:load("...wpn_X", "global")` AND `Managers.package:load("...wpn_X_3p", "global")`). The in-game body spawns both halves; the customization previewer only spawns 3p. Now preload both `<unit_path>` and `<unit_path>_3p` for every offhand override.
- **Bret offhand picker had no visible effect (clicks did nothing)**: vanilla-crafted Bret weapons sometimes have their equipped illusion stored only in the backend, with `item.skin` nil on the BackendItem object. The respawn-after-click branch in `_ct_on_offhand_pressed` was checking `item.skin or WeaponSkins.default_skins[item.key]` — both nil → no respawn, click was a no-op. Now falls through to `items_iface:get_skin(item.backend_id)` before giving up, mirroring the auto-select resolution path.

### Kruber LA shield count
13 Kruber LA shield variants total in `swap_hand="left_hand_unit"`. 7 currently exposed in the picker:
- 5 Bret/GK pure-texture (Bastonne02, Reynard01, Luidhard01, Lothar01, Alberic01)
- 2 Empire heroic texture (Ostermark01, Kotbs01)

The other 6 are LA's `kind="unit"` Empire basic variants (basic1, basic1_Ostermark01, basic2, basic2_Kotbs01, basic2_Middenheim, basic3_Middenheim01) with custom-authored mesh paths under `units/empire_shield/`. They're filtered out for now — restoring them needs LA's custom-mesh packages preloaded via `Managers.package:load`, which I haven't added yet.

## [2026-05-01 v0.7.81-dev]
### Fixed
- **Crash on Apply: "Unit not found" / `world.spawn_unit` assertion** — different cause from v0.7.80. Each vanilla weapon-skin's package chain bundles only its OWN `left_hand_unit`. Our override pointed `result.left_hand_unit` to a different shield mesh whose package was never part of the newly-applied skin's chain, so on re-equip the engine asserted. Fix: preload the override mesh's package via `Managers.package:load(unit_path, "cosmetics_tweaker", nil, true)` whenever the offhand selection changes. Wired into both `_setup_illusions` (auto-select on screen open) and `_ct_on_offhand_pressed` (manual click). Packages stay resident under the `cosmetics_tweaker` reference name for the rest of the session — small per-shield cost, ~one shield package per option the user has touched.

## [2026-05-01 v0.7.80-dev]
### Fixed
- **Crash: "Unit not found" / `world.spawn_unit` assertion** — v0.7.79's `new_units[1]` mesh resolution started forwarding LA's `kind="unit"` variants too. Those variants point to LA's custom-authored mesh files (e.g. `units/empire_shield/Kruber_Empire_shield01_mesh`) that ship without standalone packages — `LootItemUnitPreviewer:load_package` can't fetch them, and the engine asserts on `world.resource_manager().can_get(unit_type, unit_name)` when we set `result.left_hand_unit` to one of those paths. Filter LA's offhand pool to `kind="texture"` variants only (those paint onto a vanilla mesh the engine already has). LA's custom-mesh variants (`kind="unit"`) are excluded — supporting them would require loading LA's packages via `Managers.package:load`, which we'd need to add separately.
- **Pure-texture LA variants** (the Bret heraldic shields with no `new_units` field): no longer fall back to a guessed mesh from the first lex-sorted icon key. With `intended_unit = nil`, we leave the user's currently-equipped shield in place and let LA paint onto it — which is what LA's normal flow does, and matches the user-confirmed "Bret shields look fine" outcome.

### Known limitation
- LA's custom-mesh shield variants (e.g. `Kruber_empire_shield_basic1`-`basic3`, `Kerillian_elf_shield_basic_Avelorn01_mesh`, etc.) are not exposed in the picker yet. Restoring them requires hooking into LA's package-load bootstrap so the engine can spawn them. Tracked separately.

## [2026-05-01 v0.7.79-dev]
### Fixed
- **LA shield model resolution was wrong for Imperial heroic shields**: every LA `swap_hand="left_hand_unit"` SKIN_LIST entry explicitly declares its target mesh in `variant.new_units[1]`. The previous resolution path (texture-path regex + lex-sorted first-icon-key) was unreliable and assumed mesh hints from filenames; it routed Empire heroic shields like `Kruber_empire_shield_hero1_Ostermark01` and `_Kotbs01` to wrong meshes. Replaced both heuristics with a direct `variant.new_units[1]` lookup. Texture variants get the vanilla mesh LA paints onto; unit variants get LA's custom-authored mesh. Falls back to the first-icon heuristic only if `new_units` is missing (doesn't appear in current LA skin_list.lua).
- **Picker not highlighting the current shield for officially-crafted weapons**: `_setup_illusions` now resolves the equipped illusion via `items_iface:get_skin(item.backend_id)` when `item.skin` is nil (vanilla-crafted weapons sometimes hit this path), then falls back to `item_data.left_hand_unit`. Also discards stale `_offhand_selection` entries whose mesh no longer matches the rendered shield, so the picker always reflects what's visible — not whatever the user last clicked. Added diagnostic logging (`mod:info` to log) for `weapon_key`, `item.skin`, resolved skin, current `left_hand_unit`, and the auto-selected option.

## [2026-05-01 v0.7.78-dev]
### Fixed
- **LA paint leaking into vanilla inventory icons & base weapon visuals** ("blazing sun on the mace and shield", "default Bret longsword shows LA reskin"): two distinct leaks both addressed.
  1. **Global state mutation** — `LA.apply_new_skin_from_texture` permanently writes `WeaponSkins.skins[skin].inventory_icon` and `ItemMasterList[skin].inventory_icon` whenever it runs. Before v0.7.74 this never fired (stale `_spawned_units` short-circuited our call). Once v0.7.74 fixed the hook timing, every preview leaked LA icons globally. Replaced the LA-apply call with a local `_paint_offhand_textures_locally` reimplementation in `_la_bridge.lua` that only touches the supplied unit's mesh materials — no `WeaponSkins` / `ItemMasterList` writes.
  2. **Override leaking onto base weapon template** — `_offhand_selection` is keyed by `item_type`, so an LA pick on a skinned Bret weapon also overrode the unrelated base Bret weapon (same `item_type`). Added a hard gate: the `BackendUtils.get_item_units` override and the LA paint both require an active skin (illusion). Base weapon spawns with no `skin` arg fall through to vanilla. Mirrors LA's own behavior — illusions can be customized; the base template can't.
- **Note:** existing icon pollution from prior sessions (where the previous code path leaked) only clears on game restart. Fresh sessions on v0.7.78+ will not leak.

### Added
- **`cos la_offhand_dump` command** — dumps each LA shield variant -> resolved `intended_unit` mapping with the source (`texture_hint` / `first_icon` / `unresolved`) and the variant's texture path. Use this to identify variants whose intended mesh is wrong and refine `_texture_mesh_hints` in `_la_bridge.lua`.
- **Texture-path hint parser** in `_la_bridge.lua` — `_texture_mesh_hints` table maps LA folder-name patterns (e.g. `Grail_Knight_shield(%d+)`, `bret_shield_`, `Knight_shield_(%d+)`) to canonical vanilla shield unit paths. Replaces the previous nondeterministic "first key from `pairs(variant.icons)`" heuristic that could pick different shields on different runs. Falls back to the lex-sorted first icon key when no pattern matches.

## [2026-05-01 v0.7.77-dev]
### Fixed
- **Cycling main-hand illusions visually swapped the shield too**: when no offhand had been explicitly chosen, the previewer fell back to each illusion's default `left_hand_unit`, so cycling skins changed BOTH the weapon and the shield even though the offhand picker exists. Now `_setup_illusions` auto-selects the offhand option whose `unit` matches the currently-equipped illusion's `left_hand_unit` (resolved via `WeaponSkins.skins[item.skin].left_hand_unit`, falling back to `item_data.left_hand_unit`). Once auto-selected, the existing `BackendUtils.get_item_units` hook locks the shield mesh, so cycling main-hand illusions only changes the weapon. The user can still pick any other shield from the offhand picker explicitly.

## [2026-05-01 v0.7.76-dev]
### Fixed
- **LA shields painting onto the wrong shield mesh** ("skin wrapped around the wrong model"): each LA `swap_hand="left_hand_unit"` variant in `mod.SKIN_LIST` is authored against a *specific* shield mesh — the one used by any skin listed in its `icons` table. Previously we left `result.left_hand_unit` alone and let LA paint on top of whatever shield the user's vanilla weapon happened to spawn (e.g. the Bret sword + shield's default mesh), which produced visibly wrong UVs whenever the LA texture was authored for a different shield (round Empire, GK, etc.). Now `_la_bridge.build_offhand_options` resolves the first `icons` key to `WeaponSkins.skins[k].left_hand_unit` and stores it as `intended_unit`. The `BackendUtils.get_item_units` hook swaps `result.left_hand_unit` to that intended mesh before LA paints, so the heraldic texture lands on the mesh it was authored for.

## [2026-05-01 v0.7.75-dev]
### Changed
- **Restored WP Shield to Kruber's offhand pool** (kept removed: Elven / Elven Exotic). Kruber now has 13 vanilla offhand options: 5 Empire + 5 GK + 2 Deus + WP Shield.

## [2026-05-01 v0.7.74-dev]
### Fixed
- **LA offhand paint never applied in the customization-screen preview**: the `LootItemUnitPreviewer.spawn_units` hook was using `mod:hook_safe` and reading `self._spawned_units`, but that field is only assigned by the *caller* (`_on_packages_loaded`) AFTER `spawn_units` returns — so inside `hook_safe` it was nil or stale. Switched to `mod:hook` and capture the returned `units` array directly. The same fix applies to the weapon-scale override path that runs in the same hook.
- Used `self._background_world` (the field actually set on `LootItemUnitPreviewer`) as the primary world lookup, with the previous `self._world`/`self.world` as fallbacks.

### Changed
- **Trimmed Kruber's vanilla offhand pool**: removed Elven Shield / Elven Shield (Exotic) / WP Shield. Kruber now sees only Imperial-themed shields (5 Empire variants, 5 GK variants, 2 Deus variants) — matches "imperial weapon and Bretonnian shields" intent.

## [2026-05-01 v0.7.73-dev]
### Added
- **Independent offhand swap for all shield-bearing weapons**: extended `_offhand_options` to cover Bardin's `dr_1h_axe_shield` and `dr_1h_hammer_shield`, plus Saltzpyre Warrior Priest's `wh_flail_shield` and `wh_hammer_shield`. Each pool includes the character's native shield models (5 dwarf shield families with runed/magic variants; WP shield + runed/magic variants) plus a curated cross-character set (Empire/GK/Elven/Dwarf/WP) for consistency with the Kruber and Kerillian pools.
- **`_la_character_weapon_pools.Saltzpyre`**: added `wh_flail_shield` / `wh_hammer_shield` mapping so any future Loremaster's Armoury Saltzpyre/WP heraldic shields automatically appear in the second-row picker. No-op until LA bridge populates a Saltzpyre entry.

## [2026-05-01 v0.7.72-dev]
### Added
- **LA shields in the two-row offhand picker**: Loremaster's Armoury heraldic shield variants are now selectable from the second row on the weapon customization screen, alongside the existing vanilla shield options. Per-character pool with cross-career fan-out: all Kruber shield heraldics (Bret + Empire) appear on every Kruber shield-bearing weapon (`es_1h_sword_shield`, `es_1h_mace_shield`, `es_1h_sword_shield_breton`, `es_deus_01`); Kerillian Elf heraldics on `we_1h_spears_shield`; Bardin Dwarf heraldics on `dr_1h_axe_shield` / `dr_1h_hammer_shield`. No cross-character.
- **`_la_bridge.la_offhand_options_by_character`** — bridge now parses LA SKIN_LIST entries with `swap_hand="left_hand_unit"` and groups them by character prefix.
- **`_la_bridge.apply_offhand_to_unit(world, unit, armoury_key, vanilla_skin)`** — paints LA heraldic textures onto a vanilla shield unit after spawn. Wired into `GearUtils.create_equipment` (in-game body), `_spawn_item_post` (HeroPreviewer/MenuWorldPreviewer inventory preview), and `LootItemUnitPreviewer.spawn_units` (illusion browser preview).

### Changed
- **`_offhand_selection[weapon_key]` now stores the option table itself** (was a unit-path string). Vanilla entries: `{ name, unit }`. LA entries: `{ name, la_armoury_key, vanilla_skin, rarity }`. The `BackendUtils.get_item_units` hook only overrides `result.left_hand_unit` for vanilla selections; LA selections leave the vanilla mesh in place so LA can paint heraldics on top at spawn time.

## [2026-04-30 v0.7.70-dev]
### Added
- **Armor clone support**: LA bridge now registers armor/outfit recolors (e.g. Kruber KOTBS, Kerillian Autumn Weave) as separate selectable items in the skin grid. Armor entries use `cosmetic_key` fallback when `new_units` unit-path matching fails, since armor `new_units` point to body meshes not found in IML `.unit` fields.
- **Rarity background colors**: LA clone items now show red "unique" rarity backgrounds in the cosmetics grid instead of gray "default". Hooked `items_iface:get_item_rarity` to return `"unique"` for any backend_id in `LA_BRIDGE.backend_to_armoury`.

### Fixed
- **`set_loadout_item` caching ALL slot_skin writes**: The hook was caching every `slot_skin` write, preventing vanilla skin equips from reaching the server. Narrowed condition to only cache writes where `LA_BRIDGE.backend_to_armoury[backend_id]` is truthy.
- **Armor clone `.name` handling**: Armor clones must keep `entry.name = vanilla_cosmetic_key` (not `suffix_id`) because `_load_hero_unit` does `Cosmetics[item.data.name]` lookup for skin spawning. Added `name_override` parameter to `build_clone_entry`; armor entries pass the vanilla key as override.

## [2026-04-30 v0.7.61-dev]
### Fixed
- **LA clone preview not updating when switching from vanilla hat**: `_populate_loadout` in `HeroWindowCharacterPreview` compares `item.data.name` against the previewer's stored `current_item_name` to decide whether to call `equip_item`. The game's `parse_item_master_list()` sets `item.name = key` on every IML entry at boot, but our clones were created after boot via `table.clone(original)` — inheriting the vanilla key as `.name`. Since vanilla hat and all its clones shared the same `.name`, the previewer thought nothing changed and skipped the re-equip. Fix: set `entry.name = suffix_id` in `build_clone_entry` so each clone has a unique `.name`.

## [2026-04-30 v0.7.60-dev]
### Fixed
- **Server-stored clone backend_ids persisting across sessions**: Clone backend_ids leaked to the PlayFab server in sessions before the `set_loadout_item` hook was properly installed (v0.7.58). On subsequent startups, `get_loadout_item_id` returned the server's stale clone id, which the cosmetics grid showed as "equipped" even when the user had switched to vanilla. Three-layer defense:
  1. **Startup fixup** (`_fixup_server_clones`): On mod init, reads raw server loadout (bypassing cache), finds any career/slot with a clone backend_id, and replaces it with the corresponding vanilla backend_id via `get_loadout_interface_by_slot().set_loadout_item()`.
  2. **Read-time redirect** (`get_loadout_item_id` hook): If the server returns a clone backend_id and no cache entry exists, finds and returns the vanilla backend_id instead.
  3. **Loadout-table redirect** (`get_loadout` hook): Same redirect applied to the full loadout table before cache merge.

### Changed
- **`la_hats` diagnostic enhanced**: Now shows cache state, raw server value, and gate status for each hat item, making clone-vs-vanilla debugging trivial.

## [2026-04-30 v0.7.59-dev]
### Changed
- **`la_hats` diagnostic command expanded**: Shows VANILLA vs CLONE labels, rarity, equipped status, and cache entries per career for the current hat slot.

## [2026-04-30 v0.7.58-dev (LA bridge)]
### Fixed
- **`set_loadout_item` hook never firing for hat equips**: The hook was installed on `items_iface` (the items backend interface), but `BackendUtils.set_loadout_item` dispatches via `Managers.backend:get_loadout_interface_by_slot(slot_name)` which returns a DIFFERENT interface for cosmetic slots. Moved the hook to `BackendUtils.set_loadout_item` directly (table-form hook on the BackendUtils table) so it intercepts ALL loadout writes regardless of which interface handles the slot.

### Added
- **Loadout cache system** (mirrors AllHats pattern): Clone backend_ids are cached locally in `mod.loadout_cache[career_name][slot_name]` instead of being written to the server. This prevents vanilla clients from crashing on unknown backend_ids. Cache is merged into `get_loadout` and `get_loadout_item_id` reads so the game sees the clone as equipped. Clearing the cache (by equipping a vanilla hat) restores the server-side vanilla backend_id.

## [2026-04-30 v0.7.57-dev]
### Added
- **`la_hats` diagnostic command**: Lists all hat items for the current career with VANILLA/CLONE labels, backend_id, rarity, and equipped status. Essential for debugging clone registration and loadout cache behavior.

## [2026-04-30 v0.7.62-dev]
### Changed
- **Portrait system rewritten: career_settings source-level swap** (confirmed working). Instead of per-widget per-frame content swapping (which only caught the HUD unit frame), the mod now modifies `SPProfiles[5].careers[1].portrait_image` directly at the source. Every UI surface that reads the career portrait — HUD, hero selection, ESC menu, tab overlay, end-of-round — gets the custom portrait automatically because they all read from `career_settings.portrait_image` and dynamically prefix `"medium_"` / `"small_"`.
- Removed `_maybe_swap_portrait_widget`, `_vanilla_portraits`, `_portrait_swapped` (per-widget approach).
- Added `_sync_portrait_settings()` / `_restore_portrait_settings()` which swap/restore career_settings.
- `_sync_portrait_settings()` called from: `UnitFrameUI.draw` hook (for early detection), `on_game_state_changed`, `on_setting_changed("dynamic_portraits")`.
- `_restore_portrait_settings()` called from `on_unload` to clean up.
- `test_portrait` command now triggers `_sync_portrait_settings()` and reports career_settings state.
- `portrait_diag` now shows career_settings.portrait_image and picking_image values.

### Architecture decision record
The portrait feature went through 20+ versions (v0.7.37–v0.7.62) exploring multiple approaches. Key lessons:
1. **Don't hook individual UI surfaces** — VT2 has 5+ places that render portraits, each with different widget structures and content keys. Hooking them individually is fragile and incomplete.
2. **Swap at the data source** — `career_settings.portrait_image` is the single source of truth. Changing it once propagates to every UI surface automatically.
3. **Alpha must be baked into the PNG** — no widget-level masking exists. Copy alpha channel from vanilla portraits.
4. **VMF `custom_gui_textures` format** — MUST use nested tables in `ui_renderer_injections` (`{ {"ingame_ui", "material_path"} }`). Flat strings are silently skipped.
5. **Detect materials via `Gui.material()` probe** — don't hook `UIRenderer.create` (VMF bypasses it).

## [2026-04-30 v0.7.58-dev]
### Fixed
- **`portrait_dump` strict table crash**: Brute-force scan of `ingame_ui` fields accessed `_widgets` on strict tables (e.g. `ui_renderer`) which triggered `"Reading from key '_widgets' not in interface <strict table>"`. Fix: wrap all field accesses in pcall. Same protection added to hero_view windows, end-screen views, and HUD sub-elements.

## [2026-04-30 v0.7.56-dev]
### Fixed
- **Portrait alpha masking**: Custom portrait PNGs were fully opaque rectangles (A=255 everywhere). Vanilla portraits have shaped alpha channels — small portraits (60x70) have a pentagonal/shield-shaped mask with transparent corners (A=0), medium portraits (110x130) have subtle edge alpha (A=241 at corners). Applied vanilla alpha masks to all three custom portrait sizes. HUD portrait (86x108) used a scaled version of the small mask since the vanilla HUD portrait is in the atlas (not extractable as standalone PNG).

### Added
- **`portrait_dump` diagnostic command**: Deep-walks all UI surfaces (HUD unit frames, hero_view, end-screen, brute-force ingame_ui scan, HUD sub-elements) and dumps every widget with `character_portrait` or `portrait` in its content. Reports content keys, style fields (texture refs, mask fields, sizes), and all pass definitions. Run in keep, during hero selection, and at end-of-round to map all three portrait contexts.

### Research findings (portrait system architecture)
- **Portrait naming**: Career settings define `portrait_image` (base name, e.g. `"unit_frame_portrait_kruber_mercenary"`). Prefixes added at display time: `"medium_" ..` for hero selection, `"small_" ..` for matchmaking/rewards.
- **Three portrait contexts use different content keys**:
  - HUD unit frame: `widget.content.character_portrait` (base name, 86x108)
  - Hero selection: `widget.content.portrait` = `"medium_" .. base_name` (110x130)
  - End-of-round: `widget.content.character_portrait` (base name)
- **Current `UnitFrameUI.draw` hook covers only the HUD** — hero selection and end-of-round need separate hooks.
- **Frame rendering**: Frame is a SEPARATE widget drawn on top (higher z-layer) via `UIWidgets.create_portrait_frame()`. No widget-level masking — portrait alpha must be baked into the PNG texture.
- **Portrait set via**: `UnitFrameUI.set_portrait(self, portrait_texture)` → `widget_content.character_portrait = portrait_texture` (source: `unit_frame_ui.lua:470`).

## [2026-04-30 v0.7.55-dev]
### Fixed
- **LA clone preview now updates immediately**: Converted `MenuWorldPreviewer.equip_item` from `hook_safe` to wrapping hook. When the cosmetics grid passes a clone's `backend_id`, the hook swaps `item_name` from the vanilla key to the clone's `suffix_id`, so `ItemMasterList[suffix_id]` is used (custom display name, custom rarity). This makes `_spawn_item` receive the clone key directly — the fragile `_cos_la_pending_backend` mechanism (which was wiped by rapid non-hat equip_item calls for other slots) is eliminated entirely.
- **Vanilla hats no longer show LA texture overrides**: Simplified the apply gate to unconditionally block all managed armoury_keys (previously only blocked when a clone was equipped in the loadout). LA's own `_spawn_item_unit` hook would still apply textures to vanilla hats via its queue system; now the gate blocks those calls at the `apply_new_skin_from_texture` entry point regardless of loadout state. Vanilla hat = vanilla appearance.
- **Removed `_cos_la_pending_backend` mechanism**: The pending stash/consume pattern was inherently fragile — `equip_item` fires for ALL slots (hat, skin, weapons, trinkets) in rapid succession, and any non-hat equip cleared the pending state before the hat's `_spawn_item` could consume it. With the wrapping hook swapping `item_name` directly, the pending mechanism is no longer needed.

### Changed
- **LA clone entries now have `rarity = "exotic"`**: Clone items in the cosmetics grid display an orange rarity border, distinguishing them visually from vanilla hats (which retain their original rarity border).

## [2026-04-30 v0.7.54-dev]
### Fixed
- **Forward-reference crash (3rd occurrence)**: `_check_portrait_materials_ready()` (line 296) called `_collect_all_guis()` (line 360) — Lua locals are NOT hoisted. Fix: moved `_check_portrait_materials_ready` definition below `_collect_all_guis`. This is the same class of bug as v0.7.37 and v0.7.1. See `feedback_lua_forward_reference.md` for the rule.

### Removed
- **Dead `portrait_inject` command**: Manual UIRenderer destroy+create probe no longer needed — VMF handles material injection automatically via `custom_gui_textures` in `_data.lua`.

## [2026-04-30 v0.7.52-dev]
### Changed
- **Portrait material detection rewritten**: `_maybe_swap_portrait_widget` and `test_portrait` now call `_check_portrait_materials_ready()` which probes the Gui directly via `Gui.material()`, instead of relying on `_portrait_materials_ready` flag. The flag was never set because it was gated on a `UIRenderer.create` hook that VMF bypasses internally (VMF destroys+recreates the renderer in its own hook, so our hook never fires).
- `portrait_diag` now actively probes on run instead of reporting the stale flag.

## [2026-04-30 v0.7.51-dev]
### Fixed
- **Root cause: VMF `custom_gui_textures` silent failure** — `ui_renderer_injections` was a flat list of material path strings. VMF's processing iterates entries and checks `type(entry) == "table"` — strings fail this check and are silently skipped. Fix: each entry must be a nested table `{"ui_renderer_creator", "material_path_1", ...}`. The `ui_renderer_creator` is the Lua filename (no path/extension) of the script that calls `UIRenderer.create` — `"ingame_ui"` for the HUD renderer.
- Removed manual `_injected_material_sets` manipulation and `inject_materials()` calls — VMF handles injection automatically when the data format is correct.

### Research findings (v0.7.42–v0.7.50)
Systematic investigation of GUI material injection. Dead ends confirmed: `Gui.create_material` (nil), `Gui.create` (nil), `Material.set_texture` on GUI materials, manual `_injected_material_sets` append (only affects future creates), `UIRenderer.create` hook (never fires — VMF's hook runs at boot). Root cause found by comparing against InventoryFavorites and Loremasters Armoury mods which use the correct nested-table format.

## [2026-04-30 v0.7.42-dev]
### Fixed
- **`uv00_table` nil crash** (`ui_renderer.lua:106`): The v0.7.40 UIAtlasHelper `get_atlas_settings_by_texture_name` hook returned `{ material_name = texture_name }` without UV coordinate fields (`uv00`, `uv11`, `size`). The UI renderer destructures these, crashing on nil. Root cause: a single multi-definition material file (`cosmetics_tweaker_portraits.material`) doesn't work — Stingray's `Gui.create_material` creates ONE material named after the *file*, not the individual definitions inside it. So `material_name = "portrait_kruber_mercenary_hat_1002"` can never resolve.

### Changed
- **Split portrait materials into individual files**: Replaced single `cosmetics_tweaker_portraits.material` (3 definitions) with three files: `portrait_kruber_mercenary_hat_1002.material`, `medium_portrait_kruber_mercenary_hat_1002.material`, `small_portrait_kruber_mercenary_hat_1002.material`. Each file's name matches the texture name, so Stingray creates a GUI material with the correct name.
- **Removed UIAtlasHelper hooks**: `has_atlas_settings_by_texture_name` and `get_atlas_settings_by_texture_name` hooks deleted. Standalone textures don't need atlas settings — the UI falls through to `Gui.bitmap` using the material name directly.
- **Per-file material injection**: `_inject_portrait_materials()` now injects all three material paths into `_injected_material_sets` individually.

### Technical
- Dead-end confirmed: multi-definition `.material` files in Stingray GUI — `Gui.create_material(gui, path)` registers ONE material named after the file basename, not the definition names within. For GUI textures, each texture needs its own `.material` file.

## [2026-04-30 v0.7.39-dev]
### Fixed
- **LA bridge preview not updating live**: Texture swaps now apply directly via `LA.apply_new_skin_from_texture()` instead of routing through LA's deferred queues. The old queue approach required LA's `mod.update()` to process the correct queue (preview_queue vs level_queue), but preview hat swaps came through `AttachmentUtils.link` with the wrong queue routing. Direct application makes the texture change visible in the same frame, matching how weapon scaling works.
- **LA clone loadout cache not cleared on vanilla equip**: Equipping the original vanilla hat after an LA clone left the clone's backend_id cached in `loadout_cache`. `get_loadout` then overwrote the vanilla hat with the stale clone, making it impossible to re-equip the original. Fix: clear `slot_hat` from `loadout_cache` when equipping a non-clone hat.
- **Forward-reference bugs (5 locations)**: `_la_bridge_init_done` was declared at line ~1590 but referenced in closures defined earlier (equip_item hook, _spawn_item_wrapper, _spawn_item_unit_la_hook, AttachmentUtils.link hook, World.link_unit hook). All captured `nil` instead of the variable. Switched all to `LA_BRIDGE.registered` which is always accessible on the module table.
- **Wrong world reference in preview hook**: `_spawn_item_unit_la_hook` used `self._world` but HeroPreviewer stores the world as `self.world`. Changed to `self._world or self.world`.

## [2026-04-30 v0.7.37-dev]
### Changed
- **Portrait system: VMF custom_gui_textures API** — replaced dead-end `Material.set_texture` approach (which doesn't work on GUI materials) with VMF's built-in `custom_gui_textures` system. Custom portrait textures are now declared in `_data.lua` and VMF handles UIAtlasHelper registration + material injection into UIRenderers automatically.

### Fixed
- **`custom_gui_textures` format**: Material path goes in `ui_renderer_injections`, texture names go in `textures`. Previous attempt put the material path as first entry in `textures`, which VMF silently ignored.
- **`custom_gui_textures` location**: Belongs in `_data.lua` return table (processed during mod_data init), NOT in `.mod` file's `new_mod()` argument.
- **Forward reference crash** (`_get_local_player_hat_key` nil): Hat detection functions were defined after the `portrait_diag` command that called them. Lua locals are not hoisted — moved definitions above all call sites.
- **UnitFrameUI hook crash**: `set_portrait_frame_slot_info` and `_set_widget_data` don't exist on UnitFrameUI. Replaced with `draw` hook.
- **Portrait swap safety guard**: Added `_check_textures_registered()` gate — the draw hook now verifies UIAtlasHelper has our texture before swapping widget content, preventing "Material not found in Gui" crashes when registration fails.

### Technical
- Dead-end code removed: `test_swap`, `test_swap_vanilla`, `test_probe_mat` commands (all relied on `Material.set_texture` which doesn't work on GUI materials).
- `_hat_portrait_map` now stores VMF texture names (e.g. `portrait_kruber_mercenary_hat_1002`) instead of file paths.

## [2026-04-30 v0.7.22-dev]
### Fixed
- **Hero selection / end-of-round crash** (`Material 'medium_portrait_kruber_mercenary_hat_1002' not found in Gui`): The `_setup_hero_selection_widgets` and `_setup_player_scores` portrait hooks were missing the `_portrait_material_loaded` guard that the HUD hook had. With material injection disabled (v0.7.21), these hooks still set custom portrait material names on widgets, crashing when the renderer tried to resolve them. Fix: added `_portrait_material_loaded` early-return to both hooks, matching the existing guard in `_sync_player_stats`.

## [2026-04-30 v0.7.21-dev]
### Fixed
- **VMF options menu crash / blank menu** (root cause found): The portrait material injection system (`_ensure_material_injected`) was adding `cosmetics_tweaker_portraits` to `UIRenderer._injected_material_sets` globally. When Stingray's native `UIRenderer.create` couldn't resolve this material, it poisoned the **entire** Gui material loading pass — `vmf_atlas`, `armoury_atlas`, and all other materials failed to load on every subsequently-created UIRenderer. This caused: (1) VMF options menu crash (`Material 'vmf_atlas' not found in Gui`), (2) NewsFeedUI crash (`armoury_atlas not found in Gui`), (3) the previous VMFOptionsView.update safety hook blocking the menu entirely. Fix: disabled global portrait material injection. Portrait map data retained for future per-renderer injection approach.
- **ItemMasterList crashify crash loop**: `_skin_requires_unowned_dlc` used `ItemMasterList[skin_key]` which triggers ItemMasterList's `__index` metamethod — this calls crashify for unknown keys (e.g. Loremaster's Armoury keys like `Kruber_KOTBS_armor` in `WeaponSkins.skins`). Fix: use `rawget(ItemMasterList, skin_key)`.
- **VMFOptionsView.update safety hook removed**: The hook was masking the material injection root cause by blocking the VMF menu. With the injection disabled, vmf_atlas loads normally and the hook is no longer needed.

### Technical
- Portrait material injection (`_ensure_material_injected`, `_remove_injected_material`, `UIRenderer.create` hook) disabled pending a safe per-renderer injection approach. The `_portrait_material_loaded` guard prevents the portrait override path from firing.
- Added `mod.on_unload` callback for future cleanup needs.

## [2026-04-30 v0.7.13-dev]
### Fixed
- **VMFOptionsView crash when `gui` is nil**: The `vmf_atlas` pre-check guard (`if gui and not _gui_has_material(...)`) fell through to calling the original `update` when `gui` was nil — because `nil and ...` is falsy, the guard was skipped entirely. When VMF's update then tried to draw widgets, `UIRenderer_draw_texture` hit the missing material and fataled the engine. Fix: invert the condition to `if not gui or not _gui_has_material(...)` so a nil gui also triggers the early return.

## [2026-04-29 v0.7.10-dev]
### Fixed
- **Crash on first frame: `attempt to call global '_gui_has_material' (a nil value)`**. The function had been deleted from the file but its call site in the new VMFOptionsView pre-check (added in v0.7.9) was left referencing it. Restored the helper near the top of the file alongside `_skin_requires_unowned_dlc`. Same class of bug as the earlier `_skin_requires_unowned_dlc` forward-reference — should have caught both before deploying.

## [2026-04-29 v0.7.9-dev]
### Fixed
- **Persistent UIRenderer pass-stack corruption after VMF options view crash** — root-cause fix. v0.7.7's pcall-around-update caught the inner crash but left `UIRenderer.begin_pass` without a matching `end_pass`. The dirty pass-stack state PERSISTED across frames AND across UI surfaces. When the user exited VMF options (back to game HUD), the next surface to call `begin_pass` was `positive_reinforcement_ui.update` — it hit the imbalanced state and asserted *"Must provide parent scenegraph id when building multiple depth passes"*, crashing the game even though VMF options view itself was no longer active. Solution: PRE-CHECK that `vmf_atlas` is on the active Gui before letting `VMFOptionsView.update` run at all. If it's missing, skip the entire update — `begin_pass` never gets called, renderer stays clean. Settings panel renders blank until atlas reloads, but the game stays alive.

## [2026-04-29 v0.7.7-dev]
### Fixed
- **VMFOptionsView pcall cascade crash**: v0.7.6 only swallowed `"not found in Gui"` errors and re-raised everything else. When the inner crash left `begin_pass` without `end_pass`, the *next* call in the update tick threw *"Must provide parent scenegraph id when building multiple depth passes"* — a different message that bypassed our filter, got re-raised, and crashed the game. Solution: swallow ALL errors in the VMFOptionsView scope (it's narrow enough that masking real bugs there is preferable to crashing the entire game). Throttled error logging to first 5 + every 60th occurrence to avoid log spam.

## [2026-04-29 v0.7.6-dev]
### Changed
- **Reverted broad `UIRenderer.draw_widget` pcall** — it was swallowing per-widget render errors across the entire UI, making vanilla menu items briefly disappear on hover (every animation/highlight redraw that referenced a missing material got dropped). Replaced with a targeted `VMFOptionsView.update` pcall that only protects the VMF settings panel, where the original crash occurred. Vanilla menus retain normal behavior.

## [2026-04-29 v0.7.5-dev]
### Fixed
- **VMF options menu crash** (`Material 'vmf_atlas' not found in Gui`): even on a fresh boot (no reload), opening VMF's mod settings panel could crash because `vmf_atlas` wasn't injected into the active screen Gui. Crash chain: `vmf_options_view.update → draw_widgets → UIRenderer.draw_widget → ui_passes.lua:134 → engine fatal`. Added a global `pcall` wrapper around `UIRenderer.draw_widget` to swallow per-widget render errors. Doesn't fix the underlying VMF/material-loading issue, but prevents the engine from dying. Also catches the broader class of missing-material crashes after `/reload`.

## [2026-04-29 v0.7.4-dev]
### Fixed
- **Hot-reload UI crashes (cascading)**: After `/reload`, third-party mod atlases (VMF's `vmf_atlas`, LA's `armoury_atlas` / `la_notification_icon`) were getting torn down while their widgets were still on screen. The next material lookup fataled the engine on whichever surface drew first — NewsFeedUI, VMF options view, world markers. Multiple bugs contributed:
  1. `wt.mod`'s `on_reload` cleared `loaded_packages` on all 72 mods (see weapon_tweaker changelog) — root cause; fixed in `wt` v0.10.26.
  2. `mod:hook(UIRenderer, "draw_texture", ...)` was useless: `ui_passes.lua` captures `UIRenderer.draw_texture` as a *file-local* at load time, so post-load hooks are bypassed.
  3. `pcall`-wrapping the entire `NewsFeedUI.draw` left `begin_pass`/`end_pass` unbalanced, crashing `world_marker_ui.post_update` next frame with *"Must provide parent scenegraph id when building multiple depth passes."*
- Final fix: `mod:hook_origin("NewsFeedUI", "draw", ...)` replaces the draw entirely, with a per-widget pcall inside the loop so begin/end_pass stay balanced. Stale widgets are pruned after the pass closes.

## [2026-04-29 v0.7.1-dev]
### Fixed
- **Mod failed to initialize on reload**: `_skin_requires_unowned_dlc` was defined at line 791 but used at lines 713 and 748 — Lua locals must be defined before reference. Hoisted the DLC gate function to the top of the file.

## [2026-04-29 v0.7.0-dev]
### Added
- **Unlock All Portrait Frames toggle** (modded only): Makes every portrait frame equippable in the cosmetics loadout. Hooks `PlayFabMirrorBase.get_unlocked_cosmetics` to inject all `item_type == "frame"` entries into `_unlocked_cosmetics` before fake inventory items are generated. DLC-gated frames (`required_dlc`) remain locked if the player doesn't own the DLC. Requires restart after toggling.

## [2026-04-29 v0.6.38-dev]
### Added
- **DLC ownership gate**: Skins with `required_dlc` in ItemMasterList are blocked from unlock/apply if the player doesn't own that DLC (`Managers.unlock:is_dlc_unlocked`). Prevents the mod from bypassing paid cosmetic DLC paywalls in modded realm.

### Fixed
- **Locked illusions not applying**: Three separate bugs prevented locked-but-visible illusions from being applied in modded realm:
  1. `get_weapon_skin_from_skin_key` only searches `_fake_items` (unlocked skins), not `_items`. Vanilla locked skins returned no backend ID, so `_material_items` was empty and the craft hook never received a skin to apply. Fix: generate synthetic fake backend items for any skin in modded realm.
  2. `_on_illusion_index_pressed` checked `content.locked` before enabling the Apply button. Locked skins disabled the button regardless of the unlock toggle. Fix: hook `_on_illusion_index_pressed` to force `content.locked = false` in modded realm (respecting DLC ownership).
  3. `_update_state_craft_button` baked `script_data["eac-untrusted"]` directly into `disable_button` on the craft button widget (separate from `_enable_craft_button`). Fix: hook `_update_state_craft_button` to temporarily clear eac-untrusted for `apply_weapon_skin` recipe.
- **Skin stripped after applying**: `BackendInterfaceItemPlayfab._refresh_items` wipes `item.skin` on every dirty refresh if the skin isn't in `unlocked_weapon_skins` and `bypass_skin_ownership_check` is not set. Our craft hook set the skin, then called `dirtify_interfaces()`, which triggered refresh, which wiped the skin. Fix: set `bypass_skin_ownership_check = true` on the weapon item when applying locally.

### Technical
- Illusion swap in modded realm now intercepts five points (was three):
  1. `_enable_craft_button` — clear eac-untrusted for Apply button + force-clear `is_held`/`input_pressed` on disable
  2. `get_weapon_skin_from_skin_key` — synthetic backend IDs for any skin (not just custom `ct_*` skins)
  3. `craft` + `update` — local backend mirror write with deferred result delivery
  4. `_on_illusion_index_pressed` — force `content.locked = false` for non-DLC-gated skins
  5. `_update_state_craft_button` — clear eac-untrusted for craft button disable_button flag
- `_skin_requires_unowned_dlc(skin_key)` helper checks `ItemMasterList[skin_key].required_dlc` against `Managers.unlock:is_dlc_unlocked`

## [2026-04-29 v0.6.23-dev]
### Fixed
- **Mod failed to initialize** when `_register_custom_illusions` ran: `NetworkLookup.weapon_skins[skin_key]` access threw because the table has a metatable that errors on missing keys. Switched to `rawget` so the membership check no longer trips the guard. This was masking the LA bridge entirely — every `cos la_*` command failed silently because mod_script init bailed before the commands were registered.

## [2026-04-29 v0.6.20–v0.6.22-dev]
### Added
- **LA bridge diagnostics**: `cos la_dump` (registry contents), `cos la_trace 1` (per-hook tracing of `AttachmentUtils.link` and `HeroPreviewer._spawn_item_unit`), `cos la_loadout` (find equipped LA-clone backend_ids), `cos la_force <armoury_key>` (bypass detection and apply a specific LA variant directly to the player's hat unit, for isolating queue-routing vs LA-pipeline failures).

## [2026-04-28 v0.6.19-dev]
### Added
- **Modded-realm illusion swap**: Weapon illusions can now be applied in modded realm. The Apply button is re-enabled and craft calls are intercepted locally instead of sending to PlayFab (which rejects modded-realm crafting). Changes persist for the session and reset on restart.
- **Custom illusion injection**: New weapon skins can be defined in `_custom_illusions` and appear as selectable illusions in the vanilla skin browser. First entry: "Mace & Bretonnian Shield" (`ct_es_mace_gk_shield_01`) — pairs an Empire mace with a Grail Knight Bretonnian shield.
- **Unlock All Weapon Illusions toggle** (modded only): Makes every weapon illusion selectable in the illusion browser.
- **Bretonnian Sword & Shield thickness fix**: The `es_bastard_sword_thiccc` setting now also applies to the sword portion of Bretonnian Sword and Shield (`es_sword_shield_breton`), without affecting the shield. Uses `_fields` targeting to scale only right-hand units.
- **Loremaster's Armoury bridge toggle** (`la_bridge_enable`): Adds LA hat/skin recolors as separate inventory items.
- Per-hand `_fields` support in `_weapon_scale_overrides` for independent weapon/shield scaling.
- `HeroPreviewer._spawn_item` hook for correct inventory character preview scaling (replaces `MenuWorldPreviewer._spawn_item_unit` which lacked per-hand access).
- `LootItemUnitPreviewer.spawn_units` hook for illusion browser preview scaling, with skin-key-to-weapon-key resolution via `matching_item_key`.

### Fixed
- **Craft button sound loop**: Fast local craft completion left the UI hotspot's `is_held` flag set (engine only clears it on mouse release, not on `disable_button`), causing infinite craft→complete→re-craft cycles. Fixed by force-clearing `is_held` and `input_pressed` when disabling the craft button after illusion application.
- Inventory preview no longer scales both sword and shield on Bretonnian weapons — only the right-hand unit is affected when `_fields` targets right-hand.
- Illusion browser preview now resolves skin keys (e.g. `es_bastard_sword_skin_01`) to weapon keys via `matching_item_key` before applying scale overrides.
