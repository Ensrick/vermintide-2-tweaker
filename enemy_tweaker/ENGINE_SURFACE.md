# enemy_tweaker - engine contact surface

What vanilla VT2/Stingray does at every seam `enemy_tweaker` (`et`) touches, and
why the mod is there. This is the per-mod companion to the subsystem set in
`docs/engine/` (read `docs/engine/README.md` for house style). It does **not**
re-explain a subsystem the engine docs own, and it does **not** duplicate the
mod's own `DEVELOPMENT.md` (module map, the breed-adding checklist, the removed
skeleton-breed history) - it names each engine seam, cites the vanilla behavior,
and links out. Decompile paths are relative to
`C:\Users\danjo\source\repos\Vermintide-2-Source-Code`; `et` line numbers name
their `_et_*` module. `§N` = a `docs/BUG_CLASSES.md` class; `#N` / "issue N" = a
GitHub issue. Grep-verified 2026-07-12 against the decompile.

`et` rewrites the AI spawn pipeline in place: it patches the difficulty-scaled
spawn/pacing/roaming/specials settings the ConflictDirector reads, substitutes
breeds and factions in hordes, scales counts, and adds one wholly new breed (the
Skaven Warlord, issue 324). Almost every seam it touches lives under
`docs/engine/07` (conflict director + mutators). It is a host-required mod - the
spawn decisions are server-authoritative - with two exceptions that reach every
peer: the mod-added breed (its NetworkLookup entries must exist on every peer) and
the global `table.clone` shim.

## Hook table

26 LIVE registration sites, grouped into 7 rows-of-concern. Almost all route
through the mod's own protective factories in `_et_protect.lua`:
`_hook_wrap` = `mod:hook` body wrapped in pcall with a vanilla-fallback on inner
error; `_hook_wrap_table` = the same for a plain dispatcher table (table-form);
`_hook_wrap_tick` = the issue-479 variant that SKIPS the tick on inner error and
NEVER re-runs vanilla. Legend below: `[wrap]` / `[wrap,tbl]` / `[tick]` name the
factory; `[safe]` / `[hook]` are direct `mod:hook_safe` / `mod:hook`; `[tbl]` marks
a class/table passed by reference. `tools/mod-lint/lint-mod.ps1` enforces one hook
per (Class, method) ACROSS the 17 active modules. The retired Big Rebalance module
and its three dormant hook registrations were deleted under #433, so they are not
part of the count or table.

### Conflict-director lifecycle re-apply (owner doc: `docs/engine/07`)

| Class.method (kind) | Vanilla behavior at the seam | Why et hooks it | Trap / invariant |
|---|---|---|---|
| `ConflictDirector.init` [wrap] `_et_director_hooks.lua:33` | Constructs the director for a level; builds `CurrentHordeSettings` and the difficulty-patched Current* setting tables [src: `scripts/managers/conflict_director/conflict_director.lua:72`] | Re-apply every et override (horde preset, breed/faction swap, champion retune, difficulty mimic, size multipliers) once the director has (re)built the tables (`:33`) | Must run AFTER `func` - the Current* tables don't exist until init returns. Idempotent (each `_apply_*` re-reads settings) |
| `ConflictDirector.refresh_conflict_director_patches` [wrap] `_et_director_hooks.lua:69` | Runs on every active-director change (per-zone `override_conflict_setting`, mid-mission switches); rebuilds `CurrentHordeSettings = table.clone(director.horde)`, discarding any prior in-place rewrites [src: `conflict_director.lua:869`] | Re-apply difficulty-mimic (replaces Current* tables) then faction-swap + size (mutate in place) after each rebuild, else Athel-Yenlui-style zone switches revert to vanilla mid-mission (`:69`) | Order matters: mimic first (replaces tables), swaps second (mutate in place). Logs the trigger for `/et_verify_refresh` |

### Spawn-pacing tick (per-frame; issue 479 crash history) (owner doc: `docs/engine/07`)

