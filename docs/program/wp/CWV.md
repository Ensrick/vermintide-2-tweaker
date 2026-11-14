# CWV track: work packages for character_weapon_variants (cwv) and weapons_of_chaos (WOC)

Source audit: `docs/audits/2026-11-13_FORMAL_AUDIT/evidence/A2.md`. Cards are ordered by priority. `CWV/` = `character_weapon_variants/scripts/mods/character_weapon_variants/`, `WOC/` = `weapons_of_chaos/scripts/mods/weapons_of_chaos/`. Engine paths are under `<repos>/Vermintide-2-Source-Code/`; VMF paths under `<repos>/Vermintide-Mod-Framework/`.

## Family brief

1. cwv (VMF id `character_weapon_variants`, 130 Lua files) adds about 32 new weapon ITEMS that give one hero another hero's moveset or a custom mesh. WOC (VMF id `WOC`, 30 files) adds one relic item, the Blightreaper. Neither has a `_dev` twin.
2. Entry files: `CWV/character_weapon_variants.lua` (an ordered list of 97 `mod:dofile` calls that share one table, `_om`) and `WOC/weapons_of_chaos.lua`.
3. How a variant is registered: one row in `CWV/_cwv_variant_catalog.lua` (`item_key`, `base_weapon`, units, optional `template`). `_build_entry` clones the base `ItemMasterList` row (`CWV/_cwv_item_registration_owner.lua:255-574`). `_auto_register_all` runs once at `StateInGameRunning.on_enter` (`:664-893`, hook at `:903`): it writes `ItemMasterList[key]`, appends `NetworkLookup.item_names`, and adds one 5-power seed item `<key>_001` to the local backend through the `MoreItemsLibrary` mod. Templates, skins and other lookups are built by other modules at mod load.
4. Offline tests: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` runs all of them (`qa/lua/run.lua` cannot run one file by name). A new `qa/lua/tests/test_*.lua` returns `function(H, repo_root)` and must be added to the `suites` list in `qa/lua/run.lua`.
5. Trap T1, size ratchets: the cwv entry is at 1,490 of 1,490 nonblank lines and the WOC entry at 1,388 of 1,390 (`qa/decomposition_contracts.psd1`, `qa/lua/tests/test_cwv_entry_decomposition.lua:117-123`). `CWV/_cwv_regression_identity.lua` is at 1,500 of 1,500; `_cwv_regression_render.lua` and `_cwv_combat_styles.lua` are frozen above target (`qa/baselines/file_sizes_target.json`). Put new code in a NEW module loaded from an existing non-entry module. Comment lines count.
6. Trap T2, identity: a cwv `ItemMasterList` row keeps `name` and `key` of its BASE weapon (`CWV/_cwv_item_registration_owner.lua:339-365`); setting them to the cwv key crashes equip. Recognise a cwv item by `cwv_key` or `_om._cwv_key_for_item(backend_id, item_data)`. On vanilla network messages only base values may appear.
7. Trap T3, hooks: VMF keeps one handler per mod per `(Class, method)`. A second `mod:hook` on the same pair is dropped with a warning (`vmf/scripts/mods/vmf/modules/core/hooks.lua:209-236`). Run `git grep -n '"<Class>", "<method>"' -- character_weapon_variants weapons_of_chaos` first and extend the existing handler.
8. Trap T4, faults `pcall` cannot catch: `Unit.node` on a missing node, `Managers.package:load` of an unknown path, a Wwise call with an unregistered world. Also `NetworkLookup.<t>[x]` raises on a missing key and `ItemMasterList[x]` files a crash report for one (`CWV/_cwv_item_registration_owner.lua:739-744`): use `rawget` for both.
9. Trap T5, pinned text: about 1,100 offline assertions check exact source strings, and some tests lift code blocks out of files (`qa/lua/tests/test_regression_runner_verdicts.lua`, `test_cwv_entry_decomposition.lua`). After every edit run the offline suite. If a pin fails on a line you changed on purpose, update the pinned string in the same commit; never delete the test case. Also: `mod:dofile` returns a fresh module per call, so shared state must live on `mod` or `_om`, and WOC's package lists Lua files by name (see WP-CWV-12).

---

### WP-CWV-01 Keep the Outrider clone template name off the wire

| Field | Value |
|---|---|
| Priority | P0 (co-op break) |
| Size | S |
| Agent | any |
| Depends on | none for the fix; rig core (track H) for the RIG acceptance |
| Issues | none open for this defect; must keep #1320 passing |
| Source | A2-F01 |
| Streams | `character_weapon_variants/` only (single tree) |

**Goal.** A projectile fired by the Outrider Grenade Launcher creates a network game object whose `item_template_name` field is the vanilla index of `dr_deus_01_template_1`, while the shot itself still uses the cwv grenade settings.

**Context.**
- `CWV/_cwv_outrider_projectile_wire.lua:176-187` appends `outrider_grenade_launcher_template` to `NetworkLookup.item_template_names` and stamps that name on the clone's `lookup_data` rows. The local fire path needs it: it selects the grenade `projectile_info` (`scripts/unit_extensions/weapons/actions/action_grenade_thrower.lua:73-75`, `scripts/entity_system/systems/projectile/projectile_system.lua:178-181`).
- `PlayerProjectileUnitExtension.init` copies the name into its own table `self.action_lookup_data` (`scripts/unit_extensions/weapons/projectiles/player_projectile_unit_extension.lua:59-66`). It resolves its action from the BASE item, not from that name (`:56-58,68`).
- The only readers of that table are the game-object initializers, which encode the name for every peer (`scripts/network/game_object_initializers_extractors.lua:737,755`). Receivers decode with a strict lookup (`:3284`). A peer without cwv, or with a different lookup tail, has no such index.
- The initializer runs after extension init (`scripts/network/unit_spawner.lua:336-346`). cwv already owns the one `hook_safe` on `PlayerProjectileUnitExtension.init` (`CWV/_cwv_javelin_runtime_owner.lua:491`). So resetting the name in that hook changes the wire and nothing local.

**Steps.**
1. Test first. In `qa/lua/tests/test_cwv_outrider_projectile_wire.lua` add two cases:
   - `M.wire_template_name(M.TEMPLATE_KEY) == M.DONOR_TEMPLATE_KEY`; any other string and `nil` pass through unchanged.
   - Build `ext = { action_lookup_data = { item_template_name = M.TEMPLATE_KEY, action_name = "action_one", sub_action_name = "default" } }`, call `M.sanitize_projectile_lookup(ext)`, then index a strict vanilla-only table `setmetatable({ dr_deus_01_template_1 = 2, [2] = "dr_deus_01_template_1" }, { __index = function(_, k) error("missing " .. tostring(k)) end })` with `ext.action_lookup_data.item_template_name`. Expect `2`, unchanged action names, and `false` from a second call. Both cases fail before step 2.
2. In `CWV/_cwv_outrider_projectile_wire.lua` add `M.wire_template_name(name)` (returns `M.DONOR_TEMPLATE_KEY` when `name == M.TEMPLATE_KEY`, else `name`) and `M.sanitize_projectile_lookup(extension)` (rewrites `extension.action_lookup_data.item_template_name` through it; returns true only when it changed something). At the first line of `M.install`, before the `template_missing` return, set `om.outrider_projectile_wire_lib = M`.
3. In `CWV/_cwv_javelin_runtime_owner.lua`, inside the existing `mod:hook_safe("PlayerProjectileUnitExtension", "init", ...)`, directly after `pcall(_om._cwv_apply_renamed_projectile_template, self, extension_init_data)` and before `if item ~= "we_javelin" then return end`, add: `if _om.outrider_projectile_wire_lib then pcall(_om.outrider_projectile_wire_lib.sanitize_projectile_lookup, self) end`.
4. In `CWV/_cwv_regression_husk_ammo.lua`, check `issue1320_outrider_projectile_unit_and_wire`, after part (4) add: build a probe table with the clone name, call `wire_lib.sanitize_projectile_lookup(probe)`, return a failure string unless the name is now `dr_deus_01_template_1`.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0. `git grep -c "sanitize_projectile_lookup" -- character_weapon_variants/scripts` reports 3 files.
- RIG: add `qa/runtime/cwv/a2f01_outrider_wire_name.lua`, arena `keep`.
  1. `Managers.state.network:request_profile(1, "empire_soldier", "es_mercenary", true)`, then `T.local_hero()`.
  2. Equip the seed: id `cwv_es_outrider_grenade_launcher_001` (fallback `_000`, rule at `CWV/_cwv_acquisition.lua:21-43`); `T.require` that `Managers.backend:get_interface("items"):get_item_from_id(id)` is not nil; `BackendUtils.set_loadout_item(id, "es_mercenary", "slot_ranged")`; `T.ext(hero, "inventory_system"):create_equipment_in_slot("slot_ranged", id)` (pattern: `scripts/unit_extensions/default_player_unit/inventory/simple_inventory_extension.lua:2175-2183`).
  3. For the case only, wrap `GameSession.create_game_object` to record `(go_type, init_table)` and wrap `Managers.state.unit_spawner.spawn_network_unit` on the instance to record the returned unit. Restore both in cleanup.
  4. Fire without input, mirroring `action_grenade_thrower.lua:59-75`: `local a = Weapons.outrider_grenade_launcher_template.actions.action_one.default`; get `position, rotation` from `T.ext(hero, "first_person_system"):get_projectile_start_position_rotation()`; call `ActionUtils.spawn_player_projectile(hero, position, rotation, 0, ActionUtils.pitch_from_rotation(rotation), Vector3.normalize(Vector3.flat(Quaternion.forward(rotation))), a.speed, "dr_deus_01", a.lookup_data.item_template_name, a.lookup_data.action_name, a.lookup_data.sub_action_name, false, 600)`.
  5. Assert: `T.expect_eq(init.item_template_name, rawget(NetworkLookup.item_template_names, "dr_deus_01_template_1"))`; `T.expect_eq(init.item_name, rawget(NetworkLookup.item_names, "dr_deus_01"))`; on the recorded unit, `ScriptUnit.extension(unit, "projectile_system").projectile_info == rawget(Projectiles, "cwv_outrider_grenade_projectile")` (the local shot still uses the grenade, which is what #1320 needs); `T.expect_rt("character_weapon_variants", "issue1320_outrider_projectile_unit_and_wire")`.
- Evidence class: the defect is closed by U (step 1) plus R (step 5). The view of the shot from a second cwv client stays class C.

**Guardrails.** Do not remove the restamp or the lookup registration: the local shot needs both. Do not add a second hook on `PlayerProjectileUnitExtension.init` (T3). `CWV/_cwv_javelin_runtime_owner.lua` has 1,425 of 1,500 nonblank lines: add one line, no comment block. Do not touch the javelin code below the inserted line.

**Stop and escalate if.** The RIG shows `projectile_info` is no longer the cwv grenade after the change (a local reader of `action_lookup_data.item_template_name` exists that this card did not find). Or you find another cwv template whose private `lookup_data` names a non-vanilla template on a projectile, bow or throw action: list it, do not fix it here.

---

### WP-CWV-02 Make cwv and WOC non-togglable

| Field | Value |
|---|---|
| Priority | P1 |
| Size | S |
| Agent | any |
| Depends on | none; rig core (track H) for the RIG acceptance |
| Issues | none (prevents the crash classes of #278, #423, #491 from returning through the VMF "disable" checkbox) |
| Source | A2-F02 |
| Streams | `character_weapon_variants/` and `weapons_of_chaos/` (single trees) |

**Goal.** Neither mod can be switched off from the VMF options menu, and both start fully active without relying on VMF's `on_enabled` event.

**Context.**
- Both data files set `is_togglable = true` (`CWV/character_weapon_variants_data.lua:7`, `WOC/weapons_of_chaos_data.lua:71`).
- VMF always runs the mod script, then only for togglable mods applies the saved state (`vmf/scripts/mods/vmf/modules/vmf_mod_manager.lua:113-129`). Disabling turns every hook off (`.../core/toggling.lua:9-25`) but cwv's `on_disabled` removes nothing (`CWV/_cwv_commands_lifecycle.lua:593-602`). The items, lookup rows and vanilla table edits stay while every wire-safety hook is off.
- Trap: for a non-togglable mod VMF never calls `initialize_mod_state`, so `mod.on_enabled` is never fired at start-up. Both mods do start-up work there (`CWV/_cwv_commands_lifecycle.lua:580-591`, `WOC/weapons_of_chaos.lua:1022-1026`). The default state of a new mod is enabled (`vmf/scripts/mods/vmf/modules/vmf_mod_data.lua:30`).

**Steps.**
1. Test first: add `qa/lua/tests/test_cwv_woc_not_togglable.lua`. Load each data module with a stub `get_mod` the way `qa/lua/tests/test_woc_data_widgets.lua` does (for cwv, make the stub's `dofile` method `loadfile` the anim picker). Assert the returned table has `is_togglable == false`. Register the file in `qa/lua/run.lua`.
2. cwv, one commit: set `is_togglable = false`; in `CWV/_cwv_commands_lifecycle.lua` add `mod.on_enabled()` as the last statement of the install function (after the `cwv_give` command, before the closing `end`).
3. WOC, one commit: set `is_togglable = false`; add `mod.on_enabled()` as the last statement of `WOC/weapons_of_chaos.lua` (one nonblank line; the entry has two lines of headroom).

**Acceptance (machine, no human).**
- OFFLINE: the suite exits 0. `git grep -n "is_togglable = true" -- character_weapon_variants/scripts weapons_of_chaos/scripts` returns nothing. `git grep -n "mod.on_enabled()" -- character_weapon_variants/scripts weapons_of_chaos/scripts` shows exactly one call line per mod (the definitions read `mod.on_enabled = function()` and do not match).
- RIG: `qa/runtime/cwv/a2f02_not_togglable.lua`, arena `keep`: `T.expect(get_mod("character_weapon_variants"):is_enabled() == true)`, the same for `get_mod("WOC")`; `T.expect_rt("character_weapon_variants", "issue645_mace_on_kruber_sword_family")`; `T.expect_rt("WOC", "issue934_shared_relic_lease_contract")`; `host_forbid_log = { "[regression] FAIL" }`. [unverified] that these two checks fail when the start-up call is missing; they are the closest existing probes of the runtimes `on_enabled` activates.
- Evidence class: S for the flag, R for start-up parity.

**Guardrails.** Do the flag and the explicit call in the same commit per mod: with the flag still true the body would run twice at start-up. Keep `mod.on_disabled` and `mod.on_unload` exactly as they are (pinned by `qa/lua/tests/test_cwv_mace_hammer_identity.lua:138-144`; `on_unload` still runs on a mod reload). Do not place the cwv call between the lifecycle callbacks and the comment `-- (2) Variant equip event` (`test_cwv_mace_sword_integration.lua:203` lifts that span).

**Stop and escalate if.** An existing offline test drives `on_enabled` itself and now sees the body twice. Or the owner wants a runtime off switch (decision D-CWV-02): that needs a design that first swaps every cwv item out of the loadout.

---

### WP-CWV-03 Route every cwv lookup append through one recorded path

| Field | Value |
|---|---|
| Priority | P1 |
| Size | L (split: one commit per file, in the order of step 3) |
| Agent | any |
| Depends on | none; rig core (track H) for the RIG acceptance |
| Issues | advances #371, #948 |
| Source | A2-F05 |
| Streams | `character_weapon_variants/` only |

**Goal.** No cwv file appends to a `NetworkLookup` table by hand; every append goes through `_lib_network_lookup`, its result is recorded, and one log line per table reports what was added and what was refused.

**Context.**
- `CWV/_lib_network_lookup.lua:76-113` validates a lookup table and refuses to append to a damaged one. cwv calls it at two places only (`_cwv_item_registration_owner.lua:823`, where the result is thrown away, and `_cwv_outrider_projectile_wire.lua:176`).
- 35 other blocks compute `#tbl + 1` and `rawset` both directions by hand. The repo already counts them: `qa/baselines/network_lookup_append_budget.json` (cwv rows) enforced by `qa/check_network_lookup_append_budget.ps1`. Sites: `character_weapon_variants.lua:422-428`; `_cwv_core_templates.lua:207`; `_cwv_crowbill_runtime.lua:130`; `_cwv_skin_registry.lua:260,272,665,671`; `_cwv_musket_runtime.lua:149,196,559`; `_cwv_javelin_runtime_owner.lua:213,236,266,1209,1332,1367`; `_cwv_illusion_families.lua` (19 sites, first at `:76`).
- `_lib_network_lookup.lua` is a synced copy (`tools/shared_lib/`): do not edit it. `mod:dofile` returns a fresh module each call, so the record must hang on `mod`.
- Out of scope: the transactional owners (`CWV/*_construction_owner.lua`, `_cwv_old_musket_melee_owner.lua`, `_cwv_tuskgor_spear_style_construction.lua`) register on detached copies and publish through their own commit step. Leave them. Every name they add starts with `cwv_`.

