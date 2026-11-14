# CLOSED: action lists for closed issues

Source: closed-issue audit D6 (`docs/audits/2026-11-13_FORMAL_AUDIT/evidence/D6.md`, `docs/audits/2026-11-13_FORMAL_AUDIT/CLOSED_LEDGER.tsv`), repo state `origin/master` = `592253d1`, 2026-11-13.
Audience: an executing agent with only this file. Nothing here has been posted or changed on GitHub. Each part says what to post or script.

Rules that apply to every part:
- A closed issue stays closed unless Part 1 names it.
- Never write a closing keyword (`fixes`, `closes`, `resolves`) next to an issue number in any comment or PR text you produce from this file.
- Evidence classes are the ones in `docs/program/CONVENTIONS.md` section 2. Report a rig PASS as "auto-verified (R) on <mod> <version> <commit>, run <id>", never as "works".
- Dev/stable pairs: the scripts in Part 3 target the `_dev` build unless the card says otherwise. Part 4 lists the fixes that the stable tree does not have.

## Part 1. REOPEN

One issue. I do not stand behind any other reopen: every other unverified closed issue has its fix on master and can be decided by a script (Part 3).

### #406 ct: client CTD on kill with kill-heal boon

Why: the owner's last verdict was negative, a new fix shipped 29 minutes later, and the PR merge closed the issue 5 minutes after that. Nobody tested the new fix. Timeline (UTC, from the issue's label and comment events): 2026-07-19 00:02 owner comment; 00:31 agent comment "Shipped a CT dev fix" (ct_dev 0.7.295-dev); 00:36 closed by the merge of PR 808.

Action 1: reopen the issue.

Action 2: post this comment (87 words):

```
**Symptom:** Reopened by the 2026-11-13 closed-issue audit. The kill-heal boon (`ct_kill_heal`, Khaine's Communion) was reported not functional, and the client crash this issue tracks was never retested after the last change.

**Evidence:** Owner, 2026-07-19: "The boon isn't functional." A new fix (ct_dev 0.7.295-dev, `[ct:406]` receipts in `_ct_meta_trait_boons.lua`) shipped 29 minutes later. The merge of PR 808 closed this issue 5 minutes after that. No test followed. The code exists only in `chaos_wastes_tweaker_dev`; `chaos_wastes_tweaker` has no `[ct:406]` line.

**Refs:** #426 (wire-safety umbrella), audit finding D6-F01, verification card VP-CL-03.
```

Action 3: labels. Keep `bug`, `crash`, `Tweaker: Chaos Wastes`, `0-critical`, `coop-required`. Replace the lifecycle label `verify-fix` with `not-started` in ONE `gh issue edit` call that adds `not-started` and removes `verify-fix` together (`PROJECT_STANDARDS.md:2533`). Reason: `verify-fix` requires a current live-test card for the deployed build (`PROJECT_STANDARDS.md` section 11, lines 2304 to 2320) and the newest card on the issue predates the last fix. Move it back to `verify-fix` only when VP-CL-03 case `issue_406_kill_heal_host.lua` exists and has run.

What closes it again: the solo host case in VP-CL-03 is class R and proves the boon heals on the host. The reported crash is on a client, which is class C. Under the conventions the issue cannot close on machine evidence until a two-machine rig run exists; until then it stays open with `coop-required`.

Not reopened, and why (so nobody re-litigates):

| Issue | Why it stays closed |
|---|---|
| #731 (0-critical, PR auto-close, never tested) | Fix is on master and an offline unit test already covers the gate: `qa/lua/tests/test_gt_voip_disconnect_policy.lua`. Class U. See VP-CL-01. |
| #372, #157, #294, #59 (crash-class, no runtime evidence) | Fix is on master; each has a scripted assertion in Part 3. A FAIL there opens a new regression issue. |
| #182, #196, #154, #401, #697 (0-critical, closed into umbrellas) | The symptom is owned by an open issue (#748, #660). They need the cross-reference in Part 2, not a reopen. |
| #534 (owner closed with "no change") | Owner decision on a dev-tool enhancement. Only the close reason is wrong (`completed` should be `not_planned`). |

## Part 2. LINK (closed issues whose symptom an OPEN issue already owns)

70 closed issues map onto 47 open issues. Post ONE comment per open issue, using the text block under its table. Do not reopen any closed issue in this part. Do not edit labels.

How each closed issue ended: `completed` rows were closed as fixed; `not_planned` and `duplicate` rows were consolidated. "Evidence" is the round 1 evidence class of the closed issue (A = human in-game confirmation, B = session log, C = static only, D = none, n-a = not a runtime fix).

### Open #948 Universal weapon compatibility matrix (0-critical, diagnostics-armed): 4 closed predecessors

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #109 Audit Kruber Cross-Character Weapon Coverage (not_planned 2026-07-22, evidence n-a) | #948 | superseded by open #948 (universal weapon compatibility matrix) |
| #110 Audit Bardin Cross-Character Weapon Coverage (not_planned 2026-07-22, evidence n-a) | #948 | superseded by open #948 (universal weapon compatibility matrix) |
| #111 Audit Kerillian Cross-Character Weapon Coverage (not_planned 2026-07-22, evidence n-a) | #948 | superseded by open #948 (universal weapon compatibility matrix) |
| #113 Audit Warrior Priest Cross-Character Coverage (not_planned 2026-07-22, evidence n-a) | #948 | superseded by open #948 (universal weapon compatibility matrix) |

Comment to post on #948:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #109 (closed not planned 2026-07-22): superseded by this issue (universal weapon compatibility matrix)
- #110 (closed not planned 2026-07-22): superseded by this issue (universal weapon compatibility matrix)
- #111 (closed not planned 2026-07-22): superseded by this issue (universal weapon compatibility matrix)
- #113 (closed not planned 2026-07-22): superseded by this issue (universal weapon compatibility matrix)
Their acceptance is owed here. They stay closed.
```

### Open #282 cross-mod: weapon _3p package refcount leak (0-critical, verify-fix): 3 closed predecessors

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #927 Log for Issues (not_planned 2026-07-21, evidence n-a) | #282 | log container; recurrence routed to reopened #282 |
| #937 Log Career Tweaker Testing (not_planned 2026-07-21, evidence n-a) | #282 | log container -> reopened #282 |
| #940 test log (not_planned 2026-07-21, evidence n-a) | #282 | log container -> reopened #282 |

Comment to post on #282:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #927 (closed not planned 2026-07-21): log container; recurrence routed to this issue
- #937 (closed not planned 2026-07-21): log container -> this issue
- #940 (closed not planned 2026-07-21): log container -> this issue
Their acceptance is owed here. They stay closed.
```

### Open #474 CWV: Old Musket pose calibration and peer parity (0-critical, diagnostics-armed): 3 closed predecessors

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #409 cwv: Old Musket mis-posed on inventory preview only (completed 2026-07-07, evidence D) | #474 | Old Musket leaf consolidated into open #474; never verified (commit auto-close) |
| #484 Yet more CWV Musket issues (completed 2026-07-18, evidence n-a) | #474 | consolidated into open #474 (Old Musket umbrella) |
| #792 [CWV] Old Musket preview loses idle (not_planned 2026-07-22, evidence n-a) | #474 | sub-issue of open #474 |

Comment to post on #474:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #409 (closed as fixed 2026-07-07): Old Musket leaf consolidated into this issue; never verified (commit auto-close)
- #484 (closed as fixed 2026-07-18): consolidated into this issue (Old Musket umbrella)
- #792 (closed not planned 2026-07-22): sub-issue of this issue
Their acceptance is owed here. They stay closed.
```

### Open #660 Critical: Unify Appearance Across Render Surfaces (0-critical, not-started): 3 closed predecessors

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #154 Synchronize Cross-Character Weapon Cosmetics (duplicate 2026-08-04, evidence n-a) | #660 | marked duplicate of open #660 on GitHub (#660 is a blocked umbrella) |
| #401 Imperial Axe+Shield reverts to dwarf base model (duplicate 2026-08-04, evidence n-a) | #660 | marked duplicate of open #660 on GitHub (#660 is a blocked umbrella) |
| #697 Husk hat LA paint step fails nil (duplicate 2026-08-03, evidence n-a) | #660 | marked duplicate of open #660 on GitHub; owner retest 2026-08-03: the victory-screen hat was still the vanilla hat |

Comment to post on #660:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #154 (closed as duplicate 2026-08-04): marked duplicate of this issue on GitHub (this issue is a blocked umbrella)
- #401 (closed as duplicate 2026-08-04): marked duplicate of this issue on GitHub (this issue is a blocked umbrella)
- #697 (closed as duplicate 2026-08-03): marked duplicate of this issue on GitHub; owner retest 2026-08-03: the victory-screen hat was still the vanilla hat
Their acceptance is owed here. They stay closed.
```

### Open #661 Career abilities fail with modded weapons (0-critical, verify-fix): 2 closed predecessors

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #930 Log CWV tests (not_planned 2026-07-21, evidence n-a) | #661 | log container -> open #661 (still-failing CWV Greataxe/Crowbill cases) |
| #933 Log for more testing. (not_planned 2026-07-21, evidence n-a) | #661 | duplicate log container of #930 -> open #661 |

Comment to post on #661:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #930 (closed not planned 2026-07-21): log container -> this issue (still-failing CWV Greataxe/Crowbill cases)
- #933 (closed not planned 2026-07-21): duplicate log container of #930 -> this issue
Their acceptance is owed here. They stay closed.
```

### Open #914 Randomly while playing CWV items will lose their current model/skin. (0-critical, verify-fix): 2 closed predecessors

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #741 Retire cwv skin parity gate: null unconditionally (not_planned 2026-07-22, evidence n-a) | #914 | consolidated into open #914 (closing comment: explicitly NOT a fixed claim) |
| #945 Logs (not_planned 2026-07-21, evidence n-a) | #914 | log container -> open #914 |

Comment to post on #914:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #741 (closed not planned 2026-07-22): consolidated into this issue (closing comment: explicitly NOT a fixed claim)
- #945 (closed not planned 2026-07-21): log container -> this issue
Their acceptance is owed here. They stay closed.
```

### Open #233 Reapply late Loremaster husk meshes (0-critical, verify-fix): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #267 cosmetics/LA: hot-join gets NO existing state - and the join-time rebr (completed 2026-07-06, evidence A) | #233 | open #233 (0-critical): exact lifecycle recurrence of #267 hot-join LA state |

Comment to post on #233:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #267 (closed as fixed 2026-07-06): reported here: exact lifecycle recurrence of #267 hot-join LA state
Their acceptance is owed here. They stay closed.
```

### Open #279 Crafted CWV items render merged models (0-critical, verify-fix): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #390 CIM crafts CWV weapons as base vanilla item (completed 2026-07-13, evidence A) | #279 | open #279 (0-critical): sweep claim that #390 fixed crafted-CWV identity was never tested against a build |

Comment to post on #279:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #390 (closed as fixed 2026-07-13): reported here: sweep claim that #390 fixed crafted-CWV identity was never tested against a build
Their acceptance is owed here. They stay closed.
```

### Open #389 Weapon power slider not stepping by 25 (gut) (0-critical, verify-fix): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #826 [CT] Snap trial cost to 25 coins (duplicate 2026-07-20, evidence n-a) | #389 | marked duplicate of open #389 on GitHub |

Comment to post on #389:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #826 (closed as duplicate 2026-07-20): marked duplicate of this issue on GitHub
Their acceptance is owed here. They stay closed.
```

### Open #402 Modded loadouts leak into official realm (0-critical, verify-fix): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #174 Bot loadout replaced on startup by base blacksmith (5-power) items in  (completed 2026-07-03, evidence A) | #402 | closed at owner direction ("no longer considered an active problem"); open #402 documents residual corrupted cloud data. |

Comment to post on #402:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #174 (closed as fixed 2026-07-03): closed at owner direction ("no longer considered an active problem"); this issue documents residual corrupted cloud data.
Their acceptance is owed here. They stay closed.
```

