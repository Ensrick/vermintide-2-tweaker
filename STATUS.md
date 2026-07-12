# STATUS — Vermintide 2 Tweaker monorepo

> **The single "what now" board.** Claude reads this at the start of every session
> (the standup) and updates it at the end. Together with GitHub Issues it is the
> ONLY status surface: `TODO.md` / `WORK_ITEMS.md` / `TESTING_STATUS.md` were
> retired to pointer stubs 2026-07-08 (issue #432; full copies in git history +
> `_archive/docs/2026-07-08_432_consolidation/`).
> **Last updated: 2026-07-12.**

## 📌 2026-07-11/12 SESSIONS — critical-issue campaign (multi-agent) + one-at-a-time continuation

**Directive:** fix ALL critical issues (multi-agent, ultracode) -> session cap hit -> wind-down to branch `handoff/fable-2026-07-11` + umbrella issue **#494** -> new-week continuation, ONE issue at a time, docs/process wrap-up prioritized.

**✅ Shipped & Workshop-verified** (all -dev; **PC-B SKIPPED - unreachable both days, needs catch-up deploy**; every ship committed + pushed):
- **et 0.4.25-dev** (#455 boss-event mutators) + **0.4.26-dev** (OOP split: 11 `_evt_` modules + shared catalog; PROJECT_STANDARDS §2.2a; et/CLAUDE.md).
- **ct_dev 0.7.239-dev** (#470 curse-sorcerer rank-8 hole, vanilla bug) + **0.7.240-dev** (#426 peer-parity gate for modded boons/miracles - 5 gate surfaces; #406 ct_kill_heal re-enabled; 200-local ceiling build fix).
- **gt_dev 0.2.196-dev** (#459 LineObject dead-world AV, BUG_CLASSES 32) + **0.2.197-dev** (#448 downed bots stop granting Morr's).
- **wt 0.12.208-dev** (BR broadphase guard + create_equipment audit P0s).
- **crt 0.3.55-dev** (#425 peer-parity gate for 8 networked talent reworks - wire-safe wrappers + hot-join filter).
- **cwv 0.1.377-dev** (#474/#475 husk display: skin-key PRIMARY, native never re-keyed, lazy can_wield).
- **docs/engine/** 11-subsystem reference set + IMPROVEMENT_BACKLOG (72 rows; 13 P0s routed) + campaign doc deltas reconciled (career_name drop root-caused to third-party standalone Material Hijack - wt compensations stay).

**🏷 Label taxonomy (user rules 2026-07-11, codified §11/runbook/CLAUDE.md):** `verify-fix-coop` replaces `verify-fix` when 2+ testers needed (manual swap after ship.ps1 auto-label); `Fixed` = user-verified, post-fix pass (hardening/docs/regression tests) owed before close.

**🌙 OVERNIGHT 2026-07-12 (autonomous, 3-agent pool):** shipped ct_dev 0.7.241-dev (#356 arity fix - guard now filters the signature-zone list), crt 0.3.56-dev (Cursed Armor no longer swallows on_damage_taken procs, backlog P0) + 0.3.57-dev (OOP p1: entry 1332->568), cosmetics 0.9.79-dev (OOP p3: glow module; p4 wire/LA regions BATCHED for a coop window), wt 0.12.210-dev (OOP p2: 2,786-line anim core moved verbatim; p3 HELD pending in-game verify), cim_dev 0.8.55-dev (OOP p1: mission-forge safety/filter/dumps), woc 0.1.8-dev + mp 0.2.15-dev + et 0.4.27-dev (#427 warn-chat, 3 of 16 sites; 13 remain per issue comment). ENGINE_SURFACE series COMPLETE: 7 docs + reverse index (docs/engine/README). New issue #496 (gut monologue script_data shadow); #356 root-cause commented, #399 diagnostics-armed with #279 probes (cwv 0.1.381-dev). Aggregate GitHub release current (08:37Z). Two git incidents self-recovered (staged-file sweep; stale index.lock).
**⚠ Open ends (the what-now list):**
- **Handoff branch FULLY ABSORBED 2026-07-12** (all streams shipped: crt/ct_dev/cwv/cosmetics/et/gut_dev). Next up: #495 (cwv skin wire leak, 0-critical, must be parity-gated or #474 regresses), then #492/#478/#423/#424/#427, OOP program (wt -> cosmetics -> crt -> cim_dev -> ct_dev -> cwv).
- **User in-game verify queue** (full Steam restart FIRST; coop items need the 2nd machine): et 0.4.26 `/event_tweaker_regression_test`, ct_dev `[ct:470]` + #426/#406 coop checks, gt_dev #459/#448, wt 0.12.208, crt #425 coop, cwv #474/#475 coop + prior queue (see #494).
- **#495** cwv skin wire leak (0-critical): fix MUST be parity-gated or #474 regresses.
- **Not started:** #492, #478, #423/#424 damage/spawn axes, #427 warn-chat sites, OOP program order (enemy_tweaker -> wt -> cosmetics -> crt -> cim_dev -> ct_dev -> cwv).
- **User decisions:** #433 (dead BR code), #435 (dcp portraits scope).
- **PC-B catch-up deploy** when reachable.
## 📌 2026-07-08 SESSION — full OOP audit + plan + wave 1 + enforcement stack + WS3 docs (issue 429-436)

**User directive:** audit all mods one at a time, plan, refactor toward OOP; verify the Opus-era docs/standards (suspicion confirmed: 0/9 binding rules were machine-enforced). Plan = `docs/OOP_REFACTOR_PLAN.md`; audits archived `_archive/audits/2026-07-07_oop_audit/` + external backup.

**✅ Shipped & Workshop-verified** (all -dev; **PC-B SKIPPED - unreachable all session (ssh Permission denied), needs catch-up deploy**): mp 0.2.14-dev (#434 EAC restore), woc 0.1.7-dev (#422 wire-safe loadout), ct_dev 0.7.238-dev (em dashes), cwv 0.1.374-dev (#424 thrown-pickup wire substitution) + 0.1.375-dev (#371 peer-parity beacon, first consumer = javelin-bomb pool gate; `_TJB_FEATURE_ON` still off), cosmetics 0.9.75-dev, crt 0.3.54-dev, gut_dev 0.2.216-dev (regression coverage).

**🔧 Enforcement (#429 CLOSED):** CI now runs `qa/run_all.ps1` full + blocking lint-mod; ratchet baselines (`qa/baselines/`, regenerate only via `-UpdateBaseline` with sign-off); `check_dev_only_edits` pre-commit step 0; new advisory gates check_logging (NEVER-context model; live counts = #427 worklist: 16 warn-chat sites) + check_hook_test_coverage. Ratchet proven live (caught cwv growth, a79a4b1 sign-off).

**📚 WS3 docs COMPLETE (#432 phases 1-3, open for review):** contradictions/stale claims fixed; TODO/WORK_ITEMS/TESTING_STATUS retired to stubs (this board + Issues = only status surfaces); overlap clusters merged to owner docs; root topic docs moved to `docs/`; PROJECT_STANDARDS §7.10 deprecation lifecycle + §9a cross-mod API compat.

**🌙 OVERNIGHT 2026-07-12 (autonomous, 3-agent pool):** shipped ct_dev 0.7.241-dev (#356 arity fix - guard now filters the signature-zone list), crt 0.3.56-dev (Cursed Armor no longer swallows on_damage_taken procs, backlog P0) + 0.3.57-dev (OOP p1: entry 1332->568), cosmetics 0.9.79-dev (OOP p3: glow module; p4 wire/LA regions BATCHED for a coop window), wt 0.12.210-dev (OOP p2: 2,786-line anim core moved verbatim; p3 HELD pending in-game verify), cim_dev 0.8.55-dev (OOP p1: mission-forge safety/filter/dumps), woc 0.1.8-dev + mp 0.2.15-dev + et 0.4.27-dev (#427 warn-chat, 3 of 16 sites; 13 remain per issue comment). ENGINE_SURFACE series COMPLETE: 7 docs + reverse index (docs/engine/README). New issue #496 (gut monologue script_data shadow); #356 root-cause commented, #399 diagnostics-armed with #279 probes (cwv 0.1.381-dev). Aggregate GitHub release current (08:37Z). Two git incidents self-recovered (staged-file sweep; stale index.lock).
**⚠ Open ends (the what-now list):**
- **User in-game verify queue** (full Steam restart FIRST): cwv 0.1.375-dev 2-player javelin+bomb with a vanilla client (`/cwv_regression_test`, `[cwv:424]` lines), cim v0.8.34 public equip, cosmetics ct_* illusion, woc Blightreaper, ct v0.7.131-beta kill-heal client, mp `/mp_regression_test`, crt/gut suites.
- **User decisions:** #433 (dead BR code: archive-and-delete vs keep-dormant), #435 (dcp portraits career-scoped - intended?).
- **Wave 2b (GATED on the cwv beacon verify):** wire `_lib_peer_parity` into crt #425, ct #426, et #430, wt #431, cwv damage axis #423 + gut grey-out surface.
- **#427:** migrate 16 warn-chat sites to printf (worklist = `pwsh qa/check_logging.ps1`).
- **PC-B catch-up deploy** when reachable.

## 📌 2026-07-01 SESSION — repo-wide settings-menu reorg (7 parallel agents, 8 mods shipped)

**User asked for a full pass over every mod's menu localization + organization.** Pure sort/organize/polish; NO setting_id renames, NO new/removed settings, NO behavior changes (new umbrella MASTER toggles from `MENU_CONSOLIDATION_PLAN.md` §2-4 stay deferred: they need code gating). `sub_widgets` nesting done ONLY where the master was verified in code to gate the children.

**✅ Shipped & Workshop-verified** (hash + `Uploaded new content` confirmed per mod; **PC-B SKIPPED, unreachable, needs catch-up deploy**; GitHub release refreshed once at session end; each mod committed path-scoped + pushed):
- **wt 0.12.197-dev** - Weapon Tweaks group A->Z; orphaned brett loc block colocated. Availability tree untouched (deliberate #179 grouping).
- **gut_dev 0.2.164-dev** - new "Hide HUD & UI" umbrella folds the HUD-visibility surface + absorbed HideBuffs surface; "HUD" group relabeled "On-Screen Overlays"; top level A->Z. (Parallel session's 0.2.165 compendium work continued on top, untouched.)
- **et 0.7.23-dev** - 10 top-level groups A->Z with cleaner names; ~24 labels to sentence case per LOCALIZATION_STANDARD 11.1; monster/elite-pool chance sliders nested under their code-gated toggles.
- **cim_dev 0.8.43-dev** - top-level groups + children A->Z; Athanor functional order kept + commented.
- **cwv 0.1.359-dev** - variant toggles A->Z.
- **gt_dev 0.2.170-dev** - 144 widgets into 6 top-level areas A->Z (Bots / Cheats and Debug / Gameplay / Host-Side Lobby Controls / Info / Visuals and Audio); noclip, kick-idle, MOTD fine-tunes nested under code-gated masters; index-locked Creature Spawner show_widgets block untouched.
- **ct_dev 0.7.202-dev** - 8 top-level groups A->Z; ~34 trait-ban boxes alphabetized; per-mission list nested under inject_adventure_maps; "Corrupted Flesh: max clouds per minute" + "Finale God" label polish (legend -> tooltip).
- **crt 0.3.49-dev** - top level A->Z; vanilla roster order unified across all 4 character-grouped areas; 7 group labels de-noised; cbr_* on-ice block byte-identical.

**Audited clean (no changes, no bump):** cosmetics_tweaker, event_tweaker, vdl_dev, mp, WOC. Skipped by design: dcp (no options page), tweaker (frozen), all stable siblings, weapon_tweaker_dev (parked split).

**⚠ Open ends:**
- **User in-game verification** of the reorganized menus (all 8 mods). Full Steam restart first.
- **PC-B catch-up deploy** when reachable (any `deploy` auto-pushes).
- Commit `0e1115c` ("cwv") accidentally swept the parallel session's FINISHED gut_dev 0.2.165-dev compendium files (shared git index; that session staged mid-batch). Content coherent, message inaccurate for those 6 files. Later commits switched to pathspec commits (`git commit -- <path>`), which are immune.
- Follow-ups from the agents' audits filed as GitHub issues (dead wt strip scaffolding, gt_dev MOTD loc orphans, ct_dev loc-file physical reorder, mp dead key, umbrella-masters phase).

## 📌 2026-07-01 SESSION — CW log forensics + boon scrollbar + 4 fixes (ct_dev/gut_dev)

**✅ Shipped & Workshop-verified** (hash + `Uploaded new content` confirmed; **PC-B SKIPPED — unreachable, needs catch-up deploy**; GitHub release `mods-2026-07-01` refreshed on each ship):
- **ct_dev 0.7.199-dev** — boon-offer scrollbar for shrines (>4) + chests (>3): wheel / track-click / draggable thumb; boon-count caps raised 5 → 50. Look for `[ct:boon_scroll] engaged` in log.
- **gut_dev 0.2.159-dev** — #106 bastion sticky cutscene: instance-keyed post-skip guard suppresses rogue camera re-activations; camera ACTIVATE/DEACTIVATE lifecycle logging (closes client blind spot); `[gut:frametime]` 30s heartbeat.
- **ct_dev 0.7.200-dev** — #156 Magnus zero-pickups: spawner-count printf + candidate fix (enable `adventure` object set for injected adventure levels in deus; HYPOTHESIS — verify in-game). #211 disabled boons: culprit = ct's own bot random-boon picker sampling the raw pool; now gated via shared `_ct_boon_disabled`; all grants source-tagged in `[boon-trace]`. #104 corrupted-flesh FPS: `[ct:flesh_guard]` rolling cap, new setting "Corrupted Flesh Curse: Max Gas Clouds per Minute" (Curses group, default 6, 0 = vanilla) + `[ct:aoe]` attribution.

**🔎 Log forensics (2026-07-01 CW run, host + client compared):** bastion FPS = `curse_corrupted_flesh` gas clouds (~117/21.5min, both machines) + map's degenerate main-path data (host A* churn 245 vs 5); bastion cutscene = map flow re-arms camera after skip (35.5s natural-duration release); Magnus = ALL spawner lists empty at populate (object-set exclusion hypothesis; refutes old #156 theory). Host ran STALE crt/et/event_tweaker/vdl (Steam-restart trap) — tonight's reports against those 4 need retest. #129 Mathlann guard fired in anger (65→40, warcamp). Filed **#211/#212/#213**; evidence comments on #104/#106/#129/#154/#156.

**⚠ Open ends:**
- **User in-game verification:** boon scrollbar (position + wheel direction), Magnus pickups (`[ct:objset]` + nonzero `spawners:` counts), bastion-class cutscene skip, corrupted-flesh feel at cap 6/min. Full Steam restart FIRST.
- **PC-B catch-up deploy** when reachable (any `deploy` auto-pushes).
- **#212** (gut /armory + /bestiary command collision) + **#213** (freeze-unit-twice under et grunt caps) — filed, not yet fixed.
- Version skew note: this session's final `publish-release` staged the whole tree, so some GitHub zips are a patch AHEAD of their Workshop uploads (concurrent sessions mid-bump: gt_dev .168, gut_dev .160, et .21, cosmetics .59, cwv .358, cim_dev .40, dcp .16, event .19, mp .11, vdl_dev .14) — self-heals when those sessions ship.

## 📌 2026-07-01 SESSION — GitHub-issue sweep (non-gut / non-ct), 7 parallel agents

**✅ Shipped & Workshop-verified** (all `-dev`; hash + `Uploaded new content` confirmed; **PC-B SKIPPED — unreachable/off, needs catch-up deploy**):
- **enemy_tweaker 0.7.20-dev** — #42 RPC schema on `et_br_fingerprint`.
- **gt_dev 0.2.167-dev** — #44 AI-control RPC schema. (#194 no-bots + #59 BT crash re-verified already fixed in tree.)
- **CWV 0.1.357-dev** — #1 bare-globals → `_om` holder table. ⚠ main lua now at Lua 5.1's hard **200-local ceiling** — new file-scope state must go in `_om`.
- **cosmetics_tweaker 0.9.58-dev** — #45 RPC schema on all 4 LA/glow channels. (#148/#199/#186 verified already fixed.)
- **weapon_tweaker 0.12.194-dev** — #179 availability grouped by source char, #160 Exec Sword on Saltzpyre picker (SET G). (#201/#195/#187/#197 verified already fixed; #159 partial — convention live, retroactive sweep deferred.)

**🔧 Tooling (working tree, uncommitted):** #85 fixed (check_published_ids em-dash broke PS 5.1 parse); #51 detection verified fixed, remaining 9 findings gated on ct/gt dev→stable promotion; **NEW #214 fixed** (lint-mod.ps1 second positional arg clobbered source files — now named-only + write guard); **NEW #215 filed** (non-mod sentinel names trip check_in_progress exit 2).

**📝 cim_dev:** #88/#96/#86 verified already fixed with evidence comments; #83 recommended close-as-stale. (cim_dev later bumped by the probe pass below.)

**🔬 PROBE PASS (same session, later)** — passive DEFAULT-ON printf diagnostics so the user's normal playtest yields data (no manual commands; visible with mod-logging OFF). All 5 shipped + Workshop-verified; PC-B still down; GitHub `mods-2026-07-01` assets refreshed (19 files, whole tree incl. sweep's ct_dev 0.7.201-dev — skew self-heals):
- **enemy_tweaker 0.7.22-dev** — #213 double-freeze GUARD (vanilla BreedFreezer race, et grunt caps amplify; likely outright fix) + `[213:freeze]` probe; `[rpc:schema]` mod:warning→printf.
- **gt_dev 0.2.169-dev** — `[198:dummy]` per-swing dummy-hit attribution (TrainingDummyHealthExtension.add_damage); `[139:bot_tp]` teleport-while-downed probe (`post_dist`≈0 = the bug); #44 `[rpc:schema]` mod:info→printf.
- **cosmetics_tweaker 0.9.60-dev** — `[cos:sync]` 9-point LA husk/shield divergence probes (#149/#154/#200/#203/#204); `[174:loadout]` vanilla set_loadout_item chokepoint + caller hint; 4x `[rpc:schema]` mirrored to printf.
- **cim_dev 0.8.41-dev** + **mp 0.2.12-dev** — #174 attribution (cim capture/restore logging incl. `persist=`; mp `is_eac_window()` + non-writer banner).
- Next-playtest log greps: `[174:loadout]` `[cos:sync]` `[198:dummy]` `[139:bot_tp]` `[213:freeze]` `[rpc:schema]`.

**⚠ Open ends:**
- ~~**GitHub release for the 5 uploads DEFERRED**~~ **RESOLVED same day** by the forensics session's ct_dev 0.7.200-dev ship — ct_dev compiles again and its `publish-release` staged all 18 mods (incl. wt .194 / et .21 / cwv .358 / cosmetics .59 / gt_dev .168; some zips a patch ahead of Workshop, see that session's version-skew note above).
- All source changes are **uncommitted** (user commits).
- Author must **fully restart Steam** to pull the self-authored uploads.

## 📌 2026-06-24 SESSION — shipped + open (previous board)

**✅ Shipped & uploaded this session:**
- **wt 0.12.152-dev** (public) — 8 weapons baked to 3P (pickaxe, dual-axes, fire-sword, dagger, mace, scythe, Greathammer, Coghammer); scythe **+6** & glaive **+0.285** *durable* grip offsets; auto-vent made implicit.
- **gut 0.2.82-dev** (friends) — Mod Tweaker menu sounds (`Play_hud_button_open/close/select/hover`, root cause = wrong wwise-world handle), hover pressed-image removed, section padding. (Addresses the sound/highlight parts of **#77**.)
- **gut_dev created → 0.2.84-dev** — NEW friends-only Workshop item **3751024698** (id `gut_dev`). Owns the migrated **in-mission inventory** (`/gut_inv`, toggles default ON); gear cog **gated to cim**, inert/greyed otherwise (no crash).
- **gt_dev 0.2.137-dev** + **gt public 0.2.72-alpha** — in-mission inventory/keep-menus removed (migrated to gut); **resolved #62**.
- **cim PUBLIC 0.8.8** — dev fixes promoted, in-mission Athanor keep-gated, description refreshed. **cim_dev 0.8.24-dev** — adds #86 stamina fix + #88 inventory-leak fix.

**🟡 NEEDS YOUR CALL:**
- **Subscribe to gut_dev (`3751024698`)** in Steam — only way you'll see the in-mission inventory (you're on public gut, which lacks it).
- **Promote cim_dev → public 0.8.9** — carries #86 (stamina) + #88 (ESC-backout leak); both live on public 0.8.8 for your friend. Batch ready.
- **gut public beta** — make public gut the beta (needed so cim's in-mission crafting requirement is satisfiable); whittle-or-ship-as-is + visibility.
- **wt dev/stable reconciliation** — migrate changes to the friends-only wt "(Dev)" item (`3748824853`, stale), whittle public to confirmed-working. + the picker-format mismatch blocks baking the friend's Elven weapons.

**🐞 Active issues:** #86 ✅dev #87 ✅dev #88 ✅dev (all pending public promotion) · #89 deferred (cosmetics_tweaker mount-fix) · #84/#80/#81/#83 in-mission deferral/crash · #85 qa tooling · #76/#77/#78 gut Mod Tweaker fidelity (partly addressed). **Closed:** #58 #62 #79 #82.

## 🧪 NEXT-LAUNCH TEST CHECKLIST (gut Mod Tweaker + cim forge) — pre-2026-06-24, historical

Where the in-game iteration stands, so the user knows what to test on relaunch.

**✅ Confirmed working in-game (user-verified):**
- Menu **opens** from the keep ESC button + renders its **body** (rows, sliders w/ moving thumb, ON/OFF steppers, dividers).
- Slider **spacing** + row **highlight** read well (gut 0.2.63).
- **Main menu / keep ESC menu** overflow + logo fixed — "looks good now" (gut 0.2.64).
- CIM tab → **"CRAFTING"**; **vdl** off the menu (gut 0.2.63). **dcp 0.1.15**: no options page, just runs.

**🔜 SHIPPED `0.2.66` — landed, now being POLISHED (user gave detailed feedback):** title removed + native tabs/arrow-columns/fonts/row-height, keep separator lifted, typeable number field. The menu works; the items below refine it.

**🔜 SHIPPED — test on relaunch (gut `0.2.70` + cim_dev `0.8.21`) — workflow `wyeeh6kox`, exact native values + adversarial verify (both verdicts: clean, both build):**
- **Text-aware tab widths** (measured per native `UIRenderer.text_size` + 20px gap — no more fixed too-wide tabs).
- **Scrollbar** native colors (track `{255,5,5,5}`, thumb `{255,160,146,101}`) + **dynamic thumb height** (visible/total).
- **APPLY button + staged changes** — every widget (toggle/stepper/slider/dropdown/number) now writes a PENDING buffer; nothing applies until **APPLY**; exit discards. *(Big behavior change — verify staging + APPLY + discard work.)*
- **Gear icon** = the equipment `cog_icon`; control column shifted left so the gear has a 10px gutter off the arrows (no overlap).
- **Real dropdowns** (single down `drop_down_menu_arrow` + popup list, atlas-safe).
- **Number field** darker bevel/background; **Enter no longer opens chat** (`block_chat_input_for_one_frame` while editing).
- **Slider yellow fill removed**; **blue group-header bg removed** (colored text kept); **nested rows indented** per depth.
- **Standard crafting menu IN-MISSION** (`cim 0.8.21`) — opens `HeroWindowCrafting` (NOT the weave forge), verified **material-clean** (no inn-only raw materials → no crash). Via keybind `standard_crafting_hotkey` (bind it) or `/cim_craft_standard`, gated behind Allow-in-mission. *(2 follow-ups: it shares the "may crash" Allow-in-mission toggle with the parked athanor forge — can split into its own toggle + fix the label; and the loadout-access flip persists like gt's.)*

**🔜 SHIPPED — test on relaunch (gut `0.2.71` + gt_dev `0.2.136`) — workflow `w89gmzacj`, verdict clean:**
- **On/off flicker FIXED** — was a multi-fire toggle bug (`c.flag = not c.flag` ran every frame the click's `on_release` stayed latched, not a display/VMF issue); now edge-latched (`_toggle_armed`) so a click toggles once.
- **"More 1/2" tab gone** — only paginates if measured tab widths actually overflow the strip (they don't now).
- **Slider glow** — native atlas-safe `slider_thumb_hover` hover pass on the thumb.
- **APPLY box removed** (text + hotspot only).
- **Sounds wired** — `Play_hud_hover` on hover-enter edges, `Play_hud_select` on commits (toggle/arrow/dropdown/slider/tab/APPLY/gear). *(You green-lit sounds.)*
- **Bot "Cap Bot Ult Cooldown" footgun** (`gt_dev 0.2.136`) — Max default `0`→`20s` so enabling it no longer = constant bot ults. *(Your save: toggle it OFF or raise the slider — the new default won't overwrite a saved 0.)*

**🅿️ Parked — athanor *weave* forge in-mission:** deep multi-family material entanglement (`athanor_*` + `forge_overview_*` + `weave_menu_*` + HDR + LA atlas); each inn-only family faults separately. Keep **Allow-in-mission**'s athanor *hotkey* path unused (still crashes) — use the standard crafting bench above instead.

**🟡 Pending your call:**
- **Split the in-mission crafting toggle** — give standard crafting its own toggle + stop the (crashing) athanor hotkey from firing in-mission, so Allow-in-mission isn't a shared footgun. *(Offered; awaiting go.)*
- *(Sounds — done in `0.2.71`.)*

## How we work (the 5 rules)

1. **One mod in flight.** Commit or stash before switching mods.
2. **This board is the only "what now" surface.** Ask "what's next?" → the answer is here.
3. **One funnel:** `Untested → Ready-to-test → Confirmed → Promoted`. Each feature sits in exactly one stage.
4. **Feature freeze holds.** New ideas go to the Parking Lot, not into code, until in-flight work is confirmed.
5. **Session bookends.** Claude opens with a standup (git status + this board + today's one focus) and closes by updating this board.

---

## 🎯 Current focus

**Menu consolidation SHIPPED and the 2026-06-22 uncommitted WIP is long committed — every mod below shipped many patches ahead.** The live "what now" surface is now the dated SESSION blocks at the top of this file; the Current-focus / WIP / Coordination sections below are retained as 2026-06-22 historical context. Menu consolidation §1-4 landed (gut_dev 0.2.164-dev, gt_dev 0.2.170-dev, ct_dev 0.7.202-dev, crt 0.3.49-dev — see `MENU_CONSOLIDATION_PLAN.md`); the umbrella master-toggles are the only deferred piece.

> **[SUPERSEDED 2026-07-07]** The block below is the 2026-06-22 focus (land WIP first, then *start* menu consolidation). Both are done. Preserved for history.

**Land the uncommitted WIP in coherent per-mod commits, then start menu consolidation on a clean tree.**
⚠️ **CORRECTION (2026-06-22):** the tree is far more loaded than first reported — uncommitted work spans **~13 mods + QA/tooling + a new `weapon_tweaker_dev/` dir**, accumulated from the now-retired parallel agent sessions (nothing committed since 2026-06-17). The initial "5 mods" read came from a `head -30`-truncated `git status`. A full-repo triage is underway to land it in correct per-mod commits. **`gut` and `gt_dev` are mid-flight (gut's gear feature; gt_dev's modularization) — those are continue-not-commit.**

**Active initiative — Menu consolidation** (2026-06-22): organize gut + fold scattered dev-mod settings under umbrella master toggles. Full spec + per-mod catalog: **`MENU_CONSOLIDATION_PLAN.md`**. Key finding: VMF supports expandable master toggles **natively** (`checkbox` + `sub_widgets`, auto-hide when off — `vmf_options_view.lua:4461-4463`), so the dev-mod consolidation can start without waiting on gut's Advanced Settings button (that button is only for the heavy "numerous values" case).

---

## 🤝 Coordination — parallel agents (shared working tree)

- **Single-owner orchestration (2026-06-22):** the separate gut session is retired; **this session now owns every agent.** The user relays direction to this session only; this session deploys + directs all subagents (gut + dev mods). In-game testing stays with the user/friend. No cross-session relay.
- **gut — "Advanced Settings" gear drill-down** (continuing from on-disk state): a gear on any setting that has `sub_widgets` converts the Mod Tweaker list in-place into that setting's sub-options + Back (no popup). Defaults: gear always visible (pre-configure); tabs stay visible; Back primary.
- **gut shipped `v0.2.59-dev` (2026-06-22, AWAITING in-game verify):** builds 1–3 (overflow `gut_compact_esc_menu`, General-first tab, in-mission LA re-pin, keep deprecated-look → HeroView sub-state [#76], native fidelity — ON/OFF steppers / texture arrows / separators / right-justify / ALL-CAPS tabs / title z-order / hover / Wwise sounds, in-mission deprecated-exit origin-capture [#76]); **build 4 (gear [#79] + slider thumb-move fix); build 5 = `v0.2.60-dev` (keep ESC-button now opens the sub-state — needed `force_open=true` to force the hero_view re-enter so `menu_state_name` is honored).** Mod Tweaker feature-complete + keep-entry fixed. Open (see-to-tune only, no grind): sounds pending `wwise_world` resolve (`[mt:wwise]` probe), long-dropdown truncation eyeball, overflow offset-sign unconfirmed. Issues [#77]/[#78]/[#79].
- **cim_dev in-mission forge cascade CLOSED `v0.8.19-dev` ([#81], AWAITING in-game verify):** B (LA atlas HDR world) → B2 (weave_menu glow draws + skill-tree cluster) → B3 (`set_scalar` bloom pulse) → B4 (upgrade flourish) → B5 (skill-tree ring/cluster non-HDR `_bottom_widgets`). Keep path full-HDR untouched. Forge usable in Adventure missions (minus decorative glow). Fallback if a new vector surfaces: #80 vanilla-tab path (no HDR windows).
- **No registration contract needed.** The Mod Tweaker reads VMF's GENERIC node tree, so the gear auto-applies to ANY mod's `checkbox` + `sub_widgets` umbrella. → `checkbox`+`sub_widgets` cluster ⇒ gear drill-down; `group` cluster ⇒ inline [+]/[-] collapse. **The pattern chosen per cluster IS its Mod-Tweaker presentation** (matches `MENU_CONSOLIDATION_PLAN.md` §0).
- **Commits stay PATH-SCOPED** (never `git add -A`) — one mod per commit, so unrelated in-progress work is never swept in.

---

## 📥 Uncommitted WIP — full-repo commit plan (2026-06-22, full triage)

> **[SUPERSEDED 2026-07-07]** This entire commit plan is done. All the 2026-06-22 uncommitted WIP was committed long ago, and every mod has since shipped many patches ahead of the versions in the table below (verified against each mod's CHANGELOG top entry on 2026-07-07): **wt 0.12.207-dev** (was 0.12.137), **gt_dev 0.2.195-dev** (was 0.2.135), **chaos_wastes_tweaker_dev / ct_dev 0.7.237-dev** (was 0.7.161), **cim_dev 0.8.54-dev** (was 0.8.15). The `weapon_tweaker_dev` split "decision" in the HELD list is resolved: **wt stayed single-stream; `weapon_tweaker_dev/` is the ABANDONED stale clone** — never edit it (`weapon_tweaker/` is the active wt dir). The table + HELD list are kept only as a snapshot of that day's tree.

**Clean & verified — land these (pending the go):** each its own path-scoped commit.

| Area | Version | Stage (untracked) | Note |
|---|---|---|---|
| career_tweaker (crt) | 0.3.44-dev | `_armor_overcharge.lua`, `_oe_cooldown.lua`, `TALENT_TEXT_RENDERING.md`, `TODO.md` | OE Leading Shots + Armor/Overcharge + Sienna Unchained |
| chaos_wastes_tweaker_dev | 0.7.161-dev | `_ct_dup_vote_chips.lua` | dup-career vote chips + altar/curse fixes — **SHIPPED; now 0.7.237-dev.** |
| cosmetics_tweaker | 0.9.39-dev | — | `is_bot` bot-loadout fix; glow-menu trim |
| crafting_in_modded_dev (cim_dev) | 0.8.15-dev | — | loadout persistence default-OFF; **add `_craftable_trait_pool` CHANGELOG line first** — **SHIPPED; now 0.8.54-dev.** |
| enemy_tweaker (et) | 0.7.16-dev | `_et_boss_tweaks.lua` | Warlord monster-pool + horde scaling + BR on ice |
| event_tweaker | 0.4.15-dev | `event_tweaker_curses.lua` | Cursed Adventure + Other Mutators |
| general_tweaker_dev (gt_dev) | 0.2.135-dev | **19 `_gt_*.lua` modules** (+ 2 tracked deletions) | **Modularization FINISHED** ("Phase 4, final") — atomic commit. Menu consolidation NOT blocked. — **SHIPPED; now 0.2.195-dev.** |
| verminious_dreams_lighting_dev (vdl_dev) | 1.0.10-dev | — | CW curse-tint lighting layer |
| weapon_tweaker (wt) | 0.12.137-dev | `_wt_passive_charge.lua` | passive vent restore; `skip_sync` MP fix; incl. `RELEASE_SPLIT_PLAN.md` draft — **SHIPPED; now 0.12.207-dev.** (`RELEASE_SPLIT_PLAN.md` is now SUPERSEDED — split never executed.) |
| repo: QA trio | — | `qa/check_published_ids.ps1`, `qa/PUBLISHED_IDS.md` | **group with** `qa/run_all.ps1` (it invokes the script) |
| repo: docs/tooling | — | `TESTING_STATUS.md`, `tools/label-untested/`, `STATUS.md`, `MENU_CONSOLIDATION_PLAN.md` | + `docs/BUG_CLASSES.md` (Class 19) |

**Every untracked file above is a `dofile`/`require` target of already-tracked code** → must be staged in the same commit or a clean checkout fails to load. Path-scoped commits only (never `git add -A`) — protects the held items below.

**HELD — need a call (not committing):**

| Area | State | Decision |
|---|---|---|
| gui_tweaker (gut) | **keep-working** (0.2.55-dev) | Genuinely mid-flight: `_ba_*` Bestiary/Armory is a Phase-0 stub, Mod-Tweaker rework phases 1-5 not started, leftover `[mt:*]` debug lines, orphaned `hb/mod_events.lua`. Leave uncommitted; I continue it. |
| crafting_in_modded (cim, **PUBLIC**) | reconcile + ship | Version 0.8.7 > CHANGELOG 0.8.6; `_craftable_trait_pool` undocumented. Hold until you're ready to reconcile + ship public. |
| weapon_tweaker_dev (NEW dir) | **ABANDONED (2026-07-07)** | Decision resolved: the split was NEVER executed. wt stayed single-stream; `weapon_tweaker_dev/` is a STALE clone — never edit it (`weapon_tweaker/` is the active wt dir). `RELEASE_SPLIT_PLAN.md` in both dirs is marked SUPERSEDED. |

---

## 🧪 Ready to test (drain with friend — batch these)

Code-complete, awaiting in-game confirmation. Flip to Confirmed when verified.

- **crt** — OE Leading Shots; Armor & Overcharge (5 toggles + OE cooldown mirror); Sienna Unchained rework set; Mercenary Enhanced Training
- **crt armor (v0.3.32)** — gromril_ignore_chip, specials_dont_break_gromril, unchained_no_overcharge_from_ff / _from_disablers
- **ct_dev** — Duplicate-career vote chips; Chest-of-Trials uniqueness; altar-reuse visual fixes; #68 client shrine/lighting fix; Miracle of Isha next-mission scope
- **cim_dev** — Modded-loadout persistence toggle (default OFF) + index-aware schema
- *(Full untested lists: ct_dev 125 · gt_dev 102 · cim_dev 9 · vdl_dev 4 — see `TESTING_STATUS.md`)*

## ✅ Confirmed — promotion candidates (ship when YOU say so)

Not a push to release — just visibility into finished, verified work parked in dev.
- **gt_dev → gt**: 20 confirmed (3P camera set, godmode, noclip set, cutscene skips, ready-up, bot behavior improvements, …)
- **ct_dev → ct**: Disable Shadow Homing Skulls; Disable Skulls of Fury; Skittergate injection
- **wt**: Kerillian Spear, Saltzpyre Axe (all receivers); Saltzpyre Billhook (Kruber careers)

---

## 🚫 Blocked / buggy

**NOW (top-priority bugs):**
- **#62 — gut: Keep-menu-in-mission crash.** PUBLIC mod, external user, 5 logs. Highest visibility.
- **#59 — gt: Drachenfels boss BT crash** on CW `dlc_castle_*_path` — host crash kills the run.
- **#68 — ct: native CW Belakor variants render as shrines** — keystone of the CW-map cluster.
- **#65 — gt: bots_in_keep** — 2 crash classes, root cause written, feature kill-switched.

**CW injected-adventure-map cluster (one root cause — too-narrow base-level-key gate):** #68 · #56 · #59 · #60 · #52 · #58. **Fix #68's base-set first** — it unblocks #56 / #60 / #59. #52 (mission interactables) and #58 (missing `harder` pickup_settings, a data gap) each need their own follow-up.

**Known-buggy features (left untested):**
- ct_dev: Tower of Treachery gargoyle skulls don't spawn (#52)
- wt: Saltzpyre + Longbow wrong 3P model/anims (blocked on anim research)
- crt: BH career ability on non-native ranged; talent-swap UI no refresh

---

## 🅿️ Parking lot — FROZEN (do NOT start)

New-feature ideas held until in-flight work is confirmed. *(Per-mod TODOs hold the detail.)*
- **ct**: loot-rat Chest of Trials · mutator-based custom curses · shrine miracle customizer · altar coin cost · CW inventory
- **wt**: GiveWeapon command · rapier-pistol ammo rework
- **cosmetics**: Purified recolor pipeline · dirt removal · custom illusion icons + inline swap
- **enemy_tweaker**: spawn-parity Phases 1-5
- **crt**: talent/ability transplant
- **mp**: reward/loot/craft intercepts
- **cwv**: javelins/throwing-axes · hammer-vs-mace toggle
- **gut**: HeroView UI integration

---

## 📌 Next-focus candidates (pick ONE after the WIP lands)

1. **#62 public gut crash** — real external user on a public mod; highest stakes.
2. **CW-map cluster (#68 first)** — one fix unblocks 4 issues; big co-op-quality win.
3. **Friend-test batch** — drain the Ready-to-test queue, convert untested → confirmed.
4. **Whatever interests you** — but land it (commit) before opening the next thing.
