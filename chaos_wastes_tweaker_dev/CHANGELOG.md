# Chaos Wastes Tweaker Changelog

## 0.7.250-dev (2026-07-12) - #457 FEATURE: Revamp Mission Availability (group master toggles + pool floor) [untested]

### #457 (feature, 1-major) - "Revamp Mission Availability"
- **Spec (from the issue).** Instead of one checkbox per mission, make each DLC, the Chaos Wastes missions, the Helmgart campaign, and the event missions a MASTER toggle, with advanced options to pick individual missions for groups that have more than one. Designed against #487 (the empty-pool load freeze): the availability UI must make solver-starving configurations impossible or loudly warned.
- **UI revamp.** Under Adventure Maps > Inject Adventure Missions > Available Missions, each mission group is now a master toggle `enable_group_<id>` (default ON): the 9 campaign/DLC groups sit under the "Campaign Scenarios" collapsible, and "Chaos Wastes Missions" + "Event Missions" are their own master toggles beside it. Multi-mission groups expand to a "Choose Missions" advanced list of the original per-mission checkboxes; single-mission groups (Winds of Magic, Reikland Tales) are a bare toggle with no sub-list. A mission is enabled iff its group master is ON AND (the group is single-mission, or its per-mission toggle is ON). Existing per-mission setting_ids (`enable_adventure_*`, `enable_cw_*`) are unchanged, so saved selections carry over; masters default ON so an unchanged install behaves exactly as before (`_adventure_pool.lua` build_master_widget / build_campaign_dlc_group_widgets / build_cw_scenarios_block / build_event_missions_block; `chaos_wastes_tweaker_dev_data.lua` available_missions_group).
- **Pool floor kills the #487 starvation class.** The binding graph-solver constraint is `prevent_same_level_choice` (same-type siblings at a branch; `deus_map_populate_settings.lua:222` lists only that validator for TRAVEL/SIGNATURE, and no journey overrides it - so `prevent_same_level_on_same_path` is defined but never wired), whose max width in the baked CW graphs is ~2-3. An EMPTY pool, though, has no assignable level at all, so the solver burns its 100000-iteration budget (`deus_populate_graph.lua:1006-1020`) = the multi-second load freeze. `inject_duplicate_aliases` cannot rescue an empty pool - it clones an existing key and there is nothing to clone (the historical `if n > 0` gap). New `enforce_pool_floor()` runs after filter+inject and before duplication: for every journey, if a TRAVEL or SIGNATURE pool has zero real (non-`_dupN`) keys it backfills one vanilla level for that journey+pool from the pristine snapshot (always a level that journey shipped, so no DLC-ownership or cross-journey risk), then the duplicate-alias pass fills it to POOL_SAFETY_THRESHOLD=4. So no availability configuration can empty a pool; the master toggles are now safe to slam off wholesale.
- **Loud, deduped notice.** When a backfill fires, a chat notice names the pool ("the TRAVEL mission pool would be empty - kept 'pat_forest' so the map can still load. Enable at least one TRAVEL mission.") plus a `[ct:487] POOL-FLOOR backfilled ...` printf next to the freeze diagnostic. Fires once per pool when it first underflows and re-arms when the pool recovers (session guard `_M._floor_notice_shown`).
- **Coherence.** `is_pool_setting` now also matches `^enable_group_` so toggling a master re-runs `inject_pool` live (no restart to re-shape the pool). `/ct_list_missions` reads the live LEVEL_AVAILABILITY pools directly, so it already reflects the master gate + any backfilled floor key with no change. The #487 diagnostic still logs live pool sizes; an EMPTY flag now means the floor itself failed (snapshot missing) rather than the normal underflow, and its header was updated to say so.
- **No new hooks.** All changes are in `_adventure_pool.lua` (data/query/floor), `_data.lua` (widget tree), `_localization.lua` (master labels + two shared tooltips), one line in `chaos_wastes_tweaker_dev.lua` (`is_pool_setting`), and a header comment in `_ct_diag_freeze487.lua`. `MOD_VERSION` `0.7.249-dev` -> `0.7.250-dev`. Tag `[untested]`.
- **Verify in-game (solo host, full Steam restart, confirm `[ct:LOAD] v0.7.250-dev`).** (1) Menu shape: open ct settings > Adventure Maps > Inject Adventure Missions > Available Missions. Expect "Campaign Scenarios" with a master toggle per DLC/Helmgart (each expandable to "Choose Missions" except Winds of Magic / Reikland Tales), plus "Chaos Wastes Missions" and "Event Missions" masters. (2) Master gate: enable inject, turn the "Chaos Wastes Missions" master OFF, host a run - expect a normal CW run built only from campaign/DLC/event missions (no pat_/sig_ vanilla scenarios). (3) DELIBERATE UNDERFLOW (the #487 repro): enable inject, turn OFF every campaign/DLC/event master AND the "Chaos Wastes Missions" master (so nothing is enabled), then host a Chaos Wastes run. Expected: a chat notice naming the emptied pool(s) ("...TRAVEL mission pool would be empty - kept '<level>'...") and the run LOADS normally (repeated maps), NO freeze; console shows `[ct:487] POOL-FLOOR backfilled ...` and a `GRAPH-SOLVE end ... graph=N nodes` (not `graph=NIL`, not a hang on the BEGIN line). (4) Recovery: re-enable a group, host again - normal pool, no notice.

## 0.7.249-dev (2026-07-12) - #456 DIAGNOSTIC: "Into the Nest" first-Grimoire empty book-spawner census [diagnostics-armed]

### #456 (bug, 1-major) - "Into the Nest Chaos Wastes Chest of Trials location failure"
- **Report (single line, no log attached):** on `skaven_stronghold` ("Into the Nest", a Helmgart campaign map ct injects into the CW pool - `_adventure_pool.lua:69`, NOT `no_books`, so ct expects convertible book pedestals) the location of the FIRST Grimoire is ALWAYS empty in a CW run.
- **How placement works (verified from decompile).** ct converts book (tome/grimoire) pickup-spawner units to `deus_cursed_chest` inside `PickupSystem._spawn_guaranteed_pickup` (`chaos_wastes_tweaker_dev.lua:~7014`); the first `cursed_chest_count` (default 1) book pedestals become Chests of Trials and any leftover book spot becomes a 1.75x coin casket, so on the guaranteed path NO book spot should ever be empty. An "always empty" first-Grimoire spot therefore has three candidate causes: (a) the grimoire spawner UNIT never registered with PickupSystem - its level object set is not enabled under the deus game mode, the same #52/#156 family the `[ct:skull52]` census + the `GameModeHelper.get_object_sets` #156 fix already target ("set membership lives in the level binary, unreadable offline"); (b) it registered into the TRIGGERED list (`triggered_spawn_id`, `pickup_system.lua:256`) whose `activate_triggered_pickup_spawners` (`:283`) flow never fires under the deus mechanism, so `_spawn_guaranteed_pickup` is never called for it; (c) it IS a guaranteed spawner that converts, but the chest/casket fails at that position.
- **Why it can't be root-caused from source alone.** Distinguishing (a)/(b)/(c) needs the level's per-unit spawner data (which list each book spawner lands in, and its object-set membership), which lives in the compiled level bundle, not the decompiled Lua. The issue carries no host log, and the existing spawner dump (`_dump_pickup_spawners_verbose`) is `_dbg`-gated (invisible on the user's mod-logging-OFF host) and never enumerates the triggered list per-unit; the `[populate_pickups]` line reports only aggregate list counts.
- **Diagnostic armed (raw `printf`, bypasses the mod-logging toggle).** New `_ct_book_spawner_census` (no new hook - called from inside the existing `PickupSystem.populate_pickups` hook) enumerates EVERY tome/grim-tagged unit across `guaranteed` + `primary` + `secondary` + `specified` + `triggered` spawner lists, printing per unit `[ct:456] book_spawner list=<L> kind=<tome|grim> guaranteed_spawn=<b> triggered_id=<s> pos=(x,y,z)` + a `[ct:456] census ...` summary. Fires for any ct injected-catalog base (`MISSION_BY_KEY`) in BOTH Adventure and CW, so a plain-Adventure load of `skaven_stronghold` is a baseline to diff the CW load against. Also added unconditional `[ct:456] leftover_book` / `[ct:456] empty_book` printf on the casket + final-empty fallthrough paths in `_spawn_guaranteed_pickup` (were `_dbg`-only) so case (c) is captured with kind + position. Interpretation: a grimoire ABSENT from the CW census but PRESENT in the Adventure census = case (a) object-set (compose with `[ct:skull52]`); `list=triggered` = case (b); present as `list=guaranteed` + a matching `empty_book` line = case (c). `MOD_VERSION` `0.7.248-dev` -> `0.7.249-dev`. Tag `[diagnostics-armed]`.
- **Verify in-game (solo host):** `/ct_load_mission skaven_stronghold` (loads it as a CW deus mission), let the level finish loading, then grep the console for `[ct:456]`. Compare against a plain-Adventure load of "Into the Nest" (same `[ct:456] census`/`book_spawner` lines fire there too). Read the FIRST-Grimoire outcome: if the grimoire appears in the Adventure census but is MISSING from the CW census -> object-set (a), cross-check the `[ct:skull52]` set list; if it shows `list=triggered` -> (b); if it shows `list=guaranteed` plus a `[ct:456] empty_book kind=grim` line -> (c). Report the `[ct:456]` + `[ct:skull52]` lines back on #456 to pick the fix.

## 0.7.248-dev (2026-07-12) - #471 DIAGNOSTIC: Chest-of-Trials enemy multiplier spawn-composition probe [diagnostics-armed]

### #471 (bug, 1-major) - "Increased Enemy Spawns at Chest of Trials appears to not work"
- **Static audit found no code no-op.** Walked the whole #64 path against the decompile and the reporter's own log (`console-2026-07-09-17.41.56`, ct_dev v0.7.238-dev): the setting reads correctly (`[ct-settings] cot_enemy_multiplier get=3 eff=3`), the hook installs at load (`Hooking 'spawn_around_origin_unit' from [table:...]`), the scaled field (`element.difficulty_amount`) is exactly what vanilla `spawn_around_origin_unit` reads (`terror_event_mixer.lua:97-131`), every cursed-chest wave carries `difficulty_amount` (not `breed_spawn_table_per_difficulty`, which only the three Belakor events use, so line 99's early-out never applies here), and dispatch is a live `init_functions[func_name]` lookup (`:1803`/`:1942`) so the table-form hook is not upvalue-bypassed. Chest activations demonstrably fire (`cot_activation seq=0..4`), and #463's `start_event` rotation is disjoint from #64 (it wraps the synchronous pick-resolution and restores before the spawn elements' init functions run frame-by-frame during the deferred wave update) - it does NOT clobber the scaling.
- **What remains unconfirmed (the reason it "appears not to work").** The only #64 signal on a logging-OFF host was a `mod:debug` line, which is invisible. So three failure modes were indistinguishable: (a) hook body never entering, (b) `mult` not reaching the scale, (c) the position finder `ConflictUtils.find_positions_around_position` (`conflict_utils.lua:1600`, tight 5.5-10.5m ring, `distance_to_enemies=2`, `tries=30`) or the spawn budget capping the scaled request back down - the run function spawns one enemy per `event.spawn_positions` entry (`terror_event_mixer.lua:1043`), NOT per requested count.
- **Diagnostic armed (raw `printf`, bypasses the mod-logging toggle).** Extended the single `spawn_around_origin_unit` hook body (no new hook) to emit one `[ct:471] cot_spawn` line per cursed-chest spawn element: `cat` / `breed` / `diff` / `mult` / `pre_req` (count vanilla would pick pre-scale) / `built_req` (`#event.spawn_table` after vanilla ran = our scaled request) / `placed` (`#event.spawn_positions` = enemies that actually spawn) / `scaled`. Reads `built_req`/`placed` off `event` after the wrapped call, before restoring the shared element. Interpretation: `built_req==pre_req` => scale not applied; `placed<built_req` => finder/budget cap (the likely culprit); `placed==built_req>pre_req` => scale works end to end. Probe covers BOTH `spawn_counter_category` values so an elite-only wave is visible - the `cursed_chest_elites` category is never scaled today (the #64 filter only matches `cursed_chest_enemies`), a candidate fix held pending this log. Scaling behaviour itself is byte-identical to #64; only diagnostics were added. New marker `CT_COT_471_DIAG_MARKER` + `/ct_regression_test` presence check `cot471_spawn_composition_probe`. `MOD_VERSION` `0.7.247-dev` -> `0.7.248-dev`. Tag `[diagnostics-armed]`.
- **Verify in-game (solo host):** set "Chest of Trials enemy multiplier" to a clear value (e.g. 3) in the ct menu, `/ct_load_mission` any CW mission with `cursed_chest_count` 2-3, open a Chest of Trials, then grep the console for `[ct:471] cot_spawn`. Expected if working: for `cat=cursed_chest_enemies scaled=yes`, `built_req` ~= 3x `pre_req` AND `placed` ~= `built_req`. If `placed` stays near `pre_req` while `built_req` is 3x, the position finder / spawn budget is the cap (next fix: raise the cursed-chest ring / spacing or split the request across waves). Report the lines back on #471.

## 0.7.247-dev (2026-07-12) - #464 FIX: Anath Raema's Swiftness rework made reload SLOWER [untested]

### #464 (bug) - "Anath Raema's Swiftness causes slower reload"
- **Symptom.** With the `tweak_anath_raema_permanent` rework ("permanent reload speed") enabled, the trait made reload SLOWER, not faster. Vanilla (tweak off) is unaffected and correct.
- **Root cause (verified from decompiled source).** The rework's replacement buff template hard-coded `stat_buff = "reload_speed", multiplier = 0.5` (positive). `reload_speed` is an INVERSE stat: it scales the reload HOLD TIME. `WeaponUnitExtension.get_scaled_min_hold_time` runs `min_hold_time = buff_extension:apply_buffs_to_value(min_hold_time, "reload_speed")` (`weapon_unit_extension.lua:966`), and `apply_buffs_to_value` composes a regular stat_buff as `value * (multiplier + 1)` (`buff_extension.lua:1431-1432`). So `+0.5` -> `hold_time * 1.5` = 50% LONGER reload. The vanilla on-pickup buff this rework replaces uses `multiplier = -0.5` (`buff_tweak_data.lua:225`), which halves the hold time = faster. Every vanilla faster-reload buff is negative (Bounty Hunter passive `-0.2` `talent_settings_victor.lua:87`, Huntsman ability `-0.4` `talent_settings_markus.lua:30`). The rework's inline comment even claimed `0.5` "matches the vanilla multiplier" - it misremembered the sign; vanilla is `-0.5`.
- **Fix.** Changed the replacement template multiplier `0.5` -> `-0.5` (`chaos_wastes_tweaker_dev.lua:~10215`). The permanent passive now halves reload hold time = faster reload, matching the vanilla trait's on-pickup magnitude but always-on while the weapon is wielded. One-value sign fix; no new hook. Corrected the inline comment to cite the inverse-stat convention + source lines.
- **Not a wire/parity concern.** Purely a local `WeaponTraits`/`BuffTemplates` data mutation gated by the existing `tweak_anath_raema_permanent` toggle; save/restore path unchanged. `MOD_VERSION` `0.7.246-dev` -> `0.7.247-dev`. Tag `[untested]`.
- **Verify in-game (solo host):** enable "Rework: Anath Raema's Swiftness, permanent reload speed" in the ct menu, then `/ct_load_mission` any CW mission with a ranged weapon carrying the trait (or force it via the dev loader's Starting Blessing / a weapon that rolls it). Reload with the tweak ON should be visibly FASTER than a plain reload (roughly half the hold time), never slower. Cross-check: toggle the tweak OFF and reload without an ammo pickup = baseline speed; ON = clearly quicker.

## 0.7.246-dev (2026-07-12) - #463 FIX: Chest of Trials repeats the same SPECIFIC trial [untested]

### #463 (bug, regression) - "the same trial should not repeat" (gas rat twice on one mission)
- **Symptom.** With multiple Chests of Trials per mission, the same trial recurs. Reporter got the gas-rat (poison wind globadier) trial twice on one mission. Root-caused directly from the attached host log (`console-2026-07-09-17.41.56`, ct_dev v0.7.238-dev): on `dlc_dwarf_interior_khorne_path1` (conflict director `deus_skaven_beastmen`), chest activations seq0 and seq2 BOTH spawned Globadier waves - reproduced exactly.
- **Root cause (verified from decompiled source).** A chest fires `cursed_chest_prototype`, which has three faction-gated `inject_event` blocks (`deus_generic_terror_events.lua:50-90`). `is_element_available` AND-matches a block's `faction_requirement_list` against the level's factions (`terror_event_mixer.lua:1637-1645), so on a two-faction CW level exactly one block fires - and every CW conflict director has only two factions (`deus_conflict_settings.lua:3207` etc.). The mod's existing #117 force-rotation only rotates that block's top-level FACTION `event_name_list`, so with one firing block over two factions the faction merely alternates, recurring every other chest. The SPECIFIC trial the player sees (gas rat) is then picked one level deeper, inside `cursed_chest_challenge_faction_skaven`'s `one_of` -> `weighted_event_names` by `Math.next_random(data.seed, 0, total_weight)` (`terror_event_mixer.lua:1671-1696`) - which the mod never rotated. The #157 seed perturbation makes those sub-picks INDEPENDENT but not DISTINCT, so they collide (log: seq0 and seq2 both landed on `cursed_chest_challenge_skaven_poison_wind_globadier` despite distinct seeds).
- **Fix.** Added a THIRD host-authoritative layer to the existing `TerrorEventMixer.start_event` wrapper (no new hook - merged into the single `cursed_chest_prototype` handler): before the vanilla call it now also force-rotates each faction challenge's `weighted_event_names` (skaven/chaos/beastmen) to a single entry that DIFFERS from that block's last pick this mission (new per-mission tracker `_ct_cot_trial_last`, reset alongside `_ct_cot_block_last` at run start + each `_transition_next_node`). Whichever `one_of` block vanilla selects, its forced pick is rotated within that block's own (flavor-appropriate) list. The single `weight=1` entry costs vanilla the same one `next_random` call the multi-entry pick did, so the downstream seed walk is unchanged; the shared templates are save/restored around the vanilla call under the existing pcall. New probe `[ct-cot-trial]` logs the forced specific-trial picks per activation; the old `[ct-cot-unique]` line is relabeled "faction picks".
- **Regression check.** `/ct_regression_test` check `cursed_chest_unique_trials` extended: asserts `_ct_cot_trial_last` exists and that `cursed_chest_challenge_faction_skaven` still carries the `one_of`/`weighted_event_names` shape the rotation depends on (guards a vanilla restructure turning the fix into a silent no-op). Marker bumped to `..._and_weighted_v0.7.246`.
- **Not a strict code regression.** The #117 force-rotation has only ever operated at the faction level, so a specific-trial repeat was reachable in every build since v0.7.177-dev; the rigid period-2 faction alternation it introduced actually clusters the same faction into 3 of 5 chests, raising the collision odds. `MOD_VERSION` `0.7.245-dev` -> `0.7.246-dev`. Tag `[untested]`.
- **Verify in-game (solo host):** `/ct_load_mission dlc_dwarf_interior_khorne_path1` (or any CW mission) with `cursed_chest_count` set high (3-5) in the menu, then open every Chest of Trials in the mission and confirm the enemy waves differ chest-to-chest (no two chests roll the same trial, e.g. gas rat only once). Grep the new log for `[ct-cot-trial] forced specific-trial picks` - the forced pick for the firing faction's block must change every activation.

## 0.7.245-dev (2026-07-12) - #505 Single Mission dev loader + #511 io.open->marker conversion [untested]

Adds a host-only tool to force one specific Chaos Wastes mission with a chosen curse, minor modifiers, starting blessing, base difficulty and depth - the CW analogue of gt_dev's `/downbots` for issue 448, and the verification lever for the ct critical cluster (freeze #487, Chest-of-Trials over-spawn #132, etc.). Also converts the five `io.open` source self-grep rt checks (#511). `MOD_VERSION` `0.7.244-dev` -> `0.7.245-dev`. Tag `[untested]`.

### #511 - `/ct_regression_test` no longer throws on `io.open` (VMF sandbox has no `io`)
- **Symptom.** The VMF Lua sandbox exposes no `io` library, so `io.open` in an rt check throws `attempt to index global 'io' (a nil value)` in-game and reports FAIL on healthy code (proven on enemy_tweaker; fixed there in 0.7.33-dev via runtime markers). ct_dev had five such source self-grep checks.
- **Fix.** Each source-read is replaced with a load-time provenance marker asserted at runtime (the enemy_tweaker `_wrap_registry` shape): `spawn_pickup_returns_both_values` (#322) -> new `CT_SPAWN_PICKUP322_MARKER` set beside the `_spawn_pickup` hook; `morgrim143_renorm_fix` (#143) -> new `CT_MORGRIM143_RENORM_MARKER`; `manann_tempest_trait_cooldown_note` (#133) -> new `CT_MANANN_TEMPEST_NOTE_MARKER` beside the `Localize` hook; `boon_offer_scrollbar_wired` (#115/#114) keeps its existing runtime `mod._ct_boon_scroll_setup` presence assertion; `citadel145_force_finale_god_fix` (#145) keeps its existing `mod._ct_force_finale_god` + `CT_CITADEL145_FIX_MARKER` assertions. No live `io.*` call remains.
- **Delegated to a repo QA gate (PROJECT_STANDARDS 2.2b tier a - NOT written here):** the genuinely-textual sub-invariants the in-game marker cannot capture - #322's exact 2-value capture/return shape, #143's renorm needle, #133's `description_deus_crit_chain_lightning` branch needle, #115/#114's both-surface wiring, and #145's "wired at both `deus_populate_graph` branches" count. Each is a source-pattern check that belongs in a `qa/check_*.ps1`.

### Mechanism (no new hooks)
- Reuses vanilla's own single-node debug loader: `DeusMechanism:debug_load_deus_level(level, difficulty, progress, level_seed, with_belakor)` builds the seed `DEBUG_SPECIFIC_NODE<progress*1000>_<level>SEED<seed>SEED_END` and calls `_debug_load_seed` -> `_setup_run` + `rpc_deus_setup_run` to clients + a level transition (`deus_mechanism.lua:1018`/`:1054-1058`). `deus_generate_graph.lua:10-72` turns that seed into a one-node graph (`DeusDebugSpecificNodeGraph`, `deus_default_graph_settings.lua:1534`), parsing level/base/theme/run_progress out of the seed string.
- **Curse** forced via `script_data.deus_force_load_curse` (read at `deus_generate_graph.lua:67`). **Starting blessing** via `script_data.deus_force_load_blessing` (appended at `deus_run_state.lua:169-170`). **Minor modifiers** appended to the debug node's mutator list (`table.clone` in generate_graph is shallow, so `DeusDebugSpecificNodeGraph.start` IS the loaded node - `.mutators` is rebuilt to `{deus_pacing_tweak, deus_difficulty_tweak}` + the chosen modifiers just before the load). **Depth** = `run_progress` (drives ct's progressive difficulty + weapon-chest tier). Since it forces a run entirely through `script_data` + the vanilla debug entry point, there is no `(Class, method)` to hook and no dup-hook risk.
- **Level keys** are composed as `<base>_<theme>_path<N>` (`deus_populate_graph.lua:945`); `sig_snare_<theme>_path<N>` is remapped through `LEVEL_ALIAS` (`deus_map_populate_settings.lua:188-220`) because the debug path returns before the populator applies it.

### Added
- **Menu group "[untested] Dev: Single Mission Loader"** (new module `_ct_dev_mission_catalog.lua` builds the widget tree + loc from one source): a "Load Selected Mission Now" hotkey plus dropdowns for Mission (12 native Travel/Signature maps), God Theme, Path Variant, Base Difficulty, Mission Depth, Curse, two Minor Modifiers, Starting Blessing, and a Be'lakor Journey checkbox. The hotkey resolves `mod.ct_dev_load_selected_mission`.
- **Chat commands** (new module `_ct_dev_mission.lua`): `/ct_load_mission <level_key> [progress 0-1] [curse] [difficulty]` (the direct lever), `/ct_list_missions [filter]` (enumerates the LIVE pool for the current journey grouped by Travel/Signature, flagging ct-injected adventure maps), `/ct_list_curses`, `/ct_list_modifiers`, and `/ct_clear_force` (clears the forced curse/blessing/modifiers - the blessing is read by the general `get_blessings` path so it would otherwise carry into the next ordinary CW run). All curse/modifier/difficulty vocabularies are transcribed from the decompile with `file:line` citations.
- **Regression check** `dev_single_mission_loader` (`/ct_regression_test`) asserts the module loaded and the keybind target + load primitive are callable.

### Gating & scope
- **Host-only + deus-mechanism-only.** `debug_load_deus_level` runs `_setup_run` as server and pushes the run to clients, so a client is refused with an echo; and the method only exists on `DeusMechanism`, so you must already be inside a CW expedition (on the CW map screen or in a CW mission). Solo host+bots is the guaranteed path.
- **Co-op caveat:** `script_data` is per-machine, so a forced curse/modifier applies host-side; clients loading the same seed get the same base level. For a clean co-op curse test every peer would need to run ct_dev with matching force state (a broadcast is a follow-up).
- **Deferred / blocked spec items (issue 505):** the dynamic god/DLC/Helmgart-*filtered* mission dropdown is blocked pending the shared VMF filtered-dropdown feature - a flat category-labelled base dropdown is shipped instead, and the command surface covers injected Campaign/DLC keys. Pre-granting upgraded gear at higher depth is not implemented (depth drives mission tier via run_progress, not a gear grant). The "single-mission only" keep-queue interception is provided as an explicit Load action (hotkey/command) rather than a silent hook on the map-start, which is safer and gives the same result.

## 0.7.244-dev (2026-07-12) - #506 re-sync the peer-parity lib copy from master [untested]

### Changed
- **#506: `_lib_peer_parity.lua` re-copied verbatim from `tools/shared_lib/`** (copied-lib rule, PROJECT_STANDARDS 9a). The master fix commits `_applied = state` BEFORE the callback loop so a callback reading `applied_state()` observes the transition it is part of, not the previous one. ct_dev's own callbacks do not read `applied_state()` today, so this is drift-correction with no behavior change here - but any future gated feature would have inherited the stale read. career_tweaker and character_weapon_variants got the same re-copy in their own builds (0.3.58-dev / 0.1.382-dev).

## 0.7.243-dev (2026-07-12) - DIAGNOSTICS: re-arm the reverted #132 / #134 / #136 probes

Re-arms the three CW diagnostics whose predecessors were reverted in v0.7.175 (bundled into a text-fix build and stripped "per user request" as a separate concern) and never re-armed. This is a dedicated diagnostics build - the correct home for them - so the revert reason no longer applies. Where the reverted probe was redundant or the current code already covers it, this re-arm ADDS the genuinely-missing seam rather than reintroducing the old line. All output is engine `printf` (visible with mod logging OFF, the user's setup); always-on in dev, no menu toggles (diagnostics doctrine). No behavior change - observation only. `MOD_VERSION` `0.7.242-dev` -> `0.7.243-dev`. Tag `[untested]`.

### #132 - DIAGNOSTIC: Chest-of-Trials over-spawn, spawn-path-independent ground truth
- **Why a new seam, not the old probe.** The reverted v0.7.174 `[ct-probe:chestcount]` was removed because "the chest probes already exist" - and today the CONFIGURED cap (`[ct-probe] populate cursed_chest_count`) and the ACTUAL count (`[ct-spawn-tally] chests(cursed=N)`) both already land on a logging-OFF host. But BOTH count at `PickupSystem._spawn_pickup`, the pickup-system chokepoint. If Khazukan Kazakit-ha's extra Chests of Trials are raw baked LEVEL UNITS (a `DeusCursedChestExtension` attached at level compile, never routed through the pickup system or the #60 cap budget), the census misses them and the cap cannot touch them - which is exactly the reported symptom and exactly the blind spot the count probes have.
- **New probe (new module `_ct_diag_cursed_chest132.lua`, dofile'd beside `_ct_diag_freeze487`).** A new `mod:hook_safe("DeusCursedChestExtension", "extensions_ready", ...)` (distinct method from the existing `_set_state` hook, so VMF-clean) fires once per cursed chest that actually EXISTS in the world, on every peer, regardless of spawn path (`deus_cursed_chest_extension.lua:39`). It emits `[ct:132] chest_of_trials #N level=L cap=M census=C is_server=B [OVER_CAP]` per chest and CROSS-CHECKS the census via the new `mod._ct_tally_cursed_count()` accessor: `#N > census` means chests bypass `_spawn_pickup` entirely (raw baked units); `#N > cap` means the cap is not enforced on this level. Per-mission counter resets on level change (so it is correct on a client, where `populate_pickups` never runs). Read-only; cap/spawn logic untouched. Also serves #60 (same bug class).
- **Test method (host, solo enough):** full Steam restart first (confirm `v0.7.243-dev` in the load log). Enable adventure-map injection, set `cursed_chest_count` to 3, queue a Chaos Wastes run and reach **Khazukan Kazakit-ha** (`dwarf_beacons`). PROOF THE PROBE IS LIVE: the console shows one `[ct:132] chest_of_trials #1 level=dwarf_beacons cap=3 census=... is_server=true` line per chest. DIAGNOSIS: if the highest line reads `#4`/`#5 ... OVER_CAP`, the over-spawn is confirmed; compare its `census=` to the `#N` - `census` lower than `N` means the extra chests never touched the pickup system (baked level units, fix must gate them at the extension), `census` equal to `N` means they spawned through the pickup path but past the cap (fix is in the budget).

### #134 - DIAGNOSTIC: adventure-collectible -> Pilgrim's Coin conversion (add is_server to the live probe)
- **Already live, one field short.** Contrary to the label note, this probe was re-armed the next build (v0.7.176) and is still live: `mod._ct134_log` -> `[ct-probe:collectible]` logs each `loot_die` / `lorebook_page` / `painting_scrap` reaching `PickupSystem._spawn_pickup` with the `on_injected_adventure_level()` gate broken down. The remaining gap the issue calls out is that the only capture so far was CLIENT-side (`on_adv=false`); the fix needs a HOST-side line to tell whether the injected-adventure gate is false only on the client (client `IS_INJECTED` divergence, #136 class) or on the host too (the gate itself is missing this base). The line had no `is_server` field to disambiguate.
- **Change:** added `is_server=%s` to the `[ct-probe:collectible]` line (inside the existing `_spawn_pickup` hook path - no new hook, no reintroduced line). Nothing else changed.
- **Test method (host + one client):** full Steam restart first. Load a CW-injected adventure map that has Ravaged Art (`painting_scrap`) and/or Loot Dice (`loot_die`), e.g. `military`. PROOF THE PROBE IS LIVE: both peers print `[ct-probe:collectible] name=painting_scrap spawn_type=... is_server=true on_adv=... in_coin_set=no ...` (host) and the same with `is_server=false` (client). DIAGNOSIS: if the HOST line reads `on_adv=false`, the injected-adventure gate itself is missing this base (fix the gate/`IS_INJECTED` set); if the host reads `on_adv=true` but the client reads `on_adv=false`, it is the client-divergence class (#136). Absence of any `name=loot_die` line while Loot Dice are visible means the loot-die collectible uses a different pickup key than `loot_die` - itself the answer to "confirm the exact loot_die name."

### #136 - DIAGNOSTIC: host/client CW mission divergence (promote two invisible dumps to raw printf)
- **The data already existed but was suppressed.** The reverted v0.7.174 `[ct-probe:mission]` hook on `GameModeManager.gm_event_round_started` captured the resolved per-node level on both peers. That exact data is already computed by TWO existing dumps - the per-peer `[mission:start]` line in the `GameModeDeus.local_player_game_starts` hook and the per-node graph dump in the `deus_populate_graph` hook - but both use `_dbg`, which is invisible with mod logging OFF. So re-adding a third hook would have been redundant; the real gap was visibility.
- **Change 1 (symptom seam):** promoted `[mission:start]` from `_dbg` to raw `printf` as `[ct:136] mission:start is_server=... current_node=... level=... base_level=... theme=... curse=... level_seed=... god=... node_type=... injected=... node_mutators=... active_mutators=...` (added `injected=`). Fires once per peer per round (host locally, clients via `rpc_gm_event_round_started` -> the same run-state node), inside the existing `local_player_game_starts` hook - no new hook.
- **Change 2 (mechanism seam):** new `mod._ct_mission136_dump(graph, is_server)` (mirrors the v0.7.219 `mod._ct_curse56_dump` #56 pattern, but covers EVERY ingame node instead of only Citadel) called at both `deus_populate_graph` post-run branches, right beside the #56 dump. Emits `[ct:136] graph peer=HOST|CLIENT node=... level=... theme=... curse=... god=... progress=...` per node (bounded to 24 lines) plus an `ingame_nodes=N` summary, on both peers after the snapshot broadcast/apply. This reproduces the 2026-07-03 evidence table (client `node_1=dlc_portals...` vs host `node_1=dlc_bastion...`) automatically.
- **Test method (host + one client, same run):** full Steam restart on both. Solo-host is not enough - this needs a real client. Queue a Chaos Wastes expedition and play through at least the first node. PROOF THE PROBE IS LIVE: at graph generation both peers print `[ct:136] graph peer=HOST ...` / `peer=CLIENT ...` node lines; at each round start both print a `[ct:136] mission:start ...` line. DIAGNOSIS: diff the host log against the client log for the SAME run - any node whose `level=` or `god=` differs between `peer=HOST` and `peer=CLIENT`, or any round where the two `mission:start level=` differ, is the wrong-mission divergence. `level_seed=` on the mission:start line shows whether the client rolled from a seed the host had not yet synced. Cross-refs #135, #145, #56.

## 0.7.242-dev (2026-07-12) - DIAGNOSTICS: instrument the Chaos Wastes load-freeze (#487)

**Issue 487 [diagnostics-armed] [untested] - game freezes ("stuck on loading initializing the Chaos Wastes"; menus respond, game input does not) after queuing a run; user reports it follows disabling all-but-one available mission, and expects the map to REPEAT a mission when fewer are enabled than the graph has nodes:**
- **No root cause shipped - instrumentation only (diagnose-before-mitigating).** A freeze produces no crash dump, and BOTH attached console logs (`...16.48.09...`, `...17.40.24...`) are clean sessions that never reach the freeze (one is the user in the keep doing cosmetics, the other visiting a friend's CW hub as a client; frametimes healthy, both end in a deliberate quit). The cause is therefore NOT provable from evidence yet, so this build adds probes and stops for a repro.
- **Leading hypothesis (from source, [unverified] against a live repro):** the deus map-graph solver `deus_populate_graph` (`deus_populate_graph.lua`) is a backtracking constraint solver capped at 100000 iterations (:1006-1020). Its per-node validators `prevent_same_level_on_same_path` / `prevent_same_level_choice` (:165-197) reject a level KEY already used on the path, so a TRAVEL/SIGNATURE pool with fewer DISTINCT keys than the longest same-type path has nodes cannot be solved - the solver burns its full budget (a multi-second stall = the freeze) and returns nil (`deus_generate_graph.lua:97`; the caller stores nil at `deus_run_controller.lua:284` with no retry). ct's own `_adventure_pool.inject_duplicate_aliases` is the safety net (mints `<key>_dupN` distinct keys up to `POOL_SAFETY_THRESHOLD=4`), and the constraint solver dedupes on KEY so those aliases correctly count as distinct - BUT it is guarded by `if n > 0`, so a pool the user empties to ZERO (e.g. leaving only a TRAVEL scenario enabled with all adventure missions off empties the SIGNATURE pool) gets NO duplicates and stays empty. Whether the observed freeze is the empty-pool case, the marginal-underflow case, or something else entirely is exactly what the probe will settle. See issue 470 and issue 356 for the adjacent CW crash cluster.
- **Instrumentation (new module `_ct_diag_freeze487.lua`, dofile'd after `_adventure_pool`):** brackets the vanilla `DeusRunController.setup_run` call (merged into the SINGLE existing hook on that method - no new hook) which runs `deus_generate_graph`. A `[ct:487] GRAPH-SOLVE begin` breadcrumb is flushed synchronously with the LIVE `DEUS_MAP_POPULATE_SETTINGS` pool sizes (TRAVEL/SIGNATURE/SHOP, split real-vs-`_dupN`, flagging `EMPTY` and `UNDERFLOW`) - so if the solver hard-hangs this is the last console line and it names the culprit pool; `[ct:487] GRAPH-SOLVE end` reports elapsed ms, whether the graph came back nil, and its solved node counts, plus a `WARN` on a slow (>=250ms) solve. A per-frame stall watchdog (driven from the single existing `mod.update` owner, no new hook) reports any frame whose dt exceeds 3s as a recoverable game-loop stall. All output is engine `printf` (visible with mod logging OFF); always-on in dev, no menu toggle (diagnostics doctrine). Runs on host AND client (both solve the graph locally from the synced seed).
- **No behavior change.** Pool filtering, duplicate injection, and graph solving are untouched this build; only observation was added.
- **Verify in-game (host, solo is enough):** full Steam restart first (confirm `v0.7.242-dev` in the load log). In ct settings, enable adventure-map injection, then disable missions until one whole pool is near-empty (e.g. leave only ONE mission on), queue a Chaos Wastes run, and reproduce the freeze. Capture the console log: the `[ct:487] GRAPH-SOLVE begin ... EMPTY=/UNDERFLOW=` line at the hang (or the `end ... graph=NIL` / slow-solve WARN) tells us the exact pool state and confirms or refutes the underflow hypothesis before any fix is written.

## 0.7.241-dev (2026-07-12) - CRASH FIX: static-hook arity bug blunted the no_roamers guard on signature zones (#356)

**Issue 356 [verify-fix] [untested] - host CTD `pairs(nil)` at mission load on Belakor / deus missions running adventure-derived conflict directors:**
- **Root cause (arity bug in the shipped guard):** vanilla `MutatorHandler.tweak_pack_spawning_settings` is STATIC - defined dot-form (`mutator_handler.lua:748`) and DOT-CALLED with exactly 4 args (`zone_mutator_list, mutator_list, conflict_director_name, pack_spawning_settings`) at `main_path_spawning_generator.lua:327`. ct's crash guard hook (`chaos_wastes_tweaker_dev.lua:5300`) declared a spurious leading `self`, so VMF's arg pass shifted every parameter by one: the hook's `pack_spawning_settings` always read nil (its `missing_field` strip fired on EVERY call, not just the crash predicate) and, decisively, the real `zone_mutator_list` - the SIGNATURE-zone list `no_roamers` actually rides on for adventure-injected/Belakor maps - rode in as the dropped-`self` positional and was NEVER filtered. So the `pairs(nil)` host CTD the guard exists to prevent (`mutator_no_roamers.lua:6` reading `pack_spawning_settings.difficulty_overrides`; crash console 2026-07-05-23.30.21, guid 4c84c68a, `military_belakor_path1` / conflict `chaos_light` / `deus_skaven_chaos`) could still fire on signature zones.
- **Fix:** drop the spurious `self`; bind the 4 real params in vanilla order; filter BOTH lists (`zone_mutator_list` AND `mutator_list`) with the existing `ADVENTURE_INCOMPATIBLE_PACK_MUTATORS` predicate. The v0.7.231 crash-predicate (`difficulty_overrides == nil`) OR injected-adventure exemption is unchanged. This is an EDIT of the single existing hook on `(MutatorHandler, tweak_pack_spawning_settings)`, not a new hook.
- **Regression test:** NEW `no_roamers_strip_arity_356` behaviorally locks the arity - drives the REAL hooked function through VMF with 4 positional sentinel args exactly as vanilla does; a self-shift regression leaks `no_roamers` into the unfiltered zone list, `run_mutators` invokes `mutator_no_roamers` -> `pairs(nil)` Lua error caught by `pcall` and reported. Marker `CT_NO_ROAMERS_ARITY_FIX_MARKER`. Existing `adventure_pack_compat_strip` (v0.7.231 predicate marker + list membership) unchanged.
- **Diagnostics:** `[ct:356]` printf fires only when a mutator is actually filtered, now naming the list (`zone_mutator_list` vs `mutator_list`) so a field log confirms the signature-zone path is covered.
- **Verify in-game (host):** full Steam restart first; solo-host a Belakor Chaos Wastes run and load to a node on an adventure-derived conflict (e.g. `military_belakor_path1`, cursed Halescourge). Mission loads without the `pairs(nil)` crash; log shows `[ct:356] stripped {no_roamers} from zone_mutator_list on conflict 'chaos_light' ...`. Normal (non-Belakor) CW missions unchanged.

## 0.7.240-dev (2026-07-11) - CRASH FIX: peer-parity gate for modded boons/miracles + ct_kill_heal re-enable (#426 #406)

**Issue 426 [verify-fix] [untested] - ct modded boons/miracles CTD non-ct peers; Issue 406 [verify-fix] [untested] - kill-heal verify unblocked (starting-boon selectable):**

- **Root cause (426):** ct's modded boons (`power_up_ct_boon_*`, `ct_meta_*`, `ct_kill_heal`) and miracles (`ct_miracle_*`) register into `NetworkLookup.buff_templates` / `deus_power_up_templates` (correctly unconditional for ct-peer index parity), but once GRANTED or APPLIED the modded index rides vanilla wire paths that reach peers WITHOUT ct (ct's `create_network_hash` shim deliberately lets them join): host buff apply broadcasts `rpc_add_buff` (`buff_system.lua:302-305`, receiver decode :430 fatals on unknown index), granted power-ups ride the deus run-state sync (`deus_run_state_spec.lua:60/:85`), persistent miracle names re-apply each mission spawn (`deus_spawning.lua:249/:277-278`), and hot-join re-sends every live server-controlled buff (`buff_system.lua:1087-1104`). Gameplay axes per the issue 371 map = peer-parity gate, not substitution. Unconditional, never toggle-gated (never-crash doctrine).
- **Fix - peer-parity beacon + five gate surfaces:** the shared peer-parity lib (verbatim copy of `tools/shared_lib/_lib_peer_parity.lua`, same pattern cwv ships for issue 424; new file `_lib_peer_parity.lua`) proves "every lobby peer runs ct" over VMF's own mod-to-mod channel (`ct_peer_parity_present`, schema-gated) - wire-safe by construction, poll-based (no hooks), fail-safe (modded content INERT until every other human peer positively acks; solo enables immediately; any beacon error forces content off). Gate surfaces: (1) POOL - modded boons ejected from `DeusPowerUpRarityPool` while parity unconfirmed, re-injected (respecting `enable_boon_*` toggles) on confirmation, including a load-time initial eject that closes the never-transition hole (a never-acking peer would otherwise keep load-time pools live); (2) GRANT choke point - parity filter merged into the existing consolidated `DeusRunController.add_power_ups` hook beside the issue-211 disable gate (covers chest/cursed-chest/shop/set-reward/end-of-level/debug); (3) STARTING boons - parity filter in the `_add_initial_power_ups` hook (modded names only; vanilla starting boons untouched); (4) MIRACLES - `_try_buy_blessing` degrades Ulric/Isha purchases to the VANILLA blessing when parity is unconfirmed (coins buy the vanilla effect, wire-safe), Isha arm+apply parity-gated with pending state preserved for retry; (5) PARITY-LOSS STRIP - on a persistent parity loss (15s debounce; must exceed the beacon's 10s announce-retry cadence because VMF's network_send silently skips peers whose VMF handshake is still in flight, so a ct friend's lost first announce must never trigger the destructive strip) the host strips granted modded power-ups from every PRESENT player's run-state list, ct names from persistent-buffs lists, and live ct buffs off all units via `remove_server_controlled_buff` (integer-id RPC only, no-ops on peers without the buff - `buff_system.lua:340/:437-454`).
- **Adversarial pre-ship review fixes (all landed in this build):** (a) BLOCKER - the bot random-boon picker (`bots_get_random_boons`) sampled the never-ejected `DeusPowerUpsArrayByRarity` registration table and its grant re-entered `add_power_ups` under `_ct_bot_mirror_active`, skipping the pre-grant parity filter - a clean bypass of every gate; the picker and the per-bot grant check now both reject modded names under unconfirmed parity. (b) `sync_host_dependent_state` (fires on every host-settings receipt) and `on_setting_changed` re-ran `register_trait_boon` and silently re-pooled ejected boons; the parity guard now lives INSIDE `_add_dormant_to_pool` (the single pool-write primitive) so no present or future caller can undo the eject. (c) strip debounce raised 6s to 15s per the announce-cadence analysis above. (d) the strip printf states the departed-player limitation (below). (e) the strip-ticker's `mod.update` wrap logs (not swallows) errors from the wrapped chain.
- **Known limit:** run-state keys of DEPARTED players are not enumerable from the strip (present players only), so a ct player who leaves after being granted a modded boon leaves a key a future joiner's full-state sync still carries - same class as the hot-join residual, documented in DEVELOPMENT.md.
- **Solo / full-parity lobbies: no behavior change.** Solo enables on the first beacon tick (~0.5s after load); an all-ct lobby enables after acks + 2s settle, minutes before any roll/grant can occur. Chat notice (lib built-in) tells the lobby what was disabled and which player is missing ct; auto re-enables when everyone has it.
- **Honest residual:** a non-ct peer hot-joining a run that ALREADY granted modded boons can receive the engine's join sync before the beacon detects them (~0.5-1s) - the gate prevents the class for lobbies formed before the run and shrinks the mid-run window; it cannot make an already-modded run fully hot-join-proof from Lua.
- **Issue 406 (kill-heal):** the client-side `heal_network` fassert fix (is_server gate) shipped v0.7.237-dev / public ct v0.7.131-beta, but the user cannot verify it because the boon was not selectable ("missing from selectable starting boons... Fix that first"). This build re-enables the full `ct_kill_heal` block (disabled since v0.7.98-dev after a Chest-of-Trials crash; both original hazards now addressed - the heal gate for the client fassert, the parity gate for wire exposure) and restores its BOON_TREE line, so `start_boon_ct_kill_heal` + `disable_boon_ct_kill_heal` widgets exist again (loc entries restored with `[untested] [Issue 406]` tags). Restored regression check `kill_heal_uses_permanent_heal_type`.
- **Build fix (ship pass):** the wire-safety block's helpers pushed the main chunk past Lua 5.1's 200-local ceiling (Stingray compile error at first build). The block body now lives inside a single builder function (`_ct_install_peer_parity`) so it costs the chunk one local slot; behavior unchanged.
- **Regression tests:** NEW `peer_parity_beacon_installed` (install + fail-safe posture constants), `peer_parity_gate_classify` (simulated peer sets: solo safe / un-acked unsafe / all-acked safe / partial unsafe / stale-ack safe), `ct_wire_strip_name_predicate` (ct_miracle_/ct_meta_/power_up_ct_ match, vanilla names and nil do not), `modded_power_up_registry` (trait boon + meta + kill_heal in, vanilla out); RESTORED `kill_heal_uses_permanent_heal_type`.
- **Diagnostics:** `[ct:426]` printf on every gate decision (pool eject/restore, grant block, starting-boon skip, miracle degrade, Isha hold/skip, strip summary, beacon install), `[ct:406]` on kill_heal registration. The existing `ct_peer_manifest_chunk` `/peers` dump stays a diagnostic surface; the beacon is the live gate.
- **Verify in-game (coop):** full Steam restart BOTH machines first. (a) Non-ct peer joins the ct_dev host's CW lobby: expect the `[ct]` peer-parity chat notice + `[ct:426]` eject line, boons roll vanilla-only, no crash on the peer through boon claims and miracles (buy Ulric: vanilla blessing applies). (b) Both-on-ct_dev lobby: unchanged behavior, modded boons roll after ~2s settle, `[ct:426] pools restored` in log. (c) issue 406: solo or both-on-ct_dev, enable `start_boon_ct_kill_heal`, start a CW run as CLIENT, land kills - green health ticks up, no crash, no `Only server can heal` fassert.

## 0.7.239-dev (2026-07-11) - CRASH FIX: host CTD on curse-sorcerer spawn at progdiff cataclysm_3 (#470)

**Issue 470 [verify-fix] [untested] - host CTD fighting Skulking Sorcerer curse sorcerers when progressive difficulty has ramped the run to cataclysm_3:**
- **Root cause (vanilla data hole, exposed by ct's progressive difficulty):** `mutator_curse_skulking_sorcerer.lua` declares broken rank constants (`CATACLYSM = 6`, `CATACLYSM_2 = 6` duplicate, `CATACLYSM_3 = 7` at :9-11), so the `MAX_HEALTH` table its `server_initialize_function` reassigns onto `Breeds.curse_mutator_sorcerer` (:36) spans ranks 2..7 with no entry at rank 8. The base breed's own `max_health` is a full 8-entry array (`breed_chaos_mutator_sorcerer.lua:58-67`); the hole exists only while the curse is initialized. Vanilla CW never reaches rank 8, but ct progdiff stepped the run to cataclysm_3 = rank 8 (`difficulty_settings.lua:287`). Curse-sorcerer spawn resolved `max_health[8] = nil` (`conflict_director.lua:1948`), `GenericHealthExtension.init` threw in `math.clamp` mid extension-add, `extensions_ready` never ran (`entity_manager2.lua` add loop :116-146 precedes ready loop :150-171), and the half-initialized hit_reaction extension already registered one slot earlier (`unit_extension_templates.lua:403-419`) nil-deref'd on the next HitReactionSystem update = host CTD. Fatshark guarded the sibling `RESPAWN_TIME` lookup with `or RESPAWN_TIME[NORMAL]` (:43) but not `MAX_HEALTH` - confirmed oversight; the duplicate-key bug shifted the whole health band down one rank, so 150 is their evident cataclysm_3 value.
- **Fix:** UNCONDITIONAL backfill (issue 371 never-crash doctrine - not gated on the progdiff toggle or any setting): new `mod:hook_safe(MutatorHandler, "initialize_mutators", ...)` (server-only call path, `mutator_handler.lua:48`; fires after every `template.server.initialize_function` has run at :644-645, i.e. after the sparse table lands on the breed) sets `max_health[8] = 150` iff the table has `[7]` but no `[8]`. Entries 6/7 deliberately untouched - re-keying the mis-banded values would change live gameplay. Marker line `[ct:470] backfilled curse_mutator_sorcerer.max_health[8]=150 (vanilla rank hole)` prints at curse init.
- **Sibling sweep (bounded to this class):** grepped every `scripts/settings/mutators/mutator_*.lua` for rank-keyed tables. Only skulking sorcerer assigns one onto a Breed with an unguarded read. `mutator_curse_egg_of_tzeentch.lua` (ranks 2..6 tables, reads at :163/:268/:317) and `mutator_curse_bolt_of_change.lua` (reads at :195/:348) all carry `or X[NORMAL]` / `or 1` fallbacks - no backfill needed.
- **Regression test:** `curse_sorcerer_rank8_backfill` in `/ct_regression_test` - predicate backfills a sparse `{[6]=120,[7]=150}` band to `[8]=150` without mutating 6/7, leaves a full 8-entry array untouched, no-ops on nil/empty.
- **Log evidence (i470):** host crash on `bell_nurgle_path1` at cataclysm_3 via progdiff mission 4 - progdiff line 156107, curse activation 156787, spawn abort errors 158014-158017, crash 158100-158123.
- **Verify in-game:** full Steam restart first; CW run with progressive difficulty reaching cataclysm_3 (mission 4+), take the Skulking Sorcerer curse; expect the `[ct:470]` backfill line at curse init and no crash fighting the curse sorcerers.

## 0.7.238-dev (2026-07-07) - Remove em dashes from menu-facing tooltip strings

Doctrine fix (audit F3): replaced em dashes in 4 user-facing tooltip strings in `chaos_wastes_tweaker_dev_localization.lua` with hyphen/colon/comma phrasing, per the no-em-dash-in-menu-strings non-negotiable. `start_boon_ct_kill_heal_tooltip` (:384), `activate_dormant_deus_transmute_into_coins_tooltip` (:1187), `activate_dormant_explosive_pushes_on_damage_taken_tooltip` (:1189), `activate_dormant_squats_tooltip` (:1191). Code comments (incl. `_data.lua`) untouched. No behavior change. Not built, deployed, uploaded, or committed.

## 0.7.237-dev (2026-07-06) - HOTFIX: client CTD on kill with the kill-heal boon (#406)

**Issue 406 [verify-fix] - a CLIENT taking the "heal on kill" power-up (`ct_kill_heal`) hard-crashes on their next kill:**
- **Root cause:** `ct_kill_heal_on_kill` called `DamageUtils.heal_network` with no server gate; heal_network fasserts "Only server can heal" on clients (damage_utils.lua:2636). on_kill procs run on the killer's local machine, so a client-side kill = instant fassert. Same class as crt issue 405 (2026-07-07 client crash); found by the issue-405 repo-wide sweep. Latent to date because the user usually hosts.
- **Fix:** vanilla `Managers.player.is_server` gate (buff_templates.lua:325/:404 pattern); client no-ops, the host's instance of the synced buff grants the +0.25 permanent heal.
- **STABLE `chaos_wastes_tweaker` carries the same bug** (chaos_wastes_tweaker.lua:10781-10785) until the next user-triggered promotion - not patched per dev/stable doctrine.
- **Verify in-game:** as a CLIENT in Chaos Wastes on ct_dev, take the kill-heal boon and kill enemies - no crash; green health ticks up when the host runs ct/ct_dev.

## 0.7.236-dev (2026-07-06) - CLOSE issue 291 (Cataclysm-3 journey-win CTD) - user-confirmed fixed

User confirmed in-game 2026-07-06: winning a CW journey with Progressive Difficulty ramped to
Cataclysm 3 no longer crashes at the journey-completion screen. The fix shipped earlier (v0.7.220-dev,
commit 0e9260b: a guard on `StatisticsUtil._register_completed_journey_difficulty` that clamps only the
RECORDED difficulty to the `DefaultDifficulties` ceiling when the ramped tier isn't in the list; marker
`CT_JOURNEY_DIFFICULTY_GUARD_MARKER`, regression test `journey_difficulty_guard_installed`). This build
only strips the menu status tag. No behavior change.

- LOC: `progressive_difficulty` title `[crash] [diag] [Issue 291]` -> `[diag]` (kept `[diag]` - the
  `[ct:progdiff]` / `[ct:journeyguard]` probes stay armed). issue 291 was the only open crash issue
  referencing this setting, so `[crash]` comes off per LOCALIZATION_STANDARD s13.

## 0.7.235-dev (2026-07-06) - Strip issue 211 loc tag (Disabled Boons group; issue already closed)

Loc-only follow-up. issue 211 is already closed on GitHub; this flips the menu title to match.

- LOC: `disabled_boons_group` group header `[verify-fix] [Issue 211] Disabled Boons` -> `Disabled Boons`
  (group headers carry no status tag). No behavior change.

## 0.7.234-dev (2026-07-06) - CLOSE issue 262 (NetworkedFlowStateManager 512-cap host crash) - user-confirmed fixed

User confirmed in-game 2026-07-06: the host no longer crashes at the 512 flow-state cap during a
Chest of Trials fight under raised enemy caps. The fix shipped earlier (v0.7.213-dev, commit 520ed9a:
`flow_cb_create_state` decline-at-cap guard, regression test `networked_flow_state_cap_guarded`); this
build only strips the menu status tag. No behavior change.

- LOC: `cot_enemy_multiplier` title `[crash] [verify-fix] [Issue 262]` -> `[working]`. issue 262 was the
  only open crash issue referencing this setting, so `[crash]` comes off per LOCALIZATION_STANDARD s13.
  Related host-crash guards: issue 129 (Mathlann AoE), issue 205 (settings-sync flood).

## 0.7.233-dev (2026-07-06) - CLOSE issue 104 (Blood in the Darkness host FPS) as vanilla injected-map overhead

Close issue 104 (Blood in the Darkness host FPS) as vanilla injected-map overhead - census showed
FPS tracks level-baked flow-state counts, not the curse-lighting shading_callback; the corrupted-flesh
cloud cap mitigation stays, dev issue tag stripped from its setting title.

- LOC: stripped `[verify-fix]` and `[Issue 104]` from `flesh_guard_clouds_per_minute` (kept `[diag]`
  - the flesh_guard `[ct:aoe]` / `[ct:flesh_guard]` attribution printf stays armed). No behavior change.

## 0.7.232-dev (2026-07-05) - CLOSED 6 user-confirmed-fixed issues: #143 #119 #133 #121 #115 #114 (regression guards + loc-tag flips)

User confirmed all six fixed in-game; closing with regression guards where the fix was not
already covered, and clearing each option's `[Issue N]` / `[verify-fix]` loc tag.

- #143 (Morgrim's Bomb over-spawn): the live fix HALVES holy_hand_grenade's world
  `spawn_weighting` on injected adventure maps and redistributes the freed half proportionally
  so the pool SUM is byte-identical (a LOWERED total crashed the sampler in v0.7.143). NEW test
  `morgrim143_renorm_fix` source-guards the sum-preserving renorm. The grant-side faucets (shrine
  blessing pool, the drop-on-ability boon) remain toggleable via the existing per-boon disables.
- #133 (Manann's Tempest description): with `tweak_manann_tempest_cooldown` ON, the vanilla
  `deus_crit_chain_lightning` trait tooltip gains the "8 second cooldown." note via the
  `_G.Localize` hook. NEW test `manann_tempest_trait_cooldown_note`.
- #115 / #114 (Shrine / Chest boon GUI overflow): `mod._ct_boon_scroll_setup` adds a track+thumb
  scrollbar so `shrine_boon_count` / `chest_boon_count` can exceed the fixed vanilla arc. NEW test
  `boon_offer_scrollbar_wired` guards the export + both wiring sites (shrine @4 rows, chest @3).
- #119 (Trait Tier by Rarity draws from the whole melee/ranged class union): already guarded by
  `tier_by_rarity_class_union_ranged`; loc tag cleared.
- #121 (Shared Reliquaries bot over-upgrade): resolved by the issue-100 pre-bump rarity capture +
  issue-102 altar-rarity decouple, already guarded by `bot_weap_opened_rarity_pre_bump` +
  `upgrade_altar_rarity_decouple`; loc tag cleared (kept `[diag]` - the `[ct:bots121]` probe stays
  armed as recurrence insurance).
- LOC: cleared `[Issue 119/133/115/114]` + `[verify-fix]`, and `[Issue 121]` (kept `[diag]`).

## 0.7.231-dev (2026-07-05) - CRASH FIX: no_roamers pairs(nil) on Belakor / deus missions (adventure-derived conflict directors)

**Crash console 2026-07-05-23.30.21 (guid 4c84c68a), mission load of `military_belakor_path1`:** `scripts/settings/mutators/mutator_no_roamers.lua:6: bad argument #1 to 'pairs' (table expected, got nil)`. The `no_roamers` mutator iterates `pack_spawning_settings.difficulty_overrides`, which is nil on the `chaos_light` conflict director this Belakor node runs. Same crash class ct fixed in v0.7.41 for injected-adventure levels - but that fix gated the strip on `on_injected_adventure_level()`, and a Belakor node is a genuine deus mission (not injected-into-stock-Adventure), so the strip never fired and vanilla `no_roamers` crashed at `generate_spawns` during `state_ingame.on_enter`.

- **Broadened the `MutatorHandler.tweak_pack_spawning_settings` strip guard.** It now removes `ADVENTURE_INCOMPATIBLE_PACK_MUTATORS` (no_roamers) when EITHER `pack_spawning_settings.difficulty_overrides` is nil (the exact crash predicate - covers any deus mission on an adventure-derived conflict director like `chaos_light`) OR `on_injected_adventure_level()` (the original v0.7.41 aesthetic exemption, kept OR-ed so nothing strips less than before). On normal CW levels the field is present and the level isn't injected, so vanilla `no_roamers` runs untouched. Stripping never removes a working mutator: with `difficulty_overrides` nil, `no_roamers` can only ever crash.
- Prints `[ct:no_roamers] stripped {no_roamers} on conflict '<name>' ...` via engine printf when it fires, so the next log confirms the guard engaged.
- Regression: `adventure_pack_compat_strip` now also asserts `CT_NO_ROAMERS_DEUS_FIX_MARKER` so a future refactor can't silently drop the deus-mission coverage.
- Unrelated to v0.7.230's bomb-boon change (isolated `grenade_explode_buff_area` hook).

## 0.7.230-dev (2026-07-05) - #120: Bomb Boon Cooldown now gates the bomb-BUBBLE boons (was hitting the wrong boon)

**Root cause found from console 2026-07-05-23.03.16 (v0.7.229-dev).** The player held `boon_supportbomb_concentration_01` (a bomb-bubble boon) but ZERO `[ct-bomb-boon]` markers fired: `bomb_boon_cooldown`'s only runtime gate was hooked on `ProcFunctions.drop_item_on_ability_use` (the drop-a-bomb-on-ult boon), while the bomb-BUBBLE boons #120 is about (`boon_supportbomb_concentration/crit/healing/speed_01`) proc through a different function - `grenade_explode_buff_area` on `on_grenade_exploded` (deus_power_up_settings.lua:4389+; body morris_buff_settings.lua:3131), which `add_buff`s the AoE zone on every grenade explosion with no cooldown at all (`boon_supportbomb_shared_data = {duration=10, radius=6}`, buff_tweak_data.lua:583). So the setting's code + tooltip targeted the drop-on-ult boon, not the bubbles the issue names.

- **New gate on `ProcFunctions.grenade_explode_buff_area`** (the shared proc for all four supportbomb boons). Enforces the same `bomb_boon_cooldown` interval as a per-boon-instance minimum between bubble spawns: stamps `_ct_last_bubble_t` on the buff instance (naturally per-owner + per-boon, auto-cleared on run end), skips the `add_buff` when the interval hasn't elapsed. Server-only (vanilla's own is_server guard), host-synced via `effective_setting`. Prints `[ct-bomb-boon] supportbomb '<name>' proc allowed / gated ...` per proc so the next log verifies it. Duplicate-hook pre-flight: zero prior ct hooks on `grenade_explode_buff_area`.
- **The existing `drop_item_on_ability_use` gate is kept** (no regression) - one setting now caps both bomb-boon families.
- **Tooltip corrected** to name the bomb-bubble boons (concentration / crit / healing / speed) alongside the drop-on-ult boon, and to state 0 = vanilla (a bubble every explosion).
- **`[verify-fix] [Issue 120]` tag kept** - needs one in-game run with a supportbomb boon + rapid grenade throws to confirm `[ct-bomb-boon] ... gated` appears and the bubble stops re-spawning under the interval.

## 0.7.229-dev (2026-07-05) - #145 CLOSED (user-confirmed in-game): Citadel finale-god override

User confirmed the v0.7.219 fix in-game (finale god matches the `finale_dominant_god` setting; the non-Tzeentch `arena_citadel` variants load). Closing #145. No behavior change this build - it adds the missing regression coverage for the FIX and corrects the loc tag.

- **Regression test for the fix (`citadel145_force_finale_god_fix`).** The pre-existing `citadel145_probe_installed` check only guarded the diagnostic (`_ct_citadel145_dump`), not the fix. New check asserts `mod._ct_force_finale_god` is present, its `CT_CITADEL145_FIX_MARKER` matches, and it is still wired into BOTH `deus_populate_graph` branches (source-read count >= 2) - the exact silent-revert path (fix present but call dropped = #145 returns). Run via `/ct_regression_test`.
- **Loc tag corrected.** `finale_dominant_god` was `[verify-fix] [diag] [Issue 145 & 56]`; #145 is now confirmed/closed and #56 was already closed, so both stale refs are dropped and `[verify-fix]` is retired. Kept `[diag]` paired to the still-open issue 135 (weekly god override; its `[ct:god135]` probe remains live on this exact setting). New tag: `[diag] [Issue 135] Finale God`. (That issue is deliberately dereferenced above so ship.ps1 step-6 does not mis-add `verify-fix` to a diag-only issue; its status is unchanged by this build.)
- The #145 fix itself is unchanged (shipped v0.7.219): `mod._ct_force_finale_god` rewrites the god segment of `arena_citadel_*`/`sig_citadel_*` on the finished graph, honoring the override without touching `config.NO_DOMINANT_GOD`.

## 0.7.228-dev (2026-07-05) - #2 first ct_dev extraction (_ct_combat_hooks.lua) + #143 grenade-share census

Two-part maintenance/diagnostics build; no gameplay behavior changes intended.

**#2 file-size split, first ct_dev seam.** Moved the contiguous combat/proc/Chest-of-Trials
runtime-hook block (old lines 12138-13354, 1,217 lines: Manann's Tempest cooldown, Mathlann's
AoE cap #129, Corrupted Flesh guard #104, CoT enemy multiplier/uniqueness/rotation/Skaven
Warlord trial #64/#117/#324, parry-proc strip + burn VFX, Myrmidia's Wildfire, Larger Clip
#34, Block Ranger Veteran #259) verbatim into new `_ct_combat_hooks.lua` (1,270 lines),
loaded by ONE `mod:dofile` at the same execution point. Zero mod._* promotions needed;
`effective_setting`/`_dbg` get behavior-identical module shims (the `_ct_mechanic_tweaks`
pattern). Main file 15,344 -> 14,133 lines. Pure move: lint PASS (9 files, 91 hooks, 0
duplicate-hook/forward-ref), build OK. Extraction audit surfaced pre-existing dead code -
the parry-cooldown strip's caller resolves a nil global and has been a silent no-op since
~v0.7.128; preserved byte-identically and filed as #342 (decision: wire it or delete it).

**#143 round 2: grenade world-spawn share census.** The 2026-07-04 log (v0.7.219) proved
the 50% weight cut applies (`renorm: holy_hand 0.2500 -> 0.1250`, pool pre-normalized to
sum 1.0 by CWV's javelin injection - cross-mod interplay now documented in the issue) and
world-spawned Morgrim's dropped to 2 per session. The remaining perceived abundance points
at grant-side faucets (Shrine of Strife `blessing_holy_hand_grenade`, the
`drop_item_on_active_ability_use` boon, altar/shop power-ups - see issue comment). New
`[ct:morgrim143] grenade world-spawn tally` printf counts EVERY grenade-type spawn at the
existing `_spawn_pickup` chokepoint (no new hook), so holy's true share is readable from
any log. Diagnostics-only.

- VERIFY IN-GAME: normal CW run incl. Chest of Trials + one parry-boon and one
  Manann's/Mathlann's boon (regression sweep of the moved hooks); grep the log for the
  `grenade world-spawn tally` lines and report which Morgrim's faucet you're actually seeing.

## 0.7.227-dev (2026-07-05) - #299 rework: chest-revive return-to-team teleport was never firing

The 2026-07-05 host log (v0.7.225-dev) proved the revive half works but the teleport-back
never fires: at a chest, three downed players were `freed-awaiting-rescue`, one went
networked-`alive` ~1.6s later, yet ZERO `teleported back to the team` lines printed - every
armed player ended in `team-teleport TTL expired ... never became controllable`. The tick's
teleport branch was never entered.

Root causes addressed in `_ct_chest_teleport_tick` + its arm sites:
- **Stale unit resolution (primary).** The tick re-looked-up `Managers.player:player(peer,lpid).player_unit` every frame and never observed the freed unit as alive+not-disabled. Now the arm captures the stable **player object**; the tick reads `player.player_unit` off it (which updates across the respawn/recovery unit swap), only relooking-up if the stored handle has no unit yet.
- **peer_id key collision.** Host-owned BOTS share the host peer_id (the log showed slots 3 & 4 both `110000106beb4a3`), so the peer-only `pending[peer_id]` key made sibling entries overwrite each other. Now keyed by `peer_id/local_player_id`.
- **TTL vs transitions.** Bumped the arm TTL 20s -> 30s (accumulated-dt; CW node/loading transitions stall `mod.update` dt, so 20s of real gameplay could straddle a transition).
- **Self-diagnosing.** Armed a throttled per-eval probe (`[ct-chest-revive] tick key=... found=.. alive=.. disabled=.. awaiting=.. ttl=..`, logged on state change) and the TTL-expiry line now prints the FINAL found/alive/disabled/awaiting state, so a repeat failure pinpoints the exact blocker.

Still `[verify-fix] [diag]` until confirmed in-game (host-authoritative; needs a real chest revive to verify the teleport fires).

## 0.7.226-dev (2026-07-04) - #324 NEW: Skaven Warlord Chest-of-Trials trial (cross-mod with enemy_tweaker)

- **New rare cursed-chest trial `ct_cursed_chest_challenge_skaven_warlord`:** spawns enemy_tweaker's new `et_skaven_warlord` boss (the unused champion-recolour of Skarrik's model, vanilla 800-HP champion stat block; registered by et v0.7.27-dev) plus the standard clan-rat retinue. Template: `cursed_chest_challenge_skaven_rat_ogre` (deus_generic_terror_events.lua:1374-1445, the closest boss-type trial) with vanilla's distance/delay constants inlined (:92-107) and verbatim ports of the file-local `cursed_chest_enemy_spawned_func` (:17-41; keeps the `cursed_chest_objective_unit` buff + `cursed_chest_enemies` counter wiring, so the chest opens when the trial clears - deus_cursed_chest_extension.lua:173) and the spawn/despawn decal funcs (:109-151). The boss element's `pre_spawn_func` resolves the LIVE `TerrorEventUtils.add_enhancements_for_difficulty` reference at OUR definition time (the CODE_REVIEW.md v0.7.89 upvalue-gotcha pattern done right), so grudge enhancements apply per difficulty exactly like vanilla boss trials, the Boss Grudge Marks banlist keeps biting, and grudge-marked Warlords render et's 12 new grudge names.
- **Injection:** weighted pick (weight 1 vs the vanilla 3s = rare-ish) appended to the two skaven pools that already carry the monster trials - the MORE_MONSTERS block and the untagged fallback block of `cursed_chest_challenge_faction_skaven` (identified structurally by "contains cursed_chest_challenge_skaven_rat_ogre", so elites/specials blocks are never touched). Folded into the always-on unique-trials behaviour per the #117 precedent - no new menu toggle. Composes with both #117 layers (seed perturbation + prototype-level force-rotation - those operate on `event_name_list`, ours on `weighted_event_names`).
- **et-absence guard:** injection only happens when `rawget(_G, "Breeds").et_skaven_warlord` exists; without enemy_tweaker the feature skips with a single `[ct-warlord-trial]` printf note and ct behaves exactly as before. Load order is not guaranteed, so the injection is retried idempotently from the EXISTING `ConflictDirector.start_terror_event` hook at each chest activation (merged into that body - no new hook on the method).
- **Deliberate deviation from the template: no start_mission/end_mission elements.** A new mission name needs `NetworkLookup.mission_names` on every peer (strict lookup at mission_system.lua:135, id RPC'd to clients - unmodded clients would hard-error), and reusing a vanilla trial's name risks the `end_mission` fassert (mission_system.lua:227) when two chests overlap. The mission is objective-HUD only; chest completion never reads it.
- **Peer requirement (inherited from the breed):** every player in the lobby needs enemy_tweaker installed for the Warlord to spawn safely (et registers the breed's NetworkLookup entries at module load, enabled or not).
- Regression check `warlord_trial_injection` (`/ct_regression_test`): ensure-fn present; et absent => pools verified clean (guard held); et present => event registered, boss element carries the counter category + the live `add_enhancements_for_difficulty` ref, and the weighted pick exists in the skaven pools.
- **[untested] - verify: with both mods installed, open Chests of Trials in a CW run until the Skaven Warlord trial rolls (weight 1, skaven faction pools); expect the boss bar to read "SKAVEN WARLORD" (or a grudge name at higher difficulties), the trial to count down normally, and the chest to open on clear. Without enemy_tweaker: one `[ct-warlord-trial]` log line, vanilla trials unchanged.**

## 0.7.225-dev (2026-07-05) - #144 Vaul's Anvil: retire the boon-list trace, add a self-healing perk reconciler + [ct:vaul] probe

- **#144 re-scoped + fix attempt - Vaul's Anvil boon "stops working" after an equip/wield action.** New report evidence: the boon STAYS in the boon list (two clean repro logs proved the list only grows and never drops it), but its EFFECT stops after "some kind of equip action (picking up objects or swapping items)." Traced to the perk lifecycle, not the list. The boon's effect is the `deus_always_blocking_buff`, which toggles `status.override_blocking` (apply/remove_always_blocking, morris_buff_settings.lua:1003/1009). Vanilla maintains that perk ONLY reactively: block-broken lockout recovery, plus an **orphaned weapon-swap re-apply trigger** (`always_blocking_weapon_swap`, :3093, which NOTHING in the shipped engine ever calls - confirmed by full-tree grep). So once the perk is dropped (block-broken 10s lockout, or a buff refresh on an equip/wield/pickup), there is no reliable path that re-adds it and the boon silently goes inert. **Fix:** ct's Vaul's Anvil controller buff now uses a ct-owned `update_func` (`ct_vauls_anvil_reconcile`) instead of vanilla `always_blocking_update`. It is authoritative EVERY frame: the perk is present IFF a melee weapon is wielded AND the lockout is not active, so it self-heals any drop the instant the player is back on melee - independent of the orphaned swap trigger. Registered into `BuffFunctionTemplates.functions` in `pre_register_trait_boon_lookups`; the buff's `update_func` is only repointed when that registration is confirmed (else it keeps vanilla `always_blocking_update`), so a buff can never name an unregistered function (buff_extension.lua:794 calls it UNGUARDED). Runs in the same buff-update context vanilla did, so add/remove of the perk carries the same authority/network path. Isolated to ct's boon; the vanilla always_blocking weapon trait is untouched.
- **Diagnostics reshaped (per request):** the `[ct:boon144]` before/after boon-list SHRINK trace + its snapshot helper + boot printf are **RETIRED** (they proved the list is never the problem). The live instrument is now `[ct:vaul]`, emitted edge-triggered from the reconciler: `wielded / melee / locked / has_perk / override_blocking / want / action / desync` on every state change (raw printf; host runs VMF logging OFF). The `desync` watch flags the case the perk reconciler can't fix - `override_blocking` not matching the wielded/lockout state even though perk presence is correct - which would point to an external override clear (deeper than perk presence). Regression check renamed `boon144_list_trace_installed` -> `vauls_anvil_reconciler_installed` (asserts the reconciler exists and is registered into the buff-function table when available).
- **[untested] - verify:** with `enable_boon_vauls_anvil` on and Vaul's Anvil held, do the action that broke it (swap weapons / pick up objects) and confirm blocking-everything resumes on melee. The newest log's `[ct:vaul]` lines show each transition; if `desync=true` recurs, the loss is override_blocking being cleared externally (send that log) - otherwise the reconciler should keep it healed.

## 0.7.224-dev (2026-07-04) - #322 FIXED: _spawn_pickup hook now re-returns vanilla's 2nd value (pickup_unit_go_id)

- **#322 (bug) FIXED - ct's `_spawn_pickup` hook dropped vanilla's 2nd return, breaking linked-pickup client sync.** Found while fixing #294 (same hook). Vanilla `PickupSystem._spawn_pickup` returns `pickup_unit, pickup_unit_go_id` (pickup_system.lua:1207); the hook captured only the first (`local spawned = func(...)` / `return spawned`), a VMF_RECIPES §2 multi-return collapse. Almost every vanilla caller discards the 2nd value, but the linked-pickup RPC path (pickup_system.lua:1441) uses it: `local pickup_unit, pickup_unit_go_id = self:_spawn_pickup(...)` then, if the pickup links to a surface, `send_rpc_clients("rpc_link_pickup", pickup_unit_go_id, ...)` (:1447). With the go_id collapsed to nil, a surface-linked pickup couldn't be resolved/positioned on clients (host<->client desync; niche - only the link path). **Fix:** capture and re-return both - `local spawned, go_id = func(...)` / `return spawned, go_id`. The #294 residency guard's early `return` (nil, nil) already matches vanilla's own early returns, so it stays correct. No behavior change on any non-link path. Regression test `spawn_pickup_returns_both_values` (`/ct_regression_test`, source-pattern: both the two-value capture and two-value return survive). **[untested] - verify: in a 2-player CW session, spawn/throw a pickup that links to a surface (e.g. a projectile-delivered pickup that sticks); on the CLIENT it should render linked/positioned correctly, not floating or misplaced.**

## 0.7.223-dev (2026-07-04) - #299 FIXED: chest revive now returns the player to the team instead of stranding them at a distant beacon

- **#299 (bug) FIXED - "Chest of Trials Revive Teleport Fail": a chest-revived player was left alone far from the team.** Root cause verified against decompiled source. When `respawn_on_chest_complete` frees an AWAITING-RESCUE player via `StatusUtils.set_respawned_network`, that player stands up AT the respawn beacon they were hanging at - the unit is link-glued to its `flavour_unit` through the recovery animation (`player_character_state_waiting_for_assisted_respawn.lua:30` `enable_linked_movement`, `:59` disable on exit to "standing"), so it recovers wherever the beacon is. Same for the DEAD branch: zeroing `respawn_timer` makes `RespawnHandler` respawn them hanging at a beacon placed `ahead_unit_travel_dist + 70` (DEFAULT_RESPAWN_DISTANCE, `respawn_handler.lua:5`/`:682`), i.e. up to ~70m ahead of the front player. Either way the revive worked but dumped the player far from the group. **Fix:** the chest hook now arms a deferred host-side pass (`mod._ct_chest_teleport_tick`, driven from the single `mod.update` owner) for the two distant-beacon cases (awaiting-rescue + dead); the KNOCKED-DOWN case is revived in place (already with the team) and is NOT armed. The pass polls each armed player and, the instant they become controllable (`Unit.alive` AND `not status:is_disabled()` - i.e. linked-movement recovery done / dead-respawn spawned + standing, when `locomotion:teleport_to` will actually stick), teleports them to the nearest living teammate to the chest. Host-authoritative, mirroring `RespawnHandler.server_update`'s own player move (`respawn_handler.lua:398-407`): `locomotion:teleport_to(pos, rot)` + `send_rpc_clients("rpc_teleport_unit_to", ...)`. TTL of 20s drops the arm if the player never becomes controllable (re-downed / left). This is also the ordering the reporter asked for ("before bots split/teleport to the player where they respawn"): the human rejoins the team the moment they can move, minimizing the window a bot would leash out to the old beacon. No new `mod:hook` (folded into the existing `_set_state` hook + the existing `mod.update` drainer); no new menu toggle (it's part of the existing revive feature). Marker `/ct_regression_test` check `chest_revive_team_teleport_wired` (asserts the tick fn + pending table + the feature checkbox). **[untested] - verify: in a CW run with `respawn_on_chest_complete` ON, die and reach the awaiting-rescue hang far from the group (or be fully dead), then complete a Chest of Trials; expect to be revived AND pulled to a teammate, not left at the beacon. Re-check the bot behavior around the freed player.**

## 0.7.222-dev (2026-07-04) - #294 (crash) FIXED: non-resident pickup unit CTD via ct's _spawn_pickup hook

- **#294 (crash) FIXED - CTD spawning a non-resident pickup unit (skulls_2023 `pup_skull_of_fury`) through ct's `_spawn_pickup` hook.** Root cause: vanilla `PickupSystem._spawn_pickup` (pickup_system.lua:1207) calls `unit_spawner:spawn_network_unit(unit_name, ...)` at :1290 with NO residency check, and a non-resident `unit_name` crashes deep in `add_unit_extensions` (`entity_manager2.lua:114: table index is nil`). Vanilla HAS the check - `PickupSystem._safe_to_spawn_pickup` (pickup_system.lua:878) does `if not Application.can_get("unit", unit_name) then return false` - but only calls it on some spawn paths, NOT the one that reached ct's hook (:1414). The trigger here was a `skulls_2023` mutator force-spawned via a gt devtool without the mutator package resident, so `units/mutator/skulls_2023/pup_skull_of_fury` was non-resident (cosmetics_tweaker's own hat-spawn guard logged `SKIP non-resident spawn` for the same unit the same tick; ct's pass-through hook did not guard and proceeded to crash). **Fix:** ct's `_spawn_pickup` hook now pre-checks `mod._ct_pickup_unit_spawn_safe(settings)` before calling vanilla, mirroring vanilla's own `_safe_to_spawn_pickup` (`Application.can_get("unit", settings.unit_name)`); a genuinely non-resident unit is skipped (return, exactly as the vanilla safe-check would) with a `[ct:294]` printf, instead of crashing. The guard fails SAFE - it never blocks a pickup with no named unit, a `spawn_override_func` (custom spawn path), or when `can_get` is unavailable - so a resident pickup is never false-dropped. Marker `CT_PICKUP_RESIDENCY_GUARD_MARKER` + `/ct_regression_test` check `pickup_residency_guard_installed` (asserts the helper classifies nil/override as safe and a bogus unit path as unsafe). **[untested] - verify: with the guard live, force-spawn skulls_2023 skull pickups (Skull of Fury) in a CW/test context where the mutator package isn't resident; expect no CTD (the pickup silently doesn't spawn, `[ct:294] SKIP` in the log) instead of the entity_manager2 crash.**
- **Note (separate latent bug, NOT fixed here):** ct's `_spawn_pickup` hook captures only the first of vanilla's two return values (`local spawned = func(...)` / `return spawned`), dropping `pickup_unit_go_id`. Only one vanilla caller uses it - the linked-pickup RPC path (pickup_system.lua:1441 -> `rpc_link_pickup`) - so a pickup that links to a surface won't sync its link to clients while ct is active. This is a pre-existing VMF_RECIPES §2 multi-return collapse, tracked separately as #322; left out of this crash patch to keep it focused.

## 0.7.221-dev (2026-07-04) - Localization: applied dev status-tag doctrine (#301)

- **Localization: applied dev status-tag doctrine (#301).** Every option-title loc entry that matches a live widget `setting_id` now carries a status tag prefix. 524 titles tagged: 442 [working], 58 [untested] (pre-existing untested tags preserved, e.g. the Banned Weapon Traits and Boss Grudge Mark banlist rows), 24 issue-tagged. Issue tags map open GitHub issues to the exact feature they name, with co-tags: [crash] on progressive_difficulty (#291) and cot_enemy_multiplier (#262); [verify-fix] on curse_lighting_brightness (#243), inject_adventure_maps (#156/#52/#251), flesh_guard_clouds_per_minute (#104), disabled_boons_group (#211), finale_dominant_god (#145/#56), finale_approach_god (#146), altar_reuse_count_upgrade (#252/#102), any_trait_any_weapon (#260), tweak_trait_tier_by_rarity (#119), bomb_boon_cooldown (#120), tweak_manann_tempest_cooldown (#133), rv_no_save_morgrim (#259), chest_boon_count (#114), shrine_boon_count (#115), ct_meta_ammo boon disable/start (#256/#249/#131); [diag] on cursed_chest_count (#132/#60), boss_grudge_marks_group (#107), bots_mirror_host_weapon_upgrades (#121); plain [Issue N] on starting_boons_group (#144), tweak_anath_raema_permanent (#288), respawn_on_chest_complete (#299). Tags-only change: no runtime/behavior effect (VMF sorts by localized label but ignores tag prefixes). Orphan loc entries for disabled boons (dormants, Skulls-event boons, ct_kill_heal, old category-group names) were left untagged since they no longer back a live widget.

## 0.7.220-dev (2026-07-04) - #291 (crash) FIXED: Progressive Difficulty CTD on winning a CW journey at Cataclysm 2/3

- **#291 (crash) FIXED - winning a Chaos Wastes journey with Progressive Difficulty on CTDs at the finale.** Root cause is our own `progressive_difficulty` ramp, NOT a third-party mod. The ramp steps a CW run up to `cataclysm_3`, but vanilla `StatisticsUtil._register_completed_journey_difficulty` resolves the difficulty via `Managers.state.difficulty:get_default_difficulties()` = `DefaultDifficulties`, whose top entry is base `cataclysm` (`difficulty_settings.lua:412`). `cataclysm_2` / `cataclysm_3` are absent, so `table.find` returns `nil` and the next line does `current_completed_difficulty < nil` -> `attempt to compare number with nil` (decompiled `statistics_util.lua:1054`, shipped bytecode reports `:997`). Winning the Citadel final round at `cata2`/`cata3` therefore crashed on the journey-stat write. Confirmed in two logs (console 2026-07-04 19.45.55 on Khorne Citadel, and issue #291's 03.27 on Slaanesh Citadel): the crash fired ~1s after `[ct:progdiff]` logged `-> difficulty=cataclysm_3`, `difficulty_index=nil`, with Onslaught + "Cata 3 & Deathwish" BOTH disabled. **Fix:** a guard hook on `StatisticsUtil._register_completed_journey_difficulty` clamps only the RECORDED difficulty to the highest tier the vanilla journey-stat DB can represent (`cataclysm`) when it isn't in `DefaultDifficulties`. The player keeps journey-completion credit at that ceiling; the in-mission gameplay difficulty is untouched (the guard does not feed `get_run_difficulty`). Also shields against Onslaught / "Cata 3 & Deathwish" exposing the same tiers by other paths. The vanilla per-LEVEL recorder already guards this (`if difficulty then`, `statistics_util.lua:1013`), so only the journey recorder needed it. Loremaster's Armoury also hooks this function but forwards args unchanged, so the clamp reaches the vanilla body regardless of chain order. Marker `CT_JOURNEY_DIFFICULTY_GUARD_MARKER` + `/ct_regression_test` check `journey_difficulty_guard_installed` (asserts the marker, the hooked fn, and that `cataclysm_3` is still absent from `DefaultDifficulties`). **[untested] - verify: win a CW journey (Citadel) with Progressive Difficulty on so the ramp reaches cata3, confirm no CTD at the final-round-won screen.**

## 0.7.219-dev (2026-07-03) - CT backlog batch B (graph-gen cluster): #145 fix + #146 feature + #135/#56 probes

Isolated from batch A because these touch the regression-prone deus graph generation. All fold into existing hooks (no new `mod:hook`). **[untested] - graph-gen; verify in-game before trusting.**

- **#145 (Citadel finale god mismatch) FIXED + #146 (separate approach god) FEATURE.** New `mod._ct_force_finale_god` post-processes the FINISHED graph (called in both `deus_populate_graph` branches after `func`), rewriting the god segment of `arena_citadel_*` (finale) to `finale_dominant_god` and `sig_citadel_*` (approach) to the new `finale_approach_god` (0 = follow finale). This restores the override's authority WITHOUT touching `config.NO_DOMINANT_GOD`, so regular missions keep all 4 gods (disable_dominant_god intact) while only the Citadel maps honor the chosen god(s). Level keys `arena_citadel_<god>_path<N>` / `sig_citadel_<god>_path<N>` exist for all 4 gods and aren't aliased, so swapping only the god segment (keeping `path<N>`) is always a valid level. The curse is re-matched to the new god from the synced `level_seed` (deterministic per peer); an empty pool keeps the vanilla curse. Deterministic on host + client (host-synced settings), and the host re-broadcasts the graph snapshot, so no RPC-timing race. **[untested] - CONFIRM the non-Tzeentch `arena_citadel` variants actually LOAD (the Citadel is canonically Tzeentch; khorne/nurgle/slaanesh variants exist on disk but need an in-game load check), and that approach != arena when `finale_approach_god` differs.**
- **#146 UI:** new "Citadel Approach God" dropdown (`finale_approach_god`, default "Same as Finale God"), host-synced automatically.
- **#135 (weekly god mismatch) - probe.** `[ct:god135]` in `game_round_ended` logs weekly/vote god vs the finale setting vs the resolved `dominant_god`. If resolved == chosen but a different god renders, that's #145 (now fixed); only `resolved != chosen` would be a selection bug. No selection bug found in code.
- **#56 (Citadel curse client divergence) - probe.** `[ct:curse56]` runs on BOTH peers after the graph broadcast/apply, logging each Citadel node's curse/theme so a host-vs-client mismatch is captured (the #136 RPC-ordering seam). With the #145 fix both peers force the same curse deterministically, so this should now show host == client.

## 0.7.218-dev (2026-07-03) - CT backlog batch A: #157 crash fix, #143 + #259 fixes, #258/#271 lighting, + probes for #52/#68/#105/#121/#131/#249/#273

Backlog push (investigation-agent findings, applied + verified against decompiled source). Fixes and read-only diagnostic probes; no graph-gen changes (those ship separately in batch B).

- **#157 (crash) FIXED - cross-char weapon CTDs the CW loadout backend.** `BackendInterfaceDeusBase.set_loadout_item` fasserts "Item %q doesn't exist" when a wt cross-char item's items-backend id (never granted into the deus mirror) is routed through the deus loadout override. Guard hooks on the DERIVED class `BackendInterfaceDeusPlayFab` (class() copies base methods at definition, so the base is never hooked): `set_loadout_item` bails on a non-deus id (keeps the current valid deus weapon); `get_total_power_level` nil-skips a missing entry (defensive). `[ct:crash157]` logs a block. [untested]
- **#143 FIXED - Morgrim's Bomb over-spawn.** The morgrim143 census proved it is the world spread-pool sampler (`source=spawner`). On injected maps we HALVE `holy_hand_grenade`'s `spawn_weighting` and redistribute the freed half proportionally to the other grenades, so the pool SUM is byte-identical (crash-safe: the v0.7.143 crash was from LOWERING the total; a sum-preserving redistribution cannot reintroduce it). Restored after populate so vanilla Adventure / real CW are untouched. `[ct:morgrim143]` logs the renorm (before/after sums must match). [untested]
- **#259 FIXED - Morgrim's not consumed with RV 'bomb re-use on ability'.** The existing toggle only shimmed the `not_consume_grenade` PROC path; the RV lvl-30 talent saves via the `free_grenade` PERK (`action_charged_projectile.lua:84`), which was unblocked. Added a `has_buff_perk` shim that denies `free_grenade` for Morgrim's UNLESS `rewield_grenade_on_throw` is present (the Endless Bombs combo uniquely grants that, so #101 is preserved). `[ct:morgrim259]` logs saved/endless_bombs. [untested]
- **#258 FIXED - Well of Dreams (dlc_termite_3) too dark under Tzeentch.** New per-map brightness table `_CURSE_MAP_BRIGHTNESS`: doubles `ambient_tint_top` on that map under Tzeentch only. Applied inside the existing `shading_callback` on top of the profile + global knob; missing map/theme/channel = 1.0 so no other map regresses. [untested - visual]
- **#271 FIXED - Devious Delvings (dlc_termite_2) ~2x brighter.** Same table doubles the four interior levers (fill/ambient/amb_top/exposure) for every curse on that map = "brightness knob 2.0 for this map only". [untested - visual]
- **#105 (probe) - elf longbow reverts at CW altar.** The issue's "altar re-rolls the native pool" premise is DISPROVEN by source (`upgrade_item` preserves `deus_item_key`). `[ct:xchar105]` logs pre/post key on the upgrade-altar generation; if key is preserved the drop is render-side (wt), not ct.
- **#121 (probe) - Blessed Bots extra tier.** #100 + #102 already closed the two known off-by-ones; parity holds statically. `[ct:bots121]` logs bot-before/after rarity vs host tier to catch any residual.
- **#131 (probe, root-caused) - Moonfire fires more shots.** `we_deus_01` (Moonfire) is the ONLY energy weapon, so `ct_meta_ammo`'s per-shot drain discount (floored 0.25) = up to 4x shots. `[ct:moonfire131]` logs vanilla-vs-discounted cost + energy pool. A fix (exclude Moonfire from the discount) is a design call - flagged for the user.
- **#249 (probe) - client ammo HUD desync.** `/verify_meta_ammo` extended with `[ct:ammo249]`: dumps the wielded ranged weapon's real `_max_ammo`/`_available` vs HUD `ammo_count()`/`remaining_ammo()`. Run on host + client to capture the "36 vs 62" split.
- **#273 (probe) - Kruber weapon reverts to base Greatsword after a run.** `[ct:revert273]` on `game_round_ended` (CW-exit loadout) + a new `BulldozerPlayer.spawn` hook (keep-entry loadout) to capture the before/after slot keys.
- **#52 (probe) - Tower of Treachery gargoyle skulls missing.** `[ct:skull52]` object-set census folded into the #156 `get_object_sets` hook: lists every set + whether it spawns under deus, so the skull-bearing set is identified.
- **#68 (probe) - Belakor path variants render as altars on the map.** `[ct:mapnode68]` folded into the `DeusMapScene.on_enter` loop: logs each node's resolved 3D model, so the `*_belakor_path1` -> SHRINE offenders are captured for a targeted rewrite.

## 0.7.217-dev (2026-07-03) - NEW FEATURE: Progressive Difficulty (mission difficulty ramps up through a run)

- **New "Progressive Difficulty" toggle** (default OFF, top of the ct menu). The first TWO missions of a Chaos Wastes run use your starting difficulty; every mission after that steps up one tier, capping at Cataclysm 3. Start on Legend -> M1/M2 Legend, M3 Cataclysm, M4 Cataclysm 2, M5 Cataclysm 3 (cap). Start on Cataclysm -> M1/M2 Cataclysm, M3 Cata 2, M4 Cata 3 (cap). Never steps onto Versus.
  - **How:** hooks `DeusRunController.get_run_difficulty` and returns a stepped difficulty computed from the run's captured starting tier (`setup_run` arg) + the run controller's completed-level count (the mission ordinal: at mission N, `get_completed_level_count()` == N-1, so `step = max(0, completed - 1)`). That value flows through `deus_mechanism.get_next_level_data` -> the level transition -> `state_ingame.lua:245 Managers.state.difficulty:set_difficulty(...)`, which the host RPCs to every client - so the whole lobby ramps together. Difficulty tiers/ranks read from the engine's `Difficulties`/`DifficultyLookup` globals, capped at `cataclysm_3`.
  - **Safe by construction:** the CW path graph is generated ONCE at `setup_run` and takes NO difficulty argument (`deus_generate_graph`), so stepping difficulty can never reshape the graph or the mission/curse/god layout. Stepping is deterministic on every peer (host-synced start tier via `effective_setting` + synced completed count), so there is no host/client RPC-timing race. Host-controlled.
  - `[ct:progdiff]` logs the tier once per mission. Regression marker `progressive_difficulty_installed` self-tests the ramp (first two missions hold, mission 3 = start+1, and it caps at cataclysm_3). **Caveat:** a peer that HOT-JOINS mid-run inherits the host's already-stepped tier as its base and could over-step; peers present at run start are unaffected. [untested] - needs an in-game CW run to confirm the tier climbs each mission and syncs to clients.

## 0.7.216-dev (2026-07-03) - fix two dead/lying diagnostics: perf-census enemies=-1, and the pickup/chest event subscriber

- **Dead diagnostic revived: the deus pickup/chest event subscriber never attached.** `_ct_diag_subscriber` was a `setmetatable({}, { __mode = "v" })` WEAK-VALUED table whose values are the handler functions - referenced nowhere else, so the GC collected them between file-load and the first mission. By registration time `_ct_diag_subscriber.player_pickup_deus_weapon_chest` was nil, so `EventManager.register` fatally fasserted "No function found with name ... on supplied object" (`event_manager.lua:16`) inside the pcall on EVERY map populate (`[diag] subscriber register failed: ...`) - and the intended pickup/chest telemetry (which backs the #251/#156 chest diagnostics) never ran. Fixed by making it a plain strong table; both event names (`player_pickup_deus_weapon_chest`, `chest_unlock_failed`) are verified real game triggers, so the handlers now actually fire. Found in the #276 + author logs (2026-07-03).
- **#104 perf census - `enemies=-1` fixed.** The first census (v0.7.214) read `Managers.state.conflict_director._num_spawned_ai`, but the ConflictDirector manager is `Managers.state.conflict` (that other key is nil), so every `[ct:perf]` line logged `enemies=-1`. Corrected to `Managers.state.conflict`. Now the census reports the live alive-AI count alongside `flow_states`, so the next repro shows whether flow-state load tracks enemy count (dynamic objective_unit tags) or is level-baked (static). **Data so far (v0.7.214/.215 logs, 2026-07-03):** FPS tracks `flow_states` - `dlc_castle` flow=157 held ~60-76 fps, but `dlc_dwarf_whaling` (Parting of the Waves) and `dlc_termite_2` flow=363-425 dropped to 32-45 fps with 100-111ms host frame hitches (max flow_states 425). The flow_states were notably STABLE per map, which hints level-baked more than enemy-tag; the fixed enemy count will disambiguate.

## 0.7.215-dev (2026-07-03) - #133 Manann's Tempest trait description + #252 temper-altar re-roll prompt

- **#133 (Manann's Tempest description doesn't reflect the 8s cooldown) - FIXED for the weapon TRAIT.** ct already appended "8 second cooldown." to the mod BOON description (`description_ct_boon_manann_tempest`) when `tweak_manann_tempest_cooldown` is on, but the tweak also applies the 8s cooldown to the VANILLA weapon trait `deus_crit_chain_lightning` (the form most players meet, since the mod boon is opt-in/default-off) - and its description was never overridden. Added a branch to the existing `_G.Localize` hook (no new hook) that appends the same note to `description_deus_crit_chain_lightning` when the tweak is on, using `func(key, ...)` so it's EXACTLY vanilla with the tweak off. [untested] - enable the tweak, hover a weapon carrying Manann's Tempest in CW, confirm the "8 second cooldown." line.
- **#252 (temper altar shows red 'same rarity' message on same-tier re-roll) - FIXED.** The v0.7.211 decouple made a re-armed upgrade altar lit + interactable at the same rarity, but `DeusUpgradeWeaponInteractionUI._populate_widget` runs its OWN `weapon_rarity_order < chest_rarity_order` test and at same tier paints the red `reliquary_inactive_rarity` text. ct had never hooked that UI. New `hook_safe` on the derived class repaints the panel as available (item tooltip + rarity + cost) with a white `reward_info_text` of "Re-rolls this weapon's traits and properties" - but ONLY for a re-armed (`uses>0`) upgrade altar at EXACTLY the same rarity order (a genuine downgrade keeps the red text and stays blocked by `can_be_unlocked`; a genuine upgrade already hits vanilla's available branch). Mirrors vanilla's available-branch field writes (`deus_upgrade_weapon_interaction_ui.lua:62-91`), gated on `profile_synchronizer:others_actually_ingame()` like the neighboring hook, fully pcall-guarded so any API drift falls back to the vanilla (red) prompt rather than crashing. Marker `reliquary_reroll_message_hook`. [untested] - use a temper altar, return while wielding a same-rarity weapon, confirm the panel shows the item + cost + re-roll message (white) and the interact still re-rolls props/traits.

## 0.7.214-dev (2026-07-03) - #104 perf census + #120 bomb-boon cooldown + #260 trait melee/ranged split

- **#260 (melee-only traits appear on RANGED weapons) - FIXED.** The "Any Trait on Any Weapon" path (`apply_weapon_trait_filter`) assigned ONE cross-slot global union (`get_all_trait_combos()`, melee+ranged) to every weapon, so a ranged weapon could roll a melee trait at Exotic/Unique. Now, when the toggle is on, each weapon expands to the trait union of its OWN combat class only, reusing the already-correct class classifier `mod._ct_get_trait_class_pools()` (melee/ranged keyed off the `deus_*` pool names) and the same `is_ranged = not trait_table_name:find("melee")` slot test the tier path uses. Lifts the weapon-TYPE restriction (any trait within the slot) while strictly keeping the melee/ranged split. Falls back to the old global union only if `WeaponTraits.combinations` isn't loaded yet (early-timing safety), and to the weapon's own pool if a slot list is empty (never zeroes a weapon out). Tooltip updated to match. [untested] - in CW, roll a ranged weapon (staff/handgun/brace) to Exotic/Unique and confirm zero melee traits; roll a melee weapon and confirm zero ranged traits.
- **#119 (Trait Tier by Rarity restricts by weapon type) - no code change; already fixed in v0.7.177-dev.** The tier path (`get_tier_filtered_combos` + `_ct_get_trait_class_pools`) already draws from the whole melee/ranged class union, not the weapon's narrow type subset. Left untouched to avoid regressing that fix; needs an in-game confirmation pass (open a sword, an axe, a 2H and confirm each offers the full melee set). If weapon-TYPE restriction still shows here, it is a separate early-timing fallback (WeaponTraits not loaded at roll time) - capture the log rather than re-patching.

- **#120 (Bomb Boon Cooldown does nothing) - FIXED (hook was never installed).** Root cause: the override hook was registered against `BuffFunctionTemplates.functions.drop_item_on_ability_use`, but that key is `nil` there - `drop_item_on_ability_use` is a PROC function, dispatched via the global `ProcFunctions[buff.buff_func]` (`buff_extension.lua:1351`) and registered through `DLCSettings.morris.proc_functions` -> `DLCUtils.merge` (`buff_templates.lua:9589`). So the install guard was always false and `mod:hook` never ran = total no-op (exactly "does nothing"). Retargeted the hook to the global `ProcFunctions`; the dispatch re-reads `ProcFunctions[name]` every proc so a table-entry hook is honored. The wrapper now also captures and RETURNS the proc's value (`success` gates `remove_on_proc` removal at `buff_extension.lua:1354`; vanilla returns nil so it's behavior-identical today, but correct if a future patch changes it). The live-buff duration rewrite is unchanged and re-anchors to the original drop (idempotent). **Note: the data default is `0` = leave vanilla untouched, so you must set a nonzero Bomb Boon Cooldown for the change to take effect.** [untested] - confirm in-game via the `[ct-bomb-boon] drop_item cooldown overridden -> Ns` log line (its ABSENCE in prior builds was the never-installed signature) and a visibly shorter re-drop interval.

- **#104 (host FPS drops on injected maps) - live load census.** New `[ct:perf]` printf, folded into the existing `CameraManager.shading_callback` hook (no new hook) and sampled every `CT_PERF_WINDOW` (5s) on EVERY injected-adventure frame (placed before the curse-theme early returns so it runs cursed or not). Each line reports `level`, `theme`, `avg_fps`, `worst_frame_ms`, `flow_states` (`NetworkedFlowStateManager._num_states`), and `enemies` (`ConflictDirector._num_spawned_ai`) for the window. **Why:** the user localized the drop to the **first-grimoire Chest of Trials on Blood in the Darkness** (not the whole map), which points away from #104's original per-frame curse-lighting suspect and toward the same cursed_chest `objective_unit` / networked-flow-state load that overflowed the 512 cap in #262 - each Chest-of-Trials trash spawn carries a linked `objective_unit` with a networked `chest_open_state`, and hundreds of those tank framerate well before they crash. A repro at the chest now shows whether `flow_states`/`enemies` spike in lockstep with `worst_frame_ms`. Cheap per frame (one guarded clock read + a counter). Marker `perf104_census_installed`; `/ct_regression_test`. Diagnose-before-mitigate: this ships the instrument only - no perf change yet. Cross-refs #262, #251.

## 0.7.213-dev (2026-07-03) - HOST CRASH FIX: NetworkedFlowStateManager "Too many object states(512)" overflow guard

Fixes the recurring host crash `"[NetworkedFlowStateManager] Too many object states(512)."` (fatal `fassert` at `networked_flow_state_manager.lua:381`). Reproduced this session on **dlc_termite_3_tzeentch_path1** (Devious Delvings / Tzeentch) with a **Chest of Trials active and enemy_tweaker caps raised** - host crashed, client (same run) survived, confirming a host-authoritative flow-state overflow (crash dump `console-2026-07-03-18.41.50-d6dbb15d`).

**Why the existing leak fix wasn't enough.** ct already hooks `NetworkedFlowStateManager.clear_object_state` to fix the vanilla `_num_states` LEAK (destroyed units never decrementing the counter). That fix is correct and complete for CHURN - `entity_manager2.lua:390` clears every destroyed unit's state and we decrement it. But the 512 cap can be hit by states that are **genuinely live**: a Chest of Trials terror event applies the `cursed_chest_objective_unit` buff to EVERY non-special trash spawn (`deus_generic_terror_events.lua:26`), and each buff spawns a `units/hub_elements/objective_unit` carrying a `chest_open_state` networked flow state (`morris_buff_settings.lua:614`). Under enemy_tweaker's raised spawn caps a chest fight holds 512+ live objective_units at once (and `mark_for_deletion` lags actual destroy), so no leak fix can reclaim them.

**Fix: overflow guard on the create path.** New hook on `NetworkedFlowStateManager.flow_cb_create_state` (not previously hooked in ct_dev). Only when `_num_states` is within 1 of the cap, it (1) reclaims slots held by units that are already DEAD but whose destroy hasn't yet fired `clear_object_state` (mark_for_deletion lag / any residual leak), then (2) if STILL full, **declines the create** - returning the vanilla "not created" shape (nothing), which the flow callback already tolerates (`flow_callbacks.lua:1292 if created then`) - instead of letting the `fassert` fatal the host. A single trash-mob objective marker without its networked `chest_open_state` is a cosmetic degradation on that one unit; the alternative is a host crash that ends the whole team's run. The full-table sweep runs ONLY within 1 of the cap, so normal play (never near 511) pays zero cost. First decline logs `[ct:flowcap] ...` once per session via `printf`. Regression marker `networked_flow_state_cap_guarded`; `/ct_regression_test`. **Untested in-engine - needs a Chest-of-Trials run under raised enemy caps to confirm the host now rides through instead of crashing.**

## 0.7.212-dev (2026-07-03) - #143 + #145 diagnostics (read-only); #144 root-caused in code; #145 fix / #146 feature designed

Two read-only probes (both fold into existing hooks; no new `mod:hook`), plus code-level findings on #144 and #145. No behavior change.

- **#143 (Morgrim's Bomb too frequent) - appearance-by-source census.** `[ct:morgrim143]` printf tags every confirmed `holy_hand_grenade` spawn with its engine `spawn_type` at the single spawn chokepoint (`PickupSystem._spawn_pickup`): `spawner` = world spread-pool sampler (the vanilla `spawn_weighting=0.8` path, suspected origin), `guaranteed` = level-baked, `dropped` = `drop_item_on_ability_use` bomb-boon drop, `buff` = buff-spawned. This splits world-weight appearances from boon-driven ones - the exact measurement needed before a SAFE grenade-pool renormalization (the blind `spawn_weighting=0.1` cut in v0.7.143 crashed the sampler, `spawn_weighting_total < 1.0`, and was reverted). Folded into the existing `_spawn_pickup` hook. `/ct_regression_test morgrim143_probe_installed`.
- **#145 (Citadel of Eternity god mismatch) - resolved-god census + code root cause.** `[ct:citadel145]` printf logs, host-side, the resolved god/theme/curse/level for each Citadel sub-map (approach `sig_citadel*` + finale `arena_citadel*`) plus `NO_DOMINANT_GOD`, `dominant_god`, and both settings. **Root cause (code-proven):** `disable_dominant_god` (default ON) sets `config.NO_DOMINANT_GOD = true`, which makes vanilla SKIP the "reserve the dominant god for the finale" step (`deus_populate_graph.lua:686-690`). Since that reservation is the ONLY delivery vector for the `finale_dominant_god` override, the override is neutered and the two Citadel maps roll INDEPENDENT random gods - so a set Tzeentch landed on the approach by coincidence and Nurgle on the finale. Folded into the existing `game_round_ended` and `deus_populate_graph` hooks. `/ct_regression_test citadel145_probe_installed`.
- **#144 (starting boon lost) - not a code-visible grant-path bug.** Deep code trace: the starting-boon grant (`_add_initial_power_ups` hook) writes through the server-authoritative `set_player_power_ups` (append after vanilla), and every `add_power_ups` path (host + the `rpc_deus_add_power_ups` server merge) is append-only, and buff re-application is host-authoritative - so "acquiring another boon" cannot drop a prior boon. The only automatic remover is the team-WIPE defeat penalty (distinct trigger). The v0.7.211 `[ct:boon144]` list trace remains the correct instrument; awaits repro. (No new code.)
- **#145 fix + #146 feature: designed, not yet built** (both touch the regression-prone graph-gen and involve a design choice on how `disable_dominant_god` and the finale override should interact). Pending user direction.

## 0.7.211-dev (2026-07-03) - #102: multi-use temper altar no longer escalates upgrade rarity on reuse (reward decoupled from keep-lit)

Fixes the reported escalation where the **extra use** of a temper (upgrade) altar climbed the reward to exotic/unique. Root cause: `self._rarity` is BOTH the reward tier (vanilla `open_chest` -> `_generate_upgraded_weapon(..., self._rarity)`, `deus_chest_extension.lua:558`) AND the input to the dark/disable gate (`update_upgrade_chest_color:236` / `can_be_unlocked:513`, both `chest_rarity_order <= weapon_rarity_order`). The old v0.7.158 "goes dark after first use" fix kept a re-armed altar lit by bumping `self._rarity` strictly ABOVE the wielded weapon every re-roll - which leaked straight into the reward, climbing plentiful->rare->exotic->unique.

**Fix (Option B, user-chosen 2026-07-02): decouple the keep-lit visual from the reward rarity.**
- **Removed both `self._rarity` bumps** - the `_setup_rarity` hook (deleted) and the `open_chest` re-arm branch. `self._rarity` now stays at its constant per-`go_id` rolled tier, so **the reward never climbs**.
- **Added two relaxed-gate hooks** (`DeusChestExtension.update_upgrade_chest_color` and `.can_be_unlocked`, neither previously hooked in ct_dev) that, ONLY for a re-armed upgrade altar (`_altar_uses_by_go_id[go_id] > 0`), loosen the disable test from `<=` to strict `<`. A **same-tier re-roll stays lit and usable** (a rare altar re-rolls a rare weapon at rare, with fresh properties/traits via the existing `_generate_upgraded_weapon` seed-mix hook, or upgrades a still-lower weapon you switch to) while a genuine **downgrade still greys out**. Both hooks pass straight through to vanilla for first-use and every non-upgrade chest, so the only behavior change is the same-tier re-roll.
- Same-tier upgrade cost is populated and finite (`DeusCostSettings.deus_chest.upgrade[r][r] = base[r]*0.5`, e.g. rare 100, exotic 180), so `get_purchase_cost` / the cost branch of `can_be_unlocked` pass. Depletion is unaffected: a spent altar keeps `_is_purchased = true`, which both new hooks (and vanilla `can_interact`) already treat as unusable.
- **Likely side-benefit for #100** (bots landing one tier above the host): the bot-weapon-mirror reads the pre-bump `_opened_rarity`, which now equals the rolled tier for everyone. Not claimed fixed - needs a client in-game to confirm.
- Regression marker renamed `upgrade_altar_rarity_bump` -> **`upgrade_altar_rarity_decouple`** (asserts the bump is gone and the relaxed gates are present, guarding against a future session re-introducing the climb). The `altar_reuse_hook_on_open_chest` / `open_chest_hook_singleton` / `bot_weap_opened_rarity_pre_bump` markers are unchanged.

**Not addressed here: #103** (looted mesh flips on a non-final use) is a separate visual path (the `open_chest` re-arm's uncollect + `lua_update_<chest_type>` re-fire) and its multi-use repro has never been captured in a log - it stays armed-and-waiting, not touched by this decouple. **#102 fix is untested in-engine; needs a live multi-use temper-altar run to confirm the reward holds at the altar's tier.**

## 0.7.210-dev (2026-07-03) - #243: live "Curse Lighting Brightness" knob (self-tune the injected-map curse atmosphere)

- **New "Curse Lighting Brightness" numeric in the Curses menu** (`curse_lighting_brightness`, default 1.0, range 0.5-2.5). Multiplies the interior channels of the injected-map curse lighting (fill light, ambient bounce, exposure) in `CameraManager.shading_callback`, so a dark interior map that reads too dim under a curse (e.g. Devious Delvings under Be'lakor, #243) can be lifted to taste without washing out the exterior sky/sun/fog that carries the curse mood. **1.0 is behavior-identical to 0.7.209** (the knob only scales when moved). Host-synced like other settings (the host's value governs the lobby's curse atmosphere); only affects injected adventure missions, no effect on vanilla Chaos Wastes maps. This is the follow-up promised in the 0.7.209 note - the Be'lakor darkness is now tunable in-game instead of a hardcoded guess.

## 0.7.209-dev (2026-07-03) - Belakor curse lighting: stop crushing already-dark interior maps (CANDIDATE, needs in-game eyeball)

- **Be'lakor curse lighting brightened on injected adventure maps so already-dark interiors aren't near-black.** User reported Devious Delvings (`dlc_termite_2`, a Verminious Dreams mines map) going too dark under the Be'lakor curse. ct's per-curse lighting runs only on injected adventure maps (`CameraManager.shading_callback`, gated on `on_injected_adventure_level()`), and the Be'lakor profile's tints are **multiplicative** - so a factor below 1.0 on the interior channels (ambient bounce, fill light, exposure) crushes a scene whose baked atmosphere is already dim. Fix: the interior-bounce channels no longer darken at all (`ambient_tint` 0.75/0.65/1.00 -> 1.00/0.90/1.22, `ambient_tint_top` -> 0.92/0.85/1.18, `secondary_sun_color` fill -> 0.90/0.85/1.10, `exposure_mul` 0.92 -> 1.02); they now carry only the purple **hue** (green pulled below blue). The exterior sky + direct sun stay dim (sky 0.45/0.30/0.70, sun 0.62/0.60/0.92) so open-air Be'lakor missions keep their oppressive mood. Data-only change - no added per-frame cost (relevant to #104). **Visual tuning; not verified in-engine - needs the user's eyes. If interiors are now right but exteriors read too bright, or it is still dark, the next step is a live brightness knob.**

## 0.7.208-dev (2026-07-02) - #222 strict re-sweep: option tooltips no longer restate their title

VMF draws each option's title as the orange first line of the hover popup, then the
description below it (confirmed in VMF source options.lua: it builds the popup as
`title .. "\n" .. body`). The first #222 pass used too lenient a bar and left bodies that
opened by re-naming the option (e.g. "Opens the ..." under "Open ...", or a value-noun
echo under a slider title), so the name still showed twice. This pass rewrites 27
`_tooltip` bodies to open with the behavior, effect, or range instead. No magnitudes,
mechanics, `%%` escaping, host-only/mutex caveats, or boon-effect bodies were changed.

## 0.7.207-dev (2026-07-02) - #164: starting_coins VMF menu back to fine granularity (25-step moves to gut Mod Tweaker)

Per the binding 2026-07-02 direction: VMF's own options view stays at its natural fine granularity so the user can dial an exact pilgrim's-coin value (e.g. 324); the coarse 25-step now lives ONLY in gut's Mod Tweaker (#164). Removed BOTH ct-side snap paths that were forcing multiples of 25:

- **Removed the `on_setting_changed` snap** (`chaos_wastes_tweaker_dev.lua`) that rounded the persisted `starting_coins` value to the nearest 25 (`math.floor(v / 25 + 0.5) * 25` + write-back). The setting is now stored and applied verbatim as the run's starting coins at `setup_run`; any integer 0-3000 persists. Kept a guarded early return so control flow is unchanged (starting_coins drives none of the downstream syncs).
- **Removed the `VMFOptionsView.callback_draw_numeric_menu` pre-hook** (`chaos_wastes_tweaker_dev.lua`) that quantized the VMF slider's `internal_value` to multiples of 25 in real time (Issue #39). VMF's own slider now moves by 1 again, so an exact value like 324 is settable there. The unrelated Issue #40 mutex-checkbox visual-refresh hook (`callback_setting_changed`) is untouched; its header comment was trimmed to describe only the remaining hook.
- **Data comment** (`_data.lua`) for the `starting_coins` widget updated: documents that the fine-grained slider is intentional and that neither a `step` field nor a 3-element range may be added (a 3-element range is fatal to VMF's `validate_numeric_data`; a top-level `step` field is stripped by VMF's `initialize_numeric_data` at core/options.lua:439-448 and never reaches the Mod Tweaker). `range` stays `{ 0, 3000 }`.

No new settings, loc, or version-sync behavior. The `starting_coins` setter override + its regression checks (`starting_coins_setter_not_adder`, `starting_coins_value_matches_setting`) are unaffected: both read the raw setting, which is now simply un-snapped.

### Verify in-game
- Mod Options -> Chaos Wastes Tweaker -> Pilgrim's Coin: the starting-coins slider moves by 1 and you can set an exact value like 324; reopening the menu shows 324 (not snapped).
- The 25-step now lives in gut's Mod Tweaker (gut_dev 0.2.179-dev): ESC -> Mod Tweaker -> Chaos Wastes -> Pilgrim's Coin arrows move 25/click, Apply commits the snapped value.

## 0.7.206-dev (2026-07-02) - Finale God: numeric slider -> named dropdown

- **"Finale God" is now a dropdown of named gods instead of a 0-4 slider.** The old numeric widget required memorizing the value-to-god mapping; it now offers Weekly Rotation / Nurgle / Tzeentch / Khorne / Slaanesh directly. Purely a widget-type swap: the dropdown stores the same integer `value` (0 = weekly rotation, 1-4 = index into `FINALE_GODS = { nurgle, tzeentch, khorne, slaanesh }`, verified at chaos_wastes_tweaker_dev.lua:481 against the consumer at ~L3989), so every existing saved setting carries over unchanged and the apply-site code is untouched. Tooltip simplified (the numeric legend is now redundant). New loc keys `finale_god_rotation/nurgle/tzeentch/khorne/slaanesh`; new `finale_god_options` table in `_data.lua` (same shape as the existing `count_with_default_options` dropdown). `qa/check_localization.ps1` clean for ct_dev.

## 0.7.205-dev (2026-07-02) - #220 loc physical reorder (no runtime effect) + #144 boon-list diagnostic

- **#220 - localization file physically reordered to mirror the settings-menu widget tree.** `chaos_wastes_tweaker_dev_localization.lua` was in accretion order after the 0.7.202 menu reorg; its entries are now grouped under `-- ===` section banners matching the menu's top-level order (Meta, Adventure Maps, Banned Weapon Traits, Curses, Pilgrim's Coin, Reworks, Shrines/Altars/Chests, Mod Boons, Boon-Tree group names, then the generated Disabled/Starting boon pairs). **Zero runtime effect** - VMF reads the loc as a flat hash map. A comment-aware bucketer treated each `--[[ ]]` disabled block (ct_kill_heal; skulls-event/dormant) as an atomic unit; an independent guard proved content preservation (1045 entry-units + 1062-key value map byte-identical HEAD vs reordered, both `--[[ ]]` blocks verbatim, all entries comma-terminated so the permutation is valid Lua, 25-line tail loop unchanged). `qa/check_localization.ps1` clean for ct_dev (no new warnings).
- **#144 - diagnostic instrument (NO fix) for the "starting boon disappears" report.** User had Vaul's Anvil (`ct_boon_vauls_anvil`) as a starting boon; it vanished after acquiring another boon. Hypothesis was a fixed-size boon array overflowing. **Investigation finding (code-proven): there is NO fixed max-boon cap in vanilla** - a player's active power-ups live in a dynamic SharedState Lua table that `DeusRunController.add_power_ups` only ever `table.clone` + `table.append` + set (deus_run_controller.lua:1126-1141), and the network transport chunks long encoded strings rather than truncating (shared_state.lua:21/298). So overflow-overwrite is not supported by the engine. The instrument (folded into ct's existing single `add_power_ups` hook - no duplicate hook) snapshots the recipient's full boon list BEFORE and AFTER each grant via a read-only `mod._ct_boon144_list_snapshot` helper (`get_player_power_ups`, deus_run_controller.lua:1080) and emits raw printf: `[ct:boon144] pre-grant ... count=N list=...` / `[ct:boon144] post-grant ... count=M added=... list=...`, plus a `[ct:boon144] LOSS ...` line if the stored list ever shrinks across a grant (post < pre + #added). This distinguishes a genuine drop/overwrite from the starting boon simply never being persisted into the stored list (a persistence/re-sync path). Gated on `not _ct_bot_mirror_active`, whole block pcall-wrapped so it can never disturb boon application. New regression marker `boon144_list_trace_installed`.
  - **Repro for the user:** start a CW run with Vaul's Anvil as a starting boon (enable the "Vaul's Anvil as Boon" rework), acquire another boon at a shrine/chest, then send the log. If `pre-grant` already lacks `ct_boon_vauls_anvil` it was never stored (persistence bug); if `LOSS` fires it was dropped on the grant.

## 0.7.204-dev (2026-07-02) - #222 loc sweep: drop leading option-title restatement from tooltips

#222 loc sweep: removed leading option-title restatement from 23 option tooltips so the popup body no longer repeats the orange header (mutex-cluster opener hints preserved). Affected: `cursed_chest_count` and `tweak_poison_proof_duration`; the 13 Boss Grudge Marks banlist tooltips (`ban_grudge_mark_*`, "Bans the X mark, where..." -> "The boss..."); and the 8 mod-boon Rework variants (`disable_boon_ct_boon_*` / `start_boon_ct_boon_*`). No setting_ids, titles, magnitudes, or mechanical claims changed. `qa/check_localization.ps1` clean for this mod.

## 0.7.203-dev (2026-07-01) - Code-review batch: multi-return fix, alias-leak fix, dup-chip career fix, cache invalidation, dead-code cleanup

Reviewed, pre-approved fixes from a two-agent code review. No user-facing settings changed.

- **[BUG] Home Brewer `add_buff` multi-return collapse.** The `BuffExtension.add_buff` hook's guarded (scaled-potency) path did `local result = func(...)` / `return result`, collapsing vanilla's three return values (`id, sub_buffs_added, first_buff` - buff_extension.lua:517) to just the first. Any caller reading the 2nd/3rd return got nil. Now routed through the file's `_capture_returns` helper + `unpack(results, 1, n)`, matching the existing arity-preserving hooks. New marker `CT_HOME_BREWER_MULTIRETURN_MARKER` + regression check `home_brewer_add_buff_multireturn_preserved`.
- **[BUG] Adventure-pool `_dupN` alias leak.** `inject_pool()` runs on every pool-setting change; `reset_to_snapshot()` restored `LEVEL_AVAILABILITY` but not the `_dupN` entries added to `DEUS_LEVEL_SETTINGS` / `LevelSettings` / `NetworkLookup.level_keys`, and the mint loop skipped past existing `_dupN` names, so every re-run minted fresh aliases and grew the network-synced `NetworkLookup.level_keys` unboundedly. Alias creation is now idempotent: a module-level registry (`_M._dup_alias_registry`, keyed by journey+pool+slot) reuses the aliases already minted instead of coining new names. Entries are never removed from `NetworkLookup.level_keys` (removal can desync peers); reuse bounds the alias set at `POOL_SAFETY_THRESHOLD - 1` per pool.
- **[FIX] Duplicate-career vote chip showed a stale hero after a mid-view career change.** The extra-chip token cache in `_ct_dup_vote_chips.lua` was keyed by `peer_id` only, so a peer swapping careers on the map-vote screen kept the old career's token (wrong hero mesh). The cache key is now `peer_id` + `profile_index`, so a career change spawns a fresh, correct-mesh token; the `used` sweep and `DeusMapScene._clear` teardown use the same compound key. Also removed three unused locals (`Vector3`, `Vector3Box`, `Network`) left over from the v0.7.194 offset removal.
- **[HARDENING] Cache invalidation on mod disable.** `mod.on_disabled` now clears the two lazily-built, never-otherwise-invalidated trait-pool caches (`all_trait_combos_cache`, `mod._ct_trait_class_pools`) so a re-enable rebuilds them from current game data instead of serving a stale snapshot.
- **[MICRO] Blessed-bots per-frame hook reordered.** `PlayerBotBase.update` (fires ~60Hz per bot) now runs the 2s throttle check before the `mod:get` / `_is_server` calls, so the common path is just a blackboard read + a float compare.
- **Dead-code / dead-loc cleanup.** Removed the orphaned `granting_starting_coins` flag (declared, read in an always-true guard, never set since the v0.7.95 starting-coins setter rewrite) plus its stale comment block; the dead `altar_count_options` and `isha_alternative_options` option tables in `_data.lua`; and the orphaned legacy Isha dropdown loc keys (`tweak_miracle_of_isha_alternative_tooltip`, `isha_alt_vanilla`, `isha_alt_aegis`, `isha_alt_wounds`). Kept the base `tweak_miracle_of_isha_alternative` key (still read by the `_get_isha_mode` migration).
- **Docstring corrections.** `_ct_mechanic_tweaks.lua` header now says "one sync function" (the adventure-trait slider moved to gt on 2026-06-18); `chaos_wastes_tweaker_mutex.lua` header references (`career_tweaker.lua` -> `chaos_wastes_tweaker_dev.lua`, `/crt_status` -> `/cw_status`) corrected from career_tweaker copy-paste drift.

## 0.7.202-dev (2026-07-01) - Settings menu reorganization (sort + organize + polish; no functional changes)

Pure settings-UI pass. No setting_ids renamed, no settings added or removed, no behavior changed. Every user's saved config is preserved (settings are keyed by setting_id, which are untouched).

- **Top-level groups now sort A->Z by display label** (repo standing rule): Adventure Maps, Banned Weapon Traits, Curses, Disabled Boons, Pilgrim's Coin, Reworks, Shrines, Altars and Chests, Starting Boons. Previously accretion-ordered.
- **Within each group, options sort A->Z by display label** (status tag `[untested]`/`[confirmed working]` ignored for sorting), except deliberate orders which stay put and are flagged inline: the Miracle of Isha `(A)/(B)` mutex cluster, the god-grouped Disabled Curses banlist, and the paired count/cost-multiplier rows in Altar Reroll Options. The BOON_TREE-generated Disabled/Starting Boons trees are unchanged (their internal order is settled at build time by `recursive_sort`).
- **Adventure Maps: mission-selection list is now nested under its master toggle.** `available_missions_group` (the CW / campaign / event mission checklists) is now a `sub_widgets` child of the `inject_adventure_maps` checkbox, so it auto-hides when the master is off. This is purely visual and code-verified safe: `_adventure_pool.lua:747` returns early (all per-mission toggles ignored) when the master is off. `replace_shrines_with_missions` stays a loose sibling because it is NOT gated on the master (checked independently at `chaos_wastes_tweaker.lua:5661`).
- **Label polish (titles only; tooltips carry the detail):**
  - "Corrupted Flesh Curse: Max Gas Clouds per Minute" -> "Corrupted Flesh: max clouds per minute" (7 -> 6 words; #104 numeric, default 6, 0 = vanilla, unchanged).
  - "Finale God (0=weekly, 1=Nurgle, ...)" -> "Finale God"; the value legend moved into a new `finale_dominant_god_tooltip`.
  - "Cursed Mission Count (0 = vanilla)" -> "Cursed Mission Count" (the "0 = vanilla" detail is already in its tooltip).
  - "Adventure Maps in Chaos Wastes (experimental)" -> "Adventure Maps" (the "Experimental" warning already lives in the inject tooltip).
- No em dashes in any menu-facing string; all literal percents remain escaped as `%%`. `qa/check_localization.ps1` clean for this mod.

## 0.7.201-dev (2026-07-01) - Localization sweep: fix over-escaped percents, add missing dropdown keys, rewrite option descriptions

- **Fixed percent-sign rendering across the settings menu.** About 200 boon and rework tooltips were over-escaped as `%%%%`, which renders as a literal double percent in-game (e.g. "+X%% Damage" instead of "+X% Damage"). Normalized every one to the correct single `%%` per LOCALIZATION_STANDARD.md section 1 (VMF runs each localized string through one `string.format` pass, so one doubling is correct).
- **Added two missing dropdown labels.** The "Rework: Arena Ammo Boxes" dropdown referenced numeric options `0` and `10` that had no localization entry, so those two choices showed as `<0>` / `<10>`. Added `["0"]` and `["10"]`.
- **Rewrote option descriptions for players, not code.** Swept the mechanic / rework / bot / grudge-mark / potion tooltips to plain, 1-2 sentence English: removed engine and network jargon ("Host-broadcast", "reliquary", "talent set", "server-side"), a source-file reference (TRAITS_REFERENCE.md), and every em dash and arrow from menu-facing strings. Vanilla-style boon effect descriptions kept their wording. No setting_ids, defaults, ranges, or widgets changed.

## 0.7.200-dev (2026-07-01) - #156 object-set candidate fix, #211 disabled-boon bypass, #104 gas-cloud guard

### #156 - Horn of Magnus zero pickups: 'adventure' object-set candidate fix + spawner-count diagnostic

- **HYPOTHESIS-DRIVEN candidate fix, pending in-game verification.** The 2026-07-01 forensics (magnus_tzeentch_path1, v0.7.198) showed 100% spawn debt on all 13 pickup-type requests with ALL spawner lists empty at populate and `pickup_gizmo_spawned` never registering a unit - the gizmos never SPAWNED. Suspected mechanism: `GameModeSettings.deus.object_sets = { gm_sp = true }` vs adventure's `{ adventure = true, gm_sp = true }` - level units grouped in the `adventure` object set (membership lives in the level binary, unreadable offline) silently never spawn under the deus game mode.
- **Fix:** new table-form hook on `GameModeHelper.get_object_sets` (game_mode_helper.lua:58-111; returns `(object_sets_map, spawned_object_sets_array)`): when `game_mode_key == "deus"` AND the loading level key resolves through ct's STATIC adventure catalog (`AdventurePool.MISSION_BY_KEY`, deliberately not the toggle-gated `IS_INJECTED_ADVENTURE_LEVEL`, so host and clients decide identically) AND `LevelSettings[level_key].level_name` matches the level being spawned AND the level actually has an `adventure` set, append `"adventure"` to the spawned-sets array. Vanilla deus and vanilla Adventure are untouched (no catalog match / different game_mode_key). Engagement proof: `[ct:objset] injected adventure level <key>: enabling 'adventure' object set (issue #156)` (raw printf).
- **Diagnostic (lands regardless of the fix):** the `[populate_pickups]` printf now also carries `spawners: primary=N secondary=N guaranteed=N` at populate entry (field names verified against vanilla pickup_system.lua:64/75/76). All-zero on an injected level = level-load problem; nonzero = the veto is downstream.
- **Verification steps:** host a CW run, get Horn of Magnus (or any injected adventure map). Expect (1) the `[ct:objset]` line at level load, (2) nonzero `spawners:` counts on `[populate_pickups]`, (3) `[ct-spawn-tally] total>0` and actual chests/altars/pickups in-game. CAVEAT: enabling the `adventure` set may also spawn other adventure-only units on injected maps - eyeball for oddities (out-of-place props, event units).

### #211 - disabled boons still granted: bot random-boon bypass fixed + grant-source tracing

- **ROOT CAUSE (code-proven):** the bot-boon mirror's random mode (`bots_get_random_boons`) picked from the RAW `DeusPowerUpsArrayByRarity` bucket - which is only stripped of disabled boons inside the `generate_random_power_ups` remove-then-restore window - and then granted via `add_power_ups` with the pre-grant gate deliberately skipped (`_ct_bot_mirror_active`). That is the only in-code path that can produce the observed `[boon-trace] DISABLED BOON GRANTED` lines (the trace only fires in the add_power_ups hook, and the gate strips everything else). Fits all 4 host-side hits (grenadier / deus_second_wind / deus_push_charge in one minute on skaven_stronghold = one host grant mirrored to bots; skill_by_block on nurgle_belakor).
- **Fix:** `_pick_random_for_rarity` now filters the bucket through the new shared `mod._ct_boon_disabled(name)` helper (also now used by the roll-pool strip's `_should_strip` and the pre-grant gate - one check, three call sites, behavior-identical for checkbox booleans). Empty filtered bucket falls back to mirroring the host's (already-gated) boon. Defense-in-depth: the bot clone loop also skips any disabled name outright and printfs `[bot-boon] SKIPPED disabled boon` if that ever fires. Bomb-boon exclusivity / altar no-repeat are NOT applied to bot picks - both are per-recipient state this rarity-matched pick never consulted (unchanged behavior).
- **Grant-source tracing (raw printf - the host runs VMF logging OFF):** every grant through `add_power_ups` now logs `[boon-trace] grant source=<tag> boon=<name> rarity=<r> disabled=<bool> ... (issue #211)`. Tags: `bot_mirror`/`bot_random` (ct's bot loop), `set_reward` (new `DeusRunController._check_set_completed` wrapper), `cot_view_pick` (new `DeusCursedChestView._on_button_pressed` wrapper), `untagged` = the boon-ALTAR grant inside `DeusChestExtension.open_chest` (not pre-taggable: ct's only open_chest hook is the consolidated post-call hook_safe, and VMF drops a second hook on the same method - that path is double-covered by the pool strip + pre-grant gate anyway). Gate blocks also printf now.
- **Full vanilla grant-path map** (documented in-code above the tagging hooks): covered by pool strip - altar stored roll, shrine shop offerings, Chest of Trials picks, end-of-level random grants (these write run_state directly and never enter add_power_ups; the pool strip is their only filter). Covered by pre-grant gate - everything calling add_power_ups. Deliberately NOT covered - `_add_initial_power_ups` (the player's own talents-as-boons + live-event boons; stripping would desync shared run state), `grant_party_power_up`/Belakor quest challenge reward + node `terror_event_power_up` party grants (specific named power-ups written to party state / activated directly). These are instrumented-by-map only; if a future log shows a disabled boon from one of them, that map says exactly where to gate.
- New regression marker `boon_disable_shared_gate` (helper present + sane on unknown/nil keys).

### #104 - Corrupted Flesh gas-cloud FPS guard + AoE attribution

- **Rate guard:** new table-form hook on `ProcFunctions.mark_of_nurgle_explosion` (morris_buff_settings.lua:2254-2299 - the exact function that spawns the globadier-class cloud + nav-tag volume + rpc_area_damage; resolved by string at proc time per buff_extension.lua:1350, same mechanism as the #129 Mathlann guard). Host-side rolling 60s window; when the window is full the proc returns WITHOUT calling vanilla - no cloud unit, no nav volume, no RPC (the mark's other on_death buffs run normally; guard-vs-bail audited). Suppression log (rate-limited to 1 per 5s): `[ct:flesh_guard] suppressed gas cloud (n this window, cap=N/min, issue #104)`.
- **New setting:** "Corrupted Flesh Curse: Max Gas Clouds per Minute" (`flesh_guard_clouds_per_minute`, numeric 0-30, **default 6**, 0 = vanilla/uncapped) in the Curses menu. Default 6/min roughly halves the observed bastion peak (11/min) while leaving the 2.7/min steady rate untouched. Joins the host-synced registry automatically (every non-per-peer widget does via `_collect_setting_ids`); only the host evaluates the gate - the buff sits on host-side AI units and `spawn_network_unit` is server-only, so clients pass through untouched and no extra sync wiring is needed.
- **AoE attribution (logging gap):** each allowed cloud logs `[ct:aoe] template=corrupted_flesh_explosion buff=mark_of_nurgle_death_explosion source=<breed> window_n=N cap=N` (or `cap=off` when uncapped) - scoped to this deus curse mechanism only, so ordinary combat explosions never spam it (observed max 11/line-min).
- **Verification steps:** run a corrupted-flesh CW mission (nurgle theme). Expect `[ct:flesh_guard] ... guard installed` at load, `[ct:aoe]` lines per cloud, and `[ct:flesh_guard] suppressed ...` lines once the per-minute cap engages during dense fights; FPS during marked-enemy deaths should hold.

## 0.7.199-dev (2026-07-01) - Boon-offer scrollbar + boon-count caps raised to 50

- **Scrollbar for the shrine and cursed-chest boon offerings.** The shrine (DeusShopView) and cursed chest (DeusCursedChestView) lay their offered boons on a fixed vertical arc that never scrolls, so offers beyond the visible rows were stranded off-screen. Now, when a shrine offers more than 4 boons or a chest more than 3, the arc flattens into a row-snapped vertical list with a track+thumb scrollbar to the right of the boon column. Scrolling: mouse wheel (1 row per notch), clicking the track above/below the thumb (page a full window), or dragging the thumb (jump to any row). Off-window rows park far off-screen, so they cannot be hovered or bought until scrolled to; blessings and the shop's owned-boons side panel are untouched. At or below the vanilla row counts the views stay byte-identical vanilla (the single-boon NaN fix still runs).
- **Boon-count caps raised 5 -> 50** for both `shrine_boon_count` and `chest_boon_count` (defaults unchanged: 4 / 3). The existing count-override hook already passes any value through; the scrollbar is what makes counts past ~4 actually usable.
- Implementation: one consolidated `_ct_boon_scroll` block in the main lua. Setup merges into the two existing `*_create_ui_elements` hook_safe bodies (VMF one-hook-per-method rule); two new wrapping `update` hooks run scroll input + reflow before vanilla draws each frame, pcall-guarded so any vanilla shape change degrades to "no scroll" instead of crashing the view.
- Verification: not yet checked in-game. On view open with an over-cap offer, the log line `[ct:boon_scroll] engaged: N boons offered, ...` proves the path ran; a keep-side `/verify_*` command is impractical here because the state only exists while a shrine/chest view is open.

## 0.7.198-dev — 2026-07-01 — Logging discipline: demote the deus-chest fallback warning

The `[deus-chest] … injected a balanced fallback` message was firing at **warning** level on every native CW path mission (dlc_castle_*, cemetery_*, etc.) that ships no `deus_weapon_chest_distribution` — but injecting that fallback is the correct, intended behavior (it's what prevents vanilla's assert). A warning should mean "maybe a problem"; this is working as designed, so it's now a file-only `_dbg` line, not a warning. Audited the rest of ct's ~25 warning/alert sites — all others are genuine (regression FAILs, RPC schema mismatches, vanilla-call-raised recoveries, "investigate" traces), so they stay.

## 0.7.197-dev — 2026-06-30 — Shrines/Altars/Chests fully grouped (no loose options)

The Shrines, Altars and Chests menu is now four clean collapsibles with nothing dangling: **Altars & Chests per Mission**, **Altar Reroll Options**, **Boons Offered** (Shrines/Chests Number of Available Boons), and **Chest of Trials** (Revive on Chest Completion + Enemy Count Multiplier). Two new groups (`boons_offered_group`, `chest_of_trials_group`) absorb the former loose options. Pure menu structure — no setting_ids or behavior changed.

## 0.7.196-dev — 2026-06-30 — Group the per-mission count sliders under one collapsible

Follow-up to .195: the five per-mission spawn-count sliders (Upgrade Altars, Melee Swap Altars, Ranged Swap Altars, Boon Altars, Chests of Trials per Mission) are now under a single nested collapsible group, **"Altars & Chests per Mission"** (`altar_chest_counts_group`), instead of loose in the Shrines, Altars and Chests menu. With the groups-first layout rule, this collapsible and "Altar Reroll Options" both sit above the loose options (Number of Available Boons, etc.). No setting_ids changed — pure menu structure.

## 0.7.195-dev — 2026-06-30 — Shrines/Altars/Chests menu: layout rule, renames, count sliders

- **Menu-layout rule enforced globally:** collapsible sub-menus (`type = "group"`) now always render ABOVE loose options in the same parent (stable partition in `recursive_sort`). "Altar Reroll Options" now sits at the TOP of the Shrines, Altars and Chests menu instead of the bottom.
- **Renames:** "Shrine Boon Options" → **"Shrines: Number of Available Boons"**; "Chest Boon Options" → **"Chests: Number of Available Boons"**.
- **Count settings are now sliders (were dropdowns), no "Default" list entry:**
  - **Upgrade Altars / Melee Swap Altars / Ranged Swap Altars / Boon Altars** → numeric sliders, range **-1 to 9** (-1 = Default). Identical value semantics to the old dropdown, so no behavior change.
  - **Chests of Trials per Mission** → numeric slider, range **0 to 5, default 1**. The old -1/Default is gone; since the cap code already maps -1→1, default 1 matches vanilla's usual 1 per mission. (A legacy saved -1 still reads safely in code.)

## 0.7.194-dev — 2026-06-30 — Duplicate-career chips: implicit (no toggle) + #122 floating fix

- **Removed the "Map Screen" menu group + the "Show Both Chips for Duplicate Careers" toggle.** Showing both vote chips when two players share a career is a purely-corrective display fix, so it's now an **implicit, always-on** feature — no toggle, no menu group. (`show_duplicate_career_chips` / `map_screen_group` removed from data + loc; `_setting_on()` now always true.)
- **#122 — duplicate chips no longer hover above the map / land in odd places.** Root cause: `_place_dup_token` placed the chip at the correct vanilla node+slot pose but then added a token-LOCAL nudge (`+0.45 x`, `+0.35 z`) + `0.72` down-scale to "distinguish" it. Because the CW map is viewed at an angle, a token-local `+z` becomes an up/away translation in world space — that's the float. The distinction was also unnecessary: each duplicate voter already owns a **distinct vanilla slot** (its peer ordinal), and vanilla's four authored slot poses already fan the chips around a node. Fix: place using **vanilla's exact `DeusMapScene._place_token` math and nothing else** (`node_local_pose × referenced_token_poses[slot]`) — flat, correctly positioned, same size as every other chip. Needs an in-game check with two players on the same career.

## 0.7.193-dev — 2026-06-30 — Altar Reroll menu rename + #103 altar-collapse-animation fix

- **Menu rename:** "Altar Reuse (reroll bad picks)" → **"Altar Reroll Options"**.
- **#103 — altar model no longer stays collapsed after a single use (while uses remain).** A re-armed altar kept its glow (open_chest re-fires `lua_update_<chest_type>`) but its physical model stayed in the collapsed/looted pose. Root cause: vanilla `purchase()` fires `lua_update_collected` — the structure-collapse flow event — which is ONE-WAY (vanilla altars are single-use), so re-firing the arm event restores the hologram but not the structure. Fix mirrors the **Peregrinaje** mod's approach (prevention, not reversal): a new `DeusChestExtension.purchase` hook suppresses ONLY the `lua_update_collected` event when the altar will re-arm (uses remaining), so the structure never collapses. The final use still collapses normally. Everything else about `purchase()` (cost, purchased/looted state, loot RPC) is byte-identical, and the filter installs/restores under `pcall` so it **fails safe** — if it can't install, the altar collapses exactly as before (no regression to glow/cost). Needs an in-game check (altar visuals can't be validated offline).

## 0.7.192-dev — 2026-06-30 — #205 follow-up: DEBOUNCE the settings re-sync (Apply-button burst)

Completes the #205 fix for the **Apply button** case. The gut Mod Tweaker stages edits and commits the whole batch on Apply, firing `on_setting_changed` hundreds of times in one frame. The .191 supersede guard already prevented the *crash* (queue capped at one sync), but each of those calls still re-encoded all 489 settings to JSON inline → hundreds of redundant encodes in a single frame = a CPU **hitch**.

- `on_setting_changed` now marks the synced registry dirty + arms a 0.5 s countdown instead of broadcasting inline; `mod.update` fires **one** encode + **one** 46-chunk sync after the burst settles. Applying a few hundred settings = one sync, no hitch.
- `setup_run` still broadcasts immediately (single call at run start). The .191 supersede guard stays as belt-and-suspenders. Mid-run edits reach clients ~0.5 s later — harmless (clients apply on the next boon/altar roll).

## 0.7.191-dev — 2026-06-30 — CRASH FIX: host settings-sync flood → reliable-queue overflow (#205)

**Dual-log-confirmed host crash.** Editing ct settings rapidly (e.g. dragging sliders / toggling in the gut Mod Tweaker) in the Chaos Wastes keep with a client connected could crash the host. `mod._ct_broadcast_host_settings` is re-called by `on_setting_changed` on every synced-setting change, and each call enqueues the **full 489-key / 46-chunk** snapshot. The #97 fix paces the chunk *send rate* but doesn't stop rapid edits from **stacking** multiple full trains — ~4–5 stacked (204 chunks / 94 KB) overran Stingray's reliable send queue (~97 KB cap) → host wedged. Evidence: host log ended on `Reliable send queue overflow ... rpc_mod_user_data, count: 204`; the client received `46 chunks, 489 keys` at the same instant, then timed out 11 s later (`Rx age server 11.1s`).

- **Fix:** `_ct_broadcast_host_settings` now **supersedes** pending host-settings chunks — it purges any un-drained `ct_sync_host_settings_chunk` entries from the paced FIFO before enqueuing a fresh snapshot. A new full snapshot makes the old one redundant, and the receiver discards never-completed sessions, so this is safe and caps the host-settings queue at one sync (~46 chunks) no matter how fast you edit. Graph-snapshot / peer-manifest chunks untouched.
- Same crash CLASS as #97 / #129; distinct trigger (settings sync via Mod Tweaker edits, not hot-join graph sync).

## 0.7.190-dev — 2026-06-30 — Disabled Curses menu: god-prefixed + renamed + alphabetized

The "Disabled Curses" checkboxes now read `Disable: <God>: <Curse>` and are alphabetized by that label (god, then curse). God grouping is taken verbatim from vanilla `deus_map_populate_settings.lua` `all_curses` — including the non-obvious `skulking_sorcerer` = **Nurgle** (not Tzeentch).

- Renamed **"Abundance of Life" → "Unquenchable Thirst"** (`disable_curse_abundance_of_life`, Slaanesh) — the engine codename is ironic (the curse drains life); "Unquenchable Thirst" is the in-game name.
- All 14 curse labels gained their host-god prefix (Belakor treated as a god for prefixing); the two `[confirmed working]` QA tags moved to a trailing position so they don't break the alphabetical sort.
- Reordered the menu widgets in `*_data.lua` to match (menu order is widget order, not loc order). No `setting_id` changed → saved values + all `disable_curse_*` reads are unaffected.

## 0.7.189-dev — 2026-06-29 — HOTFIX: revert fatal 3-element starting_coins range (mod was dead, #164)

**0.7.188-dev broke the entire mod.** Its `starting_coins` range `{ 0, 3000, 25 }` was rejected by VMF at options-init time — `'range' field must contain an array-like table with 2 elements` — which aborts ct's ENTIRE options registration, so the mod never finished loading (no `[ct:LOAD]`, every CW tweak gone) on every host. The .188 claim that "VMF ignores the extra range element" is false: a 3rd element is **fatal**, not ignored.

- Reverted the range to `{ 0, 3000 }` (2 elements). The 25-coin snapping was never dependent on range[3] — it lives in `on_setting_changed` (chaos_wastes_tweaker.lua) and continues to work for ct's own menu.
- `#164` (making the **gut Mod Tweaker** cross-mod slider snap to 25) is NOT solvable via a VMF range[3] — VMF refuses to store it, so gut could never read it back. That needs a different, gut-side mechanism; reopening #164 to track.

## 0.7.188-dev — 2026-06-29 — starting_coins step 25 (gut Mod Tweaker reads range[3], #164) [REVERTED in .189 — broke the mod]

`starting_coins` widget range is now `{ 0, 3000, 25 }`. The 3rd element is the step the gut Mod Tweaker reads (#164) so its slider snaps to 25 instead of 1. VMF ignores the extra range element. **← This was wrong; the 3-element range is fatal to VMF options init. See .189.**

## 0.7.187-dev — 2026-06-29 — #58/#156: UNCONDITIONAL spawn census (Horn of Magnus "nothing spawns")

The recurring intermittent bug where a Chaos Wastes Horn of Magnus / injected-adventure mission spawns with NO chests, NO altars, NO pickups was never diagnosable from a log: the only evidence was `has_pickup_settings` + the *configured* `cursed_chest_count`, never what ACTUALLY spawned. Closed that hole.

- **`[ct-spawn-tally]` per-mission census (raw `printf`, always captured).** Counts every pickup that passes through `PickupSystem._spawn_pickup` — the single chokepoint for BOTH the spread pass (ammo/healing/potions/coins) and the guaranteed pass (Chests of Trials, Belakor altar, caskets) — keyed by final pickup_name. Emits ONE summary line ~8s after the host's `populate_pickups` (guaranteed-spawn pass is done by then): `level= injected= adv_base= diff= total= ZERO= | chests(cursed= weapon=) altar= coins= potions= | <full breakdown>`. `total=0` on an injected level is the unambiguous "this map is broken" signal. Wired into the EXISTING `_spawn_pickup` hook + the EXISTING `mod.update` drainer (no new hook, no second update owner) — marker `CT_SPAWN_TALLY_v1_unconditional_census`.
- **`[populate_pickups]` line now also logs `injected=` + `adv_base=` + `diff_has_entry=`.** `injected=false` on a `magnus_*`/`military_*` CW level is the prime root-cause suspect: it means `on_injected_adventure_level()` returned false, so the whole adventure→deus bridge in `_can_spawn` is skipped and EVERYTHING is vetoed. `diff_has_entry=false` reproduces the vanilla "NO PICKUP DATA FOR CURRENT DIFFICULTY → USING SETTINGS FOR EASY" fallback. Together these say WHY in the same breath as the census says WHAT.
- Both use raw `printf`, so they land on a VMF-logging-OFF host with no dump command and no debug toggle (unaffected by the .186 `_dbg`→`mod:debug` routing).

## 0.7.186-dev — 2026-06-28
- Removed per-mod debug toggle; diagnostics now route through VMF logging (mod:debug / mod:warning), gated by VMF output_mode_debug / output_mode_warning. (#169)

## 0.7.185-dev (2026-06-28) — regression coverage for the two closed issues that lacked it (#100, #101)

User audit caught that #100 (bot upgrade rarity) and #101 (Endless Bombs / Morgrim's) were closed without `_rt_register` checks (#117 already had one — `cursed_chest_unique_trials`, behavioral). Added marker-sentinel checks per the repo convention:
- `CT_BOT_WEAP_OPENED_RARITY_MARKER` + check `bot_weap_opened_rarity_pre_bump` — guards the pre-bump `_opened_rarity` capture so bots can't regress to mirroring the bumped next-use rarity (one tier above host).
- `CT_ENDLESS_BOMBS_MARKER` + check `endless_bombs_strip_on_expiry` — guards the strip-leftover-on-EXPIRY approach against reverting to the wrong consume-on-drink (.178) / continuous-eat (.179) forms that broke the intended potion+Morgrim's combo.
- Verified `dbg_helpers_two_channel` still passes after the .183 `_dbg`→`printf` change (it asserts helper existence + safe no-op, not `mod:info`).

## 0.7.184-dev (2026-06-28) — diagnostics sweep follow-up: /dump_* and /verify_* commands always print

- The .183 sweep routed the manually-invoked `/dump_*` and `/verify_*` command handlers through `_dbg` (gated by `enable_debug_logging`) — wrong UX, since the user types those to diagnose and expects output immediately. Promoted 29 command-output lines (`/verify_grudge|belakor|coins|engineer_bombs|meta_ammo|altars`, `DUMP:grudge_marks|potions|boon_loc|boon_deep|buff_deep|mutators|traits|adv_names`, `/dump_journey`, `/dump_isha`) from `_dbg` → unconditional `pcall(printf, …)`, so they print on invocation regardless of the debug toggle.
- Runtime `[belakor:diag]` traces (fire on game events, can repeat) stay gated `_dbg` — correct. Cumulative final state: 51 `pcall(printf)`, 126 `_dbg`, 0 `mod:info` calls.

## 0.7.183-dev (2026-06-28) — diagnostics visibility sweep: kill the mod:info blind spot

The user runs VMF's global mod-logging OFF, so EVERY `mod:info` line was invisible — including the mod's own `enable_debug_logging` path, so turning on debug logging did nothing visible.

- **Keystone:** `_dbg` / `_dbg_alert` helpers now emit via `printf` instead of `mod:info` (still gated by `enable_debug_logging`). Turning on debug logging now actually produces captured output (39+ call sites unblocked at once).
- **Sweep (all ~179 direct `mod:info` calls):** failure/error paths + one-shot load/version/RPC-schema/sync-handshake lines → unconditional `pcall(printf, …)` (~30, low-volume, always captured); all other diagnostics → routed through `_dbg` (gated, now-visible, silent when debug off, so no spam in friends' logs). 0 real `mod:info` calls remain (1 match is a comment). `mod:echo` (in-game chat) untouched.

## 0.7.182-dev (2026-06-28) — #156 diagnostic: make the "no pickups" probe VISIBLE (printf, was mod:info)

- #156 (Horn of Magnus / `magnus_belakor_path1` sometimes spawns zero pickups when injected into CW): the existing `[populate_pickups] … has_pickup_settings=…` defensive diagnostic used `mod:info`, which is suppressed because the user runs VMF mod-logging OFF — so it logged 0 times and the recurring bug (first seen 2026-05-22) was never diagnosable. Converted to **unconditional `printf`** (once per mission load, host-side), added `difficulty=`. No dump commands / debug toggle needed; the next host-side repro will auto-log `has_pickup_settings=false` (the smoking gun: vanilla `populate_pickups` early-bails on nil `pickup_settings`). Cause-confirm before fixing — see #156.

## 0.7.181-dev (2026-06-28) — #101 follow-up: un-stick the bomb pose after stripping

- When the leftover Morgrim's was stripped while the player was *wielding* it, destroying the grenade slot left them stuck in the bomb/throw pose on an empty slot (couldn't switch weapons). Now: capture the wielded slot before the strip, and if it was `slot_grenade`, interrupt the weapon action (`CharacterStateHelper.stop_weapon_actions`) and `wield("slot_melee")` (slot 1). No swap if they were already on melee/ranged at expiry.

## 0.7.180-dev (2026-06-28) — #101 REDONE correctly: strip leftover Morgrim's on potion EXPIRY (not consume on drink)

The whole approach was wrong (mine and the original). The intent: Endless Bombs is MEANT to work with Morgrim's — players save a Morgrim's to throw during the potion. The only exploit is the leftover: don't throw your last Morgrim's before the potion ends and it persists (duplicated) for reuse.

- **Reverted** the v0.7.178 drink-time consume AND the v0.7.179 continuous mid-potion consume — both wrongly deleted Morgrim's and broke the intended combo.
- New behavior: at DRINK, the apply-hook only RECORDS a flag (`buff.ct_endless_had_morgrim`) if you held a Morgrim's; Morgrim's stays fully usable for the whole potion. At EXPIRY (`remove_deus_potion_buff`, the shared deus-potion remove func, flag-gated so other potions are untouched) any leftover `holy_hand_grenade` in `slot_grenade` is removed. Markers: `[endless-bombs] drink: … had_morgrim=…` / `[endless-bombs] potion ended -> stripped leftover Morgrim's`.
- Setting renamed to "No Morgrim's Carry-Over (Endless Bombs)" + tooltip rewritten to match.

## 0.7.179-dev (2026-06-28) — #101 continuous-consume (drink-time consume wasn't enough)

### #101 — Morgrim's now stays consumed for the whole Endless Bombs duration
- v0.7.178 fixed the drink-time consume (log-proven: slot -> grenade_frag_01), but the player REACQUIRES Morgrim's ~1.5s later while the potion is still active (log `console-2026-06-28-00.50.57`: L11576 consume -> L11605 grenade slot = holy_hand_grenade again; 1 human + 3 bots, bots/pickups re-supplying), so it returns as the endless bomb = the "repeated use" still happening.
- Added a second hook on the buff's per-tick `update_pockets_full_of_bombs_buff`: while Endless Bombs is active and the toggle is on, any `holy_hand_grenade` that re-enters `slot_grenade` is destroyed (vanilla's own refill then restores `frag_grenade_t1`). Net: you cannot hold/throw Morgrim's at all for the potion's duration — it's always a frag. Only acts when Morgrim's is present (no per-frame churn otherwise). Marker `[endless-bombs] re-acquired Morgrim's during Endless Bombs -> destroyed slot_grenade`.
- NOTE (separate, not yet addressed): bots passing/dropping Morgrim's to the player mid-potion is itself odd behavior — flagged for its own investigation (bot-aid give vs `drop_item_on_ability_use` boon).

## 0.7.178-dev (2026-06-28) — #101 Endless-Bombs-consumes-Morgrim slot fix; #118 trait gate corrected to white-only; #117 closed

### #101 — Endless Bombs now actually consumes Morgrim's Bomb
- The consume hook on `apply_pockets_full_of_bombs_buff` checked `slot_level_event`, but Morgrim's Bomb (`holy_hand_grenade`) lives in **`slot_grenade`** (`deus_blessing_settings.lua:85`). `slot_level_event` is empty at drink time, so the branch never fired. **Log-validated** (`console-2026-06-28-00.11.23…log`): line 14995 `[SharedState] grenade:…= holy_hand_grenade` (Morgrim's in the grenade slot), line 15113 `[endless-bombs] … level_event_item=nil -> consume_morgrim=false` (old check missed it), lines 15115+ `wt … slot=slot_grenade key=holy_hand_grenade` (kept after drinking = the "repeated use" bug).
- Fix: scan `slot_grenade` first, `slot_level_event` as fallback, and `destroy_slot` whichever holds `holy_hand_grenade`. Vanilla `update_pockets_full_of_bombs_buff` then refills `slot_grenade` with `frag_grenade_t1` — Morgrim's eaten, normal endless (frag) bombs remain. Diagnostic relabeled `morgrim_in=<slot>`.

### #118 — trait gate corrected: only WHITE (`plentiful`) starters stay trait-less
- v0.7.177 over-excluded: it gated `plentiful` OR `common`, blocking traits on green (`common`/"uncommon") weapons. Per user, green is uncommon and SHOULD get traits. Gate now bails only on `plentiful` (white starting tier); `common`/`rare`/`exotic`/`unique` are all trait-eligible (`override_traits_in_result`).

### #117 — closed (user-confirmed working in v0.7.177-dev)

## 0.7.177-dev (2026-06-27) — bug batch: traits (#118/#119), Chest-of-Trials uniqueness (#117), chest revive (#116), bomb-boon cooldown (#120), grudge-mark ban (#107); #102/#103 + #122 deferred with plans

Six fixes + two researched deferrals. Build: clean (3 bundles).

### #118 — "Any Trait on Any Weapon" no longer gives traits to common/starting weapons
- `chaos_wastes_tweaker_dev.lua` `override_traits_in_result` (the single trait-injection chokepoint): added a rarity gate so the tier-by-rarity injector bails when the rolled rarity is `plentiful` or `common`. White/starting weapons stay trait-less regardless of which trait toggle is active (vanilla only grants traits at exotic/unique; this keeps the low tiers vanilla-clean).

### #119 — "Trait Tier by Rarity" no longer restricts by weapon TYPE (melee/ranged only)
- Rewrote `get_tier_filtered_combos`: instead of drawing from the weapon's OWN `baked_trait_combinations` (already narrowed by `compatible_weapon_list` — a weapon-type restriction), it now draws from the full **melee** or **ranged** trait UNION (classified at runtime from `WeaponTraits.combinations` deus pools), gated only by the rolled rarity tier (`TRAIT_RARITY_POOL`) and the ban list. A weapon is no longer confined to its own type's trait subset; fire/heat staves draw from the whole ranged pool too. New helper `mod._ct_get_trait_class_pools` (stored on `mod` to respect the 200-locals chunk cap). Regression test `fire_weapon_tier_fallback_nonempty` replaced by `tier_by_rarity_class_union_ranged`.

### #117 — Chest of Trials: unique trial each time, now ALWAYS-ON + guaranteed
- Removed the `cursed_chest_unique_trials` toggle (widget + loc deleted; behavior forced on).
- Added a second, deterministic uniqueness layer: a `TerrorEventMixer.start_event` wrapper force-rotates each `cursed_chest_prototype` `inject_event` block's `event_name_list` to a single pick that DIFFERS from that block's previous pick this mission (`mod._ct_cot_rotate_pick` + per-block `_ct_cot_block_last`, reset per mission/run). The existing seed-perturbation layer (now unconditional) still varies sub-challenges. Host-authoritative, template save/restore around the vanilla call. Marker bumped to `cot_unique_trials:force_rotate_event_name_list_v0.7.177`.

### #116 — "Revive Team on Chest Completion" now actually revives
- Rewrote the `DeusCursedChestExtension._set_state` (OPEN) body to port general_tweaker's proven per-player respawn primitive (`_gt_host_respawn`) across every party slot: awaiting-rescue (hanging) → `StatusUtils.set_respawned_network`; knocked-down → `StatusUtils.set_revived_network`; dead/queued → zero `respawn_timer`. The prior body never handled awaiting-rescue players (the gap that made it look dead) and leaned solely on `force_respawn_dead_players` (kept as a belt-and-suspenders catch-all). Verbose `mod:info` spam replaced with raw `printf` (lands on a logging-OFF host).

### #120 — "Bomb Boon Cooldown" now takes effect
- The old implementation mutated the SOURCE `DeusPowerUpTemplates` cooldown table, but the runtime buff resolves `buff.template` from a registered copy (same copy-vs-source trap that forced the reckless_swings dual-patch) — so it did nothing. Added a hook on the live `drop_item_on_ability_use` proc that, after vanilla runs, overrides the `drop_item_on_ability_use_cooldown` buff's duration to the user's configured interval (works for intervals shorter OR longer than vanilla 180/180/120; 0 = vanilla). Host-synced interval.

### #107 — Be'lakor Shadow Lieutenant now honors the grudge-mark ban list
- Extended the existing `TerrorEventUtils.apply_breed_enhancements` diagnostic hook to FILTER: on the host it strips any enhancement whose `.name` maps to a banned `ban_grudge_mark_<name>` setting before vanilla applies. Because this is the universal apply chokepoint, one filter covers the SL's hardcoded `POSSIBLE_SHADOW_LIEUTENANT_GRUDGE_MARK_NAMES` pool (which bypasses `_G.BossGrudgeMarks`), the random boss roll, and `grudge_mark_commander`. `BreedEnhancements[key].name == key == ban setting suffix` (direct map); `base` is never banned. Diagnostic printf retained (`applied=[...] banned_stripped=[...]`).

### #102/#103 — Altar exotic-escalation + "used up" mesh (DEFERRED with concrete plan)
- Left a source-grounded `TODO #102/#103:` block at the `_setup_rarity` hook. The escalation is the rarity-bump that keeps the altar lit; the clean decouple (remove bump; relax `can_be_unlocked` + `update_upgrade_chest_color` from `<=` to `<` for re-armed altars so same-rarity re-roll is allowed and lit) is well-understood but this altar re-arm path has regressed across 6 versions and is unverifiable offline. Not shipped blind.

### #122 — Duplicate-career chips mis-position (DEFERRED with concrete plan)
- Left a `TODO #122:` block in `_ct_dup_vote_chips.lua` detailing the borrow-an-unused-character-token + vanilla-`_place_token` + re-skin approach. Networked 3D map-scene UI with existing regression coverage; needs a live 2-same-career lobby to verify.

## 0.7.176-dev (2026-06-26) — #134 DIAGNOSTIC: collectible → Pilgrim's Coin spawn probe (instrument, NOT a fix)

DIAGNOSTIC ONLY — Ravaged Art (`painting_scrap`) + Loot Dice (`loot_die`) + lore pages (`lorebook_page`) appear in-mission on CW adventure maps instead of converting to Pilgrim's Coin (#134). All three conversion paths gate on `on_injected_adventure_level()` (deus run AND `adventure_base_from_level_key(level)` recognised), so the prime suspect is that gate being false on the affected maps.

- One printf `[ct-probe:collectible]` line per collectible reaching the final spawn (`PickupSystem._spawn_pickup` — added a log call inside the EXISTING hook, no new hook). Fields: `name spawn_type on_adv in_coin_set deus level adv_base`. The gate breakdown (`on_adv`/`deus`/`adv_base`) shows WHY it isn't converting; `spawn_type` shows HOW it was spawned.
- Bounded 80 lines/session, pcall-guarded, raw printf (survives mod-logging-off). Changes no conversion logic. (Issue #134)

## 0.7.175-dev (2026-06-26) — revert #132/#134/#136 diagnostics (KEPT the #133 cooldown wording)

Reverted the #132/#134/#136 printf diagnostics per user request — the chest probes already exist (the Issue #60 `[ct-probe]` budget/spawner probes are untouched), and the weekly-god / mission-divergence instrumentation is a separate concern. Removed:
- the `[ct-probe:chestcount]` hook (`DeusCursedChestExtension.extensions_ready`, #132/#60),
- the `[ct-probe:collectible]` probe folded into `PickupSystem._spawn_pickup` plus its comment header (#134),
- the `[ct-probe:mission]` hook (`GameModeManager.gm_event_round_started`, #136),
- the per-mission counter resets these added in `DeusRunController.setup_run`, `DeusMechanism._transition_next_node`, and `PickupSystem.populate_pickups` (`_ct_chestcount_n` / `_ct_collectible_probe_n`), and the `_ct_chestcount_cap` / `_ct_chestcount_level` stash in the populate probe. All four were implicit globals with no `local` declaration, so no orphan locals remain.

**KEPT the #133 Manann's Tempest "8 second cooldown." description line** (conditional on `tweak_manann_tempest_cooldown`) — untouched. Surrounding lifecycle function bodies restored intact. No behavior change beyond removing the log lines. `MOD_VERSION` `0.7.174-dev` → `0.7.175-dev`.

## 0.7.174-dev (2026-06-26) — #133 Manann's Tempest cooldown wording (conditional) + #132/#134/#136 diagnostics (instruments, NOT fixes)

One small text fix plus three printf diagnostics. The diagnostics are **instruments only** — they do not fix #132/#134/#136; they exist so the next session can read the actual numbers/tags from the user's log.

### #133 — Manann's Tempest description reflects the 8-second-cooldown tweak (text fix)
- `chaos_wastes_tweaker_dev.lua` (`_G.Localize` hook, ~3990) — when `tweak_manann_tempest_cooldown` is **active**, the boon description `description_ct_boon_manann_tempest` now appends a second line **`8 second cooldown.`**; when the tweak is **off** the description stays **EXACTLY** vanilla. Conditional via `effective_setting` (host-synced) and resolved live on each tooltip render — same pattern as this file's Khaine's Fury / Miracle descriptions. No `%` in the appended text. The cooldown itself is unchanged (`ProcFunctions.chain_lightning` hook, `MANANN_TEMPEST_COOLDOWN_S = 8.0`). NOTE: the tweak's data-file `default_value` is `false` (off) in this build, so the line shows only after the user enables the tweak. Awaiting the user's in-game eyeball.

### #132 — DIAGNOSTIC: actual cursed-chest count per mission (also #60)
- New hook `DeusCursedChestExtension.extensions_ready` (distinct method from the existing `_set_state` hook — VMF-clean, lint-confirmed) increments a per-mission tally and emits **`[ct-probe:chestcount] spawned=N cap=M level=L is_server=B`** for every cursed chest, whichever path spawned it (capped conversion OR baked spawner). The highest `spawned=N` for a level is the ground-truth chest count — compare to `cap` to confirm the Khazukan over-spawn (expect `spawned=5 cap=3`). Tally resets in `populate_pickups` (host) + the two `_ct_cursed_chest_seq` reset sites. **Cap logic unchanged.**

### #134 — DIAGNOSTIC: adventure-collectible → Pilgrim's Coin conversion
- The user sees **Loot Dice + Ravaged Art** in-mission on CW-injected adventure maps instead of Pilgrim's Coin. Added a bounded, pcall-guarded probe **inside the existing `PickupSystem._spawn_pickup` hook** (no new hook) that, inside a CW run, logs each adventure collectible as it spawns: **`[ct-probe:collectible] tag=… level=… deus=yes adv_base=… on_adv=… in_coin_set=… converted=yes/no spawn_type=…`**. `tag` ∈ {`loot_die`,`lorebook_page`,`painting_scrap`}. This reveals WHY `loot_die` isn't converting (e.g. `on_adv=false` because `adventure_base_from_level_key` didn't match the level permutation, or it spawned via a path that bypasses this hook) and confirms `painting_scrap` (Ravaged Art) is NOT name-converted — it relies on the `_can_spawn` spawner-eligibility mapping (`painting_scrap` spots → `deus_soft_currency`). Per-mission cap of 40 lines; counter resets alongside the chest tally. **Conversion/eligibility logic unchanged.**

### #136 — DIAGNOSTIC: host/client CW mission divergence
- New hook `GameModeManager.gm_event_round_started` (fires once per peer when the round begins, level fully loaded — VMF-clean) emits **`[ct-probe:mission] level=… is_server=… deus=yes/no node=… base_level=… node_level=… curse=… theme=… god=… injected=…`** on BOTH host and client, so a host+client log pair can be diffed to see where the resolved level/node diverge. Reuses `get_current_node_key`/`get_current_node` + `adventure_base_from_level_key` / `AdventurePool.IS_INJECTED_ADVENTURE_LEVEL`. **Diagnostic only.**

### Files
- `chaos_wastes_tweaker_dev.lua` — `MOD_VERSION` `0.7.172-dev` → `0.7.174-dev`; #133 conditional description append; #134 `[ct-probe:collectible]` probe folded into the existing `_spawn_pickup` hook; 2 new diagnostic hooks (`DeusCursedChestExtension.extensions_ready`, `GameModeManager.gm_event_round_started`); per-mission `_ct_chestcount_n` / `_ct_collectible_probe_n` resets beside the existing `_ct_cursed_chest_seq` resets; cap/level stash in the `populate` probe.

---

_The 0.7.173-dev notes below are superseded by 0.7.174-dev above (same build cycle — 0.7.173-dev was uploaded before the #134 diagnostic was added); retained for history._

## 0.7.173-dev (2026-06-26) — #133 Manann's Tempest cooldown wording (conditional) + #132/#136 diagnostics (instruments, NOT fixes)

One small text fix plus two printf diagnostics. The diagnostics are **instruments only** — they do not fix #132 or #136; they exist so the next session can read the actual numbers from the user's log.

### #133 — Manann's Tempest description reflects the 8-second-cooldown tweak (text fix)
- `chaos_wastes_tweaker_dev.lua` (`_G.Localize` hook, ~3990) — when `tweak_manann_tempest_cooldown` is **active**, the boon description `description_ct_boon_manann_tempest` now appends a second line **`8 second cooldown.`**; when the tweak is **off** the description stays **EXACTLY** vanilla. Conditional via `effective_setting` (host-synced, so clients show the host's toggle state) and resolved live on each tooltip render — the same pattern this file already uses for the Khaine's Fury / Miracle descriptions. No `%` in the appended text, so no `%%` escaping needed. The cooldown itself is unchanged (enforced by the `ProcFunctions.chain_lightning` hook, `MANANN_TEMPEST_COOLDOWN_S = 8.0`). NOTE: the tweak's data-file `default_value` is `false` (off) in this build — the appended line therefore shows only after the user enables the tweak. Awaiting the user's in-game eyeball.

### #132 — DIAGNOSTIC: actual cursed-chest count per mission (also #60)
- New hook `DeusCursedChestExtension.extensions_ready` (distinct method from the existing `_set_state` hook — VMF-clean, lint-confirmed) increments a per-mission tally and emits **`[ct-probe:chestcount] spawned=N cap=M level=L is_server=B`** for every cursed chest, whichever path spawned it (capped conversion OR baked spawner). The highest `spawned=N` for a level is the ground-truth chest count — compare to `cap` to confirm the Khazukan over-spawn (expect `spawned=5 cap=3`). Tally resets in `populate_pickups` (host) + the two `_ct_cursed_chest_seq` reset sites (`setup_run`, `_transition_next_node`); cap+level stashed from the existing `populate` probe. Raw `printf` (pcall-guarded) so it lands on a logging-OFF host. **Cap logic unchanged — diagnostic only.**

### #136 — DIAGNOSTIC: host/client CW mission divergence
- New hook `GameModeManager.gm_event_round_started` (fires once per peer when the round begins, level fully loaded — VMF-clean) emits **`[ct-probe:mission] level=… is_server=… deus=yes/no node=… base_level=… node_level=… curse=… theme=… god=… injected=…`** on BOTH host and client, so a host+client log pair can be diffed to see exactly where the resolved level/node diverge. Reuses the existing node accessors (`get_current_node_key`/`get_current_node`) + `adventure_base_from_level_key` / `AdventurePool.IS_INJECTED_ADVENTURE_LEVEL`. Raw `printf` (pcall). **Diagnostic only.**

### Files
- `chaos_wastes_tweaker_dev.lua` — `MOD_VERSION` `0.7.172-dev` → `0.7.173-dev`; #133 conditional description append in the `Localize` hook; 2 new diagnostic hooks (`DeusCursedChestExtension.extensions_ready`, `GameModeManager.gm_event_round_started`); per-mission `_ct_chestcount_n` reset added beside the existing `_ct_cursed_chest_seq` resets; cap/level stash in the `populate` probe.

## 0.7.172-dev (2026-06-25) — IMPLICIT crash guard: Mathlann's Storm-Strike AoE cap @ 40 targets (Issue #129)

**Host-crash fix.** A CLIENT using **Mathlann's Storm-Strike** (`boon_careerskill_01`, vanilla CW — "Your Career Skill also calls down lightning on nearby enemies") crashed the HOST. The boon's `lightning_adjecent_enemies` proc (`morris_buff_settings.lua:3744`) broadphase-queries EVERY enemy in radius and per-enemy does `add_damage_network` + a `static_blade` `create_explosion` + a beam fx. Against an enemy_tweaker `huge_shields` blob (n=121) the cascading per-enemy RPCs flooded the host **reliable send queue** (`rpc_add_damage`×2239 + `rpc_add_buff`×1007 → overflow 98152) → client `broken connection: authentication_denied` → host crash. (NOT Manann's Tempest, which is chain_lightning capped at 5 — different boon/proc/god.)

- **IMPLICIT (no toggle)** — a host crash must not be leave-on-able. Caps the proc's main broadphase sweep to **40 targets/cast** by temporarily wrapping `AiUtils.broadphase_query` for the duration of the proc (clamps only the first/main query; the per-enemy explosions' own queries are untouched), then restoring it — no permanent hook on the hot broadphase fn, network-heavy damage loop left vanilla. (Tuned up from an initial 15: the `n=121` in the log was enemy_tweaker's horde-*composition* size, not the count actually in the lightning radius, so 40 preserves a big AoE while still bounding the per-enemy `static_blade`-explosion cascade that is the real RPC amplifier.)
- **Manann's Tempest does NOT cascade off Storm-Strike** (investigated 2026-06-25): Manann's chain_lightning is crit-gated (*"Critical strikes trigger a chain lightning"*) and Storm-Strike's lightning + its `static_blade` explosion are non-crit (`is_critical_strike = false`, morris_buff_settings.lua:3764), so it can't trigger Manann's — and Manann's is doubly bounded (5 targets + 8s cooldown) regardless. The crashing client owned both boons but they don't interact; the amplifier is Storm-Strike's own explosion AoE, which the 40-cap bounds (40 lightning hits → ≤40 explosions).
- **Defensive logging** (`printf`, survives mod-logging-off): `[ct:mathlann_guard]` on install, on each cap-engage (`capped N -> 15`), and on any proc error (with guaranteed broadphase restore).
- **Every peer needs this build:** the proc is `is_local` (runs on the boon OWNER), so the client holding the boon is the one that must be capped — an un-updated client still floods the host.
- New hook `ProcFunctions.lightning_adjecent_enemies` (no collision — distinct from the `chain_lightning` Manann's Tempest hook). Cap constant `MATHLANN_STORMSTRIKE_CAP = 40`, tunable; the defensive log surfaces real-world counts for tuning.

## 0.7.168-dev (2026-06-25) — Ship: friends-only dev release (verified)

Friends-only dev ship of the v0.7.167-dev build. Verification passed (correctness, regression, duplicate-hook lint); promoting to the friends-only `ct_dev` Workshop item. No behavioral change vs v0.7.167-dev — this is a version-bump ship build (`MOD_VERSION` `0.7.167-dev` → `0.7.168-dev`) so the in-game load echo confirms the deployed bundle.

### Files
- `chaos_wastes_tweaker_dev.lua` — `MOD_VERSION` `0.7.167-dev` → `0.7.168-dev`. No other code change.

## 0.7.167-dev (2026-06-24) — Ship: #60 Beacons baked-spawner cursed-chest cap + COMPLETE unconditional `[ct-probe]` chest-count/trial instrumentation (now covers the conversion path)

Ships the Issue #60 fix (native baked `deus_cursed_chest` spawners — the Beacons path — now counted against the same per-mission `cursed_chest_count` budget the tome/grim conversion path uses) together with the final piece of the logging-OFF-host instrumentation. Develops on v0.7.166-dev with no behavioral change beyond completing the probe coverage.

### Why this build (the instrumentation gap that was held)
- The unconditional `[ct-probe]` printf coverage already landed on the **baked-cursed-chest spawner path** (`baked_cursed_chest=ALLOW/SUPPRESS`, the Beacons path in `_spawn_guaranteed_pickup`) plus the `populate` budget probe and the Chest-of-Trials `cot_activation` / `cot_seed_applied` trial probes. But the **tome/grimoire → cursed-chest CONVERSION path** (how termite/bastion/vanilla CW maps actually spawn their cursed chests — they ship NO baked `deus_cursed_chest` spawners) only logged via the GATED `_dbg` helper. On a host with VMF mod-logging OFF (the tester's setup), you got the configured count from `populate` but could count the ACTUAL spawned chests only on Beacons — half-blinding verification on every conversion-path map.

### Fix
- **New unconditional probe (`chaos_wastes_tweaker_dev.lua:~5149`).** In the existing tome/grim → cursed-chest conversion branch of `_spawn_guaranteed_pickup` (the `_chest_conversions_this_level < cap` path that increments the counter and spawns a `deus_cursed_chest` from a book pedestal), added one raw `printf("[ct-probe] conversion_cursed_chest=ALLOW kind=%s level=%s cap=%d count_now=%d spawned=%s", ...)` line, pcall-guarded, mirroring the baked-spawner `ALLOW` probe directly above. Now `[ct-probe]` `ALLOW` (baked) + `conversion_cursed_chest=ALLOW` lines together give the ACTUAL total cursed-chest count on EVERY map type from a logging-OFF host. Bounded per-spawn (fires at most `cap` times per mission load, never per-frame).
- **#60 baked-spawner cap fix intact.** `Unit.get_data(spawner_unit, "deus_cursed_chest")` branch in `_spawn_guaranteed_pickup` still routes native baked cursed-chest spawners through the same `_chest_conversions_this_level < cap` budget (ALLOW under cap → vanilla spawn + increment; SUPPRESS over cap → skip). Unchanged.
- **All prior probes untouched** — `populate` budget probe (per-mission), `baked_cursed_chest=ALLOW/SUPPRESS` (per-spawner), `cot_activation` + `cot_seed_applied` (per-chest trial). All raw `printf`, all bypass the VMF mod-logging toggle.
- **No new hooks** (folded into the existing `_spawn_guaranteed_pickup` hook). **No `spawn_weighting` touched.** Duplicate-hook lint clean.

### Files
- `chaos_wastes_tweaker_dev.lua` — `MOD_VERSION` `0.7.166-dev` → `0.7.167-dev`; +1 unconditional `[ct-probe] conversion_cursed_chest=ALLOW` line in the conversion branch of `_spawn_guaranteed_pickup`.

## 0.7.166-dev (2026-06-24) — Ship: altar "used-up visual fires on use 1" fix (verified) — re-armed reusable altars now stay lit/available, the looted mesh shows ONLY after the final use

This is the shipping build of the altar used-up-visual fix developed across v0.7.157-dev (probes) → v0.7.158-dev (upgrade-altar rarity bump) → v0.7.159-dev (the root-cause re-fire). All three verifications (correctness, regression, duplicate-hook lint) passed; promoting to a friends-only dev release. No code changes vs v0.7.159-dev beyond the MOD_VERSION bump — this entry consolidates the root cause + fix for the shipped feature.

### Root cause
- For a REUSABLE altar (Issue #61, configurable max uses), vanilla `DeusChestExtension.purchase()` (`deus_chest_extension.lua:308`) fires the `lua_update_collected` flow event — the used-up/looted MODEL transition — on EVERY open, BEFORE ct's `open_chest` post-hook runs. The post-hook's re-arm path clears `_is_purchased` / `_animation_state` and retracts the peer from the networked `collected_by_peers` (v0.7.151-dev), which stops vanilla `update()` (`:175-182`) RE-asserting the looted state — but it does NOT un-fire the already-emitted flow event. So the flow graph stayed parked on the collected/looted mesh, and a re-armed altar (uses < max) read as "used up" after use 1 even though it was still usable.
- Separately, for UPGRADE altars the dark/disabled look is driven by `update_upgrade_chest_color` (`:211-243`) firing `lua_interact_disabled` once the wielded weapon's rarity matches the altar's rolled `_rarity` — and the vanilla re-roll keeps the SAME rarity (constant per-`go_id` seed), so the altar stayed genuinely unusable, not just cosmetically dark.

### Fix (source-verified)
- **Re-fire on re-arm (`chaos_wastes_tweaker_dev.lua:6173-6198`).** In the existing `open_chest` post-hook re-arm branch (uses < max), deterministically re-fire `lua_update_<chest_type>` — the SAME event vanilla emits at `:142` when it re-rolls — so the re-armed altar leaves the used-up look IMMEDIATELY. The depleted (else) branch deliberately re-fires NOTHING, leaving vanilla's `lua_update_collected` in place, so the used-up visual now shows ONLY after the final use. Per-peer: each peer runs its own post-hook + its own `update()` derivation off the host-authoritative `collected_by_peers`, so host and clients both flip available→used-up only when the host's configured max uses are spent. `Unit.flow_event` is pcall-guarded behind a `Unit.alive` + `type(_chest_type) == "string"` guard per the repo engine-fatal rule.
- **Upgrade-altar rarity bump (`:6216-6234`, v0.7.158-dev).** On a re-armed UPGRADE altar, bump `_rarity` strictly above the just-upgraded wielded weapon (capped at `unique`), re-fire `lua_update_<bumped>` so the hologram/glow reflects the new tier, and clear `_prev_update_upgrade_chest_color_event` so `update_upgrade_chest_color` re-evaluates to a usable, lit state instead of staying on the stale `lua_interact_disabled`.
- **No new hooks** (folded into the existing `open_chest` post-hook and the read-only `DeusChestExtension.update` probe). **No `spawn_weighting` touched.** Duplicate-hook lint clean.

### Verifications (all PASS)
- **Correctness** — re-armed reusable altar leaves the used-up mesh on the same tick it re-arms; depleted altar keeps the looted mesh; upgrade altar relights at a higher tier.
- **Regression** — `/ct_regression_test` source-pattern checks `altar_visual_probe_present` (`CT_ALTAR_VISUAL_PROBE_MARKER`), `upgrade_altar_rarity_bump` (`CT_UPGRADE_ALTAR_RARITY_BUMP_MARKER`), and `altar_reuse_hook_on_open_chest` all pass.
- **Duplicate-hook lint** — PASS (0 duplicate-hook); the re-fire lives inside the single consolidated `open_chest` post-hook.

### Files
- `chaos_wastes_tweaker_dev.lua` — `MOD_VERSION` `0.7.165-dev` → `0.7.166-dev`. No other code change vs v0.7.159-dev — this is the shipping consolidation of the already-developed fix.

## 0.7.165-dev (2026-06-24) — Robust coin-starvation fix (Abundance-of-Life curse): coins now GUARANTEED via a partitioned coin-only spawner reservation, not just a count ratio

The prior fix (0.7.164-dev lowered injected-adventure `deus_potions` counts in `_adventure_pool.lua`) only *reduced* the odds of coin starvation under the Abundance-of-Life curse — it did not *guarantee* coins. This build replaces the count-only approach with a partitioned spawner reservation that mirrors vanilla's native type-partition, so coins are guaranteed regardless of pickup-type iteration order or the ×3 potion curse.

### Root mechanism (source-verified)
- On injected adventure levels, ct's `PickupSystem._can_spawn` hook DELIBERATELY un-partitions vanilla's spawner types: it grants `deus_potions`, `deus_soft_currency`, AND `deus_weapon_chest` eligibility on the SAME generic primary spawners (vanilla partitions potion-spawners vs `painting_scrap`→coin-spawners, so vanilla never starves coins).
- `PickupSystem._spawn_spread_pickups` (`pickup_system.lua:467-633`) draws ALL pickup types from ONE shared `spawners` array, in `for pickup_type in pairs(pickup_settings)` order — which is **non-deterministic in Lua 5.1** — and permanently `table.remove`s each consumed spawner (`:621-626`) before the next type runs.
- The Abundance-of-Life curse multiplies ONLY `deus_potions` ×3 (`mutator_curse_abundance_of_life.lua:7-11`, applied by `MutatorHandler.pickup_settings_updated_settings:544-560`); coins stay flat. So when potions iterate first, the ×3 demand can drain the shared pool before `deus_soft_currency` is reached → coins fall into silent `spawn_debt` (`pickup_system.lua:629`) → no coins.

### Why a count ratio can't guarantee
Allocation is per-section greedy in non-deterministic type order, not proportional to requested counts. Lowering potion counts only lowers the *probability* that a potions-first pass exhausts a finite spawner pool ahead of coins.

### Robust fix — coin-only spawner reservation (option a: re-partition, closest to vanilla)
- `chaos_wastes_tweaker_dev.lua`, in the existing `_can_spawn` hook: a deterministic ~40% slice of the primary (and secondary) spawners is reserved COIN-ONLY by DENYING `deus_potions` / `deus_weapon_chest` eligibility on them. `deus_soft_currency` is never denied by the reservation. A spawner is only `table.remove`d when a pickup that `_can_spawn` ALLOWED consumes it, so a reserved spawner survives every potion iteration regardless of `pairs()` order or the curse ×3 — it is still present and coin-eligible when `deus_soft_currency` iterates. **This is what makes coins guaranteed, not merely more likely.**
- The reserved set is **rank-based**, rebuilt once per `populate_pickups` pass on the host (the spawner lists are fully populated by then — `pickup_gizmo_spawned` fires per-spawner at level spawn, before populate). Ranking by a stable per-spawner hash of `percentage_through_level` guarantees a floor of `max(1, ceil(0.4·N))` reserved spawners for ANY non-empty pool (closing the ~4% small-pool hole a pure independent per-spawner hash would leave), never reserves the whole pool, and spreads the reserved spawners uniformly across the level (the hash decorrelates from position, so coins find a reserved spawner in whatever section they iterate). A pure-hash fallback covers any path that reaches `_can_spawn` before the set is built.
- The reservation's *effect* stays injected-adventure-only: the entire `_can_spawn` deny block (including the reservation branches) is already behind `if not on_injected_adventure_level() then return ok end`, so real CW / real Adventure / clients are untouched (their native spawner partition already protects coins). The rank-based set is rebuilt on the host every `populate_pickups` (not re-gated at the rebuild site — that file-local function is defined later in the file and a lexical forward reference would resolve to a nil global), which is inert on non-injected levels because the set is simply never consulted there.
- **No `spawn_weighting` touched** (the `[0,1)` sampler-sum crash class does not apply — only `_can_spawn` eligibility and request counts change). **No new hooks** (folded into the existing `populate_pickups` and `_can_spawn` hooks — duplicate-hook lint clean).

### Counts reconciled
With the reservation now providing the guarantee, the injected-adventure counts in `_adventure_pool.lua` are rebalanced from the defensive 18/6 potion ratio back to a normal-feeling 30 primary / 10 secondary potions (coins stay 30 / 10). The ×3 curse still triples potions, but they are now confined to the unreserved ~60% of spawners, so they can't starve coins. Non-cursed injected levels feel normal again.

### New `/ct_regression_test` check
- **`coin_reservation_partition`** — asserts the reservation is wired (`mod._ct_coin_reservation_test` + the rank-based `mod._ct_rebuild_coin_reserved_set` / `mod._ct_clear_coin_reserved_set` handles), the reserved fraction is in `(0,1)`, the per-spawner hash is deterministic, and over a representative spread of `percentage_through_level` values the reservation is a PROPER subset (neither empty — which would void the guarantee — nor total — which would starve potions/altars).

### Files
- `chaos_wastes_tweaker_dev.lua` — `MOD_VERSION` `0.7.164-dev` → `0.7.165-dev`; `_coin_reservation_hash_reserved` / `_rebuild_coin_reserved_set` / `_spawner_reserved_for_coins` + `_coin_reserved_units` set added above the `_can_spawn` hook; `_can_spawn` potion/weapon-chest branches deny on reserved spawners; `populate_pickups` rebuilds (or clears) the reserved set before vanilla populate; `coin_reservation_partition` regression check added after `cw_collectible_and_big_casket`.
- `_adventure_pool.lua` — `make_cw_pickup_settings` primary `deus_potions` 18→30, secondary `deus_potions` 6→10; comments rewritten to point at the reservation as the guarantee.

## 0.7.164-dev (2026-06-24) — Regression guards for the dup-chip wrong-node fix (0.7.162) + the #97 paced-send flood fix (0.7.163)

Two new `/ct_regression_test` source-pattern checks. No behavioral change — both fixes already shipped; these guard them against silent reversion on future edits, mirroring the existing marker-constant introspection checks (`open_chest_hook_singleton`, `variadic_hooks_arity_preserved`, etc.). The bundle is unreadable from Lua at runtime, so each check reads a marker/invariant exported onto `mod` or a file-scope global at the fix site (not a runtime grep).

### New checks
- **`dup_chip_no_current_node_fallback`** (guards ct_dev 0.7.162-dev) — asserts the dup-career extra-chip node_key resolution in `_ct_dup_vote_chips.lua` is `final_node_selected > vote > nil` with NO trailing current-node fallback (the fallback would plant a visible chip on the party's CURRENT node for an unvoted duplicate peer — the "valid-but-wrong mission node" bug). Reads `mod._ct_dup_chip_node_key_resolution`, exported at module-LOAD time near the top of the file (the resolution loop only runs during a CW map vote, so the export can't live at the resolution site). FAILs if the marker is missing, mismatched, or names the forbidden current-node token. The forbidden needle is split across two literals in the check so the check's own source can't self-match.
- **`chunk_sends_paced_not_bursted`** (guards ct_dev 0.7.163-dev / Issue #97) — asserts the three chunked broadcasts stay paced through the enqueue/drain send queue, never inline-bursting inside their `for seq` loops. Verifies the `_CT_CHUNK_PACED_SEND_MARKER` constant (added near `_ct_chunk_send_queue`), `_ct_enqueue_chunk` exists, exactly one live `mod.update` drainer owner is present, `_CT_CHUNK_DRAIN_BUDGET` is a valid number ≥ 1, and the `_ct_chunk_send_queue` FIFO table exists. FAILs loudly if any piece of the paced-send wiring is dismantled.

### Files
- `chaos_wastes_tweaker_dev.lua` — `MOD_VERSION` `0.7.163-dev` → `0.7.164-dev`; `_CT_CHUNK_PACED_SEND_MARKER` constant added near the chunk send queue; two `_rt_register` checks added after `trait_filter_restores_on_error`.
- `_ct_dup_vote_chips.lua` — load-time export `mod._ct_dup_chip_node_key_resolution = "final_node_selected>vote>nil"` near the top; resolution-site comment updated to point at it.

## 0.7.163-dev (2026-06-24) — Ship: Issue #97 host crash on hot-join (chunked-sync flooded the reliable send queue) — fixed via a paced send-queue (verified)

Shipping build of the Issue #97 chunked-sync pacing fix. All three verifications (correctness, regression, duplicate-hook lint) passed; friends-only dev release.

### Root cause (#97)
- ct_dev syncs three large payloads to clients as chunked-string RPC trains (`ct_sync_host_settings_chunk`, `ct_graph_snapshot_chunk`, and the peer-manifest chunk channel) — each payload is JSON-encoded, split into `SYNC_CHUNK_SIZE` (400-char) pieces, and sent as `(session, seq, total, chunk_str)`.
- Each broadcaster used to emit its **entire** chunk train **inline in one frame** (`for seq = 1, total do mod:network_send(...) end`). On a **large-graph hot-join** all three fire in the same frame window and dump ~200 reliable RPCs (~94 KB) onto Stingray's reliable send queue at once. That queue has a hard byte budget (~97822 B); overflowing it tears down the host connection — the reported **host crash**.

### Fix — paced send-queue (anti-flood)
- Chunks are no longer sent inline. Each chunk is **enqueued** as a self-contained `network_send` arg set into one FIFO queue (`_ct_chunk_send_queue` / `_ct_enqueue_chunk`), and a per-frame drainer on `mod.update` pops up to `_CT_CHUNK_DRAIN_BUDGET` (8) entries per tick and sends them. At 8 chunks/frame the per-frame reliable byte load (~3.6 KB) stays FAR under the ~97822 B queue cap, and the reliable channel acks faster than we enqueue, so the queue drains steadily without ever stacking near the limit.
- **Wire protocol unchanged.** Same event names, same `CT_RPC_SCHEMA` gate, same `session`/`seq`/`total` semantics, same `SYNC_CHUNK_SIZE`, same receiver reassembly. Only the **send timing** is paced. Receivers were already purely accumulative (buffer by `seq` per `(sender, session)`, act only once all `total` distinct chunks arrive — no single-frame/burst assumption), so they tolerate paced arrival with zero change.
- **Ordering / re-entrancy.** FIFO order preserved (append at tail, pop from head). A new broadcast just appends more entries; the drainer never clears the queue mid-drain and each entry carries its own `session` id, so concurrent/overlapping broadcasts never corrupt each other. Each send is `pcall`-wrapped so one bad send can't abort the rest of the drain or stall the queue; `record_send` fires at SEND time so bt's net_replay ring still records the actual emission.

### Hooks / tests
- No new hooks. The drainer is hosted on `mod.update` (ct_dev's only mod-wide per-frame entry point — the existing `DeusChestExtension.update` hook is mission/per-chest-only and read-only). Duplicate-hook lint: **PASS (0 duplicate-hook)**.

## 0.7.162-dev (2026-06-24) — Ship: duplicate-career map-vote chips (verified) — both voters' chips now render on the CW map screen

This is the shipping build of the duplicate-career map-vote chip fix developed across v0.7.160 → v0.7.161-dev. All three verifications (correctness, regression, duplicate-hook lint) passed; promoting to a friends-only dev release. No code changes vs v0.7.161-dev beyond the MOD_VERSION bump — this entry consolidates the root cause + fix for the shipped feature.

### Root cause
- General Tweaker's **Allow Duplicate Careers** lets two peers share a `profile_index` (same hero). The CW map-vote scene (`DeusMapScene`) owns exactly five player "token" chip units keyed by `profile_index` (`_profile_index_to_token`). `DeusMapDecisionView._update_player_state` places chips via `self._scene:place_token(profile_index, index, node_key)` — chip IDENTITY is `profile_index`, and `place_token` is **last-writer-wins** at the shared hero slot. So when two peers share a career, the second peer's `place_token` **overwrites** the first: only ONE chip shows for both voters (the peer that iterated LAST in `controller:get_peers()`), and the other voter's choice is invisible on the map.

### Fix
- New `_ct_dup_vote_chips.lua` subsystem, **client-side render only — no new network sync** (vote DATA is already synced via shared_state). Post-hooks `DeusMapDecisionView._update_player_state` (vanilla runs first, so the **non-duplicate case is byte-for-byte vanilla**), then detects any `profile_index` voted by >1 peer and spawns/reuses a SECOND chip per EXTRA peer — exactly the first `n−1` peers in the per-`profile_index` list (`for i = 1, #list - 1`), leaving the last to vanilla. Each extra is placed at its OWN voted node (`final_node_selected` > own `vote`, no `current_node_key` fallback to avoid the "valid-but-wrong node" bug) and distinguished by position OFFSET + slight SCALE-down (`Unit.set_local_pose`/`_position`/`_scale`, all confirmed in-file and deterministic — NOT material recolor, which can silently no-op). Lateral nudge fans by extra-ordinal so 3+ way stacks spread; per-ordinal z-lift prevents z-fighting.
- **No leak.** Extras spawned lazily, cached per-peer in `scene._ct_dup_tokens`, reused across frames, destroyed by a `DeusMapScene._clear` hook (runs from both `on_enter` and `destroy`, mirroring vanilla's `_profile_index_to_token` teardown). Toggle-off mid-view hides extras immediately.
- **Safety.** Toggle-gated (`show_duplicate_career_chips`, default ON). All engine `Unit`/`World` calls pcall-wrapped; controller/scene fields nil/type-checked; any failure bails to vanilla (one chip), never crashing the map screen.

### Hooks / tests
- Two hooks, both the SOLE hook on their `(Class, method)` pair: `(DeusMapDecisionView, _update_player_state)` and `(DeusMapScene, _clear)`. Duplicate-hook lint: **PASS (0 duplicate-hook)**. ct_dev's other `DeusMapDecisionView` hooks (`_enable_hover`, `_start`) and `DeusMapScene` hook (`on_enter`) are on different methods.

## 0.7.161-dev (2026-06-21) — Duplicate-career map-vote chips: adversarial-review fixes (correct extra-peer selection, fan-out for 3+ way, immediate hide on toggle-off)

### Fixed — BLOCKING: two peers sharing a career voting DIFFERENT nodes drew the WRONG chips
- **Bug (correctness verifier, ok=FALSE).** The v0.7.160 extra-spawn loop was `for i = 2, #list` — it spawned an extra for every peer AFTER the first in the per-`profile_index` list. But vanilla's `place_token` loop (`deus_map_decision_view.lua:665-682`) writes `_profile_index_to_token[profile_index]` once per peer (`deus_map_scene.lua:833-841`), so for a shared `profile_index` it's **LAST-WRITER-WINS**: vanilla's single visible chip shows the peer that iterated **LAST** in `ipairs(controller:get_peers())`. The old `i = 2..#list` set therefore (a) **doubled** the LAST peer — an extra chip placed on top of vanilla's chip — and (b) **never drew** the FIRST peer. With two peers voting different nodes, one node showed two stacked chips and the other showed none.
- **Order confirmation.** Both vanilla and the mod read peers from `controller:get_peers()` → `NetworkState.get_peers` → `shared_state:get_server(key)` — ONE ordered shared-state array, iterated with `ipairs` in BOTH places (verified against decompiled source 2026-06-21). The mod appends `by_profile[profile_index]` in that same order, so `list[#list]` IS the peer vanilla draws and `list[1 .. #list-1]` are exactly the peers vanilla does NOT show.
- **Fix.** Loop changed to `for i = 1, #list - 1` — spawn extras for the first n−1 peers, leave the last to vanilla. Now every voter's chip is drawn exactly once: vanilla draws `list[#list]`, the mod draws the rest. (`_ct_dup_vote_chips.lua` ~L262-L290.)

### Fixed — 3+ peers sharing ONE career: extras no longer crowd/overlap (regression verifier)
- **Bug.** All extras used the same constant `DUP_OFFSET {0.45, 0, 0.35}`, so with 2+ extras on the same node+slot they stacked on top of each other.
- **Fix.** Lateral (x) nudge now scales by the extra's running ordinal (1st extra = 1×, 2nd = 2×, …) and a small per-ordinal z-lift (`DUP_OFFSET_Z_PER_EXTRA = 0.06`) keeps co-located extras from z-fighting each other. With the common 2-peer case (one extra, ordinal == 1) the offset is identical to the old constant — **2-way visuals unchanged**. (`_place_dup_token`, `_ct_dup_vote_chips.lua` ~L131-L175 + the new ordinal arg threaded from the spawn loop.)

### Fixed — toggle OFF mid-view now hides extras immediately (regression verifier)
- **Bug.** The early-return path when `show_duplicate_career_chips` is OFF returned without hiding — extras lingered visible until the next `_clear` (view re-open/destroy), contradicting the docstring's "hidden when ... toggled off mid-view" claim.
- **Fix.** The toggle-off branch now resolves the scene (when available) and calls `_hide_all_dup_tokens(scene)` BEFORE returning, so extras disappear on the very next `_update_player_state` frame. Cache is preserved for reuse; `_clear` still owns destruction. (`_ct_dup_vote_chips.lua` ~L197-L210.)

### Preserved
- All existing safety intact: pcall around every engine `Unit`/`World` call, nil/type guards on controller/scene fields, `_clear` teardown/no-leak path, the non-duplicate case still byte-for-byte vanilla via the post-hook. No new hooks (still the two sole hooks on `(DeusMapDecisionView, _update_player_state)` and `(DeusMapScene, _clear)`). Two independent duplicate pairs still each resolve correctly (per-`profile_index` lists are independent).

## 0.7.160-dev (2026-06-21) — Duplicate-career map-vote chips: show BOTH voters' chips on the CW map screen (offset + scale to distinguish)

### Added — both vote chips now show when two players run the same career
- **Problem.** General Tweaker's **Allow Duplicate Careers** lets two players run the SAME career. On the Chaos Wastes map-vote screen the vanilla scene (`DeusMapScene`) owns exactly **five** player "token" chip units — one per hero, stored in a 1-based array keyed by `profile_index` (`_profile_index_to_token`, `deus_map_scene.lua:238-251`). `DeusMapDecisionView._update_player_state` (`deus_map_decision_view.lua:665-682`) places chips with `self._scene:place_token(profile_index, index, node_key)` — the chip IDENTITY is `profile_index`. When two peers share a `profile_index`, the second peer's `place_token` **overwrites** the first at the shared hero slot, so only **one** chip shows for both voters (sitting on whichever peer iterated last). The other player's vote is invisible on the map.
- **Fix (client-side render only — no new network sync).** New `_ct_dup_vote_chips.lua` subsystem. Post-hooks `DeusMapDecisionView._update_player_state` (vanilla runs first and places its one-chip-per-hero set EXACTLY as before — so the **non-duplicate case is byte-for-byte vanilla**), then detects any `profile_index` voted by >1 peer and, for each EXTRA peer beyond the first, spawns/reuses a SECOND chip unit (the same per-hero token asset), places it at that peer's own voted node (resolved exactly like vanilla: `final_node_selected` > own `vote` > current node), and distinguishes it.
- **Distinguishing method: position OFFSET (vertical lift + lateral nudge) + slight SCALE-down, NOT material recolor.** Rationale: the token `.unit` assets are binary (not in decompiled source); whether any exposes a tint material variable is unverified per-asset, and `Material.set_*` silently NO-OPs when the variable isn't compiled into the shader variant (`TODO.md:146-149`) — a guess-and-check dead end with a silent-failure mode. The vanilla scene already distinguishes co-located chips purely by offset pose (`referenced_token_poses[slot]`, `deus_map_scene.lua:836-837`), so an offset+scale secondary chip is visually native and uses only `Unit.set_local_pose` / `Unit.set_local_position` / `Unit.set_local_scale` — all confirmed in-file (`deus_map_scene.lua:226,230,840`) and deterministic (no silent no-op path). Offset `{x=0.45, y=0, z=0.35}`, scale `0.72`.
- **No leak.** Extra chips are spawned lazily on the first frame a duplicate is detected, cached per-peer in `scene._ct_dup_tokens` (keyed by `peer_id`), reused across frames (moved via `set_local_pose`, hidden when a peer stops being a duplicate). They're destroyed by a `DeusMapScene._clear` hook against `scene._world`, then the cache is nilled. `_clear` runs from BOTH `on_enter` (top, re-entrancy guard, `deus_map_scene.lua:454`) and `destroy` (`:512`), exactly where vanilla tears down `_profile_index_to_token` (`:532-536`), so extras are destroyed on every view re-open AND on destroy — no accumulation across map-vote re-opens.
- **Safety.** Toggle-gated (`show_duplicate_career_chips`, default ON, `[untested]`). Client-side render preference: reads the local peer's own toggle (the vote DATA is already synced; this only governs how THIS client draws it). All engine `Unit`/`World` calls are pcall-wrapped (a stale/destroyed unit handle can fatal, bypassing Lua error handling); every controller/scene field is nil/type-checked before deref; any failure bails to vanilla (one chip), never crashing the map screen.

### Hooks / tests
- Two NEW hooks, both sole hooks on their `(Class, method)` pair (pre-flight grep 2026-06-21 confirmed neither was previously hooked in ct_dev): `mod:hook_safe("DeusMapDecisionView", "_update_player_state", ...)` and `mod:hook_safe("DeusMapScene", "_clear", ...)`. ct_dev's existing `DeusMapDecisionView` hooks (`_enable_hover`, `_start`) and `DeusMapScene` hook (`on_enter`) are on DIFFERENT methods — no consolidation needed.

## 0.7.159-dev (2026-06-20) — Task 1: split "Reworks: Boons" into Existing/New sub-groups + nest Bomb Bubbles under Utility; Task 2: fix disabled-boon leak at grant; Task 3: silence misattributed trait-filter warning

### Changed — Task 1: menu restructure (no setting_ids renamed — user values persist)
- **"Reworks: Boons" split into two NESTED sub-groups:**
  - **"Reworks: Existing Boons"** (`reworks_boons_existing_group`) — toggles that change how an EXISTING boon / property / bot-boon-distribution behaves: `tweak_reckless_swings` (Khaine's Fury), `tweak_boon_movespeed`, `bomb_boon_cooldown`, `bomb_boon_exclusive`, `endless_bombs_consumes_morgrim`, `rv_no_save_morgrim`, `tweak_manann_tempest_cooldown`, `tweak_anath_raema_permanent`, `tweak_defeat_recovery`, `tweak_miracle_of_ulric_persistent`, `ulric_pack_unlimited_range`, `tweak_wildfire_generations_cap`, `tweak_miracle_of_isha_aegis`/`_wounds`, `ct_blessed_bots`, `bots_mirror_host_boons`, `bots_get_random_boons`, `bots_mirror_host_weapon_upgrades`, `announce_bot_boons`.
  - **"Reworks: New Boons (Added)"** (`reworks_boons_new_group`) — the four trait-as-boon toggles that ADD a brand-new selectable boon: `enable_boon_vauls_anvil`, `enable_boon_manann_tempest`, `enable_boon_taal_twinned_arrow`, `enable_boon_asuryan_wrath`.
  - Classification rule: "adds a brand-new boon" → New; "changes how an existing boon behaves" → Existing. `tweak_manann_tempest_cooldown` is placed in **Existing** (it changes a cooldown value and per its own tooltip affects the vanilla "boon + trait", i.e. modifies behavior rather than adding a boon).
  - `[untested]` on both new group headers (`reworks_boons_existing_group`, `reworks_boons_new_group`).
- **"Bomb Bubbles" boon set nested under Utility:** the `bomb_bubbles` category (support-bomb boons `boon_supportbomb_*`) moved from a top-level boon category to a sub-category of `utility_boons` (alongside `bombs`), in both the **Disable Boons** and **Starting Boons** trees. category_id + item setting-id tails are unchanged, so `disable_boon_bomb_bubbles_group` / `start_boon_bomb_bubbles_group` and every `disable_boon_*` / `start_boon_*` value persist; only the menu position moves.

### Fixed — Task 2: a DISABLED boon could still be granted (`[boon-trace] DISABLED BOON GRANTED: blazing_revenge`)
- **Root cause:** the disable filter only stripped the ROLL pool (`DeusPowerUpsArray` / `DeusPowerUpsArrayByRarity`) inside the `DeusPowerUpUtils.generate_random_power_ups` hook. That covers every pool-rolled choice (shrine / cursed-chest / boon-altar choices are presented stripped). **But** a boon **ALTAR** (`DeusChestExtension`, `_chest_type == power_up`) rolls and **caches** its single offered boon into `self._stored_purchase` at chest **spawn** time (`_generate_stored_power_up` → `generate_random_power_ups`[1]), then grants it via `add_power_ups` on **purchase**. If the user toggles `disable_boon_<name>` ON **mid-run after** an altar already cached that boon, the strip already missed it and the **stale cached boon** sails through to `add_power_ups`. (The same gap applied to any specific-grant path that bypasses the pool: set rewards via `_check_set_completed`, starting boons.) `add_power_ups` (`deus_run_controller.lua:1126`) is the SINGLE universal apply chokepoint for every grant source — but ct only `hook_safe`'d it (post-call, too late to block).
- **Fix:** converted ct's `(DeusRunController, add_power_ups)` hook from `hook_safe` to a full `mod:hook`, and added a **pre-grant disable gate** that removes any `effective_setting("disable_boon_<name>") == true` entry from `new_power_ups` **before** vanilla grants/activates it. `effective_setting` is host-authoritative (host's value on clients), so host + clients agree and a client never drops a boon the host legitimately granted. Filtering to empty is safe (vanilla early-returns on `#==0`). The bot-mirror reentry guard (`_ct_bot_mirror_active`) skips the gate for bot grants (those come from a pool we already control). Remains the ONLY hook on `(DeusRunController, add_power_ups)` — VMF singleton-hook invariant preserved (now a `mod:hook`). The post-grant `[boon-trace]` audit still runs after `func`; a `DISABLED BOON GRANTED` warning now only fires for a genuine bypass the gate didn't cover.

### Changed — Task 3: misattributed/noisy `[trait-filter] generate_weapon_for_slot vanilla call raised` warning downgraded to debug-gated
- **Root cause (not a trait-filter fault):** `DeusWeaponGeneration.generate_weapon_for_slot` has **no caller in the decompiled vanilla source** — the only invoker is ct's own bot-weapon-mirror helper `_gen_bot_weapon_for_slot` (`~L5726`), which **already** wraps the call in `pcall` and treats a raise as "the bot just skips that weapon slot this roll" (no crash, no user-visible effect). The raise itself is the **vanilla** `fassert(#weapon_keys > 0, "...weapon_pool state...")` at `deus_weapon_generation.lua:110`, fired when the bot's career `weapon_pool[rarity]` has no weapon group matching the requested slot at the target rarity. The trait filter only rewrites `baked_trait_combinations` (read later, exotic/unique only) and is unrelated.
- **Fix:** in `_filtered_weapon_gen`, the `generate_weapon_for_slot` label now logs via debug-gated `_dbg` (with an explanatory message) instead of the ungated `mod:warning` (which fired ~8×/run as noise). The re-raise still happens (the caller's `pcall` handles it). The other three labels (`generate_weapon` / `generate_item_from_item_key` / `upgrade_item`) are on real vanilla gameplay paths with no upstream `pcall`, so they KEEP the ungated `mod:warning` (v0.7.134 rationale).

### Hooks / tests
- No new hooks added. `(DeusRunController, add_power_ups)` changed hook **type** (`hook_safe` → `hook`) but stays single — no duplicate. Pre-flight grep confirmed: `disable_boon`, `generate_weapon_for_slot`, `add_power_ups`, `reworks_boons` each touched in exactly the intended sites.

## 0.7.158-dev (2026-06-20) — Task 1: REAL fix for weapon-upgrade altar "goes dark after first use" + Task 2: upgrade-altar property/trait reroll + Altar Reuse menu nested under Shrines/Altars/Chests

### Fixed — Task 1: weapon-upgrade altars set to >1 use no longer go dark/disabled after the first use (root cause corrected; solo host, no peers)
- **Symptom (corrected report):** the user is **solo host with no peers**, so the earlier "client RPC-latency" theory was wrong. The v0.7.151 `collected_by_peers` uncollect clears the own peer directly on the host with no RPC, yet a weapon-**upgrade** altar still darkened after one use.
- **Root cause (from vanilla `deus_chest_extension.lua`):** an upgrade altar's looted/dark look is derived **two independent ways**, and `collected_by_peers` is only one of them:
  1. `collected_by_peers` membership (`:175`) — the v0.7.151 uncollect handles this, and solo-host it's a direct local write that DOES hold. Not the culprit.
  2. **`update_upgrade_chest_color` (`:211-243`)** — runs every tick, fully independent of `collected_by_peers`. It compares the altar's rolled `_rarity` against the player's **currently wielded weapon** rarity: `event = chest_rarity_order <= weapon_rarity_order and "lua_interact_disabled" or LUA_UPDATE_RARITY_EVENTS[rarity]`. After the first upgrade the wielded weapon's rarity **equals** the altar's rolled rarity, so the comparison is true and the altar fires `lua_interact_disabled` — the grey/"dark", can't-use visual. `can_be_unlocked` (`:505-517`) likewise returns false, so the re-armed altar is **genuinely unusable**, not just cosmetically dark.
  - Vanilla re-rolls `_rarity` on every re-arm (`update()` `:140` → `_setup_rarity`), but the seed is **constant per go_id**, so it always re-rolls the SAME rarity and `update_upgrade_chest_color` always re-disables it.
- **Fix (lowest-blast-radius, upgrade-altar only):** hook `DeusChestExtension._setup_rarity` (the single writer of `self._rarity`; previously **unhooked**, so VMF-clean). For an upgrade altar that has been used ≥ 1 time this run, bump the rolled rarity **strictly above** the player's wielded (just-upgraded) weapon, capped at `unique` (the usable ceiling; `event`/order 6 is excluded). This stops `update_upgrade_chest_color` from disabling the altar and keeps `can_be_unlocked` true until the player's weapon hits `unique`, at which point the altar correctly depletes/darkens. Hooking `_setup_rarity` (rather than writing `_rarity` once in the re-arm branch) is load-bearing: vanilla re-runs `_setup_rarity` every time the setup block re-runs and would otherwise **clobber** a one-shot write one tick later. The open_chest re-arm branch also applies the bump immediately + clears the cached `_prev_update_upgrade_chest_color_event` memo for a no-flicker refresh.
- **Single-use altars and the depleted state are unchanged:** the bump is gated on `chest_type == upgrade` AND `uses ≥ 1`; first/only use takes the untouched vanilla roll, and once max uses is reached the altar darkens as before.

### Added — Task 2: weapon-upgrade altar reuse now rerolls the upgraded weapon's properties/trait
- Upgrade altars don't swap your weapon, so "reroll" means a fresh **properties/trait** roll on the upgraded weapon each reuse. Vanilla upgrade uses `DeusChestExtension._generate_upgraded_weapon` (`:426`) — a DISTINCT function from `_generate_stored_weapon` (the swap-altar path the existing seed-mix hook targets), so it was **not** previously rerolled and every reuse produced the same roll. New `mod:hook("DeusChestExtension", "_generate_upgraded_weapon", ...)` mixes the per-go_id use count into the `go_id` argument (same `+ uses * 1000003` idiom as the existing `_generate_stored_weapon` seed-mix), which flows through the function's internal `fnv32_hash` weapon_seed → a different properties/trait roll each reuse. Combined with the Task 1 rarity bump, each reuse is meaningful (higher rarity + fresh stats).

### Changed — Task 2: "Altar Reuse" menu group nested under "Shrines, Altars and Chests"
- The `altar_reuse_group` (was a top-level sibling) is now a nested sub-group inside `shrines_altars_chests_group` (VMF supports nested groups; cf. `available_missions_group` inside `adventure_maps_group`). No setting ids changed, so existing user values are preserved. Added a dedicated `altar_reuse_count_upgrade_tooltip` describing the reroll + rarity-bump behavior.

### Diagnostics
- The v0.7.157 `[altar_visual_probe]` read-only traces (the `update` watcher hook + the open_chest OPEN/REARM/DEPLETED lines) are **kept** — they remain read-only and let the user confirm the fix in-session. They can be stripped in a later release once the fix is confirmed.

### Tests
- New `upgrade_altar_rarity_bump` marker check (asserts the `_setup_rarity` fix isn't silently stripped). Existing `open_chest_hook_singleton`, `altar_visual_probe_present`, and `cursed_chest_unique_trials` checks unchanged. No duplicate hooks: `_setup_rarity`, `_generate_upgraded_weapon` were each previously unhooked; `open_chest`/`update`/`get_purchase_cost`/`_generate_stored_weapon`/`_generate_stored_power_up` remain single-hooked.

## 0.7.157-dev (2026-06-20) — Task A: altar "goes dark after first use" diagnostic probes (diagnose-only) + Task B: Chest of Trials uniqueness

### Added — Task A: read-only probes for the weapon-upgrade altar "goes dark after first use" report (DIAGNOSE-ONLY, no behavior change)
- The user reports weapon-**upgrade** altars set to allow >1 use still go "dark"/looted-looking after the FIRST use despite the v0.7.151 re-arm + `collected_by_peers` uncollect. This drop instruments the path so the next session has runtime data; **no speculative fix** was applied (user diagnoses first).
- **What the weapon-upgrade altar is:** the engine class `DeusChestExtension` with `_chest_type == DEUS_CHEST_TYPES.upgrade` (NOT a Chest of Trials — that's `DeusCursedChestExtension`). Upgrade altars are notably special in vanilla: `update()` derives `new_is_purchased` as `not self._stored_purchase and chest_type ~= upgrade or table.contains(collected_by_peers, peer_id)` (`deus_chest_extension.lua:175`). The `chest_type ~= upgrade` clause means an upgrade altar's purchased-state is driven **purely** by membership in `collected_by_peers` (the swap/power_up altars also flip purchased when `_stored_purchase` is nil). So an upgrade altar that stays "looted" after re-arm almost certainly still has the own peer in `collected_by_peers` on the next update tick.
- **Probe points (all forced output — unconditional `mod:info`, tagged `[altar_visual_probe]`; user just plays, no command):**
  1. In the consolidated `open_chest` re-arm path: an `OPEN` line (chest_type, go_id, uses/max_uses, whether the re-arm branch will run, is_server, `_is_purchased`/`_animation_state`/`_profile_index`, and `collected_by_peers` BEFORE the uncollect); a `REARM` line (own_peer + `collected_by_peers` AFTER `_ct_altar_uncollect` + the post-re-arm visual state we wrote); a `DEPLETED` line when max uses is reached (expected dark); and a `no go_id` line if the re-arm path is skipped entirely.
  2. A new **read-only** `mod:hook("DeusChestExtension", "update", ...)` (ct_dev had no prior hook on this method — VMF-clean) that, for a re-armed chest, logs each of the next 8 ticks: the pre/post `_is_purchased`/`_animation_state`/`_profile_index`, whether `_stored_purchase` is set, whether it's an upgrade chest, whether the own peer is still in `collected_by_peers`, and the full array — so the log shows exactly which tick (and which derivation) re-darkens it.
- **Obvious bug NOTED (not fixed, per diagnose-first):** the v0.7.151 `_ct_altar_uncollect` removes only the OWN peer from `collected_by_peers`. If the bug reproduces solo/host, the probes will confirm whether the own-peer removal is actually landing; if it reproduces only on a CLIENT-opened upgrade altar, suspect the `ct_altar_uncollect` RPC round-trip (host clears the field, but the host's authoritative write must propagate back before the client's `update` re-derives) — the UPDATE probe's `own_in_collected` field on the client will show it. Left for the user to confirm with the captured log.

### Added — Task B: Chest of Trials uniqueness (toggle, default OFF, [untested]) — every chest after the first spawns a different trial
- **Report:** multiple Chests of Trials in one mission spawn the same enemies. **Root cause (verified from decompiled source):** `DeusCursedChestExtension` activation calls `Managers.state.conflict:start_terror_event("cursed_chest_prototype", Managers.mechanism:get_level_seed(), unit)` (`deus_cursed_chest_extension.lua:105-109`) — every chest in the level passes the **same** level seed. `cursed_chest_prototype` (`deus_generic_terror_events.lua:50`) is a master event whose `inject_event` blocks each pick one faction challenge via `Math.next_random(data.seed, 1, #event_name_list)` (`terror_event_mixer.lua:1667`), where `data.seed` is the seed we passed (stored verbatim by `add_to_start_event_list`, `:1572-1580`). Same starting seed → same random walk → same challenge → same enemies.
- **Fix:** new host-authoritative `mod:hook("ConflictDirector", "start_terror_event", ...)`. When the event is `cursed_chest_prototype` and the toggle is on, mix a per-mission activation counter (`_ct_cursed_chest_seq`) into the seed (`HashUtils.fnv32_hash(base .. "_ct_trial_" .. seq)`, FNV-prime fallback if `HashUtils` is absent), so each subsequent chest's `inject_event` walk lands on different indices → a different trial. **Chest #1 (seq 0) keeps the vanilla seed** (no offset); only chests 2..N are perturbed. Cursed-chest activation + terror events are server-side, so clients never call this for cursed chests — purely host-driven; the value reaches clients through the normal terror-event RPC.
- **Per-mission counter reset** at both the existing `DeusMechanism._transition_next_node` hook (every node transition) and the `DeusRunController.setup_run` hook (run start) — belt-and-suspenders, no new hooks.
- **Composes with `cot_enemy_multiplier`:** this only changes the SEED used to PICK the challenge; the enemy spawn-count scaling is a separate `spawn_around_origin_unit` hook. Neither touches the other.
- New setting `cursed_chest_unique_trials` (checkbox, default `false`, `[untested]`) + tooltip; host-synced via `effective_setting` like every other ct setting.

### Tests
- `altar_visual_probe_present` (Task A marker), `cursed_chest_unique_trials` (Task B marker + asserts the per-mission counter global is a number).

## 0.7.156-dev (2026-06-20) — Fix: client crash on the CW curse banner (curse-description icon was a table, not a texture name)

Client crash in a CW expedition on an injected-adventure level (`dlc_termite_*`) with a curse active: `scripts/ui/ui_passes.lua:134: bad argument #2 to 'UIRenderer_draw_texture' (string expected, got table)`, from `deus_curse_ui.lua:214 (draw)`. **Root cause (vanilla, exposed by ct):** the curse-banner's `theme_icon` texture pass at scenegraph `description_pivot` reads its texture NAME from `content.theme_icon` (`deus_curse_ui_definitions.lua:317-324`), and that pass's `content_check_function` only tests `~= nil` — not string-ness. `DeusCurseUI.show_curse_info`/`show_special_message` set `local icon = theme_settings.icon or { 255, 255, 255, 255 }` (`deus_curse_ui.lua:144-149` / `:106-111`) and assign it straight to `content.theme_icon` (`:170`). `DeusThemeSettings.wastes` is the **only** theme with no `icon` field (all 5 god themes + belakor have one), so when ct forces `node.theme = "wastes"` to suppress curse aesthetics on a node whose curse is still shown (the `start_next_round` / `_transition_next_node` save-restore), the `or {color}` fallback fires and the renderer gets a **table** where it wants a **string** → crash. Vanilla never hits this because `deus_generate_graph` always forces a god theme for any curse node.

**Fix:** same DATA-backfill approach as the v0.7.139-dev nil-color fix, and folded into the **same** `CURSE_THEME_COLOR_BACKFILL_MARKER` load block (no new hook — there is no `mod:hook` on `DeusCurseUI` anywhere in ct; zero duplicate-hook risk). At mod-load we now also give every `DeusThemeSettings` theme that lacks a string `icon` a valid one (`"deus_icon_meta_01"`, a neutral deus-realm meta icon from `gui_icons_atlas` that is loaded in every CW expedition). Lowest blast radius: only the curse-description theme icon for the wastes-on-cursed-node case is touched; normal god-themed curse banners already have their own `icon` and are untouched (the `type(theme.icon) ~= "string"` guard skips them). Idempotent, timing-free (boot-global available at load), and identical on host and every client so the data stays consistent peer-to-peer. Extended the `curse_theme_color_backfilled` regression test to also assert every theme carries a string `icon`.

## 0.7.155-dev (2026-06-20) — Fix: CW round-end RPC overflow no longer freezes the next expedition

Reported freeze on starting a new Chaos Wastes after a round, with `[finale_dominant_god] vanilla game_round_ended errored ... Failed to pack parameter 3, too many characters in string with max length 500`. Root cause: a `mod:network_send` firing inside vanilla `DeusMechanism.game_round_ended` → `_setup_run`'s graph/settings broadcast JSON-encodes its payload into one string and overflows Stingray's 500-char RPC cap (`network_utils.lua:93`), throwing **before** vanilla assigns `self._next_state` (`deus_mechanism.lua:621`/`:666`). The v0.7.81 fix swallowed the throw to avoid a host crash, but that left the mechanism with no next state → the next CW round never loads → **freeze**. **Fix:** in the existing `game_round_ended` hook's error branch, when the transition was skipped (`_next_state == nil`), drive `self:_transition_next_node("start")` ourselves to finish what vanilla skipped (pcall-wrapped — worst case it warns, never worse than the freeze). The run + graph are already built by `_setup_run` before the failing broadcast, so the recovery is safe. This fixes the freeze regardless of WHICH mod's un-chunked `network_send` overflowed — notably a **co-loaded stable `ct` alongside `ct_dev`** (running both is misconfiguration; ct_dev can't chunk a third party's send). ct_dev's own broadcasts are all chunked (`SYNC_CHUNK_SIZE = 400`) and cannot overflow. Recent v0.7.151/.153/.154 did not contribute (none serialize into the round-end payload).

## 0.7.154-dev (2026-06-20) — Fix: CW pickup transforms leaked into real Adventure (no tomes in Adventure)

`on_injected_adventure_level()` gated only on whether the current level is one CW *can* inject into its pool — but those same maps (Horn of Magnus, etc.) exist in **stock Adventure under the same `level_id`**, so the gate returned true in real Adventure too. That leaked every CW-only pickup transform into Adventure: the **tome/grimoire → Chest-of-Trials substitution** (so tomes/grimoires vanished), the pedestal/collectible → Pilgrim's Coin conversion, the `no_roamers` pacing filter, and `force_belakor`. **Fix:** the gate now ALSO requires an actual Chaos Wastes (deus) expedition — `Managers.mechanism:game_mechanism():get_deus_run_controller()` must be live (the same "are we in CW" idiom `_current_node_theme`/`_current_node_curse` use); Adventure's mechanism has no such method, so the gate bails and Adventure plays vanilla. CW expeditions are unaffected (the run controller is live there). Reported 2026-06-20: tomes missing in Adventure mode.

## 0.7.153-dev (2026-06-20) — Miracle of Isha (Aegis / Unlimited Wounds) now lasts the NEXT MISSION ONLY

### Changed — Aegis and Unlimited Wounds are scoped to one mission instead of the whole run
- The two Miracle of Isha reworks — **(A) Aegis** (`-25% damage taken`) and **(B) Unlimited Wounds** (recruit-style, every knockdown revivable) — previously lasted the entire CW run. They now last **only the next mission** after purchase, then expire.
- **Mechanism (Option B):** dropped `is_persistent = true` from the Aegis and Wounds buff templates. Vanilla `DeusSpawning`'s per-frame save loop (`deus_spawning.lua:249`) only saves buffs whose template has `is_persistent`, so once the flag is gone these two are **never auto-saved and never auto-reapplied** by the vanilla machine — there is no whole-run carry.
- To make them cover the **next** mission (rather than dying in the shop where the buy happens — the shop is a unit-less `map` node), the buy hook now stashes the chosen buff name on a host-side run-controller field (`rc._ct_isha_pending`) that survives the shop→mission transition. A new host-only `mod:hook_safe("DeusSpawning", "_apply_initial_buffs", ...)` promotes that flag to active on the next mission's first spawn, applies the buff to every hero/bot for that mission, and **consumes it when the next node change is observed** (keyed on `rc:get_current_node_key()`, which is stable within a mission and distinct between consecutive missions — race-free, no game-start vs spawn ordering dependence).
- **Respawns within the granted mission keep the buff** — a respawn re-enters `_apply_initial_buffs` at the same node key, so the buff is re-applied (guarded by `has_buff_type` so a hero who never died is not double-stacked).
- Host-authoritative as before: `buff_system:add_buff` broadcasts to clients via `rpc_add_buff_synced` (templates are pre-registered in `NetworkLookup.buff_templates`); clients never touch the persistence list.

### Unchanged — Miracle of Ulric (+50 Power) still lasts the whole run
- Ulric **keeps** `is_persistent = true` and the vanilla whole-run save/reapply path. It is applied immediately on purchase and persists for the rest of the run, exactly as before. Only the two Isha buffs were rescoped.

### Text + tests
- Reworded the Aegis/Wounds VMF option labels + tooltips and the in-shop blessing descriptions to say "for the next mission" / "next mission only". Ulric's "+50 Power for the rest of the run" text is unchanged.
- Extended `/verify_isha` to print the one-mission pending/active flag state (`<no active CW run>` in the keep).
- Added regression marker `miracle_of_isha_one_mission_not_persistent`: asserts the apply/consume hook marker constant is present AND the live invariant that exactly Ulric (not Aegis/Wounds) carries `is_persistent` on its registered `BuffTemplates` entry.

## 0.7.152-dev (2026-06-20) — Altar cost: remove mislabeled "Chest of Trials" override from boon altars + document altar-vs-chest terminology

### Fixed — boon altars are priced by the altar-reuse multiplier again (the "Chest of Trials cost" feature was mis-targeted)
- The "Chest of Trials (pay-with-coin)" feature was hooked on `DeusChestExtension.get_purchase_cost` for `_chest_type == power_up`. **`power_up` is the boon ALTAR (Shrine of Solace), not a Chest of Trials** — so the trials schedule was wrongly **re-pricing every boon altar** and, because its branch returned first, **shadowing the intended altar-reuse multiplier** (`150 * mult^uses`). The user's own logs showed `[altar_reuse] type=power_up used 1/2` and `[trials] boon chest #1` firing on the **same object** — proof they were one altar, not two chest kinds.
- **An actual Chest of Trials is a separate engine class, `DeusCursedChestExtension`** (`scripts/unit_extensions/deus/deus_cursed_chest_extension.lua`): it has **no `_chest_type` and no `get_purchase_cost`** — you pay by fighting the trial wave, never with coin. There was no purchase step for the trials cost to legitimately hook; the feature could never have priced a real Chest of Trials.
- **Per user decision, the settings are deleted.** Removed the `trials_cost_enabled` / `trials_cost_base` / `trials_cost_mult` widgets (`_data.lua`) + their 6 localization strings, the now-dead `_ct_trials_cost_for` helper and `_ct_trials_bought_this_map` per-map counter (+ its two reset sites), and the `chest_of_trials_cost_schedule` regression test (it asserted the deleted helper/widgets and would have hard-failed). With the trials branch gone, a `power_up` open falls straight through to the altar-reuse path, so **boon altars are now correctly priced by `150 * mult^uses`** (`altar_reuse_cost_mult_power_up`).
- **Kept** the legitimate boon-altar no-repeat bookkeeping (record taken boons so later altars don't re-offer them), renamed honestly from `_ct_trials_taken_boons` → `_ct_boon_altar_taken_boons` and re-tagged its log `[trials]` → `[boon_altar]`. Added a `boon_altar_no_repeat` regression marker in place of the deleted cost-schedule test.
- **`cot_enemy_multiplier` is untouched** — it correctly targets the real Chest of Trials via the terror-event tag `spawn_counter_category == "cursed_chest_enemies"`.

### Docs — added an altar-vs-chest terminology banner
- Added a banner comment above the altar cost-helper region: in-game the only "chest" is a **Chest of Trials** (`DeusCursedChestExtension`, no `_chest_type`, no coin cost); the boon / weapon-swap / weapon-upgrade shrines are **ALTARS** that the engine confusingly calls `DeusChestExtension` with `_chest_type = power_up`/`swap_melee`/`swap_ranged`/`upgrade`. Any `_chest_type == power_up` branch acts on a BOON ALTAR, never a Chest of Trials. No new `mod:hook` (the `get_purchase_cost` hook stays a singleton — only its body shrank).
- **Supersedes the 0.7.151-dev "Cost behavior" note below**, which described the now-removed trials schedule as owning the boon price — that was the mislabeled behavior being removed here.

## 0.7.151-dev (2026-06-20) — Altar reuse: fix the re-armed shrine still looking looted

### Fixed — re-armed boon shrine (and weapon swap/upgrade altars) no longer stay visually consumed
- A reused altar (`altar_reuse_count_* > 1`) functionally re-armed but still **looked looted** between uses — the re-rolled offering's hologram never reappeared.
- **Root cause:** the re-arm zeroed only the chest's LOCAL state (`_is_purchased`, `_animation_state`, `_profile_index`, `_career_index`) but never cleared the **networked GameSession field `collected_by_peers`**. That field is the authoritative "this peer looted this chest" record. The first open inserts the opener's peer into it (vanilla server handler `rpc_deus_chest_looted`, `deus_chest_extension.lua:737-752`) and **nothing in vanilla ever removes it** — the vanilla chest network sync is one-directional toward "looted" only. So one tick after re-arm, vanilla `DeusChestExtension.update` (`deus_chest_extension.lua:175`) re-derived `new_is_purchased = ... or table.contains(collected_by_peers, peer_id)` → re-asserted `_animation_state = "looted"` (lines 177-182) → line 194 skipped `_update_chest_animation_and_sound_state`, so the offering presentation never re-fired.
- **Fix:** on re-arm, the chest now also **retracts the own peer** from `collected_by_peers`, kept adjacent to the `_profile_index`/`_career_index` zeroing so the next `update` tick sees consistent state and takes the non-looted branch (re-displaying the re-rolled hologram). The field is server-authoritative, so:
  - **Host opener** writes it directly.
  - **Client opener** sends a new `ct_altar_uncollect` VMF RPC to the host (resolving the real host peer_id — VMF's `network_send` silently drops the `"server"` recipient, VMF_RECIPES § 3), and the **server** clears the authoritative field; the cleared state replicates back to every peer. This mirrors vanilla loot, which is server-authoritative (`purchase()` → `send_rpc_server` at `deus_chest_extension.lua:315`).
- The clear removes **only the own peer**, never the whole array — co-op peers may have looted other chests, and the field is per-GameSession-object. It is a pure data write to one field: it does **not** re-enter `purchase()` and does **not** spawn anything, so there's no risk of a double-spawned preview or a re-charged purchase.
- Implemented as two `mod._ct_*` helpers + one `mod:network_register("ct_altar_uncollect", ...)` server handler (no new `mod:hook` — the re-arm already lives in the consolidated `open_chest` hook). The handler resolves the sender from VMF's `sender_peer_id` (not a raw `CHANNEL_TO_PEER_ID`) and is gated on `CT_RPC_SCHEMA`.

### Cost behavior — unchanged and correct (NOT a bug)
- A boon (power_up) chest is **not free** in vanilla: it costs a flat 150 coins (`deus_cost_settings.lua: power_up = 150`), and the purchase path genuinely debits it. ct's reuse pricing is unchanged: with **Chest of Trials ON** the trials schedule fully owns the boon price (first boon each map free, then escalating round-down-to-50); with it **OFF**, the reuse multiplier charges `ceil(150 × mult^uses)`. No cost hook (`get_purchase_cost`, `_altar_cost_mult`, `_ct_trials_cost_for`) was touched.

## 0.7.150-dev (2026-06-19) — Test-status: skull curse disables confirmed

`[confirmed working]`: Disable Shadow Homing Skulls + Disable Skulls of Fury curses (user-verified in-game).

## 0.7.149-dev (2026-06-19) — Test-status labels on all menu entries

Prefixed every VMF menu widget with `[untested]` (and `[confirmed working]` for verified features) so we know what's safe to promote to stable `ct`. Tooltips, group headers, dropdown options, and `enable_debug_logging` are not labeled. The dynamic CW-scenario / adventure-mission map toggles are labeled in the `build_loc_entries()` consuming loop: **The Skittergate** → `[confirmed working]`; everything else `[untested]`. Known issue tracked: **Tower of Treachery** — gargoyle skull missing from chest (left `[untested]`). See `TESTING_STATUS.md`.

## 0.7.148-dev (2026-06-19) — Adventure-collectible coin coverage + bigger coin casket in leftover book spots

### Added — bigger coin casket where a tome/grimoire would have been
- On injected Adventure maps, book pedestals are already converted: the first N become Chests of Trials (per `cursed_chest_count`) and the next can become the Belakor locus. **Leftover book spots used to spawn nothing — they now spawn a bigger coin casket** (a reward where the tome/grimoire would have been). It's the normal `deus_soft_currency` casket (`deus_loot_pyramide_01`) scaled to **1.75×** and tagged `ct_big_casket`; a new `GameModeDeus._get_coins_amount_and_type` hook grants tagged caskets **3× the coin** of a normal casket. `_spawn_guaranteed_pickup` runs per-peer on injected levels, so the scale + tag land on every peer's copy. Always on (no toggle), like the rest of the pedestal conversion.

### Fixed/Improved — adventure collectibles → Pilgrim's Coin
- The collectible→coin swap now also catches **`lorebook_page`** (the lore-page collectible), alongside the existing `loot_die` conversion. Confirmed coverage of the requested DLC collectibles: the Bögenhafen ale, **Blightreaper Rugbrödder ale**, and **Enchanter's Lair poison-feast chalice** are all `loot_die`-tagged spawners of the same bonus-dice "hidden mission" system, so they were already converted; `painting_scrap` (collectible art, all maps) remains handled by the spawner-eligibility mapping. So every Adventure-map collectible with no CW use now becomes coin.

### Tests
- `_rt_register("cw_collectible_and_big_casket")` — `loot_die` + `lorebook_page` are in the collectible→coin set, and `GameModeDeus._get_coins_amount_and_type` exists (so the 3× big-casket hook can bind).

## 0.7.147-dev (2026-06-19) — Chest of Trials: pay-with-coin schedule + no-repeat boon offerings

### Added — Chest of Trials pay-with-coin (new "Chest of Trials" settings group)
- **`trials_cost_enabled`** (default OFF) + **`trials_cost_base`** (50–500, default 50) + **`trials_cost_mult`** (1.0–3.0, default 1.5). When on, boon (power_up) chests — the Chest of Trials — cost Pilgrim's Coin on an escalating schedule instead of the vanilla flat 150:
  - **First boon chest each map is FREE.** The Nth after that costs `round_down_50(base × mult^(N-2))`. With base 50 / mult 2: `0, 50, 100, 200, 400`. With mult 1.5: `0, 50, 50 (75→50), 100 (112→50…), …` — all floored to the nearest 50.
  - **Per-player, resets each map** (the first chest of every new map is free again). Tracked locally per peer: `get_purchase_cost` and `purchase()`/`open_chest` both run on the buying peer, so each player pays their own escalating price. Count increments in the consolidated `open_chest` hook and resets via `_transition_next_node` (per map) + `setup_run` (run start).
  - **Host-authoritative:** base/mult read through `effective_setting` and auto-sync to clients (the keys are in the data tree, so `SYNCED_SETTING_NAMES` includes them).
  - Implemented by extending ct's existing `DeusChestExtension.get_purchase_cost` hook (no new hook — VMF dup-hook rule). When enabled, the Trials schedule fully owns the boon-chest price; weapon swap/upgrade shrines and the altar-reuse multiplier are untouched.

### Added — Chest of Trials no-repeat offerings (DEFAULT, no toggle)
- Each Chest of Trials now offers a trial **none of your earlier chests this run did**. Extends the existing `DeusPowerUpUtils.generate_random_power_ups` remove-then-restore strip: for `weapon_chest` rolls only, boons already taken this run (`mod._ct_trials_taken_boons`, recorded in `open_chest`, cleared at `setup_run`) are stripped from the pool before the roll. Per-peer; other roll sources (shrine, cursed_chest, quest) are untouched.

### Tests
- `_rt_register("chest_of_trials_cost_schedule")` — helper exists, the three keys are in the synced set, and the schedule math holds (first free; base 50 / mult 2 → 0/50/100/200; round-down-to-50 with mult 1.5). Saves/restores live settings around the probe.

## 0.7.146-dev (2026-06-18) — Fix boon-roll announce `<Invalid string format>` log error

### Fixed
- The bot boon-roll announce did `mod:echo(string.format("[ct] Bot %s got boon: %s (%s)", …))`. The boon display name can contain unfilled `%.1f` placeholders (raw loc + description_values), and `mod:echo` string-formats its first argument — so the pre-built string had its `%.1f` re-interpreted with no value and printed `<Invalid string format>` (`bad argument #2 to '?' (no value)`), 4× this session. Now passes the parts as args to `mod:echo` so it formats once; the boon name's `%` is inert as a `%s` value. Log-only (never crashed), but no more spurious error lines.

## 0.7.145-dev (2026-06-18) — REVERT the holy_hand spawn-weight cut (it crashed the game on load)

### Critical
v0.7.143-dev lowered `Pickups.grenades.holy_hand_grenade.spawn_weighting` 0.8 → 0.1 to make Morgrim's bomb rarer on injected CW campaign maps. **This crashed the game on mission load** for anyone running the build:

```
foundation/scripts/util/error.lua:26: Problem selecting a pickup to spawn,
spawn_weighting_total = 0.84999999999999998, spawn_value = 0.94332081079483032
```

Root cause: the spread-pickup sampler rolls `random` in `[0,1)` and walks the pool's cumulative `spawn_weighting`; if the pool total is **below the roll**, it falls off the end and hard-errors. holy_hand's 0.8 weight was load-bearing for the grenade pool total (the other grenades summed to only ~0.75). Cutting it to 0.1 made the total **0.85**, so any roll in `[0.85, 1.0)` crashed. This is the exact sampler invariant ct's own deus_potions renormalization already guards (a pool total must stay ≥ 1.0) — lowering a raw `spawn_weighting` violates it.

### Changed
- Removed the v0.7.143 load-time `holy_hand.spawn_weighting = 0.1` mutation entirely; holy_hand is back to vanilla 0.8 (no mutation, guaranteed crash-free). Morgrim's bomb is common again — the rate reduction has to be redone the safe way (renormalize the grenade pool so holy_hand's *share* shrinks while the total stays ≥ 1.0, or redistribute the removed weight onto the other grenades). A code comment at the old site documents the invariant so it isn't reintroduced as a bare weight cut.

## 0.7.144-dev (2026-06-18) — Fix client rendering injected adventure maps as shrines + losing curse lighting (Issue #68)

### Why
Confirmed from a paired host+client log (2026-06-18): on the CLIENT, every injected campaign/adventure node rendered as a SHRINE with no curse halo, and the in-mission curse sky/lighting tint never applied. The client logged `[DeusMapScene.on_enter] seen=15 rewritten=0 skipped=13` on every map open while the host had injected those maps. Root cause: the client builds `AdventurePool.IS_INJECTED_ADVENTURE_LEVEL` from its OWN per-map toggle selection, which can be empty or differ from the host's — so `adventure_base_from_level_key()` returns nil for every host-injected node. That makes the map UI fall to `SHRINE_NODE_UNIT` (no curse halo) **and** makes `on_injected_adventure_level()` false on the client, so ct's adventure-map curse sky/lighting tint is skipped. One defect, both symptoms.

### Fixed
- `apply_graph_snapshot` (client) now registers each host node's adventure base into the client's `IS_INJECTED_ADVENTURE_LEVEL`, validated against the full static catalog `MISSION_BY_KEY` (built at load on both peers, so a hit is a genuine adventure base — never a vanilla CW node like `arena_belakor`). Uses the host's synced `base_level`, falling back to deriving the base from the permutation level key. Idempotent; persists for the run once the snapshot is seen. Result: the client recognizes exactly the maps the host injected → nodes render as travel with the correct icon + curse halo, and ct's curse lighting applies in-mission. `[#68]` log line per newly-recognized base.

## 0.7.143-dev (2026-06-18) — Holy Hand Grenade much rarer on CW campaign maps

### Why
On the injected adventure/campaign maps, the Holy Hand Grenade ground pickup ("Morgrim's bomb") showed up far too often. Root cause: `Pickups.grenades.holy_hand_grenade.spawn_weighting = 0.8` — as likely as a regular grenade — and ct opens the campaign grenade pool on those maps, so this power-bomb claimed the (once-per-level) grenade slot constantly.

### Changed
- Load-time data mutation drops `Pickups.grenades.holy_hand_grenade.spawn_weighting` from **0.8 → 0.1** (~8× rarer). Naturally scoped to CW campaign maps — it's the only place the pickup spawns (its unit only loads in Morris/CW bundles, and vanilla CW arenas use deus spawners, not this campaign grenade pool). No toggle, per request. `[holy-hand]` log line confirms the value at load.

## 0.7.142-dev (2026-06-18) — Diagnostics for the client-only "curse lighting not showing" bug (instrument-only; no behavior change)

### Why
A client-only, intermittent bug ("worked yesterday", multiple players): the CW curse sky/lighting doesn't show for the client. Investigation (verified against decompiled source) points at this defect class: the in-mission curse tint and the curse aesthetics are recomputed LOCALLY on every peer from `current_node.theme`, not authoritatively networked. The prime suspect is ct's own `DeusMechanism.start_next_round` theme-force: it sets `theme="wastes"` (neutral) while a curse is **disabled**, and `is_curse_disabled()` reads the host value via `effective_setting` (host-settings sync). If a client's synced value diverged or hasn't arrived, the client suppresses a curse the HOST is showing → loses the curse lighting. This is sync-race + per-curse → intermittent and client-only. No fix yet — this build adds the probes to confirm it from a paired host+client log.

### Added (diagnostics only — ungated `mod:info`, no behavior change)
- `[ct:theme-force]` (ungated) — at the `start_next_round` force site: logs `is_server`, the node's `curse`/`theme`, and `is_curse_disabled` per transition. A host log showing `is_curse_disabled=false` while the client shows `true` for the same curse confirms the divergence. This is the root-cause signal and fires even without debug logging.
- The resulting per-node `theme`/`curse`/`god`/`node_type` (host vs client) is already dumped by the existing `[mission:start]` hook on `GameModeDeus.local_player_game_starts` (gated on `enable_debug_logging`) — no new hook added (VMF only allows one hook per method; a second would be dropped). Enable debug logging for that fuller dump.
- (The existing ungated `[DeusMapScene.on_enter] SKIP/rewrite` logs already capture the related "missions render as shrines" symptom — compare client SKIP vs host rewrite for the same node key; that's the open Issue #68 / DLC-or-toggle pool divergence.)

### To capture
- Reproduce in co-op with the missing lighting, get **both** the host's and the client's console logs, and diff `[ct:theme-force]` / `[ct:lighting]` per node. Then the fix (host-authoritative curse-disable on the client, or defer the theme-force until the host sync has arrived) can be targeted.

## 0.7.141-dev (2026-06-18) — Remove the Adventure save-item trait slider (moved to General Tweaker)

### Why
The "Adventure save-item trait chance (percent)" slider added in v0.7.140 controls the **Adventure-mode** charm traits Home Brewer / Healers Touch / Grenadier — it is not a Chaos Wastes feature and didn't belong in this mod. It now lives in **General Tweaker** as `gt_adventure_save_trait_chance` (1–75% slider). No other CW behavior changes.

### Removed
- `tweak_adventure_save_trait_chance` slider (data + localization), its `on_setting_changed` branch, its `sync_host_dependent_state` re-apply, and the whole `#6 Adventure save-a-consumable` block in `_ct_mechanic_tweaks.lua` (`ADV_SAVE_TRAITS`, `_adv_save_buff_entries`, `revert/apply_adv_save_traits`, `mod._ct_sync_adv_save_traits`). The `_effective` helper and the `#5 Shadow Homing Skulls stun` feature are untouched.

## 0.7.140-dev (2026-06-17) — Three user-suggested features: skull-stun slider, Adventure RNG-trait odds, Blessed Bots survival boons

All source citations verified against the decompiled vanilla source 2026-06-17.

### Mechanic tweaks (sliders, default = vanilla; main lua, mirrors the shard-strike/anath-raema save-restore pattern; wired into `sync_host_dependent_state` + `on_setting_changed`)
- **Shadow Homing Skulls stun (seconds)** (`tweak_shadow_skull_stun_sec`, default 2.5) — scales the timed "overpowered" disable the curse applies on skull impact: mutates `BuffTemplates.belakor_homing_skull_debuff_delayed_stun_effect.buffs[1].duration` (belakor_buff_settings.lua:655, perk `buff_perks.overpowered`). Server-authoritative, so the host's value governs (read via `effective_setting`). NOTE: the other skull curse, "Skulls of Fury", is a stagger (`stagger_value=2`), not a timed disable — no duration field, so it's intentionally not covered.
- **Adventure save-item trait chance (percent)** (`tweak_adventure_save_trait_chance`, default 25) — sets the proc chance of the Adventure traits Home Brewer / Healers Touch / Grenadier (`WeaponTraits.buff_templates.{trait_ring_not_consume_potion,trait_necklace_not_consume_healing,trait_trinket_not_consume_grenade}.buffs[1].proc_chance`, vanilla 0.25; weapon_traits.lua:69/84/104). Raise to 50 to match the CW Grenadier counterpart. Adventure and CW are separate templates (CW boons live in `DeusPowerUpBuffTemplates`), so CW is untouched.

### Bots
- **Blessed Bots: Survival Boons** (`ct_blessed_bots`, new module `_ct_blessed_bots.lua`) — grants every bot three CW survival boons in ANY game mode: Ereth Khial's Pride (`last_player_standing_power_reg`), Grimnir's Implacability (`deus_second_wind`), Morr's Protection (`deus_knockdown_damage_immunity_aura`). All are buff_template boons granted via `buff_system:add_buff(bot, "power_up_<key>_<rarity>", bot)` (deus_power_up_settings.lua:2865/2048/2371; deus_power_up_utils.lua:441). To resolve the templates outside a CW run we additively mirror `DeusPowerUpBuffTemplates` into the global `BuffTemplates` (BuffUtils.get_buff_template reads only BuffTemplates, buff_utils.lua:257). Host-side (single `PlayerBotBase.update` hook for this mod), throttled, idempotent (skips boons a bot already has). EXPERIMENTAL — verify in-game.

## 0.7.139-dev (2026-06-16) — Curse-banner crash fix reworked to a data backfill (kills the "trying to hook object that doesn't exist: DeusCurseUI" error)

### Why
The v0.7.137-dev curse-crash fix hooked `DeusCurseUI._update_description_widget`. But `DeusCurseUI` lives in `scripts/ui/hud_ui/` and isn't loaded until a deus HUD spins up **inside an actual CW expedition** — so at the adventure keep VMF's string-form hook couldn't resolve the class, logged a visible **`[MOD][ct][ERROR] (hook): trying to hook object that doesn't exist: DeusCurseUI`**, and the hook likely never installed (so the crash fix may have been inert). Seen in the 0.7.127-beta boot log 2026-06-17 entering the keep.

### Changed
- `chaos_wastes_tweaker_dev.lua` — **removed** the `DeusCurseUI._update_description_widget` hook + `mod._ct_curse_desc_color_or_default`, and **replaced** them with a load-time data backfill: walk `DeusThemeSettings` and set `curse_description_color = {255,255,255,255}` on any theme missing it (only `wastes`). `DeusThemeSettings` is a boot-global available at mod-load, so this is reliable and timing-free; it covers BOTH callers (`show_curse_info` :152 and the special-message path :117 read `theme_color` from the same table); and host + every client run it identically so the data is consistent peer-to-peer. No hook → no error. `CURSE_THEME_COLOR_BACKFILL_MARKER`.

### Tests
- Replaced `/ct_regression_test` check `curse_ui_nil_color_fallback` with `curse_theme_color_backfilled` (asserts `DeusThemeSettings.wastes.curse_description_color` is a valid 4-component color and no theme is left with a nil color).

## 0.7.138-dev (2026-06-16) — Trollhammer properties, fire-weapon traits, mid-run boon-count sync, bot-boon chat readout

### Why
Four issues reported 2026-06-17 in live play:
1. **Trollhammer Torpedo gets traits but no properties on CW upgrade.** Vanilla bug: the deus upgrade reads `WeaponProperties.combinations[property_table_name][rarity]` (`deus_weapon_generation.lua:161`); the torpedo's `property_table_name = "deus_trollhammer_torpedo"` (`deus_weapons.lua:256`) exists ONLY in the trait combinations table, never the property table → the property lookup returns nil → zero properties.
2. **Fire/heat weapons (Sienna staves, Bardin drakefire pistols / drakegun / flamethrower) get no trait on upgrade with the trait reworks on.** Their baked pool is the narrow `deus_ranged_heat` set, which (after the per-weapon compatible filter) has no common-tier trait. With `tweak_trait_tier_by_rarity` on, `get_tier_filtered_combos` returned zero combos at low rarity → `override_traits_in_result` early-returned → vanilla left traits nil. Melee/ranged-ammo weapons carry common-tier traits, so they got one — hence the asymmetry the user saw.
3. **Host changing boons-per-chest/shrine (or any synced setting) mid-run didn't reach clients for the rest of the run.** The host's chunked settings broadcast fired ONLY inside `DeusRunController.setup_run` (once per run). `mod.on_setting_changed` never re-broadcast, so clients' `_ct_host_settings` (read by `effective_setting`) stayed frozen at the run-start snapshot.
4. **No way for the host to see which boons bots receive** when random/mirror bot boons are on (only debug-log lines existed).

### Changed
- **Trollhammer (`chaos_wastes_tweaker_dev.lua`)** — at load, alias `WeaponProperties.combinations.deus_trollhammer_torpedo = WeaponProperties.combinations.deus_ranged` (guarded by `rawget` + key-exists; idempotent; reference-alias is safe since vanilla only reads `combinations`). No new hook. `TROLLHAMMER_PROPERTY_ALIAS_MARKER`.
- **Fire-weapon traits (`chaos_wastes_tweaker_dev.lua`)** — `get_tier_filtered_combos` now falls back to the weapon's OWN baked pool when no tier-eligible combo exists at the rolled rarity, so restricted-pool weapons draw a (possibly higher-tier) trait **only from their own compatible pool** — never a generic/incompatible one — instead of getting nothing. Behavior-preserving for melee/ranged-ammo (their `#filtered` is never 0). No new hook (merges into the existing four `DeusWeaponGeneration` hooks via `_filtered_weapon_gen`). `FIRE_WEAPON_TIER_FALLBACK_MARKER`.
- **Mid-run sync (`chaos_wastes_tweaker_dev.lua`)** — extracted the inline host broadcast into `mod._ct_broadcast_host_settings(reason)` (reuses the existing `ct_sync_host_settings_chunk` RPC + `CT_RPC_SCHEMA` — no new registration). `setup_run` now calls it; `mod.on_setting_changed` now also calls it, gated to host + synced settings (`mod._ct_synced_set`), so a mid-run host edit re-pushes immediately and the next client boon/altar roll uses the new value. `MIDRUN_SETTING_REBROADCAST_MARKER`.
- **Bot-boon chat readout (`chaos_wastes_tweaker_dev.lua` + `_data` + `_localization`)** — new host-only `announce_bot_boons` checkbox (default off). When on, the existing `add_power_ups` bot loop emits a local `mod:echo` per (bot, boon) naming the bot and the friendly boon name (`mod._ct_boon_display_name`). No new hook (merges into the existing `add_power_ups` hook_safe); `mod:echo` is local-only (no RPC/version-sync risk).

### Tests
- New `/ct_regression_test` checks: `trollhammer_property_pool_aliased`, `fire_weapon_tier_fallback_nonempty`, `midrun_setting_rebroadcast_wired`, `bot_boon_announce_wired`.

### To verify (in-game)
- Upgrade a Trollhammer Torpedo at a CW reliquary → it now gets properties as well as traits.
- With the trait reworks on, upgrade a fire weapon (staff / drakefire) → it now receives a heat-pool trait at every rarity.
- As host mid-run, raise boons-per-chest/shrine → clients' next chest/shrine offers the new count (no re-run needed).
- Enable random/mirror bot boons + `Announce Bot Boons in Chat` → host sees a chat line per bot boon grant.

## 0.7.137-dev (2026-06-16) — Fix deus curse-banner crash on suppressed-curse nodes (theme="wastes" has no curse color)

### Why
Reported crash 2026-06-17 (client, joining a CW run): `deus_curse_ui_definitions.lua:599: attempt to index field 'color' (a nil value)` on Citadel of Eternity (`sig_citadel_khorne_path5`), with `theme="wastes"`, `curse="curse_corrupted_flesh"`, `theme_color=nil`. Multi-agent root cause (high confidence): `DeusCurseUI.show_curse_info` reads `theme_color = DeusThemeSettings[theme].curse_description_color` and passes it to `_update_description_widget`, which assigns it to five glow `style.color` tables; the `description_start` animation then indexes `style.<glow>.color[1]`. **`DeusThemeSettings.wastes` is the only theme with no `curse_description_color`** (the god themes all have it). Vanilla never produces theme="wastes" with a real curse (`deus_generate_graph` forces a god theme for curse nodes), but ct **forces `node.theme="wastes"` to suppress curse aesthetics** (`start_next_round` / `_transition_next_node`) while the curse can still be shown — so `theme_color` is nil and the glow color tables are nil → crash.

### Changed
- `chaos_wastes_tweaker_dev.lua` — new `DeusCurseUI._update_description_widget` hook (mandatory pre-flight: 0 prior `DeusCurseUI` hooks) that substitutes a default opaque-white color when `color` is nil, via `mod._ct_curse_desc_color_or_default`. It sits **downstream of every theme/curse mutation path**, so it can't be defeated by the save/restore desync, and it leaves curse suppression intact (both the curse-info and special-message paths funnel through this method). Existing themed colors pass through unchanged.

### Tests
- New `/ct_regression_test` check `curse_ui_nil_color_fallback` (nil → 4-component color; existing color passes through).

### Follow-up (deferred, not in this hotfix)
- pcall-wrap the `func(...)` calls in the `start_next_round` (`:1913`) / `_transition_next_node` (`:1881`) save-restore hooks so a wrapped error can't leave `node.theme="wastes"` for the rest of the run (the secondary aggravator; the color guard already makes the UI crash-proof regardless).

## 0.7.136-dev (2026-06-16) — Fix host-crash on CW path missions with no deus_weapon_chest_distribution (e.g. cemetery_tzeentch_path1)

### Why
Reported crash 2026-06-16 (nicho, hosting): `deus_run_controller.lua:2468: No deus_weapon_chest_distribution set for cemetery_tzeentch_path1` — a **fatal** host crash. Root cause is vanilla `DeusRunController.get_deus_weapon_chest_type`: it reads `LevelSettings[level_key].deus_weapon_chest_distribution` and `assert`s if it is nil, then **rebuilds from that same table whenever the distribution is exhausted**. Some native CW path missions (the Beastmen / Tzeentch path variants like `cemetery_tzeentch_path1`) ship with **no** distribution, so the moment a deus weapon chest spawns the assert fires and the host dies — ending the run for everyone. This is the same class as Issues #58/#60/#68 (CW path missions missing pickup/chest config) but fatal rather than just dropping pickups. ct already hooks `get_deus_weapon_chest_type` (for custom altar distributions) and, when the player hasn't set custom altar counts, falls straight through to the vanilla function — so the assert was reachable.

### Changed
- `chaos_wastes_tweaker_dev.lua` — extended the **existing** `DeusRunController.get_deus_weapon_chest_type` hook (no new hook — duplicate-hook rule) with a guard, `mod._ct_ensure_deus_chest_distribution(self)`, that runs before any path reaching vanilla. It resolves the current `level_key` exactly as vanilla does and, **only if** `LevelSettings[level_key].deus_weapon_chest_distribution` is nil, injects a balanced fallback (`{ [upgrade]=1, [swap_melee]=1, [swap_ranged]=1, [power_up]=1 }`) **into `LevelSettings[level_key]`**. Injecting into LevelSettings (not just `self._deus_weapon_chest_distribution`) is required because vanilla re-reads it on exhaustion. Idempotent — never overwrites an existing distribution; degrades to a no-op if `LevelSettings`/`DEUS_CHEST_TYPES` aren't available. Logs an ungated `mod:warning` naming the offending level. Decomposed into pure helpers (`_ct_deus_chest_needs_fallback`, `_ct_build_deus_chest_fallback`) for testability.

### Tests
- New `/ct_regression_test` check `deus_chest_distribution_fallback` — asserts the inject/skip decision (nil distribution → inject; existing distribution → don't overwrite; nil level_settings → skip) and the fallback shape (covers all 4 `DEUS_CHEST_TYPES` with positive amounts; returns nil when `DEUS_CHEST_TYPES` is unavailable).

### To verify (in-game)
- Start a CW run that routes through a Beastmen/Tzeentch path mission (`cemetery_tzeentch_path1` or sibling) and confirm the host no longer crashes on chest spawn; deus weapon chests appear and open normally. Run `/ct_regression_test` → `PASS: deus_chest_distribution_fallback`. (Fix is in **ct_dev**; promote to stable + upload for nicho, who runs the public build, to receive it.)

## 0.7.135-dev (2026-06-13) — Fix dead VMF settings-gate in the dev clone (Issues #39/#40 never fired in ct_dev)

### Why
Multi-agent audit 2026-06-13. The two `VMFOptionsView` hooks added in v0.7.120-dev — the starting_coins slider snap-to-25 (#39) and the Miracle-of-Isha mutex visual refresh (#40) — gate on `widget_content.mod_name == "ct"` / `mod_name == "ct"`. VMF sets a widget's `mod_name` to the OWNING mod's registered id, and this dev clone is registered `new_mod("ct_dev", ...)`, so in the dev build every ct widget reports `"ct_dev"` and the `== "ct"` comparison was never true. Both hooks were therefore **dead in dev**: the slider didn't snap to 25 and the Isha sibling checkbox never visually deselected (exactly the #40 report). The literals were copied verbatim from stable `chaos_wastes_tweaker` (registered `"ct"`, where they work) without re-pointing to the dev id.

### Changed
- `chaos_wastes_tweaker_dev.lua:8699` — slider gate `widget_content.mod_name == "ct"` → `== "ct_dev"`.
- `chaos_wastes_tweaker_dev.lua:8729` — mutex-refresh gate `mod_name == "ct"` → `== "ct_dev"`.
- `chaos_wastes_tweaker_dev.lua:8691` — banner comment updated to `mod_name == "ct_dev"`.

Behavior-preserving in the sense that both gates were previously never true in dev (runtime no-ops); re-pointing them to the correct mod id only enables the already-authored, stable-proven behavior, scoped to this mod's own widgets. Stable `chaos_wastes_tweaker` is already correct (registered `"ct"`, gate matches) and is **not** touched.

### To verify
- In keep, open the ct_dev settings: drag the starting_coins slider and confirm it snaps in steps of 25; toggle Miracle of Isha Aegis ↔ Unlimited Wounds and confirm the sibling checkbox visually deselects.

### Follow-up (deferred)
- A runtime `_rt_register` can't catch this regression class (the gate literal lives in a closure, not readable at runtime, and this file is near the Lua 200-locals-per-chunk limit). A repo-level qa/mod-lint source-pattern check ("VMF `mod_name ==` gate literal must equal the file's `new_mod(...)` id") would prevent the copy-from-stable regression — tracked as a tooling enhancement.

### Also — Issue #51 (unpack-safety annotations)
- Appended an inline `-- unpack-safe` pragma to the 5 verified-defensible `return unpack(...)` sites (`:1890`, `:2724`, `:3632`, `:3829`, `:3868`) so `qa/check_unpack_safety.ps1` no longer WARNs on them (each was already audited single-return / empty-result per the v0.7.107-dev nil-hole audit; the prose comment just didn't match the suppression pragma). The check itself was also taught to skip `--[[ ]]` block comments and string-literal interiors, removing the `_safe_hook.lua` and `:10097` false positives (no source change to those). The matching stable `chaos_wastes_tweaker` sites still WARN until this is promoted.

## 0.7.134-dev (2026-06-08) — Fix v0.7.133 regression: Belakor-temple forced rarity dropped by the new unpack bound; ungate trait-filter failure log

### Why
Post-ship re-review of the v0.7.133 audit fixes (fresh-eyes verification pass, 2026-06-08) found that the `generate_random_power_ups` arity fix **introduced a regression**: the hook captures `n = select("#", ...)` at entry, but the Belakor-temple branch writes `args[8] = "unique"` *after* capture. Vanilla's cursed-chest path passes only 7 args (`deus_run_controller.lua:1115` — no `forced_rarity`), so the forward `pcall(func, unpack(args, 1, n))` with `n = 7` silently dropped the forced rarity that the pre-fix bare `unpack(args)` used to deliver (args 1–7 are all non-nil on that path, so the array was contiguous through 8). Net effect: the Force Bel'akor's Temple unique-rarity boon roll has been dead since v0.7.133 shipped — while the `[belakor-temple] ... forced=unique` log line kept claiming otherwise.

Also from the same re-review: the trait-filter error path logged via `_dbg_alert` (gated on Debug Logging), inconsistent with the standing rule that failure paths log ungated.

### Changed
- **`chaos_wastes_tweaker_dev.lua` (`generate_random_power_ups` hook):** after the `args[8] = "unique"` write, the unpack bound is extended via the new `mod._ct_extend_arity_for_forced_rarity(n)` (returns `max(n, 8)`; never shrinks a larger n). The forward now carries the forced rarity again.
- **`chaos_wastes_tweaker_dev.lua` (`_filtered_weapon_gen`):** failure path logs via **ungated `mod:warning`** (was `_dbg_alert`) so a raised vanilla call reaches the log without Debug Logging enabled, matching the sibling boon-hook path.

### Tests
- `belakor_forced_rarity_survives_unpack_bound` — replicates the capture→mutate→forward sequence with vanilla's 7-arg cursed-chest shape; asserts 8 args are forwarded with `"unique"` in slot 8, and that the bump never shrinks an already-larger n. Fails on the v0.7.133 shape (stale `n = 7`).

## 0.7.133-dev (2026-06-07) — Audit hardening: trait-filter pcall (F14), variadic-hook arity, dump forward-refs

### Why
Audit 2026-06-07 flagged three classes of latent bug:

- **F14 (state corruption, LOW):** the four `DeusWeaponGeneration` trait-filter hooks (`generate_weapon`, `generate_weapon_for_slot`, `generate_item_from_item_key`, `upgrade_item`) save-mutated the global `DeusWeapons[*].baked_trait_combinations`, called vanilla, then restored — **without** a pcall around the bracket. If vanilla raised mid-call, the restore was skipped and the table stayed permanently filtered for the rest of the session (banned traits never returned; `any_trait_any_weapon`'s expanded pool stuck). Same shape as the boon-removal hook that was already hardened in v0.7.90 — this finishes the job the "POTENTIAL BUG (LOW)" comment had been flagging since v0.7.28a.
- **Bare-unpack nil holes (§2a):** three hooks forwarded varargs to vanilla with bare `unpack(args)`. Lua 5.1 `#t`/`unpack(t)` is undefined across a nil hole, so a nil trailing arg truncates the forwarded list. Affected: `on_soft_currency_picked_up` (trailing `type` arg often nil), `DeusRunController.setup_run` (trailing `mutators`/`boons` often nil), `DeusPowerUpUtils.generate_random_power_ups` (trailing `forced_rarity` usually nil). Same class as the weapon_tweaker v0.12.77/.78 burn.
- **Forward-ref (lint):** `_dump_pickup_system_state` and `_dump_pickup_spawners_verbose` were `local function`-defined (~L3069/L3191) BELOW their first reference inside the `populate_pickups` hook closure (~L2698). Lua 5.1 binds locals lexically at closure-creation with no hoisting, so the closure captured a nil global and the post-populate diagnostics silently no-op'd (`pcall(nil, ...)` returns false).

### Changed
- `chaos_wastes_tweaker_dev.lua:2240-2270` — new `_filtered_weapon_gen(label, func, gen_rarity, n, args)` helper wraps the apply→vanilla→restore bracket in pcall; restore runs on the error path, `_dbg_alert`s the failure, then re-raises with the original message. All four `DeusWeaponGeneration` hooks now route through it and pass arity-preserving `(n, args)` captured via `select("#", ...)` (the vanilla fns take trailing nilable `seed`/`weapon_pool`/`slot_chance_*`).
- `chaos_wastes_tweaker_dev.lua:611` (`on_soft_currency_picked_up`) — capture `n = select("#", ...)`; forward `unpack(args, 1, n)`. args[1] (amount) mutation unchanged.
- `chaos_wastes_tweaker_dev.lua:1451,1471` (`DeusRunController.setup_run`) — capture `n`; forward `unpack(args, 1, n)`. args[5] (starting_coins) mutation unchanged.
- `chaos_wastes_tweaker_dev.lua:1559,1696` (`DeusPowerUpUtils.generate_random_power_ups`) — capture `n`; `pcall(func, unpack(args, 1, n))`. count/forced_rarity mutations unchanged.
- `chaos_wastes_tweaker_dev.lua:607-608` — bare forward declarations `local _dump_pickup_system_state` / `local _dump_pickup_spawners_verbose` added to the existing forward-decl cluster; `local` dropped on the later definitions (now ~L3069/L3192) so they assign into the forward-declared upvalue slot.
- `chaos_wastes_tweaker_dev.lua:44` — MOD_VERSION `0.7.132-dev` → `0.7.133-dev`.
- `chaos_wastes_tweaker_dev.lua:~617` — new `CT_VARIADIC_ARITY_MARKER` constant for the arity regression check.

### Tests
- New `/ct_regression_test` check `pickup_dump_helpers_forward_declared` — asserts both dump helpers are functions at chunk scope and NOT leaked to `_G` (the broken-global variant of the forward-ref bug).
- New check `variadic_hooks_arity_preserved` — marker assertion (`CT_VARIADIC_ARITY_MARKER`) plus a behavioral round-trip proving `select("#")` + `unpack(t,1,n)` preserves a value trailing a nil hole (which bare `unpack(t)` drops).
- New check `trait_filter_restores_on_error` — synthetic-table replica of the F14 apply/pcall/restore contract; FAILS if the restore is skipped on a throwing-func path or if the error is swallowed instead of re-raised.

### To verify
- Run `/ct_regression_test` — the three new checks plus all prior checks PASS.
- In a CW run, ban a trait and roll/upgrade weapons at an altar; confirm bans still apply and (if a vanilla weapon-gen error ever fires) subsequent rolls are unaffected (no stuck filter).
- With `enable_debug_logging` on, enter a CW mission and confirm the `[ct_dbg][pickups:post_populate]` / `[ct_dbg][pickup_units:post_populate]` dump lines now appear (they were silently absent before the forward-ref fix).
- Coins pickup, run start, and boon rolls still behave normally (arity fix is transparent when trailing args are present).

## v0.7.132-dev — 2026-06-06 — HOTFIX: host hard-crash on CW Belakor finale maps (nil random_director_list)

Host crash 2026-06-06 on `cemetery_belakor_path1` (GUID a6d00df6): `main_path_spawning_generator.lua:292: attempt to index local 'random_director_list' (a nil value)` during `conflict_director:ai_ready -> generate_spawns -> generate_great_cycles` at level load. Belakor finale maps (`*_belakor_path*`) carry adventure-style "random" zone directors but were NOT matched by `adventure_base_from_level_key`, so the existing `EnemyPackageLoader.setup_startup_enemies` fix (force `use_random_directors = true`) never fired for them — `_random_director_list` stayed nil and vanilla crashed when a zone picked "random".

**Fix:** extend the `use_random_directors = true` condition to also match the `_belakor_path` level-key family. That makes `_resolve_breed_packages` populate `_random_director_list`, which the spawn-zone generator reads safely. One-line condition add; native CW non-Belakor levels (already covered by the baked roaming_set path) are unaffected. Adjacent to Issue #68 (Belakor DLC map classification).



### What broke
v0.7.131 boot warning (log line 1261 of `console-2026-05-29-03.00.24-…`):
```
[MOD][ct_dev][WARNING] (hook_safe): Attempting to rehook active hook [open_chest].
```

v0.7.129's altar-reuse `mod:hook("DeusChestExtension", "open_chest", ...)` (line 684) sat in the same file as the pre-existing `mod:hook_safe("DeusChestExtension", "open_chest", ...)` (line 4742, bot-weapon-mirror). VMF silently drops the SECOND hook on the same `(Class, method)` from the same mod (`VMF_RECIPES.md` § 1, `memory/feedback_vmf_no_duplicate_hooks.md`). **The altar-reuse re-arm never actually ran** for v0.7.129 OR v0.7.130 — every "fix" we shipped was dead code, because VMF dropped my hook the moment the bot-mirror hook registered later in the file.

### Fix
Consolidate into a single `mod:hook_safe("DeusChestExtension", "open_chest", ...)` at the bot-mirror site. Altar-reuse re-arm logic runs FIRST in the body (so it fires regardless of bot-mirror reentrancy state), bot-mirror logic runs after.

The standalone `mod:hook("DeusChestExtension", "open_chest", ...)` at line 684 is gone, replaced by a banner comment naming the consolidation site (`_ct_consolidated_open_chest_hook` marker string at line ~4754) so the next session can grep for it.

### Regression test
New `/ct_regression_test` check `open_chest_hook_singleton` via the `CT_OPEN_CHEST_CONSOLIDATED_MARKER` source-pattern marker. If a future session re-introduces a duplicate hook, the consolidation banner gets broken or the marker gets removed — the test fails immediately on the next regression run, before the broken release ships.

### CLAUDE.md update
Added a top-of-file stop sign in the monorepo CLAUDE.md mandating a grep before any new `mod:hook(...)` line. Pre-flight: grep the target file for the method name in quotes, count matches, abort and consolidate if any exist. Reference: `VMF_RECIPES.md` § 1 + `memory/feedback_vmf_no_duplicate_hooks.md`.

### Burn history (so I stop)
This is the duplicate-hook-on-`open_chest` class. Same shape as v0.7.121 (`DeusRunController.setup_run` duplicate) and at least 3 cim hits before that. Per `feedback_vmf_no_duplicate_hooks`: the lint exists, the memory exists, the recipe exists — and I still introduced one. The CLAUDE.md hard stop should make it impossible to miss on the next session.

## v0.7.130-dev — 2026-05-29 — ct128 deferred init + CoT enemy multiplier + 3 regression tests

### Scope note
2026-05-29 user reports surfaced FOUR issues this session: (a) altar models on Holseher's map for several level names (#68), (b) `[ct128] DeusPowerUpTemplates not ready` log warning meaning the v0.7.128 parry-cooldown strip never actually ran, (c) `spawn_zone_baker.lua:563 nil zone` engine crash, (d) Devious Delvings (Verminious Dreams adventure mission `dlc_termite_2`) having no Khorne lighting. Of those:

- **(b) ct128 deferred init** — fixed here.
- **(c) spawn_zone_baker crash** — filed as Issue #67 against `enemy_tweaker` (silent pcall in `inject_special_packs` hook + 10× rat scaling overflowing zone density). Not a ct bug.
- **(d) Devious Delvings no Khorne lighting** — closed as Issue #66 (vdl-side gate to fix, not ct).
- **(a) altar models on map** — Issue #68 stays OPEN. My initial fix attempt classified Verminious Dreams DLC adventure missions as "native CW" content; that was wrong. User correctly called it out. Reverted. Investigation agent dispatched to find the actual root cause; will land in a follow-up release after I have ground truth on what's populating `IS_INJECTED_ADVENTURE_LEVEL` and why the user's session hit the SKIP path. No map-rewrite changes ship in this release.

Also adds Issue #64 (Chest of Trials enemy spawn multiplier) per user request, plus three regression tests for v0.7.128/.129/.130 fixes.

### Fix — ct128 parry-cooldown strip deferred to first boon roll
v0.7.128's `pcall(_ct128_strip_parry_cooldowns)` was invoked at file-load time, BEFORE Fatshark's morris settings module populated `DeusPowerUpTemplates`. Result: the strip skipped (log line 1308 of `console-2026-05-29-02.03.57-…log` says "DeusPowerUpTemplates not ready; parry-cooldown strip skipped") and the cooldowns on `static_blade` (parry → lightning bolt) and `boon_skulls_03` (orb on parry) remained at their vanilla durations. Items 5 + 6 from the 2026-05-28 batch never actually shipped working.

Fix: piggyback on the existing `DeusPowerUpUtils.generate_random_power_ups` hook (line 1557) — same pattern ct already uses for `sync_reckless_swings()` / `sync_bomb_cooldown()` / `sync_boon_movespeed()`. This hook fires on every boon roll, AFTER morris settings are loaded AND BEFORE any altar interaction (rolls happen at chest spawn, before player opens it). `_ct128_strip_parry_cooldowns` is idempotent — once `cooldown_buff` is nil, the next call's `for` loop is a no-op — so calling it on every roll is safe.

### Feature — Chest of Trials enemy spawn multiplier (Issue #64)
New numeric setting `cot_enemy_multiplier` (range 0.5–5.0, step 0.1, default 1.0) under the Shrines/Altars/Chests group. Scales the per-breed enemy count for cursed-chest trial waves only.

Hook: `TerrorEventMixer.init_functions.spawn_around_origin_unit` (vanilla terror_event_mixer.lua:96). Filter on `element.spawn_counter_category == "cursed_chest_enemies"` — that tag is set on every `cursed_chest_prototype` element (deus_generic_terror_events.lua:50+) and on nothing else, so mission-ambient hordes / patrols / specials are unaffected. Save+scale+restore the shared template's `difficulty_amount` (per-difficulty count table) and `amount` (scalar fallback) around the vanilla call; vanilla rebuilds the per-call `spawn_table` from the scaled values without persisting them on the element.

Host-broadcast via `effective_setting` so clients see the same wave size.

### Regression tests (3 new `_rt_register` entries)
Run via `/ct_regression_test`:

1. **`altar_reuse_hook_on_open_chest`** — source-pattern check via the `CT_ALTAR_REUSE_HOOK_MARKER` constant. Catches the v0.7.127 regression class (hook on `purchase` zeroing `_profile_index` between vanilla `_post_chest_unlock` and `_equip_weapon`) before it ships again. Marker value: `altar_reuse:open_chest_post_hook_v0.7.129`.
2. **`parry_cooldowns_stripped_post_load`** — runtime check that after `DeusPowerUpTemplates` is loaded AND the deferred init has fired (any boon roll triggers it), `DeusPowerUpTemplates.power_ups.{static_blade,boon_skulls_03}.buff_template.buffs[*].cooldown_buff` is nil. From the keep BEFORE any boon roll, returns nil (PASS / expected pre-roll) rather than failing.
3. **`cot_enemy_multiplier_cursed_chest_only`** — source-pattern check via the `CT_COT_ENEMY_MULT_MARKER` constant. Catches a regression where the filter is broadened beyond cursed-chest spawns (which would silently scale every terror event spawn — mission hordes, ambient rats, the lot).

### Reverted in this release
The `NATIVE_CW_DLC_BASES` table + `native_cw_dlc_base_from_level_key` helper + map-UI rewrite fallback I drafted earlier in this session are removed. They were based on a faulty classification (Verminious Dreams / Drachenfels / Karak Azgaraz DLC missions are adventure-mode content, NOT native CW content) and the user correctly told me to first gather context before shipping. Issue #68 stays open with a follow-up investigation note.

### Files touched
- `chaos_wastes_tweaker_dev.lua` — bump MOD_VERSION, add 2 marker constants, defer `_ct128_strip_parry_cooldowns` to `generate_random_power_ups` hook, add `TerrorEventMixer.init_functions.spawn_around_origin_unit` hook for CoT multiplier, add 3 `_rt_register` entries.
- `chaos_wastes_tweaker_dev_data.lua` — add `cot_enemy_multiplier` numeric widget.
- `chaos_wastes_tweaker_dev_localization.lua` — add label + tooltip strings.

## v0.7.129-dev — 2026-05-29 — Fix altar-reuse SPProfiles[0] crash

### Crash report
`scripts/unit_extensions/pickups/deus_chest_extension.lua:613: attempt to index local 'profile' (a nil value)` on weapon-swap altar use. Captured in `Downloads/console-2026-05-29-01.46.45-ce98243c-…log`. Crash dump matches. Reported by user 2026-05-29.

### Root cause
v0.7.127-dev introduced an altar-reuse feature with a `mod:hook("DeusChestExtension", "purchase", ...)`. The hook ran the vanilla `purchase()` then zeroed `_profile_index`, `_career_index`, `_animation_state`, and `_is_purchased` to force vanilla `update()` to re-enter its setup branch on the next tick.

What I missed: vanilla `DeusChestExtension.open_chest` (deus_chest_extension.lua:539) calls in order:
1. `_post_chest_unlock(stored_purchase)` → which calls `self:purchase()` ← my hook fired here
2. `self:_equip_weapon(run_controller, stored_purchase)` (line 576) ← reads `self._profile_index`

So my hook zeroed `_profile_index` BETWEEN those two calls. The subsequent `_equip_weapon` did `SPProfiles[self._profile_index]` → `SPProfiles[0] = nil` → crash on `profile.careers[career_index]`.

This affected weapon-swap altars (`swap_melee`, `swap_ranged`) and weapon-upgrade altars — anywhere `_equip_weapon` runs in the same open-chest call chain. Power-up (boon) altars don't call `_equip_weapon` (line 545-552 branch ends after `_post_chest_unlock`) and were unaffected — explains why the user's earlier v0.7.127 test session didn't crash if they only used boon shrines.

### Fix
Move the re-arm logic from the `purchase` hook to a new `open_chest` POST-vanilla hook. By the time `func(self)` returns in `open_chest`, BOTH `purchase()` AND `_equip_weapon()` have run — the chest's profile_index is no longer needed for this open. Re-arm then proceeds exactly as before (zero profile/career, reset _is_purchased, reset _animation_state), but now the timing is clean.

The cost-multiplier hook on `get_purchase_cost` and the seed-mixing hooks on `_generate_stored_power_up` / `_generate_stored_weapon` are unchanged — they're independent of the re-arm timing.

### Why this didn't show up in v0.7.127's local test
Default `altar_reuse_count_*` = 1 (vanilla) for all 4 altar types. The hook's re-arm branch (`if uses >= max_uses then return`) bails immediately for `max_uses = 1`, never zeroing the profile index. The crash only triggers when a user actually CHANGES a count setting to > 1 AND uses a weapon-family altar (swap_melee, swap_ranged, upgrade). This is a regression-test gap: I should add a no-default-config integration check that explicitly raises one count > 1 and exercises a weapon-swap altar.

## v0.7.128-dev — 2026-05-28 — Parry-proc boon no-cooldown + per-career burn-on-ability VFX (4 of 6 from request)

### Scope note — partial drop
2026-05-28 user request was a 6-item batch: (1) Necromancer career boon +1 skeleton per active boon, (2) Handmaiden career boon dash-leaves-blue-fire-trail with BW sounds, (3) elf burn-on-career-ability uses blue Moonfire DoT, (4) Necromancer same uses balefire DoT, (5) `static_blade` parry-bolt no cooldown, (6) `boon_skulls_03` parry-orb no cooldown. **Items 3, 4, 5, 6 ship in this release; items 1 and 2 deferred to a follow-up.** The reworks (3–6) reuse the well-tested Myrmidia's Wildfire DoT-template-swap pattern (chaos_wastes_tweaker_dev.lua:7962+) and the cooldown-strip is a single field nullification at boot — both ship-safe in one drop. Items 1 + 2 are NEW boons, which require new template registration + career-spawn / lunge-state changes; they deserve their own pass to avoid a half-built feature.

### Items 5 + 6 — strip cooldown on parry-proc boons
`static_blade` (deus_power_up_settings.lua:4205, "lightning bolt on parry" — fx/cw_chain_lightning + boon_career_ability_lightning_aoe damage) and `boon_skulls_03` (deus_power_up_settings.lua:3140, drakegun explosion on parry) both ship a `cooldown_buff` field that gates the `on_timed_block` proc to once per cooldown duration via vanilla buff_extension cooldown check (buff_extension.lua:1378-1390). New `_ct128_strip_parry_cooldowns()` nulls that field at mod boot — every successful timed block now fires the proc with no cooldown. Single `pcall` invocation, no hooks, idempotent on hot-reload.

### Items 3 + 4 — per-career burn VFX on `boon_careerskill_02` (burn-on-career-ability)
Direct application of the Myrmidia's Wildfire spread-by-source-status pattern, but selecting by OWNER's career instead of TARGET's burn status (the burn originates from the player's career ability press, not from a kill cascade). Hook `ProcFunctions.career_ability_apply_dot_to_adjecent_enemies` (morris_buff_settings.lua:3683); pre-seed `buff.cached_custom_dot.dot_template_name` with:

- Elf careers (`we_waywatcher` / `we_maidenguard` / `we_shade` / `we_thornsister`) → `we_deus_01_dot_fast` (blue Moonfire DoT — same template the existing Wildfire hook uses for elven_magic spreads, verified working as of v0.7.73).
- `bw_necromancer` → balefire variant (resolved lazily from `BalefireBurnDotLookup` per the same pattern as the Wildfire hook's necromancer branch).
- Every other career → vanilla orange (`boon_career_ability_burning_aoe`) — no change.

### Items 1 + 2 — deferred to follow-up
- Item 1 (Necromancer +1 skeleton per active boon): vanilla cap is hardcoded as the length of `PassiveAbilityNecromancerCharges._army_definition` (passive_ability_necromancer_charges.lua:101-106), set during `_on_talents_changed`. No `stat_buff` for "max skeletons" exists. Implementation needs a hook on `_on_talents_changed` to extend `_army_definition` by the current boon count, plus a re-trigger when boons are gained mid-mission. Combined with new career-locked boon registration (Task #8 still pending), this is a single focused session of work.
- Item 2 (Handmaiden firewalk dash with BW sounds): no vanilla "firewalk" mechanic exists on Battle Wizard's Tranquility — the closest is the Lingering Flames talent path which lives elsewhere in the codebase. Implementation would need (a) new boon registration, (b) a periodic burn-AOE-spawner hooked into `CareerAbilityWEMaidenGuard._run_ability` and the lunge state's update tick, (c) BW wwise sound event discovery (`play_bw_scholar_*flame*` or equivalent). Each of (a)/(b)/(c) is its own research thread.

Both will land in a follow-up release. Filing as tasks #34 and #35 for visibility (created alongside this CHANGELOG entry).

## v0.7.127-dev — 2026-05-28 — Altar reuse + cost multiplier per altar type

### Why
User: *"add an option to chaos wastes tweaker where players can choose how many times specific altars can be visited under the altars (boon, weapon swap, ranged swap, upgrade weapon), for each one, have a choice for how many times you can buy from it; this gives players a chance to reroll if they get something that breaks their build."*

### Added — 8 new settings (host-broadcast via `effective_setting`)
Under the new `altar_reuse_group` (Settings → "Altar Reuse (reroll bad picks)"):

| Setting | Range | Default | What it does |
|---|---|---|---|
| `altar_reuse_count_power_up`     | 1–20  | 1   | Boon shrine: how many times the same altar can be used per visit |
| `altar_reuse_cost_mult_power_up` | 0.1–10.0 | 1.0 | Boon shrine: coin-cost multiplier applied per subsequent use |
| `altar_reuse_count_swap_melee`     | 1–20  | 1   | Melee swap altar: same |
| `altar_reuse_cost_mult_swap_melee` | 0.1–10.0 | 1.0 | Melee swap altar: same |
| `altar_reuse_count_swap_ranged`     | 1–20  | 1   | Ranged swap altar |
| `altar_reuse_cost_mult_swap_ranged` | 0.1–10.0 | 1.0 | Ranged swap altar |
| `altar_reuse_count_upgrade`     | 1–20  | 1   | Weapon upgrade altar |
| `altar_reuse_cost_mult_upgrade` | 0.1–10.0 | 1.0 | Weapon upgrade altar |

Default `count=1` + `mult=1.0` = vanilla single-use behavior. No silent change for existing users.

### Cost curve — geometric, NOT linear
`cost(N-th use) = base_cost * (mult ^ (N - 1))` rounded up.

- `mult=1.0`: every use costs vanilla (1×, 1×, 1×, …).
- `mult=2.0`: 1×, 2×, 4×, 8×, 16×.
- `mult=0.5`: 1×, 0.5×, 0.25×, 0.125×.
- `mult=10`: 1×, 10×, 100×, … (steep — player picks).
- `mult=0.1`: 1×, 0.1×, 0.01×, … (basically free rerolls).

Geometric (vs. linear `base + (n-1)*delta`) was chosen because it stays well-defined for `mult < 1` (discounts) and gives the host a single dial that smoothly covers both surcharge and discount. Linear breaks at `mult < 1` (would yield negative cost beyond the 1/(1-mult) th use).

### Mechanism — 3 narrow hooks on `DeusChestExtension`

1. **`get_purchase_cost`** wrap → scale `base * mult^uses_so_far` before vanilla returns it. Clients see the same cost as the host because `effective_setting` reads the host-broadcast value.

2. **`purchase`** post-call → increment per-unit use count; if `uses < max_uses`, restore:
   - `_is_purchased = false`
   - `_animation_state = nil`
   - `_profile_index = 0`, `_career_index = 0`

   Clearing `_profile_index` is the key trick: vanilla `DeusChestExtension.update()` (deus_chest_extension.lua:134) gates its full setup branch on `profile_index ~= self._profile_index`. By zeroing it, the next tick re-enters the setup branch, which re-rolls offerings AND re-fires `Unit.flow_event(self.unit, "lua_update_<rarity>")` to visually re-arm the altar. No copy-paste of the vanilla setup block needed.

3. **`_generate_stored_power_up` / `_generate_stored_weapon`** wrap → mix the use count into the seed input so each re-roll yields a DIFFERENT power-up or weapon. Power-up version mixes the seed via `HashUtils.fnv32_hash(seed .. "_ct_reuse_" .. uses)`. Weapon version offsets the `go_id` parameter by `uses * 1000003` (a prime salt); the offset flows through the function's internal `fnv32_hash(profile, career, weapon_pickup_seed, go_id, 1)` and yields a fresh `weapon_seed` without copy-pasting the whole 20-line setup body.

### Per-run state reset
`_altar_uses_by_go_id` is wiped at the top of the existing `DeusRunController.setup_run` hook. Two reasons:
- Stingray's `unit_storage` may cycle the same network ids across runs; a stale entry would re-arm a brand-new chest with a non-zero use count and immediately apply the cost multiplier.
- Cheap (one table assignment per run).

### Network model
- Server-only state: `_altar_uses_by_go_id` is written only on the server's `purchase` hook. Clients see the visual re-arm via vanilla's standard sync path (`rpc_deus_chest_looted` on line 315 + the `_is_purchased` flip read at line 174). No new RPC.
- Settings: all via `effective_setting`, host's values broadcast to all peers via VMF.

### Known limitations / regression checklist
- **Boon shrine `_purchased_boons`**: `DeusShopView` (line 545) locks individual boons in the open shop session via `_purchased_boons[power_up.name]`. When the altar re-arms and the shop re-opens, vanilla's view init (line 400) does `_purchased_boons = _purchased_boons or {}` — the `or` keeps prior state across closes. If a player reuses the same boon altar twice in one session and the shop view instance is reused, previously-purchased boons may show locked. Test in-game: if confirmed, add a hook to clear `_purchased_boons` on shop re-open.
- **Weapon swap altar appears to "give back the old weapon"**: vanilla `_generate_stored_weapon` calls `deus_backend:grant_deus_weapon(new_weapon)` BEFORE returning. The previous weapon is still granted in the backend. This is OK — the player can equip it back if the new roll is worse, but it may visually clutter the deus-weapon inventory. Worth verifying behavior in-game.
- **Upgrade altar**: vanilla `_get_wielded_weapon` may need to re-roll the upgrade target each use. Untested. If a player uses the same upgrade altar twice with the same wielded weapon, behavior should be identical to two separate altars (re-rolls the upgraded variant). Verify.

### Documentation
- Repo `CLAUDE.md` Mod Directory: no change (ct_dev already documented as dev stream).
- `_DEVELOPMENT.md` will get a "boss-fight / altar mechanics" subsection in a follow-up if the feature ships beyond MVP.

## v0.7.126-dev — 2026-05-27 — Adventure-mode baseline pickup capture (Issue #58 follow-up)

### Why
User asked: *"We probably need a diagnostic for the horn of magnus mission that activates during campaign play so you get all the pickup location and data for that map when it's working properly."* Smart move — capture the "working" baseline on vanilla Adventure-mode Magnus, then diff against the broken CW `magnus_belakor_path1`. Whichever spawner categories the adventure mission has that the CW variant lacks is the spawn-debt root cause.

### Added — `_dump_pickup_spawners_verbose` helper
Per-spawner-unit walk for every placed spawner across `primary` / `secondary` / `specified` / `guaranteed` lists. For each unit logs:
- World position `(x, y, z)`
- Every truthy `Unit.get_data(unit, <key>)` across our 11 known pickup categories PLUS `tome` / `grimoire` / `loot_die` / `painting_scrap` (the non-pickup tags that ct's conversion paths key off).

Cap: 50 units per list (typical adventure mission has 30–80; cap keeps the log readable while still giving 50 worked examples per category).

### Wired into `PickupSystem.populate_pickups` post-func
Fires on EVERY level when `enable_debug_logging` is on — vanilla Adventure mode included. This is the best moment in the load cycle: vanilla populate has finished assigning units to spawner lists + categorizing them, and ct's `_spawn_guaranteed_pickup` conversion hook hasn't fired yet.

### How to use
1. Enable `enable_debug_logging` in ct_dev settings.
2. Start vanilla Adventure mode → "Horn of Magnus" (level `magnus`).
3. Quit out to keep after spawning completes (don't need to play through).
4. Send the log — the `[ct_dbg][pickup_units:post_populate]` block will show every spawner's position + category tags.
5. Then start a CW run that rolls `magnus_belakor_path1`. Same dump will fire there.
6. Diff the two dumps → which categories the broken CW variant is missing.

## v0.7.125-dev — 2026-05-27 — Pickup-system + Belakor-altar diagnostics (Issues #58, #60)

### Why
User reported THREE bugs from the 2026-05-27 00:04 client + 00:08 host session:
1. **#58 — Horn of Magnus (`magnus_belakor_path1`) has no pickups, chests, or altars.** Host log line 18347-18359 shows `[PickupSystem] CURRENT LEVEL HAS NO PICKUP DATA FOR CURRENT DIFFICULTY: harder, USING SETTINGS FOR EASY` + spawn-debt warnings for every category. Both host and client saw zero pickups — this is host-side level data (or geometry) gap, not a sync failure.
2. **#59 — Drachenfels boss BT crash** (filed against `general_tweaker`, NOT this mod) on `dlc_castle_slaanesh_path1` `castle_chaos_boss` event. Root cause: `gt`'s `_gt_cs_is_in_level("dlc_castle")` is exact-match only and misses CW variants. **Not a ct bug, no ct change in this release.**
3. **#60 — Belakor shadow locus missing on Karak Azgaraz CW Belakor mission (`dlc_dwarf_beacons_belakor_path1`)** — user saw 5 chests of trials + 0 altar, with host's `cursed_chest_count` setting of 3. Expected pattern: `chest, chest, chest, altar, empty`.

This release adds **diagnostic instrumentation** for both ct-side bugs (#58 + #60). Concrete fixes pending next session's log data — current code doesn't have enough signal to root-cause from the existing logs alone.

### Added — `_dump_pickup_system_state` helper + mission-start auto-dump
- New file-scope helper `_dump_pickup_system_state(prefix, also_echo)`. Walks two data sources side-by-side:
  - **`LevelSettings[level_key].pickup_settings`** — per-difficulty `primary` table contents (counts for every known category).
  - **Live `PickupSystem` lists** — `primary_pickup_spawners`, `secondary_pickup_spawners`, `specified_pickup_spawners`, `guaranteed_pickup_spawners`, `triggered_pickup_spawners`. Counted by `Unit.get_data(unit, category)` for each of 11 known pickup categories (deus_weapon_chest / deus_cursed_chest / deus_potions / deus_soft_currency / ammo / healing / grenades / level_events / explosive_barrel / frag_grenade / fire_grenade).
- Single line emitted per source. When current difficulty has no entry in `pickup_settings`, an explicit `NO MATCH for current difficulty='harder'` line surfaces the Magnus root signal directly.
- Called from `GameModeDeus.local_player_game_starts` on every mission entry when `enable_debug_logging` is on. Log-only (no chat echo) to avoid spamming during play.

### Replaced — `/dump_spawners` command
- Old body did a coarse total count + a partial `pickup_settings` walk that missed several categories (potions, soft_currency, level_events, grenades). Replaced with a single `pcall` delegating to `_dump_pickup_system_state`, so the on-demand command produces identical output to the automatic dump.

### Added — per-pedestal conversion trace in `_spawn_guaranteed_pickup`
- For Issue #60. Every tome/grim pedestal hit now emits:
  - `[pedestal] kind=<tome|grim> cap_raw=<X> cap=<Y> count=<Z>` — entry state for every invocation (max 5 per mission).
  - `[pedestal] -> chest_of_trials count_now=<N> (spawned=<bool>)` — per chest conversion.
  - `[pedestal] altar_gate force_belakor=<bool> current_is_belakor=<bool> have_deus_02=<bool> already_spawned=<bool> -> attempt=<bool>` — every altar decision, every gate.
  - `[pedestal] -> belakor_altar spawn=<bool> (vetoed=<bool>)` — per altar spawn attempt.
  - `[pedestal] -> empty (cap reached, altar not applicable)` — terminal branch.
- All gated on `enable_debug_logging` via `_dbg`. Zero overhead when debug off (fast-path bail in `_dbg`).

### Next steps
- Repro Issue #58 with v0.7.125-dev + debug on. The mission-start dump on the Magnus mission will show whether `pickup_settings[harder]` is nil (data table issue → ct injects fallback from vanilla `magnus_path1`) or whether the level just has no chest-tagged spawner units (geometry issue → can't fix from Lua).
- Repro Issue #60 with same. The pedestal trace will show whether `effective_setting("cursed_chest_count")` is returning the wrong cap, whether `_chest_conversions_this_level` is getting reset mid-mission, or whether the altar gate's `_current_node_is_belakor()` is returning false despite the curse field being correct.

### Note — no fix shipped yet
This release is diagnostic-only. The user explicitly asked for "fix and add tests for every bug fixed." For both Issue #58 and #60, the existing log data is insufficient to know what to fix — the visible symptoms have multiple plausible root causes. Shipping a guess would likely paper over the real bug. Next session's log with the new instrumentation will give a precise diagnosis.

## v0.7.125-dev — 2026-05-26 — Fork point (initial commit)

- **FORK POINT**: this directory (`chaos_wastes_tweaker_dev/`) is the new friends-only dev stream for in-flight work. The parent `chaos_wastes_tweaker/` directory remains as the public stable stream (Workshop ID 3712929235). All future dev work happens here; releases get merged back into the parent.
- Mod_id renamed `ct` → `ct_dev`. Scripts dir renamed `chaos_wastes_tweaker` → `chaos_wastes_tweaker_dev`. itemV2.cfg: visibility friends_only, published_id cleared (assigned by Workshop on first upload).
- Chat commands `/ct_*` left as-is — would collide with stable if both subscribed by the same user.

## 0.7.124-dev (2026-05-26) — Per-mission curse+mutators diagnostic dump + sync level_seed in graph snapshot (citadel curse bug investigation)

### Why
User reported "the citadel of eternity mission curse doesn't match what host set it to. There are 2 final missions, and the curse should match on each, they should be what the host set it to." Plus directive: "Make sure when debug is on, it dumps the curse for the current mission if it has one, and mutators. Make sure the log on Holseher's map dumps which missions have which curse."

Scoured the 2026-05-26 04:14 client + 04:17 host logs for the journey_citadel run. Key findings:

1. **`force_belakor=true` correctly returned from `deus_journey_with_belakor` hook** on both peers (effective_setting fix from v0.7.122 is working).
2. **Per-node populate_graph is non-deterministic across peers despite the same run_seed.** Host's `node_6 = sig_citadel_tzeentch_path5` (level_seed -465327678); client's local populate produced `node_6 = sig_citadel_slaanesh_path5` (level_seed +X). The host snapshot fixes the displayed fields (level/curse/theme), but `level_seed` was NOT in `GRAPH_FIELD_MAP` — so any downstream consumer reading `node.level_seed` (e.g. per-mission terror_event scheduling, curse-halo iconography variant selection, intra-mission generation) diverges between peers.
3. **My v0.7.123 `apply_graph_snapshot` arena_belakor skip is firing correctly** — confirmed by `[ct_graph] apply skipped 1 node(s) for arena_belakor swap preservation (key=node_10)` in the client log, with the temple node showing `level=arena_belakor` in subsequent MAP_OPEN dumps. Issue #53 fix verified working in the wild.
4. **Curse field DID match host/client** on the MAP_OPEN dumps for node_6 (sig_citadel) and final (arena_citadel) — host: `curse_bolt_of_change`/`curse_khorne_champions`, client: same. So either: (a) the mismatch happens in a downstream display path that reads from a different source than `node.curse`, or (b) the user observed the mismatch on a different visual surface (loading screen curse icon? in-mission curse banner? boon-roll curse text?). Need more instrumentation to catch where the actual mismatch surfaces.

### Added — `level_seed` to `GRAPH_FIELD_MAP`
- New short-key `ls = level_seed`. Host snapshot now syncs level_seed alongside level/curse/theme/etc. Closes the determinism gap where same `run_seed` produces different per-node `level_seed` values on host vs client.
- Backward-compatible: v0.7.123 peers receiving from v0.7.124 just ignore the unknown short key; v0.7.124 peers receiving from v0.7.123 see `value == nil` in the iterator and skip (the existing `if value ~= nil then` already handles this). No CT_RPC_SCHEMA bump needed.

### Added — per-mission diagnostic on game start
- New `pcall`-wrapped block at the top of `mod:hook_safe("GameModeDeus", "local_player_game_starts", ...)`. Gated on `enable_debug_logging` via `_dbg`. Fires on BOTH peers when a CW mission starts. Single log line:
  ```
  [mission:start] is_server=<bool> current_node=<key> level=<X> base_level=<X> theme=<X>
                  curse=<X> level_seed=<N> god=<X> node_type=<X>
                  node_mutators={<list>} active_mutators={<list>}
  ```
  - `node_mutators` reads from `current_node.mutators` (the node's declared list)
  - `active_mutators` reads from `Managers.state.game_mode._mutator_handler:activated_mutators()` (what the engine actually activated for this mission)
  - Diff between the two on the same peer = our node data and the engine's mutator activation disagree. Diff between host and client on the same node = sync gap.

### Added — `mutators` + `level_seed` to MAP_OPEN per-node dump
- `[belakor:diag] MAP_OPEN node` lines now include `level_seed=<N> mutators={<list>}`. Both peers' map opens will show the per-node mutator list so any divergence (e.g., host's node_6 has `{curse_bolt_of_change}` but client's node_6 has `{}` or a different curse) is visible at a glance.
- Same fields added to `/dump_journey` chat command's per-node dump.

### Verification path for next co-op session
Both peers turn on `enable_debug_logging`. Host enables `force_belakor`. Run journey_citadel together. At every map open AND on every mission start, both logs get full state dumps. After the session, grep `[mission:start]` + `[belakor:diag] MAP_OPEN node node_6` + `[belakor:diag] MAP_OPEN node final` on both logs and diff host vs client. If `node_mutators` and `active_mutators` diverge on the same peer, that's the bug class. If host/client diverge on the same node's mutators/curse/level_seed, that's a sync gap (and v0.7.124's level_seed sync should plug it).

### Notes
- The Issue #53 client-side Belakor temple fix from v0.7.123 verified in the wild (host log: `arena_belakor_node=node_10` set after locus destruction; client log: same; client's MAP_OPEN shows `level=arena_belakor` — i.e., the swap survives our apply now).
- Host's session ended cleanly at 05:39 with a `serialize_pipeline_library 7578 ms` stall (shader cache write timeout on exit). The accompanying crash dump is a benign shutdown timeout, not a Lua-side fault — no Lua errors precede it in the host log.

## 0.7.123-dev (2026-05-26) — Issue #53 REAL root cause: apply_graph_snapshot was reverting client's arena_belakor swap

### Why
v0.7.122 shipped the `effective_setting("force_belakor")` change plus aggressive `[belakor:diag]` instrumentation and called it Issue #53 done. The instrumentation in last night's session immediately exposed the actual bug — and it was in our own code, not the gated hook. Full grep of the client log captured every relevant signal:

- Client received `with_belakor=true` from host (`_setup_run is_server=false ... with_belakor=true`) ✓
- Client's local populate_graph ran correctly, including arena candidate flagging
- Client received host's graph snapshot via `ct_graph_snapshot_chunk` (7 chunks, 2659 bytes, 16 nodes)
- Client's `apply_graph_snapshot` overlaid host's resolved fields onto its local `_path_graph` — including for the eventual arena_belakor node

The breakage path (verified against vanilla source):
1. Once `_run_state:set_arena_belakor_node(node_X)` writes to SharedState (host-side, after Belakor altar destruction), the vanilla `DeusRunController._get_graph_data()` (deus_run_controller.lua:2035-2056) mutates `_path_graph[node_X]` in place: `level = "arena_belakor"`, `theme = "belakor"`, `base_level = "arena_belakor"`, `minor_modifier_group = {}`, etc. **This swap is what makes the map's prefix-to-unit mapper spawn `ARENA_NODE_UNIT` (the visible temple) for that node.**
2. Vanilla `DeusMapView.start()` (deus_map_view.lua:45) calls `_deus_run_controller:get_graph_data()` first — triggering the swap. Then passes the swapped graph_data to `DeusMapScene:on_enter(graph_data, ...)`.
3. ct's `DeusMapScene.on_enter` hook ran `apply_graph_snapshot(graph_data)` UNCONDITIONALLY when `_ct_host_graph_snapshot` was present — overlaying host's PRE-swap snapshot fields onto the just-swapped node. Net effect: `level="arena_belakor"` got reverted back to (e.g.) `level="bell_belakor_path1"`, `theme="belakor"` got reverted to whatever the host's snapshot had at populate time.
4. Vanilla `DeusMapScene.on_enter` then saw the un-swapped node and spawned `TRAVEL_NODE_UNIT` or `SHRINE_NODE_UNIT` instead of `ARENA_NODE_UNIT`. **No temple.**

Why this was client-only: `_ct_host_graph_snapshot` is populated by the `ct_graph_snapshot_chunk` RPC receiver — only on peers that RECEIVED the broadcast. Host itself never has a snapshot stored, so its `apply_graph_snapshot` call was a no-op (`if _ct_host_graph_snapshot then` short-circuit). Host's swap stayed intact → host saw temple.

Matches the user's exact Issue #53 report: "host sees temple, client does not."

### Changed
- `chaos_wastes_tweaker.lua:apply_graph_snapshot` — resolves `_run_state:get_arena_belakor_node()` at apply time. If non-nil, SKIPS that node when iterating the snapshot. All other nodes still get the host's resolved values (the original purpose of the snapshot — see comments at line ~770 for why we ship the graph at all). When at least one node is skipped, a `_dbg` line is emitted so the next test session can confirm the skip fired.

### Verification — what to look for next session
With `enable_debug_logging=true` on both peers:
- After altar destruction on a belakor mission: grep client log for `[ct_graph] apply skipped 1 node(s) for arena_belakor swap preservation (key=node_X)` on every subsequent map open.
- Grep client `[belakor:diag] MAP_OPEN _start` lines for `arena_belakor_node=node_X` non-nil. Confirms SharedState sync delivered.
- Grep client `[belakor:diag] MAP_OPEN node node_X level=arena_belakor` — confirms the swap survived our snapshot apply. Was previously `level=<original>` post-revert.
- Visual confirmation: client should see Belakor's Temple node on Holseher's map in the same spot host does, after destroying the first locus.

### Notes
- The v0.7.122 `effective_setting("force_belakor")` change is unchanged — it correctly catches the local-call paths (dialogue, telemetry, UI views that read `deus_journey_with_belakor` on every peer). That fix was right; it just wasn't the cause of the map-display gap. Both fixes ship together for completeness.
- The fix is purely additive (1 new lookup + 1 skip-comparison per apply). No behavior change when arena_belakor_node is nil (pre-altar-destruction map opens).

### Closes
- Issue #53 — ct: Belakor's Temple not visible on Holseher's map for CLIENT when host has 'always belakor' enabled (now actually fixed; v0.7.121-122 caught a contributing path but missed this one)

## 0.7.122-dev (2026-05-25) — Fold setup_run diagnostic into existing hook body (mod-lint duplicate-hook fix)

### Why
v0.7.121-dev added a separate `mod:hook_safe("DeusRunController", "setup_run", ...)` for the post-populate graph dump. mod-lint correctly flagged it as a duplicate registration on the same `(Class, method)` pair (the existing full `mod:hook("DeusRunController", "setup_run", ...)` at line ~1224 already registers this hook). VMF silently drops one of two registrations on the same pair, so the published bundle would have only one of the two diagnostics firing.

### Changed
- Removed the separate `mod:hook_safe("DeusRunController", "setup_run", ...)` block.
- Inlined the same diagnostic (arena-node count + arena_keys list) into the existing full hook body at line ~1224, immediately after the vanilla `func(self, unpack(args))` call returns. Same `[belakor:diag]` tag, same payload, wrapped in pcall.
- Block-comment left at the old location pointing readers to the new home.

### Verified
- `tools/mod-lint/lint-mod.ps1 chaos_wastes_tweaker` → no duplicate-hook errors.
- `publish-release.ps1` now passes its lint gate.

## 0.7.121-dev (2026-05-25) — Issue #53 Belakor temple client-side fix + Issue #54 Isha description fix + aggressive `[belakor:diag]` instrumentation

### Why
User-reported gaps (Issues #53, #54). Plus directive: "we should be aggressively dumping data to the log when I'm in game and on menus like Holseher's map or in-game that give you the info you need to fix these issues and make the mod work correctly." So both targeted fixes AND comprehensive instrumentation, gated on `enable_debug_logging` so it doesn't spam normal play.

### Fixed — Issue #53 (Belakor's Temple not visible on client map)
**Root cause:** the `BackendInterfaceDeusPlayFab.deus_journey_with_belakor` hook was gated `is_server and mod:get("force_belakor")` — meaning the host's override only fired on the host. But this method is ALSO called on client peers from non-RPC code paths — specifically `DeusMechanism.get_level_dialogue_context` (deus_mechanism.lua:1337) reads it locally on EVERY peer for dialogue/telemetry, and UI views that ask "does this journey have belakor?" do the same. Pre-v0.7.121 client peers fell through to vanilla which returns the journey's natural belakor-cycle position — wrong answer when host has force_belakor on.

**Fix:** replaced `is_server and mod:get("force_belakor")` with `effective_setting("force_belakor")`. `effective_setting` resolves to host-broadcast value on clients, local value on host — so BOTH peers' local calls now return true when host has the toggle on. The host's `game_round_ended` RPC path is unchanged (still works). The only client-local consumers of this method are display / dialogue / telemetry (none authoritative gameplay state), so mirroring the host is correct.

### Fixed — Issue #54 (Isha description shows wrong mode on client)
**Root cause:** the `Localize` hook's `blessing_of_isha_desc` branch read `effective_setting("tweak_miracle_of_isha_alternative")` — the legacy v0.7.65 dropdown key. v0.7.81 replaced that with a mutex checkbox cluster (`tweak_miracle_of_isha_aegis` / `_wounds`). On any user who migrated past v0.7.81, the legacy key is nil and the Localize hook fell through to vanilla — which displays the wounds-style text regardless of host's choice.

**Fix:** the Localize hook now reads `effective_setting("tweak_miracle_of_isha_aegis")` and `effective_setting("tweak_miracle_of_isha_wounds")` first, falling back to the legacy key for backward compat. Now description text matches the host's selected mode on both peers.

### Added — aggressive `[belakor:diag]` instrumentation (gated on `enable_debug_logging`)
All gated through the existing `_dbg(...)` helper (no-op when toggle is off; full dumps when on). Single grep tag `[belakor:diag]` covers the whole sequence from run-start to map-open.

1. **`DeusMechanism._setup_run` hook_safe** — dumps `run_id / run_seed / journey / dominant_god / with_belakor / mutator_count / boon_count / is_initial_setup / server_peer_id` on BOTH peers as the run starts. Confirms whether client receives `with_belakor=true` from host's RPC.
2. **`DeusRunController.setup_run` hook_safe** — after vanilla setup_run, dumps `_path_graph` arena-node count + arena_keys list per peer. Confirms whether client's `populate_graph` actually produced arena nodes (the temple candidates).
3. **`DeusRunController.unlock_arena_belakor` hook_safe** — fires only on host. Logs `current_node` + picked `arena_belakor_node`. SharedState should sync this value to clients (visible as `<rpc set server> arena_belakor_node = ...` in log).
4. **`DeusMapDecisionView._start` hook_safe** — fires on BOTH peers when the map view opens. Dumps `is_server / journey / current_node / belakor_enabled / arena_belakor_node / has_own_seen / graph_total / arena_in_graph / arena_keys / force_setting` plus per-node `key / level / prefix / theme / curse / god / node_type`. This is the single most diagnostic moment for Issue #53.
5. **`deus_journey_with_belakor` hook** — every call now logs the return value with peer role + setting state, so the dialogue/UI consumer paths are visible.

### Added — `/dump_journey` and `/dump_isha` chat commands
On-demand mid-game state dumps with the same `[belakor:diag]` / `[isha:diag]` tags. Workflow for next co-op session:
1. Both peers turn on `enable_debug_logging` in ct settings.
2. Host enables `force_belakor` (always belakor).
3. Both peers start a CW run together.
4. Between missions, both peers run `/dump_journey` AT THE SAME TIME from chat.
5. Both peers also run `/dump_isha` (with one host-side Isha mode toggled on).
6. Send both log files. Diff `[belakor:diag]` and `[isha:diag]` entries to confirm host/client divergence (if any) or confirm the fix.

### Fixed — `/verify_belakor` was reading non-existent `get_with_belakor`
Vanilla method is `get_belakor_enabled` (deus_run_state.lua:404). Pre-v0.7.121 the command printed `nil` for that field. Fixed to try both names; output label renamed `belakor_enabled` for clarity.

### Closes
- Issue #53 — ct: Belakor's Temple not visible on Holseher's map for CLIENT when host has 'always belakor' enabled
- Issue #54 — ct: Miracle of Isha tweak text shows 'unlimited wounds' when host selected Aegis

### Verification
Live in-game with `enable_debug_logging=true`:
- Both peers in CW with host's `force_belakor=true`: open map → grep `[belakor:diag] MAP_OPEN` → both should show non-nil `arena_belakor_node` + ≥1 arena node in graph.
- Host enables Aegis, client doesn't have any Isha toggle on. Client opens boon picker on a Miracle of Isha roll → tooltip should read "-25% damage taken" (Aegis text), not "unlimited wounds". Confirm via `/dump_isha` on client showing `eff_aegis=true desc_choice=aegis`.

## 0.7.120-dev (2026-05-25) — Fix Issues #39 (slider step-by-25) + #40 (mutex checkbox visual refresh) via two VMFOptionsView hooks

### Why
v0.7.110 filed both as GH Issues and left them for design call. User came back: "the coin increments do not work, find out what's necessary for a slider that increments, because clearly it's not working and neither is the multiple choice options." Re-read VMF source end-to-end and found two hookable callbacks that DO drive widget display in real time. Both fixes shipped.

### Changed
**`chaos_wastes_tweaker.lua`** — two new hooks at file scope, right after `mod.on_setting_changed`:

1. **`mod:hook("VMFOptionsView", "callback_draw_numeric_menu", ...)`** — pre-hook for the `starting_coins` widget. Quantizes `popup_menu_widget.content.internal_value` to multiples of `(25 / full_range)` BEFORE the original (line 4181 of `vmf_options_view.lua`) converts internal_value to a numeric value. Result: when user drags the slider, both the displayed number AND the slider fill visibly snap to multiples of 25 in real time. Gated on `mod_name == "ct" and setting_id == "starting_coins"` so other mods/widgets are unaffected. pcall-wrapped.

2. **`mod:hook("VMFOptionsView", "callback_setting_changed", ...)`** — post-hook fires after VMF's original (which persists the new value and fires `mod.on_setting_changed` — where our mutex enforcer runs and updates sibling values via `mod:set`). Calls `self:update_picked_option_for_settings_list_widgets()`, which walks every widget and re-reads `mod:get(setting_id)` to sync `is_checkbox_checked` / `current_value` / `current_value_text`. Result: when user checks the Aegis variant while Wounds is already checked, Wounds visually unchecks in the same frame. Same fix applies to any future mutex cluster on ct (e.g. isha_choice). Gated on `mod_name == "ct"`; pcall-wrapped.

### Verification (against upstream `vmf/scripts/mods/vmf/modules/ui/options/vmf_options_view.lua`)
- Slider held_function: line 2486-2492 (writes continuous `internal_value`)
- Slider numeric conversion: line 4181-4182 (reads `internal_value`, rounds to `decimals_number`)
- Slider fill render: line 4189-4199 (slider visible position derives from same value)
- Numeric widget popup creation: line 2839 (`popup_menu_widget`)
- `update_picked_option_for_settings_list_widgets`: line 4332-4445 (per-widget sync from `mod:get`)
- View open call site: line 4787 (proves it's only called on `on_enter`, hence the bug)

### Notes
- Existing snap-on-save in `on_setting_changed` is kept as belt-and-suspenders: even if the slider hook ever fails (VMF refactor, etc.), the persisted value still snaps to 25 on save. Belt-and-suspenders is justified here because the two paths fail independently — see `feedback_redundant_safeguards_ok.md`.
- Mutex enforcer in `chaos_wastes_tweaker_mutex.lua` is unchanged — the visual refresh is now driven by the new post-hook, not the enforcer itself, keeping the mutex framework generic for future clusters.
- No CHANGELOG / labels promise behavior the widget doesn't actually do — the `starting_coins` label remains plain `"Starting Coins"` and the slider's visible behavior now matches the persisted-snap-to-25.

### Closes
- Issue #39 — ct: starting_coins VMF slider steps by 1, not 25
- Issue #40 — ct: Miracle of Isha mutex checkboxes don't visually deselect siblings

### Tests
Live in-game (eye-on-outcome verification, per project rule): drag the starting_coins slider, confirm visible snap to 25. Open Reworks > Boons, check Miracle of Isha Wounds while Aegis is checked, confirm Aegis visually unchecks in the same frame.

## 0.7.119-dev (2026-05-25) -- Restore dev/alpha/beta load banner (PROJECT_STANDARDS § 3.6 update)

### Why
User feedback 2026-05-25 EOD: earlier today's chat-spam cleanup pulled the `mod:echo("<Name> v" .. MOD_VERSION)` startup line from every mod. That's correct for stable (>=1.0.0) builds but hides the active version for in-flight dev/alpha/beta work. PROJECT_STANDARDS § 3.6 amended: dev/alpha/beta/0.x versions MUST echo `[<mod_id>] v<version> loaded` at module load; stable versions stay silent.

### Changed
- `chaos_wastes_tweaker.lua` -- added a track-detector `if` after the applied-marker line: matches `-dev$` / `-alpha$` / `-beta$` / `-rc%d*$` / `^0%.`. When any branch fires, `mod:echo("[ct] v<MOD_VERSION> loaded")` runs once.

## 0.7.118-dev (2026-05-25) -- Demote starting-boon grant chat echo to log-only (chat-echo policy: PROJECT_STANDARDS § 3.6)

### Why
`chaos_wastes_tweaker.lua:3690` (inside the `DeusRunController._add_initial_power_ups` hook_safe body) called `mod:echo("Granted %d starting boon(s) to %s (%s)%s", ...)`. The grant is engine-driven -- it fires on every player-add at run start and again on every late-joiner / bot add -- not a user-typed operational toggle. Per PROJECT_STANDARDS § 3.6 ("never echo unless explicit user-typed operational toggle"), this is chat spam. Previous audit comment at line 3643-3644 flagged it as "POTENTIAL BUG (LOW)" with "Once per run would be cleaner" -- the new chat-echo policy makes the call: log-only, not chat.

### Changed
- `chaos_wastes_tweaker.lua` -- starting-boon grant log line at `_add_initial_power_ups` hook_safe body demoted from `mod:echo("Granted %d starting boon(s) to %s (%s)%s", ...)` to `mod:info("[ct:starting_boons] granted %d to %s (%s)%s", ...)`. Same fields, prefixed `[ct:starting_boons]` so the log is greppable. The audit comment at line 3643 is rewritten to document the new behavior (log-only, per § 3.6) instead of flagging it as a known bug.

### Notes
- Per-run-vs-per-player-add frequency is moot now that the line is log-only; if a future maintainer wants to dedupe to per-run, gate on the run_id at the call site -- but it's no longer chat-visible so the urgency is gone.

### Build
VMBLauncher.exe build chaos_wastes_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.7.117-dev (2026-05-25) -- Remove startup banner echo + tidy on_setting_changed (chat-echo policy: PROJECT_STANDARDS § 3.6)

### Why
User feedback 2026-05-25: `"on enabling debug logging, I'm getting needless echos to the chat that it's enabled"` and `"on startup before enabling debug logging, I'm getting things echo'd to the chat for CWV"`. Audit found 13 mods with redundant `mod:echo("<Name> v" .. MOD_VERSION)` lines at module load and one mod with `mod:echo("Setting changed: " .. setting_id)` in on_setting_changed (career_tweaker -- the source of the Debug Logging chat echo).

Policy decision codified in PROJECT_STANDARDS.md § 3.6 "Chat-echo policy":
- **NEVER** at module load -- the applied marker `[ct] enabled v<X> settings_fp=<hash>` line is the canonical version surface, lives in the log, never spams chat.
- **NEVER** in on_setting_changed for routine settings -- use `_dbg` (gated on enable_debug_logging) if a diagnostic trace is needed.
- **OK** in on_setting_changed only for explicit high-impact toggles (bt master toggle, gt AI toggle).
- **OK** in user-typed chat command bodies (`/<feature>_regression_test`, `/verify_*`, etc.).

### Changed
- chaos_wastes_tweaker.lua -- removed the load-time `mod:echo("chaos_wastes_tweaker v" .. MOD_VERSION)` banner. The applied marker line (`mod:info("[ct] enabled v%s settings_fp=%s", ...)`) further down already surfaces the version + settings hash in the log. `mod:info("chaos_wastes_tweaker v%s loaded", MOD_VERSION)` retained for log-side visibility.
- itemV2.cfg -- updated the description's "Mention the mod version" bug-report instruction. Previous text told users to find the version "at the top of the in-game chat when you load into the keep" -- now points them at the console log (search for the `enabled v` line) or `/<mod>_regression_test`.

### Build
VMBLauncher.exe build chaos_wastes_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.7.116-dev (2026-05-25) -- Fix unescaped %APPDATA% in Debug Logging tooltip + add localization_format_safe runtime test

### Why
User report: "invalid string format on mouseover for Debug Logging" -- the canonical Universal Debug Logging tooltip (PROJECT_STANDARDS.md S 3.6) shipped with a literal %APPDATA%. Lua's string.format reads %A as a format directive and raises invalid option '%A' to 'format', surfacing as a red error tooltip in the VMF settings UI. All 16 active mods were affected (every mod ships the same canonical tooltip text).

### Changed
- chaos_wastes_tweaker_localization.lua -- escaped literal % in enable_debug_logging_tooltip so VMF's tooltip render path sees %%APPDATA%% (renders as %APPDATA% to the player). Same wording, just escaped.
- chaos_wastes_tweaker.lua -- added _rt_register("localization_format_safe", ...) runtime check. dofiles the loc table and pcall(string.format, value) on every entry; surfaces any unescaped % via /<mod_id>_regression_test. Catches the bug class even when the static check (qa/check_localization.ps1) is skipped.

### Notes
Repo-wide multi-layer defense landing across all 16 mods in this sweep:

1. Layer 1 -- 16 mods' loc strings fixed.
2. Layer 2 -- qa/check_localization.ps1 extended to parse loc.<key> = { en = "..." } assignment style (chaos_wastes_tweaker's pattern -- previously slipped detection).
3. Layer 3 -- _rt_register("localization_format_safe", ...) runtime check in every mod.
4. Layer 4 -- tools/vmb-launcher/CLAUDE.md doctrine update: "Run qa/check_localization.ps1 before declaring any localization edit complete."
5. Layer 5 -- documentation: LOCALIZATION_STANDARD.md S 1 "Recurring offender" worked example, docs/BUG_CLASSES.md S 16 new entry, PROJECT_STANDARDS.md S 3.6 canonical tooltip text now uses %%APPDATA%%.

Static check (qa/check_localization.ps1) reports 0 errors post-fix (down from 15 detected + 1 hidden in chaos_wastes_tweaker).

### Build
VMBLauncher.exe build chaos_wastes_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.7.115-dev (2026-05-25) — Applied marker (universal — PROJECT_STANDARDS.md § 3.6)

### Why
Every mod now prints a single `mod:info("[ct] enabled v<X.Y.Z> settings_fp=<8-hex>")` line at load — self-documenting console_logs. Walks the data widget tree, FNV-1a-32 hashes setting=value pairs. ALWAYS fires (not gated on debug_logging).

### Changed
- `chaos_wastes_tweaker.lua` — added file-local `_settings_fingerprint()` helper + `mod:info("[ct] enabled ...")` applied-marker line right after the `_dbg_alert` helper.
- `itemV2.cfg` — bumped to v0.7.115-dev.

## 0.7.114-dev (2026-05-25) — Issue #27 pilot: explicit RPC schema_version + drop-on-mismatch

### Why

Cross-peer RPCs between host and client today have implicit schema — host and client peers MUST agree on the positional payload structure of every `mod:network_send` / `mod:network_register` pair, or the receiver silently mis-parses the message and corrupts state. With aggressive dev-iteration (multiple builds per day), the chance of a friend running a stale Workshop bundle while the host runs latest dev is high. Closes GitHub Issue #27 (the Wave-2 RPC-schema hardening tracked alongside the bt net_replay ring buffer from Issue #28).

ct is the pilot for the pattern because it ships the densest RPC traffic in this repo (3 host→client/peer→peer chunked broadcasts: settings sync, graph snapshot, peer manifest). If the pattern works here, follow-up Issues will propagate it to cosmetics_tweaker, lobby_tweaker, enemy_tweaker, crafting_in_modded, and general_tweaker.

### Design

Per-mod `CT_RPC_SCHEMA = 1` constant declared near `MOD_VERSION`. Prepended as the FIRST positional argument of every `mod:network_send` ct emits, and validated as the FIRST argument of every `mod:network_register` callback. On mismatch the receiver:
1. Calls `_dbg_alert("[rpc:schema] <channel> mismatch from peer=<peer>: peer sent v<n>, we expect v<our>. Dropping.")` — logs to file AND surfaces in chat (when debug logging is on).
2. Returns early. No state mutation, no crash.

Bump `CT_RPC_SCHEMA` ONLY when changing RPC payload shape (add/remove/reorder fields). Non-shape changes (logging tweaks, new hooks that don't touch the wire) leave the constant alone.

Graceful-degradation paths for cross-version peers are spelled out in the `CT_RPC_SCHEMA` comment block near `MOD_VERSION` — both directions (new peer to old peer, old peer to new peer) end in a clean drop, not a corruption.

### Changed

- `chaos_wastes_tweaker.lua`:
  - **`CT_RPC_SCHEMA = 1`** added near MOD_VERSION with full comment block (when to bump, graceful-degradation behavior, VMF_RECIPES.md § 10 cross-ref).
  - **`ct_sync_host_settings_chunk`** sender (host's `DeusRunController.setup_run` hook, ~L1178) + receiver (~L630): `CT_RPC_SCHEMA` prepended; receiver gates with `_dbg_alert` mismatch drop.
  - **`ct_graph_snapshot_chunk`** sender (host's `broadcast_graph_snapshot`, ~L839) + receiver (~L771): same wiring.
  - **`ct_peer_manifest_chunk`** sender (`_broadcast_local_manifest`, ~L997) + receiver (~L1002): same wiring.
  - **`_rt_register("ct_rpc_schema_present", ...)`** regression check asserts `CT_RPC_SCHEMA` exists as a number ≥ 1 so a future refactor can't silently drop the constant.
- `itemV2.cfg` — bumped to v0.7.114-dev.
- `VMF_RECIPES.md § 10` — new section "RPC schema versioning" covering the design + when to bump + the migration path for adding new RPCs.
- `PROJECT_STANDARDS.md` — cross-ref under § 3 (logging) pointing at the new recipe section.

### Migration path for follow-up mods

When propagating to bt / lobby_tweaker / cosmetics_tweaker / enemy_tweaker / crafting_in_modded / general_tweaker:
1. Declare `<MOD>_RPC_SCHEMA = 1` near MOD_VERSION.
2. Prepend the constant to every `mod:network_send` for THIS mod's RPCs.
3. Add `schema_version` as the first arg after `sender_peer_id` in every `mod:network_register` callback signature.
4. Gate with `_dbg_alert + return` on mismatch.
5. Add `_rt_register("<mod>_rpc_schema_present", ...)`.

Each propagation is a separate Issue so cross-mod churn doesn't compound. **Don't** add other mods' schema constants in ct's pilot bump.

### Closes

GitHub Issue #27 (senior-eng hardening: explicit RPC schema_version + drop-on-mismatch). Follow-up Issues to file: propagate to cosmetics_tweaker (4 RPCs: cos_la_apply / cos_la_apply_req / cos_glow_apply / cos_glow_apply_req), lobby_tweaker (lt_motd_show), enemy_tweaker (et_br_fingerprint), crafting_in_modded (cim_modded_slot), general_tweaker (one AI RPC).

### Notes

- The initial value is 1 — bumping for the pilot would be incorrect, since this is the FIRST schema version we've ever defined.
- `_dbg_alert` was chosen (not `_dbg`) because a schema mismatch is a "wrong / unexpected" event per PROJECT_STANDARDS.md § 3.6 two-channel discipline — the user wants to see this in chat when debug logging is on.
- Build verification only this version. No deploy, no Workshop upload.

## 0.7.113-dev (2026-05-25) — Issue #6 auto-probe: altar shuffle determinism dump

### Why

`/verify_altars` (v0.7.105) gave the user a point-in-time snapshot of altar shuffle inputs, but required manually running the command on host AND client at the same node. The MP determinism validation that Issue #6 calls for is far easier if the diagnostic data is captured automatically during normal play: enable debug logging, play a CW run, then diff the two console logs offline.

### Changed

- `chaos_wastes_tweaker.lua`:
  - **Inside the `DeusRunController.get_deus_weapon_chest_type` hook** (~line 1597): added `_dbg("[altar:get_chest_type] PRE ...")` and `_dbg("... POST ...")` calls bracketing the `table.shuffle(new_distribution, seed)` call. PRE captures `node_key`, `level_seed`, `fnv32(seed)`, the four `effective_setting` chest_*_count values, `is_server`, and the pre-shuffle distribution. POST captures `is_server` + post-shuffle order. With debug logging on, host and client logs can be diffed line-for-line to confirm identical seeds + identical shuffle output.
  - **Inside the `ct_sync_host_settings_chunk` RPC handler** (~line 685): added `_dbg("[altar:host_sync_arrived] ...")` after the payload merge, dumping the four chest_*_count keys the host pushed. Lets a client-side log confirm what arrived from the host without `/verify_altars`.
  - **Inside `mod.on_setting_changed`** (~line 7044): added `_dbg("[altar:setting_changed] ...")` for the four chest_*_count widgets. Records "what I just clicked locally" so post-session log diff can distinguish a per-peer mis-toggle from an actual sync failure.
- `itemV2.cfg` — bumped to v0.7.113-dev.

### Use

1. VMF menu → Chaos Wastes Tweaker → enable `enable_debug_logging`.
2. Play a CW run on host + client(s).
3. Attach the host's and each client's log from `%appdata%\Fatshark\Vermintide 2\console_logs\` to a bug report.
4. Grep for `[ct:dbg] [altar:` lines across both files. PRE seed/hash/effective values should match between peers; POST shuffle order should match between peers.

If any field differs at the same node_key, that's the root cause of the divergence — surface it in the Issue thread. `/verify_altars` remains as the on-demand alternative.

### Closes

GitHub Issue #6 (altar distribution seed determinism untested under live MP).

### Notes

- `_dbg` gates on `enable_debug_logging`; with the toggle off (default) these calls are zero-cost no-ops.
- No `_dbg_alert` used at altar sites — divergence isn't detectable from one peer's local log alone, only via offline diff, so chat surfacing would be noise.

## 0.7.112-dev (2026-05-25) — Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6)

### Why
User-requested two-channel debug discipline: `_dbg` for confirmation / dump / expected behavior (log file only), `_dbg_alert` for unexpected / wrong / mismatch (log file + in-game chat). Helpers installed in every active mod.

### Changed
- `chaos_wastes_tweaker.lua` — installed `_dbg_alert` helper alongside existing `_dbg`. Added `_rt_register("dbg_helpers_two_channel", ...)` alongside the existing 30+ ct regression checks.
- `itemV2.cfg` — bumped to v0.7.112-dev.

### Notes
- 0 existing `_dbg(...)` call sites in this mod (helper was previously unused — only the definition existed).
- 0 bare `mod:echo` reclassified — all `mod:echo` calls are inside `/ct_*` chat command bodies (user-operational, leave alone) or are the load banner.

## 0.7.111-dev (2026-05-25) — Tighten localization strings to vanilla style (~30 entries rewritten)

### Why

Mod-menu tooltips drifted into multi-paragraph essays with meta-language preambles ("Toggle whether...", "When this option is enabled..."). Vanilla VT2 tooltips are uniformly terse, present-tense, and free of meta-language. This pass aligns ct's heavy hitters with the vanilla voice per the new `LOCALIZATION_STANDARD.md` § 11 rules.

### Changed (live entries only — block-commented dormant-boon strings untouched)

- `inject_adventure_maps_tooltip`: 781 → 367 chars; dropped expedition-internals paragraph, kept finale-arena exception + host-only/restart-required.
- `replace_shrines_with_missions_tooltip`: 474 → 219 chars; trimmed "longer expeditions" rationale paragraph.
- `cursed_mission_count_tooltip`, `disable_dominant_god_tooltip`, `altar_count_tooltip`, `cursed_chest_count_tooltip`, `respawn_on_chest_complete_tooltip`, `any_trait_any_weapon_tooltip`, `tweak_trait_tier_by_rarity_tooltip`, `tweak_shard_strike_duration_tooltip`: dropped "Default = vanilla random distribution untouched" / "Side effect:" / "Subtle effect because..." rationale, kept all magnitudes inline.
- Boon tooltips (`disable_boon_ct_meta_ammo_tooltip`, `disable_boon_ct_meta_movespeed_tooltip`, `start_boon_ct_meta_ammo_tooltip`, `description_ct_meta_ammo`, the `enable_boon_*` / `tweak_*` family for Manann's Tempest / Vaul's Anvil / Asuryan's Wrath / Taal's Twinned Arrow / Anath Raema / Wildfire / Ulric / Khaine's Fury / Moot Milk / Killer in the Shadows / Poison Proof / Home Brewer / Miracle of Ulric): dropped implementation-internals paragraphs, kept "Requires a new CW run" gate + every numerical magnitude.
- Mod-boon variant tooltips (`disable_boon_ct_boon_*`, `start_boon_ct_boon_*`): collapsed "Only present in the pool when 'Rework: X as Boon' is enabled in Reworks > Reworks: Boons" → "Requires the matching Rework toggle".
- `enable_skulls_event_boons_tooltip`: 945 → 286 chars (was the worst offender in the file).
- `bots_mirror_host_boons_tooltip`, `tweak_defeat_recovery_tooltip`, `bomb_boon_cooldown_tooltip`, `bomb_boon_exclusive_tooltip`, `endless_bombs_consumes_morgrim_tooltip`, `rv_no_save_morgrim_tooltip`, `tweak_miracle_of_isha_alternative_tooltip`: trimmed.

### Not touched

- Vanilla-template boon descriptions (`disable_boon_boon_skulls_0X_tooltip`, `disable_boon_boon_supportbomb_*_tooltip`, the `X%%%%` placeholder set) — these mirror FT's stock event-boon wording and are already vanilla-style.
- The Miracle of Isha mutex cluster tooltips (`tweak_miracle_of_isha_aegis_tooltip` / `_wounds_tooltip`) — the leading "choice (A/B) of (B). Alternative to '(B/A) X' — these are mutually exclusive..." preamble is load-bearing per LOCALIZATION_STANDARD.md § 10. Cannot tighten.
- Trait tooltips inside `ban_trait_*_tooltip` — sourced verbatim from vanilla trait descriptions; already canonical voice.
- Block-commented entries (Skulls Event Boons, Activate Dormant Boons families inside the `--[[ ... ]]` blocks): edited the live `enable_skulls_event_boons_tooltip` and left the rest alone since they're not live.

### Build

VMBLauncher.exe build chaos_wastes_tweaker — verification only, no deploy/upload.

## 0.7.110-dev (2026-05-25) — Revert misleading "(snaps to nearest 25)" label on starting_coins; document VMF slider limitation in Issue #39

### Why
v0.7.95 added " (snaps to nearest 25)" to the `starting_coins` localization label as a hint that the persisted value gets rounded to a multiple of 25. The label was misleading on two counts: (1) the user did not request it, and (2) the snap happens at save time, not while dragging — the slider still moves in increments of 1 in the live VMF UI. The label promised behavior the slider doesn't visibly exhibit.

### Changed
- `chaos_wastes_tweaker_localization.lua` — reverted `starting_coins` label to `"Starting Coins"`. No code/runtime behavior change (snap-on-save in `on_setting_changed` is untouched).

### Filed
- **Issue #39** — `ct: starting_coins VMF slider steps by 1, not 25`. Documents the VMF numeric-widget limitation: there is no `step` / `snap` / `increment` field in the widget definition (verified against upstream `vmf_options_view.lua` ~L2730 + slider math ~L4181). Options to actually solve in-UI stepping (dropdown of multiples of 25, coarser bin dropdown, upstream VMF PR) listed in the issue for design call.
- **Issue #40** — `ct: Miracle of Isha mutex checkboxes don't visually deselect siblings`. Root cause: VMF's checkbox widget caches display state in `content.is_checkbox_checked` and only re-syncs from persisted value on `view:on_enter` — `mod:set` from inside `on_setting_changed` updates the store but not the open widget. Underlying mutex enforcement IS working (`_get_isha_mode()` returns the right mode); the failure is purely visual until the menu is reopened. Options listed in the issue.

### Notes
- `STARTING_COINS_MODE_MARKER` and the snap-on-save logic in `on_setting_changed`, `setup_run`, and `rpc_deus_set_initial_soft_currency` are unchanged — the bug fix from v0.7.95 (300 setting → 500 actual) stays in.

## 0.7.109-dev (2026-05-25) — Standardize Debug Logging toggle (universal convention)

### Why
Repo-wide convention: every mod now exposes a single `enable_debug_logging` checkbox at the bottom of its VMF widget tree (PROJECT_STANDARDS.md § 3.6). ct previously had no debug toggle at all — added.

### Changed
- `chaos_wastes_tweaker_data.lua` — appended `enable_debug_logging` checkbox (default `false`) AFTER `recursive_sort` so it lands at the bottom of `options.widgets`, top-level (NOT inside any group).
- `chaos_wastes_tweaker_localization.lua` — added `enable_debug_logging` + `enable_debug_logging_tooltip` strings.
- `chaos_wastes_tweaker.lua` — added file-local `_dbg(fmt, ...)` helper gated on `mod:get("enable_debug_logging")`. Output prefixed `[ct:dbg]`.
- `itemV2.cfg` — title + description bumped to v0.7.109-dev.

### Notes
- No existing debug key to rename (ct had none).

## 0.7.108-dev (2026-05-25) — Issue #34: cap ct_meta_ammo Quiver Cascade max_stacks at 30 + belt-and-suspenders _max_ammo clamp

### Why
Closes Issue #34. Pre-v0.7.108 every `ct_meta_*` per-stack buff template (Quiver Cascade `ct_meta_ammo`, Trueshot Talisman `ct_meta_crit`, Heart of Sigmar `ct_meta_health`, etc. — plus the special-cased `ct_meta_movespeed_stack_1` block) wrote `max_stacks = math.huge`. The factory trusted `_make_meta_proc` to never push the stack count beyond the active boon count. That holds under the happy path, but a runaway proc — stale `_get_player_power_ups` list during peer-late-join graph resync, a future RPC race, or any code path that calls `add_buff(stack_name)` outside the proc — can drive the `total_ammo` `stacking_multiplier` geometrically (engine resolution at buff_extension.lua:1391-1448: `final_value = final_value * (multiplier + 1) + bonus` per stack). At enough stacks the result overflows toward `math.huge`, and `tostring(math.huge) == "inf"` then renders on the HUD via `equipment_ui.lua:635` — the same shape as the wt v0.12.77 nil-hole multi-return collapse that surfaced as `inf` ammo earlier this week.

This is the latent CT version of that bug class (sibling). The user-reported infinity-ammo bug 2026-05-25 was actually wt's safe_hook multi-return collapse (already fixed); this fix addresses the matching ct path so the same symptom can't resurface from this side.

### Changed
- **New constant** `CT_META_AMMO_MAX_STACKS = 30` near `MOD_VERSION`. Doc-block explains the rationale: 30 is well past the realistic boon ceiling (typical CW run tops out at 12-18 boons; 30 is endgame-of-endgame). With the v0.7.104 hyperbolic cost floor in place, 30 stacks of +5% `total_ammo` = 1.05^30 ≈ 4.3x — generous, bounded, HUD-safe.
- `register_meta_boon` factory now writes `max_stacks = CT_META_AMMO_MAX_STACKS` (was `math.huge`) on every sub-buff entry.
- Special-cased `ct_meta_movespeed_stack_1` block: same swap.
- `_make_meta_proc` clamps its loop's upper bound: `local stacks_target = math.min(num_boons, CT_META_AMMO_MAX_STACKS)`. The cap in the template AND the clamp on the proc loop are mirrored on purpose — either alone is sufficient, both together close the door against future-code-path drift.

### Added — belt-and-suspenders `_max_ammo` ceiling
- Inside the consolidated `mod:hook_safe("GenericAmmoUserExtension", "_apply_buffs", ...)` body (search for `CT_META_AMMO_MAX_AMMO_SAFETY_CLAMP_v0.7.108`): `if type(self._max_ammo) == "number" and self._max_ammo > 9999 then self._max_ammo = 9999 end`. This is a post-vanilla-`_apply_buffs` clamp that catches the case where some OTHER buff path (talent, weapon trait, foreign mod, future ct feature) ever feeds `total_ammo` enough stacks to push `_max_ammo` toward Lua's float-printable overflow. 9999 sits well above any realistic ammo pool (vanilla max is ~190 on a Drakegun pre-buffs) and well inside Lua's float-printable integer range.
- Consolidation note: VMF doctrine (CLAUDE.md § Hooking) says `hook_safe` does NOT chain on the same (Class, method) — two registrations silently overwrite. So the existing larger-clip `ammo_per_reload` scaling and the new Issue #34 `_max_ammo` clamp now share a single hook body. Both run unconditionally; neither short-circuits the other.

### Added — regression test
- `/ct_regression_test` now includes check `ct_meta_ammo_stacks_bounded`:
  1. Asserts `CT_META_AMMO_MAX_STACKS` sentinel exists and equals 30.
  2. Walks every `ct_meta_*_stack` template in `BuffTemplates`, asserts each sub-buff's `max_stacks` is finite AND `<= CT_META_AMMO_MAX_STACKS` (catches a regression that drops the cap back to `math.huge`).
  3. Synthetic 50-boon stress: simulate the engine's stacking_multiplier formula with base=100, multiplier=0.05, clamp stacks to `CT_META_AMMO_MAX_STACKS`, run the simulated `_max_ammo` through the same `math.min(buffed_max, 9999)` gate — asserts finite AND `<= 9999` AND `> base` (sanity).

### Anti-pattern guardrails (unchanged from v0.7.104)
- Hyperbolic cost-floor curve (`_ct_meta_ammo_cost_multiplier`) is untouched — only the max stack count is bounded, not the per-stack value.
- Multiplier value (0.05) is untouched — fix only the upper bound on stack count.

### Verification
- `/ct_regression_test` in-keep → `ct_meta_ammo_stacks_bounded` should PASS alongside the existing `ct_meta_ammo_*` checks.
- Build-only verification this release (no deploy, no upload). User to drive a CW run with Quiver Cascade and confirm `/verify_ct_meta_ammo` shows finite `_max_ammo` after stacking the boon up.

## 0.7.107-dev (2026-05-25) — Hardening: nil-hole-safe variadic unpack at N call sites (lessons from wt v0.12.77/.78 burn)

### Why
Repo-wide audit of `{ func(...) }` + bare `return unpack(results)` patterns triggered by the weapon_tweaker v0.12.77/.78 silent-truncation burn. Lua 5.1's `#t` operator stops at the first internal nil entry, and bare `unpack(t)` uses `#t` as its upper bound — any wrapped function that returns multi-values with an interior nil silently loses every return after that nil at the caller. The fix is to capture the true return count via `select("#", ...)` and unpack with explicit bounds (`unpack(t, 1, n)`).

### Sites audited (6 in this file)
| Site | Hook target | Vanilla return signature | Verdict |
|---|---|---|---|
| L~1436 | `DeusMechanism._transition_next_node` | single value (`next_state`) | DEFENSIBLE-AS-IS — documented |
| L~1463 | `DeusMechanism.start_next_round` | three values (`game_mode_key`, `side_compositions`, `game_mode_settings`) | **FIXED** — `_capture_returns` + bounded unpack |
| L~2082 | `PickupSystem.populate_pickups` | nothing (bare `return` only) | DEFENSIBLE-AS-IS — documented |
| L~2727 | `DeusMapScene.on_enter` | nothing | DEFENSIBLE-AS-IS — documented |
| L~2936 | `_G.deus_populate_graph` (no-replace path) | single value (`complete_graph`); mod code reads `result[1]` | DEFENSIBLE-AS-IS — documented |
| L~2972 | `_G.deus_populate_graph` (shop-converted path) | same as above | DEFENSIBLE-AS-IS — documented |

### Added
- File-local `_capture_returns(...)` helper near MOD_VERSION (returns `select("#", ...), { ... }`) for any future hook wrapper that needs nil-hole preservation. Doctrine block above the helper documents the pattern.

### Fixed
- `DeusMechanism.start_next_round` hook now uses `local n, results = _capture_returns(func(self, ...))` + `return unpack(results, 1, n)`. Vanilla currently returns three non-nil values, but a future signature change introducing an interior nil (e.g. optional middle value) would have been silently truncated.

### Documented (no behavior change, but inline comments added)
- The five DEFENSIBLE-AS-IS sites now carry a `v0.7.107-dev nil-hole audit:` comment naming the vanilla source line they were verified against and explaining why bare `unpack` is safe at that site.

## 0.7.106-dev (2026-05-25) — Issue #28: demo integration with bt net-replay ring

### Why
Closes Issue #28 (shared net-replay ring buffer for MP desync triage). bt v0.1.2-alpha ships the ring + chat command; ct is the documented demonstrator integration so adopters can see the wiring pattern before Wave-2 (Issue #27) systematizes it across every RPC site.

### Added
- `ct_sync_host_settings_chunk` host→client broadcast is now instrumented on both ends:
  - **Host send side** (~L1098, inside the chunked-broadcast loop in the `DeusRunController.setup_run` hook): per-chunk `record_send("ct", "ct_sync_host_settings_chunk", tag, "others")` where `tag` is `"session=N seq=M total=T chunk=<200 chars>"`.
  - **Client recv side** (top of the `network_register("ct_sync_host_settings_chunk", ...)` callback at L576): per-chunk `record_recv("ct", "ct_sync_host_settings_chunk", tag, sender_peer_id)`.
- Both call sites resolve bt via `get_mod("bt"):net_replay()` and silently no-op if bt isn't installed (same install-independence pattern as the existing `is_br_active()` consumer-side check).

### How to use
1. Run a CW lobby with this mod + bt v0.1.2-alpha installed on every peer.
2. After the host's settings broadcast (fires once at run setup), every peer (host + clients) has populated their bt ring.
3. On any peer, run `/bt_net_replay ct` in chat. The output mirrors to `mod:info` so the trace lands in `%appdata%\Fatshark\Vermintide 2\console_logs\` for offline cross-peer diff.
4. Compare host's `send` lines to each client's `recv` lines: session/seq/total/chunk_str should match end-to-end, and any missing seq number identifies a dropped chunk.

## 0.7.105-dev (2026-05-24) — Issue #6: /verify_altars per-peer determinism diagnostic

### Why
Issue #6 (audit row #3 of CODE_REVIEW.md 2026-05-23 refresh) flags that the custom altar (`deus_weapon_chest`) distribution at `chaos_wastes_tweaker.lua:~1510` uses `HashUtils.fnv32_hash(node.level_seed)` as the shuffle seed — deterministic in theory, but never verified under live multiplayer (hot-join, cross-platform, run-resume). A divergence would silently produce different altar layouts for host vs client peers on the same node.

### Added
- `/verify_altars` chat command (inserted after `/verify_meta_ammo`). On each peer, prints:
  - Current `node_key` (must match across peers — graph-snapshot RPC sync check)
  - `node.level_seed` (must match — the source-of-truth seed)
  - `fnv32_hash(level_seed)` output (must match — pure function of seed)
  - `effective_setting` values for `chest_upgrade_count` / `chest_swap_melee_count` / `chest_swap_ranged_count` / `chest_power_up_count` (must match — host-broadcast settings sync check)
  - Local `mod:get(...)` values for the same four settings (diagnostic — surfaces local-vs-effective divergence if a client's own setting changed but host didn't broadcast)
  - `is_server` flag (so you can tell which peer's output is which)
  - Current `_deus_weapon_chest_distribution` pending pops (only populated AFTER a chest opens on that node)
- Output also mirrored to `mod:info` so the line lands in `console_logs/` for offline cross-peer comparison.

### Validation plan (manual, per Issue #6)
1. Host (PC-A) + client (PC-B) in the same CW lobby, same run, same node.
2. Both run `/verify_altars`. Screenshot or copy both outputs.
3. Every line should match between peers EXCEPT possibly the pending-pops list (depends on whether either peer has opened a chest yet).
4. Hot-join a 3rd peer mid-run and repeat.
5. If `node_key` / `level_seed` / hash differ → graph-snapshot RPC desync.
6. If `effective_setting` values differ → host-broadcast settings desync.
7. If only pending pops differ → shuffle ran with different state somehow.

This release ships the diagnostic but does NOT close Issue #6 — the MP test itself remains for the user to run.

## 0.7.104-dev (2026-05-24) — Quiver Cascade hyperbolic cost-floor (closes 0-cost zero-crossing) + per-meta-boon /verify_ct_meta_* commands

### Why
Two gamebreaking problems, both root-caused by audits this session:

1. **0-cost ammo / energy / overcharge bug** (`.ammo_system_design_2026-05-24.md`): v0.7.102's "consumption-side stat_buff" approach (`ammo_used_multiplier` + `reduced_overcharge`) uses vanilla `stacking_multiplier` resolution which is **linear-additive** (buff_extension.lua:1391-1448). 20 stacks of -0.05 sum to `-1.0`, giving `root_multiplier = 1 + (-1.0) = 0` → cost-per-shot rounds to 0 → infinite ammo, energy, and overcharge headroom. Latent at ~20 boons. Vanilla never ships these stat_buffs at `max_stacks > 1`; ct_meta_ammo's per-boon stacking was unexplored territory and the curve crashed through zero.
2. **User can't eyeball whether meta-boons are taking effect** (`.meta_boons_audit_2026-05-24.md`): every meta-boon stat_buff key IS valid and IS read by vanilla, but per-stack increments (1-5%) on bar-displayed stats are too small to see. Audit confirmed 0 silent-no-op key bugs — the perceived "broken" is actually "invisible". Need runtime probes per boon to distinguish "broken registration" from "tiny but working".

### Changed — Quiver Cascade redesign
- **Dropped** the `reduced_overcharge` and `ammo_used_multiplier` stat_buff entries from `CT_META_BOONS[2]`. Both used linear-additive `stacking_multiplier` resolution → divergence at 20 boons → zero / negative cost per shot.
- **Kept** the `total_ammo` stat_buff (positive-only growth, no zero-crossing — vanilla Waystalker passive ships +100% with no engine issue).
- **Added** new shared helper `_ct_meta_ammo_cost_multiplier(num_boons)` at top of file (next to `_clamp_network_bounded_max`): hyperbolic-saturating curve with hard floor.
  - Formula: `cost_factor = max(1 - (N*step) / (1 + N*step/cap), floor)` where `step=0.05`, `cap=0.75`, `floor=0.25`.
  - Bounded `[0.25, 1.0]` for any non-negative N (asserted by regression tests `ct_meta_ammo_cost_floor_holds` and `ct_meta_ammo_no_zero_cost`).
  - Sample points: N=5 → 0.81, N=10 → 0.70, N=20 → 0.57, N=50 → 0.42, N=100 → 0.35, N→∞ → 0.25 (asymptote, NEVER reaches 0).
- **Added** three direct vanilla hooks (use `mod:hook`, not `hook_safe`, since we mutate the cost arg). Each pcalls its body so a crash in resolution can never break the vanilla consumption path. Throttled per-extension log (1 line per 2s) only when factor < 1.0.
  - `GenericAmmoUserExtension.use_ammo` (vanilla line 425) — scales `ammo_used` with belt-and-suspenders integer floor `math.max(1, math.ceil(...))`.
  - `PlayerUnitEnergyExtension.drain` (vanilla line 85) — scales `amount` (float).
  - `PlayerUnitOverchargeExtension.add_charge` (vanilla line 330) — scales `overcharge_amount`, respecting `_ignored_overcharge_types` (charging, damage_to_overcharge, drakegun_charging, flamethrower — same list vanilla skips at line 343).
- **Hooks gate on local-player ownership** — husk units (remote players) early-return with no scaling. Each peer applies its own discount to its own shots; vanilla networking syncs the result.

### Added — per-meta-boon verify commands
For every entry in `CT_META_BOONS`, a factory-generated `/verify_ct_meta_<suffix>` chat command:
- `/verify_ct_meta_stagger` — probes `power_level_impact` + `power_level_melee_cleave`
- `/verify_ct_meta_crit` — probes `critical_strike_chance` + `critical_strike_effectiveness`
- `/verify_ct_meta_health` — probes `max_health` + `healing_received`
- `/verify_ct_meta_cooldown` — probes `cooldown_regen`
- `/verify_ct_meta_ammo` — probes `total_ammo` AND prints the hyperbolic cost factor from the direct hooks
- `/verify_ct_meta_movespeed` (special-cased) — reads `PlayerUnitMovementSettings.get_movement_settings_table(unit).move_speed` directly (no stat_buff path)

Each command prints `OK`/`FAIL` per stat_buff with `resolved` vs `expected` (linear projection) and `delta`. Tolerance `1e-3`. Lets the user PROVE in-mission "the stat_buff applied" — distinguishes broken-registration from invisible-effect.

### Rewritten — /verify_meta_ammo
Now prints the hyperbolic curve at N=0,1,5,10,20,50,100,1000 so the user can see saturation visually. Live section shows `num_boons`, `cost_factor`, and `total_ammo` live resolution if a player unit is available.

### Sentinel marker swap
- **Retired** `CT_META_AMMO_ENERGY_CONSUMPTION_MARKER` value (v0.7.102) — kept the local declaration as a dead placeholder so any transitional upvalue reads still resolve. The body it anchored (`buff_funcs.functions.ct_meta_ammo_refresh_capacity`) still runs the ammo refresh.
- **Added** `CT_META_AMMO_HYPERBOLIC_MARKER = "CT_META_AMMO_HYPERBOLIC_FLOOR_v0.7.104"` at top-of-file scope, read as upvalue inside `_ct_meta_ammo_cost_multiplier` body and printed by `/verify_meta_ammo`.

### Regression tests (`/ct_regression_test`)
- **Removed** `ct_meta_ammo_uses_consumption_side` — the assertion ("ammo_used_multiplier present in ct_meta_ammo_stack") is now WRONG (the stat_buff was the bug). The new `ct_meta_ammo_hyperbolic_floor_v0_7_104` check actively REJECTS its presence.
- **Added** `ct_meta_ammo_hyperbolic_floor_v0_7_104` — verifies marker constant matches v0.7.104 value, helper is exposed on mod table, `BuffTemplates.ct_meta_ammo_stack` contains `total_ammo` and does NOT contain `ammo_used_multiplier`/`reduced_overcharge`/`max_energy`/`max_overcharge`.
- **Added** `ct_meta_ammo_cost_floor_holds` — runtime probe: asserts `_ct_meta_ammo_cost_multiplier(1000)` returns a number in `[0.25, 1.0]` AND `_ct_meta_ammo_cost_multiplier(0)` returns exactly `1.0` (no behavior change without active boons).
- **Added** `ct_meta_ammo_no_zero_cost` — runtime probe: iterates N from 0 to 50, asserts cost factor stays in `[0.25, 1.0]` AND is monotonically non-increasing (curve-shape sanity).
- **Kept** `ct_clamp_helper_present` and `ct_no_direct_max_energy_mutation` — both still valid (helper still useful for future code, no direct `_max_<X>` writes anywhere in ct).

### Verification
1. Restart VT2 with mod enabled.
2. Run `/ct_regression_test` — all 4 new checks PASS (plus the two retained).
3. Run `/verify_meta_ammo` from keep — see hyperbolic curve printout (N=20→0.571, N=100→0.348, N=1000→0.250).
4. Start a CW run, pick up boons until count > 20, run `/verify_ct_meta_ammo` mid-mission — see `cost_factor` decrease as N grows, total_ammo OK/FAIL line.
5. Fire any ranged weapon with N ≥ 20 boons — ammo counter decrements every shot (not stuck at full); reload triggers at empty. Same for Sienna staff (overcharge rises) and Moonfire bow (energy drains).
6. Run `/verify_ct_meta_<X>` per boon to confirm each stat_buff resolves to its expected linear projection.

### References
- Design source: `.ammo_system_design_2026-05-24.md`
- Audit source: `.meta_boons_audit_2026-05-24.md`
- Prior fix lineage: v0.7.78 (max_overcharge → reduced_overcharge), v0.7.102 (consumption-side stat_buff), v0.7.104 (this — direct hooks).

## 0.7.103-dev (2026-05-23) — Back-fill regression test for v0.7.92 Reckless Swings name-based lookup (GH #5)

### Why
Test-coverage audit `.test_coverage_audit_2026-05-24.md` flagged v0.7.92-dev as the one ct fix shipped without an automated regression check (doctrine PROJECT_STANDARDS §15 violation — "every bug requires a test"). The v0.7.92 verification block was entirely manual (load CW, enable toggle, eyeball log line). If a future refactor reverts the name-based lookup to positional `buffs[1]`/`description_values[1]`/`[3]` indexing, nothing catches it.

### Added
- `CT_RECKLESS_SWINGS_NAME_LOOKUP_MARKER` source-pattern sentinel — file-scope constant declared next to `_find_entry_by`, read as an upvalue inside `apply_reckless_swings_tweak` (anchored anti-bitrot pattern, mirrors v0.7.102's `CT_META_AMMO_ENERGY_CONSUMPTION_MARKER`). A refactor that strips the name-based search code path also breaks the upvalue read site.
- `/ct_regression_test` check `reckless_swings_name_based_lookup` — verifies the marker constant matches the v0.7.92 value AND `_find_entry_by` helper exists AS A FUNCTION at file scope. Also schema-checks `reckless_swings_originals` for the v0.7.92 `buff_index`/`dv_threshold_index`/`dv_damage_index` numeric fields (when the tweak is active — payload-shape regression catch).

### Verification
1. Restart VT2 with mod enabled.
2. Run `/ct_regression_test` in chat — verify line `PASS: reckless_swings_name_based_lookup`.
3. (Optional positive trip) Comment out the marker declaration, rebuild, rerun — expect FAIL with "CT_RECKLESS_SWINGS_NAME_LOOKUP_MARKER not defined".

### References
- Test coverage audit: `.test_coverage_audit_2026-05-24.md` MISSING row 1.
- Doctrine: PROJECT_STANDARDS.md §15.
- Original fix: v0.7.92-dev (below).

## 0.7.102-dev (2026-05-23) — Quiver Cascade energy: consumption-side rewrite + universal `_clamp_network_bounded_max` helper (retires v0.7.101's career-specific gate)

### Why
v0.7.101-dev "fixed" the Necromancer-bot max_energy crash (GUID `10764a92-d642-43c2-a51b-07c5b45508be`) by gating the direct `_max_energy` mutation on `item_name == "we_deus_01"` + a base-sanity check + an engine clamp. User feedback (correct): **career-specific gating is the wrong approach.** If any future career (or any future ANY-careers-can-wield-any-weapon mod, of which we ship one) puts the `energy_system` extension on a different career or wields Moonfire on a non-Kerillian, the gate's whitelist is wrong and the bug class returns. The right fix is the same shape as v0.7.78's `max_overcharge → reduced_overcharge` switch: use the vanilla consumption-side stat_buff so the engine's network-bounded max field is never touched.

Vanilla DOES expose a consumption-side stat_buff for energy: **`ammo_used_multiplier`** (defined `stacking_multiplier` at `buff_templates.lua:28`, read by `PlayerUnitEnergyExtension.drain` line 95: `amount = amount * apply_buffs_to_value(1, "ammo_used_multiplier")`). It's the EXACT parallel of `reduced_overcharge`: per-cast, never network-synced, no engine cap involved. Vanilla CW boon `boon_range_01` (Hand of Drakira) already uses it — `scripts/settings/dlcs/morris/deus_power_up_settings.lua:4974`.

### Changed — three-layer doctrine fix
1. **Consumption-side stat_buff (PRIMARY).** `CT_META_BOONS.ct_meta_ammo.stat_buffs` now includes `{ stat_buff = "ammo_used_multiplier", multiplier = -0.05 }` alongside `reduced_overcharge` (overcharge) and `total_ammo` (ammo). At 12 boons → cumulative -0.60 multiplier; `stacking_multiplier` composes additively so the effective drain multiplier is `1 + (-0.60) = 0.40`. Per-cast energy cost drops to 40% → ~2.5x effective firing capacity. Functionally equivalent to the prior +60% bar buff but with no NetworkConstants ceiling risk for any career, present or future.
2. **Universal clamp helper (UNIVERSAL SAFEGUARD).** New top-of-file helper `_clamp_network_bounded_max(field_name, raw_value)` reads `NetworkConstants[field_name].max` (with safe `or 60` fallback) and clamps to `[min, cap]` with integer rounding. Exposed as `mod._clamp_network_bounded_max` for tests / future code. There are currently ZERO direct `_max_<X>` writes in the entire monorepo (verified via grep) — the helper is purely belt-and-suspenders for future code that might be tempted to write the field directly.
3. **Energy refresh block REMOVED.** The entire energy-extension mutation block at the old L5650-5742 (item-name whitelist + base-sanity gate + engine clamp + `_max_energy = N` write + `_energy` rescale) is gone. The boon's apply func now only refreshes `AmmoExtension` (for `total_ammo`); overcharge and energy ride entirely on their respective consumption-side stat_buffs and need no explicit refresh — that's the whole point of the consumption-side pattern.

### Sentinel marker swap
- **Retired:** `CT_META_AMMO_WEAPON_GATE_MARKER`, `CT_META_AMMO_ENERGY_CLAMP_MARKER` (and their two regression checks). They documented the v0.7.101 weapon-gate approach which is now wrong.
- **Added:** `CT_META_AMMO_ENERGY_CONSUMPTION_MARKER = "CT_META_AMMO_ENERGY_CONSUMPTION_v0.7.102"`. Read as an upvalue inside the `ct_meta_ammo_refresh_capacity` closure so a future refactor that strips the consumption-side comment block also breaks the marker read site (anti-bitrot).

### New `/verify_meta_ammo` (rewritten)
The v0.7.101 command was Moonfire-gate-focused. The v0.7.102 rewrite is career-agnostic. Output:
- `weapon=<name>  num_boons=<N>`
- Per-stack and N-stack totals for all 3 stat_buffs (`total_ammo`, `reduced_overcharge`, `ammo_used_multiplier`)
- Live `apply_buffs_to_value(1, <key>)` resolution from the buff_extension (cross-check vs raw arithmetic when other mods stack)
- Clamp ceilings for `max_overcharge` + `max_energy` (proves the helper works at runtime)
- Direct-mutation scan: prints current `_max_overcharge` / `_max_energy` and FLAGS any value > clamp ceiling
- Sentinel marker

### New regression checks (replaces 3 from v0.7.101)
1. `ct_meta_ammo_uses_consumption_side` — asserts `CT_META_AMMO_ENERGY_CONSUMPTION_MARKER` is the v0.7.102 value AND walks `BuffTemplates.ct_meta_ammo_stack.buffs` to verify `ammo_used_multiplier` is present and no engine-bounded `max_energy`/`max_overcharge` stat_buff is present. Catches a partial revert that puts the bug back in either the marker OR the data path.
2. `ct_clamp_helper_present` — asserts `mod._clamp_network_bounded_max` exists, is callable, and emits a clamped value `<= NetworkConstants.max_<X>.max` for both overcharge and energy when fed a deliberately oversized input (9999).
3. `ct_no_direct_max_energy_mutation` — runtime walk of `Managers.player:human_and_bot_players()` asserting `_max_energy` AND `_max_overcharge` on every player unit stays within their respective engine caps. Best-effort PASS during keep load timing.

### Files modified
- `chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/chaos_wastes_tweaker.lua` (≈170 LOC delta; net negative: full energy mutation block excised, replaced by 1-line consumption-side stat_buff entry + universal clamp helper):
  - `MOD_VERSION` `0.7.101-dev` → `0.7.102-dev`
  - Added top-of-file `_clamp_network_bounded_max(field_name, raw_value)` helper (around line 47), exposed as `mod._clamp_network_bounded_max`
  - `CT_META_BOONS.ct_meta_ammo.stat_buffs` — new `{ stat_buff = "ammo_used_multiplier", multiplier = -0.05 }` entry
  - Retired markers + new sentinel `CT_META_AMMO_ENERGY_CONSUMPTION_MARKER`
  - `ct_meta_ammo_refresh_capacity` — energy mutation block deleted; function body shrunk to its original "refresh AmmoExtension" role + an upvalue read of the new marker
  - `/verify_meta_ammo` — rewritten career-agnostic
  - 3 regression checks swapped (retired v0.7.101 weapon-gate / clamp-marker / energy-within-bounds; added v0.7.102 consumption-side / clamp-helper / no-direct-max-mutation)
- `chaos_wastes_tweaker/itemV2.cfg` — title suffix `v0.7.101-dev` → `v0.7.102-dev` (vmblauncher auto-rewrites on upload)

### Verification recipe
1. Restart VT2.
2. In the keep on ANY career (Necromancer, Outcast Engineer, Sister of the Thorn, Mercenary, Slayer — anything), run `/ct_regression_test` — all v0.7.102 checks PASS (plus the pre-existing ones).
3. Run `/verify_meta_ammo` — should print all three stat_buffs, clamp ceilings ≥ 60, and `violations=NONE`.
4. Start a CW run with **Necromancer** (the original crash career — bot or human). Collect 12+ boons. Open a Chest of Trials. No crash. Run `/verify_meta_ammo` — should show `num_boons=12`, `ammo_used_multiplier  -5% -> -60% (live=0.40)`, `violations=NONE`.
5. Start a CW run with **Kerillian + Moonfire Bow**. Collect 12+ boons. Verify firing the bow drains the energy bar visibly slower (≈40% per shot of the pre-boon rate).
6. Lint: `tools/mod-lint/lint-mod.ps1 -ModPath chaos_wastes_tweaker` PASS.

### Peer-sync safety
The fix is BACKWARD-COMPATIBLE with prior versions IF the player using v0.7.102 never crashes a non-Kerillian host running pre-v0.7.102 (because the host's local stack still mutates `_max_energy` and that's per-peer state). Mixed-version play between v0.7.101 ↔ v0.7.102 is safe; pre-v0.7.101 hosts still risk the original crash on their own side. The BuffTemplates entry is registered via the same `register_buff_in_network_lookup` path as the existing 3 stat_buffs (deterministic sort), so combined_hash is stable.

### Doctrine memory written
`feedback_vt2_max_resource_consumption_side.md` — formalizes the rule: when a boon/buff conceptually means "more of a network-bounded resource", use the consumption-side stat_buff (`reduced_<field>`, `ammo_used_multiplier`, etc.); never write `_max_<field>` directly. Career-specific gating is wrong because the bug class returns the moment another career adopts the resource.

---

## 0.7.101-dev (2026-05-23) — Quiver Cascade Moonfire-only energy gate + engine-bound clamp (fixes Necromancer-bot max_energy crash)

### Why
Crash GUID `10764a92-d642-43c2-a51b-07c5b45508be`. Engine fatal at `foundation/scripts/util/error.lua:26`:
```
Max energy outside value bounds allowed by network variable!
```
fired from `player_unit_energy_extension.lua:43`. Self state at crash: `_max_energy = 64`, `_ct_meta_ammo_base_max = 40`, `_energy = 64`. Career = **Necromancer (bot)**. `NetworkConstants.max_energy.max == 60` so 64 trips the fassert.

Root cause: the Quiver Cascade meta boon's `ct_meta_ammo_refresh_capacity` apply func (v0.7.43–v0.7.100) mutated `_max_energy` on **any** player unit with the `energy_system` extension. But per `scripts/network/unit_extension_templates.lua`, `PlayerUnitEnergyExtension` is registered on EVERY career's player + husk profile. Non-Kerillian careers fall back to `max_value or 40` (player_unit_energy_extension.lua:14) because `EnergyData` (energy_data.lua) only defines entries for Kerillian's four careers (`we_waywatcher` / `we_maidenguard` / `we_shade` / `we_thornsister`, all `max_value = 25`).

So a Necromancer bot collected 12 boons (Quiver Cascade stacks 12 → +60%): `40 × 1.60 = 64`, exceeded the cap, crashed the host. Bots get boons too — `Managers.player:owner(unit)` returns the bot's player object the same as a human's.

The original code (L5650) was AUTHORED only for Moonfire Bow (Kerillian's `we_deus_01`) per the comment, but the gate it used was extension-existence — wrong gate.

### Changed — three-layer defensive gate
`scripts/mods/chaos_wastes_tweaker/chaos_wastes_tweaker.lua` (the `ct_meta_ammo_refresh_capacity` body):

1. **Gate 1 — weapon whitelist.** Reads `inventory_extension:get_slot_data("slot_ranged").item_data.name` and proceeds only when it equals `"we_deus_01"`. Necromancer / Outcast Engineer / Sister of the Thorn / any future career-with-energy-mechanic short-circuit at this gate and the extension is never touched.
2. **Gate 2 — base sanity.** If `_ct_meta_ammo_base_max >= 40`, skip. Moonfire Bow's base on Kerillian is 25 (per `EnergyData.we_<career>.max_value`); a base of 40 means we stashed the value while the extension was on a non-Kerillian career falling back to the `or 40` default. Belt-and-suspenders against gate-1 missing a future Kerillian-equips-non-Moonfire-then-equips-Moonfire transition.
3. **Engine clamp.** Even when both gates pass, clamp `new_max` to `NetworkConstants.max_energy.max` (with hardcoded fallback `60` if the constant isn't loaded yet). That's the same value the engine fassert reads — staying at-or-below it is the only crash-free shape.

### Apply-site logging (per PROJECT_STANDARDS.md §15)
- Gate fires: `[ct/meta_ammo] energy_max gated: weapon=<name> (not Moonfire Bow); skipping`
- Base-sanity gate fires: `[ct/meta_ammo] energy_max gated: base=<n> suspiciously high for Moonfire (expected ~25); skipping`
- Scaling proceeds: `[ct/meta_ammo] energy_max scaled: weapon=we_deus_01 base=25 raw_new=<f> new_max=<n> clamp_ceiling=60 num_boons=<n>`

### New chat command — `/verify_meta_ammo`
Dumps the local player's wielded weapon item_name, base/cur max energy from the extension, num_boons from the deus run controller, the clamp ceiling, and what the refresh func would emit for the current state. Reports `gate=SKIP (not Moonfire)` or `gate=PROCEED (Moonfire)` so the user can confirm the fix works without staring at logs. Works in the keep (no run → num_boons = 0) and mid-run.

### New regression checks
Three new `_rt_register` entries on `/ct_regression_test`:
1. `ct_meta_ammo_weapon_gate_present` — asserts the file-scope marker constant `CT_META_AMMO_WEAPON_GATE_MARKER` shipped to the compiled bundle. The closure uses it as an upvalue, so removing it during a refactor breaks both the read site and this check.
2. `ct_meta_ammo_energy_clamp_present` — same shape for `CT_META_AMMO_ENERGY_CLAMP_MARKER`.
3. `ct_meta_ammo_energy_within_bounds` — runtime: walks `Managers.player:human_and_bot_players()`, finds any unit with an `energy_system` extension, asserts `_max_energy <= NetworkConstants.max_energy.max`. Returns FAIL with the offending player + value if any unit exceeds. Tolerates keep-load timing (PASS if `Managers.player` not ready).

### Files modified
- `chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/chaos_wastes_tweaker.lua` — `MOD_VERSION` `0.7.100-dev` → `0.7.101-dev`; gate + clamp in `ct_meta_ammo_refresh_capacity`; file-scope marker constants; `/verify_meta_ammo` command; 3 new regression checks.
- `chaos_wastes_tweaker/itemV2.cfg` — title suffix `v0.7.100-dev` → `v0.7.101-dev`; description body `v0.7.98-dev` → `v0.7.101-dev` (the stale `0.7.98-dev` reference inside the description was a pre-existing drift, fixed in this bump).

### Verification recipe
1. Restart VT2 with the updated mod.
2. In the keep, run `/ct_regression_test` — all 3 new checks must PASS (plus the existing ones).
3. With a Necromancer in the party (bot or human), wield any non-Moonfire ranged weapon. Run `/verify_meta_ammo` — should report `gate=SKIP (not Moonfire)`.
4. Start a CW run with Kerillian + Moonfire Bow. Collect 12+ boons. Open a Chest of Trials. Run `/verify_meta_ammo` — should report `gate=PROCEED (Moonfire)`, `would_emit` clamped to ≤ 60. No crash.

### Peer-sync safety
The fix only changes the LOCAL apply func body — no new NetworkLookup entries, no new BuffTemplates, no new DeusPowerUp* registrations. Peers running mixed versions remain compatible: pre-v0.7.101 peers crash on Necromancer-with-12-boons; v0.7.101 peers no-op the energy mutation on Necromancer. No combined_hash impact.

---

## 0.7.100-dev (2026-05-23) — Full dormant-boon code-path purge (eliminates the v0.7.99 half-fix that re-crashed at Chest of Trials)

### Why
v0.7.98-dev disabled the dormant feature by emptying `DORMANT_BOON_RARITY = {}`, but every other reference to dormant data in the file remained ACTIVE. v0.7.99-dev added `_G.DORMANT_BOON_RARITY = _G.DORMANT_BOON_RARITY or {}` to fix a Lua scope bug exposed at the Chest of Trials (crash GUID `4c5d2157-e5ee-45fd-8f49-ecdcd2e7ade3`, `chaos_wastes_tweaker.lua:1144`). That was a half-fix: live code still walked the empty table and read `activate_dormant_*` settings from a non-existent widget. User demand: **zero active code referencing dormant data**.

### Changed — full purge inventory
- `chaos_wastes_tweaker.lua` — `MOD_VERSION` bumped `0.7.99-dev` → `0.7.100-dev`.
- `chaos_wastes_tweaker.lua` — Top of file: replaced the `_G.DORMANT_BOON_RARITY = ... or {}` shim with a defensive-style preamble block + the `CT_DORMANT_PURGE_VERIFIED` sentinel constant. The global table is GONE (no empty `{}` either).
- `chaos_wastes_tweaker.lua` — Apply-site breadcrumb reworded `dormant boons disabled` → `dormant/skulls boons purged` (active vs. inactive distinction); now logs the sentinel value.
- `chaos_wastes_tweaker.lua` — `_should_strip` (in `generate_random_power_ups` hook ~L1150): dormant branch removed (`DORMANT_BOON_RARITY[name] ... activate_dormant_<name>` check deleted). Only `disable_boon_<name>` + bomb-mutex remain.
- `chaos_wastes_tweaker.lua` — `stripped_dormants` audit log path and `_should_strip` post-strip `DORMANT_BOON_RARITY[name]` check deleted. The strip loop is still defensive (belt-and-suspenders) but contains no dormant-specific code.
- `chaos_wastes_tweaker.lua` — `add_power_ups` boon-trace hook (~L3435): removed `is_dormant`, `dormant_toggle`, and the `DORMANT GRANTED WITH TOGGLE OFF` warning. The `DISABLED BOON GRANTED` warning (user-facing disable toggle) remains active.
- `chaos_wastes_tweaker.lua` — `/verify_dormants` chat command (~L3670) entire body block-commented (`--[[ ... --]]`). Re-enable is a literal uncomment.
- `chaos_wastes_tweaker.lua` — `pre_register_dormant_lookups` + `sync_dormant_boons` function declarations + apply-site calls (~L4885) wrapped in `--[[ ... --]]`. The functions iterated `DORMANT_BOON_RARITY` directly. `_injected_dormants`, `_added_to_pool`, `inject_dormant_boon`, `_add_dormant_to_pool`, `_remove_dormant_from_pool` stay ACTIVE (used by trait + meta boons as generic injectors; do NOT touch `DORMANT_BOON_RARITY`).
- `chaos_wastes_tweaker.lua` — `sync_host_dependent_state` (~L5931): the inline `sync_dormant_boons()` comment was rewritten to point at the FULL purge.
- `chaos_wastes_tweaker.lua` — `deus_rarities_valid` regression check (~L7155): replaced the `pairs(DORMANT_BOON_RARITY)` iteration with `pairs(CT_DISABLED_DORMANT_RARITIES)` so the check still validates the disabled-set's rarities are vanilla-legal (paranoia against future re-enable bringing back a bad rarity).
- `chaos_wastes_tweaker.lua` — `dormant_boon_rarity_is_table` regression check (v0.7.99) renamed to `dormant_boon_rarity_global_absent` and inverted: PASS now means `_G.DORMANT_BOON_RARITY == nil`. The full purge means no global remains.
- `chaos_wastes_tweaker.lua` — NEW regression check `dormant_setting_keys_not_consumed`: asserts the `CT_DORMANT_PURGE_VERIFIED` sentinel constant is present + correct in the compiled bundle. A future partial revert that drops the sentinel fails this check.
- `chaos_wastes_tweaker.lua` — NEW regression check `dormant_chat_commands_removed`: walks the VMF command registry (`mod._data.commands` + `_G.vmf.commands`) and asserts `verify_dormants` is NOT present.
- `itemV2.cfg` — Title suffix bumped: `v0.7.99-dev` → `v0.7.100-dev`.

### Defensive style guide added
A new preamble near `MOD_VERSION` documents the four defensive rules established after this purge:
1. Top-level tables consumed by mid-file closures: declare at TOP of file.
2. Global table indexes: wrap in `(rawget(_G, "X") or {})` sentinel.
3. NetworkLookup / BuffTemplates: always `rawget()`.
4. Every disabled feature ships with a regression check asserting the disable.

### Regression checks for dormant-related code after this purge

Five checks now cover the dormant-disabled state:
1. `dormant_boons_NOT_registered` — disabled names absent from `NetworkLookup.deus_power_up_templates` + `_G.BuffTemplates`.
2. `dormant_boons_NOT_in_pool` — disabled names absent from `DeusPowerUpRarityPool` + `DeusPowerUps[rarity]`.
3. `dormant_boon_rarity_global_absent` — `_G.DORMANT_BOON_RARITY == nil`.
4. `dormant_setting_keys_not_consumed` — purge-verified sentinel present.
5. `dormant_chat_commands_removed` — `/verify_dormants` absent from VMF registry.

### Verification
1. Restart VT2 with the updated mod.
2. Run `/ct_regression_test` in keep — all 5 dormant-related checks must PASS.
3. Start a CW run and trigger a Chest of Trials. The v0.7.99 crash GUID `4c5d2157` was at line 1144 (`_should_strip` indexing the missing global); the line no longer has that code path.

### Peer-sync safety
No change vs. v0.7.99: every peer running v0.7.100-dev produces the same `NetworkLookup` contents (no names added beyond trait/meta boons). The trait + meta boon injection paths still call `inject_dormant_boon` directly with non-dormant names — `inject_dormant_boon` is just historically named; it's a generic boon injector.

---

## 0.7.98-dev (2026-05-23) — Disable all dormant boons + Skulls event boons + ct_kill_heal (Chest-of-Trials crash mitigation)

### Why
After investigating a possible Chest-of-Trials crash, the user requested all mod-injected dormant CW boons be removed from the game entirely. The 9 vanilla "dormant" power-ups (`squats`, `deus_larger_clip`, `deus_throw_speed_increase`, `deus_ammo_pickup_give_allies_ammo`, `deus_coin_pickup_regen`, `deus_large_ammo_pickup_infinite_ammo`, `deus_timed_block_free_shot`, `deus_transmute_into_coins`, `explosive_pushes_on_damage_taken`) and the mod-defined `ct_kill_heal` boon are no longer registered in any `NetworkLookup` / `BuffTemplates` / `DeusPowerUps*` table. The v0.7.93-dev Skulls event boon mutator-clear is also disabled — Skulls boons remain behind their vanilla `skulls_2023` mutator gate (i.e. pre-v0.7.85 behavior). The implementation code is preserved in block comments so re-enable is a literal uncomment.

### Changed
- `chaos_wastes_tweaker.lua` — `MOD_VERSION` bumped `0.7.97-dev` → `0.7.98-dev`.
- `chaos_wastes_tweaker.lua` — Added apply-site log breadcrumb at mod load: `[ct] dormant boons disabled (v0.7.98-dev); 10 dormants + 10 skulls boons commented out at mod-load.` per `feedback_vt2_verify_before_shipping.md`.
- `chaos_wastes_tweaker.lua` — Added `CT_DISABLED_DORMANT_BOON_NAMES` + `CT_DISABLED_DORMANT_RARITIES` + `CT_DISABLED_SKULLS_BOON_NAMES` constants near the top of the file so the new regression checks can iterate the disabled names without depending on the block-commented originals.
- `chaos_wastes_tweaker.lua` — `DORMANT_BOON_RARITY` populated table replaced with empty `{}`; original entries preserved in block comment immediately above. With the table empty every cross-file reference (`_should_strip`, the `add_power_ups` boon-trace hook, `pre_register_dormant_lookups`, `sync_dormant_boons`, `/verify_dormants`, the `deus_rarities_valid` regression check) becomes a clean no-op without needing per-call edits.
- `chaos_wastes_tweaker.lua` — Apply-site calls `pre_register_dormant_lookups()` + `sync_dormant_boons()` block-commented.
- `chaos_wastes_tweaker.lua` — `sync_dormant_boons()` call inside `sync_host_dependent_state` line-commented so re-enable is symmetric with the apply-site uncomment.
- `chaos_wastes_tweaker.lua` — `on_setting_changed` branches for `activate_dormant_*` and `enable_skulls_event_boons` line-commented — the widgets no longer exist so the branches couldn't fire anyway, but commenting them keeps the disable explicit.
- `chaos_wastes_tweaker.lua` — Entire Skulls block (`SKULLS_EVENT_BOONS` list + `_skulls_original_mutators` + `pre_register_skulls_event_lookups` + `_set_skulls_mutators_active` + `sync_skulls_event_boons` + the two apply-site calls) wrapped in a `--[[ ... --]]` block comment.
- `chaos_wastes_tweaker.lua` — `ct_kill_heal` `do ... end` block wrapped in a `--[[ ... --]]` block comment. The NetworkLookup pre-registration that previously had to fire unconditionally is removed at the same time — acceptable because every peer re-syncing to v0.7.98-dev has identical mod state with no `ct_kill_heal` name in the lookup, so no peer-version-subset can produce divergent indices.
- `chaos_wastes_tweaker.lua` — Regression checks `dormant_boons_preregistered`, `dormant_buff_dual_registered`, `kill_heal_uses_permanent_heal_type`, and `skulls_boons_preregistered` block-commented (they would FAIL given registration is disabled). The `skulls_boons_preregistered` block-comment is mandatory because it references the now-undefined `SKULLS_EVENT_BOONS` local — leaving it live would throw "attempt to index a nil value" at `/ct_regression_test` time.
- `chaos_wastes_tweaker.lua` — Added two new regression checks:
  - `dormant_boons_NOT_registered` — iterates `CT_DISABLED_DORMANT_BOON_NAMES` and verifies each is absent from BOTH `NetworkLookup.deus_power_up_templates` AND `_G.BuffTemplates` (under each name's known rarity variant).
  - `dormant_boons_NOT_in_pool` — verifies the disabled names are not present in any rarity bucket of `DeusPowerUpRarityPool` or `DeusPowerUps[rarity]`.
- `chaos_wastes_tweaker_data.lua` — VMF widget groups `activate_dormant_boons_group` (9 checkboxes) and `skulls_event_boons_group` (1 checkbox) block-commented.
- `chaos_wastes_tweaker_data.lua` — `start_boon_dormant_group` builder block-commented in `build_start_tree()`. A starting-boon checkbox for an unregistered boon would silently no-op and mislead users.
- `chaos_wastes_tweaker_data.lua` — `ct_kill_heal` entry in BOON_TREE's health category line-commented.
- `chaos_wastes_tweaker_data.lua` — `SORT_GROUPS["start_boon_dormant_group"] = true` line-commented.
- `chaos_wastes_tweaker_localization.lua` — Block-commented: `display_name_ct_kill_heal` / `description_ct_kill_heal` / `disable_boon_ct_kill_heal*` / `start_boon_ct_kill_heal*`; `skulls_event_boons_group` / `enable_skulls_event_boons*`; `activate_dormant_boons_group` and all 9 `activate_dormant_<boon_id>` + `_tooltip` entries.
- `itemV2.cfg` — Title version suffix bumped: `v0.7.97-dev` → `v0.7.98-dev`.

### Boons removed from the game

Dormant boons (no longer registered in any lookup or pool):
- `squats`, `deus_larger_clip`, `deus_throw_speed_increase`
- `deus_ammo_pickup_give_allies_ammo`, `deus_coin_pickup_regen`
- `deus_large_ammo_pickup_infinite_ammo`, `deus_timed_block_free_shot`
- `deus_transmute_into_coins`, `explosive_pushes_on_damage_taken`

Mod-defined boon (no longer registered):
- `ct_kill_heal` (Khaine's Communion)

Skulls event boons (now stay behind the vanilla `skulls_2023` mutator gate, never roll outside the Skulls event):
- `boon_skulls_01..08` + `boon_skulls_set_bonus_01` + `boon_skulls_set_bonus_02`

### Peer-sync safety
Because every peer running v0.7.98-dev produces the same `NetworkLookup` contents (no names added beyond what other mod features already register), no `feedback_vt2_gated_registration_diverges` desync class can occur. The user is the host so all clients will re-sync against the same mod state once they update.

### Verification
1. Restart VT2 with the updated mod.
2. Run `/ct_regression_test` in keep — both new checks must PASS:
   - `dormant_boons_NOT_registered` — nil for PASS.
   - `dormant_boons_NOT_in_pool` — nil for PASS.
3. Start a CW run, open a shrine — none of the disabled boon names should appear in the offering.
4. Open a Chest of Trials — should no longer crash (the original symptom that triggered this change).
5. Mod load log line: `[ct] dormant boons disabled (v0.7.98-dev)` confirms the apply-site breadcrumb is firing.

### Re-enable instructions
Every block comment carries a `2026-05-23 v0.7.98-dev DISABLED` header with specific re-enable steps. Search the codebase for that string to find every commented block. Restore order:
1. `chaos_wastes_tweaker.lua` — populated `DORMANT_BOON_RARITY` table; apply-site calls; Skulls block; `ct_kill_heal` block; `sync_host_dependent_state` `sync_dormant_boons()` call; `on_setting_changed` branches; the 4 disabled regression checks.
2. `chaos_wastes_tweaker_data.lua` — VMF widget groups; `start_boon_dormant_group` builder; BOON_TREE `ct_kill_heal` entry; SORT_GROUPS entry.
3. `chaos_wastes_tweaker_localization.lua` — All commented locale keys.
4. Remove the two new `dormant_boons_NOT_*` regression checks (or invert their semantics).
5. Bump MOD_VERSION + itemV2.cfg suffix.

## 0.7.97-dev (2026-05-23) -- Block Outcast Engineer crafted bombs from world pickup spawns

### Why
User bug report 2026-05-23: "Bardin's Outcast Engineer bombs are appearing in the item spawns; those are his crafted bombs. They're not supposed to be there." The Outcast Engineer's bomb (`engineer_grenade_t1`) is a vanilla `Pickups.grenades` entry whose only legitimate path into inventory is the career's cooldown buff handing it out via `inventory_extension:add_equipment(slot_name, ItemMasterList["grenade_engineer"], ...)` (see `scripts/settings/dlcs/cog/buff_settings_cog.lua:232`). It is NOT meant to spawn on the ground, on racks, in chests, or via any other world-spawn path.

The ct adventure-injection broadening in v0.7.64 added `"grenades"` to `ADVENTURE_CATS` (the `_can_spawn` fallback that approves vanilla campaign pickups on injected adventure missions). That allow-list swept in EVERY entry of `Pickups.grenades`, including the engineer-only `engineer_grenade_t1`, so on a CW run with adventure injection the bomb could roll as a ground pickup for any character. Vanilla `_can_spawn` could also accidentally approve it if a spawner unit ever tagged `engineer_grenade_t1 = true` (unlikely but not blocked).

### Changed
- `chaos_wastes_tweaker.lua` — Added `_CAREER_EXCLUSIVE_PICKUPS_BLOCKLIST` constant near the top of the file (next to `BOMB_BOON_NAMES`) listing pickup names that must NEVER be world-spawned. Currently one entry: `engineer_grenade_t1` (Bardin Outcast Engineer's crafted bomb). Doc block explains the vanilla source-of-truth (`scripts/settings/equipment/pickups.lua:698`) and the career-grant path that is intentionally NOT routed through `PickupSystem._spawn_pickup` (so the denial doesn't break legitimate career mechanics).
- `chaos_wastes_tweaker.lua` — Modified the `PickupSystem._can_spawn` hook to apply the blocklist BEFORE vanilla's check and BEFORE the ct ADVENTURE_CATS allow-list. Denial is global (every level, every mechanism) since these names should never world-spawn anywhere.
- `chaos_wastes_tweaker.lua` — Added per-run denial telemetry (`_career_exclusive_denial_counts`, `_career_exclusive_logged_this_run`). Reset at the top of every `populate_pickups` hook entry. The denial path bumps the counter, and the first denial per name per run emits an apply-site `mod:info("[pickup] denied career-exclusive: <name>")` log line (rate-limited to once per name per run -- vanilla's spawn-roller polls each pickup name many times per level).
- `chaos_wastes_tweaker.lua` — Added `/verify_engineer_bombs` chat command per the verify-before-shipping doctrine. Prints the blocklist + each entry's per-run denial count + whether the name still exists in the live `Pickups` table.
- `chaos_wastes_tweaker.lua` — Added two `/ct_regression_test` checks:
  - `engineer_bombs_not_in_world_spawns` — asserts the expected blocklist names are in `_CAREER_EXCLUSIVE_PICKUPS_BLOCKLIST`. Source-pattern check; PASSes from the keep.
  - `engineer_bombs_present_in_vanilla_pickups` — asserts every blocklist name still exists somewhere in the global `Pickups` table (catches a vanilla rename that would silently make our denial path dead code).
- MOD_VERSION bumped: `0.7.96-dev` -> `0.7.97-dev`.

### Verification
1. Restart VT2 with the mod enabled.
2. From the keep, run `/ct_regression_test` -- `engineer_bombs_not_in_world_spawns` and `engineer_bombs_present_in_vanilla_pickups` should PASS.
3. Run `/verify_engineer_bombs` -- should print `engineer_grenade_t1 : denials_this_run=0, present_in_Pickups=true`.
4. Start a CW run on an injected adventure mission (any DLC mission, e.g. Magnus / Cemetery / Forest Ambush).
5. Play for a few minutes so spawn rolls accumulate. Open the keep again or `/verify_engineer_bombs` mid-run -- the denial count should be > 0 if `engineer_grenade_t1` ever rolled (it will, given the equal-weight grenade pool: previously visible as engineer bombs on the ground).
6. Confirm no engineer-style bombs (the cylindrical fragmentation-grenade model) appear as world pickups. Regular frag/fire grenades still spawn normally.
7. Pick Bardin Outcast Engineer and confirm his cooldown-grant bomb mechanic still works (he can still craft bombs via his career passive).

### Why this approach
- Constant blocklist at the top of the file (not embedded inside the hook) for visibility -- future career-exclusive pickups added to the blocklist are immediately discoverable, and the regression check's expected-list constant doubles as a one-line audit summary.
- Applied BEFORE the vanilla call to `func(self, spawner_unit, pickup_name)` so denial covers EVERY path -- not just the ct-broadened adventure fallback. Even if vanilla's per-spawner `Unit.get_data(spawner, "engineer_grenade_t1")` ever flipped true on some level, ct overrides.
- Per-run telemetry (counter + once-per-run log) instead of always-fail / count-every-call: the deny path fires many times per level for the same pickup name (each spawner polls the full grenade pool). Once-per-name-per-run is enough to surface the gate is working without spamming the log.
- The career grant path (`buff_settings_cog.lua:232` -> `inventory_extension:add_equipment`) does NOT go through `PickupSystem._spawn_pickup`, so this denial is surgical: only world-spawn paths are blocked, never the engineer's own bomb-crafting passive.

### Related career-exclusive items NOT blocked (informational; do not auto-fix without user direction)
Audited in vanilla `scripts/settings/equipment/pickups.lua` and `scripts/settings/dlcs/morris/morris_pickups_settings.lua`:
- `Pickups.special.bardin_survival_ale` -- Slayer/Ranger Veteran ale buff pickup. NOT in `ADVENTURE_CATS`, so ct's allow-list does NOT sweep it in. No fix needed.
- `Pickups.special.necromancer_ripped_soul` -- Necromancer-only orb (`can_pickup_orb` gates by `career_name == "bw_necromancer"`). Vanilla-gated, NOT in `ADVENTURE_CATS`. No fix needed.
- `Pickups.grenades.holy_hand_grenade` (Morris/CW deus pickup) -- legitimate CW world spawn, not career-exclusive (anyone in a CW run can pick it up). Already handled by `_pickup_unit_loadable` on injected-adventure levels where its unit isn't packaged. No change.

### References
- Vanilla source: `scripts/settings/equipment/pickups.lua:698` (`Pickups.grenades.engineer_grenade_t1`); `scripts/settings/dlcs/cog/buff_settings_cog.lua:232` (engineer's grant path via `add_equipment`).
- `reference_vt2_adventure_pack_spawning_compat.md` -- related context for the v0.7.78 `_pickup_unit_loadable` guard on Skittergate `holy_hand_grenade`.
- `feedback_vt2_verify_before_shipping.md` -- mandates apply-site log + verify command for behavior changes that wouldn't be obviously visible to the user.

## 0.7.96-dev (2026-05-23) — Miracle of Isha: lock in mutex single-select + verify command + regression checks

### Why
User bug report 2026-05-23: "The Miracle of Isha multiple choice doesn't work and neither of the options are titled. Both can be toggled on at the same time (at least in the GUI even if it has no effect)." All three symptoms were already addressed in the v0.7.81-v0.7.85 mutex-cluster rework that exists in current source — but the live deployed bundle was stale (or the user's machine had stale cached UI) and there was no regression gate locking in the canonical state, so a future accidental drop of the mutex declaration or the suppression hook would silently reintroduce all three symptoms with no test failing.

This release adds the missing belt-and-suspenders: (1) a flag the suppression-hook install path writes only on success, (2) a `/verify_isha` chat command that prints the current resolved mode + flag + per-title localization status, (3) three `/ct_regression_test` checks that fail loud if the mutex cluster, the localization keys, or the suppression hook ever go missing.

### Changed
- `chaos_wastes_tweaker.lua` — Added `_G.__ct_isha_suppression_hook_installed` flag. Initialized `false` immediately before the `MutatorTemplates.blessing_of_isha.server.start_function` hook block; set to `true` only on the success branch (template loaded + hook attached). Also: apply-site `mod:info("[isha] mode=%s, applying alternative ...")` log line per the verify-before-shipping doctrine.
- `chaos_wastes_tweaker.lua` — Added `/verify_isha` chat command. Prints MOD_VERSION header, resolved mode (`_get_isha_mode()`), both raw toggle values, the mutex `active("isha_choice")` member, hook-install state, and per-title localization resolution (echoes `OK` if `mod:localize(key) ~= key` else `MISSING`). Surfaces a WARN line if both toggles happen to read true at the same time (mutex enforcer should have prevented; aegis-preference still resolves deterministically in `_get_isha_mode`).
- `chaos_wastes_tweaker.lua` — Three new `/ct_regression_test` checks (appended to the test scaffold near end of file):
  - `miracle_of_isha_choice_widget_is_dropdown` — verifies mutex cluster `isha_choice` is declared with exactly `{tweak_miracle_of_isha_aegis, tweak_miracle_of_isha_wounds}` members. Failure means the radio-style single-select degraded back to independent checkboxes.
  - `miracle_of_isha_titles_present` — verifies all four localization keys (`tweak_miracle_of_isha_aegis`/`_tooltip`, `tweak_miracle_of_isha_wounds`/`_tooltip`) resolve via `mod:localize` to non-empty strings that are not just the key echoed back.
  - `miracle_of_isha_hook_installed` — verifies `_G.__ct_isha_suppression_hook_installed == true`, which is set only when the vanilla revive mutator's `server.start_function` was hookable at mod init.
- `MOD_VERSION` bumped: `0.7.95-dev` → `0.7.96-dev`.

### Verification
1. Restart VT2 with the mod enabled.
2. Run `/ct_regression_test` — three new checks `miracle_of_isha_choice_widget_is_dropdown`, `miracle_of_isha_titles_present`, `miracle_of_isha_hook_installed` should all PASS.
3. Run `/verify_isha` — should print resolved mode (vanilla / aegis / wounds), both raw toggle values, hook installed=true, and `aegis title: (A) Aegis: ... (OK)` / `wounds title: (B) Unlimited Wounds: ... (OK)`.
4. Open VMF settings → Reworks → Boons. The two Isha rows should show their full titles ("(A) Aegis: -25% damage taken for the rest of the run" and "(B) Unlimited Wounds: recruit-style, every knockdown revivable"). Toggling one ON should programmatically toggle the other OFF.
5. Start a CW run, reach the blessing shrine, purchase Blessing of Isha. Console should print `[isha] mode=<aegis|wounds>, applying alternative (vanilla mutator neutralized at server.start_function)`. If a teammate goes down, vanilla's revive-everyone-once mutator does NOT fire (Aegis: the -25% buff is already active; Wounds: knockdown becomes revivable instead of instakill).

### References
- `LOCALIZATION_STANDARD.md` § 10 — Mutex cluster pattern (the canonical (A) / (B) checkbox + leading-4-space indent label convention).
- `feedback_vt2_mutator_template_server_wrap.md` — hook `template.server.start_function`, not the dead `template.server_start_function` field.
- `feedback_vt2_verify_before_shipping.md` — apply-site log + chat verify command convention.

## 0.7.95-dev (2026-05-23) — Starting Coins: rewrite as SETTER (not adder); fix 300-setting-gives-500 bug

### Why
User report 2026-05-23: "We got an extra 200 coins even though we had the setting for starting at 300 we got 500 somehow." Root cause: the prior implementation (`mod:hook_safe("DeusRunController", "setup_run", ...)`) ran AFTER vanilla's `set_player_soft_currency(own_peer_id, REAL_PLAYER_LOCAL_ID, initial_own_soft_currency)` had already written the rolled-over coins (`~0-200` from prior run's `get_rolled_over_soft_currency()`). The mod then re-entered `on_soft_currency_picked_up(starting)` which ADDED the setting on top. Vanilla 200 + setting 300 = displayed 500.

### What changed (setter, not adder)
- `chaos_wastes_tweaker.lua` — Added full `mod:hook("DeusRunController", "setup_run", ...)` that intercepts vanilla's `initial_own_soft_currency` argument (arg[5]) and REWRITES it to the user's snapped `starting_coins` setting BEFORE vanilla executes. Vanilla's setter then writes exactly the setting value — no addition, no double-grant. Setting=0 leaves vanilla rolled-over behavior intact.
- `chaos_wastes_tweaker.lua` — Added host-side `mod:hook("DeusRunController", "rpc_deus_set_initial_soft_currency", ...)` that overrides the incoming `initial_own_soft_currency` from a joining client with the host's own setting. Keeps the "host controls economy" invariant (precedent across `coin_multiplier` / shrine multipliers).
- `chaos_wastes_tweaker.lua` — Removed the old adder block from the `hook_safe(setup_run)` body (`granting_starting_coins = true; self:on_soft_currency_picked_up(starting); granting_starting_coins = false`). The remaining `hook_safe` body now only carries the host-side settings broadcast.
- `chaos_wastes_tweaker.lua` — Added per-run idempotence flag `_starting_coins_applied_for_run` keyed off `DeusRunState:get_run_id()` to defend against host-migration replay or debug re-runs of `setup_run`. Belt-and-suspenders per `feedback_redundant_safeguards_ok.md`.
- `chaos_wastes_tweaker.lua` — Added `STARTING_COINS_MODE_MARKER = "starting_coins:setter-override-via-setup_run-arg"` embedded in the compiled bundle so the source-pattern regression check (below) can verify the setter mode shipped.
- `chaos_wastes_tweaker.lua` — Added `[ct/coins]` log lines at both apply sites: `starting_coins setter applied: vanilla_initial=X, setting=Y, final=Y (run_id=Z)` on the local setup_run hook, and `host RPC override for joining peer: client_sent=X, host_setting=Y` on the RPC handler.
- `chaos_wastes_tweaker.lua` — Added two regression checks:
  - `starting_coins_setter_not_adder` (source-pattern): asserts `STARTING_COINS_MODE_MARKER == "starting_coins:setter-override-via-setup_run-arg"`. Catches a future refactor that accidentally reverts to adder mode.
  - `starting_coins_value_matches_setting` (runtime): when a CW run is active AND `_starting_coins_applied_for_run` matches the live `run_id`, asserts `get_player_soft_currency(own_peer_id) == snapped_setting`. Gives PASS when not applicable (no run / setting=0) instead of false-positive FAIL.
- `chaos_wastes_tweaker.lua` — Added `/verify_coins` chat command: prints the current coin balance, the snapped setting, whether the override-hook marker is present, and host/client status. Use during a fresh CW run to confirm the value applied.

### Per-peer scoping (design call)
Host's setting wins. The local `setup_run` hook reads via `effective_setting("starting_coins")` (host-broadcast value on clients, own value on host), so both peers compute the same target. The host-side `rpc_deus_set_initial_soft_currency` hook ALSO enforces the host's setting on the value written for the joining client's row — belt-and-suspenders for the case where a hot-joiner's broadcast hasn't landed by the time their RPC fires.

### Verification
1. Restart VT2 with the mod enabled.
2. Run `/ct_regression_test` from the keep — `starting_coins_setter_not_adder` should PASS (the runtime check is N/A in keep).
3. In the VMF menu, set **Starting Coins** to `300`.
4. Start a fresh CW run.
5. After Olesya intro, run `/verify_coins` — should show `setting=300, live=300` (or whatever the snapped value is). Also check the log: a single `[ct/coins] starting_coins setter applied: vanilla_initial=<X>, setting=300, final=300 (run_id=<...>)` line.
6. Run `/ct_regression_test` while in the run — `starting_coins_value_matches_setting` should PASS.
7. Negative test: set Starting Coins to `0`, start another fresh CW run. `/verify_coins` should show vanilla behavior (`live=<rolled-over>` — non-zero only if you carried coins over from a prior run).

### References
- `feedback_redundant_safeguards_ok.md` — belt-and-suspenders for silent-fail surfaces.
- `feedback_vt2_verify_before_shipping.md` — every gated feature ships with a `/verify_*` chat command.
- Vanilla source: `scripts/managers/game_mode/mechanisms/deus_run_controller.lua:273` (setup_run signature), `:315` (host setter), `:350-384` (rpc_deus_set_initial_soft_currency host-side handler), `scripts/managers/game_mode/mechanisms/deus_mechanism.lua:1198` (setup_run call site — passes `rolled_over_coins`).

## 0.7.93-dev (2026-05-23) — Skulls Event Boons: rewrite year-round injection to actually work

### Why
The v0.7.85 "Enable Skulls Event Boons (any time)" toggle was a no-op. It appended new entries to `DeusPowerUpRarityPool` at mod load — but `DeusPowerUpRarityPool` is read ONCE at game boot to populate the runtime arrays the offering generator actually scans (`DeusPowerUps[rarity]`, `DeusPowerUpsArray`, `DeusPowerUpsArrayByRarity[rarity]`, `DeusPowerUpsLookup` — see `scripts/settings/dlcs/morris/deus_power_up_settings.lua:7121-7176`). Post-boot writes to the source pool never reach the arrays scanned by `deus_power_up_utils.lua:138-146`. Verified by tracing the offering generator and confirming Skulls boons never rolled outside the Skulls 2023 mutator regardless of toggle state.

### Changed
- `chaos_wastes_tweaker.lua` — Replaced `_add_skulls_to_pool` / `_remove_skulls_from_pool` (which wrote into the unused `DeusPowerUpRarityPool`) with a runtime mutator-clear approach on the live `DeusPowerUps.event[boon_skulls_*]` records. The offering roller at `deus_power_up_utils.lua:146` calls `compatible_mutator_active(power_up.mutators)` on each record's `mutators` field — clearing that field from `{"skulls_2023"}` to `{}` makes the boon roll on any CW run. Toggle-off restores the cached original array.
- `chaos_wastes_tweaker.lua` — Added `pre_register_skulls_event_lookups()` that unconditionally walks the 10 Skulls boons in sorted order at mod load. Re-registers `NetworkLookup.deus_power_up_templates` + `NetworkLookup.buff_templates` entries (idempotent overlay on vanilla's boot-time registration) and mirrors each `power_up_boon_skulls_<NN>_event` buff template from `DeusPowerUpBuffTemplates` into `_G.BuffTemplates` per `feedback_vt2_dormant_buff_template_dual_register`. Defensive against a future vanilla change that defers the DLCUtils merge.
- `chaos_wastes_tweaker.lua` — Added `skulls_boons_preregistered` regression check to `/ct_regression_test`. Walks the 10 boon names, verifies each present-in-this-build template has its NetworkLookup + BuffTemplates registration.
- `chaos_wastes_tweaker_localization.lua` — Rewrote `enable_skulls_event_boons_tooltip` to reflect the mutator-clear approach (not the old broken pool-append wording). Tooltip now warns boons 06/07/08 are inert outside the Skulls mutator (they trigger on daemon-skull pickups + read `skulls_2023_buff` stacks). Boons 01-05 + set bonuses are fully functional outside the event.
- `itemV2.cfg` — Title version suffix bumped: `v0.7.92-dev` → `v0.7.93-dev`.
- `MOD_VERSION` bumped: `0.7.92-dev` → `0.7.93-dev`.

### Why this approach over re-running `inject_dormant_boon`
The 9 ct dormants + 11 trait boons go through `inject_dormant_boon` because they have no vanilla pool entry — we have to BUILD one. The Skulls boons already have full vanilla infrastructure (template, buff variant `power_up_boon_skulls_01_event`, NetworkLookup entries, `DeusPowerUpsArray` slot, etc.). Calling `inject_dormant_boon` for them would duplicate every record in `DeusPowerUpsArray` / `DeusPowerUpsArrayByRarity` / `DeusPowerUpsLookup` and require keeping the duplicated buff-name registration in sync with the vanilla one. The mutator-clear approach preserves the vanilla `power_up_boon_skulls_set_bonus_01_event` linkage that vanilla's set-bonus amplifier closures hard-code in `deus_power_up_settings.lua:462/487/516/...` — meaning the 5-piece set bonus actually works as designed.

### Set-bonus mechanics — verified intact
Vanilla's set-bonus amplifier code (e.g. `deus_power_up_settings.lua:462`) hard-codes the buff name `power_up_boon_skulls_set_bonus_01_event`. Because we keep the boons at their vanilla "event" rarity (not injecting a new rarity copy), the buff names stay vanilla and the amplifier logic continues to detect set completion correctly. Collecting all 5 of `boon_skulls_01..05` triggers `boon_skulls_set_bonus_01` (`+effect_amplify_amount` boost to attack-speed-per-stack, on-proc multipliers, etc.). Collecting all of `boon_skulls_06..08` triggers `boon_skulls_set_bonus_02` similarly.

### Peer-sync safety
- Pre-registration is unconditional + sorted per `feedback_vt2_gated_registration_diverges` — every peer's NetworkLookup ends up with identical contents regardless of toggle state.
- Mutator-field mutation does NOT affect NetworkLookup indices (only the in-table semantics of each record). Each peer can have different toggle states without crashing — the host's roll output is what gets sent over the wire (`rpc_add_power_up` resolves by `lookup_id`, which stays the same vanilla-assigned id).
- The 2025 boons (06/07/08 + set_bonus_02) early-out cleanly if the vanilla template is missing in older builds — both pre-register and mutator-clear loops nil-check before touching.

### Verification
1. Restart VT2 with the mod enabled.
2. Run `/ct_regression_test` — `skulls_boons_preregistered` should PASS.
3. Toggle **Enable Skulls Event Boons (any time)** ON in the VMF menu.
4. Start a fresh CW run with no Skulls mutator active.
5. Visit a shrine and inspect the offered boons. Skulls boons (recognisable by the daemon-skull icons and `boon_skulls_*` localization keys) should appear in the rotation at "event" rarity.
6. Toggle the setting OFF, return to keep, start another fresh run. Skulls boons should NOT appear.
7. Optional: with toggle ON, intentionally collect 5 of `boon_skulls_01..05` in a single run and verify `boon_skulls_set_bonus_01` activates (boon icon appears in the buff bar; per-stack attack-speed boost is visibly higher).

### Boons covered (rarity: "event" — vanilla-assigned, preserved by this mod)
- `boon_skulls_01` — Frenzied Hacks: on melee hit, stack +N% attack speed. Functional.
- `boon_skulls_02` — Slaughterer's Vigour: on kill, stack +N% power level. Functional.
- `boon_skulls_03` — Crimson Parry: timed-block triggers a stagger explosion. Functional.
- `boon_skulls_04` — Bloodletter's Reservoir: on melee hit, gain THP that converts to a regen proc. Functional.
- `boon_skulls_05` — Wrathful Surge: on melee hit, stack +N% power level. Functional.
- `boon_skulls_06` — Skull-Bound Power: +N% power per `skulls_2023_buff` stack. **Inert outside the Skulls mutator** (no daemon-skull pickups → 0 stacks).
- `boon_skulls_07` — Skull Coin Bounty: daemon-skull pickup grants coins. **Inert outside the Skulls mutator.**
- `boon_skulls_08` — Skull-Bound Cooldown: daemon-skull pickup reduces career skill cooldown. **Inert outside the Skulls mutator.**
- `boon_skulls_set_bonus_01` — Khorne's Favor (5-piece set of 01-05): amplifies effect + duration of all collected set pieces. Functional outside the event.
- `boon_skulls_set_bonus_02` — Khorne's Wrath (3-piece set of 06-08): amplifies effect + duration. **Inert outside the Skulls mutator** (depends on inert source boons).

### References
- `feedback_vt2_gated_registration_diverges` — pre-register unconditionally in sorted order; gate only the pool side.
- `feedback_vt2_dormant_buff_template_dual_register` — dual-write to `DeusPowerUpBuffTemplates` AND `_G.BuffTemplates`.
- `reference_vt2_deus_power_up_rarities` — valid rarities are `event/rare/exotic/unique`. Reusing vanilla "event" rarity avoids "common"/"plentiful" crash risk.
- Vanilla source: `scripts/settings/dlcs/morris/deus_power_up_settings.lua:3069-3362` (boon templates), `:7121-7176` (boot bootstrap), `scripts/helpers/deus_power_up_utils.lua:138-146` (offering roller).

## 0.7.92-dev (2026-05-23) — Migrate Reckless Swings tweak from positional indices to name-based lookup

### Why
GitHub Issue #5: the Khaine's Fury (deus_reckless_swings) boon tweak used hard-coded array indices (`buffs[1]`, `description_values[1]`, `description_values[3]`) to mutate values. v0.7.84 added sanity guards that bail safely if FatShark reorders the arrays, making the tweak safe-but-disabled rather than safe-and-working. This refactor replaces positional indexing with name-based search so the tweak works regardless of array order.

### Changed
- `chaos_wastes_tweaker.lua` — Added `_find_entry_by(arr, predicate)` helper function for array searching.
- `apply_reckless_swings_tweak()` — Now uses `_find_entry_by` to locate:
  - `buff_template.buffs[N]` where `buff_to_add == "deus_reckless_swings_buff"`
  - `description_values[N]` where `value_type == "percent"` (threshold)
  - `description_values[N]` where `value_type == "amount"` (damage)
  - Stored indices in `reckless_swings_originals` table for use in revert.
  - Sanity guards retained as defense-in-depth (name-match + numeric-type checks before mutation).
- `revert_reckless_swings_tweak()` — Now restores using stored indices instead of hard-coded `[1]` and `[3]`.
- Inline comment updated: Issue #5 marked resolved in v0.7.92-dev.
- Logging enhanced: `apply` now reports found indices (`buff_index`, `dv_threshold_index`, `dv_damage_index`) to aide verification.
- MOD_VERSION bumped: 0.7.91-dev → 0.7.92-dev.

### Verification
1. Restart VT2 with the mod enabled.
2. Enter Chaos Wastes and enable the **Khaine's Fury Softened** toggle.
3. Check console logs for: `[khaines-fury] tweak applied via name-based lookup (buff_index=1, dv_threshold_index=1, dv_damage_index=3)` (or equivalent indices if FatShark reorders).
4. Pick the Khaine's Fury deus boon and verify:
   - Health trigger threshold shown in tooltip: 25% (not 50%)
   - Damage per hit shown: 1 (not 3)
   - In-game behaviour: taking damage at <25% health, dealing 1 damage per hit (not 3)
5. Disable the toggle and re-enable to verify revert path restores vanilla values.
6. Run `/ct_regression_test` and verify no new assertion failures.

### References
GitHub Issue #5: https://github.com/Ensrick/vermintide-2-tweaker/issues/5

### Verification (back-filled 2026-05-23 in v0.7.103-dev per PROJECT_STANDARDS §15)
Automated regression check `reckless_swings_name_based_lookup` added in v0.7.103. Run via `/ct_regression_test`.

## 0.7.91-dev (2026-05-23) — Namespace `regression_test` chat command to avoid cross-mod collision

### Why
Seven mods registered `mod:command("regression_test", ...)`. VT2 chat commands are global — only the first mod wins, the rest fail silently with `[ERROR] (command): command name 'regression_test' is already used by another mod 'cim'`. Detected in PC-A log 2026-05-23 20:50:52.

### Changed
- `chaos_wastes_tweaker.lua` — renamed `regression_test` → `ct_regression_test`. Verification log line added at registration site.

### Verification
1. Restart VT2. No `[ERROR] (command):` line in console_logs about this command name.
2. Run `/ct_regression_test` in chat. Command fires and prints results.
3. Per memory `feedback_vt2_verify_before_shipping.md`.

## 0.7.80-alpha (2026-05-20)

### Fixed: ct_meta_ammo (Quiver Cascade) crashed Sienna + Bardin drakefire users with `Max overcharge outside value bounds allowed by network variable!`

Two crash reports from a co-op session (host Sienna + Bardin drakefire client) both hit the same fassert at `player_unit_overcharge_extension.lua:110`:

```
fassert(max_value >= NetworkConstants.max_overcharge.min and max_value <= NetworkConstants.max_overcharge.max, "Max overcharge outside value bounds allowed by network variable!")
```

The crash locals showed `original_max_value = 40, max_value = 64` — Sienna staff buffed from 40 → 64 by twelve stacks of ct_meta_ammo's `+5% max_overcharge` per active boon (12 × 5% = +60%). The network variable bound is ~60 (vanilla designed it around Sienna Scholar's +50% talent: 40 base × 1.5 = 60 exactly). ANY value beyond ~60 crashes both host and husk on the per-frame `update()` call.

The bound lives in the compiled engine `.network_config` binary and is NOT widenable from Lua — `NetworkConstants.max_overcharge` is a read-only snapshot from `Network.type_info` at boot, and the transport layer (`GameSession.set_game_object_field` for `overcharge_max_value`) uses the engine's own type-info, not the Lua table. Even monkey-patching the Lua side wouldn't fix husk reads.

Fix: replaced the `{ stat_buff = "max_overcharge", multiplier = 0.05 }` entry with `{ stat_buff = "reduced_overcharge", multiplier = -0.05 }`. The new stat_buff reduces overcharge GENERATED per cast (consumed locally inside the ActionThrowProjectile / overcharge add paths — not network-synced as a max value), so the gameplay effect is "you cast more spells before overheating," equivalent to a bigger bar. Zero crash risk regardless of boon count, no Scholar talent conflict, works for any weapon with overcharge mechanics (including ones without a max_value field where the prior buff was inert).

Per-cast math: at N boons, heat per cast = `1 + N × -0.05 = 1 - 0.05N` of normal. At 12 boons: 40% heat per cast = 2.5x effective casts before hitting the cap. Stronger than the original "+60% bar" intent (1.6x more casts) but the only stable alternative; users can mentally treat it as the same "more comfortable casting" benefit.

Also removed the now-pointless `_calculate_and_set_buffed_max_overcharge_values` call from `ct_meta_ammo_refresh_capacity` since we no longer buff max_overcharge — eliminates the only ct code path that could ever drive a max_overcharge bounds crash even if another mod adds `max_overcharge` on top of Scholar talent.

Localization updated: tooltips + description now say "-5% overheat per cast" (and explain the equivalence to bigger heat bar) instead of "+5% max overheat."

Confirmed via crash-log scan: not a stacking-math bug — vanilla `stacking_multiplier` math (sum of per-stack multipliers, applied once as `value × (1 + sum)`) produced the exact 64 value. No compounding, no inflated boon count. Just the literal +60% multiplied 40, exceeding the engine cap.

## 0.7.79-alpha (2026-05-20)

### Fixed: VMF crashify exception in `tweak_belakor_temple_unique_boons_tooltip`

The tooltip text contained `"a 14% chance per slot"` — VMF's `localize` runs every string through `string.format`, so the literal `%` was interpreted as a format specifier and triggered `<<crashify-exception>>` every time the options UI initialised. Escaped as `14%%`. Visible symptom was an empty crash dialog on game exit aggregating the queued telemetry events.

## 0.7.78-alpha (2026-05-20)

### Fixed: Engine fatal `Unit not found pup_holy_hand_grenade_01_t1` on adventure-injected levels

Symptom: hard crash on level start (most reliably `dlc_dwarf_whaling` / Skittergate, but every adventure-injected mission was exposed) with engine assertion `world.resource_manager().can_get(unit_type, unit_name)` failed for `units/weapons/player/pup_grenades/pup_holy_hand_grenade_01_t1`. Lua stack: `PickupSystem._spawn_spread_pickups` → `_spawn_pickup` → `World.spawn_unit`.

Root cause: v0.7.64 broadened `_can_spawn` to allow vanilla campaign pickup categories (`ammo`, `healing`, `grenades`, …) on adventure-injected levels, fixing the v0.7.63 regression where Holly DLC missions spawned nothing. Side effect: vanilla's `grenades` bucket includes `holy_hand_grenade` (Morgrim's Bomb), whose pickup unit is only loaded by Morris/CW mission packages. On adventure-injected levels that asset is absent from the resource manager, so when RNG rolled it the engine fataled inside `World.spawn_unit`.

Fix: gate every `return true` in the `_can_spawn` hook on `Application.can_get("unit", settings.unit_name)`. Unloadable pickups soft-veto (empty spawner spot, same as if vanilla's gate had returned false) instead of crashing. Same guard applied to the deus_potions / deus_soft_currency / deus_weapon_chest paths as belt-and-suspenders (`feedback_redundant_safeguards_ok`); those entries are CW-packaged and should always pass, but the redundant check is free.

## 0.7.77-alpha (2026-05-20)

### Fixed: VMF "Attempting to rehook active hook" warning on `generate_random_power_ups`

Two separate `mod:hook("DeusPowerUpUtils", "generate_random_power_ups", ...)` blocks existed in ct — one for count override + disabled-boon enforcement + bomb-boon exclusivity (line ~783, original), one for Belakor-temple force-unique-rarity (was line ~1387). VMF allows mod:hook chaining ACROSS mods but warns when the SAME mod re-hooks the same Class+method; the second hook triggered the warning on every mod load.

Fix: consolidated the Belakor force-rarity logic into the original hook's body. Reads `args[6]` (availability_type) and `args[8]` (forced_rarity) positionally — same vanilla signature both hooks were already targeting. Semantics unchanged; one VMF hook registration instead of two.

## 0.7.76-alpha (2026-05-20)

### Added: Shared Blessings — Bots Mirror Host's Boons (toggle, default OFF)

New checkbox under Reworks → Boons: **Shared Blessings: Bots Mirror Host's Boons** (default OFF).

When enabled, every boon the lobby's heroes gain in Chaos Wastes is also granted to every bot in the warband. Covers all sources — shrine picks, altar rewards, dormant reveals, Belakor's Temple, blessings of the gods, set completions, and end-of-level grants — because every CW boon application funnels through the single canonical entry point `DeusRunController.add_power_ups` (`deus_run_controller.lua:1126`).

**Implementation:**
- `hook_safe` on `DeusRunController.add_power_ups`. When the toggle is on and the receiving player is a HUMAN on the HOST (`_run_state:is_server()`), iterate `Managers.player:human_and_bot_players()`, clone the power-up list with fresh `client_id`s per bot, and re-call `add_power_ups(cloned, bot:local_player_id(), false)` for each. `present=false` so the reward popup doesn't fire for bot grants.
- Reentry guard `_ct_bot_mirror_active` prevents infinite recursion when our mirror invocation re-enters the hook. Set rewards triggered inside a host-side `add_power_ups` (via `_check_set_completed`) also mirror naturally because the flag is only set during the inner bot iteration loop.
- Bots are entirely client-side on the host — remote peers see bots as husk units and receive their buffs via the standard server-authoritative buff_system RPC chain. So mirroring runs only on host.
- Talent-style boons (the ones with `power_up.talent = true`) are routed by vanilla `activate_deus_power_up` through `deus_backend:set_deus_talent_ids` for the receiving career — works on bot careers identically, the talent slot is written into each bot's own talent set.

**Limits / known edge cases:**
- Mid-run bot career swaps (rare) won't re-grant historical boons. Workaround: toggle the bot off and back on.
- The `present` reward popup is suppressed for bots by design (would spam the host's UI with N popups for N bots).

Per `feedback_vt2_gated_registration_diverges.md` — this is a roll-time mirror, NOT a registration-time gate. `DeusPowerUps` table indices remain identical across peers regardless of toggle state.

Localization carries Warhammer flavor: "the heroes' fortunes are bound to the Lords of the Old World" framing in the tooltip.

### Added: Khorne's Champions Banlist — Per-Mark Toggles (defaults all OFF)

New nested menu under Curses: **Khorne's Champions Banlist (Boss Enhancements)** with 13 checkboxes — one per Boss Grudge Mark. Banned marks are excluded from monster-boss enhancement rolls.

**The 13 marks (per `BossGrudgeMarks` in `grudge_mark_settings.lua:127-140`):**
Commander, Crippling Blow, Crushing Blow, Frenzy, Intangible, Periodic Curse Aura, Periodic Shield, Raging, Ranged Immune, Regenerating, Unstaggerable, Vampiric, Warping.

**Implementation:**
- `mod:hook` on `TerrorEventUtils.add_enhancements_for_difficulty` (`terror_event_utils.lua:191`). When the caller passes `enhancement_set = nil` or `enhancement_set = BossGrudgeMarks`, swap in a filtered copy that omits banned marks. Other callers (termite / dwarf-fest event variants with their own enhancement sets) pass through untouched.
- The filter only builds when at least one mark is banned (nothing-banned → return nil → vanilla code path). Empty-set fallback is safe: `generate_enhanced_breed` iterates the set into a candidate list; an empty list yields no enhancements, but the `BreedEnhancements.base` health/damage block is always appended regardless.
- Server-only — boss enhancement assignment is server-authoritative at spawn time. Clients receive the chosen enhancements via the spawn data envelope.

**Display name resolution:**
- Display strings live in compiled localization data, not lua source — internal names map to loc keys via the `display_name` field on each `BreedEnhancements` entry.
- At mod load, `_resolve_grudge_mark_display_name` walks the 13 marks and caches `Localize(display_name_<n>)` results into `mod._ct_grudge_mark_display`. Fallback to title-cased internal name if Localize isn't ready or the key is missing.
- Companion command `/dump_grudge_marks` prints the 13 internal→key→resolved-display mappings to the log for verification.

Per `feedback_vt2_gated_registration_diverges.md` — boss enhancements are not registered into a network-indexed table; the filter operates on the per-spawn random pool. No registration divergence risk.

## 0.7.75-alpha (2026-05-20)

### Added: Belakor's Temple — Reward Unique Boons (toggle, default ON)

New checkbox under Reworks → Boons: **Belakor's Temple: Reward Unique Boons** (default ON).

The Belakor arena node (the SIG zone on the Wastes map) rewards a cursed chest on completion. Vanilla `weight_by_rarity` for cursed chests is `{ event=6, exotic=3, rare=6, unique=1 }` (`deus_power_up_settings.lua:14-19`) — only a ~6% chance per slot of rolling a unique even though the temple is the prestige reward in lore.

With this toggle on, the cursed-chest roll AT THE BELAKOR TEMPLE NODE ONLY forces `forced_rarity = "unique"` via `DeusPowerUpUtils.generate_random_power_ups`. Vanilla's `forced_rarity` parameter already implements the requested fallback semantics — if the unique pool is exhausted (every unique already collected), it walks down through exotic → rare → event automatically (`deus_power_up_utils.lua:192-215`). Other cursed chests / weapon chests / shrines retain vanilla rarity weights — the override is local to the Belakor-temple call only, no global `weight_by_rarity` mutation.

Conditions:
- Toggle on.
- `availability_type == DeusPowerUpAvailabilityTypes.cursed_chest`.
- Current node = `_run_state:get_arena_belakor_node()` (the Belakor arena node, queryable per-peer at boon-roll time).

Per-peer note: each peer rolls its own seed when opening the chest (`deus_cursed_chest_view.lua:58` uses position-derived hash), so the hook runs on every player's machine independently. The boon CHOICE isn't network-sync'd; only the resulting `add_power_up` RPC is, so per-peer override is consistent.

Per `feedback_vt2_gated_registration_diverges.md`: this is a gate-at-roll-time override (not registration-time), so DeusPowerUps array indices remain identical across peers regardless of toggle state.

## 0.7.74-alpha (2026-05-20)

### Added: Myrmidia's Wildfire — Generations Cap slider

New numeric slider under Reworks → Boons: **Myrmidia's Wildfire: Generations Cap** (range 1-10, default 3).

Caps how deep the Wildfire fire-spread chain can propagate. Each spread DoT carries a generation tag — the player's own burn is generation 0, the first spread is 1, the second 2, and so on. When a burning enemy dies, the spread proc fires only if the source's generation is below the cap. Default 3 keeps the boon's chain useful for clearing small groups while preventing the runaway hallway-of-fire cascades that emerge against dense hordes.

**Tradeoffs surfaced via the tooltip:**
- Cap = 1: only the player's own burnt enemies trigger a spread; spread targets never re-spread.
- Cap = 3 (default): up to two re-spreads from a single seed kill.
- Cap = 10: near-uncapped, vanilla-like behavior but with an upper bound to keep mass-burning enemy groups from softlocking the spread loop.

Implementation: generation tracking lives on a weak-keyed `_ct_wildfire_generation` table inside the same `ProcFunctions.boon_dot_burning_01_spread` hook added in v0.7.73 for color matching. When a neighbor is tagged via `DamageUtils.apply_dot`, we record `new_gen = src_gen + 1` against the neighbor unit so the next death reads it back. Weak references mean tags die with the unit and no leak occurs across runs.

Per `feedback_vt2_gated_registration_diverges.md` — the slider is read at proc time (not at boon registration time), so peer indices remain identical regardless of cap value.

Host-authoritative because `boon_dot_burning_01_spread` is registered with `authority = "server"` in vanilla — only the server-side hook fires the spread loop.

## 0.7.73-alpha (2026-05-20)

### Reworked: Myrmidia's Wildfire spread DoT color matches the source burn

The boon `boon_dot_burning_01` (Myrmidia's Wildfire) propagates a fire DoT to nearby enemies when a burning target dies. Vanilla's `boon_dot_burning_01_spread` (`morris_buff_settings.lua:3714`) hardcodes the spread template as `boon_career_ability_burning_aoe` — regardless of what burn source actually killed the target.

ct now hooks the proc and picks the spread template from the dying enemy's active burn status effect:

- **Sister of the Thorn — Moonfire Bow** (`burning_elven_magic`) → spreads as blue flame via `we_deus_01_dot_fast`.
- **Sienna Necromancer balefire** (`burning_balefire`) → spreads as purple flame via the auto-generated `boon_career_ability_burning_aoe_balefire` (vanilla's `BalefireBurnDotLookup` builds this variant at boot via `buff_utils.lua:267`).
- **Warp-flame** (chaos sorcerer / `burning_warpfire`) → keeps vanilla Myrmidia orange — the boon is the player's own fire, not warp-corruption.
- **Vanilla burn** (`burning`) → unchanged, vanilla orange.

Hook target is `ProcFunctions.boon_dot_burning_01_spread` (same merged table as Manann's Tempest's `chain_lightning` — buff_func entries live in `dlc_settings.morris.proc_functions` and merge into the global `ProcFunctions` at boot). Implementation re-walks the vanilla spread loop with `buff.cached_custom_dot.dot_template_name` overwritten per call so each death picks its own color without leaking the previous kill's choice.

This is the contract surface for v0.7.74's generation-cap slider (planned next).

## 0.7.72-alpha (2026-05-20)

### Reworked: Quiver Cascade also extends max overheat and Moonfire energy

The `ct_meta_ammo` boon ("Quiver Cascade") previously granted only +5% total ammo per active boon. Per-stack it now also grants:

- **+5% max overheat** via `stat_buff = "max_overcharge"`. Covers Sienna's staves (firebolt, beam, conflag, fireball, geiser) and Bardin's drakefire weapons (drakegun + brace of drake pistols) — both use `PlayerUnitOverchargeExtension`, which reads `max_overcharge` at `_calculate_and_set_buffed_max_overcharge_values` (`player_unit_overcharge_extension.lua:108`).
- **+5% max Moonfire Bow energy** via a runtime hook on `PlayerUnitEnergyExtension._max_energy`. Vanilla's energy system has NO buff path (`apply_buffs_to_value` is never called on max), so we mutate `_max_energy` directly and scale `_energy` proportionally to keep the fill fraction stable. Base value is stashed at first touch and rescaled relative to live boon count.

The prior vanilla `apply_buff_func = "refresh_ranged_slot_buffs"` only refreshed `ammo_extension:refresh_buffs()`. It's replaced by a custom `ct_meta_ammo_refresh_capacity` that does ammo + overcharge recalc + Moonfire-energy rescale in one pass, so all three caps update live on each boon grant — no weapon swap required.

Localization, dropdown tooltips, and the on-boon-card description updated to reflect the extended coverage. Inertness now only applies on the (unlikely) loadout with no ranged weapon at all — every CW career has a ranged slot by default, so this remains theoretical.

Memory cleanup: prior memory file `reference_vt2_max_overheat_modifier_unified.md` was hallucinated. The correct stat_buff key is `max_overcharge` (verified against `buff_templates.lua:109`), not `max_overheat_modifier` (which exists nowhere in the source). Memory rewritten with verified facts.

## 0.7.71-alpha (2026-05-20)

### Added: Ulric's Pack — Unlimited Aura Range toggle

New checkbox under Reworks → Boons. Vanilla `wolfpack` boon's proximity buff has `range_check.radius = 20` (`deus_power_up_settings.lua:3829-3835`); when enabled, the field is set to `math.huge` so the pack's power bonus stacks regardless of how far apart the heroes have spread. `BuffAreaHelper.update_range_check` re-reads the radius every tick (`buff_area_helper.lua:26`) so a one-time field mutation is sufficient — no per-frame hook. Mirrors the bomb-cooldown save-and-restore pattern: toggling off restores vanilla 20m without restart, and `on_setting_changed` re-syncs live. Boon template is never re-registered — only the existing vanilla field is mutated — so peer index alignment is preserved (`feedback_vt2_gated_registration_diverges.md` compliant). Host-authoritative.

## 0.7.70-alpha (2026-05-20)

### Fixed: Isha dropdown "Aegis" option displayed "[Invalid String Format]"

The `isha_alt_aegis` localization at `_localization.lua:323` was `"Aegis (-25% damage taken, all run)"` with a bare `%`. VMF dropdown labels go through `string.format` via `localize_dropdown_data`; a single `%` followed by a space and a letter (`% d`) is a valid format specifier (signed decimal with leading space), so when the format call has no matching numeric arg the engine returns the canonical `"[Invalid String Format]"` placeholder.

Fix: doubled the percent sign — `(-25%% damage taken, all run)`. Same fix pattern documented in memory `feedback_vt2_localize_string_format_pipeline.md`. The other Isha dropdown labels (`isha_alt_vanilla`, `isha_alt_wounds`) have no `%` and were unaffected. The Aegis blessing DESCRIPTION strings shipped earlier (in `MIRACLE_LOC_OVERRIDES`) already escape correctly.

## 0.7.69-alpha (2026-05-19)

### Fixed: Larger Clip required 2 reloads to refill a doubled shotgun clip (now unconditional)

Per user clarification: the deus_larger_clip dormant boon is cut content re-enabled by ct; its "2 pumps to refill a 4-shell clip" is unintended vanilla behavior, not a rebalance choice. Removed the v0.7.68 toggle gate — the hook now always fires.

The behavior is identical to v0.7.68 with the toggle ON. Old toggle widget + localization entries (`tweak_larger_clip_full_reload`, `tweak_larger_clip_full_reload_tooltip`) removed; the only sane behavior is "larger clip refills in one tick."

## 0.7.68-alpha (2026-05-19)

### Added: Rework — Larger Clip scales ammo-per-reload-tick alongside clip_size

Setting: `tweak_larger_clip_full_reload` (Reworks → Boons group, default OFF).

User report: on shotguns (Grudge-Raker etc.) with `deus_larger_clip` active, the clip goes from 2→4 but refilling it requires 2 pump cycles instead of 1. Each shotgun pump still loads only 2 shells, even though the clip is now 4.

Vanilla cause: `GenericAmmoUserExtension._ammo_per_reload` is set ONCE at extension init from the weapon template (`grudge_raker.lua:155: ammo_per_reload = 2`) and is NEVER passed through `apply_buffs_to_value`. The `clip_size` stat_buff IS applied (line 95 of generic_ammo_user_extension.lua: `_ammo_per_clip = math.ceil(buff_extension:apply_buffs_to_value(_original_ammo_per_clip, "clip_size"))`), but `_ammo_per_reload` is just copied verbatim at line 28. Each reload tick caps at `_ammo_per_reload` shells — so a doubled clip needs two ticks to refill.

This is genuine vanilla behavior, not a CT regression. CT does not touch `larger_clip`, `ammo_per_reload`, or any reload code.

Fix (toggle-gated rebalance): `mod:hook_safe(GenericAmmoUserExtension, "_apply_buffs", ...)` reads the effective clip_size multiplier (`_ammo_per_clip / _original_ammo_per_clip`) and applies the SAME scale to `_ammo_per_reload`. Original value is captured once per extension instance (`_ct_original_ammo_per_reload`) so repeated `_apply_buffs` calls don't compound.

Generic: works for ANY clip_size source (boon, talent, future modded buff). On weapons without an `ammo_per_reload` template entry (everything that already reload-fills in one action) the hook is a no-op. Host-authoritative via `effective_setting`.

## 0.7.67-alpha (2026-05-19)

### Removed redundant name override on `blessing_of_power_name`

Vanilla CW already returns "Miracle of Ulric" for the `blessing_of_power_name` localization key (user-confirmed 2026-05-20). The v0.7.65 Localize hook over-reached and substituted the same string back, which was a no-op visually but conceptually wrong — the user only ever wanted the description changed, not the name. Removed the name from `MIRACLE_LOC_OVERRIDES` and narrowed the `blessing_of_power_*` branch in the Localize hook to `blessing_of_power_desc` only.

### Diagnostic: log every `blessing_of_power` purchase attempt + shop-open offerings

The 2026-05-20 3-player session had the toggle on (host-synced) and the shop was a `shop_strife` (Khorne pillar, which offers `blessing_of_power` per `deus_shop_settings.lua:13-16`), but the user reported "Ulric wasn't purchaseable" and **zero** `_try_buy_blessing` entries appear in either log for the blessing. Buy attempts for the other two blessings (`blessing_holy_hand_grenade`, `blessing_of_grimnir`) recorded normally. Cost was 100; user had 1337 coins remaining after the first two buys, so affordability is not the cause.

Without entry logging in the hook we can't tell if (a) the click never reached `_try_buy_blessing` (UI greyed out the button — most likely) or (b) some silent return-false in our own code fired. v0.7.67 closes that gap:

- **`_try_buy_blessing` entry log** — fires on every call where `blessing_name == "blessing_of_power"`, regardless of toggle state. Logs buyer, is_server, toggle, has_blessing, coins, cost. Next session will tell us whether the click reached the hook at all.
- **Reject-reason logs** — the previously-silent `has_blessing → return false` and `coins < cost → return false` paths now log their cause.
- **`DeusShopView._create_ui_elements` hook augmented** — logs the shop type, full blessing offering list, and current `blessings_with_buyer` state at shop-open. Captures whether `blessing_of_power` is even in the offering pool (it should be, for `shop_strife`).



Same bug class as v0.7.59 / v0.7.60 (gated registration diverges across peers), but at a different table. The v0.7.60 fix split registration from the rarity-pool insert for the `NetworkLookup.deus_power_up_templates` + `BuffTemplates` side tables — but **`DeusPowerUpsLookup` itself** stayed inside the toggle-gated `inject_dormant_boon` body. That table is *also* network-relevant: `deus_mechanism.lua:1256` does `DeusPowerUpsLookup[boon_id]` where `boon_id` is the integer received over RPC. If host's lookup table is ordered differently from client's, host's `rpc_add_buff(id=N)` resolves to a *different* boon on the client.

Caught in pre-deploy QA of the 2026-05-19 multiplayer log: user (client) had `activate_dormant_deus_larger_clip = ON`, friend (host) had it `OFF`. Client log line `deus_larger_clip at rarity rare (lookup_id=165)` doesn't appear in host log; every dormant + trait boon ID after `deus_coin_pickup_regen` was off by +1 on the client. Subsequent host rpc_add_buff calls would have resolved to the wrong boon.

Fix: split `inject_dormant_boon` into two functions.
- `inject_dormant_boon(name, rarity)` — registers EVERYTHING network-relevant (NetworkLookup names, buff_templates, DeusPowerUps / Array / ArrayByRarity / Lookup, BuffTemplates global mirror, DeusPowerUpBuffTemplates). Idempotent via `_injected_dormants[name]`. Called unconditionally for all dormants + trait boons in pre-register passes at mod-load.
- `_add_dormant_to_pool(name, rarity)` — inserts into `DeusPowerUpRarityPool[rarity]`. Idempotent via `_added_to_pool[name]`. Called from the toggle-gated paths (`sync_dormant_boons`, `register_trait_boon`) so each peer only rolls the boons their toggles enabled.

Both pre-register passes (`pre_register_dormant_lookups`, `pre_register_trait_boon_lookups`) now drive full registration. The previous "partial pre-register" code paths in each are simplified — the work is now consolidated in `inject_dormant_boon`. Unconditional registration sites (`register_meta_boon` for CT_META_BOONS, the ct_meta_movespeed do-block, the ct_kill_heal do-block) explicitly call `_add_dormant_to_pool` after `inject_dormant_boon` since meta boons aren't toggle-gated.

Affected dormants (9): `deus_ammo_pickup_give_allies_ammo`, `deus_coin_pickup_regen`, `deus_large_ammo_pickup_infinite_ammo`, `deus_larger_clip`, `deus_throw_speed_increase`, `deus_timed_block_free_shot`, `deus_transmute_into_coins`, `explosive_pushes_on_damage_taken`, `squats`.

Affected trait boons (11): all entries in `CT_TRAIT_BOONS` table — Vaul's Anvil, Manann's Tempest, Taal's Twinned Arrow, Asuryan's Wrath, etc.

**Hardening (pre-deploy QA-caught):** `pre_register_trait_boon_lookups` now writes `DeusPowerUpTemplates[spec.name]` UNCONDITIONALLY (using a placeholder buff array if the source buff is missing on that peer), so `inject_dormant_boon`'s template-existence check never bails — `DeusPowerUpsLookup` stays aligned across peers even for hypothetical DLC-gated source buffs. Today all four source buffs are vanilla so no peer should ever hit the placeholder path; the safety net guards future DLC trait boons.

### Fixed: client-side ct_peers manifest broadcast didn't fire (one-sided handshake)

The v0.7.64 ct_peers diagnostic was supposed to be bidirectional: when a client receives the host's ct_sync_host_settings_chunk, it should auto-reply with its own manifest so the host's log captures every joined peer's ct version + mod list. In practice it was one-sided — host self-logged via the setup_run hook but never received RECV from clients.

Root cause: the `_broadcast_local_manifest("server")` call sat AFTER `sync_host_dependent_state()` in the ct_sync receiver body. `sync_host_dependent_state` calls 11 sync_* re-registration helpers — any one throwing aborts the receiver because VMF's `network_register` safe-wrapper swallows the error. The closure capture analysis was sound; the function was assigned; the call simply never reached.

Fix: moved the manifest broadcast (and added an info log to confirm entry) BEFORE the `sync_host_dependent_state()` call in the ct_sync_host_settings_chunk handler. Now even if a downstream re-registration throws, the manifest reply still goes out.

Next 3-peer session should show `[ct_peers] RECV peer=...` lines on the host log immediately after the ct_sync broadcast lands on each client.

## 0.7.66-alpha (2026-05-19)

### Fixed: Isha alternative drained coins on every shop visit (v0.7.65 dedup bug)

The v0.7.65 Isha alternative branch of `_try_buy_blessing` deliberately skipped writing `blessing_of_isha` to `blessings_with_buyer` because that table drove the vanilla auto-mutator activation. But `DeusRunController.has_blessing` reads the SAME table to decide "is this blessing already bought" — so the shop's purchase-guard never fired and `deus_shop_view_v2.lua:854-867` never marked the slot as bought. Net result: every shop visit, players could re-purchase the Isha alternative for full price, draining coins.

Fix: the buy hook now DOES write to `blessings_with_buyer` (which fixes both the dedup and the shop UI), and a separate `mod:hook` on `MutatorTemplates.blessing_of_isha.server.start_function` suppresses the vanilla mutator behavior by setting `data.hero_side = nil` immediately after vanilla initializes. Every vanilla entry point (`server_update_function`, `server_player_disabled_function`, `server_player_hit_function`) early-returns on `not data.hero_side`, so the entire revive mechanic goes dormant. Localization and persistent buff application remain.

**Hook-target gotcha (caught in pre-deploy QA):** the live dispatch target is `template.server.start_function`, NOT `template.server_start_function`. The engine wraps every mutator's `server_*_function` fields at `mutator_templates.lua:236-269` (which runs at engine boot, before any mod loads) — the original `server_start_function` field becomes a dead pointer captured in an upvalue closure, the wrapper lives at `template.server.start_function`. Hooking the dead field compiles cleanly but suppresses nothing. The fix targets the correct wrapped field.

### Added: Miracle of Isha — Unlimited Wounds variant (recruit-style)

Third option for Isha behavior. When selected, every hero gets unlimited wounds for the rest of the run — every knockdown is revivable, no more "first down was your one wound, second down = instant death" mechanic that higher difficulties enforce.

Implementation: new buff template `ct_miracle_of_isha_wounds` with `perks = { "infinite_wounds" }` and `is_persistent = true`. Mirrors vanilla CW boon `indomitable` (`deus_power_up_settings.lua:5056-5073`). The `infinite_wounds` perk gates `GenericStatusExtension:set_wounded` at `generic_status_extension.lua:1443-1450` — the wounds-counter decrement is skipped, so `has_wounds_remaining()` always returns true, so the death-on-down branch at `player_unit_health_extension.lua:812` is never taken. Recruit difficulty achieves the same effect via `wounds = 5` (effectively unlimited for a CW run length); we use the cleaner perk-based approach.

### Changed: Miracle of Isha is now a dropdown (Vanilla / Aegis / Unlimited Wounds)

Replaces the v0.7.65 `tweak_miracle_of_isha_alternative` checkbox with a 3-option dropdown:
- **Vanilla** (default) — original Blessing of Isha behavior (one team revive when squad reduced to one hero)
- **Aegis** — every hero takes -25% damage for the rest of the run (v0.7.65 alternative)
- **Unlimited Wounds** — every hero gets unlimited wounds for the rest of the run

Migration: users with the v0.7.65 checkbox set to ON automatically get **Aegis** mode on first load after upgrade (the runtime helper `_get_isha_mode` maps boolean `true` → `"aegis"`). Off / nil → Vanilla.

### Fixed: `/ct status` debug output showed stale "(0=vanilla)" legend

The status echo at `chaos_wastes_tweaker.lua:5338-5345` still printed the v0.7.64 sentinel meaning for altar/chest counts. Now reflects v0.7.65 semantics: -1 = Default, 0 = literal zero.

## 0.7.65-alpha (2026-05-19)

### Added: Miracle of Ulric — toggle replaces vanilla "Blessing of Power" with persistent +50 Power that survives weapon swaps

Setting: `tweak_miracle_of_ulric_persistent` (Reworks → Boons group, default OFF).

Vanilla Blessing of Power mutates each player's serialized weapon `power_level` field (+50, applied at purchase time, deus_run_controller.lua:1671-1703). The +50 lives on the weapon ENTRY, so the moment a player swaps weapons at an upgrade / melee swap / ranged swap altar, the new weapon doesn't have it — the bonus EVAPORATES. The user reported this as a long-standing frustration.

When the toggle is ON: ct intercepts `_try_buy_blessing` for `blessing_of_power` and skips the vanilla weapon-mutation branch entirely. Instead, every hero gets a custom `ct_miracle_of_ulric` buff (`stat_buff = "power_level"`, `bonus = 50`, `is_persistent = true`, `max_stacks = 1`) applied directly to their `buff_extension`. Because the buff lives on the player rather than the weapon entry, it survives every weapon swap for the rest of the run. The vanilla blessing-purchase accounting (coins spent, blessings_with_buyer, bought_blessings, coin tracker) is replicated so the blessing still appears in run-stats UI.

Localization is also overridden via the existing `_G.Localize` hook: when the toggle is on, the blessing's name becomes "Miracle of Ulric" and the description reads "Grants every hero +50 Power for the rest of the run. The bonus persists through weapon swaps and upgrades at altars."

Host-authoritative: the toggle is auto-collected into `SYNCED_SETTING_NAMES` and broadcast via `ct_sync_host_settings_chunk`. Clients see whatever the host configured.

### Added: Miracle of Isha (Aegis Alternative) — toggle replaces revive with -25% damage taken for the whole team

Setting: `tweak_miracle_of_isha_alternative` (Reworks → Boons group, default OFF).

Vanilla Blessing of Isha runs `mutator_blessing_of_isha.lua` which grants a single team-revive when the squad is reduced to one hero. Useful, but binary — and the team has to actually wipe to one hero before it does anything.

When the toggle is ON: ct intercepts `_try_buy_blessing` for `blessing_of_isha` and SKIPS adding the blessing to `blessings_with_buyer`. This suppresses `DeusMechanism.start_next_round` from auto-activating the vanilla revive mutator (which reads its blessing list at `deus_mechanism.lua:759-767`). Instead, every hero gets a custom `ct_miracle_of_isha_aegis` buff (`stat_buff = "damage_taken"`, `multiplier = -0.25`, `is_persistent = true`) so the whole team takes 25% less damage for the rest of the run. Coins are still spent + tracked so the purchase feels real.

Trade-off: Isha no longer appears in the run-stats blessing UI when toggled (since the entry isn't added to `blessings_with_buyer`). Description text is rewritten to reflect the aegis behavior; the name stays "Blessing of Isha."

Host-authoritative — same auto-sync as Ulric.

### Implementation notes (shared by both miracles)

- Both buff templates are registered into the global `BuffTemplates` (and mirror-written to `DeusPowerUpBuffTemplates` for the runtime merge path) at mod-load, unconditionally. This avoids the gated-registration-diverges-across-peers bug class (feedback_vt2_gated_registration_diverges.md) — buff template names are pre-allocated in `NetworkLookup.buff_templates` on every peer's machine before any lobby connection.
- Single consolidated `mod:hook("DeusRunController", "_try_buy_blessing", ...)` handles both blessings — VMF silently shadows duplicate same-method hooks (feedback_vmf_hook_safe_no_chain.md), so the branch-on-blessing_name pattern is mandatory.
- Non-ct peers in a ct host's lobby will crash on the rpc_add_buff for these buff names (same failure mode as any other ct-injected buff). This is consistent with existing ct buff-injection behavior — not a new regression class.
- The damage-reduction sign is NEGATIVE (`-0.25`) per the vanilla `ale_defence` pattern at `buff_templates.lua:5325-5333`. Engine accumulates negative multipliers as damage reduction.

### Altar / Chest / Arena-ammo dropdowns: explicit "Default" sentinel separated from literal 0

Pre-0.7.65, the four altar dropdowns (Upgrade / Melee Swap / Ranged Swap / Boon Altars) used `value = 0` to mean "Default — leave vanilla random distribution untouched." There was no way to force literally zero altars of a given type. Similarly, `cursed_chest_count` was a numeric slider 0–10 (default 1) where 0 meant "zero chests" with no separate "use vanilla" sentinel, and `arena_ammo_count` was numeric 0–10 (default 2) with the same limitation.

User intent: explicit per-dropdown choice between "let CW decide" (Default sentinel) and "force zero" (literal 0).

Changes:
- Altar dropdowns: `value = -1` is the new "Default" sentinel. `value = 0` is now a distinct option meaning "literally zero altars of this type." 1-9 still mean "force this many." `default_value` for all four widgets updated to `-1`.
- `cursed_chest_count` converted from numeric to dropdown with the same shape: -1 = Default (vanilla picks the count, defaults to 1/mission), 0 = no chests, 1-10 = override.
- `arena_ammo_count` converted from numeric to dropdown with -1 = Default (vanilla 2), 0 = no arena ammo, 1-10 = override.
- New `count_with_default_options` dropdown table at `_data.lua:351-365` for the wider-range chest/ammo widgets.
- `chaos_wastes_tweaker.lua` consumer hooks updated:
  - `get_deus_weapon_chest_type` (`:1045-1056`): explicit `as_count` helper maps sentinel→0 in the override distribution; `is_custom = any value not -1`. Default-state altars contribute zero to the override total.
  - `populate_pickups` (`:1393-1533`): same sentinel handling; cursed_custom / ammo_custom now key off "value not equal to -1" instead of "value not equal to vanilla default."
  - `_spawn_guaranteed_pickup` cap (`:2528`): sentinel -1 maps to vanilla 1.

Existing user settings stored as 0 will surface as "0 altars" / "0 chests" after this change rather than "Default." Re-pick "Default" if that's what you intended. Tooltip strings updated to document the new semantics (`altar_count_tooltip`, new `cursed_chest_count_tooltip`, updated `arena_ammo_count_tooltip`).

## 0.7.64-alpha (2026-05-19)

Fan-out fix release for issues surfaced in the 2026-05-19 3-player run (host Lyndsey, clients Amanda + user).

### Fixed: Holly DLC adventure-injected levels (Magnus / Cemetery / Forest Ambush) spawned ZERO pickups — no ammo, no healing, no grenades, no Chests of Trials, no altars, no locus

In the bugged run, magnus_belakor_path1 (the actual Belakor cursed mission) loaded and the entire map had nothing on the ground for ~20 minutes. Host log captured 13 PickupSystem spawn-debt warnings the moment the level loaded — every requested pickup type (deus_cursed_chest=4, deus_weapon_chest=7, deus_potions=30, deus_soft_currency=30, ammo=4, grenades=4, healing=4, level_events=8) ended up 100% unfilled.

Root cause: ct's `PickupSystem._can_spawn` hook (`chaos_wastes_tweaker.lua:2163`) only returned true for the three deus pickup categories (`deus_potions`, `deus_soft_currency`, `deus_weapon_chest`). The comment at the bottom of the hook claimed vanilla `_can_spawn` already handled the campaign categories (ammo/healing/grenades) "before our hook runs" — but that's wrong for adventure-injected levels under the deus mechanism: `Managers.mechanism:can_spawn_pickup` routes to the deus pickup whitelist which doesn't recognize campaign pickup names, AND the per-spawner `Unit.get_data(spawner, pickup_name)` check often fails for category-vs-specific mismatches (spawner is tagged "ammo=true" while pickup_name is `ammo_specific_X`).

Net result on the three Holly DLC levels: every spawn-pickup call was vetoed. Other CW maps still worked because vanilla CW pickup_settings only request the three deus types — the bug was latent until adventure-injected levels surfaced it.

Fix: the hook now also returns true on injected-adventure levels for any pickup_name matching a non-deus `Pickups[bucket]` entry. The existing filters for tome/grim, guaranteed_spawn, and triggered_spawn_id stay in place, so triggered barrels / scripted event spawners stay exclusive to their tagged pickup type (no regression of the v0.6.32 burn — barrels showing up as potions).

### Fixed: Belakor locus spawned on the WRONG mission (the first adventure-injected level with `force_belakor` on, not the actual Belakor cursed one)

Host log proves it: at 03:52:51 the locus altar spawned on `nurgle_slaanesh_path1` (node_1, curse=curse_greed_pinata). The actual Belakor cursed mission `magnus_belakor_path1` (node_12, curse=curse_belakor_totems) didn't even load until 04:03:02 — and never spawned a locus (in part because of the Holly-pickup bug above).

The predicate at `chaos_wastes_tweaker.lua:2107` checked `force_belakor` + `not _belakor_altar_spawned_this_level` + `AllPickups.deus_02`. Nothing in there cares which curse the current mission actually has. `force_belakor` only guarantees a Belakor curse appears SOMEWHERE in the run — it doesn't say where.

Fix: added `_current_node_is_belakor()` (`chaos_wastes_tweaker.lua:1629`) — reads `run_controller:get_current_node().curse` and returns true only when it equals `curse_belakor_totems`. Gated both the spawn-side predicate (`:2107`) and the existing `can_spawn_belakor_locus` override (`:2198`) on it. Now the locus only places on the actual Belakor mission, and the Holly-pickup fix above lets it actually spawn there.

### Reworked: Manann's Tempest cooldown is now a single toggle for BOTH boon and trait, default OFF

Previously: trait was gated by `tweak_manann_tempest_cooldown` (toggle, default off), but the boon variant was hard-capped at 8s unconditionally — opt-out only existed for the trait side. User intent was a single toggle that gates BOTH, default off (= vanilla on both).

Changes:
- `chaos_wastes_tweaker.lua:4024` — removed the `is_trait and` qualifier so the toggle now gates both branches before the proc fires. Separate per-source buckets (`boon_next_t`, `trait_next_t`) preserved so a player running both still gets one chain per 8s from each side.
- Localization updated: title is now "Rework: Manann's Tempest — 8s cooldown (boon + trait)"; tooltip clarifies both sources are gated. Boon-enable tooltip also updated to remove the stale "hard-capped" claim and direct to the rework toggle.

### Fixed: per-boon-scaling meta boons (`ct_meta_health`, stagger/crit/cooldown/ammo/movespeed) only updated on next mission load, not on every boon gain

Reported in last night's 3-player run (host Lyndsey, clients Amanda + user): grabbing "% max health per active boon" mid-run didn't lift the player's HP cap until the next mission. Confirmed for all six meta boons.

### Root cause

Same shape as the v0.7.57 `chain_lightning` cooldown fix. `register_meta_boon` (`chaos_wastes_tweaker.lua:3507`) and the special-cased `ct_meta_movespeed` block (`:3580`) both registered the granted-proc handler into `BuffFunctionTemplates.functions`, but the engine resolves `on_boon_granted` callbacks from the flat global `ProcFunctions` (`buff_extension.lua:1350`: `local buff_func = ProcFunctions[buff_func_name]`). Result: the granted proc was dead — VMF logged the registration but the runtime lookup returned `nil`.

The apply_buff_func IS read from `BuffFunctionTemplates.functions` (`buff_extension.lua:397`), so the apply path worked. That's why every meta boon's stack count refreshed correctly on the *next* mission (the engine reapplies all power-ups at level start, running apply fresh) but stayed stuck for the rest of the current mission.

Vanilla reference: `boon_meta_01_boon_granted` lives in `morris_buff_settings.lua:4929` inside `dlc_settings.proc_functions` (merged into `ProcFunctions` at `buff_templates.lua:9533`); `boon_meta_01_apply` lives at line 2024 in `dlc_settings.buff_function_templates`. Two separate tables — ct was only writing to one.

### Fix

Added a single line at each registration site: `proc_functions[granted_name] = proc`. Now the granted proc lives in both `BuffFunctionTemplates.functions` (harmless, unread) AND `ProcFunctions` (the table the engine actually queries). The apply path is unchanged.

Vanilla `PlayerUnitHealthExtension.update` (`player_unit_health_extension.lua:281-426`) recomputes `_calculate_max_health()` every server tick, writes the new total to the GameSession `max_health` game-object field, and rescales current HP when the cap changes (lines 348-360). So once the stack buff actually exists on the buff_extension, max-HP lifts and current-HP scales without ct needing to call any refresh API explicitly.

Affected boons:
- `ct_meta_stagger` (`:3417`)
- `ct_meta_crit` (`:3426`)
- `ct_meta_health` (the reported bug)
- `ct_meta_cooldown` (`:3444`)
- `ct_meta_ammo` (`:3452` — its `refresh_ranged_slot_buffs` apply path was already correct; the stack delta now lands on every boon gain)
- `ct_meta_movespeed` (`:3580`)

Network-sync note: `add_power_ups` triggers `on_boon_granted` both locally (`deus_run_controller.lua:1158`) and via `rpc_deus_add_power_ups` on the server (`:1402`). The idempotent loop in `_make_meta_proc` (`for _ = num_existing + 1, num_boons do buff_extension:add_buff(stack_name) end`) prevents double-apply when both fire.

NOT addressed in this fix: stack decrement on boon loss. ct never removes meta-boon stacks, only grows them. Not user-requested.

### Sync: `tweak_defeat_recovery` and `enable_campaign_potions` moved from per-peer to host-synced

Both were originally per-peer for historical reasons (the wipe-prevention is host-only, so the local penalty arm was per-peer; campaign potions are server-driven spawn so client mutation was irrelevant). User intent is "all settings sync to host," so both are now in `SYNCED_SETTING_NAMES`. The two call sites (`chaos_wastes_tweaker.lua:1038, 3194`) now read via `effective_setting`. `inject_adventure_maps` stays per-peer because it mutates `NetworkLookup.level_keys` which folds into lobby `combined_hash` and can't be re-evaluated post-boot.

### Fixed: curse/mission visual desync (different halos/lighting per peer for the same CW node)

In the 2026-05-19 run, three peers received the same lobby seed `-1029216815` but landed on completely different per-node level/curse/theme assignments because `inject_adventure_maps` toggle states differed across peers. The toggle mutates each peer's local `LEVEL_AVAILABILITY` arrays at module-load — `deus_populate_graph` then picks levels by index into those arrays, so identical seed × different arrays = different graphs. The toggle can't be moved to host-sync (it folds into `combined_hash` via `NetworkLookup.level_keys` count, sealed pre-handshake).

Fix: ct now broadcasts the host's RESOLVED graph after `deus_populate_graph` returns. Clients overwrite the picker-output fields in place — level, base_level, theme, curse, god, node_type, type, terror_event_power_up + rarity, mutators, minor_modifier_group. Topological fields (next, layout_x/y, run_progress, label) are deterministic from base_graph + seed and not shipped. Per-node JSON uses short keys (`l`/`b`/`t`/`c`/`g`/...) to keep payload tight: CW ~22-28 nodes × ~110 bytes ≈ 3.6 KB worst case, well under the existing 9-10 chunk envelope.

Implementation: new `ct_graph_snapshot_chunk` RPC mirroring the existing `ct_sync_host_settings_chunk` chunked-send pattern. Two apply sites — Phase A inside `deus_populate_graph` hook on the client's return path (common case), Phase B inside `DeusMapScene.on_enter` hook for late-arrival races where the RPC lost to the engine's `rpc_deus_setup_run`. In-place mutation preserves `_path_graph` table identity and `next` pointers. Host migration is NOT covered in v1 — new host's snapshot represents its pre-migration state; documented as known limitation. No NetworkLookup writes, no buff template — purely VMF string-keyed RPC, so old-ct peers silently drop the packet without crashing.

### Added: lobby mod-mismatch logging (`/peers` chat command + auto-broadcast)

Diagnostic tool for triaging post-session desync reports: each peer now logs a manifest at lobby join + on-demand via `/peers`. Manifest fields:
- `v`  ct version string (MOD_VERSION)
- `h`  FNV-1a hash of locally-configured SYNCED_SETTING_NAMES values (catches setting drift cheaply)
- `m`  list of enabled Workshop mods (id + name + last_updated timestamp) — the smoking gun for "your friend's halo is different"
- `vt` VMF workshop timestamp
- `nl` `#NetworkLookup.level_keys` (confirms adventure-injection state per peer)

Auto-broadcast: clients reply to the host's `ct_sync_host_settings_chunk` with a manifest packet. Host's log captures every joined peer's manifest right at the first reliable post-loading moment, with a DIFF line per peer flagging ct version / settings hash / num_levels / VMF timestamp / missing-or-extra mods relative to host. New `/peers` chat command lets any peer dump cached manifests + refresh-broadcast on demand.

Network safety: new RPC is VMF string-keyed (`mod:network_register`), NOT index-sequential — does NOT trip the gated-registration-diverges class of bugs documented in `feedback_vt2_gated_registration_diverges.md`. Old-ct peers silently drop the packet with no crash. Forward-compatible: future field additions just add new keys; missing fields decode as `nil`.

The 2026-05-19 desync would have been instantly diagnosable with this in place — the three peers' manifests would have shown identical mods but different `inject_adventure_maps` state (now fixed by the graph snapshot above), making the cause obvious from logs alone.

## 0.7.63-alpha (2026-05-19)

### Fixed: client crashed decoding `deus_power_up_templates` key 177 when host's buff RPC referenced a trait boon the client hadn't pre-registered

Verbatim crash from peer `1100001043e2511` (a client in lynnd's host session), reproduced in two consecutive dumps `2026-05-19-02.59.56-…` and `2026-05-19-03.08.36-…`:

```
scripts/network_lookup/network_lookup.lua:2514:
[NetworkLookup.lua] Table deus_power_up_templates does not contain key: 177
@scripts/managers/game_mode/mechanisms/deus_run_state_spec.lua:76: in function decoder
```

Same bug class as v0.7.60 (dormants) / v0.7.61 (trait-boon templates) / v0.7.62 (adventure-injected levels) — see `feedback_vt2_gated_registration_diverges.md`. Two registration sites still had a condition that could shift the sequential `NetworkLookup.deus_power_up_templates` ids between peers running the same ct version:

1. **`pre_register_trait_boon_lookups`** (`chaos_wastes_tweaker.lua:3718`) — wrapped the entire per-spec body in `if source_template and source_template.buffs`. If a peer's `BuffTemplates` happened to be missing one of the four vanilla source buffs (`always_blocking` / `deus_crit_chain_lightning` / `deus_extra_shot` / `deus_collateral_damage_on_melee_killing_blow`) at module-init time, that entire trait boon's NetworkLookup name + buff-template registration was skipped — shifting every subsequent power-up name's id by one.
2. **`ct_kill_heal`** (`chaos_wastes_tweaker.lua:3790`) — entire registration (including `register_power_up_in_network_lookup`, implicitly via `inject_dormant_boon`) wrapped in `if power_ups and buff_funcs and buff_funcs.functions`. If those globals weren't loaded yet on some peer's machine at the moment this module ran, ct_kill_heal got no NetworkLookup id at all on that peer — but it DID get one on peers where the globals were ready, again shifting the sequential id.

Either path produces "host has id N for boon X, client has id N for boon Y or no boon at all" — when host's `rpc_add_buff` reaches the client carrying id N, the strict `__index` on `NetworkLookup.deus_power_up_templates` raises uncatchable `error()` from inside the shared-state RPC decoder (bypasses pcall — `network_event_delegate.lua:52` doesn't xpcall the decode path).

### Fix

Decouple NetworkLookup name registration from the gated content writes. Both call sites now register the NetworkLookup names unconditionally up-front (in sorted order for trait boons, single-call for ct_kill_heal), then perform the buff-template / DeusPowerUpBuffTemplates / DeusPowerUpTemplates writes inside the existing `if globals_ready` guard. The name registration is what determines the sequential id; the side-table writes only affect whether the boon is actually castable in this peer's run. Same shape as the v0.8.66-dev LA fix for `pre_register_la_inventory_packages`.

Concrete edits:
- `pre_register_trait_boon_lookups`: moved `register_power_up_in_network_lookup(spec.name)` + `register_buff_in_network_lookup("power_up_" .. spec.name .. "_" .. spec.rarity)` into an unconditional first loop over the sorted CT_TRAIT_BOONS specs. The second loop still does the gated template clone + dpubt write.
- `ct_kill_heal do-block`: hoisted `register_power_up_in_network_lookup("ct_kill_heal")` + `register_buff_in_network_lookup("power_up_ct_kill_heal_exotic")` above the `if power_ups and buff_funcs` gate. The full template construction still runs inside the gate; only the lookup-id allocation happens unconditionally.

Both registration helpers (`register_power_up_in_network_lookup`, `register_buff_in_network_lookup`) early-out via `rawget` if the name is already present, so re-runs are no-ops — safe for `sync_host_dependent_state` to invoke without producing duplicate slots.

### Note on version skew

The fix guarantees deterministic indices for peers running the same ct version. Peers on DIFFERENT ct versions can still mismatch (e.g. one peer has a boon another doesn't), and there is no safe mod-side workaround for that — players need matching mod versions. The error message in the log is the canonical diagnostic if it recurs in a mixed-version lobby.

## 0.7.62-alpha (2026-05-18)

### Fixed: client joining a host's adventure-injected Deus run crashed at `state_loading.lua:449`

Same toggle-divergence bug class as v0.7.60 (dormants) and v0.7.61 (trait boons), one layer over: the per-mission registration in `_adventure_pool.lua`'s `inject_pool` (LevelSettings permutation clones, `NetworkLookup.level_keys`, `TerrorEventBlueprints`, `WeightedRandomTerrorEvents`) was inside the toggle-gated branch and only iterated `enabled_missions()`. A peer with the master toggle off — or with a specific mission's per-mission toggle off — never registered the corresponding `<adv>_<theme>_path1` keys. When the host then advertised `magnus_belakor_path1` (or any other unregistered permutation) over SharedState, the client's `state_loading.lua:449` did `LevelSettings[level_key]` and crashed with `attempt to index local 'level_settings' (a nil value)`.

`pre_register_adventure_lookups` now runs unconditionally at the top of `inject_pool` (which itself is called at mod-load and on setting change), iterating `_M.ADVENTURE_MISSIONS` in sorted-by-key order and writing each mission's six theme permutations into LevelSettings + NetworkLookup + TerrorEventBlueprints + WeightedRandomTerrorEvents via the extracted helper `register_mission_resolvables`. Sorted iteration matches the load-bearing rule in `feedback_vt2_gated_registration_diverges.md`: two ct peers must compute identical NetworkLookup indices regardless of which toggles each one has on.

Pool selection (the `DEUS_MAP_POPULATE_SETTINGS.LEVEL_AVAILABILITY` mutation + the `IS_INJECTED_ADVENTURE_LEVEL` flag that drives the tome-to-Chest-of-Trials swap) stays gated by master + per-mission toggles, so each user's own CW runs still reflect their preferences. The defensive registration is purely additive — every write is guarded by `not rawget(...)` so re-runs are no-ops.

The `LobbyAux.create_network_hash` shim (added v0.7.4) already nils injected `level_keys` entries during hash creation, so the always-on registration does not bump the lobby `num_levels` past vanilla and does not regress vanilla-host compat. Diagnosed from amand's session 2026-05-19 (`console-2026-05-19-01.00.42-c840d040-3b0b-4de6-880f-08cb990b26a6.log`) — host migration during a Belakor pilgrimage handed control to a client whose toggles didn't have `magnus_belakor_path1` registered.

## 0.7.61-alpha (2026-05-18)

### Fixed: same toggle-divergence bug class as v0.7.60, but for trait boons

The v0.7.60 audit caught the same shape one layer over: `register_trait_boon` for the four CT_TRAIT_BOONS (Vaul's Anvil / Manann's Tempest / Taal's Twinned Arrow / Asuryan's Wrath) early-outs on `effective_setting(spec.toggle)` before doing any registration. Two peers with different `enable_boon_*` toggles would therefore append a different ordered subset of `power_up_ct_boon_*_unique` entries to `NetworkLookup.buff_templates` and `NetworkLookup.deus_power_up_templates` — same crash and same wrong-buff failure modes as the pre-v0.7.60 dormants.

`pre_register_trait_boon_lookups` now runs unconditionally before the gated registration loop, building each spec's `DeusPowerUpTemplates` entry, writing the resulting `power_up_<name>_unique` buff template to `DeusPowerUpBuffTemplates` and `_G.BuffTemplates`, and appending both names to `NetworkLookup` in sorted (`spec.name`) order. The gated `register_trait_boon` below stays as-is and runs idempotent overwrites for the registration parts, then does pool injection if the toggle is on.

### Fixed: two `respawn_on_chest_complete` reads ran through raw `mod:get` instead of `effective_setting`

`DeusCursedChestExtension._set_state` hook fires on every peer locally (the is-server gate is several lines below the setting read). On a client whose `respawn_on_chest_complete` toggle differed from the host's, the diagnostic log and the early-return both reflected the client's local value instead of the synced host value. Real behavior gating only happens host-side so the wrong-bail had no functional effect, but the diagnostic was misleading and the gate's defensive-programming intent was wrong. Both reads now route through `effective_setting`.

## 0.7.60-alpha (2026-05-18)

### Fixed: dormant-boon toggle mismatch could crash clients on `rpc_add_buff`

Before this version, `sync_dormant_boons` only injected a dormant boon's buff template (`_G.BuffTemplates` + `DeusPowerUpBuffTemplates`) AND its `NetworkLookup` entries when the user had `activate_dormant_<name>` enabled. If a host activated `squats` (or any of the 9 dormants in `DORMANT_BOON_RARITY`) and a client had that toggle off, the host's `rpc_add_buff` for the squats buff would hit the client's `NetworkLookup.buff_templates.__index` on a missing key → fatal `Table buff_templates does not contain key: N` at `network_lookup.lua:2514`. Settings-sync alone (v0.7.59) couldn't fix this because the network table is frozen at boot — a runtime setting flip can't add entries after the fact.

`pre_register_dormant_lookups` now runs unconditionally at mod-load, iterating `DORMANT_BOON_RARITY` in sorted order. For every dormant it writes the buff template into `DeusPowerUpBuffTemplates` and `_G.BuffTemplates`, then appends `power_up_<name>_<rarity>` to `NetworkLookup.buff_templates` and `<power_up_name>` to `NetworkLookup.deus_power_up_templates`. Sorted iteration is load-bearing: with `pairs()`, two peers running the same ct version could theoretically register the same set in different orders and assign different network indices to the same name. After this change, every ct-running peer ends up with identical contents in identical positions regardless of which `activate_dormant_*` toggles they have on.

Pool injection (`DeusPowerUpRarityPool` / `DeusPowerUps` / `DeusPowerUpsArray` / `DeusPowerUpsArrayByRarity` / `DeusPowerUpsLookup`) remains gated by `activate_dormant_*`, so each user's offering pool still reflects their own preferences. The host's preference still wins via the v0.7.59 settings sync — clients see the host's pool composition during runtime. `sync_dormant_boons` is itself now sorted-iteration to match.

`pre_register_dormant_lookups` is purely additive: `register_buff_in_network_lookup` / `register_power_up_in_network_lookup` early-out on names already present, and `BuffTemplates[name]` is overwritten with an identical value when the toggled-on `inject_dormant_boon` runs later. No pool-side behavior changes for users who already had their preferred dormants enabled.

Clients without ct installed at all still cannot receive ct-injected buffs and will still crash on host `rpc_add_buff` for any ct-only buff. That class of mismatch is unfixable from inside ct — those peers must install ct (matching version) to be safe.

## 0.7.59-alpha (2026-05-18)

### Fixed: settings sync silently broken since v0.7.55 — host's settings never reached clients

v0.7.55 switched `ct_sync_host_settings` from three hand-picked scalar parameters to a single 105-entry table containing every synced setting. VMF's `mod:network_send` packs all user args into one JSON-encoded string parameter on the underlying `RPC.rpc_mod_user_data`, and Stingray hard-caps each RPC string parameter at 500 characters (`scripts/helpers/network_utils.lua:93` `STRING_MAX = 500`; same constant drives vanilla `shared_state.lua`'s own chunking). The full settings table JSON-encodes to ~4-5KB, so every host broadcast threw:

```
scripts/managers/mod/mod_manager.lua:627: Failed to pack parameter 3, too many characters in string with max length 500
```

The error fires inside VMF's safe-hook wrapper, so it never surfaced as a crash — clients just silently received zero host settings for three versions. The 500-char cap is a fixed engine constraint and is unaffected by `max_upload_speed` or `small_network_packets` (those control bandwidth/MTU, not parameter packing). Found from PrincessLyndsey666's host log after a Sigmar's Crag client crashed on `rpc_add_buff` with an unknown buff_template ID — a downstream symptom of clients running ct without host-synced injection toggles.

Fix mirrors the engine's own pattern in `shared_state.lua:288-330`: encode the payload to JSON, split into ≤400-char pieces, send each as `(session, seq, total, chunk_str)` via `ct_sync_host_settings_chunk`. Receiver buffers chunks per-sender and decodes when all chunks for the current session have arrived; a partial buffer from a stale broadcast is discarded the moment a new session id appears. 400-char chunks leave headroom for VMF's `[mod_id, rpc_id]` envelope (separate string parameter) plus the JSON array wrapper `[session, seq, total, "<chunk>"]` (~20 chars).

## 0.7.58-alpha (2026-05-18)

### Fixed: Belakor altar spawn fatals `Unit not found #ID[ee6ba7f91c666e61]` on adventure-injected levels

When `force_belakor` was on and the engine rolled a Belakor altar onto an adventure-injected mission's first remaining book spot, `World.spawn_unit("units/props/blk/blk_locus_01", ...)` hit the C-level assert at `c_api_world.cpp:67` because the unit wasn't in any loaded resource package. The locus prop ships in `resource_packages/levels/dlcs/morris/belakor_common`, which vanilla CW belakor-themed levels load via `level_settings_morris.lua`'s `theme_packages_lookup.belakor`. Our adventure-injection clones the adventure level's `packages` table and adds `morris_ingame` + the deus chest unit + DLC career packages — but not the belakor_common package, so the locus unit was unresolvable.

`build_permutation_packages` (`_adventure_pool.lua`) now appends `resource_packages/levels/dlcs/morris/belakor_common` to every injected permutation regardless of theme. `force_belakor` can ignite a Belakor altar on any theme via `_spawn_guaranteed_pickup`, so the package must be available unconditionally. Diagnosed via `crashify://142f40f3-d01d-4811-bd8b-e97272b8afcb` (entered `levels/dlcs/scorpion/alleys_heavens` aka Old Haunts as a Belakor pilgrimage); hash decoded by brute-forcing candidate unit paths through the bundle unpacker.

The `DeusRunController.can_spawn_belakor_locus` permit added in v0.7.51 + the `_spawn_guaranteed_pickup` slot grant added in v0.7.55 stay as-is — they correctly OPEN the spawn gate; v0.7.58 just ensures the asset exists when the spawn actually runs.

## 0.7.57-alpha (2026-05-16)

### Fixed: Manann's Tempest cooldown hook targeted the wrong table → VMF logged "trying to hook function or method that doesn't exist"

The v0.7.48 cooldown hook for `chain_lightning` targeted `BuffFunctionTemplates.functions`, but `chain_lightning` actually lives in the GLOBAL `ProcFunctions` table:

- morris_buff_settings.lua:131-2144 is `dlc_settings.morris.buff_function_templates` (the apply-callback category — that's where `apply_pockets_full_of_bombs_buff` lives, and why our `endless_bombs_consumes_morgrim` hook on the same target works).
- morris_buff_settings.lua:2145+ is `dlc_settings.morris.proc_functions` (event-driven procs — `chain_lightning` is at line 2563 in this block).
- At runtime BuffExtension consults `ProcFunctions[buff_func_name]` (buff_extension.lua:1350) — `BuffFunctionTemplates.functions.chain_lightning` is nil.

VMF logged the registration failure but kept loading (unlike the v0.7.53 crash that killed the entire mod), so this was a soft fail: Manann's Tempest cooldown gating just never engaged. Now hooks `ProcFunctions.chain_lightning` directly — both the boon variant (unconditional 8s cooldown) and the trait variant (gated by `tweak_manann_tempest_cooldown`) work as designed.

## 0.7.56-alpha (2026-05-16)

### Fixed: module-load crash since v0.7.53 silently disabled most of the mod

`v0.7.53` consolidated `_make_meta_apply` + `_make_meta_granted` into a single `_make_meta_proc` factory, but the special-cased `ct_meta_movespeed` registration at line ~3460 (separate from the loop because movespeed uses `apply_movement_buff` instead of stat_buff) was missed in the rename. At mod load, Lua raised `attempt to call global '_make_meta_apply' (a nil value)` — VMF aborted `mod_script` initialization at that point, so EVERY hook, registration, and binding after line 3463 silently never ran. That stripped:

- The four trait-as-boon registrations (Vaul's Anvil / Manann's Tempest / Taal's Twinned Arrow / Asuryan's Wrath boon variants)
- `ct_meta_movespeed` (Boon Bound Steps)
- `ct_kill_heal` (Khaine's Communion)
- The Home Brewer +50% potion-potency hook
- The Manann's Tempest 8s cooldown hook (the entire v0.7.48 feature)
- `endless_bombs_consumes_morgrim`
- The Ranger Vet save-grenade-block hook
- The defeat-recovery handler
- `mod.on_setting_changed` / `mod.on_disabled` (live updates and cleanup gone)
- **The host-side `sync_host_dependent_state` assignment** — meaning settings broadcast was partially broken too

Fix: switch `ct_meta_movespeed` to use `_make_meta_proc(stack_name)` (same as the loop-registered meta boons). Also renamed the inline sub-buff's `name` field from `"ct_meta_movespeed_stack"` to `"ct_meta_movespeed_stack_1"` so the proc's `num_buff_stacks(stack_name .. "_1")` delta-check finds the existing stacks (otherwise it would over-stack each grant, same shape as the Bug 2 from v0.7.53 but for movespeed).

If you've been on any v0.7.53–v0.7.55 build, an unknown swath of features were silently dead. v0.7.56 actually wires them all up.

## 0.7.55-alpha (2026-05-16)

### Changed: Belakor altar now spawns at a book pedestal alongside Chests of Trials on adventure-injected missions

Previously (v0.7.51) the altar was injected via `populate_pickups.primary.deus_02 = 1`, which placed it in a random ammo/healing/grenades primary spot. User asked for it to share the 5 book-spot budget instead — 3 tomes + 2 grimoires on every adventure level. The first `cursed_chest_count` book spots become Chests of Trials (default 1); the next book spot becomes the Belakor altar when `force_belakor` is on (one per mission). Remaining book spots stay hidden as before. Removed the populate_pickups inject and the `_can_spawn` allow-list for `deus_02` — both are unnecessary now that `_spawn_pickup` is invoked directly from the tome/grim spawner hook. The `DeusRunController.can_spawn_belakor_locus` override is still required because `_spawn_pickup` calls `pickup_settings.can_spawn_func`, which routes to `can_spawn_belakor_locus`.

### Changed: sync-all-settings by default — drop hand-maintained `SYNCED_SETTING_NAMES`

After repeated bugs caused by forgetting to add a setting to the synced-broadcast list (most recently: `disable_curse_*` helper bypassed the sync, `finale_dominant_god` / `force_belakor` weren't reaching clients, the `coin_multiplier` / `shrine_boon_count` / `chest_boon_count` / `bomb_boon_exclusive` / `disable_boon_*` / `ban_trait_*` / `tweak_home_brewer_potency` / `endless_bombs_consumes_morgrim` / `rv_no_save_morgrim` toggles all silently diverged on clients), the sync model is now opt-out instead of opt-in.

- `SYNCED_SETTING_NAMES` is built at module load by walking the data file's widget tree (`mod:dofile` + recursive visit of every leaf `setting_id`). Every setting the user can configure gets broadcast from the host to clients automatically.
- A small explicit `PER_PEER_SETTING_NAMES` excludes the three settings that are deliberately each-peer-local: `tweak_defeat_recovery` (per-peer locality is part of the design), `enable_campaign_potions` (server-driven spawn ignores client-side table mutation), `inject_adventure_maps` (lobby-hash-affecting, host/client must match at lobby-join time anyway).
- All the previously-direct `mod:get` callsites that should be host-authoritative now route through `effective_setting`: `coin_multiplier` (coin pickups now use host's multiplier), `shrine_boon_count` / `chest_boon_count` (boon picker counts match host), `bomb_boon_exclusive` (pool filter applies uniformly), `disable_boon_*` (boon pool filter), `ban_trait_*` (weapon trait filter), `tweak_home_brewer_potency` (potion potency scaling), `endless_bombs_consumes_morgrim` (Morgrim destroy-vs-drop), `rv_no_save_morgrim` (Ranger Vet grenade-save proc).
- `effective_setting` is now forward-declared near the top of the file so the early-running `on_soft_currency_picked_up` hook (line ~140) can capture the local slot at closure-creation time — without the forward-declare, that closure would have bound to a nil global.

Net effect: every UI setting in the mod menu now behaves host-authoritatively by default. Adding a new setting requires no bookkeeping — the broadcast picks it up automatically just by living in the data file.

## 0.7.54-alpha (2026-05-16)

### Fixed: `disable_curse_*` toggles weren't host-synced at the call site — client saw different curse text than host

`is_curse_disabled` read `mod:get("disable_curse_<name>")` directly instead of routing through `effective_setting`. Even though all 14 `disable_curse_*` keys ARE in `SYNCED_SETTING_NAMES` (so the host broadcasts them), this helper bypassed the sync and read each peer's local toggle. The two consumers (`MutatorHandler._activate_mutator`, `DeusMechanism.get_current_node_curse`) plus the `_transition_next_node` / `start_next_round` save-restore around `node.curse` therefore made decisions based on whoever-was-asking's settings, not the host's.

Symptom: gameplay-side mutator state could diverge between peers, and (the visible one) Holseher's map / mission-tooltip curse text on a client read the client's local toggle — host could see "no curse" while client saw the curse name, or vice versa, even though the actual mutator was the host's.

Fix: forward-declare `is_curse_disabled` near the top of the file (so existing call sites still bind correctly), assign the body just below `effective_setting`, and route the lookup through `effective_setting`.

## 0.7.53-alpha (2026-05-16)

### Fixed: Quiver Cascade (`ct_meta_ammo`, +5% total ammo per boon) did nothing in-game — two bugs

**Bug 1 (stale ammo cache).** `GenericAmmoUserExtension._apply_buffs` queries `apply_buffs_to_value(_original_max_ammo, "total_ammo")` once at AmmoExtension init and caches the result as `_max_ammo`. Adding new `total_ammo` stat_buffs after that point updates BuffExtension but doesn't bust the AmmoExtension cache, so the +5%-per-boon never showed up even when stacks were present. Fix: `apply_buff_func = "refresh_ranged_slot_buffs"` on the stack sub-buff (vanilla's canonical "I changed an ammo stat, recompute max_ammo" hook, used by Markus huntsman's passive and others; idempotent under repeated calls). `register_meta_boon` now propagates `apply_buff_func` from the spec into the sub-buff entry.

**Bug 2 (quadratic stack growth).** The `_make_meta_granted` proc queried `num_buff_stacks(stack_name)` to decide how many delta-stacks to add. But the actual stored key is `sub_buff_template.name`, which the factory builds as `stack_name .. "_" .. i` — so the query returned 0 every time and the granted proc re-added the full current boon count on every subsequent boon grant (triangular sum: after N additional boons the player had N(N+1)/2 stacks, not N). With Bug 1 masking everything visually, this went unnoticed.

Fix: consolidated apply + granted into a single `_make_meta_proc` that queries `num_buff_stacks(stack_name .. "_1")` (the first sub-buff's actual name) and adds only the delta. Same body for both procs so the result is idempotent regardless of fire order — vanilla `on_boon_granted` fires before the new boon's own apply, so the apply path handles the initial stack-up and granted handles incremental boons.

Other meta boons (stagger / crit / cooldown / health) ran the same buggy granted-proc, but their stat_buffs are queried per-use (not cached like total_ammo), so Bug 1 didn't apply and Bug 2 made them OVER-buffed rather than silently inert. Both are now fixed for every meta boon — expect previously over-buffed runs to feel "weaker" but correct.

### Fixed: finale_dominant_god override didn't reach clients — same bug shape as the v0.7.49 Belakor sync fix

The previous `_setup_run` hook flipped `dominant_god` only in host's local run state. `game_round_ended` (deus_mechanism.lua:551-619) reads `self._vote_data.dominant_god` into a local at the top and uses that single value for BOTH `_setup_run` AND `send_rpc_clients("rpc_deus_setup_run", ..., dominant_god_id, ...)`. The hook never reached the RPC payload, so clients populated their graph with the unmodified god.

Fix: hook `DeusMechanism.game_round_ended` and pre-mutate `self._vote_data.dominant_god` before vanilla runs; restore after. The mutation is host-only, gated on `reason == "start_game"`, and restores even if vanilla errors (pcall + rethrow). Vote_data persists on `self` until next mission-start, so restore-on-return is mandatory.

The `_setup_run` finale_dominant_god branch is removed since it was always redundant for the host and broken for clients.

## 0.7.51-alpha (2026-05-16)

### Added: Belakor altar (`deus_02`) spawns on adventure-injected campaign levels when host has "Always Include Belakor's Temple" on

Three coordinated changes route an altar into each adventure-injected map:

- `populate_pickups` injects `pickup_settings.primary.deus_02 = 1` (with proper save/restore so toggling the setting off cleanly reverts), gated on `on_injected_adventure_level() and effective_setting("force_belakor")`.
- `PickupSystem._can_spawn` adds `deus_02` to the allow-list for adventure-injected levels. The populate_pickups gate is the only place a request gets generated, so vanilla / non-belakor runs are unaffected.
- `DeusRunController.can_spawn_belakor_locus` returns true on adventure-injected levels when force_belakor is on. The vanilla gate rejects every non-belakor-themed node (campaign themes don't qualify), so without this the altar would still be vetoed at spawn time even after populate_pickups requested one.

`force_belakor` is now host-authoritative — added to the synced settings broadcast so clients use the host's value consistently across all three gates.

## 0.7.50-alpha (2026-05-16)

### Fixed: Moot Milk (Hangover Brew) alt rework slowed the player to 25% instead of +25%

The reworked Moot Milk's movement-speed sub-buff had `multiplier = 0.25` with `apply_buff_func = "apply_movement_buff"`. That function does `move_speed *= multiplier`, so 0.25 capped the player at 25% of base speed (a -75% slow) for the entire potion duration. Vanilla speed_boost_potion uses 1.5 for +50%; the intended +25% needs 1.25. Code comments / changelog have always advertised this as +25% — the value was just wrong since the rework shipped. Decanter-extended (`_increased`) variant inherits from the same builder, so it's fixed too.

## 0.7.49-alpha (2026-05-16)

### Fixed: clients couldn't see the Belakor curse on Holseher's map when host had "Always Include Belakor's Temple" on

Previously the `force_belakor` override was applied inside `DeusMechanism._setup_run`. That works for the host's own run state, but the upstream caller (`game_round_ended`) computes `with_belakor` BEFORE calling `_setup_run`, then re-uses that same outer-scope variable when it broadcasts `rpc_deus_setup_run` to clients. The hook never reached the RPC payload, so clients ran graph generation with `with_belakor=false` and rolled no Belakor nodes / no Belakor curse spread.

Fix: hook the upstream `BackendInterfaceDeusPlayFab.deus_journey_with_belakor` so the override happens at the source. Now both `_setup_run` and the RPC use the same modified value, and clients see the Belakor curse propagated through the graph.

Known related bug (NOT fixed in this version): `finale_dominant_god` has the same shape — the `_setup_run` hook flips the host's local `dominant_god` but the RPC keeps the original. Clients on a `finale_dominant_god`-overridden run see vanilla god distribution on their map. File a follow-up if this matters.

## 0.7.48-alpha (2026-05-16)

### Added: Manann's Tempest — 8s per-source cooldown

Wraps `BuffFunctionTemplates.functions.chain_lightning` to enforce a per-owner cooldown:

- **Boon variant** (the Unique-rarity Manann's Tempest boon, when its toggle is on) — always rate-limited to 1 chain per 8 seconds. No new toggle; the boon now ships with this cap baked in.
- **Trait variant** (the vanilla `deus_crit_chain_lightning` weapon trait) — new toggle `tweak_manann_tempest_cooldown` under Reworks > Reworks: Boons. Off (default) = vanilla (no cooldown, fires on every crit). On = 8s cooldown that mirrors the boon.

Boon and trait cooldowns are independent buckets per `owner_unit`, so running both gives you one chain per 8s from each side (matches the existing stacking design). The cooldown gate mirrors the proc's own ALIVE / first_hit / is_critical_strike check so it only consumes on procs that would actually have fired. Trait toggle is host-authoritative via the existing settings sync.

## 0.7.47-alpha (2026-05-16)

### Added: Rework — Killer in the Shadows potion lasts 2x as long

New toggle in Reworks > Reworks: Potions. Doubles the invisibility potion's duration: base 5s → 10s, increased 15s → 30s (Decanter then stacks on the increased variant the usual 50%, giving 15s/45s). Same `BuffTemplates` save-and-restore pattern as the Poison Proof duration rework — mutates `BuffTemplates.killer_in_the_shadows_potion.buffs[1].duration` + `_increased` at apply, restores on revert. Synced via the host-authoritative settings broadcast.

## 0.7.28b → 0.7.40-alpha (2026-05-15) — consolidated session log

Twelve versions in one session. Listed chronologically by version.

### 0.7.28b — Rework: Shard Strike duration nerf (configurable)
Toggle in Reworks > Reworks: Boons. Slider 1–16s controls the duration of Shard Strike's damaging stagger aura (vanilla 16s, overtuned at top tier). Mutates `WeaponTraits.buff_templates.armor_breaker.buffs[1].duration` + the global `BuffTemplates` mirror; save-and-restore so toggling off restores vanilla.

### 0.7.29 — Activate Dormant Boons feature
9 dormant boons (defined in source but never registered in `DeusPowerUpRarityPool`) get individual activation toggles. When enabled, the boon is injected into the rarity pool and all derived runtime tables (`DeusPowerUps`, `DeusPowerUpsArray`, `DeusPowerUpsArrayByRarity`, `DeusPowerUpsLookup`, `DeusPowerUpBuffTemplates`) using the same construction pattern as vanilla's registration loop at `deus_power_up_settings.lua:7121-7176`. Includes: Mathlann's Bounty, Bögenauer's Prosperity, Nethu's Relentlessness, Grungni's Gift, Hashut's Greeting, timed-block free shot, Smednir's Transmutation, Chotec's Touch, Squats. Dormants appear in `starting_boons` with `(Dormant)` suffix; pulled from `disable_boons` since they only roll when activated.

### 0.7.30 — 4 new Mod Boons (per-boon scaling)
Modeled on vanilla's `boon_meta_01` (Lileath's Favour). Each scales different stats per total active boon count:
- **Reactive Bulwark** (`ct_meta_stagger`) — +1% stagger power + 1% melee cleave per boon
- **Crit Cascade** (`ct_meta_crit`) — +1% crit chance + 5% crit power per boon
- **Vitality Cascade** (`ct_meta_health`) — +1% max HP + 1% healing received per boon
- **Ability Cascade** (`ct_meta_cooldown`) — +2% cooldown regen per boon

New "Mod Boons" boon-tree category. Localize hook routes the display name and description keys.

### 0.7.31 — Home Brewer +50% potency for reworked potions
When the player holds Home Brewer (the `not_consume_potion` perk), the Moot Milk rework's numerical multipliers scale by 1.5x for that drink. Implementation: hook `BuffExtension.add_buff`, save the template's multiplier/bonus fields, scale, call vanilla add, restore. Multiplayer-safe via per-peer perk check.

### 0.7.32 — New Mod Boon: Khaine's Communion
Exotic-rarity mod boon: heal 1 permanent HP on every enemy kill. Server-authoritative proc with `authority = "server"`; `DamageUtils.heal_network` with `heal_from_proc` heal type. Catalogued under Defensive > Health by effect, prefixed `(Mod Boon)` in display name.

### 0.7.33 — Addaioth's Splendour description fix
Vanilla in-game text said "Every 30 seconds, ranged Critical Hits explode for 10% of their Damage" but the actual implementation uses cooldown_duration = 10 and damage = 30% (vanilla swapped the values positionally when filling description_values). Static loc override via the existing `_G.Localize` hook returns the corrected string.

### 0.7.34 — Trait-as-Boon: 4 traits as opt-in Unique-rarity boons
Per user request, four weapon traits get optional boon variants (each behind its own toggle, default off):
- **Vaul's Anvil** — naturally non-stacks with the trait (binary perk)
- **Manann's Tempest** — stacks with the trait (each fires its own chain lightning per crit)
- **Taal's Twinned Arrow** — stacks (+2 projectiles if both held)
- **Asuryan's Wrath** — melee-only via the existing proc filter; stacks with the trait (~75% effective proc chance with both)

`register_trait_boon` clones the source trait's buff template, registers a new power-up template, and injects via `inject_dormant_boon` at Unique rarity.

### 0.7.35 — New Mod Boon: Wind Cascade
Exotic-rarity mod boon: +1% movement speed per active boon. Uses `apply_movement_buff` (the only function that actually moves the player's speed needle in vanilla — plain `stat_buff = "movement_speed"` isn't read by anything). Each stack compounds via `1.01^N`; at 1% per stack the compounding diff is tiny (10 stacks = +10.5% vs +10% additive).

### 0.7.36 — Rework: Anath Raema's Swiftness permanent
Swaps the trait's on-ammo-pickup-temporary `+50%` reload speed (10s window) for a permanent passive reload speed while the weapon (with the trait) is wielded. Mutates both `WeaponTraits.buff_templates.deus_ammo_pickup_reload_speed` AND `BuffTemplates.deus_ammo_pickup_reload_speed` with save-and-restore.

### 0.7.37 — Crash fix: dormant boons at "common" rarity
**Crash:** `deus_power_up_utils.lua:208: attempt to index a nil value`. **Root cause:** `DeusPowerUpRarities` is `{ event, rare, exotic, unique }` — only 4 valid boon rarities. "common" and "plentiful" are weapon-drop rarities, NOT boon rarities. I'd injected `squats` and `deus_larger_clip` at "common" → `existing_power_ups_lut["common"]` was nil → crash on next shrine after rolling either boon. **Fix:** moved both to "rare". Memory saved: `reference_vt2_deus_power_up_rarities.md`.

### 0.7.38 — Crash fix: NetworkLookup.buff_templates missing entries
**Crash:** `network_lookup.lua:2514: [NetworkLookup.lua] Table buff_templates does not contain key: power_up_deus_timed_block_free_shot_exotic`. **Root cause:** my `inject_dormant_boon` was registering the buff in `DeusPowerUpBuffTemplates` and `BuffTemplates` but NOT in `NetworkLookup.buff_templates`. NetworkLookup has a metatable that throws on unknown keys. **Fix:** new `register_buff_in_network_lookup(buff_name)` helper called for every injected buff.

### 0.7.39 — Rework: Defeat Recovery (soft wipe rescue)
When the team would wipe and the toggle is on: each peer's coins are zeroed, each peer loses 5 random boons, host force-respawns dead/disabled players. Mission continues from the wipe point (NOT a full level reload — engine doesn't expose a safe mid-run reload path). Fires once per level via `_defeat_recovery_triggered_this_round` flag; resets on `_transition_next_node`.

### 0.7.40 — Crash fix: NetworkLookup.deus_power_up_templates missing entries
**Crash:** `network_lookup.lua:2514: [NetworkLookup.lua] Table deus_power_up_templates does not contain key: ct_boon_asuryan_wrath`. **Root cause:** vanilla has TWO separate NetworkLookup tables for boons — `buff_templates` (fixed v0.7.38) and `deus_power_up_templates`. The latter is used for power-up selection RPCs (chest pick, boon offer, grant). My injected boon names weren't there. Triggered when picking ANY boon at a chest while having an unregistered injected boon as a current power-up — the chest's add-and-resync re-serialized the full power-up list, hit the unregistered name, errored. **Fix:** new `register_power_up_in_network_lookup` helper called at the top of `inject_dormant_boon` for every injected boon (dormants, meta boons, ct_kill_heal, trait-as-boon variants).

## 0.7.28a-alpha (2026-05-15)

### Added: Rework — Trait Tier by Rarity

New toggle in `Reworks` group. When on, every weapon roll and altar upgrade picks a trait combo whose ALL traits are eligible for the rolled rarity (per the user-confirmed tier table walked 2026-05-15; see `TRAITS_REFERENCE.md` for the full per-trait assignment).

**Tier assignments** (34 traits total):
- **T1 Common** (9): Off Balance, Resourceful Combatant, Heroic Intervention, Parry, Resourceful Sharpshooter, Inspirational Shot, Rhya's Thorns, Anath Raema's Swiftness, Myrmidia's Great Leveller
- **T2 Rare** (9 + 2 overlap): Regrowth, Barrage, Hunter, Thermal Equalizer, Heat Sink, Opportunist, Bloodthirst, Deadeye, Follow Up + (Scrounger, Conservative Shooter)
- **T3 Exotic** (4 + 6 overlap): Divine Shield, Shockwave, Huanchi's Fangs, Swift Slaying + (Scrounger, Conservative Shooter, Anatha Raema's Talons, Vaul's Tempo, Asuryan's Wrath, Addaioth's Splendour)
- **T4 Unique** (6 + 4 overlap): Shard Strike, Asaph's Endless Quiver, Quetzl's Repulsion, Manann's Tempest, Taal's Twinned Arrow, Vaul's Anvil + (Anatha Raema's Talons, Vaul's Tempo, Asuryan's Wrath, Addaioth's Splendour)

**Implementation** (`chaos_wastes_tweaker.lua`):
- `TRAIT_RARITY_POOL` table maps each trait → set of allowed rarity strings (`{ common = true, rare = true, ... }`)
- `get_tier_filtered_combos(item_key, rarity)` filters the weapon's `baked_trait_combinations` to combos whose all traits are eligible for the rolled rarity
- `override_traits_in_result(result, rarity)` overwrites `result.traits` with a random tier-eligible pick
- Extended the existing trait-filter hooks (`generate_weapon`, `generate_weapon_for_slot`, `upgrade_item`) to also post-process via `override_traits_in_result`, and added a new hook on `generate_item_from_item_key`

**Side effects of the toggle:**
1. **Traits now roll at ALL rarities** — vanilla `deus_weapon_generation.lua:166-169` only rolls traits at Exotic/Unique. Our override doesn't rely on the vanilla rarity gate (we filter the original `baked_trait_combinations` ourselves), so Common and Rare weapons get traits too. This addresses the user's earlier "every upgrade should offer a trait" wish — every upgrade now does, because every rarity has a pool.
2. **Upgrades effectively reroll the trait** — each upgrade re-picks from the new rarity's pool, so the trait changes on every upgrade. Fulfills the "guaranteed reroll on upgrade" sub-toggle request from the trait walk.

**No-op cases (preserves vanilla):**
- Toggle off → no behavior change
- Weapon has no tier-eligible combos at the rolled rarity → vanilla result kept (probably empty `traits`, same as before)

### Deferred to v0.7.28b
- "Rework: Shard Strike duration" (nerf the 16s damaging aura — configurable)

## 0.7.27a-alpha (2026-05-15)

### Disambiguating prefixes on every boon menu label

Long dropdowns in the disable/start trees were ambiguous — you couldn't tell at a glance whether a given checkbox was a disable toggle or a start-boon toggle, especially after scrolling past the parent group header. Every item and group title now carries a path-aware prefix:

| Widget type | Disable side | Start side |
|---|---|---|
| Item (e.g., Attack Speed) | `Disable Boon: Attack Speed` | `Starting Boon: Attack Speed` |
| Group (e.g., Properties) | `Disable Boons: Properties` | `Starting Boons: Properties` |

Bulk regex transformation applied via PowerShell on `chaos_wastes_tweaker_localization.lua`:

- 172 item labels prefixed on each side (344 total item transformations)
- 10 group titles prefixed on each side (20 total group transformations)
- Tooltips left untouched (`*_tooltip` keys correctly excluded via negative lookbehind)

No tree-structure changes in this phase. v0.7.27b will rebuild the 10-group structure into the new 21-category structure documented in `BOON_CATEGORIZATION_DRAFT.md`.

Backup of original localization preserved at `chaos_wastes_tweaker_localization.lua.v0726.bak` for quick rollback if needed.

## 0.7.26-alpha (2026-05-15)

### Renamed "Modified Boons" group to "Reworks"

Broadens the umbrella to include potion reworks (and anything else we add later that mutates vanilla mechanics). Existing settings (Khaine's Fury tweak, Movement Speed boon tweak, bomb boon cooldown, Morgrim's toggles) are unchanged — only the group label and `setting_id` are renamed (`modified_boons_group` → `reworks_group`). Player-facing settings persist correctly because their own setting_ids are unchanged; VMF keys user values by individual `setting_id`, not by group path.

### Added: Tweak — Poison Proof potion lasts 4 minutes

Doubles the Poison Proof (gas/poison immunity) potion's duration from 120s to 240s. With Decanter, the `_increased` variant extends from 240s → 360s (still +50% over the new base). Implementation mutates `BuffTemplates.poison_proof_potion.buffs[1].duration` and the `_increased` sibling directly at mod load; vanilla's `action_potion.lua:68` resolution picks up `_increased` when `buff_perks.potion_duration` is held, so Decanter composition is automatic.

### Added: Tweak — Hangover Brew alternative effect

Replaces Hangover Brew's (`moot_milk_potion`) vanilla dodge-distance/dodge-speed buff with a different effect package:

- +25% movement speed (apply_movement_buff on `move_speed`)
- Unlimited dodges (`buff_perks.infinite_dodge`)
- +40% stamina regen (`stat_buff = "fatigue_regen"`)
- 60-second duration (90 seconds with Decanter, via `_increased` variant)

The visual `screenspace_drink` activation/loop effects are kept so it still feels like a potion. Implementation replaces `BuffTemplates.moot_milk_potion.buffs` with a 4-buff array (FX + MS + infinite dodge + stamina regen) at mod load; mirrors for `moot_milk_potion_increased`. Save-and-restore pattern matches the other tweaks so toggling off restores vanilla.

### Known limitation: Home Brewer composition deferred to v0.7.27

User asked for Home Brewer to provide a +50% potency boost on top of the rework. Home Brewer in vanilla is `not_consume_potion` (chance to refund the potion), not a potency boon — so the tweak would need:

1. New `<potion>_potion_brewed` and `<potion>_potion_brewed_increased` variants registered in `BuffTemplates`
2. Each variant added to `NetworkLookup.buff_templates` (else RPCs in `action_potion.lua:74` fail)
3. A hook on `ActionPotion:client_owner_buff_function` (or similar) to swap to `_brewed*` when `not_consume_potion` perk is held
4. Numeric scaling at variant-build time (multipliers × 1.5)

That's a 1-2 hour effort with its own test cycle. Splitting it out keeps v0.7.26 small and verifiable.

## 0.7.25-alpha (2026-05-15)

### Boon menu re-categorization (round 2 of 2): Ability Cooldown + Orbs groups

Per user verdict, boons whose primary benefit is ability cooldown reduction now live in their own "Ability Cooldown" group, and orb-like boons (which would otherwise be lumped in with the upcoming Vermintide Skulls event content) get their own "Orbs" group. The "Skulls" group is reserved exclusively for Vermintide Skulls event boons going forward.

**New group: "Ability Cooldown"** (6 boons) — moved out of Properties / Utility & Team:

- From Properties: `ability_cooldown_reduction`
- From Utility & Team: `cooldown_on_friendly_ability`, `deus_cooldown_reg_not_hit`, `deus_cooldown_regen`, `deus_skill_on_special_kill`, `friendly_cooldown_on_ability`

**New group: "Orbs"** (5 boons) — moved out of Combat / Defense / Healing / Utility:

- From Combat: `focused_accuracy`, `static_charge`
- From Defense, Damage Reduction & Parry: `protection_orbs`
- From Healing, THP & Health Gain: `health_orbs`
- From Utility & Team: `sharing_is_caring`

Source groups (Properties, Combat, Defense/DR/Parry, Healing/THP, Utility & Team) lose those entries respectively. Both the `disabled_boons_group` and `starting_boons_group` mirror trees are updated in lockstep, and `recursive_sort` auto-alphabetizes the four new sub-groups by display name.

## 0.7.24-alpha (2026-05-14)

### Fixed: Khaine's Fury (`tweak_reckless_swings`) — damage tweak silently failed

User reported the Khaine's Fury softening tweak didn't actually soften the damage even with the toggle on. Root cause: the apply/revert functions were mutating `DeusPowerUpBuffTemplates.deus_reckless_swings_buff.buffs[1].damage_to_deal` — but the runtime buff system reads from the global `BuffTemplates` table, which received COPIED values via `DLCUtils.merge` at game boot (`buff_templates.lua:9532`). Mutating the source `DeusPowerUpBuffTemplates` had zero effect on what the proc function `deus_reckless_swings_buff_on_hit` actually read at hit time (`template.damage_to_deal` still 3).

Fix: mutate `BuffTemplates.deus_reckless_swings_buff.buffs[1].damage_to_deal` directly instead of the source `DeusPowerUpBuffTemplates`. The outer `health_threshold` tweak via `DeusPowerUpTemplates` was already correct (the apply path at `deus_power_up_utils.lua:250` reads that table directly), so it kept working — only the per-hit damage was uncorked.

Effect: with the toggle on, melee hits now deal 1 self-damage instead of 3, matching the displayed tooltip text. Host-side mutation suffices because the proc function is `is_server()` gated and damage is networked via `add_damage_network`.

## 0.7.23-alpha (2026-05-14)

### Diagnostic: verbose logging on chest-of-trials revive hook

User reports `respawn_on_chest_complete` isn't working. Setting was confirmed `true` in user_settings, hook registered correctly in last session's log, but no observable revives. Added `mod:info` lines to `DeusCursedChestExtension._set_state` hook so the next log shows:

- Whether `_set_state` fires at all, and which state value (verifies the hook isn't being shadowed and state OPEN is being reached).
- Setting value, `is_server` flag (verifies the host-only + setting-on gates pass).
- Per-slot dump at chest-open time: peer_id, `health_state`, `unit_alive`, `is_knocked_down`, `is_disabled_by_pact_sworn`.
- Whether `StatusUtils.set_revived_network` was called (knocked-down branch).
- Whether `pending_chest_respawn[peer]` was set (dead branch).
- Whether `game_mode:force_respawn_dead_players()` was called.

If chest-revive is working but not noticed (host-only hook + no dead teammates during testing), the log will show empty branches. If the hook isn't firing at all, that narrows the diagnosis to either wrong `state` value, missed `is_server` gate (testing as client), or shadowed hook. Strip the logging once root cause is fixed.

## 0.7.22-alpha (2026-05-14)

### Boon menu re-categorization (round 1 of 2)

Started reorganizing the 172-boon disable / starting-boon menus into more cohesive categories. Categories 1 and 2 done this round; remaining 5 groups TBD.

**New group: "Defense, Damage Reduction & Parry"** — aggregates 23 boons that were previously scattered across Properties / Combat / Healing & Sustain:

- From Properties: `block_cost`, `protection_aoe`, `protection_chaos`, `protection_skaven`, `push_block_arc`, `stamina`
- From Combat: `barkskin`, `deus_block_procs_parry`, `deus_damage_reduction_on_incapacitated`, `deus_parry_damage_immune`, `deus_push_cost_reduction`, `deus_standing_still_damage_reduction`, `deus_timed_block_free_shot`, `explosive_pushes_on_damage_taken`, `missing_health_power_up`, `pent_up_anger`, `skill_by_block`, `speed_over_stamina`, `static_blade`, `thorn_skin`
- From Healing & Sustain: `deus_knockdown_damage_immunity_aura`, `hidden_escape`, `protection_orbs`

**Renamed: "Healing & Sustain" → "Healing, THP & Health Gain"** with reshuffled contents:

- Gained: `health` (from Properties), `resolve` (from Combat), `deus_coin_pickup_regen` (from Utility & Team), `boon_supportbomb_healing_01` (from Bombs)
- Lost: the three boons moved to Defense/DR/Parry above

**Other moves (per user verdicts):**

- `last_player_standing_power_reg`: Combat → Utility & Team (user verdict — utility)
- `deus_push_charge`, `deus_push_increased_cleave`: stayed in Combat (user verdict — offense, even though they're push-related)

The `recursive_sort` helper now also auto-sorts the new `disable_boon_defense_and_dr_group` and `start_boon_defense_and_dr_group` alphabetically by display name. Both `disabled_boons_group` and `starting_boons_group` mirror trees have been updated in lockstep.

Categories still pending (TBD next session): Combat (further split into damage / crit / ranged / etc.?), Utility & Team, Bombs, Skulls & Sets, Talents, Properties. User to provide further verdicts.

## 0.7.21-alpha (2026-05-14)

### Added: Host→client settings sync (clients now see host's curse layout, not vanilla)

v0.7.20 fixed the shop_view nil crash by gating the `deus_populate_graph` hook on `is_server` — clients passed through to vanilla, never crashed. But clients still produced a VANILLA local graph while host produced a MUTATED one, so the map and theme on each peer differed (client saw wrong curse on a mission, wrong god on the map).

v0.7.21 replaces the `is_server` gate with proper sync:

1. **Host broadcasts effective settings** at the end of `DeusRunController.setup_run` via VMF's `mod:network_send`. Sent BEFORE the engine's `full_sync` RPC so clients receive the settings before their own `setup_run` triggers `deus_populate_graph`. Settings synced: `cursed_mission_count`, `replace_shrines_with_missions`, `disable_dominant_god`.
2. **Clients receive and stash** in a `_ct_host_settings` table via `mod:network_register("ct_sync_host_settings", ...)`.
3. **The graph hook uses `effective_setting(name)`** instead of `mod:get(name)`. On host this returns the user's actual setting; on client it returns the host's most-recently-broadcast value. If the broadcast hasn't arrived yet (first run, RPC ordering), falls back to vanilla-equivalent defaults — same safety as v0.7.20's gate.

Net effect: with host running e.g. `cursed_mission_count = 30, disable_dominant_god = true`, all peers now produce the same graph from the same seed. Map shows the same cursed nodes for everyone, themes match, no more "wrong curse on a mission" desync.

### Tweaked: Belakor lighting — brightened interior, slightly dimmed exterior

User feedback: Belakor interiors were almost pitch-black. Bumped `ambient_tint` from `{0.45, 0.40, 0.75}` to `{0.75, 0.65, 1.00}` (brighter purple-ish bounce), `ambient_tint_top` from `{0.35, 0.30, 0.80}` to `{0.60, 0.55, 1.00}` (brighter zenith), `secondary_sun_color` slightly brighter too. `skydome_tint_color` and `sun_color` dimmed slightly so the outdoor still feels oppressive. `exposure_mul` from 0.85 → 0.92 (less overall darkening).

## 0.7.20-alpha (2026-05-14)

### Fixed: `deus_shop_view_v2.lua:182: attempt to index field '_shop_config' (a nil value)` crash on client when host/client mod settings differ

Crash reported by user (client) when client had `replace_shrines_with_missions = true` (shops off, converted to missions) and host had it false (vanilla shops on).

Root cause: CW graph generation is deterministic from seed — both peers call `deus_populate_graph` independently (`rpc_deus_setup_run` triggers it on clients). Our hook fired on BOTH peers with their own settings:
- Host: hook saw `replace_shrines_with_missions = false`, no mutation, graph kept SHOP nodes with `level = "shop_strife"` etc.
- Client: hook saw `replace_shrines_with_missions = true`, converted SHOP→TRAVEL with `label = 0`, vanilla level picker then rolled a random TRAVEL level (e.g. `pat_mountain_wastes_path1`) for that node.

Host transitioned the run to the shop node and loaded `shop_strife.level`. Shop UI opened on both peers via flow events. Client's `DeusShopSettings.shop_types[<client's mutated level>]` returned nil → crash on the `_shop_config.blessings` index.

Fix: gate the entire `deus_populate_graph` hook behind `Managers.player.is_server`. Clients now pass straight through to vanilla; their local graph matches what host would have generated without our overrides. UI lookups won't nil-crash because every node has its vanilla level/type. Host's mutations still drive the authoritative shared state.

This same fix prevents future similar bugs from `cursed_mission_count`, `disable_dominant_god`, `filter_available_curses`, and any other graph-modifying override that has differing values between peers.

## 0.7.19-alpha (2026-05-14)

### No code changes — version bump to force Steam Workshop CDN refresh

Friend's subscriber client pulled v0.7.17 despite v0.7.18 being uploaded and the Steam Web API correctly reporting `file_size = 1,399,303`. Steam CDN edges can serve stale content for hours after a metadata update. Bumping MOD_VERSION (visible in chat echo) changes the bundle hash and forces fresh CDN propagation.

## 0.7.18-alpha (2026-05-14)

### Added: `disable_dominant_god` checkbox (default on)

The "all 4 gods rotate uniformly" behaviour from v0.7.14 is now a user-toggleable setting in the Run Structure group. Default on (matches v0.7.14+). Toggle off to restore vanilla CW's "dominant god is reserved for the finale, never appears on regular missions" rule. Independent of `cursed_mission_count` — works at any count value including 0.

### Tweaked: Curse-node exterior shading-env profiles softened (~30% pull toward neutral)

User feedback: Khorne, Nurgle, and Tzeentch exterior tints (sky / sun / ambient / fog) were "oppressive" — the outdoor color saturated the whole scene. Each value pulled approximately 30% toward neutral (1.0):

- Khorne fog `{1.55, 0.25, 0.20}` → `{1.39, 0.48, 0.44}` (less blood-bath)
- Nurgle skydome `{0.45, 1.30, 0.40}` → `{0.62, 1.21, 0.58}`
- Tzeentch sun `{1.55, 0.60, 0.20}` → `{1.39, 0.72, 0.44}` (less deep-orange punch)

Slaanesh and Belakor untouched (user said Slaanesh looks great; Belakor not flagged). Per-light point-light palettes also untouched — those are doing their job; the issue was just the overarching exterior color washing the scene.

## 0.7.17-alpha (2026-05-14)

### Tweaked: Tzeentch lights now 100% deep blue, outdoor light pushed to deep orange

User feedback v0.7.16: "more blue on tzeentch for sure — make all the lights and most of the natural lights a magic blue, but then have just the overarching outdoor light be a deep orange."

- **Per-light palette**: dropped the 10% cool-white slot. 100% of Light components are now deep magic blue (75% deepest cobalt, 25% mid cobalt variant). Caveat: vanilla torches that get their warm glow from particle FX / self-illumination materials (not from Light components) will still look warm — pulling those cool would need a separate hook on the particle effect registry. Holding off until you say it matters.
- **Outdoor shading env**: sun, secondary sun, and ambient pushed from "warm orange" to "deep orange" (R 1.40→1.55, G 0.75→0.60, B 0.35→0.20 on sun_color; same shape for ambient + ambient_top). Fog stays cool blue, sky stays cobalt. Result should read as: cobalt sky with deep-orange sunlight pouring through, hitting magic-blue rooms.

## 0.7.16-alpha (2026-05-14)

### Fixed: `terror_event_mixer.lua:1662: attempt to index a nil value` crash on adventure-injected nodes

Crash reproduced on a `nurgle_tzeentch_path1` node (Festering Ground under tzeentch theme). The level's flow fires `start_random_event("nurgle_end_event_loop")`, which evaluates `WeightedRandomTerrorEvents[level_key][event_chunk_name]` at terror_event_mixer.lua:1595. Our injected adventure permutation keys (`<base>_<theme>_path<n>`) don't have entries in `WeightedRandomTerrorEvents` (vanilla builds it from `LevelSettings` at boot, before our pool injects), so the lookup returns nil and the indexer crashes.

Same fix shape as the existing `TerrorEventBlueprints` mirror in `_adventure_pool.lua`: when injecting each permutation key, also mirror `WeightedRandomTerrorEvents[base_lvl]` to `WeightedRandomTerrorEvents[permutation_key]` if a base entry exists. Adventure end-event chunks now resolve to the same set the base adventure level uses.

## 0.7.15-alpha (2026-05-14)

### Tweaked: Tzeentch point lights are now all deep blue, no accents

v0.7.13 kept some magenta + mint in the Tzeentch per-light palette as variety. User feedback: too much mix; wants every mod-tinted point light to be deep blue, and the warm orange (already set on sun_color / ambient_tint in v0.7.13's shading env profile) to be the only source of warmth in the scene. Reduced palette to just two deep-blue variants + a tiny cool-neutral slot:

- 65% **deep cobalt** (saturated, darker than the v0.7.13 dominant — `{ 0.20, 0.35, 1.45 }`)
- 25% mid cobalt variant (`{ 0.30, 0.55, 1.35 }` — still deep blue, slightly varied)
- 10% cool white spark (`{ 1.00, 1.05, 1.15 }` — rare neutral)

No magenta, no mint, no warm orange in per-light. Vanilla torches stay warm naturally; warm orange ambient/sun comes from the shading-env profile.

## 0.7.14-alpha (2026-05-14)

### Fixed: `cursed_mission_count` override never gave Khorne curses when journey's dominant god was Khorne

User reported 4 runs in a row with no Khorne-themed cursed missions. Log confirmed: `dominant god <khorne>`, and the 13/13 cursed nodes were distributed nurgle/slaanesh/tzeentch only — the final node was the only one to receive a Khorne curse (`curse_khorne_champions` on `arena_ruin_khorne_path1`).

Root cause: vanilla `spread_curse` (deus_populate_graph.lua) reserves the dominant god exclusively for the "final" node (line 686-690) and then EXCLUDES it from the non-final rotation (line 698 — `if NO_DOMINANT_GOD or god ~= context.dominant_god then`). With dominant=khorne, the 12 non-final cursed nodes can only pick from {nurgle, tzeentch, slaanesh}.

Fix: when our count override is active, also set `config.NO_DOMINANT_GOD = true`. All 4 gods enter the uniform rotation. Final loses its "always dominant" guarantee but with `count >= total_curseable` it gets cursed anyway (by whichever god the rotation picks). Saved/restored alongside the other override fields.

## 0.7.13-alpha (2026-05-14)

### Tweaked: Tzeentch lighting — keep point lights cool, warm orange comes from sun/ambient

v0.7.11's Tzeentch palette added a 25% warm-orange complement to per-light tinting. User feedback: vanilla level torches are already warm orange, so adding more warmth to point lights double-saturates the warm channel without producing the contrast we wanted — Tzeentch nodes still read as "blue blue blue" with no real visual pop.

Better approach: keep per-light point lights all cool (blue / magenta / mint / white) and deliver the warm complement via the **sun_color + ambient_tint + secondary_sun_color** entries in the per-frame ShadingEnvironment profile. Daylight + skybounce pours warm orange across the scene; torches stay warm-orange (vanilla); magic point lights stay cool blue (mod). Net visual: cobalt sky lit by warm orange sun rays — strong color separation by light type.

Per-light Tzeentch palette is now blue-dominant: 55% cobalt blue / 20% magenta aurora / 15% cool white / 10% mint. No warm orange in the palette — that's the sky/sun's job now.

## 0.7.12-alpha (2026-05-14)

### Fixed: `cursed_mission_count` override didn't curse the very first nodes (run_progress=0)

v0.7.9-alpha lowered `CURSES_MIN_PROGRESS` to `0` so early nodes would be eligible — but vanilla's `get_nodes_above_progress` (deus_populate_graph.lua:45-55) uses **strict** `progress < node.run_progress`, so nodes with `run_progress = 0` got `0 < 0 = false` and stayed filtered out. User's v0.7.11 run: 14/16 cursed, the missing 2 were the first nodes at run_progress 0 / 0.16. Fix: set `CURSES_MIN_PROGRESS = -1` instead, so `-1 < 0 = true` and the first-mission nodes are in the candidate pool.

With `cursed_mission_count >= total_curseable`, this guarantees every node (including the first 1-2) gets a curse — what the user explicitly wanted.

## 0.7.11-alpha (2026-05-14)

### Tweaked: Curse light palettes — stronger contrast, added neutral white slot

v0.7.10's palettes were still too monotone on Tzeentch (the "cyan ice" complement was too close to its cobalt-blue dominant — visually "blue blue blue"). Rebalanced every god to:

1. **Drop dominant weight** from 50% → 35-40% so more lights pick up accents.
2. **Add a neutral white-ish slot** (15-20% of lights). User feedback that Slaanesh's purple looks good with white light sources generalizes — leaving some lights uncolored makes the colored ones register as deliberate accents instead of the whole scene saturating to one hue.
3. **Use true color-wheel complements** instead of nearby hues:
   - Khorne (red) → cold cyan (was warm gold)
   - Nurgle (green) → pustule magenta (was swamp teal — fine accent but not a complement)
   - **Tzeentch (blue) → warm orange** (was warm gold — orange is the true blue complement, 25% weight, much more contrast)
   - Slaanesh (pink) → yellow-green
   - Belakor (purple) → pale gold
4. Keep an accent slot of a related hue + a small "secondary pop" slot for visual variety in dim corners.

Distribution remains deterministic per light-index hash (`idx * 7919 + 11`), so the look is repeatable per level. The user can compare directly to v0.7.10 by re-entering the same cursed node.

## 0.7.10-alpha (2026-05-14)

### Improved: Cursed-node level lights use a per-curse palette instead of one flat tint

v0.6.x → v0.7.9 painted every level light in a cursed adventure mission the same RGB (e.g. all-blood-red for Khorne) — too monotone. Replaced with per-curse PALETTES: each god gets a dominant color plus accent / warm counterpoint / complementary contrast shades. Lights are deterministically distributed across the palette buckets (50% dominant / 25% accent / 10% warm / 15% complement), so adjacent lights tend to group but the room as a whole reads as themed atmosphere rather than monochrome.

Per-curse identity preserved:
- **Khorne**: blood red dominant, ember orange accent, gold-flame warm pop, cold steel-blue complement
- **Nurgle**: bog green dominant, jaundiced yellow accent, pustule magenta pop, swamp teal complement
- **Tzeentch**: cobalt blue dominant, magenta aurora accent, warm gold flicker, cyan ice complement
- **Slaanesh**: hot pink dominant, deep purple accent, teal yellow-green complement, peach warm pop
- **Belakor**: twilight purple dominant, moonlight blue accent, pale yellow-green ghost complement, shadow violet counterpoint

The distribution hash is stable across game loads (`(idx * 7919 + 11) % total_weight`) so the same level always lights the same way for a given curse — no per-frame rainbow noise.

## 0.7.9-alpha (2026-05-14)

### Diagnostic: cursed_mission_count=30 → 8 cursed nodes confirmed, halo invisible because of node-unit prefix matching

v0.7.8 diagnostic revealed `spread_curse` IS cursing 8 of 11 curseable nodes (so the override works); the visual is missing because `DeusMapScene.spawn_graph_units` (`scripts/ui/views/deus_menu/deus_map_scene.lua:182`) picks the 3D node mesh by string prefix on `node.level`:
- `pat_*` → TRAVEL_NODE_UNIT (has cursed-halo flow events)
- `sig_*` → SIG_NODE_UNIT
- `arena_*` → ARENA_NODE_UNIT
- else (e.g. `military_*`, `nurgle_*`, `farmlands_*`, `dlc_castle_*`) → SHRINE_NODE_UNIT (no halo flow events)

All 8 of the user's cursed nodes use adventure-injected level base names (`military` → Righteous Stand, `nurgle` → Festering Ground, etc.) which don't match any of the vanilla prefixes — so they all render as SHRINE_NODE_UNIT and the halo never appears.

The mod already has a `DeusMapScene.on_enter` hook that rewrites adventure-base level keys to `pat_<icon>_<theme>_path1` before the unit-spawn loop runs. That should fix the visual — but the diagnostic doesn't confirm whether it's firing for the user's graph. This release adds per-node log lines so v0.7.9's log will show exactly how many nodes the hook rewrites and which keys it skips.

### Fixed: `cursed_mission_count` override skips nodes below `CURSES_MIN_PROGRESS`

Same override block now also drops `CURSES_MIN_PROGRESS` to 0 for the duration of `func()`. Vanilla's filter (typically 0.2) was excluding the first 2-3 nodes of every journey from being cluster-center candidates. With `range=0` (exact count), those early nodes were guaranteed-uncursed even when the user set count=30. The user's v0.7.8 dump showed 3 uncursed nodes at progress 0/0.16/0 — all dropped by the filter. Lower it so the early run is also fair game. Saved/restored alongside the existing range/count fields.

## 0.7.8-alpha (2026-05-14)

### Diagnostic only: fix `count_cursed` to read the right field

v0.7.5 / v0.7.6's diagnostic counted nodes by `n.type == "TRAVEL"` etc., but the completed graph returned by `deus_populate_graph` uses `n.node_type` ("ingame"/"shop"/"start") — `type` only lives on the BASE graph (input). My counter never matched any node and reported `cursed=0 / total_curseable=0` on every run, including ones that almost certainly had curses applied. Switched to `n.node_type == "ingame"` and added a `dump_graph` helper that logs EVERY node (cleanly tagged) so we can see the real state. Re-run with v0.7.8 to get accurate cursed-count numbers.

## 0.7.7-alpha (2026-05-14)

### Added: `tweak_boon_movespeed` — double the Movement Speed property boon (5% -> 10%)

New checkbox in the Modified Boons group. The Movement Speed boon is a one-of-a-kind reward awarded on mission completion in Chaos Wastes (boon-treated, not a buff stack). Vanilla `MorrisBuffTweakData.movespeed` is `{ description_value = 0.05, multiplier = 1.05 }`. `deus_power_up_settings.lua` bakes both into runtime tables: the multiplier into `DeusPowerUpBuffTemplates.power_up_movespeed_{common,rare,legendary}.buffs[1].multiplier` (1.05 in all three rarity entries), and the description_value into `DeusPowerUpTemplates.movespeed.description_values[1].value` (single 0.05 entry, referenced by all rarities). The tweak save-and-restores both: writes 1.10 to each rarity's multiplier and 0.10 to the description value. The in-game tooltip auto-reflects "10%" because vanilla `description_properties_movespeed` is formatted off `description_values`.

Mirrors the reckless_swings pattern: forward-declared `sync_boon_movespeed`, called from the boon-roll hook (post-call), `on_setting_changed`, and at mod load; reverted from `on_disabled` so toggling the mod off cleans up the persistent DeusPowerUpBuffTemplates / DeusPowerUpTemplates mutations.

## 0.7.6-alpha (2026-05-14)

### Diagnostic only: extended `deus_populate_graph` logging for the `cursed_mission_count` debug

v0.7.5-alpha added a `post-run cursed=N / total_curseable=M` log but only in the `replace_shrines_with_missions = OFF` branch. The user's failing scenario has the toggle ON, so the log never fired. This release moves the count + dumps every curseable node's `curse`, `god`, `progress`, and `level` so we can see exactly which nodes ended up cursed and which were skipped. No behavior change otherwise.

## 0.7.5-alpha (2026-05-14)

### Improved: Cursed-node atmosphere lighting (richer per-curse profiles)

v0.7.2-alpha's curse sky tint applied one flat RGB multiplier across every shading variable, so e.g. a Khorne node became a single saturated red blanket. Replaced with per-curse PROFILES that tint each shading-environment variable differently — sky, sun, secondary sun, ambient, ambient top, fog, and exposure all get their own multiplier per curse. The result reads as themed atmosphere ("sunset over a burning landscape", "rotten daylight in a bog") rather than a single-color filter.

Color identity is preserved: red Khorne, green Nurgle, blue Tzeentch, pink Slaanesh, dark purple Belakor. But each curse gets accent variation (e.g. Khorne sun is warm orange against a deep red sky; Tzeentch sun has a magenta-aurora glow against cobalt sky).

### Added: Diagnostic logging on `deus_populate_graph` (cursed-mission count debugging)

User reported `cursed_mission_count = 30` produced zero visibly-cursed nodes on Olesya's map. Adding two `mod:info` lines to the existing `deus_populate_graph` hook to confirm (a) the override was read correctly and applied, and (b) how many cursed nodes vanilla's `spread_curse` actually produced in the completed graph. Both log under the `[deus_populate_graph]` prefix.

## 0.7.4-alpha (2026-05-14)

### Fixed: `Join failed - Game version mismatch` when peer has Adventure Maps injection on

Symptom: a player with `inject_adventure_maps` enabled couldn't join a friend hosting without it (or any vanilla lobby) — Steam reported "Game version mismatch" even though mod versions, network_hash, trunk_revision, and engine_revision were all identical between peers.

**Root cause.** VT2's `LobbyAux.create_network_hash` (lobby_aux.lua:26) folds `num_levels = #NetworkLookup.level_keys` into the lobby `combined_hash` that all peers compare at join time. Our `_adventure_pool.lua` registers a new level_keys entry for every injected adventure permutation (each enabled campaign / event mission × 6 themes — see `register_network_lookup_key`); without that registration the multiplayer level-load RPC fatals on a strict `__index` ("Table level_keys does not contain key"). The cost: vanilla `num_levels` ≈ 582, fully-injected ≈ 774. Peers with mismatched counts produced different `combined_hash` values and the matchmaker rejected the join.

Concretely from the failing-join log: client `combined_hash=528235b057837034 num_levels=774` vs host `combined_hash=d0ec3cbd18a2bce0 num_levels=582`, with every other hash input identical.

**Fix.** Hook `LobbyAux.create_network_hash` and temporarily nil out the injected `NetworkLookup.level_keys` entries (indices strictly greater than the vanilla count, captured once at mod load before `inject_pool` runs) for the duration of the call, then restore. Lua's `#` operator returns the contiguous-prefix length, so the vanilla hash-creation code sees vanilla `num_levels` regardless of how much we've injected. Entries are restored before the hook returns so the in-game level-load RPC, which indexes the same table, continues to work.

**Effect.**
- Peers with `inject_adventure_maps` on can join vanilla or non-matching peer lobbies. Hash matches.
- Peers hosting CW with injection on advertise a vanilla lobby hash, so vanilla peers can also join.
- Vanilla CW scenarios play correctly cross-config. The host's `LevelSettings` lookup uses string keys that exist in both configurations.

**Caveats.**
- Picking an injected adventure mission as host while a vanilla peer is in the lobby still crashes the vanilla peer: their `NetworkLookup.level_keys` doesn't contain the injected permutation key, so the level-load RPC fatals on the strict `__index`. Workaround for now: when hosting cross-config, pick a vanilla CW scenario, not an injected adventure node. A future revision could surface peer-side mod state in lobby_data to gate injected-level selection automatically.
- Other mods that legitimately register new `NetworkLookup.level_keys` entries would also be hidden by this shim. If you ever add such a mod, change `_vanilla_level_keys_count` to capture a baseline that includes those entries (or move ct's capture into a deferred init that runs after all level-mutating mods have loaded). Not a problem today — no sibling mod in the active set touches `level_keys`.

Reference: memory entry `reference_vt2_lobby_combined_hash.md` documents the full hash composition and `num_levels` source. The shim follows the pattern from `feedback_vmf_hook_safe_no_chain.md` (single mod:hook on `LobbyAux.create_network_hash` so no chain-shadow risk).

## 0.7.3-alpha (2026-05-14)

### Fixed: `[NetworkedFlowStateManager] Too many object states(512)` crash

Vanilla Fatshark bug. `NetworkedFlowStateManager.clear_object_state` (networked_flow_state_manager.lua:493) nils `_object_states[unit]` when a unit is destroyed but **never decrements `_num_states`**. The counter is monotonic — `_num_states` only grows, and the run fatals once it hits `_max_states` (512). Every destroyed unit that ever held a networked flow state permanently leaks its slot.

Hits hardest in CW runs with adventure-mission injection + curses: the `cursed_chest_objective_unit` buff is applied to every cursed-chest enemy spawn (`apply_objective_unit` in morris_buff_settings.lua:614) which spawns a `units/hub_elements/objective_unit` carrying a `chest_open_state` networked flow state. Each enemy = 1 permanently-leaked slot. Reproduced ~40 min into a Verminious Dreams khorne node after 2 Chests of Trials were activated (crash dump `console-2026-05-14-03.23.33-d86fd894-...`).

Fix: hook `NetworkedFlowStateManager.clear_object_state` to count the states being released and subtract from `_num_states` before delegating to vanilla. One-line vanilla-bug patch.

## 0.7.2-alpha (2026-05-13)

### Added: Curse sky / atmosphere tinting on adventure missions

The per-light tint from v0.6.x only colored individual point/spot lights — adventure-level skies, sun, and atmospheric fog stayed vanilla, so cursed adventure missions looked "too normal." This release adds per-frame multiplicative tinting of the live ShadingEnvironment.

Pattern lifted from Peregrinaje (bundle-unpacked from Workshop install — file 92BC0C4E7BFF8C3A.lua referenced `ShadingEnvironment.set_scalar`, `skydome_tint_color`, `sun_color`, `secondary_sun_color`, `ambient_tint`, `ambient_global_tint`, `fog_color`, `exposure`, `apply_environment_variables`). Implementation:

- `hook_safe` on `CameraManager.shading_callback` so we run AFTER vanilla `MoodHandler.apply_environment_variables` (camera_manager.lua:346) — our curse tint multiplies the post-mood color.
- Gates: only fires on injected adventure levels with a non-`wastes` node theme (khorne/nurgle/tzeentch/slaanesh/belakor).
- Variables tinted: `skydome_tint_color`, `sun_color`, `secondary_sun_color`, `ambient_tint`, `ambient_tint_top`, `fog_color`.
- Per-curse multipliers tuned to be visible without flattening the scene.
- No save/restore: Stingray re-seeds the shading_environment from the level's baked template every frame, so leaving the cursed node automatically restores vanilla atmosphere.

## 0.7.1-alpha (2026-05-13)

### Fixed: Chest of Trials no longer interactable

v0.6.28–v0.7.0 hooked `_spawn_pickup` to mutate the chest's physics actors (scene_query / collision_filter / collision_enabled) in an attempt to make altars/chests walk-through on adventure levels. Each variant broke chest interaction. Reverted the entire actor-manipulation hook.

Researched the Peregrinaje mod's source (bundle-unpacked from Workshop install): Peregrinaje does NOT touch chest collision — it relies on vanilla pickup-spawn flow with `with_physics = false`, which destroys an actor named `"pickup"` via `PickupUnitExtension.set_physics_enabled` (pickup_unit_extension.lua:125-135). That actor is only a small trigger zone though; the chest's main collision body stays. In vanilla CW the level designer places altars/chests in alcoves so they're never on the path — there is no engine mechanism that makes them walk-through on demand.

Accepting that altars/chests can block on adventure-level injections (per user direction: "give up on collisions"). The chests are now back to interacting properly.

### Fixed: Campaign potions appearing when `enable_campaign_potions` is off

Defensive cleanup at the top of `populate_pickups`: when the toggle is off, scrub `damage_boost_potion`, `speed_boost_potion`, `cooldown_reduction_potion` from `Pickups.deus_potions` every call. Guards against a mid-flight error in a previous (toggle-on) call leaving the campaign-potion clones in the table.

## 0.7.0-alpha (2026-05-13)

First experimental public release. Marks the formal opening of the mod to a broader audience after months of internal iteration. Title changed to "Tweaker: Chaos Wastes" (was "Tweaker: Chaos Wastes (WIP)"), Workshop description rewritten to cover the full feature surface, new thumbnail in place.

Headline since the last released build: the **Adventure Maps in Chaos Wastes** subsystem. Adventure missions are now injectable into the CW random map pool with full mission lifecycle (curses, boons, finale routing) intact: tomes/grims become Chests of Trials, pickups rewrite to CW types, altars seed at 5/map (1 upgrade + 1 melee swap + 1 ranged swap + 2 boon), cursed nodes carry the matching sky/lighting tint, and altars/chests use `filter_trigger` so the player walks through them.

## 0.6.33-dev (2026-05-13)

### Fixed: Event barrels spawning as potions (broke scripted events)

`_can_spawn` hook was returning true for `deus_potions`/`deus_soft_currency`/`deus_weapon_chest` on EVERY adventure spawner (except tome/grim), including **triggered event spawners** for scripted lamp_oil / explosive_barrel / training_dummy_bob spawns. `_spawn_guaranteed_pickup` iterates all pickup names asking `_can_spawn` for each, then picks randomly from candidates — so a triggered barrel-spawner could roll `healing_draught` instead of `lamp_oil` and break the scripted event.

Fix: in the `_can_spawn` adventure-fallback, also short-circuit to `false` when:
- `Unit.get_data(spawner, "guaranteed_spawn")` is truthy (book / specified spawners)
- `Unit.get_data(spawner, "triggered_spawn_id")` is a non-empty string (event-driven spawners)

CW types still flow onto generic primary spawners (the ones without any specific event tag) so coin / potion / altar counts are unaffected.

## 0.6.32-dev (2026-05-13)

### Fixed: Chest of Trials interaction broken in v0.6.28+

v0.6.28's `Actor.set_scene_query_enabled(actor, false)` made altars/chests walk-through BUT broke interaction with them. Cause: `GenericUnitInteractorExtension._find_best_interaction_unit` (interactor extension line 254) discovers interactables via `PhysicsWorld.immediate_overlap(..., "collision_filter", "filter_overlap_interaction")` which needs scene_query=true on the actor. The "proximity check" assumption in the v0.6.28 comment was wrong — interaction discovery is scene-query-driven.

Fix: revert scene_query disable. Instead, reclassify the actor's collision filter to `filter_trigger` via `Actor.set_collision_filter` — the vanilla "non-blocking interactable" filter (see `ai_utils.lua:521` for the canonical pattern). The player_mover sweep ignores `filter_trigger` actors so the player walks through; raycast overlaps still hit them so interaction works.

`set_collision_enabled(false)` is also kept as belt-and-braces but the filter change is the load-bearing piece.

## 0.6.31-dev (2026-05-13)

### Fixed: Exact cursed-mission count

Setting `cursed_mission_count` was driving `CURSES_HOT_SPOTS_MIN/MAX_COUNT` only, but vanilla `spread_curse` (deus_populate_graph.lua:681) then *spread* each cluster center to neighbouring nodes within `CURSES_HOT_SPOT_MIN_RANGE..MAX_RANGE`, so requesting N would typically yield 5–15 cursed nodes. Fix: when the override is active, also force `CURSES_HOT_SPOT_MIN_RANGE = MAX_RANGE = 0` so each cluster curses only its center node. Both ranges are saved before the override and restored in `restore_curse_count` so vanilla CW spread behaviour returns intact when the setting is back to 0.

## 0.4.1-dev (2026-05-10)

### Fixed: `<<1>>`..`<<9>>` in altar count dropdowns

The four altar-count dropdowns (Upgrade / Melee Swap / Ranged Swap / Boon Altars) showed `<<1>>` through `<<9>>` instead of plain `1`–`9`. Cause: `altar_count_options` used `text = "1"`..`"9"` as labels, expecting VMF to fall through to the literal string when no loc entry matched. VMF actually wraps missing keys in `<<>>`. Fix: added explicit `["1"]` … `["9"]` entries in `_localization.lua`. Updated the misleading comment in `_data.lua` to document the real VMF behaviour.

## 0.4.0-dev (2026-05-10)

### Added: Bomb-boon balance toggles

Four new toggles in **Modified Boons** group, sourced from a community balance thread:

- **Bomb Boon Cooldown (s)** — uniform cooldown override for the *Drop bomb on ability use* boon. Vanilla per-item cooldowns are 180s (Rally Flag), 180s (Morgrim's Bomb), 120s (Endless Bombs Potion); a single positive value here applies uniformly to all three. 0 = vanilla. Implemented by mutating `DeusPowerUpTemplates.drop_item_on_ability_use.buff_template.buffs[1].cooldown_durations` (read at proc time in `morris_buff_settings.lua:2830`). Mirrors the Khaine's Fury save-and-restore pattern; reverts on `on_disabled` and re-applies on setting change.

- **Bomb Boons Mutually Exclusive** — once any bomb boon is owned (`drop_item_on_ability_use` or `deus_grenade_multi_throw`), other bomb boons are stripped from the random pool for the rest of the run. Implemented inside the existing `generate_random_power_ups` save-and-restore filter (the third hook arg is `existing_power_ups`); piggybacks on the same removed-then-restored pool list.

- **Endless Bombs Consumes Morgrim's** — when the Endless Bombs potion is drunk, any saved Morgrim's Bomb is permanently destroyed instead of dropped on the ground. Hooks `BuffFunctionTemplates.functions.apply_pockets_full_of_bombs_buff` and calls `destroy_slot("slot_level_event")` only when the slot item is `holy_hand_grenade`; other level-event items keep vanilla drop behaviour.

- **Block Ranger Veteran from Saving Morgrim's** — RV's `bardin_ranger_passive_consumeable_dupe_grenade` (10% chance not to consume on grenade throw, applied via `not_consume_grenade` proc stat_buff) cannot fire when the thrown grenade is a Morgrim's Bomb. Hooks `ActionChargedProjectileUtility.fire_charged_projectile`; instance-level monkey-patch of the buff_extension's `apply_buffs_to_value` for the duration of the call (with `rawget`-aware restore through `__index`), gated on `projectile_context.item_name == "holy_hand_grenade"`.

## 0.3.9-dev (2026-05-09)

Version bump for batch deploy. No behaviour changes since 0.3.4-dev — the gap reflects internal version increments during cross-mod work that didn't land separate CW changes.

## 0.3.4-dev (2026-05-01)

### Fixed: Banned Weapon Traits list

The previous list had 20 entries, of which **7 were no-ops** because the names didn't match any real CW weapon trait: `increased_punch_through`, `off_balance`, `power_vs_skaven` (a property, not a trait), `resourceful_combatant`, `scrounger` (a deus weapon theme name), `shockwave` (also a theme), `swiftslaying`. The other 13 silently missed real traits like Swift Slaying, Shockwave, Off Balance, Piercing Projectiles, Resourceful Sharpshooter, etc. — so users couldn't actually ban those.

Replaced with the **31 real traits** that appear in `DeusWeapons[*].baked_trait_combinations`, dumped via the new `dump_traits` command and labeled with Fatshark's official display names + descriptions as tooltips. Banned-trait setting names now match `WeaponTraits.traits[name]` keys exactly, so the runtime check `mod:get("ban_trait_" .. trait)` actually fires.

## 0.3.3-dev (2026-05-01)

### Added: `dump_traits` command

New console command lists every weapon trait that can roll on any CW weapon (union of `DeusWeapons[*].baked_trait_combinations`), resolving each trait's `display_name` and `advanced_description` via `Localize()`. Used to gather the official Fatshark text needed to give the Banned Weapon Traits options proper labels and tooltips.

## 0.3.2-dev (2026-05-01)

### Fixed: `<<key>>` placeholders in mod options menu

40 boon-disable / starting-boon widgets referenced tooltip keys (`disable_boon_squats_tooltip`, `start_boon_squats_tooltip`, `..._deus_power_up_quest_granted_test_01_tooltip`, and all 36 `*_talent_N_M_tooltip`) that were never defined in `_localization.lua`. VMF rendered the unresolved keys as raw `<<key>>` strings on hover. Removed the broken tooltip refs from the widgets — the labels themselves were already auto-generated stubs (`"Talent 1 1"`, `"Squats"`, etc.) with no descriptive text to put in tooltips.

## 0.3.0-dev (2026-05-01)

### Fixed: Campaign potions in CW now actually spawn

The `enable_campaign_potions` toggle never produced visible results because the patch shared the campaign potion settings tables by reference. Engine-startup normalization (in `pickups.lua`) divides each entry's `spawn_weighting` by the sum of its group, so campaign-potion entries had weights ~3× the CW potions. The random sampler iterates with `pairs()` and breaks on the first cumulative weight that hits the random value (in `[0,1)`); the CW potions consistently exhausted that range first, so campaign potions never got picked. Fix: clone the entries and override their `spawn_weighting` to match the CW potion scale.

### Fixed: Boon labeled as "Reckless Swings" is actually called "Khaine's Fury"

Renamed the modified-boon toggle to "Tweak: Khaine's Fury" to match the in-game display name.

### Changed: Altar count defaults are now 0 = vanilla random

`chest_upgrade_count`, `chest_swap_melee_count`, `chest_swap_ranged_count`, and `chest_power_up_count` now default to 0 (leave vanilla distribution untouched). Range expanded from 0–8 to 0–9. Setting any of the four to a non-zero value still replaces the entire chest distribution; types still at 0 produce no altars of that type.

## 0.2.5-dev (2026-04-28)

### Added: Disabled Boons

All 172 boons can now be individually disabled from appearing at shrines, chests, altars, and Belakor's Temple. Boons are organized into 6 sub-groups: Properties, Talents, Skulls & Sets, Combat, Healing & Sustain, Utility & Team.

### Added: Starting Boons

All 172 boons can be toggled on as starting boons granted at the beginning of a Chaos Wastes run. Uses the same 6 sub-groups. Starting boons bypass the disabled-boons list and are granted to all players based on host settings.

### Added: Modified Boons

New "Modified Boons" section for per-boon gameplay tweaks. First entry: **Reckless Swings** — reduces self-damage from 3 to 1 per hit and lowers the health threshold from 50% to 25%, letting the boon stay active longer. Tooltip updates dynamically when the tweak is enabled.

### Added: Banned Weapon Traits

20 Chaos Wastes weapon traits can be individually banned from appearing on weapon upgrades.

### Fixed: Boon localization

Boon names in settings UI now display readable names instead of raw internal keys (e.g. "Attack Speed" instead of `<attack_speed>`). Localization is generated at mod registration time from the static boon key list, then upgraded to actual game display names on first Chaos Wastes entry.

### Changed: Removed redundant settings wrapper

Settings are no longer nested inside a redundant "Chaos Wastes" collapsible group.

## 0.2.0-dev (2026-04-24)

### Added: Version logging

Mod now logs `Chaos Wastes Tweaker v<version> loaded` on init so the running version can be verified in the console log.