**Steps.**
1. Test first: `qa/lua/tests/test_cwv_lookup_ledger.lua` with a stub `mod` whose `dofile` loads files from `character_weapon_variants/`. Assert: (a) two calls of the factory return the same object; (b) `register_named(nl, "weapon_skins", "cwv_x")` appends symmetrically and `rows` gains one entry with `inserted = true`; (c) a repeat returns the same index, `inserted = false`; (d) with a one-directional table (`nl.weapon_skins.orphan = 99`) the call returns nil and `summary()` counts one refusal; (e) `is_cwv_index(nl.weapon_skins, index)` is true only for appended indices.
2. Add `CWV/_cwv_lookup_ledger.lua`: `return function(mod)`; if `mod._cwv_lookup` exists return it; else load the lib with `mod:dofile("scripts/mods/character_weapon_variants/_lib_network_lookup")`, build `L` with `register(lookup, name)`, `register_named(network_lookup, table_name, name)` (same return values as the lib), `rows`, `is_cwv_index(lookup, index)`, `summary(network_lookup)` (per table name: `added`, `refused`, `first`, `last`) and `log(printf)` printing `[cwv:nl] table=<t> added=<n> refused=<n> first=<i> last=<i>` per table plus `[cwv:nl] REFUSED table=<t> name=<s> reason=<r>` per refusal; store it on `mod._cwv_lookup`.
3. Convert, one file per commit: (i) entry: change line 482 to `local _cwv_network_lookup = mod:dofile("scripts/mods/character_weapon_variants/_cwv_lookup_ledger")(mod)` and replace the body of `register_damage_profile` (`:422-428`) with a call to `mod:dofile(".../_cwv_lookup_ledger")(mod).register(lookup, profile_name)` (net nonblank lines must not grow; this removes two); (ii) `_cwv_core_templates.lua`; (iii) `_cwv_crowbill_runtime.lua`; (iv) `_cwv_skin_registry.lua`; (v) `_cwv_musket_runtime.lua`; (vi) `_cwv_javelin_runtime_owner.lua`; (vii) `_cwv_illusion_families.lua`. In each, replace the whole hand-written block (the `rawget` guard, `#tbl + 1`, both `rawset`s) with `mod._cwv_lookup.register_named(NetworkLookup, "<table>", key)` (or `mod:dofile(".../_cwv_lookup_ledger")(mod)` at the top of files that run before entry line 482). Also change `_cwv_item_identity_transport_owner.lua:16-17` to pass the ledger object instead of a fresh lib.
4. After each file, lower or delete its rows in `qa/baselines/network_lookup_append_budget.json` to the count the gate now measures.
5. In `CWV/_cwv_item_registration_owner.lua` at the end of `_auto_register_all` call `mod._cwv_lookup.log(printf)` once.

