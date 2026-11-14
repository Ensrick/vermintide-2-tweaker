# D3: build findings/D3_ledger.tsv from the triage table below and print bucket statistics.
# Writes only inside the audit workspace.
import csv, os, re, collections

BASE = r"<audit-workspace>"
COLS = ["number", "mod", "author_class", "type", "lifecycle", "priority", "summary", "cluster", "fix_state",
        "verification_class", "auto_check", "disposition", "related", "confidence", "note"]
R = []


def row(*a):
    assert len(a) == len(COLS), (a[0], len(a))
    R.append(dict(zip(COLS, a)))


row(52, "ct_dev", "owner", "bug", "diagnostics-armed", "0-critical",
    "Tower of Treachery injected into CW: skull interactables reportedly absent; skulls only feed an achievement.",
    "cw-injected-map-objects", "diag-armed-no-data", "R",
    "Load dlc_wizards_tower natively and through the loader; count skull flow units and [ct:skull52] selection/spawn rows in both runs; assert identical sets.",
    "KEEP-VERIFY", "156c 294c 533c 1124 251 456", "M",
    "R2. Priority mislabelled: flow_callbacks.lua:5628-5629 only triggers an achievement; body retracts 'mission impossible'. Probe exists in dev tree only. Close if the two-run census matches.")
row(60, "ct", "owner", "bug", "verify-fix", "2-moderate",
    "Khazukan Be'lakor map exceeded Chest of Trials cap (5 vs 3); reconciler prunes excess pickup-origin waiting chests.",
    "cw-chest-cap", "fix-shipped-unverified", "R",
    "Load dlc_dwarf_beacons_belakor_path1 with cap 3 and Belakor totems; after 8 s count live cursed-chest extensions <= 3 and shadow locus == 1.",
    "KEEP-VERIFY", "132c 349 58c", "H",
    "R2. Present in both trees; check names differ (dev cursed_chest_reconcile_132, official ct_chest_count_live_60). Baked chests are never pruned by design.")
row(61, "et", "owner", "enhancement", "verify-fix", "2-moderate",
    "Client-selected personal combat handicap applied host-side per authenticated peer; host allow-gate added later.",
    "et-personal-handicap", "fix-shipped-unverified", "C",
    "Solo host covers: enable allow-gate and own preset, script hits on a spawned enemy, assert incoming/outgoing factors. Client preset transport and isolation need two clients.",
    "KEEP-VERIFY", "272 640c 55c", "M",
    "Owner asked 08-04 what the feature is; host gate shipped 0.7.56 (enemy_tweaker_data.lua:510-524). Owner acceptance of the design is not recorded. Policy is unit-tested.")
row(102, "ct", "owner", "bug", "verify-fix", "1-major",
    "Reused temper altar escalated weapon rarity rare to exotic to unique; fix decouples keep-lit visual from reward rarity.",
    "cw-altar-reuse", "fix-shipped-unverified", "R",
    "Spawn an upgrade altar with 2+ uses; script two open_chest calls; assert chest _rarity unchanged and awarded weapon rarity equals the rolled rarity both times.",
    "KEEP-VERIFY", "100c 103c 252", "H",
    "R3. _ct_altar_reuse_owner.lua:578-669; no self._rarity write remains. Existing runtime check only compares a marker string.")
row(107, "ct", "owner", "bug", "verify-fix", "2-moderate",
    "Host-banned Grudge Marks still appeared on Be'lakor Shadow Lieutenant; filter now limited to the 13 authored marks.",
    "grudge-enhancements", "fix-shipped-unverified", "R",
    "Unit: installed hook with base, banned and allowed enhancements removes only the banned. Runtime: spawn Shadow Lieutenant with ban-all; read applied enhancement names.",
    "KEEP-VERIFY", "323 221c 453", "H",
    "R3. _ct_boss_grudge_marks.lua:12-16,56-67,123-160. Body still says not-started; label and 11-06 card say verify-fix.")
row(141, "ct_dev", "owner", "feature", "diagnostics-armed", "2-moderate",
    "Save and resume a Chaos Wastes expedition at the map vote; only a read-only readiness audit exists.",
    "cw-run-state", "diag-armed-no-data", "R",
    "Scripted run: call /ct_resume_audit at two map screens; assert config=7/7 progress=4/4 rows. After build: save, restart, resume, compare run-state hash.",
    "OWNER-DECISION", "-", "M",
    "R4. Feature not implemented (peer remap, state restore are large). Decide build or decline; the audit row alone can be captured automatically.")
row(144, "ct", "owner", "bug", "verify-fix", "2-moderate",
    "Vaul's Anvil auto-block stopped after weapon swaps or pickups; reconciler re-adds the perk when melee is wielded.",
    "cw-boon-repairs", "fix-shipped-unverified", "R",
    "Grant Vaul's Anvil; script wield ranged/melee and pickup cycles; assert always-blocking buff present and override_blocking true on melee, false during lockout.",
    "KEEP-VERIFY", "-", "H",
    "R3. _ct_meta_trait_boons.lua:115-150. Reopened once. Runtime check only asserts the callable is registered.")
