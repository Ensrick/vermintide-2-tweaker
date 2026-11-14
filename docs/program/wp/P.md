# Track P: release pipeline

Author: auditor B1, 2026-11-13. Evidence: `docs/audits/2026-11-13_FORMAL_AUDIT/evidence/B1.md` (finding ids `B1-Fnn`). Repo HEAD read: `592253d1`. Launcher facts were read from the public launcher repository `Ensrick/vmb-launcher` at tag `v0.6.3` (the approved build; receipts record `0.6.3+9737acd8`).

## Track brief

1. Today: 58,057 lines of release and paperwork tooling in 129 files ship 21 Workshop items. A dev ship is 21 operator steps and 4 CI cycles. The best complete cycle on record is 86 minutes.
2. `qa-gate` runs 21.9 minutes at the median against a 30 minute timeout. In run 43536586120, `run_selftests` took 11.0 minutes, `bundle_output_set_host_matrix` 4.2, `check_build_receipts` 2.2, `lua_unit_tests` 1.9.
3. Compiled bundles are 98.7% of a 15 GiB git history. Six mod pairs keep two hand-edited copies (152,289 duplicated Lua lines).
4. Target: one resumable command (`tools/ship/release.ps1`) that claims, builds, lands, ships and writes `ship-result.json`; CI near 10 minutes for product changes; no follow-up pull request after a ship; no compiled files in git; one hand-edited tree per mod.
5. Order rule: shipping must still work after every card. Take cards in number order unless "Depends on" says otherwise. One pull request per card (per mod where a card says so).
6. Trap 1, pin file: every ship rewrites `tools/verify/live_test_contract_exceptions.psd1` in the working tree (`tools/ship/ship.ps1:2727`). Until that change merges, the lifecycle guard fails other pull requests and the next ship stops (`tools/ship/ship.ps1:1950`). Commit that one file on its own branch and land it. WP-P-05 removes this.
7. Trap 2, live-head binding, enforced twice: a ship needs the shipped commit to be the live `master` head, a merged pull request, and a green `qa-gate` on that exact commit (`tools/ship/publication-authorization.ps1:31-57`). The launcher re-checks the same at upload (`Services/PublicationReceiptGate.cs:410-416` in the launcher repository). Editing `ship.ps1` alone cannot relax it. If anyone merges during your ship, the ship fails: sync and rerun at the same version.
8. Trap 3, claims: run `tools/ship/claim.ps1 -Mod <mod>` before bumping. Use the number it returns. A claim is stale after 24 hours (`tools/ship/claim.ps1:25`). The owner identity is `VT2_SHIP_SESSION_ID`, then `CLAUDE_SESSION_ID`, then `CODEX_THREAD_ID`, then the worktree path (`tools/ship/claim.ps1:135-155`). Do not add or remove those variables mid-flight. After a failed ship, rerun at the same version; never re-claim.
9. Trap 4, Steam state: the upload needs Steam running, logged in and registered. A bad state is found only at upload, after the GitHub release is public. Run the launcher's read-only `doctor` verb first (WP-P-07 builds it in). Never restart Steam yourself: see D-P-09.
10. Trap 5, helper scripts outside the repo: the working land and ship drivers live in `%USERPROFILE%\.claude\vt2-ship-helpers\` (`land-pr.ps1`, `ship-cycle.ps1`, `ship-chain.ps1`). They are unversioned and hold hard-coded paths. WP-P-09 ports them into the repo; until then read them, do not extend them.
11. Editing rules for every card: scripts are ASCII only (`tools/ship/ship.ps1:64`). Until D-P-01 is applied in WP-P-06, write syntax that Windows PowerShell 5.1 parses (no ternary, no `??`, no `&&`).
12. `ship.ps1` tests its own source text: 128 `IndexOf` calls in lines 922-1697 assert the order of statements. After any edit run `pwsh -NoProfile -File tools/ship/ship.ps1 -SelfTest` and `powershell -NoProfile -File tools/ship/ship.ps1 -SelfTest`. Add lines; do not reorder existing ones.
13. Workflow YAML is guarded by `qa/check_ci_hardening.ps1` (for example line 379 pins `runs-on: ubuntu-latest` for the lifecycle job). A YAML edit usually needs a matching edit there.
14. Every file in a mod directory except `bundleV2/` and `.build-receipt.json` is a build-receipt input (`tools/ship/build-receipt.ps1:122-135`). Renaming or deleting even a Markdown file there forces a rebuild. Hygiene cards stay out of mod directories.
15. Never write into `<workshop>\<real_id>\`, never launch the game, never run a publishing `ship.ps1` for a version without a pre-release suffix unless D-P-04 is satisfied. `<workshop>` means `<steam>\steamapps\workshop\content\552500`.

---

### WP-P-01 Make the lifecycle guard workflow pass on Linux

| Field | Value |
|---|---|
| Priority | P1 |
| Size | S (under 1 h) |
| Agent | any |
| Depends on | none |
| Issues | none |
| Source | B1-F03 |
| Streams | none (tooling only) |

**Goal.** The `Issue lifecycle guard` workflow concludes `success` on issue events and on its daily schedule.

**Context.** The job runs on `ubuntu-latest` (`.github/workflows/issue-lifecycle.yml:26`). Commit `b201ca5c` (2026-11-06) added two self-test blocks that start the vendored Windows binary `qa/lua/vendor/lua-5.1.5-win64/lua5.1.exe`: `tools/verify/live_test_contract.ps1:539` and `tools/verify/ct_official_receipt_routes_contract.ps1:159`. Every completed run since then failed with `Exception calling "Start" ... lua5.1.exe` (48 of 56 runs, seven scheduled runs in a row). The same self-tests also run on Windows inside `qa-gate`, so skipping them on Linux loses no coverage. Changing the runner instead would need edits to `qa/check_ci_hardening.ps1:379` and its fixtures, so this card does not do that.

**Steps.**
1. In `tools/verify/live_test_contract.ps1`, wrap the block from line 539 (`$lua=Join-Path $repoRoot 'qa/lua/vendor/lua-5.1.5-win64/lua5.1.exe'`) through the line `}finally{$process.Dispose()}` in `if([string][System.Environment]::OSVersion.Platform -ceq 'Win32NT'){ ... }else{ Write-Host '[live-test-contract] SKIP Lua expression oracle: needs the vendored Windows runtime; the Windows qa-gate runs it.' }`.
2. In `tools/verify/ct_official_receipt_routes_contract.ps1`, wrap the block from line 159 (`$lua=Join-Path $Root ...`) through `}finally{$process.Dispose()}` (line 243) the same way. Replace the literal `15` in `$checks+=15` (line 244) and `LuaAssertions=15` (line 246) with a variable `$luaAssertions` that is 15 on Windows and 0 otherwise. The caller discards the result (`tools/verify/live_test_contract.ps1:900`, `| Out-Null`).
3. Do not use `$IsWindows`: it is undefined in Windows PowerShell 5.1 and would skip the oracle on Windows.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File tools/github/check-lifecycle-cardinality.ps1 -SelfTest` exits 0 and prints `constant-prefix load matrix passed` and `CT official receipt routes passed`. The same command with `powershell` exits 0.
- OFFLINE: `pwsh -NoProfile -File qa/check_ci_hardening.ps1` exits 0 (no YAML changed).
- HOSTED: after merge, `gh workflow run issue-lifecycle.yml`, then `gh run list --workflow issue-lifecycle.yml --limit 3 --json conclusion,event` shows `success` for the `workflow_dispatch` run, and its log contains the SKIP line twice.
- Evidence class S. Closes no issue.

**Guardrails.** Do not change `.github/workflows/issue-lifecycle.yml`. Do not weaken any assertion on Windows. Keep both files ASCII.

**Stop and escalate if.** The Linux run still fails after the fix at a different Windows-only call. Record the new failing line and stop; do not switch the runner.

---

### WP-P-02 Write a JSON result and a ledger for every ship run

| Field | Value |
|---|---|
| Priority | P1 |
| Size | M (half a day) |
| Agent | any |
| Depends on | none |
| Issues | advances #724 |
| Source | B1-F09 |
| Streams | none (tooling only) |

**Goal.** Every `ship.ps1` run, successful or not, leaves one `ship-result.json` and one line in a ledger, so failures can be counted by stage.

**Context.** `tools/ship/ship.ps1` reports only coloured console text and exit codes 0 or 1 (`Fail` at lines 145-153; success exits at 2291 build-only, 2716 bootstrap, 3131 ship). Failed attempts are logged nowhere, so the pipeline's failure rate cannot be computed. Later cards (WP-P-08, WP-P-09) need this record.

