# Track H: the unattended test rig

## Track brief

The rig lets an agent verify mod behaviour against the running game with no human. It has three parts:

- **Orchestrator** (`tools/harness/run.ps1`, PowerShell 7 plus `GameProcess.cs`): builds an isolated profile, starts the game on a private desktop, watches it, collects evidence, proves the owner's profile was not touched.
- **Bootstrap** (private Workshop item `3839345856`, one constant `.mod` file): inert unless the rig started the game; then it compiles the driver text from the run plan.
- **Driver** (`tools/harness/driver/vt2_rig_driver.lua`, sent as text each run): walks the game from boot to the keep, runs the plan's cases, prints evidence lines, quits. Test scripts are Lua text in `qa/runtime/`; nothing is built or uploaded per script.

### Proven on 2026-11-13 and 2026-11-14 (author machine, game build 25901688; evidence in `docs/audits/2026-11-13_FORMAL_AUDIT/evidence/rig-runs/`)

| # | Fact | How it was shown |
|---|---|---|
| 1 | The retail game starts without the launcher: `binaries_dx12\vermintide2_dx12.exe -eac-untrusted --bundle-dir ../bundle --ini settings --silent-mode -skip-splash`, working directory `binaries_dx12`, child environment `SteamAppId=552500`. | Run `e1-direct-visible`: log shows `eac-untrusted = true`, `realm = modded`. |
| 2 | Profile isolation works. With child-only `USERPROFILE`, `APPDATA`, `LOCALAPPDATA`, the save folder, settings and console log all land in the rig profile. SHA-256 of the owner's `user_settings.config`, `save_data.sav`, `launcher.config` was identical before and after every run. | `[Save] Save dir:` line; `isolation: OK` in each `summary.json`. `bundle/settings.ini` places all four paths under `%APPDATA%`. |
| 3 | A private desktop keeps the game invisible: no window of the game's job reached the user desktop in a 540 s run. | Run `smoke-keep-81c936d6`. |
| 4 | `-skip-splash` carries the title screen into network init with no key press. Without a driver the 6.13 main menu then waits. | `Enter Substate StateTitleScreenInitNetwork` 31 s after start. |
| 5 | The EAC line `Integrity violation: NO_BOOTSTRAPPER` is normal in the modded realm. | The same line is in the owner's own launcher-started modded sessions. |
| 6 | The console log is buffered. Lines reach disk late and a killed process loses its tail. | E1 log ends mid-line at +39 s of a 130 s run. |
| 7 | The game loads only Workshop items that Steam lists as subscribed. A folder Steam does not know is ignored, whatever it contains. | A folder `9000000099` with a valid mod produced `was not found in the workshop folder`; the handle table held exactly the 39 subscribed ids. This corrects `vt2-mod-updater`'s documentation. |
| 8 | A Workshop item can be created and subscribed with no GUI and no web cookies: `ugc_tool.exe -c item.cfg -x` creates it, and the game's own `steam_api64.dll` (`SteamAPI_ISteamUGC_SubscribeItem`, `DownloadItem`) subscribes and installs it. | `tools/harness/steam-ugc.ps1`: item state went 0 to 5 (subscribed, installed) in seconds. |
| 9 | A mod's `.mod` file is plain Lua that the game compiles with `loadstring`, and the object its `run()` returns gets `update(dt)` and `on_game_state_changed` from the game's own mod manager (`Vermintide-2-Source-Code/scripts/managers/mod/mod_manager.lua:368-373, 146-176, 208-226, 486-502`). So the driver needs no mod framework and can be delivered as text. | Source reading; exercised by run `smoke-keep-4b32903a` (also `-5f5ca4b0`, `-9d23f887`). |
| 10 | Retail exe switches that exist: `--default-console-log-path`, `--default-crash-dump-path`, `--suppress-messagebox`, `--silent-mode`, `--lua-heap-mb-size`, `--no-console`, `--deadlock-detector-enabled`, `--deadlock-detector-timeout`. There is no no-rendering and no log-flush switch. | String scan of the exe. |
| 11 | The driver walks the game from process start to the keep with no input, runs a case and quits. Keep ready 54 to 62 s after process start with VMF and the driver only; the process is gone 3 to 4 s after `RUN END`. | Runs `smoke-keep-4b32903a`, `-5f5ca4b0`, `-9d23f887` (2026-11-14): 5 of 5 assertions PASS, `RUN END` seen, `isolation: OK`. |
| 12 | A clean modded-realm run ends with process exit code `0xFA730001` (4201840641), not 0: the engine sets it when it logs the EAC notice of fact 5 (`[Application] setting exit code to 0xfa730001`). Judge a run by `RUN END` and the log's `[Log end]`, never by the exit code alone. | All three runs: `summary.json` verdict `EXITED code=4201840641` with rig exit 0. |
| 13 | The game makes one routine commit about 5 s after the keep loads (`_commit_internal "1"`). Unshielded it sends `updateHeroAttributes` with one key, `keep_decorations`: the account's painting layout decoded and encoded again (`Vermintide-2-Source-Code/scripts/managers/backend_playfab/backend_interface_keep_decorations_playfab.lua:7-22, 62-64`; compared as a string at `playfab_mirror_base.lua:2879-2883`). The owner's own sessions show the same request. No character data was in it. | `smoke-keep-5f5ca4b0`: `SHIELD saw request=updateHeroAttributes keys="keep_decorations"`. The 19 painting slots loaded in all three runs equal, slot by slot, the owner's last own keep visit (2026-08-21). The body of the first run's request was not logged. |
| 14 | The write shield can be installed before that commit, and the commit still completes. Driver 0.4.2 installs it on the first tick on which the backend mirror exists (title screen, 1.5 s after `Backend Enabled`) and answers the painting comparison with the acknowledged value. | `smoke-keep-9d23f887`: `SHIELD installed t=8.5 state=StateTitleScreen`, later `_commit_internal "1"` and `commit result "success"`, and no `updateHeroAttributes` request anywhere in the log. |

