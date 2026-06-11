# Tweaker: Events — Changelog

## 0.4.13-dev (2026-05-25) -- Restore dev/alpha/beta load banner (PROJECT_STANDARDS § 3.6 update)

### Why
User feedback 2026-05-25 EOD: earlier today's chat-spam cleanup pulled the `mod:echo("<Name> v" .. MOD_VERSION)` startup line from every mod. That's correct for stable (>=1.0.0) builds but hides the active version for in-flight dev/alpha/beta work. PROJECT_STANDARDS § 3.6 amended: dev/alpha/beta/0.x versions MUST echo `[<mod_id>] v<version> loaded` at module load; stable versions stay silent.

### Changed
- `event_tweaker.lua` -- added a track-detector `if` after the applied-marker line: matches `-dev$` / `-alpha$` / `-beta$` / `-rc%d*$` / `^0%.`. When any branch fires, `mod:echo("[ewt] v<MOD_VERSION> loaded")` runs once. The short id `ewt` is used in the chat banner per the canonical short-id list in CLAUDE.md (the applied-marker line above still uses `[event_tweaker]` for log-grep continuity).

## 0.4.12-dev (2026-05-25) -- Fix applied-marker prefix typo (`[ewt]` -> `[event_tweaker]`)

### Why
The applied-marker line at `event_tweaker.lua:69` printed `[ewt] enabled v%s settings_fp=%s`. `ewt` is not this mod's id -- per the Mod Directory + the 0.4.9-dev CHANGELOG entry, the canonical prefix is `[event_tweaker]` (the directory name + VMF mod id), matching how the file's `_dbg` / `_dbg_alert` helpers use `[event_tweaker:dbg]` / `[event_tweaker]`. The typo silently broke log greps of the form `\[event_tweaker\] enabled v` that the Fix 3 audit (2026-05-25 EOD) was running across all 16 mods.

### Changed
- `event_tweaker.lua` -- applied-marker line now reads `[event_tweaker] enabled v%s settings_fp=%s`. Format unchanged (the bracketed id is the only edit) so existing log-parsing regexes still match.

### Build
VMBLauncher.exe build event_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.4.11-dev (2026-05-25) -- Add Geheimnisnacht 2026 + Khorne's Skulls 2026 presets

### Why
Source `scripts/settings/dlcs/geheimnisnacht_2026/` and `dlcs/skulls_2026/` are present in decompiled VT2 (FEATURE flags `FEATURE_geheimnisnacht_2026` + `FEATURE_skulls_2026` both TRUE in 2026-05-25 game log). The 2026 DLCs only add cosmetics + portraits -- gameplay still rides the existing `mutator_geheimnisnacht_2021` (ritual sites) and `mutator_skulls_2023` (skull pickups). Adding preset entries lets the host select the 2026 year cleanly.

### Changed
- `event_tweaker.lua` -- `EVENT_PRESETS` gained `geheimnisnacht_2026` and `skulls_2026` entries. Geheimnisnacht 2026 maps verified in `dlcs/geheimnisnacht_2025/geheimnisnacht_utils.lua:43-49` (`maps_by_year[2026] = { "farmlands", "dlc_wizards_tower", "catacombs", "bell", "ussingen" }`); `mutator_geheimnisnacht_2021.lua:103`'s `string.find(live_event, "geheimnisnacht_%d+")` matches `"geheimnisnacht_2026"` and resolves via `_cached_maps_by_event` to that map list. Skulls 2026 reuses `mutator_skulls_2023` since no `mutator_skulls_2026.lua` exists in source.
- `event_tweaker.lua` -- `DLC_BY_PRESET` gained `geheimnisnacht_2026 = "geheimnisnacht_2026"` and `skulls_2026 = "skulls_2026"`. DLC IDs verified in `dlc_settings.lua:597, :606`.
- `event_tweaker_data.lua` -- `PRESET_OPTIONS` + `DLC_BY_PRESET_UI` mirror the new entries so the dropdown surfaces 2026 picks and hides them for hosts who don't own the DLC.
- `event_tweaker_localization.lua` -- `preset_geheimnisnacht_2026` and `preset_skulls_2026` strings (Geheimnisnacht's mentions the 5-map list; Skulls' notes the cosmetic-only nature of the 2026 DLC).

