# Track COS: cosmetics_tweaker, dynamic_cosmetic_portraits, character_dialogue

Source audit: `docs/audits/2026-11-13_FORMAL_AUDIT/evidence/A3.md` (repo HEAD `592253d1`, decompile `93dea911`, game 6.13.0). Line numbers below are from that HEAD: if a line has moved, match by the quoted identifier.

## Family brief

- `cosmetics_tweaker/` (public Workshop item, single tree, no dev twin): illusions, shields and offhands, hats, glow, Loremaster's Armoury (LA) bridge, peer sync. Entry `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua` is a composition root that installs about 100 `_cos_*.lua` / `_la_*.lua` modules. In-game suite: `/cos_regression_test`.
- `dynamic_cosmetic_portraits/` (DCP, friends-only, single tree): Kruber Mercenary portraits only. Entry `.../dynamic_cosmetic_portraits.lua`. Suite: `/dcp_regression_test`. New portrait assets come only from `tools/add_portrait.ps1`.
- `character_dialogue/` (friends-only, single tree): 34,332 of 35,643 Lua lines are a generated catalogue. Logic is `character_dialogue.lua` plus five `_cd_*.lua` files. Its two hooks act only when the local player hosts. Suite: `/cd_regression_test`.
- Host tests: `qa/lua/tests/test_*.lua`, each registered in the `suites` list of `qa/lua/run.lua`. Run all with `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1`.

Five traps:
1. Tests pin source text. 50 of 65 `test_cos_*` files and `qa/rt_textual_invariants.psd1` assert exact strings and counts in production files. Moving or renaming a line can fail them. Update the matching test in the same change. Never delete a test to get green.
2. `BackendUtils.get_item_units` is hooked once (`_cos_equipment_assembly.lua:148`) and decides its answer from flags set by other hooks (`_in_create_equipment`, the husk wield context, the open customization screen, `mod._cos_score_hat_swap`). Calling it, or reordering those hooks, without the flags gives a different answer.
3. Wire safety. Custom skin keys and LA clone ids must never reach vanilla `NetworkLookup` encodes. Four encode sites are guarded (`_cos_wire.lua:128, 142, 158`, `_cos_la_loadout_safety.lua:318`). `COS_RPC_SCHEMA = 2` (`cosmetics_tweaker.lua:119`): add optional fields only, never bump it.
4. The entry file is near Lua's 200-local limit and under a file-size ceiling (`qa/check_file_sizes.ps1`). Install order is load-bearing. Put new code in a module and pass it inside an existing `.install(mod, { ... })` table. Do not add top-level locals.
5. Third-party coupling. LA may be absent. MoreItemsLibrary and Material-Hijack are embedded here and other mods reach them through a replaced global `get_mod`. Do not rename `_G._cos_mil_embed_owner` or `_G._cos_mh_embed_owner`. Diagnostics must use engine `printf` (`mod:info` is invisible to testers).

---

### WP-COS-01 Validate peer cosmetic payload fields before storing or applying

| Field | Value |
|---|---|
| Priority | P0 (crash class reachable by any lobby peer) |
| Size | M |
| Agent | any |
| Depends on | none |
| Issues | advances 416 (no closure: 416 is class C) |
| Source | A3-F04 |
| Streams | `cosmetics_tweaker/` only (single tree) |

**Goal.** A `cos_la_apply_req` or `cos_la_apply` payload with a wrong type, an unknown `hand_field`, or a unit outside the receiver's own offhand pool changes no store and is not rebroadcast.

**Context.** The host handler stores and rebroadcasts `payload.offhand_unit` and `payload.hand_field` as received (`_cos_la_sync_transport.lua:748-756`). The client handler stores them too (`:1053-1057`). `mod._store_offhand_mesh_recv` (`:571`) uses `hand_field` as a table key and treats any non-string unit as CLEAR. On the next husk spawn the receiver writes `result[hand_field] = unit_path` into the table vanilla returns from `BackendUtils.get_item_units` (`_cos_equipment_assembly.lua:386-408`; LA paths write at `:295` and `:317`). The allow-list `mod._dual_offhand_unit_allowed` returns `true` for every non-dual item type without looking at the hand or the unit (`_cos_offhand_state_runtime.lua:156-160`). The only other gate is unit residency (`_cos_offhand_catalog.lua:265-271`). The only valid hand keys of that table are `left_hand_unit` and `right_hand_unit` (`Vermintide-2-Source-Code/scripts/managers/backend/backend_utils.lua:144-146`). `""` is the legitimate CLEAR value for `offhand_unit` (`_cos_offhand_picker.lua:826-828`). Wire kinds in use are `hat`, `armor`, `offhand`, `illusion`.

**Steps.**
1. Add tests first to `qa/lua/tests/test_cos_la_sync_transport.lua`, using its existing `build()` fixture and `handlers[...]` table (`:187-254`). Host cases (`build({ is_server = true, host_peer = "local-peer" })`, call `handlers["cos_la_apply_req"]("peerA", 2, payload)`): (a) `{ slot = "tpl", kind = "offhand", offhand_unit = "units/x", hand_field = "material_settings_name" }`; (b) same with `hand_field = 42`; (c) `offhand_unit = {}`; (d) `slot = 7`; (e) `kind = "bogus"` with `armoury_key = "KruberPure"` (a key the fixture bridge knows). For each assert `mod._offhand_mesh_by_peer.peerA == nil`, `la_equips_by_peer.peerA == nil` and `#sends == 0`. Client cases: call `handlers["cos_la_apply"]` from the host peer with the same bad fields plus `wearer_peer_id = 9`, assert the same. Positive controls: a valid `left_hand_unit` payload and a valid `""` CLEAR still store and rebroadcast. Run the suite: the negative cases must fail on unfixed code.
2. Create `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_payload_policy.lua`, pure, no engine globals. Export `M.HANDS = { left_hand_unit = true, right_hand_unit = true }`, `M.KINDS = { hat = true, armor = true, offhand = true, illusion = true }`, and `M.clean(payload, from_host)` returning `clean, reason`. Rules: payload is a table; `slot` is a string of 1 to 128 bytes with no control characters; `hand_field` is nil or in `M.HANDS`; `offhand_unit` is nil or a string of at most 200 bytes with no control characters; `kind` is in `M.KINDS` whenever `armoury_key` or `revert` is present; `armoury_key`, `vanilla_key`, `wearer_career` are nil or strings of at most 128 bytes; `revert` is nil or `true`; when `from_host` is true `wearer_peer_id` is a non-empty string. Return a new table holding only these fields.
3. In `_cos_la_sync_transport.lua` load the policy with `mod:dofile` at the top of `LaSyncTransport.install`. In both handlers, right after the schema check, replace `payload` with `Policy.clean(payload, <is client handler>)`. On rejection print one bounded line (`[cos:416] payload rejected peer=%s reason=%s`, at most 16 per session) and return.
4. In `_cos_offhand_state_runtime.lua:156` change `mod._dual_offhand_unit_allowed(item_type, hand_field, unit_path)`: return false unless `hand_field` is `left_hand_unit` or `right_hand_unit`; for non-dual item types require `unit_path` to equal `opt.unit` or `opt.intended_unit` of some row in `_get_offhand_options(item_type)[hand_field]` (`_get_offhand_options` is defined at `:83` in the same file); keep the existing dual branch.
5. In `_cos_equipment_assembly.lua` at `:290` and `:315` skip the write when `hand_field` is not one of the two valid keys.
6. Update the host test that pins the open allow-list: `qa/lua/tests/test_cos_offhand_runtime_owners.lua:121` expects `mod._dual_offhand_unit_allowed("ordinary", "right_hand_unit", "x") == true`. Give the fixture an `ordinary` pool with one unit and assert: unit in the pool for the right hand passes, unit not in the pool fails, a hand that is not one of the two valid keys fails. Keep the three dual assertions at `:122-124` unchanged.
7. Register an in-game check `issue416_payload_policy` in `_cos_runtime_checks.lua` with `_rt_register`: it calls the policy with the five bad payloads and one good one and returns a string on any wrong verdict.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0, with the new cases present. `pwsh -NoProfile -File qa/run_all.ps1 -Quick` reports no ERROR.
- RIG: suite sweep in arena `keep`: `T.expect_rt("cosmetics_tweaker", "issue416_payload_policy")` PASS.
- Class U closes this defect. Issue 416 stays open (class C).

