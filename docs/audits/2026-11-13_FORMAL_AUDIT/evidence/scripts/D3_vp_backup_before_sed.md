# D3 verification packs: Chaos Wastes, Events, Enemies (60 open issues)

Source triage: `findings/D3.md` and `findings/D3_ledger.tsv`. Repo head when written: `592253d1`.
Nothing in this file has been run. Every engine call a script needs that I did not read is marked `[unverified]`.

## Read this before any card: builds and names

| Stream | VMF mod id | Version on master (file:line) | Load banner in the console log | Regression command |
|---|---|---|---|---|
| Chaos Wastes public | `ct` | `0.7.354-beta` (`chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/chaos_wastes_tweaker.lua:44`) | `[ct:LOAD] v0.7.354-beta` | `/ct_regression_test` |
| Chaos Wastes dev | `ct_dev` | `0.7.354-dev` (`chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua:44`) | `[ct:LOAD] v0.7.354-dev` (same marker, only the suffix differs) | `/ct_regression_test` |
| Enemies | `enemy_tweaker` | `0.7.65-dev` (`enemy_tweaker/scripts/mods/enemy_tweaker/enemy_tweaker.lua:3`) | `[et:LOAD] v0.7.65-dev` | `/et_regression_test` |
| Events | `event_tweaker` | `0.4.54-dev` (`event_tweaker/scripts/mods/event_tweaker/event_tweaker.lua:4`) | `[event_tweaker:LOAD] v0.4.54-dev` | `/event_tweaker_regression_test` |
| GUI public | `gut` | `0.2.290` (`gui_tweaker/scripts/mods/gui_tweaker/gui_tweaker.lua:38`) | `[gut:LOAD] v0.2.290` | `/gut_regression_test` |
| GUI dev | `gut_dev` | `0.2.369-dev` (`gui_tweaker_dev/scripts/mods/gui_tweaker_dev/gui_tweaker_dev.lua:43`) | `[gut:LOAD] v0.2.369-dev` | `/gut_regression_test` |

Rules that apply to every card below:

1. Never load `ct` and `ct_dev` in one boot. Both register `/ct_regression_test` and the same globals.
2. The two Chaos Wastes trees are different code with different check and command names. 29 of the 32 Chaos Wastes `verify-fix` cards name the public build. Each card says which build it runs against. Use that build's names only.
3. Public live checks registered in `chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_diag_official_apply_evidence.lua:297-305` return `SKIP` when the state they read is absent (`:288-295`). The boot-time suite runs in the keep, so they SKIP there. A SKIP is never a pass. Drive the state first, then run the matching command (`/verify_coins`, `/verify_ct_citadel`, `/verify_ct_anath_raema`, `/verify_ct_ammo_bounds`, `/verify_ct_linked_pickups`, `/verify_ct_progression`, `/verify_ct_chest_cap`) and match its row. The row format is `[ct:<verifier>] <PASS|FAIL|SKIP> <reason> | <fields>` with verifier names `coins`, `ct_citadel`, `ct_anath_raema`, `ct_ammo_bounds`, `ct_linked_pickups`, `ct_progression`, `ct_chest_cap` (`:269-287`). `ct_altar_reroll` and `ct_trial_placement` can only return SKIP (`:62-67,272-273`).
4. Most other in-mod checks compare a marker string or test that a function exists. They prove the code loaded, not that it works. Each card says which reused checks test behaviour.
5. `[et:LOAD]` and `[event_tweaker:LOAD]` are written with `mod:info` (`enemy_tweaker.lua:69`, `event_tweaker.lua:46`). The rig profile must leave VMF info logging on, or these two banners will be missing from the log.
6. Options that change level injection need a restart to take effect. Set them in the plan's option values before boot, not with `T.set` inside a case: `inject_adventure_maps` and `enable_adventure_<level_key>` (`chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_adventure_pool.lua:165,217`).
7. Single Mission Loader: `/ct_load_mission <mission_key> [progress 0-1] [curse] [difficulty]`, host only, only from the Pilgrimage Chamber level `morris_hub` (`chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_dev_mission.lua:97-104,212-240`; same file and line in the dev tree). It calls the engine's `DeusMechanism.debug_load_deus_level` (`Vermintide-2-Source-Code/scripts/managers/game_mode/mechanisms/deus_mechanism.lua:1017-1021`). `/ct_list_missions` prints valid keys.
8. Rig call list: `evidence/C1.md` section 4.3, cited below as "C1 row N" (spawn enemies row 31, pickups row 32, teleport/kill/difficulty row 33, buffs row 34, grant boons row 35, bot input row 36, UI views row 39, win level row 41).

## No rig needed

| Issue | Evidence class | Exact command or file:line that proves it | Action |
|---|---|---|---|
| #322 | S + U | Public: `chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_official_verify_runtime.lua:226-235` packs every return of `func` and returns `unpack(result, 1, result.n)`; the only exit of the hook is that call (`chaos_wastes_tweaker.lua:5939-5958`). Dev: `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_pickup_spawn_owner.lua:298,328`. Engine returns two values at `Vermintide-2-Source-Code/scripts/entity_system/systems/pickups/pickup_system.lua:1283`. Unit: `powershell -File qa/check_lua_unit_tests.ps1` must pass `qa/lua/tests/test_ct_spawn_pickup_two_return.lua` (5 tests, `:32-79`). | Close |
| #259 | U | `qa/lua/tests/ct_official_boon_repair_cases.lua:142,189,210` (loaded by `qa/lua/tests/test_ct_official_verify_rollup.lua:39`) run the production wrapper `chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_official_boon_repairs.lua:175`: Ranger save denied, Endless Bombs allowed, toggle off is a pass-through, both method overrides restored after success and after an error. Engine seam: `Vermintide-2-Source-Code/scripts/unit_extensions/weapons/actions/action_charged_projectile.lua:83-87`. Command: `powershell -File qa/check_lua_unit_tests.ps1`. | Close. Backstop: VP-D3-01 asserts the in-game check `morgrim_exact_restore_259` |
| #1191 | U | `qa/lua/tests/test_ct_426_exact_catalog.lua:173,209` ("two peers registering in different orders agree", "a drifted peer reads as parity-absent"). Dev builds the catalog identity at `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_peer_parity_owner.lua:225`. | Merge into #426 (same wire-parity owner, same two-machine run). Do not close alone: see fix row NF-4 |
| #1817 | X | Player cap is engine and lobby level: `Vermintide-2-Source-Code/scripts/managers/matchmaking/matchmaking_manager.lua:42` (`MAX_NUMBER_OF_PLAYERS = 4`), `Vermintide-2-Source-Code/scripts/managers/network/lobby_setup.lua:6` (`max_members = 4`). | Owner decision. Default: close as not planned, out of scope for a tweaker mod |
| #452 | X | Only a read-only census exists (`enemy_tweaker/scripts/mods/enemy_tweaker/_et_special_variants.lua:3-10`); the requested skins are player attachment meshes with 0 matching nodes on AI skeletons (issue body, owner audit 2026-08-03). Also blocked by NF-1. | Owner decision. Default: close as not planned; reopen only if AI-compatible models are supplied |
| #466 | X | The remaining work is a balance policy the issue reserves for the owner (`issues/open/466.md`, comment 2026-08-02). No scorer exists in `chaos_wastes_tweaker_dev/`. | Owner decision. Default: close as not planned; the shipped bot coin ledger is unaffected |
| #141 | X | Only a read-only audit command exists (`chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_resume_audit.lua:37`). Design note: `chaos_wastes_tweaker_dev/SAVE_RESUME_FEASIBILITY_141.md`. | Owner decision. Default: close as not planned and keep the design note |

## Owner only

