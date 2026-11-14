# Program plan: from 329 open issues to zero, with every feature verified

Status: ACTIVE. Written 2026-11-13 from the formal audit (`docs/audits/2026-11-13_FORMAL_AUDIT/AUDIT.md`).
Audience: any AI agent (Claude Opus, GPT Sol, or stronger) and the owner.
If you are an agent and you only read one file, read `docs/program/README.md` (one page). This file is the map; the cards are the work.

## 1. What "done" means

1. **Zero open issues.** Every issue is closed with evidence attached, declined by the owner, or merged into another issue that is.
2. **Every existing feature has a named verification method** (unit test, static check, rig script, or an entry on the short human list) recorded in the repository.
3. **The rig runs unattended** after every change and after every game patch, and its result decides what ships.
4. **The process fits the project**: one command to ship, one page to read before working, no bookkeeping commits.

## 2. The idea in five sentences

The audit found that fixes exist but nothing verifies them, because the only verifier was a human who stopped playing. 250 of the 329 open issues can be decided by a machine: 190 by a script inside the running game, 60 offline. So the program first builds an unattended in-game test rig, then burns the backlog down cluster by cluster with scripted checks, fixing what fails. In parallel it repairs the critical defects the audit found by reading the code, starting with the ones that can damage a player's saved loadouts. Then it removes the structural causes (duplicated dev and stable trees, shared state with no owner, a release pipeline larger than the risk) so the backlog does not grow back.

## 3. Operating rules for the program

These replace any older rule they conflict with. The owner approved the first three on 2026-11-13.

| # | Rule |
|---|---|
| R1 | **Machine evidence closes issues.** Evidence class U (unit test), S (static check) or R (rig run reading engine state) closes an issue. Class V (needs eyes or ears) and C (needs two real clients) go to the human list and never block other work. |
| R2 | **The game may be launched by an agent only through the rig** (`tools/harness/run.ps1`): isolated profile, private desktop, one instance at a time. Any other launch stays forbidden. |
| R3 | **No more manual test cards.** Do not write, pin or refresh `CURRENT LIVE TEST` comments. A verification script in `qa/runtime/` replaces the card. |
| R4 | **Test before the fix, where the defect reproduces offline.** Add the failing test, then the fix. |
| R5 | **Verify before shipping.** The rig tests the local build. A Workshop upload is never part of a card's acceptance. |
| R6 | **One card, one pull request, one worktree.** Never commit from the shared primary checkout. The draft pull request titled `<card id>: <title>` is the claim. |
| R7 | **A PASS is worded exactly:** "auto-verified (R) on `<mod> <version>` at `<commit>`, rig run `<id>`". Never "works", never "fixed". |
| R8 | **Do not add process.** No new labels, gates, documents or receipts unless a card in track G, P or T says so. |
| R9 | **Player data first.** A rig run signs in to the owner's real account. Anything that reads or writes loadouts, inventory or saves runs in the rig's isolated profile with the backend write shield on (`WP-H-14`), never calls a backend commit function, and restores what it changed. |
| R10 | **When blocked, stop and write it down** in the pull request: what you tried, what you need. Do not guess, do not widen the card. |
| R11 | **Still binding from before:** cite the decompiled source for engine claims; one hook per `(Class, method)` per mod; never write into a real Workshop subscription folder; clean-versioned public uploads need the owner's signal naming the version. |

## 4. Decisions

### Taken (owner, 2026-11-13)

| Id | Decision |
|---|---|
| D-01 | Verification must be fully autonomous: scripts verify and test features, including against the running game. |
| D-02 | Agents may launch Vermintide 2 unattended for testing (scope narrowed by R2 to the rig). |
| D-03 | Reports from anyone other than Ensrick and RainReligion are low priority unless they are real bugs. Feature requests outside a tweaker mod's scope may be declined. |
| D-04 | Closed issues are not trusted: re-verify, link or reopen on evidence. |

### Pending, with the default that agents follow until the owner says otherwise