row(146, "ct", "owner", "feature", "verify-fix", "2-moderate",
    "Separate Citadel approach and finale god selection through a post-generation graph pass.",
    "cw-graph-loader", "fix-shipped-unverified", "R",
    "Generate graph with finale Khorne and approach Nurgle; read sig_citadel and arena_citadel node level/god/theme/curse; load both levels without error.",
    "KEEP-VERIFY", "145c", "H",
    "R2. _ct_campaign_graph_owner.lua:199-205,410,455. Graph rewrite is unit-testable; rendered theme is a minor V residue.")
row(243, "ct", "owner", "bug", "verify-fix", "1-major",
    "Belakor curse lighting near-black on dark injected interiors; profile retuned and brightness slider added.",
    "cw-curse-lighting", "fix-shipped-unverified", "V",
    "Automatable part: load dlc_termite_2 with Belakor theme, read applied shading values equal profile x knob, compare screenshot mean luminance against uncursed control.",
    "KEEP-VERIFY", "66c 104c 258 271", "M",
    "_ct_curse_lighting_owner.lua:138-146. Readability judgement stays human. One loader session covers #243, #258 and #271; vdl must be off.")
row(249, "ct+gut", "owner", "bug", "verify-fix", "2-moderate",
    "Teammate ammo HUD wrong with Quiver Cascade; HUD half passed in logs, client never received ammo boon stacks.",
    "cw-boon-ammo", "fix-shipped-unverified", "C",
    "Solo covers /verify_boon_ammo_hud exact==wire and unit restore_plan. Client stack count after host grant and hot join needs two clients.",
    "KEEP-VERIFY", "34c 131c 256 185c", "M",
    "08-04 logs: host quiver_stacks=20, client 0. Rebroadcast repair (issue249_stack_rebroadcast_on_restore) shipped after; no co-op rerun.")
row(251, "ct_dev", "owner", "bug", "diagnostics-armed", "2-moderate",
    "Injected Blood in the Darkness: first tome location has no Chest of Trials; cause unknown.",
    "cw-injected-map-objects", "diag-armed-no-data", "R",
    "Load injected Blood in the Darkness with cap 3; dump book-spawner census; assert a cursed-chest unit within 2 m of the first tome spawner.",
    "KEEP-FIX", "60 156c 456", "M",
    "R2. Shipped difficulty-key change cannot reach the guaranteed-spawn path (owner audit 08-03). Needs census then a fix.")
row(252, "ct", "owner", "bug", "verify-fix", "3-low",
    "Same-tier altar reroll showed red rejection text; prompt now reads 'Reroll this weapon?'.",
    "cw-altar-reuse", "fix-shipped-unverified", "R",
    "Target a re-armed same-tier altar; read interaction widget: reward_info_text equals the prompt, disabled_text empty; measured text width within widget width.",
    "KEEP-VERIFY", "102 103c", "H",
    "R3. _ct_altar_reuse_owner.lua:686-687. Clipping is measurable from text size; shares the #102 scenario.")
row(253, "ct_dev", "owner", "feature", "diagnostics-armed", "3-low",
    "Weave winds as CW curses; only a command-gated Metal wind adapter exists, seven winds unbuilt.",
    "cw-curse-modifiers", "fix-shipped-unverified", "R",
    "Enable /ct_weave_metal; spawn Stormvermin; apply a fixed hit; assert armour result equals the Chaos Warrior case; off restores vanilla.",
    "OWNER-DECISION", "455c", "M",
    "R3. Label says diagnostics-armed but the card tests shipped behaviour. Decide: finish Metal only and close, or keep an umbrella for seven more winds.")
row(256, "ct", "owner", "bug", "verify-fix", "1-major",
    "Ammo-per-boon refresh could drive reserve ammo negative; current and reserve ammo now clamped.",
    "cw-boon-ammo", "fix-shipped-unverified", "R",
    "Give a ranged weapon partial spawn ammo, refill clip, grant a meta-ammo stack; assert reserve >= 0 and 0 <= clip <= max after refresh.",
    "KEEP-VERIFY", "34c 249", "H",
    "R3. _ct_meta_boon_owner.lua:319-345; vanilla cause verified at generic_ammo_user_extension.lua:100-112. Official check returns SKIP without a live extension.")
row(258, "ct", "owner", "bug", "verify-fix", "1-major",
    "Well of Dreams too dark under Tzeentch curse; per-map top-ambient multiplier 2.0.",
    "cw-curse-lighting", "fix-shipped-unverified", "V",
    "Automatable part: on dlc_termite_3 with Tzeentch assert ambient_tint_top multiplier 2.0 applied, other maps 1.0; luminance delta versus control screenshot.",
    "KEEP-VERIFY", "66c 68c 104c 243 271", "M",
    "_ct_curse_lighting_owner.lua:171-175. Same harness as #243.")
