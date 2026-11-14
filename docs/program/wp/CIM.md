# Track CIM: crafting, progression, career (work packages)

Author: auditor A5, 2026-11-13. Source findings: `docs/audits/2026-11-13_FORMAL_AUDIT/evidence/A5.md` (A5-F01 to A5-F24). Cards are ordered by priority.
Path shorthand used in every card: `CIMD/` = `crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/`, `CIMS/` = `crafting_in_modded/scripts/mods/crafting_in_modded/`, `MP/` = `modded_progression/scripts/mods/modded_progression/`, `CRT/` = `career_tweaker/scripts/mods/career_tweaker/`, `VT2SRC/` = `<repos>/Vermintide-2-Source-Code/`.

## Family brief

- Four trees, three mods. Crafting in Modded: dev `cim_dev` (entry `CIMD/crafting_in_modded_dev.lua`, 70 files, the working tree) and public stable `cim` (entry `CIMS/crafting_in_modded.lua`). Players craft and edit weapons and accessories for free in the modded realm; all of them live in one VMF setting, `forged_weapons`.
- Modded Progression `mp` (entry `MP/modded_progression.lua`): local daily quests paying Silver Shillings, spendable on plain-Shilling Emporium cosmetics, plus one "Fresh profile" slice. The rest of its plan is not built.
- Career Tweaker `crt` (entry `CRT/career_tweaker.lua`): 75 toggleable talent and passive reworks through one apply/restore engine. Talent/ability swapping is not loaded.
- Engine fact behind the P0 cards: in game 6.13 the modded realm signs in to the player's real account. `MODDED_REALM` only sets `GameSettingsDevelopment.read_only_backend` (`VT2SRC/scripts/settings/game_settings_development.lua:49-52`). That blocks statistics, weave and pose writes, but career loadouts and talents are still pushed by `updateHeroAttributes` (`VT2SRC/scripts/managers/backend_playfab/playfab_mirror_base.lua:2875-2909`). The backend mirror these mods edit is the live account mirror.
- Trap 1: the cim entry chunk is near Lua 5.1's limit of 200 locals. Put new code in a new module and new state on `mod._cim_*`. Never add a top-level `local` to the entry.
- Trap 2: VMF silently drops a second hook on the same `(Class, method)` from one mod, and `mod:dofile` is not cached. Grep the mod for the target first. Hook lines and flag assignments are also pinned as text by `qa/rt_textual_invariants.psd1` and by host tests: when a card moves a pinned line, update the pin in the same change.
- Trap 3: hook the concrete class `PlayFabMirrorAdventure`, never `PlayFabMirrorBase` (`class()` copies parent methods at definition time). Never call `items:get_item_from_id` from inside a mirror hook; read `mirror._inventory_items` with `rawget`.
- Trap 4: `ItemMasterList` and every `NetworkLookup.*` table raise on a missing key. Use `rawget`.
- Trap 5: stable is not a copy of dev. Stable has `_cim_standard_forge_presentation.lua` where dev has that code inline in `standard_forge.lua`; settings are stored per mod id, so `cim_dev` and `cim` keep separate collections; PR #1824 (stable 0.8.149) is open against the stable tree.
- Every source change needs the version claim and CHANGELOG entry of `PROJECT_STANDARDS.md` section 6.6; cards do not repeat that. Diagnostics use engine `printf`, not `mod:info`.
- Host tests: add `qa/lua/tests/test_<name>.lua` (shape `return function(H, repo_root) ... H.test(name, fn) ... end`), add the name to the `suites` list in `qa/lua/run.lua`, run `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1`.

---

### WP-CIM-01 Keep crafted item ids out of the career-data commit

| Field | Value |
|---|---|
| Priority | P0 (official loadout slots are reset to starting gear) |
| Size | M |
| Agent | any (the design is fixed below; do not redesign) |
| Depends on | none |
| Issues | advances #402 and #1688 (their gui_tweaker half is track GUT) |
| Source | A5-F01; related A7-F01, A7-F02; D4 cluster `gut-native-loadout-store` |
| Streams | both: `crafting_in_modded_dev/` first, then `crafting_in_modded/` (the public mod has the same exposure) |

**Goal.** No backend id created by Crafting in Modded can appear in an `updateHeroAttributes` request, whether or not Tweaker: GUI is installed.

