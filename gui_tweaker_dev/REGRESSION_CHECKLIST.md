# Regression Checklist — gui_tweaker_dev

Subset of the monorepo [REGRESSION_CHECKLIST.md](../docs/REGRESSION_CHECKLIST.md) for Tweaker: GUI dev.

Last updated: 2026-07-13.

## Mod Tweaker

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