row(259, "ct", "owner", "bug", "verify-fix", "2-moderate",
    "Ranger's Parting Gift perk saved Morgrim's Bomb despite the block toggle; has_buff_perk shim added.",
    "cw-boon-repairs", "fix-shipped-unverified", "U",
    "Unit on installed hook: fake buff extension with free_grenade perk and holy_hand_grenade gives free_grenade false; with rewield perk true; overrides restored after error.",
    "KEEP-VERIFY", "101c", "H",
    "_ct_combat_hooks.lua:1481-1540; engine seam action_charged_projectile.lua:83-87. Runtime row [ct:morgrim259] gives cheap R confirmation.")
row(271, "ct", "owner", "bug", "verify-fix", "1-major",
    "Devious Delvings curse lighting too dark; four interior channels doubled for every curse.",
    "cw-curse-lighting", "fix-shipped-unverified", "V",
    "Automatable part: on dlc_termite_2 assert the four interior multipliers 2.0 and exterior unchanged; luminance delta versus control screenshot.",
    "KEEP-VERIFY", "66c 104c 243 258", "M",
    "_ct_curse_lighting_owner.lua:176-183. Same harness as #243.")
row(288, "ct", "owner", "bug", "verify-fix", "2-moderate",
    "Anath Raema rework kept the vanilla 10 s ammo-pickup trigger; permanent reload-speed child now enforced.",
    "cw-boon-repairs", "fix-shipped-unverified", "R",
    "Wield trait weapon with rework on; assert exactly one active reload_speed -0.5 buff with no duration; toggle off restores the vanilla template.",
    "KEEP-VERIFY", "464c", "H",
    "R3. _ct_boon_balance.lua:828-856. Reload timing can be measured by script instead of a stopwatch.")
row(289, "ct", "owner", "enhancement", "verify-fix", "3-low",
    "Progressive modifier stacking: from map 3 add one extra Slaanesh mutator on cursed missions.",
    "cw-progressive-scaling", "fix-shipped-unverified", "R",
    "Scripted run to map 3 with stacking on; read active mutators: node curse plus exactly one of empathy/abundance; maps 1-2 none; shrine none.",
    "KEEP-VERIFY", "104c 323 460", "M",
    "R4. _ct_modifier_stack_policy.lua:18. Client activation parity is a C residue. Body still says not-started.")
row(299, "ct", "owner", "bug", "verify-fix", "1-major",
    "Chest of Trials revive freed the player at a distant rescue point; move-before-free transaction with position readback.",
    "cw-bots", "fix-shipped-unverified", "R",
    "Kill a bot far from the team by script; complete a chest; assert bot within 3 m of a teammate before respawn release and [ct:299] row PASS.",
    "KEEP-VERIFY", "116c 149 337c", "M",
    "R3. _ct_chest_revive_owner.lua:398-402. Original report was a human player; the remote-human path is a C residue. Raw Vector3 write to POSITION_LOOKUP remains at :384-385.")
row(322, "ct", "owner", "bug", "verify-fix", "2-moderate",
    "_spawn_pickup hook dropped the second return value, breaking linked-pickup client RPC; now returns both.",
    "cw-hook-arity", "fix-shipped-unverified", "S",
    "Static: assert the PickupSystem._spawn_pickup wrapper captures and returns two values; unit test_ct_spawn_pickup_two_return passes; optional solo [ct:322] row shows non-nil go_id.",
    "CLOSE-STATIC-VERIFIABLE", "294c 144", "H",
    "_ct_pickup_spawn_owner.lua:298,328; engine pickup_system.lua:1208,1283. Owner saw it work in co-op 07-20. A hook return-arity lint would cover the whole class.")
row(323, "ct+et", "owner", "feature", "verify-fix", "3-low",
    "Progressive elite enhancements by map depth using two proven recipes; Enemy Tweaker half unbuilt.",
    "grudge-enhancements", "fix-shipped-unverified", "R",
    "Scripted run at map 2+ with chance forced to 100; spawn an elite; assert recipe applied; specials and trash none; ban-all on still applies.",
    "KEEP-VERIFY", "107 453", "M",
    "R3/R4. CT slice shipped 0.7.350. Move the unbuilt Enemy Tweaker half to #453 and drop the Enemies label.")
row(324, "et", "owner", "enhancement", "diagnostics-armed", "2-moderate",
    "Custom Skaven Warlord had no combat AI; on current build it does not register at all.",
    "et-custom-breed", "diag-armed-no-data", "R",
    "Keep: capture [et:324] cap-probe rows at load and after network init. After fix: spawn et_skaven_warlord; assert target acquired and tree past spawn node within 15 s.",
    "KEEP-FIX", "371 454c 1138 451 1413c", "H",
    "R1 then R3. enemy_tweaker/CHANGELOG.md:3-12: registrar refused both custom breeds in 12 of 12 logs. Type should be bug; blocks #451.")
