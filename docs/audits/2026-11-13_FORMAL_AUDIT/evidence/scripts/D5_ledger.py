# D5 ledger builder: writes findings/D5_ledger.tsv and validates row count / word limits.
import os, collections
BASE = r'<audit-workspace>'
HDR = ['number','mod','author_class','type','lifecycle','priority','summary','cluster','fix_state',
       'verification_class','auto_check','disposition','related','confidence','note']
R = []
def row(*a):
    assert len(a) == len(HDR), (a[0], len(a))
    R.append(list(a))

GT = 'general_tweaker'
GTD = 'general_tweaker_dev'

row(2,'repo (all mods)','owner','tooling','not-started','2-moderate',
    'Umbrella ratchet: split Lua files over 1500/2500 lines; one hard-limit file and 19 target-tier files remain.',
    'arch-umbrella','needs-design-decision','S',
    'qa/check_file_sizes.ps1 exit 0. Ran today: exit 1; hard-limit=1 (stable chaos_wastes_tweaker.lua, 12455 lines), target-tier=19, 2 baseline rows removable.',
    'OWNER-DECISION','428, 546, 504c, 1159c, 429c','H',
    'Recommend close: the gate plus qa/baselines/file_sizes*.json already own the debt and block growth; 134 comments are a publication log. Hard-limit file disappears on the next full CT stable promotion (dev twin is 1497 lines). 7 of 19 target rows are data tables or check registries.')

row(72,GT,'owner','tooling','verify-fix','3-low',
    'Five failed-join popup hardening regression checks (ownership, teardown, soft deferral, unknown result, nil-preserving forward).',
    'gt-lobby-session','fix-shipped-unverified','U',
    'Execute the five registered checks offline against production _gt_lobby_failed_join_reveal.lua (they use fake tables only) plus test_gt_lobby_failnotify_hardening.lua green.',
    'CLOSE-STATIC-VERIFIABLE','16c, 378','H',
    'All five names registered in official 0.2.180; check bodies are pure Lua (general_tweaker/.../_gt_regression_checks.lua:817-845). Offline test reads only the dev tree. A coverage issue should close on the test run, not on a human typing the command.')

row(169,GT+' (stable)','owner','tooling','not-started+blocked','3-low',
    'Retired enable_debug_logging key: one executable read remains in official General _gt_debug_probes.lua:91.',
    'stable-promotion-debt','blocked:stable-promotion (missed twice)','S',
    'qa/check_logging.ps1 "#169 retired-key floor" reports zero sites (today: 1 pinned site) and test_gt_vmf_debug_gate.lua green.',
    'MERGE-INTO:427','427, 724, 1509c','H',
    'General stable shipped 0.2.179 (041d59fc, 2026-11-02) and 0.2.180 (72ab4d29, 2026-11-06) without this one-line fix although the issue was "blocked on stable promotion". Dev already fixed. Candidate branch origin/agent/issue169-retired-key-gate [unverified].')

row(241,GT,'owner','bug','verify-fix','1-major',
    'Noclip must suppress ledge grab, kill volumes and deep-floor suicide for the local player only.',
    'gt-godmode-noclip','fix-shipped-unverified','R',
    'Harness: noclip on, move player below z=-240 and call entered_kill_volume; assert alive, not ledge-hanging; noclip off: same calls kill.',
    'KEEP-VERIFY','939c','H',
    'Fix present in official 0.2.180: _gt_noclip.lua:159,164,171,179,188,209. Named check issue241_noclip_boundary_routes only tests a wired-flag. Joining-client rpc_suicide route is class C.')

row(242,GT,'owner','bug','verify-fix','1-major',
    'Disable Enemy Spawns must also stop monsters, patrols, specials and critters.',
    'gt-spawner','fix-shipped-unverified','R',
    'Harness: option on, load mission, tick 120 s through pacing; assert ConflictDirector._all_spawned_units stays empty and script_data flags set; option off: units appear.',
    'KEEP-VERIFY','254, 1138','H',
    'Fix present: general_tweaker.lua:1238-1262 (spawn_unit_immediate), _gt_time_hooks.lua:47 (dequeue gate), flags :1273-1290. Named check is marker-only (:1299-1330). Flag ai_outside_navmesh_intervention_disabled has no reader in the decompiled source.')

row(247,GT,'owner','bug','verify-fix','1-major',
    'Bot takeover keep-slot redesign: temporary bot drives own hero, AFK takeover, clean reclaim.',
    'gt-bots','blocked:emergency gate true in carded official 0.2.180','R',
    'Assert mod._gt_ai_takeover_disabled == false, toggle ai_takeover_enabled, assert a bot player controls the hero unit and party slot unchanged; toggle off restores human control.',
    'KEEP-FIX','44c, 359c','H',
    'S1. Card targets official 0.2.180 but general_tweaker.lua:260 sets mod._gt_ai_takeover_disabled = true (also in published commit 73d7c367); all entry points bail (_gt_ai_takeover.lua:217,356,431,508,639,772) and issue247_keep_slot_takeover_wired returns FAIL (_gt_regression_checks.lua:858). Dev has false (general_tweaker_dev.lua:271). Unit test covers dev only.')