### Build
VMBLauncher.exe build event_tweaker -- verification only.

## 0.4.10-dev (2026-05-25) -- Add "Suppress Fatshark's live event" toggle (preset=off no longer leaks live event through)

### Why
User report 2026-05-25: with `event_preset = "off"` and only `mut_night_mode = true` checked, ran a mission while Fatshark had Skulls 2026 + Geheimnisnacht 2026 live. Result: keep loaded as `inn_level_skulls`, Geheimnisnacht skull pickup spawned on the map, mission lighting flipped to event-mode, tab menu showed the live event + event modifiers active. User mental model: "off should disable the current event." Mod behavior: all three hooks were additive-only -- `get_special_events`, `get_active_events`, `get_level_variation_data` each returned Fatshark's `original` untouched when there was no preset or injection. So whatever Fatshark was serving still reached `append_live_event_mutators` / `mutator_geheimnisnacht_2021`'s ritual-site `string.find(live_event, "geheimnisnacht_%d+")` / `AdventureMechanism.get_starting_level`.

### Changed
- `event_tweaker.lua` -- new file-local `suppress_live_event()` helper reading the new setting. The three hooks now treat `original` as nil/empty when suppress is on:
  - `get_special_events` -- drops Fatshark's entries before merging our injection. Also short-circuits the `DialogueSystem.on_add_extension` read path (`dialogue_system.lua:196-212`) so no live-event ambient dialogue fires.
  - `get_active_events` -- drops Fatshark's strings so `mutator_geheimnisnacht_2021`'s `string.find` finds no `"geheimnisnacht_%d+"` match and the ritual-site engine stays dormant on missions.
  - `get_level_variation_data` -- when suppress is on AND no preset, force `merged.hub_level = "inn_level"` so `AdventureMechanism.get_starting_level` (`adventure_mechanism.lua:627`) returns the plain inn instead of Fatshark's seasonal hub.
- `event_tweaker.lua` -- `target_hub_level()` returns `"inn_level"` when suppress is on with no preset, so toggling suppress on while standing in `inn_level_skulls` / `inn_level_halloween` triggers a keep swap back via `set_next_level + promote_next_level_data`.
- `event_tweaker.lua` -- `on_setting_changed` now also calls `apply_now("suppress_live_event changed")` when the toggle flips. Matches preset-change behavior.
- `event_tweaker.lua` -- `/event_probe` now prints the suppress state next to the preset.
- `event_tweaker.lua` -- `[event-inject]` log line now includes `suppress=true|false` so leak-through is verifiable from console_logs.
- `event_tweaker.lua` -- added `_rt_register("suppress_live_event_default_off", ...)` to confirm the default value never accidentally ships as `true`.
- `event_tweaker_data.lua` -- new top-level checkbox `suppress_live_event` directly under the `event_preset` dropdown. `default_value = false`.
- `event_tweaker_localization.lua` -- `suppress_live_event` + `suppress_live_event_tooltip` strings.

### Notes
- **Default off by design.** Existing users see no behavior change. The data file's `default_value = false` is the source of truth; the regression check confirms it.
- **Skulls 2026 / Geheimnisnacht 2026 do not need new mutator catalog entries.** Decompiled source `scripts/settings/dlcs/skulls_2026/` and `dlcs/geheimnisnacht_2026/` ship only `item_master_list_*` + `weapon_skins_*` + portrait frames. The canonical mutators are still `mutator_skulls_2023` and `mutator_geheimnisnacht_2021`, both already in `MUTATOR_CATALOG`. The new `skulls_2026` / `geheimnisnacht_2026` *preset* entries (active_events string + hub_level) are still TODO -- they'd be additive to the dropdown.
- **Why not piggyback on `event_preset = "off"`?** Considered but rejected -- it would silently change behavior for anyone who has preset=off today and *wants* Fatshark's live event to pass through. New opt-in toggle = no breakage.

### Build
VMBLauncher.exe build event_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.4.9-dev (2026-05-25) -- Remove startup banner echo + tidy on_setting_changed (chat-echo policy: PROJECT_STANDARDS § 3.6)

### Why
User feedback 2026-05-25: `"on enabling debug logging, I'm getting needless echos to the chat that it's enabled"` and `"on startup before enabling debug logging, I'm getting things echo'd to the chat for CWV"`. Audit found 13 mods with redundant `mod:echo("<Name> v" .. MOD_VERSION)` lines at module load and one mod with `mod:echo("Setting changed: " .. setting_id)` in on_setting_changed (career_tweaker -- the source of the Debug Logging chat echo).

