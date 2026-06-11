# Tweaker: GUI — Changelog

## 0.2.8-dev (2026-06-07) — HUD drag preserves each widget's vanilla baseline

### Why
Audit 2026-06-07 (F5, HIGH). `_apply_offset_to_scenegraph` wrote the RAW drag delta straight into `node.local_position[1]/[2]`, discarding each widget's non-zero vanilla baseline. The vanilla `HudCustomizer.run` (decompiled `scripts/ui/hud_ui/hud_customizer.lua:119-122`) can assign the raw offset only because the nodes IT customizes baseline at `{0,0}` — its `offset_registry` value IS that node's `local_position`. Our REGISTRY targets real HUD widget nodes whose baselines are non-zero: `equipment_ui` pivot `{0,69}`, `buff_ui` pivot_root `{150,18}`, `boss_health` pivot_parent `{0,-72}`, `challenge_tracker` pivot `{1,155}`, `loot_objective`/`news_feed` etc. So the first drag (even a tiny one) snapped those widgets to screen origin instead of moving them by the delta. `reset_widget` already wrote `entry.vanilla_position` back, confirming that field is the correct baseline reference — the drag path just wasn't using it.

### Changed
- `_hud_customizer.lua:106-134` — extracted the position math into a new exported `CustomizerModule.local_position_for(widget_id, dx, dy)` that returns `vanilla_position + delta` (reads `REGISTRY_BY_ID[widget_id].vanilla_position`, degrades to `{0,0}` baseline for unknown ids). `_apply_offset_to_scenegraph` now calls it instead of assigning the raw `dx, dy`. Baseline preserved; pure delta applied. No new hooks (the two call sites — `_reapply_all_offsets` and the per-class `init` hook body in `install_hooks` — already pass the registry entry's data through `widget_id`).
- `gui_tweaker.lua:578-611` — added `_rt_register("hud_offset_preserves_vanilla_baseline", ...)`. Registered next to the `gut_*` HUD commands (after the `Customizer` dofile) because it closes over `Customizer`.

### Tests
- `/gut_regression_test` → new `hud_offset_preserves_vanilla_baseline` check. Asserts `local_position_for("equipment_ui", 25, -40)` == `{25, 29}` (baseline `{0,69}` + delta), `local_position_for("buff_ui", 0, 0)` == `{150, 18}` (zero-drag returns exact baseline — the old raw-write returned `{0,0}` here), and unknown ids degrade to `{0,0}+delta`. Fails if the baseline term is dropped again.

### To verify
- `/gut_edit_hud`, then drag `equipment_ui` (ammo/equipment cluster), `buff_ui` (buff icons), and `boss_health` a small amount — they should track the cursor smoothly from their current on-screen spot, NOT jump to the screen origin on the first click-drag.
- `/gut_reset_hud` should still snap each widget back to its vanilla position (unchanged path).
- `/gut_regression_test` reports the new check PASS.

## 0.2.7-dev (2026-05-30) -- Loc integrity: ESC-menu button loc key

### Why
`qa/check_name_integrity.ps1` check #2 flagged `display_name = "mod_tweaker_button_name"` (gui_tweaker.lua:627) — the ESC-menu "Mod Tweaker" button entry assigned a loc key that resolved in no loc table. The vanilla ingame_view render path runs the button's `display_name` through Localize (style `localize = true`, ingame_view.lua:138-140 + :252), and `display_name_func` is a dead vanilla field never invoked — so the button rendered the raw key string instead of "Mod Tweaker".

### Changed
- `gui_tweaker_localization.lua` — added `mod_tweaker_button_name = { en = "Mod Tweaker" }` (matches the intent of the existing `display_name_func` that returned "Mod Tweaker").

### Notes
- Resolves the gui_tweaker entry in the 13 check_name_integrity errors.

## 0.2.5-dev (2026-05-25) -- Restore dev/alpha/beta load banner (PROJECT_STANDARDS § 3.6 update)

### Why
User feedback 2026-05-25 EOD: earlier today's chat-spam cleanup pulled the `mod:echo("<Name> v" .. MOD_VERSION)` startup line from every mod. That's correct for stable (>=1.0.0) builds but hides the active version for in-flight dev/alpha/beta work. PROJECT_STANDARDS § 3.6 amended: dev/alpha/beta/0.x versions MUST echo `[<mod_id>] v<version> loaded` at module load; stable versions stay silent.

### Changed
- `gui_tweaker.lua` -- added a track-detector `if` after the applied-marker line: matches `-dev$` / `-alpha$` / `-beta$` / `-rc%d*$` / `^0%.`. When any branch fires, `mod:echo("[gut] v<MOD_VERSION> loaded")` runs once.

## 0.2.4-dev (2026-05-25) -- Fix unescaped %APPDATA% in Debug Logging tooltip + add localization_format_safe runtime test

### Why
User report: "invalid string format on mouseover for Debug Logging" -- the canonical Universal Debug Logging tooltip (PROJECT_STANDARDS.md S 3.6) shipped with a literal %APPDATA%. Lua's string.format reads %A as a format directive and raises invalid option '%A' to 'format', surfacing as a red error tooltip in the VMF settings UI. All 16 active mods were affected (every mod ships the same canonical tooltip text).

### Changed
- gui_tweaker_localization.lua -- escaped literal % in enable_debug_logging_tooltip so VMF's tooltip render path sees %%APPDATA%% (renders as %APPDATA% to the player). Same wording, just escaped.
- gui_tweaker.lua -- added _rt_register("localization_format_safe", ...) runtime check. dofiles the loc table and pcall(string.format, value) on every entry; surfaces any unescaped % via /<mod_id>_regression_test. Catches the bug class even when the static check (qa/check_localization.ps1) is skipped.

### Notes
Repo-wide multi-layer defense landing across all 16 mods in this sweep:

1. Layer 1 -- 16 mods' loc strings fixed.
2. Layer 2 -- qa/check_localization.ps1 extended to parse loc.<key> = { en = "..." } assignment style (chaos_wastes_tweaker's pattern -- previously slipped detection).
3. Layer 3 -- _rt_register("localization_format_safe", ...) runtime check in every mod.
4. Layer 4 -- tools/vmb-launcher/CLAUDE.md doctrine update: "Run qa/check_localization.ps1 before declaring any localization edit complete."
5. Layer 5 -- documentation: LOCALIZATION_STANDARD.md S 1 "Recurring offender" worked example, docs/BUG_CLASSES.md S 16 new entry, PROJECT_STANDARDS.md S 3.6 canonical tooltip text now uses %%APPDATA%%.

Static check (qa/check_localization.ps1) reports 0 errors post-fix (down from 15 detected + 1 hidden in chaos_wastes_tweaker).

### Build
VMBLauncher.exe build gui_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.2.3-dev (2026-05-25) — Applied marker (universal — PROJECT_STANDARDS.md § 3.6)

### Why
Every mod now prints a single `mod:info("[gut] enabled v<X.Y.Z> settings_fp=<8-hex>")` line at load — self-documenting console_logs. Walks the data widget tree, FNV-1a-32 hashes setting=value pairs. ALWAYS fires (not gated on debug_logging).

### Changed
- `gui_tweaker.lua` — added file-local `_settings_fingerprint()` helper + `mod:info("[gut] enabled ...")` applied-marker line right after the `_dbg_alert` helper.
- `itemV2.cfg` — bumped to v0.2.3-dev.

## 0.2.2-dev (2026-05-25) — Fix dead `NewsHeadUI` hook (issue #41)

### Why
Two `[MOD][gut][ERROR] (hook_safe): trying to hook object that doesn't exist: NewsHeadUI` lines fired every session. The HUD customizer's REGISTRY (`_hud_customizer.lua` line 23) used `class_name = "NewsHeadUI"`, but vanilla VT2's news-feed widget class is named `NewsFeedUI` — the file lives at `scripts/ui/hud_ui/news_feed_ui.lua`. The two error lines came from `install_hooks` iterating REGISTRY and registering both `init` and `destroy` hooks (lines 264 and 268) against the non-existent class.

### Changed
- `_hud_customizer.lua` line 23 — renamed `class_name` `NewsHeadUI` → `NewsFeedUI`, and `definitions_file` documentation reference from `news_head_ui_definitions.lua` → `news_feed_ui_definitions.lua` (the actual vanilla path).
- `gui_tweaker.lua` — `MOD_VERSION` bumped 0.2.1-dev → 0.2.2-dev.
- `itemV2.cfg` — title bumped to v0.2.2-dev.

### Notes
- `scenegraph_node_id = "pivot"` is correct — confirmed against `news_feed_ui_definitions.lua` scenegraph_definition.
- Result: the news-feed HUD widget is now actually drag-repositionable in `/gut_edit_hud` instead of being silently absent from the live-views table.

### Closes
- #41 (gut hook_safe target `NewsHeadUI` doesn't exist — 2 silent dead hooks).

## 0.2.1-dev (2026-05-25) — Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6)

### Why
User-requested two-channel debug discipline: `_dbg` for confirmation / dump / expected behavior (log file only), `_dbg_alert` for unexpected / wrong / mismatch (log file + in-game chat). Helpers installed in every active mod. gui_tweaker previously had no `_dbg` helper at all.

### Changed
- `gui_tweaker.lua` — added file-local `_dbg(fmt, ...)` and `_dbg_alert(fmt, ...)` helpers at top. Output prefix `[gut:dbg]` / `[gut]`.
- `gui_tweaker.lua` — promoted the previous one-line `/gut_regression_test` stub to a proper `_RT_CHECKS` scaffold and registered `dbg_helpers_two_channel`.
- `itemV2.cfg` — bumped to v0.2.1-dev.

### Notes
- 0 existing `_dbg(...)` call sites (helper was newly introduced).
- 0 bare `mod:echo` reclassified — every `mod:echo` in `gui_tweaker.lua` is either inside a `/gut_*` chat command body (user-operational) or is the unconditional `hud-customizer hook install failed` operational error at line 306. Both classes are correct as bare `mod:echo` per the policy.
