# Tweaker: Events — Development Notes

Internal id: `event_tweaker`. Workshop id: `3721290755`. Visibility: `private` (do NOT change without explicit user direction — see `feedback_workshop_metadata_user_dictates`).

## What this mod does

Lets the host pick any combination of vanilla / DLC mutators for the lobby — including dormant live-event mutators (Geheimnisnacht ritual sites, Khorne skull pickups) — without waiting for Fatshark to push the event live. Vanilla clients work; only the host needs the mod. Mutator activation broadcasts to clients via `rpc_activate_mutator_client`.

Two flavors of selection sit on top of each other:

1. **Event Preset** dropdown (Off / Geheimnisnacht 2021 / 2025 / 2026 / Skulls 2023 / 2026). Drives three things at once: the mutator list, the `active_events` string list (so `mutator_geheimnisnacht_2021`'s `server_start_function` finds its ritual-site map list), and the keep level (so the keep gets pre-baked Geheimnisnacht/Skulls decorations).
2. **Per-category checkboxes** for any individual mutator, organized into 7 groups. Stacks additively on top of whatever the preset already pulls in; deduped before injection.

Plus one orthogonal switch:

3. **`suppress_live_event`** (v0.4.10-dev+, default off). When on, the three hooks below drop Fatshark's `original` response *before* merging our own. Lets the host neutralize whatever event Fatshark is currently serving (Skulls 2026 keep + Geheimnisnacht 2026 ritual sites + event lighting + tab-menu modifier list, etc.) without waiting for the live event to roll over. The preset and per-mutator checkboxes still stack on top.

## "Other Mutators" — dynamic discovery (ported from Deed Mutators Selector)

`v0.4.14-dev` absorbed the one worthwhile feature of **Deed Mutators Selector** (Workshop `3579882542`): iterate the live `MutatorTemplates` global and surface every mutator the engine flags player-facing (`display_name`+`description`), instead of a hand-curated list. The "Other Mutators" group auto-includes the package-free Chaos Wastes / Deus mutators not in a curated category. Three exclusions keep it adventure-safe (`_is_adventure_safe_mutator(name, tmpl)`): `hide_from_player_ui` (Fatshark-hidden Deus pacing knobs), a non-empty `packages` field (those go to Cursed Adventure), and `_CURSE_BROKEN_IN_ADVENTURE` (weave/deus-only crashers). Labels are pulled from the game's own `Localize` (no fabrication), registered dynamically in the loc file. Wired across all three files; `mod._ET_CURSE_BROKEN` is the shared blacklist.

## Cursed Adventure — CW/Be'lakor curses on standard maps (`v0.4.14-dev`)

Lets the host run package-bearing Chaos Wastes / Be'lakor **curses** (`MANAGED_CURSES`) on a plain adventure mission, with themed lighting. Normally those crash in adventure (`[memory: reference_vt2_mutator_packages_deus_only]`) because their unit/decal resource package is loaded only by `DeusRunState.set_event_mutators` (`deus_run_state.lua:438-453`). A 4-agent adversarial source audit (2026-06-19) established that the curse *mechanics* use only standard mission managers, and `entity_system.lua:176`+`:424-435` register every DLC entity system into every mission at boot — so the package is the only blocker.

| Piece | How |
| :--- | :--- |
| **Injection** | `selected_curse_mutators()` feeds `gather_mutators()` → the existing `get_special_events` hook → the lobby mutator handler → `rpc_activate_mutator_client` to clients. Same path as every other mutator. |
| **Package preload (normal join + host)** | Hook `MutatorHandler._activate_mutator` — the chokepoint hit on the HOST (via `activate_mutators`) AND every CLIENT (via `rpc_activate_mutator_client` → `_activate_mutator`, `mutator_handler.lua:782`). SYNC-load (`Managers.package:load(pkg, "event_tweaker_curse_package", nil, false)`) each `packages` entry *before* `func` runs `start_function`. Idempotent (`has_loaded` + `_loaded_curse_packages` set). |
| **Package preload (hot-join)** | Hook `MutatorHandler.init` (`hook_safe`) — a mid-mission joiner instantiates already-spawned curse husks during game-object sync, which happens BEFORE the activate RPC (`peer_states.lua`), so `_activate_mutator` would be too late. `init` knows the mutator list at construction (host: the `mutators` arg; client: the network-synced `_initialized_mutator_map`, populated before game objects), so preload there too. Belt-and-suspenders with the `_activate_mutator` load. |
| **Unload** | `StateIngame.on_exit` (`state_ingame.lua:1847`) — ref-balanced `unload` per peer. |
| **Lighting** | Hook `CameraManager.shading_callback`; multiply per-god ShadingEnvironment vars (`_CURSE_SKY_PROFILES`, copied from `chaos_wastes_tweaker.lua:3247`). `_active_curse_god` cached on activate/deactivate. Reverts for free (engine re-seeds the shading_env every frame). `cursed_lighting` toggle (default on). |
| **Mechanism gate** | All four hooks no-op unless `Managers.mechanism:current_mechanism_name() == "adventure"`, so a real CW run (Deus loads the package, ct tints) is untouched. |

**Multiplayer:** unlike the host-only rest of the mod, the curse group needs **every player** to run event_tweaker — clients load the package locally to instantiate replicated curse units (`spawn_network_unit` husks).

**Excluded crashers** (`_CURSE_BROKEN_IN_ADVENTURE`, never surfaced): `curse_bolt_of_change` (Deus-mechanism-only `get_deus_run_controller`), `curse_belakors_shadows` (weave mutator, nil-arithmetic crash — package-free so the package filter can't catch it), `curse_empathy` (server-side `data.hero_side` nil-index). **Experimental** (surfaced, won't crash, may be inert): `curse_egg_of_tzeentch`, `curse_greed_pinata`.

**Catalog lives in `event_tweaker_curses.lua`, a shared `require`'d module** (`MANAGED_CURSES` / `BROKEN_IN_ADVENTURE` / `CURSE_TO_GOD`), NOT a `mod._field` set in the script. VMF loads files `localization → data → script` (script LAST), so a script-set field is nil when `_data.lua` / `_localization.lua` evaluate. A `require`'d module is evaluated once (by the first requiring file) and cached — all three files see it. This mirrors `enemy_tweaker_breeds.lua`. **Burned once** (v0.4.14-dev first cut): the entire Cursed Adventure UI group silently never built. Rule: anything `_data.lua` / `_localization.lua` need from the script must go through a shared `require`'d module, never a script-assigned `mod._field`.

## Architecture

Three hooks, all on backend classes. Single chokepoint per concern — every consumer of the hooked function sees the override consistently.

| Hook | Purpose | Why this entry point | suppress_live_event behavior |
| :--- | :--- | :--- | :--- |
| `BackendInterfaceLiveEventsPlayfab:get_special_events` | Inject `{name, weekly_event = "append", mutators}` so `GameModeBase.append_live_event_mutators` (`game_mode_base.lua:264`) picks up our mutators on every mission load. | Single class, no derived classes — string-form `mod:hook` patches the prototype that all instances see via `__index`. `GameModeBase.append_live_event_mutators` is the canonical mutator-activation path; mutator IDs flow from there into `mutator_handler.lua:85` `initialize_mutators` and out via `rpc_activate_mutator_client` to clients. | Drops Fatshark's entries before merge → also short-circuits the `DialogueSystem.on_add_extension` read at `dialogue_system.lua:196-212` so live-event ambient dialogue stops. |
| `BackendInterfaceLiveEventsPlayfab:get_active_events` | Inject the preset's event-name string (e.g. `"geheimnisnacht_2021"`). | `mutator_geheimnisnacht_2021.lua:58-86` calls `live_events_interface:get_active_events()` and does `string.find(live_event, "geheimnisnacht_%d+")` on each entry to decide which 5 maps spawn ritual sites (year-specific lists in `geheimnisnacht_utils.lua:5-41`). Without this hook, the mutator activates but spawns nothing. Skulls does NOT inspect this list — its mutator's `server_start_function` is self-contained. | Drops Fatshark's strings → `string.find` finds no `"geheimnisnacht_%d+"` match → ritual-site engine stays dormant on missions. |
| `BackendManagerPlayFab:get_level_variation_data` | Merge `hub_level = "inn_level_halloween"` / `"inn_level_skulls"` into the returned table. | `AdventureMechanism.get_starting_level` (`adventure_mechanism.lua:625`) reads `Managers.backend:get_level_variation_data().hub_level` and loads that level. Vanilla seasonal events ship pre-decorated keep level files — `inn_level_halloween`, `inn_level_skulls`, `inn_level_celebrate`, `inn_level_sonnstill` — defined in `scripts/settings/level_settings.lua:152-196`. Decorations are baked geometry, not runtime spawns. Mutators can't do this because `GameModeBase` skips hubs. | When suppress is on AND no preset hub_level, forces `merged.hub_level = "inn_level"` (matches `adventure_mechanism.lua:7 HUB_LEVEL_NAME`) so the keep reverts to plain inn. |

Two file-local tables drive the selection logic. **They MUST stay in sync** — VMF's mod-script vs mod-data load order isn't documented, and no sibling tweaker mod shares state across files, so the catalog is duplicated:

- `MUTATOR_CATALOG` in `event_tweaker.lua` — read by `selected_individual_mutators()` and the `event_clear` command.
- `CATEGORIES` in `event_tweaker_data.lua` — read at widget-tree build time to generate the checkbox groups.

`EVENT_PRESETS` lives only in `event_tweaker.lua`. The presets dropdown in `event_tweaker_data.lua` references the keys directly (no shared list needed because the dropdown's `value` strings are themselves the preset keys).

## Adding a new mutator

The mutator name must be a string that's already registered in `NetworkLookup.mutator_templates`. To verify before adding: check that `scripts/settings/mutators/mutator_<name>.lua` exists in the unpacked source (Vermintide-2-Source-Code). All vanilla + DLC batch_01/02/04 + Geheimnisnacht_2021 + Skulls_2023 mutators qualify; see `mutator_settings.lua:5-38` and the various DLC `_common_settings.lua` files for the full list.

1. Add the name to the matching category's `mutators` array in **both** `event_tweaker.lua` (`MUTATOR_CATALOG`) and `event_tweaker_data.lua` (`CATEGORIES`).
2. Add `mut_<id>` and `mut_<id>_tooltip` keys to `event_tweaker_localization.lua`. Convention: tooltip leads with `[<mutator_id>]` so the literal name being injected is verifiable from the UI.
3. Bump `MOD_VERSION` in `event_tweaker.lua` per the always-bump rule.
4. Build (`& $exe build event_tweaker`), deploy (`& $exe deploy event_tweaker`) where `$exe` is `tools\vmb-launcher\bin\Release\net9.0-windows\win-x64\publish\VMBLauncher.exe`, restart, test.

## Adding a new event preset

When a mutator inspects `active_events` internally (Geheimnisnacht does, Skulls does NOT), it needs a preset entry to work — checking the box alone won't trigger its set pieces. Same applies to events that ship a baked keep variant.

1. Add the preset to `EVENT_PRESETS` in `event_tweaker.lua`. Required fields:
   - `active_events` (table of strings) — what `get_active_events` will return
   - `mutators` (table of strings) — what `get_special_events` will return as the `mutators` field
   - `hub_level` (string, optional) — keep level variant to load. Use one of `inn_level_halloween` / `inn_level_skulls` / `inn_level_celebrate` / `inn_level_sonnstill`.
2. Add an option entry to the `event_preset` dropdown's `options` list in `event_tweaker_data.lua`.
3. Add `preset_<key>` localization key in `event_tweaker_localization.lua`.

## Confirmed mutator catalog (all year-round in NetworkLookup)

- **Vanilla** (`scripts/settings/mutator_settings.lua:5-38`): no_ammo,
  no_pickups, player_dot, instant_death, whiterun, no_respawn, elite_run,
  specials_frequency, more_specials, same_specials, big_specials,
  elite_specials, gutter_runner_mayhem, chaos_warriors_trickle,
  mixed_horde, multiple_bosses, hordes_galore, powerful_elites,
  shared_health_pool, high_intensity, wave_of_plague_monks,
  wave_of_berzerkers, night_mode, life, metal, heavens, light, shadow,
  fire, death, beasts, twitch_darkness (excluded — Twitch-only).
- **DLC mutators_batch_01**
  (`scripts/settings/dlcs/mutators_batch_01/mutators_batch_01_common_settings.lua:5-10`):
  splitting_enemies, darkness, ticking_bomb, realism.
- **DLC mutators_batch_02**
  (`mutators_batch_02_common_settings.lua:5-12`): escort, slayer_curse,
  explosive_loot_rats, leash, bloodlust, skulking_sorcerer.
- **DLC mutators_batch_04**
  (`mutators_batch_04_common_settings.lua:5-9`): flames,
  lightning_strike, chasing_spirits.
- **Live-event** (`geheimnisnacht_2021_common_settings.lua:52`,
  `skulls_2023_common_settings.lua:27`): geheimnisnacht_2021,
  geheimnisnacht_2021_hard_mode, skulls_2023.
- **No mutators_batch_03** in current source (probably retired or skipped numbering).

## Known mutator behaviors that affect the mod

- `mutator_geheimnisnacht_2021.lua:58-86` calls
  `live_events_interface:get_active_events()` and does
  `string.find(live_event, "geheimnisnacht_%d+")` to determine which 5
  maps spawn ritual sites — the year picked decides which canonical map
  list activates (see `geheimnisnacht_utils.lua:5-41` for the per-year
  lists). **Hence the preset dropdown is required for Geheimnisnacht to
  do anything visible.**
- `mutator_skulls_2023.lua` does NOT inspect `active_events` — its
  `server_start_function` spawns skull pickups on every
  `pickup_system.primary/secondary_pickup_spawners` unconditionally. The
  mutator alone is enough; preset is cosmetic for Skulls.
- `GameModeBase.append_live_event_mutators`
  (`game_mode_base.lua:257-288`) skips hub levels and tutorial levels.
- `level_keys = nil` on a special-event entry means "applies to all
  levels" (line 275 condition).
- **Keep decoration is NOT mutator-driven.** Vanilla
  Geheimnisnacht/Skulls/Anniversary swap the entire keep level file
  (decorations are baked geometry). `AdventureMechanism.get_starting_level`
  (`adventure_mechanism.lua:625`) reads
  `Managers.backend:get_level_variation_data().hub_level` and returns
  it. Variant level keys defined in
  `scripts/settings/level_settings.lua:152-196`: `inn_level_halloween`,
  `inn_level_skulls`, `inn_level_celebrate`, `inn_level_sonnstill`. Each
  loads its own world file and decoration packages. Hooked in v0.3.0-dev
  via `BackendManagerPlayFab.get_level_variation_data` — single entry
  point, all callers (state_ingame, interactions, carousel) get the
  override. Caveat: changing the preset after the keep is already loaded
  does NOT swap the keep — user must restart or run a mission and return.

## Sharp edges

### `get_special_events` entries MUST have a `name` field

When hooking `BackendInterfaceLiveEventsPlayfab:get_special_events` (or
otherwise fabricating live-event data), every entry MUST include a
non-nil string `name` in addition to `weekly_event` and `mutators`.

```lua
-- WRONG — crashes on startup with "table index is nil"
{ weekly_event = "append", mutators = { "geheimnisnacht_2021" } }

-- CORRECT
{ name = "geheimnisnacht_2021", weekly_event = "append", mutators = {...} }
```

**Why:** `scripts/entity_system/systems/dialogues/dialogue_system.lua:198-200`
does:

```lua
local event_name = event_data.name
self._global_context[event_name] = true   -- nil here = "table index is nil" crash
```

This runs on every level load **including the keep/hub**, so the crash
hits at startup — NOT only on missions.
`GameModeBase.append_live_event_mutators` skips hub levels, but
`DialogueSystem` does not. **Caused the v0.2.0-dev → v0.2.1-dev fix.**

**How to apply:** When any future tweaker-class mod injects fake events
into the live-events backend interface:

- Always set `entry.name` to a non-nil string. Use the canonical event
  name if it matches (e.g. `"geheimnisnacht_2021"`, `"skulls_2023"`), or
  a synthetic identifier (e.g. `"event_tweaker_custom"`) for
  hand-rolled selections.
- The dialogue system also iterates `entry.mutators` and calls
  `_load_special_event_dialogues(mutator_name, ...)` — that path uses
  `Application.can_get` first so missing dialogue files don't crash.

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

### Injected mutators that write scalar pacing values crash `ConflictDirector.init` (issue 386, v0.4.22-dev)

Some mutators' `update_conflict_settings` write PLAIN NUMBERS into `CurrentPacing`. The canonical case is `mutator_high_intensity.lua:12-14`:

```lua
CurrentPacing.delay_horde_threat_value       = 200
CurrentPacing.delay_specials_threat_value    = 200
CurrentPacing.delay_mini_patrol_threat_value = 200
```

`MutatorHandler.conflict_director_updated_settings` (`mutator_handler.lua:567`) runs every INITIALIZED mutator's `update_conflict_settings` and is dispatched from `ConflictDirector.refresh_conflict_director_patches` (`conflict_director.lua:886`), which `ConflictDirector.init` calls at line 94 — **before** init reads those three fields at lines 219-221 and passes each to `DifficultyTweak.converters.tweaked_delay_threat_value`. That converter **always** indexes its argument as a per-difficulty table (`difficulty_tweak.lua` `get_value_for_difficulty`: `value_table[Difficulties[i]]`), so a scalar there is an uncatchable "attempt to index a number value" fatal that kills the director → zero AI for the whole mission. Vanilla Adventure never lists these mutators, so the fields keep their table-shaped base values (`conflict_settings.lua`, keys `normal`..`versus_base`); **our injection is what triggers it**.

**Fix (do not remove):** a `hook_safe` on `MutatorHandler.conflict_director_updated_settings` runs after the vanilla dispatch writes the scalars (still inside `refresh_conflict_director_patches`, so before init's line 219 read) and converts any scalar left in those three fields into `{ normal = v, [current_difficulty] = v }`. `get_value_for_difficulty` walks DOWN to `Difficulties[1] == "normal"`, so the floor key covers every difficulty. Host-only in effect (`conflict_director_updated_settings` early-returns on clients) and a strict no-op when the fields are already tables. Regression check: `issue386_sanitize_pacing_scalar_to_table`.

**If you add a mutator to the catalog:** if its source `update_conflict_settings` assigns a plain number to any field ConflictDirector reads as a per-difficulty table, this sanitizer already covers the three known pacing fields — extend `PACING_TABLE_FIELDS` if a new field surfaces.

## Diagnostic commands

- `/event_probe` — dump `active_events`, `special_events`, `weekly_events` from the hooked backend interface (you'll see your injected entries reflected back) plus what the mod would currently inject given the active settings.
- `/event_active` — list mutators the engine actually activated in the current level (read from `Managers.state.game_mode._mutator_handler:activated_mutators()`). Use this to confirm the host-side hook + mutator handler picked up our injection.
- `/event_clear` — uncheck every individual mutator checkbox. The Event Preset dropdown is untouched.
- `/event_apply` — reload the current level so any pending preset or mutator changes take effect. Auto-fires on `event_preset` change; for individual mutator toggles you have to invoke this command (or wait for the next natural level transition).

## Build & deploy (matches sibling tweaker mods)

```powershell
$exe = "C:\Users\danjo\source\repos\vermintide-2-tweaker\tools\vmb-launcher\bin\Release\net9.0-windows\win-x64\publish\VMBLauncher.exe"
& $exe build  event_tweaker
& $exe deploy event_tweaker
# To push to Workshop (creates a new revision visible only to subscribers):
& .\upload_event_tweaker.ps1
# Or do all three in one shot:
& $exe all    event_tweaker
```

The legacy `deploy_all.ps1` shim that used to cover this flow was removed 2026-05-21 — use `VMBLauncher.exe deploy <mod>` (or `tools\ship\ship.ps1`) directly. `upload_event_tweaker.ps1` mirrors `upload_wt.ps1`'s pattern — it aborts if `itemV2.cfg` has `visibility = "public"` to prevent a repeat of the prior automated-public-flip incident that got two mods removed-from-community (irreversible).

## Known limitations

- Anniversary 2025 / 2026 and Sonnstill keep variants exist in `level_settings.lua:152-196` (`inn_level_celebrate`, `inn_level_sonnstill`) but no presets yet. Trivial to add — see "Adding a new event preset". (Geheimnisnacht 2026 and Skulls 2026 presets were added in v0.4.11-dev once Fatshark shipped the 2026 DLC content; gameplay still rides `mutator_geheimnisnacht_2021` / `mutator_skulls_2023` since no new mutator files were shipped.)
- Drachenfels event mutators and Karak Aspect winter event aren't surfaced because they're tangled with game mode selection (Deus / Chaos Wastes mechanism), not the standard mutator pipeline.
- Modded mutators from other workshop mods would need to be registered in `NetworkLookup.mutator_templates` independently — this mod only exposes mutators that ship in vanilla / first-party DLC.
- Backend-only event consequences — portrait frames, contracts, achievements — won't come back. The mod ships *gameplay* (mutators + keep decoration), not *loot*.