| Class.method (kind) | Vanilla behavior | Why et hooks it | Trap / invariant |
|---|---|---|---|
| `ConflictDirector.update` [tick] `_et_pacing.lua` | The master AI tick: runs horde pacing, mini-patrol, specials; its spawn-queue bookkeeping (`update_spawn_queue`, decrements) runs AFTER the spawn call [src: `conflict_director.lua:1430`; queue bookkeeping `:1835-1891`] | Temporarily override `RecycleSettings.max_grunts`, restoring on every path; recover the exact malformed main-path terror-event loop from #479 | ROW OF CONCERN. Registered via `_hook_wrap_tick`, NOT `_hook_wrap`. Fault output is one first-fault plus one recovery summary. For `terror_event_mixer.lua:1800` only, remove the partial event and advance the recycler index exactly as vanilla would after `start_event`; quarantine ET pacing overrides for the session. Unknown failures are skipped without guessed mutation |
| `ConflictDirector.update_horde_pacing` [wrap] `_et_pacing.lua:87` | Runs the paced-horde frequency decision, reading `RecycleSettings.push_horde_if_num_alive_grunts_above` and `CurrentPacing.horde_frequency` [src: `conflict_director.lua:890`] | Override push threshold + frequency tuple around the call, restore after (`:87`) | Save/restore both together; vanilla writes new tables so a shallow ref for restore is safe |
| `ConflictDirector.horde_killed` [wrap] `_et_pacing.lua:117` | Recomputes the next horde schedule when a horde dies [src: `conflict_director.lua:1022`] | Same `horde_frequency` override here or the frequency slider has no effect after the first horde (`:117`) | Distinct method from `update_horde_pacing` - separate (Class, method) pair |
| `ConflictDirector.update_mini_patrol` [wrap] `_et_pacing.lua:140` | Ambient mini-patrol spawn pass, gated on intensity + grunt cap [src: `conflict_director.lua:1377`] | Raise the intensity gate and grunt cap to infinity for the call when `ambients_ignore_threat` is on, then restore (`:140`) | Both gates must move together or the inner cap check still bails |
| `ConflictDirector.handle_alone_player` [wrap] `_et_pacing.lua:202` | The rush intervention (rushing-special + ambush horde for a lone player); unlike hordes and speed-run specials it has NO freeze gate in its body [src: `conflict_director.lua:1250`] | VANILLA-BUG fix (issue 449): stand it down while `pacing:get_state() == "pacing_frozen"` so it can't spawn enemies during a frozen cutscene (e.g. The Enchanter's Lair), matching its two vanilla siblings (`:202`) | UNCONDITIONAL (vanilla-bug class, host-side spawn decision). Caller retries every ~1s, so the `[et:449]` line logs once per freeze episode. Writes the same `data.disabled` debug-reason field vanilla uses |
| `ConflictDirector.calculate_threat_value` [safe,tbl] `_et_pacing.lua:170` | Writes `self.threat_value` from the per-breed `threat_values` upvalue built ONCE at file-load by walking `pairs(Breeds)`; the `delay_*_threat_value` thresholds gate spawns off it [src: `conflict_director.lua:2317`; upvalue `local threat_values = {}` `:2295`] | `hook_safe` multiply `threat_value` by `spawn_pace_multiplier` and recompute the delay flags so thresholds trip sooner/later (`:170`) | ROW OF CONCERN. Table-form (`ConflictDirector` by ref). The upvalue built at boot is the mod-added-breed crash class: a breed added after boot has no `threat_values` entry -> `nil * amount` fatal (§ breed threat_values; see dead ends) - which is why the Warlord registers its value via the static `set_threat_value` at breed-add, NOT here |
| `Pacing.update` [safe,tbl] `_et_pacing.lua:254` | Maintains per-player + total intensity that feeds spawn-rate decisions [src: `scripts/managers/conflict_director/pacing.lua:175`] | `hook_safe` scale `player_intensity[k]` and `total_intensity` by `spawn_pace_multiplier` after vanilla writes them (`:254`) | Per-frame row. Table-form (`Pacing` by ref); type-guard every field before multiplying |

### Horde composition + breed substitution (owner doc: `docs/engine/07`)

