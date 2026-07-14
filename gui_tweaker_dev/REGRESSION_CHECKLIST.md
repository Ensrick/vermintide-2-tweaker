# Regression Checklist — gui_tweaker_dev

Subset of the monorepo [REGRESSION_CHECKLIST.md](../docs/REGRESSION_CHECKLIST.md) for Tweaker: GUI dev.

Last updated: 2026-07-13.

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