**Guardrails.** Do not bump `COS_RPC_SCHEMA`. Do not change what a correct sender sends. Do not validate `slot` against a fixed list: for weapons it carries a weapon template name, not a slot name. Do not touch the `revert` semantics beyond field validation.

**Stop and escalate if.** A positive control fails after step 4 because a legitimate sender unit is missing from the receiver pool for the same item type: write down the item type and unit and stop (pool parity is a separate defect).

---

### WP-COS-02 Report vacuous in-game regression checks as SKIP, not PASS

| Field | Value |
|---|---|
| Priority | P1 (the rig records every check as an assertion) |
| Size | M |
| Agent | any |
| Depends on | none |
| Issues | none |
| Source | A3-F12 |
| Streams | `cosmetics_tweaker/`, `dynamic_cosmetic_portraits/`, `character_dialogue/` (single trees) |

**Goal.** A check that could not inspect its subject reports SKIP with a reason, and every mod in this family prints one `PASS:` / `FAIL:` / `SKIP:` line per named check.

**Context.** The rig runs each mod's regression command and records one assertion per echoed check line. DCP checks return nil (counted PASS) when source files are unreadable, which the file says is always true in the retail game (`dynamic_cosmetic_portraits.lua:134-143`; returns at `:197, :785, :788, :829, :834, :836, :859, :863, :1369, :1372`). Cosmetics checks return nil on absent context at `_cos_runtime_checks.lua:393, :714, :1747, :1770, :1938, :2001, :2018`. The cosmetics runner has no skip verdict for a returned value: any string is FAIL, nil is PASS, SKIP exists only through the `precondition` option (`_cos_command_owner.lua:43-75`). The DCP runner already treats a returned `"skip: ..."` string as SKIP (`dynamic_cosmetic_portraits.lua:154-172`). `character_dialogue` has one command that prints a single aggregate `failures=%d` line (`character_dialogue.lua:610-661`), so no check can be named.

**Steps.**
1. Tests first. In `qa/lua/tests/test_dcp_entry_portrait_flow.lua` (it runs the real entry in a sandbox and exposes `f.commands` and `f.logs`): run `f.commands.dcp_regression_test()` with `io` absent from the sandbox and assert that the lines for `skin_map_overrides_hat_map`, `hud_alpha_mask_conformance_pipeline`, `portrait_materials_use_visible_shader_526` and `portrait_override_player_scoped` start with `  SKIP:`. Add a cosmetics runner test (new file `qa/lua/tests/test_cos_command_owner.lua`, registered in `qa/lua/run.lua`): load `_cos_command_owner.lua` with a fake `mod`, register three checks returning nil, `"boom"`, `"skip: no context"`, run the command, assert one PASS, one FAIL, one SKIP line. Add to `qa/lua/tests/test_character_dialogue.lua`: the regression command echoes at least six lines matching `^  PASS: ` with distinct names.
2. `_cos_command_owner.lua`: in the runner, after `pcall(check.fn)`, treat `ok and type(err) == "string" and err:sub(1, 5) == "skip:"` as SKIP (same echo format as the precondition SKIP). Print each verdict with `printf("[cos-regression] %s %s%s", verdict, name, detail)` in addition to the existing echo.
3. `_cos_runtime_checks.lua`: at the seven lines listed above return `"skip: <reason>"` instead of nil, using the reason already in the trailing comment.
4. `dynamic_cosmetic_portraits.lua`: at the ten lines listed above, when the return sits inside an `_rt_register` body, return `_rt_note_skip("<check name>", "<reason>")` (helper at `:109`). In `portrait_materials_use_visible_shader_526` also return the skip verdict when none of the material files could be read. When a check has a runtime half that already ran, say so in the reason (for example `source half not readable, runtime half passed`).
5. `character_dialogue.lua:610-661`: split the command body into named checks held in a local list `{ name, fn }` (suggested names: `override_state_parsing`, `catalogue_unique_events`, `catalogue_durations`, `browser_group_totals`, `browser_page_cap`, `morris_package_mapping`, `isolation_owner_tokens`). Echo `  PASS: <name>` or `  FAIL: <name> -- <message>` per check, then keep the existing summary line.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0 with the new tests. `git grep -n "vacuous pass" cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_runtime_checks.lua` returns no line that still ends in a bare `return nil`.
- RIG: arena `keep` suite sweep lists SKIP (not PASS) for the four DCP source-text checks and shows named lines for `character_dialogue`.
- Class U closes this work package.

**Guardrails.** Do not rename existing check names or commands (`cos_regression_test`, `dcp_regression_test`, `cd_regression_test`). Do not change the echo line prefixes `  PASS: `, `  FAIL: `, `  SKIP: `. Do not delete a check. `qa/rt_textual_invariants.psd1` holds needles for DCP source lines: keep those lines.

**Stop and escalate if.** A check converted to SKIP is listed as a required PASS in an open issue's live test card: record the issue number and the check name, do not edit the card.

---

### WP-COS-03 Fix dialogue line overrides always selecting line 1

| Field | Value |
|---|---|
| Priority | P1 |
| Size | S |
| Agent | any |
| Depends on | none |
| Issues | advances 605 |
| Source | A3-F01 |
| Streams | `character_dialogue/` only (single tree) |

**Goal.** With an override on a dialogue group, a disabled line is never selected and every eligible line can be selected.

**Context.** The hook draws indices with `DialogueQueries.get_dialogue_event_index(dialogue, true)` (`character_dialogue.lua:390`) and ends with `return index or 1` (`:396`). In vanilla, `wrap_around = true` only resets the counter and never builds the shuffle table (`Vermintide-2-Source-Code/scripts/entity_system/systems/dialogues/dialogue_queries.lua:85-107`). Every generated group starts with `randomize_indexes_n = 0, randomize_indexes = {}` (for example `Vermintide-2-Source-Code/dialogues/generated/bright_wizard_bell.lua:133, 147`) and is rebuilt per level (`.../dialogues/tag_query_loader.lua:64-78`). So on a group that has an override from session start every drawn index is nil, `Policy.choose_index` (`_cd_policy.lua`) returns nil, and the hook returns 1. Reproduced offline 200 of 200 times, including when line 1 is the disabled line (audit script `docs/audits/2026-11-13_FORMAL_AUDIT/evidence/scripts/A3_cd_fresh_group.lua.txt`). Existing tests pass because they inject a fake index source (`qa/lua/tests/test_character_dialogue.lua:26-48`). Vanilla reference loop: `dialogue_queries.lua:110-132`.