**Acceptance (machine, no human).**
- OFFLINE: suite exits 0; `pwsh -NoProfile -File qa/check_network_lookup_append_budget.ps1` exits 0 with no cwv row left in the baseline; `git grep -nE "local (idx|index|lookup_index) = #" -- character_weapon_variants/scripts/mods/character_weapon_variants` returns only non-lookup uses (review each hit).
- RIG: `qa/runtime/cwv/a2f05_lookup_ledger.lua`, arena `keep`: `local L = get_mod("character_weapon_variants")._cwv_lookup`; for every row with `inserted`, `T.expect` that `rawget(row.lookup, row.index) == row.name` and `rawget(row.lookup, row.name) == row.index`; `T.expect_eq(refused_total, 0)`; `host_forbid_log = { "[cwv:nl] REFUSED" }`. Also `T.expect_rt` for `issue567_skin_reverse_index_valid` and `issue1320_outrider_projectile_unit_and_wire`.
- Evidence class: S (gate) and R (ledger read-back). Advances #371 and #948 only; it does not close them.

**Guardrails.** The lib fails closed where the old code appended blindly. That is intended; do not add a fallback that appends anyway. Keep the exact text `_network_lookup.register_named(NetworkLookup, "item_names", key)` once in the registration owner and update the pin at `qa/lua/tests/test_cwv_entry_decomposition.lua:939-940` to the new entry string (T5). Do not move entry line 482. Do not change the ORDER in which names are appended inside a file.

**Stop and escalate if.** The RIG reports any refusal with the standard mod set (it means another mod leaves one-directional rows in that table: record table, name and reason, change nothing). Or a converted file would exceed its size ceiling (T1).

---

### WP-CWV-04 Add a solo send-side tap for mod lookup indices

| Field | Value |
|---|---|
| Priority | P1 |
| Size | M |
| Agent | any |
| Depends on | rig core (track H); WP-CWV-01 (without it the Outrider step FAILS, which is the correct verdict); WP-CWV-03 is optional and sharpens the oracle |
| Issues | advances #278, #371, #423, #424, #491 (sending side: R; receiving side stays C) |
| Source | A2-F01, A2-F19, A2 section 6c row 9 |
| Streams | new files under `qa/runtime/` only; no mod code |

**Goal.** A rig case that runs with one player and FAILS whenever cwv or WOC puts one of its own lookup indices on a vanilla RPC, game object or player-sync field.

**Context.**
- Most co-op crashes of this family are one event: a number taken from a mod-appended `NetworkLookup` row is sent on a vanilla message, and a peer whose table lacks that row decodes it with a strict lookup. The sending side can be observed alone, because a solo host still calls the send functions and still creates game objects.
- Send points: `NetworkTransmit.send_rpc`, `send_rpc_server`, `send_rpc_clients`, `send_rpc_all` (`scripts/network/network_transmit.lua:169,185,431,508`); `GameSession.create_game_object(game_session, go_type, init_table)` (`scripts/network/unit_spawner.lua:346`); the player-sync skin id set by `CosmeticUtils.update_cosmetic_slot` through `player:set_data(slot .. "_skin", id)` (`scripts/helpers/cosmetic_utils.lua:205-209,230-250`).
- Argument positions: `rpc_add_equipment(go_id, slot_id, item_id, weapon_skin_id)` (`scripts/unit_extensions/default_player_unit/inventory/simple_inventory_extension.lua:1447-1456`); `rpc_sync_loadout_slot(peer_id, local_player_id, slot_id, item_id, rarity_id, ...)` (`scripts/helpers/loadout_utils.lua:22-39`; the `send_rpc` form has the target peer as one extra leading argument). Game-object init fields filled from lookups: `item_name`, `item_template_name`, `husk_unit`, `pickup_name` (`scripts/network/game_object_initializers_extractors.lua:745,754-755`).
- Limit: a solo host never sends client-to-host messages (`rpc_attack_hit` is a local call on the host, `scripts/entity_system/systems/weapon/weapon_system.lua:179-183`). That direction is covered by the in-mod check `cwv_wire_safe_damage_profile_gate`.

**Steps.**
1. Add `qa/runtime/cwv/wire_tap_solo.lua` (arena `keep`). Inside the case define:
   - `is_mod_name(name)`: true for `^cwv_`, `^woc_`, `^units/cwv_`, `^units/woc_`, `outrider_grenade_launcher_template`, `cursed`.
   - `is_mod_index(lookup, id)`: decode with `rawget(lookup, id)`; true when `is_mod_name` of the result, or when `get_mod("character_weapon_variants")._cwv_lookup` exists and its `is_cwv_index(lookup, id)` is true (present after WP-CWV-03; `T.note("oracle", "ledger" or "names")`).
   - the tap: on the instance `Managers.state.network.network_transmit` set wrapper functions for the four send functions that append `{ rpc_name, args }` to a list and then call `NetworkTransmit.<name>(self, rpc_name, ...)`; replace `GameSession.create_game_object` with a wrapper that appends `{ go_type, init_table }`. Remove all wrappers in cleanup (set the instance fields to nil, restore the saved `GameSession.create_game_object`).
2. Drive: for careers `es_mercenary`, `wh_captain`, `dr_ranger`, `we_waywatcher` in turn (`Managers.state.network:request_profile(1, <profile>, <career>, true)`, then `T.local_hero()`): save the original ids with `BackendUtils.get_loadout_item_id(career, "slot_melee")` and `"slot_ranged"`; for every cwv seed whose `ItemMasterList` row lists that career in `can_wield` (seed ids from `get_mod("character_weapon_variants")._cwv_live.seed_ids()` when WP-CWV-05 has landed, else `<item_key>_001` for the keys in `CWV/_cwv_variant_catalog.lua`, skipping ids the backend does not hold): `BackendUtils.set_loadout_item(id, career, slot)`, `inventory:create_equipment_in_slot(slot, id)`, `inventory:wield(slot)`, `T.wait(1)`. `slot` is `"slot_" .. row.slot_type`. Restore the saved ids at the end of each career.
3. For the ranged variants `cwv_es_outrider_grenade_launcher`, `cwv_es_javelin`, `cwv_wh_javelin`, also spawn one projectile without input the way WP-CWV-01's RIG step 4 does, using each template's own `action_one.default.lookup_data`. If the javelin throw is refused by the peer gate (`[cwv:424] ... BLOCKED`), record `T.note` and continue: a blocked throw sends nothing.
4. Assertions, one `T.expect` per recorded message: for `rpc_add_equipment`, argument 3 against `NetworkLookup.item_names` and argument 4 against `NetworkLookup.weapon_skins`; for `rpc_sync_loadout_slot`, argument 4 against `item_names` and argument 5 against `NetworkLookup.rarities`; for every game object, the four named fields against `item_names`, `item_template_names`, `husks`, `pickup_names`; after each equip, `Managers.player:local_player():get_data(slot .. "_skin")` against `weapon_skins`. Each must NOT be a mod index. Add `T.expect(#records > 0, "tap saw traffic")` so an empty tap cannot pass.
5. Add `qa/runtime/woc/wire_tap_blightreaper.lua` with the same tap: on `es_mercenary` equip backend id `woc_blightreaper_001` in `slot_melee` (`T.require` it exists), same assertions, plus `T.expect_rt("WOC", "wire_woc_never_leaves_woc_key")`.
6. Add both files to a plan `qa/runtime/plans/cwv_wire.json`.