row(342, "ct", "owner", "bug", "verify-fix", "2-moderate",
    "Parry cooldown strip was a no-op on the wrong table; registered cooldown template durations are now zeroed.",
    "cw-boon-repairs", "fix-shipped-unverified", "R",
    "After one boon roll read boon_skulls_03_cooldown and every static_blade cooldown template: all durations 0; then two scripted timed blocks both proc.",
    "KEEP-VERIFY", "128c", "H",
    "R3. _ct_parry_cooldown_policy.lua; _ct_combat_hooks.lua:1138-1161; _ct_run_creation_owner.lua:652-659. Applies with no toggle.")
row(349, "ct_dev", "rain", "bug", "diagnostics-armed", "2-moderate",
    "Mission of Mercy may exceed the Chest of Trials cap; census armed but never run on that map.",
    "cw-chest-cap", "diag-armed-no-data", "R",
    "/ct_load_mission dlc_dwarf_interior with cap 2; wait 8 s; read [ct:349] class and live chest count; over_cap_raw_level_units means a fix is needed.",
    "KEEP-VERIFY", "60 132c 262c", "H",
    "R2. Fully scriptable; same harness as #60. Close if within cap, otherwise convert to a fix task.")
row(357, "ct", "owner", "enhancement", "verify-fix", "3-low",
    "Owner-local buff-bar countdown for the bomb-bubble boon cooldown.",
    "cw-cooldown-display", "fix-shipped-unverified", "R",
    "Grant a bomb boon with cooldown 10; trigger a proc; assert display buff with duration 10 and expected icon id; gated throw does not restart; 0 shows none.",
    "KEEP-VERIFY", "120c 143c 358 919", "M",
    "R3. Icon appearance is a V residue; owner-only delivery to a remote peer is a C residue.")
row(358, "ct", "owner", "enhancement", "verify-fix", "3-low",
    "Manann's Tempest two-state ready/cooldown icon; re-wield now keeps the original deadline.",
    "cw-cooldown-display", "fix-shipped-unverified", "R",
    "Own the trait; assert ready buff; trigger proc gives 8 s cooldown buff; unwield and re-wield at 2 s leaves about 5 s; expiry returns ready.",
    "KEEP-VERIFY", "133c 357", "M",
    "R3. _ct_bomb_cooldown_display.lua:71-75,144-178 (0.7.349). Body still describes the pre-fix state.")
row(361, "ct", "owner", "feature", "verify-fix", "3-low",
    "Rotten Miasma options: permanent torch carrier, safe radius, stack interval; dead-carrier selection corrected.",
    "cw-curse-modifiers", "fix-shipped-unverified", "R",
    "Load a mission with Rotten Miasma; set radius 12 and interval 0.5; assert one safe-area unit, its radius, tick field; move and kill carrier, owner follows policy.",
    "KEEP-VERIFY", "919 920c", "M",
    "R3. _ct_miasma.lua:100; _ct_miasma_policy.lua:30-39. Client presentation of the sphere is a C/V residue.")
row(369, "et", "owner", "feature", "verify-fix", "2-moderate",
    "Per-difficulty enemy health multipliers 0.1-5.0 applied at health init with live rescale.",
    "et-enemy-stats", "fix-shipped-unverified", "R",
    "Set active-tier multiplier 2.0; spawn a clanrat; assert max health equals 2x base; damage 50 percent, change slider, percent preserved; inactive tier no change.",
    "KEEP-VERIFY", "-", "H",
    "R3. _et_health_multiplier.lua:30,72. Menu placement is checkable from the widget tree. Client health agreement is a C residue using vanilla RPCs.")
row(393, "evt", "owner", "bug", "diagnostics-armed", "1-major",
    "Injected high_intensity mutator has little observable effect; settled-verdict probe armed.",
    "evt-mutator-injection", "diag-armed-no-data", "R",
    "Start an Adventure mission with High Intensity injected; read the [event-inject:393] verdict and live pacing fields against mutator_high_intensity values.",
    "KEEP-VERIFY", "275c 386c 626c", "H",
    "R2. One run decides: intact means subtle by design and close; settings_stomp means fix hook order against enemy_tweaker.")
row(413, "evt", "owner", "crash", "verify-fix", "0-critical",
    "Shadow mutator crashed Adventure clients on a non-resident light unit; replaced by an Adventure adapter.",
    "evt-shadow-adapter", "fix-shipped-unverified", "C",
    "Solo host covers: enable Shadow, assert no gargoyle-head spawn, far enemy carries -0.8 buff, near enemy none, template restored. Client crash path needs a real client.",
    "KEEP-VERIFY", "1123 386c 455c 430 294c", "M",
    "_evt_shadow_adventure.lua:61-101,455-473; engine mutator_shadow.lua:153-160. plan() peer-capability drop is unit-tested.")