**Steps.**
1. Tests first, in `qa/lua/tests/test_character_dialogue.lua`. Add a test-local table `NativeShaped` with three functions that copy the control flow of vanilla `build_randomized_indexes` (unweighted branch), `get_dialogue_event_index` and a `filter_sound_event` that returns true. Add a helper `fresh()` returning `{ sound_events_n = 3, sound_events = { "a", "b", "c" }, randomize_indexes_n = 0, randomize_indexes = {} }`. Add tests that call the new `Policy.select_index` (step 2) 200 times on fresh groups: with `{ a = false }` the result is never 1 and both 2 and 3 occur; with `{ c = true }` and a filter that always returns false the result is always 3; with `{ a = false, b = false }` the result is always 3; with no usable line (`{ a = false, b = false, c = false }`) the result is nil. Add one `H.test_if` case that loads the real vanilla file from `os.getenv("VT2_DECOMPILE_ROOT") or (repo_root .. "/../Vermintide-2-Source-Code")` (strip the UTF-8 BOM, set `_G.DialogueSettings = { sound_event_default_length = 4.5 }` and `_G.TagQuery = { FilterOP = {} }` for the load, restore both afterwards) and repeats the first assertion. The tests must fail before step 2.
2. `_cd_policy.lua`: add `Policy.select_index(dialogue, overrides, queries, context, global_filters)`. Behaviour: first draw `queries.get_dialogue_event_index(dialogue)` (no wrap argument, so vanilla builds the shuffle); loop at most `dialogue.sound_events_n` times; for index `i` read `state = overrides[dialogue.sound_events[i]]`; accept when `state == true`, or when `state == nil` and `queries.filter_sound_event(dialogue, i, context, global_filters)`; otherwise remember the first index whose state is not `false` as fallback, draw the next with `queries.get_dialogue_event_index(dialogue, true)` and OR its second return into `wrapped`. After the loop, if `wrapped` call `queries.build_randomized_indexes(dialogue)`. Return the accepted index, else the fallback, else nil. Keep `Policy.choose_index` for the existing tests.
3. `character_dialogue.lua:388-397`: replace the hook body with: if `not Policy.has_override(dialogue, overrides)` return `func(dialogue, context, global_filters)`; otherwise `local index = Policy.select_index(dialogue, overrides, DialogueQueries, context, global_filters)`; return `index` when it is a number, else return `func(dialogue, context, global_filters)`.
4. Add the named check `override_selection_fresh_group` to `/cd_regression_test` (after WP-COS-02 it is a named check; before it, add to the failure counter): build a fresh three-line table, set a temporary local override table, call `Policy.select_index` with the live `DialogueQueries` 50 times, fail if the disabled index is returned.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0; the four new tests exist; the `H.test_if` case runs when the decompile is present and is reported as skipped otherwise.
- RIG: add `qa/runtime/character_dialogue/issue_605_line_override_selection.lua`, arena `keep` (solo, so the local player is the server). Steps: `T.require` that `Managers.state.entity:system("dialogue_system")._dialogues` has a group with `sound_events_n >= 3` and no `sound_event_filters` (`Vermintide-2-Source-Code/scripts/entity_system/systems/dialogues/dialogue_system.lua:100`); `T.cmd("cd_line", <first event of that group>, "disable")`; call `require("scripts/entity_system/systems/dialogues/dialogue_queries").get_filtered_dialogue_event_index(dialogue, { query_context = {}, global_context = {}, user_context = {}, user_memory = {}, faction_memory = {} }, {})` 100 times; `T.expect` that index 1 never returns and at least two distinct indices return; then `T.cmd("cd_line", <event>, "default")`.
- Class U closes the selection defect. 605 stays open (feature umbrella).

**Guardrails.** Do not change the `TagQueryDatabase.iterate_query` hook (`:399-412`). Do not copy decompiled source into the repo beyond the three short control-flow functions in the test. Selection runs only on the host (`dialogue_system.lua:957-959`): do not try to make it work for clients.

**Stop and escalate if.** The real-vanilla `H.test_if` case disagrees with the native-shaped case: the stand-in is wrong, fix the stand-in, do not weaken the assertion.

---

### WP-COS-04 Make swallowed husk wield errors machine-visible

| Field | Value |
|---|---|
| Priority | P1 |
| Size | S |
| Agent | any |
| Depends on | none (uses the `skip:` verdict if WP-COS-02 has landed) |
| Issues | none (supports triage of 233, 738) |
| Source | A3-F07 |
| Streams | `cosmetics_tweaker/` only (single tree) |

**Goal.** Every error swallowed by the remote-player wield hook is counted, logged once with a traceback, and fails a named regression check.

**Context.** `_cos_husk_wield_runtime.lua:179-185` wraps the whole remaining hook chain of `SimpleHuskInventoryExtension._wield_slot` in `pcall`, logs one line, and returns nil. `weapon_tweaker` (`_wt_transform_runtime.lua:355`) and `character_weapon_variants` (`_cwv_husk_path.lua:1376`) hook the same method, so their errors disappear here too. The existing test pins the swallow (`qa/lua/tests/test_cos_husk_wield_runtime.lua:141-160`, `H.equal(result, nil)`). Default for the open owner decision OD-COS-03: keep swallowing (no new crashes for public subscribers) but make it impossible to miss.

**Steps.**
1. Test first: extend the test at `qa/lua/tests/test_cos_husk_wield_runtime.lua:141`. After the planted error assert `f.owner.swallowed_errors() == 1`, assert a second planted error gives 2, and assert the captured `printf` output contains `[cos:husk-wield] SWALLOWED` exactly once per distinct message (give the fixture a `printf` stub that records lines).
2. `_cos_husk_wield_runtime.lua`: replace `pcall(func, ...)` at `:179` with `xpcall` and a handler that returns `tostring(err) .. "\n" .. debug.traceback()` (guard `debug` with `rawget(_G, "debug")`). Lua 5.1 `xpcall` takes no extra arguments: wrap the call in a closure. Keep `state.current = previous` as the first statement after the call.
3. On failure: increment `state.swallowed` (initialise to 0 where `state` is created at `:29`), and print with `state.printf` one line per distinct first line of the message, at most 8 per session: `[cos:husk-wield] SWALLOWED n=%d wearer=%s slot=%s err=%s`. Keep `return nil`.
4. In `publish_owner` (`:10-18`) add `owner.swallowed_errors = function() return state.swallowed or 0 end`.
5. Register an in-game check `husk_wield_no_swallowed_errors` in `_cos_runtime_checks.lua` with `_rt_register`: return `"skip: no remote player wield observed"` when no husk wield ran this session (add a `state.wields` counter next to `state.swallowed`), a failure string naming the count when `swallowed_errors() > 0`, nil otherwise.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0 with the extended test.
- RIG: solo arenas cannot create a remote player, so the check reports SKIP there. In the `coop` arena (later) add `host_forbid_log = { "[cos:husk-wield] SWALLOWED" }` to every cosmetics case and `T.expect_rt("cosmetics_tweaker", "husk_wield_no_swallowed_errors")`.
- Class U closes this work package. The behaviour under real remote players is class C.

**Guardrails.** Do not rethrow (OD-COS-03). Do not add a second hook on `SimpleHuskInventoryExtension._wield_slot`. Do not move the context assignment at `:103-109` or the restore.

**Stop and escalate if.** `xpcall` is unavailable or wrapped in the game environment (the retail VM is not the vendored Lua): keep `pcall`, drop the traceback, and note it.

---

### WP-COS-05 Repair and pin the embedded MoreItemsLibrary provider

| Field | Value |
|---|---|
| Priority | P1 |
| Size | M |
| Agent | any |
| Depends on | none |
| Issues | none |
| Source | A3-F03, A3-F08 |
| Streams | `cosmetics_tweaker/` only (single tree). Do not edit `character_weapon_variants/` or `weapons_of_chaos/` |

**Goal.** The embedded MoreItemsLibrary retries its backend-mirror hook on every game-state change, announces who the provider is, and the global `get_mod` and VMF prototype wraps are covered by tests.

