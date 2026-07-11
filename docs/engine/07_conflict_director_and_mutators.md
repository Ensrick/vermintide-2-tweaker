# Engine reference 07 - Conflict director, breeds and mutators

Engine reference for the AI spawning / pacing / mutator stack and how enemy_tweaker (et),
event_tweaker (evt) and chaos_wastes_tweaker_dev (ct) hook it. Vanilla paths are relative to
`C:\Users\danjo\source\repos\Vermintide-2-Source-Code`; our paths are relative to this monorepo.
Every claim cites file:line or is marked [unverified].

---

## 1. Architecture map

| File / class | Single responsibility |
|---|---|
| `scripts/managers/conflict_director/conflict_director.lua` - `ConflictDirector` | Server-side orchestrator: owns the spawn queue, per-side spawned bookkeeping, threat value, horde/mini-patrol timers, terror-event entry points, and the per-level settings refresh. Created at `state_ingame.lua:2238`, updated at `:954` (server) / `:957` (client stub) |
| `conflict_director/pacing.lua` - `Pacing` | 4-state intensity cycle (`pacing_build_up -> pacing_sustain_peak -> pacing_peak_fade -> pacing_relax`, pacing.lua:121-173) driving three population gates: `threat_population` (roamers), `specials_population`, `horde_population` (pacing.lua:89-99) |
| `conflict_director/specials_pacing.lua` - `SpecialsPacing` | Slot-based special spawner: per-slot breed + timer, dispatch through the **plain tables** `SpecialsPacing.setup_functions` (:75) and `SpecialsPacing.select_breed_functions` (:122); `delay_spawning` (:595) is the engine's "hold specials" lever |
| `conflict_director/horde_spawner.lua` - `HordeSpawner` | Composes and spawns ambush / vector / vector_blob / event hordes. Composition roll reads `composition.loaded_probs` via `LoadedDice.roll_easy` (horde_spawner.lua:139/243/349/743); per-unit spawn funnels into `ConflictDirector:spawn_queued_unit` via `HordeSpawner.spawn_unit` (:1228) |
| `conflict_director/terror_event_mixer.lua` - `TerrorEventMixer` | **Static module, not a class.** Element-list interpreter for terror events: global state tables (:59-64), `init_functions` (:65) / `run_functions` (:624) dispatch tables, `start_event` (:1757), `update` (:1871), `run_event` (:1908) |
| `conflict_director/enemy_recycler.lua` - `EnemyRecycler` | Roaming population: activates/deactivates baked spawn packs around players; roaming spawns get `spawn_type = "roam"` (enemy_recycler.lua:585/604); pack lookup `BreedPacksBySize[pack_type][amount]` is UNGUARDED (:286), floor `min_roaming_patrol_size = 3` (:260) |
| `conflict_director/spawn_zone_baker.lua` - `SpawnZoneBaker` | Bakes the level's roaming spawn zones (density, pack members, per-zone conflict director + zone mutators) |
| `conflict_director/main_path_spawning_generator.lua` | Zone generation pass; per-zone it folds mutators into pack-spawning settings via the STATIC `MutatorHandler.tweak_pack_spawning_settings(zone_mutator_list, mutator_list, name, settings)` - dot call, 4 args, NO self (main_path_spawning_generator.lua:327) |
| `conflict_director/level_analysis.lua` - `LevelAnalysis` | Main-path generation + boss/patrol terror-event placement (`generate_boss_paths` places `boss_events`, level_analysis.lua:1508-1516; mechanism override at :1053-1060) |
| `conflict_director/breed_freezer.lua` - `BreedFreezer` | Unit pooling: freezes dead horde units for reuse; unfreeze attempted in `update_spawn_queue` (conflict_director.lua:1859), freeze attempted in `register_unit_destroyed` (:2386); commits in CD `pre_update`/`post_update` (:1699-1709) |
| `conflict_director/peak_delayer.lua`, `gathering.lua`, `patrol_analysis.lua`, `enemy_recycler.lua` | Support: travel-dist peak throttle (update at conflict_director.lua:1681-1696), dogpile attacker bookkeeping, patrol spline analysis |
| `scripts/managers/game_mode/mutator_handler.lua` - `MutatorHandler` | Owns initialized (`self._mutators`) and active (`self._active_mutators`) mutator sets; dispatches every template callback; server/client split; RPC sync (`rpc_activate_mutator_client` / `rpc_deactivate_mutator_client`, mutator_handler.lua:22-25) |
| `scripts/managers/game_mode/mutator_templates.lua` | **Template folding at boot**: wraps each `mutator_settings` entry's `server_*_function` / `client_*_function` fields into `template.server.*` / `template.client.*` closures with defaults (mutator_templates.lua:238-545). The raw `server_start_function` field is DEAD after folding - hook the folded form |
| `scripts/settings/mutator_settings.lua` | The mutator list + `local_require` loader (:5-52); DLC batches appended via `DLCUtils.append("mutators", ...)` (:40). Curse/deus mutators live in `scripts/settings/mutators/mutator_curse_*.lua` / `mutator_deus_*.lua` |
| `scripts/managers/game_mode/game_mode_manager.lua` - `GameModeManager` | Glue: builds the mutator list (game-mode mutators + `LevelSettings[level].mutators`, game_mode_manager.lua:85-95), creates `MutatorHandler` (:99), activates on `setup_done` (:163-166), forwards `ai_killed`/`ai_spawned`/`player_hit`/`damage_taken` (:193-235), `players_left_safe_zone` (:256-257), `conflict_director_updated_settings` (:133-135), updates the handler (:709/:740), hot-join sync (:920) |
| `scripts/settings/conflict_settings.lua` | All spawn-side data: `HordeSettings` (:82), `RoamingSettings` (:663), `SpecialsSettings` (:1821), `BossSettings` (:2475), `IntensitySettings` (:2903), `PacingSettings` (:2955), `PackSpawningSettings` (:3641), and `ConflictDirectors` (:5106) which composes one of each per director name. `loaded_probs` LoadedDice tables are pre-built at file load (:72-77 for HordeCompositions, :636-641 for HordeCompositionsPacing) |
| `scripts/settings/breeds.lua` + `scripts/settings/breeds/breed_*.lua` | `Breeds` global: dofile list (breeds.lua:26-73), then normalization (name/is_ai/race sets/elite set, :305-384). `SET_BREED_DIFFICULTY()` re-resolves per-difficulty action damage tables (:194-226) |
| `scripts/settings/breeds/breed_tweaks.lua` | `BreedTweaks` per-rank step-multiplier arrays - 9 entries, indexed by difficulty RANK 1..9 (breed_tweaks.lua:7-17) |
| `scripts/settings/difficulty_settings.lua` | `DifficultySettings` with `rank` per difficulty: normal=2, hard=3, harder=4, hardest=5, cataclysm=6, cataclysm_2=7, cataclysm_3=8, versus_base=9 (difficulty_settings.lua:22/58/100/142/186/237/287/341). **There is no rank-1 entry** (legacy "easy"). `Difficulties` array (:402-411), `DefaultDifficulties` stops at cataclysm (:412-418), rank lookups (:389-400) |
| `scripts/settings/difficulty_tweak.lua` | `DifficultyTweak.converters` (:76-98). `tweaked_delay_threat_value` -> `nearest_lerp_table` -> `get_value_for_difficulty`, which ALWAYS indexes its arg as a table keyed by difficulty NAME, walking DOWN the `Difficulties` array (:5-15). Deathwish/tweak offsets shift the difficulty used for composition/pacing/intensity by up to 2 steps (:79-90) |
| `scripts/settings/dlcs/morris/deus_conflict_settings.lua` | CW directors `ConflictDirectors.deus_*` (:3147-3224) plus deus horde/boss/pacing blocks (boss_events at :566+) |
| `scripts/managers/game_mode/mechanisms/deus_run_state.lua` - `DeusRunState` | CW run shared state; `set_event_mutators` is the ONLY code that loads a mutator template's `packages` list (deus_run_state.lua:438-453) - Adventure has no equivalent loader |