row(426, "ct", "owner", "crash", "verify-fix", "0-critical",
    "CT custom boon and miracle buffs crashed peers without CT; fail-closed parity gates shipped to the public stream.",
    "ct-wire-parity", "fix-shipped-unverified", "C",
    "Solo covers /ct_426_diag exact catalog and both public checks; unit simulates an un-acked peer refusing every writer. A non-CT joiner needs two clients.",
    "KEEP-VERIFY", "371 406c 425c 1191 458 494c", "M",
    "public-release label. Closed #406 was shut without its co-op check; treat as part of this verification.")
row(430, "evt", "owner", "crash", "verify-fix", "0-critical",
    "Cursed Adventure curses crash peers lacking Event Tweaker; parity floor and hot-join session lock added.",
    "evt-curse-parity", "fix-shipped-unverified", "C",
    "Solo covers: loop each curse in an Adventure mission, assert mutator active, issue430 checks pass, no resource error. Non-ET joiner containment needs two clients.",
    "KEEP-VERIFY", "371 413 386c 455c 532c 660", "M",
    "07-22 audit: per-curse behaviour in Adventure never verified. The per-curse loop is solo R work and should run first.")
row(450, "et", "owner", "enhancement", "verify-fix", "1-major",
    "Six boss balance tweaks; Rain found adds firing on death and tracking unchanged; reworked in 0.7.54.",
    "et-boss", "fix-shipped-unverified", "R",
    "/verify_boss_balance per toggle; script Halescourge to 49 percent on Cataclysm: exactly one troll or spawn queued, none on death; Skarrik ranged hit x0.70.",
    "KEEP-VERIFY", "531c 451", "M",
    "R3. _et_boss_behavior_core.lua:17-33. Card covers 3 of the requested controls; Berserk/Crippling from closed #531 and all health changes need numeric readback too.")
row(451, "et", "owner", "feature", "verify-fix", "2-moderate",
    "Six new boss concepts; only a greataxe Chosen prototype exists and it currently fails to register.",
    "et-custom-breed", "blocked:custom-breed registration refused at mod load (#324)", "R",
    "After #324: /et_spawn_chosen in War Camp; assert breed et_chosen_greataxe, boss flag, health band, target acquired; kill clears boss bar; issue451 checks pass.",
    "KEEP-FIX", "324 371 452 1497 1413c 428", "H",
    "R3. Card cannot pass: enemy_tweaker/CHANGELOG.md:3-12 records the Chosen refused in 12 of 12 logs. Narrow to the Chosen; decide the five unbuilt concepts.")
row(452, "et", "owner", "feature", "not-started", "2-moderate",
    "Five new Skaven specials using Versus premium skins; player attachment meshes do not fit AI skeletons.",
    "et-custom-breed", "blocked:AI-compatible models or owner accepting plain appearance", "X",
    "None until assets or a decision exist; then spawn the clone breed and assert registration plus a 5 percent replacement rate over N scripted spawns.",
    "OWNER-DECISION", "451 324", "H",
    "Also depends on #324. Recommend close as not planned unless the owner accepts gameplay-only variants.")
row(453, "et", "owner", "feature", "diagnostics-armed", "2-moderate",
    "Per-category rates and toggles for grudge marks and event modifiers on enemies; only a read-only audit exists.",
    "grudge-enhancements", "diag-armed-no-data", "R",
    "Script one spawn per category including a lord; run /et_modifier_audit; assert rows for all four categories and the gap list; then build per category.",
    "KEEP-FIX", "531c 323 107", "M",
    "R3. Special and elite rows captured, boss and lord rows missing. Absorb the Enemy Tweaker half of #323.")
row(456, "ct_dev", "owner", "bug", "diagnostics-armed", "1-major",
    "Injected Into the Nest: first grimoire location always empty; no capture exists on the correct map.",
    "cw-injected-map-objects", "diag-armed-no-data", "R",
    "Load skaven_stronghold natively and injected; census book spawners; assert a grimoire unit at the first grimoire spawner position in both runs.",
    "KEEP-FIX", "156c 251", "H",
    "R2. Earlier 'verified' evidence was captured on Skittergate (owner audit 08-02). Pure state census.")
row(458, "ct", "owner", "enhancement", "verify-fix", "0-critical",
    "Configurable starting-boon shrine: offers, miracles, price percent, purchase limit.",
    "cw-start-shrine-pricing", "fix-shipped-unverified", "R",
    "Start a run with the shrine on; assert shop opens with N offers and M pooled miracles, price equals percent x base, buy debits price, limit blocks a second buy.",
    "KEEP-VERIFY", "1146 467 426 919 912 828c 115c", "M",
    "R2. _ct_start_shrine_runtime.lua:34-38,153-162. 0-critical on an enhancement. Layout with offers other than 4 is a V residue; client reader fix is a C residue.")
