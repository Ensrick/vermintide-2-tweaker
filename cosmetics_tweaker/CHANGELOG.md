# Cosmetics Tweaker — Changelog

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
