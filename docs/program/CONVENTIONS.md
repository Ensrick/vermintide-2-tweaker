# Program conventions: work packages (WP) and verification packs (VP)

Audience: the auditors writing plan content now, and the weaker agents (Opus, GPT Sol) who will execute it later.
An executing agent will read ONE card and act. It will not have the audit in context. Write every card so it stands alone.

## 1. Program in one paragraph

Goal: zero open issues, every existing feature with a named verification method, codebase and process at a professional standard.
The audit's central finding: fixes exist (about 97% of spot-checked `verify-fix` fixes are present on master) but nothing verifies them, because the only verifier was a human who stopped playing. 250 of 329 open issues (76%) can be decided by automated evidence. So the program builds an unattended in-game test rig first, then burns the backlog down cluster by cluster, then removes the structural causes.

## 2. Evidence classes (who may close what)

| Class | Meaning | Closes an issue on machine evidence? |
|---|---|---|
| U | engine-free Lua unit test (`qa/lua/tests`) that loads production code | yes |
| S | static check (lint, schema, data-table check against the decompile) | yes |
| R | rig run: a script inside the running game reads engine state and asserts | yes |
| V | needs human eyes or ears | no: goes to the human list, with rig stills and state dumps attached |
| C | needs two real clients | no, unless a two-machine rig run exists; the solo part is still scripted |
| X | blocked or owner decision | no |

A rig PASS is reported as "auto-verified (R) on <mod> <version> <commit>, run <id>", never as "works".

## 3. The rig (what cards may assume exists)

- `tools/harness/run.ps1 -Plan <plan.json>`: starts the game unattended on a private desktop with an isolated profile, runs the plan, writes `summary.json` / `summary.md`, exits non-zero on FAIL/ERROR. One instance at a time (it holds a lock; callers just wait).
- Test scripts live in `qa/runtime/<mod>/issue_<N>_<slug>.lua` (one case per file, returns a table). Plans live in `qa/runtime/plans/<name>.json`.
- Arenas: `boot` (log only), `keep`, `mission:<level_key>`, `deus` (Chaos Wastes), `coop` (two machines, later).
- Every boot also runs every loaded mod's `/<mod>_regression_test` suite and records each check as an assertion (`T.expect_rt`).
- Verdicts per case: PASS, FAIL (product wrong), ERROR (script bug), TIMEOUT, SKIP, INCONCLUSIVE (precondition not reached). Only FAIL means the product is wrong.

Script helper API (`T`), usable inside a case:

| Call | Meaning |
|---|---|
| `T.step(label)` | name the next action |
| `T.wait(seconds)`, `T.frames(n)`, `T.wait_until(fn, timeout, label)` | pause the case while the game runs |
| `T.require(cond, label)` | precondition; false = INCONCLUSIVE |
| `T.expect(cond, label)`, `T.expect_eq(got, want, label)`, `T.expect_near(got, want, tol, label)` | assertions; the case continues after a failure |
| `T.cmd(name, ...)` | run a mod chat command |
| `T.expect_rt(mod_id, check_name)` | a named in-mod regression check passed in this boot |
| `T.local_hero()`, `T.bots()`, `T.first_bot_unit()` | units, waiting until alive |
| `T.ext(unit, system)` | `ScriptUnit.extension` or INCONCLUSIVE |
| `T.set(mod_id, setting, value)` | change a mod option for this case (restored after) |
| `T.spawn(breed, offset)`, `T.pickup(name, offset)` | spawn, tracked for cleanup |
| `T.as_bot(bot_unit)` | drive a bot's input: `tap_attack`, `hold_attack`, `defend`, `fire`, `charge_shot`, `activate_ability`, `wield(slot)` |
| `T.open_view(name, params)`, `T.widget(view, name)` | open a UI view, read a widget's content table |
| `T.shot(label)` | capture a still for AI or human review |
| `T.note(key, value)` | free evidence line |
| `host_expect_log = {...}`, `host_forbid_log = {...}` (case fields) | log lines that must / must not appear |

Engine calls a script may use (load level, change hero, equip, spawn, buff, teleport, open view, end level) are listed with decompile citations in `docs/audits/2026-11-13_FORMAL_AUDIT/evidence/C1.md` section 4.3. Cite the engine read you assert on as `Vermintide-2-Source-Code/<path>:LINE`.

## 4. Work package card (WP)