row(254,GTD,'owner','bug','diagnostics-armed','2-moderate',
    'Creature Spawner reports success but no enemy appears in Chaos Wastes missions.',
    'gt-spawner','diag-armed-no-data','R',
    'Harness in a Deus level: request one clanrat through the spawner, wait 8 s, parse [gt:254] enqueue/blocker/terminal rows and count units of that breed.',
    'KEEP-FIX','59c, 693c, 802','M',
    'No fix exists; probe in general_tweaker_dev/_gt_creature_spawner.lua (issue254_deus_spawn_queue_diagnostics_armed registered). One autonomous run selects the fix branch.')

row(282,'weapon_tweaker + cwv + cosmetics','owner','crash','verify-fix','0-critical',
    'Package reference leak gives "not unloaded" deadlock warning at shutdown; Deepwood lease latch fixed.',
    'package-residency','fix-shipped-unverified','R',
    'Harness: 3x Keep-mission-Keep, read Managers.package:reference_count per mod reference name (bounded), quit, grep console log for "not unloaded" and "Package still referenced".',
    'KEEP-VERIFY','201, 702, 947, 154c, 477c','M',
    'Deepwood fix present in both WT streams (_wt_deepwood_runtime.lua:96-110, identical files; engine PackageManager.is_loading at foundation/.../package_manager.lua:282). Thread drifted across three mods; the original handgun _3p leak was never attributed. Should become the cross-mod package-ledger harness issue.')

row(298,GT,'owner','feature','verify-fix','2-moderate',
    'Six independent Improved Bot Combat toggles and three sliders; attacker ping still elite-only.',
    'gt-bots','fix-shipped-unverified (partial scope)','R',
    'Harness: per child toggle, feed bot blackboard an elite/special/boss attacker and assert ping and target decisions; policy truth table offline (test_gt_improved_bot_combat_controls.lua).',
    'OWNER-DECISION','297c, 261c, 468c','H',
    'Controls present in official data (general_tweaker_data.lua:213-226). _gt_improved_bot_combat.lua:191 admits breed.elite only; issue asked elites+monsters+specials. Official 0.2.180 has no issue298_* runtime check although the card says "the named control regression passes". Decide: accept elite-only and close on R, or extend classifier (small U-testable change).')

row(300,GT,'owner','bug','verify-fix','2-moderate',
    'Bound awaiting-respawn bot rescue range: unlimited, shared follow leash, or custom 10-100 m.',
    'gt-bots','fix-shipped-unverified','R',
    'Harness: put a player in assisted-respawn state at 30 m and 45 m, run three modes, read bot blackboard ally target; selection only at or inside limit.',
    'KEEP-VERIFY','261c, 384c, 492c, 515c','H',
    'Policy present in official: _gt_bot_fixes.lua:733-791, widgets general_tweaker_data.lua:160-183. Pure distance policy also U-testable.')

row(302,GTD,'owner','feature','diagnostics-armed','1-major',
    'Developer geometry highlight toggles: seven of thirteen requested categories ship, outline only, no fill.',
    'gt-client-visual','needs-design-decision','V',
    'Automatable part: per-category draw counter above zero when matching units exist and no error spam; overlay alignment and colour need eyes.',
    'OWNER-DECISION','508c','H',
    'Owner-only dev tool. 2026-08-02 audit asked for a ruling: accept seven-category outline-only scope or continue. Recommend accept and close; 1-major is inflated for a debug overlay.')

row(309,GTD,'owner','feature','not-started+blocked','2-moderate',
    'Disconnect grace: trace falsified the design (unit already dead, slot becomes bot in 0.05 s); needs ruling.',
    'gt-lobby-session','needs-design-decision','C',
    'None if closed. Option A (grace on replacement bot) would need two clients and a damage-ledger assertion on the replacement bot.',
    'OWNER-DECISION','608c, 731c, 1153c, 753','H',
    'Recommend close as infeasible (option B): diagnostics did their job on 2026-08-04. Blocked since 2026-08-16 on a yes/no question.')

row(321,'weapon_tweaker + enemy + career + chaos_wastes','owner','enhancement','verify-fix','2-moderate',
    'Retire inert Big Rebalance toggles; gate rejects active widgets, module loads and Workshop claims.',
    'retired-br','fix-shipped-unverified','S',
    'qa/check_retired_big_rebalance.ps1 exit 0 (ran today: OK) plus test_crt_retired_big_rebalance.lua green.',
    'CLOSE-STATIC-VERIFIABLE','301c, 433c','H',
    'Resolution is deletion; nothing behavioural to observe. Card asks a human to scroll six settings pages looking for an absent group; the widget tree is static data.')

