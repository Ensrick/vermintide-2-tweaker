# Track WT: Weapon Tweaker (`wt`) and its dev mirror (`wt_dev`)

Source audit: `docs/audits/2026-11-13_FORMAL_AUDIT/evidence/A1.md` (auditor A1, 2026-11-13, repo `592253d1`, decompile `93dea911` = game 6.13.0). All defects below are static evidence; none was observed in the running game. `<repos>` is the folder that holds `vermintide-2-tweaker`, `Vermintide-2-Source-Code` and `Vermintide-Mod-Framework`.

## Family brief

1. `weapon_tweaker/` is the public beta mod `wt`: cross-career weapon availability (930 career/weapon toggles), 3P animation remapping for foreign weapons, mesh and grip substitutions, balance toggles. `weapon_tweaker_dev/` is the friends-only mod `wt_dev`: the same code plus dev tools.
2. Entry files: `weapon_tweaker/weapon_tweaker.mod`, then `weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker_localization.lua`, `weapon_tweaker_data.lua`, `weapon_tweaker.lua` (a 33-step `mod:dofile` manifest; order is load-bearing). Dev: `weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/weapon_tweaker_dev*.lua`; all other file names are the same in both trees.
3. Mirror rule: make the change in `weapon_tweaker/` first, then make the identical change in the same file under `weapon_tweaker_dev/`. Allowed differences only: `get_mod("wt_dev")`, module paths `scripts/mods/weapon_tweaker_dev/`, the three entry file names, `local MOD_VERSION`. Dev-only code must sit between `-- WT_DEV_OVERLAY_BEGIN:<id>` and `-- WT_DEV_OVERLAY_END:<id>`. Never edit inside an overlay block unless the card says so. New `_wt_*.lua` files are copied to both trees and are bundled automatically (wildcard in `resource_packages/*/*.package`).
4. Gate for the mirror: `pwsh -NoProfile -File qa/check_wt_stream_parity.ps1` must print `[check_wt_stream_parity] OK`. It also requires the dev version in `weapon_tweaker_dev/itemV2.cfg` to be exactly one patch above the public one. Version bumps, CHANGELOG and publication are not part of these cards: follow `PROJECT_STANDARDS.md` section 6.6.
5. Host tests: `qa/lua/tests/test_wt_<name>.lua`, shape `return function(H, repo_root) ... end` with `H.test`, `H.test_if`, `H.equal`, `H.deep_equal`, `H.truthy`. Every new test name must be added to the `suites` list in `qa/lua/run.lua`. Run all: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1`. The host is PUC Lua 5.1 (no `goto`, `xpcall` takes no extra arguments); the game is LuaJIT.
6. Rig scripts for cards without an issue number are named `qa/runtime/wt/wp_wt_<NN>_<slug>.lua`.
7. Trap 1, VMF lifecycle: a mod disabled in the VMF options still loads its script and still receives `update` and `on_game_state_changed`; only its hooks are off (`<repos>/Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/toggling.lua:9-52`, `core/events.lua:44-67`). `mod:is_enabled()` is nil while the script is loading.
8. Trap 2, loading: `mod:dofile` is not a singleton. Load each module once, from the place the card names, and share values through `mod._wt`. Do not reorder the manifest.
9. Trap 3, hooks: one hook per `(Class, method)` per mod. VMF drops a second registration. Grep before adding; merge into the existing handler. Hook wrappers must keep every return value, including nil holes (`select("#", ...)` plus `unpack(t, 1, n)`).
10. Trap 4, size ratchet: `qa/check_file_sizes.ps1` fails if a frozen file grows. Frozen in both trees: `_wt_runtime_checks.lua`, `_wt_anim_remap_data.lua`, `weapon_tweaker_data.lua` / `weapon_tweaker_dev_data.lua`. The dev entry file is about 110 lines below the 1500-line limit. Put new code in new files.
11. Trap 5, engine rules: never write a 1P field (`anim_event`, `wield_anim`, `state_machine`); never change a shared weapon template for all careers when a career-scoped table exists; `Unit.node` on a missing node kills the game even inside `pcall` (use `Unit.has_node`); `ItemMasterList` and `NetworkLookup` raise on unknown keys (use `rawget`); never add, rename or reorder a `NetworkLookup` registration (it changes the peer catalog and silently turns off features in co-op).
12. Many existing host tests assert source text (for example the order of `dofile` lines). Moving code can break them; update the assertion, never delete the test.

Card order is priority order. Dependencies are stated per card.

---

### WP-WT-01 Restore native weapons on disable and stay inert while disabled

| Field | Value |
|---|---|
| Priority | P0 (static evidence: players lose their own weapons after disabling; unlocks stay active while crash guards are off) |
| Size | M |
| Agent | any |
| Depends on | none |
| Issues | none (removes noise from every availability report, for example #183, #138, #948) |
| Source | A1-F01 |
| Streams | both (parity gate) |

**Goal.** Disabling `wt` in the VMF options leaves every hero able to wield its own weapons, nothing is re-applied while the mod is disabled, and enabling it again re-applies the saved settings.

**Context.** VMF calls `on_disabled` and turns hooks off, but keeps calling `update` and `on_game_state_changed` (family brief, trap 1). `clear_weapon_unlocks` (`weapon_tweaker/scripts/mods/weapon_tweaker/_wt_availability.lua:379-394`) removes the career from `can_wield` for every pair of `weapon_unlock_map`. 260 of the 930 pairs are native, for example `dr_ranger` on `dr_1h_axe` (vanilla list: `Vermintide-2-Source-Code/scripts/settings/equipment/item_master_list_exported.lua:7273-7277`). So a disable strips native careers. Then the next state change runs `apply_weapon_unlocks` and all balance appliers again (`weapon_tweaker.lua:927-986`) although all hooks, including the node crash guard, are off. Nothing in the mod reads `mod:is_enabled()` except `_wt_fire_sword_owner.lua:29`. There is no `mod.on_enabled`.

**Steps.**
1. Add `qa/lua/tests/test_wt_lifecycle_disable.lua` and list it in `qa/lua/run.lua`. For both trees, load `_wt_availability.lua` with `loadfile` + `setfenv` (pattern: `qa/lua/tests/test_wt_runtime_checks_module.lua:154-158`). Environment: `get_mod(name)` returns the stub mod for `"wt"` / `"wt_dev"` and nil otherwise; `ItemMasterList = { dr_1h_axe = { can_wield = { "dr_ironbreaker", "dr_slayer", "dr_ranger" } }, es_1h_sword = { can_wield = { "es_mercenary", "es_huntsman", "es_knight" } }, wh_crossbow = { can_wield = { "wh_captain", "wh_bountyhunter", "wh_zealot", "xx_other_mod" } } }`. Stub mod: `_wt = { weapon_unlock_map = { dr_ranger = { "dr_1h_axe", "es_1h_sword" }, es_mercenary = { "wh_crossbow" } }, cwv_conditional_managed = {} }`, `get(self, id)` reading a `settings` table, no-op `set`, `info`, `error`, and `dofile(self, path)` that loads `<tree>/<path>.lua` through the same environment helper.
2. In that test assert, with all three `unlock_<career>_<weapon>` settings true: after `mod._wt.apply_weapon_unlocks()` the cross careers are present; after `mod._wt.clear_weapon_unlocks()`: `dr_ranger` is in `dr_1h_axe.can_wield` (fails today), `dr_ranger` is not in `es_1h_sword.can_wield`, `es_mercenary` is not in `wh_crossbow.can_wield`, `xx_other_mod` is still in `wh_crossbow.can_wield`, no list has duplicates. Second case: with `unlock_dr_ranger_dr_1h_axe = false`, apply removes `dr_ranger` (intended while enabled) and clear puts it back. Run the suite and confirm the new test fails for the native assertions.
3. Fix `clear_weapon_unlocks` in `_wt_availability.lua`: replace the inner strip loop with `_set_career(item, career, WT.is_native_weapon(career, weapon_key))`. `_set_career` is defined at `:130-137`; `WT.is_native_weapon` is set at `:45` from `_wt_native_weapon_ownership.lua` (a static catalog of vanilla ownership). Correct the comment at `:373-378`.
4. In `weapon_tweaker.lua`, after `mod._wt.MOD_VERSION = MOD_VERSION` (`:263`), add `mod._wt.is_active = function() return mod:is_enabled() == true end`.
5. In `weapon_tweaker.lua`, move the block that starts at `mod:info("Weapon Tweaker: Baseline Active")` and ends at `mod._force_load_necromancer_fx_package()` (inside `mod.on_game_state_changed`, `:938-959`) into `local function _wt_apply_all()` defined directly above `mod.on_game_state_changed`. In the handler keep the heap-probe lines, then add `if not mod._wt.is_active() then return end`, then call `_wt_apply_all()`. Keep the loadout dump and the remaining probe lines after it.
6. In `weapon_tweaker.lua`, directly after `mod._wt.rework_master_runtime = _wt_rework_runtime` (`:1012`) add:
   `mod.on_enabled = function(initial_call) if initial_call then return end; _wt_master_toggles.seed(mod); _wt_rework_runtime:sync(); _wt_apply_all() end` (write it on several lines). It must be defined before the `_wt_fire_sword_owner` install line (`:1040`), because that owner wraps `on_enabled` and resets its own disabled flag (`_wt_fire_sword_owner.lua:268-279`).
7. In `weapon_tweaker_backend.lua`, inside `mod.update` (`:595`), directly after `if prev_update then pcall(prev_update, dt) end`, add `if not mod._wt.is_active() then return end`.
8. In `_wt_settings_runtime.lua`, make the first statement of `mod.on_setting_changed` and of `mod.on_settings_batch_changed`: `if c.is_active and not c.is_active() then return end`. In `weapon_tweaker.lua` pass `is_active = mod._wt.is_active` in the table given to `_wt_settings_runtime` `.install` (`:1014-1026`).
9. If an existing host test now fails because its stub `mod._wt` has no `is_active`, add `is_active = function() return true end` to that stub. Do not weaken the production lines.
10. Mirror steps 3 to 8 into `weapon_tweaker_dev/` (entry file `weapon_tweaker_dev.lua`).

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0 with `test_wt_lifecycle_disable` passing for both trees. `pwsh -NoProfile -File qa/check_wt_stream_parity.ps1` prints OK. `pwsh -NoProfile -File qa/check_file_sizes.ps1 -Quiet` does not exit 2.
- RIG: add `qa/runtime/wt/wp_wt_01_disable_restore.lua`, arena `keep`, mod `wt` enabled. Steps: (a) `local wt = get_mod("wt")`; for every `career, row` in `wt._wt.native_weapon_ownership` and every `weapon, is_native` in `row` with `is_native == true` and `wt:get("unlock_" .. career .. "_" .. weapon) == true`: `T.expect` that `career` is in `rawget(ItemMasterList, weapon).can_wield`. (b) `T.set("wt", "unlock_es_mercenary_wh_crossbow", true)`, call `wt.on_setting_changed("unlock_es_mercenary_wh_crossbow")`, expect `es_mercenary` in `ItemMasterList.wh_crossbow.can_wield`. (c) `get_mod("VMF").mod_state_changed("wt", false)` (`<repos>/Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/toggling.lua:55-66`), `T.frames(3)`. Expect every native pair of (a) present regardless of its setting, and `es_mercenary` absent from `wh_crossbow`. (d) Call `wt.on_game_state_changed("enter", "StateIngame")`, `T.frames(3)`, repeat the assertions of (c). (e) `mod_state_changed("wt", true)`, `T.frames(3)`, expect `es_mercenary` present again. All assertions must PASS.
- Evidence class: R. No issue is closed by this card.

**Guardrails.** Do not snapshot live `can_wield` as the vanilla baseline: a mod reload keeps mutated tables. Do not gate the `prev_update` chain: the peer parity beacon must keep ticking. Do not call `mod.on_game_state_changed` from `on_enabled`: the Flame Sword wrapper would mark itself suspended. Do not try to revert template edits here (WP-WT-07). A native toggle set to off while the mod is enabled must still remove the native career: that is the product's design.

**Stop and escalate if.** The rig reports a native pair missing after disable although `_wt_native_weapon_ownership.lua` lists it, or present although it does not. That means the static catalog (verified by its header only through game 6.11.3) no longer matches the game. Record the pairs; do not edit the catalog by guess. Decision D-WT-01 covers the wider question of full vanilla restore.

### WP-WT-02 Add a scriptable regression runner with printf evidence

| Field | Value |
|---|---|
| Priority | P1 |
| Size | S |
| Agent | any |
| Depends on | none |
| Issues | none (gives every WT issue a machine-readable check channel) |
| Source | A1-F11 |
| Streams | both (parity gate) |

**Goal.** The 77 in-mod checks can be run by a function call that returns a table and prints one engine `printf` line per check, while `/wt_regression_test` keeps its exact chat output.

**Context.** `weapon_tweaker/scripts/mods/weapon_tweaker/_wt_regression.lua:24-49` keeps the check list `_RT_CHECKS` file-local. The only runner is the chat-command closure, and it reports through `mod:echo`, `mod:info` and `mod:warning`. With mod logging off (the owner's setup, repo `CLAUDE.md` rule 9) nothing reaches the console log. The rig sweep runs the chat command and captures echo text, so that text must not change. One check is a tautology: `husk_extension_hooked` (`_wt_runtime_checks.lua:36-48`) passes whenever the class exists and then tests the length of a string literal.

**Steps.**
1. Add `qa/lua/tests/test_wt_regression_runner.lua` and list it in `qa/lua/run.lua`. For both trees load `_wt_regression.lua` with `loadfile` + `setfenv` (pattern: `qa/lua/tests/test_wt_runtime_checks_module.lua:154-158`). Environment: `get_mod` returns a stub mod with `_wt = { MOD_VERSION = "0.0.0-test" }`, `get_name` returning `"wt"`, `command(self, name, text, fn)` storing `fn`, and `echo` / `info` / `warning` that append `string.format(...)` to a list; `printf` appends `string.format(...)` to a second list.
2. In the test register four checks through `mod._wt.rt_register`: `a_pass` returns nil; `b_fail` returns `"boom"`; `c_skip` returns `"skip: no engine"`; `d_raise` calls `error("kaput")`. Assert: `mod._wt.run_regression` is a function; it returns four rows in registration order with fields `name`, `result` (`"PASS"`, `"FAIL"`, `"SKIP"`, `"FAIL"`) and `detail`; the `printf` list is exactly `[wt:RT] check=a_pass result=PASS`, `[wt:RT] check=b_fail result=FAIL detail=boom`, `[wt:RT] check=c_skip result=SKIP detail=skip: no engine`, a line starting with `[wt:RT] check=d_raise result=FAIL detail=`, and `[wt:RT] summary pass=1 fail=2 skip=1 total=4 version=0.0.0-test`. Then call the stored command function and assert the echo list contains, in order, `=== wt regression_test (v0.0.0-test) ===`, `  PASS: a_pass`, `  FAIL: b_fail -- boom`, `  SKIP: c_skip -- skip: no engine`, and `=== 1 passed, 2 failed, 1 skipped ===`. Run the suite: the test fails because `run_regression` does not exist.
3. In `_wt_regression.lua` add `local function _run()`: loop `_RT_CHECKS`, classify exactly like the existing loop (`:32-47`: `pcall`; nil result = PASS; a string starting with `skip:` = SKIP; anything else or a raise = FAIL), build the rows, and for each row call `pcall(printf, ...)` with the line format of step 2. Replace line breaks in `detail` with a space. Build the tag as `"[" .. tostring(mod:get_name()) .. ":RT]"`. Return `rows, pass, fail, skip`. Set `WT.run_regression = _run`. Rewrite the command body to call `_run()` once and produce the same `mod:echo`, `mod:info` and `mod:warning` lines as today from the rows.
4. In `_wt_runtime_checks.lua` replace lines `:43-47` of the `husk_extension_hooked` body (the comment about the VMF hook table and the two `_MARKER` lines) with the single line `return "skip: hook presence is not readable from Lua; husk remap needs two clients"`. The file is frozen by the size ratchet: the edit must not add lines.
5. Mirror steps 3 and 4 into `weapon_tweaker_dev/`.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0 with the new suite passing for both trees; `qa/check_wt_stream_parity.ps1` prints OK; `qa/check_file_sizes.ps1 -Quiet` does not exit 2.
- RIG: add `qa/runtime/wt/wp_wt_02_regression_runner.lua`, arena `keep`: `local rows = get_mod("wt")._wt.run_regression()`; `T.expect(#rows >= 70, "suite size")`; for every row with `result == "FAIL"` call `T.note(row.name, row.detail)`; `T.expect_eq(<number of FAIL rows>, 0, "no failing in-mod check")`. Case field `host_expect_log = { "[wt:RT] summary" }`.
- Evidence class: R for "the in-mod suite ran clean on this build". No issue is closed by this card.

**Guardrails.** Do not change the echo text, the check order, or any check body other than the one in step 4. Do not add a chat command: the parity gate has a fixed list of 12 public commands (`qa/check_wt_stream_parity.ps1:28-41`). Do not add lines to `_wt_runtime_checks.lua`.

**Stop and escalate if.** `tools/harness/` already parses a different per-check log line for other mods (grep `expect_rt` and `:RT]` under `tools/harness` and `qa/runtime`): use that format instead and say so. If the rig run shows FAIL rows, do not edit checks to make them pass: list name and detail for triage.

### WP-WT-03 Disable public `wt` when `wt_dev` is also enabled

| Field | Value |
|---|---|
| Priority | P1 |
| Size | M |
| Agent | strong (VMF re-entrancy: a mod must not disable itself inside its own lifecycle callback) |
| Depends on | WP-WT-01 |
| Issues | none (protects tester evidence for all WT issues) |
| Source | A1-F01, A1-F17 |
| Streams | both (parity gate) |

**Goal.** When both streams are enabled, public `wt` is disabled through VMF within one second, with one chat line and one `printf` line, and `wt_dev` runs alone.

**Context.** Both streams hook the same engine methods and both rewrite `ItemMasterList[*].can_wield` from their own settings on every state change (`_wt_availability.lua:176-225`). VMF calls the mods in `pairs` order (`<repos>/Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/events.lua:62-67`), so the result is not deterministic. Neither tree checks for the other (no `get_mod("wt")` in the dev tree). After WP-WT-01 a disabled stream is inert, so it is enough to guarantee that at most one stream is enabled. `get_mod("VMF").mod_state_changed(name, false)` disables a mod properly (`core/toggling.lua:55-66`). `set_mod_state` writes the saved enabled list after it called `on_enabled` (`core/toggling.lua:9-35`), so a disable issued from inside `on_enabled` would be overwritten.

**Steps.**
1. Add `qa/lua/tests/test_wt_sibling_guard.lua` (list it in `qa/lua/run.lua`). It loads `_wt_sibling_guard.lua` from both trees with plain `dofile` and asserts: `M.sibling_id("wt") == "wt_dev"`; `M.sibling_id("wt_dev") == "wt"`; `M.public_must_yield("wt", true, { is_enabled = function() return true end })` is true; false when the sibling is nil, when the sibling's `is_enabled` returns false or raises, when the second argument is false, and always false for `"wt_dev"`. For `M.tick(mod, dt, get_mod_fn, print_fn)`: with a stub public mod and an enabled stub sibling, 0.5 s of ticks do nothing; at 1.0 s it calls `print_fn` once, `mod:echo` once, and `get_mod_fn("VMF").mod_state_changed("wt", false)` once, and returns true; for a stub `wt_dev` mod it never calls `mod_state_changed`.
2. Create `weapon_tweaker/scripts/mods/weapon_tweaker/_wt_sibling_guard.lua` as a pure module (no globals read at load) with the three functions of step 1. `tick` accumulates `dt` in a module-local and evaluates at most once per second: `self_id = mod:get_name()`, `sibling = get_mod_fn(M.sibling_id(self_id))`, and if `M.public_must_yield(self_id, mod:is_enabled() == true, sibling)` then print `[wt:SIBLING] wt and wt_dev are both enabled; disabling public wt`, echo `Weapon Tweaker (dev) is enabled. The public Weapon Tweaker was turned off to avoid conflicts.`, call `get_mod_fn("VMF").mod_state_changed(self_id, false)` and return true.
3. In `weapon_tweaker_backend.lua` inside `M.install`, load the guard once: `local sibling_guard = mod:dofile("scripts/mods/weapon_tweaker/_wt_sibling_guard")`. In `mod.update`, directly after the `is_active` line added by WP-WT-01, add `if sibling_guard.tick(mod, dt, get_mod, function(line) pcall(printf, "%s", line) end) then return end`.
4. Copy the new file to `weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/` unchanged and mirror step 3 (path `scripts/mods/weapon_tweaker_dev/_wt_sibling_guard`).

**Acceptance (machine, no human).**
- OFFLINE: the unit-test gate exits 0 with the new suite; the parity gate prints OK; `git grep -n 'get_mod("wt_dev")' -- weapon_tweaker/` returns nothing.
- RIG: add `qa/runtime/wt/wp_wt_03_sibling_exclusion.lua`, arena `keep`, plan loads both `wt` and `wt_dev` enabled in the isolated profile. `T.wait(3)`; `T.expect_eq(get_mod("wt"):is_enabled(), false, "public yielded")`; `T.expect_eq(get_mod("wt_dev"):is_enabled(), true, "dev active")`; for the pairs `es_mercenary/wh_crossbow`, `wh_captain/es_2h_hammer`, `we_waywatcher/es_1h_mace`: `T.expect_eq(<career in ItemMasterList[weapon].can_wield>, get_mod("wt_dev"):get("unlock_" .. career .. "_" .. weapon) == true, ...)`. Case field `host_expect_log = { "[wt:SIBLING]" }`.
- Evidence class: R. No issue is closed by this card.

**Guardrails.** Call `mod_state_changed` only from `update`, never from `on_enabled`, `on_disabled` or `on_all_mods_loaded`. `wt_dev` never yields. Do not write the literal `get_mod("wt_dev")` in shared code: the parity gate rewrites that exact text in the dev tree, so the two files would differ. Derive the id from `mod:get_name()`. The bare string `"wt_dev"` is allowed in the public tree; the gate forbids only the dev tool identifiers listed at `qa/check_wt_stream_parity.ps1:144-151`.

**Stop and escalate if.** `get_mod("VMF").mod_state_changed` is nil in the rig run. Or the owner decision D-WT-02 (which stream yields) is answered differently from the default used here.

### WP-WT-04 Pin the 3P animation funnel with a golden host test

| Field | Value |
|---|---|
| Priority | P1 |
| Size | M |
| Agent | any |
| Depends on | none |
| Issues | advances #112, #290, #946, #748 (no closure: this card only pins current behaviour) |
| Source | A1-F02, A1-F11 |
| Streams | both for the four export lines; the test loads the public tree |

**Goal.** A host test executes the real `Unit.animation_event` hook body of `wt` under stubs and fails when any redirect or remap decision changes.

**Context.** The hook at `weapon_tweaker/scripts/mods/weapon_tweaker/_wt_anim_remap.lua:610-946` is the core of the mod. It decides in seven ordered steps (reload route, flail block, per-unit `state.remap`, force-fire block, `_career_anim_redirect`, `_anim_redirect`, `_suffix_career_map`). No test runs it; existing tests only read the tables or grep the file. The per-unit state is filled by the wield hooks (`:980`, `:1051`) through `_populate_unit_state_from_wield` (`:950-966`). The module reads its inputs from `mod._wt` at load (`:36-49`) and registers its hooks with `mod:hook`, `mod:traced_hook`, `mod:safe_hook`. Every later refactor of this code (WP-WT-06, WP-WT-10, WP-WT-11) needs this test first.

**Steps.**
1. In `_wt_anim_remap.lua`, in the export block (`:1063-1069`), add four lines: `WT.anim_redirect = _anim_redirect`, `WT.career_anim_redirect = _career_anim_redirect`, `WT.three_p_key_remaps = _3p_key_remaps`, `WT.three_p_remap_triggers = _3p_remap_triggers`. Mirror into the dev tree. No behaviour changes.
2. Create the shared loader `qa/lua/fixtures/wt_anim_funnel_env.lua`. It returns `function(repo_root, has_event)` that: builds a stub mod with `_wt = { feature_enabled = function() return true end, local_career_name = function() return nil end, dbg = function() end, MOD_VERSION = "test", weapon_unlock_map = {} }`; gives the mod `dofile(self, path)` that loads `repo_root .. "/weapon_tweaker/" .. path .. ".lua"` with `loadfile` + `setfenv` in the same environment; sets `mod._wt.build_3p_template_remaps` to the value returned by `scripts/mods/weapon_tweaker/_wt_anim_remap_data` (the entry does this at `weapon_tweaker.lua:412`); captures the handler passed to `mod:hook("Unit", "animation_event", fn)` and the handler passed to `mod:safe_hook("SimpleHuskInventoryExtension", "wield", fn)`; accepts and ignores `mod:traced_hook`, `mod:command`, `mod:echo`, `mod:info`. Environment globals: `get_mod(name)` returns the stub only for `"wt"`; `Unit = { has_animation_event = function(unit, event) return has_event(unit, event) end }`; `ScriptUnit = { has_extension = function(unit, system) if system == "career_system" and unit.career then return { _career_name = unit.career } end end }`; `Managers = { player = { local_player = function() return nil end, owner = function() return nil end } }`. The loader returns `{ mod = mod, anim = <animation hook>, husk_wield = <husk wield hook> }`.
3. Add `qa/lua/tests/test_wt_anim_funnel_golden.lua` (list it in `qa/lua/run.lua`). Matrix:
   - careers: `es_mercenary`, `dr_ranger`, `dr_slayer`, `we_waywatcher`, `wh_captain`, `wh_priest`, `bw_adept`;
   - policies: `all` (`has_event` always true) and `none` (always false), one loader instance per policy;
   - subjects: one per key `t` of `mod._wt.three_p_template_remaps` (`template = t`, `key = "wt_probe_key"`); one per key `k` of `mod._wt.three_p_key_remaps` plus `es_1h_flail` and `bw_1h_flail_flaming` (`template = "wt_probe_template"`, `key = k`); one neutral subject (`wt_probe_template`, `wt_probe_key`);
   - wield event: for a template subject, `wield_patches.patches[t][career] or wield_patches.bulk[t][career] or "to_wt_probe"` (from `dofile` of `wt_wield_patches.lua`); for key subjects `"to_wt_probe"`; for the neutral subject run once per key of `mod._wt.career_anim_redirect` and once with `"to_wt_probe"`;
   - events: for a template or key subject, the sorted keys of every remap table of that subject plus `attack_swing_left`, `attack_swing_right`, `attack_swing_heavy_left`, `attack_swing_stab_02`, `attack_swing_heavy_stab`; for the neutral subject, the sorted union of the keys of `anim_redirect`, the keys of `career_anim_redirect`, `"probe" .. suffix` for every key of `mod._wt.suffix_career_map`, plus `reload` and `idle`.
4. For each (policy, career, subject, wield): create `unit = { career = career }`; call `husk_wield(function() end, { _unit = unit, _equipment = { slots = { slot_melee = { item_data = { key = key, template = template } } } } }, "slot_melee")`; call `anim(rec, unit, wield)` and then `anim(rec, unit, event)` for each event in order, where `rec(u, e)` appends `e` to a per-call list. Build one output line per (policy, career, subject, wield): `policy|career|template|key|wield|@wield>d;e1>d1;e2>d2,d2b;...` listing only calls whose delivered list differs from the single source event (write an empty right side when nothing was delivered). Sort the lines.
5. Compare the joined text with `qa/lua/tests/fixtures/wt_anim_funnel_golden.txt` (normalise line endings). On mismatch fail with the first differing line. When the environment variable `WT_ANIM_GOLDEN_OUT` is set, also write the fresh text to that path. Generate the golden once this way, copy it into the fixture path, and commit it.

**Acceptance (machine, no human).**
- OFFLINE: the unit-test gate exits 0 with `test_wt_anim_funnel_golden`. Self-check, not committed: change one value in `_3p_remap_spear_to_polearm` (`_wt_anim_remap.lua:296-299`) and confirm the gate fails, then revert. The parity gate prints OK.
- RIG: none. This card is class U infrastructure.
- No issue is closed by this card.

**Guardrails.** Do not change any table value or any branch of the hook. Do not add a hook. The `#536` reload router is not loaded by this harness (`WT.reload_3p_route` is nil); that is expected, say so in a test comment. Keep the golden under 3,000 lines; the line format above is chosen for that.

**Stop and escalate if.** The module cannot be loaded under stubs without editing production code beyond step 1. Report which global or `mod._wt` field is missing instead of adding a production fallback.

### WP-WT-05 Compute animation coverage and check target events in the rig

| Field | Value |
|---|---|
| Priority | P1 |
| Size | L (three sessions: fixture generator; host test; rig scripts) |
| Agent | any |
| Depends on | WP-WT-04 (loader), WP-WT-02 for the rig part |
| Issues | advances #290, #946, #748, #948, #112. Class R closes only the claim "the target event exists on the receiver body"; how it looks stays class V |
| Source | A1-F02, A1-F05, A1-F11 |
| Streams | none for mod code (test and rig files only) |

**Goal.** For every cross-career pair the repo states, by computation, which fired 3P events have no valid target on the receiver, and the rig proves on the real skeletons that every configured target event exists.

**Context.** `wt` routes 670 cross-career pairs. The only status record is a hand-kept ledger in the dev tree, and it marks every row `untested` (`qa/lua/tests/test_wt_kruber_coverage.lua:19-24`). Two partial vocabulary fixtures already exist for the dev picker: `qa/lua/tests/fixtures/wt_picker_target_3p_vocab.lua` (25 templates) and `wt_picker_template_anim_events.lua` (17 templates). Their headers describe how they were generated: execute each decompiled weapon template file under Lua 5.1 with stubbed engine globals and collect `actions.<action>.<sub_action>.(anim_event_3p or anim_event)`. The engine fires exactly that value on the 3P body (`Vermintide-2-Source-Code/scripts/unit_extensions/weapons/weapon_unit_extension.lua:510-512, 652`). Template files return `{ <template_name> = weapon_template }` (example: last lines of `scripts/settings/equipment/weapon_templates/2h_billhooks.lua`).

**Steps.**
1. Write the generator `qa/lua/fixtures/gen_wt_anim_vocab.lua`, run by hand with the vendored interpreter: `qa/lua/vendor/lua-5.1.5-win64/lua5.1.exe qa/lua/fixtures/gen_wt_anim_vocab.lua <decompile root> <output path>`. It executes every file in `<decompile root>/scripts/settings/equipment/weapon_templates/` under a permissive stub environment and, for every returned template, records `wield = wield_anim`, and `events` = the set of `anim_event_3p or anim_event` of every top-level sub-action plus `wield_anim`, `wield_anim_3p`, `wield_anim_no_ammo`, `wield_anim_not_loaded` and every value of `wield_anim_career` / `wield_anim_career_3p`. It also reads `ItemMasterList.<key> = { ... template = "<name>" ... }` rows as text from `scripts/settings/equipment/item_master_list_exported.lua` and `scripts/settings/dlcs/*/item_master_list_*.lua` into `item_template[key] = name`. Output: `qa/lua/tests/fixtures/wt_anim_vocab.lua` returning `{ source = "<decompile commit>", templates = {...}, item_template = {...} }`. Commit the fixture.
2. Add `qa/lua/tests/test_wt_anim_coverage.lua` (list it in `qa/lua/run.lua`). Inputs: the fixture, `wt_unlock_data.lua`, `_wt_native_weapon_ownership.lua`, `wt_wield_patches.lua`, and the WP-WT-04 loader. Receiver groups: `es_` (4 careers), `dr_` (4), `we_` (4), `wh_captain` / `wh_bountyhunter` / `wh_zealot`, `wh_priest`, `bw_` (4). Native vocabulary `V(group)` = union of `templates[item_template[w]].events` over the weapons `w` that `_wt_native_weapon_ownership.lua` lists for the group's careers.
3. For every non-native pair `(career, weapon)` of `weapon_unlock_map`, with `t = item_template[weapon]`: load the funnel with `has_event(unit, e) = V(group)[e] == true`; wield with template `t`; fire `wield_patches.patches[t][career] or wield_patches.bulk[t][career] or templates[t].wield`; then fire every event of `templates[t].events`. Report a row `group|weapon|event|delivered` for every call whose delivered event is not in `V(group)` (or delivered nothing).
4. Compare the sorted rows with the baseline `qa/lua/tests/fixtures/wt_anim_coverage_baseline.txt`. The test fails when a row appears that is not in the baseline and when a baseline row no longer occurs. Create the baseline from the first run. Its line count is the computed replacement for the hand-kept "needs animations" numbers.
5. Rig, one script per hero (`kruber`, `bardin`, `kerillian`, `saltzpyre`, `sienna`): `qa/runtime/wt/issue_948_anim_targets_<hero>.lua`, arena `keep`, the case switches the local hero to a career of that hero first. Then `local u = T.local_hero()`, `local career = T.ext(u, "career_system"):career_name()`. For every template `name, tpl` in `Weapons` with `tpl.wield_anim_career_3p and tpl.wield_anim_career_3p[career]`: `T.expect(Unit.has_animation_event(u, tpl.wield_anim_career_3p[career]), name .. "|wield")`. For every key `name` of `get_mod("wt")._wt.three_p_template_remaps`: pick the remap table the mod would select for this career (the entry whose prefix matches the career name, else `_default`; skip `false`) and for each target value `T.expect(Unit.has_animation_event(u, target), name .. "|" .. source .. ">" .. target)`.
6. Rig, one extra case `qa/runtime/wt/wp_wt_05_empty_repeater_1p.lua`, arena `keep`, hero Kruber Mercenary: enable `unlock_es_mercenary_we_crossbow_repeater`, equip and wield `we_crossbow_repeater`, then `T.expect(Unit.has_animation_event(<first person unit>, "to_repeating_handgun"), "1P authors the empty-wield event")`. If the rig has no equip helper yet, end the case with `T.require(false, "equip helper missing")`.

**Acceptance (machine, no human).**
- OFFLINE: the unit-test gate exits 0; the baseline file exists; `git grep -c "wt_anim_coverage_baseline" qa/lua/tests/test_wt_anim_coverage.lua` is at least 1.
- RIG: the five `issue_948_anim_targets_<hero>` cases PASS. A FAIL names template and event; record it in the baseline discussion, do not edit tables in this card.
- Evidence: class S for the computed list, class R for "target exists on the skeleton". Neither closes #290, #946, #748 or #948 alone: the visual result is class V. The cases supply the per-row facts those issues need.

**Guardrails.** `V(group)` is a proxy: it proves the hero's skeleton authors the event under some native weapon, not that it plays correctly in the chosen stance. Say this in the test header. Do not edit `wt_port_status.lua` or any remap table here. Vanilla uses `Unit.has_animation_event` as a plain existence test (`Vermintide-2-Source-Code/scripts/flow/flow_callbacks.lua:2978`); it does not need the weapon to be wielded.

**Stop and escalate if.** More than 10 template files cannot be executed under stubs: list them rather than hand-writing their events. Or the step 6 case FAILS: that confirms audit finding A1-F05 (the empty-wield override changes a 1P event, set at `_wt_cross_char_template_patches.lua:424-454`, consumed at `Vermintide-2-Source-Code/scripts/unit_extensions/default_player_unit/inventory/simple_inventory_extension.lua:2052, 2113`); record it under D-WT-06 and do not change the override.

### WP-WT-06 Extract the funnel decision into a pure resolver module

| Field | Value |
|---|---|
| Priority | P1 |
| Size | L (session A: move tables and helper functions; session B: move the decision body) |
| Agent | strong (three dev overlay blocks live inside the hook body and must keep working) |
| Depends on | WP-WT-04 |
| Issues | advances #112, #290, #946, #748 (structure only, no behaviour change) |
| Source | A1-F02 |
| Streams | both (parity gate) |

**Goal.** One pure function decides which 3P event is delivered for a fired event; the hook only builds the context and performs the call; the WP-WT-04 golden file is unchanged.

**Context.** Seven decision steps and their data are interleaved with logging, sampling counters and engine calls in one 336-line closure (`weapon_tweaker/scripts/mods/weapon_tweaker/_wt_anim_remap.lua:610-946`). Thirteen mechanisms in total touch 3P events, and nobody can state the result for a given (career, weapon, event) without running the game. The tables are file-locals of the same module: `_anim_redirect` (`:51`), `_career_anim_redirect` (`:70`), `_suffix_order` / `_suffix_career_map` (`:125-158`), the `_3p_remap_*` tables (`:271-348`), `_3p_remap_triggers` (`:352`), `_3p_key_remaps` (`:447`), with helpers `_safe_has_anim` (`:163`), `_try_suffix_redirect` (`:168`), `_resolve_preview_wield_event` (`:220`), `_resolve_3p_remap` (`:384`), `_resolve_template_remap` (`:434`), `_resolve_key_remap` (`:485`). In the dev tree the hook body contains three overlay blocks: `anim-picker-play-trace`, `animation-probe-outcomes`, `animation-probe-misses` (dev file lines 829-881, 1056-1069, 1072-1084).

**Steps.**
1. Session A. Create `_wt_anim_resolver.lua` (pure: no `get_mod`, no engine globals). Move the tables and helper functions named above into it as fields of the returned table `M`. Each helper that needs to know whether a unit authors an event takes a `has_event(name)` function argument instead of calling `Unit.has_animation_event`.
2. In `_wt_anim_remap.lua` load the resolver once, next to the existing `_wt_cwv_effective_template` load (`:46-47`): `local _resolver = mod:dofile("scripts/mods/weapon_tweaker/_wt_anim_resolver")`. Replace every moved definition with a local alias of the same name (`local _anim_redirect = _resolver.anim_redirect`, and so on) so that `/info`, the `_wt_anim_remap_data` builder call (`:429-433`), the exports and the dev overlay code compile unchanged. Run the unit-test gate: the golden must pass untouched.
3. Add `qa/lua/tests/test_wt_anim_resolver.lua` (list it in `qa/lua/run.lua`) with table-driven cases against the resolver alone, at least: `to_spear` for `wh_captain` gives `to_2h_billhook` when authored; `to_2h_billhook` for `wh_captain` is not redirected; `to_longbow` for `es_huntsman` gives `to_es_longbow`; `probe_2h_billhook` for `es_knight` gives `probe_polearm`; an event with no rule passes through; every case once with `has_event` false to cover the fall-through.
4. Session B. Add `M.decide(ctx)` to the resolver. `ctx = { event, career, state, has_event, template_remaps, remap_identity }`. It performs exactly the logic of `_wt_anim_remap.lua:702-760` (state reset and remap selection on `to_*` events), `:778-814` (flail block), `:816-866` (remap and force-fire), `:872-921` (career redirect, including the two writes to `state.remap` at `:877-878` and `:906-907`), `:924-933` and `:935-943`. It returns `mode, target, info` with `mode` one of `flail`, `remap`, `force`, `career`, `career_pass`, `global_native`, `global`, `suffix`, `pass`, and `info.remap_miss = true` when `state.remap` existed but supplied no usable target.
5. In the hook, replace `:702-945` with: build `ctx`, call `_resolver.decide(ctx)`, then perform the same call style per mode as today: `flail` and `global_native` return `func(unit, target, ...)`; `force` calls `pcall(_original_animation_event, unit, target)`; `remap`, `career`, `global`, `suffix`, `career_pass` and `pass` call `pcall(func, unit, target, ...)` and return nothing. Keep the `_log_anims` lines and the sampled `_dbg` line in the hook, driven by `mode`.
6. Mirror into the dev tree. Keep the three overlay blocks in the hook, not in the resolver: `anim-picker-play-trace` stays before the `decide` call; `animation-probe-outcomes` goes into the `remap` dispatch branch; `animation-probe-misses` runs when `info.remap_miss` is true.

**Acceptance (machine, no human).**
- OFFLINE: the unit-test gate exits 0; `git diff --stat` shows no change to `qa/lua/tests/fixtures/wt_anim_funnel_golden.txt`; `git grep -c "has_animation_event\|get_mod\|Managers" -- weapon_tweaker/scripts/mods/weapon_tweaker/_wt_anim_resolver.lua` is 0; the parity gate prints OK; the size gate does not exit 2.
- RIG: `T.expect_rt("wt", "issue290_billhook_kruber_effective_3p_complete")`, `T.expect_rt("wt", "issue112_remap_identity_includes_receiver_career")` and the five WP-WT-05 hero cases still PASS on the new build.
- No issue is closed by this card.

**Guardrails.** No table value changes. No reordering of the seven steps. Do not change which paths use `pcall` and which return a value (WP-WT-08 owns that). Do not touch `_wt_anim_remap_data.lua` (frozen). Keep `WT.billhook_kruber_contract` working (`_wt_anim_remap.lua:1070-1080`).

**Stop and escalate if.** A dev overlay block reads a local that would only exist inside `decide` after the move (for example `force_target` or `career_redir`). List the block id and the local; do not duplicate decision logic into the overlay.

### WP-WT-07 Route template mutations through one ordered registry

| Field | Value |
|---|---|
| Priority | P1 |
| Size | L (session A: registry module and tests; session B: wire the five call sites; session C: disable path and rig script) |
| Agent | strong (ordering between owners, several source-text tests to update) |
| Depends on | WP-WT-01 |
| Issues | advances #445, #1737, #943 (deterministic toggle state); no closure |
| Source | A1-F04 |
| Streams | both (parity gate) |

**Goal.** Every lifecycle event applies the weapon-table owners through one `reconcile(reason)` in one fixed order, and disabling the mod reverts every revertible owner.

**Context.** Eleven owners write `Weapons`, damage profiles or settings tables. Their apply order is written out by hand at five places: `_wt_apply_all` (from WP-WT-01, formerly `weapon_tweaker.lua:938-959`), the rework-master callback (`weapon_tweaker.lua:1004-1011`), the parity flip `_wt431_reapply_profile_repoints` (`_wt431_damage_profile_parity.lua:228-254`), the CWV transition (`weapon_tweaker_backend.lua:641-656`) and the settings batch (`_wt_settings_runtime.lua:71-87`). The history owner requires a sandwich: revert the axe overlay, reproject history, reapply the overlay (`_wt_history_owner.lua:61-108`); the rework-master and CWV sites call `mod._wt_apply_axe_balance(nil, false)` without it. `mod.on_disabled` (`weapon_tweaker.lua:992-1002`) does not revert the priest punch, Bret and brace profile repoints. Those three read one predicate, `mod._wt431_profiles_allowed()` (`_wt431_damage_profile_parity.lua:158-168`; readers at `_wt_priest_punch_owner.lua:195-197`, `_wt_brett_sword_shield_buff.lua:208-211`, `_wt_authentic_pistol_owner.lua:155`). Inside `on_disabled`, `mod:is_enabled()` is already false (`<repos>/Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/toggling.lua:11, 24`).

**Steps.**
1. Add `qa/lua/tests/test_wt_mutation_registry.lua` (list it in `qa/lua/run.lua`): owners registered with orders 30, 10, 20 are applied as 10, 20, 30 and each receives the reason; `revert_all()` runs 30, 20, 10; an `apply` that raises is logged through the injected log function, the other owners still run, and `reconcile` returns `false` plus the failed ids; a duplicate id is rejected; an owner without `revert` is accepted only with `restart_bound = true` and is listed in the second return value of `revert_all`.
2. Create `_wt_mutation_registry.lua` (pure): `M.new(log)` returns `{ register(spec), reconcile(reason), revert_all(), ids() }`, `spec = { id, order, apply, revert, restart_bound }`.
3. In `weapon_tweaker.lua`, directly above `_wt_apply_all`, create the registry (`mod._wt.registry = ...new(function(fmt, ...) pcall(printf, "[wt:REG] " .. fmt, ...) end)`) and register these owners with late-bound closures (each closure checks that the `mod` field exists, as the current code does):

   | order | id | apply | revert |
   |---|---|---|---|
   | 10 | availability | `apply_weapon_unlocks()` | `clear_weapon_unlocks()` |
   | 20 | career_actions | `patch_career_actions_on_weapons()` | `clear_career_action_injections()` |
   | 30 | energy | `mod._wt374_seed_energy_data()` | `mod._wt374_revert_energy_data()` |
   | 40 | history_and_axe | `mod._wt_reconcile_history_owner_stack(reason)`, else `mod._wt_apply_axe_balance(nil, false)` | `_wt_history_owner:restore()` |
   | 50 | priest_punch | `mod.wt_apply_priest_punch_buff()` | same function |
   | 60 | bret | `mod.wt_apply_brett_buff()` | same function |
   | 70 | brace_repoint | `mod._wt431_brace_repoint()` | same function |
   | 80 | bolt_staff | `_wt_bolt_staff_overcharge_runtime.apply()` | `_wt_bolt_staff_overcharge_runtime.revert()` |
   | 90 | fire_sword | `mod._wt_apply_fire_sword(nil, false)` | `mod._wt_apply_fire_sword(nil, true)` |

   Add a comment listing what is deliberately not registered because it is applied once at load and cannot be reverted: authentic brace (`_wt_weapon_balance_patches.lua:371`), the 1H sword push-combo revert, the cross-character template patches, the Deepwood guard.
4. In `_wt431_damage_profile_parity.lua`, make the first line of `mod._wt431_profiles_allowed` (`:158`): `if not mod._wt.is_active() then return false end`. This turns orders 50 to 70 into reverts while the mod is disabled.
5. Replace the applier calls at the five sites with one call each: `_wt_apply_all` calls `mod._wt.registry.reconcile("game_state")` and keeps its other lines (Deepwood and Necromancer package loads, `mod._wt368_deferred_availability = true`, `apply_trait_filters()`); the rework-master callback body becomes `mod._wt.registry.reconcile("rework_master")`; `_wt431_reapply_profile_repoints` becomes `mod._wt.registry.reconcile("peer_parity")` followed by the existing `mod._wt942_owner:reconcile()` line; the CWV transition block calls `mod._wt.registry.reconcile("cwv_transition")` and keeps `M.refresh_on_setting_change(mod)` and its info line; `on_settings_batch_changed` calls an injected `c.reconcile("settings_batch")` (pass `reconcile = function(reason) return mod._wt.registry.reconcile(reason) end` in the install table) and keeps `master_toggles.reconcile_batch`, `rework_runtime:prepare_batch`, `backend.refresh_on_setting_change`, `extra_batch` and its log line.
6. In `mod.on_disabled` keep the `overcharge_presentation.restore` line, replace the individual revert calls with `mod._wt.registry.revert_all()`, keep `revert_trait_pools()` and the info line.
7. Leave the single-setting branches of `mod.on_setting_changed` and the deferred-availability and first-apply blocks of the backend `mod.update` as they are.
8. Update the host tests that assert the old call lists (at least `qa/lua/tests/test_wt_settings_runtime.lua`; run the gate to find the others). Mirror everything into the dev tree.

**Acceptance (machine, no human).**
- OFFLINE: the unit-test gate exits 0. `git grep -n "_wt_apply_axe_balance(nil, false)" -- weapon_tweaker/scripts/mods/weapon_tweaker/` shows only the registry block, `_wt_history_owner.lua` and `_wt_axe_balance.lua`. The parity and size gates pass.
- RIG: add `qa/runtime/wt/wp_wt_07_toggle_roundtrip.lua`, arena `keep`. (a) For each setting in `wt_cog_hammer_heavy_speed_nerf`, `wt_mace_sword_speed_nerf`, `wt_one_hand_axe_cleave_nerf`, `wt_executioner_light_headshot_bonus`, `wt_priest_punch_buff`, `wt_brett_sword_shield_buff`, `wt_fire_sword_sweep_opener`, `wt_fire_sword_nova_slowdown`, `wt_bolt_staff_primary_overcharge_reduction`: deep-copy `Weapons[t].actions` for the templates `two_handed_cog_hammers_template_1`, `dual_wield_hammer_sword_template`, `one_hand_axe_template_1`, `one_hand_axe_template_2`, `two_handed_swords_executioner_template_1`, `two_handed_hammer_priest_template`, `flaming_sword_template_1`, `staff_spark_spear_template_1`; `T.set` the setting to true and call `get_mod("wt").on_setting_changed(id)`; set it back and call again; `T.expect` deep equality with the copy. (b) `get_mod("VMF").mod_state_changed("wt", false)`, `T.frames(3)`; for every template in `Weapons` and every sub-action with an `impact_data.damage_profile` or `damage_profile` string: `T.expect` that it does not start with `wt_`. (c) Re-enable, then `T.expect_eq(select(1, get_mod("wt")._wt.registry.reconcile("rig")), true, "reconcile clean")`.
- Evidence class: R. No issue is closed alone; #445, #943 and #1737 get a deterministic state to test against.

**Guardrails.** Do not change any owner's internals. Do not register `mod._wt942_owner`; keep its existing calls. Do not make authentic brace or the push-combo revert live in this card (D-WT-05). Energy seeding touches only `EnergyData`, so its position is free; history must stay before Flame Sword because `_wt_fire_sword_owner` is installed on top of the axe policy (`weapon_tweaker.lua:1040`).

**Stop and escalate if.** A host test or the rig shows that two owners need opposite relative orders at two sites. Write down the pair and the two sites; do not pick one.

### WP-WT-08 Count swallowed errors and call hooked originals only once

| Field | Value |
|---|---|
| Priority | P1 |
| Size | M |
| Agent | any |
| Depends on | WP-WT-02 (the rig reads the counters through the regression runner); do WP-WT-04 first so the funnel edit is covered |
| Issues | none (makes hidden failures behind #201, #630 and similar reports visible in rig runs) |
| Source | A1-F07, A1-F08 |
| Streams | both (parity gate) |

**Goal.** `mod:safe_hook` never runs the hooked original twice, and every error that `wt` swallows on a vanilla path is counted and printed once, so a rig run can assert that none happened.

**Context.** `mod.safe_hook` (`weapon_tweaker/scripts/mods/weapon_tweaker/_safe_hook.lua:132-163`) runs the handler under `xpcall` and, when the handler raises, calls `func(...)`. Handlers such as the `GearUtils.spawn_inventory_unit` wrapper call the original first and do their work afterwards (`_wt_ingame_3p_swap_owner.lua:62-64`), so an error in the later work runs the original a second time (static evidence: weapon units spawned twice). `mod.traced_hook` delegates to `safe_hook` (`_safe_hook.lua:200-224`). Separately, the `GearUtils.create_equipment` wrapper swallows every error of the whole chain and returns `{}` (`_wt_transform_runtime.lua:331-341`, `:352`), which the engine stores as the slot record (`Vermintide-2-Source-Code/scripts/unit_extensions/default_player_unit/inventory/simple_inventory_extension.lua:874-877`). The animation funnel swallows every error of `Unit.animation_event` for every unit (`_wt_anim_remap.lua:838, 865, 884, 913, 919, 930, 940, 945`). None of this is visible when mod logging is off.

**Steps.**
1. Add `qa/lua/tests/test_wt_safe_hook_single_call.lua` (list it in `qa/lua/run.lua`). Load `_safe_hook.lua` from both trees with `loadfile` + `setfenv`; the stub mod's `hook(self, class, method, wrapper)` stores `wrapper`, and `error`, `info`, `debug` record their text. Cases, each calling the stored wrapper with a counting `original` that returns `1, nil, 3, nil`: (a) handler `function(func, ...) return func(...) end`: original called once, four values returned with the nil holes; (b) handler calls `func(...)` and then raises: original called exactly once (fails today: twice), the four original values are returned, one error line is recorded; (c) handler raises before calling `func`: original called exactly once; (d) the original itself raises inside the handler: original called exactly once and the error propagates to the caller of the wrapper.
2. Fix `mod.safe_hook`. Inside the wrapper keep `local n_args, args = select("#", ...), { ... }`. Pass the handler a `tracked` function that sets `called = true`, calls `func(...)`, stores the count and the packed results, and returns them. Run the handler as `xpcall(function() return handler(tracked, unpack(args, 1, n_args)) end, _error_handler)` (a closure, because the PUC Lua 5.1 test host ignores extra `xpcall` arguments while the game's LuaJIT accepts them). On success return the handler's values as today (`unpack(results, 2, n)`). On failure log as today and count it (`local wt = rawget(self, "_wt"); if wt and wt.note_swallowed then wt.note_swallowed("safe_hook", tostring(class) .. "." .. tostring(method)) end`; `_safe_hook.lua` loads before `mod._wt` exists, so look it up at call time), then: if `called` and results were stored, return the stored original results; if `called` and nothing was stored (the original raised), re-raise with `error(message, 0)`; otherwise `return func(unpack(args, 1, n_args))`.
3. Add a counter table in `weapon_tweaker.lua` after `mod._wt = mod._wt or {}` (`:262`): `mod._wt.swallowed = { create_equipment = 0, anim_event = 0, safe_hook = 0 }` and `mod._wt.note_swallowed = function(kind, detail) ... end`, which increments the counter and prints `[wt:SWALLOW] kind=<kind> n=<count> detail=<text>` through `pcall(printf, ...)` only for the first three occurrences per kind.
4. In `_wt_transform_runtime.lua` call `mod._wt.note_swallowed("create_equipment", <weapon key and error text>)` in the `if not ok then` branch (`:334-341`). Keep the existing `mod:error` line and keep returning `{}`.
5. In `_wt_anim_remap.lua` change each `pcall(func, unit, <event>, ...)` listed in Context to capture its result (`local ok, err = pcall(...)`) and call `mod._wt.note_swallowed("anim_event", tostring(<event>) .. ": " .. tostring(err))` when `ok` is false. Do not change what the hook returns.
6. Register one in-mod check. Put it in `_wt_regression.lua` after `WT.rt_register = _rt_register` (not in the frozen `_wt_runtime_checks.lua`): `_rt_register("wt_no_swallowed_errors", function() local s = WT.swallowed or {} if (s.create_equipment or 0) + (s.anim_event or 0) + (s.safe_hook or 0) > 0 then return string.format("swallowed errors: create_equipment=%d anim_event=%d safe_hook=%d", s.create_equipment or 0, s.anim_event or 0, s.safe_hook or 0) end end)`.
7. Mirror into the dev tree.

**Acceptance (machine, no human).**
- OFFLINE: the unit-test gate exits 0 with the new suite and with `test_wt_anim_funnel_golden` unchanged; parity and size gates pass.
- RIG: add `qa/runtime/wt/wp_wt_08_no_swallowed_errors.lua`, arena `mission:<any level key the rig supports>` with bots: `T.wait(60)` while bots fight a spawned horde (`T.spawn`), then `T.expect_rt("wt", "wt_no_swallowed_errors")`. Case field `host_forbid_log = { "[wt:SWALLOW]" }`.
- Evidence class: U for the double call, R for the counters. No issue is closed by this card.

**Guardrails.** Do not turn a swallowed error into a raised one in this card: the `{}` fallback and the funnel `pcall`s stay (D-WT-04). Do not edit handlers that use `safe_hook`; fix the wrapper only. Keep the nil-hole handling (`select("#", ...)` and explicit `unpack` bounds). Do not touch the two marker globals in `_safe_hook.lua`.

**Stop and escalate if.** The rig case FAILS. That is a real finding, not a script bug: record the `[wt:SWALLOW]` lines (event name, error text) and open the matching fix as a new card; do not silence the counter.

### WP-WT-09 Scope the Brace special 3P remap to non-native receivers

| Field | Value |
|---|---|
| Priority | P2 |
| Size | S |
| Agent | any |
| Depends on | WP-WT-04 (golden test guards the funnel) |
| Issues | none (same bug class as closed issue #210) |
| Source | A1-F03 |
| Streams | both (parity gate) |

**Goal.** `wt` no longer writes `anim_event_3p` on the shared Brace of Pistols template; cross-career wielders still get the substitute event through the career-scoped remap table, and native Saltzpyre is untouched.

**Context.** `_patch_brace_template_for_kruber` (`weapon_tweaker/scripts/mods/weapon_tweaker/_wt_cross_char_template_patches.lua:44-82`, called at `:84`) sets `sub_action.anim_event_3p = "attack_shoot_fast"` on every Brace sub-action whose `anim_event` is `special_action` (`:63-76`). Vanilla has that action and no native `anim_event_3p` (`Vermintide-2-Source-Code/scripts/settings/equipment/weapon_templates/brace_of_pistols.lua:342`). The engine fires `anim_event_3p or anim_event` on the 3P body for every career (`Vermintide-2-Source-Code/scripts/unit_extensions/weapons/weapon_unit_extension.lua:510-512, 652`), so native Witch Hunter careers are changed too. The same file moved the longbows to career-scoped entries of `_3p_template_remaps` for exactly this reason (`:131-148`). The funnel picks a template entry by career prefix, treats `false` as "no remap" and falls back to `_default` (`_wt_anim_remap.lua:434-445`).

**Steps.**
1. Add `qa/lua/tests/test_wt_brace_remap_scope.lua` (list it in `qa/lua/run.lua`). Load `_wt_cross_char_template_patches.lua` from both trees with `loadfile` + `setfenv`. Environment: `Weapons = { brace_of_pistols_template_1 = { actions = { action_one = { default = { anim_event = "attack_shoot" } }, action_three = { default = { anim_event = "special_action" } } } } }`; stub mod with `_wt = { dbg = function() end, dbg_alert = function() end, three_p_template_remaps = {} }`, `warning`, `info`, `hook_safe` as no-ops, and `dofile(self, path)` loading the real sibling files (`wt_wield_patches`, `_wt_longbow_variable_zoom`) through the same environment. Assert after load: no sub-action of the fixture template has `anim_event_3p` (fails today); `mod._wt.three_p_template_remaps.brace_of_pistols_template_1.wh_ == false`; its `_default.special_action == "attack_shoot_fast"`; `Weapons.brace_of_pistols_template_1.wield_anim_career_3p.es_mercenary == "to_repeating_handgun"` (unchanged behaviour).
2. In `_patch_brace_template_for_kruber` delete the `if tpl.actions then ... end` loop (`:63-76`) and the `n_action_remaps` counter (`:51`, `:81`). In its place register the runtime remap, in the same style as the longbow patchers: `_3p_template_remaps.brace_of_pistols_template_1 = _3p_template_remaps.brace_of_pistols_template_1 or {}`, then `.wh_ = false` and `._default = _BRACE_REPEATER_ANIM_REMAP_3P`. Update the trailing `_dbg` line and the comment above the function.
3. Mirror into the dev tree.

**Acceptance (machine, no human).**
- OFFLINE: the unit-test gate exits 0; `git grep -n "sub_action.anim_event_3p" -- weapon_tweaker/ weapon_tweaker_dev/` returns nothing; parity gate OK.
- RIG: add `qa/runtime/wt/wp_wt_09_brace_template_clean.lua`, arena `keep`: for every `action, subs` in `Weapons.brace_of_pistols_template_1.actions` and every `name, sub` in `subs`: `T.expect(type(sub) ~= "table" or sub.anim_event_3p == nil, action .. "." .. name)`. Then `T.expect_eq(get_mod("wt")._wt.three_p_template_remaps.brace_of_pistols_template_1.wh_, false, "native opt-out")`.
- Evidence class: U and R for the data state. Whether the Kruber 3P special shot still looks right is class V; attach `T.shot` of a Kruber bot firing the special if the rig can drive it.

**Guardrails.** Keep `_default` (not `es_` only): Kerillian careers also receive the Brace (`wt_wield_patches.lua`, bulk row `brace_of_pistols_template_1`) and get the substitute event today. Do not touch the wield overrides in the same function. Do not edit `_wt_weapon_balance_patches.lua` (authentic brace).

**Stop and escalate if.** The WP-WT-04 golden changes. It should not, because that harness does not load this module; a change means the funnel was edited by mistake.

### WP-WT-10 Make runtime wield redirects agree with the baked wield table

| Field | Value |
|---|---|
| Priority | P2 |
| Size | M |
| Agent | any |
| Depends on | WP-WT-04 (loader, golden), WP-WT-05 (fixture `wt_anim_vocab.lua`) |
| Issues | advances #290, #748, #948 (removes contradictory encodings); no closure |
| Source | A1-F02 |
| Streams | both (parity gate) |

**Goal.** For every (weapon template, career) that has a baked 3P wield event, the runtime redirect layers produce the same event when given the template's vanilla wield event, or the difference is listed in a reviewed baseline.

**Context.** The 3P wield stance is encoded twice. Static: `wield_anim_career_3p` values from `weapon_tweaker/scripts/mods/weapon_tweaker/wt_wield_patches.lua` (`patches`, `bulk`), which the engine reads directly (`Vermintide-2-Source-Code/scripts/unit_extensions/default_player_unit/inventory/simple_inventory_extension.lua:2011-2013`). Runtime: `_career_anim_redirect` and `_suffix_career_map` in `_wt_anim_remap.lua` (after WP-WT-06: in `_wt_anim_resolver.lua`). They disagree. Example: Kerillian's greatsword on Saltzpyre is baked as `to_2h_sword` (`wt_wield_patches.lua:247`), while the runtime tables send its vanilla wield `to_2h_sword_we` to `to_1h_sword` (`_wt_anim_remap.lua:104-106`) and the suffix `_2h_sword_we` to `_1h_sword` (`:127-129`). For baked pairs the engine fires the baked event, so the runtime entry is only reached on fallback paths, where it then selects a different stance.

**Steps.**
1. Add `qa/lua/tests/test_wt_wield_layer_agreement.lua` (list it in `qa/lua/run.lua`). For every template `t` in `patches` and `bulk` and every career `c` with baked event `B`: `W = fixture.templates[t] and fixture.templates[t].wield`; skip when nil (clone aliases listed in `wield_patches.cwv_style_donors`). Using the WP-WT-04 loader with `has_event` always true: new unit with `career = c`, husk wield with template `t`, fire `W`, take the first delivered event `D`. Emit `t|c|W|B|D` when `D ~= W and D ~= B`. Compare the sorted lines with `qa/lua/tests/fixtures/wt_wield_layer_conflicts.txt` (create it from the first run). The test fails on any difference in either direction.
2. For each baseline line, find the runtime entry that produced `D`: a per-career value in `_career_anim_redirect[W].overrides`, the `alt` of `_career_anim_redirect[W]`, or a value in `_suffix_career_map`. If exactly one baked template uses this `W` for this career, change that runtime value to `B` (for an `alt` result add `overrides[c] = B` instead of changing `alt`; for a suffix result set the suffix value so that the rebuilt event equals `B`). Remove the line from the baseline.
3. If two baked templates share `W` for the same career with different `B`, do not change anything for that line. Keep it in the baseline and add a comment line above it starting with `# ambiguous:` naming both templates.
4. Regenerate the WP-WT-04 golden. Review the diff: only lines that contain an event edited in step 2 may change.
5. Mirror into the dev tree.

**Acceptance (machine, no human).**
- OFFLINE: the unit-test gate exits 0; every remaining line of `wt_wield_layer_conflicts.txt` is preceded by an `# ambiguous:` comment; the parity gate prints OK.
- RIG: the five `issue_948_anim_targets_<hero>` cases of WP-WT-05 still PASS (every new target exists on the receiver skeleton).
- Evidence: class S for agreement. Stance appearance on fallback paths stays class V. No issue is closed by this card.

**Guardrails.** Never edit `wt_wield_patches.lua` in this card: the baked value is the reference (D-WT-03). Do not delete a runtime entry; change values only. Do not touch attack-event remap tables.

**Stop and escalate if.** More than 40 conflict lines appear: the fixture or the loader is probably wrong; check `fixture.templates[t].wield` for three templates by hand against the decompile before editing anything.

### WP-WT-11 Add a funnel fast path for units without wield state

| Field | Value |
|---|---|
| Priority | P2 |
| Size | S |
| Agent | any |
| Depends on | WP-WT-04; do it after WP-WT-06 if that card is open, to avoid conflicting edits |
| Issues | none (performance on the hottest hook; related to the Lua heap instrumentation in `weapon_tweaker.lua:928-985`) |
| Source | A1-F15 |
| Streams | both (parity gate) |

**Goal.** An animation event on a unit that never wielded a weapon through the wield hooks, and that is not a redirect key, reaches the engine without career lookups and without creating per-unit state.

**Context.** `Unit.animation_event` is hooked for every unit in the game (`weapon_tweaker/scripts/mods/weapon_tweaker/_wt_anim_remap.lua:610`). For every enemy event the hook does a `pcall` in `_is_local_player_unit` (`:540-546`, called at `:641`), up to three `pcall`s in `_unit_career_name` (`:551-588`, called at `:649`) and creates a state table through `_state_for` (`:416-424`, called at `:650`). Only units that passed a wield hook have `template` / `key` in their state, so for all other units only the redirect layers can act: the reload route (`:656-664`), `_career_anim_redirect`, `_anim_redirect` and the suffix redirect. For player units, `remap_identity` builds a string on every event (`:702-703`) although it is used only for `to_*` events.

**Steps.**
1. Add `qa/lua/tests/test_wt_anim_fast_path.lua` (list it in `qa/lua/run.lua`). Use the WP-WT-04 loader with a counting `ScriptUnit.has_extension`. Cases on units that never went through the wield hook: (a) `anim(rec, {}, "idle")`: `rec` got exactly `idle`, `has_extension` was called 0 times (fails today), and `mod._wt.unit_state[unit] == nil` (fails today); (b) unit `{ career = "wh_captain" }`, event `to_spear`, `has_event` true: delivered `to_2h_billhook` (unchanged); (c) unit `{ career = "es_knight" }`, event `probe_2h_billhook`: delivered `probe_polearm` (unchanged); (d) event `reload` on a stateless unit: delivered `reload`.
2. In `_wt_anim_remap.lua`, after the tables are defined, build `local _STATELESS_EVENTS = {}` with the keys of `_anim_redirect`, the keys of `_career_anim_redirect`, `reload` and `reload_last`, and add `local function _has_redirect_suffix(event_name)` that returns true when the name ends with one of the entries of `_suffix_order`.
3. In the hook, directly after the 1P early return (`:637-639`) and before `local is_local = ...` (`:641`), add: `if not _unit_state[unit] and not _STATELESS_EVENTS[event_name] and not _has_redirect_suffix(event_name) then pcall(func, unit, event_name, ...) return end`. This is the same call style as the current last line of the hook (`:945`). If WP-WT-08 has landed, count a failure here the same way.
4. Change `:702-704` so that `remap_identity` is computed only when `event_name:sub(1, 3) == "to_"`.
5. Mirror into the dev tree.

**Acceptance (machine, no human).**
- OFFLINE: the unit-test gate exits 0 with the new suite and with an unchanged `wt_anim_funnel_golden.txt`; parity and size gates pass.
- RIG: add `qa/runtime/wt/wp_wt_11_funnel_fast_path.lua`, arena `keep`: `local rat = T.spawn("skaven_clan_rat", <offset>)`, `T.wait(3)`, `T.expect_eq(get_mod("wt")._wt.unit_state[rat], nil, "no remap state for an enemy")`; then `T.expect_rt("wt", "issue290_billhook_kruber_effective_3p_complete")`.
- Evidence class: U and R. No issue is closed by this card.

**Guardrails.** Keep the fast path after the feature-flag check and the 1P early return, so both keep their exact behaviour. Do not remove the final `pcall`. Do not change `_state_for`; the wield hooks still create state. `_last_3p_unit` (`:499`, `:642`) is never read; leave it.

**Stop and escalate if.** The golden file changes. That means a stateful path was affected; revert and report the differing line.

### WP-WT-12 Delete the dead preview node guard and fix ENGINE_SURFACE facts

| Field | Value |
|---|---|
| Priority | P2 |
| Size | S |
| Agent | any |
| Depends on | none |
| Issues | none (removes a trap; related crash class #201, #269) |
| Source | A1-F06, A1-F13 |
| Streams | both (parity gate; each tree has its own `ENGINE_SURFACE.md`) |

**Goal.** The preview hook no longer carries a guard that can never run, and the mod's engine-surface document states the hooks that actually exist.

**Context.** `validate_attachment_sources` (`weapon_tweaker/scripts/mods/weapon_tweaker/_wt_cross_character_safety.lua:67-89`) returns unless its argument has a `.third_person` table. Its only caller passes the fourth argument of `MenuWorldPreviewer._spawn_item_unit` (`_wt_menu_preview_owner.lua:308-313`), and vanilla already passes the `.third_person` sub-table there, whose keys are `wielded` / `unwielded` / `display` (`Vermintide-2-Source-Code/scripts/ui/views/world_hero_previewer.lua:687, 714, 909-917, 1057`). So the guard is always skipped. If someone "fixed" the shape, it would write `link.source = "j_hips"` into the shared vanilla linking table (`_wt_cross_character_safety.lua:80`). The real protection is the `GearUtils.link_units` hook in the same file (`:126-141`), which copies before changing. `weapon_tweaker/ENGINE_SURFACE.md` documents the dead guard as live, says "27 live engine registration sites" (`:26`) where the audit counted 44, names channel `wt_damage_profiles_exact_v1` where the code uses `_v2` (`_wt431_damage_profile_parity.lua:104`), describes the `SimpleInventoryExtension._wield_slot` hook as a diagnostic `hook_safe` where the code is a full `mod:hook` in `_wt_weapon_action_lifecycle.lua:83`, and cites line numbers such as `:4585` in a file that now has 1,376 lines.

**Steps.**
1. Delete the function `validate_attachment_sources` and return `{}` from `install` (`_wt_cross_character_safety.lua:67-89`, `:144`). Delete its readers: `weapon_tweaker.lua:827-828` and `:872`; `_wt_menu_preview_owner.lua:41` and the PRE block `:309-313` (keep the hook and everything after the PRE block).
2. Run the unit-test gate. `qa/lua/tests/test_wt_menu_preview_owner.lua` and `qa/lua/tests/test_wt_phase5_runtime_owners.lua` assert source text that names the deleted symbol: change those assertions to require its absence (`H.equal(source:find("validate_attachment_sources", 1, true), nil)`).
3. In `weapon_tweaker/ENGINE_SURFACE.md`: recount the registrations with `git grep -nE "(mod|self):(hook|hook_safe|safe_hook|safe_hook_safe|traced_hook|traced_hook_safe)\(" -- weapon_tweaker/scripts/mods/weapon_tweaker/` (exclude `_safe_hook.lua` and the dummy-class hooks in `_wt_runtime_checks.lua:572-686`; count the Moonfire loop at `_wt_moonfire_aoe.lua:277-290` as 6) and write that number at `:26`. Remove "(a) pre-validate attachment source nodes" from the `_spawn_item_unit` row. Correct the `_wield_slot` row and the channel name as described in Context. Add rows for `VMFOptionsView.initialize_checkbox_widget` and `callback_setting_changed` (`_wt_master_toggles.lua:294, 302`), `GameNetworkManager.remove_peer` (`_wt431_damage_profile_parity.lua:170`), and the backend `get_career_loadouts`, `add_loadout`, `delete_loadout` hooks (`weapon_tweaker_backend.lua:798, 853, 873`). Replace every `weapon_tweaker.lua` line number above 1376 with the module file name.
4. In `MOD_DEPENDENCIES.md:39` and `:58` remove `wt` and `wt_dev` from the `bt` consumer lists: no `bt` reference exists in either tree (`git grep -n '"bt"' -- weapon_tweaker/ weapon_tweaker_dev/` is empty).
5. Mirror steps 1 and 3 into `weapon_tweaker_dev/` (its `ENGINE_SURFACE.md` documents the dev tree; recount there, the dev tree has more hooks).

**Acceptance (machine, no human).**
- OFFLINE: `git grep -n "validate_attachment_sources" -- weapon_tweaker/ weapon_tweaker_dev/` returns nothing; `git grep -n "exact_v1\|27 live engine" -- weapon_tweaker/ENGINE_SURFACE.md weapon_tweaker_dev/ENGINE_SURFACE.md` returns nothing; the unit-test, parity and size gates pass.
- RIG: `T.expect_rt("wt", "link_units_node_guard")` and `T.expect_rt("wt", "issue269_unwielded_staff_hip_fallback")` PASS on the new build; add `qa/runtime/wt/wp_wt_12_preview_cross_weapon.lua`, arena `keep`: open the hero inventory view (view name per the rig documentation) with a Kruber career and preview `bw_skullstaff_fireball` (enable `unlock_es_mercenary_bw_skullstaff_fireball` first); case field `host_forbid_log = { "Unit.node", "has no node" }`; `T.shot("kruber_staff_preview")`.
- Evidence class: S for the deletion and the document, R for "no node error in the preview". No issue is closed by this card.

**Guardrails.** Do not touch `mod._wt_link_filter` or the `GearUtils.link_units` hook. Do not create a new document or a new QA gate for the hook count. Do not delete the `LevelEndView._verify_weapon_data` hook or `_wt_trait_pools.lua` in this card (dead but harmless; several tests stub `apply_trait_filters`).

**Stop and escalate if.** The rig preview case logs a node error. Then the `link_units` guard does not cover the preview path as the audit assumed: stop, restore the PRE block, and report the log line.

---

## Owner decisions

The owner is unavailable. Agents proceed on the default and name the decision id in their report.

| Id | Question | Conservative default to assume |
|---|---|---|
| D-WT-01 | Must disabling `wt` restore exact vanilla state without a restart? | Natives are always restored and the mod is inert while disabled (WP-WT-01); revertible owners are reverted (WP-WT-07); load-time patches (wield tables, authentic brace, push-combo revert) stay until restart. |
| D-WT-02 | When `wt` and `wt_dev` are both enabled, which one runs? | `wt_dev` runs; public `wt` is disabled through VMF with one chat line (WP-WT-03). |
| D-WT-03 | Baked wield table and runtime redirect tables disagree: which is right? | The baked value in `wt_wield_patches.lua`: it is what plays today (WP-WT-10). |
| D-WT-04 | Should errors that `wt` swallows on vanilla paths be raised again? | No. Keep the fallbacks, count and print them, and let the rig assert zero (WP-WT-08). |
| D-WT-05 | Should restart-bound toggles (authentic brace, 1H sword push-combo revert, weapon history) become live toggles? | No. Leave them restart-bound and unregistered (WP-WT-07). |
| D-WT-06 | The empty-wield override for the elf repeater also changes a 1P event (A1-F05). Keep it? | Keep it: it prevents a network fault. Only record the rig result of WP-WT-05 step 6. |
| D-WT-07 | Should a cross-career weapon stay equipped across game restarts (A1-F18, #1190, #354)? | No change. The loadout cache stays session-only; do not add persistence. |
| D-WT-08 | Is universal availability (#948) dev-only? | Yes. Evidence for public issues must come from the public build; dev results count only for dev overlays. |
| D-WT-09 | Moonfire AoE revert acts host-side on every player's arrows (A1-F09). Change it? | No change and no relabel. |