Globals rebuilt per director/difficulty refresh: `CurrentConflictSettings`, `CurrentPacing`,
`CurrentIntensitySettings`, `CurrentBossSettings`, `CurrentSpecialsSettings`,
`CurrentHordeSettings`, `CurrentRoamingSettings`, `CurrentPackSpawningSettings`
(conflict_director.lua:849, :877-883).

---

## 2. Lifecycle and data flow

### 2.1 Boot (file load, before any mission)

1. `breeds.lua` dofiles every breed file, then normalizes (`breed.name`, race sets, `ELITES`) (breeds.lua:26-73, :305-384).
2. `conflict_settings.lua` builds all settings blocks + `ConflictDirectors`, pre-computing `loaded_probs` (conflict_settings.lua:72-77, :636-641). DLC files append (e.g. deus directors, deus_conflict_settings.lua:3147+).
3. `conflict_director.lua` file scope builds the `local threat_values` upvalue from `pairs(Breeds)` ONCE (conflict_director.lua:2295-2303). A breed registered later is invisible to it unless seeded via `ConflictDirector.set_threat_value` (:2313-2315).
4. `mutator_templates.lua` folds `mutator_settings` into `MutatorTemplates` with server/client closure tables (mutator_templates.lua:236-545).

### 2.2 Mission start (server)