row(332,GT,'owner','enhancement','verify-fix','2-moderate',
    'Client-side mutator death-explosion filter and client-only retained corpse cap (Max Ragdolls).',
    'gt-coop-client','fix-shipped-unverified','C',
    'On a joined client: count retained corpse units against cap after N kills and after lowering cap; log filtered explosion template names. Needs a host peer; corpse look is visual.',
    'KEEP-VERIFY','','M',
    'Present in official: _gt_client_ragdolls.lua:34 (max 0), :205-229 (1 s reconcile). RainReligion 2026-08-04: corpses linger about 2 s with explosions disabled; the follow-up question to Rain was never answered.')

row(333,GT,'owner','feature','verify-fix','2-moderate',
    'Offline Twitch mode without an account; four category filters must apply to both vote candidates.',
    'gt-twitch','fix-shipped-unverified','R',
    'Harness: enable mode, disable one category, start mission, call TwitchGameMode:_get_next_vote 200 times; assert no template of the disabled category in either slot.',
    'KEEP-VERIFY','','H',
    'Fix present in official: _gt_offline_twitch.lua:72-93 (hooks _in_whitelist and replaces native _next_standard_vote; engine twitch_manager.lua:1287,1403). Re-implemented vanilla selection can drift after a game patch. Offline oracle test exists for both streams.')

row(347,GTD,'rain','feature','diagnostics-armed','2-moderate',
    'Bots should collect pickups inside closed chests; observation probe armed, never run.',
    'gt-bots','diag-armed-no-data','R',
    'Harness: stand a bot beside a closed chest, arm /gt_chest_pickup_probe, open chest via interaction, parse [gt:347] availability census before and after.',
    'KEEP-FIX','297c, 364, 294c','M',
    'Feasibility question, not a fix. If contents are not in AIBotGroupSystem tables before opening and no Lua reveal event exists, close as not feasible with the trace as the reason.')

row(364,GT,'owner','bug','verify-fix','2-moderate',
    'Bots must not claim or drink Bardin Survival Ale via mule claim, greedy pickup or instant pickup.',
    'gt-bots','fix-shipped-unverified','R',
    'Harness: spawn bardin_survival_ale near idle bots for 30 s; assert no bot blackboard mule_pickup or inventory holds it; potion control still picked up.',
    'KEEP-VERIFY','365, 297c, 366c','H',
    'In-game check still string-predicate only (_gt_bot_pickups.lua:29-37) but an offline test now drives the three production consumers (test_gt_official_verify_rollup.lua:225-289), which was the 2026-08-03 requirement.')

row(365,GT,'owner','feature','verify-fix','3-low',
    'Bots may drink surplus ale only when every teammate has three stacks above half duration.',
    'gt-bots','fix-shipped-unverified','R',
    'Harness: set team ale buff stacks/durations through BuffExtension, spawn ale, tick; assert consumption only in full-stack over-half case; policy table offline.',
    'KEEP-VERIFY','364, 320c','H',
    'Policy present in official: _gt_bot_ale_policy.lua:5-24; issue365_smart_bot_ale_policy registered.')

row(378,GTD,'owner','bug','diagnostics-armed','1-major',
    'Missing-mod lobby join hangs forever; watchdog shipped in dev; real hang never reproduced.',
    'gt-lobby-session','fix-shipped-unverified','U',
    'Run gt_lobby378_watchdog_abort_reroutes_to_menu offline (fake StateLoading, pure Lua). Real hang needs a named mod combination that stalls: currently unknown (X).',
    'CLOSE-STATIC-VERIFIABLE','72','M',
    'Label wrong: a fix shipped, this is not diagnostics. 2026-08-04 logs: mismatched join succeeded in 0.09 s. Issue itself says close as not reproducible once the synthetic check passes (_gt_regression_checks.lua:459-485, dev). Watchdog is not in the official stream.')

row(380,GTD,'owner','bug','diagnostics-armed','2-moderate',
    'Downed red overlay and wounded grayscale persist with Disable Downed Screen Effects on.',
    'gt-client-visual','diag-armed-no-data','R',
    'Harness: option on, /down, parse [gt:neuterfx] swallowed rows for three moods and read MoodHandler active moods; remaining on-screen tint is visual.',
    'KEEP-FIX','','M',
    'No current log has the option enabled. Engine seam MoodHandler.set_mood at mood_handler.lua:335. RainReligion also asked for the wounded grayscale to be removed.')

row(385,GTD,'owner','bug','diagnostics-armed','2-moderate',
    'Bots teleport repeatedly while already closer than the leash distance (no-path branch).',
    'gt-bots','diag-armed-no-data','R',
    'Soak harness: bots plus scripted player route through obstructed geometry; count [gt:385] below-leash teleports per bot per 5 s window; assert at most one.',
    'KEEP-VERIFY','139c, 515c','M',
    'Retry bound shipped (gt_bot385_close_no_path_retry_bound); pre-#515 trace is stale. Engine BTConditions.cant_reach_ally at bt_bot_conditions.lua:1167.')