| Class.method (kind) | Vanilla behavior | Why et hooks it | Trap / invariant |
|---|---|---|---|
| `HordeSpawner.compose_blob_horde_spawn_list` [wrap] `_et_swaps.lua:164` | Builds a blob horde's spawn list from `CurrentHordeSettings.compositions_pacing[composition_type]`; returns `(spawn_list, num_to_spawn)` [src: `scripts/managers/conflict_director/horde_spawner.lua:241`] | Apply the breed-swap map to the list AND, when inside an event-driven compose, replicate/trim entries to hit the event-size multiplier (`:164`) | ROW OF CONCERN. `compose*` MULTI-RETURN is the origin of § 2 (multi-return collapse, et v0.2.4) - capture both returns. Event replication EXCLUDES `breed.boss` breeds: two boss instances in one frame race their BT init and crash on `current_health_percent = nil` (Drachenfels 3x crash, dlc_castle_slaanesh). First arg is a STRING key, not a composition table (F16) |
| `HordeSpawner.spawn_unit` [wrap] `_et_swaps.lua:250` | Spawns one unit of `breed_name` for a horde; ambush breed names live in file-local upvalues popped per-spawn, so this is the only reliable substitution site [src: `horde_spawner.lua` spawn_unit] | Substitute the per-unit breed via the swap map (guard `Breeds[replacement]` exists) (`:250`) | Only swap when the replacement breed actually exists in `Breeds` |
| `SpawnerSystem.spawn_horde_from_terror_event_ids` [wrap] `_et_event_size.lua:30` | Spawns a terror-event horde (the majority of visible adventure hordes) [src: `scripts/entity_system/systems/spawner/spawner_system.lua:389`] | Stash the event-size multiplier on `mod._et_event_breed_scale` so the inner `compose_blob` hook scales the list; suppress entirely at mult 0 (`:30`) | Capped at 5x (clamps a stale saved value). pcall + finally clears the flag so a vanilla throw can't leak it into the next (paced) compose call |
| `HordeSpawner.spawn_horde` [wrap] `_et_event_size.lua:72` | Entry point for an event-triggered horde [src: `horde_spawner.lua` spawn_horde] | Debug breadcrumb ONLY (composition/horde type + active event scale) - no behavior change (`:72`) | Pure instrumentation; always-on in dev per the diagnostics doctrine |

### Specials pacing - table-form dispatcher hooks (owner doc: `docs/engine/07`)

| Class.method (kind) | Vanilla behavior | Why et hooks it | Trap / invariant |
|---|---|---|---|
| `SpecialsPacing.setup_functions["specials_by_slots"]` [wrap,tbl] `_et_specials.lua:71` | The setup-time slot method; reads `CurrentSpecialsSettings.breeds` / `.max_specials` [src: `scripts/managers/conflict_director/specials_pacing.lua:75` (the `setup_functions` table)] | Override `max_specials` and filter `breeds` by the per-difficulty per-special disable toggles for the call, then restore (`:71`) | Table-form on the `setup_functions` DISPATCHER table (a plain method table). On inner error, restore settings and fall through to vanilla (never rethrow - a stack trace kicks the session, § 4.1) |
| `SpecialsPacing.select_breed_functions["get_random_breed"]` [wrap,tbl] `_et_specials.lua:105` | The per-pick breed selector [src: `specials_pacing.lua:122` (the `select_breed_functions` table)] | Weighted selection + per-breed disable over the enabled pool; preserve vanilla's coordinated-attack `override_breed_name` (`:105`) | Table-form. Must pass through when `state_data.override_breed_name` is set, or coordinated attacks break |

### Completed AI spawn observation (#452/#531)

| Class.method (kind) | Vanilla behavior | Why et hooks it | Trap / invariant |
|---|---|---|---|
| `ConflictDirector._post_spawn_unit` [safe] `_et_boss_grudge.lua` | Completes one AI spawn after unit, breed, and game-object setup [src: `scripts/managers/conflict_director/conflict_director.lua:2029`] | One host-authoritative branch applies enabled Cata+ boss grudge buffs. A read-only branch observes each of five ordinary special breeds for #452 skeleton compatibility. Another samples at most two distinct breeds in each modifier category for #453 extension/state/banned-modifier readiness. | This is the single owner of the `(ConflictDirector, _post_spawn_unit)` pair. Both diagnostic callbacks remain mutation-free: no attachment/buff/attribute/spawn/RPC. #452 caps at five rows/eight missing nodes; #453 caps at eight rows. |