**Steps.**
1. Add `qa/check_ship_result.ps1` with `[switch]$SelfTest` (the runner `qa/run_selftests.ps1` discovers `qa/check_*.ps1` files that declare that switch). It dot-sources the helper from step 2 and asserts, in a temp folder: a result with two stages completed as `failed` writes one file that parses as JSON with `schema`, `mod`, `mode`, `status`, `failed_stage`, `stages`; the ledger gains exactly one line; a second completion writes nothing more; an unwritable folder produces a warning and no exception.
2. Add `tools/ship/ship-result.ps1` with four functions. `Get-VtShipResultDirectory` returns `$env:VT2_SHIP_RESULT_DIR` when set, else `Join-Path $env:APPDATA 'VMBLauncher\ship_runs'`. `New-VtShipResult -Mod -Mode` returns an ordered hashtable: `schema = 1`, `run_id` (UTC `yyyyMMddTHHmmssZ` plus the process id), `mod`, `mode` (`build-only` or `ship`), `started_utc`, `ps_version`, `version`, `published_id`, `source_commit` (all three `$null`), `stages = @()`, `status = 'running'`, `failed_stage`, `message`, `finished_utc`. `Set-VtShipResultStage -Result -Name` closes the previous stage with `ended_utc` and appends `{ name; started_utc }`. `Complete-VtShipResult -Result -Status -Message` (status `ok`, `failed` or `crashed`) sets `failed_stage` to the last stage name when not `ok`, writes `<dir>\<run_id>-<mod>.json` as UTF-8 without BOM, and appends the same object as one line to `<dir>\ledger.jsonl`. All writes sit in `try/catch` and only warn.
3. In `tools/ship/ship.ps1` add lines only: (a) dot-source the helper after line 143; (b) in `Fail`, before `exit 1`, call `Complete-VtShipResult` with `failed` and `$Message` when `$script:VtShipResult` exists; (c) immediately before the comment `# Step 1: resolve paths + parse published_id and MOD_VERSION` (line 1715) create `$script:VtShipResult` and set stage `resolve`; (d) set stages `preflight` (before the claim gate near 1857), `qa` (before 2048), `build` (2086), `deploy` (before 2336), `verify-deploy` (2387), `release` (2444), `upload` (before 2570), `verify-upload` (2620), `pins` (2720), `labels` (2750), `cards` (2930), `finish` (3083); fill `version`, `published_id`, `source_commit` right after each is known; (e) call `Complete-VtShipResult` with `ok` before each of the three `exit 0` lines; (f) in the outermost `finally`, after `Exit-VmbMachineTransactionLease` (line 3076), complete with `crashed` when the status is still `running`.
4. Add `tools/ship/ship-stats.ps1`: reads `ledger.jsonl` and prints counts by `status` and `failed_stage` as JSON.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_ship_result.ps1 -SelfTest` exits 0; the same with `powershell` exits 0.
- OFFLINE: set `$env:VT2_SHIP_RESULT_DIR` to a new empty temp folder, run `pwsh -NoProfile -File tools/ship/ship.ps1 -Mod no_such_mod`. Expected: exit code 1; exactly one `*-no_such_mod.json` with `"status":"failed"` and `"failed_stage":"resolve"`; `ledger.jsonl` has one line. This run stops at the "Mod directory not found" check and builds nothing.
- OFFLINE: `ship.ps1 -SelfTest` exits 0 under `pwsh` and under `powershell`.
- Evidence class S. Advances #724 only.

**Guardrails.** Do not reorder or wrap existing statements in `ship.ps1` (track brief line 12). Result code must never throw. Write nothing inside the repository at run time.

**Stop and escalate if.** `ship.ps1 -SelfTest` fails twice with an assertion you cannot tie to your inserted lines. Revert the `ship.ps1` edits, keep the helper and its check, and report the assertion text.

---

### WP-P-03 Delete merged branches and root stub files

| Field | Value |
|---|---|
| Priority | P3 |
| Size | M (half a day) |
| Agent | any |
| Depends on | none |
| Issues | advances #546 |
| Source | B1-F15, B1-F18 |
| Streams | none. Do not touch any mod directory |

**Goal.** No merged branch remains locally or on the remote, the 12 root stub files are gone, and no tracked file is matched by `.gitignore`.

**Context.** The primary checkout has 1,152 local branches (766 merged into `master`) and the remote has 98 (54 merged and not deleted). `PROJECT_STANDARDS.md:1949-1952` already requires merged remote branches to be deleted. Twelve root files are pointer stubs of 129 to 466 bytes; `PROJECT_STANDARDS.md:1803-1806` (stage 3) allows deleting a stub once no inbound reference remains. Twenty files are tracked although ignored (`_archive/` 17, `_investigating/` 1, two fixture zips), which makes `git add` exit 1.

**Steps.**
1. Inventory first. Run `git fetch origin --prune`. Save `git for-each-ref --format='%(refname:short) %(objectname:short) %(committerdate:short)' --no-merged origin/master refs/heads refs/remotes/origin` to a file outside the repo and post its line count and the 30 newest lines as a comment on issue #546. Do not delete anything in that list.
2. Remote: for each name in `git branch -r --merged origin/master` except `origin/master` and `origin/HEAD`, run `git push origin --delete <name without origin/>`.
3. Local: for each name in `git branch --merged master --format='%(refname:short)'` except `master` and except any branch listed by `git worktree list --porcelain` (lines starting `branch `), run `git branch -d <name>`. Never use `-D`.
4. Stubs: `COMMANDS.md`, `CROSS_MOD_ARCHITECTURE.md`, `LOCALIZATION_STANDARD.md`, `REGRESSION_CHECKLIST.md`, `TESTING_STATUS.md`, `TODO.md`, `VMF_RECIPES.md`, `WEAPONS.md`, `WEAPON_CATALOG.md`, `WORK_ITEMS.md`, `.meta_boons_audit_2026-05-24.md`, `.test_coverage_audit_2026-05-24.md`. For each: read the stub to learn the new home; `git grep -n -F "<name>"`; fix every hit that means the root file (not `docs/<name>` or `<mod>/<name>`) and that is outside mod directories; then `git rm <name>`. The commit message lists each stub and its new home.
5. Tracked but ignored: `git rm -r --cached _archive _investigating` (files stay on disk). For `qa/fixtures/content_manifest/updater-1430.zip` and `vmb-1429.zip` add two negation lines to `.gitignore` next to the two existing `!qa/fixtures/recovery_manifests/...zip` lines.

**Acceptance (machine, no human).**
- `git branch -r --merged origin/master | wc -l` is 2 or less. `git branch --merged master | wc -l` is at most 1 plus the number of worktree branches.
- `git ls-files -ci --exclude-standard | wc -l` is 0.
- `git ls-files | grep -v / | wc -l` is 22 or less (34 today minus 12).
- `pwsh qa/run_all.ps1 -Quick -SkipLua` reports no new blocking failure; `pwsh qa/check_bundle_authority.ps1` exits 0 after the `.gitignore` edit.
- Evidence class S.

**Guardrails.** Leave alone: unmerged branches, `refs/preserve/*`, `refs/worktree-archives/*`, every stash, every worktree (never `git worktree remove`). Do not edit, move or delete any file inside a mod directory, including `cosmetics_tweaker/LOGS_PC_B.md` (track brief line 14). Do not scrub the profile path from fixtures or gates in this card: several are hash-bound.

**Stop and escalate if.** A stub is still referenced from inside a mod directory (leave that stub in place and list it). `git branch -d` refuses a branch (leave it). `check_bundle_authority` rejects the `.gitignore` change (revert that hunk).

---

### WP-P-04 Stage an unshipped build for the rig

| Field | Value |
|---|---|
| Priority | P1 |
| Size | M (half a day) |
| Agent | any |
| Depends on | none (track H consumes it) |
| Issues | none |
| Source | lead request; B1 section 7 |
| Streams | any mod row of `tools/mod-inventory.psd1`; reads only |

> **Correction by the lead, 2026-11-13, after the rig experiments.** The premise of this card is wrong. The game ignores a Workshop folder that Steam does not list as subscribed: a folder `9000000099` holding a valid mod produced `was not found in the workshop folder`, and the game's handle table held exactly the subscribed ids. The updater's documentation claim was never true for an unsubscribed id. The target of this card is therefore not a `99<id>` folder but a **rig slot**: a private Workshop item owned by the rig and subscribed once (card WP-H-07, ids in `tools/harness/slots.psd1`).
> Do steps 1, 3, 4, 5 and 7 as written (collect and validate the build output, write `rig_build.json`). Replace steps 2, 6, 8, 9 and 10 with WP-H-07 steps 2 and 3, and ignore every `99` prefix rule and the `10<id>` entry. Deliver this card and WP-H-07 as one pull request.

**Goal.** `tools/harness/stage-build.ps1` places the compiled files of any mod, from any commit or worktree, in a Workshop folder that Steam does not manage, and prints the mod-list entry a rig run needs.

**Context.**
- The game loads a mod from any `<workshop>\<id>\<mod>.mod`; the folder name is not validated (`<repos>/vt2-mod-updater/CLAUDE.md`, "Why synthetic IDs"). The updater uses `10<real_id>` (`<repos>/vt2-mod-updater/src/VT2ModUpdater/Services/Deployer.cs:29`, `:97-104`); local development used `9000000XXX`. Steam reverts or deletes foreign writes in a real item folder, so the rig must never use `<real_id>`.
- What a folder needs: every file of `<mod>/bundleV2/`, flat: the root `.mod_bundle`, the shared bundles, any sidecar bundle, and the `<mod>.mod` descriptor. Proof: the ship's deploy check walks `Get-ChildItem $bundleDir -File` (`tools/ship/ship.ps1:2410`); the launcher's deploy deletes `*.mod` and `*.mod_bundle` in the target, then copies every file of `BundleV2Dir` with a hash check (`Services/ModRunner.cs:179-196` in the launcher repository); the updater extracts the release zip flat and adds two sidecar text files, so extra non-bundle files are tolerated (`Deployer.cs:161-171`). Example: `general_tweaker_dev/bundleV2/` holds `209fb8c3c0a8c3a4.mod_bundle`, `4e6a9317aab221e1.mod_bundle`, `e6ffaaca2a71199e.mod_bundle`, `general_tweaker_dev.mod`.
- The launcher's `deploy` verb cannot be used: it resolves the id from `itemV2.cfg` and refuses a missing folder (`Services/ModRunner.cs:158-165`).
- How the game picks mods: it reads the `mods` list of `user_settings.config` (`Vermintide-2-Source-Code/scripts/managers/mod/mod_manager.lua:279`), looks each `id` up among scanned folders and disables an entry whose folder is missing (`:291-300`). In the modded realm it skips the sanctioned-mod metadata check (`:38-40`) and scans unsanctioned folders (`:273`). Per entry it reads `id`, `name`, `enabled`, `last_updated` (`:291-338`); `children` and `num_children` only when `mod_settings.toposort` is true (`:281`, `:532-533`).

**Steps.**
1. Create `tools/harness/stage-build.ps1` (PowerShell 7) with parameters `-Mod <inventory Dir>`, `-Source tracked|build|release` (default `tracked`), `-Ref <commit-ish>` (default `HEAD`), `-RepoRoot <checkout or worktree>` (default: the script's repository), `-Tag <release tag>` (for `release`), `-WorkshopRoot <path>`, `-Unstage`, `-Json`, `-SelfTest`.
2. Identity: read the row for `-Mod` with `Import-PowerShellDataFile tools/mod-inventory.psd1`. Rig folder id = `99` followed by the 10-digit `WorkshopId` (12 digits; example `general_tweaker_dev` 3733367409 gives `993733367409`). Refuse a row without a 10-digit id.
3. Workshop root: `-WorkshopRoot` if given; else read the Steam install path from the registry and find the library that owns app 552500 in `steamapps\libraryfolders.vdf`, as `<repos>/vt2-mod-updater/src/VT2ModUpdater/Services/SteamPaths.cs:20-43` does.
4. Collect files into a temp folder. `tracked`: `git -C <RepoRoot> archive --format=zip -o <tmp>.zip <Ref> <Mod>/bundleV2`, then expand and take the files of the `<Mod>/bundleV2` sub-folder (binary safe; never pipe bundle bytes through PowerShell text). `build`: run `pwsh -NoProfile -File <RepoRoot>/tools/ship/ship.ps1 -Mod <Mod> -BuildOnly -NoClaim` (non-publishing; `-NoClaim` is legal only with `-BuildOnly`, `tools/ship/ship.ps1:1707-1709`), require exit 0, then take every file of `<RepoRoot>/<Mod>/bundleV2/`. `release`: with `gh release download`, fetch `manifest.json` from the tag, take the row whose `mod_id` equals the inventory `ModId`, fetch the zip named by its `asset_filename`, require the zip's SHA-256 to equal the row's `sha256`, expand flat.
5. Validate the set: exactly one `<Mod>.mod`; the row's `RootBundle` is present; every other file matches `^[0-9a-f]{16}\.mod_bundle$`; drop files named in the row's `BuildArtifactExclusions`.
6. Target = `<workshop>\<rig id>`. Before any write assert that the leaf matches `^99\d{10}$` and that the target differs from `<workshop>\<WorkshopId>`. Create the folder if missing, delete only `*.mod`, `*.mod_bundle` and `rig_build.json` inside it, copy the set, and compare SHA-256 of each copy with its source.
7. Write `<target>\rig_build.json`: `schema 1`, `mod`, `mod_id`, `real_workshop_id`, `rig_id`, `source`, `commit` (`git rev-parse <Ref>`, or `HEAD` plus `dirty: true|false` for `build`), `version` (the `MOD_VERSION` string of `<Mod>/scripts/mods/<Mod>/<Mod>.lua` at that source), `files: [{ name, size, sha256 }]`, `staged_utc`.
8. Output, as JSON with `-Json`: `rig_id`, `folder`, `mod_entry`, `disable_ids = [ "<WorkshopId>", "10<WorkshopId>" ]`.
9. `-Unstage` removes the folder only when its leaf matches `^99\d{10}$` and it contains `rig_build.json`.
10. Document the mod-list contract in a comment block at the top of the script. The run's isolated `user_settings.config` (never the owner's real file) needs one block inside `mods = [ ... ]`, tab indented, keys in this order, `enabled` directly above `id`:

```
	{
		enabled = true
		id = "993733367409"
		last_updated = "<staged_utc>"
		name = "rig general_tweaker_dev 0.2.279-dev"
	}
```

   Place it after the Vermintide Mod Framework entry (`id = "1369573612"`): every mod descriptor asserts that `new_mod` exists (`general_tweaker_dev/general_tweaker_dev.mod:3`). In the same profile set the entries for `<WorkshopId>` and `10<WorkshopId>` to `enabled = false`, or the mod loads twice. Keep `mod_settings.toposort` absent or `false`. The run must start the game in the modded realm.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File tools/harness/stage-build.ps1 -SelfTest` exits 0. Fixtures: a temp git repository with a fake mod and a temp workshop root. Asserted: folder name `99<id>`; file set equals the fixture's `bundleV2`; equal hashes; refusal to write to a leaf without the `99` prefix; refusal when `<Mod>.mod` is missing; `-Unstage` leaves a folder without `rig_build.json` alone.
- OFFLINE: `pwsh -NoProfile -File tools/harness/stage-build.ps1 -Mod general_tweaker_dev -Source tracked -Ref origin/master -WorkshopRoot <empty temp folder> -Json` exits 0; the folder `<temp>\993733367409` holds exactly the names printed by `git ls-tree --name-only origin/master general_tweaker_dev/bundleV2/` plus `rig_build.json`; `git status --porcelain` is unchanged.
- RIG (track H wires it): arena `boot` with the staged entry. `host_expect_log` holds the mod's load line `[<tag>:LOAD] v<version>`, where `<tag>` comes from `Get-VtLoadTagResolution` (`tools/ship/load-tag-resolution.ps1`) and `<version>` from `rig_build.json`. `host_forbid_log` holds `was not found in the workshop folder` (`mod_manager.lua:297`).
- Evidence class: infrastructure; closes no issue.

**Guardrails.** Never write to `<workshop>\<real_id>` or `<workshop>\10<real_id>`. Never edit the owner's real `user_settings.config`. `-Source build` leaves `bundleV2/` and `.build-receipt.json` modified in that worktree: never commit them from this script. After WP-P-11 moves a mod to receipt authority its bundles are no longer tracked: `-Source tracked` must then fail with a message that names `-Source build`.

**Stop and escalate if.** `<workshop>\1369573612\` (Vermintide Mod Framework) is missing. On 2026-11-13 only two item folders existed locally and `<steam>\steamapps\workshop\appworkshop_552500.acf` reported `NeedsDownload`. Without the framework no mod loads, and it cannot be staged from this repository. Also stop if the engine rejects a 12-digit folder id in the first rig boot (the forbidden log line appears): report it, do not invent another scheme.

---

### WP-P-05 Make source pins informational; end the pin pull request

| Field | Value |
|---|---|
| Priority | P1 |
| Size | M (half a day; the self-test suite takes about 11 minutes per run) |
| Agent | strong (changes what an authority check accepts; must keep the anchor checks strict) |
| Depends on | none |
| Issues | advances #1328 |
| Source | B1-F02 |
| Streams | none (tooling only) |

**Goal.** A ship leaves the working tree clean, and a pin that names an older deployed tree no longer fails the lifecycle guard or stops the next ship.

**Context.**
- `tools/verify/live_test_contract_exceptions.psd1` stores, per audited mod, the git tree id of the deployed `scripts/mods` folder (keys `ModTree` and `ModTrees` in `ReceiptFamilyOverrides`, `ReceiptRouteOverrides`, `ReceiptDiscoveryOverrides`).
- The source-authority check throws when a pin is not the deployed tree: `tools/verify/live_test_source_authority.ps1:1784-1787` (route), `:1856-1859` (family), `:1894` (discovery). Right after each of these it also checks token anchors against the deployed source, and those fail when audited code changed (`:1793-1800`).
- Since issue #1328 the ship moves the pins itself with no review (`Invoke-VtPublishedPinFinalization`, `tools/ship/exception-pin-finalization.ps1:492`, called at `tools/ship/ship.ps1:2727` and `:3050`). The file's own header says the anchors are the real protection (`tools/verify/live_test_contract_exceptions.psd1:17-19`). So the tree comparison only forces a second pull request.
- The next ship refuses to start while pins are stale (`Invoke-VtCurrentSourcePinReconciliation`, `tools/ship/current-source-pin-recovery.ps1`, stop at `tools/ship/ship.ps1:1950`). A stale pin after a half-finished ship failed six unrelated pull requests (issue #1328, comment of 2026-09-06).
- 59% of master commits since 2026-09-20 touch this file.

**Steps.**
1. Tests first. Five self-test assertions expect a wrong tree to be rejected: `tools/verify/live_test_contract.ps1:1335` and `:1646`, `tools/verify/ct_official_receipt_routes_contract.ps1:87`, `tools/verify/cwv719_receipt_route_contract.ps1:85`, `tools/verify/wt942_receipt_route_contract.ps1:105`. Change each to expect acceptance when the documents and anchors are unchanged (for the three contract files replace `& $reject {& $apply -Tree ('0'*40)} 'tree drift' ...` with a plain `& $apply -Tree ('0'*40) | Out-Null`, and keep the counter increment that follows on the same line so printed totals do not change). Keep every anchor-drift rejection test as it is. Run the self-test: these five now fail.
2. In `tools/verify/live_test_source_authority.ps1` remove only the tree-membership test: at line 1785 delete ` -or $pinnedTrees -cnotcontains $ModTree`; at line 1857 delete ` -or $pinnedTrees -cnotcontains [string]$record[0].ModTree`; delete the statement at line 1894. Keep the 40-hex format checks and the duplicate checks. Run the self-test: all pass.
3. Stop the rewrites without touching `ship.ps1`. In `tools/ship/exception-pin-finalization.ps1` add near the top `$script:VtSourcePinRewriteEnabled = ($env:VT2_SOURCE_PIN_REWRITE_SELFTEST -ceq '1')`. The environment form survives repeated dot-sourcing and child processes; the flag is false in every real ship. As the first statement of `Invoke-VtPublishedPinFinalization` add: when that flag is false, return `[pscustomobject]@{ Completed = $true; Changed = $false; PinCount = 0; Summary = 'disabled: source pins are informational' }`. As the first statement of `Invoke-VtCurrentSourcePinReconciliation` (`tools/ship/current-source-pin-recovery.ps1`) add: when the flag is false, return `[pscustomobject]@{ Status = 'disabled'; Changed = $false; RequiresMetadataPR = $false; Summary = 'disabled: source pins are informational' }`.
4. The gates that test the rewrite path dot-source the helper at script scope: `qa/check_publication_pin_finalization.ps1:6`, `qa/check_publication_pin_handoff.ps1:6`, `qa/check_current_source_pin_recovery.ps1:99`. At the top of each of these three scripts, before any dot-source, save the old value and set `$env:VT2_SOURCE_PIN_REWRITE_SELFTEST = '1'`; restore the old value in a `finally` at the end. They then keep testing the dormant code.
5. Update the header comment of `tools/verify/live_test_contract_exceptions.psd1` (lines 7-24) and the two paragraphs of `PROJECT_STANDARDS.md` section 6.6 that describe pin repointing (they start at lines 1209 and 1240): pins record the tree an override was reviewed against; they are no longer rewritten and no longer compared.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File tools/github/check-lifecycle-cardinality.ps1 -SelfTest` exits 0. `pwsh -NoProfile -File qa/run_selftests.ps1` exits 0. `ship.ps1 -SelfTest` exits 0 under `pwsh` and `powershell`.
- OFFLINE: `git grep -c "cnotcontains \$ModTree" -- tools/verify/live_test_source_authority.ps1` prints nothing (0 matches).
- LIVE, at the next ordinary dev ship: the summary line reads `Pins : disabled: source pins are informational`; `git status --porcelain` is empty in the ship worktree and in the primary checkout; an unrelated open pull request's `qa-gate` stays green with no pin pull request.
- After 10 ships: `git log --since=<merge date> --first-parent --name-only master` shows no commit whose only path is the pin file.
- Evidence class S. Advances #1328: the half-published case can no longer strand pins.

**Guardrails.** Do not delete pins from the file: `tools/verify/live_test_contract.ps1:1519-1524` and `:1690` read real pins to find the source tree their offline proofs run against. Do not weaken or remove any anchor check. Do not edit `tools/ship/ship.ps1` in this card.

**Stop and escalate if.** A self-test other than the five listed fails. Making a test pass would need a weaker anchor check. `qa/check_publication_doctrine.ps1` rejects the reworded doctrine text (report the rule it cites).

---

### WP-P-06 Scope qa-gate to the change: about 10 minutes for product pull requests

| Field | Value |
|---|---|
| Priority | P1 |
| Size | L. Split: stage A (steps 1-5, `qa/run_all.ps1` only), stage B (steps 6-7, workflow YAML and its guard) |
| Agent | any for stage A; strong for stage B (must edit `qa/check_ci_hardening.ps1` fixtures) |
| Depends on | none |
| Issues | advances #546 |
| Source | B1-F11, B1-F16, B1-F07 |
| Streams | none (tooling only) |

**Goal.** A pull request that changes only mod directories gets `qa-gate` in about 10 minutes; pipeline changes still run every self-test; a nightly run stays complete.

**Context.** Measured in hosted run 43536586120 (23.4 minutes in `run_all.ps1`): `run_selftests` 659.8 s (47%), `bundle_output_set_host_matrix` 250.8 s, `check_build_receipts` 130.2 s, `lua_unit_tests` 113.4 s, `wt_history_source_host_matrix` 76.8 s. The first, second and fifth test pipeline tooling, not the change. Other fixed costs of the job: tracker lifecycle step 3.1 minutes, three Windows PowerShell 5.1 steps 1.3 minutes. Every merge reruns this for all open pull requests (`strict` branch protection) and a ship waits for one more run on `master`. A tested change-set helper already exists: `Get-WtHistoryFreshnessChangeSet` (`qa/wt_history_freshness_scope.ps1:123`) returns `Determinate` and `Paths` for the index, the hosted pull-request range or the hosted push range. Projection: stage A gives about 12.5 minutes, stage B about 9 to 10.

**Steps.**
1. In `qa/run_all.ps1` add the switch `-Full`. After the policy setup, dot-source `qa/wt_history_freshness_scope.ps1`, call `Get-WtHistoryFreshnessChangeSet -RepoRoot $repoRoot -Staged:$Staged` once and keep the result in `$script:qaChangeSet`.
2. Add `Test-QaScope([string[]]$Prefixes)`: returns `$true` when `-Full` is set, when the change set is not `Determinate`, or when any changed path starts with one of the prefixes.
3. Guard these `Run-Check` lines with it, printing `===== <name> =====` and `SKIP (scope): no changed path under <prefixes>` when skipped: line 408 `run_selftests` (prefixes `qa/`, `tools/`, `.github/`); line 417 `bundle_output_set_host_matrix` (`tools/ship/`, `tools/mod-inventory.psd1`, `qa/check_bundle_output_set.ps1`, `qa/run_bundle_output_set_host_matrix.ps1`); lines 420-470, the fourteen `wt_history` checks (`tools/weapon-history/`, `weapon_tweaker/`, `weapon_tweaker_dev/`, `qa/check_wt_history`, `qa/run_wt_history`).
4. Line 377, `check_branch_reconciliation_census`: add `-Policy 'Advisory'`. It fails only because 14 days passed (`qa/check_branch_reconciliation_census.ps1:14`, `:78`).
5. Extend `Invoke-PolicySelfTest` in `qa/run_all.ps1` with four fixtures for `Test-QaScope`: a path under `general_tweaker_dev/` skips `run_selftests`; `tools/ship/claim.ps1` runs it; an indeterminate change set runs it; `-Full` runs it.
6. Stage B. In `.github/workflows/qa.yml`: add `schedule: - cron: '41 9 * * *'` under `on:`; change the `run_all` step to pass `-Full` when `github.event_name` is `schedule` or `workflow_dispatch`; under D-P-01 delete the three `shell: powershell` steps (lines 74-84). Make the matching edits in `qa/check_ci_hardening.ps1` so its fixtures describe the new file.
7. Stage B, only if the median is still above 10 minutes: run `check_build_receipts` and `lua_unit_tests` concurrently inside `qa/run_all.ps1` with `Start-ThreadJob`, replaying each one's output under its own header.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/run_all.ps1 -SelfTest` exits 0 and lists the four new fixtures.
- OFFLINE: on a branch whose only difference from `origin/master` is one Lua file in a mod, `pwsh qa/run_all.ps1` prints `SKIP (scope)` under `run_selftests` and `bundle_output_set_host_matrix`; with `-Full` it prints neither.
- HOSTED: a pull request that touches only `tools/ship/claim.ps1` logs `===== run_selftests =====` with no SKIP line.
- HOSTED: `gh run list --workflow qa.yml --event pull_request --limit 40 --json createdAt,updatedAt,conclusion,headBranch`: over 10 consecutive successful runs of mod-only pull requests the median duration is 13 minutes or less after stage A and 10 minutes or less after stage B.
- Evidence class S. Advances #546 only.

**Guardrails.** Never skip `lua_unit_tests`, `check_lua_parse`, `check_published_ids`, `check_versions`, `check_build_receipts`, `check_release_bundle_atomicity` or the lint step. An indeterminate change set must run everything. Do not change branch protection (D-P-08). Do not remove the tracker lifecycle step from `qa.yml`: its self-test reads real mod source and must keep running for product changes.

**Stop and escalate if.** `qa/check_ci_hardening.ps1` needs more than fixture updates that mirror your YAML edit (for example it forbids a `schedule` trigger by rule). A scoped run passes a pull request that a `-Full` run fails: report the check name; that check must leave the scoped set.

---

### WP-P-07 Run the launcher doctor before a ship changes anything

| Field | Value |
|---|---|
| Priority | P1 |
| Size | S (under 1 h) |
| Agent | any |
| Depends on | none |
| Issues | advances #1328 |
| Source | B1-F08, B1-F14 |
| Streams | none (tooling only) |

**Goal.** A ship on a machine where Steam or the SDK is not ready stops before the build, the GitHub release and the upload.

**Context.** `ship.ps1` probes launcher capabilities only (`tools/ship/ship.ps1:2016-2029`, verb `capabilities`). The launcher checks Steam readiness in its `doctor` verb and again at upload, which comes after the GitHub release is public (`tools/ship/ship.ps1:2465` before `:2570`). Two of 68 ship days since 2026-09-20 ended half-published. `doctor` is read-only: it prints one line per check as `[ ok ]`, `[warn]` or `[ERR ]` followed by `Title: detail` and exits 3 when any check is an error (`Cli/Commands.cs:228-247`, `Cli/CliDispatcher.cs:22` in the launcher repository). Its checks are VMB, Project folder, Steam, Vermintide 2 SDK, ugc_tool.exe, Workshop content folder (`Services/Diagnostics.cs`).

**Steps.**
1. In `tools/ship/ship.ps1`, next to the other hoisted helpers (after `Get-ShipDeploymentPolicy`, about line 290), add `Get-ShipDoctorProblems([string[]]$Lines)`: returns the lines that match `^\[ERR \]` or `^\[warn\] Steam:`.
2. In `Invoke-ShipSelfTest` add assertions for it: an `[ERR ] Steam: ...` line and a `[warn] Steam: ...` line are returned; `[ ok ] Steam: ...` and `[warn] Workshop content folder: ...` are not.
3. After the line that prints `VMBLauncher publication capability: PASS` (about 2029) and only when `-not $BuildOnly`, add: `$doctorRun = Invoke-ShipLauncherNoWindow -LauncherExecutableLease $launcherExecutableLease -ArgumentList @('doctor', '--no-banner', '--config', $launcherSettings)`; compute the problems; call `Fail` when the exit code is not 0 or any problem line exists, with the text `VMBLauncher doctor reports the release station is not ready; nothing was built, published or uploaded: <problem lines>`.

**Acceptance (machine, no human).**
- OFFLINE: `ship.ps1 -SelfTest` exits 0 under `pwsh` and `powershell`.
- OFFLINE: `git grep -n "'doctor', '--no-banner'" -- tools/ship/ship.ps1` prints one line, and its line number is lower than that of `& $quickGate -Quick`.
- LIVE, at the next ordinary dev ship: the log shows the doctor call before `==> Headless preflight`, and the ship completes.
- Evidence class S.

**Guardrails.** Do not restart Steam or change any machine state when doctor fails (D-P-09). Add lines only (track brief line 12).

**Stop and escalate if.** On the healthy release machine `doctor` exits non-zero, or reports `[ERR ] Project folder` when called with the ship-private `--config`. Report its full output; do not loosen the filter.

---

### WP-P-08 Authorize a ship by mod tree instead of the live head

| Field | Value |
|---|---|
| Priority | P2 |
| Size | L. Split: launcher change and release; then repository change |
| Agent | strong (two repositories; changes the upload authorization rule) |
| Depends on | WP-P-02, WP-P-06, and decision D-P-06 |
| Issues | advances #724 |
| Source | B1-F07 |
| Streams | none (tooling only) |

**Goal.** A ship succeeds when `master` has moved, provided the shipped commit is on `master` and the shipped mod's directory is identical at the shipped commit and at the live head.

**Context.** Today the shipped commit must equal the live head (`tools/ship/publication-authorization.ps1:31-34`), checked three times per ship (`tools/ship/ship.ps1:1928`, `:2450`, `:2532`). The launcher enforces the same independently at upload: "Source commit is not the live default-branch HEAD" (`Services/PublicationReceiptGate.cs:410-416`, live query in `QueryLiveSnapshot` at `:1053-1096`). 31 of 81 verified ships went out from a head commit that did not change the shipped mod: the operator waited for CI on someone else's merge. The default for D-P-06 is "no launcher change", so by default this card is parked and WP-P-09's retry handles a moved head.

**Steps.**
1. Only with D-P-06 granted. First measure: with `tools/ship/ship-stats.ps1` (WP-P-02), over 20 ships after WP-P-06, count runs whose `message` contains `is not live`. If fewer than 4, stop: the change is not worth its risk.
2. Launcher repository (`Ensrick/vmb-launcher`, from tag `v0.6.3`): in `Services/PublicationReceiptGate.cs` extend `QueryLiveSnapshot` to compute, with `git` in the source root, whether the receipt's source commit is an ancestor of the live head and whether `git rev-parse <commit>:<mod folder>` and the blob of `tools/mod-inventory.psd1` are equal at both commits. Replace the two `SameSha(..DefaultBranchCommit, receipt.SourceCommit)` tests at lines 411-416 with: equal, or ancestor with equal mod tree and equal inventory blob. Add tests to `tests/PublicationReceiptGateTests.cs` for the five cases in Acceptance. Add the capability string `ancestor-mod-tree-authorization-v1` to `CapabilitiesCommand` (`Cli/Commands.cs:134-158`). Release as `v0.6.4` through that repository's own procedure.
3. This repository: in `tools/ship/publication-authorization.ps1` give `Test-PublicationAuthorizationSnapshot` the parameters `SourceIsAncestor`, `SourceModTree`, `DefaultModTree`, `SourceInventoryBlob`, `DefaultInventoryBlob` and apply the same rule; record the live head and the mod tree in the evidence object. Give `Get-LivePublicationAuthorization` the parameters `-RepoRoot` and `-Mod`, fetch the default branch, and compute those values. Pass them at the three call sites in `tools/ship/ship.ps1` and at the publisher's call in `tools/publish-release/publish-release.ps1`.
4. Raise `$minimumShipLauncherVersion` (`tools/ship/ship.ps1:2015`) to `0.6.4` and require the new capability in `Test-VmbLauncherPublicationCapabilityOutput` (`tools/ship/publication-receipt.ps1`).

**Acceptance (machine, no human).**
- OFFLINE, both repositories: fixtures for five cases. (a) head equals source: allowed. (b) head moved, source is an ancestor, mod tree and inventory equal: allowed. (c) mod tree differs: refused, message names both tree ids. (d) source is not an ancestor: refused. (e) inventory blob differs: refused.
- OFFLINE: `ship.ps1 -SelfTest` under both hosts; `pwsh qa/run_selftests.ps1`; the launcher's test suite.
- LIVE: one dev ship completes while an unrelated pull request is merged during its build; `ship-result.json` records a `source_commit` that differs from the head at upload time.
- Evidence class S.

**Guardrails.** The merged pull request and the green `qa-gate` on the shipped commit stay mandatory. Do not install a launcher build that was not released from the launcher repository's tagged source.

**Stop and escalate if.** D-P-06 is not granted (default). The launcher source checkout is missing or not at a released tag. Any other launcher gate also compares against the live head.

---

### WP-P-09 Add a resumable release driver inside the repository

| Field | Value |
|---|---|
| Priority | P1 |
| Size | L. Split: (a) `land` action and tests; (b) `start`; (c) `finish` with resume and retry |
| Agent | any for (a); strong for (b) and (c) (state machine around a publishing tool) |
| Depends on | WP-P-02 (ledger), WP-P-07; works with or without WP-P-05 |
| Issues | advances #1025, #724 |
| Source | B1-F09, B1-F07 |
| Streams | none (tooling only) |

**Goal.** `tools/ship/release.ps1` takes a mod with finished source edits from claim to verified upload in one command, can be rerun after any interruption without repeating a completed step, and replaces the scripts in `%USERPROFILE%\.claude\vt2-ship-helpers\`.

**Context.** `ship.ps1` performs 2 of the 21 steps of a dev ship. The rest (claim, version strings, commit, pull request, waiting, merge, waiting, sync, pin pull request) is done by hand or by unversioned helper scripts. Recurring failures are all mechanical: version text out of step in the Lua file, `itemV2.cfg` and CHANGELOG; a pull-request body with a closing keyword; a branch behind `master`; a head that moved before the ship; a claim owner that changed between processes.

**Steps.**
1. Create `tools/ship/release.ps1` with `-Action land|start|finish|run|status`, `-Mod`, `-Pr`, `-Branch`, `-ChangelogFile`, `-PrTitle`, `-PrBodyFile`, `-CommitMessageFile`, `-AllowPublic`, `-NoRemote`, `-ConfirmVersion`, `-DryRun`, `-SelfTest`. All `gh` and `git` calls go through two wrapper functions, `Invoke-ReleaseGh` and `Invoke-ReleaseGit`, so tests can replace them.
2. Journal: `%APPDATA%\VMBLauncher\ship_runs\release-<mod>.json` with `mod`, `session_id` (a GUID created at claim time), `version`, `branch`, `pr`, `merge_commit`, and one entry per step. At the start of every action set `$env:VT2_SHIP_SESSION_ID` to the journal's `session_id` so the claim owner stays the same across processes (`tools/ship/claim.ps1:135`).
3. Every step has a postcondition that is checked against the real state, not the journal. A step whose postcondition holds is skipped.
   - claim: `tools/ship/claim.ps1 -Mod <mod>`; done when `claim.ps1 -Mod <mod> -Verify -ExpectedVersion <version>` exits 0.
   - version: read the old `MOD_VERSION` from `<mod>/scripts/mods/<mod>/<mod>.lua`; write the claimed one; in `<mod>/itemV2.cfg` replace every ` v<old>` with ` v<new>` (title and description banner); insert `-ChangelogFile` at the top of `<mod>/CHANGELOG.md` after replacing the token `{VERSION}`. Done when `qa/check_versions.ps1` exits with a code below 2 and `Test-ReleaseIdentity` (`tools/ship/release-identity.ps1:41`) accepts the pair.
   - build: `tools/ship/ship.ps1 -Mod <mod> -BuildOnly`. Done when `qa/check_build_receipts.ps1 -Mod <mod>` exits 0.
   - commit: `git add -- <mod>` and commit with `-CommitMessageFile`. Done when `git status --porcelain -- <mod>` is empty.
   - pull request: push the branch; reject a body that matches `(?i)\b(close[sd]?|fix(e[sd])?|resolve[sd]?)\s*:?\s+#\d+` (use `Refs #N`); `gh pr create`. Done when `gh pr view <branch> --json number` returns a number.
   - land (also available alone as `-Action land -Pr <n>`): wait while `mergeStateStatus` is `UNKNOWN`; exit 11 on `DIRTY`; on `BEHIND` run `gh pr update-branch` and wait for the head to change; wait until the check `qa-gate` is in bucket `pass` and nothing is pending (exit 12 on a failed check); `gh pr merge --merge --delete-branch`; confirm state `MERGED` (exit 10); wait for the `QA` run on `master` whose `headSha` is the merge commit (exit 13 if not `success`).
   - sync: fetch; put the worktree on the live `origin/master` commit, clean.
   - ship: `tools/ship/ship.ps1 -Mod <mod>` with `-AllowPublic` or `-NoRemote` as given. Done when the ledger of WP-P-02 holds a record with this mod, this version, mode `ship`, status `ok`. If the result's `message` says the commit is not the live head, repeat sync and ship, at most three times (exit 24 after that).
   - aftercare: if `git status --porcelain` lists `tools/verify/live_test_contract_exceptions.psd1`, commit only that file on `pins/<mod>-<version>`, open a pull request and run the land step for it. Otherwise nothing.
4. A version without a pre-release suffix: `finish` stops before the ship step with exit 20 unless `-ConfirmVersion` equals the version (D-P-04).
5. `-Action status -Mod <mod>` prints the journal as JSON. `-DryRun` prints each step with `done` or `pending` and changes nothing.
6. Add `qa/check_release_driver.ps1` with `[switch]$SelfTest`. With stubbed wrappers it asserts: each land exit code; skip of completed steps; the body rule; the exit 20 stop; the three-try head retry; that the session id from the journal wins over an existing environment value.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_release_driver.ps1 -SelfTest` exits 0; same with `powershell`.
- OFFLINE: `pwsh tools/ship/release.ps1 -Action run -Mod general_tweaker_dev -DryRun` prints nine steps and leaves `git status --porcelain` and the `ship_runs` folder unchanged.
- LIVE, on one friends-only mod with a `-dev` version: `-Action start`, then interrupt `-Action finish` while it waits for `qa-gate`, then run `-Action finish` again. Expected: no second claim, no second pull request, one `ok` ship record in the ledger, exit 0.
- Evidence class S.

**Guardrails.** The driver calls `claim.ps1` and `ship.ps1`; it never calls the launcher, `gh release` or the uploader itself. It never restarts Steam, never force-pushes, never deletes a claim. One active journal per mod. Do not copy the helper scripts verbatim: they contain machine paths and session text.

**Stop and escalate if.** A completed real ship is about to be repeated (the ledger shows `ok` for this version and the driver still wants to ship). The claim verify exits 5 (stale) or 6 (other owner): report, do not re-claim.

---

### WP-P-10 Add a rollback action and rehearse it once

| Field | Value |
|---|---|
| Priority | P1 |
| Size | M (half a day plus one rehearsal ship) |
| Agent | any |
| Depends on | WP-P-09 |
| Issues | none |
| Source | B1-F06 |
| Streams | one mod per run. For a dev/stable pair, each tree is rolled back on its own |

**Goal.** One command restores a mod's source to the state of an earlier published version and ships it as a new version, and the time this takes is measured.

**Context.** Policy is roll-forward only (`docs/PROMOTION_PROCESS.md:189-193`). No tool exists and the path was never rehearsed. Re-uploading old bytes directly is not possible: the launcher only uploads a build that matches the current commit, version and claim (`Services/PublicationReceiptGate.cs:392-420` in the launcher repository). The commit of every published version is recorded: each release's `manifest.json` has a row per mod with `mod_id`, `version` and `source_commit`.

**Steps.**
1. Add `-Action rollback -Mod <mod> -ToVersion <version> -Reason <text>` to `tools/ship/release.ps1`.
2. Find the commit: read `ModId` for the mod from `tools/mod-inventory.psd1`; walk `gh release list --limit 200 --json tagName` newest first; for each tag read `manifest.json` (`gh release download <tag> -p manifest.json -O -`); take `source_commit` of the first row with that `mod_id` and `version`. Exit 30 when none is found.
3. Require a clean worktree on the live `origin/master`. Restore: `git rm -r -q -- <mod>`, `git checkout <source_commit> -- <mod>`, then `git checkout HEAD -- <mod>/CHANGELOG.md <mod>/itemV2.cfg` (history and Workshop identity stay current).
4. Write a changelog fragment with the first line `## {VERSION} (<date>) - Roll back to <ToVersion>` and a body naming the reason, the commit and the release tag. Put no issue number and no lifecycle tag in the heading, so the ship labels nothing.
5. Continue with the `run` flow of WP-P-09 (claim a new version, write it, build, commit, pull request, land, ship).
6. Extend `qa/check_release_driver.ps1`: in a temp repository with two versions of a fake mod, after the restore step `git diff --stat <old commit> -- <mod>/scripts` is empty and a file added after the old version is gone.
7. Rehearse on `verminious_dreams_lighting_dev` (friends-only, `-dev` version): roll back to its previous published version, then restore the current source the same way. Record both durations from the ledger in the pull request.

**Acceptance (machine, no human).**
- OFFLINE: the extended self-test exits 0 under both hosts.
- LIVE rehearsal: after the first run, `git diff <source_commit> origin/master -- verminious_dreams_lighting_dev/scripts` shows only the `MOD_VERSION` line; the ledger holds an `ok` ship record; after the second run the `scripts` tree differs from the pre-rehearsal commit only in the `MOD_VERSION` line.
- Report the measured wall-clock time. Target: 60 minutes or less before WP-P-06, 30 or less after.
- Evidence class S for the tool. The rehearsal proves the path, not gameplay.

**Guardrails.** Never reuse an old version number. Never restore `itemV2.cfg` from the old commit. A version without a suffix still stops at exit 20 (D-P-04).

**Stop and escalate if.** The mod is `weapon_tweaker` or `weapon_tweaker_dev`: `qa/check_wt_stream_parity.ps1` binds the two trees and versions, so a one-sided rollback fails the gate. The old commit's tree fails today's blocking QA for a reason unrelated to the mod's own code.

---

### WP-P-11 Move mods to receipt authority; stop tracking bundles

| Field | Value |
|---|---|
| Priority | P2 |
| Size | L. Split: pilot (`character_dialogue`), then one pull request per mod |
| Agent | strong for the pilot (first real use of this lane); any for the repeats |
| Depends on | WP-P-02; decision D-P-02 (granted by default) |
| Issues | advances #558 (closes it when all 21 rows are done) |
| Source | B1-F04, B1-F13 |
| Streams | single-stream and `_dev` rows first. Stable rows only with D-P-05 |

**Goal.** No `.mod_bundle` file is tracked at `HEAD`; each mod commits only its hash receipt.

**Context.** Bundles are 16.52 GiB of 16.73 GiB of history. The repository already has a second mode, selected per mod by `BundleAuthority` in `tools/mod-inventory.psd1`: `receipt` keeps `<mod>/.build-receipt.json` (schema 3, hashes of every output file) and no tracked `bundleV2/`. The switch is one typed change (`docs/BUNDLE_AUTHORITY.md:53-62`), validated by `qa/check_bundle_authority.ps1`. The approved launcher supports it (capabilities `receipt-authority-publication-v1` and `receipt-authority-local-deploy-v1`, `Cli/Commands.cs:145-146`). All 21 rows are still `tracked`. 20 mods already have a schema-3 receipt; `verminious_dreams_lighting` has none. Issue #558 says no row may flip until a durable archive exists (#1434). The program default D-P-02 waives that for forward tracking: old bundles stay in git history, which is not rewritten (D-P-03), and every build is also a release asset.

**Steps.**
1. Pilot on `character_dialogue` (friends-only, `0.1.15-dev`, four tracked files). Confirm the starting state: `pwsh qa/check_build_receipts.ps1 -Mod character_dialogue` exits 0.
2. One commit with exactly these changes: in `tools/mod-inventory.psd1` set that row to `BundleAuthority = 'receipt'`; add the line `/character_dialogue/bundleV2/` to the root `.gitignore`; `git rm --cached` all four files of `character_dialogue/bundleV2/`. Do not touch `.build-receipt.json` or any source file.
3. Run `pwsh qa/check_bundle_authority.ps1`, `pwsh qa/check_release_bundle_atomicity.ps1`, `pwsh qa/check_mod_inventory.ps1`: all exit 0. Land the pull request.
4. Prove the lane with one real dev ship of `character_dialogue` through WP-P-09 (changelog: "authority transition, no runtime change"). Add `-NoRemote` if `<workshop>\3765055148\` exists.
5. Check the published result: the release `manifest.json` row for `character_dialogue` has `bundle_authority` `receipt`; the zip named by `asset_filename` exists; its SHA-256 equals the row's `sha256`; its entries are the names in the receipt's output list.
6. Repeat steps 1-5 without the proof ship for, in this order: `event_tweaker`, `enemy_tweaker`, `career_tweaker`, `dynamic_cosmetic_portraits`, `weapons_of_chaos`, `modded_progression`, the five `_dev` rows and `weapon_tweaker_dev`, `weapon_tweaker`, `cosmetics_tweaker`, `character_weapon_variants`. One pull request per mod.
7. Stable rows (`chaos_wastes_tweaker`, `crafting_in_modded`, `general_tweaker`, `gui_tweaker`, `verminious_dreams_lighting`) change at their next promotion (WP-P-13), because any edit under a stable directory needs promotion approval.
8. When the last row is done, update the three texts that say every row is tracked: `docs/BUNDLE_AUTHORITY.md:28`, the header of `tools/mod-inventory.psd1`, the header of `qa/check_bundle_authority.ps1`.

**Acceptance (machine, no human).**
- Per mod: `git ls-files <mod>/bundleV2 | wc -l` is 0; the three gates in step 3 exit 0; `qa-gate` is green.
- Pilot: `ship-result.json` status `ok`, and the four checks of step 5 pass.
- Final: `git ls-files "*.mod_bundle" | wc -l` is 0. Evidence class S for #558.

**Guardrails.** Do not rewrite history, do not run `git gc --prune` or `git filter-repo` (D-P-03). Do not delete bundle files from disk in the primary checkout: other sessions may be building. After a mod is in receipt mode, `tools/harness/stage-build.ps1 -Source tracked` no longer works for it; use `-Source build` (WP-P-04).

**Stop and escalate if.** `ship.ps1` fails its capability probe for receipt authority. `qa/check_bundle_authority.ps1` rejects the transition although the commit holds exactly the three changes. The release has no zip for the mod. The updater (`<repos>/vt2-mod-updater`) refuses the row: stop the rollout and report; do not flip further mods.

---

### WP-P-12 Lock verminious_dreams_lighting stable to generated output

| Field | Value |
|---|---|
| Priority | P2 |
| Size | M (half a day) |
| Agent | any |
| Depends on | none |
| Issues | none |
| Source | B1-F05 |
| Streams | neither tree's files change in this card. Afterwards: hand edits only in `verminious_dreams_lighting_dev/` |

**Goal.** The stable tree of the lighting mod can change only through `tools/promote/promote.ps1`, a gate enforces that, and the generator is proven on the current dev tree.

**Context.** "Single tree" in this track means one hand-edited tree per mod. The other stream's directory stays in git as generated output, because `ship.ps1` and the launcher read a mod's files from git under `<mod>/` at the shipped commit (`tools/ship/ship.ps1:1885-1903`; `Services/PublicationReceiptGate.cs` in the launcher repository). Deleting the generated directory would need launcher support and is not part of this track. `tools/promote/promote.ps1` already ports dev to stable with identity replacement (`Convert-Id`, lines 63-82; pair table at 45-51), but only top-level Lua files (`Get-ChildItem -Filter *.lua -File`, line 90), in place, with no record of what it produced. The lighting pair is the smallest: stable has 3 Lua files at version `1.0.7`, dev has 4 at `1.0.20-dev`, and the dev main file loads `_lib_debug.lua` (`verminious_dreams_lighting_dev/scripts/mods/verminious_dreams_lighting_dev/verminious_dreams_lighting_dev.lua:19`), so the stable output needs all four.

**Steps.**
1. Add `qa/check_promotion_snapshot.ps1` with `-Staged` and `-SelfTest`. For every `tools/promote/snapshots/<mod>.json` it compares the git blob id of every `*.lua` under `<mod>/scripts/mods/<mod>/` (recursive; `HEAD`, or the index with `-Staged`) with the manifest's `files` list. Exit 2 on a changed, missing or extra file. Self-test fixtures: match passes; one edited file fails; one extra file fails; one missing file fails.
2. In `tools/promote/promote.ps1`: enumerate dev Lua files recursively and keep relative sub-paths; add a per-pair `DevOnlyFiles` list to the table at lines 45-51 (empty for every pair now) and skip exactly those names; add `-OutDir <path>` to write the generated tree there instead of the stable directory; add `-WriteManifest` to write `tools/promote/snapshots/<mod>.json` with `schema 1`, `mod`, `source_dir`, `source_commit`, `version`, `baseline: false`, `files: [{ path, git_blob }]`.
3. Add `-Baseline` to `promote.ps1`: writes the manifest from the stable tree as it is now, with `source_commit: null` and `baseline: true`. Run it for `verminious_dreams_lighting` and commit `tools/promote/snapshots/verminious_dreams_lighting.json`.
4. Wire the gate into `qa/run_all.ps1` before the Quick return (next to `check_mod_inventory`, line 268), passing `-Staged:$Staged`, so the pre-commit hook and the ship preflight run it.
5. Prove the generator without touching the stable tree: `pwsh tools/promote/promote.ps1 -Mod verminious_dreams_lighting -Apply -Version 1.0.20 -OutDir <temp>`.
6. In `docs/PROMOTION_PROCESS.md` add one paragraph under "Two promotion modes": a pair with a snapshot manifest is promoted only as a whole tree with `promote.ps1 -Apply -WriteManifest`; hand-applied hunks (Mode A) are not allowed for it.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_promotion_snapshot.ps1 -SelfTest` exits 0; `pwsh qa/check_promotion_snapshot.ps1` exits 0 on the repository.
- OFFLINE, in a scratch worktree: append a blank line to `verminious_dreams_lighting/scripts/mods/verminious_dreams_lighting/verminious_dreams_lighting.lua`, `git add` it, run `pwsh qa/check_promotion_snapshot.ps1 -Staged`: exit 2. Then discard the change.
- OFFLINE: step 5 exits 0 and prints `grep-clean`; `<temp>` holds 4 Lua files; `Select-String -Path <temp>\*.lua -Pattern 'verminious_dreams_lighting_dev'` finds nothing; each file parses: `qa/lua/vendor/lua-5.1.5-win64/lua5.1.exe -e "assert(loadfile([[<file>]]))"` exits 0 (this compiles the file and does not run it).
- OFFLINE: `git diff --stat origin/master -- verminious_dreams_lighting verminious_dreams_lighting_dev` is empty for this card's pull request.
- Evidence class S.

**Guardrails.** Do not promote or ship `verminious_dreams_lighting` in this card: its version has no suffix (D-P-04). Keep the manifest outside mod directories (track brief line 14). Do not change `Convert-Id` behaviour for existing pairs.

**Stop and escalate if.** The generated main file differs from the dev file in more than identity strings and the `MOD_VERSION` line (compare line by line after applying `Convert-Id` to the dev text). `qa/check_dev_only_edits.ps1` or the promotion authorization check flags this tooling-only pull request.

---

### WP-P-13 Template: move one dev/stable pair to a single hand-edited tree

| Field | Value |
|---|---|
| Priority | P2 |
| Size | L per pair. Split exactly along the steps: reconcile, classify, lock, promote |
| Agent | strong (decides which stable-only code is kept; needs the mod family's context) |
| Depends on | WP-P-12; WP-P-04 for the rig check; the mod family's own fix cards. For Chaos Wastes: auditor A4's reconciliation cards first |
| Issues | the pair's open `public-release` issues are advanced when its promotion ships |
| Source | B1-F05 |
| Streams | both trees until step 5. After step 5: `<mod>_dev/` only, and `<mod>/` only through `promote.ps1` |

**Goal.** For pair `<mod>`, every fix is written once in `<mod>_dev/`, and `<mod>/` is reproduced from it by `tools/promote/promote.ps1`.

**Context.** Use this card once per pair, in this order (measured 2026-11-13, Lua files only: stable-only / dev-only / differing / changed lines): `crafting_in_modded` 1 / 4 / 23 / 744; `gui_tweaker` 9 / 9 / 72 / 2,167 (has an `hb/` sub-folder); `general_tweaker` 1 / 35 / 37 / 7,431; `chaos_wastes_tweaker` 12 / 57 / 21 / 20,271, last, because its stable tree holds its own `_ct_official_*` modules. `weapon_tweaker` and `weapon_tweaker_dev` already keep byte parity under `qa/check_wt_stream_parity.ps1` and are out of scope. The rule "a public-release fix goes into BOTH trees" applies to a pair until its step 5 is merged.

**Steps.**
1. Measure. `pwsh tools/promote/promote.ps1 -Mod <mod>` (dry run) lists files to update and files new in dev. List stable-only files by comparing the two `scripts/mods/` file sets with the dev suffix removed.
2. Reconcile into dev. For every stable-only file and every stable-only hunk, decide with the family's cards: port it into `<mod>_dev/` (normal dev pull request with its test) or record why it is dropped. Finish when stable has no behaviour that dev lacks.
3. Classify dev-only code. A whole file that must not reach stable goes into the pair's `DevOnlyFiles` list in `tools/promote/promote.ps1`. Dev-only code inside a shared file is wrapped in paired comment markers `-- <ID>_DEV_OVERLAY_BEGIN:<name>` and `-- <ID>_DEV_OVERLAY_END:<name>` (the convention `qa/check_wt_stream_parity.ps1` already uses), and `promote.ps1` strips marked blocks. Add that stripping, with a self-test, in the first pair that needs it. Everything unmarked ships to stable.
4. Preview. `pwsh tools/promote/promote.ps1 -Mod <mod> -Apply -Version <current stable version> -OutDir <temp>`, then `git diff --no-index --stat <mod>/scripts/mods/<mod> <temp>`. This is exactly what the next promotion changes for players. Attach it to the pair's promotion issue.
5. Lock. `pwsh tools/promote/promote.ps1 -Mod <mod> -Baseline`; commit the manifest. From this merge on, `qa/check_promotion_snapshot.ps1` rejects hand edits to `<mod>/`.
6. Verify before promoting. In a worktree, apply the promotion (`-Apply -Version <next> -WriteManifest`), stage that stable build for the rig with `pwsh tools/harness/stage-build.ps1 -Mod <mod> -Source build -RepoRoot <worktree>`, and run the family's verification packs against it.
7. Promote, only when allowed (D-P-04 for a version without a suffix, D-P-05 for the promotion label): the same promotion commit, then the flow of WP-P-09 with `-AllowPublic`. Follow `docs/PROMOTION_PROCESS.md`, "Protected-PR authorization". In the same pull request the stable row may move to receipt authority (WP-P-11, step 2).

**Acceptance (machine, no human).**
- After step 2: the stable-only file list is empty, or every remaining name has a recorded decision in the pull request.
- After step 5: `pwsh qa/check_promotion_snapshot.ps1` exits 0; a staged hand edit under `<mod>/scripts` makes it exit 2.
- After step 6, RIG: the family's verification packs PASS on the staged stable build (arena and assertions as defined in those packs).
- After step 7: regenerate to a temp folder from the recorded `source_commit` and `git diff --no-index <mod>/scripts/mods/<mod> <temp>` is empty.
- Evidence classes: S for the lock; R for the build check; issue closure follows the family's packs.

**Guardrails.** No hand hunks into a locked stable tree. Do not copy `itemV2.cfg`, `published_id` or visibility between streams (`promote.ps1` leaves them alone). Cross-mod calls keep targeting the stable ids (`get_mod("cim")`, `get_mod("gt")`).

**Stop and escalate if.** A stable-only module has no dev counterpart and no owner decision (Chaos Wastes `_ct_official_*`: wait for A4's cards). The preview in step 4 contains a feature that has no passing verification pack. D-P-04 or D-P-05 is not satisfied at step 7: stop after step 6 and leave the promotion pull request open.

---

## Owner decisions

| Id | Question | Conservative default the cards assume |
|---|---|---|
| D-P-01 | May all tooling require PowerShell 7 and drop Windows PowerShell 5.1? | Yes. Applied in WP-P-06 stage B (the three `shell: powershell` CI steps). Until that lands, new scripts stay 5.1-parsable. |
| D-P-02 | May bundles stop being tracked going forward, although issue #558 says to wait for a durable archive (#1434)? | Yes. WP-P-11 proceeds mod by mod. Old bundles stay in history; every build is also a release asset. |
| D-P-03 | Rewrite git history or start a fresh repository to shed 16.5 GiB? | Not assumed. Pending. No card depends on it and WP-P-11 forbids history rewriting. |
| D-P-04 | Who may upload a public version that has no pre-release suffix? | Only the owner's fresh signal naming the version. Encoded as `release.ps1 -ConfirmVersion <version>`; without it the driver stops with exit 20 before the ship. |
| D-P-05 | May an agent apply the `stable-promotion-approved` label to its own promotion pull request? | Only when the stable version being promoted carries a pre-release suffix (today `chaos_wastes_tweaker` at `-beta`), which the doctrine already ships without asking (`PROJECT_STANDARDS.md:1398-1406`). Otherwise the pull request waits for the owner. |
| D-P-06 | May the launcher be changed and re-released so a ship no longer needs the exact live head? | No. WP-P-08 stays parked; WP-P-09 retries when the head moved. |
| D-P-07 | Is whole-tree promotion (no hand-picked hunks into stable) acceptable? | Yes for `verminious_dreams_lighting`. For every other pair only after its verification packs pass on the generated stable build (WP-P-13, step 6). |
| D-P-08 | Drop the "branch must be up to date" rule (`strict`) in branch protection once CI is fast? | No change. Keep `strict`. |
| D-P-09 | Who may restart Steam when the launcher doctor reports it not ready? | Nobody automatically. The ship stops and the question goes to the owner (`docs/PORTABLE_SETUP.md`, "SDK prerequisites and exceptional Steam recovery"). |
| D-P-10 | What happens to the 386 unmerged local and 44 unmerged remote branches, 54 stashes and 226 preserve or archive refs? | Kept untouched. WP-P-03 deletes merged branches only and posts the unmerged inventory on issue #546. |