### Status of the remaining unknowns

| Unknown | Status |
|---|---|
| Driver reaches the keep, runs a case, quits by itself | **Proven 2026-11-14**, three runs (`smoke-keep-4b32903a`, `-5f5ca4b0`, `-9d23f887`): keep ready 54 to 62 s after process start, case PASS, clean self-quit. VMF and the driver only; the full mod sets are WP-H-02. |
| Write shield is up before the game's first save | **Proven 2026-11-14** (`smoke-keep-9d23f887`, driver 0.4.2): shield installed at the title screen; the start-up commit completed and sent nothing. That a changed loadout is held back is not yet shown. WP-H-14. |
| Suite sweep captures every mod's regression output | Not yet run. WP-H-03. |
| `debug_load_level` loads a mission in retail | Not yet run. WP-H-04. |
| Hands-free entry into the Chaos Wastes hub | Unknown. WP-H-05. |
| A still can be captured from a private desktop | Unknown. WP-H-10. |
| Two-machine co-op | Needs owner decision OD-07. WP-H-12. |

### Six traps

1. **Never launch the game any other way.** `run.ps1` refuses when a Vermintide process exists, when free RAM is under 6 GiB, or when another rig run holds the lock. Do not work around a refusal: wait.
2. **The log is not live.** Liveness comes from the driver's settings-file checkpoints (`vt2_rig_progress`). Verdicts are trusted only after `RUN END` and a clean exit.
3. **Only FAIL means the product is wrong.** ERROR is a script bug, INCONCLUSIVE is a precondition not reached. Fix the script; never retry a case until it turns green.
4. **The profile is a copy.** The owner's save and settings are copied in before each run and never written back. A case that needs a specific loadout or setting creates it; it never assumes the copy has it.
5. **The account is not a copy.** A rig run signs in to the owner's real account. The driver's backend write shield (WP-H-14) is up from the title screen and stops loadout, talent, user-data and keep-painting changes from being sent; never switch it off to make a case pass. Sign-in itself runs the game's normal sign-in cloud scripts, as in any start.
6. **A script cannot edit a VMF setting table in place** (`mod:get` returns a copy). Change state through the mod's own writer or command.

---

### WP-H-01 Land the rig prototype in the repository with offline tests

| Field | Value |
|---|---|
| Priority | P0 |
| Size | M |
| Agent | any |
| Depends on | none |
| Issues | #1338 (agent bridge: superseded by the rig) |
| Source | C1 (design), PF-1 |
| Streams | tooling only |

**Goal.** `tools/harness/` holds the working prototype from the audit, with tests that run without the game.

**Context.** The prototype files are in `docs/audits/2026-11-13_FORMAL_AUDIT/rig/`: `run.ps1`, `GameProcess.cs`, `steam-ugc.ps1`, `driver/vt2_rig_driver.lua`, `bootstrap/vt2_rig_driver.mod`, `bootstrap/item.cfg`, `cases/*.lua`, `plans/*.json`. They were exercised on the author machine on 2026-11-13 (see the table above).

