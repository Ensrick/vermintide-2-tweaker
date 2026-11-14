# Track GUT: GUI Tweaker work packages (`gui_tweaker_dev`, `gui_tweaker`)

Source audit: `docs/audits/2026-11-13_FORMAL_AUDIT/evidence/A7.md` (finding ids A7-Fnn). Related: A5-F01 (crafting_in_modded writes crafted ids into career loadouts), D4 cluster `gut-native-loadout-store`. Cards are ordered by priority. Each card stands alone.

## Family brief

- What it is: two mods. `gui_tweaker_dev/` (mod id `gut_dev`, `0.2.369-dev`, friends-only) and `gui_tweaker/` (mod id `gut`, `0.2.290`, public). About 43,000 Lua lines and 134 files each. One mod id carries about fifteen features: a modded-realm saved-loadout store, a HUD editor, the Mod Tweaker settings menu, third-person and free camera, cutscene skip, in-mission menus, a compendium, scoreboard repairs with two VMF RPC channels, and a partial fork of the HideBuffs mod under `hb/`.
- Entry files: `<tree>/scripts/mods/<tree>/<tree>.lua` (a manifest that loads about 60 modules; the order matters), `<tree>_data.lua` (option widgets), `<tree>_localization.lua`. Offline tests: `qa/lua/tests/test_gut_*.lua` and `test_mod_tweaker_*.lua`. Run them only with `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1`. A new test file must also be added to the `suites` list in `qa/lua/run.lua` or the run fails.
- The trees are forked both ways. Nine files exist only in dev, nine only in stable, 22 common files differ, and `_gut_native_loadouts.lua` is 2,130 lines in dev and 1,501 in stable. Never copy a file across. "Streams: both" means: make the same logical change by hand in each tree, with `gui_tweaker_dev` / `gut_dev` in one and `gui_tweaker` / `gut` in the other.
- Trap 1, VMF drops duplicates silently. A second `mod:hook` or `mod:hook_safe` on the same (Class, method) from the same mod is ignored. A second `mod:command` with the same name replaces the first (`<repos>/Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/commands.lua:28-40`). Grep the tree before adding either. Merge into the existing body.
- Trap 2, the backend mirror hooks (`PlayFabMirrorAdventure.*` in `_gut_native_loadouts.lua`). Never call the wrapped vanilla writer in the modded realm: it would push modded loadouts into the official cloud save. Never call an items-interface method (`get_item_from_id`, `get_all_backend_items`) from inside a read hook: it re-enters the hook without bound. Never pass a modded-store row index into an official read: pass nil.
- Trap 3, size ratchets. Measured in non-empty lines on 2026-11-13: dev `_gut_native_loadouts.lua` 2039 of 2039 (`qa/baselines/file_sizes_target.json:19`), stable entry 1282 of 1282 and stable `_gut_native_loadouts.lua` 1416 of 1416 (`qa/decomposition_contracts.psd1:56-80`), dev entry 1395 of 1415 (`qa/decomposition_contracts.psd1:31-35`). These files may shrink but not grow. Put new code in a new module. A line added to one of them must be paid for by removing a line there. `qa/rt_textual_invariants.psd1` pins source strings: if you move pinned text, update its row in the same change.
- Trap 4, silent failure paths. `mod:dofile` never throws: on error it logs to a channel the owner keeps off and returns nothing (`<repos>/Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/safe_calls.lua:41-44,53-60`). `mod:get` and `mod:set` deep-copy tables on every call (`.../core/settings.lua:54,74`), so `mod:get("native_loadouts")` is a copy of the last saved state, never the live store. Diagnostics must use engine `printf`, never `mod:echo` or `mod:info`. Lifecycle callbacks (`mod.update`, `mod.on_setting_changed`, `mod.on_game_state_changed`) are capture-previous chains: one throw skips every later handler.
- Trap 5, evidence. Both trees register the chat command `gut_regression_test` (`gui_tweaker_dev.lua:151`, `gui_tweaker.lua:146`): load only one tree per rig boot. Until WP-GUT-07 lands, a PASS from that command can mean "could not look". Do not build, deploy, upload or claim a version from a card; shipping follows `PROJECT_STANDARDS.md` section 6.6 and is not part of any card here.

### WP-GUT-01 Stop the exit snapshot overwriting unresolved stored item ids

| Field | Value |
|---|---|
| Priority | P0 (data loss: saved modded loadouts) |
| Size | M |
| Agent | any |
| Depends on | none |
| Issues | #354, #353, #375 (advances; none closed by this card alone) |
| Source | A7-F01 |
| Streams | both. The defect is identical. `_gut_exit_snapshot_core.lua` is the same file in both trees after id normalization; the call sites differ by line only |

**Goal.** At an exit edge, a stored gear id that does not resolve right now is left untouched in the modded loadout store, in both trees, proven by a unit test and a rig case.

