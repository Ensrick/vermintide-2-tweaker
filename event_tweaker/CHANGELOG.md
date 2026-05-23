# Tweaker: Events — Changelog

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