row(460, "ct", "rain", "enhancement", "verify-fix", "2-moderate",
    "Progressive difficulty: one tier up after two maps, two after four; coin multiplier reduced from map 3.",
    "cw-progressive-scaling", "fix-shipped-unverified", "R",
    "Scripted pilgrimage completing maps; read run difficulty and coin credit at 0, 2 and 4 completed maps; new run resets; toggles off keep baseline.",
    "KEEP-VERIFY", "291c 487c 289 323 470", "H",
    "R4. _ct_progressive_difficulty.lua:10-13,52-54; policy unit-testable. Hot-join tier agreement is a C residue.")
row(465, "ct_dev", "owner", "enhancement", "not-started", "2-moderate",
    "Preserve boons, coins and weapons when a human and a bot swap; intrinsic preservation shipped in 0.7.353-dev.",
    "cw-bots", "fix-shipped-unverified", "C",
    "Solo covers the 47 installed-callback unit cases and bot-side capture on add. A real second client must leave and rejoin to prove the transfer.",
    "KEEP-VERIFY", "100c 121c 321 466 1146 487c", "M",
    "Labels stale: blocked + not-started although the change was published 10-25 and its cited blocker #1146 is itself verify-fix.")
row(466, "ct_dev", "owner", "enhancement", "not-started", "2-moderate",
    "Bots should prefer boons suited to career, talents and weapons; economy half shipped, priority policy missing.",
    "cw-bots", "needs-design-decision", "U",
    "After a policy table exists: unit-test a deterministic scorer over fixtures; runtime: offer N boons to a bot and assert the pick equals the scorer.",
    "OWNER-DECISION", "100c 121c 467 465", "H",
    "Needs the owner's priority table or permission to design one. The shipped bot coin ledger could be verified and split off.")
row(467, "ct", "owner", "enhancement", "verify-fix", "2-moderate",
    "Per-boon shrine prices from an opt-in manifest, for example Barkskin 225 and 113 at a 50 percent start shrine.",
    "cw-start-shrine-pricing", "fix-shipped-unverified", "R",
    "Unit: policy price fixtures 225/150/113/100. Runtime: force a Barkskin offer; widget price 225; buy debits 225; toggle off gives 200.",
    "KEEP-VERIFY", "458 466 1146", "H",
    "R2. _ct_boon_pricing_runtime.lua:10-14,22-25.")
row(470, "ct", "owner", "crash", "verify-fix", "0-critical",
    "Cataclysm 3 with Skulking Sorcerer curse: breed max_health[8] nil crashed health init; entry backfilled to 150.",
    "cw-difficulty-rank", "fix-shipped-unverified", "R",
    "Load a mission at cataclysm_3 with curse_skulking_sorcerer; assert Breeds.curse_mutator_sorcerer.max_health[8] == 150; spawn the breed; no script error.",
    "KEEP-VERIFY", "487c 479c 59c 505 460", "H",
    "R2. _ct_node_entry_owner.lua:171-191; vanilla hole verified at mutator_curse_skulking_sorcerer.lua:9-11,19-27. A static sweep of rank-keyed mutator tables covers the class.")
row(471, "ct", "owner", "bug", "verify-fix", "1-major",
    "Chest of Trials enemy multiplier appeared ineffective; placement top-up added.",
    "cw-chest-trials-spawn", "fix-shipped-unverified", "R",
    "Trigger the same trial at multiplier 1.0 and 3.0; count AI units spawned for the trial; assert about 3x within engine caps; other spawns unchanged.",
    "KEEP-VERIFY", "64c 262c", "M",
    "R3. _ct_combat_hooks.lua:363-523; _ct_cot_placement_policy.lua. Original report had no evidence; the official readback check deliberately SKIPs.")
row(505, "ct", "owner", "feature", "verify-fix", "0-critical",
    "Single Mission Loader redesign: chamber-only menu for mission, curse and progress; progress clamped to 0.999.",
    "cw-graph-loader", "fix-shipped-unverified", "R",
    "From morris_hub invoke the loader for every catalog mission in a loop; assert level reaches in-game, progress 0.999, upgrade chest opens; outside hub refused.",
    "KEEP-VERIFY", "299 461c 564c 470", "H",
    "R2. _ct_dev_mission_catalog.lua:121; engine assert deus_weapon_generation.lua:30. The loader is the harness entry point for most CT checks: verify first.")
row(571, "ct+gut", "owner", "bug", "verify-fix", "2-moderate",
    "CW Tab pane collectible rows overflowed during banner animation at 4K or scaled UI; fixed-offset layout port.",
    "cw-hud", "fix-shipped-unverified", "R",
    "Open the player list in CW; sample child widget rects across animation frames at 3840x2160 and a scaled UI; assert inside panel rect and fit=true.",
    "KEEP-VERIFY", "114c 533c 461c 557c 704", "M",
    "R3. _ct_tab_collectibles_layout.lua. The defect was numeric overflow, so rect readback suffices; final look is a small V residue.")