row(421,'cosmetics_tweaker','owner','crash','verify-fix','0-critical',
    'Custom ct_* illusion keys must never reach the vanilla weapon_skins wire (non-mod peer crash).',
    'wire-safety','fix-shipped-unverified','C',
    'Single-client part: equip a ct_* illusion, wrap the four rpc_add_equipment senders, assert outgoing weapon_skin_id within vanilla lookup size. Peer survival needs a non-mod client.',
    'KEEP-VERIFY','660, 371, 1145, 422c, 737c, 495c','H',
    'Fix present: cosmetics_tweaker/.../_cos_wire.lua:28-53 null-and-restore; /cos_421_diag at _cos_diagnostics.lua:217. Child of #660/#371. Mis-bucketed: no Cosmetics label.')

row(427,'chaos_wastes_tweaker + general_tweaker + verminious_dreams_lighting (stable)','owner','bug','not-started+blocked','2-moderate',
    'Three public stable _dbg_alert helpers send routine diagnostics to chat through mod:warning.',
    'stable-promotion-debt','blocked:stable-promotion (missed in three promotions)','S',
    'qa/check_logging.ps1 -Quiet -WarnChatRegression prints debt remaining=0. Ran today: exit 0, remaining=3.',
    'KEEP-FIX','169, 499, 727, 1025, 240c','H',
    'general_tweaker.lua:48-50, chaos_wastes_tweaker.lua:89-91, verminious_dreams_lighting.lua:20-22. GT stable shipped 2026-11-02 and 11-06, CT stable 2026-11-06 (d372880f) without the three-line port. Make this the single stable-debt carrier for #169/#499/#727/#1025.')

row(428,'repo (all mods)','owner','tooling','not-started','2-moderate',
    'Umbrella: shared copied _lib_*.lua libraries; 15 canon libs with drift gate; consumer migrations remain.',
    'arch-umbrella','no-fix (substrate done, migrations remain)','S',
    'qa/check_shared_lib_drift.ps1 exit 0 (ran today: OK) plus a census showing zero unmanifested duplicate helpers named in OOP_REFACTOR_PLAN WS4.',
    'KEEP-FIX','2, 546, 660, 420, 1155c, 431c','M',
    'Real remaining work per docs/OOP_REFACTOR_PLAN.md:218-232: per-owner NetworkLookup migrations, wire-substitution helper (4 inline copies in cosmetics), triplicated diag probe, MIL embed. Body no longer matches title; 43 comments are release receipts. Replace with at most five bounded child tasks.')

row(444,'all mods','owner','enhancement','not-started+blocked','3-low',
    'Translate about 7,047 English strings into seven Fatshark locales; readiness gate exists; blocked on English freeze.',
    'i18n','blocked:english freeze','S',
    'qa/check_translation_readiness.ps1 -Strict exit 0 (issue reports 49,329 missing translations, 34 computed generators).',
    'CLOSE-NOT-PLANNED','340, 346c, 443c','M',
    'Not required for "every existing feature works". Park the plan in docs/TRANSLATION_READINESS_444.md and reopen at a 1.0 freeze.')

row(488,GTD,'rain','feature','diagnostics-armed','3-low',
    'Bot gas and warpfire stacking resistance shipped; shield-versus-Ratling behaviour still observation only.',
    'gt-bots','fix-shipped-unverified (hazard) + diag-data-captured-not-acted (ratling)','R',
    'Harness: apply six gas then six warpfire hits to a bot, read mitigation receipts 0/20/40/60/80/100 percent per hazard, reset after 2 s clear.',
    'KEEP-VERIFY','297c','M',
    'Two unrelated ideas in one issue. 2026-07-18 log sweep already captured ratling state walks 1-12 but no design followed. Close hazard half on R; move ratling shield to its own issue or decline.')

row(490,GT+' (stable)','owner','crash','verify-fix','1-major',
    'Official General world-liveness fixes: GUI material, stale world handle, has_world gates.',
    'gt-stable-liveness','fix-shipped-unverified','R',
    'Harness: Draw boss-event spheres on, 3x Keep-mission-Keep plus one restart; process alive, no "Gui material not found" or access violation in log.',
    'KEEP-VERIFY','293c, 459c, 302','H',
    'Fix present in official: _gt_bot_teleport_lab.lua:853,860,877,906-908; _gt_solo_qol.lua:351. Offline test_gt_stable_world_liveness.lua exists. Issue body still says 0.2.177 while the card says 0.2.180.')