**Context.** A craft auto-equips by default (`CIMD/crafting_in_modded_dev_data.lua:112-114`) through `items.set_loadout_item(crafted_id, ...)` (`CIMD/_cim_modded_loadout_owner.lua:519-526`, importer at `:632`). Vanilla writes that id into `_career_data` (`VT2SRC/scripts/managers/backend_playfab/backend_interface_item_playfab.lua:635-665`, `playfab_mirror_base.lua:1928-1941`). At commit, `_check_career_data(careers_data, career_data_mirror)` (`playfab_mirror_base.lua:3409-3628`, only caller `:2885`) diffs it against the server copy and returns `dirty_hero_data`, whose loadout tables are references to the live loadouts. They are JSON-encoded at `:2889-2896` and, for oversized payloads, later at `:2992-2993`. At the next official sign-in the id is not in the inventory, so the slot is "broken" and replaced with starting gear (`:1579-1721`). cim has no code on this path. The only protection is in gui_tweaker, and it was inactive on the public build for ten weeks (#1688).

**Steps.**
1. Add `qa/lua/tests/test_shared_official_loadout_guard.lua` and register it. It loads `tools/shared_lib/_lib_official_loadout_guard.lua` with `loadfile` and uses plain tables. Cases: (a) an owned id in `slot_melee` of loadout 2 is absent from the `dirty_hero_data` returned by `M.wrap` when a fake `func` marks that loadout dirty, and is present again in `careers_data` after `wrap` returns; (b) a loadout with no mirror row falls back to loadout 1's mirror value; (c) both nil gives `unsafe == 1` and leaves the value; (d) a raising `func` still restores, and the error is re-raised; (e) mutating `careers_data` after `wrap` does not change the returned `dirty_hero_data`; (f) non-owned strings and non-string values are never touched. Run the suite: it fails (library missing).
2. Create the pure library `tools/shared_lib/_lib_official_loadout_guard.lua` returning `M` with `VERSION = 1` and:
   - `M.scrub(careers_data, career_data_mirror, is_owned_id)`: for every career, every loadout index `i`, every `key, value` with `type(value) == "string"` and `is_owned_id(value) == true`, replace the value with `career_data_mirror[career][i][key]`, or if that is nil with `career_data_mirror[career][1][key]`. If both are nil leave the value and count it in `unsafe`. Return `subs` (array of `{ career, i, key, value }`) and `unsafe`.
   - `M.detach(dirty_hero_data)`: replace every `hero.careers[career].loadouts[k]` table with a shallow copy.
   - `M.restore(careers_data, subs)`: write every original value back.
   - `M.wrap(func, self, careers_data, career_data_mirror, is_owned_id, report)`: `scrub`; call `func(self, careers_data, career_data_mirror)` under `pcall`, capturing all three returns; `detach` the third; `restore`; call `report(#subs, unsafe)` when either is non-zero; on a `func` error re-raise with `error(err, 0)` after `restore`; otherwise return the three values unchanged.
3. Register the library for `crafting_in_modded_dev` and `crafting_in_modded` in `tools/shared_lib/manifest.psd1` (copy the entry shape of `_lib_debug.lua`), then run `.\tools\shared_lib\sync-shared-libs.ps1 -Apply`.
4. Create `CIMD/_cim_career_commit_guard.lua`, an installer `return function(context)` taking `mod`, `guard`, `rt_register`, `print_line`. It registers exactly one hook: `mod:hook("PlayFabMirrorAdventure", "_check_career_data", function(func, self, careers_data, career_data_mirror) return guard.wrap(func, self, careers_data, career_data_mirror, mod._cim_is_modded_backend_id, report) end)`. `report` prints `[cim:402] scrubbed=%d unsafe=%d` through `print_line` at most 12 times per session and stores `mod._cim402_last_report = { scrubbed = n, unsafe = u }`. Set `mod._cim402_guard_installed = true`. Register the rt check `issue402_career_commit_guard`: run `guard.wrap` on a fixture with a fake `func`; return an error string unless the owned id is absent from the result and back in the fixture afterwards.
5. Load it from the entry directly after the forge state owner block (`CIMD/crafting_in_modded_dev.lua:286-297`), with no new local: `mod:dofile("scripts/mods/crafting_in_modded_dev/_cim_career_commit_guard")({ mod = mod, guard = mod:dofile("scripts/mods/crafting_in_modded_dev/_lib_official_loadout_guard"), rt_register = _rt_register, print_line = printf })`.
6. Repeat steps 4 and 5 in the stable tree (forge state owner block at `CIMS/crafting_in_modded.lua:239-250`; stable mod id and paths).

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` passes with the new suite; `.\qa\check_shared_lib_drift.ps1` passes; `git grep -c '"_check_career_data"' -- crafting_in_modded_dev/scripts crafting_in_modded/scripts` shows exactly one hook registration per tree.
- RIG: add `qa/runtime/cim/issue_402_career_commit_scrub.lua`, arena `keep`, mods: `cim_dev` only (Tweaker: GUI not loaded). Steps: `T.require(rawget(_G, "MODDED_REALM") == true, "modded realm")`; read the career, the current `slot_melee` id and its item `key`; craft that key with `get_mod("cim_dev")._cim_temper_runtime_state.commit_craft({ item_key = key, properties = {}, traits = {}, power_level = 300, rarity = "modded", via_mirror = true, career_name = career }, bid, { raw_item_key = key })` where `bid = Application.guid()`; equip with `items:set_loadout_item(bid, career, "slot_melee")`; wrap `enqueue` (`VT2SRC/scripts/managers/backend_playfab/playfab_request_queue.lua:25`) on the live request-queue instance (`Managers.backend:get_backend_mirror()._request_queue`, `playfab_mirror_base.lua:58`) so that a request with `FunctionName == "updateHeroAttributes"` is recorded and forwarded ONLY if `tostring(request.FunctionParameter.hero_attributes.characters_data):find(bid, 1, true)` is nil; `Managers.backend:commit(true, function() done = true end)`; `T.wait_until(function() return done end, 90, "commit finished")`. Assertions: no recorded request contained `bid`; `mirror._career_data[career][index].slot_melee == bid` (still equipped locally); `T.expect_rt("cim_dev", "issue402_career_commit_guard")`. Cleanup: remove the wrapper, re-equip the original id, delete the craft with `get_mod("cim_dev")._cim277_delete_owned_ids({ bid })`.
- Evidence class: R advances #402 and #1688. Neither closes on this card alone.

**Guardrails.** Do not hook `_commit_internal`, `set_character_data` or any other mirror method: gui_tweaker hooks several of them and this card must not change equip behaviour. Do not remove the crafted id from `_career_data` permanently: the item must stay equipped for the session. Do not edit gui_tweaker. Known and accepted consequence (OD-CIM-02): without Tweaker: GUI's modded loadouts a crafted item is no longer equipped after a restart.

**Stop and escalate if.** Another mod in the repo already hooks `PlayFabMirrorAdventure._check_career_data` (grep first); the rig case records a request containing the id (do not forward it; report FAIL with the request text); PR #1824 is still open when you reach step 6 (finish the dev half and record that the stable half is pending).

---

### WP-CIM-02 Stop the commit hook from dropping completion callbacks

| Field | Value |
|---|---|
| Priority | P0 (end-of-mission soft-lock) |
| Size | S |
| Agent | any |
| Depends on | none |
| Issues | advances #80 |
| Source | A5-F03 |
| Streams | both trees |

**Goal.** A backend commit that carries a completion callback always reaches vanilla, and a forge flag cannot stay set across a game-state change.

**Context.** `mod:hook("BackendManagerPlayFab", "commit", ...)` returns without calling vanilla while `_custom_forge_active` or `mod._cim_standard_forge_active` is true (`CIMD/crafting_in_modded_dev.lua:732-735`; stable `CIMS/crafting_in_modded.lua:683`). Vanilla registers the callback and returns an id (`VT2SRC/scripts/managers/backend_playfab/backend_manager_playfab.lua:933-937`, `playfab_mirror_base.lua:2714-2752`); callbacks fire in `_check_current_commit` (`:1847-1868`). The end-of-mission screen is activated inside such a callback (`VT2SRC/scripts/game_state/state_ingame_running.lua:718-737`), and so is the mechanism switch (`VT2SRC/scripts/managers/game_mode/game_mechanism_manager.lua:523-528`). Forges can be open in a mission (`CIMD/crafting_in_modded_dev.lua:405, 494`). The standard-forge flag is one boolean set and cleared by three window classes (`CIMD/standard_forge.lua:213-244`; stable `CIMS/_cim_standard_forge_presentation.lua:65-85`), so one missed `on_exit` leaves it true for the session.

**Steps.**
1. Add `qa/lua/tests/test_cim_commit_gate.lua` (register it). It loads `CIMD/_cim_commit_gate.lua` with `loadfile` and asserts: `should_suppress(true, nil) == true`; `should_suppress(true, function() end) == false`; `should_suppress(false, nil) == false`; for `M.hook(func, self, skip_queue, cb, forge_active)`: with `forge_active = true` and a callback, the recording `func` is called once with the same three arguments and its return value is returned; with `forge_active = true` and no callback, `func` is not called and nil is returned; with `forge_active = false`, `func` is always called. Run: fails (file missing).
2. Create `CIMD/_cim_commit_gate.lua` (pure): `M.should_suppress(forge_active, commit_complete_callback)` returns `forge_active == true and commit_complete_callback == nil`; `M.hook(func, self, skip_queue, commit_complete_callback, forge_active)` returns nothing when suppressed, else `return func(self, skip_queue, commit_complete_callback)`.
3. In the entry, load it onto the mod before the hook (`mod._cim_commit_gate = mod:dofile("scripts/mods/crafting_in_modded_dev/_cim_commit_gate")`) and change only the hook body at `CIMD/crafting_in_modded_dev.lua:733-734` to `return mod._cim_commit_gate.hook(func, self, skip_queue, commit_complete_callback, (_custom_forge_active or mod._cim_standard_forge_active) and true or false)`. Keep the line `mod:hook("BackendManagerPlayFab", "commit", function(func, self, skip_queue, commit_complete_callback)` byte for byte: `qa/rt_textual_invariants.psd1:553` pins it.
4. In `mod.on_game_state_changed` (`CIMD/crafting_in_modded_dev.lua:1159`) add as the first two statements `_custom_forge_active = false` and `mod._cim_standard_forge_active = false` (a view cannot survive a game-state change).
5. Right after the load in step 3, register the rt check `issue_cim_commit_callback_preserved` with `_rt_register`: it calls `mod._cim_commit_gate.hook` with a recording function for the three combinations of step 1 and returns an error string on any deviation.
6. Apply steps 2 to 5 to the stable tree (hook at `CIMS/crafting_in_modded.lua:683`, state callback at `:1026`).

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` passes; `pwsh -NoProfile -File qa/check_rt_textual_invariants.ps1` passes.
- RIG: `qa/runtime/cim/issue_cim_commit_callback.lua`, arena `keep`. Case A: set `get_mod("cim_dev")._cim_standard_forge_active = true`; `local id = Managers.backend:commit(true, function() fired = true end)`; `T.expect(id ~= nil, "commit returned an id")`; `T.wait_until(function() return fired end, 90, "callback fired while the forge flag is set")`; cleanup sets the flag false. Case B: set the flag true, call `get_mod("cim_dev").on_game_state_changed("enter", "StateIngame")`, then `T.expect_eq(get_mod("cim_dev")._cim_standard_forge_active, false, "flag reset on state change")`. Also `T.expect_rt("cim_dev", "issue_cim_commit_callback_preserved")`.
- Evidence class: R. No issue closes; #80 advances.

**Guardrails.** Do not remove the hook or the suppression of callback-less commits (OD-CIM-05). Do not refactor the three window hooks or replace the boolean with another structure: `qa/lua/tests/test_cim_cwv_template_catalog.lua:194` and `test_cim_direct_craft.lua` depend on the literal assignment. Do not touch `_craft_via_synth` (`CIMD/standard_forge.lua:1224-1245`).

**Stop and escalate if.** The textual-invariant gate fails after step 3 (the pinned line changed); case A also times out with the flag false (then commits are blocked in the rig itself and the case is INCONCLUSIVE, not a product failure).

---

### WP-CIM-03 Open the standard bench through an existing HeroView screen

| Field | Value |
|---|---|
| Priority | P0 (Lua assert in the view update path, dev and public) |
| Size | S |
| Agent | any |
| Depends on | none |
| Issues | advances #80 |
| Source | A5-F02, A5-F16 |
| Streams | both trees |

**Goal.** `/cim_craft_standard` and the `standard_crafting_hotkey` keybind open the keep crafting bench instead of asserting.

**Context.** `mod.open_standard_crafting` calls `transition_with_fade("hero_view_force", { menu_state_name = "forge" })` (`CIMD/crafting_in_modded_dev.lua:516-518`; stable `CIMS/crafting_in_modded.lua:470`). `HeroView.post_update_on_enter` passes that name to `_change_screen_by_name`, which asserts when the name is not a screen (`VT2SRC/scripts/ui/views/hero_view/hero_view.lua:477-480, 499-510`). The screens are `overview`, `achievements`, `loot`, `keep_decorations`, `weave_forge`, `handbook` (`VT2SRC/scripts/ui/views/hero_view/hero_view_definitions.lua:74-166`). `forge` is a window layout of the overview screen (`VT2SRC/scripts/ui/views/hero_view/states/hero_window_layout.lua:72`), selected through `menu_sub_state_name` (`hero_view.lua:82-94`, `VT2SRC/scripts/ui/views/hero_view/states/hero_view_state_overview.lua:252-255`). Vanilla's own bench interaction uses `menu_state_name = "overview", menu_sub_state_name = "forge"` (`VT2SRC/scripts/unit_extensions/generic/interactions.lua:2203-2207`). Separately, the scoped `HeroView.on_enter` hook swallows an error from vanilla (`CIMD/crafting_in_modded_dev.lua:567-576`) after vanilla has already blocked input (`hero_view.lua:282-288`).

**Steps.**
1. Add `qa/lua/tests/test_cim_standard_bench_route.lua` (register it). It loads `CIMD/_cim_bench_route.lua` and asserts `M.transition_params()` deep-equals `{ menu_state_name = "overview", menu_sub_state_name = "forge" }` and returns a new table on each call. With `H.test_if` (decompile present: `os.getenv("VT2_DECOMPILE_ROOT") or repo_root .. "/../Vermintide-2-Source-Code"`, the pattern of `qa/lua/tests/test_cim_ranalds_game_keys_1696.lua:104-145`) it reads `scripts/ui/views/hero_view/hero_view_definitions.lua` and `scripts/ui/views/hero_view/states/hero_window_layout.lua`, collects every `name = "<x>"`, and asserts the screen name is in the first file and the sub-state name in the second. It also asserts that neither entry file contains the plain text `menu_state_name = "forge"`. Run: fails.
2. Create `CIMD/_cim_bench_route.lua` (pure) with `M.transition_params()`.
3. Load the module onto `mod._cim_bench_route` next to the other policy loads near the top of the entry. In `mod.open_standard_crafting` replace the literal params table with `mod._cim_bench_route.transition_params()`. Correct the comments at `CIMD/crafting_in_modded_dev.lua:463-464` and `:517`.
4. In the `HeroView.on_enter` hook (`CIMD/crafting_in_modded_dev.lua:546-577`): keep the `pcall` and the three restore assignments, then replace the warning-only branch with `if not ok then error(err, 0) end`.
5. Register the rt check `issue_cim_bench_route_is_real_screen`: return `"skip: HeroView not loaded"` when `rawget(_G, "HeroView")` is nil; otherwise return an error string unless `mod._cim_bench_route.transition_params().menu_state_name == "overview"`.
6. Apply steps 2 to 5 to the stable tree (`CIMS/crafting_in_modded.lua:418-472` and `:499-528`).

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` passes; `git grep -n 'menu_state_name = "forge"' -- crafting_in_modded_dev/scripts crafting_in_modded/scripts` prints nothing.
- RIG: `qa/runtime/cim/issue_cim_standard_bench_opens.lua`, arena `keep`. `T.cmd("cim_craft_standard")`; `T.wait_until(function() local ui = Managers.ui._ingame_ui return ui and ui.current_view == "hero_view" end, 15, "hero view open")`; `T.wait(2)`; `T.expect(get_mod("cim_dev")._cim_standard_forge_active == true, "crafting window entered")`; case field `host_forbid_log = { "Could not find state by name" }`; cleanup closes the view with `Managers.ui._ingame_ui:handle_transition("exit_menu")` and waits until `current_view` is nil.
- Evidence class: R. #80 advances (its in-mission tab route is owned by gui_tweaker and is not decided here).

**Guardrails.** Do not change the gates in `open_standard_crafting` (Chaos Wastes block, keep check, `allow_in_mission`). Do not touch `mod.open_forge`. Do not add a second `HeroView.on_enter` hook.

**Stop and escalate if.** The decompile shows a screen named `forge` (the audit premise is then wrong: stop and change nothing); the rig opens the view but `_cim_standard_forge_active` stays false (the console layout file `hero_window_layout_console.lua:130` may be in use: record which layout the rig ran).

---

### WP-CIM-04 Restore saved crafts without deleting them or re-saving the game

| Field | Value |
|---|---|
| Priority | P1 (a saved craft becomes invisible after restart; the record survives) |
| Size | M |
| Agent | any |
| Depends on | none |
| Issues | #1654 (closes on R); advances #277 and #682 (same store) |
| Source | A5-F04, A5-F05; D4 cluster `cim-crafted-item-persistence` |
| Streams | both trees (`_cim_synthetic_item_contract.lua` is identical in both after id normalisation) |

**Goal.** At boot every saved craft is put back in the inventory once, with no "new item" marker, no per-item save of the game's own save file, one inventory refresh in total, and a mismatch is reported instead of removing the item.

**Context.** Restore and fresh crafts share `M.inject_mirror_item` (`CIMD/_cim_synthetic_item_contract.lua:1078-1136`). It calls `mirror.add_item(mirror, backend_id, payload)` at `:1113` with no skip flags, so vanilla marks the id as new and autosaves (`VT2SRC/scripts/managers/backend_playfab/playfab_mirror_base.lua:2494-2545`, `VT2SRC/scripts/helpers/item_helper.lua:128-158`). It then compares the row with an expectation and on any mismatch removes the row (`:1118-1131`). Each restored item also runs `dirtify_interfaces` plus `items:_refresh()` (`CIMD/crafting_in_modded_dev.lua:968-988`). The loops are `_athanor_inject_all` (`:1082-1130`) and `_athanor_retry_pending` (`:1134-1150`), run on every `BackendManagerPlayFab._create_interfaces`. A tester lost sight of a crafted weapon after a restart with no Lua error (#1654). An existing test pins "mismatch removes the row" for the craft path (`qa/lua/tests/test_cim_synthetic_item_contract.lua:1503-1512`); that stays true for crafts.

**Steps.**
1. Add cases to `qa/lua/tests/test_cim_synthetic_item_contract.lua` beside the `#1654` cases, reusing `playfab_mirror`, `saved_record` and `restore` (`:1441-1475`): (a) `contract.inject_mirror_item(mirror, id, payload, nonce, record, { restore = true })` on a mirror whose `add_item` records its arguments shows arguments 4 and 5 are both `true`; without the options table both are nil. (b) With `{ restore = true }` and an `add_item` that perturbs `item.properties.stamina`, the call returns `true`, the row is still in `mirror._inventory_items`, and the sixth return value is a string containing `properties`. (c) Without options the same perturbation still returns nil and removes the row. (d) `contract.inject_and_refresh_mirror_item(mirror, id, payload, nonce, record, refresh, { restore = true, defer_refresh = true })` never calls `refresh`. Run: (a), (b), (d) fail.
2. In `M.inject_mirror_item` add a sixth parameter `options`. When `options and options.restore == true`: call `pcall(mirror.add_item, mirror, backend_id, payload, true, true)`; on a postcondition mismatch do not call `_cleanup_injected_payload` and return `true, nil, token, false, rollback, "mismatch:" .. tostring(mismatch_field)`. Every other path is unchanged.
3. In `M.inject_and_refresh_mirror_item` add a seventh parameter `options`, pass it through, return the warning as a fifth value, and skip `M.complete_mirror_injection_refresh` when `options.defer_refresh == true`.
4. In the entry, with no new entry local: move the body of the inner `refresh_backend` function (`CIMD/crafting_in_modded_dev.lua:968-984`) to `mod._cim_refresh_backend_items = function() ... end` defined just above `_athanor_inject_item`, and make the inner function call it. Give `_athanor_inject_item` a third parameter `options`, pass it to `contract.inject_and_refresh_mirror_item`, and return the warning as a fifth value.
5. In `_athanor_inject_all` and `_athanor_retry_pending` call `_athanor_inject_item(w, bid, { restore = true, defer_refresh = true })`. When a warning comes back, `printf("[cim:1654] restore kept bid=%s key=%s field=%s", ...)` once per `(bid, field)` and store it in `mod._cim_restore_warnings[bid]`. After each loop, if at least one item was injected, call `mod._cim_refresh_backend_items()` once. Print one line per pass: `[cim:restore] saved=%d present=%d kept_with_warning=%d failed=%d`.
6. Extend the existing rt check `issue1654_saved_crafts_restored` so it also fails when a restored id is a key of `PlayerData.new_item_ids`.
7. Apply steps 2 to 6 to the stable tree (`CIMS/crafting_in_modded.lua:875, 954, 1002`).

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` passes, including the unchanged case at `test_cim_synthetic_item_contract.lua:1503-1512`.
- RIG: plan `qa/runtime/plans/cim_restore_two_boot.json`, two boots on the same profile, arena `keep`. Boot 1, `qa/runtime/cim/issue_1654_craft_two_copies.lua`: craft two copies of the hero's current melee key through `get_mod("cim_dev")._cim_temper_runtime_state.commit_craft`, the first with `properties = { attack_speed = 0 }`, the second with `properties = { stamina = (0.2 * 3 / 5 - 0.1) / (0.2 - 0.1) }`; assert both rows exist in `Managers.backend:get_backend_mirror()._inventory_items`. Boot 2, `qa/runtime/cim/issue_1654_both_restored.lua`: for every id in `get_mod("cim_dev"):get("forged_weapons")` assert `rawget(mirror._inventory_items, id) ~= nil`; assert `next(get_mod("cim_dev")._cim_restore_failures) == nil`; assert no saved id is a key of `PlayerData.new_item_ids`; `T.expect_rt("cim_dev", "issue1654_saved_crafts_restored")`; `host_expect_log = { "[cim:restore] saved=" }`; `host_forbid_log = { "mirror_postcondition" }`. Cleanup in boot 2 deletes both crafts with `_cim277_delete_owned_ids`.
- Evidence class: R closes #1654 when boot 2 passes on the build that carries this change.

**Guardrails.** Do not change the craft path (new crafts keep the strict postcondition and the "new" marker). Do not touch the property trim in `CIMD/_cim_forge_state_owner.lua:519-565` or the `validate_saved_occupant` branch. Do not delete or rewrite any saved record.

**Stop and escalate if.** The rig cannot yet restart and continue on one profile (deliver the offline part and state that #1654 stays open); boot 2 shows a saved id missing with no `[cim:1654]` line (a different loss path: capture the `[cim:restore]` line and the saved record; do not guess).

---

### WP-CIM-05 Make the regression suites safe for the rig sweep

| Field | Value |
|---|---|
| Priority | P1 (every boot's suite sweep can report a PASS for a check that did not run) |
| Size | M |
| Agent | any |
| Depends on | none (the rig calls `get_mod("VMF").run_command("<id>_regression_test")` and captures echo output) |
| Issues | none directly; precondition for machine closure of this family's `verify-fix` issues |
| Source | A5-F07 |
| Streams | `crafting_in_modded_dev/`, `crafting_in_modded/`, `modded_progression/`, `career_tweaker/` |

**Goal.** Each of the three suites reports PASS, FAIL or SKIP per check on chat and on the engine log, exposes the last results as a table, and never reports PASS for a check that could not run.

**Context.** The cim runner already has three verdicts (`CIMD/_cim_bootstrap_runtime.lua:156-185`). The mp and crt runners have two: a check that returns any string is FAIL and a check that returns nil is PASS (`MP/modded_progression.lua:115-130`, `CRT/_crt_regression.lua:43-59`). Four checks return nil when they cannot evaluate, which counts as PASS: `CIMD/_cim_settings_runtime.lua:30`, `MP/modded_progression.lua:151`, `CRT/_crt_regression.lua:209`, `CRT/_crt_regression.lua:632`. Results are written with `mod:echo`, `mod:info`, `mod:warning` only, and the load marker `[<id>:LOAD]` is `mod:info` (`CIMD/_cim_bootstrap_runtime.lua:81-83`, `MP/modded_progression.lua:100`, `CRT/career_tweaker.lua:87`), which is invisible when mod logging is off.

**Steps.**
1. Add `qa/lua/tests/test_shared_rt_runner.lua` (register it) for `tools/shared_lib/_lib_rt_runner.lua`: the three verdicts, a raising check (FAIL with the error text), a check returning a non-string value (FAIL), order preserved, counts equal the number of checks, and an `emit` that raises does not stop the run. Run: fails (library missing).
2. Create the pure library `tools/shared_lib/_lib_rt_runner.lua`: `M.run(checks, emit)`, where `checks` is the array of `{ name, fn }` and `emit(verdict, name, detail)` is called once per check under `pcall`. Verdicts: `pcall` ok and result nil is `PASS`; ok and a string starting with `skip:` is `SKIP` (detail is the rest, trimmed); anything else is `FAIL`. It returns `{ pass = n, fail = n, skip = n, results = { { name =, verdict =, detail = }, ... } }`.
3. Register the library for the four trees in `tools/shared_lib/manifest.psd1`; run `.\tools\shared_lib\sync-shared-libs.ps1 -Apply`.
4. In each runner replace the loop with `M.run`. `emit` does both `mod:echo("  %s: %s%s", verdict, name, detail and (" -- " .. detail) or "")` and `pcall(printf, "[<id>:RT] %s %s %s", verdict, name, tostring(detail or ""))`. After the run: echo the summary, `pcall(printf, "[<id>:RT] SUMMARY pass=%d fail=%d skip=%d version=%s", ...)`, and store the returned table in `mod._cim_rt_last`, `mod._mp_rt_last`, `mod._crt_rt_last`. Keep command names and the banner echo.
5. Change the four silent returns listed in Context to `return "skip: <short reason>"`.
6. Next to each `mod:info("[<id>:LOAD] ...")` add `pcall(printf, "[<id>:LOAD] v%s enabled fp=%s OK", ...)` with the same arguments. Keep the `mod:info` line.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` passes; `.\qa\check_shared_lib_drift.ps1` passes; `git grep -n "then return end  *-- .*skip" -- crafting_in_modded_dev/scripts crafting_in_modded/scripts modded_progression/scripts career_tweaker/scripts` prints nothing.
- RIG: one boot with `cim_dev`, `mp`, `crt` loaded, arena `keep`. Case fields `host_expect_log = { "[cim:LOAD] v", "[mp:LOAD] v", "[crt:LOAD] v", "[cim:RT] SUMMARY", "[mp:RT] SUMMARY", "[crt:RT] SUMMARY" }`. Script `qa/runtime/cim/suite_tables_present.lua`: after the sweep, for `get_mod("cim_dev")._cim_rt_last`, `get_mod("mp")._mp_rt_last`, `get_mod("crt")._crt_rt_last` assert each is a table with `pass + fail + skip == #results`, and `T.note` the three counts.
- Evidence class: R. No issue closes.

**Guardrails.** Do not rename commands or checks (the rig keys `T.expect_rt` on check names). Do not delete checks here, including the one known to fail (`modded_loadout_round_trip_save_then_clear`, handled by WP-CIM-11). Do not convert nil returns to skips beyond the four listed.

**Stop and escalate if.** A check reports FAIL after the change that reported PASS before only because of the new verdict rules (list it with its returned text; do not edit the check to make it pass).

---

### WP-CIM-06 Protect the crafted collection: validate, back up, import

| Field | Value |
|---|---|
| Priority | P1 (the only copy of every crafted item is one settings key) |
| Size | L (split: 6a steps 1-4, 6b steps 5-6, 6c steps 7-9; each part ships alone, step 10 with each) |
| Agent | any |
| Depends on | WP-CIM-04 (same owner file and restore loop; land 04 first) |
| Issues | advances #1654 and #277 |
| Source | A5-F06 |
| Streams | both trees |

**Goal.** A crafted collection cannot be lost to a bad write, a rejected record, or a move between the dev and stable mods unless the player chooses it.

**Context.** `save()` writes the whole registry with `mod:set("forged_weapons", save_data)` (`CIMD/_cim_forge_state_owner.lua:65-91`). VMF keeps every mod's settings in one table. If any mod stores a table with mixed array and map keys the save fails for all mods, and the file is only written on game-state change, options close or reload (`<repos>/Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/settings.lua:5-7, 20-34`). `load()` drops any record the contract rejects and then calls `save()`, which makes the drop permanent (`CIMD/_cim_forge_state_owner.lua:92-137`). Settings are namespaced by mod id (`settings.lua:48-55`), so `cim_dev` and `cim` each have their own `forged_weapons` and neither tree reads the other's.

**Steps.**
1. Add `qa/lua/tests/test_cim_store_policy.lua` (register it) for `CIMD/_cim_store_policy.lua`: a record holding a mixed table is rejected with its backend id and field path; an empty table and nested arrays are accepted; `merge_missing` never overwrites an existing id, returns the count added, and never mutates its inputs. Run: fails.
2. Create `CIMD/_cim_store_policy.lua` (pure): `M.is_serializable(value)` (true for number, string, boolean; for a table true only if all keys are strings or all keys are the integers 1..n, checked recursively); `M.validate_store(store)` returns `true` or `false, backend_id, path`; `M.merge_missing(target, source)` returns a new table and the count added; `M.count(store)`.
3. In `CIMD/_cim_forge_state_owner.lua` rename the current `save` body to `save_strict(source)`: build `save_data` as today, validate it, and when invalid do not call `mod:set`, `printf("[cim:store] REFUSED write: record %s field %s is not serializable; previous save kept", ...)`, then `error("store_not_serializable", 0)`. Change every `pcall(save, candidate)` in the file to `pcall(save_strict, candidate)` (dev: `:162`, `:209`, `:228`, in `mod._cim_register_craft`, `mod._cim_register_crafts_batch`, `mod._cim_unregister_crafts_batch`; stable has only the first, at `CIMS/_cim_forge_state_owner.lua:162`). Define `save(source)` as `return pcall(save_strict, source)`, so every other caller (`load()`, `_cim_set_custom_glow`, `_cim_unregister_craft`, `mod._cim_persist_crafts`, the returned `save`) keeps a function that never throws.
4. In `load()`: copy each rejected record into the setting `forged_weapons_rejected` under its id as `{ record = weapon, reason = err }` (at most 200 entries; when full, skip new ones and print once), instead of only printing. Call the trailing `save()` only when a record was rejected or migrated (`rarity == "promo"` or `via_mirror == nil`); otherwise do not write.
5. Session backup: the first time `load()` runs in a process (guard `mod._cim_store_backup_done`), if the stored `forged_weapons` is a non-empty table, `mod:set("forged_weapons_backup", stored, false)`. Never write an empty backup.
6. Add the command `cim_restore_backup` in `CIMD/_cim_command_owner.lua`. Without an argument it echoes how many backup ids are missing from the live store. With `CONFIRM` it registers the missing records through `mod._cim_register_crafts_batch` (validates and persists once, `CIMD/_cim_forge_state_owner.lua:185-216`) and runs the restore loop. It never removes or overwrites an id.
7. Other-stream read: give the forge state owner a context getter `get_user_setting` (default `function(key) return Application.user_setting(key) end`) and a function `mod._cim_other_stream_store()` returning `get_user_setting("mods_settings")[other_id].forged_weapons`, where `other_id` is `"cim"` in the dev tree and `"cim_dev"` in the stable tree, or nil when any level is missing.
8. Add the command `cim_import_other_stream`: without an argument echo the `merge_missing` count; with `CONFIRM` register the missing records through `mod._cim_register_crafts_batch`. Additive only.
9. At load, if `get_mod("cim")` and `get_mod("cim_dev")` both exist and both return true from `:is_enabled()`, print once with `printf` and `mod:echo`: `[cim:store] both Crafting in Modded streams are enabled; each keeps its own crafted items`.
10. Register rt checks: `issue_cim_store_serializable` (`validate_store` on the live registry) and `issue_cim_store_backup_present` (returns `"skip: no crafted items"` when the live store is empty).
11. Apply each part to the stable tree. Stable has no `mod._cim_register_crafts_batch`: there, steps 6 and 8 call `mod._cim_register_craft(backend_id, record)` once per missing id and stop at the first refusal.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` passes. Add a case (new file `qa/lua/tests/test_cim_forge_state_store.lua`) that installs `_cim_forge_state_owner.lua` with a fake `mod` whose `get`/`set` use an in-memory table and count `set` calls, and asserts: a record with a mixed table makes `mod._cim_register_craft` return `false` with a reason starting `save:` and leaves the stored table unchanged; a `woc_*` record ends in `forged_weapons_rejected`; a clean store causes no `set("forged_weapons", ...)` from `load()`.
- RIG: `qa/runtime/cim/issue_cim_store_backup.lua`, arena `keep`: note `get_mod("cim_dev"):get("forged_weapons_backup")` id count, craft one item, assert the backup count is unchanged (the backup is from session start), `T.cmd("cim_restore_backup")`, `T.expect_rt("cim_dev", "issue_cim_store_serializable")`. Cleanup deletes the craft.
- Evidence class: U and R. Advances #1654 and #277; closes neither.

**Guardrails.** No automatic import between streams (OD-CIM-03). No file IO (`io` is unavailable in retail and `qa/rt_textual_invariants.psd1:696` forbids `io.open` in the entry). Do not change the record shape or `SCHEMA_VERSION`. Do not make `woc_*` relic records restorable: they only move to the rejected store.

**Stop and escalate if.** `Application.user_setting("mods_settings")` is nil or not a table in the rig (stop part 6c and report what the call returned); an existing host test asserts that `load()` always calls `save()`.

---

### WP-CIM-07 Adopt the loadout guard in every item-minting mod

| Field | Value |
|---|---|
| Priority | P1 |
| Size | L (split per consumer mod: cwv, woc, mp; then the contract text) |
| Agent | strong (each mod marks its own ids differently, and the gui_tweaker store has open defects this must not mask) |
| Depends on | WP-CIM-01 |
| Issues | advances #402, #1688, #375 |
| Source | A5-F01, A5-F10; A7-F01, A7-F02; D4 cluster `gut-native-loadout-store` |
| Streams | `character_weapon_variants/`, `weapons_of_chaos/`, `modded_progression/` (single trees); text in `docs/CROSS_MOD_ARCHITECTURE.md` |

**Goal.** One written contract, enforced by the same library in every mod that creates backend ids: an id the official account does not own is never sent in career data and never destroyed in a modded store.

**Context.** WP-CIM-01 adds `tools/shared_lib/_lib_official_loadout_guard.lua` and uses it for cim's ids only. Other mods create ids that do not exist on the account: Character Weapon Variants (`cwv_<key>_NNN`), Weapons of Chaos relics (`woc_*`), Modded Progression's Emporium overlay rows (`MP/modded_progression.lua:589-624`) and locally granted ids (`:386-398`). gui_tweaker's modded loadout store (`gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_native_loadouts.lua`) stops the write earlier, by never letting `_career_data` change in the modded realm, but it is optional, was inactive on the public build (#1688), and has open defects of its own: its exit snapshot can replace a stored modded id with the official fallback (A7-F01) and the store has no single owner (A7-F02). VMF chains hooks from different mods on one method, so each mod can install its own `_check_career_data` wrapper with its own predicate. No shared registry is needed.

**Steps.**
1. For each consumer mod find the single function that answers "did this mod create this backend id" and cite it in the change. If none exists, write one as a pure function with a host test first (that mod's own id shapes return true; vanilla GUIDs and other mods' ids return false).
2. Register the library for the consumer in `tools/shared_lib/manifest.psd1`, run the sync, and install one hook per mod exactly as in WP-CIM-01 step 4, with a per-mod report prefix and an rt check named `issue402_career_commit_guard`.
3. Career Tweaker (A5-F10): add no guard. Add one sentence to the `level_override_*` and `unlock_all_careers` tooltips in `CRT/career_tweaker_localization.lua` saying that talent and career choices made while the override is on are saved to the shared profile. No code change.
4. Add a section "Official loadout contract" to `docs/CROSS_MOD_ARCHITECTURE.md` with three rules: (R1) a mod that creates backend ids installs the guard with its own predicate; (R2) a modded-only store never overwrites an id because it does not resolve right now; (R3) realm detection reads `rawget(_G, "MODDED_REALM")` first. Name the owners: guard library `tools/shared_lib/_lib_official_loadout_guard.lua`; store `_gut_native_loadouts.lua`.
5. Add `qa/lua/tests/test_shared_official_loadout_contract.lua` (register it): read `tools/shared_lib/manifest.psd1` as text and assert the guard library lists all five consumer trees.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` and `.\qa\check_shared_lib_drift.ps1` pass; `git grep -c '"_check_career_data"'` shows exactly one hook per consumer tree.
- RIG: copy `qa/runtime/cim/issue_402_career_commit_scrub.lua` per mod (`qa/runtime/cwv/`, `qa/runtime/woc/`, `qa/runtime/mp/`), equip one of that mod's items, same request-capture assertion. Run each once without gui_tweaker and once with `gut_dev` loaded. With `gut_dev` loaded the expected result is zero scrubs and no request containing the id.
- Evidence class: R advances #402 and #1688. They close only together with the track GUT cards for A7-F01 and A7-F02.

**Guardrails.** Do not edit gui_tweaker here. Do not make the guard depend on gui_tweaker being present or absent. Do not add a cross-mod global registry.

**Stop and escalate if.** A consumer mod's ids cannot be told apart from account-owned ids by a pure predicate (describe the id shapes found); the run with `gut_dev` loaded shows scrubs above zero (the store let a write through: report it to track GUT with the `[<id>:402]` line).

---

### WP-CIM-08 Remove mp's inert un-gate hooks and correct its claims

| Field | Value |
|---|---|
| Priority | P1 (players are told six systems work; one does) |
| Size | M |
| Agent | any |
| Depends on | none |
| Issues | #1671 closes on U; advances #1684 and #1693 |
| Source | A5-F08, A5-F09, A5-F18 |
| Streams | `modded_progression/` (single tree) |

**Goal.** Modded Progression installs no hook that does nothing on the current game, carries no dead scaffolding, and describes only what it provides.

**Context.** Four hooks wrap vanilla methods in a bracket that clears the pre-6.12 flag `script_data["eac-untrusted"]`: `LevelEndViewBase.init` (`MP/modded_progression.lua:1244`), `HeroWindowItemCustomization._enable_craft_button` and `_update_state_craft_button` (`:1340-1341`), `AchievementManager.trigger_event` (`:1354`). The 6.13 gates read `GameSettingsDevelopment.read_only_backend` instead (`VT2SRC/scripts/ui/views/level_end/level_end_view_base.lua:59, 231`, `VT2SRC/scripts/ui/views/hero_view/windows/hero_window_item_customization.lua:1878, 1928`, `VT2SRC/scripts/managers/achievements/achievement_manager.lua:128-130`), so the hooks change nothing; the code comments say so (`MP/modded_progression.lua:400-407, 1351-1353`). `mark_seeded`, `apply_mirror_overlay` and three `serialize_*_from_mirror` functions have no caller (`:188-190, 319-345`). `/mp_reset` wipes all local progress with no confirmation (`:1466-1476`). The in-game description lists XP, loot chests, Okri's Challenges and the crafting bench as working (`MP/modded_progression_localization.lua:4`).

**Steps.**
1. Update tests first. In `qa/lua/tests/test_mp_fresh_profile_routing.lua:496-498` change the three `H.truthy(main:find(...))` assertions to assert the text is absent, and at `:505` change the expected count of `mark_seeded(` from 1 to 0. Add `qa/lua/tests/test_mp_reset_policy.lua` (register it) for `MP/_mp_reset_policy.lua`: `plan(nil)` returns `"preview"`, `plan("CONFIRM")` returns `"wipe"`, any other argument returns `"preview"`. Run: the changed assertions and the new suite fail.
2. Delete the four `mod:hook(...)` lines named in Context. Delete `_with_eac_off_unless_fresh` (`:544-547`) and the rt check `mp840_fresh_unavailable_slices_gated` (`:549-563`).
3. In `MP/_mp_hook_targets.lua` remove the entries for those four targets (`:33, 66-68`).
4. Delete `mark_seeded`, `_overlay_applied`, `apply_mirror_overlay` and the three `serialize_*_from_mirror` stubs with their comment banners. Keep `is_seeded` and `mod.is_unlocked`; above `mod.is_unlocked` add the comment `-- No seeding path exists: this returns true for every key until a seeding slice ships.`
5. Create `MP/_mp_reset_policy.lua` (pure) with `M.plan(argument)`. Change `/mp_reset` so that, unless the plan is `"wipe"`, it only echoes a preview (number of currency kinds, unlocks, inventory rows, Shilling balance) and the line `Run /mp_reset CONFIRM to wipe.`
6. Replace the `mod_description` text with: `Adds local daily quests that pay Silver Shillings in the modded realm, and lets you spend them on plain Shilling cosmetics at Lohner's Emporium. The optional Fresh starting state gives a separate starter inventory. Progress is stored locally. This mod does not provide XP, loot chests, Okri's Challenges, login rewards or the crafting bench.` Change the `start_level_35_unlocked` label to `Level 35, everything unlocked (not available yet)`.
7. In root `CLAUDE.md` and `README.md` change the `modded_progression` row purpose to the same scope and remove "Sibling API consumed by CWV + cosmetics_tweaker".

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` passes; `git grep -n "apply_mirror_overlay\|serialize_.*_from_mirror\|mark_seeded\|_with_eac_off_unless_fresh" -- modded_progression/scripts` prints nothing; `git grep -n 'mod:hook("AchievementManager"\|mod:hook("LevelEndViewBase"' -- modded_progression/scripts` prints nothing; `pwsh -NoProfile -File qa/check_rt_textual_invariants.ps1` passes (the pinned mp lines at `qa/rt_textual_invariants.psd1:559-560` are untouched).
- RIG: arena `keep`, `mp` loaded: `T.expect_rt("mp", "mp573_quest_surface_is_owned_and_backend_free")` and `T.expect_rt("mp", "mp577_backend_free_emporium_purchase")`. Script `qa/runtime/mp/issue_mp_reset_needs_confirm.lua`: read `get_mod("mp").get_currency("SM")`, `get_mod("mp").credit("SM", 5)`, `T.cmd("mp_reset")`, assert the balance is the credited value, then `get_mod("mp").spend("SM", 5)`.
- Evidence class: U closes #1671 (`qa/lua/tests/test_mp_hook_targets_resolve.lua` passes with the reduced target list). #1684 and #1693 advance: the inert brackets are gone; local login rewards stay unbuilt.

**Guardrails.** Do not remove `mod.with_eac_off`, `mod.is_modded_realm`, `mod.is_eac_window` or the `eac_*` rt checks: other mods call them through `_lib_modded_realm_authority.lua`. Do not change the two `_with_eac_off` delegates passed to the daily UI adapter (`MP/modded_progression.lua:1261-1272`). Do not edit `modded_progression/itemV2.cfg` (Workshop text is owner-dictated, OD-CIM-07). Do not remove the `level_35_unlocked` dropdown value (a saved setting may hold it).

**Stop and escalate if.** Another test pins one of the deleted lines (list it; update it only if it asserts the presence of text, not behaviour); removing a hook changes a result in the daily UI or Emporium host tests.

---

### WP-CIM-09 Write mp's current plan and build the next slices

| Field | Value |
|---|---|
| Priority | P2 |
| Size | L (one slice per session; the order is fixed below) |
| Agent | strong (each slice is a new local transaction beside the live account mirror and needs judgment about isolation) |
| Depends on | WP-CIM-08, WP-CIM-01 |
| Issues | advances #840, #573, #577, #1692; #607 stays blocked |
| Source | A5 section 3.2 (planned versus built) |
| Streams | `modded_progression/` |

**Goal.** `modded_progression/PLAN.md` states one current plan with a slice table, and each slice that is built ships with a host test written first and a rig case.

**Context.** Built today: local dailies and a Silver Shilling ledger (`MP/mp_dailies.lua`), plain-Shilling Emporium purchases (`MP/modded_progression.lua:1056-1114`), and the Fresh profile's items and loadouts slice (22 routed methods, `MP/_mp_fresh_profile_runtime.lua:556-577`). Not built: mission XP and levels, loot chests, Okri's Challenges, login rewards, vanilla-cost crafting, weekly quests. The original design (clear the EAC flag at UI gates, overlay the mirror) cannot work on 6.13 and must not be revived: never clear `read_only_backend`, and a Fresh slice never writes the native mirror (`modded_progression/PLAN.md:44-52, 105-112`). Loot contents are rolled by CloudScript (`VT2SRC/scripts/managers/backend_playfab/backend_interface_loot_playfab.lua:28-46`, cited from PLAN.md, [unverified by this author]), so chests cannot be reproduced from client source. Mission XP is computed in client Lua (`VT2SRC/scripts/entity_system/systems/mission/rewards.lua:59-99`, `Rewards._mission_results`), hero XP is read through `hero_attributes:get(hero, "experience")` (`VT2SRC/scripts/settings/experience_settings.lua:119-123`), and the backend manager has a talents override route (`VT2SRC/scripts/managers/backend_playfab/backend_manager_playfab.lua:343-371`).

**Steps.**
1. Rewrite `modded_progression/PLAN.md` as a current document: scope, the 6.13 constraints, and the slice table below. Move every paragraph marked HISTORICAL to a final appendix without editing it.
2. Slice table (scope per OD-CIM-04). Build in this order; it is fine to stop after any slice.

   | # | Slice | Test to write first | Rig case |
   |---|---|---|---|
   | 1 | Fresh XP and levels: profile field `experience[hero]`; a mission-end adapter computes XP with the vanilla client math and adds it to the profile; `hero_attributes:get(hero, "experience")` is served from the profile only while the Fresh route is active | `qa/lua/tests/test_mp_fresh_xp.lua`: award on win and on loss from a fixture `mission_results`; level thresholds from `ExperienceSettings`; no write when the route is inactive; copy-on-write persistence | arena `mission:<any>`: end the level; assert profile XP rose and the raw `mirror._read_only_data[hero .. "_experience"]` did not change |
   | 2 | Fresh talents: route the talents interface to the profile through `add_talents_interface_override` | `qa/lua/tests/test_mp_fresh_talents.lua`: set and read per career and loadout; the level gate uses the profile level; official talents untouched | arena `keep`: pick a talent; assert the profile changed and `mirror._career_data[career][i].talents` did not |
   | 3 | Weekly quests on the daily model (local roster, UTC week, Shilling reward) | extend `qa/lua/tests/test_mp_dailies.lua` with week rollover and claim-once | arena `keep`: `Managers.backend:get_interface("quests"):get_quests().weekly` holds only rows whose name starts with `mp_` |
   | 4 | Fresh currency and store: Shilling balance and Emporium ownership served from the profile | extend `qa/lua/tests/test_mp_emporium_purchase.lua` | arena `keep`, two boots: purchase, restart, ownership persists; no request enqueued during the purchase |

3. For each slice: write the pure state module and its test, then the runtime adapter, then one rt check that reads live state, then the rig case. Reuse the copy-on-write pattern of `MP/_mp_fresh_profile_state.lua` and the routing predicate of `MP/_mp_fresh_profile_runtime.lua:236-256`.
4. Keep these closed and say so in PLAN.md: loot chests (#607), login and calendar rewards (#1684), Okri's Challenge tracking, vanilla-cost crafting, Versus and event currencies.
5. After slice 2, extend the in-game description from WP-CIM-08 to mention levels and talents for the Fresh state only.

**Acceptance (machine, no human).**
- OFFLINE: for each slice the named test exists, fails before the runtime code and passes after; `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` passes.
- RIG: the case in the table passes, and in the same boot a wrapper around `enqueue` on the live request queue (`VT2SRC/scripts/managers/backend_playfab/playfab_request_queue.lua:25`) records no request caused by the slice (`generateEndOfLevelLoot`, any `crafting*` name, or `updateHeroAttributes` carrying changed talents).
- Evidence class: U plus R per slice. #840 advances per slice and closes when slices 1, 2 and 4 pass. #573 and #577 close on their existing checks plus a restart case in the verification packs, not on this card.

**Guardrails.** No approximated loot tables. No writes to `mirror._career_data`, `mirror._read_only_data` or `mirror._inventory_items` from a Fresh slice. No new hooks on `BackendInterfaceItemPlayfab` beyond the 22 routed methods. Do not change the default `starting_state`.

**Stop and escalate if.** A slice needs a value only the server knows; a routed read has a consumer that bypasses the interface and reads the mirror directly (list the consumer with its `VT2SRC` path and line); the owner answers OD-CIM-04 differently.

---

### WP-CIM-10 Settle Career Tweaker's scope and make its catalog checkable

| Field | Value |
|---|---|
| Priority | P2 |
| Size | L (split: 10a steps 1-3 archive and purpose, 10b steps 4-6 checks, 10c step 7 conversion) |
| Agent | strong (deciding which closure rows can become data means reading each closure) |
| Depends on | WP-CIM-05 |
| Issues | #447, #472, #473, #999, #367, #699, #936, #1686 gain machine checks (R); #153, #221, #440 unchanged |
| Source | A5-F13; A5 sections 3.3 and 3.4 |
| Streams | `career_tweaker/` (single tree) |

**Goal.** The shipped tree contains only what Career Tweaker loads, its stated purpose matches that, and every catalog row is covered by a test or a rig case.

**Context.** The mod is documented as "Talent/ability swapping", but `CRT/_crt_talent_swap.lua` (181 lines) is deliberately never loaded and its API fields are set to nil (`CRT/career_tweaker.lua:529-538`); the rt check `public_beta_talent_swaps_disabled` asserts that. Saved `talent_swap_*` values are left untouched. The retired Big Rebalance leaves a 405-line commented block (`CRT/career_tweaker_data.lua:63-467`) and about 329 localization lines. What ships is a catalog of 75 reworks over 18 of 20 careers (none for `bw_scholar` or `we_thornsister`): 12 rows are pure data (`patches = { { buff =, field =, value = } }`), 51 carry `custom_apply` / `custom_restore` closures, 3 come from a builder, 9 are empty owner rows for hook-owned toggles (`CRT/_crt_balance_catalog_early.lua:27-90`, composed by `CRT/_crt_balance_catalog.lua`). All rows go through one apply/restore engine in `CRT/career_tweaker_balance.lua`.

**Steps.**
1. Default per OD-CIM-06, remove swapping from the shipped tree: move `CRT/_crt_talent_swap.lua` to `_archive/career_tweaker_talent_swap/`, delete the `talent_swap_*` localization keys (`CRT/career_tweaker_localization.lua:49` onward), keep the entry lines `CRT/career_tweaker.lua:529-538` and the rt check.
2. Read `qa/check_retired_big_rebalance.ps1` and `qa/lua/tests/test_crt_retired_big_rebalance.lua`. Move the commented block `CRT/career_tweaker_data.lua:63-467` and the `cbr_*` localization entries to `_archive/career_tweaker_big_rebalance/` only if both checks still pass afterwards; otherwise leave them and record which check requires them.
3. Change the purpose text in root `CLAUDE.md`, `README.md` and the mod's `mod_description` to: `Toggleable talent and passive reworks, family presets, armor and overcharge options, hero level override.`
4. Add `qa/lua/tests/test_crt_catalog_targets.lua` (register it). With `H.test_if` on the decompile being present (pattern of `qa/lua/tests/test_cim_ranalds_game_keys_1696.lua:104-145`), build the catalog with a stub context (see `qa/lua/tests/test_crt_balance_split.lua` for the loader) and, for every `patches` row, assert that the text `<buff> = {` or `["<buff>"] = {` occurs in at least one `.lua` file under `VT2SRC/scripts`, or that `<buff>` is listed in `_CRT_BUFF_NAMES` (`CRT/career_tweaker_balance.lua:41-76`). Print the number of rows checked.
5. Add `qa/lua/tests/test_crt_apply_restore_roundtrip.lua` (register it): for every pure-data row, build a fake `BuffTemplates` holding the target buff with a sentinel value, apply, assert the field equals the row value, restore, assert deep equality with the starting table.
6. Add the rig script `qa/runtime/crt/rework_patch_rows.lua`, arena `keep`: for each pure-data row id, read the field, `T.set("crt", id, true)`, assert `rawget(BuffTemplates, buff).buffs[1][field] == value`, `T.set("crt", id, false)`, assert the value read first. `T.note` the row count. For closure rows assert the existing named checks with `T.expect_rt("crt", ...)`: `issue473_dance_of_blades_contract`, `issue447_flagellation_contract`, `issue472_focused_spirit_contract`, `issue999_feel_nothing_refresh`, `issue366_ale_independent_stack_decay`, `issue367_ale_one_second_drink`, `issue619_foot_knight_contract`, `issue1686_buff_icons_in_atlas`, `crt_tourney_leaf_catalog_936`.
7. Conversion, one row kind at a time: where a closure only rewrites `Talents[hero][id].description_values[n].value` and restores it (the shape of `_build_stat_buff_rework`, `CRT/_crt_balance_catalog_early.lua:27-58`), express it as a data field `tooltip = { talent =, index =, value = }` handled once by the engine, and add the row to the round-trip test. Record the closure-row count before and after; it may only go down.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` passes; `pwsh -NoProfile -File qa/check_retired_big_rebalance.ps1` passes; `git grep -n "talent_swap_" -- career_tweaker/scripts` prints only comment lines in `career_tweaker.lua`; the two new tests print the number of rows they checked.
- RIG: `qa/runtime/crt/rework_patch_rows.lua` passes for every pure-data row and the listed `T.expect_rt` checks pass.
- Evidence class: R gives machine evidence for #447, #472, #473, #999, #367, #936, #1686 at the level "template state changed and was restored". Any part of those issues about feel, animation or how an icon looks stays class V. #699: icon presence is R, appearance is V. #728 needs two clients (C).

**Guardrails.** Do not write new reworks, including for the two uncovered careers. Do not rename or reorder `_CRT_BUFF_NAMES`: its order fixes cross-peer network ids. Do not delete saved-setting ids. Do not remove the `CareerExtension.current_ability_cooldown` guard (`CRT/career_tweaker.lua:758-762`). Do not edit `_lib_peer_parity.lua` or `_lib_wire_catalog.lua` (shared libraries).

**Stop and escalate if.** The owner answers OD-CIM-06 with "revive" (then skip step 1 and write a spec first: allowed swap pairs, how the spawned `CareerExtension` is rebuilt after a swap, and the nil-cooldown crash the guard at `CRT/career_tweaker.lua:739-762` describes); the Big Rebalance gate requires the commented block to stay.

---

### WP-CIM-11 Delete cim's dormant loadout-persistence path

| Field | Value |
|---|---|
| Priority | P2 (dead hooks on the equip path and a regression check that fails in the field) |
| Size | M |
| Agent | any |
| Depends on | WP-CIM-01, WP-CIM-03 (same files; land them first) |
| Issues | none; removes the failing check quoted in the body of #1654 |
| Source | A5-F12 |
| Streams | both trees |

**Goal.** cim no longer installs loadout capture, restore or migration code that is switched off, and its suite has no check for that path.

**Context.** `mod:set("persist_modded_loadouts", false, false)` forces the feature off at every load (`CIMD/_cim_loadout_wire_owner.lua:76`), and the owner's header calls the path dormant (`CIMD/_cim_modded_loadout_owner.lua:21-26`). It still installs a `hook_safe` on `BackendInterfaceItemPlayfab.set_loadout_item` (`:905`), a table hook on `BackendUtils.set_loadout_item` (`:930`), the commands `cim_restore_loadout` (`:940`) and `cim_dump_loadout` (`:973`), a per-frame install call (`CIMD/crafting_in_modded_dev.lua:1181`) and a restore timer on every state change that only logs "skipped" (`:1157-1169, 1190-1199`). Its rt check `modded_loadout_round_trip_save_then_clear` failed in a tester session (issue #1654 body). Live code in the same file that must stay: `_auto_equip_slot_type` and `_auto_equip_crafted_weapon` (`:499-578`), `_snapshot_exact_loadout`, `_write_exact_loadout_item`, `_finalize_exact_loadout` (`:596-676`), the command `cim_craft_standard` (`:964`), and `mod._cim_register_restore_callback` (`:398-405`), which cosmetics_tweaker calls and requires (`cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_glow_cim_bridge.lua:151-158`, `_cos_runtime_checks.lua:965`).

**Steps.**
1. In `qa/lua/tests/test_cim_modded_loadout_owner.lua` delete the cases that exercise capture, restore, migration and purge; keep and adapt the cases for auto-equip and the three exact-loadout functions; add a case asserting the installer registers no hook, exactly one command (`cim_craft_standard`), and that `mod._cim_register_restore_callback(function() end)` returns `true`. Run: the new case fails.
2. In `CIMD/_cim_modded_loadout_owner.lua` delete: the `_modded_loadout` store with its save, load and migration (`_career_value_is_flat`, `_migrate_modded_loadout`), the stale purge, both capture hooks, the body of `_restore_modded_loadout`, `_reequip_live_avatar` if no remaining function calls it, and the two commands. Keep `mod._cim_register_restore_callback` storing the function and returning `true`. In this step keep returning no-op functions for `restore_modded_loadout`, `install_backendutils_capture`, `modded_loadout_save`, `modded_loadout_load`, `get_modded_loadout`, `set_modded_loadout` so the entry still loads.
3. In the entry remove the timer and its two uses, the per-frame `_install_backendutils_capture()` call, the forward declaration and binding of `_restore_modded_loadout`, and the `get_restore_modded_loadout` getter passed to the forge state owner. Then remove the no-op exports from step 2 and the matching fields of `_regression_context`.
4. In `CIMD/_cim_loadout_wire_owner.lua` remove `mod:set("persist_modded_loadouts", false, false)`, `persist_loadouts_enabled` and its export. Leave the rest of that file unchanged (`qa/rt_textual_invariants.psd1:660-661` pin the rarity functions).
5. Delete each rt check whose body calls a function removed above: start from `modded_loadout_round_trip_save_then_clear`, `modded_loadout_has_no_stale_entries`, `backendutils_capture_installed`, `persist_loadouts_gate_off_is_passthrough`, `restore_after_playfab_inventory_populated`, and the helper `_rt_with_loadout_sandbox` (`CIMD/_cim_regression_checks.lua:304-358`) when no remaining check uses it. Read each body before deleting; keep any check that tests live code.
6. Apply to the stable tree.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` passes; `git grep -n "persist_modded_loadouts\|cim_restore_loadout" -- crafting_in_modded_dev/scripts crafting_in_modded/scripts` prints nothing; `git grep -n 'set_loadout_item"' -- crafting_in_modded_dev/scripts crafting_in_modded/scripts` shows no `mod:hook` or `mod:hook_safe` line; `pwsh -NoProfile -File qa/check_rt_textual_invariants.ps1` passes.
- RIG: arena `keep`: craft one weapon through `commit_craft`, call `get_mod("cim_dev")._cim_auto_equip_crafted_weapon(career, "slot_melee", bid)`, assert it returns true and `BackendUtils.get_loadout_item_id(career, "slot_melee") == bid`; assert `get_mod("cim_dev")._cim_rt_last` (from WP-CIM-05, when landed) has no result named `modded_loadout_round_trip_save_then_clear`. Cleanup re-equips the original id and deletes the craft.
- Evidence class: U and R. No issue closes.

**Guardrails.** Do not delete the saved setting `modded_loadout` from players' settings. Do not edit gui_tweaker, which owns modded loadout persistence now. Keep `mod._cim_auto_equip_crafted_weapon` and the three `mod._cim_*_exact_loadout*` functions with unchanged names and returns (the Ranald importer and an rt check use them). Do not start invoking the registered restore callbacks: today they never run, because `_restore_modded_loadout` returns at `:688-691` before reaching them at `:800-801`; whether cosmetics needs them is a question for the cosmetics track.

**Stop and escalate if.** A repo-wide grep finds another caller of `mod._cim_clear_modded_loadout_for_bid`, `mod._cim_clear_modded_loadout_for_bids` or any other removed `mod._cim_*` field (keep that field as a no-op and name the caller).

---

## Owner decisions

The owner is unavailable. Agents proceed on the default and name the decision id in their report.

| Id | Question | Conservative default to assume |
|---|---|---|
| OD-CIM-01 | Where does official-loadout protection live: only in Tweaker: GUI, or in every mod that creates items? | In every mod that creates backend ids, through `_lib_official_loadout_guard.lua`. Tweaker: GUI's store stays an optional extra. |
| OD-CIM-02 | Without Tweaker: GUI, should a crafted item stay equipped after a restart? | No. It stays equipped for the session only. Account safety comes first. |
| OD-CIM-03 | Should crafted items move automatically between the dev and stable mods? | No. Only through the explicit `cim_import_other_stream CONFIRM` command, additive, never overwriting. |
| OD-CIM-04 | Is Modded Progression still meant to become a full local economy? | No expansion beyond what client source can back: dailies, Shilling Emporium, and the Fresh slices for XP, talents, weekly quests and store. Loot chests, login rewards, challenge tracking and vanilla-cost crafting stay unbuilt. |
| OD-CIM-05 | Keep suppressing backend commits while a forge is open? | Keep it for commits without a callback. Always let a commit with a callback through. |
| OD-CIM-06 | Career Tweaker talent/ability swapping: revive or remove? | Remove from the shipped tree (archive the module, drop its strings), keep saved setting ids reserved, change the stated purpose. |
| OD-CIM-07 | May agents rewrite Modded Progression's Workshop description (`itemV2.cfg`), which promises more than the mod does? | No. Change only in-game text and repo docs. The item is private; record the mismatch for the owner. |
| OD-CIM-08 | May the Community Builds browser (it queries a third party's database) be promoted to the public mod? | No. It stays in `cim_dev` only and gains no new request types. |
| OD-CIM-09 | At restore, if a saved craft does not match what the engine parses, hide it or keep it? | Keep it in the inventory and print the differing field. Never delete a saved record automatically. |