**Steps.**
1. Move the prototype to `tools/harness/` (`run.ps1`, `GameProcess.cs`, `steam-ugc.ps1`, `driver/`, `bootstrap/`) and the cases and plans to `qa/runtime/_rig/` and `qa/runtime/plans/`. Replace the hard-coded Steam path with one resolved from the registry key `HKCU:\Software\Valve\Steam\SteamPath`, and the rig root default with `%LOCALAPPDATA%\vt2-harness`.
2. Add `tools/harness/tests/GameProcess.Tests.ps1`: start `cmd.exe /c exit 7` on a private desktop with two child-only variables, assert exit code 7, zero windows on the user desktop, parent environment unchanged.
3. Add `qa/lua/tests/test_rig_driver.lua`: load `tools/harness/driver/vt2_rig_driver.lua` with stub globals (`Application.user_setting` returning a plan with two hex-encoded cases, `Managers`, `Unit.alive`, `Boot`), call `driver:on_game_state_changed("enter", "StateIngame")` and `driver:update(0.1)` in a loop, and assert the printed lines contain `RUN BEGIN`, one `CASE END ... verdict=PASS`, one `verdict=FAIL` (the second case fails an `expect`), `RUN END`, and that `Boot.quit_game` became true. Add cases for ERROR (script throws), TIMEOUT and INCONCLUSIVE (`T.require(false)`).
4. Add `tools/harness/tests/Profile.Tests.ps1`: run the profile-building part of `run.ps1` against a fixture `user_settings.config` (factor it into `New-RigProfile.ps1` first) and assert: the plan block parses back, only the plan's mod ids are enabled, the driver entry exists once, `vt2_rig_results` and `vt2_rig_progress` from an earlier run are gone.
5. Write `tools/harness/README.md` (one page): what the rig is, the plan format, the verdicts, the five traps above, how to read `summary.md`.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -File tools/harness/tests/GameProcess.Tests.ps1` and `Profile.Tests.ps1` exit 0; `pwsh -File qa/check_lua_unit_tests.ps1` passes including `test_rig_driver`.
- `git grep -n "C:\\\\Users" -- tools/harness qa/runtime` returns nothing.

**Guardrails.** Do not change the bootstrap `.mod` (its bytes are what Workshop item 3839345856 holds). Do not add the rig to `tools/mod-inventory.psd1`: it is not a product mod.

**Stop and escalate if.** The driver cannot be loaded under the offline stubs without changing its behaviour: report which engine call is in the way.

---

### WP-H-02 Smoke plans green: boot to keep with VMF only, then with every mod

| Field | Value |
|---|---|
| Priority | P0 |
| Size | M |
| Agent | any |
| Depends on | WP-H-01 |
| Issues | #1497, #595 (class: boot soft-lock, missing bundled file) |
| Source | D3 (VP-D3-01), C1 E3 |
| Streams | tooling only |

**Goal.** One command proves that the game reaches the keep unattended with a given mod set and that every mod in the set loaded, and exits 0.

**Context.** `qa/runtime/plans/smoke-keep.json` enables VMF and the driver only. The same case must also run with the full public set and the full dev set, because #1497 (infinite loading into the keep) and #595 (a bundled file missing) were boot failures that no gate caught.

**Steps.**
1. Add `--default-console-log-path <run folder>\console.log` to the arguments in `run.ps1` and read the log from there (the switch exists in the retail exe; keep the old lookup as fallback if the file does not appear within 20 s).
2. Extend `qa/runtime/_rig/smoke_keep.lua`: for every mod id in the plan's `expect_mods` list assert `T.find_mod(id) ~= nil`, and note its version (`mod.MOD_VERSION` when exposed, else from the load banner).
3. Add host-side log assertions to `run.ps1`: plan fields `host_expect_log` and `host_forbid_log` (regex lists) evaluated on the final log; defaults forbid `<<Script Error>>`, `Lua Stack`, `was not found in the workshop folder`, `Syntax error in .mod file`, `Failed to run callback`. A forbidden hit makes the run exit 1 and names the line.
4. Add plans `smoke-public.json` (every public Tweaker item plus its dependencies, ids from `tools/mod-inventory.psd1` rows with `Public = $true`) and `smoke-dev.json` (every dev or single-stream item). Generate both from the inventory with `tools/harness/New-SmokePlan.ps1` so they cannot drift.
5. Record the measured seconds to `KEEP READY` in `summary.json` for each plan.

**Acceptance (machine, no human).**
- RIG: `pwsh -File tools/harness/run.ps1 -Plan qa/runtime/plans/smoke-keep.json` exits 0 with `RUN END` seen and `isolation OK`. Same for `smoke-public.json` and `smoke-dev.json`; if a mod fails to load, that is a real finding: file it, do not edit the plan to hide it.
- A deliberately broken fixture (a plan naming a mod id that is not installed) exits 1 on the forbidden log line.

**Guardrails.** Do not raise timeouts to make a run pass. Do not disable a forbidden-log default; add a per-plan allow entry with the reason if a line is proven benign.

**Stop and escalate if.** The game does not reach the keep unattended on this build: attach `summary.json` and the last 80 log lines and stop. That is a harness design question, not something to patch around.

---

### WP-H-03 Suite sweep: run every in-mod regression suite on every boot

| Field | Value |
|---|---|
| Priority | P0 |
| Size | M |
| Agent | any |
| Depends on | WP-H-02; better after WP-T-01 |
| Issues | #1656, and every issue whose card cites a named in-mod check |
| Source | D1-F2, B2-F02, B2-F03, C1 |
| Streams | tooling only |

**Goal.** Every loaded mod's `/<mod>_regression_test` runs unattended and each check becomes one row in `sweep.json` with PASS, FAIL or SKIP.

**Context.** About 790 in-game checks exist and run only when a human types a command. The one live run (2026-09-21, #1656) found 22 failures, 4 of them real regressions. The suites print through `mod:echo` and `mod:info`; the driver already captures those by wrapping the `VMFMod` log methods while a command runs (`T.cmd` returns the lines and prints each as an `OUT` evidence line).

**Steps.**
1. Keep `qa/runtime/_rig/sweep_regression.lua` as the case: list commands containing `regression_test` with `T.commands("")`, run each with `T.cmd`, wait two seconds between suites.
2. Add `tools/harness/Parse-Sweep.ps1`: read the run's `evidence.txt`, group `OUT` lines by mod, and classify each check line. Until WP-T-01 lands the formats differ per mod, so keep the patterns in one table `tools/harness/sweep-formats.psd1` (mod id, PASS regex, FAIL regex, summary regex). After WP-T-01 the single format is `[<mod>:rt] <check> PASS|FAIL|SKIP <detail>` read straight from the log.
3. Write `sweep.json` (`mod`, `check`, `verdict`, `detail`) and `sweep.md` into the run folder, and fail the run (exit 1) when any check is FAIL.
4. Implement `T.expect_rt(mod_id, check_name)` in the driver from the captured lines of the current boot, so issue scripts can assert on a named check.
5. Run the sweep on the public set and on the dev set. For every FAIL write one line in `qa/runtime/reports/sweep-<date>.md` with a classification: script defect, environment, or real regression. Real regressions get an issue that cites the check name.

**Acceptance (machine, no human).**
- RIG: `run.ps1 -Plan qa/runtime/plans/sweep-dev.json` produces `sweep.json` with at least 500 rows; the count per mod matches the mod's registered check count within 5%.
- OFFLINE: `Parse-Sweep.ps1` has a test over a recorded `evidence.txt` fixture with known counts.
- The report file exists and has zero rows classified "unknown".

**Guardrails.** Do not edit a check to make it pass in this card. Do not count a check that printed nothing as PASS: it is SKIP.

**Stop and escalate if.** A suite's command crashes the game or never returns: mark that suite INCONCLUSIVE, continue with the others, and file it.

---

### WP-H-04 Mission arena: load a level as host with bots, act, return, quit

| Field | Value |
|---|---|
| Priority | P1 |
| Size | M |
| Agent | any |
| Depends on | WP-H-02 |
| Issues | enables about 88 Adventure-mission issues (packs in `vp/D1.md` to `vp/D5.md`) |
| Source | C1 E4 |
| Streams | tooling only |

**Goal.** A plan with arena `mission:<level_key>` loads that level from the keep, runs its cases, and the run ends cleanly.

**Context.** The driver calls `Managers.mechanism:debug_load_level(level_key, 0)` (`Vermintide-2-Source-Code/scripts/managers/game_mode/game_mechanism_manager.lua:880-892`, Adventure path `mechanisms/adventure_mechanism.lua:580-594`), waits for `StateIngame` with the wanted level key and a live hero, then runs the cases. `qa/runtime/_rig/mission_military.lua` is the first case: level key, hero alive, bots alive, spawn one enemy with `conflict:spawn_queued_unit` (`conflict_director_testify.lua:18-22`), read a buff extension.

**Steps.**
1. Run `mission_military.lua` and fix what the first real run shows (argument order of `spawn_queued_unit`, the breed count accessor). Cite the engine line for each call you settle on.
2. Add driver helpers and document them in `tools/harness/README.md`: `T.spawn(breed_name, offset)` returning the unit once alive and tracking it for cleanup; `T.kill(unit)`; `T.teleport(unit, position)`; `T.invincible(on)`; `T.end_level(result)` using the game mode manager's `complete_level` or `fail_level` (`game_mode_manager.lua:636, 645`); `T.return_to_keep()`.
3. After each case run cleanup: kill spawned units, restore invincibility, restore changed settings.
4. Add `mission-smoke.json`: keep, then `mission:military`, then back to the keep, then quit.

**Acceptance (machine, no human).**
- RIG: `mission-smoke.json` exits 0 three times in a row; `summary.json` records the load seconds.
- OFFLINE: `test_rig_driver.lua` covers the arena sequencing with a stub mechanism (level key changes after N updates).

**Guardrails.** Use bots or direct extension calls as the actor; do not send OS input. Keep the lobby private.

**Stop and escalate if.** `debug_load_level` does nothing in retail: report it and switch this card to the vote path (`matchmaking_manager.lua:1006`), as a new step, not a guess.

---

### WP-H-05 Chaos Wastes arena

| Field | Value |
|---|---|
| Priority | P1 |
| Size | M |
| Agent | strong (the hub entry path is unproven and needs engine reading) |
| Depends on | WP-H-04 |
| Issues | enables about 57 Chaos Wastes issues (`vp/D3.md`) |
| Source | C1 E5 |
| Streams | tooling only |

**Goal.** A plan with arena `deus` or `deus:<level_key>` reaches the Chaos Wastes hub, starts a run or one level, and can grant and read boons.

**Context.** `deus_mechanism.lua:1002-1030` has `debug_load_level` and `debug_load_deus_level`. Reaching the hub with no input is the unknown. Boons: `deus_run_controller:add_power_ups` (`state_ingame_testify.lua:167-211`).

**Steps.**
1. Try `debug_load_level("morris_hub")` from the keep. If the mechanism does not switch to `deus`, read `game_mechanism_manager.lua` for the mechanism switch call and use that. Record the working sequence with citations in `tools/harness/README.md`.
2. Add helpers: `T.deus_run_controller()`, `T.grant_boon(name)`, `T.has_boon(name)`, `T.deus_coins()`, `T.set_deus_coins(n)`.
3. Add `deus-smoke.json`: hub, one level, grant one vanilla boon, assert it is active, quit.

**Acceptance (machine, no human).** RIG: `deus-smoke.json` exits 0 three times in a row.

**Guardrails.** Vanilla boons only in the smoke plan. Custom boons belong to the Chaos Wastes packs.

**Stop and escalate if.** No hands-free path into the hub exists after reading the mechanism code: write what was tried; Chaos Wastes packs then stay on the human list until solved.

---

### WP-H-06 Complete the test API that the verification packs use

| Field | Value |
|---|---|
| Priority | P1 |
| Size | L (split per helper group: UI, inventory, input, wire) |
| Agent | any; one helper group per pull request |
| Depends on | WP-H-04 |
| Issues | all class R issues |
| Source | `docs/program/CONVENTIONS.md` section 3; rig feature lists at the end of `vp/D1.md`, `vp/D2.md`, `vp/D3.md` |
| Streams | tooling only |

**Goal.** Every helper named in the verification packs exists, is documented, and has an offline test with stubs plus one rig case.

**Context.** The packs were written against the API table in the conventions and name extra helpers. Helpers are Lua text under `tools/harness/driver/lib/`, sent with the plan like the driver.

**Steps.**
1. Collect the helper names: the conventions table, plus each pack file's "rig features needed" section. Put the union in `tools/harness/API.md` as one table: name, what it does, the engine call it wraps with a decompile citation, which packs use it.
2. Implement in four groups, one pull request each: **UI** (`T.open_view`, `T.widget`, `T.press(widget, hotspot)` using the `on_right_click`/`on_pressed` content fields as in `hero_window_cosmetics_inventory_testify.lua:7-9`, `T.close_view`); **inventory and career** (`T.set_career` via `request_profile`, `T.equip(slot, item_key or backend_id)`, `T.backend_items(filter)`, `T.loadout(career)`), all read-only against the backend except through the game's own setters, never a commit call; **actor input** (`T.as_bot(unit)` wrapping `PlayerBotInput` methods at `player_bot_input.lua:262-325`); **wire** (`T.transmit_spy(rpc_name)`: record arguments passed to `network_transmit` for one RPC during a step, the solo check for lookup-index bugs from A2 section 6c and D1 primitive P7).
3. Add `T.set(mod_id, setting, value)` through the mod object's `set` and its `on_setting_changed`, restored in cleanup.
4. Add `T.shot` as a stub that records the request; the capture itself is WP-H-10.

**Acceptance (machine, no human).**
- OFFLINE: each helper has a stub test in `qa/lua/tests/test_rig_api_*.lua`.
- RIG: `qa/runtime/plans/api-selftest.json` exercises each helper once and exits 0.
- `tools/harness/API.md` lists every helper name that appears in any `qa/runtime/**/*.lua` (a script checks this).

**Guardrails.** No helper may call a backend commit function or write a save. No helper sends OS input.

**Stop and escalate if.** A pack needs something only pixels can answer: that part is class V, do not fake it with state.

---

### WP-H-07 Rig slots: test unshipped builds without touching real mod folders

| Field | Value |
|---|---|
| Priority | P1 |
| Size | M |
| Agent | any |
| Depends on | WP-H-02 |
| Issues | none (enables rule R5, verify before shipping) |
| Source | proven fact 7 and 8 above; replaces the synthetic-folder premise of WP-P-04 |
| Streams | tooling only |

**Goal.** `tools/harness/stage-build.ps1 -Mod <dir> -Slot <n>` puts a locally built mod where the game will load it, and the plan runs against that build instead of the subscribed one.

**Context.** The game ignores folders Steam does not list as subscribed, so a local build cannot go in an invented folder. A mod's bundles are addressed by package name, not by folder id, so any build can be placed in any subscribed item's folder. The rig therefore owns a few private Workshop items ("rig slots") whose content it overwrites before a run. Real mod folders are never written. Steam may restore a slot's published content at any time; the rig re-stages and re-hashes right before every launch, so that is harmless.

**Steps.**
1. Create six private items once, with the procedure proven for the bootstrap: a folder with `item.cfg` (`visibility = "private"`, title `VT2 Rig Slot <n>`), content = the bootstrap's bundles plus an inert `.mod` (`return { run = function() return {} end, packages = {} }` is not safe as the first mod, so keep one package line), then `ugc_tool.exe -c item.cfg -x`, then `tools/harness/steam-ugc.ps1 -ItemId <id>`. Record the six ids in `tools/harness/slots.psd1`.
2. `stage-build.ps1`: build with the approved launcher (`VMBLauncher.exe build <mod> --clean --config <private config whose ProjectRoot is the worktree>`), copy `bundleV2/*` into the slot folder, write `slot.json` there (mod dir, commit, version, file hashes).
3. `run.ps1`: plan field `local_builds: [{ "mod": "<dir>", "slot": 1 }]`. Before launch verify the slot's hashes against `slot.json`, enable the slot id in the profile's mod list at the position of the mod's real id, and disable the real id. Put the build's commit and version in `summary.json`.
4. Assert in the smoke case that the loaded version equals the staged version (the load banner or `MOD_VERSION`).

**Acceptance (machine, no human).**
- RIG: stage `verminious_dreams_lighting_dev` from a worktree where `MOD_VERSION` was changed to a marker value; the smoke run reports the marker version and exits 0; the real Workshop folder of that mod has unchanged hashes before and after.
- OFFLINE: test that `run.ps1` refuses when a slot's hashes do not match `slot.json`.

**Guardrails.** Never write into a real mod's Workshop folder. Never make a slot item public or friends-visible. This card does not upload mod content: slot items are published once with placeholder content.

**Stop and escalate if.** A mod staged in a slot fails to load while the same build loads from its real folder: record both logs; that would mean some mod depends on its folder id.

---

### WP-H-08 Mod sets, option values and save fixtures

| Field | Value |
|---|---|
| Priority | P1 |
| Size | M |
| Agent | any |
| Depends on | WP-H-02 |
| Issues | all packs that need an option set at load |
| Source | C1 section 5.2, D-auditor pack notes ("which build", "option values needed") |
| Streams | tooling only |

**Goal.** A plan can name a mod set, set any mod option before boot, and choose which save the profile starts from.

**Steps.**
1. `tools/harness/modsets.psd1`: named sets generated from `tools/mod-inventory.psd1` (`public-all`, `dev-all`, one set per mod with its dependencies from `MOD_DEPENDENCIES.md`). Plan field `modset`.
2. Plan field `options: { "<mod_id>": { "<setting>": <value> } }` written into the profile's `mods_settings` table before launch (VMF reads it once at load: `Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/settings.lua:10`).
3. Plan field `save`: `owner-copy` (default), or a named fixture under `qa/runtime/fixtures/saves/` (start with `fresh`). Never write a fixture from the owner's save without removing account identifiers; document what a save contains first.
4. Always force in the run profile: mod logging to the log file on, developer mode on, lobby private at `KEEP READY` (`matchmaking_manager.lua:2246-2271`).

**Acceptance (machine, no human).** OFFLINE: profile tests for modset, options and save selection. RIG: a case reads back an option value set by the plan through `T.find_mod(id):get(setting)`.

**Guardrails.** The owner's real profile is read once per run and never written.

**Stop and escalate if.** A mod reads an option from somewhere other than VMF settings: list it in `tools/harness/README.md` as "not settable by plan".

---

### WP-H-09 Reliability: liveness, crash classification, queue, repeatability

| Field | Value |
|---|---|
| Priority | P1 |
| Size | M |
| Agent | any |
| Depends on | WP-H-04 |
| Issues | none |
| Source | C1 section 5.9, E7; proven fact 6 |
| Streams | tooling only |

**Goal.** A run can hang, crash or be starved and the rig still returns a correct, classified result; ten runs of one plan give ten identical verdict tables.

**Steps.**
1. Liveness: the driver saves a `vt2_rig_progress` checkpoint at every phase and case boundary and every 15 s. `run.ps1` ends the run as INCONCLUSIVE when the checkpoint is older than 60 s in play or 240 s in loading.
2. Crash: a new file in the profile's `crash_dumps`, or exit without `RUN END`, marks the running case CRASH and every later case INCONCLUSIVE. Copy the dump and the log into the run folder.
3. Resource floor: refuse to start under 6 GiB free RAM or while a known game process runs (list in `tools/harness/busy-processes.txt`); stop a run as INCONCLUSIVE if free RAM falls under 3 GiB.
4. Queue: replace "refuse when locked" with `-Wait <minutes>` so several agents can submit plans; the lock stays one run at a time.
5. Retention: keep the last 30 run folders plus any folder named in `qa/runtime/reports/`; delete older ones (list first, explicit paths).
6. Repeatability: `tools/harness/Repeat-Plan.ps1 -Plan x -Count 10` and a comparison of verdict tables. A case with differing verdicts goes into `qa/runtime/quarantine.txt` and is excluded from closing issues until fixed.
7. Order check: a FAIL is re-run once alone in a fresh boot before it is reported; "passes alone" is reported as order-dependent.

**Acceptance (machine, no human).** OFFLINE: canned-log tests reproduce every verdict kind (PASS, FAIL, ERROR, TIMEOUT, INCONCLUSIVE, CRASH). RIG: `Repeat-Plan.ps1 -Plan mission-smoke.json -Count 10` reports ten identical tables and the owner's profile hashes unchanged ten times.

**Guardrails.** Never kill a process the rig did not start. Never retry until green.

**Stop and escalate if.** The author machine shows display stalls or a hardware error during runs: stop all runs and report; bulk runs then move to the second machine (OD-07).

---

### WP-H-10 Stills for the human list and for AI review

| Field | Value |
|---|---|
| Priority | P2 |
| Size | M |
| Agent | strong (capture on a private desktop is unproven) |
| Depends on | WP-H-06 |
| Issues | the 26 class V issues, partially |
| Source | C1 section 5.7, E6; OD-02 |
| Streams | tooling only |

**Goal.** `T.shot(label)` saves a PNG of the game at that moment into the run folder.

**Steps.**
1. Try, in this order, and keep the first that returns a non-black 1280x720 image from a private-desktop run: an engine call if one exists (`type(rawget(_G, "FrameCapture"))`, `type(Application.save_render_target)` are printed in the driver's `PROBE` line); `PrintWindow` with the full-content flag from a helper thread attached to the private desktop; Windows Graphics Capture; as a last resort a visible-desktop run mode used only for still packs.
2. Protocol: the driver prints `SHOT REQ` and waits on a settings checkpoint acknowledgement; `run.ps1` captures and acknowledges.
3. `tools/harness/Review-Stills.md`: the prompt for a vision-capable agent (image plus the issue's expected sentence; answer PASS, FAIL or CANNOT-TELL with a reason). Under OD-02 only presence or absence may close.
4. Attach stills and state dumps to the generated human list (WP-G-07).

**Acceptance (machine, no human).** RIG: a case takes one still in the keep; the file exists, is 1280x720, and its mean brightness is above a floor.

**Guardrails.** One still per check; no capture loops (the author machine has a history of compositor stalls under fast redraw).

**Stop and escalate if.** Every capture route returns black on a private desktop: document it and use the visible-run mode on the second machine.

---

### WP-H-11 Evidence publishing and scheduled runs

| Field | Value |
|---|---|
| Priority | P1 |
| Size | M |
| Agent | any |
| Depends on | WP-H-03, WP-G-01 |
| Issues | none (implements rules R1 and R7) |
| Source | E1 section 9.4, PLAN section 7 |
| Streams | tooling only |

**Goal.** A green case turns into the fixed evidence comment and, where the rules allow, a closed issue, with one command.

**Steps.**
1. `tools/harness/Publish-Evidence.ps1 -Run <folder> [-Post]`: for each case with an `issue` number build the comment text of PLAN section 7 (mod, version, commit, run id, script path, assertion counts, game build, "not covered" line from the script's `not_covered` field). Without `-Post` it only writes `evidence/<issue>.md` in the run folder.
2. With `-Post`: comment on the issue; close it only when every script listed for that issue in `qa/runtime/index.json` passed in this run and the script's class is R, S or U. Never close on a quarantined case.
3. `qa/runtime/index.json`: issue number to script paths and class, generated from the scripts' own header fields; a QA check fails when an issue-closing script has no entry.
4. Nightly run: a windowless scheduled task (`pythonw` or `pwsh -WindowStyle Hidden`, never a console window) that runs the smoke and sweep plans when the machine is idle and writes `qa/runtime/reports/nightly-<date>.md`. It publishes nothing by itself.
5. Patch-day trigger: when the game build id in `appmanifest_552500.acf` differs from the last run's, run the canary (WP-T-04) and the smoke plans first and flag every stored evidence record as "older than the current game build".

**Acceptance (machine, no human).** OFFLINE: `Publish-Evidence.ps1` on a recorded run folder produces the exact comment text of a fixture; with `-Post -WhatIf` it lists the issues it would close and why the others stay open.

**Guardrails.** One comment per issue per run. No labels invented. No closing of class V or C issues.

**Stop and escalate if.** The pull-request gate still rejects closures without "user-confirmed" (WP-G-01 not landed): write evidence files only and stop.

---

### WP-H-12 Two-machine co-op runs

| Field | Value |
|---|---|
| Priority | P2 |
| Size | L |
| Agent | strong |
| Depends on | WP-H-09, owner decision OD-07 |
| Issues | the 42 class C issues |
| Source | C1 section 5.8, E8 |
| Streams | tooling only |

**Goal.** One plan drives a host on the author machine and a client on the second machine through named barriers, and each side asserts on its own state.

**Context.** Retail has no LAN mode and peer identity is the Steam id, so co-op needs two Steam accounts that own the game on two machines. The join call is `Managers.matchmaking:request_join_lobby(lobby, { friend_join = true })` (`matchmaking_manager.lua:2090-2100`).

**Steps.**
1. Confirm OD-07 facts by script on the second machine (game installed, a second account logged in, the bootstrap item subscribed with `steam-ugc.ps1`).
2. Roles: plan field `role` per case (`host`, `client`); `run.ps1 -Role` on each machine; the two orchestrators exchange barrier names over SSH.
3. Driver: `T.barrier(name)` waits until the other side reached the same barrier (through the progress checkpoint, relayed by the orchestrators).
4. First plan: host in the keep, client joins, both assert the other's hero unit exists and its career name; then the #1143 heal route.
5. Husk assertions are state, not looks: attached unit names, item and skin keys, animation state names, error-free log on the observing side.

**Acceptance (machine, no human).** RIG: `coop-smoke.json` exits 0 on both machines three times in a row.

**Guardrails.** The lobby stays private. Never run the second machine's game while someone uses it.

**Stop and escalate if.** OD-07 is answered "no second account": class C issues stay on the human list with their scripted solo parts.

---

### WP-H-13 Script lint and offline stub for test scripts

| Field | Value |
|---|---|
| Priority | P1 |
| Size | S |
| Agent | any |
| Depends on | WP-H-01 |
| Issues | none |
| Source | C1 section 5.5 step 6 |
| Streams | tooling only |

**Goal.** A badly formed test script fails in CI in seconds, not in a three-minute rig run.

**Steps.**
1. `qa/runtime/_stub/T.lua`: a stub of the whole `T` table where every helper exists and records calls.
2. `qa/check_runtime_scripts.ps1`: for each `qa/runtime/**/issue_*.lua` and each `_rig/*.lua`: it parses, returns a table with `run`, `arena`, `issue` (number or 0), `class` (R), `timeout`, optional `not_covered`; its top level has no engine access; every `T.<name>` it uses exists in the stub; the file name matches `issue_<N>_<slug>.lua` and `<N>` equals the `issue` field.
3. Wire it into `qa/run_all.ps1` as a blocking check scoped to `qa/runtime/**`.

**Acceptance (machine, no human).** OFFLINE: the check passes on the existing cases; a fixture script with a misspelled helper, and one whose file name disagrees with its issue number, each fail with a message naming the problem.

**Guardrails.** The stub proves shape only. It must never be used to claim a behaviour passed.

**Stop and escalate if.** None expected.

---

### WP-H-14 Backend write shield: a test run can never change the real account

| Field | Value |
|---|---|
| Priority | P0 |
| Size | S |
| Agent | any |
| Depends on | WP-H-01 |
| Issues | #402, #1688 (class: modded state written to the official account) |
| Source | D4 (`vp/D4.md` section 0), A5 section 2.0, A5-F01, A7-F01 |
| Streams | tooling only |

**Goal.** For the whole of every rig run the game sends no career loadout, talent or user-data change to the backend, and the run's evidence says what was held back.

**Context.** The isolated profile isolates local files only. The modded realm signs in to the owner's real account, and since game 6.13 the engine sends career loadouts on its own whenever `mirror._career_data` differs from `mirror._career_data_mirror` (`Vermintide-2-Source-Code/scripts/managers/backend_playfab/playfab_mirror_base.lua:2885-2900`); user data is sent by `_commit_user_data` in the same commit. Only statistics, weave data and weapon poses are behind `read_only_backend` (`:2826`, `:2839`, `:2857`). So a script that equips an item, or a crash in the middle of a case, could change the official account without any script calling a commit. The prototype driver (0.4.0) already installs a shield at `KEEP READY` and at every `LEVEL READY`: on the live mirror instance it replaces `_check_career_data` (always answers "not dirty") and `_commit_user_data` (sends nothing), and prints `SHIELD blocked=...` with a count when something was held back. The commit still runs and completes, so no caller waits for its callback.

Three runs on 2026-11-14 settled the timing (facts 13 and 14 above). With driver 0.4.0 the game's routine start-up commit went out 4 s before `KEEP READY`, so before the shield existed (`smoke-keep-4b32903a`). Driver 0.4.1 calls `install_shield()` on every tick until the mirror exists and prints the key names of every `updateHeroAttributes` request: the start-up commit carried `keep_decorations` only (`smoke-keep-5f5ca4b0`). Driver 0.4.2 also replaces `get_keep_decorations_json` on the live `keep_decorations` interface so that the comparison at `playfab_mirror_base.lua:2879-2883` sees the acknowledged string; the start-up commit then completes and sends nothing (`smoke-keep-9d23f887`). What is still not shown is the other half: that a change made by a case is held back and reported.

**Steps.**
1. Keep the shield in `tools/harness/driver/vt2_rig_driver.lua` (`install_shield`, `shield_keep_decorations`), called on every tick so that it is up as soon as the mirror exists. Add an offline test to `qa/lua/tests/test_rig_driver.lua` with a stub mirror and a stub `keep_decorations` interface: (a) `_career_data` differs from `_career_data_mirror`: `mirror:_check_career_data(...)` returns false and a `SHIELD blocked=characters_data` line is printed; (b) one painting slot differs from the acknowledged layout: `get_keep_decorations_json()` returns the acknowledged string and a `SHIELD blocked=keep_decorations changed_slots=1` line is printed; (c) the class tables of both stubs are untouched (instance overrides only); (d) with `backend_shield = false` in the plan nothing is replaced.
2. Widen the request watch. Driver 0.4.2 wraps `enqueue` on the live request queue and prints `SHIELD saw request=updateHeroAttributes keys=<names>` (key names only, never values; observe and pass through). Print `SHIELD saw request=<FunctionName>` for every other cloud-script request built after `KEEP READY` as well. Add to the default `host_forbid_log` of `run.ps1`: any `Enqueuing ExecuteCloudScript request` line for `updateHeroAttributes`, and any `UpdateUserData` line; a plan with `backend_shield: false` drops these two defaults.
3. Add the helper `qa/runtime/_shared/official_mirror.lua` from `vp/D4.md` section 0.4 (`OM.snapshot`, `OM.assert_clean`, `OM.assert_untouched`, `OM.restore`) and make the driver call `OM.restore(snapshot taken at KEEP READY)` in its end-of-run path, before it quits, as a second line of defence.
4. A plan may set `backend_shield: false` only when its cases test commit behaviour itself. `qa/check_runtime_scripts.ps1` (WP-H-13) fails any plan that does so without a `backend_shield_reason` field.
5. Document in `tools/harness/README.md`: what a rig run does on the real account even with the shield (it signs in, so the normal sign-in cloud scripts run exactly as when the owner starts the game), and what it never does.

**Acceptance (machine, no human).**
- OFFLINE: the new unit test passes.
- RIG (start-up): `smoke-keep` exits 0; its log has `SHIELD installed` before the first `_commit_internal` line and no `updateHeroAttributes` request at all (reference run: `smoke-keep-9d23f887`).
- RIG: a case equips a different vanilla item in one slot through `BackendUtils.set_loadout_item`, waits for the next commit (or 30 s), and asserts: a `SHIELD blocked=characters_data` line exists, the log has no `updateHeroAttributes` request after `SHIELD installed`, and after `OM.restore` the mirror equals the snapshot. Exit 0.

**Guardrails.** Override the instance, never the class (a class override would leak into the owner's normal play only if it survived the process, which it cannot, but subclasses copy methods and a class override may simply miss). Never swallow a commit callback.

**Stop and escalate if.** The log shows an `updateHeroAttributes` request with character data after the shield was installed: stop all rig runs that equip or craft, and report the request line.

---

## Owner decisions for this track

| Id | Question | Default |
|---|---|---|
| OD-H-01 | The rig created one private Workshop item (the bootstrap, 3839345856) on the owner's account on 2026-11-13. Keep it? | Keep. It is private, constant, and inert outside rig runs. |
| OD-H-02 | Six more private items as rig slots (WP-H-07)? | Yes: needed to test builds before shipping. |
| OD-H-03 | May the rig run while the owner uses the machine for something else? | Yes when it is light use; it refuses when another game runs or free RAM is under 6 GiB. |
| OD-H-04 | Nightly unattended runs on the author machine? | Yes, windowless, smoke and sweep only, publishing nothing. |
| OD-H-05 | Retire the agent bridge (#1338) and `send_keys.ps1`? | Yes: the rig replaces them and does not touch the owner's clipboard, focus or input. |