### Open #413 Shadow mutator crashes Adventure clients (0-critical, verify-fix): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #803 [Events] Make Shadow mutator work in Adventure (not_planned 2026-07-19, evidence n-a) | #413 | feature half of open #413 |

Comment to post on #413:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #803 (closed not planned 2026-07-19): feature half of this issue
Their acceptance is owed here. They stay closed.
```

### Open #491 CWV pairing skins crash non-CWV peers (0-critical, verify-fix): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #495 cwv skins leak on resync and equipment RPCs (completed 2026-07-14, evidence A) | #491 | verified by the user in two-player testing. open #491 tracks the residual pairing-skin wire leak |

Comment to post on #491:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #495 (closed as fixed 2026-07-14): verified by the user in two-player testing. this issue tracks the residual pairing-skin wire leak
Their acceptance is owed here. They stay closed.
```

### Open #592 CWV must provide exactly one 5-power Blacksmith seed per weapon (0-critical, verify-fix): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #928 Blacksmith Quality CWV item instances missing (not_planned 2026-07-21, evidence n-a) | #592 | consolidated into reopened #592 |

Comment to post on #592:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #928 (closed not planned 2026-07-21): consolidated into this issue
Their acceptance is owed here. They stay closed.
```

### Open #624 CIM restore Keep forge interaction (0-critical, verify-fix): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #1689 cim Keep forge blocked again since 6.12.0 (duplicate 2026-11-13, evidence n-a) | #624 | marked duplicate of reopened #624 on GitHub |

Comment to post on #624:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #1689 (closed as duplicate 2026-11-13): marked duplicate of this issue on GitHub
Their acceptance is owed here. They stay closed.
```

### Open #712 Blightreaper missing -90 rotations and Z offset (0-critical, diagnostics-armed): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #958 Blightreaper Regression (not_planned 2026-07-21, evidence n-a) | #712 | duplicate of open #712 (Blightreaper offsets lost again) |

Comment to post on #712:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #958 (closed not planned 2026-07-21): duplicate of this issue (Blightreaper offsets lost again)
Their acceptance is owed here. They stay closed.
```

### Open #786 [CWV] Combat Style switch hides remote weapons (0-critical, verify-fix): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #620 Add per-item combat style switching (completed 2026-07-16, evidence A) | #786 | open #786 (0-critical) and #657: style switch hides remote weapon; regression in the controller shipped under #620 |

Comment to post on #786:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #620 (closed as fixed 2026-07-16): this issue (0-critical) and #657: style switch hides remote weapon; regression in the controller shipped under #620
Their acceptance is owed here. They stay closed.
```

### Open #807 [CWV] Kruber Rapier crashes HUD on equip (0-critical, verify-fix): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #789 [CWV] Kruber Rapier shows offhand pistol (not_planned 2026-07-19, evidence n-a) | #807 | subsumed by open #807 |

Comment to post on #807:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #789 (closed not planned 2026-07-19): subsumed by this issue
Their acceptance is owed here. They stay closed.
```

### Open #822 [WOC] Blightreaper missing and exposed in Athanor (0-critical, verify-fix): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #793 [cross-mod] Exclude Blightreaper from Athanor menu (not_planned 2026-07-19, evidence n-a) | #822 | subset of open #822 |

Comment to post on #822:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #793 (closed not planned 2026-07-19): subset of this issue
Their acceptance is owed here. They stay closed.
```

### Open #919 Profile settings failure. Chaos Wastes (0-critical, diagnostics-armed): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #920 Single-Mission-Loader - No Curse? (not_planned 2026-07-21, evidence n-a) | #919 | consolidated into open #919 |

Comment to post on #919:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #920 (closed not planned 2026-07-21): consolidated into this issue
Their acceptance is owed here. They stay closed.
```

### Open #80 Enable In-Mission HeroView Crafting (1-major, verify-fix): 2 closed predecessors

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #83 Crafting in Modded v0.8.7 - Crash in map when opening the UI (completed 2026-07-19, evidence A) | #80 | open #80/#404 record recurrence (dynamic list widgets not covered); #83 was reopened twice |
| #710 Athanor weapon list crashes on arch material (not_planned 2026-07-17, evidence n-a) | #80 | same crash signature as #83; recurrence tracked on open #80/#404 |

Comment to post on #80:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #83 (closed as fixed 2026-07-19): this issue/#404 record recurrence (dynamic list widgets not covered); #83 was reopened twice
- #710 (closed not planned 2026-07-17): same crash signature as #83; recurrence tracked on this issue/#404
Their acceptance is owed here. They stay closed.
```

### Open #102 Prevent Temper Altar Rarity Escalation (1-major, verify-fix): 2 closed predecessors

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #100 ct_dev: bot weapon-upgrade mirror gives bots one rarity tier ABOVE hos (completed 2026-07-04, evidence A) | #102 | open #102: re-arm rarity bump regression of the #100/#103 fix |
| #103 ct_dev: multi-use temper (upgrade) altar still flips to the 'used-up'/ (completed 2026-07-03, evidence A) | #102 | open #102: keep-lit altar fix overwrites rarity one tier high (fix incomplete) |

Comment to post on #102:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #100 (closed as fixed 2026-07-04): reported here: re-arm rarity bump regression of the #100/#103 fix
- #103 (closed as fixed 2026-07-03): reported here: keep-lit altar fix overwrites rarity one tier high (fix incomplete)
Their acceptance is owed here. They stay closed.
```

### Open #738 Host cosmetics skipped as bot alias on husks (1-major, verify-fix): 2 closed predecessors

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #513 Model/Husk score screen doesn't have the loremaster override skin on. (completed 2026-07-14, evidence A) | #738 | open #738: #513 owner-alias boundary keys on peer id alone |
| #698 Husk repaints GK armor on Foot Knight (completed 2026-07-19, evidence A) | #738 | open #738: host cosmetics skipped; regression introduced by the #698 fix |

Comment to post on #738:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #513 (closed as fixed 2026-07-14): reported here: #513 owner-alias boundary keys on peer id alone
- #698 (closed as fixed 2026-07-19): reported here: host cosmetics skipped; regression introduced by the #698 fix
Their acceptance is owed here. They stay closed.
```

### Open #290 Restore missing WT cross-character animations (1-major, verify-fix): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #319 Axe+Falchion on Kruber; Larger Issue FAILING TO GET ANIMATIONS PROPERL (completed 2026-07-06, evidence A) | #290 | open #290: same anim-picker config symptom recurring in wt 0.12.201-dev |

Comment to post on #290:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #319 (closed as fixed 2026-07-06): reported here: same anim-picker config symptom recurring in wt 0.12.201-dev
Their acceptance is owed here. They stay closed.
```

### Open #299 Chest of Trials Revive Teleport Fail (1-major, verify-fix): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #116 ct_dev: 'Revive Team on Chest Completion' does not work (must respawn  (completed 2026-07-03, evidence A) | #299 | open #299: chest revive leaves player at respawn point |

Comment to post on #299:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #116 (closed as fixed 2026-07-03): reported here: chest revive leaves player at respawn point
Their acceptance is owed here. They stay closed.
```

### Open #377 Add contextual glow editor and icon badge (1-major, verify-fix): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #926 Glow Menu Changes (not_planned 2026-07-21, evidence n-a) | #377 | consolidated into reopened #377 |

Comment to post on #377:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #926 (closed not planned 2026-07-21): consolidated into this issue
Their acceptance is owed here. They stay closed.
```

### Open #404 Restore Athanor trait/property picker pools (1-major, verify-fix): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #539 Mid-mission Customize crashes: gsub on nil ItemId (completed 2026-07-14, evidence A) | #404 | crash scope verified; remaining Athanor panel defects tracked on open #404 |

Comment to post on #404:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #539 (closed as fixed 2026-07-14): crash scope verified; remaining Athanor panel defects tracked on this issue
Their acceptance is owed here. They stay closed.
```

### Open #450 Boss Balance Toggles (1-major, verify-fix): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #531 Hook remaining behavioral boss controls (not_planned 2026-07-19, evidence n-a) | #450 | subsumed by open #450 |

Comment to post on #450:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #531 (closed not planned 2026-07-19): subsumed by this issue
Their acceptance is owed here. They stay closed.
```

### Open #471 Fix Chest of Trials spawn multiplier (1-major, verify-fix): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #64 ct: optional setting to increase enemy spawns from Chests of Trials (completed 2026-06-13, evidence C) | #471 | open #471: shipped Chest-of-Trials spawn multiplier reported ineffective |

Comment to post on #471:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #64 (closed as fixed 2026-06-13): reported here: shipped Chest-of-Trials spawn multiplier reported ineffective
Their acceptance is owed here. They stay closed.
```

### Open #632 Make Blightreaper a cursed Shyish relic (1-major, not-started): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #643 WOC: add native Shyish death spirits to Blightreaper kills (not_planned 2026-07-17, evidence n-a) | #632 | duplicate of open #632 |

Comment to post on #632:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #643 (closed not planned 2026-07-17): duplicate of this issue
Their acceptance is owed here. They stay closed.
```

### Open #682 CIM cannot craft weapons, accessories only (1-major, verify-fix): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #22 cim: equipped loadout (modded weapons + LA cosmetics) not fully restor (completed 2026-06-04, evidence A) | #682 | open #682: modded loadout restore reports modded_loadout_entries=0 on cim 0.8.87-dev |

Comment to post on #682:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #22 (closed as fixed 2026-06-04): reported here: modded loadout restore reports modded_loadout_entries=0 on cim 0.8.87-dev
Their acceptance is owed here. They stay closed.
```

### Open #700 In-mission mission vote shows no client popup (1-major, verify-fix): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #305 Mission Selection during Mission (completed 2026-07-13, evidence A) | #700 | open #700: in-mission vote dead-ends in co-op (clients get no popup) |

Comment to post on #700:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #305 (closed as fixed 2026-07-13): reported here: in-mission vote dead-ends in co-op (clients get no popup)
Their acceptance is owed here. They stay closed.
```

### Open #1684 mp eac-untrusted brackets inert since game 6.12.0 (1-major, diagnostics-armed): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #568 Modded Progression: simulated daily claim calls PlayFab and forces gam (completed 2026-07-13, evidence A) | #1684 | verified by the project owner on mp 0.2.18-dev, but that code has since been rewritten. original fix identifiers gone (19/39); daily-claim code rewritten under open #1684/#573 |

Comment to post on #1684:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #568 (closed as fixed 2026-07-13): verified by the project owner on mp 0.2.18-dev, but that code has since been rewritten. original fix identifiers gone (19/39); daily-claim code rewritten under this issue/#573
Their acceptance is owed here. They stay closed.
```

### Open #748 Validate WT animation-picker target vocabularies (2-moderate, verify-fix): 6 closed predecessors

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #161 Restore Saltzpyre Polearm Animations (not_planned 2026-07-21, evidence n-a) | #748 | weapon-specific animation leaf subsumed by open umbrella #748 (closing comment: shared 3P vocabulary architecture still broken) |
| #178 Fix Kruber Rapier animations (not_planned 2026-07-21, evidence n-a) | #748 | weapon-specific animation leaf subsumed by open umbrella #748 (closing comment: shared 3P vocabulary architecture still broken) |
| #180 Retune Kruber Greathammer animations (not_planned 2026-07-21, evidence n-a) | #748 | weapon-specific animation leaf subsumed by open umbrella #748 (closing comment: shared 3P vocabulary architecture still broken) |
| #182 Retune Kruber Cog Hammer animations (not_planned 2026-07-21, evidence n-a) | #748 | weapon-specific animation leaf subsumed by open umbrella #748 (closing comment: shared 3P vocabulary architecture still broken) |
| #184 Add Kruber ranged animation tuning (not_planned 2026-07-21, evidence n-a) | #748 | weapon-specific animation leaf subsumed by open umbrella #748 (closing comment: shared 3P vocabulary architecture still broken) |
| #196 Fix Billhook charge animation vocabulary (not_planned 2026-07-21, evidence n-a) | #748 | weapon-specific animation leaf subsumed by open umbrella #748 (closing comment: shared 3P vocabulary architecture still broken) |