**Acceptance (machine, no human).**
- OFFLINE: the rig's script loader test accepts both files (table shape, no syntax errors).
- RIG: both cases PASS on a build that contains WP-CWV-01. To prove the tap can fail, run `wire_tap_solo.lua` once against the commit before WP-CWV-01: the Outrider game object must produce a FAIL on `item_template_name`. Record both run ids.
- Evidence class: R for "this build sends no cwv or WOC index while equipping and firing every variant solo". It does not close the listed issues alone; the VP for each issue cites this case for its sending half and leaves the remote view as C.

**Guardrails.** Wrap on the INSTANCE (`network_transmit`), not on the `NetworkTransmit` class, and always restore. Never leave a cwv item equipped at the end of a case. Do not change mod code in this card; if the tap finds a leak, write it up for a new card.

**Stop and escalate if.** A FAIL appears on a field other than the Outrider's `item_template_name` (new leak: record rpc or go_type, field, decoded name, variant). Or `Managers.state.network.network_transmit` is nil in the keep (the rig arena is not a network session: `T.require` it and report INCONCLUSIVE).

---

### WP-CWV-05 Add live variant checks that read spawned units

| Field | Value |
|---|---|
| Priority | P1 |
| Size | L (split: step 1-3 module and unit test; step 4 command; step 5 rig sweep) |
| Agent | any |
| Depends on | none for the module; rig core (track H) for the sweep |
| Issues | advances #417, #482, #692, #747, #914, #915 and every `verify-fix` issue whose claim is "variant X equips with the right mesh, template and scale" (class R part) |
| Source | A2-F08, A2 section 6a and 6c rows 1-6 |
| Streams | `character_weapon_variants/` only |

**Goal.** One callable entry, `mod._cwv_live.run(owner_unit, slot_name)`, reads the weapon units actually spawned on a player, compares them with the variant catalog, prints one engine `printf` line per check and returns the rows; a rig sweep equips every variant and asserts on those rows.

**Context.**
- The in-game suite (112 checks) never reads a spawned unit: in its five modules there are 0 reads of `Unit.local_scale`, 0 `World.*` calls and 1 `ScriptUnit.extension`. It checks tables and calls mod functions with fake inputs.
- What vanilla stores after an equip: `equipment.slots[slot]` with `item_data`, `item_template`, `right_unit_1p`, `right_unit_3p`, `left_unit_1p`, `left_unit_3p` (`scripts/unit_extensions/default_player_unit/inventory/gear_utils.lua:76-93`); `inventory:equipment()` returns it (`.../simple_inventory_extension.lua:504`). The 3P unit resource is the hand unit path plus `_3p` (`gear_utils.lua:155-172`).
- Engine reads that a fix cannot fake: `Unit.is_a(unit, "<resource path>")` (used at `scripts/entity_system/systems/pickups/pickup_system.lua:243`), `Unit.local_scale(unit, 0)`, `Application.can_get("unit", path)`, `Unit.has_animation_event(unit, event)` (`scripts/entity_system/systems/ai/ai_inventory_extension.lua:112`). The 3P wield event vanilla fires is `template.wield_anim_career_3p[career]`, else `wield_anim_3p`, else the 1P wield event (`simple_inventory_extension.lua:1922-1924,2007-2012`).
- Authored expectations: the catalog row (`right_hand_unit`, `left_hand_unit`, `template`, `effective_templates`, `no_left_hand`) and `_om.weapon_transform.plan_cwv_hand_transform(def, hand, perspective)`, which returns `scale`, `scale_multiplier`, `offset`, `rotation` (`CWV/_cwv_weapon_transform_owner.lua:554-572,735-747`). Scale is written as an absolute value; offset is relative to the unit's own position, so only scale is asserted.

**Steps.**
1. Test first: `qa/lua/tests/test_cwv_live_checks.lua`. Load the new module with `loadfile` and call its pure function `evaluate(expected, observed)` with one all-correct observation (expect no FAIL row) and one observation per defect: missing `ItemMasterList` row, `name` not equal to base, wrong 3P unit (`is_a.right_3p = false`), scale off by 0.01, package not loadable, missing wield event. Each must yield exactly one FAIL row with the matching `check` name.
2. Add `CWV/_cwv_live_checks.lua` exporting `install(mod, ctx)` which returns and stores on `mod._cwv_live`:
   - `seed_ids()`: a copy of `ctx.om._cwv_blacksmith_seed_ids` (seed backend id -> item key).
   - `expected(item_key, career_name)`: from the definition and its base row: `item_key`, `base_weapon`, `template_names` (the set of `def.template`, the base row's `template`, and every `name` in `def.effective_templates`), `units = { right_1p, right_3p, left_1p, left_3p }` (definition unit or base unit; left only when the definition or base has one and `no_left_hand` is not set), `scale = { right_1p, right_3p, left_1p, left_3p }` (the plan's `scale` when it has no `scale_multiplier`, else nil), `wield_event_3p`.
   - `observe(owner_unit, slot_name, expected)`: reads `ScriptUnit.extension(owner_unit, "inventory_system"):equipment().slots[slot_name]` and returns `row_present`, `row_cwv_variant`, `row_name` (from `rawget(ItemMasterList, item_key)`), `item_key` (`_om._cwv_key_for_item(backend_id, item_data)`), `template_ok` (`rawequal(slot.item_template, rawget(Weapons, n))` for some `n` in `template_names`), `alive` and `is_a` per unit, `scale` per unit as three numbers from `Vector3.to_elements(Unit.local_scale(unit, 0))`, `can_get` for each 3P path, `has_wield_event`.
   - `evaluate(expected, observed)`: pure; returns rows `{ check, status = "PASS" | "FAIL" | "SKIP", detail }` for `registered`, `name_is_base`, `item_key`, `template`, `unit_right_1p`, `unit_right_3p`, `unit_left_1p`, `unit_left_3p`, `scale_*` (tolerance 0.001), `package_3p`, `wield_event_3p`. A check with no expectation is SKIP.
   - `run(owner_unit, slot_name)`: resolves the item key of the slot, calls the three functions, prints `printf("[cwv:live] item=%s check=%s status=%s detail=%s", ...)` once per row and `[cwv:live] SUMMARY item=%s pass=%d fail=%d skip=%d`, returns the rows.
3. Load it from `CWV/_cwv_commands_lifecycle.lua` (not from the entry, T1): inside the install function, after the `cwv_give` command, add `mod:dofile("scripts/mods/character_weapon_variants/_cwv_live_checks").install(mod, { om = _om, variant_definitions = _variant_definitions })` (before the `mod.on_enabled()` line if WP-CWV-02 has landed).
4. In the same place register `mod:command("cwv_live_check", "Check the wielded cwv weapon against its catalog row", ...)`: runs `run` on the local hero's wielded slot and echoes the summary line.
5. Rig sweep `qa/runtime/cwv/live_variant_sweep.lua`, arena `keep`: for the four careers of WP-CWV-04 step 2, for every seed the career can wield: equip as in WP-CWV-04 step 2, `T.wait_until` the slot's item resolves to the key, `T.wait(2)`, `local rows = get_mod("character_weapon_variants")._cwv_live.run(hero, slot)`, then `T.expect(row.status ~= "FAIL", item_key .. ":" .. row.check .. ":" .. tostring(row.detail))` per row; `T.note` the unit's local position and rotation; `T.shot(item_key)` for the human list. Restore the original loadout. `host_forbid_log = { "[cwv:register] DENIED", "admission=denied" }`.

**Acceptance (machine, no human).**
- OFFLINE: suite exits 0 including `test_cwv_live_checks`.
- RIG: `live_variant_sweep.lua` PASSES with at least 30 distinct item keys reaching a SUMMARY line (`T.expect(count >= 30)`); 32 live definitions exist, the Crossbow depends on a setting.
- Evidence class: R for registration, base name, template, unit resources, scale, package and wield-event presence per variant. Not covered (class V): how the weapon looks, position and rotation correctness, attack animations. Not covered (class C): the remote view.

**Guardrails.** `evaluate` must not touch engine globals (it is the unit-tested core). Do not add checks that call cwv's own resolvers for the EXPECTED side beyond the two named in Context; the point is to compare the engine with authored data. Do not put any of this in the entry or in a `_cwv_regression_*.lua` file (T1).