1. `GameModeManager.init` collects mutator names (game mode + level) and creates `MutatorHandler`, which on the server immediately runs `initialize_mutators` -> `_server_initialize_mutator` -> `template.server.initialize_function` per name (game_mode_manager.lua:85-99, mutator_handler.lua:45-48, :621-650). **Initialize runs data-level mutations** (default init folds in breed max_health/armor multiplication, mutator_templates.lua:230-234, :5-34) - this is where curse breed tables land on `Breeds`.
2. `ConflictDirector:new` (state_ingame.lua:2238) -> `init` (conflict_director.lua:72): calls `set_updated_settings` (:94) -> `refresh_conflict_director_patches` (:852) which clones+difficulty-patches all `Current*` globals (:877-883) and then dispatches `Managers.state.game_mode:conflict_director_updated_settings()` (:885-887) -> `MutatorHandler.conflict_director_updated_settings` -> every INITIALIZED template's `update_conflict_settings` (mutator_handler.lua:567-582). Back in `init`, the three `CurrentPacing.delay_*_threat_value` fields are converted through `DifficultyTweak.converters.tweaked_delay_threat_value` (:216-221) - **this read happens after mutators may have scribbled on CurrentPacing** (see trap 4.1).
3. `ai_ready` (conflict_director.lua:3575): nav world, `SpawnZoneBaker`, `tweak_zones` mutator pass (:3626), `SpecialsPacing:new` (:3653), `generate_spawns` (:3661, hands the mutator list to the baker :3551-3554), `BreedFreezer` (:3667-3669). Then `ai_nav_groups_ready` (:3672): `EnemyRecycler` (:3673), `HordeSpawner` (:3677), boss path/terror placement when `CurrentBossSettings.boss_events` allow (:3679-3683, level_analysis.lua:1508-1516).
4. `GameModeManager.setup_done` -> `MutatorHandler.activate_mutators` -> per-mutator `_activate_mutator`: `server.start_function`, `client.start_function`, `template.register_rpcs`, then broadcast `rpc_activate_mutator_client` to clients (game_mode_manager.lua:163-166, mutator_handler.lua:102-112, :652-703). Clients activate via the RPC receiver (:771-783). Hot-joiners get replayed activations + `hot_join_sync_function` (:148-170).

### 2.3 Per-frame (server, `ConflictDirector.update`, conflict_director.lua:1430)

Order matters:
1. main-path player info; per-zone checks: `check_update_mutators(zone.mutators)` deactivates/initializes+activates zone mutators (:597, :795-842) and `check_updated_settings` swaps the conflict director at zone boundaries (:605, :762-793); either triggers `refresh_conflict_director_patches` (:608-610) which REBUILDS all `Current*` clones - any mod mutation of those globals is lost here unless re-applied.
2. threat: every 1s `calculate_threat_value` sums `threat_values[breed] * activated_count` and derives `delay_horde` / `delay_mini_patrol` / `delay_specials` flags (:1466-1471, :2317-2332); `check_pacing_event_delay` forces all three during terror-event delay (:2334-2340, event `event_delay_pacing` :2393).
3. pacing: every 1s `Pacing:update` averages per-player `status_ext:get_pacing_intensity()` into `total_intensity` and steps the state machine (:1476-1505, pacing.lua:175-198); state transitions broadcast `rpc_pacing_changed` (pacing.lua:165-169). Rush/lone-player/speed-run interventions (:1507-1519).
4. safe-zone exit: first `is_round_started` tick calls `game_mode:players_left_safe_zone`, starts `specials_pacing` and seeds `_next_horde_time` from `CurrentPacing.horde_startup_time` (:1522-1542).
5. specials: `specials_pacing:update(t, alive_specials, pacing:specials_population(), positions)` unless disabled by settings/game mode (:1544-1548).
6. hordes: `update_horde_pacing` (:1550-1556, :890-1020) - gated on `pacing:horde_population() >= 1` and not `delay_horde`; skips/pushes when `#spawned > RecycleSettings.push_horde_if_num_alive_grunts_above` (:906-926); picks ambush/vector/vector_blob and multi-wave counts from `CurrentPacing`/`CurrentHordeSettings` (:936-1004); executes via `horde_spawner:horde` (:1018). `horde_killed` reschedules (:1022-1041).
7. mini patrols during `pacing_build_up` on levels with `use_mini_patrols` (:1558-1564); `horde_spawner:update` (:1566-1568).
8. `TerrorEventMixer.update` once director is ai_ready (:1585-1588): runs one element per active event per frame (`run_event` advances `event.index` when a run_function returns true, terror_event_mixer.lua:1908-1945), then drains `start_event_list` (:1890-1901). `start_event` expands the blueprint through `process_terror_event` - difficulty-rank + faction + mutator-tag element filtering (`is_element_available`, :1611-1658; tags from `MutatorHandler.get_terror_event_tags`, :1737) - then `Managers.state.game_mode:post_process_terror_event(elements)` gives mutators a rewrite pass (:1779, mutator_handler.lua:502-515).
9. roaming: `enemy_recycler:update` with `pacing:threat_population()`, zeroed when `RecycleSettings.max_grunts` reached (:1601-1648); main-path events (:1650-1652).
10. **spawn queue drain**: `update_spawn_queue` spawns AT MOST ONE unit per frame, skipping entries whose breed package is not yet loaded on all peers (`enemy_package_loader:is_breed_loaded_on_all_peers`, :1835-1891), preferring a breed-freezer unfreeze (:1859-1868).
11. far-off despawn (:1656-1660), deferred spline patrols (:1662-1679), peak delayer (:1681-1696).

### 2.4 Unit spawn path (server)