### Roaming density + patrol + the global clone shim (owner docs: `docs/engine/07`, `docs/engine/01`)

| Class.method (kind) | Vanilla behavior | Why et hooks it | Trap / invariant |
|---|---|---|---|
| `table.clone` [hook, GLOBAL] `_et_roaming.lua:272` | Foundation deep-clone; `skip_metatable` defaults nil [src: `foundation/scripts/util/table.lua`, `[unverified]` exact line] | Force `skip_metatable = true` on EVERY clone engine-wide (SpawnTweaks port) so the deep pack-member clone loop survives 15x roaming scaling without OOM (`:272`) | ROW OF CONCERN - broadest blast radius in the mod: it rewrites a foundation primitive for the whole game. Justified because callers passing no `skip_metatable` already accepted the nil default (which the engine treats as no metatable copy); SpawnTweaks has shipped it for years. Installed BEFORE the `spawn_amount_rats` hook |
| `EnemyRecycler.inject_roaming_patrol` [wrap] `_et_roaming.lua:166` | Injects a roaming pack sized by `SizeOfInterestPoint[ip]` via `BreedPacksBySize[pack_type][amount]` [src: `scripts/managers/conflict_director/enemy_recycler.lua:262`; crash site `:286`] | et raises `SizeOfInterestPoint` for bigger packs; pre-check `BreedPacksBySize` has a roster for the `(pack_type, amount)` pair and BAIL before vanilla if not, so the missing-roster crash never reaches `:286` (`:166`) | Roster table only has canonical sizes {1,2,3,4,6,8}, so IP-driven pack size plateaus at 8 - the ambient layer below is what scales past that |
| `SpawnZoneBaker.spawn_amount_rats` [wrap] `_et_roaming.lua:277` | Places loose ambient units per zone at map-bake time [src: `scripts/managers/conflict_director/spawn_zone_baker.lua:698`] | Scale `num_wanted_rats` by `roaming_size_multiplier` for MORE PACKS (uncapped, unlike the plateaued IP layer); suppress at mult 0 (`:277`) | ROW OF CONCERN - deep-clones pack members; needs the `table.clone` shim above to reach 15x without OOM (cap constant kept as a regression net) |
| `SpawnZoneBaker.inject_special_packs` [wrap] `_et_roaming.lua:232` | Overrides zone pack types across a cycle; an unchecked inner loop `for k = zone_index, zone_index + period_length - 1` overruns `cycle_zones` on small Deus cycles [src: `spawn_zone_baker.lua:505`] | CRASH GUARD only: pcall vanilla inside the body so an overrun falls to log-and-skip (zones keep their level-bake defaults) instead of a level-load fatal (`:232`) | pcall vanilla HERE (not via the wrap fallback) so a throw doesn't re-invoke and re-crash. Hit on Deus + cataclysm-mimic small-cycle DLC levels |
| `AIGroupSystem.create_formation_data` [wrap] `_et_patrol.lua:35` | Builds a patrol's formation rows; iterates `formation` as `for row, columns in ipairs(formation)` and places each along the spline [src: `scripts/entity_system/systems/ai/ai_group_system.lua:816`, iterate `:861`] | Replicate rows to scale patrol size by `patrol_size_multiplier`; suppress at mult 0 (`:35`) | Bind args BY POSITION: a prior version bound the 2nd positional as the group ext and replicated `spline_name` (a STRING), so patrol scaling silently never ran. HARD 14-row cap: rows past the spline/navmesh end get a nil `spawn_pos` -> malformed off-mesh member -> `POSITION_LOOKUP` crash in the patrol update (v0.7.13-dev) |

### Mod-added breed (Skaven Warlord, issue 324) + banner (owner docs: `docs/engine/03`, `04`, `07`, `10`)

