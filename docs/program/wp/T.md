# Track T: test infrastructure work packages

Author: auditor B2, 2026-11-13. Source findings: `docs/audits/2026-11-13_FORMAL_AUDIT/evidence/B2.md` (B2-F01 to B2-F15).

Conventions used in every card:
- Paths are relative to the repository root (`vermintide-2-tweaker`) unless they start with `<audit>` (the audit workspace folder `vt2-audit-20261113`) or `<repos>` (the folder that holds the repos; the decompiled game source is `<repos>/Vermintide-2-Source-Code`, revision `93dea911`, game version 6.13.0).
- "Audited trees" means: `weapon_tweaker`, `chaos_wastes_tweaker_dev`, `general_tweaker_dev`, `gui_tweaker_dev`, `crafting_in_modded_dev`, `verminious_dreams_lighting_dev`, `cosmetics_tweaker`, `dynamic_cosmetic_portraits`, `career_tweaker`, `enemy_tweaker`, `character_weapon_variants`, `character_dialogue`, `weapons_of_chaos`, `event_tweaker`, `modded_progression`.
- The offline Lua suite is run with `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` from the repository root. Baseline on 2026-11-13: 584 suites, 7,537 cases, all pass, 3m16s.
- Order: WP-T-06 first (the Quick gate is red today), then WP-T-01, WP-T-02, WP-T-04, WP-T-03, the rest in any order.

Measured baseline the cards refer to (all from `docs/audits/2026-11-13_FORMAL_AUDIT/evidence/B2.md`):
- 792 literal in-game check registrations in the audited trees: 31 read live session state, 178 read engine data tables, 333 only call mod logic with made-up inputs, 78 are marker or source-text only, 159 are existence checks, 13 register a named function.
- The offline suite executes 43.2% of logic lines; 11 of 15 entry files are never loaded.
- 595 Lua test files: 504 behavioural, 85 source-text dominated, 6 tooling.

---

### WP-T-01 Give every regression runner a programmatic entry and printf verdicts

| Field | Value |
|---|---|
| Priority | P1 |
| Size | L (split: step 1-3 one session; then one session per 4 mods) |
| Agent | strong for steps 1-3 (shared contract the rig parses), any for the per-mod roll-out |
| Depends on | none |
| Issues | advances every `verify-fix` issue whose card names a regression check (167 of 228); #1656 |
| Source | B2-F02 |
| Streams | every tree that has a runner: dev and stable for the five pairs, `weapon_tweaker` and `weapon_tweaker_dev` |

**Goal.** Each mod exposes `mod.run_regression_tests()` and prints one engine `printf` line per check, so the rig and a log reader get verdicts without chat and without mod logging.

**Context.** There are 15 separate runner copies. They print PASS through `mod:echo` + `mod:info` and FAIL through `mod:echo` + `mod:warning` (example `weapon_tweaker/scripts/mods/weapon_tweaker/_wt_regression.lua:28-49`). The owner plays with mod logging off, so only engine `printf` is guaranteed to reach `console-*.log` (repository `CLAUDE.md` rule 9; `PROJECT_STANDARDS.md:819-821`). Seven runners count SKIP, seven do not; only `general_tweaker_dev` has BAD-SHAPE (`general_tweaker_dev/scripts/mods/general_tweaker_dev/general_tweaker_dev.lua:404`); only `character_weapon_variants` has XFAIL/XPASS (`character_weapon_variants.lua:226-250`). The runners can only be started by typing a chat command.
Runner sites: `_wt_regression.lua:28` (wt, both trees), `chaos_wastes_tweaker_dev.lua:348`, `chaos_wastes_tweaker.lua:328`, `general_tweaker_dev.lua:390`, `general_tweaker.lua:365`, `gui_tweaker_dev.lua:151`, `gui_tweaker.lua:146`, `_cim_bootstrap_runtime.lua:156` (both cim trees), `_cos_command_owner.lua:42`, `_crt_regression.lua:43`, `_et_regression.lua:33`, `_evt_regression.lua:24`, `modded_progression.lua:115`, `dynamic_cosmetic_portraits.lua:154`, `verminious_dreams_lighting_dev.lua:71`, `verminious_dreams_lighting.lua:74`, `weapons_of_chaos.lua:119`, `character_dialogue.lua:610` (custom self-check, no check list).