`spawn_queued_unit` (conflict_director.lua:1732) is the universal enqueue: horde, specials,
terror events, patrols, debug all reach it (`spawn_one` :3410, `spawn_at_raw_spawner` :3462,
`HordeSpawner.spawn_unit` horde_spawner.lua:1228). It requests the breed package
(`enemy_package_loader:request_breed`, may substitute a replacement breed :1736-1747) and queues
`{breed, pos, rot, category, animation, spawn_type, optional_data, group_data, unit_data, id}`
(:1749-1790). Dequeue -> `_spawn_unit` (:1905): resolves `health = breed.max_health[difficulty_rank]`
(:1947-1954 - the rank-hole crash site, see 4.3), builds extension init data, calls
`optional_data.prepare_func` (:2003-2005), `game_mode:pre_ai_spawned` -> mutator
`pre_ai_spawned_function` (:2007, game_mode_manager.lua:226-227, mutator_handler.lua:384-401),
spawns the network unit (:2022), then `_post_spawn_unit` (:2029): `post_ai_spawned` mutator pass
(:2034), per-side bookkeeping (:2061-2088), event `"ai_unit_spawned"` (:2090),
`optional_data.spawned_func` (:2105-2107). Death/despawn unwind:
`register_unit_killed`/`destroy_unit` -> `_remove_unit_from_spawned` (:2344-2369, :2403-2416,
:2188-2293) fires `optional_data.despawned_func` (:2262-2264) and `"ai_unit_despawned"` (:2290-2292);
`register_unit_destroyed` runs `breed.run_on_despawn` and offers the unit to the breed freezer
(:2371-2391).

### 2.5 Difficulty and per-rank breed data

`Managers.state.difficulty:get_difficulty()` returns (name, tweak); `get_difficulty_rank()` the
numeric rank. Per-rank breed arrays (`breed.max_health`, BreedTweaks step multipliers) are indexed
by RANK (conflict_director.lua:1947-1948; breed_tweaks.lua:7-17 - 9 entries covering ranks 1-9).
Per-difficulty-NAME tables (pacing delay thresholds, conflict_settings.lua:2994-3025) are resolved
by `get_value_for_difficulty`'s downward walk over `Difficulties` (difficulty_tweak.lua:5-15) -
missing high keys fall back to the nearest lower entry; `normal` (`Difficulties[1]`) is the floor.
The two schemes DO NOT mix: a NAME-keyed table read as rank-indexed (or vice versa) produces holes.
Difficulty tweak (Deathwish range -10..10) offsets which difficulty's composition/pacing/intensity
tables get used (difficulty_tweak.lua:79-90, applied at conflict_director.lua:873-875).

### 2.6 Deus / Chaos Wastes specifics

- CW missions run the `deus_*` conflict directors (deus_conflict_settings.lua:3147-3224); zone
  sequencing injects `no_roamers` / `easier_packs` as ZONE mutators via `deus_pacing_tweak`
  sequences (mutator_deus_pacing_tweak.lua:32-89).
- Curses are ordinary mutator templates (`mutator_curse_*.lua`) whose `packages` field is loaded
  ONLY by `DeusRunState.set_event_mutators` (deus_run_state.lua:438-453). Activating a
  package-bearing curse on an Adventure mission without preloading = async "Resource not found"
  fatal (memory `reference_vt2_mutator_packages_deus_only`).
- The run difficulty flows `DeusRunController.get_run_difficulty` -> level transition ->
  `Managers.state.difficulty:set_difficulty` [unverified exact vanilla line; asserted in ct comment
  chaos_wastes_tweaker_dev.lua:2373-2381].

---

## 3. Hookable seams

Legend: method = colon-called (hook signature `function(func, self, ...)`); STATIC = dot-called
plain function or dispatch-table entry (hook signature `function(func, ...)` - NO self).
Getting this wrong shifts every argument by one (see 4.5).