| Id | Question | Default |
|---|---|---|
| OD-01 | While nobody tests by hand, does every dev change still need its own Workshop upload? | Batch: one upload per mod per day at most, only after a green rig run for that mod. Until track P makes shipping cheap, a card ends at "merged and rig-green"; the ship is a separate card (`WP-P` release train). |
| OD-02 | May an AI's judgment of a rig still close a class V issue? | Only for presence or absence (icon shown, mesh present, text not clipped). Motion, timing, sound and fine colour stay with a human. |
| OD-03 | Is the `weapon_tweaker_dev` friends-only mirror still needed? | Keep it, but stop treating it as a second product: one source, generated at build time (track P). |
| OD-04 | May git history be rewritten to shed 16.5 GiB of compiled bundles? | No. Stop tracking bundles going forward; leave history alone. |
| OD-05 | modded_progression and career_tweaker: build the planned scope, or trim the promise? | Fix what exists and correct the Workshop descriptions now; new scope waits for a written spec the owner approves (`WP-CIM` scope cards). |
| OD-06 | External feature request #1817 (ten players). | Decline as out of scope, with a polite note. |
| OD-07 | Second machine (PC-B) as the co-op client and bulk-run machine. | Yes once the solo rig is stable; needs a second Steam account that owns the game. Until then class C issues keep their scripted solo part and wait. |
| OD-08 | Stable (public) promotions need a per-version signal. | One digest per week listing every version ready to promote, each with its rig evidence; the owner answers once. |

The family and track files list further small decisions, each with a default. Agents never wait on a decision that has a default.

## 5. Tracks

| Track | What it delivers | Cards | Who |
|---|---|---|---|
| **H** Harness | The rig: orchestrator, in-game driver, test API, scenario library, stills, co-op | `wp/H.md` | strong agent for the core, any agent for scripts |
| **B** Burn-down | Every open issue decided: verification packs per cluster, fixes for what fails, closures | `vp/D1.md` to `vp/D5.md`, `vp/CLOSED.md` | any agent |
| **Family tracks** `WT`, `CWV`, `COS`, `CW`, `CIM`, `GT`, `GUT` | Critical defect fixes first, then one owner per shared state | `wp/<FAMILY>.md` | any agent; "strong" where the card says |
| **T** Test infrastructure | Offline tiers, regression suites that print machine-readable results, patch-day canary | `wp/T.md` | any agent |
| **P** Pipeline | One resumable ship command, no tracked bundles, CI under 10 minutes, rollback, one tree per mod | `wp/P.md` | any agent, in card order |
| **G** Governance | The rule changes above, a 6 KB agent entry, specs instead of cards, knowledge moved into the repo, document cleanup | `wp/G.md` | any agent |

## 6. Waves

Work inside a wave runs in parallel. A wave's exit gate is a machine check.

### Wave 0: stop the bleeding and unblock (no rig needed)

| Lane | Work | Cards |
|---|---|---|
| Safety | Every P0 card in the family tracks: player-data paths (crafted ids in loadouts, the loadout snapshot overwrite, the commit hook that drops callbacks, the non-existent forge screen), co-op crash classes (the Outrider projectile lookup index, the event join lock, the boon gate, the lobby-hash shim), public-build defaults (peer win/fail/restart, lag compensation). Each with an offline test first. | P0 cards in `wp/CIM.md`, `wp/GUT.md`, `wp/CWV.md`, `wp/CW.md`, `wp/GT.md`, `wp/COS.md`, `wp/WT.md` |
| Rules | Decision record for R1 to R3, the new agent entry, the execution protocol, tracker guard out of the pull-request gate, the broken lifecycle workflow | first cards of `wp/G.md`, `WP-P-01` |
| Quick closes | The "No rig needed" tables: 33 issues closable on static or offline evidence, 12 merges, 7 declines | top of each `vp/D*.md` |
| Rig | Orchestrator and driver to the first unattended boot-to-keep run | `wp/H.md` first cards |

**Exit gate:** `tools/harness/run.ps1 -Plan qa/runtime/plans/smoke-keep.json` exits 0 unattended; every P0 card is merged with its offline test green; open issues at or below 280.

### Wave 1: see what is actually true

| Lane | Work | Cards |
|---|---|---|
| Rig | Suite sweep (every `/<mod>_regression_test` on every boot), mission and Chaos Wastes arenas, the `T` API complete, local-build staging | `wp/H.md` |
| Truth | Run the smoke and sweep plans against the current public and dev builds. Triage every failing check into: script defect, environment, real regression. This repeats the only experiment (2026-09-21) that ever found real regressions. | `VP-*-01` packs, `vp/CLOSED.md` regression pack |
| Tests | Regression runners print one engine line per check and expose a programmatic entry; marker-only checks move offline; checks that report PASS without running are fixed | `wp/T.md`, family cards |