**Steps.**
1. Read `tools/shared_lib/manifest.psd1` and `tools/shared_lib/sync-shared-libs.ps1` to see how `_lib_debug.lua` is declared and copied into mods, and how a copied library is listed in a mod's `resource_packages/<mod>/<mod>.package` (`qa/check_dofile_package_coverage.ps1` enforces the listing).
2. Add `tools/shared_lib/_lib_regression_runner.lua`. It returns a table with `new(opts)` where `opts = { prefix = "<log prefix>", version = MOD_VERSION, emit = <function(line)>, echo = <function(fmt, ...)> or nil }`. `new` returns `{ register = function(name, fn, check_opts), run = function() ... end, count = function() ... end }`. `run` executes every check under `pcall` and maps the result: `nil` = PASS; a string starting with `skip:` = SKIP; any other string or a raised error = FAIL; boolean `true` = BADSHAPE; `check_opts.known_defect` set and the check fails = XFAIL, set and the check passes = XPASS. For each check it calls `emit` with exactly `[<prefix>:rt] <check> <VERDICT> <detail>` (detail empty for PASS; one line, newlines replaced by spaces, cut at 300 characters). After the loop it emits `[<prefix>:rt] done pass=<n> fail=<n> skip=<n> xfail=<n> total=<n> v=<version>`. FAIL count includes XPASS and BADSHAPE. `run` returns a table `{ pass, fail, skip, xfail, total, results = { { name, verdict, detail }, ... } }`. The default `emit` is `function(line) pcall(printf, "%s", line) end`.
3. Add `qa/lua/tests/test_shared_regression_runner.lua` and list it in the `suites` table of `qa/lua/run.lua`. It loads the library with `loadfile`, passes a test-local `emit` that appends to a list, and asserts the exact line text for each of the six verdicts, the summary line, the 300-character cut, that a raising check does not stop the loop, and that `run` returns the counts.
4. Per mod: replace the runner body with the library. Keep the existing registrar name (`_rt_register`, `mod._ct_rt_register`, `mod._gt_rt_register`, `WT.rt_register`, ...) as a thin alias of `runner.register` so no check registration line changes. Set `mod.run_regression_tests = function() return runner.run() end`. Keep the chat command; its callback calls `mod.run_regression_tests()` and echoes only the summary to chat. Use as `prefix` the same token the mod already prints in its `[<prefix>:LOAD]` banner.
5. Run `tools/shared_lib/sync-shared-libs.ps1 -Apply` and add the copied file to each mod's `.package`.
6. `character_dialogue.lua:610`: wrap the existing inline self-check as one registered check named `cd_selfcheck` on the same library.
7. Delete or rewrite `qa/lua/tests/test_regression_runner_verdicts.lua` cases that cut the old runner text out of entry files; the behaviour is now covered by step 3.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0 and its output contains the case names of `test_shared_regression_runner`.
- OFFLINE: `git grep -n '=== %d passed' -- '*/scripts/mods/*'` returns 0 lines. `git grep -c 'run_regression_tests' -- '*/scripts/mods/*'` lists every tree named in Context.
- OFFLINE: `pwsh -NoProfile -File qa/check_shared_lib_drift.ps1` and `pwsh -NoProfile -File qa/check_dofile_package_coverage.ps1` exit 0.
- RIG: plan with arena `boot` loading all dev mods; `host_expect_log` contains one `[<prefix>:rt] done ` line per loaded mod. Evidence class R for the runner itself.

**Guardrails.** Do not change any check body in this card. Do not change registration order (output order is relied on). Do not print through `mod:info`, `mod:debug` or `mod:warning`. Do not add a new chat command.

**Stop and escalate if.** The harness track (WP-H) defines a different line format for `T.expect_rt`: use theirs and note it here. A mod's entry file is at the Lua 200-local limit and cannot take one more local (`chaos_wastes_tweaker_dev.lua` documents this at lines 339-341): attach the runner to the `mod` table instead and say so.

---

### WP-T-02 Move marker-only checks offline; make vacuous passes SKIP

| Field | Value |
|---|---|
| Priority | P1 |
| Size | L (split per mod; ct_dev and gt_dev first, they hold 36 of the 78) |
| Agent | any |
| Depends on | WP-T-01 (for the SKIP verdict in every runner) |
| Issues | #1656; advances #463, #693 (their only checks are marker checks) |
| Source | B2-F03, B2-F05 |
| Streams | audited trees; apply the same edit to the stable twin when the check exists there |

**Goal.** No in-game check passes by comparing a string to itself or by returning early without testing anything.

**Context.** 78 in-game checks only compare marker constants or source text, and 6 define the marker as a local inside the check, so they cannot fail. Examples: `career_tweaker/scripts/mods/career_tweaker/_crt_regression.lua:136-141` (`rawget_on_buff_templates_marker`), `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_regression.lua:330-341` (`game_round_ended_swallows_error`), `weapon_tweaker/scripts/mods/weapon_tweaker/_wt_runtime_checks.lua:36-48` (`husk_extension_hooked`), `general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_creature_spawner.lua:1640-1647` (`gt693_cs_client_request_wired`, compares a flag set at line 1003). Other checks return `nil` (PASS) when their subject is absent, for example `_ct_regression.lua:426-436` (`if not cls then return nil end`). The static home for text invariants already exists: `qa/rt_textual_invariants.psd1` (350 rows) checked by `qa/check_rt_textual_invariants.ps1`.
The full classified list is `<audit>/scripts/B2_out/rt_checks_classified.json` (fields `mod`, `file`, `line`, `name`, `cls`, `marker`); the classifier is `<audit>/scripts/B2_rt_extract.py` + `B2_rt_classify.py`.

**Steps.**
1. Copy the two classifier scripts into `qa/tools/rt_check_census.py` (one file; take the repository root from its own location, no absolute paths). Add modes `--list` and `--fail-on marker,local-marker` (exit 2 when any check is in class `M` or defines `local ... MARKER ... = "` inside its body).
2. For each class `M` check: if the marker constant is still useful as a "fix present" needle, add a row to `qa/rt_textual_invariants.psd1` (fields documented at the top of that file; grep the live source for the needle first) and delete the in-game check. If the needle protects nothing, delete the check. If the check claims a hook is installed, replace the body with a real read: the target class exists and the mod's own handler was registered (use the registration record from WP-T-09 when it exists; until then return `skip: no hook introspection`).
3. For each check that returns `nil` when its subject is missing (`if not X then return nil end`, `if not X then return end` before the first assertion): return `"skip: <what is missing>"` instead. Find candidates with `py -3 qa/tools/rt_check_census.py --list --early-nil` (add that mode: a `return` or `return nil` inside an `if not ...` on a line before the first failure string).
4. Update each mod's CHANGELOG entry and bump `MOD_VERSION` per the repository rules for the trees touched.