| Seam | Kind | Safe pattern | Used by us |
|---|---|---|---|
| `ConflictDirector.init` (conflict_director.lua:72) | method | post-wrap: call `func(self, ...)` FIRST, then apply settings mutations - init itself refreshes `Current*` | et enemy_tweaker.lua:1173 |
| `ConflictDirector.refresh_conflict_director_patches` (:869) | method | post-wrap and RE-APPLY every `Current*` mutation here - fires at init AND every zone director/mutator change (:608-610) | et enemy_tweaker.lua:1209 |
| `ConflictDirector.spawn_queued_unit` (:1732) | method | full wrapper, substitute the breed TABLE only and forward all 10 params; let vanilla do the package request. ONE consolidated hook per mod (VMF drops duplicates) | et enemy_tweaker.lua:1287 |
| `ConflictDirector.calculate_threat_value` (:2317) | method | `hook_safe` post-adjust of `self.threat_value` + delay flags | et enemy_tweaker.lua:2006 |
| `ConflictDirector.update_horde_pacing` / `horde_killed` / `update_mini_patrol` / `update` (:890/:1022/:1377/:1430) | method | full wrapper for timer scaling; always fall through to vanilla | et enemy_tweaker.lua:1897-1976 |
| `ConflictDirector.start_terror_event` (:1055) | method | full wrapper; returns the mixer id | ct _ct_combat_hooks.lua:374 |
| `ConflictDirector.set_threat_value(breed_name, value)` (:2313) | API, not hook | seed threat for mod-added breeds (the `threat_values` upvalue is boot-frozen, :2295-2303). Note vanilla body ignores `self` - callable dot or colon | et _et_skaven_warlord_breed.lua:151-161 |
| `optional_data.prepare_func` / `spawned_func` / `despawned_func` | data callback | attach to `optional_data` when YOU enqueue a spawn - engine calls them at :2003, :2105, :2262. Cleanest per-spawn seam, no hook at all | available, underused |
| `ConflictDirector.set_breed_override_lookup` (:3331) + `AIInterestPointSystem.set_breed_override_lookup` (ai_interest_point_system.lua:841) | API | roamer breed substitution the way `mutator_elite_run` does it (mutator_elite_run.lua:19-20) | not used by us |
| `Pacing.update` (pacing.lua:175) | method | `hook_safe` post-scale of `total_intensity` (runs 1/s) | et enemy_tweaker.lua:2031 |
| `SpecialsPacing.setup_functions[...]` / `select_breed_functions[...]` (specials_pacing.lua:75/:122) | STATIC dispatch tables | table-form hook, NO self: dot-dispatched at specials_pacing.lua:63/:101 | et enemy_tweaker.lua:2365/2399 (correct, via `_hook_wrap_table`) |
| `HordeSpawner.compose_blob_horde_spawn_list` / `spawn_horde` / `spawn_unit` (horde_spawner.lua:241/…/1228) | method | full wrapper; keep `loaded_probs` intact when touching compositions | et enemy_tweaker.lua:1468/1626/1554 |
| `TerrorEventMixer.start_event` (terror_event_mixer.lua:1757) | STATIC (dot-called at :1898) | hook WITHOUT self | ct _ct_combat_hooks.lua:491 (correct) |
| `TerrorEventMixer.init_functions[...]` / `run_functions[...]` (:65/:624) | STATIC dispatch tables | table-form hook, no self; args `(event, element, t[, dt])` | ct _ct_combat_hooks.lua:297 |
| `MutatorHandler.initialize_mutators` (mutator_handler.lua:85) | method | `hook_safe` AFTER: every `server.initialize_function` has run, so breed-table writes have landed - the place to repair data holes | ct chaos_wastes_tweaker_dev.lua:3264 (470 backfill) |
| `MutatorHandler._activate_mutator` (:652) | method | full wrapper. Fires on host (activate_mutators) AND on every client (rpc receiver :771-783) - the single chokepoint for both peers. Early-return only for symmetric, host-synced conditions | ct chaos_wastes_tweaker_dev.lua:3220 (host-synced `effective_setting`, :2329-2335); evt _evt_cursed_adventure.lua:93 (package preload) |
| `MutatorHandler.conflict_director_updated_settings` (:567) | method | `hook_safe` AFTER: sanitize what `update_conflict_settings` wrote into `Current*`, still before `ConflictDirector.init:219` reads it | evt _evt_guard386_pacing.lua:119 |
| `MutatorHandler.tweak_pack_spawning_settings` (:748) | **STATIC** (dot-called, main_path_spawning_generator.lua:327) | hook WITHOUT self; 4 args exactly | ct chaos_wastes_tweaker_dev.lua:5300 - **currently WRONG, has self** (see 4.5) |
| `MutatorTemplates[name]` dispatch fields (`template.server.*`, `template.update_conflict_settings`, `template.tweak_pack_spawning_settings`) | data | wrap the FOLDED field in place, idempotently (mark the template). Never touch `template.server_start_function` etc. - dead after folding (mutator_templates.lua:238-545) | evt _evt_guard455_boss_events.lua:66-87 |
| `BackendInterfaceLiveEventsPlayfab.get_special_events` / `get_active_events`, `BackendManagerPlayFab.get_level_variation_data` | method | the mutator INJECTION seam: `get_special_events` feeds `GameModeBase.append_live_event_mutators` (game_mode_base.lua:257-282) which appends/overrides the mission mutator list before `MutatorHandler:new` | evt _evt_backend_hooks.lua:32/85/114 |
| Events `"ai_unit_spawned"` / `"ai_unit_despawned"` / `"on_unit_killed"` (conflict_director.lua:2090/:2290/:2368) | event manager | `Managers.state.event:register` - zero-hook observation of spawn lifecycle | available |
| `DeusRunController.get_run_difficulty`, `DeusMechanism.get_current_node_curse` / `_transition_next_node` / `start_next_round` | method | full wrappers; keep results deterministic across peers (host-synced settings only) | ct chaos_wastes_tweaker_dev.lua:2399/3296/3310/3348 |

Known traps for every seam: VMF drops the second hook on the same (class, method) pair
(BUG_CLASSES.md section 1); wrappers collapse multi-returns (section 2 - spawn functions return
`unit, go_id`, conflict_director.lua:2026); an early-return guard that skips vanilla diverges
host/client state (section 26 / memory `reference_vt2_guard_that_delegates_still_crashes`).

---

## 4. Traps and crash classes

### 4.1 Scalar pacing writes crash `ConflictDirector.init` (issue 386)

Some vanilla mutators' `update_conflict_settings` write PLAIN NUMBERS into
`CurrentPacing.delay_horde_threat_value` / `delay_specials_threat_value` /
`delay_mini_patrol_threat_value` - canonical writer `mutator_high_intensity.lua:12-14` (`= 200`).
Dispatch happens inside `refresh_conflict_director_patches` (conflict_director.lua:885-887), which
`init` calls at :94 BEFORE reading those fields at :219-221 and feeding each to
`DifficultyTweak.converters.tweaked_delay_threat_value` - which ALWAYS indexes its arg as a
name-keyed table (difficulty_tweak.lua:5-15, :91-93). Scalar -> "attempt to index a number value"
-> director dead, zero AI all mission. Vanilla Adventure never lists these mutators; evt's
injection is what exposes it. Fix shipped: evt sanitizes scalars to `{ normal = v, [diff] = v }` in
a `hook_safe` on `conflict_director_updated_settings` (_evt_guard386_pacing.lua:52-127). Not in
BUG_CLASSES.md; memory `reference_vt2_mutator_scalar_pacing_conflictdirector_crash`.