**Context.** Paths: DEV = `gui_tweaker_dev/scripts/mods/gui_tweaker_dev/`, PUB = `gui_tweaker/scripts/mods/gui_tweaker/`.
- The store rule is "never sanitize": an id that does not resolve now is served from the official loadout for that read only, and the stored id is kept so it works again when its mod registers it (DEV `_gut_native_loadouts.lua:70-84`, read hook fallback at `:813-821`, `_official_gear_fallback` at `:596-613`).
- `M.exit_snapshot` (DEV `_gut_native_loadouts.lua:1576-1641`, PUB `:1373`) runs on `exit StateIngame`, `enter StateTitleScreen` and `on_unload`, for every career in the store. It reads the "live" value with `BackendUtils.get_loadout_item_id(career, slot, false)` (DEV `:1541`). That value comes from the items-interface cache, which is filled through gut's own read hook (`Vermintide-2-Source-Code/scripts/managers/backend_playfab/backend_interface_item_playfab.lua:108-124`, `:447-452`). So for an unresolved stored id X the live value is already the official fallback O.
- O resolves, so `_live_slot_value` accepts it (DEV `:1546`). `Core.diff_row` writes every non-nil live value that differs from the store (`_gut_exit_snapshot_core.lua:61`). The caller replaces the selected row and persists (DEV `:1594-1603`).
- Result: one session with the mod that provides X disabled (CWV, crafting_in_modded, Loremaster's Armoury, a Weapon Tweaker unlock) replaces X by O in the selected row of every career, permanently. Only the five gear slots are affected (`slot_melee`, `slot_ranged`, `slot_necklace`, `slot_ring`, `slot_trinket_1`); cosmetic reads return nil when unresolved and are skipped already.
- The existing test (`qa/lua/tests/test_gut_exit_snapshot.lua`) feeds hand-made live tables into `diff_row`, so it cannot see the contaminated live value.

**Steps.**
1. Test first. In `qa/lua/tests/test_gut_exit_snapshot.lua` add the case "exit-snapshot keeps a stored gear id that does not resolve". Build `store = { es_mercenary = { selected_index = 1, loadouts = { { slot_melee = "X_modded", slot_ranged = "R1", slot_necklace = "N_modded" } } } }` and `live_by_career = { es_mercenary = { slot_melee = "O_official", slot_ranged = "R2", slot_necklace = "O_neck" } }`. Call `Core.reconcile_selected(live_by_career, store, SLOTS, protect)` with `protect = function(career, slot, stored_value) return stored_value == "X_modded" or stored_value == "N_modded" end`. Assert: total diverged is 1, the merged row has `slot_melee == "X_modded"`, `slot_necklace == "N_modded"`, `slot_ranged == "R2"`, and the new fourth return value `skipped` is 2. Add two more cases: without the fourth argument the result is what it is today (3 diverged), and a nil stored value is still filled from live even when `protect` is given. Run the suite: the first case must fail now. Keep that failing output in the change description.
2. In both trees edit `_gut_exit_snapshot_core.lua`. `Core.diff_row(live, stored, slot_names, protect_slot)`: when `protect_slot` is a function, `stored[slot] ~= nil` and `protect_slot(slot, stored[slot])` is true, do not write the slot and count it in a new fourth return value. `Core.reconcile_selected(live_by_career, store, slot_names, protect)`: pass `function(slot, value) return protect(career, slot, value) end` into `diff_row` when `protect` is a function, and return the summed skip count as a fourth value. Both functions must behave exactly as before when the new argument is nil. Keep the two files identical (they contain no mod id).
3. In DEV `_gut_native_loadouts.lua:1594-1595` and PUB `_gut_native_loadouts.lua:1391-1392` pass the protector as the fourth argument: `function(_, slot, value) return GEAR_SLOT_SET[slot] and _resolve_item_raw(value) ~= RESOLVE_YES end`. Capture the fourth return value and add `skipped_unresolved=%d` to the final `[gut:persist]` printf (DEV `:1639-1640`). Do not touch the READONLY branch (DEV `:1609-1634`): its read hook does not substitute a fallback.
4. Publish one seam for the rig, next to `mod._gut_reset_modded_loadouts` (DEV `:1256`, PUB `:1256`): `mod._gut_exit_snapshot = M.exit_snapshot`.
5. Both `_gut_native_loadouts.lua` files are at their size ratchet (family brief, trap 3). Pay for the added lines by shortening the comment block above `M.exit_snapshot` (DEV `:1484-1516`; the sentence is at `:1511-1514`): the sentence "Gear reconciles only a value that resolves ... never a clear" is now incomplete anyway; replace it with one line stating the protect rule.
6. Add to the same test file a source assertion (temporary, until WP-GUT-03 makes the adapter executable): neither `_gut_native_loadouts.lua` contains the old three-argument call `reconcile_selected(live_by_career, store, LOADOUT_SLOT_NAMES)` followed by a newline.
7. Add the rig case `qa/runtime/gut/issue_354_exit_snapshot_keeps_unresolved_id.lua`, arena `keep`. Let `m = get_mod("gut_dev") or get_mod("gut")`, `items = Managers.backend:get_interface("items")`, `mirror = items._backend_mirror`, `career` = the local player's career name, `PROBE = "gut_rig_unresolvable_necklace"`.
   - `T.require(rawget(_G, "MODDED_REALM") == true, "modded realm")`. `T.set(<loaded gut mod id>, "gut_use_non_modded_loadouts", false)` (the case needs STORE mode). `T.require(type(m._gut_exit_snapshot) == "function", "seam present")`. Read `before = m:get("native_loadouts")`; `T.require(before and before[career], "store seeded")`; `sel = before[career].selected_index`; `old = before[career].loadouts[sel].slot_necklace`. Copy `official_before = mirror._career_data[career][mirror._career_loadouts[career]].slot_necklace`.
   - `T.step("inject")`: `mirror:set_character_data(career, "slot_necklace", PROBE)` (in the modded realm gut captures this into the store and does not call vanilla, DEV `_gut_native_loadouts.lua:894-931`). `T.expect_eq(mirror._career_data[career][mirror._career_loadouts[career]].slot_necklace, official_before, "official row untouched")`. If that fails, restore the raw field to `official_before` at once and end the case.
   - `Managers.backend:dirtify_interfaces()`; `served = BackendUtils.get_loadout_item_id(career, "slot_necklace")`; `T.require(served ~= nil and served ~= PROBE, "fallback served")`.
   - `T.step("exit edge")`: `m._gut_exit_snapshot("rig")`.
   - `T.expect_eq(m:get("native_loadouts")[career].loadouts[sel].slot_necklace, PROBE, "stored id kept")`.
   - Cleanup: `mirror:set_character_data(career, "slot_necklace", old)`; `Managers.backend:dirtify_interfaces()`.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0 and lists the three new cases. `pwsh -NoProfile -File qa/check_file_sizes.ps1` does not exit 2. `pwsh -NoProfile -File qa/check_decomposition_contracts.ps1` and `pwsh -NoProfile -File qa/check_rt_textual_invariants.ps1` pass.
- RIG: `issue_354_exit_snapshot_keeps_unresolved_id.lua` PASS in `keep` on a dev boot and on a public boot. Before the fix the same script FAILS at "stored id kept".
- Evidence class: U closes finding A7-F01. #354, #353 and #375 are advanced only; they close through restart-persistence cases in the GUI verification pack (class R, #353 also needs Loremaster's Armoury on the rig).

**Guardrails.** Do not add any path that clears a stored value. Do not change what `diff_row` does with nil live values. Do not call `iface:get_item_from_id` inside `_resolve_item_raw` (trap 2). Do not run the rig case in the official realm: there `set_character_data` is the vanilla writer.

**Stop and escalate if.** The first new unit case passes before step 2 (the core was already changed: re-read it). `_resolve_item_raw`, `GEAR_SLOT_SET` or `RESOLVE_YES` are not in scope at the call site (the file was reorganized: find the new owner, do not duplicate them). The rig case shows the official row changed at "inject".

### WP-GUT-02 Extract a pure loadout store module with one mutation API

| Field | Value |
|---|---|
| Priority | P0 (the store behind the official-save leak and the row-corruption issues) |
| Size | L. Split: session 1 = module skeleton, seed, set, select, add, delete and their tests; session 2 = read decision, overlay, reconcile, reset, bot designation, fixture round-trip |
| Agent | strong. The API must reproduce nine existing writers exactly, including two index spaces and vanilla quirks; a wrong default here is a data-loss bug |
| Depends on | WP-GUT-01 (its protect rule is part of `reconcile`) |
| Issues | #375, #402, #954, #1033, #353, #354 (advances; none closed) |
| Source | A7-F02, A7-F15; D4 cluster `gut-native-loadout-store`; A5-F01 |
| Streams | `gui_tweaker_dev/` only. Stable is decomposed differently (its `_gut_native_loadouts.lua` is 1,501 lines plus `_gut_native_loadout_checks.lua` and `_gut_native_loadout_commands.lua`) and receives this through the single-tree migration. Do not hand-port |

**Goal.** A new engine-free module `_gut_loadout_store.lua` owns every read and write of the modded loadout table, is covered by an offline suite, and is not yet called by any production hook (no behaviour change in this card).

**Context.** Paths: DEV = `gui_tweaker_dev/scripts/mods/gui_tweaker_dev/`.
- In the modded realm gut serves the game's saved loadouts from its own table so that official cloud data is never written. The table is a file-local in DEV `_gut_native_loadouts.lua:187-200` (`_STORE`, saved as VMF setting `native_loadouts`); a second table holds the readonly overlay (`:221-233`, setting `native_cosmetic_overlay`). Shape: `_STORE[career] = { selected_index, bot_index, bot_loadout, loadouts = { [i] = { slot_x = id, ..., talents = "1,2,.." } }, _seeded, _slot_integrity_v2, _bot_designation_snapshot_v2 }`.
- Nine code paths in two files mutate that table directly: `set_character_data` hook `:894-931`, `set_loadout_index` `:937-957`, `add_loadout` `:960-985`, `delete_loadout` `:988-1014`, `set_career_read_only_data` `:1024-1060`, outer equip capture `_capture_bu_equip` `:666-692`, seed and repair `_ensure_seeded` `:385-431`, reset `M.reset_modded_loadouts` `:1199-1254`, exit snapshot `:1576-1641`, plus the bot owner `_gut_bot_loadout_snapshot.lua:179-187, 383-388, 471-495` through the injected `store()` accessor. Each resolves the row index by its own rule (`optional_loadout_index or entry.selected_index` at `:927` and `:1054`, always `selected_index` at `:683`).
- Nothing can execute `_gut_native_loadouts.lua` offline; `qa/lua/tests/test_gut_native_loadout_policy.lua` only searches its text. Every loadout issue (#375, #402, #954, #1033, #353, #354, closed #387 and #372) was fixed by adding another writer, flag or trace to this table.
- crafting_in_modded writes crafted ids into career loadouts and relies on this store for isolation (A5-F01), so the store's write rule is a cross-mod contract (WP-GUT-04).
- VMF `mod:get` and `mod:set` deep-copy tables (`<repos>/Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/settings.lua:54,74`). The store therefore keeps a private working copy and saves the whole table on each write.

**Steps.**
1. Create DEV `_gut_loadout_store.lua`. It returns a table `Store` with `Store.new(deps)`. `deps = { load = function() return table_or_nil end, save = function(tbl) end, load_overlay, save_overlay, slot_names, gear_slots, weapon_slots, policy, exit_core, max_loadouts = function() return n end, log = function(fmt, ...) end }`. The file must not contain `get_mod`, `Managers`, `mod:` or any engine global. `policy` is the table from `_gut_native_loadout_policy.lua`; `exit_core` is `_gut_exit_snapshot_core.lua`.
2. Implement these methods as line-for-line ports of the cited code. Every mutator saves exactly once and returns `changed, changes`, where `changes` is an array of `{ career, index, key, old, new }`.
   - `store:entry(career)`: the entry or nil. Read only.
   - `store:ensure_seeded(career, official_rows, official_selected)`: port of `:385-431`, including the repair through `policy.row_is_corrupt_partial`, `policy.repair_corrupt_row`, `policy.repair_missing_loadout_slots`. It must deep-copy `official_rows` and never write to them.
   - `store:read(career, key, index, resolve)`: returns `value, resolved_index, source`. `source` is one of `"store"`, `"store-unknown"`, `"need-official-fallback"`, `"nil-jewelry"`, `"row-missing"`, following the decision in the read hook `:781-836` (weapon slot nil: fallback; jewelry nil: nil; `resolve(value)` says no: fallback; unknown: serve the store value). `resolve` is injected; do not copy `_resolve_item_raw` into the store.
   - `store:rows(career)`: returns `selected_index, rows`, where `rows` is a copy (new array, shallow-copied rows). `store:has(career, index)`.
   - `store:set(career, key, value, index)`: port of `:916-931` (nil index means the selected row; creates a bare entry when none exists).
   - `store:select(career, index)`: port of `:946-955` (refuses a missing row).
   - `store:add(career)`: port of `:969-984`. Keep the vanilla quirk: the new row is a copy of the selected row and the selection becomes `old_selected + 1` (`Vermintide-2-Source-Code/scripts/managers/backend_playfab/playfab_mirror_base.lua:2036-2067`).
   - `store:delete(career, index)`: port of `:997-1013` (no-op when `index > n` or `n == 1`; selection fix-up as written).
   - `store:overlay_get / overlay_set / overlay_clear(career, key, official_index)`: port of `:238-274`.
   - `store:reset(career_or_nil)`: wraps `policy.clear_modded_loadouts(store_table, overlay_table, career)`.
   - `store:reconcile_selected(live_by_career, protect)`: calls `exit_core.reconcile_selected` with the protect rule from WP-GUT-01 and applies the merged rows as `:1597-1603` does.
   - `store:set_bot_designation(career, index, snapshot)` and `store:apply_bot_migrations(migrations)`: the two write shapes used by `_gut_bot_loadout_snapshot.lua:179-187` and `:484-495`.
   - `store:batch(fn)`: runs `fn`, suppresses saves inside it, saves once at the end (replaces the `defer_persist` argument at `:385`).
3. Do not change the saved shape. Same top-level career keys, same entry fields, same three marker flags. A table saved by the module must load in the current release and the reverse.
4. Add `qa/lua/tests/test_gut_loadout_store.lua` and register it in the `suites` list of `qa/lua/run.lua`. Load the module with `loadfile` under an environment that has no `get_mod`, `Managers` or `mod` (use `setfenv` with a table holding only the Lua standard library): loading and every case must work there. The fake `save` must deep-copy what it receives, like VMF does. Cases, one `H.test` each:
   - fresh seed copies official rows; changing the official rows afterwards does not change the store; official rows passed with a `__newindex` that errors are never written.
   - seed repair of a bare entry adds missing rows and refills a corrupt partial row except the accessory slots (`slot_necklace`, `slot_ring`, `slot_trinket_1`).
   - `set` with nil index writes the selected row; `set` with index 2 changes row 2 only and leaves rows 1 and 3 equal to their earlier copies.
   - `select` to a missing row changes nothing; `add` copies the selected row, selects `old + 1`, and stops at `max_loadouts()`; `delete` guards and selection fix-up.
   - `read` decision table: the five `source` values above, each with one input.
   - `reconcile_selected` keeps a protected stored id and writes an unprotected divergence.
   - `reset` keeps the bot designation (existing policy behaviour) and `batch` saves once for N seeds (count the `save` calls).
   - overlay set, get, clear keyed by the official index.
   - `rows` returns copies: writing into the result does not change `store:entry(career)`.
   - every mutator calls `save` exactly once outside `batch`.
   - round trip: a fixture table in the current saved shape (with all three flags) loads, a no-op read sequence runs, and the next save deep-equals the fixture.
5. Run `pwsh -NoProfile -File qa/check_dofile_package_coverage.ps1`. If it reports the new module as unloaded, add one line in `_gut_native_loadouts.lua` that dofiles it into an unused local and pay for the line (family brief, trap 3). Otherwise leave production untouched.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0 with all `test_gut_loadout_store` cases listed. `git grep -nE "get_mod|Managers|mod:" -- gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_loadout_store.lua` shows comment lines only. `git diff --stat` shows no change to any hook body. `pwsh -NoProfile -File qa/check_file_sizes.ps1` does not exit 2.
- RIG: none (no behaviour change). The next boot's regression sweep must be unchanged.
- Evidence class: U for the module. No issue closes on this card.

**Guardrails.** No production wiring. No change to the saved shape. Do not "fix" vanilla quirks while porting. Do not add a sanitize or clean-up pass. Do not put resolver, mirror or interface knowledge into the store. Do not touch `gui_tweaker/`.

**Stop and escalate if.** A writer cannot be reproduced without engine state that is not expressible as an injected function. An existing policy test contradicts the code you are porting (the code is the reference: record the difference, do not pick one silently). The round-trip case cannot be made to pass without changing the saved shape.

### WP-GUT-03 Route the nine loadout writers through the store

| Field | Value |
|---|---|
| Priority | P0 |
| Size | L. One commit per path in the order of step 3; any prefix of the sequence is shippable |
| Agent | strong. Each step moves a hook that stands between the modded realm and the official cloud save |
| Depends on | WP-GUT-02 |
| Issues | #375, #402, #954, #1033, #353, #354 (advances) |
| Source | A7-F02, A7-F15 |
| Streams | `gui_tweaker_dev/` only (same reason as WP-GUT-02) |

**Goal.** `_gut_native_loadouts.lua` no longer touches the store table. Every hook is a thin adapter over `_gut_loadout_store.lua`, and an offline suite drives the real adapters against a fake mirror and proves that official tables are never mutated.

**Context.** Paths: DEV = `gui_tweaker_dev/scripts/mods/gui_tweaker_dev/`.
- The eight `PlayFabMirrorAdventure` hooks are registered at DEV `_gut_native_loadouts.lua:760, 840, 874, 894, 937, 960, 988, 1024`; the outer capture hook on `BackendUtils.set_loadout_item` at `:699`. The (Class, method) pairs and hook kinds must not change (family brief, trap 1).
- Isolation rule: in STORE and READONLY mode the vanilla writer must not run, so that `_career_data` stays equal to `_career_data_mirror` and the commit diff sends nothing (`Vermintide-2-Source-Code/scripts/managers/backend_playfab/playfab_mirror_base.lua:2885-2891`). In MODE_OFF (official realm, Versus) the hook must call vanilla once with unchanged arguments.
- Index rule: a fallback read into official data passes a nil index, never the store index (`:596-613`; vanilla `get_character_data` at `playfab_mirror_base.lua:1909-1919`).
- Recursion rule: the read path may only read raw fields. Calling `iface:get_item_from_id` there re-enters `_refresh` and the hook until the Lua heap is exhausted (incident note at `:455-467`). Today nothing but a comment enforces this.
- `get_career_loadouts` returns the live store array (`:870`); after this card it returns copies.

**Steps.**
1. Create DEV `_gut_loadout_adapters.lua` exporting `Adapters.new(deps)` with `deps = { store, mode = function(mirror) end, MODE_OFF, MODE_STORE, MODE_READONLY, resolve, official_fallback, dirtify, prepare, policy, log }`. It returns one function per hook with the hook's own signature: `get_character_data(func, self, career_name, key, optional_loadout_index)`, `get_career_loadouts`, `has_loadout`, `set_character_data`, `set_loadout_index`, `add_loadout`, `delete_loadout`, `set_career_read_only_data`, and `capture_bu_equip(mode, mirror, career_name, slot_name, value, source)`. No `mod:hook` call in this file.
2. Test first. Add `qa/lua/tests/test_gut_loadout_adapters.lua` (register it in `qa/lua/run.lua`). Fakes: a mirror `{ _characters_data_key = "characters_data", _career_data = {...}, _career_data_mirror = <deep copy>, _career_loadouts = {...} }`, a spy `func` that counts calls and records arguments, a store from WP-GUT-02 with an in-memory `save`. Cases that must exist before any path is routed:
   - STORE mode, each of the five writers: spy call count is 0 and the three fake official tables deep-equal their initial copies.
   - READONLY mode: an ordinary gear write changes nothing anywhere; a cosmetic write lands in the overlay; spy count is 0.
   - MODE_OFF, every adapter: spy called once with identical arguments; store `save` count is 0.
   - fallback read: when `resolve` says no, the spy receives nil as its fourth argument, never the store index.
   - re-entrancy: a `resolve` that calls `get_character_data` again returns through `func` and does not recurse (depth stays at most 2).
   - `get_career_loadouts` result can be mutated without changing the store.
3. Route one path per commit, in this order, running the offline suite after each: (a) the three readers `:760-884`, adding a depth counter that calls `func` and returns when the adapter is entered while already active; (b) `set_character_data` `:894-931`; (c) `set_career_read_only_data` `:1024-1060`; (d) `set_loadout_index` `:937-957`; (e) `add_loadout` `:960-985`; (f) `delete_loadout` `:988-1014`; (g) `_capture_bu_equip` `:666-692`; (h) `_ensure_seeded` `:385-431` and `M.reset_modded_loadouts` `:1199-1254` using `store:batch`; (i) `M.exit_snapshot` `:1576-1641` and the bot owner's `store` / `persist` dependencies at `:1078-1084`. In each commit the hook body becomes a one-line call into the adapter and the old body is deleted.
4. After (i) delete `local _STORE`, `_store`, `_persist`, `_OVERLAY`, `_overlay`, `_persist_overlay` from `_gut_native_loadouts.lua`.
5. Keep every `printf` line text byte-identical (log tooling and existing issue cards match on `[gut_dev:NATIVE_LOADOUTS]`, `[gut:persist]`, `[gut:954]`, `[gut:1033]`).
6. Update `qa/rt_textual_invariants.psd1:319` (it pins `Policy.readonly_action(slot, v) == "preserve"` in `_gut_native_loadouts.lua`) to the file that holds the text after the move. If `_gut_native_loadouts.lua` drops below the baseline, lower its row in `qa/baselines/file_sizes_target.json` with the script's documented update switch; never raise it.
7. Add the rig case `qa/runtime/gut/issue_375_loadout_rows_isolated.lua`, arena `keep`, modded realm (`T.require(rawget(_G, "MODDED_REALM") == true, ...)`). With `items = Managers.backend:get_interface("items")`, `mirror = items._backend_mirror`, `career` = local career: copy `mirror._career_data[career]` deeply; find a second owned necklace `B` in `items:get_all_backend_items()` (item data `slot_type == "necklace"`, `Vermintide-2-Source-Code/scripts/settings/equipment/item_master_list_exported.lua:7831`), else `T.require(false, "second necklace owned")`; `BackendUtils.set_loadout_item(B, career, "slot_necklace")`; assert the deep copy still equals `mirror._career_data[career]`; assert `get_mod("gut_dev"):get("native_loadouts")[career].loadouts[sel].slot_necklace == B` (`sel` = that entry's `selected_index`); assert `BackendUtils.get_loadout_item_id(career, "slot_necklace") == B` after `Managers.backend:dirtify_interfaces()`. If the career has two rows: `items:set_loadout_index(career, other)` and assert the other row's necklace is unchanged from the copy taken before. Cleanup: re-equip the original necklace and reselect the original row.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0. `git grep -n "_STORE" -- gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_native_loadouts.lua` returns no lines. `git grep -c 'mod:hook("PlayFabMirrorAdventure"' -- gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_native_loadouts.lua` prints 8. `pwsh -NoProfile -File qa/check_rt_textual_invariants.ps1`, `qa/check_file_sizes.ps1` (not exit 2) and `qa/check_decomposition_contracts.ps1` pass.
- RIG: `issue_375_loadout_rows_isolated.lua` PASS in `keep`; `T.expect_rt("gut_dev", "native_loadouts_gear_fallback_nondestructive")` and `T.expect_rt("gut_dev", "issue954_bot_loadout_snapshot")` still PASS; `host_forbid_log = { "WEAPON SLOT UNRESOLVED" }`.
- Evidence class: U for the adapters, R for the isolation. #375 and #402 are advanced; they close in the GUI verification pack (restart persistence and official-realm legs).

**Guardrails.** One path per commit. Never let a store-mode branch reach `func`. Raw field reads only on the read path. No change to index translation, to log text, to hook targets or kinds. Do not fix A7-F07, A7-F08 or the bot index on delete here: no behaviour change except the two named ones (re-entrancy guard, copies from `get_career_loadouts`).

**Stop and escalate if.** A step-2 case shows that the CURRENT code mutates a fake official table in STORE or READONLY mode: stop routing, keep the failing case, and raise it as a P0 defect. A hook would have to change kind or target. A test that executes the entry file (`test_gut_runtime_checks_mission_map.lua`, `test_gut_mod_tweaker_keep_routing.lua`, `test_gut_module_extraction.lua`) can only pass by deleting one of its cases.

### WP-GUT-04 Publish the loadout isolation contract for item-minting mods

| Field | Value |
|---|---|
| Priority | P0 (official-save leak class, #402) |
| Size | M |
| Agent | strong. Other mods will trust the answer; a wrong "safe" re-opens the official-save leak |
| Depends on | none. In dev, if WP-GUT-03 has landed, the probe lines go into `_gut_loadout_adapters.lua` instead of the hook bodies |
| Issues | #402 (advances). Enables the crafting_in_modded fix for A5-F01 in track CIM |
| Source | A7-F02, A5-F01, D4 finding F1 |
| Streams | both. Consumers resolve the public id first, so the contract must exist on `gut` and on `gut_dev` |

**Goal.** Both trees expose `mod.loadout_isolation` (contract version 1). It tells another mod, by a functional probe and not by a self-declared list, whether a loadout write in the current session is captured by gut instead of reaching official data.

**Context.** Paths: DEV = `gui_tweaker_dev/scripts/mods/gui_tweaker_dev/`, PUB = `gui_tweaker/scripts/mods/gui_tweaker/`.
- In the modded realm the game still commits loadout changes to the official account: the commit builds `updateHeroAttributes` from the diff of `_career_data` against `_career_data_mirror` (`Vermintide-2-Source-Code/scripts/managers/backend_playfab/playfab_mirror_base.lua:2885-2891`). gut prevents this by hooking the writers on `PlayFabMirrorAdventure` and not calling vanilla (DEV `_gut_native_loadouts.lua:894-931`, `:1024-1060`).
- Mods that mint their own backend ids (crafting_in_modded, character_weapon_variants, weapons_of_chaos, modded_progression) write those ids into career loadouts and have no isolation of their own (A5-F01). If gut is absent, disabled or an older build, the id reaches the shared official data and the slot is replaced by starting gear at the next official sign-in (`playfab_mirror_base.lua:1579-1721`). That is #402.
- gut's only self-check today compares wanted method names with a list the module writes itself (DEV `_gut_native_loadouts.lua:1870-1888`). It cannot tell whether a hook is installed and active.
- Track CIM adds an independent last line of defence (WP-CIM-01): crafting_in_modded hooks `PlayFabMirrorAdventure._check_career_data` and scrubs its own ids out of the commit diff, so it is safe even when Tweaker: GUI is absent. The two layers do not replace each other: gut captures the write before `_career_data` changes and keeps the item equipped across restarts; the scrub only keeps it off the cloud. gut must not add a hook on `_check_career_data`.
- A probe through the real dispatch is possible without touching data: call the hooked class function with a throwaway `self`. If gut's hook is live it can answer before doing anything; if it is not, vanilla runs on the throwaway table and errors at `self._career_data[career_name]` (`playfab_mirror_base.lua:1928-1930`), which a `pcall` catches.

**Steps.**
1. Test first. Add `qa/lua/tests/test_gut_loadout_isolation.lua` (register it in `qa/lua/run.lua`). It loads the new module from step 2 with `loadfile`. Cases:
   - `Isolation.rows_clean(career_data, career_data_mirror, keys)`: equal tables give `true`; one differing slot gives `false` plus a detail string naming career, row and key; an extra row gives `false`; a missing argument gives `nil`.
   - `Isolation.new(deps):status()` with `deps = { class = fake, in_modded_realm = fn, mode = fn, mirror = fn, keys = {...} }`: a fake class whose `set_character_data` and `set_career_read_only_data` return `"gut-captured"` gives `chokepoint_owned == true`; a fake that throws gives `false`; a fake that returns nil gives `false`; `mode() == "off"` gives `safe_to_write_loadout() == false` whatever the probe says.
2. Create `_gut_loadout_isolation.lua` in both trees (same content apart from the mod id, and it needs no mod id: take `deps`). Export `PROBE_CAREER = "__gut_isolation_probe__"`, `PROBE_TOKEN = "gut-captured"`, `rows_clean`, and `new(deps)` returning:
   - `status()` -> `{ contract = 1, realm_modded = bool, mode = "off" | "store" | "readonly", chokepoint_owned = bool, official_rows_clean = bool or nil, reason = string or nil }`.
   - `safe_to_write_loadout()` -> `boolean, reason`. True only when `mode ~= "off"` and `chokepoint_owned`.
   - `chokepoint_owned` is computed as: `local probe_self = { _characters_data_key = "characters_data" }`; `local ok1, r1 = pcall(class.set_character_data, probe_self, PROBE_CAREER, "slot_melee", "probe")`; `local ok2, r2 = pcall(class.set_career_read_only_data, probe_self, "probe", "slot_melee", "probe", PROBE_CAREER)`; owned when both calls succeed and both return `PROBE_TOKEN`.
   - `official_rows_clean` is `rows_clean(mirror._career_data, mirror._career_data_mirror, keys)` with `keys` = the nine loadout slot names plus `"talents"`. Do not use `mirror:_check_career_data` for this: it also reports legitimate character-level changes such as the selected career (`playfab_mirror_base.lua:3409-3440`).
3. Add the probe answer to the two write hooks in both trees, directly after the existing early return for `MODE_OFF` and nil career: in `set_character_data` add `if career_name == Isolation.PROBE_CAREER then return Isolation.PROBE_TOKEN end`; in `set_career_read_only_data` the same with `career`. Find the hooks with `git grep -n 'mod:hook("PlayFabMirrorAdventure", "set_character_data"\|mod:hook("PlayFabMirrorAdventure", "set_career_read_only_data"' -- gui_tweaker gui_tweaker_dev`. Pay for the added lines (family brief, trap 3).
4. Publish in both trees, in `_gut_native_loadouts.lua` after the hooks are registered: `mod.loadout_isolation = Isolation.new({ class = rawget(_G, "PlayFabMirrorAdventure"), in_modded_realm = BootGuard.in_modded_realm, mode = <maps _feature_mode() to "off" / "store" / "readonly">, mirror = <returns Managers.backend:get_interface("items")._backend_mirror under pcall>, keys = <LOADOUT_SLOT_NAMES plus "talents"> })`.
5. Register one in-game check through `mod._gut_rt_register`, name `issue402_isolation_contract`: in the modded realm it fails unless `status().chokepoint_owned == true` and `official_rows_clean ~= false`; in the official realm it fails unless `safe_to_write_loadout() == false`. Replace the body of `native_loadouts_official_write_chokepoint` (DEV `_gut_native_loadouts.lua:1870-1888`; in stable it lives in `_gut_native_loadout_checks.lua`) with a call to the same status.
6. Document the consumer rule in the existing `docs/CROSS_MOD_ARCHITECTURE.md` under a heading "Loadout isolation contract": "A mod that wants its created item to stay equipped across restarts asks first: `local gut = get_mod("gut") or get_mod("gut_dev"); local iso = gut and gut.loadout_isolation; local kept = iso and iso.contract == 1 and iso.safe_to_write_loadout()`. When `kept` is false the mod may still equip for the session only if it scrubs its own ids from the commit (WP-CIM-01); otherwise it must not write, and prints one bounded `printf` line with the reason. A mod must never write a mod-minted id into a loadout in the official realm." The consumer-side change itself belongs to track CIM (A5-F01) and is not part of this card.
7. Add the rig case `qa/runtime/gut/issue_402_isolation_contract.lua`, arena `keep`, modded realm. `iso = (get_mod("gut_dev") or get_mod("gut")).loadout_isolation`. `T.expect_eq(iso.contract, 1, ...)`; `T.expect_eq(iso.status().mode, "store", ...)`; `T.expect(iso.status().chokepoint_owned, ...)`; take a deep copy of `mirror._career_data`; equip a second owned necklace with `BackendUtils.set_loadout_item` (find it as in `issue_375_loadout_rows_isolated.lua`; `T.require` it exists); `T.expect(iso.status().official_rows_clean == true, ...)` and the deep copy still equals `mirror._career_data`. Cleanup: re-equip the original.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0 with the new cases. `git grep -c "loadout_isolation" -- gui_tweaker/scripts/mods/gui_tweaker gui_tweaker_dev/scripts/mods/gui_tweaker_dev` is at least 1 per tree. Size and decomposition gates pass.
- RIG: `issue_402_isolation_contract.lua` PASS in `keep` on a dev boot and a public boot; `T.expect_rt("gut_dev", "issue402_isolation_contract")` and the same for `"gut"`.
- Evidence class: U for `rows_clean` and the status logic, R for the live probe. #402 is advanced: its closure also needs the official-realm leg in the GUI verification pack.

**Guardrails.** The probe must use a throwaway `self`, never the live mirror. `safe_to_write_loadout` must fail closed: any error, missing class or unknown mode is `false`. Do not add a second hook on either method (family brief, trap 1). Do not change what the hooks do for real careers.

**Stop and escalate if.** The probe returns the token in the official realm (the mode gate is broken: P0, stop). Another mod's hook on the same method makes the probe throw on the rig with only Tweaker mods loaded (name the mod; decision D-GUT-07 may need to change). The stable hook bodies cannot take two more lines without removing code that is not a comment.

### WP-GUT-05 Run lifecycle handlers through one isolating dispatcher

| Field | Value |
|---|---|
| Priority | P1 (crash-safety: one error can leave the player input-locked) |
| Size | L. Split by event: `update`, then `on_game_state_changed`, then `on_setting_changed`, then the rest. Each split is shippable |
| Agent | any |
| Depends on | none. Do not run in parallel with WP-GUT-06 or WP-GUT-07 (same entry file) |
| Issues | none |
| Source | A7-F04 |
| Streams | `gui_tweaker_dev/` only. Stable receives it through the single-tree migration |

**Goal.** Each VMF lifecycle event of `gut_dev` is assigned exactly once, to a dispatcher that runs every registered handler under its own `pcall`, in today's order, and prints one bounded line when a handler fails.

**Context.** Paths: DEV = `gui_tweaker_dev/scripts/mods/gui_tweaker_dev/`.
- VMF calls one function per event per mod, inside one protected call (`<repos>/Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/events.lua:10-15`). gut multiplexes by chaining: `local prev = mod.update; mod.update = function(dt) if prev then prev(dt) end ... end`. A throw in any link skips every later-loaded link for that dispatch, every frame in the case of `update`.
- Chain sites today. `update`: `_hide_ui.lua:249`, `_gut_reset_presentation.lua:286`, `_gut_damage_numbers.lua:226`, `_gut_camera.lua:416`, `_gut_freecam.lua:342`, `_gut_cutscenes.lua:717`, `_gut_video_profiles.lua:119`, `_gut_simple_ui_compat.lua:81`, `_gut_diagnostics.lua:131`, `_gut_boss_damage_sync.lua:523`, `_gut_custom_stat_sync.lua:565`. `on_game_state_changed`: `gui_tweaker_dev.lua:655` (root), `:1109` (exit snapshot), `_gut_damage_numbers.lua:257`, `_gut_camera.lua:445`, `_gut_freecam.lua:433`, `_gut_mission_map.lua:428`, `_gut_diagnostics.lua:122`, `_gut_scoreboard_live.lua:366`, `_gut_scoreboard_retention.lua:125`, `_gut_boss_damage_sync.lua:569`, `_gut_custom_stats.lua:305`, `_gut_custom_stat_sync.lua:608`. `on_setting_changed`: `gui_tweaker_dev.lua:583` (root), `_gut_inventory_backdrop.lua:211`, `_gut_damage_numbers.lua:241`, `_gut_mainmenu.lua:96`, `_gut_camera.lua:432`, `_gut_freecam.lua:423`, `_gut_monologue.lua:37`, `_gut_scoreboard_retention.lua:138`, `_gut_boss_damage_sync.lua:610`, `_gut_custom_stat_sync.lua:647`. `on_disabled`: seven sites, `on_all_mods_loaded`: `gui_tweaker_dev.lua:945` and two more, `on_user_left`: two sites, `on_unload`: via `:1109`. List them all with `git grep -nE "mod\.(update|on_[a-z_]+)\s*=[^=]" -- gui_tweaker_dev/scripts/mods/gui_tweaker_dev`.
- Handlers that must run to keep the game usable sit late in the chains: the free camera force-exit on state change (`_gut_freecam.lua:433-457`; if skipped, the `PlayerInputExtension.is_input_blocked` hook at `:395-407` keeps blocking input in the next level), the third-person reset (`_gut_camera.lua:445`), the cutscene skip processor (`_gut_cutscenes.lua:717`).
- Execution order today equals module load order, because every link calls the previous one first.

**Steps.**
1. Test first. Add `qa/lua/tests/test_gut_lifecycle.lua` (register in `qa/lua/run.lua`). It loads the new pure module `_gut_lifecycle.lua` with `loadfile`. Cases: handlers run in registration order; a throwing handler does not stop later ones; exactly one emitted line per (event, handler name) however many times it throws; all arguments are forwarded including trailing nils (use `select("#", ...)`); registering the same name twice for one event raises; an unknown event name raises.
2. Create DEV `_gut_lifecycle.lua`: `Lifecycle.new({ emit = function(line) end })` returns `{ on = function(event, name, fn), dispatch = function(event, ...), names = function(event) }`. Events: `update`, `on_setting_changed`, `on_game_state_changed`, `on_enabled`, `on_disabled`, `on_unload`, `on_all_mods_loaded`, `on_user_joined`, `on_user_left`. The failure line is `[gut:LIFECYCLE] event=<e> handler=<name> error=<text>`.
3. In `gui_tweaker_dev.lua`, before the first module that chains (`_hud_customizer` at `:517`), create the instance with `emit = function(line) printf("%s", line) end`, publish it as `mod._gut_lifecycle`, and assign each `mod.<event>` once to a function that calls `dispatch`. Turn the two root handlers (`:583`, `:655`) and `:945` into `on(..., "root", fn)` registrations.
4. Convert the chain sites one file per commit, strictly in the order the files are loaded by `gui_tweaker_dev.lua` (earliest first). That keeps the converted set a prefix of the load order, so the execution order never changes while old and new styles coexist. In each file replace the capture-and-wrap block by `mod._gut_lifecycle.on("<event>", "<module name>", function(...) <body without the prev call> end)`.
5. Exit snapshot (`gui_tweaker_dev.lua:1106-1117`): keep `bind_snapshot_edges` but pass `previous_state = nil` and `previous_unload = nil`, and register the two returned functions with `on("on_game_state_changed", "exit_snapshot", ...)` and `on("on_unload", "exit_snapshot", ...)`.
6. Keep the in-game check `lifecycle_chain_integrity` (`:215`) working (the root handler still receives the probe id). Add a check `lifecycle_isolation` that builds a private `Lifecycle.new` instance, registers a throwing and a normal handler, and fails unless the normal one ran.
7. Offline tests that load a converted module against a fake `mod` (`test_gut_freecam.lua`, `test_gut_cutscenes_hookchain.lua`, `test_gut_custom_stat_sync.lua`, `test_gut_boss_damage_sync.lua`, `test_gut_simple_ui_dropdowns.lua`, others found by running the suite) need `mod._gut_lifecycle` on their fake: give them a real instance loaded with `loadfile`. Do not delete cases.
8. The dev entry has 20 lines of headroom (family brief, trap 3). If the dispatcher set-up does not fit, move the body of the root `on_setting_changed` handler (`:583-648`) into a new module and register it from there.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0. `git grep -nE "mod\.(update|on_setting_changed|on_game_state_changed|on_disabled|on_all_mods_loaded|on_user_left|on_unload)\s*=[^=]" -- gui_tweaker_dev/scripts/mods/gui_tweaker_dev` returns lines in `gui_tweaker_dev.lua` only, one per event. Decomposition and size gates pass.
- RIG: a `keep` boot with `T.expect_rt("gut_dev", "lifecycle_isolation")`, `T.expect_rt("gut_dev", "lifecycle_chain_integrity")` and `host_forbid_log = { "[gut:LIFECYCLE]" }`. Add `qa/runtime/gut/lifecycle_no_handler_errors.lua` for it. The same `host_forbid_log` entry should then be added to every gut rig case.
- Evidence class: U for isolation and order, R for "no handler fails in a normal boot". No issue closes.

**Guardrails.** Do not change any handler body. Do not reorder. Do not convert `hb/mod_events.lua` (it defines `mod.hb_*` names and is not loaded; WP-GUT-11 deletes it). Do not wrap handlers in a second `pcall` inside the modules.

**Stop and escalate if.** A module needs its handler to run before an earlier-loaded one (an order inversion). A rig boot prints `[gut:LIFECYCLE]`: that is a real latent defect in the named handler; record it as a new finding with the line, do not silence it.

### WP-GUT-06 Make feature-module load failures visible

| Field | Value |
|---|---|
| Priority | P1 (a broken module vanishes with its checks; the regression run still passes) |
| Size | M |
| Agent | any |
| Depends on | none. Do not run in parallel with WP-GUT-05 or WP-GUT-07 (same entry file) |
| Issues | none |
| Source | A7-F09, A7-F17 |
| Streams | `gui_tweaker_dev/` only. Stable receives it through the single-tree migration; the fingerprint path defect (step 6) exists only in dev |

**Goal.** Every feature module loaded by `gui_tweaker_dev.lua` goes through one loader that records success or failure, prints the real error with engine `printf`, and fails a named in-game check when anything did not load.

**Context.** Paths: DEV = `gui_tweaker_dev/scripts/mods/gui_tweaker_dev/`.
- The entry loads 22 modules as bare `pcall(mod.dofile, mod, "<path>")` statements: `gui_tweaker_dev.lua:932, 983, 989, 1165, 1174, 1183, 1193, 1216, 1226, 1240, 1256, 1260, 1283, 1296, 1305, 1370, 1386, 1392, 1393, 1399, 1400, 1401`. They include the camera, free camera, in-mission menus, the compendium and the three `hb/` files.
- `mod:dofile` never throws. It reports through `mod:error` and returns nothing (`<repos>/Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/safe_calls.lua:41-44, 53-60`). So `ok` is always true, and blocks of the form `local ok, api = pcall(mod.dofile, ...)` ... `else printf("... failed: %s", tostring(api))` (for example `:1310-1320`) print `nil`. The owner runs with mod logging off, so the real error is never seen.
- In-game checks registered by a module disappear with it, so `/gut_regression_test` reports all PASS when a module failed.
- Hard dependencies use `mod:dofile` directly and are dereferenced at once (for example `local Customizer = mod:dofile(...)` at `:517`, used at `:524`). A failure there aborts the whole entry file.
- VMF itself loads mod files by passing the global `dofile` to a protected call (`.../core/safe_calls.lua:82-90`), so calling `dofile(path)` under `xpcall` gives the same load with the error text in hand.
- Separate small defect in the same block: the settings fingerprint requires `scripts/mods/gui_tweaker_dev/gui_tweaker_data` (`:72`); the file is `gui_tweaker_dev_data.lua`. Static evidence says every dev log prints `[gut:LOAD] v... fp=nodata` (`:111`).

**Steps.**
1. Test first. Add `qa/lua/tests/test_gut_module_loader.lua` (register in `qa/lua/run.lua`). It loads the new pure module with `loadfile`. Cases: a module that returns a table is returned and recorded as ok; a module that throws returns nil, is recorded with the original error text, and one line `[gut:LOAD_FAIL] module=<name> error=<text>` is emitted; with `{ required = true }` the same failure is recorded, emitted and then re-raised; `failures()` lists failed names in load order; `check()` returns nil when all loaded and a string naming the failed modules otherwise; `summary()` returns ok and total counts.
2. Create DEV `_gut_module_loader.lua`: `Loader.new({ dofile = function(path) end, emit = function(line) end })` returning `{ load = function(name, path, opts), failures, check, summary }`. Use `xpcall(function() return deps.dofile(path) end, function(e) return tostring(e) end)` (plain Lua 5.1: `xpcall` takes no extra arguments).
3. In `gui_tweaker_dev.lua`, right after the boot guard load at `:4-6`, load the loader with `mod:dofile`, create it with `dofile = function(path) return dofile(path) end` and `emit = function(line) printf("%s", line) end`, and keep it in a local `load_feature`.
4. Replace each of the 22 bare statements by `load_feature("<module name>", "<same path>")`. Replace each `local ok, x = pcall(mod.dofile, mod, "<path>")` feature block by `local x = load_feature(...)` and keep only the `if type(x) == "table" then ... end` branch (the `else printf` branches go away; the loader already printed). Replace direct `mod:dofile` loads of feature modules by `load_feature(name, path, { required = true })`. Leave these alone, they are not feature loads: the lazy suppliers that must return `ok, value` pairs (`:868`, `:872`), and the reloads inside in-game checks (`:253`, `:278`).
5. After the last load, print `[gut:MODULES] ok=<n> total=<n> failed=<names or none>` with `printf`, and register the in-game check `all_feature_modules_loaded` that returns `loader.check()`.
6. Fingerprint: in `_settings_fingerprint` (`:71-109`) replace `pcall(require, "scripts/mods/gui_tweaker_dev/gui_tweaker_data")` by a load of `scripts/mods/gui_tweaker_dev/gui_tweaker_dev_data` through `mod:dofile` (the localization file is already reloaded this way at `:278`). Treat a nil result as `nodata` as today.
7. Extend the test with a source check on `gui_tweaker_dev.lua`: no line starts with `pcall(mod.dofile`, and the string `gui_tweaker_dev/gui_tweaker_data"` does not occur.
8. Add the rig case `qa/runtime/gut/boot_modules_loaded.lua`, arena `boot`: `host_expect_log = { "[gut:LOAD] v", "[gut:MODULES] ok=" }`, `host_forbid_log = { "[gut:LOAD_FAIL]", "fp=nodata" }`.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0. `git grep -nE "^\s*pcall\(mod\.dofile" -- gui_tweaker_dev/scripts/mods/gui_tweaker_dev/gui_tweaker_dev.lua` returns no lines. `pwsh -NoProfile -File qa/check_decomposition_contracts.ps1` passes (the entry must end at or below 1415 non-empty lines; removing the `else printf` branches frees lines).
- RIG: `boot_modules_loaded.lua` PASS; `T.expect_rt("gut_dev", "all_feature_modules_loaded")` in `keep`.
- Evidence class: U for the loader, R for "all modules load in the real game". No issue closes.

**Guardrails.** Do not change the load order. Do not convert the `mod:dofile` calls inside feature modules (for example the seven at the top of `_gut_native_loadouts.lua`): entry file only. Do not make a previously optional module required. Tests that execute the entry (`test_gut_runtime_checks_mission_map.lua`, `test_gut_mod_tweaker_keep_routing.lua`, `test_gut_module_extraction.lua`) must keep all their cases; give their fakes a global `dofile` if they need one.

**Stop and escalate if.** The rig boot prints `[gut:LOAD_FAIL]` for a module: that is a real defect that was hidden until now; record module and error text as a new finding and do not mask it. Global `dofile` is not callable from the entry in the rig boot (then keep `mod:dofile` inside the loader and report the result as "nil returned", and say so in the change description).

### WP-GUT-07 Make source-text checks report SKIP in the retail game

| Field | Value |
|---|---|
| Priority | P1 (the rig records every check verdict as an assertion) |
| Size | M |
| Agent | any |
| Depends on | none. Do not run in parallel with WP-GUT-05 or WP-GUT-06 (same entry file). Track T cards WP-T-01 (shared runner) and WP-T-02 (vacuous passes) cover the same ground repo-wide; this card is the GUI slice, uses only the existing `skip:` return value, and is valid before or after them. If WP-T-02 already converted a site, leave it |
| Issues | none directly. Affects the evidence value of every GUI issue that cites `/gut_regression_test` |
| Source | A7-F12 |
| Streams | both. The rig runs the public build for public-release issues |

**Goal.** In the retail game, a gut check whose only content is a search of source text reports SKIP with a reason, and a check with a real runtime half no longer carries an unreachable source tail. The source-text assertions are enforced offline instead.

**Context.** Paths: DEV = `gui_tweaker_dev/scripts/mods/gui_tweaker_dev/`, PUB = `gui_tweaker/scripts/mods/gui_tweaker/`.
- The in-game runner (DEV `gui_tweaker_dev.lua:151-171`, PUB `gui_tweaker.lua:146-166`) maps a check that returns nothing to PASS, a returned string starting with `skip:` to SKIP (it also prints `[regression] SKIP <name>: <why>` with engine `printf`), and anything else to FAIL.
- The retail game has no `io` library, so the source reader `_rt_src_read` returns nil there (DEV `gui_tweaker_dev.lua:127-150`). Checks that search source then run `if not txt then return end`, which the runner counts as PASS.
- Sites with that exact early return, dev: `gui_tweaker_dev.lua:369` (`cutscene_postskip_fade_swallow`), `:414` and `:430` (`gut_cutscene_no_global_latch`), `:1010` (`respawn_timer_ingamehud_draw_path`); `_gut_mod_tweaker_contracts.lua:666` (`mod_tweaker_arrow_edge_latch_hold_repeat`), `:731` (`mod_tweaker_keybind_render`), `:764` (`issue631_keybind_mouse_capture`), `:797` (`mod_tweaker_scrollbar_grab_offset`), `:944` (`mod_tweaker_compact_esc_implicit`), `:990` (`crafting_tab_honors_bench_toggle`), `:1022` (`salvage_store_atlas_injected`), `:1078` (`cosmetics_split_tab_ungated_gear_gated`); `_gut_runtime_checks_mission_map.lua:100` (`mission_map_preview_backdrop`); `_gut_ui_tweaks_integration.lua:38` (`hb_setting_names_guarded`), `:82` (`hb_penlight_removed`), `:115` (`hb_fork_dormancy_gate`). Stable has the same checks except `issue631_keybind_mouse_capture`, at `gui_tweaker.lua:298, 343, 359, 930`, `_gut_mod_tweaker_contracts.lua:637, 702, 782, 929, 975, 1007, 1063`, and the same lines in the other two files.
- Count note: the audit said 31 by a loose pattern. The exact population with this early return is 15 checks in dev and 14 in stable. A few more checks read source in the form `if txt and not txt:find(...)`; they already assert live values first and are not changed by this card.
- The rig calls the command and records one assertion per check (`docs/program/CONVENTIONS.md` section 3). Today these checks would be recorded as passing assertions that looked at nothing.
- The offline home for source-text assertions exists: `qa/rt_textual_invariants.psd1`, checked by `qa/check_rt_textual_invariants.ps1`. It has 33 rows with `mod='gut_dev'` and none with `mod='gut'`.

**Steps.**
1. Test first. Add `qa/lua/tests/test_gut_rt_source_skip.lua` (register it in `qa/lua/run.lua`). For both trees read the entry file, `_gut_mod_tweaker_contracts.lua`, `_gut_runtime_checks_mission_map.lua` and `_gut_ui_tweaks_integration.lua` as text and assert that no line matches the Lua pattern `if not [%w_]*txt then return end`. It fails today with 16 hits in dev and 15 in stable.
2. Classify every listed check and write the classification (check name, class) into the change description. Class "runtime half": before the source read, the check asserts a live value, meaning more than "a function or a table exists" (a returned value, a setting, a field of engine data). Class "pure": everything else. Known: `gut_cutscene_no_global_latch` is "runtime half" (it tests the gate function with two inputs and reads `script_data.skippable_cutscenes`); `cutscene_postskip_fade_swallow` and `respawn_timer_ingamehud_draw_path` are "pure" (they only test that one function exists). Decide the others by reading them; when unsure, choose "pure".
3. For every source string a listed check searches for, make sure a row exists in `qa/rt_textual_invariants.psd1`. Row format: `@{ mod='gut_dev'; file='<repo-relative path>'; needle='<text>'; literal=$true; polarity='present' or 'absent'; issueRef='#N'; note='<what breaks>' }`. Add the missing rows for dev, and the same rows with `mod='gut'` and `gui_tweaker/` paths for stable. Grep the live source for each needle before adding its row, as the manifest header requires.
4. "pure" checks: replace `if not txt then return end` by `if not txt then return "skip: source text unreadable in this runtime" end`. Keep the check and its name.
5. "runtime half" checks: delete the source-reading tail (from the `debug.getinfo` call that locates the file to the end of the function), now that step 3 enforces those needles offline. The runtime assertions stay and the check keeps its name. This also frees lines in the size-limited entry files.
6. `qa/lua/tests/test_gut_runtime_checks_mission_map.lua` covers the unreadable-source path of the mission-map checks. If one of its cases expects "nothing returned" for `mission_map_preview_backdrop` with a nil source, change the expected value to the new skip string. Do not delete the case.
7. Add the rig case `qa/runtime/gut/regression_skips_are_reported.lua`, arena `keep`: `T.cmd("gut_regression_test")`; `host_expect_log = { "[regression] SKIP respawn_timer_ingamehud_draw_path", "[regression] SKIP cutscene_postskip_fade_swallow" }`; `T.expect_rt(<loaded gut mod id>, "gut_cutscene_no_global_latch")`.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0. `git grep -nE "if not (main_)?txt then return end" -- gui_tweaker/scripts/mods/gui_tweaker gui_tweaker_dev/scripts/mods/gui_tweaker_dev` returns no lines. `pwsh -NoProfile -File qa/check_rt_textual_invariants.ps1` passes with the added rows. `pwsh -NoProfile -File qa/check_decomposition_contracts.ps1` passes.
- RIG: `regression_skips_are_reported.lua` PASS on a dev boot and a public boot.
- Evidence class: S for the moved source assertions and the source-shape test, R for the live verdicts. No issue closes. Issue cards that quoted "N passed" from this command before this change stay as they are.

**Guardrails.** Keep every check name. Never turn a FAIL into a SKIP. Do not weaken a needle when moving it. Do not add a new runner module: the shared runner is WP-T-01. Do not touch checks outside the listed sites.

**Stop and escalate if.** A moved needle fails offline (the needle is stale or a fix regressed: record the check name and the needle; do not delete the row). A listed check is named in the pinned test card of an open issue as its only evidence and becomes SKIP: list the issue numbers in the change description so the verification pack can replace that evidence with a rig case.

### WP-GUT-08 Remove the duplicate `/mod_tweaker` command registration

| Field | Value |
|---|---|
| Priority | P1 |
| Size | S |
| Agent | any |
| Depends on | none |
| Issues | #1670 |
| Source | A7-F03 |
| Streams | `gui_tweaker_dev/` (code). `gui_tweaker/` (one comment only: the code fix is already there) |

**Goal.** In `gut_dev` the chat command `/mod_tweaker`, the hotkey and the ESC menu entry all open the same view, `mod_tweaker_view`, in the keep and in a mission.

**Context.** Paths: DEV = `gui_tweaker_dev/scripts/mods/gui_tweaker_dev/`, PUB = `gui_tweaker/scripts/mods/gui_tweaker/`.
- DEV `_gut_mod_tweaker_shell.lua:330` registers `mod:command("mod_tweaker", ...)`, which calls `mod.gut_open_mod_tweaker()` and opens the standalone view through `Managers.ui:handle_transition("mod_tweaker_view", ...)`. It is installed from `gui_tweaker_dev.lua:888`.
- DEV `_ba_heroview_inject.lua:196-202` registers `mod:command("mod_tweaker", ...)` a second time. It calls `mod._gut_open_mod_tweaker()`, which opens the hero-view sub-state `gut_mod_tweaker` and refuses outside the keep. This file loads later (`gui_tweaker_dev.lua:1392`).
- VMF replaces a command registered twice by the same mod without a message (`<repos>/Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/commands.lua:28-40`). So in dev the command opens the sub-state presenter, which the same shell marks as switched off (`_USE_KEEP_SUBSTATE = false`, `_gut_mod_tweaker_shell.lua:198`).
- #1670 reports that the command route lost menu sounds while the ESC route kept them, on GUI Dev. The two routes are two different presenters (`_mod_tweaker_view.lua` versus `_mod_tweaker_state.lua`).
- Stable removed the second registration (PUB `_ba_heroview_inject.lua:196-200`) but its comment says command registration is "first-wins", which is the opposite of what VMF does. The fix was never ported to dev.

**Steps.**
1. Test first. Add `qa/lua/tests/test_gut_mod_tweaker_command_route.lua` (register in `qa/lua/run.lua`). Load DEV `_ba_heroview_inject.lua` with `loadfile` while the global `get_mod` returns a recording fake mod (`hook_safe`, `hook_disable`, `command`, `echo`, `info` record their calls). Assert the file registers no command named `mod_tweaker`. Also assert, by reading the text, that DEV `_gut_mod_tweaker_shell.lua` contains exactly one `mod:command("mod_tweaker"`. The first assertion must fail now.
2. In DEV `_ba_heroview_inject.lua` delete lines 196-202 (the comment and the `mod:command("mod_tweaker", ...)` block). Put this comment in their place: "Do not register /mod_tweaker here. `_gut_mod_tweaker_shell.lua` owns that command. VMF replaces a same-mod command registered twice (last one wins), so a registration here would silently reroute the command to this dormant hero-view path." Keep `mod._gut_open_mod_tweaker` (the in-game contract check at `_gut_mod_tweaker_contracts.lua:306-307` requires it).
3. In PUB `_ba_heroview_inject.lua:196-200` replace "first-wins, so a second registration cannot expose" by the same correct statement.
4. If `docs/COMMANDS.md` describes `/mod_tweaker` as keep-only, change the row to the shell's description.
5. Add the rig case `qa/runtime/gut/issue_1670_mod_tweaker_one_route.lua`. Arena `keep`: `ui = Managers.ui._ingame_ui`. `T.cmd("mod_tweaker")`; `T.wait_until(function() return ui.current_view == "mod_tweaker_view" end, 5, "command opens the view")`; `v1 = ui.views.mod_tweaker_view`; `v1:exit(false)` (`ModTweakerView:exit`, DEV `_mod_tweaker_view.lua:1271`); wait until `ui.current_view ~= "mod_tweaker_view"`. Then `get_mod("gut_dev").gut_open_mod_tweaker()` (the function the hotkey and the ESC entry call); wait for the same view name; `T.expect_eq(ui.views.mod_tweaker_view, v1, "same view instance")`; exit again. Add a second file or step for arena `mission:<any level>`: `T.cmd("mod_tweaker")` opens `mod_tweaker_view` there too. `host_forbid_log = { "only opens in the keep/inn" }`.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0. `git grep -c 'mod:command("mod_tweaker"' -- gui_tweaker_dev/scripts/mods/gui_tweaker_dev` totals 1.
- RIG: `issue_1670_mod_tweaker_one_route.lua` PASS in `keep` and in a mission, on a dev boot.
- Evidence class: #1670 closes on R. The issue is a difference between two entry routes; after the change both routes run the same view instance and the same code, which the rig asserts. Whether a click is audible is class V and is not part of #1670; a report that both routes are silent would be a new issue.

**Guardrails.** Do not delete `_mod_tweaker_state.lua`, `_mod_tweaker_state_interaction.lua` or `HeroViewStateModTweaker` (decision D-GUT-02). Do not flip `_USE_KEEP_SUBSTATE`. Do not add a repo-wide lint rule here; that belongs to track T.

**Stop and escalate if.** The rig shows `current_view == "hero_view"` after `T.cmd("mod_tweaker")` on the fixed build (another registration exists: find it with `git grep -n '"mod_tweaker"'`).

### WP-GUT-09 Stop the vanilla bot refresh erasing the shared bot designation

| Field | Value |
|---|---|
| Priority | P1 (a modded session can change official-realm bot designations) |
| Size | M |
| Agent | any |
| Depends on | none |
| Issues | #954 (advances) |
| Source | A7-F07 |
| Streams | both. `_gut_bot_loadout_snapshot.lua` is the same file in both trees after id normalization |

**Goal.** In modded STORE mode the vanilla body of `BackendInterfaceItemPlayfab.refresh_bot_loadouts` no longer runs, so it cannot write to `PlayerData.loadout_selection.bot_equipment` or read store rows with an official index. Official realm, Versus and readonly mode keep exact vanilla behaviour.

**Context.** Paths: DEV = `gui_tweaker_dev/scripts/mods/gui_tweaker_dev/`, PUB = `gui_tweaker/scripts/mods/gui_tweaker/`.
- Vanilla `refresh_bot_loadouts` (`Vermintide-2-Source-Code/scripts/managers/backend_playfab/backend_interface_item_playfab.lua:128-160`) does three things: `self._bot_loadouts = table.clone(self._loadouts)`; for each career with a designation index in `PlayerData.loadout_selection.bot_equipment`, if `backend_mirror:has_loadout(career, index)` is false it sets `bot_equipment[career] = nil` (`:139-142`); then it copies that row's slots through `backend_mirror:get_character_data(career, slot, index)`.
- `bot_equipment` is the live PlayerData table and is shared by the official and the modded realm. In STORE mode gut answers `has_loadout` and `get_character_data` from the modded store (DEV `_gut_native_loadouts.lua:874-884`, `:760`). So when the official designation index is larger than the number of modded rows for that career, vanilla erases the official designation, and otherwise it equips the bot from a modded row chosen by an official index.
- gut registers a post-callback on this method (`mod:hook_safe`, DEV and PUB `_gut_bot_loadout_snapshot.lua:452-454`) that overlays its detached snapshots (`safe_overlay`, `:436-450`). A post-callback runs after the vanilla body, so the erase has already happened.
- gut does not need the vanilla index loop: its own designation is the snapshot stored in `store[career].bot_loadout`, written by the bot checkbox hook (`:471-495`) and applied by `overlay` (`:206-433`). A career without a snapshot keeps the cloned base loadout, which is what vanilla gives a career without a designation.

**Steps.**
1. Test first. In `qa/lua/tests/test_gut_bot_loadout_snapshot.lua` add a case "STORE-mode refresh does not run the vanilla body". Use the file's existing fake mod (it records `hook` and `hook_safe` handlers by `"Class.method"`, lines 38-39) and also record which of the two registered each handler. Install with `Runtime.install`. Build an interface `{ _loadouts = { es_mercenary = { slot_melee = "M1" } }, _bot_loadouts = {} }` and a spy `func` that sets a flag and, like vanilla, sets `native.es_mercenary = nil`. With `mode` returning the store mode, call the registered handler as `handler(func, iface)`. Assert: the handler was registered with `hook` (not `hook_safe`); the spy flag is false; `native.es_mercenary` is unchanged; `iface._bot_loadouts.es_mercenary.slot_melee == "M1"`; `iface._bot_loadouts.es_mercenary ~= iface._loadouts.es_mercenary` (a copy, not the same table). Add two more assertions with `mode` returning the off mode and the readonly mode: the spy ran exactly once and the handler returned what the spy returned. The first assertion fails today.
2. In `_gut_bot_loadout_snapshot.lua` (both trees) replace the `hook_safe` registration at `:452-454` by a full wrapper on the same pair:
   `mod:hook("BackendInterfaceItemPlayfab", "refresh_bot_loadouts", function(func, self) if mode(self) ~= mode_store then return func(self) end; <clone>; safe_overlay(self, "refresh") end)`.
   `<clone>` builds `self._bot_loadouts` as a new table with one new table per career holding the same slot values as `self._loadouts` (two levels are enough: `_loadouts[career][slot] = id`, vanilla `:108-124`). Write the copy by hand; do not call `table.clone` (it is an engine helper and the offline host does not have it).
3. Update the existing cases in `test_gut_bot_loadout_snapshot.lua` and `test_gut_native_loadout_policy.lua` that call the refresh handler as `refresh(iface)`: they now call `refresh(spy, iface)`. Do not delete cases.
4. The pair (`BackendInterfaceItemPlayfab`, `refresh_bot_loadouts`) must stay registered exactly once in each tree: `git grep -n '"refresh_bot_loadouts"' -- gui_tweaker gui_tweaker_dev` shows one `mod:hook` per tree and no `mod:hook_safe`.
5. Add the rig case `qa/runtime/gut/issue_954_bot_designation_not_erased.lua`, arena `keep`, modded realm (`T.require(rawget(_G, "MODDED_REALM") == true, ...)`). `sel = PlayerData.loadout_selection`; `T.require(type(sel) == "table", ...)`; make sure `sel.bot_equipment` is a table (create it if nil and remember that). `career` = local career; `old = sel.bot_equipment[career]`. `T.step("out-of-range designation")`: `sel.bot_equipment[career] = 29`; `Managers.backend:get_interface("items"):refresh_bot_loadouts()`; `T.expect_eq(sel.bot_equipment[career], 29, "vanilla erase did not run")`. Cleanup: `sel.bot_equipment[career] = old` (and remove the table again if the case created it), then refresh once more. Before the fix the expectation fails because 29 is not a row of the modded store.
6. Add a second rig case for the mission leg, `qa/runtime/gut/issue_954_bot_wields_snapshot.lua`, arena `mission:<any level with bots>`: for the first bot, `career` = its career name, `snap = get_mod(id):get("native_loadouts")[career]` and `T.require(snap and snap.bot_loadout, "bot has a designation snapshot")` (otherwise INCONCLUSIVE); `inv = T.ext(T.first_bot_unit(), "inventory_system")`; `T.expect_eq(inv:equipment().slots.slot_melee.item_data.backend_id, snap.bot_loadout.slot_melee, "bot melee")` and the same for `slot_ranged` (`Vermintide-2-Source-Code/scripts/unit_extensions/default_player_unit/inventory/simple_inventory_extension.lua:183, 504`).

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0. `git grep -n 'mod:hook_safe("BackendInterfaceItemPlayfab", "refresh_bot_loadouts"' -- gui_tweaker gui_tweaker_dev` returns no lines.
- RIG: `issue_954_bot_designation_not_erased.lua` PASS in `keep` on both builds; `T.expect_rt(<mod id>, "issue954_bot_loadout_snapshot")` and `"issue954_modded_career_import"` still PASS; `issue_954_bot_wields_snapshot.lua` PASS or INCONCLUSIVE.
- Evidence class: U and R close finding A7-F07. #954 is advanced: its remaining open leg is "the bot wields the designated weapons in a mission", which `issue_954_bot_wields_snapshot.lua` decides (class R) once a designation exists on the rig profile.

**Guardrails.** Do not change `get_bot_loadout`, `_save_bot_equipment`, the import logic or the snapshot semantics (decision D-GUT-01). Do not write to `PlayerData` anywhere in this change. Readonly mode stays on the vanilla body.

**Stop and escalate if.** With the vanilla loop gone, an existing case shows a bot that had a native designation but no snapshot now gets the base loadout where the test expected a designated row: do not restore the vanilla loop; record the case and the career, and check whether the import (`overlay`, `:284-340`) should have produced a snapshot first.

### WP-GUT-10 Pin the boot guard's vanilla continuations with a source contract

| Field | Value |
|---|---|
| Priority | P1 (soft-lock class: a game patch can leave modded sign-in hanging) |
| Size | S |
| Agent | any |
| Depends on | none |
| Issues | #402, #1688 (advances) |
| Source | A7-F14, D4 finding F3 |
| Streams | tests only; the guard file is the same in both trees after id normalization, so one test covers both |

**Goal.** A test fails as soon as a refreshed decompile no longer has the sign-in steps that `_gut_official_loadout_boot_guard.lua` replays or skips, and a rig case proves that modded sign-in completes with the guard active.

**Context.** Paths: DEV = `gui_tweaker_dev/scripts/mods/gui_tweaker_dev/`.
- To keep modded sessions from rewriting official loadouts at boot (#402), the guard hooks five `PlayFabMirrorAdventure` methods (DEV `_gut_official_loadout_boot_guard.lua:98, 111, 125, 133, 146`) and, instead of calling vanilla, performs vanilla's bookkeeping itself: `_continue_after_fix` (`:83-95`) sets `broken_slots_data = nil`, decrements `_num_items_to_load` and calls `_request_user_inventory` or `_verify_default_gear`; the blocked `_fix_career_data` calls `_verify_default_gear` (`:111-122`); the blocked `_verify_career_loadouts` and the discarded `verify_career_loadouts_cb` call `_verify_dlc_careers` (`:133-158`).
- These copies match the game today: `fix_career_data_request_cb` at `Vermintide-2-Source-Code/scripts/managers/backend_playfab/playfab_mirror_base.lua:3292-3344`, `_fix_career_data` at `:3277-3290`, the caller at `:3230-3233`, `_verify_career_loadouts` and `verify_career_loadouts_cb` at `.../playfab_mirror_adventure.lua:91-119`.
- The backend is ready only when `_num_items_to_load == 0` (`playfab_mirror_base.lua:1789-1791`). If a patch adds a step or renames a continuation, the counter is left unbalanced or a stage is skipped, and sign-in in the modded realm never completes. Nothing detects that today; the realm flag change in game 6.12 already went unnoticed for weeks (#1688).
- Precedent for reading the decompile from a unit test: `qa/lua/tests/test_cim_ranalds_game_keys_1696.lua:107, 139` (`os.getenv("VT2_DECOMPILE_ROOT")` or `<repo>/../Vermintide-2-Source-Code`, and `H.test_if(condition, name, body, reason)` to skip visibly when it is absent).

**Steps.**
1. Add `qa/lua/tests/test_gut_boot_guard_source_contract.lua` (register in `qa/lua/run.lua`). Resolve the decompile root exactly as `test_cim_ranalds_game_keys_1696.lua` does. Register every case with `H.test_if(decompile_present, ..., "decompiled Vermintide-2-Source-Code checkout not found (set VT2_DECOMPILE_ROOT)")`. Helper: `body(text, header)` returns the text from the line that starts with `header` up to the next line that starts with `PlayFabMirror` and contains ` = function`.
2. Cases against `scripts/managers/backend_playfab/playfab_mirror_base.lua`:
   - `body(text, "PlayFabMirrorBase.fix_career_data_request_cb = function (self, result)")` contains, in this order: `self.broken_slots_data = nil`, `self._num_items_to_load = self._num_items_to_load - 1`, `if function_result.num_items_granted > 0 then`, `self:_request_user_inventory()`, `self:_verify_default_gear()`; and it contains `_num_items_to_load` exactly twice (one statement).
   - `body(text, "PlayFabMirrorBase._fix_career_data = function (self, broken_slots_data, override_mechanism, override_cb_func)")` contains `override_cb_func or "fix_career_data_request_cb"` and exactly one `self._num_items_to_load = self._num_items_to_load + 1`.
   - the text contains `PlayFabMirrorBase._set_inital_career_data = function (self, career_name, character_data, slots_to_verify)`, `PlayFabMirrorBase._verify_default_gear = function (self)`, `PlayFabMirrorBase._request_user_inventory = function (self)`, `PlayFabMirrorBase._verify_dlc_careers = function (self)`.
   - `body(text, "PlayFabMirrorBase.ready = function (self)")` contains `self._num_items_to_load == 0`.
3. Cases against `scripts/managers/backend_playfab/playfab_mirror_adventure.lua`:
   - `body(text, "PlayFabMirrorAdventure._verify_career_loadouts = function (self)")` contains exactly one `self._num_items_to_load = self._num_items_to_load + 1` and `FunctionName = "verifyCareerLoadouts"`.
   - `body(text, "PlayFabMirrorAdventure.verify_career_loadouts_cb = function (self, result)")` contains exactly one `self._num_items_to_load = self._num_items_to_load - 1` followed by `self:_verify_dlc_careers()`.
   - the text contains `self._characters_data_key = "characters_data"` and `self._characters_data_key = "vs_characters_data"`.
4. Case against `foundation/scripts/util/application_parameter.lua`: contains `rawset(_G, "MODDED_REALM", modded_realm)`.
5. Guard-side case (always runs, no decompile needed): for both trees, the guard file contains each of `_verify_default_gear`, `_request_user_inventory`, `_verify_dlc_careers`, `fix_career_data_request_cb`, `verify_career_loadouts_cb`, and the five hook registrations.
6. Add the rig case `qa/runtime/gut/issue_402_modded_signin_completes.lua`, arena `keep`, modded realm: `mirror = Managers.backend:get_interface("items")._backend_mirror`; `T.expect(mirror:ready() == true, "backend ready")`; `T.expect_eq(mirror._num_items_to_load, 0, "no pending backend requests")`; `host_expect_log = { "[gut:402] " }`; `T.expect_rt(<mod id>, "issue1688_modded_realm_authority")`. Reaching the `keep` arena at all already proves sign-in finished; the log line proves the guard's hooks were installed before the boot callbacks ran, which D4 left as an open question for #402.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0. On a machine with the decompile checked out next to the repo, none of the new cases is reported as skipped.
- RIG: `issue_402_modded_signin_completes.lua` PASS on a dev boot and a public boot.
- Evidence class: S for the source contract, R for the completed sign-in. #402 and #1688 are advanced; their closure needs the official-realm leg (official rows unchanged after a modded session) in the GUI verification pack.

**Guardrails.** This card changes no mod code. Do not "repair" the guard to match a failing contract case without reading the new decompile: a failing case means the game changed and the guard must be re-derived.

**Stop and escalate if.** A contract case fails against the current decompile (either the decompile was refreshed or a quoted statement here is wrong: record which line differs and stop). The rig boot never reaches the keep with only Tweaker mods loaded: P0, the guard is suspect; attach the last `[gut:402]` lines.

### WP-GUT-11 Wire the HideBuffs fork and remove its dead half

| Field | Value |
|---|---|
| Priority | P2 |
| Size | M |
| Agent | any |
| Depends on | none (if WP-GUT-05 has landed, register the handler in step 3 with `mod._gut_lifecycle.on` instead of chaining) |
| Issues | none |
| Source | A7-F05 |
| Streams | both. The four `hb/` files are the same in both trees after id normalization, and the public mod shows the same dead options |

**Goal.** Under the default decision D-GUT-03 (keep the small fork, do not grow it): the never-loaded lifecycle file is gone, the two outline options take effect when toggled, the dormant fork no longer edits vanilla data, and the twelve options that only the stock UI Tweaks mod implements say so in their text.

**Context.** Paths: DEV = `gui_tweaker_dev/scripts/mods/gui_tweaker_dev/`, PUB = `gui_tweaker/scripts/mods/gui_tweaker/`.
- `hb/` is a partial copy of the HideBuffs ("UI Tweaks") mod: `hb_data.lua` (setting names and data), `hide_elements.lua` (16 hooks that hide or restyle HUD elements), `level_loading_screen.lua` (3 hooks), `mod_events.lua` (lifecycle functions `mod.hb_on_*`, `mod.hb_update`). The entry loads only the first three (DEV `gui_tweaker_dev.lua:1399-1401`, PUB `gui_tweaker.lua:1298-1300`). No file loads `hb/mod_events.lua` and nothing calls a `mod.hb_*` lifecycle function (`git grep -n "mod_events\|hb_on_\|hb_update"` finds only the file itself and comments). It is still compiled into both bundles because the package globs `hb/*`.
- Consequence: outline hiding is applied once at load (`hb/hide_elements.lua:394`). The re-apply on setting change exists only in the dead file (`hb/mod_events.lua:193-196`). Static evidence says toggling "Hide pickup outlines" or "Hide other outlines" does nothing until restart. The applied state is engine data: `OutlineSettings.ranges` (`hb/hide_elements.lua:359-377`; `Vermintide-2-Source-Code/scripts/settings/outline_settings.lua:56`).
- The fork must stay dormant when the stock mod is installed and enabled (`mod.hb_fork_active()`, `hb/hb_data.lua:76-94`). One hook ignores that gate and edits the vanilla `realism` visibility group on every call (`hb/hide_elements.lua:220-229`).
- Twelve option widgets have no reader anywhere in gut: `hide_frames`, `hide_levels` (`<tree>_data.lua:186-187`), `force_default_frame` (`:221`) and the nine children of `HIDE_BUFFS_GROUP` (`:202-213`): `victor_bountyhunter_passive_infinite_ammo_buff`, `grimoire_health_debuff`, `markus_huntsman_passive_crit_aura_buff`, `markus_knight_passive_defence_aura`, `kerillian_waywatcher_passive`, `kerillian_maidenguard_passive_stamina_regen_buff`, `HIDE_WHC_GRIMOIRE_POWER_BUFF`, `HIDE_SHADE_GRIMOIRE_POWER_BUFF`, `HIDE_ZEALOT_HOLY_CRUSADER_BUFF`. Upstream implements them in unit-frame and buff-bar hooks that were not copied. Their names are in `<tree>_localization.lua:240-289`.
- `gui_tweaker_dev/ENGINE_SURFACE.md:277` and `:340` describe `hb/mod_events.lua` as live. That is wrong.

**Steps.**
1. Test first. Add `qa/lua/tests/test_gut_hb_fork_adapter.lua` (register in `qa/lua/run.lua`). It loads the new pure module from step 2 with `loadfile`. Cases with a fake `m = { SETTING_NAMES = { HIDE_PICKUP_OUTLINES = "HIDE_PICKUP_OUTLINES", HIDE_OTHER_OUTLINES = "HIDE_OTHER_OUTLINES" }, hb_fork_active = fn, reapply_pickup_ranges = counting fn }`: fork active and id `HIDE_PICKUP_OUTLINES`: one re-apply; id `HIDE_OTHER_OUTLINES`: one; another id: none; fork dormant: none; `SETTING_NAMES` nil: none and no error. File cases for both trees: `hb/mod_events.lua` cannot be opened; `hb/hide_elements.lua` contains `hb_fork_active()` between the line `mod:hook(IngameHud, "_update_components_visibility"` and the next `mod:hook`; for each of the twelve ids in `Adapter.STOCK_ONLY_SETTINGS`, the localization file has a line whose first token (after indentation) is that id and whose `en` text contains `(needs UI Tweaks)`.
2. Create `_gut_hb_fork_adapter.lua` in both trees (identical content): `Adapter.STOCK_ONLY_SETTINGS` (the twelve ids), `Adapter.on_setting_changed(m, setting_id)` (calls `m.reapply_pickup_ranges()` when `m.SETTING_NAMES` exists, `m.hb_fork_active()` is true and the id is one of the two outline ids), and `Adapter.install(m)` which chains `m.on_setting_changed`: capture the previous function, call it first, then call `Adapter.on_setting_changed(m, setting_id)`.
3. In both entries, directly after the three `hb/` loads, add one statement that loads the adapter and calls `install(mod)`. Both entries are size-limited (family brief, trap 3): pay for the line.
4. In `hb/hide_elements.lua` (both trees) add as the first statement of the `IngameHud._update_components_visibility` hook body: `if not mod.hb_fork_active() then return func(self, ...) end`.
5. Delete `hb/mod_events.lua` in both trees. Then run `pwsh -NoProfile -File qa/check_dofile_package_coverage.ps1`.
6. In both localization files append ` (needs UI Tweaks)` to the `en` name of each of the twelve ids, and append to each matching `_tooltip` entry that exists the sentence `Only works when the UI Tweaks mod is installed.` Do not change setting ids. Do not remove widgets.
7. In `gui_tweaker_dev/ENGINE_SURFACE.md` delete the table row at `:277` and correct the paragraph at `:340`: the fork has no lifecycle chain; `hb/mod_events.lua` was removed; outline re-apply runs from `_gut_hb_fork_adapter.lua`.
8. Add the rig case `qa/runtime/gut/hb_fork_outline_toggle.lua`, arena `keep`: `T.require(get_mod("HideBuffs") == nil, "stock UI Tweaks not loaded")`; `id` = the loaded gut mod id; `before = OutlineSettings.ranges.pickup`; `T.set(id, "HIDE_PICKUP_OUTLINES", true)` and, if the rig's `T.set` does not notify the mod, call `get_mod(id).on_setting_changed("HIDE_PICKUP_OUTLINES")`; `T.expect_eq(OutlineSettings.ranges.pickup, 0, "pickup outlines hidden")`; set it back to false the same way; `T.expect_eq(OutlineSettings.ranges.pickup, before, "restored")`.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0. `git ls-files "*hb/mod_events.lua"` prints nothing. `git grep -c "needs UI Tweaks" -- gui_tweaker/scripts/mods/gui_tweaker/gui_tweaker_localization.lua gui_tweaker_dev/scripts/mods/gui_tweaker_dev/gui_tweaker_dev_localization.lua` prints 12 for each. The localization and size gates in `pwsh -NoProfile -File qa/run_all.ps1 -Quick` pass.
- RIG: `hb_fork_outline_toggle.lua` PASS in `keep` on a dev boot and a public boot; `T.expect_rt(<mod id>, "hb_fork_dormancy_gate")` (note: that check is one of the source-text checks of WP-GUT-07 and may report SKIP there; then rely on the offline case).
- Evidence class: U and R for the outline toggle and the gate, S for the labels and the deleted file. Whether an outline is visibly gone is class V and not claimed.

**Guardrails.** Do not implement the twelve missing features and do not copy more upstream code (decision D-GUT-03). Do not change the HideBuffs setting ids: stock UI Tweaks integration matches on them. Use ` (needs UI Tweaks)` exactly; no issue numbers or status words in player-facing text. Do not edit `itemV2.cfg`.

**Stop and escalate if.** A test or gate shows that something does load `hb/mod_events.lua` after all. The localization gate rejects the qualifier. The rig shows `OutlineSettings.ranges.pickup` already changes without the adapter (then the static finding was wrong: keep the deletion and the gate, drop steps 2 and 3, and say so).

### WP-GUT-12 Add the upstream MIT notice for the HideBuffs fork

| Field | Value |
|---|---|
| Priority | P2 (licence compliance on a public item) |
| Size | S |
| Agent | any |
| Depends on | none (after WP-GUT-11 there are three `hb/` files instead of four) |
| Issues | none |
| Source | A7-F06 |
| Streams | both |

**Goal.** Both mod trees carry the upstream copyright and permission notice for the code under `hb/`, and each `hb/` file names its origin.

**Context.**
- `gui_tweaker_dev/scripts/mods/gui_tweaker_dev/hb/` and `gui_tweaker/scripts/mods/gui_tweaker/hb/` are derived from the HideBuffs ("UI Tweaks") mod. The files say so themselves: "copied VERBATIM (renamespaced ...) from HideBuffs.lua" (`hb/hide_elements.lua:6-8`), "verbatim literal entries" (`hb/hb_data.lua:9`).
- Upstream is `https://github.com/Shazbot/Vermintide-Mods`, MIT License, "Copyright (c) 2018 Shazbot" (local clone `<repos>/Vermintide-Mods/LICENSE`; clone HEAD `3c9ebd8ca0f4e4f91e95ed7eedded828b76bbfdc`, 2023-04-16). MIT requires the copyright notice and the permission notice in all copies or substantial portions.
- Neither tree contains the notice or the author's name (`git grep -il "shazbot" -- gui_tweaker gui_tweaker_dev` is empty). The repo root `LICENSE` is MIT with the owner's own copyright line only.
- The exact upstream commit the fork was copied from is not recorded [unverified].
- Files under `scripts/mods/<tree>/hb/` are globbed into the Lua bundle (`<tree>/resource_packages/<tree>/<tree>.package`), so a non-Lua file must not be placed there.

**Steps.**
1. Create `gui_tweaker_dev/THIRD_PARTY_NOTICES.md` and `gui_tweaker/THIRD_PARTY_NOTICES.md` (mod root, next to `CHANGELOG.md`). Content: component "HideBuffs (UI Tweaks)"; upstream URL; the list of derived files (`hb/hb_data.lua` from `HideBuffs_data.lua` and `mod_data.lua`; `hb/hide_elements.lua` from `HideBuffs.lua`; `hb/level_loading_screen.lua` from `level_loading_screen.lua`); the full licence text copied byte for byte from `<repos>/Vermintide-Mods/LICENSE`; the reference commit above with the note that the original copy point is not recorded; a short list of changes (renamed to this mod's id, options tree removed, Penlight dependency replaced, dormancy gate added per hook); and a last section "Suggested Workshop credit line" containing: `Includes code from HideBuffs (UI Tweaks) by Shazbot, MIT License.`
2. Add two comment lines at the very top of every existing `hb/*.lua` in both trees: `-- Derived from HideBuffs (UI Tweaks) by Shazbot, MIT License: https://github.com/Shazbot/Vermintide-Mods` and `-- Licence text and list of changes: THIRD_PARTY_NOTICES.md in the mod root.`
3. Add `qa/lua/tests/test_gut_third_party_notices.lua` (register in `qa/lua/run.lua`): for both trees the notices file opens and contains `Copyright (c) 2018 Shazbot` and `Permission is hereby granted, free of charge`; each of `hb/hb_data.lua`, `hb/hide_elements.lua`, `hb/level_loading_screen.lua` contains `Shazbot` in its first three lines.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0. `git grep -c "Copyright (c) 2018 Shazbot" -- gui_tweaker/THIRD_PARTY_NOTICES.md gui_tweaker_dev/THIRD_PARTY_NOTICES.md` prints 1 for each.
- RIG: none.
- Evidence class: S closes finding A7-F06 for the source trees.

**Guardrails.** Copy the licence text from the upstream file; do not retype it from memory. Do not edit `itemV2.cfg` or any Workshop description (decision D-GUT-08). Do not put the notice file under `scripts/`. Comment lines only in the `hb/` files.

**Stop and escalate if.** `<repos>/Vermintide-Mods/LICENSE` is not present and the upstream text cannot be read from the upstream repository. The upstream licence at that path is not MIT or names another holder.

## Owner decisions

The owner is unavailable. Agents proceed on the default and name the decision id in the change description. A card that depends on a decision says so.

| Id | Question | Conservative default to assume |
|---|---|---|
| D-GUT-01 | #954: should a bot follow later edits to its designated loadout row (vanilla behaviour), or keep the equipment it had when the bot box was ticked? | Keep the current behaviour: the bot uses the detached snapshot taken at designation; to change the bot's gear the player unticks and ticks the box again. Do not add auto-follow or a bot-edit action. Rig cases assert the snapshot semantics |
| D-GUT-02 | Keep or delete the hero-view Mod Tweaker presenter (`_mod_tweaker_state.lua`, `_mod_tweaker_state_interaction.lua`, about 2,400 lines, switched off since 0.2.62-dev)? | Keep the files, keep it unreachable (`_USE_KEEP_SUBSTATE = false`, no command). Do not delete and do not enable |
| D-GUT-03 | HideBuffs fork: finish it, keep it small, or drop it for integration with the stock UI Tweaks mod only? | Keep it small (WP-GUT-11): keep the 19 working hooks, delete the dead file, label the twelve stock-only options. Do not copy more upstream code |
| D-GUT-04 | HUD editor: one layout per exact resolution, per aspect ratio, or global? | Per exact resolution, as today. No migration of saved offsets |
| D-GUT-05 | Is the "Use non-modded loadouts" mode still wanted? It adds a second overlay store and a third branch in every loadout hook | Keep it. WP-GUT-02 and WP-GUT-03 must preserve READONLY and overlay behaviour exactly |
| D-GUT-06 | Retire the legacy `/save_loadout`, `/load_loadout`, `/list_loadouts` commands now that the native store has 30 rows? | Keep them unchanged |
| D-GUT-07 | Where does the official-loadout protection live: in Tweaker: GUI only, or as a shared library in every mod that creates items (A5 question 1)? | Both layers. Tweaker: GUI owns write capture and publishes `mod.loadout_isolation` contract 1 (WP-GUT-04). Each item-creating mod also scrubs its own ids from the commit (WP-CIM-01), so it is safe without Tweaker: GUI |
| D-GUT-08 | Add the HideBuffs credit line to the public Workshop descriptions (`itemV2.cfg`)? Compiled bundles carry no comments, so the notice is otherwise only in the repository | Do not edit `itemV2.cfg`. WP-GUT-12 adds the repository notice and drafts the line for the owner |