**Acceptance (machine, no human).**
- OFFLINE: `py -3 qa/tools/rt_check_census.py --fail-on marker,local-marker` exits 0.
- OFFLINE: `pwsh -NoProfile -File qa/check_rt_textual_invariants.ps1` exits 0 with the new rows.
- OFFLINE: `py -3 qa/tools/rt_check_census.py --list --early-nil` prints 0 rows.
- Evidence class S for the moved invariants. Issues #463 and #693 are NOT closed by this card: they need a rig script (class R).

**Guardrails.** Do not weaken a check that reads engine tables. Do not delete a check whose name appears in an open issue's pinned card without replacing it by a rig assertion or a textual row: `git grep` the name in `qa/runtime` and ask the VP owner if it is cited. Never make a suite green by loosening an assertion (`PROJECT_STANDARDS.md` 5.1d rule 4).

**Stop and escalate if.** A marker check turns out to be the only evidence cited by more than 5 open issues: list them and wait for the VP authors. `qa/check_rt_textual_invariants.ps1` rejects new rows (issue #1577 was this class).

---

### WP-T-03 Add the engine-free integration tier on real vanilla data

| Field | Value |
|---|---|
| Priority | P1 |
| Size | L (split: harness; then one invariant suite per mod family) |
| Agent | strong for the harness (stub boundary needs judgment), any for the suites |
| Depends on | none |
| Issues | none directly; turns data-table defects into class S |
| Source | B2-F01, B2-F04, B2-F11; experiment in `docs/audits/2026-11-13_FORMAL_AUDIT/evidence/B2.md` section 5 |
| Streams | reads all trees, writes only under `qa/` |

**Goal.** One command loads the real vanilla data tables in plain Lua 5.1 and checks mod data against them in seconds.

**Context.** A prototype did this on 2026-11-13 with the vendored `qa/lua/vendor/lua-5.1.5-win64/lua5.1.exe`: 743 vanilla files in 0.5 s; `ItemMasterList` 2,979 entries, `Weapons` 183, `BuffTemplates` 1,547, `Breeds` 79, `CareerSettings` 30; 930 rows of `weapon_tweaker/scripts/mods/weapon_tweaker/wt_unlock_data.lua` and the catalog in `character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_dawi_maces.lua` resolved against them. Prototype files: `<audit>/scripts/B2_engfree/probe.lua`, `stubs3.lua`, `mathshim.lua`, `check_mod_layer.lua`. `NetworkLookup` construction is NOT proven (it reached line 708 of 2,395 of `<repos>/Vermintide-2-Source-Code/scripts/network_lookup/network_lookup.lua`); booting a whole mod entry file is NOT proven. This card covers data tables only.
Exact stub set that was sufficient:
- Loader: strip the UTF-8 BOM; `require`/`dofile` by slash path keyed in `package.loaded`; maintain `package.load_order` (needed by `foundation/scripts/util/local_require.lua:5-16`); map dotted names to slashes.
- Constants: `PLATFORM="win32"`, `BUILD="release"`, `IS_WINDOWS=true`, `IS_CONSOLE`, `IS_LINUX`, `IS_XB1`, `IS_PS4` false, `IS_NOT_CONSOLE`, `IS_NOT_LINUX`, `IS_NOT_XB1`, `IS_NOT_PS4` true, `IS_NOT_WINDOWS=false`, `HAS_STEAM=true`, `DEDICATED_SERVER=false`, `LEVEL_EDITOR_TEST=false`, `LAUNCH_MODE="game"`, `script_data={}`, `GLOBAL_MUSIC_WORLD=false`, `Development={}`.
- Functions with real return values: `Application.platform/build/argv/user_setting/is_dedicated_server/settings/bundled/make_hash/time_since_launch/sysinfo/process_id/guid/set_user_setting/save_user_settings`; `Application.can_get("lua", name)` answers whether `<decompile>/<name>.lua` exists; `Script.new_map` and `Script.new_array` return `{}`; `Math.random`, `Math.random_range`, `Math.next_random(seed, lo, hi)` (stand-in generator, not the engine sequence); `Crashify.print_exception` no-op; `Localize(key)` returns `"<key>"`; `printf`, `print_warning`, `print_error`, `cprint`, `cprintf`, `visual_assert` no-ops; `Color`, `Vector2`, `Vector4`, `Matrix4x4Box` plain-table constructors.
- Shims: LuaJIT `bit` (`tobit`, `band`, `bor`, `bxor`, `bnot`, `lshift`, `rshift`); functional `Vector3`, `Quaternion`, `Vector3Box`, `QuaternionBox` (`mathshim.lua`; needed by `scripts/settings/dlcs/shovel/passive_ability_necromancer_charges.lua:170`).
- Inert recording stubs (indexable, callable, never asserted on): `Managers`, `Wwise`, `WwiseWorld`, `Unit`, `World`, `Level`, `Actor`, `Mover`, `Camera`, `Network`, `GameSession`, `LanClient`, `Steam`, `SteamHelper`, `Gui`, `Material`, `Mesh`, `Window`, `Keyboard`, `Mouse`, `Pad1`, `PhysicsWorld`, `GwNavQueries`, `GwNavWorld`, `EngineOptimized`, `EngineOptimizedExtensions`, `Profiler`, `Renderer`, `ShadingEnvironment`, `LineObject`, `Light`, `Localizer`, `NetworkConstants`, `ResourcePackage`, `Viewport`, `Clipboard`, `Stats`, `Achievement`, `Friends`, `BackendUtils`, `Presence`, `Benchmark`, `Vector3Aux`, `Matrix4x4`, `Rectangle2D`.
- Real vanilla files loaded first, in this order: `foundation/scripts/util/user_setting` (then call `Development.init_user_settings`), `application_parameter` (then `Development.init_application_parameters({}, true)`), `development_parameter` (then `Development.init_parameters`), `error`, `patches`, `class`, `callback`, `misc_util`, `table`, `math`, `string`, `local_require`, `stack`, `circular_queue`, `grow_queue`, `vector3`, `quaternion`, `frame_table`, `path`, `rectangle`, `state_machine`, `script_unit` (all under `foundation/scripts/util/`); `scripts/settings/dlc_settings`; `scripts/helpers/dlc_utils`; `DLCUtils.require_list("additional_settings")` (as the game does at `scripts/boot.lua:387`); `scripts/utils/colors`; `scripts/utils/global_utils`; `scripts/utils/loaded_dice`; `scripts/unit_extensions/human/ai_player_unit/ai_utils`.
- Data targets, in this order: `scripts/settings/equipment/item_master_list`, `scripts/settings/equipment/weapons`, `scripts/unit_extensions/default_player_unit/buffs/buff_templates`, `scripts/settings/breeds`, `scripts/settings/profiles/career_settings`, `scripts/settings/equipment/weapon_skins`.

**Steps.**
1. Create `qa/integration/loader.lua`, `stubs.lua`, `mathshim.lua` from the prototype. Remove every absolute path: the decompile root comes from the first argument; the repository root from the script location.
2. Create `qa/integration/fake_vmf.lua`: `get_mod(id)` returns a recorder with `get`, `set`, `hook`, `hook_safe`, `hook_origin`, `command`, `dofile` (resolves `<mod dir>/<path>.lua` through a mod-id to directory map read from `tools/mod-inventory.psd1` values written into a small Lua table), `echo`, `info`, `warning`, `error`, `debug`, `localize`. It records calls; it simulates nothing.
3. Create `qa/integration/suites/vanilla_selfcheck.lua` (every melee or ranged `ItemMasterList` entry has a `Weapons` template; table sizes are at least the 6.13.0 numbers above), `wt_unlock_map.lua` (every key in `weapon_unlock_map` is in `ItemMasterList` or starts with `cwv_`, its template is in `Weapons`, every career is in `CareerSettings`), `cwv_variant_catalogs.lua` (for each CWV catalog module that can be loaded with `loadfile`: `base_weapon` in `ItemMasterList`, `template` in `Weapons` or starts with `cwv_`, careers in `CareerSettings`). Each suite returns a list of problems.
4. Create `qa/check_integration.ps1`: finds the decompile at `$env:VT2_DECOMPILE_ROOT` or the sibling folder `../Vermintide-2-Source-Code`; if absent prints `[integration] SKIP - decompile not available` and exits 0; otherwise runs the vendored Lua on `qa/integration/run.lua`, prints the table sizes, the number of vanilla files executed, one line per suite, and exits 2 if any suite reports a problem. Add `-SelfTest`: run each suite against a planted bad key and require a failure.
5. Fail the run if a value that came from an inert stub reaches a suite assertion (the stub objects carry a marker field; the assertion helper checks for it).
6. Wire it into the full `qa/run_all.ps1` (not Quick) and add a row to `qa/CHECKS.md`.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_integration.ps1` exits 0 and prints `vanilla files executed:` with a number of at least 700 and `ItemMasterList=2979 Weapons=183 BuffTemplates=1547 Breeds=79 CareerSettings=30` (for decompile revision `93dea911`), in under 10 seconds.
- OFFLINE: `pwsh -NoProfile -File qa/check_integration.ps1 -SelfTest` exits 0.
- OFFLINE: with `VT2_DECOMPILE_ROOT` pointing at an empty folder the command prints the SKIP line and exits 0.
- Evidence class S.

**Guardrails.** Never copy vanilla source into the repository (the decompile is proprietary; `qa/check_source_provenance.ps1` states it is not a CI dependency). Do not simulate frames, units, rendering, packages or network. Do not assert exact `NetworkLookup` indices: vanilla builds them with `pairs()` (`network_lookup.lua:36-45`), so order differs between Lua VMs. Known result, not a defect to fix here: 260 of the 930 `weapon_unlock_map` rows name a weapon the career already wields in vanilla; report it, do not fail on it.

**Stop and escalate if.** A new game version changes boot order so a listed file fails to load: record the failing file and line and stop. You find you need to stub a function's return value to make a suite pass: that assertion does not belong in this tier.

---

### WP-T-04 Wire the patch-day canary as one command

| Field | Value |
|---|---|
| Priority | P1 |
| Size | M |
| Agent | any |
| Depends on | none (uses WP-T-03 when present) |
| Issues | none directly; prevents the 6.12 class (#1671, #1686, #1687) |
| Source | B2-F11; auditor D4 scripts |
| Streams | reads all trees, writes only under `qa/` |

**Goal.** After a game update, `pwsh qa/check_patch_day.ps1` says which hook targets and icon names no longer exist, before anything ships.

**Context.** Game patch 6.12 removed `IngameUI.not_in_modded` and several atlas icons; the mods found out from player reports. Two offline checks exist as audit scripts: `<audit>/scripts/D4_hook_targets.py` (literal `mod:hook("Class", "method")` targets resolve to a definition in the decompile, one inheritance level) and `<audit>/scripts/D4_icon_atlas_check.sh` (literal `icon = "<name>"` values exist in `<repos>/Vermintide-2-Source-Code/scripts/ui/atlas_settings/gui_icons_atlas.lua`). A second hook script, `<audit>/scripts/B2_hook_targets.py`, walks the whole `class(X, Parent)` chain; on 2026-11-13 it found 756 literal string hooks in the audited trees, 752 resolved, and 4 expected misses: three hooks on VMF's own `VMFOptionsView` (`weapon_tweaker/scripts/mods/weapon_tweaker/_wt_master_toggles.lua:294,302`, `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_settings_lifecycle_owner.lua:202`) and one `rawget`-guarded hook (`crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/standard_forge.lua:417`). 246 table-form hooks cannot be checked this way. Both D4 scripts contain absolute paths.

**Steps.**
1. Add `qa/patchday/hook_targets.py` from `B2_hook_targets.py` (it supersedes the D4 one: same check, full parent chain). Arguments: `--decompile <root>`, `--mods <dir>...` (default: every `Dir` in `tools/mod-inventory.psd1`), `--allow qa/patchday/hook_allowlist.txt`. Exit 2 on any unresolved target not in the allowlist. Create the allowlist with the 4 entries above, one `Class.method` per line with a reason comment.
2. Add `qa/patchday/icon_atlas.py`, a Python port of `D4_icon_atlas_check.sh` over all mods, same arguments, allowlist `qa/patchday/icon_allowlist.txt`.
3. Add `qa/check_patch_day.ps1`: resolve the decompile root (`$env:VT2_DECOMPILE_ROOT`, else `../Vermintide-2-Source-Code`); print its `git rev-parse --short HEAD` and newest commit subject; run both scripts; run `qa/check_integration.ps1` if it exists; run the offline Lua suite; print one summary line per part; exit 2 if any part fails; exit 0 with `SKIP` when the decompile is absent.
4. Add a section "Game update procedure" to `docs/BUG_TRIAGE_RUNBOOK.md`: update the decompile checkout, run this command, fix every finding, then ship.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_patch_day.ps1` exits 0 on the current tree and prints `hook targets: 756 checked, 0 unresolved (4 allowlisted)` (numbers for 2026-11-13; the audited-tree count rises when stable trees are included).
- OFFLINE: a fixture test in the script (`--self-test`) plants `mod:hook("IngameUI", "not_in_modded", f)` in a temporary mod folder and requires exit 2.
- OFFLINE: `git grep -n 'C:\\\\Users' -- qa/patchday` returns 0 lines.
- Evidence class S.

**Guardrails.** Do not add this to the pre-commit hook or to hosted CI as a blocking step: the hosted runner has no decompile. Do not auto-edit mod code from the findings.

**Stop and escalate if.** The icon check reports missing icons on the current tree: do not allowlist them; list them (they may be live defects of the #1686 class) and hand them to the owning mod track.

---

### WP-T-05 Replace source-text pinning tests with behavioural ones

| Field | Value |
|---|---|
| Priority | P2 |
| Size | L (split by test-file prefix: ct 22, cos 9, wt 9, gut 9, gt 9, cwv 8, crt 5, cim 5, rest) |
| Agent | any |
| Depends on | none |
| Issues | none |
| Source | B2-F12, B2-F05 |
| Streams | tests only (`qa/lua/tests`) |

**Goal.** A test fails because behaviour changed, not because a line of source was reworded.

**Context.** 85 of 595 test files are source-text dominated: 30 execute no production code and 55 have at least half their cases made only of `source:find("literal", 1, true)`. Example: `qa/lua/tests/test_ct_mission_graph_sync.lua` asserts that named strings appear in the entry file in a given order; `qa/lua/tests/test_crt_ale_decay.lua` asserts a table row exists as text. 731 of 5,148 cases are pure text assertions. The list is `<audit>/scripts/B2_out/lua_tests_classified2.tsv` (column `cls` = `TEXT_ONLY...` or `EXEC+TEXT_DOMINANT...`, column `text_cases`).

**Steps.**
1. For each listed file, for each text-only case, pick one of three outcomes:
   a. The asserted code lives in a module that loads with `loadfile` and plain arguments: load it, call the function, assert the result or the recorded calls on a fake `mod`. Delete the text case.
   b. The assertion is "this wiring line exists in the entry file" and the entry cannot be loaded offline: move the needle to `qa/rt_textual_invariants.psd1` (one row, with `issueRef` and `note`) and delete the Lua case. One static home for text invariants.
   c. The assertion duplicates a behavioural case in the same file: delete it.
2. Keep case names stable where a case is rewritten, so history stays searchable.
3. After each file, run the suite.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0.
- OFFLINE: `py -3 qa/tools/lua_test_census.py --fail-over 20` exits 0, where the script is a port of `<audit>/scripts/B2_classify_lua_tests2.py` that counts text-dominated files and fails above the given number (baseline 85; target 20).
- OFFLINE: `pwsh -NoProfile -File qa/check_rt_textual_invariants.ps1` exits 0.
- Evidence class U for rewritten cases, S for moved needles.

**Guardrails.** Do not delete a case that is the only test naming an issue number (`git grep -n "#<N>" qa/lua/tests` before deleting). Do not edit production code to make it loadable in this card; if a small seam is needed, note it for the mod track.

**Stop and escalate if.** More than a third of a file's cases can only be kept as text: leave the file, record why in the card's log.

---

### WP-T-06 Make every gate scan tracked files only

| Field | Value |
|---|---|
| Priority | P1 |
| Size | M |
| Agent | any |
| Depends on | none |
| Issues | none open (same class as closed #1101 and #1176) |
| Source | B2-F06 |
| Streams | `qa/` only |

**Goal.** `qa/run_all.ps1 -Quick` passes in a checkout that contains git-ignored scratch copies of mod trees.

**Context.** On 2026-11-13 `pwsh -NoProfile -File qa/run_all.ps1 -Quick` exited 2 in the primary checkout. The only failure: `qa/check_native_resource_contracts.ps1` reported 10 "uncensused native boundary" rows under `.temp/public-promotion-20261105/`, a git-ignored folder (`.gitignore:32`). The script walks the disk (`Get-ChildItem -Recurse`, lines 163-170) and excludes only `_archive`, `bundleV2`, `_test_fixtures`, `.claude`. Other gates carry their own lists (`qa/check_cross_mod_deps.ps1`, `qa/check_cfg.ps1`, `qa/check_pusfume_compatibility.ps1` each exclude `.temp` by hand). The pre-commit hook runs Quick (`tools/hooks/pre-commit.ps1:205-213`), so commits from that checkout are blocked.

**Steps.**
1. Add a function `Get-QATrackedFiles -RepoRoot <path> [-Filter '*.lua']` to `qa/worktree_state.ps1` (already dot-sourced by `run_all.ps1`). It returns `git --no-optional-locks ls-files --cached --others --exclude-standard` output (tracked plus untracked-but-not-ignored), filtered by extension, as full paths.
2. Change `qa/check_native_resource_contracts.ps1` lines 85 and 163 to use it. Extend the script's existing self-test (it already builds a fake `.claude\worktrees` root near line 303) with a `.temp/x/mod/scripts/mods/mod/a.lua` copy that must not be scanned.
3. List every other gate that walks the repository root: `git grep -nE 'Get-ChildItem[^|]*-Recurse' -- 'qa/check_*.ps1'`. Convert each one that scans mod sources to the helper. Leave walks over a specific mod folder or over a temp fixture folder alone.
4. Add `qa/check_gate_enumeration.ps1`: fails if a `qa/check_*.ps1` file contains `Get-ChildItem` with `-Recurse` on `$repoRoot`/`$RepoRoot`/`$root` and does not call `Get-QATrackedFiles`, unless the line carries the comment `# enumeration-ok: <reason>`. Wire it into `run_all.ps1` Quick.

**Acceptance (machine, no human).**
- OFFLINE: copy any mod's `scripts` folder to `.temp/enum-test/<mod>/scripts` and run `pwsh -NoProfile -File qa/run_all.ps1 -Quick`; exit code 0 and the output ends with `[worktree-purity] OK`. Remove the copy afterwards.
- OFFLINE: `pwsh -NoProfile -File qa/check_native_resource_contracts.ps1 -SelfTest` exits 0 (use the script's actual self-test switch name).
- OFFLINE: `pwsh -NoProfile -File qa/check_gate_enumeration.ps1` exits 0.

**Guardrails.** Do not delete or move anything under `.temp/`: it belongs to other sessions. Do not change what a gate checks, only which files it reads.

**Stop and escalate if.** A gate needs ignored files on purpose (build output under `bundleV2`): keep its walk, add the `enumeration-ok` comment with the reason.

---

### WP-T-07 Scope run_all by changed path

| Field | Value |
|---|---|
| Priority | P2 |
| Size | M |
| Agent | strong (decides which gates may be skipped safely) |
| Depends on | WP-T-06; coordinate with track P (release pipeline, auditor B1) which owns the release gates |
| Issues | none |
| Source | B2-F06, B2-F09 |
| Streams | `qa/`, `tools/hooks/pre-commit.ps1` |

**Goal.** A commit that touches one mod runs the product gates and unit suites for that mod in under 90 seconds; release gates run only when release files change.

**Context.** Quick takes 439 s. About 196 s is the whole Lua unit suite, which runs on every commit (`qa/run_all.ps1:395`; `-SkipLua` at line 545 only skips luacheck). Of 107 gates, 70 (28,307 of 37,953 lines) check release, receipt, claim, tracker or provenance state, not mod code (classification in `docs/audits/2026-11-13_FORMAL_AUDIT/evidence/B2.md` section 2; script `<audit>/scripts/B2_classify_checks.py` holds the per-file map). `-Staged` already scopes a few checks to the index (#1683).

**Steps.**
1. Add `qa/gate_profiles.psd1`: for each `Run-Check` name in `run_all.ps1`, a `Profile` (`product`, `release`, `tracker`) and `Paths` (glob list that makes the gate relevant; `*` = always). Seed it from the audit classification: groups A and B = `product`; D and F = `release`; C and E = `tracker`.
2. In `run_all.ps1` add `-ChangedOnly` (uses `git diff --cached --name-only` with `-Staged`, else `git diff --name-only origin/master...HEAD`). With `-ChangedOnly`, a gate runs when its `Paths` match a changed file. `product` gates with `Paths='*'` always run. Print one line listing the skipped gates.
3. Lua unit suite: add `-Suites <prefix list>` to `qa/check_lua_unit_tests.ps1` that passes a filter to `qa/lua/run.lua`; under `-ChangedOnly` map changed mod folders to test prefixes (`weapon_tweaker*` -> `wt`, `chaos_wastes_tweaker*` -> `ct`, `general_tweaker*` -> `gt`, `gui_tweaker*` -> `gut`,`mod`, `crafting_in_modded*` -> `cim`, `cosmetics_tweaker` -> `cos`, `character_weapon_variants` -> `cwv`, `career_tweaker` -> `crt`, `enemy_tweaker` -> `et`, `event_tweaker` -> `event`, `modded_progression` -> `mp`,`modded`, `weapons_of_chaos` -> `woc`, `dynamic_cosmetic_portraits` -> `dcp`, `character_dialogue` -> `character`,`dialogue`; `tools/shared_lib` or `qa/lua` -> all). Every registered suite must still register (the manifest audit in `qa/lua/suite_manifest.lua` requires it); only skip running the case bodies of unselected suites.
4. Change the pre-commit hook call to `-Quick -SkipLua -Staged -ChangedOnly`. CI keeps the full run.

**Acceptance (machine, no human).**
- OFFLINE: stage a one-line comment change in `event_tweaker/scripts/mods/event_tweaker/_evt_regression.lua`, run `pwsh -NoProfile -File qa/run_all.ps1 -Quick -SkipLua -Staged -ChangedOnly`; exit 0, wall time under 90 s, output lists the skipped gates and shows only `event` suites executing case bodies. Unstage afterwards.
- OFFLINE: `pwsh -NoProfile -File qa/run_all.ps1 -Quick` (no `-ChangedOnly`) still runs every gate.
- OFFLINE: a self-test proves a change under `tools/ship/` selects the `release` gates.

**Guardrails.** CI must stay unscoped. Do not move or delete any release gate; track P decides their fate. Do not skip `check_lua_parse`, `check_published_ids`, `check_versions` or the duplicate-hook lint under any scope.

**Stop and escalate if.** Track P has already defined gate profiles: use theirs, do not create a second map.

---

### WP-T-08 One shared fake VMF, isolated cases, sharded runner

| Field | Value |
|---|---|
| Priority | P2 |
| Size | L (split: fake + 20 files; isolation fixes; sharding) |
| Agent | any |
| Depends on | WP-T-03 step 2 (same `fake_vmf.lua`; if T-03 is not done, create the file here) |
| Issues | none |
| Source | B2-F12, B2-F14 |
| Streams | `qa/lua` only; one production line in `weapon_tweaker` and `weapon_tweaker_dev` |

**Goal.** The offline suite passes in any case order, from any working directory, in under 60 seconds, with one VMF fake instead of 185.

**Context.** 185 test files define their own `mod:hook`/`get`/`dofile` fakes and 140 assign a fake `get_mod`. When cases were run without their siblings, 5 cases failed: `qa/lua/tests/test_gut_view_pending.lua:240`, `test_cos_attachment_spawn_sync.lua:328`, `test_cos_customization_view_lifecycle.lua:221` (two cases), `test_cos_equipment_assembly.lua:427`. The suite fails when started outside the repository root because `weapon_tweaker/scripts/mods/weapon_tweaker/wt_unlock_data.lua:34` falls back to a path relative to the working directory. The run is serial (3m16s).

**Steps.**
1. Put the shared fake at `qa/lua/support/fake_vmf.lua` (same file as `qa/integration/fake_vmf.lua` from WP-T-03; keep one copy and `require` it from both). API: `FakeVmf.new()` returns `{ get_mod, mods, hooks(mod_id), commands(mod_id), settings(mod_id) }`; a second `hook` on the same `(class, method)` for one mod is recorded as `dropped = true`, matching VMF.
2. In the four files above, give each case fresh state (build the fixture inside the case, or reset it in a local `setup()` called first). Confirm by running each file with its other cases disabled.
3. `wt_unlock_data.lua:34` (both wt trees): replace the relative `dofile` fallback with a loader passed by the test (`rawget(_G, "WT_TEST_LOADER")`), or have the tests supply `get_mod` through the shared fake and delete the fallback.
4. Add `--shard i/n` to `qa/lua/run.lua`: all suites register; case bodies whose ordinal modulo n differs from i are replaced by no-ops (prototype: `<audit>/scripts/B2_cov_probe2.lua`). `qa/check_lua_unit_tests.ps1` starts n = processor count (max 8) processes and fails if any fails. Add `--shuffle <seed>`.
5. Migrate test files to the shared fake in batches of 20, starting with files whose fake is a plain recorder. A file with special semantics may keep its own fake with a one-line comment why.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0 in under 60 s wall time.
- OFFLINE: from a different working directory, `& <repo>/qa/lua/vendor/lua-5.1.5-win64/lua5.1.exe <repo>/qa/lua/run.lua --suite-manifest <inventory> --shuffle 12345` reports 0 failures (inventory: the sorted list of `test_*.lua` base names, LF-terminated).
- OFFLINE: `git grep -lE '(_G\.get_mod|env\.get_mod|get_mod) *= *function' -- qa/lua/tests | wc -l` is 20 or less (baseline 140).

**Guardrails.** The fake records; it must not grow engine behaviour. Do not change production modules except the one line in step 3. Keep the suite-manifest audit intact.

**Stop and escalate if.** A case fails under shuffle for a reason other than shared state in its own file.

---

### WP-T-09 Record hooks at registration and check them in game

| Field | Value |
|---|---|
| Priority | P2 |
| Size | M per mod family; L overall |
| Agent | strong (touches how every hook is registered) |
| Depends on | WP-T-01 |
| Issues | none directly; gives VP authors a real "hook installed" assertion |
| Source | B2-F03 |
| Streams | dev trees first; stable trees at promotion |

**Goal.** Each mod's regression suite can state, from engine state, that every hook it registered has a live target and was installed, and how often each fired.

**Context.** No in-game check can see whether a hook is installed. `weapon_tweaker/scripts/mods/weapon_tweaker/_wt_runtime_checks.lua:36-48` says so in a comment and falls back to a local string. VMF silently drops a second hook on the same `(Class, method)` from one mod (repository `CLAUDE.md` rule 8). There are 1,064 hook sites in the audited trees; 756 are string-form literals.

**Steps.**
1. Add `tools/shared_lib/_lib_hook_census.lua`: `install(mod)` wraps `mod.hook`, `mod.hook_safe`, `mod.hook_origin` once. The wrapper records `{ kind, class_name or "<table>", method, fired = 0 }` in `mod._hook_census`, wraps the handler to increment `fired` (one integer add, no allocation), then calls the original VMF function with the wrapped handler. Offline test `qa/lua/tests/test_shared_hook_census.lua` with the shared fake: records, counts, passes all arguments and all return values through (use `select("#", ...)`), detects a duplicate pair.
2. In each mod entry file, call `install(mod)` before the first hook registration.
3. Register one check per mod through the runner: `hook_census_targets_live`: for every recorded string-form entry, `rawget(_G, class_name)` is a table and `type(class[method]) == "function"`; return the list of misses as the failure string; return `skip:` for classes that load later than the keep (state which). Register a second check `hook_census_no_duplicates`.
4. Expose `mod.hook_fire_counts()` returning the census so a rig script can assert "fired at least once after the action" with `T.expect`.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0 including `test_shared_hook_census`.
- OFFLINE: `tools/mod-lint/lint-mod.ps1` still exits 0 for every mod (the wrapper must not look like a duplicate hook).
- RIG: arena `keep`; `T.expect_rt("<mod>", "hook_census_targets_live")` and `T.expect_rt("<mod>", "hook_census_no_duplicates")` PASS for each loaded dev mod. Evidence class R.

**Guardrails.** The counting wrapper sits on hot paths (damage, update): no string building, no logging, no `pcall` added. Do not wrap hooks registered on `_G` functions differently from VMF's own handling. Roll out one mod at a time and run the rig boot between mods.

**Stop and escalate if.** Any rig boot shows a new `Lua Error` or a frame-time regression after a mod is converted: revert that mod and report. VMF's hook functions are not replaceable on the mod object in the retail sandbox: stop, record the error text.

---

### WP-T-10 Publish the in-game check census and verify cited check names

| Field | Value |
|---|---|
| Priority | P2 |
| Size | S |
| Agent | any |
| Depends on | WP-T-02 step 1 (`qa/tools/rt_check_census.py`) |
| Issues | none |
| Source | B2-F03, B2-F05, B2-F15 |
| Streams | `qa/`, docs |

**Goal.** Anyone writing a verification pack can look up whether a named in-game check tests behaviour, and no document cites a check that does not exist.

**Context.** Verification packs reuse in-mod checks through `T.expect_rt` and must say "whether each actually tests behaviour". Only 209 of 792 checks read engine-owned state. `weapon_tweaker/REGRESSION_CHECKLIST.md:223` and `weapon_tweaker/CHANGELOG.md:1020` cite a check `issue732_cwv_infantry_spear_saltzpyre_remap` that no Lua file registers. Closed bug #929 has no test that names it.

**Steps.**
1. Make `qa/tools/rt_check_census.py --write qa/runtime/rt_check_census.tsv` emit one row per check: `mod`, `stream`, `check`, `file`, `line`, `class` (`live`, `data`, `logic`, `exists`, `marker`), `issue` (number parsed from the name, or empty). Commit the file.
2. Add `qa/check_rt_check_census.ps1`: regenerates to a temp file and fails if it differs from the committed one (drift gate); then scans `*/REGRESSION_CHECKLIST.md`, `docs/REGRESSION_CHECKLIST.md`, `qa/runtime/**/*.lua` and `qa/runtime/plans/*.json` for check names (backticked tokens matching `issue[0-9]+_[a-z0-9_]+` and every `T.expect_rt("<mod>", "<name>")`), and fails on a name missing from the census. Wire into Quick.
3. Fix the #732 citation: either register the check in `weapon_tweaker` (and the dev mirror) or correct the two documents to the test that exists (`qa/lua/tests/test_wt_cwv_effective_template.lua`).

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_rt_check_census.ps1` exits 0.
- OFFLINE: `git grep -c 'issue732_cwv_infantry_spear_saltzpyre_remap'` shows either a registration in a `.lua` file or no remaining mention.
- Evidence class S.

**Guardrails.** Do not scan CHANGELOG files in the gate (history cites checks that were legitimately removed). Class labels are heuristic: a VP author may override a row by adding a `# census: live` comment on the registration line; the script honours it.

**Stop and escalate if.** The census differs between the dev and stable tree of a pair by more than names added in dev: list the differences for the mod track.

---

## Not turned into cards (out of scope or unproven)

- Whole-mod entry-file boot in the integration tier and full `NetworkLookup` construction: not proven by the experiment. Propose a follow-up only after WP-T-03 lands.
- Running behavioural suites against the stable trees at promotion (B2-F13): depends on the single-tree migration decision in track G.
- Deleting `tools/lint/regression-lint.ps1` (1,256 lines, referenced by nothing) and refreshing `tools/triage/triage-log.ps1` expected mods: S3 hygiene, fold into any card that touches those folders.