### 4.2 `boss_events`-indexing mutators on fixed-end-boss levels (issue 455)

`multiple_bosses` (mutator_multiple_bosses.lua:8/:13), `blessing_of_grimnir`
(mutator_blessing_of_grimnir.lua:60) and `deus_pacing_tweak` (mutator_deus_pacing_tweak.lua:482/:498)
index `CurrentBossSettings.boss_events` with no nil check [line numbers per evt banner,
_evt_guard455_boss_events.lua:3-15]. `CurrentBossSettings` is rebuilt per level from the director's
`boss` block (conflict_director.lua:879); fixed-end-boss levels (warcamp) ship a boss block WITHOUT
`boss_events` -> host fatal at initialize (mutator_handler.lua:644-645), update_conflict_settings
dispatch (:578-579), or start. Fix shipped: evt wraps the folded dispatch fields with a
presence-gated no-op (_evt_guard455_boss_events.lua:37-87). Not in BUG_CLASSES.md.

### 4.3 Per-rank data hole -> mid-extension-add CTD (issue 470, "rank hole")

`mutator_curse_skulking_sorcerer.lua` defines broken rank constants - `CATACLYSM = 6`,
`CATACLYSM_2 = 6` (duplicate key), `CATACLYSM_3 = 7` (:9-11) - so the `MAX_HEALTH` table it assigns
onto `Breeds.curse_mutator_sorcerer.max_health` at `server_initialize_function` (:19-27, :36) spans
ranks 2..7 with NOTHING at rank 8 (cataclysm_3, difficulty_settings.lua:287). The base breed has a
full 8-entry array (breed_chaos_mutator_sorcerer.lua:58-67); the hole exists only while the curse
is initialized. A curse-sorcerer spawn at rank 8 resolves `max_health[8] = nil`
(conflict_director.lua:1947-1948), `GenericHealthExtension.init` throws mid extension-add, and the
half-initialized hit_reaction extension nil-derefs on the next update = host CTD
(generic_hit_reaction_extension.lua:230 per issue 470 log). Vanilla CW never reaches rank 8; ct's
`progressive_difficulty` does (chaos_wastes_tweaker_dev.lua:2364-2413). Fatshark guarded the
sibling `RESPAWN_TIME` read with `or RESPAWN_TIME[NORMAL]` (:43) but not MAX_HEALTH. Fix shipped:
ct backfills `[8] = 150` in a `hook_safe` on `MutatorHandler.initialize_mutators`
(chaos_wastes_tweaker_dev.lua:3250-3270). General rule: ANY rank-keyed table a mod pushes onto a
breed must cover ranks 2..8 (9 if versus matters), or carry an `or` fallback. Not in BUG_CLASSES.md.

### 4.4 `no_roamers` on directors without `difficulty_overrides`

`mutator_no_roamers.tweak_pack_spawning_settings` does
`pairs(pack_spawning_settings.difficulty_overrides)` (mutator_no_roamers.lua:5-6 area). Adventure
directors (`chaos_light` etc.) lack the field -> `pairs(nil)` host fatal when CW zone sequencing
(mutator_deus_pacing_tweak.lua:37-38/:60-62) injects `no_roamers` on a level using an
adventure-derived director (ct crash guids 004768e7, 4c84c68a). ct strips the name in a
`tweak_pack_spawning_settings` hook (chaos_wastes_tweaker_dev.lua:5300-5341) - but see 4.5: the
strip currently misses the zone list.

### 4.5 Static-vs-method hook arity (dot-called engine functions)

`MutatorHandler.tweak_pack_spawning_settings` is STATIC - defined `function (zone_mutator_list,
mutator_list, conflict_director_name, pack_spawning_settings)` (mutator_handler.lua:748) and
dot-called with exactly 4 args (main_path_spawning_generator.lua:327). Same for
`TerrorEventMixer.start_event` (dot-called, terror_event_mixer.lua:1898) and the
`SpecialsPacing.setup_functions` / `select_breed_functions` / `TerrorEventMixer.init_functions` /
`run_functions` dispatch tables. VMF does not inject `self`; a hook written
`function(func, self, a, b, ...)` on a static seam binds `self = first real arg` and shifts
everything else by one - guards silently test the wrong values (nil predicates read as
always-true/false) while a symmetric pass-through call happens to forward correctly, so the bug is
invisible until the guarded case fires. Live instance: ct's no_roamers strip (see 5, candidate 1).
Related BUG_CLASSES: none yet (candidate for a new entry); closest is section 1b (silent dead hook).

### 4.6 Other conflict-stack traps (with BUG_CLASSES / memory cross-refs)

