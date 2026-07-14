# Regression Checklist — gui_tweaker_dev

Subset of the monorepo [REGRESSION_CHECKLIST.md](../docs/REGRESSION_CHECKLIST.md) for Tweaker: GUI dev.

Last updated: 2026-07-13.

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