| Class.method (kind) | Vanilla behavior | Why et hooks it | Trap / invariant |
|---|---|---|---|
| `ConflictDirector.spawn_queued_unit` [wrap] `_et_champion_warlord.lua:176` | Server-authoritative breed spawn from the queue [src: `conflict_director.lua:1732`] | SINGLE consolidated hook for two disjoint substitutions: eligible monster -> Skaven Warlord, and roaming elite -> Champion (`:176`) | ROW OF CONCERN. Host-only substitution (`Managers.player.is_server`) so the breed replicates normally - but the mod-added breed's `NetworkLookup` entries only exist on et peers, so EVERY peer must run et (wire safety, `docs/engine/03`). Consolidated per the one-hook-per-pair rule |
| `BTSpawnAllies.find_spawn_point` [wrap,tbl] `_et_champion_warlord.lua:308` | The Warlord's call-allies BT node resolves a spawner group and `_spawn` derefs `data.spawners` [src: `scripts/entity_system/systems/behaviour/nodes/bt_spawn_allies_action.lua:175`] | CRASH GUARD: off its home arena the spawner group is absent; nil `blackboard.spawning_allies` so the node returns "done" before `_spawn`'s `#spawners` modulo-crash, giving the Warlord a wind-up but no reinforcements (`:308`) | Table-form (`BTSpawnAllies` by ref). Only diverts when the group is genuinely absent AND no fallback-spawner escape exists; uses `POSITION_LOOKUP`/`Unit.world_position` with `Vector3Box` for the stored position |
| `_G.Localize` [hook] `_et_skaven_warlord_breed.lua:377` | Global loc-key -> string lookup; the boss health-UI and the grudge-name list read it [src: `boss_health_ui.lua:174`, `terror_event_utils.lua:75`] | et's ONLY `_G.Localize` hook: supply the Warlord display name + 12 grudge names (`:377`) | One `_G.Localize` hook only - a second silently shadows (CLAUDE.md NON-NEGOTIABLE 8). VMF `_localization.lua` is not in global `Localize`, so vanilla-visible strings must come through here |
| `BreedFreezer.try_mark_unit_for_freeze` [wrap] `_et_pacing.lua:305` | Queues a unit for deferred freeze; the actual freeze is deferred to `commit_freezes` [src: `scripts/managers/conflict_director/breed_freezer.lua:232`; vanilla error `:253`] | Issue 213 guard: with et's raised `max_grunts`, `deactivate_area -> destroy_unit` can re-mark the same unit same-frame, and vanilla prints "freeze unit twice" AND falls through to a conflicting `mark_for_deletion`. Replicate vanilla's own dup-check first and return true to suppress (`:305`) | ROW OF CONCERN (`docs/engine/04`). Reads vanilla's own `units_to_freeze[breed]` - the exact state vanilla checks, same lifecycle - so no frame/pool guesswork. Fail-open: any missing state falls through to vanilla |
| `BeastmenStandardHealthExtension.add_damage` [wrap] `_et_banner.lua:128` | Beastmen banner health; `can_damage_banner` gate REJECTS ranged before reaching `super.add_damage` [src: `scripts/unit_extensions/health/beastmen_standard_health_extension.lua:38`] | "Banner breakable by ranged": when on, relay ranged attack types straight to `GenericHealthExtension.add_damage` (what vanilla does for accepted attacks) instead of vanilla's reject (`:128`) | Full 18-param signature verbatim. Off = pure passthrough (no behavior change); on, non-ranged still defers to vanilla to preserve the suicide path + whitelist |
| `GenericHealthExtension.init` [wrap] `_et_health_multiplier.lua` | ConflictDirector has already selected rank-indexed breed health and any spawn modifier before health-extension init | #369 host scales the final hostile-AI health by the active difficulty slider, then tags the extension for bounded live rescaling | Host only; 1.0 is passthrough. Uses vanilla `set_max_health` / `set_server_damage_taken` replication. Includes bosses/lords; excludes pets, critters, and heroes. Shared breed arrays are untouched. |
| `DamageUtils.apply_buffs_to_damage` [hook,tbl] `_et_personal_handicap.lua` | Server-only buff/proc damage chokepoint before network quantization [src: `scripts/helpers/damage_utils.lua:2134`; caller `:1790`] | #61 host adjusts the authenticated human peer's bounded incoming/outgoing base damage, then delegates once so vanilla buffs, conversions, callbacks, and procs observe the same value | Host only. Requires an actual hostile-AI breed on the other side; excludes friendly fire, self/environment damage, bots, and pets. Client sends preset only on context change with three handshake retries; no per-hit RPC, buff, lookup, or shared-table mutation. |