Comment to post on #748:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #161 (closed not planned 2026-07-21): weapon-specific animation leaf subsumed by open umbrella this issue (closing comment: shared 3P vocabulary architecture still broken)
- #178 (closed not planned 2026-07-21): weapon-specific animation leaf subsumed by open umbrella this issue (closing comment: shared 3P vocabulary architecture still broken)
- #180 (closed not planned 2026-07-21): weapon-specific animation leaf subsumed by open umbrella this issue (closing comment: shared 3P vocabulary architecture still broken)
- #182 (closed not planned 2026-07-21): weapon-specific animation leaf subsumed by open umbrella this issue (closing comment: shared 3P vocabulary architecture still broken)
- #184 (closed not planned 2026-07-21): weapon-specific animation leaf subsumed by open umbrella this issue (closing comment: shared 3P vocabulary architecture still broken)
- #196 (closed not planned 2026-07-21): weapon-specific animation leaf subsumed by open umbrella this issue (closing comment: shared 3P vocabulary architecture still broken)
Their acceptance is owed here. They stay closed.
```

### Open #645 Expand Reciprocal Combat Style Families (2-moderate, diagnostics-armed): 4 closed predecessors

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #1026 Add four cross-character weapon style swaps (not_planned 2026-08-02, evidence n-a) | #645 | consolidated into open #645 |
| #1027 Add Kruber mace style to Kruber sword (not_planned 2026-07-27, evidence n-a) | #645 | consolidated into #1026 -> open #645 |
| #1028 Add Kruber sword style to Kerillian sword (not_planned 2026-07-27, evidence n-a) | #645 | consolidated into #1026 -> open #645 |
| #1029 Add Tuskgor spear style to Kerillian spear (not_planned 2026-07-27, evidence n-a) | #645 | consolidated into #1026 -> open #645 |

Comment to post on #645:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #1026 (closed not planned 2026-08-02): consolidated into this issue
- #1027 (closed not planned 2026-07-27): consolidated into #1026 -> this issue
- #1028 (closed not planned 2026-07-27): consolidated into #1026 -> this issue
- #1029 (closed not planned 2026-07-27): consolidated into #1026 -> this issue
Their acceptance is owed here. They stay closed.
```

### Open #717 Mod Tweaker entries lost text colors (2-moderate, verify-fix): 2 closed predecessors

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #611 Add weapon-availability master toggles (completed 2026-07-19, evidence A) | #717 | open #717: renderer-twin parity regression of #611 |
| #694 Remove lifecycle tags from player UI (completed 2026-07-18, evidence n-a) | #717 | open #717: the #694 tag-strip also removed entry colours |

Comment to post on #717:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #611 (closed as fixed 2026-07-19): reported here: renderer-twin parity regression of #611
- #694 (closed as fixed 2026-07-18): reported here: the #694 tag-strip also removed entry colours
Their acceptance is owed here. They stay closed.
```

### Open #25 cosmetics_tweaker: persist LA cosmetics + per-instance weapon illusions across game restart (2-moderate, verify-fix): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #376 LA illusions do not persist across restart (not_planned 2026-08-03, evidence n-a) | #25 | consolidated into reopened #25 |

Comment to post on #25:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #376 (closed not planned 2026-08-03): consolidated into this issue
Their acceptance is owed here. They stay closed.
```

### Open #60 Enforce Be'lakor Chest and Altar Counts (2-moderate, verify-fix): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #132 Enforce Khazukan Trial Chest Cap (not_planned 2026-07-19, evidence n-a) | #60 | exact duplicate of open #60 (Khazukan chest cap) |

Comment to post on #60:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #132 (closed not planned 2026-07-19): exact duplicate of this issue (Khazukan chest cap)
Their acceptance is owed here. They stay closed.
```

### Open #408 Sort WT Availability by Display Name (2-moderate, verify-fix): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #179 wt: Weapon Availability - group rows by source char in fixed order (Kr (completed 2026-07-02, evidence A) | #408 | open #408/#183 report the same Weapon Availability ordering symptom (sweep 2026-07-18: fix incomplete, melee-only) |

Comment to post on #408:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #179 (closed as fixed 2026-07-02): this issue/#183 report the same Weapon Availability ordering symptom (sweep 2026-07-18: fix incomplete, melee-only)
Their acceptance is owed here. They stay closed.
```

### Open #499 Consolidate per-issue probes into diagnostics modules (2-moderate, not-started): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #500 Stale probes for closed issues still running (completed 2026-07-13, evidence n-a) | #499 | surviving-probe migration deferred to open #499 |

Comment to post on #499:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #500 (closed as fixed 2026-07-13): surviving-probe migration deferred to this issue
Their acceptance is owed here. They stay closed.
```

### Open #558 Stop tracking generated bundle outputs (2-moderate, not-started): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #1429 [tooling] Add receipt-bound local deployment (completed 2026-09-08, evidence n-a) | #558 | open #558 states #1429 remains incomplete (no released receipt-bound local deploy) |

Comment to post on #558:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #1429 (closed as fixed 2026-09-08): this issue states #1429 remains incomplete (no released receipt-bound local deploy)
Their acceptance is owed here. They stay closed.
```

### Open #571 Contain injected collectible HUD layout (2-moderate, verify-fix): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #533 The Collectibles for Chaos Wastes Mission on tab (not_planned 2026-07-22, evidence n-a) | #571 | remaining defect is open #571 |

Comment to post on #571:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #533 (closed not planned 2026-07-22): remaining defect is this issue
Their acceptance is owed here. They stay closed.
```

### Open #641 Name offhand cosmetics independently (2-moderate, verify-fix): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #924 Blood-Bloomed Bouclier Custom Cosmetic description (not_planned 2026-07-21, evidence n-a) | #641 | duplicate of open #641 |

Comment to post on #641:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #924 (closed not planned 2026-07-21): duplicate of this issue
Their acceptance is owed here. They stay closed.
```

### Open #692 Bret Longsword greatsword styles need inverse Z offsets (2-moderate, verify-fix): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #648 Tune Bretonnian Longsword Greatsword Combat Styles (completed 2026-07-17, evidence A) | #692 | open #692: delivered greatsword style lacks inverse transform |

Comment to post on #692:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #648 (closed as fixed 2026-07-17): reported here: delivered greatsword style lacks inverse transform
Their acceptance is owed here. They stay closed.
```

### Open #719 Client sees Sienna crowbill for Kruber variant (2-moderate, diagnostics-armed): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #392 CWV blacksmith/template items resolve to base weapon (completed 2026-07-14, evidence A) | #719 | open #719: client resolves Kruber crowbill variant to base Sienna item (same husk base-resolution symptom) |

Comment to post on #719:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #392 (closed as fixed 2026-07-14): reported here: client resolves Kruber crowbill variant to base Sienna item (same husk base-resolution symptom)
Their acceptance is owed here. They stay closed.
```

### Open #802 [Events] Place event missions at top level (2-moderate, verify-fix): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #626 ET: Dissect Feast mission activation (completed 2026-07-21, evidence A) | #802 | owner 2026-07-20: "the main issue now is #802" |

Comment to post on #802:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #626 (closed as fixed 2026-07-21): owner 2026-07-20: "the main issue now is this issue"
Their acceptance is owed here. They stay closed.
```

### Open #316 WT: Empire Longbow weapon-special zoom missing on cross-career users (3-low, verify-fix): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #580 wt: substitute Saltzpyre Moonfire presentation (completed 2026-07-13, evidence A) | #316 | open #316: Saltzpyre loses crossbow presentation (regression of #580/#210 isolation) |

Comment to post on #316:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #580 (closed as fixed 2026-07-13): reported here: Saltzpyre loses crossbow presentation (regression of #580/#210 isolation)
Their acceptance is owed here. They stay closed.
```

### Open #440 Investigate Bardin's Disabler Dodge Consistency (3-low, not-started): 1 closed predecessor

| Closed issue | Open issue that tracks it | One-line reason |
|---|---|---|
| #439 Warrior Priest Career Skill / Bubble Often Prioritizes Bardin Over Oth (duplicate 2026-07-08, evidence n-a) | #440 | root issue tracked in open #440 |

Comment to post on #440:

```
Cross-reference from the 2026-11-13 closed-issue audit. This issue is the live owner of work first tracked in:
- #439 (closed as duplicate 2026-07-08): root issue tracked in this issue
Their acceptance is owed here. They stay closed.
```

### Flat index (closed issue -> open issue)

| Closed | Open | Closed | Open | Closed | Open | Closed | Open |
|---|---|---|---|---|---|---|---|
| #22 | #682 | #64 | #471 | #83 | #80 | #100 | #102 |
| #103 | #102 | #109 | #948 | #110 | #948 | #111 | #948 |
| #113 | #948 | #116 | #299 | #132 | #60 | #154 | #660 |
| #161 | #748 | #174 | #402 | #178 | #748 | #179 | #408 |
| #180 | #748 | #182 | #748 | #184 | #748 | #196 | #748 |
| #267 | #233 | #305 | #700 | #319 | #290 | #376 | #25 |
| #390 | #279 | #392 | #719 | #401 | #660 | #409 | #474 |
| #439 | #440 | #484 | #474 | #495 | #491 | #500 | #499 |
| #513 | #738 | #531 | #450 | #533 | #571 | #539 | #404 |
| #568 | #1684 | #580 | #316 | #611 | #717 | #620 | #786 |
| #626 | #802 | #643 | #632 | #648 | #692 | #694 | #717 |
| #697 | #660 | #698 | #738 | #710 | #80 | #741 | #914 |
| #789 | #807 | #792 | #474 | #793 | #822 | #803 | #413 |
| #826 | #389 | #920 | #919 | #924 | #641 | #926 | #377 |
| #927 | #282 | #928 | #592 | #930 | #661 | #933 | #661 |
| #937 | #282 | #940 | #282 | #945 | #914 | #958 | #712 |
| #1026 | #645 | #1027 | #645 | #1028 | #645 | #1029 | #645 |
| #1429 | #558 | #1689 | #624 |  |  |  |  |

## Part 3. REGRESSION PACK (closed issues with no runtime evidence)

Population: 67 closed issues = the 56 ledger rows marked `REVERIFY-VIA-HARNESS` plus the other closed-completed runtime issues with evidence class C or D. Nothing here reopens an issue.

What to do with a result (use these two texts):

- PASS: post one comment on the CLOSED issue, leave it closed:
  `auto-verified (<U|S|R>) on <mod> <version> <commit>, run <id>: <script or check name>. Closed-issue regression pack VP-CL-<NN>.`
- FAIL: open a NEW issue. Title: `Regression of #<N>: <8 words max>`. Body (Symptom / Evidence / Refs, under 150 words): the failing assertion text, the run id, the log line, and `Refs: #<N> (closed <date>), VP-CL-<NN>`. Labels: the closed issue's type, mod and priority labels, plus `regression` and `not-started`. Do not reopen #<N>.
- ERROR, TIMEOUT, INCONCLUSIVE: fix the script or the precondition. Post nothing.

Card format: `docs/program/CONVENTIONS.md` section 5, with one change. The last column of each Cases table is "On PASS" instead of "PASS closes?", because every issue here is already closed.