**Stop and escalate if.** A variant FAILS `unit_*` or `template` in the sweep: that is a product finding, not a harness problem. Record item, check and detail and open one item per variant family; do not loosen the check. If more than five variants are INCONCLUSIVE because the seed is missing from the backend, stop: the acquisition path (`CWV/_cwv_acquisition.lua`) is the defect.

---

### WP-CWV-06 Make regression verdicts machine-readable and truthful

| Field | Value |
|---|---|
| Priority | P1 |
| Size | S |
| Agent | any |
| Depends on | none |
| Issues | advances #1656 |
| Source | A2-F08 |
| Streams | `character_weapon_variants/` and `weapons_of_chaos/` |

**Goal.** Every check of `/cwv_regression_test` and `/woc_regression_test` writes exactly one engine `printf` line with its verdict, no check reports PASS when it could not run, and the suite leaves no fake peer behind.

**Context.**
- cwv runner: `CWV/character_weapon_variants.lua:226-250`. PASS is written with `mod:info` and FAIL with `mod:warning`, which depend on VMF's logging settings; only SKIP, XFAIL and XPASS use `printf`. WOC runner: `WOC/weapons_of_chaos.lua:119-133`, `mod:echo` only. A rig or a log reader therefore cannot rely on a line per check.
- WOC checks `issue422_wire_safety_unconditional_singleton` and `no_unit_path_package_force_load` read their own source through `_rt_src_read`, which returns nil in the shipped game; the checks then `return` nil, which the runner counts as PASS (`WOC/weapons_of_chaos.lua:99-118,1238-1239,1276`).
- cwv check `issue474_old_musket_hot_join_identity_and_remote_fire` registers a fake peer `rt474-peer` in the live identity table and never clears it (`CWV/_cwv_regression_identity.lua:1382-1389`); other checks do clear theirs on the same live table (`:844,970`).
- Two cwv checks cannot fail on a regression and must not be cited as evidence: `cwv_itemmasterlist_uses_rawget` and `cwv_networklookup_uses_rawget` (`CWV/_cwv_regression_runtime_identity.lua:413-478`) compare a constant with itself and test `rawget`. They are pinned by `qa/lua/tests/test_cwv_marker_check_contract.lua`; leave them in place.

**Steps.**
1. Test first: in `qa/lua/tests/test_regression_runner_verdicts.lua` add to the cwv cases `H.truthy(find_line(printfs, "[regression] PASS <name>"))` and `H.truthy(find_line(printfs, "[regression] FAIL <name>"))` for one passing and one failing synthetic check, and add a WOC case (lift `mod:command("woc_regression_test"` from `weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua` with the same `extract_command` helper) asserting `[regression] PASS`, `[regression] FAIL` and `[regression] SKIP` lines in `printfs`.
2. cwv runner: in the PASS branch add `pcall(printf, "[regression] PASS %s", c.name)` and in the FAIL branch `pcall(printf, "[regression] FAIL %s: %s", c.name, tostring(err))`, each on the SAME line as the existing statement, separated by `;` (the entry may not gain nonblank lines, T1).
3. WOC runner: add the three `pcall(printf, "[regression] <VERDICT> %s...", ...)` calls on the existing lines in the same way.
4. WOC: change the two `if not txt then return end` lines to `if not txt then return "skip: source text is not readable in the shipped game" end`.
5. cwv: in `issue474_old_musket_hot_join_identity_and_remote_fire`, after the loop that accepts the identities, clear the peer the way `:970` does: `_om._appearance_lifecycle:clear_peer("rt474-peer")` (method defined at `CWV/_cwv_appearance_lifecycle.lua:338`). `CWV/_cwv_regression_identity.lua` is at its 1,500-line ceiling: remove one comment line in the same check for every line you add.

**Acceptance (machine, no human).**
- OFFLINE: suite exits 0. `git grep -c 'pcall(printf, "\[regression\] PASS' -- character_weapon_variants/scripts weapons_of_chaos/scripts` reports 2 files. `git grep -c "skip: source text" -- weapons_of_chaos/scripts` reports 2 hits.
- RIG: boot plus `keep` suite sweep: `host_expect_log` contains one `[regression] ` line for each of 5 named checks per mod (pick any five registered names), and the two WOC checks appear as SKIP, not PASS. Assert after the sweep that the cwv identity table holds no `rt474-peer`: `T.expect(select(1, get_mod("character_weapon_variants")._cwv_peer_appearance.resolve_peer("rt474-peer", "slot_melee", "es_handgun")) == nil)`.
- Evidence class: U for the runner output, R for the sweep. #1656 is advanced, not closed (its remaining failing checks are separate items).

**Guardrails.** Keep the existing echo texts and the existing `printf` formats for SKIP, XFAIL and XPASS unchanged: `test_regression_runner_verdicts.lua` runs the lifted runner and asserts on them. Net nonblank lines in both entries must not grow. Do not delete or rename any check in this card.

**Stop and escalate if.** The lifted runner in the offline test no longer extracts (the test finds the block by `mod:command("<name>"` up to the first line that is exactly `end)`): restore that shape rather than changing the extractor.

---

### WP-CWV-07 Make variant admission failures loud and re-pinnable

| Field | Value |
|---|---|
| Priority | P1 |
| Size | M |
| Agent | any (the redesign named under "Stop and escalate" needs a strong agent) |
| Depends on | none; rig core (track H) for the RIG acceptance |
| Issues | advances #1656, #628 |
| Source | A2-F04, A2-F10 |
| Streams | `character_weapon_variants/` only |

**Goal.** When a variant family refuses to register, the log says which item and why on every boot, an in-game check fails, and an offline test fails as soon as weapon_tweaker's history catalog and cwv's pinned values disagree.

**Context.**
- `_build_entry` returns nil for five families unless a per-family admission function answers true (`CWV/_cwv_item_registration_owner.lua:259-320`, five copies of one block). A refused item is simply absent from the inventory; the only trace is a `printf` capped at 16 lines per family.
- The admission chain compares live tables with exact values. Example: `CWV/_cwv_history_producer_binding.lua:33-35,61` requires `wt._wt_history_runtime.catalog.current_source.revision == "93dea911a4cc464a0eb51cfdc3a443297bfc4550"` (the commit of the decompiled 6.13.0 source, also at `weapon_tweaker/scripts/mods/weapon_tweaker/_wt_history_2_0_10_catalog.lua:8`); `CWV/_cwv_shortsword_history_envelope.lua:10-12,21-27,98-99` pins blob hashes and the damage-profile name `medium_burning_smiter_stab_H`. 29 forty-character hash literals (23 distinct) sit in six runtime files (`_cwv_mace_sword_donor_envelope.lua`, `_cwv_elven_shield_history_envelope.lua`, `_cwv_sword_donor_envelope.lua`, `_cwv_shortsword_history_envelope.lua`, `_cwv_tuskgor_history_envelope.lua`, `_cwv_history_producer_binding.lua`).
- So a game patch, or an edit of weapon_tweaker's catalog, makes weapons disappear with no error. This card does not remove the pins (decision D-CWV-03); it makes the failure impossible to miss and tells the next agent what to re-pin.

**Steps.**
1. Test first: `qa/lua/tests/test_cwv_admission_pins.lua`. (a) Read as text the six cwv files named in Context and the `_wt_history_*.lua` files of BOTH `weapon_tweaker/scripts/mods/weapon_tweaker/` and `weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/` (name them in the test; take the list from `git ls-files`, 19 per tree today). Assert that every 40-hex string literal in the cwv files (23 distinct today) occurs in each tree's text, and that the literal compared with `"revision"` in `_cwv_history_producer_binding.lua` is the `revision` value of `current_source` in `_wt_history_2_0_10_catalog.lua`. (b) Drive the new denial helper of step 2 with a fake admission that returns false: expect one `[cwv:register] DENIED item=<key> family=<name> reason=admission` line and `denied[key] == "admission"`; drive it twice: still one line.
2. In `CWV/_cwv_item_registration_owner.lua` replace the five copied blocks at `:259-320` with one table `_ADMISSIONS = { { keys = { cwv_es_javelin = true, cwv_wh_javelin = true }, family = "javelin", admit = _javelin_admission }, ... }` (old musket, shortsword, elven shield, greataxe) and one loop with the existing condition: refuse when `existing ~= nil and not rawequal(existing, _registered_keys[key])`, or `pcall(admit, def)` fails, or its result is not `true` (three of the five copies write `~=` instead of `rawequal`; for plain tables that is the same test). On refusal call `deny(def.item_key, family, reason)`: record in a local `denied` table and print the line of step 1(b) once per item per session with `pcall(printf, ...)`. Keep the old capped `[cwv:428] owner=<family>_item edge=build_entry admission=denied ...` line too. Export `denied` as `_om.item_registration.denied`.
3. In `CWV/_cwv_regression_runtime_identity.lua` register `cwv_all_live_definitions_registered`: for every definition that is not `skin_only`, not `cwv_retired`, and not `cwv_es_crossbow` while `mod:get("enable_cwv_es_crossbow")` is false, require `ctx.registered_keys[def.item_key]`; the failure string lists each missing key with `_om.item_registration.denied[key]`.
4. At the top of `CWV/_cwv_history_producer_binding.lua` add a three-line comment: which literal to change when the decompiled source moves, and that `test_cwv_admission_pins` names the files.