**Context.** `_la_prefix_embedded.lua:94-96` replaces `VMFMod.hook`, `hook_safe`, `hook_origin` for all mods (it drops LA's duplicate registrations) and `:117` replaces global `get_mod` so `get_mod("MoreItemsLibrary")` and `get_mod("Material-Hijack")` return the `cosmetics_tweaker` handle when the standalone mods are absent. `character_weapon_variants/.../_cwv_item_registration_owner.lua:674` and `weapons_of_chaos/.../_woc_relic_registration_owner.lua:449` rely on that lookup. `_moreitemslibrary_embedded.lua:393-399` wraps `mod.on_game_state_changed` to retry `hook_backend_mirror()` (`:227`), but the file loads at `cosmetics_tweaker.lua:45` and `LIFECYCLE.install` (`cosmetics_tweaker.lua:437`) later assigns `mod.on_game_state_changed` without chaining (`_cos_mod_lifecycle.lua:25`). The retry is dead. The only receipts use `mod:info` (`_moreitemslibrary_embedded.lua:61, 255`), which testers do not see. None of the three files is loaded by any host test. Moving the embeds out of cosmetics is owner decision OD-COS-02: default is to keep them here.

**Steps.**
1. Test first, in `qa/lua/tests/test_cos_mod_lifecycle.lua` (it already loads the module with `loadfile`): set `mod.on_game_state_changed = function(...) calls[#calls + 1] = { ... } end` before `Lifecycle.install(mod, deps)`; after install call `mod.on_game_state_changed("enter", "StateIngame")`; assert the earlier function ran exactly once with the same two arguments. Add a second case where the earlier function throws: the lifecycle body still runs.
2. `_cos_mod_lifecycle.lua`: at the top of `M.install`, before the assignment at `:25`, add `local previous = mod.on_game_state_changed`. As the first statement of the new handler call it under `pcall` when it is a function; on error print one `printf` line. Keep exactly one `mod.on_game_state_changed = function` assignment in the file (a test counts it).
3. `_moreitemslibrary_embedded.lua`: set `mod._cos_mil_provider = { state = "sibling" | "standalone" | "embedded", owner = <string> }` in the three branches (`:41`, `:55`, `:62`). After `backend_mirror_hooked = true` (`:254`) add `pcall(printf, "[cos:mil] backend mirror hooked provider=embedded owner=cosmetics_tweaker")`. Export `mod._cos_mil_mirror_hooked = function() return backend_mirror_hooked end`.
4. New host test `qa/lua/tests/test_cos_embedded_providers.lua` (register in `qa/lua/run.lua`). Load `_la_prefix_embedded.lua` with `loadfile` under saved and restored globals `VMFMod`, `get_mod`, `_cos_mil_embed_owner`, `_cos_mh_embed_owner`, `_cos_la_prefix_get_mod_wrapped`, and a fake cosmetics mod offering `info`, `warning`, `get`, `hook`. Assert: (a) a mod whose `get_name()` is not `"Loremasters-Armoury"` gets its `hook` call forwarded with the same four arguments and the original return value; (b) for a mod named `"Loremasters-Armoury"` the second registration of the same `(obj, method)` is dropped and the first is forwarded; (c) `get_mod("MoreItemsLibrary")` returns the standalone when it exists and is enabled, else the mod named by `_G._cos_mil_embed_owner`, and any other name is passed through; (d) loading the file twice does not wrap twice.
5. Register an in-game check `mil_provider_identity` in `_cos_runtime_checks.lua`: fail when `get_mod("MoreItemsLibrary")` is nil or lacks a function `add_mod_items_to_masterlist`; when `mod._cos_mil_provider.state == "embedded"` fail unless that handle is this mod and `mod._cos_mil_mirror_hooked()` is true; otherwise pass.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0 with the new tests. `tools/mod-lint/lint-mod.ps1` reports no duplicate hook for `cosmetics_tweaker`.
- RIG: arena `keep`, add `qa/runtime/cosmetics_tweaker/issue_0_mil_provider_identity.lua` (no issue number: use 0): `T.expect_rt("cosmetics_tweaker", "mil_provider_identity")`; `T.expect(type(get_mod("MoreItemsLibrary").add_mod_items_to_masterlist) == "function", ...)`; case field `host_expect_log = { "[cos:mil] backend mirror hooked" }` when the provider state is `embedded`.
- Class U closes the lifecycle defect; class R decides whether the mirror hook is actually installed.

**Guardrails.** Do not move, rename or delete the embeds. Do not add a second hook on `BackendInterfaceItemPlayfab.init` (`_moreitemslibrary_embedded.lua:378`). Do not change the `get_mod` resolution order. Do not touch the MIT licence block at the end of the file.

**Stop and escalate if.** The rig check fails with `mirror_hooked == false` in the keep: that confirms the items interface was created before the hook. Record the log and stop. Choosing a new install seam needs a strong agent.

---

### WP-COS-06 Record cosmetics appearance source-of-truth decisions

| Field | Value |
|---|---|
| Priority | P1 |
| Size | S |
| Agent | strong (must classify every reader of three stores as input, adapter or resolver logic) |
| Depends on | none |
| Issues | advances 660 |
| Source | A3-F02 |
| Streams | `docs/` and no code |

**Goal.** `docs/APPEARANCE_UNIFICATION_PLAN.md` has a section `W4 Cosmetics: offhand_shield_swaps` that fixes the design for WP-COS-07 to WP-COS-11 and lists every current reader and writer of the offhand stores.

**Context.** The repo already has the target architecture (descriptor, adapters, one reconciler, retained-state proof, family-at-a-time migration with deletion: `docs/APPEARANCE_UNIFICATION_PLAN.md` sections 2 and 3) and a pure library `tools/shared_lib/_lib_appearance_descriptor.lua` (`M.CELLS` at `:18-30`, `M.validate` at `:230`, `M.build` at `:377`). Cosmetics has not started: one hook on `BackendUtils.get_item_units` (`_cos_equipment_assembly.lua:148`, about 430 lines) picks the mesh for every surface from flags set elsewhere and from three stores: `_offhand_selection` (`cosmetics_tweaker.lua:616`), `_la_equips_by_peer` (`:829`), `mod._offhand_mesh_by_peer` (`:840`). The census counts 871 of 1,088 cosmetics pairs as unsupported (`docs/generated/APPEARANCE_CENSUS_GAPS.generated.md:28`). The audit did not read `docs/WEAPON_APPEARANCE_STANDARD.md` [unverified]: read it before writing.

**Steps.**
1. Read `docs/APPEARANCE_UNIFICATION_PLAN.md`, `docs/WEAPON_APPEARANCE_STANDARD.md`, and the header of `_cos_appearance_census.lua`.
2. Build the inventory with `git grep -n` over `cosmetics_tweaker/scripts/mods/cosmetics_tweaker` for: `_offhand_selection`, `offhand_selection`, `_la_equips_by_peer`, `la_equips_by_peer`, `_offhand_mesh_by_peer`, `get_saved_offhands`, `_in_create_equipment`, `get_current_husk_wield`, `get_active_customization_backend_id`, `_cos_score_hat_swap`. Drop comment lines. For each remaining hit record file, function, read or write, and which surface it serves.
3. Append the section to the plan with these decisions (they are the defaults: record them as decided):
   - D1. First family: `offhand_shield_swaps` (the census family name).
   - D2. One pure module `_cos_offhand_resolver.lua` answers "which unit per hand". No hook resolves units itself after migration.
   - D3. The resolver takes an explicit `context` with `surface` (a name from `M.CELLS`), `wearer_peer`, `career_name`, `item_type`, `template`, `backend_id`, `skin`, `base_units`, `in_live_equip`, `customization_backend_id`, `deus_yield`.
   - D4. The three stores stay, as inputs only. Adapters read them and pass rows in. Priority order inside the resolver equals today's order in the hook. Stage 1 changes no behaviour.
   - D5. Vanilla calls `get_item_units` with four fixed arguments, so call-scoped context cannot be passed as a parameter. It moves into one exception-safe context stack (WP-COS-08) instead of four separate flags.
   - D6. The resolver result is shaped so `M.validate` accepts it (`left_hand_unit`, `right_hand_unit` as `{ unit = ... }`, plus `fallback`). Bundling the descriptor library into cosmetics is deferred until all surfaces use the resolver.
   - D7. No wire change, no new hook, superseded branches are deleted in the same change as each surface.
   - D8. A census pair flips to `implemented` only with rig evidence from the probe (WP-COS-07), per plan section 4.
   - D9. Order: probe, context stack, owner and bot, husk, previews, score.
4. Add the inventory table under the section.

**Acceptance (machine, no human).**
- OFFLINE: `git grep -c "W4 Cosmetics: offhand_shield_swaps" docs/APPEARANCE_UNIFICATION_PLAN.md` = 1. The inventory table has one row per non-comment grep hit from step 2 (state both counts in the commit message). `pwsh -NoProfile -File qa/run_all.ps1 -Quick` reports no ERROR.
- Class S. Closes nothing; 660 stays open.

**Guardrails.** Do not create a new document. Do not edit `docs/WEAPON_APPEARANCE_STANDARD.md`. Do not change census data or `M.CELL_STATES` (OD-COS-08). No code changes.

**Stop and escalate if.** `docs/WEAPON_APPEARANCE_STANDARD.md` contradicts D2 to D7: quote the conflicting paragraph in the section, mark the decision "blocked by standard", and stop.

---

### WP-COS-07 Add a runtime probe for wielded weapon units

| Field | Value |
|---|---|
| Priority | P1 |
| Size | M |
| Agent | strong (must choose expected values that the fix cannot move) |
| Depends on | none (WP-COS-06 recommended) |
| Issues | advances 660, 200, 203 |
| Source | A3-F02, A3-F12 |
| Streams | `cosmetics_tweaker/` only (single tree) |

**Goal.** One command prints, for every player unit, the unit actually wielded per hand and view next to the unit the mod expects, with a PASS, FAIL or SKIP verdict per row.

**Context.** No test in this family reads what the engine spawned. The engine keeps wielded units on the inventory extension's equipment table: `right_hand_wielded_unit_3p`, `left_hand_wielded_unit_3p` (`Vermintide-2-Source-Code/scripts/unit_extensions/default_player_unit/inventory/simple_inventory_extension.lua:1993-1995`), `right_hand_wielded_unit`, `left_hand_wielded_unit` (`:2017-2019`), `wielded_slot` (`:669`), reached through `SimpleInventoryExtension.equipment` (`:504`) and `SimpleHuskInventoryExtension.equipment` (`.../simple_husk_inventory_extension.lua:181`). Every spawned weapon unit carries its path in unit data `unit_name` (`Vermintide-2-Source-Code/scripts/network/unit_spawner.lua:293-300`), and the third-person unit path is the first-person path plus `_3p` (`.../inventory/gear_utils.lua:189`). The mod already reads `unit_name` in `_unit_mesh_name` (`cosmetics_tweaker.lua:170-181`).

**Steps.**
1. Create `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_appearance_probe.lua` with two pure functions and one installer. `M.judge(row)`: `SKIP` when `row.expected == nil`, `PASS` when `row.actual == row.expected`, else `FAIL`. `M.format(row)`: `[cos:probe] peer=%s who=%s slot=%s hand=%s view=%s actual=%s expected=%s verdict=%s`. `M.install(mod, deps)` registers the command and the check; `deps` carries `get_managers`, `script_unit`, `unit`, `backend_utils`, `printf`, `la_equips_by_peer`, `local_player_safe`.
2. Host test first: `qa/lua/tests/test_cos_appearance_probe.lua` (register in `qa/lua/run.lua`): `judge` and `format` on six rows; `collect` (step 3) on a fake player manager with one local player and one remote player whose equipment tables hold fake units and a fake `unit.get_data`.
3. `collect()`: iterate `Managers.player:players()`. For each player with an alive `player_unit` read `ScriptUnit.has_extension(unit, "inventory_system")`, then `ext:equipment()`. For the wielded slot emit four rows (left and right, 1P and 3P; skip nil units). `actual` is `Unit.get_data(u, "unit_name")` when `Unit.has_data(u, "unit_name")`.
4. Expected value, local human only in this card: `local slot_data = equipment.slots[equipment.wielded_slot]`; `local units = BackendUtils.get_item_units(slot_data.item_data, slot_data.item_data.backend_id, slot_data.skin, ext._career_name)`; expected 1P is `units.left_hand_unit` or `units.right_hand_unit`, expected 3P is that string plus `_3p`. Leave `expected = nil` (SKIP) while the customization screen is open (`mod._active_customization_item_type ~= nil`) and for bots and remote players. Remote rows still print `actual` and the store entry (`armoury_key` or mesh) as extra fields.
5. Register `mod:command("cos_appearance_probe", ...)`: print every row with `printf`, then `[cos:probe] rows=%d pass=%d fail=%d skip=%d`. Register the check `appearance_probe_local_wielded` through `mod._cos_command_owner.register`: fail when any local row is FAIL, return `"skip: no local hero"` when there is none.
6. Wire the module from the entry inside an existing install table or directly as `mod:dofile(...).install(mod, { ... })` after the runtime checks block (`cosmetics_tweaker.lua:1552`). Add no top-level local.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0 with the new test.
- RIG: `qa/runtime/cosmetics_tweaker/issue_660_owner_wielded_units.lua`, arena `keep`: `local hero = T.local_hero()`; `local eq = T.ext(hero, "inventory_system"):equipment()`; for each of `slot_melee` and `slot_ranged`: wield it (`T.as_bot` is for bots: use the inventory extension `wield(slot)`), `T.frames(10)`, then `T.expect_eq(Unit.get_data(eq.right_hand_wielded_unit_3p, "unit_name"), <expected from step 4>, ...)` for each non-nil hand and view; `T.cmd("cos_appearance_probe")`; case field `host_forbid_log = { "verdict=FAIL" }`; `T.expect_rt("cosmetics_tweaker", "appearance_probe_local_wielded")`.
- Class R evidence for the owner surface with no offhand pick. It closes no issue alone.

**Guardrails.** The probe is read-only: no `Unit.set_*`, no store writes, no network sends. Do not add a hook. Do not compute `expected` from the mod's own log lines.

**Stop and escalate if.** `unit_name` is absent on wielded units in the rig run: record which rows lacked it and stop (the probe needs another engine read).

---

### WP-COS-08 Replace ad-hoc ambient flags with one context stack

| Field | Value |
|---|---|
| Priority | P1 (WP-COS-09 and WP-COS-10 depend on it) |
| Size | M |
| Agent | strong (hook ordering and exception safety across four modules) |
| Depends on | WP-COS-06, WP-COS-07 |
| Issues | advances 660 |
| Source | A3-F02, A3-F21 |
| Streams | `cosmetics_tweaker/` only (single tree) |

**Goal.** Call-scoped appearance context lives in one module with a push and pop that survives errors, and the `get_item_units` hook reads it in one place. No behaviour change.

**Context.** Vanilla calls `BackendUtils.get_item_units(item_data, backend_id, skin, career_name)` with fixed arguments (`Vermintide-2-Source-Code/scripts/managers/backend/backend_utils.lua:144`), so the mod tells the hook who is asking through side channels: `_in_create_equipment` set around the vanilla call with no protection (`_cos_equipment_assembly.lua:145, 638-640`), the husk wield context (`_cos_husk_wield_runtime.lua:103-109`, restored at `:181`), and `mod._cos_score_hat_swap` set and cleared around `func` (`_cos_preview_runtime.lua:211-213`, read at `_cos_equipment_assembly.lua:160`). If the wrapped call raises and a caller above catches it, a flag stays set for the rest of the session. Tests pin the current flag (`qa/lua/tests/test_cos_equipment_assembly.lua:89`, `:331`).

**Steps.**
1. Test first: `qa/lua/tests/test_cos_appearance_context.lua` (register in `qa/lua/run.lua`): `Context.with(frame, fn, ...)` returns all of `fn`'s results including nil holes; `Context.current()` is the frame inside and the previous frame after; nesting works; when `fn` raises, the previous frame is restored and the same error is re-raised; `Context.find(key)` returns the nearest frame that has `key`.
2. Create `_cos_appearance_context.lua`: a module-local stack; `M.with(frame, fn, ...)` pushes, calls through `pcall` with an explicit argument count (`select("#", ...)`), pops, then re-raises with `error(err, 0)` or returns `unpack(results, 1, n)`; `M.current()`; `M.find(key)`. No engine globals.
3. Create one instance in the entry and pass it in the existing install tables of `_cos_equipment_assembly` (`cosmetics_tweaker.lua:925`), `_cos_husk_wield_runtime` (`:818`) and `_cos_preview_runtime` (`:953`) as `appearance_context = ...`. Store the instance on `mod._cos.appearance_context`, not in a new top-level local.
4. `_cos_equipment_assembly.lua`: replace the `_in_create_equipment` set and reset at `:638-640` with `Context.with({ in_live_equip = true }, func, ...)`. In the `get_item_units` hook read `Context.find("in_live_equip")`, `Context.find("husk")` and `Context.find("score_hat_swap")` once near the top into locals and use those locals where the old flags were read (`:160`, `:180`, `:493`).
5. `_cos_husk_wield_runtime.lua`: build the same table that is assigned to `state.current` at `:104` and run vanilla inside `Context.with({ husk = that_table }, ...)`. Keep `state.current` and the `current()` accessor updated as today (other modules read them). Keep the error policy of WP-COS-04 (catch at this hook, count, return nil).
6. `_cos_preview_runtime.lua:210-214`: replace the set and clear of `mod._cos_score_hat_swap` with `Context.with({ score_hat_swap = swap_unit }, func, self, item_name, slot, backend_id, skin, skip_wield_anim)`. Delete the `mod._cos_score_hat_swap` field.
7. Update the two pinned tests in `test_cos_equipment_assembly.lua` to assert the same behaviour through the context (bracket set inside the wrap, restored after), and add a case: `func` raises inside `create_equipment`, the error propagates, and a later `get_item_units` call sees no `in_live_equip`.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0. `git grep -n "_cos_score_hat_swap" cosmetics_tweaker/scripts` returns nothing. `git grep -c "_in_create_equipment" cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_equipment_assembly.lua` = 0.
- RIG: `qa/runtime/cosmetics_tweaker/issue_660_owner_wielded_units.lua` (WP-COS-07) still passes in `keep` and in one `mission:<level_key>` run with bots.
- Class U and R. No issue closes.

**Guardrails.** `_active_customization_backend_id` is UI state, not call-scoped: leave it. Do not change what any branch of the hook returns. Do not change hook registration order in the entry.

**Stop and escalate if.** Any existing behaviour test in `test_cos_equipment_assembly.lua` (`:307-460`) changes its expected value: stop, the refactor altered behaviour.

---

### WP-COS-09 Extract offhand unit resolver for owner and bot surfaces

| Field | Value |
|---|---|
| Priority | P1 |
| Size | L (split: step 1 alone is one session; steps 2 to 5 a second) |
| Agent | strong (behaviour-preserving extraction from a 430-line hook) |
| Depends on | WP-COS-06, WP-COS-07, WP-COS-08 |
| Issues | advances 660, 200, 203, 266 |
| Source | A3-F02 |
| Streams | `cosmetics_tweaker/` only (single tree) |

**Goal.** For the local player and bots, the per-hand unit is computed by a pure function with an explicit context, and the hook only gathers inputs and writes the result.

**Context.** The owner branch of the `BackendUtils.get_item_units` hook runs from the `local resolved_skin = skin` line to the end of the hook (`_cos_equipment_assembly.lua:435-580`). It derives the effective backend id (CIM scope, `mod._la_instance_policy.resolve_preview_backend_id`), reads `_offhand_selection[effective_backend_id]`, and for each hand picks between an LA authored mesh (`_resolve_authored_offhand_mesh`), an LA texture receiver (`LA_BRIDGE.resolve_texture_receiver`) and a vanilla option unit, gated by `_override_package_ready` and `mod._la_instance_policy.selection_owned`. Existing behaviour tests drive the installed hook with stubs (`qa/lua/tests/test_cos_equipment_assembly.lua:307-460`).

**Steps.**
1. Characterization tests first, in `test_cos_equipment_assembly.lua`, through the installed hook: no selection returns vanilla units; vanilla option unit selected and ready is applied; selected but not ready keeps the base unit; LA key with `kind = "unit"` and a ready mesh is applied; LA texture variant uses the texture receiver; a foreign selection (`selection_owned` false) is rejected; the browse override is suppressed inside `create_equipment` when the customization backend id matches; `deus_yield` inside `create_equipment` suppresses the override; a `weapon_skin` item resolves the item type of its `matching_item_key`. These must pass on unmodified code. Commit them alone.
2. Create `_cos_offhand_resolver.lua`, pure. `M.resolve_owner(context, selection, deps)` returns `{ left_hand_unit = <string or nil>, right_hand_unit = <string or nil> }` and a `reasons` list (one entry per hand: `applied`, `not-ready`, `foreign-selection`, `no-mesh`, `suppressed`). `deps`: `selection_owned`, `pool_for(item_type)`, `authored_mesh(key)`, `authored_variant(key)`, `texture_receiver(key, base_unit, family)`, `package_ready(unit)`, `cim_prepare(...)`. Move the per-hand logic from the hook into it without changing order.
3. Add `qa/lua/tests/test_cos_offhand_resolver.lua` (register in `qa/lua/run.lua`): the nine cases of step 1 against the pure function, plus one test that loads `tools/shared_lib/_lib_appearance_descriptor.lua` and shows that a spec built from a resolver result (`item_key`, `identity_evidence = { kind = "backend_id", value = ... }`, hands as `{ unit = ... }`, `fallback` with the base units) passes `M.validate`.
4. In the hook: build `context` once (`surface = "owner_3p"` when the context stack has `in_live_equip`, otherwise leave the surface as `inventory_preview` for now), call the resolver, write the returned units into `result`, and emit the existing `_trace("RESOLVE ...")` and `_dbg` lines from `reasons`. Delete the moved code in the same change.
5. Pass the module in the existing install table at `cosmetics_tweaker.lua:925` as `offhand_resolver = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_offhand_resolver")`.
6. Extend the probe (WP-COS-07, step 4): bots get an expected value from the same resolver call; a bot without a backend id expects the vanilla units.
7. For rig setup add a debug command `cos_offhand_pick <hand> <index>` in `_cos_offhand_diagnostics.lua` that commits option `index` of the current wielded weapon's pool through the same functions the picker uses on Apply (`_cos_offhand_picker.lua`, the handler of a pressed offhand cell, and the commit policy `_cos_offhand_commit_policy.lua`), then re-wields through `mod._cos_rewield`.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0. `_cos_equipment_assembly.lua` is at least 60 lines shorter than before step 4 (`git diff --stat`).
- RIG: arena `keep`, extend `issue_660_owner_wielded_units.lua` with a second case: equip a sword and shield, `T.cmd("cos_offhand_pick", "left_hand_unit", 2)`, `T.frames(30)`, assert the left-hand 3P and 1P `unit_name` equal the option unit (and plus `_3p`), then pick index 1 and assert the base unit returns. Arena `mission:<level_key>`: probe rows for bots have no FAIL.
- Class R on the owner surface advances 200, 203, 266: each closes only when its own verification pack passes.

**Guardrails.** Do not touch the husk branch (`:180-425`) in this card. Do not change store shapes. Do not send anything new on the wire. Keep every existing `[la-state]` and `[cos:trace]` line text (issue cards and text invariants grep for them).

**Stop and escalate if.** A characterization test from step 1 cannot be made to pass on unmodified code (the hook has behaviour the nine cases do not describe): add the missing case first; if it depends on live engine state that stubs cannot express, write it down and stop.

---

### WP-COS-10 Route the husk surface through the resolver

| Field | Value |
|---|---|
| Priority | P1 |
| Size | L (split: bus fixture and scenarios first; resolver move second) |
| Agent | strong (multi-peer ordering, career scoping, two stores with precedence) |
| Depends on | WP-COS-01, WP-COS-09 |
| Issues | advances 233, 416, 738, 149 |
| Source | A3-F02, A3-F06, A3-F16 |
| Streams | `cosmetics_tweaker/` only (single tree) |

**Goal.** Remote-player units are chosen by `resolve_husk` with an explicit context, and a three-peer offline test proves that all peers end with the same stores.

**Context.** The husk branch of the hook (`_cos_equipment_assembly.lua:180-425`) reads `_la_equips_by_peer[wearer][template]` (with a CWV candidate fallback and a career check through `mod._cos_husk_identity.entry_matches_career`), then `mod._offhand_mesh_by_peer[wearer][template]`. Transport tests today use one peer (`qa/lua/tests/test_cos_la_sync_transport.lua`). In VMF, target `"all"` reaches every peer including the sender (`docs/VMF_RECIPES.md:369`). The host relays: clients send `cos_la_apply_req`, only the host sends `cos_la_apply` (`_cos_la_sync_transport.lua:378, 695, 1012-1026`).

**Steps.**
1. Bus fixture first: `qa/lua/tests/fixtures/cos_peer_bus.lua`. It builds N instances of the real `_cos_la_sync_transport.lua` using the stub pattern of `test_cos_la_sync_transport.lua:164-254`, each with its own `mod`, stores and peer id, and routes `mod:network_send(name, target, schema, payload)`: a peer id goes to that instance's handler, `"all"` goes to every instance including the sender. Deliveries are queued and flushed by `bus.pump()` so tests control ordering. Because the module reads globals (`Managers`, `Unit`), the fixture swaps the globals to the receiving instance's view before each delivery and restores them after.
2. `qa/lua/tests/test_cos_peer_bus.lua` (register in `qa/lua/run.lua`), host H, clients A and B: (a) A equips an LA offhand: all three hold the same entry for A; (b) A reverts: none holds it; (c) a vanilla mesh from A supersedes A's LA entry on the same hand on all three; (d) B clears its stores, sends `cos_la_state_req` to H, and ends equal to H after `cos_la_state_ack`; (e) H has no bridge and no LA (`la_bridge.registered = false`, `get_mod` returns nil): A's LA key is rejected and B never receives it (assert this as the documented current behaviour, OD-COS-04); (f) malformed payloads from A change nothing on H or B.
3. Characterization tests for the husk branch through the installed hook (extend `test_cos_equipment_assembly.lua` `:408-460`): LA entry `kind = "offhand"` with a unit variant swaps the hand; texture variant uses the receiver; career mismatch drops the entry; vanilla mesh store applies when compatible and ready; not ready keeps the base; `deus_yield` skips both. Commit before moving code.
4. Add `M.resolve_husk(context, la_entry, vanilla_hands, deps)` to `_cos_offhand_resolver.lua` and move the branch logic. Keep the diagnostics (`[la-state] HUSK-GATE`, `HUSK-SWAP`, `HUSK-VANILLA-SWAP`, `[cos:698]`, `PROBE.emit`) in the hook, driven by the returned `reasons`. `context.surface = "husk"`, taken from the context stack frame set in `_cos_husk_wield_runtime.lua`.
5. Probe: remote rows get `expected` from `resolve_husk` with the same inputs.
6. Register the in-game check `husk_resolver_synthetic`: call `resolve_husk` with a synthetic entry for one shield pool unit taken from `_get_offhand_options("es_1h_sword_shield")`, live `Application.can_get`, and assert the returned unit equals the pool unit when resident.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0 with the bus scenarios. `git grep -c "_la_equips_by_peer\[" cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_equipment_assembly.lua` is lower than before and every remaining hit is in the adapter block that builds resolver inputs.
- RIG: solo arenas have no remote players: `T.expect_rt("cosmetics_tweaker", "husk_resolver_synthetic")` PASS in `keep`. In `coop` (later): `T.cmd("cos_appearance_probe")` on both machines, `host_forbid_log = { "verdict=FAIL" }`.
- Class U (bus) is evidence for the store-convergence part of 233, 416, 738. The rendered result on a second machine stays class C.

**Guardrails.** Do not change timers, retry counts or the relay topology (OD-COS-04, OD-COS-05). Do not bump `COS_RPC_SCHEMA`. Do not edit `_cos_la_sync_transport.lua` except to fix a defect a bus scenario proves, and then in a separate change with its own test.

**Stop and escalate if.** A bus scenario shows peers diverging on a valid sequence: that is a product defect. Record the minimal sequence as a failing test marked with the issue number it matches (233, 416 or 738) and stop.

---

### WP-COS-11 Route preview and score surfaces through the resolver

| Field | Value |
|---|---|
| Priority | P2 |
| Size | L (split: 11a inventory preview and illusion browser; 11b CIM Athanor; 11c score and team) |
| Agent | strong (identity differs per preview surface; the audit read this module only in part) |
| Depends on | WP-COS-09 |
| Issues | advances 660, 481, 730 |
| Source | A3-F02 |
| Streams | `cosmetics_tweaker/` only (single tree). Reads `crafting_in_modded_dev/` but does not edit it |

**Goal.** Each preview hook declares its surface on the context stack, and identity resolution for previews is a pure function tested per surface.

**Context.** Previews reach the same `get_item_units` hook through vanilla. Today the hook infers "this is a preview" from the absence of other flags and derives the instance from the open customization screen or a CIM scope (`_cos_equipment_assembly.lua:448-508`, the block from `local cim_context, cim_identity, cim_scoped =` to `local sel =`). Preview entry points: `MenuWorldPreviewer.equip_item` and `HeroPreviewer.equip_item` (`_cos_preview_runtime.lua:121, 158`), `_spawn_item` wrappers (`:567-568`), `LootItemUnitPreviewer.load_package`, `spawn_units`, `update`, `destroy` (`:611-828`), `TeamPreviewer._spawn_hero` (`:298`). CIM passes its scope through `_cos_cim_preview.lua`. The keep inventory instance is `MenuWorldPreviewer`, a class copy of `HeroPreviewer` (`Vermintide-2-Source-Code/scripts/ui/views/menu_world_previewer.lua:7`), so hooks on the base class do not fire for it. `LootItemUnitPreviewer.spawn_units` must stay a `mod:hook` (vanilla assigns `_spawned_units` after it returns). The audit read `_cos_preview_runtime.lua` only around the cited lines [unverified beyond them].

**Steps.**
1. Read `_cos_preview_runtime.lua`, `_cos_cim_preview.lua` and `_cos_la_instance_policy.lua` in full. Extend the inventory table from WP-COS-06 with the preview readers.
2. 11a tests first (through the installed hook, in `qa/lua/tests/test_cos_preview_runtime.lua` and `test_cos_equipment_assembly.lua`): keep preview of the item being customized shows the browsed option; keep preview of a different instance of the same item type shows that instance's committed option, not the browsed one; illusion browser row without a backend id uses the customization screen identity only when the policy admits it; no identity means vanilla units.
3. 11a: wrap the vanilla call in the `equip_item`, `_spawn_item` and `LootItemUnitPreviewer.spawn_units` hooks with `Context.with({ surface = "inventory_preview" | "illusion_browser" }, func, ...)`. Add `M.resolve_identity(context, deps)` to `_cos_offhand_resolver.lua` and move the effective-backend-id derivation into it. The hook passes `context.surface` from the stack. Delete the moved code.
4. 11b tests first in `qa/lua/tests/test_cos_cim_preview.lua`: an exact CIM context resolves its own backend id; an invalid or foreign context yields no override (fail closed); absent context falls back to `illusion_browser`. Then set `surface = "cim_preview"` from the CIM scope and route through `resolve_identity`.
5. 11c: in the `TeamPreviewer._spawn_hero` hook set `surface = "score_team"` with the wearer peer. Tests first: a score row for a remote wearer resolves from that peer's stores, never from the local selection.
6. Probe: add `cos_appearance_probe preview` that prints rows for the open previewer's spawned units (`MenuWorldPreviewer._equipment_units` is keyed by slot index and `_item_info_by_slot` by slot name: bridge through `info.spawn_data[1].slot_index`).
7. In `_cos_appearance_census.lua` flip only the pairs for which a rig PASS exists; regenerate `docs/generated/APPEARANCE_CENSUS_GAPS.generated.md` with `tools/gen-appearance-gaps/gen-appearance-gaps.ps1`.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0. `pwsh -NoProfile -File qa/check_appearance_census_gaps.ps1` exits 0. The hook body in `_cos_equipment_assembly.lua` no longer calls `resolve_preview_backend_id` or `resolve_scoped_identity` (`git grep -c` = 0 for both in that file).
- RIG: `qa/runtime/cosmetics_tweaker/issue_660_inventory_preview_units.lua`, arena `keep`: `T.open_view` the hero inventory, `T.cmd("cos_offhand_pick", "left_hand_unit", 2)`, `T.cmd("cos_appearance_probe", "preview")`, `host_forbid_log = { "verdict=FAIL" }`. `qa/runtime/cosmetics_tweaker/issue_481_athanor_preview_units.lua`, arena `keep`, with `crafting_in_modded_dev` loaded: same assertion on the Athanor preview.
- Class R on unit identity advances 481 and 730. Texture and glow correctness on those surfaces stays class V: attach `T.shot` stills.

**Guardrails.** Do not change `crafting_in_modded_dev/`. Do not convert `LootItemUnitPreviewer.spawn_units` to `hook_safe`. Do not hook `HeroPreviewer` methods expecting them to fire for the keep inventory. Do not flip a census pair without a rig PASS.

**Stop and escalate if.** Score or lobby rows carry no instance identity (the plan document says they lack "an exact selected-slot identity producer"): leave those pairs unsupported, record the missing producer, and stop 11c.

---

### WP-COS-12 Derive DCP portrait counts from one manifest

| Field | Value |
|---|---|
| Priority | P2 |
| Size | M |
| Agent | any |
| Depends on | none |
| Issues | none (526 is class V and unaffected) |
| Source | A3-F11 |
| Streams | `dynamic_cosmetic_portraits/` only (single tree) |

**Goal.** Adding or removing a portrait needs one manifest row plus assets, and no literal count gates readiness.

**Context.** `_check_portrait_materials_ready` returns false unless `#_PORTRAIT_ATLAS_TEXTURES == 24` and `#_PORTRAIT_STANDALONE_MATERIALS == 12` (`dynamic_cosmetic_portraits.lua:451-452`). The same literals are in two in-game checks (`:854`, `:888`), in the log line at `:491`, in `qa/check_dcp_portrait_atlas.ps1:31` and in host tests (`qa/lua/tests/test_dcp_portrait_materials.lua:32, 46, 61-63, 109-110`). The documented workflow (`tools/add_portrait.ps1:248-257`) does not mention them, so a 13th portrait added by the book would silently disable every custom portrait. The portrait set is typed by hand in four places: `_PORTRAIT_STANDALONE_MATERIALS`, `_hat_portrait_map` and `_skin_portrait_map` in the entry, `_texture_names` in `dynamic_cosmetic_portraits_data.lua`, and the `.package`.

**Steps.**
1. Tests first. In `qa/lua/tests/test_dcp_entry_portrait_flow.lua` extend `load_entry` so the test `mod:dofile` can substitute the manifest (step 2) and the atlas descriptor. Case A: a 13-set manifest plus a 26-row descriptor and a `UIAtlasHelper` stub that knows all 26 rows makes `/test_portrait` report `active=true` for the 13th hat key. Case B: a 13-set manifest with the real 24-row descriptor leaves the career row vanilla. In `qa/lua/tests/test_dcp_portrait_materials.lua` replace the literal tests at `:32, :46, :61-63, :109-110` with parity tests: manifest sets, HUD and small PNG files under `gui/1080p/single_textures/custom_portraits`, atlas descriptor rows, medium `.material` files and the medium rows of the `.package` describe the same set.
2. Create `dynamic_cosmetic_portraits/scripts/mods/dynamic_cosmetic_portraits/_dcp_portrait_manifest.lua` returning `{ hats = { ... }, skins = { ... } }`. Move the two tables from the entry (`_hat_portrait_map` at `:300`, `_skin_portrait_map` at `:359-371`) verbatim, comments included.
3. Entry: load the manifest with `mod:dofile`. Keep the local names `_hat_portrait_map` and `_skin_portrait_map` (text invariants reference `_skin_portrait_map[skin_key]` and `_hat_portrait_map[hat_key]`). Build `_PORTRAIT_STANDALONE_MATERIALS` as the sorted list of `"materials/ui/" .. set.medium`. Compute `local _EXPECTED_SETS` (number of sets) and replace `24` with `2 * _EXPECTED_SETS` and `12` with `_EXPECTED_SETS` at `:451-452`, `:854`, `:888`, and format the counts into the log line at `:491`. In `_check_portrait_materials_ready` also require that every set's `hud` and `small` name is an atlas row and that no atlas row is unreferenced.
4. `dynamic_cosmetic_portraits_data.lua`: build `_texture_names` from the manifest (`mod:dofile` works in data files: `cosmetics_tweaker_data.lua:2` does it).
5. `qa/check_dcp_portrait_atlas.ps1:31`: replace `-ne 24` with the count of `portrait_*.png` plus `small_portrait_*.png` files in the source folder, and fail when the HUD, small and medium file counts differ. Update the final OK message to print the computed count.
6. `tools/add_portrait.ps1:248-257` and `dynamic_cosmetic_portraits/CLAUDE.md`: change the next-steps text to "add one row to `_dcp_portrait_manifest.lua` and the medium material and texture rows to the `.package`".

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0. `pwsh -NoProfile -File qa/check_dcp_portrait_atlas.ps1` exits 0. `git grep -n -E "~= (24|12)\b" dynamic_cosmetic_portraits/scripts` returns nothing.
- RIG: arena `keep`, `qa/runtime/dynamic_cosmetic_portraits/issue_526_portrait_readiness.lua`: `T.expect_rt("dynamic_cosmetic_portraits", "portrait_cutouts_use_atlas_path_526")`, `T.expect_rt("dynamic_cosmetic_portraits", "portrait_maps_have_registered_materials")`, and `T.expect(UIAtlasHelper.has_atlas_settings_by_texture_name("portrait_kruber_mercenary_hat_0001"), ...)` (`Vermintide-2-Source-Code/scripts/helpers/ui_atlas_helper.lua:605`).
- Class U and S close this work package.

**Guardrails.** Do not regenerate or edit any PNG, `.texture`, `.material` or the atlas. Do not remove the 24 legacy HUD/small rows from the `.package` here. Do not add portraits. Do not extend beyond `SPProfiles[5].careers[1]` (OD-COS-07).

**Stop and escalate if.** The parity test finds an existing mismatch between the four lists on unmodified master: report the exact difference and stop before changing data.

---

## Owner decisions

The owner is unavailable. Agents proceed on the default and name the decision id in the change description.

| Id | Question | Conservative default |
|---|---|---|
| OD-COS-01 | `cosmetics_tweaker` is a public item on a `-dev` version with no dev twin (A3-F05). Create a friends-only twin? | No new Workshop item and no visibility change. Publish a cosmetics build only after that card's OFFLINE and RIG acceptance pass on the candidate. |
| OD-COS-02 | Move the embedded MoreItemsLibrary, Material-Hijack and LA prefix patch into a shared infrastructure mod? | Keep them in `cosmetics_tweaker`. Pin them with tests (WP-COS-05). Do not edit CWV or WOC for this. |
| OD-COS-03 | Remote-player wield errors: rethrow or keep swallowing? | Keep swallowing. Count, log once with traceback, fail the named check (WP-COS-04). |
| OD-COS-04 | Must the host run the mod, and have LA, for client cosmetics to relay (A3-F06)? | Yes: keep host-authoritative relay and rejection of unknown keys. No client-to-client sends. |
| OD-COS-05 | Replace timed retry windows with acknowledgements (A3-F16)? | Change no timer or retry count. Prove current behaviour with the bus test (WP-COS-10) first. |
| OD-COS-06 | Which LA build is supported, and should the bridge refuse an unknown LA layout (A3-F15)? | Support whatever passes the existing variant filter. Never fail registration on an unknown field. No version gate. |
| OD-COS-07 | Extend DCP beyond Kruber Mercenary? | No. Keep one career. Remove the literal counts only (WP-COS-12). |
| OD-COS-08 | Add a "not applicable" state to the appearance census vocabulary? | No change to `M.CELL_STATES`. Keep the notes. |
| OD-COS-09 | Global glow override is inert, and `tpe_show_self_in_3p` has no reader (A3-F09). Delete or restore? | Leave both as they are. Do not wire new settings to them and do not remove widgets. |
| OD-COS-10 | `character_dialogue` binds only to `gut_dev` and acts only on the host (A3-F18). Change? | Keep the `gut_dev` binding. Add no stable binding and no client-side selection. |