## Subsystem notes (how the vanilla flow runs end-to-end, for et's cases)

Each note is the minimum needed to read the hooks above; `docs/engine/07` and the
mod's `DEVELOPMENT.md` carry the full architecture.

### The ConflictDirector settings pipeline (owner: `docs/engine/07`)

`ConflictDirectors[name]` (`conflict_settings.lua`) bundles `pacing`/`horde`/`boss`/
`specials`/`roaming`/`factions`; a level picks its starting director and per-zone
`override_conflict_setting` switches it mid-mission. On every switch,
`refresh_conflict_director_patches` rebuilds the live `CurrentHordeSettings` as
`table.clone(director.horde)` [src: `conflict_director.lua:869`], which is why et
re-applies its faction/size rewrites there AND at `init` - a single apply at init
would be discarded at the first zone boundary. et deliberately patches only PACED
hordes (`HordeCompositionsPacing`); the ~194-key `HordeCompositions` table drives
terror-event hordes (the majority of visible adventure hordes) and is reached only
through the `compose_blob` / `spawn_horde_from_terror_event_ids` count-scaling path,
not the preset patcher (see the removed-skeletons dead end).

### Mod-added breed = every table that snapshots `pairs(Breeds)` at boot (owner: `docs/engine/04`, `docs/engine/03`)

The single most-burned class in this mod. At least three systems iterate
`pairs(Breeds)` at file-load and never re-scan: `ConflictDirector`'s `threat_values`
upvalue [src: `conflict_director.lua:2295`], `PerformanceManager._activated_per_breed`,
and `StatisticsDefinitions.player.*_per_breed`. A breed added after boot (the Skaven
Warlord) is missing from all three, and each miss is a distinct crash
(`nil * amount` in `calculate_threat_value`, `nil + 1` on first activate, a stats
ferror on first kill). A defensive HOOK is NOT sufficient, because VMF still executes
a disabled mod's module-level code (so `Breeds[name] = ...` sticks) but skips its hook
registrations - so the fix must be UNCONDITIONAL direct writes at the breed-add site
(`ConflictDirector.set_threat_value(nil, name, value)` is callable as a static
method; direct `StatisticsDefinitions.player.*_per_breed` writes; a
`PerformanceManager.init` hook to seed the per-mission table; forward+reverse
`NetworkLookup.breeds`). The full checklist lives in `DEVELOPMENT.md`.

### Protective wrapper factories + the issue-479 tick discipline (owner: `docs/engine/07`)

Every et hook body is bracketed (`PROJECT_STANDARDS` § 4.1): nothing fails silently.
`_hook_wrap` / `_hook_wrap_table` run the body under pcall and fall through to vanilla
on inner error. That fallback is safe ONLY for idempotent targets. `ConflictDirector.update`
is NOT idempotent - its spawn-queue bookkeeping runs after the spawn, so a re-run
re-pops the same queue entry and doubles state (issue 479). Its hook uses
`_hook_wrap_tick`, which on inner error SKIPS the tick (one `[et:479]` printf) and never
re-runs vanilla, and runs vanilla under `_call_with_override` so any engine-global
override (`RecycleSettings.max_grunts`) is restored on both the success and error path.
This is the guard-that-delegates lesson (§ issue 270) applied to a non-re-runnable tick.

## What the engine will NOT let us do (dead ends, already paid for)

Pulled from `DEVELOPMENT.md` and `docs/BUG_CLASSES.md` - do not re-discover these.

- **A hook cannot make a mod-added breed safe, because a disabled mod still runs its
  module code but not its hooks.** The `Breeds[name] = ...` write sticks even when the
  user toggles et off in VMF, and the three boot-snapshot tables then crash with no hook
  in sight. Breed registration side-effects (threat value, stats, NetworkLookup) MUST be
  unconditional direct writes at the breed-add site, not hooks (v0.3.3->0.3.5 threat_values
  crash, v0.3.6 stats crash; `DEVELOPMENT.md` breed-adding checklist).