row(499,'repo (all mods)','owner','tooling','not-started+blocked','2-moderate',
    'Diagnostics registry and ownership gate landed; one legacy probe file left in official General.',
    'stable-promotion-debt','blocked:stable-promotion (missed twice)','S',
    'qa/diagnostic_ownership.psd1 has zero LegacyProbe rows and zero RemovalIssue=499 rows (today 1 and 6); only two standing *probe*.lua roots remain.',
    'MERGE-INTO:427','198c, 524c, 347, 393, 518','H',
    'Remaining file: general_tweaker/.../_gt_probe_dummy_hits.lua. The other five RemovalIssue rows are live diagnostics that die with their own issues. Registry: 23 rows (16 active, 4 permanent, 2 standing, 1 temporary).')

row(509,'dcp + woc + enemy + modded_progression','owner','tooling','not-started+blocked','2-moderate',
    'Regression harness backfill for four mods is in source; held on a Modded Progression Workshop publication.',
    'arch-umbrella','fix-shipped-unverified (blocked: MP publication for a 4-mod card)','R',
    'Run /dcp_ /woc_ /et_ /mp_regression_test, parse [regression] PASS/FAIL lines: zero FAIL. Static part: each mod registers a command and checks (12/20/54/26 today).',
    'KEEP-VERIFY','1684, 501c, 511c, 512c','M',
    'Engineering done; open only so a human can type four chat commands. Every active stream now has a *_regression_test command (17 streams counted).')

row(546,'repo','owner','tooling','not-started+blocked','1-major',
    'Roll-up of repository professionalization; eight children closed, open children are #2, #428, #558.',
    'arch-umbrella','stale-superseded','S',
    'None of its own: closes when #2, #428 and #558 close.',
    'CLOSE-NOT-PLANNED','2, 428, 558, 504c, 540c, 541c, 542c, 543c, 544c, 545c, 676c','H',
    'Pure roll-up with no work of its own; the three open children already track everything. 1-major on a checklist issue distorts the priority view.')

row(548,GT,'owner','bug','verify-fix','3-low',
    'Godmode must block Troll bile debuffs and fly-swarm overpowered control loss.',
    'gt-godmode-noclip','fix-shipped-unverified','R',
    'Harness: godmode on, call StatusUtils.set_overpowered_network(player,true,"slow_bomb"/"fly_bomb") from a blob source; assert not overpowered; godmode off applies; /verify_godmode_flies PASS.',
    'KEEP-VERIFY','1009, 529c, 940c','H',
    'Fix present in official: _gt_godmode_fly_runtime.lua:56-59, _gt_godmode_fly_policy.lua:10-11, command at general_tweaker.lua:1103. Engine seam status_utils.lua:332.')

row(558,'repo','owner','tooling','not-started+blocked','2-moderate',
    'Stop tracking generated bundles (67 .mod_bundle files, 167 MB tree, 6 GiB pack); blocked on #1434.',
    'ship-pipeline','blocked:#1434 owner decision','S',
    'git ls-files "*.mod_bundle" returns 0 and every tools/mod-inventory.psd1 row has BundleAuthority receipt (today 67 files, 21 rows tracked).',
    'KEEP-FIX','1434, 545c, 1429c, 1430c','M',
    'Real cost (pack size, binary churn) but the six-step transition is heavy. Blocked since 2026-08-31 on one owner decision.')

row(595,'weapons_of_chaos','owner','crash','verify-fix','0-critical',
    'WOC startup crash: mod:dofile target missing from its enumerated resource package (two occurrences).',
    'package-residency','fix-shipped-unverified','S',
    'qa/check_dofile_package_coverage.ps1 exit 0 (ran today: OK); enumerate published bundle for the Murmur64 of each packaged Lua; boot-to-Keep smoke shows no "Resource not found".',
    'CLOSE-STATIC-VERIFIABLE','1497','H',
    'WOC is the only one of 21 packages that lists Lua files one by one (29 entries, 30 files); the other 20 use scripts/mods/<mod>/*. Switching WOC to the wildcard removes the bug class. #1497 (other bucket) is the same regression report.')

row(659,GTD,'owner','bug','diagnostics-armed','2-moderate',
    'Necromancer Raise Dead produces no skeleton in the Keep; four-phase trace armed, no capture.',
    'gt-keep-necro','diag-armed-no-data','R',
    'Harness: Necromancer in Keep with bots-in-keep on, trigger the raise-dead action, parse four-phase [gt:659] trace and count pet units.',
    'KEEP-FIX','940c, 399, 417','M',
    'Old pet-ban hypothesis falsified by the 0.2.252 capture; no fix exists. Keep-only convenience: low value.')

row(696,'cosmetics_tweaker (+ Loremaster Armoury)','owner','bug','verify-fix','3-low',
    'Loremaster Armoury units log material-lookup warnings at spawn; pre-spawn parent-package lease shipped.',
    'package-residency','fix-shipped-unverified','R',
    'Harness with Loremaster Armoury installed: visit keep, preview, mission; grep log for warning hashes 5a0213f3, 6e98026a, c61ad6e5 equal zero; issue696_la_prespawn_parent_lease PASS.',
    'KEEP-VERIFY','481, 660, 742c, 199c','M',
    'Fix present: _cos_la_prespawn_lease.lua, check at _cos_runtime_checks.lua:711. Warning-only, third-party mod: lowest priority; mis-bucketed (no Cosmetics label).')