row(802, "evt", "owner", "bug", "verify-fix", "2-moderate",
    "Event missions appeared in wrong menus and displaced Campaign; single Events area sorted after visible areas.",
    "evt-missions-menu", "fix-shipped-unverified", "R",
    "Open Own Game by script; read area widgets: first is Helmgart, exactly one Events area later; its missions equal the enabled allowlist; reopen three times.",
    "KEEP-VERIFY", "336c 457c 626c 649c 941", "H",
    "R1. _evt_missions.lua:446. Controller path can be driven by setting gamepad mode [unverified].")
row(912, "ct", "owner", "bug", "verify-fix", "2-moderate",
    "Starting Coins 0 inherited rollover currency and odd values were rounded; policy now exact for 0-3000.",
    "cw-run-setup-settings", "fix-shipped-unverified", "R",
    "Set starting coins 0 then 324; start a fresh run each time; read own soft currency right after setup_run equals the setting; /verify_coins PASS.",
    "KEEP-VERIFY", "164c 750c 825c 919", "H",
    "R2. _ct_starting_coins_policy.lua:8-12; engine deus_run_controller.lua:273,315.")
row(917, "ct", "rain", "feature", "verify-fix", "3-low",
    "Keep compatible Adventure weapon illusions in Chaos Wastes across starter, upgrade and same-family swap.",
    "cw-illusions", "fix-shipped-unverified", "R",
    "Equip a known skin in Adventure; start a run with the option on; assert starter item.skin equals it when matching_item_key matches; after upgrade same; off not forced.",
    "KEEP-VERIFY", "750c", "H",
    "R3. _ct_adventure_illusions.lua:70. item.skin is data, so no visual judgement is needed. Body still says not-started.")
row(919, "ct+gut", "owner", "bug", "diagnostics-armed", "0-critical",
    "Mod Tweaker profiles: CW run used profile 1 boons while profile 2 was active; partial restore.",
    "cw-run-setup-settings", "diag-armed-no-data", "U",
    "Unit: category with non-rendered owned settings; capture P1, switch P2, switch back; assert every setting round-trips. Runtime: script the card and read all keys.",
    "KEEP-FIX", "912 592 712 749 205c 561c 828c 920c", "M",
    "Static audit 08-03 named a cause; snapshot still iterates rendered nodes (gui_tweaker_dev/_mod_tweaker_view_pending.lua:77-97). No fix cited. The awaited log can be produced by script.")
row(941, "evt", "owner", "enhancement", "verify-fix", "3-low",
    "Prologue added to Event Missions as a solo-only projected row.",
    "evt-missions-menu", "fix-shipped-unverified", "R",
    "issue941 check passes; select Prologue in the Events list and launch solo: level prologue reaches in-game; two-player verdict blocked_not_solo by unit test.",
    "KEEP-VERIFY", "626c 802", "M",
    "R2. _evt_missions.lua:378-440 (0.4.48). Body still says not-started.")
row(1123, "evt", "owner", "bug", "verify-fix", "1-major",
    "Event Tweaker gave Be'lakor Shadows enemies 90 percent damage reduction in CW; private clone now used only during Adventure Shadow.",
    "evt-shadow-adapter", "fix-shipped-unverified", "R",
    "In keep and in a CW Belakor-shadows mission assert the shared template has no multiplier (issue413_shadow_adventure_adapter); a fixed hit deals vanilla damage.",
    "KEEP-VERIFY", "413", "H",
    "R1/R2. event_tweaker_shadow_policy.lua:13; _evt_shadow_adventure.lua:455-473. The existing check already reads live template state.")
row(1124, "ct_dev", "owner", "bug", "diagnostics-armed", "3-low",
    "Unknown whether the Old Haunts gargoyle-head objective works when injected into CW; observer armed.",
    "cw-injected-map-objects", "diag-armed-no-data", "R",
    "Load dlc_portals through the loader; read limited-item-track spawner activation and [ct:1124] rows; script heads to sockets; assert four spawners and objective completion.",
    "KEEP-VERIFY", "52 156c 251", "M",
    "R3. A verification task filed as a bug; nobody reported a failure. Thread says rolled back to not-started 08-31 while the label says diagnostics-armed.")
row(1146, "ct", "owner", "bug", "verify-fix", "0-critical",
    "Start shrine showed '-' for every price and nothing could be bought; false discount sentinel now treated as zero.",
    "cw-start-shrine-pricing", "fix-shipped-unverified", "R",
    "Unit test exists. Runtime: open the start shrine; every offer price_text is numeric; buy one; coin delta equals the displayed price.",
    "KEEP-VERIFY", "458 467 465", "H",
    "R2. _ct_start_shrine_policy.lua:50-51; test_ct_start_shrine_policy.lua:95; engine sentinel deus_shop_view_v2.lua:289-290.")
