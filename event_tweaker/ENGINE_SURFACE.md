# event_tweaker - engine contact surface

What vanilla VT2/Stingray does at every seam `event_tweaker` (`evt`) touches, and
why the mod is there. This is the per-mod companion to the subsystem set in
`docs/engine/` (read `docs/engine/README.md` for house style). It does **not**
re-explain a subsystem the engine docs own, and it does **not** duplicate the
mod's own `DEVELOPMENT.md` (module contracts, the three-hook architecture table,
the four issue-guard mechanics) or `CLAUDE.md` (workflow guardrails) - it names
each engine seam, cites the vanilla behavior, and links out. Decompile paths are
relative to `C:\Users\danjo\source\repos\Vermintide-2-Source-Code`; `evt` line
numbers name their `_evt_*` module. `§N` = a `docs/BUG_CLASSES.md` class; `#N` /
"issue N" = a GitHub issue. Grep-verified 2026-07-12 against the decompile.

`evt` is a host-side injector: it fabricates live-event backend responses so the
lobby runs any combination of vanilla/DLC mutators (and a themed keep) without
Fatshark pushing the event live. The mutators it injects are broadcast to
UNMODDED clients over the vanilla `rpc_activate_mutator_client` path, so
crash-safety of every injected name is the mod's core invariant - three of its
hooks/guards exist only to keep an injected mutator from fataling a peer. One
feature group (Cursed Adventure) inverts the host-only model and needs every peer
to run the mod (clients must preload the curse resource package for replicated
husks).

## Hook table

