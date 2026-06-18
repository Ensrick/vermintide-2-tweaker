# Tweaker: GUI — Changelog

## 0.2.13-dev (2026-06-17) — Fix: view missing required IngameUI contract methods (input_service crash)

v0.2.12 fixed construction (the view now attaches — log confirms `[mt] setup_views: ModTweakerView attached`), but opening it then crashed `ingame_ui.lua: attempt to call method 'input_service' (a nil value)`: IngameUI calls `active_view:input_service()` **unconditionally** every frame (ingame_ui.lua:416/770) and the view didn't implement it.

### Fixed
- `_mod_tweaker_view.lua` — added the three view-contract methods IngameUI calls unconditionally on the active/new/old view: `input_service()` (returns the view's input service), and no-op `post_update_on_enter(params)` / `post_update_on_exit(params, was_replaced)` (called on every view transition — would have crashed on open/close next). The other contract methods (`current_state` / `disable_toggle_menu` / `hotkey_allowed` / `set_map_interaction_state` / `is_survey_*`) are guarded with `if view.method` in IngameUI and are safely omitted.

## 0.2.12-dev (2026-06-17) — Fix: Mod Tweaker view crashed IngameUI (nil view on open)

In-game test of v0.2.11 crashed on opening the Mod Tweaker: `ingame_ui.lua:625: attempt to index a nil value` (current_view = "mod_tweaker_view"). Root cause: `IngameUI.init` passes the context to `setup_views(ingame_ui_context)` as an **argument** (ingame_ui.lua:107) and does NOT store `self.ingame_ui_context` at that point — the scaffold hook read `self.ingame_ui_context` (nil), so `ModTweakerView:new` threw, the view never attached, and transitioning to the missing view indexed `views[current_view]` = nil → hard crash.

### Fixed
- `gui_tweaker.lua` — the `setup_views` hook now captures the **`ingame_ui_context` argument** (`function(self, ingame_ui_context)`) and builds the view from it; refuses to attach a context-less view.
- `gui_tweaker.lua` — the `mod_tweaker_view` transition closure now switches `current_view` only if `self.views.mod_tweaker_view` exists, so a missing view can never crash IngameUI (the ESC entry becomes a no-op instead).
- `_mod_tweaker_view.lua` — `init` errors clearly on a nil context (caught by the hook's pcall) instead of failing mid-body.

(Unrelated: the log also shows a pre-existing VMF/Loremasters-Armoury tooltip error in `vmf_options_view` via the deprecated `_G.UIResolutionScale_pow2` — not part of gut.)

## 0.2.11-dev (2026-06-17) — Mod Tweaker view: first renderable pass (tasks #6–8)

The Mod Tweaker (the in-game settings menu for all the Tweaker mods, opened from the ESC menu) now actually **renders** — previously the view was a stub and clicking the ESC entry opened nothing. Built from the verified VT2 `OptionsView` contract (read 2026-06-17): borrows the IngameUI renderer, registers a modal input service, draws in one `begin_pass`/`end_pass`, and returns to the ESC menu via `ingame_ui:transition_with_fade("ingame_menu")`.

### Changed
- **`_mod_tweaker_definitions.lua`** — real scenegraph (root/screen-dim/panel/title/left tab strip/right list/hint) + widget factories (panel, title, hint, tab, checkbox, slider). Deliberately atlas-free (`rect`+`text`+`hotspot` passes only) so the first on-screen pass can't fail on a missing texture; visual polish (proper checkbox/slider art) is a later pass. Per-row/per-tab hotspot styles give correct hit regions.
- **`_mod_tweaker_view.lua`** — replaced the stub with a working `ModTweakerView`: init borrows the context renderer + registers the `gut_mod_tweaker` input service; `on_enter` shows the cursor + makes the view modal + builds tabs/rows from the registered categories; `update` draws and handles input; checkbox click toggles + persists, slider drag sets value + persists (both through the controller `mod.mod_tweaker` so there's a single registry); `exit` transitions back to the ESC menu. Reads the registry via the controller (NOT a fresh `_mod_tweaker_settings` dofile, which would be empty).
- **`gui_tweaker.lua`** — registers a dogfood `gut` category (debug-logging checkbox that bridges to VMF + a demo slider) so the view shows real, interactive content end-to-end.

### To verify (in-game)
- In a mission or the keep, press ESC → click **Mod Tweaker** (above Options). A panel should open with a "Tweaker: GUI" tab on the left and two rows: a Debug-logging checkbox (click toggles ON/OFF) and a demo slider (drag to change the value). ESC closes back to the ESC menu. `/gut_regression_test` still passes the mod_tweaker entry/transition checks.

## 0.2.10-dev (2026-06-16) — `/gut_lua_mem` diagnostic (Lua-heap footprint measurement)

### Why
A friend (nicho) hit the VT2 hard crash `Not enough memory reserved for heap lua_heap` (reserved 1073741824 = 1 GiB, `heap_allocator.cpp:227`) at mission load while running ~58 mods incl. the now-public Tweaker mods — the Lua heap was pinned at 100% (1 GiB used of 1 GiB). The `lua_atpanic/lua_close` callstack is the symptom, not the cause. To attribute footprint per-mod (which can't be read off source line counts — it's a runtime quantity) we need a live measurement.

### Changed
- `gui_tweaker.lua` — new `/gut_lua_mem [label]` command: forces a full GC and prints live Lua memory (`collectgarbage("count")`) in MB. Per-mod workflow: disable suspects → launch → load a level → `/gut_lua_mem baseline`; enable one mod → relaunch → `/gut_lua_mem <mod>`; the jump is that mod's footprint. (Lower-bound proxy: the engine `lua_heap` also holds bytecode + C-side Lua structures; compare deltas, not absolutes.)

## 0.2.9-dev (2026-06-16) — Phase 0: fix Versus host-crash in vanilla damage-feedback (UI-absorption groundwork)

### Why
First step of absorbing NumericUI + UI Tweaks (HideBuffs) into gut against the current GUI. The reported Versus host-crash is a **vanilla** bug, independent of any rendering: `UnitFrameUI.add_damage_feedback` (`unit_frame_ui.lua`) assigns `self._damage_widgets[order_index]` and sets `widget.content.visible = true` (vanilla L1687-1690 / L1699-1702) for a NEW event *before* the over-MAX eviction at the bottom — and that eviction is dead-coded behind `fassert(false)` (vanilla L1724-1725). When more than `#self._damage_widgets` (4 with damage feedback on) distinct damage events are active at once, `order_index` exceeds the pool, the widget is `nil`, and `widget.content.visible = true` is a fatal index-of-nil. On the **host** it crashes the whole session. Reproduced in Versus by a Pactsworn Ratling Gunner's sustained machinegun fire stacking 5+ simultaneous damage messages on one hero frame (crash GUID `59ae9a93-…`, 2026-06-15). NumericUI re-news the vanilla `UnitFrameUI`, keeping this vanilla path live — but the bug is vanilla and the fix is independent of NumericUI.

### Changed
- `gui_tweaker.lua` — new `mod:hook("UnitFrameUI", "add_damage_feedback", …)` (the mandatory pre-flight grep confirmed gut had no prior `UnitFrameUI` hook). The wrapper drops the **overflow** event before it reaches the nil-widget index — only when the pool is already full AND a new `order_index` would be assigned (a brand-new event, or a re-activated `disabled` one). Existing active events pass through untouched. No vanilla state is mutated (pure pre-call guard; degrades safely if the vanilla shape drifts). The cap is self-healing: vanilla `_update_damage_feedback` removes expired events from `_hash_order` (`table.remove`, vanilla L1819), freeing slots. Perf-gated: the hash/lookup work only runs in the rare at-capacity case. Always-on (a safety guard, not a toggled feature). Decision rule extracted to `mod._gut_damage_feedback_should_drop` for testability.

### Tests
- New `/gut_regression_test` check `damage_feedback_overflow_guard` — pins the drop/keep decision across boundary cases (full pool + new → drop; free slot + new → keep; existing event → always pass through; empty pool → drop).

### To verify (in-game)
- Host a Versus match (host-side crash), keep Numeric UI enabled for now, play a Pactsworn Ratling Gunner and hold sustained fire on heroes — confirm **no host crash** (the 5th+ simultaneous damage message is silently dropped instead). Then `/gut_regression_test` → `PASS: damage_feedback_overflow_guard`.

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
