# Tweaker: Events — Development Notes

Internal id: `event_tweaker`. Workshop id: `3721290755`. Visibility: `private` (do NOT change without explicit user direction — see `feedback_workshop_metadata_user_dictates`).

## What this mod does

Lets the host pick any combination of vanilla / DLC mutators for the lobby — including dormant live-event mutators (Geheimnisnacht ritual sites, Khorne skull pickups) — without waiting for Fatshark to push the event live. Vanilla clients work; only the host needs the mod. Mutator activation broadcasts to clients via `rpc_activate_mutator_client`.

Two flavors of selection sit on top of each other:

1. **Event Preset** dropdown (Off / Geheimnisnacht 2021 / Geheimnisnacht 2025 / Skulls 2023). Drives three things at once: the mutator list, the `active_events` string list (so `mutator_geheimnisnacht_2021`'s `server_start_function` finds its ritual-site map list), and the keep level (so the keep gets pre-baked Geheimnisnacht/Skulls decorations).
2. **Per-category checkboxes** for any individual mutator, organized into 7 groups. Stacks additively on top of whatever the preset already pulls in; deduped before injection.

## Architecture

Three hooks, all on backend classes. Single chokepoint per concern — every consumer of the hooked function sees the override consistently.

| Hook | Purpose | Why this entry point |
| :--- | :--- | :--- |
| `BackendInterfaceLiveEventsPlayfab:get_special_events` | Inject `{name, weekly_event = "append", mutators}` so `GameModeBase.append_live_event_mutators` (`game_mode_base.lua:264`) picks up our mutators on every mission load. | Single class, no derived classes — string-form `mod:hook` patches the prototype that all instances see via `__index`. `GameModeBase.append_live_event_mutators` is the canonical mutator-activation path; mutator IDs flow from there into `mutator_handler.lua:85` `initialize_mutators` and out via `rpc_activate_mutator_client` to clients. |
| `BackendInterfaceLiveEventsPlayfab:get_active_events` | Inject the preset's event-name string (e.g. `"geheimnisnacht_2021"`). | `mutator_geheimnisnacht_2021.lua:58-86` calls `live_events_interface:get_active_events()` and does `string.find(live_event, "geheimnisnacht_%d+")` on each entry to decide which 5 maps spawn ritual sites (year-specific lists in `geheimnisnacht_utils.lua:5-41`). Without this hook, the mutator activates but spawns nothing. Skulls does NOT inspect this list — its mutator's `server_start_function` is self-contained. |
| `BackendManagerPlayFab:get_level_variation_data` | Merge `hub_level = "inn_level_halloween"` / `"inn_level_skulls"` into the returned table. | `AdventureMechanism.get_starting_level` (`adventure_mechanism.lua:625`) reads `Managers.backend:get_level_variation_data().hub_level` and loads that level. Vanilla seasonal events ship pre-decorated keep level files — `inn_level_halloween`, `inn_level_skulls`, `inn_level_celebrate`, `inn_level_sonnstill` — defined in `scripts/settings/level_settings.lua:152-196`. Decorations are baked geometry, not runtime spawns. Mutators can't do this because `GameModeBase` skips hubs. |

Two file-local tables drive the selection logic. **They MUST stay in sync** — VMF's mod-script vs mod-data load order isn't documented, and no sibling tweaker mod shares state across files, so the catalog is duplicated:

- `MUTATOR_CATALOG` in `event_tweaker.lua` — read by `selected_individual_mutators()` and the `event_clear` command.
- `CATEGORIES` in `event_tweaker_data.lua` — read at widget-tree build time to generate the checkbox groups.

`EVENT_PRESETS` lives only in `event_tweaker.lua`. The presets dropdown in `event_tweaker_data.lua` references the keys directly (no shared list needed because the dropdown's `value` strings are themselves the preset keys).

## Adding a new mutator

The mutator name must be a string that's already registered in `NetworkLookup.mutator_templates`. To verify before adding: check that `scripts/settings/mutators/mutator_<name>.lua` exists in the unpacked source (Vermintide-2-Source-Code). All vanilla + DLC batch_01/02/04 + Geheimnisnacht_2021 + Skulls_2023 mutators qualify; see `mutator_settings.lua:5-38` and the various DLC `_common_settings.lua` files for the full list.

1. Add the name to the matching category's `mutators` array in **both** `event_tweaker.lua` (`MUTATOR_CATALOG`) and `event_tweaker_data.lua` (`CATEGORIES`).
2. Add `mut_<id>` and `mut_<id>_tooltip` keys to `event_tweaker_localization.lua`. Convention: tooltip leads with `[<mutator_id>]` so the literal name being injected is verifiable from the UI.
3. Bump `MOD_VERSION` in `event_tweaker.lua` per the always-bump rule.
4. Build (`vmb build event_tweaker --no-workshop --cwd`), deploy (`& .\deploy_all.ps1 -Mods @("event_tweaker")`), restart, test.

## Adding a new event preset

When a mutator inspects `active_events` internally (Geheimnisnacht does, Skulls does NOT), it needs a preset entry to work — checking the box alone won't trigger its set pieces. Same applies to events that ship a baked keep variant.

1. Add the preset to `EVENT_PRESETS` in `event_tweaker.lua`. Required fields:
   - `active_events` (table of strings) — what `get_active_events` will return
   - `mutators` (table of strings) — what `get_special_events` will return as the `mutators` field
   - `hub_level` (string, optional) — keep level variant to load. Use one of `inn_level_halloween` / `inn_level_skulls` / `inn_level_celebrate` / `inn_level_sonnstill`.
2. Add an option entry to the `event_preset` dropdown's `options` list in `event_tweaker_data.lua`.
3. Add `preset_<key>` localization key in `event_tweaker_localization.lua`.

## Sharp edges

### `get_special_events` entries MUST have a `name` field

`DialogueSystem.on_add_extension` (`dialogue_system.lua:196-212`) reads `event_data.name` and uses it as a key in `self._global_context`. Missing `name` → `self._global_context[nil] = true` → "table index is nil" crash. Hits on every level load including the hub, so the crash is at startup, NOT only on missions. **Caused the v0.2.0-dev → v0.2.1-dev fix.** See `feedback_special_events_name_required.md` in memory.

### Hub levels skip the mutator path

`GameModeBase.append_live_event_mutators` (`game_mode_base.lua:260-262`) explicitly returns early on `level_settings.hub_level` or `level_settings.tutorial_level`. Anything that needs to run on the keep — visual decorations, ambient audio, NPC swaps — has to use a different mechanism. Currently we only handle keep decoration (`hub_level` swap). Other keep-level changes (mission board reskin, NPC dialogue) would need additional hooks.

### Preset changes auto-reload the level (v0.4.0+)

All three hooked queries (`get_special_events`, `get_active_events`, `get_level_variation_data`) are consulted at level-load time only. So a preset change between loads is dormant until the next level swap. Worked around via `mod.on_setting_changed` (host only):
- In the keep, target `hub_level` differs from current → `level_transition_handler:set_next_level(new_hub_level) + promote_next_level_data()`. State-machine's update loop picks it up via `needs_level_load()` and triggers a `load_next_level` transition (`state_ingame.lua:1291`).
- In the keep, same `hub_level` (or no preset selected) → `Managers.state.game_mode:retry_level()`. Reloads current keep; `DialogueSystem` re-reads hooked `get_special_events` on the way back in.
- In a mission → `retry_level()`. Re-runs `append_live_event_mutators` against the new mutator list, rebuilds `_mutator_handler`, broadcasts via the vanilla mutator-activate RPC to all clients. Clients don't need the mod.

Individual mutator checkboxes do NOT auto-reload (5 toggles would = 5 keep reloads). Use `/event_apply` to apply checkbox changes manually.

### Vanilla mutator name strings are the literal IDs from the source files

E.g. `geheimnisnacht_2021` (NOT `mutator_geheimnisnacht_2021`). The `mutator_` prefix is the filename convention, but the registered name (the one in `NetworkLookup.mutator_templates`) is just the suffix.

## Diagnostic commands

- `/event_probe` — dump `active_events`, `special_events`, `weekly_events` from the hooked backend interface (you'll see your injected entries reflected back) plus what the mod would currently inject given the active settings.
- `/event_active` — list mutators the engine actually activated in the current level (read from `Managers.state.game_mode._mutator_handler:activated_mutators()`). Use this to confirm the host-side hook + mutator handler picked up our injection.
- `/event_clear` — uncheck every individual mutator checkbox. The Event Preset dropdown is untouched.
- `/event_apply` — reload the current level so any pending preset or mutator changes take effect. Auto-fires on `event_preset` change; for individual mutator toggles you have to invoke this command (or wait for the next natural level transition).

## Build & deploy (matches sibling tweaker mods)

```powershell
Set-Location "C:\Users\danjo\source\repos\vermintide-2-tweaker"
node C:/Users/danjo/source/repos/vmb/vmb.js build event_tweaker --no-workshop --cwd
& .\deploy_all.ps1 -Mods @("event_tweaker")
# To push to Workshop (creates a new revision visible only to subscribers):
& .\upload_event_tweaker.ps1
```

`upload_event_tweaker.ps1` mirrors `upload_wt.ps1`'s pattern — it aborts if `itemV2.cfg` has `visibility = "public"` to prevent a repeat of the prior automated-public-flip incident that got two mods removed-from-community (irreversible).

## Known limitations

- Anniversary 2025 / 2026 and Sonnstill keep variants exist in `level_settings.lua:152-196` (`inn_level_celebrate`, `inn_level_sonnstill`) but no presets yet. Trivial to add — see "Adding a new event preset".
- Drachenfels event mutators and Karak Aspect winter event aren't surfaced because they're tangled with game mode selection (Deus / Chaos Wastes mechanism), not the standard mutator pipeline.
- Modded mutators from other workshop mods would need to be registered in `NetworkLookup.mutator_templates` independently — this mod only exposes mutators that ship in vanilla / first-party DLC.
- Backend-only event consequences — portrait frames, contracts, achievements — won't come back. The mod ships *gameplay* (mutators + keep decoration), not *loot*.
