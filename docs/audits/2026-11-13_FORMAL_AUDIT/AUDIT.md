# Formal engineering audit: Vermintide 2 Tweaker monorepo

| | |
|---|---|
| Date | 2026-11-13 |
| Commit audited | `592253d1` (master) |
| Game version referenced | 6.13.0 (decompiled source, commit `93dea911`) |
| Lead auditor | Claude Fable 5.2, at the owner's request |
| Audit team | 17 independent audit streams (7 code, 6 tracker, 4 specialist), reports in `evidence/` |
| Status | Snapshot. The living plan is `docs/program/PLAN.md`. |

## 1. Executive summary

**Verdict.** The project is not failing because its code is bad. It is failing because nothing verifies the code. The fixes are being written, and written carefully: in 100 `verify-fix` issues spot-checked against source, 98 fixes were present on master and plausible. But the only verifier was a person playing the game, and that stopped. The newest game log on the author machine is from 2026-08-21, and the last tester comment on any issue is from 2026-09-23. Since then the project has kept producing fixes, versions, test cards and receipts for a reader who is not there.

Everything else in this audit follows from that one fact.

**The numbers that matter.**

| Fact | Value |
|---|---|
| Open issues | 329. 228 wait for a human in-game check (`verify-fix`), 54 wait for a human to capture a log (`diagnostics-armed`), 47 are not started. Median age 124 days. |
| Open issues decidable by automated evidence | 250 of 329 (76%): 190 by a script inside the running game, 40 by a static check, 20 by a unit test. 42 need a second client, 26 need human eyes or ears, 11 are blocked or owner calls. |
| Open issues closable today with no game at all | 33, plus 12 merges and 7 that should be declined. |
| Manual test cards written for a human | 1,111 across open issues, up to 12 re-issues on one issue. 846 of 858 were never followed by a non-owner comment. |
| Closed "completed" runtime issues never verified at runtime | 66 of 384 (18 of them crash-class). One (#406) was closed 34 minutes after the owner wrote that the fix did not work. |
| In-game regression checks that exist | 792 in the active builds. They run only when a human types a chat command. The one time they were run (2026-09-21) 22 failed, 4 of them real regressions in issues marked fixed. |
| Size | 523,704 lines of mod Lua in 1,309 files; 196,802 lines of Lua tests; 58,057 lines of release and paperwork tooling. |
| Release cost | A dev ship is 21 operator steps and 4 CI cycles; the best complete cycle on record is 86 minutes. A quarter of all master commits in the last 90 days only moved a bookkeeping file. |
| Mandatory reading before an agent may ship a one-line fix | About 89,000 tokens; 268,000 for a bug fix. |

**The five things that must change, in order.**

1. **Build an unattended in-game test rig.** Desk research and experiments on the day of the audit (section 8) show it is feasible: the retail game ships Fatshark's own automation calls, boots to the keep with no input, and can be driven by a small test-driver mod. This single investment turns 190 stalled issues into scripted checks and makes the 792 existing in-game checks run on every boot.
2. **Change what counts as evidence.** A scripted check that reads engine state closes an issue. A human is asked only for what needs eyes, ears or a second player (68 issues today), and gets stills and state dumps to judge. The manual test-card system stops.
3. **Fix the critical static defects now.** 20 findings are rated S0 (section 6). Several touch player data: in game 6.13 the modded realm mutates the player's live account mirror, and two mods can write mod-made item ids into career loadouts.
4. **Cut the process to what the risk justifies.** One resumable ship command, no compiled bundles in git, no per-ship bookkeeping pull request, CI under 10 minutes, a 6 KB agent entry document instead of 356 KB of required reading.
5. **Remove the structural causes.** One source tree per mod instead of diverged dev and stable forks; one owner for each piece of shared state (weapon appearance, loadouts, animation remapping); errors surfaced instead of swallowed.

**What is good and must be kept.** Citation discipline against the decompiled source; the engine reference documents; a professionally hardened CI configuration (pinned actions, read-only tokens, branch protection matching its documentation); a single mod inventory; a shared-library drift gate; a large engine-free unit suite; and a rich set of in-game commands that the rig can reuse as test verbs.

## 2. Scope and method

**Scope.** Every active mod in the repository (21 Workshop items in 15 families), the legacy `tweaker`, all tooling under `tools/` and `qa/`, CI, all 329 Markdown documents, the full issue tracker (329 open, 613 closed, 6,768 comments), and the agent-facing rule layers above the repository.

**Method.** Seventeen independent audit streams, each with a written brief, a read-only mandate and an evidence rule (every code claim cites `path:line`; every engine claim cites the decompiled source; anything not read is marked unverified):

| Stream | Subject | Report |
|---|---|---|
| A1 | weapon_tweaker and its dev mirror | `evidence/A1.md` |
| A2 | character_weapon_variants, weapons_of_chaos | `evidence/A2.md` |
| A3 | cosmetics_tweaker, dynamic_cosmetic_portraits, character_dialogue | `evidence/A3.md` |
| A4 | chaos_wastes_tweaker (dev and public), event_tweaker, enemy_tweaker | `evidence/A4.md` |
| A5 | crafting_in_modded (dev and public), modded_progression, career_tweaker | `evidence/A5.md` |
| A6 | general_tweaker (dev and public), verminious_dreams_lighting, legacy tweaker | `evidence/A6.md` |
| A7 | gui_tweaker (dev and public) | `evidence/A7.md` |
| B1 | Release engineering, CI, source control, supply chain | `evidence/B1.md` |
| B2 | Test and verification infrastructure | `evidence/B2.md` |
| C1 | Feasibility of autonomous runtime verification | `evidence/C1.md` |
| D1 to D5 | Triage ledger of all 329 open issues, by mod family | `evidence/D1.md` to `D5.md`, `ISSUE_LEDGER.tsv` |
| D6 | The 613 closed issues | `evidence/D6.md`, `CLOSED_LEDGER.tsv` |
| E1 | Documentation, governance, process weight, agent executability | `evidence/E1.md` |
| Lead | Cross-cutting measurements (duplication, drift, hook collisions, history) | section 3, `evidence/data/` |

Reference frames used for judgment: the ISO/IEC 25010 product-quality characteristics (functional suitability, reliability, security, maintainability, performance efficiency, compatibility), the four delivery metrics from DevOps research (lead time, deployment frequency, change failure rate, time to restore), and the test pyramid.

**Limits, stated plainly.**
- This is an architecture and engineering audit, not a line-by-line review of 524k lines. Each code stream read the load-bearing modules in full, sampled the rest, and says exactly which.
- At audit time the game was not installed, so every runtime defect in the code reports is static evidence with a named runtime observation that would confirm it. Section 8 records what was then observed in the running game.
- The owner and the agents post from one GitHub account, so counts of "human" replies are lower bounds.
- Severity is the auditors' judgment on a four-step scale: S0 critical (crash or soft-lock class, save or progression corruption, co-op desync, or a systemic process failure), S1 high, S2 medium, S3 low.

## 3. System overview in numbers

| Mod family | Trees | Lua lines (active tree) | Hook sites | `pcall` | In-game checks | Open issues |
|---|---|---|---|---|---|---|
| Weapons (`wt`) | public beta + friends-only mirror | 36,948 | 42 | 275 | 80 | 35 |
| Character Weapon Variants, Weapons of Chaos | single | 57,559 | 150 | 835 | 127 | 71 |
| Cosmetics, Portraits, Dialogue | single | 86,329 | 104 | 480 | 81 | 37 |
| Chaos Wastes, Events, Enemies | dev + public (diverged) | 57,032 | 191 | 837 | 192 | 60 |
| Crafting, Progression, Career | dev + public | 46,637 | 234 | 616 | 170 | 42 |
| General, Lighting | dev + public (diverged) | 33,120 | 197 | 329 | 96 | about 33 |
| GUI | dev + public (diverged) | 43,310 | 144 | 654 | 86 | 39 |
| **All trees, including the stable copies** | | **523,704** | **1,697** | **5,951** | **1,223** | **329** |

Cross-cutting measurements (scripts and raw output in `evidence/data/`):

- **History.** 2,937 commits in seven months, 1,337 of them in July. Nearly every commit is agent-written.
- **Duplication.** The six dev/stable pairs hold 152,289 duplicated Lua lines. After normalizing namespaces, the pairs have drifted in both directions: Chaos Wastes public has 12 files that dev lacks and 57 that it is missing; GUI has 9 files unique to each side; General public matches no dev build.
- **Shared engine seams.** 878 distinct engine functions are hooked. 88 are hooked by two or more mods and 28 by three or more. Four mods (cwv, cosmetics, wt, WOC) all hook the same weapon spawn and preview functions, which is the mechanical root of the appearance bug family (#660).
- **Defensive code.** 5,951 `pcall`/`xpcall` call sites, about one per 66 lines of code.
- **Vendored shared library.** 15 `_lib_*.lua` modules are copied into up to 10 mods each and kept identical by a drift gate. This is a sound pattern for standalone Workshop bundles.
- **Repository weight.** 15.2 GiB on GitHub. Compiled `.mod_bundle` files are 98.7% of reachable history.

## 4. Scorecard

Five-step maturity scale: 1 initial (depends on individuals, unverified), 2 repeatable, 3 defined, 4 measured, 5 optimizing.

| Dimension | Score | Basis |
|---|---|---|
| Functional correctness, as verified | 1 | Fix code is present and plausible, but almost nothing is observed. 20 S0 and 86 S1 findings are almost all static. The only live suite run failed 22 checks. |
| Reliability and crash safety | 2 | Many crash classes are understood and guarded. But guards swallow errors (5,951 `pcall`), some hooks re-run vanilla after a failure, and several mods cannot be disabled back to vanilla. |
| Player-data and co-op safety | 1 | Mod-made item ids can reach the live account's loadouts; a snapshot path can overwrite stored loadouts for every career; any modded peer can end the host's mission in the public General build; peer-supplied unit names are applied unvalidated. |
| Maintainability and modularity | 2 | The module split and citation discipline are real assets. Shared state has no single owner (appearance: 15+ stores; loadout mirror: 9 mutation paths; weapon animation: 13 rewrite mechanisms; cwv: one 286-field table shared by 29 files). 152k duplicated lines. |
| Testability and verification | 1 | A large offline suite exists, but a large share of it pins source text, the in-game suites mostly prove that code loaded, and nothing runs against the game without a human. |
| Delivery and release engineering | 2 | Security posture of CI is professional. The pipeline is far out of proportion, has no rollback, binds every ship to the live head of the whole repository, and its real procedure lives outside the repository. |
| Documentation and governance | 2 | Deep, cited knowledge. Unusable in mass (356 KB required reading), 31 verified contradictions, 39% of the principal rules machine-enforced, much operational knowledge outside the repository. |
| Issue management | 2 | Rigorous form, unreliable state: lifecycle and priority labels contradict threads in every bucket; umbrella issues cannot pass or fail. |
| Operability by weaker agents | 1 | A weaker agent cannot ship unattended today: all 21 recorded failure modes are pipeline or machine mechanics, none a mod defect. |

## 5. Principal findings

Each principal finding (PF) merges evidence from several streams. Sub-report finding ids are given so the detail can be traced.

### PF-1 (S0) There is no verification, and the project compensated with paperwork

- 282 of 329 open issues are in a state that waits for a human who is not playing. Across the three largest buckets, 210 + 222 + (D3, D4, D5) pinned cards produced a handful of human test results; in the cosmetics and weapons bucket, 210 cards and 750 comments produced three (D2-F1). In the CWV bucket there has been no human evidence since 2026-09-23 while 28 further versions shipped (D1-F1).
- The fixes exist: D1 27 of 28, D2 42 of 42, D3 29 of 30 spot-checked fixes are on master and plausible. "The work is being done; it is not being observed" (D1).
- The system responded to unverifiable work by adding process: pinned exact cards, a deployed-source "authority" validator, receipts, lifecycle label guards. 335 cards were rewritten in November for no reader (E1-F01). The card guard runs inside the pull-request gate, so one malformed card on any issue fails every pull request (E1-F01, B1).
- The rules also forbid the remedy: only a "user-confirmed" receipt closes an issue, and launching the game is prohibited in five rule layers (E1-F02).

**Impact.** The backlog cannot shrink, and every additional fix increases the unverified surface that later fixes build on.

### PF-2 (S1) The evidence instruments do not measure behaviour

- The in-game regression suites mostly assert that code loaded: of 115 ct_dev checks about 25 read live engine state and 42 compare a marker string (D3, A4-F09); `/gt_regression_test` has 113 checks, almost all marker or wiring presence (A6-F05); 31 of 124 GUI checks cannot run in retail yet report PASS (A7); three portrait checks report PASS without running (A3-F12); the cwv suite never reads a live unit transform (A2-F08).
- They cannot be consumed by a machine: chat-only entry, output through `mod:echo`/`mod:info`, which is invisible with mod logging off (A1-F11, A5-F07, C1).
- A named check is statically broken and has been since 2026-07-19: the #730 check expects `cache_identity == "mesh_unit"` while the code declares `"mesh_unit+variant_key"`; 16 pinned cards require that suite to pass (D2-F2).
- Cards drift: #1211's card demands a check that does not exist anywhere in master (D1-F3); 64 of 68 CWV cards were version-bumped in place without re-validation (D1-F4).
- Offline tests pin source text: about 37% of offline assertions in the cwv family (A2-F09); the 2,130-line GUI loadout module is never executed offline, tests only search its text (A7-F02); pipeline self-tests assert the script's own source (B1-F12).
- Evidence is collected on a different build than the one the card names: 20 General cards point at official 0.2.180 while 42 of 46 General test files never read the official tree (D5); 29 of 32 Chaos Wastes cards target the public tree, whose check names differ from dev (D3).

### PF-3 (S0) Process has displaced product work

- 58,057 lines of release and paperwork tooling in 129 files, plus a C# launcher, ship 21 Workshop items whose typical payload is 1 to 2 MB (B1-F01).
- A dev ship takes 21 operator steps and 4 CI cycles; the best complete cycle on record is 86 minutes after the build was already committed. Every ship rewrites one metadata file and needs a second pull request; 59% of master commits since 2026-09-20 touch that file (B1-F02).
- In the last 90 days 46.9% of master commits touched a mod, 25.7% only moved pins, 24.4% only changed tooling or QA.
- `qa-gate` runs 21.9 minutes at the median against a 30-minute timeout and is not scoped to the change (B1-F11). The tracker lifecycle workflow has failed on every run since 2026-11-06 because a Linux runner starts a Windows executable (B1-F03).
- There is no rollback path. Replacing a broken public build takes 1.5 to 2 hours when everything is green and works on exactly one machine (B1-F06, B1-F14).
- Required reading: 89k tokens to ship one line, 188k with the mod's required documents, 268k for a bug fix (E1-F03). A document fix inside a mod directory invalidates the build receipt, so correcting a document needs a version claim and a build (E1-F06).

### PF-4 (S1) Dev and stable are diverged forks, not a promotion pipeline

- Chaos Wastes public is a separate reimplementation (`_ct_official_*` modules), holding the stronger wire fence (22 hooks against dev's 2) and lacking dev's journey-stat crash guard. A literal "promote dev" would delete the public fence (A4-F05).
- General public matches no dev build: 36 files identical, 22 differ, 35 missing (A6-F07). GUI has forked both ways; a duplicate `/mod_tweaker` registration was fixed in public and never in dev (A7-F03). Crafting public has a refactor that dev lacks (A5).
- Closed-issue fixes are mostly dev-only: fix identifiers are absent from the stable tree for 15 of 24 Chaos Wastes and 14 of 20 General issues checked, including crash guards (D6-F04).
- The Weapons parity gate proves the public tree is a textual subset of dev, not runtime parity: 36 overlay blocks and 5 dev-only files, about 5,275 lines, include a larger unlock map (A1).
- Cost: 152,289 duplicated lines, about 71,000 lines of copy commits in 90 days, seven gates and tools to police the copies (B1-F05).

### PF-5 (S0) Player data is exposed

Engine fact (A5 section 2.0, cited): since game 6.13 the modded realm is not a separate backend. `MODDED_REALM` sets a read-only flag that skips some commits, but career loadouts, talents and selected career are still built and sent. A loadout id that is not in the inventory at the next official sign-in is treated as a broken slot and replaced with starting gear.

- Crafting in Modded writes crafted item ids into career loadouts (auto-equip is on by default) and has no isolation of its own; protection exists only in another mod (A5-F01). This is the mechanism behind open issue #402.
- Game 6.12 removed the realm flag that GUI Tweaker's loadout store tested; static evidence suggests the public build passed modded equips into official character data from 2026-08-26 until 0.2.290 on 2026-11-02 (D4, #1688). The fix has never been observed in game.
- GUI Tweaker's exit-time snapshot reads its "live" value through its own read hook, so an unresolved modded id has already been replaced by the official fallback, which is then written over the store for every career (A7-F01).
- The playtester lost a crafted weapon (#1654). The cause is unknown, and the armed diagnostic iterates the saved store, so it cannot see a record that was never saved or was deleted (D4). Boot-time restore deletes a saved craft whenever its stored form differs from what the engine parses (A5-F04).
- The in-game regression suites run against the live save (D4).

### PF-6 (S0) Co-op safety depends on conventions that are not enforced

- A cwv-only `NetworkLookup` index is stamped on a replicated vanilla game object with no peer gate, introduced by a fix (A2-F01). cwv and WOC append to 13 lookup tables with 35 hand-rolled appends against 2 uses of the shared helper (A2-F05).
- Both Chaos Wastes builds hide appended level keys from the lobby hash, so unmodded players can join, and nothing gates the level or graph axis (A4-F01). The custom-boon parity gate edits a table the roller never reads (A4-F02). event_tweaker's hot-join lock hooks a base-class method that subclass instances never call, so the late-joiner crash guard cannot fire (A4-F03).
- In the public General build any modded peer can win, fail or restart the host's mission and be invulnerable, with no host opt-in and unversioned RPCs (A6-F01). Host melee lag compensation is on by default and has never had a two-client test (A6-F02, #1034).
- Peer-supplied `hand_field` and `offhand_unit` are relayed by the host and applied with no validation beyond the unit being resident (A3-F04).
- Disabling cwv or WOC drops every wire-safety hook while their items stay registered and equipped (A2-F02).

### PF-7 (S1) Shared state has no owners

- Weapon appearance: one 470-line hook infers the calling surface from four ambient flags and consults more than 15 independent stores; ten other hooks paint per surface. The repository's own census marks 871 of 1,088 surface-by-edge pairs unsupported (A3-F02). This is the structural cause of #660 and its 22 child issues.
- Loadouts: nine mutation paths in two files write one closure-held table with different row-index rules (A7-F02): the root of #375, #402, #954, #1033.
- Weapon animation: thirteen mechanisms rewrite third-person animation events; two encode the same mapping and disagree (A1-F02). Eleven owners mutate the same vanilla tables with apply order hand-written at five call sites (A1-F04).
- cwv: one table with 286 fields shared by 29 files is the module interface, and load order is the contract (A2-F06).
- cosmetics_tweaker replaces the mod framework's hook prototype and the global `get_mod`, and is the hidden provider of MoreItemsLibrary for two other mods (A3-F03).

### PF-8 (S1) Errors are hidden instead of surfaced

- 5,951 `pcall` sites. enemy_tweaker's `_hook_wrap` re-runs vanilla after an error and swallows the second failure on 21 hooks, including `ConflictDirector.init` (A4-F07). The cosmetics husk wield hook swallows every error from vanilla and from every other mod's hook below it (A3-F07).
- General Tweaker installs always-on global guards (`World.spawn_unit` swaps a non-resident unit for an empty one, `Unit.get_data` swallows nil) that mask other mods' crashes, so the behaviour of every other family depends on whether General is loaded (A6-F03).
- 22 GUI module loads fail silently (A7). Lifecycle callbacks are chained with no isolation: one throw skips every later handler, including freecam's input-unlock cleanup (A7-F04). The crafting commit hook drops the completion callback that shows the end-of-mission screen, which is a soft-lock path (A5-F03).

### PF-9 (S1) Game patches break features and nothing notices

- Patches 6.12 and 6.13 broke ten features in the crafting, progression, career and GUI family with no gate noticing; two offline checks written during this audit (do hook targets still resolve in the decompile; do icon atlas names still exist) would have caught two of the classes (D4).
- modded_progression's un-gate hooks are inert on 6.13: of six advertised systems, two work (A5-F08). A weapon-data hook targets a bug 6.13 no longer has (A1-F10).
- Five cwv variant families register only if another mod's private state and the decompiled-source commit hash match byte-exact pins: 29 SHA literals in runtime Lua. The next game patch makes weapons silently vanish (A2-F04).
- Cross-checks of engine assumptions found mismatches in every code stream (A1: 3 of 16; A2: 2 of 14; A3: 2 of 14; A4: 4 of 18).

### PF-10 (S1) Mods cannot be switched off cleanly

- Disabling Weapon Tweaker does not restore vanilla: the framework still sends update and state-change events to a disabled mod, `on_disabled` strips 260 native career/weapon pairs, and the next state change re-applies every edit with all 44 hooks off (A1-F01).
- cosmetics restores nothing when disabled (A3-F14). Crafting mutates `ItemMasterList` globally with no restore (A5-F14).

### PF-11 (S1) Unverified code is on public items

- cosmetics_tweaker is a public Workshop item on a `-dev` version with no stable twin; 31 of its 37 open issues are `verify-fix` (A3-F05). weapon_tweaker, career_tweaker and event_tweaker are public with pre-release versions and ship every change, including diagnostics, "with no asking" (E1 W15).
- The unverified queue was promoted to public: GUI 0.2.290 and Crafting 0.8.148 (D4). Bot Takeover is switched off on the build its own test card names (D5, #247).

### PF-12 (S1) Operational knowledge lives outside the repository

- About 160 memory files (590 KB) about this project live in one vendor's private memory store, invisible to the other vendor's agents, to CI and to a fresh clone. 116 memory names cited in the repository no longer exist (E1-F04).
- The scripts actually used to ship live in an unversioned folder outside the repository and were lost once already (B1-F09, E1-F09).
- The two agent vendors have opposite rules about launching the game (E1 C19).

### PF-13 (S2) Planned scope is not built, and retired scope is still carried

- modded_progression delivers local dailies and one Emporium path out of six advertised systems. career_tweaker's stated purpose, talent and ability swapping, is deliberately not loaded; 75 rework rows cover 18 of 20 careers (A5).
- Dead bulk: about 700 lines of force-disabled loadout persistence (A5-F12), inert glow override with 14 setting readers (A3-F09), a half-wired HideBuffs fork with 12 menu toggles that have no code and a missing MIT notice (A7-F05, F06), the legacy `tweaker` with 13 QA exclusions and no dependents (A6).

### PF-14 (S2) Repository and supply-chain hygiene

- 15.2 GiB public repository, 98.7% compiled bundles; the replacement mode was built across eight tooling issues and is used by 0 of 21 mods (B1-F04). 1,152 local branches, 464 commits not on master (B1-F15).
- The local account name appears on 140 lines in 83 tracked files; one document holds a private network address (B1-F19).
- Asset provenance is recorded for one mod only; the licence text may not match the content (B1-F17).

## 6. Critical defects register (S0)

| Id | Defect (static evidence unless noted) | Fix card |
|---|---|---|
| A5-F01 | Crafted item ids written into career loadouts with no isolation; reaches the live account (#402) | `WP-CIM` |
| A5-F02 | `/cim_craft_standard` and its keybind open a hero-view screen name that does not exist; vanilla asserts | `WP-CIM` |
| A5-F03 | Commit-suppression hook drops the completion callback that shows the end-of-mission screen: soft-lock | `WP-CIM` |
| A7-F01 (S0 candidate) | Exit-time loadout snapshot overwrites stored modded ids with the official fallback for every career | `WP-GUT` |
| D4 (#1688, #402) | Public GUI build passed modded equips into official character data for ten weeks; fix unobserved | `VP-D4`, `WP-GUT` |
| D4 (#1654) | Playtester item loss; diagnostic cannot see the lost record | `WP-CIM` |
| A2-F01 | cwv-only lookup index on a replicated vanilla game object, no peer gate: mixed-lobby crash class | `WP-CWV` |
| A4-F01 | Lobby-hash shim admits peers with different level lookup tables | `WP-CW` |
| A4-F02 | Custom-boon parity gate edits a table the roller never reads | `WP-CW` |
| A4-F03 | event_tweaker join lock hooks a method subclasses never call; #430 crash guard cannot fire | `WP-CW` |
| D3 (#451, #324) | Both custom breeds refused at mod load in 12 of 12 logs; card cannot pass | `WP-CW` |
| D6-F01 | #406 (co-op crash) closed 34 minutes after the owner reported the fix did not work | `VP-CLOSED` |
| D1-F1, D2-F1 | No human evidence since September while versions kept shipping | track H |
| D1-F2 | The only live suite run failed 22 checks; refixed and never re-run | `VP-D1` |
| B1-F01, B1-F02 | Pipeline out of proportion; every ship needs a second pull request | track P |
| E1-F01, E1-F02 | Card system gates every merge with no reader; rules forbid machine verification | track G |
| C1 (S0) | No autonomous runtime verification exists | track H |

## 7. Tracker audit

**Open issues (329).** Full ledger: `ISSUE_LEDGER.tsv` (one row per issue: class, cluster, fix state, disposition, the automated check that would decide it).

| Verification class | Count | Meaning |
|---|---|---|
| R | 190 | A script inside the running game can read state and decide |
| S | 40 | A static check decides |
| U | 20 | A unit test decides |
| C | 42 | Needs two real clients (most have a scripted solo part) |
| V | 26 | Needs human eyes or ears (each has a machine sub-check) |
| X | 11 | Blocked, unbuilt, or an owner decision |

| Disposition | Count |
|---|---|
| Keep and verify (fix shipped, unverified) | 228 |
| Close now on static or offline evidence | 33 |
| Keep and fix (code wrong or missing) | 26 |
| Owner decision | 23 |
| Merge into another issue | 12 |
| Decline (not planned or out of scope) | 7 |

- The 329 issues fall into 131 clusters; 51 clusters have three or more members. One script family per cluster decides most of them (for example: one two-client husk harness covers 11 issues; one Blightreaper script decides 6 of 8; boot, keep commands and one mission load reach 19 Chaos Wastes issues).
- Reporters: 305 owner, 19 RainReligion, 5 external. All five external reports were assessed: #1211, #1190, #1465 and #1796 are real bugs; #1817 (ten players) is a feature request outside a tweaker mod's scope.
- Labels are unreliable in every bucket: 29 of 71 CWV issues are `0-critical` but 8 have crash evidence; seven `verify-fix` cosmetics issues have bodies that say "not ready"; shipped fixes sit under `not-started`.
- 24 umbrella issues cannot pass or fail a test and should become milestones or checklists (D5).

**Closed issues (613).** Full ledger: `CLOSED_LEDGER.tsv`.

- Closing mechanism: 586 manual, 20 commit keyword, 7 pull-request merge. The auto-closes all fall between 2026-07-02 and 07-19; none since the guard landed. The burst days were agents sweeping issues the owner had labelled fixed (36 closed in 45 seconds on 07-19).
- Of 384 closed-completed runtime issues: 296 have an in-game confirmation (102 of those exist only as an agent's sentence), 11 have real-session logs, 31 static evidence only, 35 nothing. So 66 were never verified at runtime, 18 of them crash-class.
- Recommendations: 1 reopen (#406), 56 re-verify through the rig as regression entries, 70 link to the open issue that tracks the same symptom, 486 leave closed.
- One verified fix is no longer on master (#568, rewritten under open #1684 and #573). 44 other crash fixes checked are present.

## 8. Can verification be automated? Findings and experiments

The owner's two stated concerns were: a fully autonomous process, and a way to know that what exists works without a person playing. The audit answered them in two steps: desk research (stream C1), then experiments on the author machine once the game finished installing.

### 8.1 What the game offers (desk research, all cited in `evidence/C1.md`)

- The retail game ships Fatshark's own test framework and its handler files. They show unguarded engine calls for loading a level, choosing a hero, equipping items, spawning enemies and pickups, adding buffs, teleporting, opening views, and ending a level.
- Mod code can compile Lua text at run time (`loadstring`), run any mod's chat command without typing (the framework's `run_command`), read the command line, write a results table through the user-settings file, and quit the game cleanly.
- A boot from process start to the keep took 67 seconds in the owner's last session with 27 mods; a mission load takes 42 to 73 seconds. A full pass over the scriptable backlog is about two hours of unattended machine time. Writing the scripts is the real cost.
- Retail has no LAN or offline mode and peer identity is the Steam account, so real co-op needs two accounts on two machines.
- File writes (`io`) are removed from the retail Lua environment. Evidence leaves the game through the console log and the user-settings file.

### 8.2 What was proven on 2026-11-13 and 2026-11-14

| # | Question | Result |
|---|---|---|
| 1 | Does the retail game start without the launcher? | **Yes.** `vermintide2_dx12.exe -eac-untrusted --bundle-dir ../bundle --ini settings --silent-mode -skip-splash` with `SteamAppId=552500` in the child environment. The log shows the modded realm. |
| 2 | Can a run be kept away from the owner's settings and saves? | **Yes.** With child-only `USERPROFILE`, `APPDATA` and `LOCALAPPDATA` the game reads and writes a rig profile. Hashes of the owner's settings, save and launcher files were identical before and after every run. |
| 3 | Can a run be invisible? | **Yes.** On a private desktop no window of the game reached the user desktop during a 540-second run. |
| 4 | Does the game get past the title screen with no key press? | **Yes** as far as network sign-in with `-skip-splash`; the 6.13 main menu then needs the driver's bypass (one settings flag, cited). |
| 5 | Can the rig load its own code without a Workshop upload per change? | **Yes, with one correction to earlier project belief.** The game ignores a Workshop folder that Steam does not list as subscribed, so "synthetic" local folders do not work. The rig therefore uses one tiny private Workshop item (a constant bootstrap file, published once) and sends the driver and every test script as text in the run plan. |
| 6 | Can Workshop items be created and subscribed with no GUI? | **Yes.** The SDK tool creates the item; the game's own Steam library subscribes and installs it (`steam-ugc.ps1`). No browser cookies, no Steam restart. |
| 7 | Is the console log usable as a live signal? | **No.** It is buffered and a killed process loses its tail. The driver therefore writes progress checkpoints through the settings file, and verdicts are trusted only after a clean exit. |
| 8 | Does the driver reach the keep, run a case and quit by itself? | **Yes.** Three runs on 2026-11-14 (`smoke-keep-4b32903a`, `-5f5ca4b0`, `-9d23f887`), private desktop, VMF and the driver only: the game reached the keep 54 to 62 seconds after process start, the case passed 5 of 5 assertions, the driver printed `RUN END`, and the game closed by itself within 4 seconds more; the isolation check was OK each time. The runs also settled three things. A clean modded-realm exit reports code `0xFA730001`, not 0. The game sends one routine save about 5 seconds after the keep loads, in the owner's own sessions too; it carries only the keep-painting layout, unchanged. The first run installed the write shield after that save, so the driver now installs it at the title screen and answers that save as well: the third run sent no save at all. |

Prototype and run records: `rig/` and `evidence/rig-runs/` in this audit folder. The harness track of the plan (`docs/program/wp/H.md`) turns the prototype into a tested tool and lists what is still unproven: mission and Chaos Wastes arenas, stills from a private desktop, and two-machine co-op. Every rig run signs in to the owner's real game account, exactly as a normal start does; what the rig holds back there, and what is proven about it, is in `WP-H-14`.

### 8.3 What this buys

| Population | Count | What the rig does |
|---|---|---|
| Open issues, class R | 190 | A script reads engine state and decides. One script family per cluster. |
| Open issues, class S and U | 60 | Decided offline; 33 are closable today. |
| Open issues, class C | 42 | The solo part is scripted now; the two-client part needs the second machine or a human. |
| Open issues, class V | 26 | The rig supplies stills and state dumps so a human judges only what needs judging. |
| In-game regression checks | 792 | All run on every boot instead of never. |
| Closed issues never verified at runtime | 66 | Become regression entries; a failure opens a new issue. |

### 8.4 Limits, stated plainly

A rig PASS means: the scripted steps produced the stated engine state, in a lean profile, on this game build. It does not mean the feature is pleasant, complete, or correct with the owner's full third-party mod list. Motion quality, timing, sound, fine colour and real network behaviour stay with humans. The wording of machine evidence is fixed accordingly (plan rule R7).

### 8.5 Test infrastructure as measured (stream B2)

- The engine-free Lua suite passes: 584 suites, 7,537 cases, 3 minutes 16 seconds. It executes 43% of logic lines, but 11 of the 15 mod entry files, where the 1,064 hooks are wired, are never loaded offline.
- `qa/run_all.ps1 -Quick` fails today (exit 2 after 7 minutes 19 seconds) because one gate scans a git-ignored scratch folder.
- Of the 792 in-game checks, 3.9% read live session state, 22.5% read engine data tables, 42% are pure-logic self-tests that could run offline, 20% test that something exists, and 10% compare a marker string. Several cannot fail.
- 70 of the 107 QA gates, 75% of their lines, guard process paperwork rather than product behaviour.
- 81% of the `verify-fix` issues already have an offline test and 73% of their cards name a PASS line, yet all wait for a human, because issues carry no verification class. In ten sampled cards 86% of the steps were assertable from state and about 2% needed eyes.
- An experiment with the Lua interpreter the repository already vendors loaded 743 real vanilla data files in half a second with 86 stubs (`ItemMasterList` 2,979 entries, `Weapons` 183, `BuffTemplates` 1,547) and validated 930 Weapon Tweaker unlock rows against them. An engine-free integration tier on real game data is practical; the plan adds it (`WP-T-03`).

## 9. Recommendations

| # | Recommendation | Plan track |
|---|---|---|
| 1 | Build the unattended test rig and run every existing in-game suite on every boot | H |
| 2 | Adopt machine evidence: classes U, S and R close issues; V and C go to a short human list with stills and state dumps; stop manual test cards | G |
| 3 | Fix the S0 defects first, each with an offline test before the fix, player-data paths before everything | family tracks |
| 4 | Close, merge or decline the 52 issues that need no game | B (packs D1 to D5, "No rig needed") |
| 5 | Burn the backlog down by cluster with scripted verification packs; fix what fails; re-verify the 66 unverified closures as regression entries | B |
| 6 | Test before shipping: the rig runs local builds from a synthetic Workshop folder, so verification no longer needs an upload | H, P |
| 7 | Replace the release pipeline with one resumable command with a machine-readable result; remove the per-ship bookkeeping pull request; stop tracking compiled bundles; add a rollback verb | P |
| 8 | One source tree per mod; stable built from a tag. Reconcile the diverged forks deliberately (Chaos Wastes last) | P, CW, GT, GUT |
| 9 | Give each piece of shared state one owner: loadout store, appearance decision, animation remap, lookup-table appends | family tracks |
| 10 | Make errors visible: no swallowed callbacks, guards observable and switchable, regression suites print one machine-readable line per check | family tracks, T |
| 11 | Add a patch-day canary: hook targets resolve, atlas names exist, lookup tables stable, boot-to-keep smoke | T, H |
| 12 | Shrink the rule surface: one 6 KB agent entry, runbooks backed by scripts, generated inventories, decision records; import project knowledge from the private memory store into the repository | G |
| 13 | Decide the unbuilt scope: modded_progression and career_tweaker get a written spec and a test per slice before more code | CIM |

## 10. Risks to the program

| Risk | Mitigation |
|---|---|
| The rig cannot do what the design assumes | The cheapest design-killing experiments were run first (section 8). Each remaining unknown has a named fallback. |
| A rig run disturbs the owner's settings, saves or desktop | Isolated profile, private desktop, before-and-after hashes of the real profile, one instance at a time, kill-on-close job. |
| A game patch invalidates results | Record the build id in every run; run the canary first after a patch. |
| Weaker agents break the pipeline while simplifying it | Pipeline cards are ordered so shipping keeps working after each one; no big-bang. |
| Many agents work at once and collide | One claim mechanism (a draft pull request per card), worktrees only, never the shared checkout. |
| Rig PASS is over-read as "works" | Evidence wording is fixed: "auto-verified (R) on version and commit, run id". Visual and co-op remainders stay listed for humans. |
| The S0 player-data defects cause loss before they are fixed | They are the first cards; crafting auto-equip and the snapshot path get offline reproductions before any other work. |

## 11. Appendices

- **A. Sub-reports.** `evidence/A1.md` to `E1.md`: scope and coverage, architecture as built, feature inventory with a verification class per feature, numbered findings with evidence, testability seams, and work items.
- **B. Ledgers.** `ISSUE_LEDGER.tsv` (329 rows), `CLOSED_LEDGER.tsv` (613 rows), `evidence/data/FINDINGS_REGISTER.tsv`.
- **C. Measurements.** `evidence/data/F1_metrics.txt` (per-mod counts), `F1_pairs.txt` (dev/stable drift), `F1_hooks.txt` (engine functions hooked by several mods).

Findings by stream:

| Stream | S0 | S1 | S2 | S3 | Total |
|---|---|---|---|---|---|
| A1 | 0 | 4 | 12 | 3 | 19 |
| A2 | 1 | 7 | 13 | 3 | 24 |
| A3 | 0 | 5 | 13 | 3 | 21 |
| A4 | 3 | 7 | 8 | 4 | 22 |
| A5 | 3 | 5 | 11 | 5 | 24 |
| A6 | 0 | 7 | 11 | 5 | 23 |
| A7 | 0 | 5 | 11 | 5 | 21 |
| B1 | 2 | 7 | 8 | 4 | 21 |
| B2 | 1 | 7 | 5 | 2 | 15 |
| C1 | 1 | 3 | 5 | 1 | 10 |
| D1 | 2 | 4 | 2 | 0 | 8 |
| D2 | 1 | 3 | 3 | 0 | 7 |
| D3 | 1 | 3 | 1 | 0 | 5 |
| D4 | 2 | 3 | 4 | 1 | 10 |
| D5 | 0 | 4 | 6 | 2 | 12 |
| D6 | 1 | 5 | 6 | 3 | 15 |
| E1 | 2 | 7 | 11 | 3 | 23 |
| **Total** | **20** | **86** | **130** | **44** | **280** |