File: `docs/program/wp/<TRACK>.md`. IDs: `WP-<TRACK>-<NN>`. Tracks: `H` harness, `G` governance and docs, `P` release pipeline, `T` test infrastructure, and one per mod family for fixes and refactors: `WT`, `CWV` (cwv + WOC), `COS` (cosmetics, portraits, dialogue), `CW` (Chaos Wastes, events, enemies), `CIM` (crafting, progression, career), `GT` (general, lighting, legacy), `GUT` (GUI).

```
### WP-<TRACK>-<NN> <imperative title, max 10 words>

| Field | Value |
|---|---|
| Priority | P0 (data loss, crash, soft-lock, co-op break) / P1 / P2 / P3 |
| Size | S (under 1 h) / M (half a day) / L (several sessions; say how to split) |
| Agent | any / strong (needs design judgment: say why) |
| Depends on | WP ids, or none |
| Issues | open issue numbers this closes or advances (or none) |
| Source | audit finding ids, e.g. A5-F01 |
| Streams | which trees: `x_dev/` only, `x/` only, or both (and why) |

**Goal.** One sentence: the observable end state.

**Context.** 3 to 8 lines. What is wrong and why, with `path:line` for the mod code and `Vermintide-2-Source-Code/<path>:line` for engine facts. Enough that the agent does not need the audit.

**Steps.**
1. Numbered, imperative, concrete: file, function, what to change to what. Name the exact identifiers.
2. Include the test to add (file name, what it asserts) BEFORE the fix step when the defect is reproducible offline.

**Acceptance (machine, no human).**
- OFFLINE: exact command and the expected result (e.g. `lua5.1 qa/lua/run.lua test_x` passes; `git grep -c "..."` = 0).
- RIG (if the behaviour is runtime): the script to add under `qa/runtime/`, its arena, and the assertions that must PASS.
- State which evidence class closes each listed issue.

**Guardrails.** What not to touch, what not to "fix" on the way, known traps.

**Stop and escalate if.** Concrete conditions under which the agent must stop and write the question down instead of guessing.
```

Rules for WP authors:
- One defect or one coherent change per WP. If a fix needs an owner decision, write the WP for the default option and name the decision id in "Stop and escalate".
- Order steps so the repo is never left broken between steps.
- Never write "verify in game" as acceptance. If no machine check is possible, say which part is class V/C and what the rig still asserts.
- Dev/stable pairs: until the single-tree migration lands, a fix for a public-release issue must be applied to BOTH trees; say so in Streams and Steps.
- Do not propose new process, labels, documents or gates unless the WP is in track G/P/T.
- Max 12 WPs per family. Merge small related items; drop S3 hygiene unless it removes a trap.

## 5. Verification pack card (VP)

File: `docs/program/vp/<BUCKET>.md`. IDs: `VP-<BUCKET>-<NN>`. One VP per cluster of issues that one rig script family can decide.

```
### VP-<BUCKET>-<NN> <cluster slug>: <title>

| Field | Value |
|---|---|
| Issues | #a (R), #b (R), #c (C: solo part only) ... |
| Arena | boot / keep / mission:<level_key> / deus |
| Mods and stream | which mod ids must be loaded; public or dev build; option values needed |
| Boots | how many separate boots and why |
| Depends on | WP-H ids (rig features needed, e.g. "T.open_view"), fix WPs if the fix is not on master |

**Setup.** Career, items, settings, world state the cases need, and how the script creates each (engine call with citation, or mod command).

**Cases.** One row per script file:

| Script | Issue | Steps (T calls, in order) | Assertions (engine state read, with citation) | PASS closes? |
|---|---|---|---|---|

**Reused in-mod checks.** `/<mod>_regression_test` check names this pack relies on (`T.expect_rt`), and whether each actually tests behaviour.

**Left for humans.** Per issue: what remains class V or C after the script passes, in one line each.

**If it FAILS.** What a FAIL most likely means and which WP or file to look at first.
```

Rules for VP authors:
- Prefer reading engine state the fix cannot move (unit paths, extension fields, buff lists, backend item tables, widget content) over the mod's own log receipt.
- A case must set up its own preconditions and clean up. No dependence on case order.
- Convert the issue's newest CURRENT LIVE TEST card: numbered steps become `T.step` + calls, "Expected" becomes assertions, "no error/crash" becomes `host_forbid_log`.
- Also list, per bucket, the issues that need NO rig: a table `Issue | evidence class | exact command or file that proves it | action (close / merge into #N / owner decision)`.

## 6. Style

Plain English, short sentences, no em dashes, no invented labels. Use repo-relative paths. Never write a personal path (`C:\Users\...`): use `<repos>` for the folder holding the repos. Cite, do not assert. Mark anything not read as `[unverified]`.