**Exit gate:** a sweep report exists for every mod (`qa/runtime/reports/sweep-<date>.md`) with zero unclassified failures; every real regression has an issue and a card.

### Wave 2: burn the backlog down

One agent per bucket (D1 to D5), each working its verification packs in order: write the scripts for a cluster, run the pack on the rig, close what passes, open a fix card for what fails, rerun. The closed-issue regression pack runs alongside.

**Exit gate:** no open issue of class U, S or R without either a passing run (closed) or a failing run with a fix card in progress. Expected open count: about 80 (classes V, C and X).

### Wave 3: remove the causes

| Lane | Work | Cards |
|---|---|---|
| Pipeline | Resumable ship command, pin pull request removed, bundles untracked, CI scoped, rollback verb, then one tree per mod | `wp/P.md` in order |
| Shared state | Loadout store with one mutation API; appearance decision with one owner; animation remap with one table; lookup-table appends through one helper | "strong" cards in `wp/GUT.md`, `wp/COS.md`, `wp/WT.md`, `wp/CWV.md` |
| Forks | Reconcile Chaos Wastes, General and GUI dev and public trees deliberately, keeping the stronger side per module | `wp/CW.md`, `wp/GT.md`, `wp/GUT.md` |
| Knowledge | Documents consolidated, memory-store knowledge imported, inventories generated | `wp/G.md` |

**Exit gate:** each structural card's rig pack is green before and after the change; a dev ship is one command and under 15 minutes; required reading for a one-line fix is under 20 KB.

### Wave 4: humans, co-op and scope

- **Human list.** One generated list of the class V issues, each with the rig's stills and state dumps, for one playtest session by the owner or RainReligion.
- **Co-op.** Two-machine rig runs for the class C issues (`wp/H.md` co-op card), or the same human session.
- **Scope.** modded_progression and career_tweaker: spec first, then one slice at a time, each with its test.

**Exit gate:** zero open issues.

## 7. How one issue moves

```
open issue
  -> is it in a "No rig needed" table?            yes -> close / merge / decline with the stated evidence
  -> does it need a fix first (table in its VP)?   yes -> fix card -> merged
  -> its verification pack script runs on the rig
        PASS  -> evidence comment (R7 wording) -> close
        FAIL  -> fix card (the script is now the regression test) -> rerun
        INCONCLUSIVE / ERROR -> fix the script, not the verdict
  -> class V or C remainder -> human list entry with stills and state dumps
```

Evidence comment (the only comment an agent posts when closing):

```
Verification: auto-verified (R) on <mod> <version> at <commit>, rig run <run id>.
Script: qa/runtime/<mod>/issue_<N>_<slug>.lua
Assertions: <n> passed, 0 failed. Game build <build id>.
Not covered by automation: <one line, or "nothing">.
```

For a closed issue that the regression pack re-verifies, the same comment is added without reopening. A failing regression entry opens a new issue that cites the closed one.

## 8. Shipping during the program

- A card that changes mod source ends when its pull request is merged and its acceptance is green. It does not upload.
- Uploads happen in release trains (OD-01): per mod, at most daily, after a green rig run of that mod's packs against the merged build. Dev streams need no approval. Clean public versions go on the weekly digest (OD-08).
- Until the pipeline cards land, a release train uses today's `tools/ship/ship.ps1` procedure unchanged.
- Dev/stable pairs, until the single-tree migration: a fix for a public-release issue is applied to both trees in the same card.

## 9. Metrics (reported by `tools/program/board.ps1`, track G)

| Metric | Start (2026-11-13) | Target |
|---|---|---|
| Open issues | 329 | 0 |
| Issues waiting on a human | 282 | under 70, then 0 |
| In-game checks executed unattended per boot | 0 | all (792) |
| Rig scripts in `qa/runtime/` | 0 | one per class R issue or cluster |
| Dev ship, operator steps and minutes | 21 steps, 86 min best case | 1 command, under 15 min |
| `qa-gate` median | 21.9 min | under 10 min |
| Required reading for a one-line fix | 356 KB | under 20 KB |
| Duplicated dev/stable Lua lines | 152,289 | 0 |

## 10. Index

The full list of cards is generated into `INDEX.md` (133 work packages (P0 20, P1 71, P2 38, P3 4), 85 verification packs.) It starts with the P0 cards, which come first whatever the wave.
