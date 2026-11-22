# Test rig (`tools/harness/`)

The rig lets an agent check mod behaviour against the running game with no human. It is the only way an agent may start Vermintide 2 (program rule R2, `docs/program/PLAN.md` section 3). Card track: `docs/program/wp/H.md`.

| Part | File | What it does |
|---|---|---|
| Orchestrator | `run.ps1` (+ `GameProcess.cs`, `New-RigProfile.ps1`, `Resolve-Vt2Install.ps1`) | Finds the game through the Steam registry key, builds an isolated profile, starts the retail exe on a private desktop inside a kill-on-close job, watches it, collects evidence, proves the owner's profile was not touched |
| Bootstrap | `bootstrap/vt2_rig_driver.mod` | The whole of private Workshop item `3839345856`. Inert unless the game runs in the modded realm, the command line carries `-vt2-test-run <nonce>` and the profile holds a plan with that nonce. Then it compiles the driver text from the plan. Never edit it: its bytes are what the item holds. The item's bundles were built from `docs/audits/2026-11-13_FORMAL_AUDIT/rig/bootstrap/package-src/` |
| Driver | `driver/vt2_rig_driver.lua` | Sent as hex text in every plan. Walks boot to keep, runs the cases, prints evidence lines, saves results, quits |
| Helper groups | `driver/lib/*.lua`, table `API.md` | Sent with every plan like the driver; each adds helpers to every case's `T` (`T.set`, `T.shot`, ...). `API.md` lists every helper, its status, the engine call it wraps and the plans that exercise it |
| Subscribe | `steam-ugc.ps1 -ItemId <id>` | Subscribes and installs a Workshop item through the game's own `steam_api64.dll` (no browser, no GUI) |
| Cases and plans | `qa/runtime/_rig/*.lua`, `qa/runtime/<mod>/issue_<N>_<slug>.lua`, `qa/runtime/plans/*.json` | Test scripts are Lua text; nothing is built or uploaded per script |