- **Mutator `server_*_function` raw fields are dead after boot folding** (mutator_templates.lua:238-545).
  Wrap `template.server.start_function` / `template.update_conflict_settings`, never the raw field.
  (Monorepo CLAUDE.md "Hooks that silently no-op".)
- **`threat_values` boot-frozen upvalue** (conflict_director.lua:2295-2303): mod-added breeds crash
  `calculate_threat_value` (`nil * amount`, :2323) unless seeded via `set_threat_value` (:2313).
  Also `reset_queued_spawn_by_breed` / `_reset_spawned_by_breed` iterate `pairs(Breeds)` at init
  (:296-322) - register breeds BEFORE mission start, never mid-mission.
- **`loaded_probs` invariant**: replacing a composition table without rebuilding
  `loaded_probs = { LoadedDice.create(weights) }` crashes the next horde roll
  (horde_spawner.lua:139/243/349/743; built at conflict_settings.lua:72-77/:636-641). et rebuilds
  via `_build_loaded_probs` (enemy_tweaker.lua:655-663).
- **`Current*` globals are per-refresh clones**: `CurrentHordeSettings.compositions_pacing` is a
  deep clone of `HordeCompositionsPacing` taken at conflict_director.lua:881 - mutating the global
  mid-mission does nothing until the next refresh, and mutating the clone is lost at the next zone
  boundary. Re-apply in a `refresh_conflict_director_patches` post-hook (et pattern,
  enemy_tweaker.lua:1209-1226, :849-868).
- **`BreedPacksBySize` holes**: `EnemyRecycler` does an unguarded
  `BreedPacksBySize[pack_type][amount]` (enemy_recycler.lua:286); packs exist only at canonical
  sizes, so writing arbitrary sizes into `SizeOfInterestPoint` CTDs (et crash
  adbe4524-971a-476f-b17d-41b8b6b20940; snap fix enemy_tweaker.lua:983-1025).
- **Package-bearing mutators are Deus-only** (deus_run_state.lua:438-453): preload `packages`
  in a `_activate_mutator` wrapper on BOTH peers before running them in Adventure
  (evt _evt_cursed_adventure.lua:93-141; memory `reference_vt2_mutator_packages_deus_only`).
- **Journey-stat cataclysm ceiling** (issue 291): `StatisticsUtil._register_completed_journey_difficulty`
  `table.find`s the difficulty in `DefaultDifficulties` (stops at cataclysm,
  difficulty_settings.lua:412-418) then compares with the nil result -> CTD at cata_2/3. Clamp only
  the RECORDED difficulty (ct chaos_wastes_tweaker_dev.lua:2442-2453; memory
  `reference_vt2_journey_stat_cataclysm_ceiling_crash`).
- **Zone mutator churn**: `check_update_mutators` DEACTIVATES mutators that leave the zone list and
  initializes+activates newcomers every zone boundary (conflict_director.lua:795-842) - any
  once-only assumption in a wrapped `start_function` must be idempotent.
- **Networked activation symmetry**: `_activate_mutator` runs on clients via RPC
  (mutator_handler.lua:771-783). Gating it on a LOCAL setting desyncs peers; gate only on
  host-synced state (ct's `is_curse_disabled` uses `effective_setting`,
  chaos_wastes_tweaker_dev.lua:2324-2335). Cross-ref BUG_CLASSES.md section 9 (RPC schema
  divergence) and the issue 371 wire-safety doctrine (memory
  `reference_vt2_wire_safety_never_toggle_gated`).
- **`event_delay_pacing` re-enables specials with a hard delay** (conflict_director.lua:2393-2401):
  toggling terror-event delay off calls `specials_pacing:delay_spawning(t, 10, 15)` - mods driving
  this event get a built-in specials cooldown they did not ask for.

---

## 5. Implications for our mods

Concrete, ranked. P0 = crash-guard defect, P1 = fights the engine with real risk, P2 = simplification.

1. **P0 - ct no_roamers strip has the static-hook arity bug and misses the zone list.**
   `chaos_wastes_tweaker_dev.lua:5300` hooks the STATIC `MutatorHandler.tweak_pack_spawning_settings`
   with a `self` parameter. At the only call site (main_path_spawning_generator.lua:327, 4 args,
   dot call) the binding shifts: `self` = real zone_mutator_list, ..., `pack_spawning_settings` =
   nil. Consequences: (a) the "keyed off the crash predicate" check
   (`pack_spawning_settings.difficulty_overrides == nil`, :5318) always sees nil -> always takes
   the strip path, so the predicate is decorative; (b) the forward call
   `func(self, filter(zone_mutator_list), filter(mutator_list), ...)` (:5340) filters the SESSION
   mutator list but passes the real ZONE list through `self` UNFILTERED - and `no_roamers` only
   ever arrives via zone mutators (mutator_deus_pacing_tweak.lua:37-38/:60-62), which vanilla runs
   at mutator_handler.lua:766. The Belakor `pairs(nil)` crash (guid 4c84c68a) this v0.7.231 rework
   targets can still fire. Fix: drop `self`, take exactly `(func, zone_mutator_list, mutator_list,
   conflict_director_name, pack_spawning_settings)`, filter BOTH lists, and keep the
   difficulty_overrides predicate (it becomes meaningful again). Add a BUG_CLASSES entry for 4.5.