**Acceptance (machine, no human).**
- OFFLINE: suite exits 0. Changing the `revision` string in a scratch copy of `_wt_history_2_0_10_catalog.lua` makes `test_cwv_admission_pins` fail and name the cwv file and literal (run it once to prove, do not commit). `git grep -c "edge=build_entry admission=denied" -- character_weapon_variants/scripts` reports 1 (was 5).
- RIG: `qa/runtime/cwv/a2f04_all_variants_registered.lua`, arena `keep`: `T.expect_rt("character_weapon_variants", "cwv_all_live_definitions_registered")`; for each live item key in the catalog `T.expect(rawget(ItemMasterList, key) ~= nil, key)`; `host_forbid_log = { "[cwv:register] DENIED", "admission=denied" }`. Run it once with weapon_tweaker loaded and once without.
- Evidence class: U for the pin agreement, R for "all variants registered on this build".

**Guardrails.** Behaviour of admission must not change: same conditions, same order of the five families, same return of nil. Do not edit any `*_envelope.lua` or `*_construction_owner.lua` logic. The registration owner has 897 nonblank lines; this change should shrink it.

**Stop and escalate if.** The RIG shows a denial on the current build (a real product failure: report family and reason; the re-pin is a separate task). Or you are asked to delete the envelope modules or relax their `rawequal` and hash checks: that is the redesign "build from the donor, then validate the result" and needs decision D-CWV-03 and a strong agent.

---

### WP-CWV-08 Check the variant catalog against the decompiled source

| Field | Value |
|---|---|
| Priority | P1 |
| Size | M |
| Agent | any |
| Depends on | none |
| Issues | advances #948; replaces manual gates U-1, U-2 and the unit catalogue step of G-CROSS-CHAR in `character_weapon_variants/DEFINITION_OF_DONE.md` |
| Source | A2-F03, A2-F13, A2 section 2.3 rows 3-6 |
| Streams | `character_weapon_variants/` (read), new test and fixture under `qa/lua/` |

**Goal.** An offline test fails when a catalog row names a base weapon, unit path, career, template or swap key that does not exist in the game data, and the Definition of Done names that test instead of a manual step.