Rig root: `%LOCALAPPDATA%\vt2-harness` (`-RigRoot` overrides it; the author machine's existing root is `%USERPROFILE%\.claude\vt2-harness`). It holds `profile\` (the isolated profile, rebuilt from copies before each run) and `runs\<utc stamp>-<name>-<nonce>\` (evidence).

## Running

```powershell
pwsh -NoProfile -File tools/harness/run.ps1 -Plan qa/runtime/plans/smoke-keep.json [-RigRoot <dir>] [-Visible]
```

Exit code: 0 every case PASS; 1 at least one FAIL; 2 ERROR, TIMEOUT or INCONCLUSIVE, or the run did not complete; 3 the rig refused to start or isolation broke. It refuses when a Vermintide process exists, Steam is not running, free RAM is under 6 GiB, the bootstrap item is not installed, or another rig run holds the lock.

Offline tests (no game): `pwsh -File tools/harness/tests/<name>.Tests.ps1` for `GameProcess`, `Profile`, `HostLog`, `FindRunLog`, `SmokePlan` and `Slots`, and `qa/lua/tests/test_rig_driver.lua` and `test_rig_api_*.lua` (simulated game: `qa/lua/tests/_rig_driver_env.lua`) inside `pwsh -File qa/check_lua_unit_tests.ps1`. `pwsh -File qa/check_runtime_scripts.ps1` checks the shape of every case and plan in seconds (fields, file-name issue number, no engine access at the top level, every `T.<name>` in the stub `qa/runtime/_stub/T.lua` and in `API.md`); it proves shape only, never that a case passes. `qa/runtime/plans/api-selftest.json` calls each available keep helper once in the game.

## Plan format

```json
{
  "name": "smoke-keep",
  "mods": ["1369573612"],
  "timeout": 300,
  "settle": 4,
  "arenas": ["keep", "mission:military"],
  "settings": { "max_fps": "30" },
  "expect_mods": ["VMF"],
  "host_expect_log": ["\\[gt:LOAD\\] v"],
  "host_forbid_log": [],
  "host_allow_log": [ { "pattern": "<regex>", "reason": "why this one line is benign" } ],
  "cases": [ { "id": "smoke-keep", "arena": "keep", "file": "../_rig/smoke_keep.lua" } ]
}
```

`mods` are Workshop folder ids to enable (VMF first; the driver is added last). A plan id missing from the copied mod list gets an entry, so a mod that is not installed shows up as a forbidden log line instead of being skipped silently. Every other mod in the copied list is disabled. `timeout` is the in-game run limit in seconds (the host limit is that plus 240). `file` is relative to the plan file. `expect_mods` are VMF mod ids the smoke case asserts are loaded.

Host log checks (`Read-HostLog.ps1`, on the final log): every `host_expect_log` regex must match; any `host_forbid_log` regex, and by default `<<Script Error>>`, `Lua Stack`, `was not found in the workshop folder`, `Syntax error in .mod file` and `Failed to run callback` on the game's own lines, plus the two shield defaults, is forbidden. A forbidden hit or a missing expected line makes the run exit 1 and is named in the summary. Do not disable a default; add one `host_allow_log` entry with its reason for a line proven benign. `pwsh -File tools/harness/Read-HostLog.ps1 -LogFile <log> -PlanFile <plan> -Nonce <n> -ExitCode` judges a saved log on its own.

Full-set smoke plans: `pwsh -File tools/harness/New-SmokePlan.ps1` writes `qa/runtime/plans/smoke-public.json` (inventory rows with `Public = $true`) and `smoke-dev.json` (rows with stream `dev` or `single`) from `tools/mod-inventory.psd1`; `-Check` reports drift. Never edit them by hand. `smoke-broken-fixture.json` is a negative control: it names a mod id that is not installed and must exit 1.

A case file returns a table:

```lua
return { issue = 0, timeout = 60, run = function(T) T.step("x"); T.expect(cond, "label") end }
```

Every `T` helper, available or planned, is a row of `tools/harness/API.md` (the case rules are `docs/program/CONVENTIONS.md` section 3). `T.set(mod_id, setting, value)` changes one mod option through the mod's own `set` with its `on_setting_changed` and puts the old value back when the case ends; `T.shot(label)` only records the request until WP-H-10. `T.career(profile, career)` and `T.equip(career, slot, item)` use the game's own setters (never a commit); the write shield holds the change back from the game's next commit, and the case end undoes it. `T.open_view`, `T.close_view`, `T.widget` and `T.press` drive views through IngameUI transitions and hotspot fields, never OS input; a view left open is closed at cleanup. `T.first_bot_unit`, `T.as_bot` (bot input methods, one update each) and `T.pickup` are the actor helpers; the keep has no bots, so their cases run in a mission arena. `T.transmit_spy(rpc_names)` records the RPCs this machine sends (the solo check for lookup-index bugs) and passes every call through.

## Arenas and mission helpers (WP-H-04)

`arenas` run in the plan's order and may repeat: `["keep", "mission:military", "keep"]` loads Righteous Stand after the keep cases and returns to the keep before quitting. The run always starts in the keep; arenas of cases the plan does not list follow at the end. A level change goes through the host's `Managers.mechanism:debug_load_level(level, 0)` (`Vermintide-2-Source-Code/scripts/managers/game_mode/game_mechanism_manager.lua:880-892`; the keep is the hub level `inn_level`). The driver waits for `StateIngame` with that level and a live hero, prints `LEVEL READY level=<key> load_seconds=<s>`, and `summary.json` lists every load under `level_loads`. An arena other than `keep`, `mission:<key>` or `level:<key>` ends its cases INCONCLUSIVE.

A case file may also return a `cleanup` function (it gets the case's `T`). The driver calls it once when a case that started ends, whatever the verdict, in the main update and before the helpers' own cleanups, and prints `CASE CLEANUP id=<case> ok=<true|false>`. An error in it becomes `NOTE id=<case> key=case_cleanup_error` and never changes the verdict. It must not wait (`T.wait`, `T.frames`, `T.wait_until` and `T.main` need the case coroutine), and it should be safe to call after the case already undid its work.

Mission helpers. Each change is undone when the case ends, also after FAIL or ERROR, and is printed as `CLEANUP id=<case> actions=<n> errors=<n>`:

| Helper | Does | Engine call |
|---|---|---|
| `T.main(fn, ...)` | runs `fn(...)` in the driver's main update, outside the case coroutine, and returns its results (its error is raised in the case); one update | engine calls that take a unit fail inside a coroutine ("Attempting get_data with reference from another lua state", lead run 2026-11-15) |
| `T.spawn(breed, offset[, timeout])` | queues one enemy next to the hero (`offset` a Vector3 or `{x, y, z}`), returns the unit once alive; killed at cleanup if still alive | `conflict_director_testify.lua:18-22`, `spawned_units_by_breed` `conflict_director.lua:2144` |
| `T.kill(unit)` | kills a living unit | `AiUtils.kill_unit`, `ai_utils.lua:1326` |
| `T.teleport(unit, position)` | moves a unit with a `teleport_to` locomotion | `player_unit_locomotion_extension.lua:1005` |
| `T.invincible(on)` | sets the hero's health-extension invincibility, restored at cleanup | `generic_health_extension.lua:496-512` |
| `T.end_level(result)` | `"win"` completes, `"fail"` fails the level as host | `game_mode_manager.lua:636, 645` |
| `T.return_to_keep([timeout])` | loads `inn_level` and waits until the keep is ready | as above |

Use bots or these host-side calls as the actor; never OS input. Every helper above that passes a unit to the engine runs through `T.main`; do the same in a case for any engine call that takes a unit or an extension method that may touch one (e.g. `T.main(function() return buff_ext:has_buff_type(name) end)`). Plain table reads such as `HEALTH_ALIVE[unit]` are fine in the coroutine.

## Regression sweep (WP-H-03)

`qa/runtime/_rig/sweep_regression.lua` lists every chat command containing `regression_test` and runs each with `T.cmd`, two seconds apart. `T.cmd` runs the command in the main update (a suite's checks touch units), and the driver prints every VMF echo as `OUT mod=<VMF mod name> via=echo text="..."`. A plan with `"sweep": true` (`qa/runtime/plans/sweep-public.json`, `sweep-dev.json`, generated by `New-SmokePlan.ps1`) makes `run.ps1` call `Parse-Sweep.ps1`. It writes `sweep.json` (one row per check: suite, mod, check, verdict PASS/FAIL/SKIP, the runner's raw word, detail) and `sweep.md` into the run folder, and a FAIL row makes the run exit 1. Row and summary patterns live in `tools/harness/sweep-formats.psd1`; every runner today echoes `  <VERDICT>: <check>[ -- <detail>]`. After WP-T-01 the engine lines `[<prefix>:rt] <check> <VERDICT> <detail>` are read from the console log. XPASS and BAD-SHAPE count as FAIL, XFAIL as SKIP. A suite that printed nothing is a SKIP row, never a PASS; one whose command never returned is INCONCLUSIVE. Each suite's row count is compared with its own summary line.

`T.expect_rt(mod_id, check)` asserts on a row captured earlier in the same boot (`mod_id` is the VMF mod name, e.g. `gt_dev`): PASS or XPASS passes, FAIL, XFAIL or BAD-SHAPE fails, and SKIP, an unknown check or a suite not run in this boot is INCONCLUSIVE. Run the sweep case (or `T.cmd("<mod>_regression_test")`) before it.

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
5. The account is not a copy. A run signs in to the owner's real account. The driver's backend write shield must stay on (see below).
6. A script cannot edit a VMF setting table in place (`mod:get` returns a copy). Use the mod's own writer or command.

## The real account: what a run does and never does (backend write shield, WP-H-14)

The profile is isolated; the account is not. The modded realm signs in to the owner's real account.

What a run does on the account, shield or not:
- It signs in. The game's normal sign-in cloud scripts run exactly as when the owner starts the game; they happen at the title screen, before the backend mirror exists, so before the shield can go up.
- It reads the account: inventory, loadouts, talents, keep paintings, quests.
- Cloud-script requests the game builds after the shield is up are passed through unchanged. The driver names each one in the evidence (`SHIELD saw request=<name>` after `KEEP READY`; for `updateHeroAttributes` the key names, never values). The shield does not block them.
- Statistics, weave data and weapon poses are not sent in the modded realm anyway: they sit behind `GameSettingsDevelopment.read_only_backend`, which the modded realm sets (`Vermintide-2-Source-Code/scripts/settings/game_settings_development.lua:49-52`; checked at `scripts/managers/backend_playfab/playfab_mirror_base.lua:2826`, `:2839`, `:2857`).

What a run never does while the shield is on (driver 0.4.3, `install_shield`, on the live mirror instance only, from the first tick the mirror exists):
- Send a career loadout or talent change: `_check_career_data` answers "not dirty" (`playfab_mirror_base.lua:2885`) and prints `SHIELD blocked=characters_data` with the number of changed fields.
- Send user data: `_commit_user_data` sends nothing (`:2111`, `:2911`) and prints `SHIELD blocked=user_data`.
- Send the keep painting layout: the layout comparison (`:2877-2883`) sees the acknowledged string; `SHIELD blocked=keep_decorations changed_slots=<n>` when a case changed it.
- Call a commit function itself. The game's own commits still run and complete, so no caller waits for its callback.
- Leave a changed official row behind: at `KEEP READY` the driver snapshots `mirror._career_data` with `qa/runtime/_shared/official_mirror.lua` and puts it back before it quits (`SHIELD restore changed_fields=<n>`).
- Write the owner's local profile files (`isolation: OK` in every summary).

`run.ps1` checks the log afterwards: any `Enqueuing ExecuteCloudScript request updateHeroAttributes` line or any `UpdateUserData` line from the game makes a passing run exit 1 and is listed in `summary.md` (`Read-HostLog.ps1`). `summary.json` also says whether `SHIELD installed` came before the first `_commit_internal`. Cases read the shield's counts with `T.shield()` and get shared helpers with `T.shared("official_mirror")`.

A plan may set `backend_shield: false` only when its cases test commit behaviour itself, and then needs a `backend_shield_reason` (enforced by `qa/check_runtime_scripts.ps1`, WP-H-13). Never switch the shield off to make a case pass.

## Rig slots: testing an unshipped build (WP-H-07)

The game loads only Workshop items Steam lists as subscribed, and a mod's bundles are found by package name, not folder id. So the rig owns six private items ("VT2 Rig Slot 1" to "6", ids in `slots.psd1`) whose content it overwrites with a local build. A real mod's Workshop folder is never written.

- Once: `pwsh -File tools/harness/New-RigSlotItems.ps1` prepares the six item folders (private, placeholder content: the bootstrap's bundles plus an inert `vt2_rig_slot.mod`) and prints the `ugc_tool -c item.cfg -x` and `steam-ugc.ps1 -ItemId <id>` commands; `-Publish` runs them. ugc_tool asks the Vermintide 2 modding-EULA question on stdin and exits 1 "You did not agree to the EULA" without an answer; `Invoke-UgcTool.ps1` answers `y` once the prompt appears, as VMB does. Record each id in `slots.psd1`. The six items were created on 2026-11-15 (ids 3840301411, 3840301616, 3840301649, 3840301687, 3840301709, 3840301739).
- Per build: `pwsh -File tools/harness/stage-build.ps1 -Mod <dir> -Slot <n>` builds the mod from the worktree that holds the script (through `tools/ship/ship.ps1 -BuildOnly` under the machine-wide build lock; `-NoBuild` stages the existing `bundleV2`), replaces the slot folder's files with `bundleV2\*` and writes `slot.json` (commit, version, file hashes). It refuses any id that is not in `slots.psd1`, a real mod's id and the bootstrap.
- Per run: plan field `"local_builds": [{ "mod": "<dir>", "slot": <n> }]`. `run.ps1` refuses (exit 3) when the slot's files no longer match `slot.json` (Steam may restore the placeholder at any time: re-stage). The slot takes the real id's place in the mod list (a copy of the real entry, multi-line description included, inserted right before it; the run is refused when the real id has no entry, never appended at the end), the real id is disabled, the staged version must appear in the mod's load banner, and `summary.json` lists the build's commit, version and `real_folder_unchanged`.

## Reading a run

`runs\<run>\summary.md` has one line with the host verdict (`EXITED code=...`, `HOST-TIMEOUT-KILLED`, `VISIBLE-WINDOW`), the exit code, `isolation OK|BROKEN` and whether `RUN END` was seen, then one table row per case (verdict, assertion count, failed count, seconds, first failure). `summary.json` adds `keep_ready_seconds` (log timestamp of `KEEP READY` minus the first log line; the polled `marks_seconds.keep_ready` is later because the log is buffered), the driver's own `keep_ready_driver_t`, the host log findings, `loaded_versions` from the `[<tag>:LOAD] v<version>` banners, the seconds from start to each boot mark, the first script errors and notes. `evidence.txt` is every `[vt2t:<nonce>]` line in order; `console.log` is the game log (the game is started with `--default-console-log-path <run>\console.log`; `log_source` says whether that switch worked or the profile's `console_logs` folder was used after 20 s; in the rig runs of 2026-11-15 the retail exe ignored the switch and the fallback found the log); `plan.json` and `user_settings.after.config` are kept for replay.
