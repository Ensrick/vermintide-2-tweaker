# Test rig (`tools/harness/`)

The rig lets an agent check mod behaviour against the running game with no human. It is the only way an agent may start Vermintide 2 (program rule R2, `docs/program/PLAN.md` section 3). Card track: `docs/program/wp/H.md`.

| Part | File | What it does |
|---|---|---|
| Orchestrator | `run.ps1` (+ `GameProcess.cs`, `New-RigProfile.ps1`, `Resolve-Vt2Install.ps1`) | Finds the game through the Steam registry key, builds an isolated profile, starts the retail exe on a private desktop inside a kill-on-close job, watches it, collects evidence, proves the owner's profile was not touched |
| Bootstrap | `bootstrap/vt2_rig_driver.mod` | The whole of private Workshop item `3839345856`. Inert unless the game runs in the modded realm, the command line carries `-vt2-test-run <nonce>` and the profile holds a plan with that nonce. Then it compiles the driver text from the plan. Never edit it: its bytes are what the item holds. The item's bundles were built from `docs/audits/2026-11-13_FORMAL_AUDIT/rig/bootstrap/package-src/` |
| Driver | `driver/vt2_rig_driver.lua` | Sent as hex text in every plan. Walks boot to keep, runs the cases, prints evidence lines, saves results, quits |
| Subscribe | `steam-ugc.ps1 -ItemId <id>` | Subscribes and installs a Workshop item through the game's own `steam_api64.dll` (no browser, no GUI) |
| Cases and plans | `qa/runtime/_rig/*.lua`, `qa/runtime/<mod>/issue_<N>_<slug>.lua`, `qa/runtime/plans/*.json` | Test scripts are Lua text; nothing is built or uploaded per script |

Rig root: `%LOCALAPPDATA%\vt2-harness` (`-RigRoot` overrides it; the author machine's existing root is `%USERPROFILE%\.claude\vt2-harness`). It holds `profile\` (the isolated profile, rebuilt from copies before each run) and `runs\<utc stamp>-<name>-<nonce>\` (evidence).

## Running

```powershell
pwsh -NoProfile -File tools/harness/run.ps1 -Plan qa/runtime/plans/smoke-keep.json [-RigRoot <dir>] [-Visible]
```

Exit code: 0 every case PASS; 1 at least one FAIL; 2 ERROR, TIMEOUT or INCONCLUSIVE, or the run did not complete; 3 the rig refused to start or isolation broke. It refuses when a Vermintide process exists, Steam is not running, free RAM is under 6 GiB, the bootstrap item is not installed, or another rig run holds the lock.

Offline tests (no game): `pwsh -File tools/harness/tests/GameProcess.Tests.ps1`, `pwsh -File tools/harness/tests/Profile.Tests.ps1`, and `qa/lua/tests/test_rig_driver.lua` inside `pwsh -File qa/check_lua_unit_tests.ps1`.

## Plan format

```json
{
  "name": "smoke-keep",
  "mods": ["1369573612"],
  "timeout": 300,
  "settle": 4,
  "arenas": ["keep", "mission:military"],
  "settings": { "max_fps": "30" },
  "cases": [ { "id": "smoke-keep", "arena": "keep", "file": "../_rig/smoke_keep.lua" } ]
}
```

`mods` are Workshop folder ids to enable (VMF first; the driver is added last). Every other mod in the copied list is disabled. `timeout` is the in-game run limit in seconds (the host limit is that plus 240). `file` is relative to the plan file. A case file returns a table:

```lua
return { issue = 0, timeout = 60, run = function(T) T.step("x"); T.expect(cond, "label") end }
```

The `T` helpers are listed in `docs/program/CONVENTIONS.md` section 3; the driver implements `step`, `note`, `wait`, `frames`, `wait_until`, `require`, `expect`, `expect_eq`, `expect_near`, `find_mod`, `local_player`, `local_hero`, `level_key`, `bots`, `ext`, `cmd`, `commands` today.

## Verdicts

| Verdict | Means |
|---|---|
| PASS | every assertion held |
| FAIL | an assertion did not hold: the product is wrong (the only verdict that says so) |
| ERROR | the script threw or did not compile: fix the script |
| TIMEOUT | the case ran longer than its `timeout` |
| INCONCLUSIVE | a `T.require` precondition was false, or the case was never reached |

## Six traps

1. Never launch the game any other way. Do not work around a refusal: wait.
2. The log is not live (it is buffered). Liveness comes from the driver's `vt2_rig_progress` settings checkpoints. Trust verdicts only after `RUN END` and a clean exit. A clean modded-realm exit code is `0xFA730001`, not 0.
3. Only FAIL means the product is wrong. Fix an ERROR or INCONCLUSIVE script; never retry a case until it turns green.
4. The profile is a copy. The owner's save and settings are copied in before each run and never written back. A case that needs a loadout or setting creates it.
5. The account is not a copy. A run signs in to the owner's real account. The driver's backend write shield (WP-H-14) must stay on.
6. A script cannot edit a VMF setting table in place (`mod:get` returns a copy). Use the mod's own writer or command.

## Reading a run

`runs\<run>\summary.md` has one line with the host verdict (`EXITED code=...`, `HOST-TIMEOUT-KILLED`, `VISIBLE-WINDOW`), the exit code, `isolation OK|BROKEN` and whether `RUN END` was seen, then one table row per case (verdict, assertion count, failed count, seconds, first failure). `summary.json` adds the seconds from start to each boot mark (`title`, `ingame`, `keep_ready`, `run_end`), the first script errors and notes. `evidence.txt` is every `[vt2t:<nonce>]` line in order; `console.log` is the game log; `plan.json` and `user_settings.after.config` are kept for replay.