**Context.**
- `character_weapon_variants/DEFINITION_OF_DONE.md` asks the author to read the base `ItemMasterList` entry and the template by hand (gates U-1, U-2) and to list every unit reference (G-CROSS-CHAR). Nothing enforces it: no script references the file, and the required changelog footer appears in 70 of 485 versions.
- A wrong unit path is an uncatchable engine fault at mod load, because cwv force-loads variant units (`CWV/_cwv_husk_residency_owner.lua:221-253`). A stale swap key silently disables a conversion (the 6.11 damage-profile rename recorded in issue #1656).
- The audit ran these checks by hand on 6.13.0 and they pass today: all 25 distinct `base_weapon` keys exist; all 24 literal vanilla unit paths exist (16 in `scripts/network_lookup/inventory_package_list.lua`, 8 only in DLC lists such as `scripts/settings/dlcs/bless/bless_equipment_settings.lua:153-163`, field `settings.inventory_package_list`); the Cudgel and Sword-and-Mace swap keys occur in `scripts/settings/equipment/weapon_templates/1h_falchions.lua` and `dual_wield_hammer_sword.lua`.
- The offline suite cannot read the decompiled repo, so the game facts must come from a committed fixture with provenance, like `qa/lua/fixtures/cwv_javelin_construction_source.provenance.json`.

**Steps.**
1. Add the generator `qa/lua/fixtures/gen_cwv_vanilla_catalog.py` (argument: path to `<repos>/Vermintide-2-Source-Code`). It writes `qa/lua/fixtures/cwv_vanilla_catalog_native.lua` returning a table with: `item_keys` (every key matching `^ItemMasterList\.([a-z0-9_]+) = \{` in `scripts/settings/equipment/item_master_list*.lua` and `scripts/settings/dlcs/*/item_master_list*.lua`, value = its `template` string when the block has one); `units` (every `"units/..."` string in `scripts/network_lookup/inventory_package_list.lua` and in the `inventory_package_list` blocks of `scripts/settings/dlcs/*/*_equipment_settings.lua`); `templates` (per weapon template file under `scripts/settings/equipment/weapon_templates/`: the template names assigned to `Weapons.<name>` or returned, and the set of string values of `damage_profile`, `damage_profile_left`, `damage_profile_right`, `hit_effect`, `impact_sound_event`, `no_damage_impact_sound_event`); `anims` (strings of `scripts/network_lookup/anims_lookup_table.lua`). It also writes `cwv_vanilla_catalog_native.provenance.json` with `native_commit` (output of `git rev-parse HEAD` in the source repo) and the file count. Run it and commit both outputs.
2. Add `qa/lua/tests/test_cwv_catalog_static.lua`. Load the catalog the way `qa/lua/tests/test_cwv_regression_harness_1656.lua:31-40` does (`dofile(root .. "_cwv_variant_catalog.lua")({ om = om }).definitions` with the pure policy modules loaded into `om`). For each of the 35 rows assert: `base_weapon` is in `item_keys`; every `right_hand_unit` / `left_hand_unit` that starts with `units/weapons/player/` is in `units` together with its `_3p` form (skip `units/weapons/player/wpn_invisible_weapon`); paths starting with `units/cwv_` appear in `character_weapon_variants/resource_packages/character_weapon_variants/character_weapon_variants.package`; every career is one of the 20 vanilla career names; when `template` is a key of `templates` it is vanilla, otherwise the string must occur as `Weapons.<template>` or `Weapons[...]` assignment target in a `CWV/*.lua` file. Then load the swap maps: require every key of `_CUDGEL_DAMAGE_PROFILE_SWAP`, `_CUDGEL_HIT_EFFECT_SWAP`, `_CUDGEL_IMPACT_SOUND_SWAP` to be in the value set of `one_hand_falchion_template_1`, and the keys of `_SAM_RIGHT_HAND_SWAP` and `_SAM_LEFT_HAND_SWAP` in that of the mace-and-sword template (these maps are locals of `CWV/_cwv_core_templates.lua:661-675,759-788`; read them by loading the lines between the `local _X = {` and its closing brace with `loadstring`, as other tests in this folder do). Require the five attack remap targets in `CWV/_cwv_cross_access.lua:214-294` to be in `anims`. Every failure message starts with the row's `item_key`.
3. Register the test in `qa/lua/run.lua`.
4. In `character_weapon_variants/DEFINITION_OF_DONE.md`, under "How to use this file", add a short table `Gate | Enforced by` with: U-1 and U-2 -> `qa/lua/tests/test_cwv_catalog_static.lua`; G-CROSS-CHAR unit list -> same test; U-9 inventory and equip cells -> `qa/runtime/cwv/live_variant_sweep.lua` (WP-CWV-05) once it exists; all other gates -> manual. Delete nothing else.

**Acceptance (machine, no human).**
- OFFLINE: suite exits 0. In a scratch copy, change one character in (a) one `base_weapon`, (b) one unit path, (c) one cudgel swap key: each makes `test_cwv_catalog_static` fail with that row's `item_key` (or the map name) in the message. Do not commit the scratch changes.
- Evidence class: S. No RIG part.

**Guardrails.** The fixture is data only: never `require` it from mod code and keep it out of `character_weapon_variants/`. Do not "fix" a catalog row to make the test pass without checking the decompiled source for the right value. Rows whose unit comes from `_om.greataxe`, `_om.crowbill_family` or `_om.dawi_maces` are resolved by loading those pure modules into `om` (the loader named in step 2 does this).

**Stop and escalate if.** The test fails on the current catalog after a correct generator run: that is a real defect in a shipped variant. Report the row; fixing it is a separate card. If the decompiled source repo is at a different commit than `93dea911`, regenerate, and report which rows changed status.

---

### WP-CWV-09 Freeze the shared `_om` table and convert one module

| Field | Value |
|---|---|
| Priority | P2 |
| Size | M |
| Agent | any (removing `_om` from a large module needs a strong agent: load order is the contract there) |
| Depends on | WP-CWV-01, WP-CWV-03, WP-CWV-05 (they add or remove `_om` uses; take the baseline after them) |
| Issues | advances #1273, #1656 |
| Source | A2-F06 |
| Streams | `character_weapon_variants/` only |

**Goal.** An offline test stops any cwv file from gaining new uses of the shared `_om` table, new modules use explicit arguments only, and the Rapier owner is converted as the worked example.

**Context.**
- `CWV/character_weapon_variants.lua:55` creates `local _om = {}` and hands it to almost every module. Measured: 286 distinct fields, 1,597 `_om.` references in 29 files. Modules publish functions onto it and other modules look them up by name later, so a renamed field or a changed load order breaks the boot and no tool sees it (issue #1273; in #1656 twelve failing checks were traced to names that were no longer bound after the entry was split).
- The table exists because the entry hit Lua 5.1's limit of 200 local variables (`:17-18`, `:49-55`), not by design.
- Smallest user: `CWV/_cwv_rapier_runtime_owner.lua` (one use, `_om.rapier_contract.disable_pistol(template, _always_false)`; the module is called from the entry at `:904-907`).

**Steps.**
1. Test first: `qa/lua/tests/test_cwv_om_ratchet.lua`. Starting from the entry text, collect module names from every `scripts/mods/character_weapon_variants/<name>` string, read each file, repeat until no new name appears. For each file count `_om.` occurrences on lines that do not start with `--`. Compare with a table `BASELINE = { ["<file>"] = <count>, ... }` written into the test: fail when a file's count is above its baseline or when a file not in the table has a count above 0. Generate the table by running the counter once on the tree as it is when you start. Register the test in `qa/lua/run.lua`.
2. Convert the Rapier owner: in `CWV/_cwv_rapier_runtime_owner.lua` replace `local _om = assert(ctx.om, ...)` with `local _rapier_contract = assert(ctx.rapier_contract, "cwv rapier owner requires rapier_contract")` and the one use with `_rapier_contract.disable_pistol(template, _always_false)`. In the entry call at `:904-907` replace the line `om = _om,` with `rapier_contract = _om.rapier_contract,` (same number of nonblank lines, T1).
3. Update the pinned string at `qa/lua/tests/test_cwv_rapier_contract.lua:64` to the new call text (T5), and set the Rapier file's baseline to 0.
4. Add to `character_weapon_variants/DEVELOPMENT.md` (top of the architecture section) three lines: new modules receive what they need as named `ctx` fields and return what they provide; they do not read or write `_om`; `test_cwv_om_ratchet` enforces it.

**Acceptance (machine, no human).**
- OFFLINE: suite exits 0. `git grep -c "_om" -- character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_rapier_runtime_owner.lua` returns no match. Adding one `_om.x = 1` line to any module in a scratch copy makes `test_cwv_om_ratchet` fail and name the file.
- RIG: boot plus `keep`: `T.expect(rawget(Weapons, "rapier_template") ~= nil)`, `T.expect(rawget(Weapons, "rapier_template").ammo_data == nil)`, and the `cwv_es_rapier` rows of `qa/runtime/cwv/live_variant_sweep.lua` (WP-CWV-05) PASS.
- Evidence class: S for the ratchet, R for "Rapier still builds".

**Guardrails.** Do not convert any other module in this card. Do not reorder entry lines. Lowering a baseline number is always allowed; raising one is not. The Rapier owner also writes `wield_anim_career_3p` on the vanilla `fencing_sword_template_1` (`CWV/_cwv_rapier_runtime_owner.lua:98-104`): leave that as it is.

**Stop and escalate if.** A card you are executing seems to need a new `_om` field: pass the value through `ctx` or put it on `mod` with a `_cwv_` name, and say so in the commit. If the offline module walk misses files that `git ls-files` shows (modules loaded through a computed path), list them in the test by hand and report it.

---

### WP-CWV-10 Measure the cost of the global `Unit` hooks

| Field | Value |
|---|---|
| Priority | P2 |
| Size | M |
| Agent | any |
| Depends on | rig core (track H) |
| Issues | none |
| Source | A2-F07 |
| Streams | `character_weapon_variants/` (one small export) and `qa/runtime/` |

**Goal.** The per-frame cost of cwv's four hooks on engine `Unit` functions is a recorded number from a rig run, with a pass limit, so the decision to keep or redesign them rests on evidence.

**Context.**
- `CWV/_cwv_custom_mesh_runtime.lua:472-509` hooks `Unit.node`, `Unit.has_node`, `Unit.flow_event` and `Unit.set_flow_variable` for every caller in the game, to redirect lookups from the Old Musket's custom mesh to a hidden vanilla rifle (the "FX proxy", `:397-462`). The comment at `:466-468` says so.
- Every call to a VMF-hooked function goes through VMF's dispatcher, which builds a new table for the return values on each call and unpacks it again (`vmf/scripts/mods/vmf/modules/core/hooks.lua:78-81,176-187`). VMF cannot remove a hook, only mark it inactive, and an inactive hook still goes through the dispatcher (`:137-168`).
- Nobody has measured how many such calls happen per frame. The other per-frame cwv hooks (`CharacterStateHelper.move_on_ground` / `move_in_air`, `GenericAmmoUserExtension.update`, `WeaponSpreadExtension.update`) are not measured by this card.

**Steps.**
1. In `CWV/_cwv_custom_mesh_runtime.lua`, on the line before `mod:hook(Unit, "node", ...)`, publish the pre-hook functions for tests: `mod._cwv_engine_originals = { node = Unit.node, has_node = Unit.has_node, flow_event = Unit.flow_event, set_flow_variable = Unit.set_flow_variable }`.
2. Add `qa/runtime/cwv/a2f07_unit_hook_cost.lua`, arena `mission:military` (level key at `scripts/settings/level_settings.lua:1264`), with no cwv weapon equipped: this is the cost every session pays.
   - `T.require(type(os) == "table" and type(os.clock) == "function", "os.clock")` and `T.require(get_mod("character_weapon_variants")._cwv_engine_originals ~= nil)`.
   - Count: for each of the four names replace `Unit[name]` with a counting wrapper around the current value for 300 frames (`T.frames(300)`), then restore. `T.note` calls per frame for each.
   - Cost per call: pick a node name `n` for which the original `has_node(hero, n)` is true (try `"j_spine"`, `"j_head"`, `"root_point"`; INCONCLUSIVE if none). Time 200,000 calls of `Unit.has_node(hero, n)` and of the original `has_node(hero, n)` with `os.clock()`; the same for `Unit.node`. The difference divided by 200,000 is the added cost per call. Use the `has_node` figure for `flow_event` and `set_flow_variable` (they cannot be called in a loop safely).
   - `ms_per_frame = sum(calls_per_frame[name] * added_cost[name]) * 1000`. `T.note` it. `T.expect(ms_per_frame < 0.25, "Unit hook cost per frame")`.
   - Repeat the count once in the same level after spawning a horde (`T.spawn` 30 `skaven_clan_rat`) and `T.note` the second figure; the assertion uses the larger one.

**Acceptance (machine, no human).**
- OFFLINE: suite exits 0 (the export is one line; no test pins the hook block: check with `git grep -n "_orig_unit_has_node" -- qa`).
- RIG: the case runs to a verdict and `summary.json` contains the four call counts, the two per-call costs and `ms_per_frame`. PASS means the hooks cost under 0.25 ms per frame (1.5% of a 60 fps frame) and A2-F07 is downgraded with the number attached. FAIL is a valid result of this card.
- Evidence class: R.

**Guardrails.** Do not change, gate or remove the four hooks in this card. Do not hook anything on `Unit` from the mod; the counting wrappers live in the rig case and are restored in cleanup. `os.clock` availability in the game VM is [unverified]; if it is missing, report INCONCLUSIVE with that reason, do not invent a timer.

**Stop and escalate if.** The case FAILS. The only real fix is to remove the FX proxy (make the custom unit answer the node and flow lookups itself, or make a hidden vanilla rifle the gameplay unit and the custom mesh its visual child). That is a redesign of the Old Musket and needs decision D-CWV-06 and a strong agent. Write the numbers down and stop.

---

### WP-CWV-11 Play a remote Old Musket shot once

| Field | Value |
|---|---|
| Priority | P2 |
| Size | S |
| Agent | any |
| Depends on | none |
| Issues | advances #474, #1211 |
| Source | A2-F14 |
| Streams | `character_weapon_variants/` only |

**Goal.** When another player fires the Old Musket, the observer triggers the shot sound once, whichever of the two channels delivers the report first.

**Context.**
- The shooter sends each shot twice: `op = "fire"` on `cwv_old_musket_mode_v1` and a `cwv_musket_fire` payload on `cwv_item_identity` (`CWV/_cwv_old_musket_wire.lua:196-220`). The second channel was added when the first seemed not to deliver (`:222-226`); issue #1211's crash log shows the first delivering.
- Both receivers call `play_remote_fire` (`CWV/_cwv_old_musket_wire.lua:328-330`, `CWV/_cwv_item_identity_transport_owner.lua:314-319`), which has no duplicate check and calls `WwiseUtils.trigger_unit_event` (`CWV/_cwv_old_musket_wire.lua:294-317`). Static reading: two triggers per shot when both channels deliver.
- The Wwise world guard added for #1211 (`registered_level_world`, `:279-290`) must stay exactly as it is: an unregistered world there is an uncatchable crash (T4).

**Steps.**
1. Test first: add a case to `qa/lua/tests/test_cwv_old_musket_runtime_contracts.lua` (it already loads `_cwv_old_musket_wire.lua`; reuse its loader). Stub `Managers.world` (`has_world` true, `world` and `wwise_world` return tokens), a peer that resolves to a live `player_unit`, `Unit.alive` true, and `WwiseUtils.trigger_unit_event` as a counter. Deliver one shot through both paths: the handler registered for `cwv_old_musket_mode_v1` with `(peer, 1, "fire", "slot_ranged", "player_combat_weapon_rifle_fire", bid, 7)` and `_om._old_musket_play_remote_fire(peer, "player_combat_weapon_rifle_fire", "identity_channel", 7)`. Expect the counter at 1. A second shot with sequence 8 through both paths: counter 2. Two reports without a sequence number inside 0.1 s of game time: one trigger. The case fails before step 2 (counter 2 after the first shot).
2. In `CWV/_cwv_old_musket_wire.lua`: keep a local `fire_seq`, incremented in `_om._old_musket_publish_fire`; give the local `send` helper an optional sixth value and pass `fire_seq`; add `fire_seq = fire_seq` to the identity payload. Give `play_remote_fire` a fourth parameter `seq` and a table `last_fire_by_peer[sender_peer_id] = { seq = ..., t = ... }`: return false when `seq` is a number equal to the stored one, or when `seq` is nil and less than 0.1 s of `Managers.time:time("game")` passed since the stored time. Add `seq` as the last parameter of the mode-channel handler and forward it.
3. In `CWV/_cwv_item_identity_transport_owner.lua:316-317` pass `payload.fire_seq` as the fourth argument.

**Acceptance (machine, no human).**
- OFFLINE: suite exits 0 with the new case. `git grep -c "fire_seq" -- character_weapon_variants/scripts` reports 2 files.
- RIG: none possible solo (the receiver functions are private and need a remote sender). `T.expect_rt("character_weapon_variants", "issue474_old_musket_hot_join_identity_and_remote_fire")` must still pass in the `keep` sweep.
- Evidence class: U for the duplicate check. Whether the observer hears the shot at all is class C and V; this card does not change that.

**Guardrails.** Old builds must keep working: a receiver without this change ignores the extra value; a sender without it sends no sequence, which the 0.1 s window covers. Do not remove either channel (decision D-CWV-01 keeps the redundant delivery). Do not touch `registered_level_world`.

**Stop and escalate if.** The existing loader in the test cannot reach the registered channel handler (then capture it through the stub `mod.network_register` and say so). If you find a third sender of the shot report, list it.

---

### WP-CWV-12 Bundle every WOC script through a wildcard

| Field | Value |
|---|---|
| Priority | P2 |
| Size | S |
| Agent | any |
| Depends on | none |
| Issues | none open (prevents a repeat of the #595 start-up crash) |
| Source | A2-F18 |
| Streams | `weapons_of_chaos/` only |

**Goal.** A new WOC Lua module is bundled without anyone editing the package file.

**Context.**
- `weapons_of_chaos/resource_packages/weapons_of_chaos/weapons_of_chaos.package` lists 29 Lua files by name. A module that is `mod:dofile`d but not listed is missing from the shipped bundle and the game crashes at keep spawn. This happened in WOC v0.1.11 and again in v0.1.58 (`weapons_of_chaos/POSTMORTEMS.md`, issue #595).
- cwv uses one line, `"scripts/mods/character_weapon_variants/*"` (`character_weapon_variants/resource_packages/character_weapon_variants/character_weapon_variants.package:2`), and the coverage gate understands wildcards (`qa/check_dofile_package_coverage.ps1:251`).
- Every executing agent that adds a WOC module would otherwise hit this trap.

**Steps.**
1. Run `git grep -n "weapons_of_chaos.package" -- qa/lua/tests`. Six tests read the file; at least `qa/lua/tests/test_woc_wire_policy.lua:89-94` asserts single Lua lines. Change each assertion on a `"scripts/mods/weapons_of_chaos/<module>"` line to assert the wildcard line `"scripts/mods/weapons_of_chaos/*"` instead. Leave assertions on unit, material and texture lines alone. The suite now fails (the wildcard is not there yet).
2. In the package file replace the 29 lines inside `lua = [ ... ]` with the single line `"scripts/mods/weapons_of_chaos/*"`. Change nothing in the `material`, `unit` and `texture` blocks.

**Acceptance (machine, no human).**
- OFFLINE: suite exits 0. `pwsh -NoProfile -File qa/check_dofile_package_coverage.ps1` exits 0. `git grep -c "scripts/mods/weapons_of_chaos/" -- weapons_of_chaos/resource_packages` reports 1 line.
- RIG: on a build made after the change, `qa/runtime/woc/a2f18_package_wildcard.lua`, arena `keep`: `T.expect(get_mod("WOC") ~= nil)`, `T.expect(rawget(ItemMasterList, "woc_blightreaper") ~= nil)`, `T.expect_rt("WOC", "issue595_required_runtime_helpers_loaded")`.
- Evidence class: S for the package, R for "WOC still loads".

**Guardrails.** `WOC/_woc_appearance_census.lua` (test data, never loaded) will now be bundled; that is harmless, do not delete or move it here. Do not hand-edit `weapons_of_chaos/bundleV2/` or `.build-receipt.json`; the build regenerates them.

**Stop and escalate if.** A gate other than the two named above reads the old explicit list and fails (report the gate; do not restore the list).

---

## Owner decisions

The owner is unavailable. Agents proceed on the default. A card that would contradict a default stops and records the question.

| Id | Question | Conservative default for agents |
|---|---|---|
| D-CWV-01 | Must a player WITHOUT cwv or WOC be able to share a lobby with a player who has them (no crash, silent visual fallback)? | Yes. Keep the rule "no mod-only value on a vanilla message"; keep both delivery channels and all fallbacks. |
| D-CWV-02 | May the mods be switched off from the VMF menu at run time? | No. Non-togglable (WP-CWV-02). A user who had one disabled gets it enabled after the update. |
| D-CWV-03 | Keep the strict admission system (exact pins on weapon_tweaker's catalog and on vanilla values) or replace it with "build from the donor, then validate the result"? | Keep it. Only make failures loud and re-pinnable (WP-CWV-07). No agent deletes or relaxes an envelope module. |
| D-CWV-04 | cwv clears `required_dlc` on clones of weapons from five paid DLCs (`CWV/_cwv_item_registration_owner.lua:499`). Keep? | Leave the line unchanged. No card touches DLC gating. |
| D-CWV-05 | Is "only one player per lobby may hold the Blightreaper" required (about 1,570 lines, three channels, verifiable only with two clients)? | Keep as is. Fix defects only; add nothing to `WOC/_woc_shared_relic*.lua`. |
| D-CWV-06 | If WP-CWV-10 fails its limit, redesign the Old Musket so the four global `Unit` hooks can go? | No redesign without the owner. Record the numbers and stop. |
| D-CWV-07 | Scope of Combat Styles and of the Old Musket stance toggle (together about 12,000 lines). Extend, freeze or split out? | Freeze. Fix defects; no new style families, no new stance features. |
| D-CWV-08 | Unfinished content in the shipped build: Dawi Mace family with placeholder meshes (#602), Skarrik boss weapons with assets but no item (#614, #615, #642). | Leave as is. No new art, no new item registration, no removal. |
| D-CWV-09 | cwv edits four vanilla weapons' `can_wield` lists and seven vanilla templates with no setting (`CWV/_cwv_cross_access.lua:18-150`, `_cwv_variant_bootstrap_owner.lua:228-263`, `character_weapon_variants.lua:556-571`, `_cwv_rapier_runtime_owner.lua:98-104`). Move to weapon_tweaker? | Leave in cwv. Do not add new vanilla edits to cwv. |

Findings of `docs/audits/2026-11-13_FORMAL_AUDIT/evidence/A2.md` that have no card (S2 and S3, to keep the track at twelve): A2-F09 (source-text pins in offline tests), A2-F10 (declarative variant recipes), A2-F11 (vanilla edits, see D-CWV-09), A2-F12 (comments and stale documents), A2-F13 (package force-loads; partly covered by WP-CWV-08), A2-F15 (preview hooks on a class and its parent), A2-F16 (private Crafting in Modded functions), A2-F19 (Chaos Wastes identity; the tap of WP-CWV-04 can be extended to arena `deus`), A2-F20 (undeclared dependencies), A2-F21 to A2-F24.