10 registration sites (per `CLAUDE.md`; `tools/mod-lint/lint-mod.ps1` enforces one
hook per (Class, method) mod-wide), grouped into 4 rows-of-concern. `[hook]` = full
wrapper (`mod:hook`, can rewrite args/returns); `[safe]` = `mod:hook_safe`
(post-callback, no override). All 10 are string-form (each target class has a single
implementation reached through `__index`, so no derived-class split). Note: two of
the four issue guards (#413 weave, #455 boss-events) are NOT hooks - they enforce at
the `add()` injection chokepoint / by wrapping mutator-template dispatch fields, and
are covered in the subsystem notes, not this table.

### Live-event injection - the three backend hooks (owner doc: `docs/engine/11`, feeds `docs/engine/07`)

| Class.method (kind) | Vanilla behavior at the seam | Why evt hooks it | Trap / invariant |
|---|---|---|---|
| `BackendInterfaceLiveEventsPlayfab.get_special_events` [hook] `_evt_backend_hooks.lua:32` | Returns the weekly special-event list; `GameModeBase.append_live_event_mutators` reads it to activate mutators on every mission load, and `DialogueSystem.on_add_extension` reads each entry's `.name` [src: `backend_interface_live_events_playfab.lua:126`; consumer `game_mode_base.lua:257`; dialogue read `dialogue_system.lua:198-200`] | Inject `{name, weekly_event="append", mutators}` so the selected mutators activate; optionally drop Fatshark's entries first (`suppress_live_event`) (`:32`) | Every injected entry MUST carry a non-nil string `name` - `DialogueSystem` does `self._global_context[event_data.name] = true` on EVERY level load incl. the keep, so a nil name is a "table index is nil" startup CTD (§ special-events-name-required; v0.2.0->0.2.1 fix). Broadcast to unmodded clients - injected names must be crash-safe (the guards below) |
| `BackendInterfaceLiveEventsPlayfab.get_active_events` [hook] `_evt_backend_hooks.lua:85` | Returns the active-event NAME strings; `mutator_geheimnisnacht_2021` does `string.find(live_event, "geheimnisnacht_%d+")` over them to pick which 5 maps spawn ritual sites [src: `backend_interface_live_events_playfab.lua:134`; consumer `geheimnisnacht_utils.lua` per-year lists] | Inject the preset's event-name string so Geheimnisnacht's ritual-site engine finds its map list (without it the mutator activates but spawns nothing) (`:85`) | Skulls does NOT inspect this list (its `server_start_function` is self-contained), so a preset is cosmetic for Skulls but REQUIRED for Geheimnisnacht |
| `BackendManagerPlayFab.get_level_variation_data` [hook] `_evt_backend_hooks.lua:114` | Returns the level-variation table; `AdventureMechanism.get_starting_level` reads `.hub_level` and loads that keep level [src: `backend_manager_playfab.lua:1174`; consumer `adventure_mechanism.lua:614`] | Merge `hub_level = "inn_level_halloween"/"inn_level_skulls"` so the keep loads its pre-decorated (baked-geometry) seasonal variant; on suppress-with-no-preset pin to plain `"inn_level"` (`:114`) | Decorations are baked into the level file, NOT runtime spawns - a mutator can't produce them (`GameModeBase` skips hubs). `table.clone` the original (may be the cached EMPTY_TABLE). Queried only at keep-load, so a mid-keep preset change needs a level reload (`_evt_apply.lua`) |

### Injected-mutator crash guard: scalar pacing (issue 386, host-fatal if absent) (owner doc: `docs/engine/07`)

| Class.method (kind) | Vanilla behavior | Why evt hooks it | Trap / invariant |
|---|---|---|---|
| `MutatorHandler.conflict_director_updated_settings` [safe] `_evt_guard386_pacing.lua:119` | Runs every initialized mutator's `update_conflict_settings`; dispatched from `ConflictDirector.refresh_conflict_director_patches`, which `ConflictDirector.init` calls BEFORE it reads the `delay_*_threat_value` pacing fields [src: `mutator_handler.lua:567`; dispatch `conflict_director.lua:886`; init read `conflict_director.lua:219-221` -> `DifficultyTweak.converters.tweaked_delay_threat_value`] | Sanitize: some injected mutators (`mutator_high_intensity`) write PLAIN NUMBERS into `CurrentPacing.delay_*_threat_value`, but the converter always indexes its arg as a per-difficulty table, so a scalar is an uncatchable "index a number value" fatal that kills the director -> zero AI. Convert any leftover scalar to `{normal=v, [current_difficulty]=v}` (`:119`) | LOAD-BEARING guard, never toggle-gated (`CLAUDE.md`). `hook_safe` fires after vanilla writes the scalar but still inside `refresh_conflict_director_patches`, i.e. before init reads it. Host-only in effect (vanilla early-returns on clients); strict no-op when fields are already tables. Our injection is what triggers it - vanilla Adventure never lists these mutators (§ mutator scalar pacing, issue 386) |

### Cursed Adventure: curse package + lighting (every-peer; per-frame row) (owner docs: `docs/engine/05`, `docs/engine/08`)

| Class.method (kind) | Vanilla behavior | Why evt hooks it | Trap / invariant |
|---|---|---|---|
| `MutatorHandler._activate_mutator` [hook] `_evt_cursed_adventure.lua:93` | The per-mutator activation chokepoint, hit on the HOST (via `activate_mutators`) AND every CLIENT (via `rpc_activate_mutator_client` -> `_activate_mutator`) [src: `mutator_handler.lua:782` (client RPC path)] | SYNC-load each curse's resource `packages` entry BEFORE `func` runs the mutator's `start_function`; refresh the god-lighting cache (`:93`) | Package-bearing CW/Deus curses normally crash in Adventure because only `DeusRunState.set_event_mutators` loads their package [src: `deus_run_state.lua:438-453`]; the mechanics themselves use standard managers. Idempotent (`has_loaded` + `_loaded_curse_packages`). All four curse hooks no-op unless mechanism is `"adventure"` so real CW runs are untouched |
| `MutatorHandler._deactivate_mutator` [hook] `_evt_cursed_adventure.lua:104` | Per-mutator deactivation [src: `mutator_handler.lua`, `[unverified]` exact line] | Keep the active-god lighting cache current on deactivate (`:104`) | Distinct method from `_activate_mutator` - no hook collision |
| `MutatorHandler.init` [safe] `_evt_cursed_adventure.lua:119` | Constructs the handler; knows the mutator list at construction (host: the `mutators` arg; client: the network-synced `_initialized_mutator_map`, populated before game objects) [src: `mutator_handler.lua`, init `[unverified]` exact line] | Hot-join safety: a mid-mission joiner instantiates already-spawned curse husks during game-object sync, which happens BEFORE the activate RPC, so `_activate_mutator`'s load would be too late - preload here too (`:119`) | Belt-and-suspenders with `_activate_mutator`. `_initialized_mutator_map` shape is engine-internal, so harvest any string key OR value as a candidate name |
| `StateIngame.on_exit` [safe] `_evt_cursed_adventure.lua:141` | Fires on leaving the in-game state (keep or mission) [src: `scripts/game_states/ingame/state_ingame.lua`, `[unverified]` exact line] | Ref-balanced `Managers.package:unload` per peer + clear the god cache on mission exit (`:141`) | Only drop a `_loaded_curse_packages` entry whose `unload` pcall actually succeeded - a divergent-ref failure must keep the entry so it isn't orphaned/leaked (`docs/engine/05` refcount model) |
| `CameraManager.shading_callback` [safe] `_evt_cursed_adventure.lua:193` | Per-frame shading callback; vanilla wraps its whole body in `if self._world == world` (UI/preview/end-screen worlds also drive it) [src: `scripts/managers/camera/camera_manager.lua`, `[unverified]` exact line] | Multiply per-god ShadingEnvironment vars for the active curse's sky/atmosphere tint (`:193`) | PER-FRAME row: must mirror the `self._world == world` guard, and must NEVER read `mod._evt` or any cross-file indirection - all reads are file-local upvalues, zero table allocations per frame (`CLAUDE.md`). Reverts for free (engine re-seeds the shading_env every frame); gated on mechanism `"adventure"` so ct owns real CW tinting |

### Diagnostics (always-on in dev, printf only) (owner doc: `docs/engine/07`)

| Class.method (kind) | Vanilla behavior | Why evt hooks it | Trap / invariant |
|---|---|---|---|
| `ConflictDirector.init` [safe] `_evt_diagnostics.lua:137` | Fires once per level as the conflict director initializes; by this point `CurrentIntensitySettings` / `CurrentPacing` hold the post-mutator values the director will pace against [src: `conflict_director.lua` init, read fields `:219`] | Issue 393 post-init snapshot: printf the intensity/pacing fields + the injected mutator list to prove whether an injected mutator's writes survived or were stomped (`:137`) | Read-only diagnostic, no behavior change; printf only (users run mod-logs OFF), pcall-wrapped. Diagnostics are always-on in dev, never a menu toggle (memory `feedback_diagnostics_never_toggles`). enemy_tweaker also touches `ConflictDirector` - no collision (VMF hook-drop is per-mod) |

## Subsystem notes (how the vanilla flow runs end-to-end, for evt's cases)

Each note is the minimum needed to read the hooks above; the owning `docs/engine`
doc and the mod's `DEVELOPMENT.md` carry the full architecture.

### Injection path + the single chokepoint (owner: `docs/engine/07`; detail: `DEVELOPMENT.md` Architecture)

Selection flows one way: `_evt_selection.lua`'s `gather_mutators()` builds the name
list, its inner `add()` is the SINGLE injection chokepoint, and the
`get_special_events` hook wraps that list into the fabricated live-event entry. From
there the vanilla path takes over: `GameModeBase.append_live_event_mutators`
[src: `game_mode_base.lua:257`] activates each name, `mutator_handler.lua`
`initialize_mutators` builds the handlers, and `rpc_activate_mutator_client`
broadcasts to clients (who need NO mod). Because everything an injected name touches
runs on an unmodded client, crash-safety is enforced at `add()` - which is why a new
injection route that bypasses `add()` silently bypasses every guard.

### The four injected-mutator crash guards - two hooks, two not (owner: `docs/engine/07`)

Only ONE guard (issue 386, above) is a `mod:hook`. The other three are enforced
without hooking a vanilla method, and are load-bearing regardless:
- **Issue 413 (weave-only mutators)** - the 7 Winds-of-Magic mutators
  (`shadow`/`heavens`/`light`/`death`/`beasts`/`fire`/`life`) assume a Weave context;
  outside one, `Managers.weave:get_active_wind_settings()` is nil and the weave
  packages are non-resident, so they nil-index or spawn a non-resident unit and fatal
  (host, client, or every-peer depending on the mutator) [src: `weave_manager.lua`
  wind-settings; `mutator_shadow.lua:186-187` non-resident unit]. Fixed by DROPPING
  the 7 names at `add()` whenever no weave wind is active - a host-only mod cannot
  preload vanilla clients, so exclusion at injection is the only safe fix
  (`_evt_guard413_weave.lua`).
- **Issue 455 (boss-event mutators)** - `multiple_bosses` / `blessing_of_grimnir` /
  `deus_pacing_tweak` index `CurrentBossSettings.boss_events` with no nil check; a
  fixed-end-boss level (e.g. The War Camp) ships a boss block with no `boss_events`
  table, so injecting one is an instant host fatal [src: `conflict_director.lua:879`
  rebuilds CurrentBossSettings; dispatch `mutator_handler.lua:644-645`/`:578-579`].
  Fixed by WRAPPING the mutator template's live dispatch fields
  (`template.server.initialize_function` / `.start_function` /
  `template.update_conflict_settings`) with a no-op-when-absent check. Note the engine
  folds `server_*_function` into `template.server.*` at boot, so wrapping the raw
  `server_*_function` field would be a dead write (`_evt_guard455_boss_events.lua`).
- **Issue 386 (scalar pacing)** - the one guard that is a hook (see table).

The paid-for lesson is that a host-only injector's blast radius is every unmodded
peer, and each vanilla mutator has to be individually proven adventure-safe before it
can be surfaced.

### Cursed Adventure inverts the host-only model (owner: `docs/engine/05`)

Unlike the rest of the mod, the curse group needs EVERY peer running event_tweaker,
because a client instantiates replicated curse husks (`spawn_network_unit`) from a
package the base game only loads inside a Deus run. The load is doubled deliberately:
`_activate_mutator` covers the normal-join + host case, and `init` covers the
hot-join race (game-object sync precedes the activate RPC). Unload is ref-balanced on
`StateIngame.on_exit`. This is the standard `docs/engine/05` refcount discipline -
load guarded by `has_loaded`, unload only the entries whose unload succeeded.

## What the engine will NOT let us do (dead ends, already paid for)

Pulled from `DEVELOPMENT.md` "Sharp edges" and `docs/BUG_CLASSES.md` - do not
re-discover these.

- **A fabricated live-event entry with no `name` crashes at STARTUP, not on a mission.**
  `DialogueSystem.on_add_extension` keys `_global_context` on `event_data.name` on
  every level load including the keep, so a nil name is "table index is nil" at boot -
  even though `append_live_event_mutators` itself skips hubs. Always set a non-nil
  string name (canonical event name, or a synthetic `"event_tweaker_custom"`)
  [src: `dialogue_system.lua:198-200`; v0.2.0->0.2.1 fix].
- **A scalar written into a per-difficulty pacing field kills the whole conflict
  director.** `mutator_high_intensity` assigns plain numbers to
  `CurrentPacing.delay_*_threat_value`; the difficulty converter always indexes them
  as tables, so `ConflictDirector.init` fatals and the mission gets zero AI. The
  sanitizer only exists because OUR injection lists mutators vanilla Adventure never
  would - extend `PACING_TABLE_FIELDS` if a new scalar-writing field surfaces (issue
  386).
- **A host-only mod cannot make an injected mutator safe on a vanilla client by
  preloading - it can only decline to inject it.** That is why the weave-only fix
  (issue 413) is exclusion-at-injection, in contrast to Cursed Adventure where every
  peer runs the mod and preloads. Any future "run this normally-gated mutator in
  Adventure" idea has to answer "does an unmodded client survive it?" first.
- **Keep decoration is not mutator-driven and mutators cannot reach hubs.**
  `GameModeBase.append_live_event_mutators` early-returns on `hub_level` /
  `tutorial_level` [src: `game_mode_base.lua:260-262`], and vanilla seasonal keeps are
  entirely separate baked level files. The only lever is swapping `hub_level` via
  `get_level_variation_data`; mission-board reskins or keep NPC/dialogue swaps would
  need additional, different hooks.
- **All three backend queries are consulted at level-load only.** A preset change
  between loads is dormant until the next level swap; there is no push mechanism, so
  `_evt_apply.lua` fakes one with a `retry_level()` / `set_next_level` reload. Individual
  mutator checkboxes deliberately do NOT auto-reload (N toggles would = N keep reloads)
  - `/event_apply` is the manual trigger.

## Doc maintenance

Follows `docs/engine/README.md` maintenance rules: if an evt hook moves, a guard is
added, or a cited vanilla line drifts after a game patch, edit the affected row in
the SAME commit. This doc complements, and must not duplicate, `DEVELOPMENT.md`
(module contracts + the guard mechanics in full) and `CLAUDE.md` (workflow) - when a
guard's mechanic changes, `DEVELOPMENT.md` is the primary and this doc's row is the
follow-on edit. Line numbers are against the 2026-07-12 decompile - match crash logs
by function name, not line. A few `MutatorHandler`/`StateIngame`/`CameraManager`
targets carry `[unverified]` exact lines (class + method grep-confirmed; the interior
line was not pinned this pass) - replace the tag with a citation when next touched.
Section shape (hook table -> subsystem notes -> dead ends) matches
`character_weapon_variants/ENGINE_SURFACE.md`. Reverse index:
`docs/engine/README.md` "Per-mod surface docs".
