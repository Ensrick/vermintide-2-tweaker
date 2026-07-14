# Regression Checklist — gui_tweaker_dev

Subset of the monorepo [REGRESSION_CHECKLIST.md](../docs/REGRESSION_CHECKLIST.md) for Tweaker: GUI dev.

Last updated: 2026-07-13.

## CKC native Options checkbox (#528 follow-up)

- [ ] With CKC installed and togglable, Options > Gameplay renders Crosshair Kill Confirmation as one native checkbox, never an On/Off dropdown.
- [ ] Checking/unchecking the box live-enables/disables CKC and does not re-enable vanilla kill confirmation.
- [ ] The cog remains visible beside the checkbox, clears the scrollbar, and focuses Mod Tweaker > Interface > HUD > Crosshair Kill Confirmation.
- [ ] With CKC absent or non-togglable, the untouched stock multi-option dropdown renders.
- [ ] `/gut_regression_test` passes `ckc_bridge_uses_native_checkbox`.

## HUD edit drag geometry (#547)

- [ ] Enter HUD edit mode and inspect all ten registered HUD elements at the current resolution.
- [ ] Each overlay rectangle sits on its visible element and hover starts only inside that rectangle.
- [ ] Drag pivot-based equipment, buffs, boss health, duties, books, and news-feed elements; the rectangle follows the moved element without an offset.
- [ ] Edge confinement still uses the visible rectangle, and offsets survive closing/reopening the HUD.
- [ ] `/gut_regression_test` passes `hud_drag_geometry_uses_render_bounds`.

## Mod Tweaker settings-tree ordering (#557)

- [ ] Open tabs with mixed top-level groups and loose settings; groups appear first and each partition is alphabetical by localized label.
- [ ] Expand groups with mixed nested children; the same rule applies at each sibling level and no descendant moves outside its parent.
- [ ] Confirm authored header sections retain their sequence.
- [ ] Confirm Equipment remains Cosmetics, Crafting, Weapons, then nested CWV rather than being alphabetized.
- [ ] Exercise both keep and in-mission Mod Tweaker presentations.
- [ ] `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` passes the ordering suite.

## Well of Dreams cutscene trace (#257)

- [ ] Enable GUT Skip Cutscenes and Auto-skip; disable any standalone cutscene-skip mod.
- [ ] Run The Well of Dreams (`dlc_termite_3`) once and record whether any fade remains visible.
- [ ] Attach all `[gut:257]` lines. Confirm they include activation/skip event names, fade durations, callback order, and a fade disposition.
- [ ] Confirm no `[gut:257]` lines appear on another mission.
- [ ] Confirm the trace stops after at most 32 callback records and one `phase=cap` marker for one CutsceneSystem instance.
- [ ] `/gut_regression_test` passes `issue257_well_of_dreams_cutscene_probe`.

## Simple UI compatibility (#314)

- [ ] With Simple UI and UI Tweaks enabled, drag fitted windows through every screen edge; each remains wholly visible.
- [ ] Resize a window larger than the viewport; its left edge and top title/drag handle remain reachable.
- [ ] Change resolution/UI scale; existing windows recover into the new bounds without replacing their position tables.
- [ ] Without Simple UI installed/enabled, GUT behavior and logs are unchanged.
- [ ] `/gut_regression_test` passes `issue314_simple_ui_window_confinement`.

## Native options

### issue292-video-profiles-native-apply — saved graphics presets bypass engine apply

