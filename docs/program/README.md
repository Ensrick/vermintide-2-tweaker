# The program: zero open issues, every feature verified

Start here. One page. Written 2026-11-13 after a formal audit of the whole repository.

## What happened

An audit of all mods, tooling, documents and the issue tracker found one root cause behind the backlog: **fixes exist, but nothing verifies them.** The only verifier was a human playing the game, and that stopped in September. 250 of the 329 open issues can be decided by a machine. So the program builds an unattended in-game test rig, burns the backlog down with scripted checks, fixes the critical defects found by reading the code, and then removes the structural causes.

- The audit: `docs/audits/2026-11-13_FORMAL_AUDIT/AUDIT.md`
- The plan: `PLAN.md` (waves, rules, decisions, metrics)
- Every card: `INDEX.md`

## If you are an agent

1. Read `PLAN.md` section 3 (eleven rules) and `EXECUTION_PROTOCOL.md` (how to claim, work and finish in this repository). That is all the required reading.
2. Pick a card from `INDEX.md`:
   - Take the first unclaimed **P0** card. If none is left, take the lowest-numbered card of the current wave (`PLAN.md` section 6) whose "Depends on" cards are merged.
   - A card is claimed when a pull request titled `<card id>: ...` exists (`gh pr list --state all --search "<card id> in:title"`).
   - Cards marked `Agent: strong` need a top-tier model. If you are not one, skip them.
3. Open the card in `wp/<TRACK>.md` or `vp/<BUCKET>.md`. Each card stands alone: goal, context with file and line, numbered steps, machine acceptance, guardrails, when to stop.
4. Do exactly the card. Paste the acceptance output into the pull request.
5. Stuck? Stop and write what you tried and what you need in the pull request. Do not guess and do not widen the card.

## Layout

| Path | What |
|---|---|
| `PLAN.md` | Goal, rules, decisions and their defaults, tracks, waves with exit gates, how one issue moves, shipping, metrics |
| `INDEX.md` | Generated table of every work package and verification pack; the P0 list |
| `CONVENTIONS.md` | Card formats, evidence classes, the rig's test API |
| `EXECUTION_PROTOCOL.md` | Worktree, branch, claim, commit, gate and ship mechanics for one card |
| `wp/H.md` | The rig: orchestrator, driver, arenas, slots, stills, co-op |
| `wp/G.md`, `wp/P.md`, `wp/T.md` | Governance and documents; release pipeline; test infrastructure |
| `wp/CIM.md`, `wp/GUT.md`, `wp/CWV.md`, `wp/CW.md`, `wp/GT.md`, `wp/COS.md`, `wp/WT.md` | Fixes and refactors per mod family, critical defects first |
| `vp/D1.md` to `vp/D5.md` | Verification packs for all 329 open issues, by mod family; each file starts with the issues that need no game |
| `vp/CLOSED.md` | The 613 closed issues: one reopen, links, and a regression pack for the 66 never verified at runtime |
| `ISSUE_LEDGER.tsv` | One row per open issue: class, cluster, disposition, the check that decides it, its pack and fix cards |

## The evidence classes (who may close what)

| Class | Evidence | Closes on machine evidence |
|---|---|---|
| U | engine-free unit test that loads production code | yes |
| S | static check | yes |
| R | rig run: a script in the running game reads engine state and asserts | yes |
| V | needs human eyes or ears | no: human list, with stills and state dumps |
| C | needs two real clients | no: two-machine rig run or human list |
| X | blocked or owner decision | no |

## For the owner

Decisions already taken and decisions waiting are in `PLAN.md` section 4. Every waiting decision has a default, so nothing is blocked on you; change a default by editing the table. The short list of things only you can do is the "Owner decisions" table at the end of each track file.