- **Horde presets only reach paced hordes, so mod-added breeds were rarely seen.** The
  skeleton-breed clones (v0.2.x-v0.3.8) were removed in v0.4.0 because presets patch only
  `HordeCompositionsPacing`; most adventure hordes are terror-event-driven
  (`HordeCompositions`, 194 keys) and bypassed the patches. Reviving them requires fanning
  the preset across those 194 event keys first - and re-paying the breed-add crash tax
  (`DEVELOPMENT.md` "Skeleton breed clones").
- **`ConflictDirector.update` cannot be re-run to recover from a throw.** Its post-spawn
  queue bookkeeping means a vanilla-fallback re-run doubles partial state; the tick must be
  skipped instead (issue 479). Any future hook on a per-tick engine function whose state
  mutates mid-call must use `_hook_wrap_tick`, not `_hook_wrap`.
- **Two boss-breed instances spawned in one frame race their BT init and crash.** Event-size
  replication in `compose_blob` must exclude `breed.boss` breeds - a second Drachenfels/Rat
  Ogre copy can have `blackboard.current_health_percent = nil` when its BT first evaluates
  (host crash, dlc_castle_slaanesh, event_size 3x). Boss breeds are unique-instance enemies.
- **A wrapper that forwards only the first return silently breaks the caller.** `compose_blob`
  returns `(spawn_list, num_to_spawn)`; forwarding only the list sent `nil` to a downstream
  `for i = 1, num` (this mod is the ORIGIN of § 2, multi-return collapse, v0.2.4). Capture
  every return.
- **A patrol formation longer than its spline builds an off-mesh member that crashes later.**
  Past the spline/navmesh end, `create_formation_data` returns a nil `spawn_pos` and builds a
  breed-name-less member with an off-mesh boxed position, which later crashes the patrol update
  on `POSITION_LOOKUP[unit]`. Patrol replication is hard-capped at 14 rows - bigger patrols are
  an engine limit, not something we can force (v0.7.13-dev).
- **Argument shape must be bound by position, not guessed.** `create_formation_data`'s patrol
  scaling silently did nothing for versions because the hook bound `spline_name` (a string) as
  the formation table; the real row-array is the 2nd positional (`ai_group_system.lua:861`
  iterates it). Grep the decompile signature and bind by true position.
- **Routine WARNING-channel logs land in the player's chat.** et's per-spawn `mod:warning`
  lines spammed chat every mission (issue 240); log-only alerts must go through pcall-guarded
  engine `printf`, reserving `mod:warning` for genuine failure paths (§ chat spam, issue 240).

## Doc maintenance

#451 remains observation-only. `_et_boss_ideas_core.lua` classifies the six
proposals without engine globals; `_et_boss_ideas.lua` reads `Breeds`,
`BreedActions`, `BreedBehaviors`, `InventoryConfigurations`,
`NetworkLookup.breeds`, and `Application.can_get("unit", ...)`. It adds one
bounded command but no hook, breed, spawn, package load, or lookup write. Breed
ids are serialized through `NetworkLookup.breeds` [src:
`network_lookup.lua:267-270`; `game_object_initializers_extractors.lua:178-179`].
The four lord sources remain `level_specific` package entries [src:
`enemy_package_loader_settings.lua:38-48`], so unit residency is evidence for a
future preload plan, never permission to spawn arena AI directly.

Follows `docs/engine/README.md` maintenance rules: if an et hook moves, a guard is
added, or a cited vanilla line drifts after a game patch, edit the affected row in
the SAME commit. This doc complements, and must not duplicate, `DEVELOPMENT.md` (the
breed-adding checklist + removed-feature history in full) - when the breed/spawn
mechanics change, `DEVELOPMENT.md` is primary and this doc's rows are the follow-on
edit. Any future balance-system replacement must document its engine registrations
as a new design; the retired BR hooks are not a template to silently restore. Line
numbers are against the 2026-07-12 decompile -
match crash logs by function name, not line. The `table.clone` target carries an
`[unverified]` exact line (function grep-confirmed present in `foundation/scripts/util/`).
Section shape (hook table -> subsystem notes -> dead ends) matches
`character_weapon_variants/ENGINE_SURFACE.md`. Reverse index:
`docs/engine/README.md` "Per-mod surface docs".