| Field | Value |
|-------|-------|
| Symptom | Rebuilding a screenshot/performance configuration requires manually changing every Video option. |
| Root cause | The native menu has one pending-settings transaction but no reusable local snapshots. Direct `Application.set_user_setting` writes would bypass its reload/restart and timed-revert lifecycle. |
| Fix version(s) | gui_tweaker_dev v0.2.244-dev (#292) |
| Category | UNIT / UI INTEGRATION / PERSISTENCE |
| Repro | Save two visibly different Video profiles, switch slots, Apply, keep/revert, reopen, restart, rename, and delete. Include a resolution unavailable to a second display or a capability-specific option when possible. |
| Expected post-fix | Selection replays native widget callbacks into `changed_user_settings` / `changed_render_settings`; native Apply activates the profile. Unsupported values skip safely. Five flat VMF-persisted slots survive restart. |
| Detection | Offline `test_gut_video_profiles.lua`; `/gut_regression_test`: `issue292_native_video_profile_pipeline`; bounded `[gut:292]` save/stage/delete lines. |

---

## Mod Tweaker

### issue525-progression-tab-label — readable name leaks into compact chrome

| Field | Value |
|-------|-------|
| Symptom | Modded Progression's generated top tab uses or truncates `Modded Progression` instead of reading `Progression`. |
| Root cause | Both Mod Tweaker presentations derived compact tab chrome directly from each VMF mod's readable name; their exact-label tables were duplicated and had already drifted. |
| Fix version(s) | gui_tweaker_dev v0.2.248-dev (not deployed) |
| Category | UNIT / UI INTEGRATION |
| Repro | Enable Modded Progression, then open Mod Tweaker in the keep and in a mission. |
| Expected post-fix | The existing Modded Progression category renders as the exact `PROGRESSION` top-tab label in both presentations. Its settings and VMF identity are unchanged. |
| Detection | Offline `test_mod_tweaker_tab_labels.lua`; `/gut_regression_test`: `issue525_progression_tab_label`; solo visual confirmation required after deployment. |

### issue318-disabled-integrations-in-place — disabled mod escapes or disappears

| Field | Value |
|-------|-------|
| Symptom | VMF-disabled CWV appears as a blacked-out top-level tab or disappears instead of remaining in its normal Equipment > Weapons section. |
| Root cause | Category enumeration first hid disabled mods, while the earlier merge counted only enabled members; neither preserved installed layout identity separately from edit authority. |
| Fix version(s) | gui_tweaker_dev v0.2.244-dev (not deployed) |
| Category | UNIT / UI INTEGRATION |
| Repro | Install WT and CWV, disable CWV in VMF, then open Mod Tweaker in Keep and mission. Repeat with stock UI Tweaks disabled. |
| Expected post-fix | CWV and UI Tweaks retain their normal grey section header with `Disabled in VMF` on hover. Disabled sections do not expand, expose rows, stage values, participate in profiles/DEFAULT, or receive Apply writes. Re-enabling restores the same section in place. |
| Detection | Offline `test_mod_tweaker_disabled_sections.lua`; `/gut_regression_test`: `issue318_disabled_integrations_keep_normal_sections`; solo visual/hover confirmation required after deployment. |

### issue572-search-magnifier-focus-geometry — icon crowds text or remains while typing

| Field | Value |
|-------|-------|
| Symptom | The native magnifier appears too large for Mod Tweaker's 30px field and remains visible after the user clicks into the field to type. |
| Root cause | Vanilla's padded 128px atlas tile geometry was copied from a taller inventory control without a Mod Tweaker focus-visibility contract. |
| Fix version(s) | gui_tweaker_dev v0.2.243-dev (#572) |
| Category | UNIT / UI INTEGRATION |
| Repro | Open Mod Tweaker in Keep and mission, inspect the empty field, click anywhere in it, type, then leave focus; repeat at a non-default UI scale. |
| Expected post-fix | An approximately 28px glyph sits wholly inside the unfocused 30px field, disappears while focused, and returns after focus leaves. Text begins at x=47 and the full-field hotspot and search transactions do not change. |
| Detection | Offline `test_mod_tweaker_search.lua`; `/gut_regression_test`: `issue572_mod_tweaker_native_search_icon`; in-game visual/focus confirmation while issue #572 carries `verify-fix`. |

### issue575-numeric-caret-native-metrics — caret follows proportional glyph boundaries

| Field | Value |
|-------|-------|
| Symptom | Clicking a slider's numeric value places the caret roughly one character left, with error varying by glyph and UI scale. |
| Root cause | Mod Tweaker measured an unscaled material proxy, omitted `font_type`, and centered width without subtracting the renderer's glyph origin. |
| Fix version(s) | gui_tweaker_dev v0.2.240-dev (#575; user verified 2026-07-13) |
| Category | UNIT / UI INTEGRATION |
| Repro | Edit one/multi-digit, negative, and decimal slider values; click every boundary and use Left/Right/Home/End plus insert/delete at multiple UI scales. |
| Expected post-fix | The caret uses `UIFontByResolution` and `UIRenderer.text_size` full/prefix metrics, remains at the intended insertion boundary, and commit/cancel/highlight behavior is unchanged. |
| Detection | `/gut_regression_test`: `mod_tweaker_numeric_caret_geometry`; offline `test_mod_tweaker_numeric_editor.lua`; tier-a manifest locks native metric resolution and both `_mod_tweaker_view` / `_mod_tweaker_state` click call sites. |