None. Every owner decision above has a default. The three lighting issues (#243, #258, #271) still need human eyes after their script passes; they are in VP-D3-07.

## Needs a fix first

These issues cannot pass their pack until the named change lands. "A4-Fnn" refers to `findings/A4.md`.

| Id | Issues | What is wrong (path:line) | The fix | Size |
|---|---|---|---|---|
| NF-1 | #324, #451 (and #452) | Both custom breeds are registered at mod load (`enemy_tweaker/scripts/mods/enemy_tweaker/_et_boss_ideas.lua:211`, `_et_skaven_warlord_breed.lua:119`). The registrar's capacity reader returns `damage_source_cap_unavailable` when `NetworkConstants` is nil (`_et_custom_breed_registrar.lua:509-523`). The engine creates `NetworkConstants` only at `Vermintide-2-Source-Code/scripts/network_lookup/network_constants.lua:3`, loaded from `scripts/game_state/loading_sub_states/win32/state_loading_restart_network.lua:161`, after mods boot. `enemy_tweaker/CHANGELOG.md:3-12` records the refusal in 12 of 12 logs. | Run VP-D3-15 case 1 first to learn what `Network.type_info` returns at load. Then either read capacity from a source that exists at load, or defer the capacity proof and commit to the first frame `NetworkConstants.damage_source_id` exists. Keep "refuse when capacity is unknown". Trap: breeds must exist before boot-time `pairs(Breeds)` consumers (`enemy_tweaker/DEVELOPMENT.md` breed checklist). | M, strong agent |
| NF-2 | #919 | Profile snapshots take their members from the active tab's display node list (`gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_view.lua:773`, `_mod_tweaker_view_pending.lua:77-97`, twin at `_mod_tweaker_state.lua:284-301`). The owner's 2026-08-03 audit says settings without a row are never captured and mismatched members are dropped silently. No fix is cited in any changelog. | Write the unit test first (VP-D3-03 case 6 names it). Build snapshot membership from the owning mod's registered settings, and count plus log every member dropped in `_switch_profile`. | M |
| NF-3 | #430, #413 (late joiner only) | A4-F03: the hot-join lock hooks `GameModeBase.is_joinable` (`event_tweaker/scripts/mods/event_tweaker/_evt_guard430_curse_parity.lua:132`). Subclasses copy parent methods at class definition (`Vermintide-2-Source-Code/foundation/scripts/util/class.lua:53-59`), so `GameModeAdventure` instances never call the hooked function. | Hook `GameModeAdventure`, `GameModeDeus` and `GameModeWeave` (one hook each), or `GameModeManager.is_joinable` (`Vermintide-2-Source-Code/scripts/managers/game_mode/game_mode_manager.lua:1275`). VP-D3-13 case 5 is the regression. | S |
| NF-4 | #1191; #426 and #458 on the dev stream only | A4-F02: in dev the shrine purchase hook forwards to vanilla with no parity test (`chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_grant_owner.lua:460-477`); `purchase_allowed` is defined and never called (`_ct_wire_policy.lua:186`); the parity gate and the `enable_boon_*` toggles edit a table the roller does not read (A4-F02, not re-read by me). The public tree has the fence. | Call `purchase_allowed` before `func` in the dev hook and make roller membership the gated table, or port the public wire runtime. Public-build packs are not blocked by this. | M |
| NF-5 | #460 on the public build | A4-F22: the journey-stat guard exists only in dev (`chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_journey_difficulty_guard.lua:37-48`; no match for `_register_completed_journey_difficulty` in `chaos_wastes_tweaker/`). Static evidence suggests a public run that wins a journey's last level at Cataclysm 2 or 3 fails in `Vermintide-2-Source-Code/scripts/managers/backend/statistics_util.lua:1042-1054`. | Port the guard file to the public tree. Until then VP-D3-08 stops before the final level. | S |
| NF-6 | #426 two-machine leg; any co-op run of injected maps | A4-F01: the lobby-hash shim admits peers whose level list differs (`chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua:616-637` per A4, public `chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/chaos_wastes_tweaker.lua:435-458`) and nothing gates the level axis. | Owner decision first (A4 question Q1): delete the shim, or gate injection on an acknowledged level-key identity. Solo packs are not affected. | L |
| NF-7 | #453 (and the Enemy Tweaker half of #323) | Only a read-only audit exists (`enemy_tweaker/scripts/mods/enemy_tweaker/_et_enemy_modifiers.lua`); no rates, toggles or application code. | Build one category at a time on the existing `ConflictDirector._post_spawn_unit` owner using `TerrorEventUtils.apply_breed_enhancements` (`Vermintide-2-Source-Code/scripts/settings/terror_events/terror_event_utils.lua:80-104`). VP-D3-16 case 5 collects the missing boss and lord rows first. | L, split per category |
| NF-8 | #251, #456 | No fix exists and the cause is unknown. The shipped difficulty-key change cannot reach the guaranteed-spawn path (owner audit on #251, 2026-08-03). | Run VP-D3-09 first. Its census names the failing path; write the fix from that. | Unknown until the census |
| NF-9 | #1309 | Cause unknown. Three hypotheses are listed on the issue (2026-08-16). | Run VP-D3-13 case 3 solo first; it removes two of the three. | Unknown |
| NF-10 | #249 and #465, two-machine legs on the dev stream | A4-F04: the dev hot-join fence strips every player's custom boons when the joiner is not yet acknowledged (`chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_peer_parity_owner.lua:777-820`, not re-read by me). | Decide with NF-4. Until then a co-op FAIL on these two may be this fence, not the issue's own code. | M |

## Verification packs

Path key used inside every card: `ct/` = `chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/` (public). `ctd/` = `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/` (dev). `et/` = `enemy_tweaker/scripts/mods/enemy_tweaker/`. `evt/` = `event_tweaker/scripts/mods/event_tweaker/`. `V2/` = `Vermintide-2-Source-Code/`. `drc` = `Managers.mechanism:game_mechanism():get_deus_run_controller()` (`V2/scripts/managers/game_mode/mechanisms/deus_mechanism.lua:523`).

### VP-D3-01 boot-smoke: boot to keep with every mod, zero error lines

| Field | Value |
|---|---|
| Issues | #1497 (R) |
| Arena | boot, then keep |
| Mods and stream | Boot A "public set": VMF plus every single-stream mod and the stable half of each pair (`ct` 0.7.354-beta, `gut` 0.2.290, and so on per `tools/mod-inventory.psd1`), with `enemy_tweaker` 0.7.65-dev and `event_tweaker` 0.4.54-dev. Boot B "dev set": the same list with each `_dev` twin instead of its stable mod (`ct_dev` 0.7.354-dev, `gut_dev` 0.2.369-dev). Default options. |
| Boots | 2. `ct` and `ct_dev` must never load together. #1497 was reported with the dev set. |
| Depends on | Rig: `boot` and `keep` arenas, log scan, `T.expect_rt`. No fix. |

**Setup.** Fresh isolated profile, solo host, VMF info logging on (rule 5 at the top of this file). No other state.

**Cases.**

| Script | Issue | Steps (T calls, in order) | Assertions (engine state read, with citation) | PASS closes? |
|---|---|---|---|---|
| `qa/runtime/shared/boot_banners_and_errors.lua` | none (covers the class of #595 and every "mod failed to load" report) | Arena `boot`. No T calls. | `host_expect_log`: one `[<id>:LOAD] v<version>` line per loaded mod, version equal to that mod's `MOD_VERSION` source line (table at the top of this file). `host_forbid_log`: `Resource not found: scripts/mods/`, `%[MOD%]%[.-%]%[ERROR%]`, `<<Script Error>>`, `Attempting to rehook active hook`. | Gate for all other packs |
| `qa/runtime/enemy_tweaker/issue_1497_local_host_reaches_keep.lua` | #1497 | Arena `keep`, timeout 120. `T.wait_until(local peer is InGame, 120, "host in game")`. `T.expect_eq(Managers.state.game_mode:game_mode_key(), "inn", "keep loaded")`. `T.cmd("et_regression_test")`. `T.expect_rt("enemy_tweaker", "issue1497_local_host_hot_join_bypass")`. | Local peer state: `Managers.state.network.network_server.peer_state_machines[Network.peer_id()].current_state == PeerStates.InGame` (`V2/scripts/network/network_server.lua:29,56,141`; `V2/scripts/network/peer_state_machine.lua:20-30`; `V2/scripts/network/peer_states.lua:486`). The soft-lock looped at `V2/scripts/network/peer_states.lua:383-398`. `host_forbid_log`: `%[et:451%] hot%-join sync HELD`, `%[et:451%] hot%-join sync KICKED`. | Yes |
| `qa/runtime/shared/keep_regression_suites.lua` | none | Arena `keep`. For each loaded mod run its regression command and record every check with `T.expect_rt`. | No FAIL row. SKIP rows are listed, not counted as pass. | Gate |

**Reused in-mod checks.** `issue1497_local_host_hot_join_bypass` (`et/_et_custom_breed_parity.lua:613-672`): tests behaviour. It reads evidence written inside both installed hooks and the live roster, and it skips unless the host is alone. `morgrim_exact_restore_259`, `vauls_anvil_reconciler_144`, `anath_raema_registry_retry_288`, `parry_cooldowns_registered_342` (`ct/_ct_official_boon_repairs.lua:198-236`, public build only): run the production callback on isolated tables; they prove logic, not live effect.

**Left for humans.** Nothing.

**If it FAILS.** Missing banner or `Resource not found`: a `mod:dofile` target is absent from the built bundle; compare the mod's `.package` file with its `mod:dofile` calls (the #595 class). #1497 case times out: read `et/_et_custom_breed_parity.lua:174-221,329-409` and look for a `HELD` row naming the local peer id. Only the named check fails while the keep loads: the check, not the fix, is wrong (this happened on 0.7.61-dev, corrected in 0.7.62-dev per `enemy_tweaker/CHANGELOG.md:100-104`).

### VP-D3-02 mission-load: one Adventure mission and one Chaos Wastes mission through the loader

| Field | Value |
|---|---|
| Issues | #505 (R), #470 (R) |
| Arena | `mission:military` (baseline), then `deus` |
| Mods and stream | Public `ct` 0.7.354-beta only (plus VMF and the rig driver). Option `starting_coins` = 1000. |
| Boots | 1 |
| Depends on | Rig: a `deus` arena that leaves the host standing in `morris_hub`; `T.spawn`. No fix. |

**Setup.** Solo host with bots. Path key: see the line under "Verification packs". The loader refuses outside `morris_hub` (`ct/_ct_dev_mission.lua:97-104`). Mission keys come from `/ct_list_missions` (catalog `ct/_ct_dev_mission_catalog.lua:83-116`); the examples use `pat_forest` (composed as `pat_forest_nurgle_path3` in `qa/lua/tests/ct_official_feature_cases.lua:313`).

**Cases.**

| Script | Issue | Steps (T calls, in order) | Assertions (engine state read, with citation) | PASS closes? |
|---|---|---|---|---|
| `qa/runtime/shared/mission_load_military.lua` | none | Arena `mission:military`. `T.local_hero()`, `T.bots()`. | `LevelHelper:current_level_settings().level_id == "military"` (same read as `V2/scripts/managers/backend/statistics_util.lua:944-947`). Forbid the error patterns of VP-D3-01. | Baseline |
| `qa/runtime/ct/issue_505_loader_progress_clamp.lua` | #505 | Arena `deus`. `T.require(level_id == "morris_hub")`. `T.cmd("ct_load_mission", "pat_forest", "1")`. `T.wait_until(level_id ~= "morris_hub" and hero alive, 180)`. | `drc:get_current_node().run_progress == 0.999` (`V2/scripts/managers/game_mode/mechanisms/deus_run_controller.lua:2074,360`; the engine asserts `run_progress < 1` at `V2/scripts/managers/game_mode/mechanisms/deus_weapon_generation.lua:30`). `host_expect_log`: `%[ct:505%] single_mission_load level=.- progress=0.999` (`ct/_ct_dev_mission.lua:142-144`). | Yes, with the next two |
| `qa/runtime/ct/issue_505_loader_upgrade_chest.lua` | #505 | Same mission. Find a chest: `Managers.state.entity:get_entities("DeusChestExtension")` (`V2/scripts/managers/entity/entity_manager2.lua:56`) with `ext:get_chest_type() == DEUS_CHEST_TYPES.upgrade` (`V2/scripts/unit_extensions/pickups/deus_chest_extension.lua:395`). `T.require` one exists. Teleport the hero next to it and interact (rig interaction helper) or call `ext:open_chest()` (`:539`) [calling it outside the interaction flow is unverified]. | Hero's wielded weapon rarity equals `ext:get_rarity()` (`:363`) afterwards. `host_forbid_log`: `Run progress should never be equal or higher than 1.0`. | Yes |
| `qa/runtime/ct/issue_505_loader_hub_gate.lua` | #505 | Arena `keep`. `T.cmd("ct_load_mission", "pat_forest")`. `T.wait(10)`. | Level id unchanged. `host_forbid_log`: `%[ct:505%] single_mission_load level=`. | Yes |
| `qa/runtime/ct/issue_505_loader_catalog_sweep.lua` | #505 | Arena `deus`. For every key printed by `/ct_list_missions`: load, wait in game, return to hub. | Each key reaches in game with no forbidden log line; failures listed by key. | Advisory (long; run nightly). It is also the entry test for packs 03 to 10 |
| `qa/runtime/ct/issue_470_rank8_sorcerer.lua` | #470 | Arena `deus`. `T.cmd("ct_load_mission", "pat_forest", "0.999", "curse_skulking_sorcerer", "cataclysm_3")`. Wait in game. `T.spawn("curse_mutator_sorcerer", offset)`. `T.wait(5)`. | `Breeds.curse_mutator_sorcerer.max_health[8] == 150` and `[7] == 150`. The vanilla table stops at rank 7 (`V2/scripts/settings/mutators/mutator_curse_skulking_sorcerer.lua:9-11,19-27,36`) and the director reads `breed.max_health[difficulty_rank]` with no fallback (`V2/scripts/managers/conflict_director/conflict_director.lua:1948`). Spawned unit alive with `T.ext(unit, "health_system"):get_max_health() > 0` (`V2/scripts/unit_extensions/generic/generic_health_extension.lua:203`). `host_forbid_log`: `generic_hit_reaction_extension`, `math.lua:29`. | Yes |

**Reused in-mod checks.** `single_mission_loader_redesign_505` (`ct/_ct_official_feature_leaf.lua:55`): catalog and clamp constants only. `issue470_sparse_rank8_backfill` (`ct/_ct_official_verify_runtime.lua:356`): reads the live breed table; meaningful only after the curse was initialized in this boot, so run it after the #470 case.

**Left for humans.** Nothing.

**If it FAILS.** Loader case never leaves the hub: the rig's hub entry, or the level key is not owned (DLC); run `/ct_list_missions`. Clamp case shows 1.0: `ct/_ct_dev_mission_catalog.lua:121-129`. #470 case shows `max_health[8] == nil`: the `MutatorHandler.initialize_mutators` post-hook did not run; in dev it is `ctd/_ct_node_entry_owner.lua:171-191`, in public find the same backfill near `ct/_ct_official_verify_runtime.lua:305`.

### VP-D3-03 run-setup: starting coins, start shrine, boon prices, illusions, settings profiles

| Field | Value |
|---|---|
| Issues | #912 (R), #458 (R), #467 (R), #1146 (R), #917 (R), #919 (R) |
| Arena | `deus` (fresh ordinary pilgrimage, not the loader), `keep` for #919 |
| Mods and stream | Boot A: public `ct` 0.7.354-beta. Boot B (only #919): `ct_dev` 0.7.354-dev + `gut_dev` 0.2.369-dev, because `/ct_profile_audit` exists only in dev (`ctd/_ct_profile_snapshot.lua:167`) and the #919 card names those builds. |
| Boots | 2 |
| Depends on | Rig: start an ordinary pilgrimage from `morris_hub`; `T.open_view` / `T.widget` or direct view read; equip a backend item (C1 row 27). Fix NF-2 before the #919 case can pass. |

**Setup.** Solo host. Each case starts its own fresh run. Shop view instance: `Managers.state.game_mode:game_mode()._shop_view` (`V2/scripts/managers/game_mode/game_modes/game_mode_map_deus.lua:103`, accessor `V2/scripts/managers/game_mode/game_mode_manager.lua:911`). Offers: `view._shop_items.power_ups[i]` with `.power_up`, `.discount`, `.widget.content.price_text` (`V2/scripts/ui/views/deus_menu/deus_shop_view_v2.lua:289-302,660`). Own coins: `drc:get_player_soft_currency(drc:get_own_peer_id())` (`V2/scripts/managers/game_mode/mechanisms/deus_run_controller.lua:925,254`). Buy: `drc:shop_buy_power_up(power_up, discount)` (`:989`). Owned boons: `drc:get_player_power_ups(peer_id, 1)` (`:1080`). Public setting ids: `starting_coins`, `ct_buy_starting_boons`, `ct_start_shrine_boon_count` (0-8), `ct_start_shrine_miracle_count` (0-3), `ct_start_shrine_cost_percent` (multiples of 10), `ct_start_shrine_purchase_limit` (0 is the default; the card calls the no-limit choice "Unlimited"), `ct_individual_boon_prices`, `preserve_adventure_illusions` (`ct/chaos_wastes_tweaker_data.lua:496-499`).

**Cases.**

| Script | Issue | Steps (T calls, in order) | Assertions (engine state read, with citation) | PASS closes? |
|---|---|---|---|---|
| `qa/runtime/ct/issue_912_starting_coins_exact.lua` | #912 | `T.set("ct","starting_coins",324)`. Start a run. Read coins before any pickup. `T.cmd("verify_coins")`. Repeat in a new run with 0. | Coins `== 324`, then `== 0`. Vanilla writes the baseline at `V2/.../deus_run_controller.lua:273,315`. `host_expect_log`: `%[ct:coins%] PASS` each time. `T.note` the `incoming=` field of that row: the zero case only proves "rollover replaced" when `incoming > 0`; if it is 0 report the zero case INCONCLUSIVE. | Yes (324 case alone proves exactness; zero case needs `incoming > 0`) |
| `qa/runtime/ct/issue_1146_start_shrine_prices_numeric.lua` | #1146 | `ct_buy_starting_boons`=true, boon count 4, miracles 0, cost 100, limit 0, `starting_coins`=1000, `ct_individual_boon_prices`=false. Start a run. `T.wait_until(shop view present, 60)`. Buy offer 1, then offer 2. | `view._shop_type == "dlc_morris_map"` (`ct/_ct_start_shrine_runtime.lua:15`). 4 offers. Every `price_text` matches `^%d+$` (never `-`). After each buy: coin delta equals the displayed price and the boon name is in `get_player_power_ups`. Vanilla passes `discount = false` for undiscounted offers (`V2/.../deus_shop_view_v2.lua:289-290`), which was the cause. | Yes |
| `qa/runtime/ct/issue_458_start_shrine_config.lua` | #458 | Cost 50, limit 1, count 4, miracles 0. Start a run; buy one; try a second. New run: miracles 1 with only `ct_start_shrine_miracle_blessing_of_power` on. New run: `ct_buy_starting_boons`=false. | Price equals the vanilla price times 0.5, rounded as the policy does (`ct/_ct_start_shrine_policy.lua:43-60`); second buy leaves coins and boons unchanged. Miracle run: exactly one miracle offer and it is Blessing of Power. Off run: no shop view at the start node. `T.cmd("ct_verify_start_shrine")`. | Yes. Layout with a count other than 4 is left for humans |
| `qa/runtime/ct/issue_467_individual_prices.lua` | #467 | `ct_individual_boon_prices`=true, shrine cost 100 then 50. For each offer compare with the manifest. Then turn the option off in a new run. | For every offer: `tonumber(price_text) == policy.price(name, rarity, discount, percent)` using the production module `ct/_ct_boon_pricing_policy.lua:73` (`barkskin` 225, `money_magnet` 150 at `:26,32`; 113 at 50 percent). Buy one: coin delta equals that price. Off: price equals the vanilla rarity price. If neither control boon is offered, `T.note` it; the per-offer comparison still decides. | Yes |
| `qa/runtime/ct/issue_917_adventure_illusions.lua` | #917 | Equip a melee weapon with a known non-default skin in the Adventure loadout (C1 row 27). `T.set("ct","preserve_adventure_illusions",true)`. Start a run. Then upgrade that weapon at an upgrade chest (as in VP-D3-02). | Starter melee item from `drc:get_own_loadout()` (`V2/.../deus_run_controller.lua:839`) has `.skin` equal to the saved skin, and that skin's `ItemMasterList[skin].matching_item_key` equals the starter item key (the rule is at `ct/_ct_adventure_illusions.lua:70`). Same skin after the upgrade. With the option off the mod must not write the skin: assert no `[ct:917]` apply row [row name unverified]. | Yes. `.skin` is data; no visual judgement needed |
| `qa/runtime/ct_dev/issue_919_profile_round_trip.lua` | #919 | Boot B, arena `keep`. Open Mod Tweaker on the Chaos Wastes tab (rig view helper; view class `ModTweakerView`, switch function `_switch_profile(slot)` at `gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_view_pending.lua:129`). Profile 1: `starting_coins`=111, one `start_boon_<name>` true, `disable_curse_rotten_miasma`=true; apply. Profile 2: 222, a different boon, false; apply. Switch to 1. `T.cmd("ct_profile_audit")`. Start a run. | After the switch back: `get_mod("ct_dev"):get(id)` returns the profile 1 value for all three ids and for every other `start_boon_*` id. In the run: coins `== 111` and owned boons equal profile 1's set. | Yes, after NF-2. Expected to FAIL on master today |

**Reused in-mod checks.** `issue912_exact_starting_coins` (`ct/_ct_official_verify_runtime.lua:350`), `issue458_start_shrine_config`, `issue467_individual_boon_prices`, `issue1146_false_discount` (`ct/_ct_official_shop.lua:56-58`), `issue917_adventure_illusion_preservation` (`ct/_ct_official_verify_runtime.lua:360`): policy and wiring checks run in the keep; none reads a live shop or a live loadout. `ct_initial_coins_readback_912`: live, SKIP outside a run.

**Left for humans.** #458: how the shop looks with 0 to 8 offers (class V; attach `T.shot`). Client side of #458 and #467 (a client's saved value must not override the host's false): class C, needs the two-machine run.

**If it FAILS.** Dash prices: `ct/_ct_start_shrine_policy.lua:43-60`. Price differs from the debit: display and charge no longer share `M.price` (`ct/_ct_start_shrine_runtime.lua:157-166`). #919: NF-2.

### VP-D3-04 chest-counts: Chest of Trials cap and trial enemy multiplier

| Field | Value |
|---|---|
| Issues | #60 (R), #349 (R), #471 (R) |
| Arena | `deus` through the loader |
| Mods and stream | Public `ct` 0.7.354-beta. Plan options set before boot: `inject_adventure_maps`=true, `enable_adventure_dlc_dwarf_beacons`=true, `enable_adventure_dlc_dwarf_interior`=true. If the #349 case finds an overflow, repeat it once on `ct_dev` 0.7.354-dev, where the `[ct:349] chest_count_audit ... class=` row exists (`ctd/_ct_diag_cursed_chest132.lua:30`). |
| Boots | 1 (2 only if #349 overflows) |
| Depends on | Rig: `deus` arena; event listener or unit census inside a case. VP-D3-02 loader cases must pass first. No fix. |

**Setup.** Chest census: `Managers.state.entity:get_entities("DeusCursedChestExtension")` (`V2/scripts/managers/entity/entity_manager2.lua:56`; states at `V2/scripts/unit_extensions/deus/deus_cursed_chest_extension.lua:8-13`, `WAITING = 1`). Shadow locus census: `Managers.state.entity:system("pickup_system"):get_pickups_by_type("deus_02")`, the same read the mod uses (`ct/_ct_official_chest_cap.lua:91-95`). Cap setting: `cursed_chest_count`. Multiplier setting: `cot_enemy_multiplier`. Wait at least 8 seconds after mission entry before counting (the reconciler settles then).

**Cases.**

| Script | Issue | Steps (T calls, in order) | Assertions (engine state read, with citation) | PASS closes? |
|---|---|---|---|---|
| `qa/runtime/ct/issue_60_khazukan_chest_cap.lua` | #60 | `T.set("ct","cursed_chest_count",3)`. `T.cmd("ct_load_mission","dlc_dwarf_beacons","0.5","curse_belakor_totems")`. Wait in game, `T.wait(10)`. Census. `T.cmd("verify_ct_chest_cap")`. | Live cursed chests `<= 3`. Locus count `== 1`. `host_expect_log`: `%[ct:ct_chest_cap%] PASS`. If the row is SKIP with "unprunable", `T.note` the fields and report INCONCLUSIVE: baked chests are never deleted by design. | Yes |
| `qa/runtime/ct/issue_349_mission_of_mercy_cap.lua` | #349 | `cursed_chest_count`=2. `T.cmd("ct_load_mission","dlc_dwarf_interior","0.5")`. Wait in game, `T.wait(10)`. Census. `T.cmd("verify_ct_chest_cap")`. | Live cursed chests `<= 2`. On overflow record each chest's state and the verifier fields `live`, `eligible`, `marked`. | Yes if within cap. Overflow with eligible chests is a FAIL; overflow of baked chests becomes a fix task |
| `qa/runtime/ct/issue_471_trial_multiplier.lua` | #471 | Loader mission with at least one cursed chest. Register a listener on the engine event `ai_unit_spawned` (`V2/scripts/managers/conflict_director/conflict_director.lua:2090`). Run A: `cot_enemy_multiplier`=1, start the trial with `ext:on_server_interact(...)` (`V2/.../deus_cursed_chest_extension.lua:293`; it starts terror event `cursed_chest_prototype` at `:103-107`) [argument list unverified], count spawns for 60 s, kill them (C1 row 33). Run B in a fresh load: multiplier 3. | Count B is at least 2 times count A for the same trial type (record the challenge name from `ext._telemetry_data.challenge_name`, `:96`). Spawn count outside the trial window unchanged. `T.note` the public `[ct:471]` placement row fields. | Yes when both runs drew the same trial type; otherwise INCONCLUSIVE, rerun |

**Reused in-mod checks.** `cursed_chest_reconcile_132` (`ct/_ct_official_chest_cap.lua:166`): planner contract on synthetic data. `ct_chest_count_live_60`: live, SKIP in the keep. `cot_enemy_multiplier_cursed_chest_only`: marker string. `ct_trial_placement_readback_471`: always SKIP (rule 3).

**Left for humans.** Nothing for the counts. Telegraph look for the extra trial enemies: class V, low value.

**If it FAILS.** #60 over cap with `eligible > 0`: reconciler did not prune (`ct/_ct_official_chest_cap.lua:78-105`). #471 ratio near 1: the terror-event hook did not install. In dev it is installed only if `TerrorEventMixer` exists at mod load, with no else branch (`ctd/_ct_combat_hooks.lua:390-529`); check the same for public (`M.spawn_around` at `ct/_ct_official_verify_runtime.lua:239` is called from the public hook).

### VP-D3-05 altar-reuse: multi-use temper altar keeps its rarity and shows the reroll prompt

| Field | Value |
|---|---|
| Issues | #102 (R), #252 (R) |
| Arena | `deus` through the loader |
| Mods and stream | Public `ct` 0.7.354-beta. Options: `enable_altar_reuse`=true, `altar_reuse_count_upgrade`=3, `starting_coins`=3000. The #102 card still names dev, but the same change is in the public tree (`ct/chaos_wastes_tweaker.lua:584-586`, `chaos_wastes_tweaker/CHANGELOG.md:104`); one public run covers both issues. |
| Boots | 1 |
| Depends on | Rig: interaction helper for the local hero or a bot (`T.as_bot`), HUD widget read. No fix. |

**Setup.** Find an upgrade altar as in VP-D3-02 (`get_entities("DeusChestExtension")`, `get_chest_type() == DEUS_CHEST_TYPES.upgrade`). `T.require` one exists; if the mission has none, load another key. Record `r0 = ext:get_rarity()` (`V2/scripts/unit_extensions/pickups/deus_chest_extension.lua:363`) before the first use. The hero must wield a weapon of lower rarity than `r0` for the first use.

**Cases.**

| Script | Issue | Steps (T calls, in order) | Assertions (engine state read, with citation) | PASS closes? |
|---|---|---|---|---|
| `qa/runtime/ct/issue_102_altar_rarity_stable.lua` | #102 | Use the altar three times (interaction helper; the vanilla entry is `DeusChestExtension.open_chest`, `V2/.../deus_chest_extension.lua:539`). After each use read the altar and the wielded weapon. | After every use: `ext:get_rarity() == r0` and the wielded weapon's `rarity == r0`. Vanilla awards `self._rarity` (`:426,539`), so a changed `get_rarity()` is the defect. After the last allowed use `ext:can_be_unlocked() == false` (`:487`). | Yes |
| `qa/runtime/ct/issue_252_reroll_prompt.lua` | #252 | After the first use, target the same altar again so the interaction prompt is built (vanilla `DeusUpgradeWeaponInteractionUI._populate_widget`, `V2/scripts/settings/dlcs/morris/deus_upgrade_weapon_interaction_ui.lua:18`). Read `self._widgets_by_name.chest_content.content` on that UI instance (`:49`) [how the rig reaches the instance is unverified]. Accept. | `content.reward_info_text == "Reroll this weapon?"` and `content.disabled_text == nil` (vanilla would set `disabled_text = "reliquary_inactive_rarity"` at `:98`). Text width at the widget's font size is not larger than the widget width (clipping check; `UIRenderer.text_size` [unverified]). After accept: rarity unchanged, one use and the displayed cost consumed. Then with coins set to 0 the prompt shows the normal unaffordable state. | Yes. If the rig cannot read the HUD widget, report INCONCLUSIVE, not PASS |

**Reused in-mod checks.** `upgrade_altar_rarity_decouple` (`ct/chaos_wastes_tweaker.lua:12542`): marker string only. `ct_altar_prompt_readback_252`: always SKIP (rule 3). Neither closes anything.

**Left for humans.** #252: one still of the prompt (`T.shot`) for a quick look; not required to close.

**If it FAILS.** Rarity climbs: something writes `self._rarity` again; `git grep -n "self._rarity *=" chaos_wastes_tweaker/` must return nothing. Prompt wrong: the `_populate_widget` post-hook (dev copy at `ctd/_ct_altar_reuse_owner.lua:686-700`).

### VP-D3-06 boons: boon and trait repairs, ammo bounds, cooldown icons

| Field | Value |
|---|---|
| Issues | #144 (R), #288 (R), #342 (R), #256 (R), #357 (R), #358 (R), #249 (C: solo part only) |
| Arena | `deus` through the loader |
| Mods and stream | Boot A: public `ct` 0.7.354-beta. Options: `enable_boon_reworks`=true, `enable_boon_vauls_anvil`=true, `enable_boon_manann_tempest`=true, `tweak_manann_tempest_cooldown`=true, `tweak_anath_raema_permanent`=true, `bomb_boon_cooldown`=10. Boot B (only #249): `ct_dev` 0.7.354-dev + `gut_dev` 0.2.369-dev, because the #249 card names them and `/verify_boon_ammo_hud` is a gut_dev command (`gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_numericui_cooldown_realtime.lua:213`). |
| Boots | 2 |
| Depends on | Rig: grant a boon (C1 row 35), wield a slot on the test subject, throw a grenade, force a critical hit. Where the rig cannot do one of these the case must report INCONCLUSIVE. No fix for the solo parts. NF-10 may affect the #249 two-machine leg. |

**Setup.** Subject: the local hero (the public `/verify_ct_*` commands read the local player only, `ct/_ct_diag_official_apply_evidence.lua:68-74`). Grant boons with `drc:add_power_ups` (`V2/scripts/managers/game_mode/mechanisms/deus_run_controller.lua:1126`). Buff reads: `T.ext(hero, "buff_system")` with `has_buff_type`, `num_buff_type`, `apply_buffs_to_value` (`V2/scripts/unit_extensions/default_player_unit/buffs/buff_extension.lua:1213,1263,1391`). Public power-up names: `ct_boon_vauls_anvil`, `ct_boon_manann_tempest`, `ct_meta_ammo` (`ct/_ct_wire_policy.lua`).

**Cases.**

| Script | Issue | Steps (T calls, in order) | Assertions (engine state read, with citation) | PASS closes? |
|---|---|---|---|---|
| `qa/runtime/ct/issue_144_vauls_anvil_reconcile.lua` | #144 | Grant `ct_boon_vauls_anvil`. Wield melee, wait 1 s. Wield ranged, wait 1 s. Wield melee. `T.pickup` a potion, pick it up, wield it, wield melee. Repeat after a loader transition to a second mission. | With melee wielded: `has_buff_type("deus_always_blocking_buff")` and `T.ext(hero,"status_system").override_blocking == true` (`V2/scripts/unit_extensions/generic/generic_status_extension.lua:48,1417-1418`). With ranged wielded: both false or nil. Exactly one such buff after every return to melee (`num_buff_type == 1`). | Yes. The block-break lockout branch is optional: add it only if the rig can break the hero's block |
| `qa/runtime/ct/issue_288_anath_raema_permanent.lua` | #288 | `hero buff ext:add_buff("deus_ammo_pickup_reload_speed")` (`V2/.../buff_extension.lua:165`; the mod enforces its child at this lookup). `T.cmd("verify_ct_anath_raema")`. Remove, `T.set("ct","tweak_anath_raema_permanent",false)`, add again. | On: `num_buff_type("deus_ammo_pickup_reload_speed_permanent") == 1` and `apply_buffs_to_value(1, "reload_speed") == 0.5` with no other reload buff present. `host_expect_log`: `%[ct:ct_anath_raema%] PASS`. Off: no permanent child and the template is the vanilla one (has an event trigger). | Yes. Equipping a real trait weapon instead of calling `add_buff` is stronger; do that if the rig can craft one |
| `qa/runtime/ct/issue_342_parry_cooldown_zero.lua` | #342 | Start a run through the loader so at least one boon roll happened (the strip runs on a roll). Read the templates. | `BuffTemplates.boon_skulls_03_cooldown.buffs[i].duration == 0` for every i, and the same for the cooldown template of every registered Static Blade rarity (walk `DeusPowerUps[rarity].static_blade` as the production policy does, `ct/_ct_parry_cooldown_policy.lua`). Vanilla uses these names at `V2/scripts/settings/dlcs/morris/morris_buff_settings.lua:4267,4323`. | Yes for "cooldown removed". Two consecutive timed blocks both proccing is optional extra |
| `qa/runtime/ct/issue_256_ammo_bounds.lua` | #256 | Hero with a clip weapon. Fire to a partial clip and reserve (bot input or `T.as_bot` on a bot is not usable here: the verifier reads the local hero). `T.pickup("all_ammo_small")` and reload. Grant `ct_meta_ammo`; grant it again. After each step run `T.cmd("verify_ct_ammo_bounds")` and read the extension. | Ranged weapon unit from `inventory:get_slot_data("slot_ranged").right_unit_1p`, extension `ammo_system`: `_available_ammo >= 0`, `0 <= _current_ammo <= _max_ammo` (`V2/scripts/unit_extensions/weapons/ammo/generic_ammo_user_extension.lua:25,30,96,100-112`; the unfloored vanilla line is `:108`). `host_expect_log`: `%[ct:ct_ammo_bounds%] PASS`; forbid `%[ct:ct_ammo_bounds%] FAIL`. `T.note(ext._original_ammo_percent)`: the vanilla defect needs a value below 1. | Yes if `_original_ammo_percent < 1` at the time of a grant; otherwise INCONCLUSIVE (enter a second loader mission with partial ammo and repeat) |
| `qa/runtime/ct/issue_357_bomb_cooldown_icon.lua` | #357 | Grant `boon_supportbomb_concentration_01`. Give a grenade. Throw it. Wait for the bubble. Throw a second inside 10 s. Wait 11 s, throw again. Then `bomb_boon_cooldown`=0 and throw. | After the first accepted proc: `has_buff_type("ct_bomb_cooldown_display_concentration")` (template names at `ct/_ct_bomb_cooldown_display.lua:17-31`), remaining duration near 10. Second throw: the buff's end time does not move. After expiry: a new buff appears on the next throw. With 0: the display buff never appears. | Yes |
| `qa/runtime/ct/issue_358_manann_ready_cooldown.lua` | #358 | Grant `ct_boon_manann_tempest`. Wait 1 s. Land a critical hit that procs (rig helper). Wait 9 s. Then set `tweak_manann_tempest_cooldown`=false. | Before a proc: `has_buff_type("ct_manann_ready_display_boon")`. After the proc: `ct_manann_cooldown_display_boon` present and the ready buff absent; about 8 s later ready is back. Option off: neither buff present. Names from `ct/_ct_bomb_cooldown_display.lua:56-66`. | Yes for the boon source. The trait source and the re-wield case need a trait weapon; report them as not run if absent |
| `qa/runtime/ct_dev/issue_249_owner_ammo_parity.lua` | #249 | Boot B. Grant the dev Quiver Cascade boon. `T.cmd("verify_boon_ammo_hud")` before firing, after firing and reloading, after a second grant. | `host_expect_log`: `LOCAL PASS exact=(%d+)/%1 wire=%1/%1` (format seen in the 2026-08-04 log review on the issue). Max ammo above the weapon template base. `T.expect_rt("ct_dev","issue249_stack_rebroadcast_on_restore")`. | No. Solo part only |

**Reused in-mod checks.** `vauls_anvil_reconciler_144`, `anath_raema_registry_retry_288`, `parry_cooldowns_registered_342` (`ct/_ct_official_boon_repairs.lua:198,218,233`): the first two run production logic on isolated tables, the third reads the live registered templates (behaviour, after a roll). `issue357_owner_cooldown_display`, `issue358_manann_tempest_cooldown_display` (`ct/_ct_official_cooldowns.lua:118,121`): wiring. `ct_meta_ammo_current_floor_256`, `ct_anath_raema_active_288`: live, SKIP in the keep.

**Left for humans.** #357 and #358: that the icon art is the right one (class V; attach `T.shot`). #249 (class C): the two-machine run must add: host grants Quiver Cascade to itself and the client; both run `/verify_boon_ammo_hud`; the client's `quiver_stacks` equals the host's count; the host's teammate frame for the client shows the client's exact and max ammo; repeat after one map transition and one hot join. #357: owner-only delivery of the icon to a second player (class C).

**If it FAILS.** #144: the reconciler callback is not attached to the cloned buff; public code in `ct/_ct_official_boon_repairs.lua` (check near `:198`), dev copy `ctd/_ct_meta_trait_boons.lua:115-150,294-307`. #342 non-zero duration: the strip did not run on a roll or reads the wrong table (dev wiring `ctd/_ct_run_creation_owner.lua:652-659`). #256 negative reserve: `ct/_ct_ammo_guard_core.lua` clamp not reached.

### VP-D3-07 curses: Rotten Miasma options, Metal wind adapter, curse lighting

| Field | Value |
|---|---|
| Issues | #361 (R), #253 (R), #243 (V), #258 (V), #271 (V) |
| Arena | `deus` through the loader |
| Mods and stream | Boot A: public `ct` 0.7.354-beta, Verminious Dreams Lighting not loaded (it overwrites the same channels). Plan options before boot: `inject_adventure_maps`=true, `enable_adventure_dlc_termite_2`=true, `enable_adventure_dlc_termite_3`=true. Boot B (only #253): `ct_dev` 0.7.354-dev, because `/ct_weave_metal` exists only in dev (`ctd/_ct_weave_metal_runtime.lua:297`). |
| Boots | 2 |
| Depends on | Rig: `T.shot`, a fixed camera pose, optionally a mean-luminance number per still (not in the T list; without it the stills go to the human list unranked). No fix. |

**Setup.** Active mutator data: `Managers.state.game_mode._mutator_handler._active_mutators[name]` (`V2/scripts/managers/game_mode/mutator_handler.lua:42,675`; handler field at `V2/scripts/managers/game_mode/game_mode_manager.lua:99`). Miasma safe-area unit: that table's `rotten_miasma_safe_area` (`V2/scripts/settings/mutators/mutator_curse_rotten_miasma.lua:116-119`). Shading values: `ShadingEnvironment.vector3(env, name)` and `.scalar(env, "exposure")`, with `env = World.get_data(world, "shading_environment")` (used by vanilla at `V2/scripts/ui/mission_vote_ui/mission_voting_ui.lua:285`; for the level world this is unverified).

**Cases.**

| Script | Issue | Steps (T calls, in order) | Assertions (engine state read, with citation) | PASS closes? |
|---|---|---|---|---|
| `qa/runtime/ct/issue_361_miasma_options.lua` | #361 | `T.set("ct","miasma_safe_radius",12)`, `miasma_stack_interval`=0.5, `miasma_permanent_carrier`=true. `T.cmd("ct_load_mission","pat_forest","0.5","curse_rotten_miasma")`. Give the hero the torch (item `wpn_deus_relic_01` in `slot_level_event`), move 20 m, drop it, move 20 m more. Then set the three options back to 8, 1.3, false. | Exactly one safe-area unit. `BuffTemplates.curse_rotten_miasma.buffs[1].safe_area_radius[i] == 12` and `.buff_exposure_tick_rate == 0.5` (written at `ct/_ct_miasma.lua:26-39`). Live buff on the safe-area unit has `radius == 12` and `Unit.get_data(safe_area, "radius") == 12` (`ct/_ct_miasma.lua:67-78`). After the drop the unit's position stays within 1 m of the hero. After restore: radius 8, tick 1.3, and the unit follows the dropped torch again. | Yes. A dead carrier losing ownership is covered by unit tests of `ct/_ct_miasma_policy.lua:30-39`; add a live kill of a bot carrier if the rig can hand the torch to a bot |
| `qa/runtime/ct_dev/issue_253_metal_wind_adapter.lua` | #253 | Boot B. `T.cmd("ct_weave_metal","on")`, `T.cmd("ct_weave_metal","strength","1")`. Load any mission. Spawn `skaven_storm_vermin` and `chaos_warrior`; apply the same fixed melee hit to each (C1 rows 31, 33). `T.cmd("ct_weave_metal","off")`, load again, repeat. | On: damage taken by the Stormvermin is within 10 percent of the Chaos Warrior's for the same hit. Off: Stormvermin damage is higher than on. No `Managers.weave` nil error in the log. | Yes for the Metal slice. The issue then closes or stays an umbrella by owner decision (default: close after Metal passes; seven other winds not planned) |
| `qa/runtime/ct/issue_271_delvings_lighting.lua` | #271 | `T.cmd("ct_load_mission","dlc_termite_2","0.5","curse_blood_storm")`. Fixed interior camera pose. For `curse_lighting_brightness` in 0.5, 1.0, 2.0: wait 2 s, read shading values, `T.shot`. Repeat with a second curse. | Node theme is the curse's god (`drc:get_current_node().theme`). The interior channels `ambient_tint`, `ambient_tint_top`, `secondary_sun_color` and `exposure` scale with the knob between the three settings (ratio 2 between 1.0 and 0.5 within 5 percent). `T.note` all values. Stills attached. | No (V). Machine part: the knob moves the four channels |
| `qa/runtime/ct/issue_258_well_of_dreams_lighting.lua` | #258 | Same on `dlc_termite_3` with `curse_change_of_tzeentch`, and once with a Khorne curse as control. | Same knob assertion for `ambient_tint_top`. Stills for Tzeentch and control. The fixed x2 for this map and theme lives in `ct/_ct_official_verify_runtime.lua:183-200`; it cannot be toggled, so it is shown only by the stills. | No (V) |
| `qa/runtime/ct/issue_243_belakor_interior_lighting.lua` | #243 | Same on `dlc_termite_2` with `curse_belakor_totems`. | Same knob assertion. Stills. The Belakor profile values are at `ct/chaos_wastes_tweaker.lua:5400` (dev: `ctd/_ct_curse_lighting_owner.lua:138-146`). | No (V) |

**Reused in-mod checks.** `issue361_miasma_customization_installed` (`ct/_ct_official_feature_leaf.lua:34`): hook installed only. `curse_theme_color_backfilled`: data only. No lighting check exists in the public tree.

**Left for humans.** #243, #258, #271: one person looks at the three still sets and answers "interior readable, still looks cursed, exterior not washed out". #361: how the sphere looks to a client (class C/V). #253: none.

**If it FAILS.** Miasma radius unchanged: the `server.update` wrapper did not install because `MutatorTemplates.curse_rotten_miasma.server.update` was not a function at mod load (`ct/_ct_miasma.lua:80-83,105-116`). Knob has no effect: the shading hook only runs on injected adventure levels, so check the injection options took effect (restart needed) and that vdl is not loaded.

### VP-D3-08 scaling: progressive difficulty, modifier stacking, elite enhancements, grudge bans, Citadel gods

| Field | Value |
|---|---|
| Issues | #460 (R), #289 (R), #323 (R), #107 (R), #146 (R) |
| Arena | `deus`, one ordinary pilgrimage played across 5 maps by script |
| Mods and stream | Public `ct` 0.7.354-beta. Options: `progressive_difficulty`=true, `progressive_difficulty_increase`=true, `progressive_coin_reduction`=-25, `coin_multiplier`=2.0, `progressive_modifier_stack`=true, `cursed_mission_count`=30, `progressive_elite_enhancements`=true, `progressive_elite_step_percent`=25, `disable_dominant_god`=true, `finale_dominant_god`=3 (Khorne), `finale_approach_god`=1 (Nurgle); god order `nurgle, tzeentch, khorne, slaanesh` at `ct/_ct_diag_official_apply_evidence.lua:97`. Start on Legend (`hardest`). |
| Boots | 1 for the run, plus 1 control boot with every option above off |
| Depends on | Rig: start an ordinary pilgrimage, win a level (C1 row 41), pick the next node on the map screen, `T.spawn` with spawn data. Fix NF-5 before the run may finish the journey at Cataclysm 2 or 3 on the public build: until then stop after map 5 is entered. |

**Setup.** Completed maps: `drc._run_state:get_completed_level_count()` (the read the mod uses, `ct/_ct_diag_official_apply_evidence.lua:241`). Run difficulty: `drc:get_run_difficulty()` (`V2/scripts/managers/game_mode/mechanisms/deus_run_controller.lua:509`). Active mutators: `Managers.state.game_mode._mutator_handler:has_activated_mutator(name)` (`V2/scripts/managers/game_mode/mutator_handler.lua:220`). Coins: `drc:get_player_soft_currency(drc:get_own_peer_id())` (`:925`); a synthetic pickup is `drc:on_soft_currency_picked_up(10)` (`:900`). Enhancement buffs on a unit: `has_buff_type("grudge_mark_<name>")`; the engine adds them at `V2/scripts/settings/terror_events/terror_event_utils.lua:80-104` from the lists in `V2/scripts/settings/grudge_mark_settings.lua:3-8,104-119`. A spawn with enhancements: `Managers.state.conflict:spawn_queued_unit(breed, pos, rot, category, nil, nil, { enhancements = {...} })` (`V2/scripts/managers/conflict_director/conflict_director.lua:1732,2039-2041`).

**Cases.**

| Script | Issue | Steps (T calls, in order) | Assertions (engine state read, with citation) | PASS closes? |
|---|---|---|---|---|
| `qa/runtime/ct/issue_460_progressive_difficulty.lua` | #460 | At each of maps 1 to 5 after entry: read difficulty, do one synthetic coin pickup of 10, `T.cmd("verify_ct_progression")`. Win the level, pick the next node. | Difficulty: `hardest` on maps 1-2, `cataclysm` on 3-4, `cataclysm_2` on 5 (policy `ct/_ct_progressive_difficulty.lua`, step after 2 and after 4 completed maps). Coin delta: 20 on maps 1-2, 15 from map 3. `host_expect_log`: `%[ct:ct_progression%] PASS` at every map. A second fresh run starts at `hardest`. Control boot: difficulty constant and delta 20 on all maps [the pickup multiplier is `coin_multiplier` x reduction; confirm rounding in `ct/chaos_wastes_tweaker.lua:657` hook]. | Yes. Hot-join tier agreement is class C |
| `qa/runtime/ct/issue_289_modifier_stack.lua` | #289 | Same run. On every cursed mission read the node curse and the two allowlisted mutators. Also read them inside a shrine node. | Maps 1-2: neither `curse_empathy` nor `curse_abundance_of_life` active unless it is the node's own curse. From map 3 on a cursed mission: exactly one of the two is active and it differs from `drc:get_current_node().curse` (allowlist at `ct/_ct_modifier_stack_policy.lua:18`). Shrine and map screen: neither active. Control boot: never active beyond the node's own curse. | Yes for the host. Client activation is class C |
| `qa/runtime/ct/issue_323_progressive_elites.lua` | #323 | On map 1 and on map 5 (4 completed, rate 100 percent at step 25): spawn 5 `skaven_storm_vermin`, 5 `skaven_clan_rat`, 2 `skaven_gutter_runner` with plain `spawn_queued_unit`. Then `T.set("ct","ban_all_grudge_marks",true)` and spawn 5 more Stormvermin. | Map 1: no spawned unit has `grudge_mark_elite_health`. Map 5: every Stormvermin has `grudge_mark_elite_health` and exactly one of `grudge_mark_shockwave_attacks` or `grudge_mark_ignore_death_aura` (recipes at `ct/_ct_progressive_elite_policy.lua:28-29`); clan rats and the special have none. With ban-all on the Stormvermin result is unchanged. | Yes for the CT slice. The Enemy Tweaker half moves to #453 |
| `qa/runtime/ct/issue_107_grudge_filter.lua` | #107 | Any loader mission. `ban_grudge_mark_commander`=true, others off. Spawn `chaos_warrior` with `enhancements = { BreedEnhancements.base, BreedEnhancements.commander, BreedEnhancements.frenzy }`. Then `ban_all_grudge_marks`=true and spawn again. Then both off and spawn again. | Run 1: unit has `grudge_mark_health` and `grudge_mark_frenzy`, not `grudge_mark_commander`. Run 2: has `grudge_mark_health`, neither mark. Run 3: all three. `T.cmd("verify_grudge_marks")` reports 0 FAIL (`ct/chaos_wastes_tweaker.lua:7788`). This exercises the same `apply_breed_enhancements` seam the Shadow Lieutenant uses. | Yes |
| `qa/runtime/ct/issue_146_citadel_gods.lua` | #146 | In the run, once the graph exists: `T.cmd("verify_ct_citadel")`. Read `drc._path_graph`. If the run reaches the Citadel, record the level keys that load. | Every node whose `level` starts with `sig_citadel_` has `theme == "nurgle"` and `god == "nurgle"`; every `arena_citadel_` node has `khorne` (fields read at `ct/_ct_diag_official_apply_evidence.lua:92-113`). `host_expect_log`: `%[ct:ct_citadel%] PASS`. Second run with `finale_approach_god`=0: both follow Khorne. | Yes for the graph. Loading both Citadel maps without error needs the run to reach them (blocked by NF-5 at Cataclysm 2+; start that run on Recruit) |

**Reused in-mod checks.** `issue289_progressive_modifier_stack` (`ct/_ct_progressive_modifier_runtime.lua:207`) and `issue323_progressive_elite_runtime` (`ct/_ct_progressive_elite_runtime.lua:206`): seam and policy presence. `issue107_grudge_application_master` (`ct/_ct_official_verify_runtime.lua:361`): callback logic on synthetic data. `ct_progression_readback_460`, `ct_citadel_graph_readback_146`: live, SKIP in the keep.

**Left for humans.** #146: that the two Citadel maps look like their gods (class V, low value). #460, #289: a second client agreeing on tier and on the extra mutator (class C).

**If it FAILS.** Wrong tier: `ct/_ct_progressive_difficulty.lua` or the immutable start tier `drc._ct_progdiff_start` was not captured. Extra mutator missing: the `GameModeDeus.mutators` hook (`V2/scripts/managers/game_mode/game_modes/game_mode_deus.lua:667`). Ban-all strips `grudge_mark_health`: the pre-0.7.354 defect is back (the filter must only touch the 13 names at `ct/chaos_wastes_tweaker.lua:7661`).

### VP-D3-09 injected-maps: Adventure maps inside Chaos Wastes keep their objects

| Field | Value |
|---|---|
| Issues | #52 (R), #251 (R), #456 (R), #1124 (R) |
| Arena | `deus` through the loader, plus `mission:<level_key>` native controls |
| Mods and stream | `ct_dev` 0.7.354-dev. All four cards name dev and the diagnostic rows `[ct:skull52]`, the book-spawner census and `[ct:1124]` exist only there. Plan options before boot: `inject_adventure_maps`=true and `enable_adventure_<key>`=true for `dlc_wizards_tower`, `dlc_bastion`, `skaven_stronghold`, `dlc_portals`; `cursed_chest_count`=3. |
| Boots | 1 |
| Depends on | Rig: loader, native mission load, unit census. VP-D3-02 must pass on the dev build first. Fix NF-8 after this pack names the cause for #251 and #456. |

**Setup.** Object sets the engine spawns for a level and mode: `GameModeHelper.get_object_sets(level_name, game_mode_key)` returns the spawned set list (`V2/scripts/managers/game_mode/game_mode_helper.lua:58-98`); `level_name` is `LevelSettings[key].level_name`. Book spawners: `Managers.state.entity:system("pickup_system").guaranteed_pickup_spawners` and `.triggered_pickup_spawners` (`V2/scripts/entity_system/systems/pickups/pickup_system.lua:64-65,249-263`). Spawned books and heads: `pickup_system:get_pickups_by_type("tome" | "grimoire" | "gargoyle_head")` (`:232`). Cursed chests: `get_entities("DeusCursedChestExtension")`.

**Cases.**

| Script | Issue | Steps (T calls, in order) | Assertions (engine state read, with citation) | PASS closes? |
|---|---|---|---|---|
| `qa/runtime/ct_dev/issue_52_tower_object_sets.lua` | #52 | `T.cmd("ct_load_mission","dlc_wizards_tower")`. In the mission compute the spawned set list for mode `adventure` and for the live game mode key (`Managers.state.game_mode:game_mode_key()`). | Every set spawned under `adventure` is also spawned under the live mode. `T.note` both lists and the `[ct:skull52] ... phase=selection_final` row (`ctd/_ct_diag_skull52.lua:415`). | Yes. The skulls only feed an achievement (`V2/scripts/flow/flow_callbacks.lua:5628-5629`), so set parity is sufficient |
| `qa/runtime/ct_dev/issue_456_nest_grimoires.lua` | #456 | Control: arena `mission:skaven_stronghold`, wait 10 s, record each grimoire position. Then `T.cmd("ct_load_mission","skaven_stronghold")`, wait 10 s, record again. | Control has 2 grimoires. Injected run: a grimoire (or the pickup the mod converts it to; record its name) within 2 m of each control position. List every guaranteed and triggered spawner with position and resulting pickup. | Yes if both positions are filled. If the first is empty the listing is the diagnosis for NF-8 |
| `qa/runtime/ct_dev/issue_251_bastion_first_tome_chest.lua` | #251 | Control: `mission:dlc_bastion`, record the 3 tome positions. Then `T.cmd("ct_load_mission","dlc_bastion")` on Cataclysm, wait 10 s. | A cursed chest within 2 m of each control tome position (cap 3). `host_expect_log`: `%[populate_pickups%] level=.- diff_has_entry=true`. `host_forbid_log`: `NO MATCH for current difficulty`. | Yes if all three are filled. Otherwise the per-spawner listing is the diagnosis for NF-8 |
| `qa/runtime/ct_dev/issue_1124_old_haunts_heads.lua` | #1124 | `T.cmd("ct_load_mission","dlc_portals")`. Win-skip or teleport to the objective start (C1 row 33). Poll for 120 s. | `#get_pickups_by_type("gargoyle_head")` reaches 4 [pickup key from the issue body, `penny_level_settings_part_1.lua:63-67`, not re-read]. `host_expect_log`: `%[ct:1124%] .*mutation=false`. If the rig can carry a head to a socket, also expect a `[ct:1124] ... completed=true` row. | Yes when four heads spawn and the objective completes. Four heads without completion is INCONCLUSIVE |

**Reused in-mod checks.** None that test behaviour. `diag_132_134_136_present` and the #52 / #1124 probe checks only say the probes are installed.

**Left for humans.** Nothing. Co-op on injected maps is blocked on NF-6.

**If it FAILS.** #52 set missing under the live mode: the #156 object-set repair regressed; compare `GameModeSettings.deus.object_sets` with `GameModeSettings.adventure.object_sets`. #251 and #456: read the listing: a missing spawner, a triggered spawner never activated, or a cap that selected other spots (see `ctd/_adventure_pool.lua:383-475` and `V2/.../pickup_system.lua:821-844`).

### VP-D3-10 bots: chest revive brings the bot to the team; progression survives a bot swap

| Field | Value |
|---|---|
| Issues | #299 (R), #465 (C: solo part only) |
| Arena | `deus` through the loader, with bots |
| Mods and stream | Boot A: public `ct` 0.7.354-beta, option `respawn_on_chest_complete`=true. Boot B (only #465): `ct_dev` 0.7.354-dev; the feature exists only in dev (`ctd/_ct_replacement_runtime.lua`). |
| Boots | 2 |
| Depends on | Rig: kill a unit and teleport (C1 row 33), complete a Chest of Trials (start it as in VP-D3-04, then kill the wave). `coop` arena for the #465 remainder. NF-10 may affect that remainder. |

**Setup.** A mission with at least one cursed chest and three bots. Positions from `POSITION_LOOKUP[unit]`. The public rescue code logs one row per attempt: `[ct:299] key=... alive=... awaiting=... health_alive=... moved=... freed=... retained=... action=...` (`ct/_ct_official_chest_rescue.lua:311`), tolerance 3 m (`ct/_ct_chest_revive_policy.lua`, `RETAIN_DISTANCE_SQ = 9`).

**Cases.**

| Script | Issue | Steps (T calls, in order) | Assertions (engine state read, with citation) | PASS closes? |
|---|---|---|---|---|
| `qa/runtime/ct/issue_299_chest_revive_moves_bot.lua` | #299 | Teleport the team 60 m past the nearest respawn point. Kill one bot. `T.wait_until(bot is dead and waiting for rescue, 60)`. Complete the Chest of Trials with the hero. `T.wait_until(bot unit alive again, 30)`. | At the first frame the bot is alive: distance from the bot to the nearest living teammate is at most 3 m. 5 s later still within 10 m (it did not run back). `host_expect_log`: `%[ct:299%] .*retained=true`. `host_forbid_log`: `%[ct:299%] .*FAILED`, `DROPPED`, `DEGRADED`. | Yes for bots. A dead human client is class C |
| `qa/runtime/ct_dev/issue_465_bot_side_capture.lua` | #465 | Boot B. Start a run, note that bots were added. | `host_expect_log`: a `%[ct:465%] .*policy=implicit` row (`ctd/_ct_replacement_runtime.lua:43`; text asserted by `qa/lua/tests/test_ct_replacement_compensation.lua:380`). Offline: `powershell -File qa/check_lua_unit_tests.ps1` passes that test file. | No. Solo part only |

**Reused in-mod checks.** `issue299_chest_revive_move_before_free` (`ct/_ct_official_chest_rescue.lua:397`): policy marker and adapter presence; it cannot fail on a wrong landing.

**Left for humans.** #465 (class C). The two-machine run must add: client collects two named boons and coins; client leaves; assert the replacing bot holds the same boons (host reads `drc:get_player_power_ups` for the bot); client rejoins; assert the boons are back exactly once and coins follow the host-balance rule in `chaos_wastes_tweaker_dev/REPLACEMENT_COMPENSATION.md`. #299: one co-op check that a dead human is moved the same way.

**If it FAILS.** #299 bot alive far away: the readback at `ct/_ct_official_chest_rescue.lua:263-268` accepted a wrong position, or the move was skipped (`action=` field in the row).

### VP-D3-11 wire-parity: mod boons never reach a peer that cannot decode them

| Field | Value |
|---|---|
| Issues | #426 (C: solo part only) |
| Arena | `keep` and `deus`; `coop` for the remainder |
| Mods and stream | Public `ct` 0.7.354-beta alone. The issue carries `public-release` and its card says not to close on dev evidence. |
| Boots | 1 solo, then the two-machine run |
| Depends on | Rig: `coop` arena with a second machine that does not load `ct`. Owner decision NF-6 changes what the two-machine run should expect. #1191 is merged here; its dev-side gap is NF-4. |

**Setup.** The public wire catalog has 29 rows: 10 power-ups and 19 buffs (`chaos_wastes_tweaker/CHANGELOG.md:5-7`; names in `ct/_ct_wire_policy.lua`).

**Cases.**

| Script | Issue | Steps (T calls, in order) | Assertions (engine state read, with citation) | PASS closes? |
|---|---|---|---|---|
| `qa/runtime/ct/issue_426_catalog_integrity.lua` | #426 | Arena `keep`. For every catalog name read both lookup directions. `T.cmd("ct_426_diag")`. | `rawget(NetworkLookup.deus_power_up_templates, name)` (or `NetworkLookup.buff_templates` for buff rows) is an integer and the reverse row equals the name. `#NetworkLookup.deus_power_up_templates <= 255`. `T.expect_rt("ct","ct_426_public_exact_catalog")`, `T.expect_rt("ct","ct_426_public_receiver_floors")`. | No. Solo part |
| `qa/runtime/ct/issue_426_solo_boon_works.lua` | #426 | Arena `deus`, loader mission. Grant `ct_boon_vauls_anvil`. | It is in `drc:get_player_power_ups(peer, 1)` and its buff is on the hero. No `[ct:426] BLOCKED` row solo. `T.expect_rt("ct","ct_426_public_gate_surface")`, `T.expect_rt("ct","ct_426_public_hot_join_containment")`. | No. Solo part |

**Reused in-mod checks.** The four `ct_426_public_*` checks (`ct/_ct_peer_parity_owner.lua`, names listed at `:1211` area): they read the live lookup tables and the installed hook set, so they test state, not gameplay.

**Left for humans.** #426 (class C). The two-machine run must add, with machine B not loading `ct`: (1) B joins the host in the keep and both reach a Chaos Wastes mission; (2) the host enables a mod boon as a starting boon and tries to buy one at a shrine; assert on the host that no mod power-up name appears in any player's `get_player_power_ups` and no mod buff is added while B is present; (3) B's log has no script error and B stays connected for 5 minutes of play; (4) B leaves: mod boons become available again. Then repeat with B on a different `ct` build (the #1191 case): the gate must stay closed.

**If it FAILS.** Catalog row missing: registration order changed; see `ct/_ct_wire_bootstrap.lua`. A mod boon reached B: find which writer was not fenced; the public fence hooks are registered in `ct/_ct_peer_parity_owner.lua:739-1115` (per A4-F05).

<!-- D3-CONTINUE -->