row(724,'repo (ship tooling)','owner','tooling','not-started+blocked','1-major',
    'Permanent version-allocation ledger implemented; activated for 8 of 21 streams.',
    'ship-pipeline','blocked:per-stream reviewed activation (8 of 21)','S',
    'tools/ship/claim-allocation-policy.psd1 EnabledMods equals the 21 inventory rows and qa/check_permanent_claim_allocation.ps1 passes.',
    'KEEP-FIX','432c, 942, 1684, 1692, 169','M',
    'Each activation needs owner approval, a manual initialization and a policy PR. Finish the 13 remaining streams in one transaction or replace claims with merge-time version assignment.')

row(727,'chaos_wastes_tweaker + general_tweaker + verminious_dreams_lighting (stable)','owner','tooling','not-started+blocked','3-low',
    'Logging advisory sweep: four findings left, all in stable trees (one echo, three warn-chat).',
    'stable-promotion-debt','blocked:stable-promotion','S',
    'qa/check_logging.ps1 exit 0 with ADVISORY findings 0. Ran today: exit 1, findings=4 (echo=1, per-frame=0, warn-chat=3).',
    'MERGE-INTO:427','427, 169, 240c','H',
    'Echo site: chaos_wastes_tweaker.lua:6940; the three warn-chat rows are exactly #427.')

row(753,GTD,'owner','enhancement','diagnostics-armed','2-moderate',
    'Read-only probes classify Steam, PlayFab and P2P disconnect causes; armed, waiting for a real outage.',
    'gt-lobby-session','diag-armed-no-data','U',
    'test_gt_disconnect_failure_diag.lua green; drive the three wrapped seams with fake failing state and assert exactly one [gt:753] observed= row each.',
    'CLOSE-STATIC-VERIFIABLE','309, 608c, 731c','M',
    'The deliverable is the probe, and it is deployed and armed. An issue cannot stay open until Steam next goes down.')

row(774,'character_weapon_variants + gui_tweaker_dev','owner','bug','verify-fix','2-moderate',
    'Combat Style change in a mission was rejected during an active weapon action; interruption fix shipped.',
    'cwv-combat-style','fix-shipped-unverified','R',
    'Harness: in mission start a weapon action, call the style transaction; assert stop_action once, style saved, weapon rebuilt once; career action rejected; issue774_* PASS.',
    'KEEP-VERIFY','645, 661, 620c, 944c','H',
    'Fix present: _cwv_combat_styles.lua:994-1002; named check at _cwv_regression_combat_style.lua:10. Mis-bucketed: CWV issue without a CWV label.')

row(797,GT,'owner','feature','verify-fix','2-moderate',
    'Read-only live player stat HUD with compact/expanded pages, scale and position options.',
    'gt-client-visual','fix-shipped-unverified','V',
    'Automatable: HUD on, change weapon and buffs, compare HUD model rows with BuffExtension values, /gt_stat_hud_metrics bounded, HUD off clears widgets. Legibility and layout need eyes.',
    'KEEP-VERIFY','499, 940c','M',
    'Present in official: _gt_diag_player_stats.lua:437,445; issue797_player_stat_hud registered.')

row(1008,GT,'owner','bug','verify-fix','2-moderate',
    'Godmode 9999 damage per strike must also override armour-zeroed hits.',
    'gt-godmode-noclip','fix-shipped-unverified','R',
    'Harness: spawn Chaos Warrior, deal a body hit with godmode and damage child on: health removed 9999 and unit dead; both off: zero damage.',
    'KEEP-VERIFY','549c','H',
    'Fix present in official: general_tweaker.lua:935 (DamageUtils.calculate_damage hook; engine damage_utils.lua:449). Named check is a policy truth table (_gt_regression_checks.lua:1094-1134).')

row(1009,GT,'owner','bug','verify-fix','2-moderate',
    'Godmode must block Blightstorm capture while keeping the outer pull.',
    'gt-godmode-noclip','fix-shipped-unverified','R',
    'Harness: spawn a Blightstorm vortex, call StatusUtils.set_in_vortex_network(player,true,vortex): returns false and status unchanged with godmode; captured with godmode off.',
    'KEEP-VERIFY','548','H',
    'Fix present in official: general_tweaker.lua:810 (engine status_utils.lua:278). Named check is a policy truth table (_gt_regression_checks.lua:1055-1073).')