row(1149, "evt", "owner", "bug", "verify-fix", "2-moderate",
    "Event Tweaker modifier rows showed raw keys and lacked icons; client-sync half moved to #1309.",
    "evt-mutator-injection", "fix-shipped-unverified", "R",
    "In the keep run issue1149_modifier_loc_icon_coverage: every discovered mutator has a non-bracketed name and a resolvable icon.",
    "KEEP-VERIFY", "1309", "H",
    "R1. _evt_preview.lua:285. Vague title and body; scope narrowed in comments. Icon matching in-game art is a V residue.")
row(1191, "ct_dev", "owner", "bug", "diagnostics-armed", "2-moderate",
    "Two CT peers on different builds could ack parity with different boon catalogs; exact catalog identity added.",
    "ct-wire-parity", "fix-shipped-unverified", "U",
    "Unit: two parity instances with different catalogs produce an identity mismatch and a closed gate. Solo: /ct_426_diag shows exact catalog committed. Real pair is C.",
    "MERGE-INTO:426", "426 371 1158", "M",
    "Label and body stale: ct_dev builds wire_identity (_ct_peer_parity_owner.lua:225+, CHANGELOG 0.7.322-dev). Same owner and co-op session as #426.")
row(1309, "evt", "owner", "bug", "diagnostics-armed", "2-moderate",
    "Chaos Wastes Tzeentch Twins curse reportedly does nothing for clients; host diagnostic armed.",
    "evt-mutator-injection", "diag-armed-no-data", "C",
    "Solo covers: enable curse, script 30 kills, assert activation row with non-nil seed and splits_spawned > 0. Client-kill path needs a real client.",
    "KEEP-FIX", "1149", "M",
    "A solo run eliminates two of three hypotheses (nil seed, curse withheld); only client-kill attribution needs a second machine.")
row(1497, "et", "rain", "bug", "verify-fix", "0-critical",
    "Boot soft-lock: Enemy Tweaker hot-join fence held and kicked the local host; local-host bypass shipped.",
    "et-custom-breed", "fix-shipped-unverified", "R",
    "Boot-to-keep smoke: launch with the mod set, assert local peer in-game within 120 s, no HELD/KICKED row for the local peer, issue1497 check PASS.",
    "KEEP-VERIFY", "451 595 358 1413c", "H",
    "R1. _et_custom_breed_parity.lua:174-177,197-220,329-350,392-409; engine peer_states.lua:365-409. Rain confirmed keep entry 09-01; only the named check failed and was corrected in 0.7.62.")
row(1817, "ct", "external", "feature", "not-started", "3-low",
    "External request: ten-player lobbies, host-chosen bot count, difficulty scaling by player count.",
    "out-of-scope", "no-fix", "X",
    "None; not planned.",
    "CLOSE-OUT-OF-SCOPE", "-", "H",
    "Player cap is engine and lobby level (matchmaking_manager.lua:42, lobby_setup.lua:6), not a tweak. Decline and point at existing large-lobby mods.")


def words(s):
    return len(s.split())


bad = [(r["number"], "summary", words(r["summary"])) for r in R if words(r["summary"]) > 20]
bad += [(r["number"], "auto_check", words(r["auto_check"])) for r in R if words(r["auto_check"]) > 30]
out = os.path.join(BASE, "findings", "D3_ledger.tsv")
with open(out, "w", encoding="utf-8", newline="") as f:
    f.write("\t".join(COLS) + "\n")
    for r in R:
        vals = [str(r[c]) for c in COLS]
        for v in vals:
            assert "\t" not in v and "\n" not in v, r["number"]
        f.write("\t".join(vals) + "\n")
bucket = [int(x["number"]) for x in csv.DictReader(
    open(os.path.join(BASE, "data", "bucket_C_cw_events_enemies.tsv"), encoding="utf-8"), delimiter="\t")]
nums = [r["number"] for r in R]
print("rows", len(R), "unique", len(set(nums)), "bucket", len(bucket))
print("missing", sorted(set(bucket) - set(nums)), "extra", sorted(set(nums) - set(bucket)))
print("over-length", bad)
for col in ["type", "lifecycle", "priority", "verification_class", "disposition", "author_class", "fix_state",
            "cluster", "confidence", "mod"]:
    c = collections.Counter(r[col].split(":")[0] if col in ("fix_state", "disposition") else r[col] for r in R)
    print(col, dict(sorted(c.items(), key=lambda kv: -kv[1])))
c = collections.Counter((r["lifecycle"], r["verification_class"]) for r in R)
print("lifecycle x class", dict(sorted(c.items())))
c = collections.Counter((r["disposition"].split(":")[0], r["verification_class"]) for r in R)
print("disposition x class", dict(sorted(c.items())))
tiers = collections.Counter()
for r in R:
    if r["verification_class"] == "R":
        m = re.match(r"(R\d)", r["note"])
        tiers[m.group(1) if m else "untagged"] += 1
print("R first tier", dict(sorted(tiers.items())))
cl = collections.defaultdict(list)
for r in R:
    cl[r["cluster"]].append(r["number"])
for k, v in sorted(cl.items(), key=lambda kv: -len(kv[1])):
    print("cluster", k, v)