2. **P1 - et roaming density: replace `SizeOfInterestPoint` mutation with the engine's pack-spawning seam.**
   et scales roaming by mutating the global `SizeOfInterestPoint` and snapping to canonical pack
   sizes to dodge the `BreedPacksBySize` hole (enemy_tweaker.lua:983-1033), which plateaus at size 8.
   The engine's own "more/fewer roamers" lever is a template `tweak_pack_spawning_settings` using
   `MutatorUtils.tweak_pack_spawning_settings_density_multiplier` (mutator_utils.lua:170; used by
   `mutator_deus_more_roamers.lua:10-12`), folded per zone at main_path_spawning_generator.lua:327.
   Registering a tiny et MutatorTemplate (no NetworkLookup needs - `tweak_pack_spawning_settings`
   runs off the INITIALIZED list, host-side, mutator_handler.lua:748-769) and injecting it through
   evt-style list injection scales density continuously, per-zone, with zero
   `BreedPacksBySize` risk. Impact: removes the snap workaround + the plateau, deletes a global
   backup/restore pair.

3. **P2 - et spawn-pace scaling duplicates vanilla flag logic; use thresholds or per-breed threat.**
   `enemy_tweaker.lua:2006-2023` re-derives `delay_horde`/`delay_mini_patrol`/`delay_specials`
   after scaling `threat_value`, mirroring conflict_director.lua:2327-2329 (drift risk if vanilla
   adds a flag - e.g. `check_pacing_event_delay` :2334 already runs after). Engine-idiomatic:
   scale the CONVERTED thresholds once per `ConflictDirector.init`/`refresh` post-hook (the mod
   already owns both hooks, :1173/:1209) - divide `self.delay_*_threat_value` by the multiplier -
   or scale per-breed inputs via `set_threat_value` (:2313). Same for the `Pacing.update` intensity
   post-scale (enemy_tweaker.lua:2031-2047): scaling `CurrentPacing.peak_intensity_threshold` /
   `peak_fade_threshold` at refresh time is the same lever vanilla's own difficulty system uses
   (`pacing_overrides.peak_intensity_threshold`, difficulty_settings.lua:77-79) with two fewer
   per-second hooks.

4. **P2 - et horde preset swap still mutates the boot globals; target the live clone for everything.**
   The preset SWAP mutates `HordeCompositionsPacing` globally with a backup/restore dance
   (enemy_tweaker.lua:598-618, :665-675) while SIZE scaling already moved to the per-refresh clone
   `CurrentHordeSettings.compositions_pacing` (:849-868) precisely because the engine deep-clones at
   conflict_director.lua:881. Applying the preset variants to the clone in the same refresh hook
   (rebuilding `loaded_probs` as now) makes the globals read-only, kills the restore path, and
   removes the BUG_CLASSES section 7 unwind obligation for this feature.

5. **P2 - et monster/elite swap could ride vanilla's own substitution seam for roamers.**
   The consolidated `spawn_queued_unit` wrapper (enemy_tweaker.lua:1287-1343) is correct for
   event/boss spawns, but the roaming-elite half re-implements what
   `set_breed_override_lookup` + `AIInterestPointSystem.set_breed_override_lookup` already provide
   (conflict_director.lua:3331, ai_interest_point_system.lua:841; pattern: mutator_elite_run.lua:19-20).
   The engine seam handles interest-point roamers with chance tables and no per-spawn hook cost.
   Keep the wrapper for monsters (terror-event path), move roamer substitution to the lookup.
   Verify the lookup covers `EnemyRecycler` packs, not only interest points, before switching [unverified].

6. **P2 - evt cursed-adventure + guards are the model; document them as the canonical mutator-wrap pattern.**
   The three shipped evt patterns compose the safe recipe for anything that injects vanilla
   mutators: (a) single injection chokepoint with per-name gates (`gather_mutators` add(),
   _evt_selection.lua:181-234), (b) idempotent in-place wrapping of FOLDED template dispatch fields
   with a marker (`__et455_guarded`, _evt_guard455_boss_events.lua:66-87), (c) post-dispatch
   sanitizer on `conflict_director_updated_settings` (_evt_guard386_pacing.lua:119-127), (d)
   `_activate_mutator` package preload mirrored on host and client (_evt_cursed_adventure.lua:93-141).
   ct's curse-disable gate (chaos_wastes_tweaker_dev.lua:3220) and 470 backfill (:3264) follow the
   same shape. Any future mod touching MutatorTemplates should copy these, not invent new seams.

7. **P2 - ct progressive difficulty: sweep remaining rank-8 consumers.**
   ct's ramp makes rank 8 reachable where vanilla CW never goes (chaos_wastes_tweaker_dev.lua:2364-2413).
   The 2026-07-11 sweep covered `scripts/settings/mutators/*` (:3243-3246) and the journey recorder
   (#291); per-rank arrays elsewhere (BreedTweaks arrays are 9-wide, breed_tweaks.lua:7-17, safe)
   and `nearest_table_value`-style rank tables in DLC content have not been exhaustively audited
   [unverified]. Any new "reach cata_3 in CW" feature should grep for `[CATACLYSM_3]`-style local
   rank constants and `get_difficulty_rank()` table indexing first.