row(1025,'repo docs','owner','tooling','not-started+blocked','1-major',
    'Single-source publication docs and headless-only verification; one stale launcher block remains in stable Lighting docs.',
    'stable-promotion-debt','blocked:markdown in a stable mod dir treated as a stable promotion','S',
    'qa/check_publication_doctrine.ps1 exit 0 with zero frozen legacy rows. Ran today: exit 0, "1 exact legacy launcher-path row(s) remain frozen".',
    'CLOSE-STATIC-VERIFIABLE','724, 540c','M',
    'Remaining row: verminious_dreams_lighting/DEVELOPMENT.md:187-212. A 25-line markdown edit is blocked because receipts hash non-shipped markdown. Close now or after a docs-only PR.')

row(1034,GT,'owner','feature','verify-fix','1-major',
    'Host-side melee latency compensation for remote clients; default on in official 0.2.180.',
    'gt-coop-client','fix-shipped-unverified','C',
    'Automatable: queue/cancel policy offline (test_gt_host_lag_comp.lua) and host harness with synthetic remote-player block/dodge status; real latency timing needs a remote client.',
    'KEEP-VERIFY','308c','H',
    'Risk: default_value = true on the public stream (general_tweaker_data.lua:740-742) while never co-op verified; hooks BTMeleeOverlapAttackAction.hit_player, AiUtils.damage_target, AiUtils.stagger (_gt_host_lag_comp.lua:333,386,435). Recommend default off until class C evidence exists.')

row(1138,GT,'owner','bug','not-started','2-moderate',
    'Mod-added special breeds were missing from the Creature Spawner Regular list.',
    'gt-spawner','fix-shipped-unverified','U',
    'gt_cs_breed_list_dynamic injects a special=true probe breed and asserts membership in regular and special lists; run it offline with a Breeds stub.',
    'CLOSE-STATIC-VERIFIABLE','454c','H',
    'Label stale: fix is in both streams (_gt_creature_spawner.lua:226 official, :253 dev; check at _gt_regression_checks.lua:924 official). Open only because the card needs an external mod (Warlock Engineer TEST) that the card validator cannot authorize.')

row(1143,GT,'owner','enhancement','verify-fix','2-moderate',
    'Developer /heal command: full permanent health and cleared wounds on host and client routes.',
    'gt-coop-client','fix-shipped-unverified','R',
    'Host route: damage and wound the local hero, run the command function, assert health equals max and wounded false. Client route needs a joined peer (C).',
    'KEEP-VERIFY','','H',
    'Present in official: _gt_dev_heal.lua:235,240. Close on host R plus offline client-route test (test_gt_dev_heal.lua); not worth a second human for a dev command.')

row(1150,GT,'owner','bug','verify-fix','2-moderate',
    'Allow Duplicate Careers must follow the host-advertised value, not the client local toggle.',
    'gt-coop-client','fix-shipped-unverified','C',
    'Automatable: policy truth table offline (test_gt_dupc_policy.lua); host run asserts advertised lobby value; client adoption after join needs a second peer; parse /dupc_state.',
    'KEEP-VERIFY','','M',
    'Present in official: _gt_duplicate_careers_parity.lua:221,236; no engine hooks in that module (:43).')

row(1328,'repo (ship tooling)','owner','tooling','not-started+blocked','0-critical',
    'ship.ps1 announced readiness before final cleanup; ordering fixed; historical drain timeout cause unknown.',
    'ship-pipeline','fix-shipped-unverified (waiting for a natural recurrence)','S',
    'ship.ps1 self-test ordering assertion (tools/ship/ship.ps1:1589-1590: success banner after transaction-lease exit) green in CI.',
    'CLOSE-STATIC-VERIFIABLE','1180c, 1548c, 1777c','H',
    'Success summary now after all cleanup (tools/ship/ship.ps1:3083-3098). "Blocked on contemporaneous evidence" can never be satisfied on purpose: close and reopen on recurrence. 0-critical is inflated.')

row(1338,GTD+' + tools/agent-bridge','owner','feature','diagnostics-armed','2-moderate',
    'Agent bridge: outbound log telemetry shipped; inbound REPL phases 2-4 not built; clipboard probe never run.',
    'agent-bridge','diag-armed-no-data','R',
    'Bridge self-test: watcher receives [agent:*] BEGIN/END frames after arming; phase 2: a token sent through the inbound channel is echoed in the log within N seconds.',
    'KEEP-FIX','511c, 517c','H',
    'Highest-leverage item in the tracker: every R check in this ledger needs this driver or an equivalent. _gt_agent_bridge.lua is 273 lines, commands at :198-240; watcher is 112 lines; untouched since 2026-08-20. Still needs a human to type chat commands. Priority should be raised.')

row(1434,'repo (release tooling)','owner','tooling','not-started+blocked','2-moderate',
    'Immutable source-exact recovery archive; GitHub immutable releases are disabled; needs an owner choice.',
    'ship-pipeline','needs-design-decision','S',
    'gh api repos/Ensrick/vermintide-2-tweaker/immutable-releases returns enabled=true (today: enabled=false, enforced_by_owner=false), then the fixture suite.',
    'OWNER-DECISION','558, 1527, 1430c','H',
    'One decision (enable immutable releases here, create a recovery repo, or accept a weaker fallback) unblocks #558 and #1527. Waiting since 2026-08-27.')