Policy decision codified in PROJECT_STANDARDS.md § 3.6 "Chat-echo policy":
- **NEVER** at module load -- the applied marker `[event_tweaker] enabled v<X> settings_fp=<hash>` line is the canonical version surface, lives in the log, never spams chat.
- **NEVER** in on_setting_changed for routine settings -- use `_dbg` (gated on enable_debug_logging) if a diagnostic trace is needed.
- **OK** in on_setting_changed only for explicit high-impact toggles (bt master toggle, gt AI toggle).
- **OK** in user-typed chat command bodies (`/<feature>_regression_test`, `/verify_*`, etc.).

### Changed
- event_tweaker.lua -- removed the load-time `mod:echo("event_tweaker v" .. MOD_VERSION)` banner. The applied marker line (`mod:info("[event_tweaker] enabled v%s settings_fp=%s", ...)`) further down already surfaces the version + settings hash in the log. `mod:info("event_tweaker v%s loaded", MOD_VERSION)` retained for log-side visibility.
- itemV2.cfg -- updated the description's "Mention the mod version" bug-report instruction. Previous text told users to find the version "at the top of the in-game chat when you load into the keep" -- now points them at the console log (search for the `enabled v` line) or `/<mod>_regression_test`.

### Build
VMBLauncher.exe build event_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.4.8-dev (2026-05-25) -- Fix unescaped %APPDATA% in Debug Logging tooltip + add localization_format_safe runtime test

### Why
User report: "invalid string format on mouseover for Debug Logging" -- the canonical Universal Debug Logging tooltip (PROJECT_STANDARDS.md S 3.6) shipped with a literal %APPDATA%. Lua's string.format reads %A as a format directive and raises invalid option '%A' to 'format', surfacing as a red error tooltip in the VMF settings UI. All 16 active mods were affected (every mod ships the same canonical tooltip text).

### Changed
- event_tweaker_localization.lua -- escaped literal % in enable_debug_logging_tooltip so VMF's tooltip render path sees %%APPDATA%% (renders as %APPDATA% to the player). Same wording, just escaped.
- event_tweaker.lua -- added _rt_register("localization_format_safe", ...) runtime check. dofiles the loc table and pcall(string.format, value) on every entry; surfaces any unescaped % via /<mod_id>_regression_test. Catches the bug class even when the static check (qa/check_localization.ps1) is skipped.

### Notes
Repo-wide multi-layer defense landing across all 16 mods in this sweep:

1. Layer 1 -- 16 mods' loc strings fixed.
2. Layer 2 -- qa/check_localization.ps1 extended to parse loc.<key> = { en = "..." } assignment style (chaos_wastes_tweaker's pattern -- previously slipped detection).
3. Layer 3 -- _rt_register("localization_format_safe", ...) runtime check in every mod.
4. Layer 4 -- tools/vmb-launcher/CLAUDE.md doctrine update: "Run qa/check_localization.ps1 before declaring any localization edit complete."
5. Layer 5 -- documentation: LOCALIZATION_STANDARD.md S 1 "Recurring offender" worked example, docs/BUG_CLASSES.md S 16 new entry, PROJECT_STANDARDS.md S 3.6 canonical tooltip text now uses %%APPDATA%%.

Static check (qa/check_localization.ps1) reports 0 errors post-fix (down from 15 detected + 1 hidden in chaos_wastes_tweaker).

### Build
VMBLauncher.exe build event_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.4.7-dev (2026-05-25) — Applied marker (universal — PROJECT_STANDARDS.md § 3.6)

### Why
Every mod now prints a single `mod:info("[ewt] enabled v<X.Y.Z> settings_fp=<8-hex>")` line at load — self-documenting console_logs. Walks the data widget tree, FNV-1a-32 hashes setting=value pairs. ALWAYS fires (not gated on debug_logging).

### Changed
- `event_tweaker.lua` — added file-local `_settings_fingerprint()` helper + `mod:info("[ewt] enabled ...")` applied-marker line right after the `_dbg_alert` helper.
- `itemV2.cfg` — bumped to v0.4.7-dev.

### Notes
- Marker prefix `[ewt]` matches the user's mod-list short-ID convention; the legacy `_dbg` prefix `[event_tweaker:dbg]` stays unchanged this pass (existing call sites; renaming is out of scope).

## 0.4.6-dev (2026-05-25) — Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6)

### Why
User-requested two-channel debug discipline: `_dbg` for confirmation / dump / expected behavior (log file only), `_dbg_alert` for unexpected / wrong / mismatch (log file + in-game chat). Helpers installed in every active mod.

### Changed
- `event_tweaker.lua` — installed `_dbg_alert` helper alongside existing `_dbg`. Added new `_RT_CHECKS` regression scaffold (`/event_tweaker_regression_test`) with `dbg_helpers_two_channel` check (event_tweaker had no regression command before).
- `itemV2.cfg` — bumped to v0.4.6-dev.

### Notes
- 0 existing `_dbg(...)` call sites in this mod (helper was previously unused).
- 0 bare `mod:echo` reclassified.

## 0.4.5-dev (2026-05-25) — Tighten localization strings to vanilla style (3 entries rewritten)

### Why

The Event Preset tooltip and the Geheimnisnacht raw-mutator tooltips were the only verbose strings in this mod — the rest were already terse `[mut_name] one-line description` form. This pass aligns et with the vanilla voice per the new `LOCALIZATION_STANDARD.md` § 11 rules.

### Changed

- `event_preset_tooltip`: dropped the "(1) the mutator list, (2) the active_events string..." enumeration paragraph; kept the keep-level rename (inn_level_halloween / inn_level_skulls), the host-only gate, and the "Off = hand-pick" hint.
- `mut_geheimnisnacht_2021_tooltip`, `mut_geheimnisnacht_2021_hard_mode_tooltip`: trimmed; kept the canonical-5-maps cross-reference and the side-objective auto-enable behavior.

### Not touched

- Every other `mut_*_tooltip` — already at vanilla style.
- The category headers — already ≤4 words.

### Build

VMBLauncher.exe build event_tweaker — verification only.

## 0.4.4-dev (2026-05-25) — Standardize Debug Logging toggle (universal convention)

### Why
Repo-wide convention: every mod now exposes a single `enable_debug_logging` checkbox at the bottom of its VMF widget tree (PROJECT_STANDARDS.md § 3.6). event_tweaker previously had no debug toggle at all — added.

### Changed
- `event_tweaker_data.lua` — appended `enable_debug_logging` checkbox (default `false`) at the bottom of the widgets list, top-level (NOT inside any group).
- `event_tweaker_localization.lua` — added `enable_debug_logging` + `enable_debug_logging_tooltip` strings.
- `event_tweaker.lua` — added file-local `_dbg(fmt, ...)` helper at top. Output prefix `[event_tweaker:dbg]`.
- `itemV2.cfg` — title + description bumped to v0.4.3-dev.

### Notes
- No existing debug key to rename.

## 0.4.2-dev (2026-05-23) — Diagnostic logging on injection hook

### Why
Surface the per-call injection state of `get_special_events` so unexpected
mutator interactions (e.g. "Horn of Magnus had no pickups — was a special_event
inject accidentally appending an incompatible mutator?") are diagnosable from
the console log without re-running with extra instrumentation.

### Changed
- `event_tweaker.lua:264-270` — added `mod:info("[event-inject] preset=%s injecting %d mutator(s): [%s]", ...)` inside the `BackendInterfaceLiveEventsPlayfab.get_special_events` hook. Fires once per call (mission load + keep transitions), prints the resolved preset name and the comma-joined mutator list. Level chosen per PROJECT_STANDARDS §3.2 — this is a normal-flow event, not a guard.

### Notes
- No behavior change; observation only.

## 0.4.1-dev (2026-05-18) — DLC paywall gate (soft-bypass fix)

- Fixed: the canonical-event preset dropdown and the per-mutator checkbox grid exposed DLC-gated content with no ownership check. Picking Geheimnisnacht / Skulls without owning the corresponding DLC caused the three injection hooks (`BackendInterfaceLiveEventsPlayfab.get_special_events`, `get_active_events`, `BackendManagerPlayFab.get_level_variation_data`) to push the DLC mutator + active_events string + decorated keep level into the lobby anyway. The vanilla level-load path then refused to load the map, surfacing a confusing failure instead of clean "not owned" behavior. Soft bypass — no actual DLC content played, but the mod offered broken choices and the lobby state was wrong.
- Fix (load-bearing — at the injection hooks in `event_tweaker.lua`): new `DLC_BY_MUTATOR` / `DLC_BY_PRESET` maps citing the canonical DLC IDs from `scripts/settings/dlc_settings.lua` — `geheimnisnacht_2021` (line 274), `geheimnisnacht_2025` (line 576), `skulls_2023` (line 287). `active_preset()` now returns nil for un-owned preset DLCs (treating them as "off"), and `selected_individual_mutators()` filters DLC-gated mutators the host doesn't own. `gather_mutators()` re-checks preset.mutators as defense-in-depth in case a future preset bundles a mutator from a different DLC. All gates use `Managers.unlock:is_dlc_unlocked(dlc_id)` with a `dlc_exists` pre-check to avoid the fassert in `unlock_manager.lua:527`. Fails closed if `Managers.unlock` isn't constructed yet — the hooks rerun on every level load so the gate evaluates normally once it's up. Modded mods can unlock vanilla progression but never paid DLC paywalls.
- Fix (UI polish — in `event_tweaker_data.lua`): preset dropdown options and per-mutator checkboxes for un-owned DLCs are now skipped at widget-build time. Fails open if `Managers.unlock` isn't ready (mod-data evaluates very early in VMF init); the hook-side gate is still load-bearing.
- DLC mapping: `geheimnisnacht_2021` mutator + `geheimnisnacht_2021_hard_mode` mutator → `geheimnisnacht_2021` DLC. `skulls_2023` mutator → `skulls_2023` DLC. 2025 preset is gated on the `geheimnisnacht_2025` DLC (its own ritual-site engine keys off the `geheimnisnacht_2025` active_events string).

## 0.4.0-dev (2026-05-16) — Mid-game preset apply + dropdown localization fix

- Fixed: dropdown options (`Off`, `Geheimnisnacht 2021/2025`, `Khorne's Skulls 2023`) and all widget tooltips now localize correctly. `event_tweaker_data.lua` was calling `mod:localize(...)` at file-load time, but VMF's `new_mod` evaluates `mod_data` before `mod_localization`, so every call returned the raw key string ("preset_off", "event_preset_tooltip", "mut_no_ammo_tooltip", etc.) — VMF rendered those literals in the UI. Switched to passing localization keys as plain strings and letting VMF resolve them at render time, matching the working pattern in `enemy_tweaker_data.lua`.
- Added: `mod.on_setting_changed` auto-reloads the level when `event_preset` changes mid-game (host only). Three cases:
  - In the keep, preset's `hub_level` differs from current keep level → `level_transition_handler:set_next_level(new_hub_level) + promote_next_level_data()`. State-machine's update loop detects `needs_level_load()` and triggers a `load_next_level` transition (`state_ingame.lua:1291`), swapping `inn_level` ↔ `inn_level_halloween` ↔ `inn_level_skulls`.
  - In the keep, same `hub_level` (or no preset) → `Managers.state.game_mode:retry_level()`. Reloads the current keep; on the way back in, `DialogueSystem` re-reads the hooked `get_special_events`.
  - In a mission → `retry_level()`. Re-runs `GameModeBase.append_live_event_mutators` against the new mutator list, rebuilding `_mutator_handler` and broadcasting via the vanilla mutator-activate RPC to all clients.
- Added: `event_apply` console command — manual trigger for the same reload flow. Use after toggling individual mutator checkboxes (those don't auto-reload — a quick pass through 5 checkboxes would otherwise trigger 5 keep reloads).
- Auto-reload is preset-change-only by design. Individual mutator toggles are dormant until `event_apply` or the next natural level transition.

## 0.3.0-dev (2026-05-07) — Keep decoration via `hub_level` swap

- Added: third hook on `BackendManagerPlayFab.get_level_variation_data`. When a preset is active, merges `hub_level = "inn_level_halloween"` (Geheimnisnacht 2021/2025) or `"inn_level_skulls"` (Skulls 2023) into the returned table. `AdventureMechanism.get_starting_level` (`adventure_mechanism.lua:625`) reads this and loads the pre-decorated keep level instead of the default `inn_level`.
- Why mutators alone can't decorate the keep: `GameModeBase.append_live_event_mutators` skips hub levels (`game_mode_base.lua:260-262`), so the mutator's `server_start_function` never runs there. Vanilla VT2 sidesteps this by shipping entire pre-decorated keep level files — `inn_level_halloween`, `inn_level_skulls`, `inn_level_celebrate`, `inn_level_sonnstill` — defined in `scripts/settings/level_settings.lua:152-196`. Decorations are baked geometry, not runtime spawns.
- Updated: `event_preset` tooltip describes all three things the preset drives (mutators, active_events string, keep level) plus the keep-restart caveat.
- Caveat: changing the preset while standing in the keep does NOT re-trigger keep load. Restart the game OR start a mission and return to swap variants.

## 0.2.1-dev (2026-05-07) — Fix DialogueSystem startup crash

- Fixed: game crashed at every level load (including the keep) with `dialogue_system.lua:180: table index is nil`. Root cause: `DialogueSystem.on_add_extension` (`dialogue_system.lua:196-212`) iterates `BackendInterfaceLiveEventsPlayfab:get_special_events()` and reads `event_data.name` on every entry, then uses it as a key in `self._global_context`. Our injected entry had only `weekly_event` and `mutators` — no `name`. `self._global_context[nil] = true` blew up.
- Fix: every injected special-event entry now includes `name = <preset_pick or "event_tweaker_custom">`. The preset key (e.g. `"geheimnisnacht_2021"`) is used when a preset is active; otherwise a synthetic identifier so per-mutator selections without a preset still pass.
- Why this hit at startup, not on missions: `GameModeBase.append_live_event_mutators` skips hub levels, but `DialogueSystem` does not — it reads `special_events` on every level load including the keep.

## 0.2.0-dev (2026-05-06) — Rename, scope-expand to full mutator catalog

- Renamed: `seasonal_tweaker` → `event_tweaker`. Workshop title changed from "Seasonal Tweaker" to "Tweaker: Events" to match the sibling mod naming convention. Internal mod ID, folder, .mod file, .package file, lua filenames, and resource_packages directory all renamed.
- Scope: was 3 event presets only. Now ships a checkbox-per-mutator catalog across 7 categories — Difficulty Modifiers (9), Special / Elite Spawns (12), Hordes & Waves (6), Atmosphere & Hazards (6), Objective Modifiers (3), Winds of Magic (8), Live-Event Mutators raw (3). Plus the existing Event Preset dropdown for canonical events that need the active_events-string magic. Total ~50 mutators selectable, all confirmed registered year-round in `NetworkLookup.mutator_templates` via `DLCUtils.append("mutators", ...)`.
- `gather_mutators()` accumulates preset.mutators ∪ checkbox-selected mutators (deduped) and injects them into a single `{name, weekly_event = "append", mutators}` entry returned from the hooked `get_special_events`.
- Added commands: `event_probe` (dump live-event state from hooked backend interface + show what would be injected), `event_active` (list mutators the engine actually activated), `event_clear` (uncheck every individual mutator without touching the preset).
- Localization: every mutator gets `mut_<id>` and `mut_<id>_tooltip`. Tooltips lead with `[<id>]` so the literal mutator name being injected is verifiable from the UI.
- Catalog list duplicated between `event_tweaker.lua` and `event_tweaker_data.lua` — VMF's mod-script vs mod-data load order isn't documented, and no sibling tweaker mod shares state across files. Both files carry comments flagging the sync requirement when mutators are added.

## 0.1.0-dev (2026-05-06) — Scaffolded

- Scaffolded via VMB as `seasonal_tweaker` (renamed same day in 0.2.0). Initial scope: three event presets (Geheimnisnacht 2021, Geheimnisnacht 2025, Khorne's Skulls 2023) with two hooks on `BackendInterfaceLiveEventsPlayfab` — `get_special_events` and `get_active_events`.
- Hook target chosen because `BackendInterfaceLiveEventsPlayfab` has no derived classes (string-form `mod:hook` patches the prototype that all instances see through `__index`), and it's the single chokepoint that `GameModeBase.append_live_event_mutators` reads through. Activates the chosen event's mutators via the vanilla mutator handler — `rpc_activate_mutator_client` then broadcasts to all clients, so vanilla clients work without any modded sync.