Mod ids for `T.expect_rt` and `T.set` (read from each mod's main file): `gt_dev`, `ct_dev`, `gut_dev`, `cim_dev`, `wt`, `cosmetics_tweaker`, `character_weapon_variants`, `enemy_tweaker`.

Offline suite command (class U): `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` (`qa/lua/README.md`). It runs every `qa/lua/tests/test_*.lua`; there is no single-test switch.

Correction to the round 1 report: only 4 of these issues have a regression check with the issue NUMBER in its name (#89, #240, #406, #534), but 27 have a named in-mod check on master, found from the closing comments. Those names are used below and each was confirmed as a registered check name on `origin/master`. A check whose name ends in `_present`, `_registered`, `_installed`, `_wired` or `_marker_present` asserts that code exists, not that it behaves; cards say which were read.

### Execution order: the 18 crash-class issues first

| Order | Issue | Card | Evidence available today | Class |
|---|---|---|---|---|
| 1 | #731 Client CTD on disconnect: VOIP channel nil (0-critical) | VP-CL-01 | unit test exists | U, then R |
| 2 | #372 gut loadout hover fatal (0-critical) | VP-CL-05 | none | R |
| 3 | #294 ct CTD spawning non-resident pickup (0-critical) | VP-CL-03 | in-mod check, behavioural, read | R |
| 4 | #406 ct client CTD with kill-heal boon (0-critical, reopened in Part 1) | VP-CL-03 | in-mod check, catalog only | R for the host part, C for the crash |
| 5 | #157 cross-character ranged weapon CTDs the CW loadout | VP-CL-03 | none | R |
| 6 | #59 Drachenfels boss behaviour-tree crash | VP-CL-02 | in-mod check, marker only | R |
| 7 | #362 create_equipment returns nil | VP-CL-07 | none | R |
| 8 | #216 3P camera screen-particle nil id | VP-CL-06 | unit test exists | U, then R |
| 9 | #65 bots_in_keep, two crash classes | VP-CL-02 | six in-mod checks, not read | R |
| 10 | #195 Necromancy staff soul_rip crash | VP-CL-07 | in-mod check, behavioural, read | R |
| 11 | #225, #236 Deepwood staff wield crash on Kruber | VP-CL-07 | unit test exists | U, then R |
| 12 | #71 Pressing amulet crashes game | VP-CL-08 | unit test and in-mod check exist | U, then R |
| 13 | #81 in-mission forge crash on LA atlas | VP-CL-08 | in-mod check | R (needs Loremaster's Armoury for the original trigger) |
| 14 | #50 mid-mission item customization crash | VP-CL-08 | none | R |
| 15 | #47 property bubbles do not apply | VP-CL-08 | in-mod checks | R |
| 16 | #76 Mod Tweaker renderer recreation crash | VP-CL-06 | in-mod check, structural | R (needs Loremaster's Armoury for the original trigger) |
| 17 | #20 cwv ItemMasterList exceptions per keep load | VP-CL-09 | none | R (boot log) |
| 18 | #67 enemy_tweaker inject_special_packs crash | VP-CL-09 | none | R |

---

### VP-CL-01 gt-voip: stale VOIP leave-room RPC after host loss

| Field | Value |
|---|---|
| Issues | #731 (U; R for the hook wiring; C for a real disconnect) |
| Arena | none for the unit test; `keep` for the rig case |
| Mods and stream | `gt_dev` (dev build). The stable `general_tweaker` has no guard (Part 4). |
| Boots | 1 |
| Depends on | rig: `T.expect`, `host_expect_log`. No fix WP: the fix is on master. |

**Setup.** None. The rig case never touches the real network: it calls the hooked class function with a table that looks like a client whose server channel is gone.

**Cases.**

| Script | Issue | Steps (T calls, in order) | Assertions (engine state read, with citation) | On PASS |
|---|---|---|---|---|
| `qa/lua/tests/test_gt_voip_disconnect_policy.lua` (exists) | #731 | run the offline suite | `Policy.should_drop_server_rpc("rpc_voip_room_request", false, "gone", {host=17})` is true, false for the server and for other RPCs; `general_tweaker_dev.lua` loads the guard exactly once (`general_tweaker_dev/scripts/mods/general_tweaker_dev/general_tweaker_dev.lua:1942`) | note (U) |
| `qa/runtime/gt_dev/issue_731_voip_nil_channel.lua` (new) | #731 | `T.step("client-shaped self, no server channel")`; `local ok = pcall(NetworkTransmit.send_rpc_server, { is_server = false, server_peer_id = "vp_missing_peer" }, "rpc_voip_room_request", false)`; `T.step("control: other RPC is not swallowed")`; `local ok2 = pcall(NetworkTransmit.send_rpc_server, { is_server = false, server_peer_id = "vp_missing_peer" }, "rpc_vp_not_a_real_rpc")` | `T.expect(ok, "guard dropped the VOIP RPC")`; `T.expect(not ok2, "guard is narrow")`; `host_expect_log = {"[gt:731][WARN] Dropped stale VOIP leave-room RPC"}`. Without the guard, vanilla reads `PEER_ID_TO_CHANNEL[self.server_peer_id]` and passes nil to the engine RPC (`Vermintide-2-Source-Code/scripts/network/network_transmit.lua:185-195`); the caller is `Voip._ensure_left_voip_room` (`Vermintide-2-Source-Code/scripts/network/voip.lua:384`). Guard: `general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_network_transmit_guard.lua:22` | note (R) |

**Reused in-mod checks.** None.

**Left for humans.** #731: a real host loss while a VOIP room is active (class C, two machines).

**If it FAILS.** `ok == false`: the hook is not installed in this build; check the `mod:dofile` at `general_tweaker_dev.lua:1942`. `ok2 == true`: the guard swallows more than the VOIP RPC; read `_gt_network_transmit_guard.lua` (the noclip guard runs first in the same hook).

---

### VP-CL-02 gt-bots: boss behaviour-tree guard and bot toggles

| Field | Value |
|---|---|
| Issues | #59 (R), #65 (R), #194 (R), #320 (R), #43 (R through the in-mod check) |
| Arena | `keep` for #59, #43, #65; `mission:military` for #194, #320 |
| Mods and stream | `gt_dev` (dev build). Options set per case. |
| Boots | 3: one keep boot; one mission boot with `gt_no_bots` on (bots must be absent from level start); one mission boot with bots present for #320 |
| Depends on | rig: `T.expect_rt`, `T.set` before boot, `T.spawn`, `T.bots`; a level load from inside a keep case for #65 [unverified that the rig allows it] |

**Setup.** #320 needs a bot holding a potion: add one to the first bot with the inventory extension's `add_equipment("slot_potion", <potion item name>)` (`Vermintide-2-Source-Code/scripts/unit_extensions/default_player_unit/inventory/simple_inventory_extension.lua:858`) [unverified: exact potion item name; take one from `ItemMasterList`].

**Cases.**

| Script | Issue | Steps (T calls, in order) | Assertions (engine state read, with citation) | On PASS |
|---|---|---|---|---|
| `qa/runtime/gt_dev/issue_59_bt_health_nil.lua` | #59 | `T.require(rawget(_G, "BTConditions") ~= nil, "BTConditions loaded")`; for each name in `at_half_health`, `at_one_third_health`, `at_two_thirds_health`, `at_one_fifth_health`, `at_three_fifths_health`, `can_transition_half_health`, `can_transition_one_third_health`: `local ok = pcall(BTConditions[name], {})` | `T.expect(ok, name)` for all seven. Vanilla compares `blackboard.current_health_percent` with a number and raises on nil (`Vermintide-2-Source-Code/scripts/entity_system/systems/behaviour/nodes/bt_conditions.lua:296-308`). Hooks: `general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_creature_spawner.lua:1481-1487` | note (R) |
| same file, second block | #59 | `T.expect_rt("gt_dev", "gt_cs_is_in_level_prefix_match")` | the level-family match that made `dlc_castle_*_path1` count as Drachenfels | note (R) |
| `qa/runtime/gt_dev/issue_65_bots_in_keep_cycle.lua` | #65 | `T.set("gt_dev", "gt_bots_in_keep", true)`; `T.wait_until(function() return #T.bots() > 0 end, 30, "bots in keep")`; request a level load (`Managers.mechanism:debug_load_level("military")`, `Vermintide-2-Source-Code/scripts/managers/game_mode/game_mechanism_manager.lua:880-892`); `T.wait_until(level started, 120)` | `host_forbid_log = {"statistics_database.lua", "Script Error"}`. The crash class was a stale bot statistics id at venture end; `StatisticsDatabase.unregister` is at `Vermintide-2-Source-Code/scripts/managers/backend/statistics_database.lua:164`. Feature gate: `general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bots_keep.lua:128` | note (R) |
| `qa/runtime/gt_dev/issue_194_no_bots.lua` | #194 | boot option `gt_no_bots = true`; in the mission `T.wait(10)` | `T.expect_eq(script_data.ai_bots_disabled, true, "flag set")`: vanilla skips bot handling on this flag (`Vermintide-2-Source-Code/scripts/managers/game_mode/game_modes/game_mode_adventure.lua:364-371`). `T.note("bot_count", <number of bot players>)` and expect 0 [unverified: accessor for the bot player list] | note (R) |
| `qa/runtime/gt_dev/issue_320_bot_potion_on_boss.lua` | #320 | `T.set("gt_dev", "gt_bot_drink_potions_in_danger", true)`; `T.set("gt_dev", "gt_bot_drink_on_boss", true)`; give the first bot a potion (Setup); `T.spawn("skaven_rat_ogre", {4, 0, 0})`; `T.wait_until(function() return bot_inv:get_slot_data("slot_potion") == nil end, 45, "bot drank")` | the bot's `slot_potion` empties while a boss is near. Settings: `general_tweaker_dev/scripts/mods/general_tweaker_dev/general_tweaker_dev_data.lua:342, 356`. [unverified: line of `SimpleInventoryExtension.get_slot_data`] | note (R) |
| `qa/runtime/gt_dev/issue_43_lobby_rpc_schema.lua` | #43 | `T.expect_rt("gt_dev", "gt_lobby_rpc_schema_present")` | check registered at `general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_regression_checks.lua` (stable copy at `general_tweaker/scripts/mods/general_tweaker/_gt_regression_checks.lua:167`) | note (R) |

**Reused in-mod checks.** `bt_health_conditions_nilguarded_marker_present` (read: compares a marker string only, not behaviour). `gt_cs_is_in_level_prefix_match` (not read). `no_bots_apply_sets_ai_bots_disabled` (read: calls `mod._gt_apply_no_bots(true/false)` and reads `script_data.ai_bots_disabled`; behavioural at function level). `no_bots_setting_registered`, `bots_in_keep_active_default_false`, `bots_in_keep_crashfix_marker_present`, `bots_in_keep_helpers_exposed`, `bots_in_keep_necro_pets_marker_present`, `bots_in_keep_reset_bookkeeping_safe`, `bots_in_keep_setting_registered`, `bot_drink_potion_advanced_conditions_registered` (dev tree only), `gt_lobby_rpc_schema_present` (none read; structural by name except `reset_bookkeeping_safe`).

**Left for humans.** #59: the real Drachenfels boss fight on a Chaos Wastes `dlc_castle_*_path1` map (the script proves the guard, not the fight). #320: whether the bot's choice looks sensible. #65: nothing.

**If it FAILS.** #59: a `pcall` false means the hooks did not install; they sit inside a guarded block in `_gt_creature_spawner.lua` near line 1446. #65: read the first `Script Error` after the level load in the log. #194: `_gt_bots_keep.lua` (`gt_no_bots` branch). #320: `_gt_bot_fixes.lua` (`_gt_danger_near`).

---

### VP-CL-03 cw-crash-guards: Chaos Wastes crash guards

| Field | Value |
|---|---|
| Issues | #157 (R), #294 (R), #406 (R for the host heal; C for the client crash, see Part 1) |
| Arena | `deus` |
| Mods and stream | `ct_dev` (dev build). None of these guards exist in the stable `chaos_wastes_tweaker` (Part 4). |
| Boots | 1 |
| Depends on | rig: reaching a Chaos Wastes level unattended (`DeusMechanism.debug_load_level`, `Vermintide-2-Source-Code/scripts/managers/game_mode/mechanisms/deus_mechanism.lua:1002`), `T.pickup`, `T.spawn`, `T.expect_rt` |

**Setup.** A running Chaos Wastes level as host. For #406 grant the boon with `DeusRunController.add_power_ups` (`Vermintide-2-Source-Code/scripts/managers/game_mode/mechanisms/deus_run_controller.lua:1126`; calling pattern in `Vermintide-2-Source-Code/scripts/game_state/state_ingame_testify.lua:167-211`) using the power-up name `ct_kill_heal`. The hero must be below full permanent health before the kill [unverified: the damage call to use; if none is available, report INCONCLUSIVE].

**Cases.**

| Script | Issue | Steps (T calls, in order) | Assertions (engine state read, with citation) | On PASS |
|---|---|---|---|---|
| `qa/runtime/ct_dev/issue_157_deus_loadout_unknown_id.lua` | #157 | `local deus = Managers.backend:get_interface("deus")` (`Vermintide-2-Source-Code/scripts/game_state/state_ingame_testify.lua:175`); `T.note("class", tostring(getmetatable(deus)))`; `local ok = pcall(deus.set_loadout_item, deus, "VP_NOT_A_DEUS_ID", <career name of the local hero>, "slot_ranged")`; `local ok2 = pcall(deus.get_total_power_level, deus, <profile name>, <career name>)` | `T.expect(ok, "unknown id does not fassert")`; `T.expect(ok2, "power level survives")`; `host_expect_log = {"[ct:crash157] BLOCKED set_loadout_item non-deus id"}`. Vanilla fasserts on an id missing from `_extra_deus_inventory` (`Vermintide-2-Source-Code/scripts/managers/backend_playfab/backend_interface_deus_base.lua:112-116`; power level at `:130`). Guard: `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_run_runtime_owner.lua:267-293`, hooked on `BackendInterfaceDeusPlayFab` (`Vermintide-2-Source-Code/scripts/managers/backend_playfab/backend_interface_deus_playfab.lua:5`) | note (R) |
| `qa/runtime/ct_dev/issue_294_pickup_nonresident.lua` | #294 | `T.expect_rt("ct_dev", "pickup_residency_guard_installed")`; `local s = AllPickups.pup_skull_of_fury`; `T.require(s ~= nil, "pickup defined")`; `T.note("resident", Application.can_get("unit", s.unit_name))`; `T.pickup("pup_skull_of_fury", {2, 0, 0})`; `T.wait(2)` | `host_forbid_log = {"entity_manager2.lua", "table index is nil"}`; if `resident` is false: `T.expect_eq(get_mod("ct_dev")._ct_pickup_unit_spawn_safe(s), false, "guard refuses")`. Vanilla's own residency test is `Application.can_get("unit", unit_name)` (`Vermintide-2-Source-Code/scripts/entity_system/systems/pickups/pickup_system.lua:878-882`); spawn entry `:1157`. Guard: `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_pickup_spawn_owner.lua:248` | note (R) |
| `qa/runtime/ct_dev/issue_406_kill_heal_host.lua` | #406 | `T.expect_rt("ct_dev", "issue406_kill_heal_mod_boon_catalog")`; grant `ct_kill_heal` (Setup); `local h = T.ext(T.local_hero(), "health_system")`; `local before = h:current_permanent_health()`; `T.spawn("skaven_slave", {2, 0, 0})`; kill it with the hero as attacker; `T.wait(1)` | `T.expect(h:current_permanent_health() > before, "permanent health rose")` (`Vermintide-2-Source-Code/scripts/unit_extensions/default_player_unit/player_unit_health_extension.lua:1073`); `host_expect_log = {"[ct:406] kill_heal result="}`. The heal goes through `DamageUtils.heal_network` (`Vermintide-2-Source-Code/scripts/helpers/damage_utils.lua:2484`). Mod code: `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_meta_trait_boons.lua:369-412` | comment on the OPEN issue: "host part auto-verified (R)"; the issue stays open (class C) |

**Reused in-mod checks.** `pickup_residency_guard_installed` (read: calls the guard with nil, with a self-spawning pickup and with a bogus unit name; behavioural at function level; `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_runtime_owner.lua:294`). `issue406_kill_heal_mod_boon_catalog` (read: asserts the boon is listed in the settings catalog; it does not test the heal; `_ct_meta_trait_boons.lua:499`). Offline tests that touch the guard: `qa/lua/tests/test_ct_pickup_spawn_owner.lua`, `qa/lua/tests/test_ct_spawn_pickup_two_return.lua`.

**Left for humans.** #406: a client with the boon kills an enemy and neither peer crashes (class C). #157: nothing. #294: nothing.

**If it FAILS.** #157 with `ok == false`: note the `class` line; if the modded realm uses a backend class other than `BackendInterfaceDeusPlayFab`, the hook is on the wrong class (`_ct_run_runtime_owner.lua:264-267`). #294: `_ct_pickup_spawn_owner.lua`. #406 with no health change: read the `[ct:406]` line; `server=false` means the host gate failed, a missing line means the proc never fired.

---

### VP-CL-04 cw-data: Chaos Wastes data, text and sync fixes

| Field | Value |
|---|---|
| Issues | #34 (R), #143 (R), #39 (R), #54 (R), #27 (R through the in-mod check), #56 (C: solo part only), #68 (V: solo part only) |
| Arena | `keep` for #34, #39, #54, #27; `deus` for #143, #56, #68 |
| Mods and stream | `ct_dev` (dev build) |
| Boots | 2 (keep, deus) |
| Depends on | rig: `T.expect_rt`, `T.set`, `host_expect_log`, `T.shot`; an injected adventure level in the Chaos Wastes run for #143 |

**Setup.** #143 needs a Chaos Wastes level that ct injected from the adventure pool (the renormalisation only runs there). #68 needs the Chaos Wastes map open on a run that contains a `*_belakor_path1` variant of an adventure DLC level.

**Cases.**

| Script | Issue | Steps (T calls, in order) | Assertions (engine state read, with citation) | On PASS |
|---|---|---|---|---|
| `qa/runtime/ct_dev/issue_34_meta_ammo_bounded.lua` | #34 | `T.expect_rt("ct_dev", "ct_meta_ammo_stacks_bounded")` | check at `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_regression.lua:1276` | note (R) |
| `qa/runtime/ct_dev/issue_143_morgrim_weight.lua` | #143 | `T.expect_rt("ct_dev", "morgrim143_renorm_fix")`; `T.require(level is an injected adventure level, "injected level")`; `T.wait(5)` | `host_expect_log = {"[ct:morgrim143] grenade pool renorm: holy_hand"}` and the two "pool sum" numbers in that line are equal (parse the line, `T.expect_near(sum_before, sum_after, 0.0001)`). Log line: `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_pickup_population_owner.lua:625` | note (R) |
| `qa/runtime/ct_dev/issue_39_starting_coins_step.lua` | #39 | `T.set("ct_dev", "starting_coins", 137)`; `T.frames(5)` | `T.expect_eq(get_mod("ct_dev"):get("starting_coins") % 25, 0, "snapped to 25")`. Hook: `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_settings_lifecycle_owner.lua:181` (`VMFOptionsView.callback_draw_numeric_menu`). [unverified: whether `T.set` runs the snap-on-save path; if the value stays 137, report INCONCLUSIVE and escalate] | note (R) |
| `qa/runtime/ct_dev/issue_54_isha_text.lua` | #54 | `T.set("ct_dev", "tweak_miracle_of_isha_aegis", true)`; `T.set("ct_dev", "tweak_miracle_of_isha_wounds", false)`; `local a = Localize("blessing_of_isha_desc")`; swap the two settings; `local w = Localize("blessing_of_isha_desc")` | `T.expect(a ~= w, "text follows the selected mode")`; `T.expect(#a > 0 and a:sub(1, 1) ~= "<", "aegis text resolved")`; same for `w`. Stable copy of the branch: `chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/chaos_wastes_tweaker.lua:4757`; dev: `git grep -n blessing_of_isha_desc -- chaos_wastes_tweaker_dev` | note (R) |
| `qa/runtime/ct_dev/issue_27_rpc_schema.lua` | #27 | `T.expect_rt("ct_dev", "ct_rpc_schema_present")` | structural | note (R) |
| `qa/runtime/ct_dev/issue_56_curse_probe_host.lua` | #56 | reach the first Chaos Wastes map; `T.wait(5)` | `host_expect_log = {"[ct:curse56]"}` (`chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_campaign_graph_owner.lua:249`). `T.note` every `[ct:curse56]` line for the later two-machine comparison | no note: class C |
| `qa/runtime/ct_dev/issue_68_belakor_node_model.lua` | #68 | open the Chaos Wastes map; `T.wait(3)`; `T.shot("cw_map_nodes")` | for each `[ct:mapnode68]` line whose level ends in `_belakor_path1`, the resolved model is not `units/morris_map/deus_map_base_shrine_01` (`Vermintide-2-Source-Code/scripts/ui/views/deus_menu/deus_map_scene.lua:10, 176-191`). Probe: `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_adventure_runtime_owner.lua:615, 636` | note (R) for the model name; the look is V |

**Reused in-mod checks.** `ct_meta_ammo_stacks_bounded` (partly read: checks the cap constant `CT_META_AMMO_MAX_STACKS == 30` and then buff templates; returns "skip" outside the keep). `morgrim143_renorm_fix` (read: marker string only). `ct_rpc_schema_present` (not read).

**Left for humans.** #56: host and client show the same Citadel curse (class C). #68: the node looks like a level node, not an altar (class V; use the still).

**If it FAILS.** #68 is the likeliest FAIL: the thread shows a probe and no fix. A FAIL there means the bug was never fixed; file the regression issue as a `bug`, not a `regression`. #143: `_ct_pickup_population_owner.lua` near line 593 to 625.

---

### VP-CL-05 gut-loadouts: modded loadout console

| Field | Value |
|---|---|
| Issues | #372 (R), #379 (R), #387 (R) |
| Arena | `keep` (modded realm) |
| Mods and stream | `gut_dev` (dev build; the hook also exists in the stable tree at the same line) |
| Boots | 1 |
| Depends on | rig: `T.open_view`, `T.widget`; equip helper (`BackendUtils.set_loadout_item` + `create_equipment_in_slot`, `Vermintide-2-Source-Code/scripts/unit_extensions/default_player_unit/inventory/simple_inventory_extension.lua:2175-2183`). Agent: strong, because reaching the window instance needs view internals. |

**Setup.** Open the hero view on the loadout page. Get the live `HeroWindowLoadoutSelectionConsole` instance [unverified: the path from the hero view to its active window objects; if it cannot be reached, report INCONCLUSIVE, do not call the class method with a fake `self`]. The local career needs two melee items in the backend for #379 and #387.

**Cases.**

| Script | Issue | Steps (T calls, in order) | Assertions (engine state read, with citation) | On PASS |
|---|---|---|---|---|
| `qa/runtime/gut_dev/issue_372_context_menu_unresolvable.lua` | #372 | `local bogus = { slot_melee = "VP_BOGUS", slot_ranged = "VP_BOGUS", slot_necklace = "VP_BOGUS", slot_ring = "VP_BOGUS", slot_trinket_1 = "VP_BOGUS" }`; `local ok = pcall(window._populate_context_menu_loadout, window, bogus, 1)` | `T.expect(ok, "unresolvable ids do not crash the preview")`. Vanilla resolves each id with `get_item_from_id` and passes the nil result to `UIUtils.get_ui_information_from_item`, which indexes it (`Vermintide-2-Source-Code/scripts/ui/views/hero_view/windows/hero_window_loadout_selection_console.lua:811-924`; `Vermintide-2-Source-Code/scripts/helpers/ui_utils.lua:219-220`). Hook: `gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_native_loadouts.lua:1124` | note (R) |
| `qa/runtime/gut_dev/issue_379_context_menu_live_row.lua` | #379 | capture the cached row the window holds for loadout index `i` (`content.loadout`, set at `hero_window_loadout_selection_console.lua:191`); equip a different melee item; `window:_populate_context_menu_loadout(cached_row, i)`; read the context-menu widget content for `slot_melee` | the icon shown equals `UIUtils.get_ui_information_from_item(new_item)` (first return value), not the old item's. Live row source: `BackendInterfaceItemPlayfab.get_career_loadouts` (`Vermintide-2-Source-Code/scripts/managers/backend_playfab/backend_interface_item_playfab.lua:469`) [unverified: widget content field names] | note (R) |
| `qa/runtime/gut_dev/issue_387_loadout_switch_weapons.lua` | #387 | store item A in loadout 1 and item B in loadout 2 with `set_loadout_item(item_id, career, "slot_melee", index)` (`backend_interface_item_playfab.lua:635`); switch the selected loadout from 1 to 2 the way the console does [unverified: the call the console makes]; `T.frames(10)` | `T.expect_eq(BackendUtils.get_loadout_item(career, "slot_melee").backend_id, B, "melee follows the loadout")`. `get_item_from_id` consults `_items` only (`backend_interface_item_playfab.lua:384`). Resolver: `gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_native_loadouts.lua` (`_resolve_item_raw`) | note (R) |

**Reused in-mod checks.** The gut native-loadout suite in `gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_native_loadout_checks.lua` runs at boot (names not read). Offline: `qa/lua/tests/test_gut_loadout_paging.lua` mentions the hook.

**Left for humans.** Nothing for #372. #379 and #387: that the preview icons look right (V, low value once the ids match).

**If it FAILS.** #372: the hook at `_gut_native_loadouts.lua:1124` no longer validates slots before calling vanilla (the guard compares `_resolve_item_raw(id)` with `RESOLVE_YES` about 40 lines below). #387: open issue #1190 mentions loadout weapons again; link the new regression issue to it.

---

### VP-CL-06 gut-menu-camera: Mod Tweaker, HUD registry, third-person camera

| Field | Value |
|---|---|
| Issues | #76 (R), #79 (U), #216 (U, then R), #191 (R + V), #190 (R boot), #192 (R boot), #78 (V) |
| Arena | `keep` for #76, #79; `mission:military` for #216, #191; `boot` for #190, #192 |
| Mods and stream | `gut_dev` (dev build). #216 needs a Sienna career. |
| Boots | 2 (keep, mission) |
| Depends on | rig: `T.cmd`, `T.expect_rt`, `T.set`, `T.shot`, career selection (`Managers.state.network:request_profile`, `Vermintide-2-Source-Code/scripts/game_state/state_ingame_testify.lua:97-101`) |

**Setup.** #216: local hero is any Sienna career, third-person camera on (`gut_tp_camera_enabled`, `gui_tweaker_dev/scripts/mods/gui_tweaker_dev/gui_tweaker_dev_data.lua:93`), overcharge above zero [unverified: line of `PlayerUnitOverchargeExtension.add_charge`; use the overcharge extension's own add call].

**Cases.**

| Script | Issue | Steps (T calls, in order) | Assertions (engine state read, with citation) | On PASS |
|---|---|---|---|---|
| `qa/runtime/gut_dev/issue_76_mod_tweaker_reopen.lua` | #76 | `T.expect_rt("gut_dev", "mod_tweaker_transition_registered")`; five times: `T.cmd("mod_tweaker")`, `T.wait(1)`, close the view [unverified: close call], `T.wait(1)` | `host_forbid_log = {"armoury_atlas", "c_api_world"}`; the process is alive after the fifth cycle | note (R), saying "without Loremaster's Armoury" if that mod was not loaded |
| `qa/lua/tests/test_gut_view_rows.lua` (exists) | #79 | run the offline suite | the test covers `plan_drill_children` and the gear rows (`gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_definitions.lua`) | note (U) |
| `qa/lua/tests/test_gut_screen_particle_ledger.lua` (exists) | #216 | run the offline suite | covers the screen-particle create/stop/destroy surface | note (U) |
| `qa/runtime/gut_dev/issue_216_tp_camera_overcharge.lua` | #216 | `T.set("gut_dev", "gut_tp_camera_enabled", true)`; raise overcharge (Setup); `T.wait(2)`; `local fp = T.ext(T.local_hero(), "first_person_system")`; `local ok1 = pcall(fp.stop_spawning_screen_particles, fp, nil)`; `local ok2 = pcall(fp.destroy_screen_particles, fp, nil)` | `host_forbid_log = {"set_particles_material_scalar"}`; `T.expect(ok1 and ok2, "nil particle id tolerated")`; `T.expect_eq(overcharge_ext.onscreen_particles_id, nil, "no screen overlay in 3P")`. Vanilla calls `World.set_particles_material_scalar` with that id every frame (`Vermintide-2-Source-Code/scripts/unit_extensions/default_player_unit/charge/player_unit_overcharge_extension.lua:653-687`); sinks at `Vermintide-2-Source-Code/scripts/unit_extensions/default_player_unit/player_unit_first_person.lua:1081, 1089`. Hooks: `gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_camera.lua:269, 299, 307` | note (R) |
| `qa/runtime/gut_dev/issue_191_tp_camera_on.lua` | #191 | `T.set("gut_dev", "gut_tp_camera_enabled", true)`; `T.wait(2)`; `T.shot("tp_camera")` | `T.expect_eq(get_mod("gut_dev"):get("gut_tp_camera_enabled"), true, "setting owned by gut")`; `host_forbid_log = {"Script Error"}` | note (R) for "option exists and loads"; camera position is V |
| `qa/runtime/gut_dev/issue_190_192_migrated_groups.lua` | #190, #192 | at boot | the option ids exist in gut: `gut_mainmenu_group` (`gui_tweaker_dev_data.lua:616`), `gut_skip_cutscenes_enabled` (`:626`), `gut_disable_intro_monologue` (`:650`): `T.expect(get_mod("gut_dev"):get(id) ~= nil)` for the two non-group ids; `host_forbid_log = {"[MOD][gut_dev][ERROR]"}` | note (R) |

**Reused in-mod checks.** `mod_tweaker_transition_registered` (not read; structural by name; `gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_mod_tweaker_contracts.lua:157`).

**Left for humans.** #78: Mod Tweaker top strip, tab spacing and row underline (class V; attach `T.shot` of the open menu). #191: camera distance and offset feel. #76: the original crash needs Loremaster's Armoury loaded.

**If it FAILS.** #216: `_gut_camera.lua` hooks listed above. #76: `_gut_mod_tweaker_contracts.lua` and the `HeroViewStateModTweaker` registration.

---

### VP-CL-07 wt: weapon tweaker crash guards and wield data

| Field | Value |
|---|---|
| Issues | #362 (R), #195 (R), #236 and #225 (U, then R), #162 (R + V), #26 (R through the in-mod checks) |
| Arena | `keep` for #195, #162, #26; `mission:military` for #362, #236 |
| Mods and stream | `wt` (public beta build `weapon_tweaker`; mirror `weapon_tweaker_dev`). #362 also needs `cosmetics_tweaker` loaded. |
| Boots | 2 (keep, mission) |
| Depends on | rig: `T.expect_rt`, `T.ext`, career selection, equip helper |

**Setup.** #362: hero on any level that is not the whaling map, `cosmetics_tweaker` loaded. #236: career `es_mercenary`, option `unlock_es_mercenary_we_life_staff` on (`weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker_data.lua:244`), `we_life_staff` equipped in the ranged slot.

**Cases.**

| Script | Issue | Steps (T calls, in order) | Assertions (engine state read, with citation) | On PASS |
|---|---|---|---|---|
| `qa/runtime/wt/issue_362_create_equipment_stub.lua` | #362 | `T.require(get_mod("cosmetics_tweaker") ~= nil, "cosmetics loaded")`; `local unit3p = ItemMasterList.whale_oil_barrel.right_hand_unit .. "_3p"` [unverified: field holding the barrel unit]; `T.require(not Application.can_get("unit", unit3p), "barrel unit not resident on this level")`; `local inv = T.ext(T.local_hero(), "inventory_system")`; `local ok = pcall(inv.add_equipment, inv, "slot_level_event", "whale_oil_barrel")` | `T.expect(ok, "add_equipment completed")`; `host_expect_log = {"create_equipment CRASHED"}`. Vanilla indexes the return of `GearUtils.create_equipment` without a nil check (`Vermintide-2-Source-Code/scripts/unit_extensions/default_player_unit/inventory/simple_inventory_extension.lua:858-876`; `Vermintide-2-Source-Code/scripts/unit_extensions/default_player_unit/inventory/gear_utils.lua:7`). Fix: the hook returns `{}` on failure (`weapon_tweaker/scripts/mods/weapon_tweaker/_wt_transform_runtime.lua:341, 352`) | note (R) |
| `qa/runtime/wt/issue_195_necro_package.lua` | #195 | `T.expect_rt("wt", "necromancer_fx_package_resident_if_dlc")` | the check reads `Managers.package:has_loaded("resource_packages/careers/bw_necromancer")` (`weapon_tweaker/scripts/mods/weapon_tweaker/_wt_runtime_checks.lua:1270-1280`). It returns "skip" when the Necromancer DLC is not owned: treat that as INCONCLUSIVE | note (R) |
| `qa/lua/tests/test_wt_deepwood_runtime.lua` (exists) | #236, #225 | run the offline suite | offline cover of the Deepwood staff runtime guard | note (U) |
| `qa/runtime/wt/issue_236_deepwood_wield_kruber.lua` | #236, #225 | Setup; wield the ranged slot on the local hero; `T.wait(2)` | `host_forbid_log = {"ep_r_index", "staff_life.lua"}`; the wielded slot is `slot_ranged`. Guard: `weapon_tweaker/scripts/mods/weapon_tweaker/_wt_cross_character_safety.lua:15-54` [unverified: the wield call for the local hero while the window has no focus, see `docs/audits/2026-11-13_FORMAL_AUDIT/evidence/C1.md` 4.3 row 36] | note (R) |
| `qa/runtime/wt/issue_162_saltzpyre_wield_data.lua` | #162 | `T.expect_rt("wt", "saltzpyre_dual_axes_wield_axe_falchion")`; `T.expect_rt("wt", "saltzpyre_dagger_wield_falchion")` | checks at `weapon_tweaker/scripts/mods/weapon_tweaker/_wt_runtime_checks.lua:1305, 1319` | note (R) for the data; the rendered animation is V |
| `qa/runtime/wt/issue_26_safe_hook.lua` | #26 | `T.expect_rt("wt", "wt_safe_hook_installed")`; `T.expect_rt("wt", "wt_safe_hook_preserves_multi_returns_with_nil_holes")` | helper at `weapon_tweaker/scripts/mods/weapon_tweaker/_safe_hook.lua` | note (R) |

**Reused in-mod checks.** `necromancer_fx_package_resident_if_dlc` (read: real engine read, behavioural). `saltzpyre_dual_axes_wield_axe_falchion`, `saltzpyre_dagger_wield_falchion`, `wt_safe_hook_installed`, `wt_safe_hook_preserves_multi_returns_with_nil_holes` (not read; the last one is behavioural by name).

**Left for humans.** #162: Saltzpyre dual axes and dagger look right in third person (V). #236: the staff looks and animates acceptably on Kruber (V).

**If it FAILS.** #362 with `ok == false`: read the error; if it comes from wt's own pre-processing rather than vanilla, the stub return was lost (`_wt_transform_runtime.lua:306-352`).

**Guardrail.** Never run the #362 case without `cosmetics_tweaker` loaded and the residency precondition true. In the original report cosmetics refused the raw spawn of the non-resident unit; without that refusal the engine may hard-crash instead of raising a Lua error.

---

### VP-CL-08 cim: Crafting in Modded forge and Athanor

| Field | Value |
|---|---|
| Issues | #71 (U, then R), #81 (R), #50 (R), #47 (R), #49 (R), #38 (R), #238 (R), #46 (R) |
| Arena | `keep` for #71, #47, #49, #38, #238, #46; `mission:military` for #81, #50 |
| Mods and stream | `cim_dev` (dev build); `gut_dev` for the in-mission inventory entry point |
| Boots | 2 (keep, mission) |
| Depends on | rig: `T.expect_rt`, `T.open_view`, `T.widget` |

**Setup.** None for the keep cases. The mission cases need the in-mission item customization window open [unverified: the open path; it is reached through gut's in-mission inventory, `gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_mission_inventory.lua`].

**Cases.**

| Script | Issue | Steps (T calls, in order) | Assertions (engine state read, with citation) | On PASS |
|---|---|---|---|---|
| `qa/lua/tests/test_cim_weave_economy.lua` (exists) | #71 | run the offline suite | offline cover of the forge-level lookup | note (U) |
| `qa/runtime/cim_dev/issue_71_talent_forge_level.lua` | #71 | `local w = Managers.backend:get_interface("weaves")` (`Vermintide-2-Source-Code/scripts/game_state/state_ingame_running.lua:799`); `local ok = pcall(w.get_talent_required_forge_level, w, "mercenary_helborgs_tutelage")`; `T.expect_rt("cim_dev", "weave_talent_forge_level_guard_present")` | `T.expect(ok, "adventure talent name does not nil-index")`. Vanilla function: `Vermintide-2-Source-Code/scripts/managers/backend_playfab/backend_interface_weaves_playfab.lua:1238` | note (R) |
| `qa/runtime/cim_dev/issue_81_hdr_not_forcebuilt.lua` | #81 | `T.expect_rt("cim_dev", "heroview_hdr_not_forcebuilt_in_mission")` | check at `crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_regression_forge_surfaces.lua` (stable copy `:852`); guard at `_cim_mission_forge_safety.lua:598` | note (R), "without Loremaster's Armoury" if not loaded |
| `qa/runtime/cim_dev/issue_50_customization_in_mission.lua` | #50 | open the item customization window in the mission (Setup); `T.wait(2)`; close it | `host_forbid_log = {"object_set_names", "Script Error"}`. Vanilla builds the preview from `LevelResource.object_set_names("levels/ui_store_preview/world")` (`Vermintide-2-Source-Code/scripts/ui/views/hero_view/windows/hero_window_item_customization.lua:382-410`). Hook: `crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_mission_forge_safety.lua` (stable copy `:281`) | note (R) |
| `qa/runtime/cim_dev/issue_47_49_property_bubbles.lua` | #47, #49 | `T.expect_rt("cim_dev", "stamina_movespeed_clamp_at_overcap")`; `T.expect_rt("cim_dev", "default_property_cap_is_five_bubbles")` | checks at `crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_regression_checks.lua:1047, 1223` | note (R) for the accounting; "bubbles apply to the equipped item" stays unproven, say so |
| `qa/runtime/cim_dev/issue_38_accessories_label.lua` | #38 | open the forge overview; read the text of widget `viewport_title_2` | `T.expect_eq(text, "ACCESSORIES", "label")`. Set at `crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_forge_ui_owner.lua:548` | note (R) |
| `qa/runtime/cim_dev/issue_238_trait_twin.lua` | #238 | `T.expect_rt("cim_dev", "trait_twin_copies_description_pair")` | check at `crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_regression_forge_surfaces.lua:755`; vanilla renderer `UIUtils.get_trait_description` (`Vermintide-2-Source-Code/scripts/helpers/ui_utils.lua:190`) | note (R) |
| `qa/runtime/cim_dev/issue_46_rpc_schema.lua` | #46 | `T.expect_rt("cim_dev", "rpc_schema_gate_drops_on_mismatch")` | check at `_cim_regression_forge_surfaces.lua:1168` | note (R) |

**Reused in-mod checks.** `weave_talent_forge_level_guard_present` (not read; structural by name). `heroview_hdr_not_forcebuilt_in_mission`, `stamina_movespeed_clamp_at_overcap`, `default_property_cap_is_five_bubbles`, `trait_twin_copies_description_pair`, `rpc_schema_gate_drops_on_mismatch` (not read; behavioural by name). Offline: `qa/lua/tests/test_cim_regression_module.lua`, `qa/lua/tests/test_cim_weave_loadout_owner.lua`.

**Left for humans.** #47: a property bubble click changes the equipped item's stats (R is possible once a forge "apply property" helper exists; until then V). #81: the forge with Loremaster's Armoury loaded.

**If it FAILS.** #71: `_cim_regression_checks.lua:41` area and the weave forge-level hook. #50: `_cim_mission_forge_safety.lua`.

---

### VP-CL-09 cos-cwv-et: cosmetics, weapon variants, enemy tweaker

| Field | Value |
|---|---|
| Issues | #20 (R boot), #33 (R), #14 (R), #45 (R), #67 (R), #55 (R), #240 (R), #37 (V), #186 (R only with Loremaster's Armoury) |
| Arena | `boot` for #20; `keep` for #33, #14, #45, #240; `mission:military` for #67, #55 |
| Mods and stream | `character_weapon_variants`, `cosmetics_tweaker`, `enemy_tweaker` (single-stream mods) |
| Boots | 2 (keep, mission with enemy_tweaker options set before boot) |
| Depends on | rig: `T.expect_rt`, `T.set` before boot, `host_forbid_log` |

**Setup.** #67: `roaming_size_multiplier` at its maximum (`enemy_tweaker/scripts/mods/enemy_tweaker/enemy_tweaker_data.lua:687`). #55: `horde_frequency_min = 20`, `horde_frequency_max = 30` (`enemy_tweaker/scripts/mods/enemy_tweaker/_et_pacing.lua:148`).

**Cases.**

| Script | Issue | Steps (T calls, in order) | Assertions (engine state read, with citation) | On PASS |
|---|---|---|---|---|
| `qa/runtime/character_weapon_variants/issue_20_itemmaster_exceptions.lua` | #20 | boot to the keep | `host_forbid_log = {"ItemMaster List has no item cwv_"}`. The message comes from the `ItemMasterList` index guard (`Vermintide-2-Source-Code/scripts/settings/equipment/item_master_list.lua:134`). Registration pass: `character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_item_registration_owner.lua:664` | note (R) |
| `qa/runtime/character_weapon_variants/issue_33_wield_hook_unique.lua` | #33 | `T.expect_rt("character_weapon_variants", "cwv_wield_hook_unique")` | check in `character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_regression_runtime_identity.lua:542` | note (R) |
| `qa/runtime/cosmetics_tweaker/issue_14_la_chars_compatible.lua` | #14 | `T.expect_rt("cosmetics_tweaker", name)` for `la_chars_compatible_different_char_denied`, `la_chars_compatible_no_sources_denied`, `la_chars_compatible_profile_fallback_deny`, `la_chars_compatible_profile_fallback_match`, `la_chars_compatible_same_char_allowed` | function under test: `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_apply_runtime.lua:112` | note (R) for the compatibility rule |
| `qa/runtime/cosmetics_tweaker/issue_45_rpc_schema.lua` | #45 | `T.expect_rt("cosmetics_tweaker", "cos_rpc_schema_present")` | check at `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_runtime_checks.lua:435` (structural) | note (R) |
| `qa/runtime/enemy_tweaker/issue_67_roaming_max.lua` | #67 | boot with the Setup option; load the mission; `T.wait_until(level started, 120)` | `host_forbid_log = {"spawn_zone_baker.lua", "Script Error"}`. Vanilla function: `SpawnZoneBaker.inject_special_packs` (`Vermintide-2-Source-Code/scripts/managers/conflict_director/spawn_zone_baker.lua:505`). Wrap: `enemy_tweaker/scripts/mods/enemy_tweaker/_et_roaming.lua:216` | note (R) |
| `qa/runtime/enemy_tweaker/issue_55_horde_frequency.lua` | #55 | boot with the Setup options; in the mission `T.wait(5)` | `CurrentPacing.horde_frequency` holds 20 and 30 [unverified: table shape; vanilla passes it to `ConflictUtils.random_interval` at `Vermintide-2-Source-Code/scripts/managers/conflict_director/conflict_director.lua:900`] | note (R) |
| `qa/runtime/enemy_tweaker/issue_240_alert_log_only.lua` | #240 | `T.expect_rt("enemy_tweaker", "et_alert_helpers_log_only_240")` | check at `enemy_tweaker/scripts/mods/enemy_tweaker/_et_log.lua:117` | note (R) |

**Reused in-mod checks.** `cwv_wield_hook_unique`, the five `la_chars_compatible_*`, `cos_rpc_schema_present`, `et_alert_helpers_log_only_240` (none read). Offline: `qa/lua/tests/test_cwv_entry_decomposition.lua`, `qa/lua/tests/test_cos_la_apply_runtime.lua`, `qa/lua/tests/test_cos_offhand_picker.lua`.

**Left for humans.** #14: a Grail Knight hat does not appear on a Warrior Priest body at mission start (needs Loremaster's Armoury and two careers; V). #37: browsing the shield picker does not apply the first option (needs Loremaster's Armoury; V). #186: Okri's Challenges from Loremaster's Armoury stay disabled (R only with that mod loaded: with `la_disable_okri_challenges` on, `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_okri.lua:8, 58`).

**If it FAILS.** #20: `_cwv_item_registration_owner.lua` (the existence test must use `rawget(ItemMasterList, key)`). #67: `_et_roaming.lua`.

---

### Issues in the population that need NO rig

| Issue | Evidence class | Exact command or file that proves it | Action |
|---|---|---|---|
| #12 cim CRAFT auto-equips | S | `git grep -c -F "backend_items.set_loadout_item" origin/master -- 'crafting_in_modded_dev/*.lua' 'crafting_in_modded/*.lua'` prints nothing (0 files; run 2026-11-13) | note (S) on the closed issue |
| #35 cosmetics dead husk hook | S | `git grep -c -E 'SimpleHuskInventoryExtension", *"extensions_ready"' origin/master -- cosmetics_tweaker` = 0; the hook is on `init` at `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_husk_identity_runtime.lua:218` | note (S) |
| #41 gut dead `NewsHeadUI` hook | S | `git grep -c "NewsHeadUI" origin/master -- 'gui_tweaker_dev/*.lua' 'gui_tweaker/*.lua'` = 0; registry row uses `NewsFeedUI` (`gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_hud_customizer.lua:36`; class at `Vermintide-2-Source-Code/scripts/ui/hud_ui/news_feed_ui.lua:18`) | note (S) |
| #93 gut compact ESC menu always on | S | `git grep -c -E 'setting_id *= *"gut_compact_esc_menu"' origin/master -- gui_tweaker_dev gui_tweaker` = 0; guard described at `gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_mod_tweaker_contracts.lua:931-938`; offline test `qa/lua/tests/test_gut_mod_tweaker_keep_routing.lua` | note (S) |
| #160 wt Executioner Sword in the dev anim picker | none | the dev anim picker is gone: `git ls-tree -r --name-only origin/master -- weapon_tweaker/scripts` has no `*anim_picker*` file | none; nothing left to verify |
| #42 enemy_tweaker RPC schema | none | the named check `et_rpc_schema_present` and the `et_br_fingerprint` RPC no longer exist; the schema gate now lives at `enemy_tweaker/scripts/mods/enemy_tweaker/_et_personal_handicap.lua:71, 89` | none; optional unit test under a T-track WP |
| #28 network-replay ring buffer | none | `bt_net_replay_bounded` and `_net_replay` have 0 hits in `*.lua` on master; `buff_tweaker` was retired | none |
| #82 cwv embed MoreItemsLibrary | X | closed "per maintainer" with no change; `_moreitemslibrary_embedded` exists only in `cosmetics_tweaker` | none (owner decision already made) |
| #64 Chest of Trials spawn multiplier | R | owned by open #471 (Part 2); in-mod check `cot_enemy_multiplier_cursed_chest_only` | verify under #471's card, not here |
| #409 Old Musket preview pose | V | owned by open #474 (Part 2) | none here |
| #89 cosmetics-only customization mount | R | `T.expect_rt("gut_dev", "issue89_cosmetics_only_customize_mount")` (`gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_mod_tweaker_contracts.lua:1096`); offline `qa/lua/tests/test_gut_cosmetics_mission_mount.lua` | note (R) when the keep boot of VP-CL-06 runs |
| #534 gt debug lines for other players | C | owner closed it with "removing verify fix, no change"; in-mod check `gt534_leash_share_wired` is structural | none; close reason should be `not_planned` (owner) |
| #131 Moonfire bow shots in Chaos Wastes | X | thread concludes working as designed | none |
| #135 weekly god override | none | superseded by #145 (closed, user-confirmed) | none |
| #335 localization status tags | S | superseded by #694; lifecycle tags removed from player UI | none |
| #627 Outrider launcher model | V | carries `wontfix`; model later replaced under #762 | none |
| #1158 peer-parity gates | C | structural deliverable; runtime proof is owed on open #423, #424, #426, #491 | none here |
| #1159 god-file decomposition | S | structural; `qa/check_decomposition_contracts.ps1` | none |

Count check: 9 cards cover 49 issues (#731; #59, #65, #194, #320, #43; #157, #294, #406; #34, #143, #39, #54, #27, #56, #68; #372, #379, #387; #76, #79, #216, #191, #190, #192, #78; #362, #195, #236, #225, #162, #26; #71, #81, #50, #47, #49, #38, #238, #46; #20, #33, #14, #45, #67, #55, #240, #37, #186). The table above covers the other 18. Total 67.

## Part 4. STABLE-TREE GAPS (round 1 finding D6-F04)

Closed issues whose fix exists in the `_dev` tree and not in the stable sibling. This feeds the tree-reconciliation work; nothing here is posted to GitHub.

How the rows were chosen: for every closed runtime issue, the identifiers added by the commits that cite it were collected (`docs/audits/2026-11-13_FORMAL_AUDIT/evidence/scripts/D6_fixcheck_all.py`). A row is listed when at least 60% of the identifiers that still live in the `_dev` tree are missing from the stable tree. The identifier in each row was then hand-picked as one that belongs to that issue, and re-checked with the grep below.

Grep used for the "Absent in stable" column (run on `origin/master` = `592253d1`, 2026-11-13), 0 hits in every row:
- identifiers without a colon: `git grep -c -w -F "<identifier>" origin/master -- <stable dir>/`
- log tags with a colon (`ct:...`): `git grep -c -F "<identifier>" origin/master -- <stable dir>/`

`<stable dir>` is `chaos_wastes_tweaker` for the first table and `general_tweaker` for the second.

The last column tells the reconciliation agent what kind of port it is. "yes" means a file with the same name exists in both trees and has drifted. "no" means the dev file has no same-named file in stable. For Chaos Wastes "no" is the normal case and does not mean the feature is missing: the dev tree was split into `_ct_*_owner.lua` modules while the stable tree keeps the older single-file layout (`chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/chaos_wastes_tweaker.lua`, over 12,000 lines), so a port is not a file copy. For General Tweaker "no" usually means a module that was never promoted.

What this does NOT prove: that the public stable build has the bug. A missing guard only matters if the stable tree contains the code path that needs it. That was not checked per row and is marked [unverified] for all rows. It is static evidence; a rig run of the stable build with the Part 3 scripts would settle it.

### Chaos Wastes Tweaker: 15 issues, plus 2 crash guards found by manual grep

| Issue | Fix identifier | Present in dev at path:line | Absent in stable (hits) | Crash-class? | Same-named file exists in stable? |
|---|---|---|---|---|---|
| #63 Add Optional Trial Chest Costs | `issue63_cot_cost_transaction` | `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_cot_cost.lua:141` | 0 | no (3-low) | no |
| #68 ct: native CW Belakor path variants of Fatshark | `ct:mapnode68` | `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_adventure_runtime_owner.lua:615` | 0 | no (no priority) | no |
| #114 ct_dev: Chest of Trials boon GUI can't fit >3 bo | `boon_offer_scrollbar_wired` | `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_regression.lua:797` | 0 | no (no priority) | no |
| #115 ct_dev: Shrine boon GUI can't fit >4 boon option | `boon_offer_scrollbar_wired` | `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_regression.lua:797` | 0 | no (no priority) | no |
| #121 ct_dev: Shared Reliquaries / Blessed Bots - bots | `pre_rarity` | `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_bot_weapon_chest_owner.lua:614` | 0 | no (no priority) | no |
| #133 ct_dev: Manann's Tempest description doesn't ref | `description_deus_crit_chain_lightning` | `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_adventure_runtime_owner.lua:308` | 0 | no (no priority) | no |
| #136 Synchronize Chaos Wastes Mission Selection | `apply_host_graph_snapshot_to_live_run` | `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_host_state_transport_owner.lua:647` | 0 | no (0-critical) | no |
| #157 wt + ct: cross-character ranged weapon (fireball | `ct:crash157` | `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_run_runtime_owner.lua:272` | 0 | yes | no |
| #294 [crash] ct: CTD spawning skulls_2023 'pup_skull_ | `_ct_pickup_unit_spawn_safe` | `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_pickup_spawn_owner.lua:248` | 0 | yes | no |
| #331 [Chaos Wastes Tweaker] Create Bots Category | `issue331_bot_coin_pickup_installed` | `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_runtime_owner.lua:233` | 0 | no (2-moderate) | no |
| #350 Open Trial Rewards During Combat | `issue350_cot_early_reward_policy` | `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_cot_early_reward_core.lua:31` | 0 | no (3-low) | no |
| #351 Convert Adventure Pickups to Pilgrim's Coins | `_ct351_rewrite_network_spawn` | `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_host_state_transport_owner.lua:480` | 0 | no (2-moderate) | no |
| #556 Granting talents as starting boons | `issue556_starting_talent_identity` | `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_tab_panel_owner.lua:385` | 0 | no (2-moderate) | no |
| #590 ct: Pool aliases exceed level capacity | `map_duplicate_level_aliases` | `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_adventure_pool.lua:603` | 0 | yes | yes |
| #1004 Starting Boons preview: show localized descripti | `issue1004_boon_hover_tooltip_wired` | `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_tab_panel_owner.lua:351` | 0 | no (3-low) | no |
| #291 [crash] CW journey-complete CTD on Cataclysm 3 - | `ct:journeyguard` | `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_journey_difficulty_guard.lua:43` | 0 | yes | no |
| #406 ct: client CTD on kill with kill-heal boon | `ct:406` | `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_meta_trait_boons.lua:401` | 0 | yes | no |

Notes:
- #291 and #406 are not among the 15 (their commits did not meet the 60% rule or cite other numbers) but their crash guards are absent from stable, so they are listed.
- #114 and #115 share one fix (the boon-offer scrollbar). #293 and #295 in the next table share one fix.
- #68 has a probe only, no fix (Part 3, VP-CL-04).
- #590 is the only Chaos Wastes row where the file exists in both trees (`_adventure_pool.lua`).

### General Tweaker: 14 issues

| Issue | Fix identifier | Present in dev at path:line | Absent in stable (hits) | Crash-class? | Same-named file exists in stable? |
|---|---|---|---|---|---|
| #139 Bots abandon split team after player down | `gt_bot139_teleport_veto_singleton_and_gated` | `general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_regression_checks.lua:638` | 0 | no (0-critical) | yes |
| #255 gt: 'disable ult effects' option doesn't work (N | `_ult_screen_fx` | `general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_solo_qol.lua:468` | 0 | no (0-critical) | yes |
| #293 [crash] gt: create_screen_gui 'Gui material not | `_gt_btlab_gui_deferred` | `general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_teleport_lab.lua:263` | 0 | yes | yes |
| #295 [crash] gt: game crashes shortly after enabling | `_gt_btlab_gui_deferred` | `general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_teleport_lab.lua:263` | 0 | yes | yes |
| #304 Keep dummy collision | `_gt_restore_keep_dummy_collision` | `general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_dummy_collision.lua:58` | 0 | no (3-low) | no |
| #308 Melee Latency Smoothing (Client-Side Prediction | `gt_melee_warning` | `general_tweaker_dev/scripts/mods/general_tweaker_dev/general_tweaker_dev_data.lua:1272` | 0 | no (1-major) | no |
| #320 Bots using potions | `bot_drink_potion_advanced_conditions_registered` | `general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_regression_checks.lua:1317` | 0 | no (1-major) | yes |
| #337 gt_dev: /recall_position_N teleports but reports | `_drain_pending_recall` | `general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_saved_positions.lua:188` | 0 | no (2-moderate) | no |
| #492 gt bots lock in aid branch, strand behind | `_gt492_should_suppress_pick` | `general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_aid_owner.lua:1051` | 0 | no (1-major) | no |
| #523 gt: bots actively heal hurt allies with kits | `issue523_bot_heal_allies_policy` | `general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_regression_checks.lua:1424` | 0 | no (2-moderate) | yes |
| #600 Fix Bot "Wait!" Command in Command Wheel Not Sto | `issue600_wait_aim_and_duration` | `general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_command_wheel.lua:355` | 0 | no (2-moderate) | no |
| #693 Client Unable to use Creature Spawner | `gt693_cs_client_request_wired` | `general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_creature_spawner.lua:1640` | 0 | no (2-moderate) | yes |
| #731 Client CTD on disconnect: VOIP channel nil | `channel_closed_during_send` | `general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_network_transmit_guard.lua:49` | 0 | yes | no |
| #939 Falling off ledge in godmode | `issue939_godmode_ledge_boundary` | `general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_regression_checks.lua:2246` | 0 | no (1-major) | yes |

Notes:
- #731 is a guard for a vanilla disconnect race, so the stable build is exposed regardless of which gt features it carries.
- #293 and #295 guard the bot teleport lab, a dev tool. Check whether the stable tree ships the lab at all before porting.
- #308 (melee latency smoothing) and #304 (keep dummy collision) are whole features that exist only in dev.

Summary for the reconciliation agent:

| Mod pair | Closed issues with a checkable fix | Dev-only (60% rule) | Crash-class among them |
|---|---|---|---|
| chaos_wastes_tweaker_dev vs chaos_wastes_tweaker | 24 | 15 | #157, #294, #590 (plus #291, #406 by manual grep) |
| general_tweaker_dev vs general_tweaker | 20 | 14 | #293, #295, #731 |
| gui_tweaker_dev vs gui_tweaker | 31 | 0 | none |
| crafting_in_modded_dev vs crafting_in_modded | 10 | 1 (#1360, `issue1360_ranalds_build_import`, `crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua:1014`) | none |

### The one fix that is gone from master: #568

| Field | Value |
|---|---|
| Closed issue | #568 Modded Progression: simulated daily claim calls PlayFab and forces game exit (0-critical, closed 2026-07-13) |
| Evidence at close | "Verified fixed in Modded Progression 0.2.18-dev by the project owner on 2026-07-13" (agent comment) |
| Fix commit | `9a2b717f` "mp 0.2.18: keep simulated daily claims local (#568)", 2026-07-13 |
| What is gone | 19 of the 39 identifiers that commit added no longer exist in any `.lua` file on master, including `_build_claim_wallet`, `_claim_markers`, `_daily_generation`, `_daily_is_claimed`, `_ensure_daily_state`, `_get_daily_state`, `_is_mp_daily_id`, `_new_daily_state`, `_persist_claim_wallet`, `_register_daily_templates`, `_set_daily_state` |
| What replaced it | A rewritten daily system with three owners, each registering its own runtime check: `modded_progression/scripts/mods/modded_progression/_mp_daily_ui_runtime.lua:5` (`issue1684_owned_daily_ui`; refusals log `[mp:1684] daily_ui_denied ... backend=none` at `:69`), `modded_progression/scripts/mods/modded_progression/_mp_daily_reroll_runtime.lua:5` (`issue1684_daily_reroll_backend_boundary`), `modded_progression/scripts/mods/modded_progression/_mp_calendar_login_guard.lua:5, 26` (`issue1684_calendar_login_action_boundary`, hook on `HeroWindowGotwfOverview._claim_daily_reward`) |
| Open owner now | #1684 "mp eac-untrusted brackets inert since game 6.12.0" (`diagnostics-armed`, 1-major) for the backend boundary; #573 "Add backend-free dailies and shillings" (`verify-fix`) for the feature |
| Action | No reopen. Post the Part 2 cross-reference on #1684. The owner's 2026-07-13 verification does not cover the current code: the #568 symptom ("claiming a simulated daily must not reach the backend or exit the game") must be an acceptance row of #1684's verification card, asserted with `T.expect_rt("modded_progression", "issue1684_owned_daily_ui")` and `T.expect_rt("modded_progression", "issue1684_calendar_login_action_boundary")` plus a keep case that claims one modded daily and forbids a backend call in the log [unverified: mod id string for Modded Progression; read it from the mod's main file] |

Related: #589 (mp login reward claim forces exit, closed 2026-07-14) survives: 8 of the 9 identifiers of its fix commit `00ecf571` are still on master.
