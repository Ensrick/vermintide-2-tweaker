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

Offline tests (no game): `pwsh -File tools/harness/tests/<name>.Tests.ps1` for `GameProcess`, `Profile`, `HostLog`, `FindRunLog`, `SmokePlan` and `Slots`, and `qa/lua/tests/test_rig_driver.lua` inside `pwsh -File qa/check_lua_unit_tests.ps1`. `pwsh -File qa/check_runtime_scripts.ps1` checks the shape of every case and plan in seconds (fields, file-name issue number, no engine access at the top level, every `T.<name>` in the stub `qa/runtime/_stub/T.lua`); it proves shape only, never that a case passes.

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

The `T` helpers are listed in `docs/program/CONVENTIONS.md` section 3; the driver implements `step`, `note`, `wait`, `frames`, `wait_until`, `require`, `expect`, `expect_eq`, `expect_near`, `find_mod`, `local_player`, `local_hero`, `level_key`, `bots`, `ext`, `cmd`, `commands`, `shield`, `shared` today.

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

- Once: `pwsh -File tools/harness/New-RigSlotItems.ps1` prepares the six item folders (private, placeholder content: the bootstrap's bundles plus an inert `vt2_rig_slot.mod`) and prints the `ugc_tool -c item.cfg -x` and `steam-ugc.ps1 -ItemId <id>` commands; `-Publish` runs them. Record each id in `slots.psd1`.
- Per build: `pwsh -File tools/harness/stage-build.ps1 -Mod <dir> -Slot <n>` builds the mod from the worktree that holds the script (through `tools/ship/ship.ps1 -BuildOnly` under the machine-wide build lock; `-NoBuild` stages the existing `bundleV2`), replaces the slot folder's files with `bundleV2\*` and writes `slot.json` (commit, version, file hashes). It refuses any id that is not in `slots.psd1`, a real mod's id and the bootstrap.
- Per run: plan field `"local_builds": [{ "mod": "<dir>", "slot": <n> }]`. `run.ps1` refuses (exit 3) when the slot's files no longer match `slot.json` (Steam may restore the placeholder at any time: re-stage). The slot takes the real id's place in the mod list, the real id is disabled, the staged version must appear in the mod's load banner, and `summary.json` lists the build's commit, version and `real_folder_unchanged`.

## Reading a run

`runs\<run>\summary.md` has one line with the host verdict (`EXITED code=...`, `HOST-TIMEOUT-KILLED`, `VISIBLE-WINDOW`), the exit code, `isolation OK|BROKEN` and whether `RUN END` was seen, then one table row per case (verdict, assertion count, failed count, seconds, first failure). `summary.json` adds `keep_ready_seconds` (log timestamp of `KEEP READY` minus the first log line; the polled `marks_seconds.keep_ready` is later because the log is buffered), the driver's own `keep_ready_driver_t`, the host log findings, `loaded_versions` from the `[<tag>:LOAD] v<version>` banners, the seconds from start to each boot mark, the first script errors and notes. `evidence.txt` is every `[vt2t:<nonce>]` line in order; `console.log` is the game log (the game is started with `--default-console-log-path <run>\console.log`; `log_source` says whether that switch worked or the profile's `console_logs` folder was used after 20 s); `plan.json` and `user_settings.after.config` are kept for replay.