row(1527,'repo (GitHub lifecycle tooling)','owner','tooling','not-started+blocked','2-moderate',
    'Auto-reopen public-release issues closed without official-stream evidence; observe-only planner merged.',
    'ship-pipeline','blocked:#1434','S',
    'Fixture suites qa/check_public_release_closure_{policy,collector,evidence,transport}.ps1 green (1,361 lines with tools/github collector).',
    'CLOSE-NOT-PLANNED','1434, 1465, 1509c','M',
    'Guards one manual mistake (#1509) in a single-maintainer repo. A close checklist line does the same job; the mutation half cannot ship without #1434 anyway.')

row(1667,'repo (ship tooling)','owner','tooling','not-started+blocked','2-moderate',
    'Re-shipping an already uploaded friends-only item failed NOCHANGE proof; log-chain proof merged.',
    'ship-pipeline','fix-shipped-unverified (waiting for a natural NOCHANGE retry)','S',
    'qa/check_workshop_nochange_result.ps1 green and offline replay of the real workshop_log reproduces manifest 7244323320533321348 (reported in thread).',
    'CLOSE-STATIC-VERIFIABLE','1307c, 1651c, 1652c','H',
    'tools/ship/workshop-nochange-log-proof.ps1 exists. Acceptance waits for an event that policy forbids manufacturing; close and reopen if the message recurs.')

row(1801,GT,'owner','feature','diagnostics-armed','2-moderate',
    'Official Freeze World toggle: non-player world stops while the player can walk and look.',
    'gt-time','fix-shipped-unverified','R',
    'Harness: toggle freeze; world paused flag true and AI unit positions constant for 2 s; scripted move input changes player position; resume restores; issue1801_world_freeze_owner PASS.',
    'KEEP-VERIFY','1802, 303c, 13c','M',
    'Label wrong: this is a shipped feature candidate with a full card, not a diagnostic. Present in official: _gt_selective_freeze.lua (299 lines), EntitySystem.system_update hook at _gt_time_hooks.lua:29.')

row(1802,GT,'owner','enhancement','verify-fix','2-moderate',
    'Readable host-only time-scale presets with a restore-normal key.',
    'gt-time','fix-shipped-unverified','R',
    'Harness: apply each preset, read Managers.state.debug.time_scale_index against the native table; non-host write refused; disable mod returns index to 100 percent.',
    'KEEP-VERIFY','1801, 13c','M',
    'Present in official: _gt_time_owner.lua, _gt_time_control.lua; engine debug_manager.lua:20,86. Client-rejection half is class C.')

# ---- validation + write
nums = [r[0] for r in R]
assert len(R) == 54, len(R)
assert len(set(nums)) == 54
bucket = [int(l.split('\t')[0]) for l in open(os.path.join(BASE, 'data', 'bucket_F_general_other.tsv'), encoding='utf-8').read().splitlines()[1:]]
assert sorted(nums) == sorted(bucket), (set(bucket) - set(nums), set(nums) - set(bucket))
warn = []
for r in R:
    for c in r:
        assert '\t' not in str(c) and '\n' not in str(c)
    if len(r[6].split()) > 20: warn.append((r[0], 'summary', len(r[6].split())))
    if len(r[10].split()) > 30: warn.append((r[0], 'auto_check', len(r[10].split())))
    assert r[9] in ('U', 'S', 'R', 'V', 'C', 'X'), r
R.sort(key=lambda r: r[0])
out = os.path.join(BASE, 'findings', 'D5_ledger.tsv')
with open(out, 'w', encoding='utf-8', newline='') as f:
    f.write('\t'.join(HDR) + '\n')
    for r in R:
        f.write('\t'.join(str(c) for c in r) + '\n')
print('rows', len(R), 'warnings', warn)
C = collections.Counter
def show(name, idx, f=lambda x: x):
    print(name, dict(sorted(C(f(r[idx]) for r in R).items(), key=lambda kv: -kv[1])))
show('type', 3); show('lifecycle', 4); show('class', 9); show('author', 2)
show('disposition', 11, lambda d: d.split(':')[0])
show('priority', 5)
show('fix_state', 8, lambda d: d.split(':')[0].split(' (')[0])
show('cluster', 7)
for cls in 'USRVCX':
    print(cls, [r[0] for r in R if r[9] == cls])
for d in sorted(set(r[11].split(':')[0] for r in R)):
    print(d, [r[0] for r in R if r[11].split(':')[0] == d])
for lc in sorted(set(r[4] for r in R)):
    print(lc, [(r[0], r[9]) for r in R if r[4] == lc])
