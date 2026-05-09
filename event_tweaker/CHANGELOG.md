# Tweaker: Events — Changelog

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
