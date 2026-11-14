# Track GT: General Tweaker, Verminious Dreams Lighting, legacy `tweaker`

Author: auditor A6, 2026-11-13, against repo HEAD `592253d1`. Source findings: `docs/audits/2026-11-13_FORMAL_AUDIT/evidence/A6.md`. Line numbers are for that commit; match by function name if they drift.
Path shorthand used in every card: `GTD/` = `general_tweaker_dev/scripts/mods/general_tweaker_dev/`, `GTS/` = `general_tweaker/scripts/mods/general_tweaker/`, `VDL/` = `verminious_dreams_lighting_dev/scripts/mods/verminious_dreams_lighting_dev/`, `V2SRC/` = `Vermintide-2-Source-Code/`, `VMF/` = `Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/` (the last two are sibling repos under `<repos>`).

## Family brief

1. `general_tweaker_dev/` (mod id `gt_dev`, friends-only; version at `GTD/general_tweaker_dev.lua:3`): 93 Lua files. Host and solo utilities: bot fixes, cheats, level control, enemy and item spawners, lobby tools, time control, diagnostics. The entry file `GTD/general_tweaker_dev.lua` loads every `_gt_*.lua` module with `mod:dofile` in a fixed order.
2. `general_tweaker/` (mod id `gt`, PUBLIC; entry `GTS/general_tweaker.lua`): 59 files. It is a hybrid that matches no dev build: 36 files equal dev, 22 differ, 35 dev files are absent. Never assume a dev line, helper or module exists in stable. Open the stable file.
3. `verminious_dreams_lighting_dev/` and `verminious_dreams_lighting/`: one script each (`VDL/verminious_dreams_lighting_dev.lua`), two hooks, lighting profiles for three levels. `tweaker/`: frozen legacy mod (id `t`), built by nothing.
4. Offline tests live in `qa/lua/tests/test_*.lua`; each returns `function(H, repo_root)` and uses `H.test`, `H.equal`, `H.deep_equal`, `H.truthy`. A new file must also be added to the `suites` list in `qa/lua/run.lua` or the suite inventory check fails. Run everything with `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` (expect `[lua_unit_tests] OK`). To load a hook-registering module with no game, copy the stub loader at `qa/lua/tests/test_gt_official_verify_rollup.lua:12-62` (stub `mod`, `setfenv`, hooks captured by name).
5. Every change inside a mod directory needs a `MOD_VERSION` bump and a `CHANGELOG.md` entry citing the issue or finding (`qa/check_versions.ps1`). Cards do not build, deploy or upload; that is the release track.

Five traps:
- **T1 Stable is write-by-promotion.** `qa/check_dev_only_edits.ps1` exits 2 on any edit under `general_tweaker/` or `verminious_dreams_lighting/` unless `VT2_PROMOTION=1`, and CI needs a maintainer approval comment (`docs/PROMOTION_PROCESS.md:134-150`). Do not run `tools/promote/promote.ps1 -Apply` for one fix: it copies whole dev files into the hybrid. Use "Mode A" (`docs/PROMOTION_PROCESS.md:89-110`): the same small hunk in both trees, stable on its own branch, left for approval. Never self-authorize.
- **T2 File-size ratchet.** `qa/check_file_sizes.ps1` counts non-empty lines and fails (exit 2) when a frozen file grows past `qa/baselines/file_sizes_target.json`: `GTD/general_tweaker_dev.lua` 1910 (now 1909), `GTD/_gt_regression_checks.lua` 2236 (now 2236), `GTD/_gt_creature_spawner.lua` 1552 (now 1552), `GTD/general_tweaker_dev_data.lua` 1553 (now 1511). `GTD/_gt_bot_fixes.lua` (1485) and `GTD/_gt_bot_teleport_lab.lua` (1489) fail if they reach 1500. Put new code in new files. For every line added to a frozen file, delete a comment line in the same file (the extraction-history comments at `GTD/general_tweaker_dev.lua:1601-1711` are safe to trim).
- **T3 VMF saves defaults.** On first load VMF writes each widget's `default_value` into the user's settings (`VMF/options.lua:603-604`). Changing `default_value` later changes nothing for existing users. `mod:set(id, value)` does not call `on_setting_changed` unless the third argument is true (`VMF/settings.lua:46-61`).
- **T4 Source-pin tests.** 38 of the 46 `qa/lua/tests/test_gt_*.lua` files assert exact source strings, hook locations and load order (examples: `test_gt_regression_module.lua:25-33` pins 88 check names, `test_gt_time_hooks.lua:35-54` pins the `mod:dofile` order from `_gt_time_owner` to `_gt_hacks`, `test_gt_bot_utility_policy.lua:69` pins where the `Utility` hook lives). Run the suite after every step. Update a pin only in the same commit as the code it pins, and never weaken a behavioural assertion.
- **T5 Runtime rules.** One hook per `(Class, method)` per mod: VMF drops a second one, so extend the existing hook body. `mod.update` and chat commands run before the frame refreshes `POSITION_LOOKUP` (`V2SRC/scripts/boot.lua:747-752`, `V2SRC/scripts/game_state/state_ingame.lua:804-808`): read positions with `Unit.world_position(unit, 0)` there. The `dt` passed to `mod.update` is scaled game time (`V2SRC/foundation/scripts/managers/time/time_manager.lua:199-201`). `WorldManager.world(name)` asserts when the world is missing (`V2SRC/foundation/scripts/managers/world/world_manager.lua:107-115`).

---

### WP-GT-01 Require host opt-in for client-requested host actions

| Field | Value |
|---|---|
| Priority | P0 (any peer with the mod can end or restart the host's mission) |
| Size | M |
| Agent | any |
| Depends on | none (RIG part needs the track H rig) |
| Issues | none open; advances #1150 context only |
| Source | A6-F01 |
| Streams | both: `general_tweaker_dev/` first, then the same hunk in `general_tweaker/` (the public build has the same handlers) |

**Goal.** A host refuses a peer's request to win, fail or restart the level, respawn, be invulnerable, or spawn or destroy enemies unless the host ticked one new option, and the two unversioned requests carry a schema number.

**Context.**
- `gt_level_control`: the host runs `complete_level`, `fail_level` or `retry_level` for any sender (`GTD/_gt_level_control.lua:136-141`; send at `:123`; the comment at `:80-83` says "Any peer can trigger it"). Payload is `(verb)`, no schema.
- `gt_respawn_request`: same shape (`GTD/_gt_level_control.lua:537`, `:546-551`), payload `(lpid)`.
- `gt_godmode_state`: the host stores a peer's flag (`GTD/general_tweaker_dev.lua:779-788`) and then skips damage to that peer and returns 9999 for its hits (`:825-848`, `:1048-1067`, `:1307-1308`).
- `gt_cs_request` (dev only): a peer spawns any breed or destroys all enemies on the host (`GTD/_gt_creature_spawner.lua:942-990`).
- Stable twins: `GTS/_gt_level_control.lua:76,115,128-133,258,311,320-325`, `GTS/general_tweaker.lua:718`. Stable has no `gt_cs_request`.
- No host setting exists to refuse any of this.

**Steps.**
1. Add `qa/lua/tests/test_gt_host_request_policy.lua` and list it in `qa/lua/run.lua`. Part A (pure policy, file from step 2): `refuse(true, true, 1, 1)` is false; `refuse(true, false, 1, 1)` and `refuse(true, nil, 1, 1)` return `true, "host_opt_in_off"`; `refuse(true, true, "fail", 1)` returns `true, "schema_mismatch"`; `refuse(false, true, 1, 1)` returns `true, "not_host"`; `ignore_remote_godmode(true, false)` is true, `(true, true)` is false, `(false, false)` is false. Part B (handler): load `GTD/_gt_level_control.lua` with the stub loader pattern (`qa/lua/tests/test_gt_official_verify_rollup.lua:12-62`), stub `mod:network_register(name, fn)` to store `handlers[name]`, set `Managers.player.is_server = true` and a `Managers.state.game_mode` stub that counts `fail_level` calls. Assert: `handlers.gt_level_control("peer-x", 1, "fail")` makes 0 calls with the setting false and 1 call with it true; the old payload `handlers.gt_level_control("peer-x", "fail")` makes 0 calls. Part B must fail before step 3.
2. Create `GTD/_gt_host_request_policy.lua` (no engine calls):
   ```lua
   local P = {}
   P.SCHEMA = 1
   P.SETTING = "gt_host_allow_client_requests"
   function P.refuse(is_server, allow_setting, schema, expected_schema)
       if is_server ~= true then return true, "not_host" end
       if expected_schema ~= nil and schema ~= expected_schema then return true, "schema_mismatch" end
       if allow_setting ~= true then return true, "host_opt_in_off" end
       return false
   end
   function P.ignore_remote_godmode(is_server, allow_setting)
       return is_server == true and allow_setting ~= true
   end
   return P
   ```
3. In `GTD/_gt_level_control.lua`, after line 7, load the policy into `mod._gt_host_request_policy` and define `mod._gt_host_request_refused(kind, sender_peer_id, schema, expected_schema)`: it calls `P.refuse(Managers.player and Managers.player.is_server, mod:get(P.SETTING), schema, expected_schema)` and, on a refusal other than `not_host`, logs once per `kind|peer|reason` with `mod:info("[gt:host-request] refused kind=%s peer=%s reason=%s", ...)`. Return the two policy values.
4. Same file: change the sends at `:123` and `:537` to pass `mod._gt_host_request_policy.SCHEMA` as the first payload argument. Change the handlers at `:136` and `:546` to `function(sender_peer_id, schema, verb)` and `function(sender_peer_id, schema, lpid)`, and make their first statement `if mod._gt_host_request_refused("level", sender_peer_id, schema, mod._gt_host_request_policy.SCHEMA) then return end` (`"respawn"` for the second). Change the two client echoes (`:124`, `:538`) to add "The host must enable Allow Client Requests."
5. `GTD/_gt_creature_spawner.lua`: directly after the `is_server` return at `:953-954` add: if `mod._gt_host_request_refused("spawn", sender_peer_id)` then call `_gt_cs_ack(sender_peer_id, "The host has client requests turned off.")` and return. This file is frozen (T2): delete as many comment lines from its header (`:10-14`) as you add.
6. `GTD/general_tweaker_dev.lua`: in the godmode handler, after the schema check at `:780-782`, add one line: `if mod._gt_host_request_policy and mod._gt_host_request_policy.ignore_remote_godmode(Managers.player and Managers.player.is_server, mod:get("gt_host_allow_client_requests")) then return end`. Delete one comment line from `:1601-1711` (T2).
7. `GTD/general_tweaker_dev_data.lua`: insert a checkbox `gt_host_allow_client_requests`, `default_value = false`, tooltip `gt_host_allow_client_requests_tooltip`, immediately before the `allow_duplicate_careers` widget (`:1144-1150`; that group is sorted A to Z by label). `GTD/general_tweaker_dev_localization.lua`: add `gt_host_allow_client_requests = { en = "Allow Client Requests" }` and a tooltip saying that, when you host, other players running this mod may ask your game to win, fail or restart the level, respawn them, honour their godmode, and spawn or clear enemies; off by default. Put both next to `allow_duplicate_careers` (`:611`).
8. Stable (separate branch, Mode A, see T1): copy `_gt_host_request_policy.lua` to `GTS/` with the path string changed to `general_tweaker`; apply steps 3, 4, 6, 7 at `GTS/_gt_level_control.lua:76-133,258-325`, `GTS/general_tweaker.lua:718`, `GTS/general_tweaker_data.lua:839`, `GTS/general_tweaker_localization.lua:351`. Skip step 5.
9. Bump versions and changelogs.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` passes including the new file. `git grep -n "network_send(_GT_LEVEL_RPC\|network_send(_GT_RESPAWN_RPC" -- general_tweaker_dev general_tweaker` shows `SCHEMA` as the first payload argument on every hit. `pwsh -NoProfile -File qa/check_file_sizes.ps1` does not exit 2.
- RIG: `qa/runtime/gt/host_request_default_off.lua`, arena `keep`, mods `gt_dev`: `T.expect_eq(get_mod("gt_dev"):get("gt_host_allow_client_requests"), false, "opt-in is off on a fresh profile")`.
- Class C (two machines, later): client runs `T.cmd("fail")`; host asserts the level key is unchanged 10 s later and its log has `[gt:host-request] refused kind=level`.
- Evidence class: U closes the host-side logic of A6-F01. The end-to-end refusal stays C.

**Guardrails.** Do not gate `gt_ai_toggle_request` (it only acts on the sender and is authenticated at `GTD/_gt_ai_takeover.lua:438-443`), `gt_lobby_motd_show`, `gt_draw_leash` or `gt_cs_ack`. Do not change `_GT_GODMODE_RPC_SCHEMA`. The host's own commands and keybinds must behave as before. Respect T1, T2 and T4.

**Stop and escalate if.** The stable handlers do not match the shapes described (stop on the stable half only; the dev half still lands). Loading `GTD/_gt_level_control.lua` under stubs needs more than about 20 stub lines: keep Part A, replace Part B with a test of `mod._gt_host_request_refused` alone, and write down what blocked the load. Owner decision GT-D1 changes the default.

---

### WP-GT-02 Turn host melee lag compensation off by default

| Field | Value |
|---|---|
| Priority | P1 |
| Size | S |
| Agent | any |
| Depends on | none |
| Issues | #1034 (stays open: class C) |
| Source | A6-F02 |
| Streams | both: `general_tweaker_dev/` first, then the same hunk in `general_tweaker/` (the public build ships it default ON) |

**Goal.** Host-side melee latency compensation is off for new and existing users until someone turns it on, in both trees.

**Context.**
- `gt_host_lag_comp` has `default_value = true` in `GTD/general_tweaker_dev_data.lua:970-972` and `GTS/general_tweaker_data.lua:740-742`. The feature delays enemy melee hits against remote players on the host. It has never been verified with two clients (#1034 is `verify-fix`, `coop-required`).
- The runtime treats anything but an explicit `false` as enabled: `GTD/_gt_host_lag_comp.lua:126` (`~= false`), `:324` and `:485` (`== false`). `GTS/_gt_host_lag_comp.lua` is identical.
- Changing the default alone does nothing for existing users: VMF already saved `true` for them (T3, `VMF/options.lua:603-604`). A one-time migration is required.
- `qa/lua/tests/test_gt_host_lag_comp.lua:176-179` currently asserts "default on". Its stub `mod` (`:51-72`) has no `set`.

**Steps.**
1. Edit `qa/lua/tests/test_gt_host_lag_comp.lua` first: (a) change the case at `:176-179` to require `default_value = false` after the `gt_host_lag_comp` setting id; (b) add `set = function(_, key, value) saved[key] = value end` to the stub `mod` and make `get` read `saved` first; (c) add a case: with `saved.gt_host_lag_comp = true` and no migration flag, loading the runtime sets `saved.gt_host_lag_comp == false` and `saved.gt_host_lag_comp_default_off_v1 == true`; loading again with the flag set and the user value `true` leaves `true` untouched; (d) add policy cases for step 2. The file must fail now.
2. `GTD/_gt_host_lag_comp_policy.lua`: add
   ```lua
   function P.migrate_default_off(saved_value, migrated)
       if migrated == true then return saved_value, true end
       return false, true
   end
   ```
3. `GTD/_gt_host_lag_comp.lua`, directly after the policy is loaded (line 2), add:
   ```lua
   do
       local flag = "gt_host_lag_comp_default_off_v1"
       local value, done = Policy.migrate_default_off(mod:get("gt_host_lag_comp"), mod:get(flag))
       if mod:get(flag) ~= true then
           mod:set("gt_host_lag_comp", value)
           mod:set(flag, done)
       end
   end
   ```
   No third argument on either `mod:set` (no `on_setting_changed` call is wanted here).
4. Same file: `:126` becomes `enabled = mod:get("gt_host_lag_comp") == true,`; `:324` and `:485` compare with `~= true` instead of `== false`.
5. `GTD/general_tweaker_dev_data.lua:972`: `default_value = false`. If the tooltip text (`GTD/general_tweaker_dev_localization.lua:704`) says the option is on by default, reword it.
6. Stable (separate branch, Mode A, T1): the same edits in `GTS/_gt_host_lag_comp_policy.lua`, `GTS/_gt_host_lag_comp.lua:2,126,324,485`, `GTS/general_tweaker_data.lua:742` and the stable tooltip.
7. Bump versions and changelogs. State in the changelog that the option was reset to off once.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` passes. `git grep -n "gt_host_lag_comp\") ~= false\|gt_host_lag_comp\") == false" -- general_tweaker_dev general_tweaker` prints nothing.
- RIG: `qa/runtime/gt/issue_1034_lag_comp_default_off.lua`, arena `keep`, mods `gt_dev`: `T.expect_eq(get_mod("gt_dev"):get("gt_host_lag_comp"), false, "lag compensation is off")`.
- Evidence class: U + R prove the default. #1034 itself is class C and stays open until a two-machine run shows `unsafe == 0` and `applied + blocked + dodged + staggered == queued` in `/gt_lag_comp_status` after 20 queued hits.

**Guardrails.** Do not remove the feature, its setting or its command. Do not change the delay logic here (WP-GT-09 does). Do not rename the setting id. Respect T1 and T4.

**Stop and escalate if.** Owner decision GT-D2 says to keep it on. The stable file differs from dev at the named lines (stop the stable half only).

---

### WP-GT-03 Route world and position reads through one helper

| Field | Value |
|---|---|
| Priority | P1 (class: native access violation that `pcall` cannot catch) |
| Size | L. Split: part A = steps 1 to 4 (helper, test, the one unguarded site); part B = steps 5 to 9 (five duplicated guards). Each part is one commit and leaves the suite green. |
| Agent | any |
| Depends on | none |
| Issues | #490 (advances; see Acceptance) |
| Source | A6-F08 |
| Streams | `general_tweaker_dev/` only. Behaviour-preserving refactor; stable keeps its own copies until the next promotion (T1). |

**Goal.** One module owns "is the level world alive" and "where is this unit", every draw path uses it, and no gt_dev code calls `Managers.world:world("level_world")` unguarded.

**Context.**
- `WorldManager.world(name)` asserts when the world is missing; `has_world` is the safe probe (`V2SRC/foundation/scripts/managers/world/world_manager.lua:107-115`). Using a cached handle from a destroyed world is a native fault. `mod.update` keeps running between game states, when no level world exists.
- The guard is copied in five places, each with its own cache fields: `GTD/_gt_debug_highlights.lua:271-276` and `:301-316`; `GTD/_gt_bot_teleport_lab.lua:1075-1084` and `:1195-1200`; same file `:1447-1456` and `:1482-1484`; `GTD/_gt_solo_qol.lua:369-378`; `GTD/_gt_melee_warning.lua:211-217`.
- One site has no guard: `GTD/_gt_creature_spawner.lua:612` (`_gt_cs_position_at_cursor`), called from `:796`, `:884` and the projectile hook at `:1221`.
- `POSITION_LOOKUP[unit]` is a dead handle in `mod.update` and chat-command context for the local player (`GTD/_gt_saved_positions.lua:27-49` records the crash). The safe read is `Unit.world_position(unit, 0)`.

**Steps.**
1. Add `qa/lua/tests/test_gt_world.lua` and list it in `qa/lua/run.lua`. Load `GTD/_gt_world.lua` with `dofile`. Cases: (a) `live()` returns nil and does not raise when `has_world` returns false and `world()` would raise; (b) `live()` returns the world when present; (c) `is_live(w1)` is true, then false after the stub manager starts returning a different world `w2`; `is_live(nil)` is false; (d) `live()` is nil when `managers()` returns nil or a table without `world`; (e) `unit_pos(nil)` is nil; `unit_pos(u)` is nil when `Unit.alive(u)` is false and `world_position` is not called; otherwise it returns the stub position; (f) static: the text of `GTD/_gt_creature_spawner.lua` does not contain `Managers.world:world(`. Case (f) fails until step 4.
2. Create `GTD/_gt_world.lua`:
   ```lua
   local M = {}
   function M.new(engine)                       -- engine = { managers = function() return Managers end, Unit = Unit }
       local W = {}
       function W.live()
           local managers = engine.managers()
           local wm = managers and managers.world
           if not (wm and wm:has_world("level_world")) then return nil end
           return wm:world("level_world")
       end
       function W.is_live(world)
           return world ~= nil and W.live() == world
       end
       function W.unit_pos(unit)
           if not (unit and engine.Unit.alive(unit)) then return nil end
           return engine.Unit.world_position(unit, 0)
       end
       return W
   end
   return M
   ```
3. `GTD/general_tweaker_dev.lua`: directly after line 70 add `mod._gt_world = mod:dofile("scripts/mods/general_tweaker_dev/_gt_world").new({ managers = function() return Managers end, Unit = Unit })`. Delete one comment line from `:1601-1711` (T2).
4. `GTD/_gt_creature_spawner.lua:612`: replace with `local world = mod._gt_world.live()` and `if not world then return nil end`. At the callers `:796` and `:884`, return early with `mod:echo("[Spawn]: No level is loaded.")` when the position is nil (`:1221` already has an `or`). The file is frozen (T2): delete as many header comment lines (`:10-14`) as you add.
5. `GTD/_gt_debug_highlights.lua`: body of `_world()` (`:271-276`) becomes `return mod._gt_world.live()`; in `_destroy_gui()` replace the three lines at `:305-307` with `if mod._gt_world.is_live(w) then`.
6. `GTD/_gt_bot_teleport_lab.lua`: in `_clear_and_null` (`:1079-1081`) and `_shared_clear_and_null` (`:1451-1453`) use `if mod._gt_world.is_live(w) then`; at `:1195-1196` and `:1483-1484` use `local world = mod._gt_world.live()`.
7. `GTD/_gt_solo_qol.lua:369-371`: `local world = mod._gt_world.live()` then the existing `if not world then return end`.
8. `GTD/_gt_melee_warning.lua:211-217`: `local world = mod._gt_world.live()`, `if not world then return end`, `local ww = Managers.world:wwise_world(world)`.
9. Extend the test with static cases: none of the four files in steps 5 to 8 contains `has_world("level_world")`. Bump version and changelog.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` passes. `git grep -n "has_world(\"level_world\")" -- general_tweaker_dev/scripts` lists only `_gt_world.lua` and `_gt_time_context.lua`. `git grep -n "Managers.world:world(" -- general_tweaker_dev/scripts` prints nothing. `pwsh -NoProfile -File qa/check_file_sizes.ps1` does not exit 2.
- RIG: `qa/runtime/gt/issue_490_world_swap.lua`, arena `mission`, level `military`, bots on. `T.set` the options `gt_solo_draw_boss_spheres`, `gt_devtools_leash_lines`, `gt_devtools_bot_hud`, `gt_debug_highlights`, `gt_melee_warning` to true; `T.wait(10)`; `T.cmd("restart")` (destroys and recreates the level world); `T.wait_until` the local hero is alive again (120 s); `T.wait(10)`; `T.expect_rt("gt_dev", "gt_459_lineobject_cleanup_liveness_gated")`. `host_forbid_log = { "%[gt:update%] consumer '.-' raised", "Access violation" }`. PASS means the process survived the world swap with every draw path active.
- Evidence class: R. Run the same script once with mods `gt` (public build, before or after this card): a PASS there is the R evidence for #490, which is about the public build.

**Guardrails.** Do not touch `GTD/_gt_time_context.lua` (engine-free, own tests). Keep every cache field name, every `[gt:459]` log line, and the assignments `mod._gt459_liveness_gated_dh` (`GTD/_gt_debug_highlights.lua:320`) and `mod._gt459_liveness_gated_lab` (`GTD/_gt_bot_teleport_lab.lua:1103`): an in-game check reads them. Do not change how anything is drawn (GT-D8). `GTD/_gt_bot_teleport_lab.lua` must stay under 1500 non-empty lines (T2); this change removes lines.

**Stop and escalate if.** A copy does more than the `has_world` probe and the handle identity test: leave that copy alone and write down what it does.

---

### WP-GT-04 Make `/ai` and AFK takeover actually start the swap

| Field | Value |
|---|---|
| Priority | P1 |
| Size | M |
| Agent | any |
| Depends on | WP-GT-03 part A (`mod._gt_world.unit_pos`) |
| Issues | #247 |
| Source | A6-F24, A6-F09 |
| Streams | `general_tweaker_dev/` only. #247 is not a public-release issue. The stable twin has the same lines (`GTS/_gt_ai_takeover.lua:252,669,782,818,835`); it follows by normal promotion. |

**Goal.** Typing `/ai`, or going AFK with the AFK option on, starts the host swap, and the swap no longer reads the local player's `POSITION_LOOKUP` entry.

**Context.**
- The swap is started only from the `on_setting_changed` branch for `ai_takeover_enabled` (`GTD/general_tweaker_dev.lua:641-656`), which calls `mod._gt_ai_handle_toggle_change`.
- `/ai` does `mod:set("ai_takeover_enabled", not mod:get("ai_takeover_enabled"))` (`GTD/_gt_ai_takeover.lua:664-670`). VMF calls `on_setting_changed` only when the third argument of `mod:set` is true (`VMF/settings.lua:46-61`, documented at `VMF/events.lua:70-83`). So the command flips the saved value and nothing else. The AFK driver has the same gap at `:818` (start) and `:782`, `:835` (end); its comment at `:814-815` says it expects the callback.
- The options-menu checkbox works, because VMF notifies for widget changes.
- Host path: `mod.update` consumer `ai_pending` (`:680-683`) calls `_ai_consume_pending_host_toggle` (`:634-662`), which calls `_ai_swap_human_to_bot`. That function reads `POSITION_LOOKUP[unit] or Unit.local_position(unit, 0)` for the local hero (`:252`) and stores it at `:298` and `:306`. In `mod.update` that entry is a dead handle (T5). By `:298` a native bot may already be removed (`:271-272`) and the temporary bot created (`:282-283`), so a raise there leaves an extra bot.
- `:397` (`_ai_set_local_active`) sets the option under `mod._gt_ai_suppress_setting_callback`; it must stay without a notify.

**Steps.**
1. Add `qa/lua/tests/test_gt_ai_takeover_dispatch.lua` and list it in `qa/lua/run.lua`. Load `GTD/_gt_ai_takeover.lua` with the stub loader pattern (`qa/lua/tests/test_gt_official_verify_rollup.lua:12-62`): `mod:dofile` loads the real `_gt_ai_takeover_policy.lua`; `mod:command(name, text, fn)` stores `commands[name]`; `mod.set` records `{ id, value, notify }`; `mod:get` returns false; `mod:network_register`, `mod._gt_register_update`, `mod:info`, `mod:echo` are no-ops. Cases: (a) calling `commands.ai()` records exactly one set of `ai_takeover_enabled` whose third value is `true`; (b) static: read the source text, collect every line that contains `mod:set("ai_takeover_enabled"`, and assert that exactly one of them does not end its call with `, true)` (the one inside `_ai_set_local_active`, which passes the variable `active`); (c) static: the source does not contain `POSITION_LOOKUP[`. All three fail now.
2. `GTD/_gt_ai_takeover.lua`: add `, true` as the third argument at `:669`, `:782`, `:818` and `:835`. Leave `:397` unchanged.
3. Same file `:252`: `local position = mod._gt_world.unit_pos(unit)`. Wrap only the four `:store(...)` calls at `:298-299` and `:306-307` in `pcall`; leave `human_data.spawn_state = "despawned"` (`:305`) outside it.
4. Bump version and changelog.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` passes, including the existing `test_gt_ai_takeover.lua`.
- RIG: `qa/runtime/gt/issue_247_host_ai_takeover.lua`, arena `mission`, level `military`, bots on, mods `gt_dev`. Steps: `local gt = get_mod("gt_dev")`; `local hero = T.local_hero()`; `local bots_before = #Managers.player:bots()`; `T.cmd("ai")`; `T.wait_until(function() return next(gt._gt_ai_saved_state) ~= nil end, 10, "takeover recorded")`; `T.expect(not Unit.alive(hero), "human unit despawned")`; `T.wait(5)`; `T.cmd("ai")`; `T.wait_until(function() local u = Managers.player:local_player().player_unit; return u and Unit.alive(u) end, 30, "human unit is back")`; `T.expect_eq(#Managers.player:bots(), bots_before, "bot count restored")`; `T.expect(next(gt._gt_ai_saved_state) == nil, "saved state cleared")`. `host_forbid_log = { "%[gt:update%] consumer 'ai_pending' raised" }`.
- Evidence class: R closes the host route of #247. The client route (client asks the host) is class C and stays on the co-op list.

**Guardrails.** `qa/lua/tests/test_gt_ai_takeover.lua:76-97` pins strings in this file (for example the comment "Despawn before changing cameras" and `pcall(_ai_remove_takeover_bot, saved)`): do not reword or delete them. Do not restructure the swap or its rollback. Do not touch the RPC schema (`mod.GT_AI_RPC_SCHEMA = 2`).

**Stop and escalate if.** After step 2 the rig shows the swap starting twice for one `/ai` (that would mean the callback also fires through another path): revert step 2 and report. The rig case fails at "human unit is back": that is a product failure of the swap-back path, report it with the log, do not patch around it.

---

### WP-GT-05 Give the always-on engine guards one owner, counters and a switch

| Field | Value |
|---|---|
| Priority | P1 (they hide other mods' faults from every test) |
| Size | M |
| Agent | any |
| Depends on | none |
| Issues | none |
| Source | A6-F03 |
| Streams | `general_tweaker_dev/` only. The rig loads `gt_dev`; stable follows by normal promotion. |

**Goal.** Every global nil-guard gt_dev installs lives in one module, counts each time it fires, logs the first firing, and can be switched off at run time so the rig can test other mods with the guards off.

**Context.** These hooks are installed at load with no setting and change engine behaviour for the whole game:

| Guard name | Hook | Today at | Fires when |
|---|---|---|---|
| `world_spawn_unit` | `World.spawn_unit` | `GTD/_gt_creature_spawner.lua:1551-1560` | `Application.can_get("unit", name)` is false: spawns `units/hub_elements/empty` instead |
| `unit_get_data` | `Unit.get_data` | `GTD/_gt_hacks.lua:488-491` | unit is nil: returns nil |
| `unit_create_actor` | `Unit.create_actor` | `GTD/_gt_creature_spawner.lua:1517-1524` | in the keep and actor id is -1: swallowed |
| `request_breed_limits` | `EnemyPackageLoader.request_breed` | `GTD/_gt_creature_spawner.lua:1562-1568` | always: forces `ignore_breed_limits = true` (`V2SRC/scripts/game_state/components/enemy_package_loader.lua:186-219`) |
| `update_aggro` | `AiUtils.update_aggro` | `GTD/_gt_creature_spawner.lua:1199-1209` | `blackboard.aggro_list` is nil |
| `bt_health_nil` | eight `BTConditions` health conditions | `GTD/_gt_creature_spawner.lua:1427-1493` | health field is nil |
| `fog_volume` | `VolumetricsFlowCallbacks.unregister_fog_volume` | `GTD/_gt_hacks.lua:481-486` | unit is dead |
| `whereabouts_no_pos` | `PlayerWhereaboutsExtension.update` | `GTD/_gt_hacks.lua:493-507` | unit has no position |
| `round_start_no_pos` | `RoundStartedSystem._players_left_start_area` | `GTD/_gt_hacks.lua:509-525` | a tracked unit has no position |
| `commander_no_pos` | `AICommanderExtension._update_units` | `GTD/general_tweaker_dev.lua:551-575` | commander has no position |
| `utility_inputs` | `Utility.get_action_utility` | `GTD/_gt_bot_fixes.lua:57-81` (stays there) | a consideration input is not a number |

With gt_dev loaded, a missing unit package in any other mod becomes an invisible unit instead of a crash, and nothing records that it happened.

**Steps.**
1. Add `qa/lua/tests/test_gt_engine_guards.lua` and list it in `qa/lua/run.lua`. Load `GTD/_gt_engine_guards.lua` with the stub loader pattern (`qa/lua/tests/test_gt_official_verify_rollup.lua:12-62`). The stub `mod:hook(target, method, fn)` must accept a string or a table target; key the captured closure as `"<Class>.<method>"` using a name map for the table targets you put in the env (`World`, `Unit`, `EnemyPackageLoader`, `AiUtils`, `BTConditions`, `VolumetricsFlowCallbacks`). Cases: (a) guards on: `hooks["World.spawn_unit"](orig, world, "missing")` with `Application.can_get` false passes `"units/hub_elements/empty"` to `orig` and `mod._gt_guard_counts.world_spawn_unit == 1`; (b) after `mod.gt_set_engine_guards(false)` the same call passes `"missing"` and the count does not change; (c) with guards off, every captured hook returns exactly what `orig` returns for an `orig` that returns `"a", nil, "c"` (`select("#", ...) == 3`); (d) guards on: `hooks["Unit.get_data"](orig, nil, "breed")` does not call `orig` and counts 1; off: `orig` is called; (e) `request_breed`: on passes `true` as the third argument, off passes the caller's value. The test fails now because the module does not exist.
2. Create `GTD/_gt_engine_guards.lua`. It defines: a file-local `enabled = mod:get("gt_engine_guards_enabled") ~= false`; `mod._gt_guard_counts = {}`; `mod._gt_guard_fired(name, detail)` (increments the count and, on the first firing of that name, prints `[gt:guard] <name> fired detail=<detail>` with engine `printf` under `pcall`); `mod._gt_guards_on()` (returns `enabled`); `mod.gt_set_engine_guards(value)` (sets `enabled`, saves it with `mod:set("gt_engine_guards_enabled", enabled)`, prints `[gt:guard] switch enabled=<bool>`); a command `gt_guards` with optional argument `on` or `off` that prints the state and every count. No settings widget.
3. Move each hook in the table (except `utility_inputs`) into that file unchanged, then give each body the first statement `if not enabled then return func(<the same arguments, including ...>) end` and a `mod._gt_guard_fired("<name>", <detail>)` call on the branch that changes behaviour. Keep the nil checks on optional classes (`if AiUtils then`, `rawget(_G, "AICommanderExtension")`). Move the `_gt_bt_health_nil_seen` table, its two factory functions and the line `GT_BT_HEALTH_NILGUARD_MARKER_v0_2_149 = "gt-bt-health-conditions-nilguarded-i59"` with the `bt_health_nil` hooks.
4. `unit_create_actor` needs the keep test: in `GTD/_gt_creature_spawner.lua` next to `:362` add `mod._gt_cs_is_in_keep = _gt_cs_is_in_keep`, and in the moved hook call `mod._gt_cs_is_in_keep and mod._gt_cs_is_in_keep()` inside the body (the spawner loads later, so resolve it at call time).
5. `GTD/general_tweaker_dev.lua`: replace the whole block `:551-575` (comment and hook) with one line `mod:dofile("scripts/mods/general_tweaker_dev/_gt_engine_guards")`. The file shrinks (T2 satisfied).
6. `GTD/_gt_bot_fixes.lua:57`: make the first statement of the hook body `if mod._gt_guards_on and not mod._gt_guards_on() then return func(breed_action, action_name, blackboard, ...) end`, and call `mod._gt_guard_fired("utility_inputs", detail)` just before `return 0` (`:72`). Add no more than 10 lines here (T2).
7. Bump version and changelog.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` passes. `git grep -n "mod:hook(Unit, \|mod:hook(World, \|\"request_breed\"\|\"update_aggro\"\|\"unregister_fog_volume\"\|\"_players_left_start_area\"\|\"_update_units\"" -- general_tweaker_dev/scripts` lists only `_gt_engine_guards.lua`. `pwsh -NoProfile -File qa/check_file_sizes.ps1` does not exit 2.
- RIG 1: `qa/runtime/gt/guards_counters.lua`, arena `mission`, level `military`, bots on: `T.wait(60)`; `T.expect(type(get_mod("gt_dev")._gt_guard_counts) == "table", "counters exist")`; write each count with `T.note("guard." .. name, count)`. This is the first measurement of which guards are load-bearing.
- RIG 2: `qa/runtime/gt/guards_off_smoke.lua`, same arena: `get_mod("gt_dev").gt_set_engine_guards(false)`; `T.spawn("skaven_clan_rat", ...)` five times; `T.wait(30)`; then `gt_set_engine_guards(true)`. `host_forbid_log = { "%[gt:update%] consumer '.-' raised" }`. A crash here is a finding about the code a guard was hiding, not a failure of this card: record it and keep the switch.
- Evidence class: U for the pass-through and counting; R for the counters.

**Guardrails.** Default stays ON: no behaviour change for players (GT-D4). Do not narrow when a guard is armed in this card. Do not move the keep-spawn behaviour hooks (`BTSpawnAllies`, `BTLootRatFleeAction`, `NavigationGroupManager`, `LocomotionUtils`, `GwNavQueries`, `BTSkulkAroundAction` at `GTD/_gt_creature_spawner.lua:1230-1272,1497-1516,1526-1533`) or `BuffSystem.add_buff` (`:1539-1549`). The `Utility` hook must stay in `GTD/_gt_bot_fixes.lua` (`qa/lua/tests/test_gt_bot_utility_policy.lua:69-72` pins it). Do not add `mod:get` calls inside the hot hook bodies; read the file-local `enabled`.

**Stop and escalate if.** A `(Class, method)` in the table is hooked a second time anywhere in gt_dev (`git grep` before moving it): do not create a second hook (T5); report it.

---

### WP-GT-06 Expose load-level, give-item and teleport as `mod.gt_*` functions

| Field | Value |
|---|---|
| Priority | P1 (missing building blocks for rig scripts) |
| Size | M |
| Agent | any |
| Depends on | none |
| Issues | none |
| Source | A6 section 2.6 ("Gaps") |
| Streams | `general_tweaker_dev/` only. New dev-only module; never promoted. |

**Goal.** Other code can call `get_mod("gt_dev").gt_load_level(level_key)`, `.gt_give_item(pickup_name, unit)` and `.gt_teleport_to(x, y, z, unit)`; each returns `true`, or `false` and a reason string, and never raises.

**Context.**
- gt_dev can win, fail and restart a level, spawn enemies and pickups, and recall saved positions, but it cannot start a level from the keep, put a consumable into an inventory slot, or teleport to coordinates.
- Load level: `Managers.mechanism:debug_load_level(level_key, environment_variation_id)` is host-only and returns silently on a client (`V2SRC/scripts/managers/game_mode/game_mechanism_manager.lua:880-892`); the Adventure implementation sets the next level, promotes it and advances the state (`V2SRC/scripts/managers/game_mode/mechanisms/adventure_mechanism.lua:580-594`). Level keys are the keys of `LevelSettings` (for example `military`, `V2SRC/scripts/settings/level_settings.lua:1264`).
- Give item: vanilla's own recipe for handing a consumable to a local human or bot is the local function `add_item` at `V2SRC/scripts/settings/twitch_vote_templates_items.lua:59-139`: read `AllPickups[name].slot_name` and `.item_name` (table built at `V2SRC/scripts/settings/equipment/pickups.lua:939-951`; `healing_draught` gives `slot_healthkit` / `potion_healing_draught_01`), `inventory_extension:destroy_slot(slot_name)`, `inventory_extension:add_equipment(slot_name, item_data, nil, {})`, then send `rpc_add_equipment` (to clients if server, else to the server), then re-wield if that slot is wielded.
- Teleport: `PlayerUnitLocomotionExtension.teleport_to(self, pos, rot)` (`V2SRC/scripts/unit_extensions/default_player_unit/player_unit_locomotion_extension.lua:1005-1023`). Its last line reads `POSITION_LOOKUP[unit]`, which is a dead handle in command and `mod.update` context; `GTD/_gt_saved_positions.lua:203-238` already solves this by writing a fresh `Vector3` into `POSITION_LOOKUP[unit]` just before the call.

**Steps.**
1. Add `qa/lua/tests/test_gt_rig_blocks.lua` and list it in `qa/lua/run.lua`. Part A (policy from step 2): `level_request(true, "military", {})` is true; `(false, "military", {})` gives `false, "not_host"`; `(true, "", {})` and `(true, 5, {})` give `"bad_level_key"`; `(true, "nope", nil)` gives `"unknown_level"`. `give_plan({ slot_name = "slot_healthkit", item_name = "potion_healing_draught_01" }, false, nil)` returns a table with those two fields; `give_plan(nil, false, nil)` gives `nil, "unknown_pickup"`; `give_plan({}, false, nil)` gives `"not_an_inventory_item"`; owner remote `true` gives `"owner_not_local"`; held template `wpn_grimoire_01` or `wpn_side_objective_tome_01` gives `"slot_holds_objective_item"`. `teleport_target(1, 2, 3)` is true; `(1, 0/0, 3)`, `(math.huge, 2, 3)` and `("1", 2, 3)` give `false, "bad_coordinates"`. Part B: load `GTD/_gt_rig_blocks.lua` with the stub loader pattern and assert that `mod.gt_load_level("military")` calls the stub `Managers.mechanism:debug_load_level` once with `"military", 0`, that `mod.gt_load_level("nope")` calls it zero times and returns `false, "unknown_level"`, and that `mod.gt_give_item("healing_draught", unit)` calls `destroy_slot("slot_healthkit")` then `add_equipment("slot_healthkit", <ItemMasterList entry>, nil, <table>)` on the stub inventory.
2. Create `GTD/_gt_rig_blocks_policy.lua` with the three pure functions `level_request(is_server, level_key, level_settings)`, `give_plan(pickup_settings, owner_is_remote, held_template_name)`, `teleport_target(x, y, z)` returning exactly the values listed in step 1 (a coordinate is valid when it is a number, equals itself, and is not plus or minus `math.huge`).
3. `GTD/_gt_saved_positions.lua`: extract the teleport body of `_drain_pending_recall` (`:203-238`: locomotion lookup, `Vector3`, optional rotation, the `POSITION_LOOKUP` seed at `:230-231`, the `pcall(loco.teleport_to, loco, pos, rot)`) into `mod._gt_teleport_unit(unit, x, y, z, rot)` returning `true` or `false, err`. `_drain_pending_recall` then calls it and keeps its own messages.
4. Create `GTD/_gt_rig_blocks.lua`:
   - `mod.gt_load_level(level_key, environment_variation_id)`: policy check with `Managers.player and Managers.player.is_server` and `type(level_key) == "string" and rawget(LevelSettings, level_key) or nil`; then `Managers.mechanism:debug_load_level(level_key, environment_variation_id or 0)` under `pcall`.
   - `mod.gt_give_item(pickup_name, unit)`: `unit` defaults to the local player unit; require `Unit.alive(unit)`, `Managers.player:owner(unit)` and `ScriptUnit.has_extension(unit, "inventory_system")`; `rawget(AllPickups, pickup_name)`; held template name from `inventory:get_slot_data(slot_name)` and `BackendUtils.get_item_template(slot_data.item_data)`; policy check with `owner.remote == true`; then the vanilla sequence from Context, including the `rpc_add_equipment` send and the re-wield.
   - `mod.gt_teleport_to(x, y, z, unit)`: policy check; `unit` defaults to the local player unit; `mod._gt_teleport_unit(unit, x, y, z, nil)`.
   - Each function prints one line with engine `printf`: `[gt:rig] <load_level|give_item|teleport> ok=<bool> reason=<text>`.
   - Commands `gt_load_level <level_key>`, `gt_give <pickup_name>`, `gt_tp <x> <y> <z>` that call the functions and echo the result.
5. `GTD/general_tweaker_dev.lua`: add `mod:dofile("scripts/mods/general_tweaker_dev/_gt_rig_blocks")` directly after the `_gt_saved_positions` line (`:2022`). Delete one comment line from `:1601-1711` (T2).
6. Bump version and changelog.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` passes. `pwsh -NoProfile -File qa/check_command_collisions.ps1` reports no collision for the three new commands.
- RIG 1: `qa/runtime/gt/blocks_load_level.lua`, arena `keep`: `T.expect(get_mod("gt_dev").gt_load_level("military"), "accepted")`; `T.wait_until(function() return Managers.level_transition_handler:get_current_level_key() == "military" and T.local_hero() ~= nil end, 180, "military loaded")`.
- RIG 2: `qa/runtime/gt/blocks_give_item.lua`, arena `mission`, level `military`, bots on: `local bot = T.first_bot_unit()`; `T.expect(get_mod("gt_dev").gt_give_item("healing_draught", bot), "accepted")`; `T.wait_until(function() local d = T.ext(bot, "inventory_system"):get_slot_data("slot_healthkit"); return d and d.item_data and d.item_data.name == "potion_healing_draught_01" end, 5, "bot holds the draught")`.
- RIG 3: `qa/runtime/gt/blocks_teleport.lua`, same arena: `local hero = T.local_hero()`; `local p = Unit.world_position(hero, 0)`; `local x, y, z = p.x + 2, p.y, p.z`; `T.expect(get_mod("gt_dev").gt_teleport_to(x, y, z), "accepted")`; `T.frames(5)`; `T.expect_near(Unit.world_position(hero, 0).x, x, 1.0, "hero moved")`. `host_forbid_log = { "Vector3 expected, got userdata" }`.
- Evidence class: U for validation and call order; R for the three effects.

**Guardrails.** No new hooks. Do not call `debug_load_level` when not host. Do not write a weapon-equip function here: a rig script can call `BackendUtils.set_loadout_item` and `create_equipment_in_slot` itself (`V2SRC/scripts/unit_extensions/default_player_unit/inventory/simple_inventory_extension.lua:2175-2183`). Do not change what `/recall_position_N` prints. `rawget` the strict tables (`AllPickups`, `LevelSettings`, `ItemMasterList`).

**Stop and escalate if.** RIG 1 logs `ok=false` with a `debug_load_level` error in retail: switch the body to `Managers.level_transition_handler:set_next_level(level_key)` plus `:promote_next_level_data()` (the retail-proven form in `event_tweaker/scripts/mods/event_tweaker/_evt_apply.lua:81-83`) and record which one worked. The rig cannot keep a case alive across a level load: report it to track H; do not work around it in the mod.

---

### WP-GT-07 Remove presence-only checks from `/gt_regression_test`

| Field | Value |
|---|---|
| Priority | P2 |
| Size | L. Split into three commits: (1) the eight feature-module checks, (2) bot checks in `GTD/_gt_regression_checks.lua:580-1400`, (3) the rest plus the marker globals. The suite must pass after each. |
| Agent | strong (each check needs a judgment: real test or presence check; a wrong deletion removes real coverage) |
| Depends on | none. Do it after WP-GT-05 if both are scheduled, to avoid editing the same marker twice. |
| Issues | none |
| Source | A6-F05 (with its round 2 correction) |
| Streams | `general_tweaker_dev/` only |

**Goal.** Every check that `/gt_regression_test` runs either executes production code, reads live state, or validates the settings tables; checks that only prove "this code was loaded" are gone, and so are the globals that existed only for them.

**Context.**
- The rig records every `/gt_regression_test` check as an assertion on each boot (`T.expect_rt`). A check that only compares a marker constant adds a PASS that proves nothing about behaviour.
- gt_dev registers 114 checks: 88 in `GTD/_gt_regression_checks.lua`, the rest in feature modules (runner at `GTD/general_tweaker_dev.lua:384-421`; a check returns nil on success or a reason string). A heuristic classification found 47 that call production functions with stub inputs (good, for example `gt_bot515_teleport_latch_rearm` at `GTD/_gt_regression_checks.lua:853-867`), 4 that read live state, 9 that inspect the data tables, and 48 that only compare marker constants, load-time flags (`*_wired`, `*_armed`) or `type(mod.x) == "function"`.
- 21 bare globals exist only for these checks: lines matching `^GT_[A-Za-z0-9_]*MARKER[A-Za-z0-9_]* = "` in `GTD/_gt_bot_fixes.lua` (10), `GTD/_gt_bot_aid_owner.lua` (3), `GTD/_gt_bots_keep.lua` (3), `GTD/_gt_creature_spawner.lua` (3), `GTD/_gt_bot_pickups.lua` (1), `GTD/_gt_necro_keep_trace.lua` (1).
- Presence-only candidates that are NOT tied to an open issue (35; confirm each by reading): `ai_takeover_marker_present`, `ai_takeover_client_send_queue_wired`, `bot_follow_mode_dropdown_consolidated`, `bot_greedy_pickup_hooks_present`, `bot_leash_veto_while_teammate_needs_aid_present`, `bots_in_keep_crashfix_marker_present`, `bots_in_keep_helpers_exposed`, `breach_probe_present_dev_gated`, `bt_health_conditions_nilguarded_marker_present`, `btlab_no_class_hooks`, `dbg_helpers_two_channel`, `devtools_bot_hud_wired`, `gt534_leash_share_wired`, `gt693_cs_client_request_wired`, `gt_459_lineobject_cleanup_liveness_gated`, `gt_ai_rpc_schema_present`, `gt_bot139_teleport_veto_singleton_and_gated`, `gt_bot142_veto_still_final`, `gt_bot261_leash_conflict_invariants`, `gt_bot448_downed_morrs_grant_suppressed`, `gt_bot468_smart_self_heal_wired`, `gt_cs_rpc_schema_present`, `gt_dh_local_player_safe_508`, `gt_dh_no_position_lookup_reads`, `gt_draw_rpc_schema_present`, `gt_lobby_join_dispatch_consolidated`, `gt_lobby_join_dispatch_pcall_isolated`, `gt_lobby_rpc_schema_present`, `gt_no_mission_hotkey_flip`, `issue600_wait_aim_and_duration`, `issue939_godmode_ledge_boundary`, `necro_potion_give_half_targeted_promote`, `saved_positions_module_wired`, `tether_dump_present`, and `ai_takeover_vmf_ping_api_available` (read it first: it checks the live VMF API and is probably a keeper).
- Presence-only checks whose name cites an OPEN issue (13; keep the name, see step 3): `gt_bot385_below_leash_instrument`, `gt_dh_hud_update_invocation_302`, `issue1143_dev_heal_command`, `issue1802_native_time_controls`, `issue241_noclip_boundary_routes`, `issue247_keep_slot_takeover_wired`, `issue254_deus_spawn_queue_diagnostics_armed`, `issue309_disconnect_grace_diagnostics_armed`, `issue380_downed_mood_swallow_complete`, `issue659_necromancer_keep_trace_armed`, `issue753_disconnect_failure_diagnostics_armed`, `issue797_player_stat_diagnostics_armed`, `issue797_player_stat_hud`.
- Pins to expect: `qa/lua/tests/test_gt_regression_module.lua:25-33` (88 names, first `gt_pickup_lookup_uses_rawget`, last `issue241_noclip_boundary_routes`) and `:42-43` (counts of `_rt_register(` in two files). Several marker names are also pinned in `qa/lua/tests/test_gt_*.lua` and two `MARKER` strings appear in `tools/verify/live_test_contract_exceptions.psd1`.

**Steps.**
1. Classify. For each check, read the body and label it: KEEP (calls a production function and compares the result, or reads live engine or VMF state, or validates settings or localization tables), DELETE (every assertion is a marker constant, a load-time flag, or a field type test), MIXED (a marker pre-check followed by real assertions). Write the labels in the commit message.
2. Before touching a check, run `git grep -n "<check_name>" -- qa docs tools`. If a rig script under `qa/runtime/` uses it in `T.expect_rt`, either keep the check or update that script in the same commit.
3. Apply: MIXED loses only its marker pre-check lines. DELETE checks that are not in the open-issue list are removed. DELETE checks in the open-issue list keep their name; if a pure function for that feature exists (a `*_policy.lua` or an exported predicate), make the body call it with one positive and one negative case; if none exists, leave the check unchanged and list it in the commit message as "presence-only, kept for issue N".
4. Add one data-driven check `gt_public_api_present` in `GTD/_gt_regression_checks.lua` that loops over a list of exported function names and returns the missing ones. Seed the list with: `gt_win_level`, `gt_fail_level`, `gt_restart_level`, `gt_cs_spawn`, `gt_cs_destroy`, `gt_is_spawn`, `gt_clear_enemies`, `gt_noclip_toggle`, `gt_pause_toggle`, `gt_time_normal`, `_gt_ai_swap_human_to_bot`, `_gt_register_update`, `_bik_fill`, `_gt_apply_no_bots`. This replaces all the single "function is exported" checks.
5. For each `GT_*MARKER*` global and each `mod._GT_*_MARKER` field: `git grep -n "<NAME>" -- general_tweaker_dev qa tools`. Delete the definition only when the definition is the last hit. Remove a pin in `qa/lua/tests/` in the same commit.
6. Update `qa/lua/tests/test_gt_regression_module.lua` to the new count, first name and last name, and the two `_rt_register(` counts. Add a case that fails if `GTD/_gt_regression_checks.lua` contains the text `MARKER`, and a case that fails if any `GTD/*.lua` has a line matching `^GT_[A-Za-z0-9_]*MARKER`.
7. Bump version and changelog once per commit.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` passes. `git grep -c "MARKER" -- general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_regression_checks.lua` prints nothing (zero hits), unless a kept open-issue check is listed in the commit message as the reason. `git grep -nE "^GT_[A-Za-z0-9_]*MARKER" -- general_tweaker_dev/scripts` prints at most the names listed as kept. `pwsh -NoProfile -File qa/check_file_sizes.ps1` does not exit 2 (`_gt_regression_checks.lua` may only shrink).
- RIG: any boot of `gt_dev` reports zero FAIL and zero BAD-SHAPE among the gt_dev checks, and the number of gt_dev checks recorded equals the number asserted in `test_gt_regression_module.lua` plus the feature-module checks.
- Evidence class: S and U. No issue is closed by this card.

**Guardrails.** Never delete a check that executes production code, even if it also tests a marker. Do not rename a surviving check (rig scripts and issue cards cite the names). Do not turn checks into multi-frame scenarios; that belongs in `qa/runtime/` scripts. `GTD/_gt_regression_checks.lua` and `GTD/_gt_creature_spawner.lua` are frozen (T2): they may only shrink.

**Stop and escalate if.** A marker or check name is referenced in `tools/verify/*.psd1`: leave both and list them. You cannot tell whether a body is presence-only: keep it.

---

### WP-GT-08 Gate the vdl shading hook on the level world

| Field | Value |
|---|---|
| Priority | P2 |
| Size | S |
| Agent | any |
| Depends on | none |
| Issues | none |
| Source | A6-F15 |
| Streams | `verminious_dreams_lighting_dev/` only. The public script has the same hook shape (`verminious_dreams_lighting/scripts/mods/verminious_dreams_lighting/verminious_dreams_lighting.lua:433`); it follows by normal promotion (T1). |

**Goal.** The lighting override is applied only to the level world, and on levels without a profile the hook does no work after the first frame.

**Context.**
- `VDL/verminious_dreams_lighting_dev.lua:636-687` hooks `CameraManager.shading_callback(self, world, shading_env, viewport)` with `mod:hook_safe`. Vanilla runs its own body only `if self._world == world` (`V2SRC/scripts/managers/camera/camera_manager.lua:283-284`) because other worlds (inventory and preview worlds) drive the same callback. The vdl hook has no such test, so on a profiled level it also tints those worlds. The mod's own `verminious_dreams_lighting_dev/ENGINE_SURFACE.md:37,63-68` says it mirrors the gate.
- On every level without a profile, `_CURRENT_LEVEL_KEY` is nil (`:695`), so each call re-reads the level key and builds three pattern strings in `_resolve_profile_key` (`:402-411`, `:482-487`).
- On a profiled level each call allocates one table per sampled variable (`:640-643` with `_vector3_to_bytes` at `:353-355`).

**Steps.**
1. Add `qa/lua/tests/test_vdl_shading_hook.lua` and list it in `qa/lua/run.lua`. Load `VDL/verminious_dreams_lighting_dev.lua` with the stub loader pattern (`qa/lua/tests/test_gt_official_verify_rollup.lua:12-62`): stub `mod` with `info`, `echo`, `warning`, `debug`, `command`, `localize`, `get` (returns true for `enable_dlc_termite_2`, nil otherwise), `set`, `hook_safe` (stores `hooks["Class.method"]`) and `dofile` (loads the real `_lib_debug.lua`). Env: `Managers.state.game_mode.level_key` returns a variable `level` and counts calls; `ShadingEnvironment` with `vector3` returning `{ x = 0.1, y = 0.2, z = 0.3 }`, `scalar` returning 1, and `set_vector3` / `set_scalar` that count calls; `Vector3 = function(x, y, z) return { x = x, y = y, z = z } end`. Cases: (a) `level = "dlc_termite_2"`, `hooks["CameraManager.shading_callback"]({ _world = "A" }, "B", {}, {})` makes 0 `set_*` calls (fails today); (b) same level, `_world = "A"`, world `"A"`: exactly 4 `set_vector3` calls (the profile at `:185-196` sets sun, amb, amb_top, fog) and 0 `set_scalar`; (c) `level = "military"`: call `hooks["GameModeManager.local_player_game_starts"]({ _world = "A" }, {}, {})` once, note the `level_key` call count, call the shading hook three times with world `"A"`: 0 `set_*` calls and the `level_key` count does not rise (fails today).
2. `VDL/verminious_dreams_lighting_dev.lua:636`: make the first statement of the hook `if self._world ~= world then return end`.
3. Negative cache: in the `local_player_game_starts` hook (`:689-705`) change `_CURRENT_LEVEL_KEY = key` to `_CURRENT_LEVEL_KEY = key or false`. In `_profile_for_current_level` and `_profile_for_current_level_raw` (`:482-495`): when `_CURRENT_LEVEL_KEY == false` return `nil, nil` without calling `_current_level_key()`; when it is nil keep today's live lookup. Check the other readers of `_CURRENT_LEVEL_KEY` (`git grep -n "_CURRENT_LEVEL_KEY" -- verminious_dreams_lighting_dev`) still treat `false` as "no profile".
4. Sampling: in the hook, write the sampled bytes into the existing `_LAST_SAMPLED[short_key]` table when it exists instead of creating a new one each call.
5. Fix the two sentences in `verminious_dreams_lighting_dev/ENGINE_SURFACE.md:37,63-68` only if they are still wrong after the change. Bump version and changelog.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` passes including the new file. `git grep -n "self._world ~= world" -- verminious_dreams_lighting_dev/scripts` has one hit.
- RIG: `qa/runtime/vdl/shading_profile_applied.lua`, arena `mission`, level `dlc_termite_2`, mods `verminious_dreams_lighting_dev`: hook-free read after 5 s: the case registers nothing; it calls `T.cmd("vdl_fog")` and asserts through `host_expect_log`/chat capture is not available, so instead assert on state: `T.expect_rt("verminious_dreams_lighting_dev", "cw_permutation_prefix_match")` and `host_forbid_log = { "%[MOD%]%[verminious_dreams_lighting_dev%]%[ERROR%]" }`. The colour itself is class V: attach `T.shot("termite_2_lighting")`.
- Evidence class: U closes the gate and the negative cache. Look and feel stays V.

**Guardrails.** Do not change any profile value, the curse layer maths (`:665-686`), or the commands. Do not add a dependency on `chaos_wastes_tweaker` (GT-D7). Do not touch the stable tree.

**Stop and escalate if.** Loading the script under stubs fails for a reason other than a missing stub function (write down the global it needs). Case (b) does not give 4 calls before you change anything: the profile table changed; re-derive the number from `_PROFILES.dlc_termite_2` and say so.

---

### WP-GT-09 Resolve lag-compensation hits inside the frame, on wall-clock time

| Field | Value |
|---|---|
| Priority | P2 (the feature is off by default after WP-GT-02; this must land before anyone turns it back on) |
| Size | M |
| Agent | any |
| Depends on | WP-GT-02 |
| Issues | #1034 (advances; closure is class C) |
| Source | A6-F02, A6-F23 |
| Streams | `general_tweaker_dev/` only |

**Goal.** Queued enemy melee hits are resolved after `StateIngame.update` in the same frame, with deadlines measured in real time, instead of from `mod.update` on scaled time.

**Context.**
- `GTD/_gt_host_lag_comp.lua` queues hits (`:333-384`, `:386-433`) and resolves them from an update consumer registered as `host_lag_comp` (`:482-506`). For a whole hit the deferred closure re-enters vanilla `BTMeleeOverlapAttackAction.hit_player` (`:368-371`, `:146-151`), which calls `push_player` (`V2SRC/scripts/entity_system/systems/behaviour/nodes/bt_melee_overlap_attack_action.lua:638-663`), which reads `POSITION_LOOKUP[unit]` and `POSITION_LOOKUP[hit_unit]` (same file `:619-622`).
- `mod.update` runs before the frame refreshes `POSITION_LOOKUP` (T5), so those reads use last frame's handles. A failure is swallowed and only counted as `unsafe` (`:164-167`): the hit disappears.
- `record.remaining` is reduced by the `dt` given to `mod.update`, which is scaled by the global time scale (T5), while the delay comes from real round-trip time.
- A per-frame call that runs right after vanilla `StateIngame.update` already exists: `_gt_cs_after_state_update` in `GTD/_gt_creature_spawner.lua:1141-1144`, invoked through `mod._gt_time_state_update` (`GTD/_gt_time_hooks.lua:13-19`, hook at `GTD/_gt_creature_spawner.lua:1146-1148`).
- `qa/lua/tests/test_gt_host_lag_comp.lua` loads the runtime under stubs (`:51-110`) and drives it through `updates.host_lag_comp`.

**Steps.**
1. Edit `qa/lua/tests/test_gt_host_lag_comp.lua` first: give the env `Application = { time_since_launch = function() return clock end }`; replace every `update(dt)` call with "advance `clock`, then call `mod._gt_host_lag_comp_tick()`"; assert `updates.host_lag_comp == nil`; add a case: queue one hit with a 0.2 s delay, advance the clock by 0.1 and tick (not applied), advance to 0.25 and tick (applied once); add a case with the stub time scale irrelevant: ticking twice at the same clock value applies nothing twice. The file fails now.
2. `GTD/_gt_host_lag_comp.lua`: replace the consumer registration at `:482-506` with `mod._gt_host_lag_comp_tick = function() ... end`. Inside, compute `local now = Application.time_since_launch()`, `local elapsed = _last_tick and math.max(now - _last_tick, 0) or 0`, store `_last_tick = now`, then run the existing body with `elapsed`. Reset `_last_tick = nil` in `_reset()` (`:309-317`).
3. `GTD/_gt_creature_spawner.lua`, in `_gt_cs_after_state_update` (`:1141-1144`), add `if mod._gt_host_lag_comp_tick then mod._gt_host_lag_comp_tick() end`. The file is frozen (T2): delete one header comment line (`:10-14`).
4. Bump version and changelog.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` passes. `git grep -n "_gt_register_update" -- general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_host_lag_comp.lua` prints nothing. `pwsh -NoProfile -File qa/check_file_sizes.ps1` does not exit 2.
- RIG (solo, wiring only): `qa/runtime/gt/issue_1034_tick_wired.lua`, arena `mission`, level `military`: `T.set("gt_dev", "gt_host_lag_comp", true)`; `T.wait(5)`; `T.expect(type(get_mod("gt_dev")._gt_host_lag_comp_tick) == "function", "tick exported")`; `host_forbid_log = { "%[gt:update%] consumer 'host_lag_comp' raised" }`.
- Evidence class: U for timing. #1034 stays open: it needs a two-machine run showing `unsafe == 0` and `applied + blocked + dodged + staggered == queued` in `/gt_lag_comp_status`.

**Guardrails.** Do not add a second hook on `StateIngame.update` (T5). Do not change eligibility, the queue cap, or the cancel rules. Do not turn the feature on by default.

**Stop and escalate if.** `_gt_cs_after_state_update` is no longer called every frame in a mission (check `GTD/_gt_time_hooks.lua:17-19`): report instead of adding a hook.

---

### WP-GT-10 Three small correctness fixes: keep test, manual dumps, `/bots_in_keep`

| Field | Value |
|---|---|
| Priority | P2 |
| Size | M (three independent parts; one commit each) |
| Agent | any |
| Depends on | WP-GT-03 part A (the helper module) |
| Issues | #247 (part B makes its diagnostics usable) |
| Source | A6-F10, A6-F13, A6-F24 (bots part) |
| Streams | `general_tweaker_dev/` only |

**Goal.** "Am I in the keep" no longer depends on a flag another command flips; `/dump_ai` and `/dump_menu` always write to the console log; `/bots_in_keep` removes its bots when switched off.

**Context.**
- Part A. `/inndmg` flips `DamageUtils.is_in_inn` (`GTD/_gt_godmode_qol.lua:120-131`). Vanilla sets that flag once per level from the level's `hub_level` setting (`V2SRC/scripts/game_state/state_ingame.lua:135-137`). gt_dev also uses it as its location test: `GTD/_gt_level_control.lua:110,314,338,403,517`, `GTD/_gt_bots_keep.lua:79-83`, `GTD/_gt_solo_qol.lua:75`, `GTD/_gt_debug_probes.lua:151`, `GTD/_gt_dummy_collision.lua:22-25`. After `/inndmg` in the keep, `/win`, `/fail` and `/restart` stop refusing. The engine's own location test is `LevelTransitionHandler:in_hub_level()` (`V2SRC/scripts/game_state/components/level_transition_handler.lua:708-716`).
- Part B. `/dump_ai` and `/dump_menu` set and reset a retired key `gt_debug_mode` that nothing reads (`GTD/_gt_debug_probes.lua:422-429`, `:908-913`). The dump lines go through `_dbg`, which is `mod:debug` (`:66-68`) and prints only when VMF logging is set to custom with debug output (`:96-105`). On a default setup the commands write nothing.
- Part C. `/bots_in_keep` only calls `mod:set` (`GTD/_gt_bots_keep.lua:370-372`). `mod:set` without a third argument does not call `on_setting_changed` (T3), and the bot clear lives only in that callback (`GTD/general_tweaker_dev.lua:657-670`). The fill still happens through a once-per-second hook, so ON works and OFF leaves the bots. `/no_bots` in the same file shows the right pattern (`:427-431`).

**Steps.**
1. Part A test: extend `qa/lua/tests/test_gt_world.lua` with cases for `in_hub()`: true when the stub `level_transition_handler:in_hub_level()` returns true; false when it returns nil or false; false when the handler is missing; false when `in_hub_level` raises. Add a static case: no file under `GTD/` except `_gt_godmode_qol.lua` contains `.is_in_inn`.
2. Part A code: add to `GTD/_gt_world.lua`
   ```lua
   function W.in_hub()
       local managers = engine.managers()
       local lth = managers and managers.level_transition_handler
       if not (lth and lth.in_hub_level) then return false end
       local ok, value = pcall(lth.in_hub_level, lth)
       return ok and value == true
   end
   ```
   Replace each location read listed in Context with `mod._gt_world.in_hub()`. In `GTD/_gt_dummy_collision.lua` and `GTD/_gt_bots_keep.lua` change only the body of the local helper (`_is_in_inn`, `_bik_in_inn`). Leave `/inndmg` itself unchanged.
3. Part B test: extend `qa/lua/tests/test_gt_vmf_debug_gate.lua` (it already loads `GTD/_gt_debug_probes.lua` under stubs, `:33-60`): with `mod.debug` a no-op and a `printf` stub that records lines, `mod._gt_dbg_force(function() mod._dbg_log("x %d", 1) end)` records `x 1`; calling `mod._dbg_log("y")` outside it records nothing. Add a static case: the dev file no longer contains `gt_debug_mode`.
4. Part B code in `GTD/_gt_debug_probes.lua`: add a file-local `_force_print = false`; make `_dbg` (`:66-68`) call `pcall(printf, fmt, ...)` when `_force_print` is true and `mod:debug(fmt, ...)` otherwise; add `mod._gt_dbg_force = function(fn) _force_print = true; local ok, err = pcall(fn); _force_print = false; if not ok then pcall(printf, "[gt:dump] error: %s", tostring(err)) end end`. Change the two commands to `mod._gt_dbg_force(function() _gt_dump_ai_now("manual") end)` and the same for `_gt_dump_menu_now`, deleting the four `gt_debug_mode` lines in each.
5. Part C: in the `/bots_in_keep` command compute `local new_val = not mod:get("gt_bots_in_keep")`, `mod:set("gt_bots_in_keep", new_val)`, then call `mod._bik_fill()` when `new_val` is true or `mod._bik_clear()` when false (nil-check both), and echo the new state.
6. Bump version and changelog per commit.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` passes. `git grep -n "\.is_in_inn" -- general_tweaker_dev/scripts` lists only `_gt_godmode_qol.lua`. `git grep -n "gt_debug_mode" -- general_tweaker_dev/scripts` prints nothing.
- RIG A: `qa/runtime/gt/inndmg_keeps_level_control_refusing.lua`, arena `keep`: note the level key; `T.cmd("inndmg")`; `T.cmd("fail")`; `T.wait(10)`; `T.expect_eq(Managers.level_transition_handler:get_current_level_key(), <noted key>, "still in the keep")`; `T.cmd("inndmg")` to restore.
- RIG B: `qa/runtime/gt/dump_ai_prints.lua`, arena `keep`: `T.cmd("dump_ai")`; `host_expect_log = { { pattern = "%[ai_dump:manual%] === END ===", count = 1 } }`.
- RIG C: `qa/runtime/gt/bots_in_keep_toggle.lua`, arena `keep`: `T.cmd("bots_in_keep")`; `T.wait_until(function() return #Managers.player:bots() >= 1 end, 10, "bots filled")`; `T.cmd("bots_in_keep")`; `T.wait_until(function() return #Managers.player:bots() == 0 end, 10, "bots cleared")`.
- Evidence class: U for parts A and B logic, R for all three effects. Part B advances #247 only as tooling.

**Guardrails.** Part B: `qa/lua/tests/test_gt_vmf_debug_gate.lua` pins the VMF predicate in this file; do not touch `vmf_debug_enabled` or `mod._dbg_on`. The automatic dumps (state enter, layout change) stay gated as they are. Part A: do not change what `/inndmg` does to damage. Do not edit the stable tree.

**Stop and escalate if.** RIG A fails because `in_hub_level()` is false in the keep on the rig's profile: report the level key and stop; do not fall back to `is_in_inn`.

---

### WP-GT-11 Archive the legacy `tweaker` mod and drop its 13 QA exclusions

| Field | Value |
|---|---|
| Priority | P3 |
| Size | M |
| Agent | any |
| Depends on | none |
| Issues | none |
| Source | A6-F20 |
| Streams | repo root: `tweaker/`, `qa/`, `tools/gen-name-map/`, docs |

**Goal.** `tweaker/` is no longer in the active tree, no QA or tool script carries a special case for it, and nothing about its Workshop item changes.

**Context.**
- `tweaker/` is the original monolith (mod id `t`, `tweaker/tweaker.mod:5`), raw SDK layout, 9 tracked files, last changed at commit `5c0fd6d3` (2026-04-24). It is excluded from `tools/mod-inventory.psd1` (`:35-36`), so nothing builds it. No Lua outside it calls `get_mod("t")`.
- 13 scripts special-case it (15 lines): `qa/check_event_register_signature.ps1:118`, `qa/check_file_sizes.ps1:94`, `qa/check_localization.ps1:31,41`, `qa/check_logging.ps1:293`, `qa/check_name_integrity.ps1:268`, `qa/check_unpack_safety.ps1:111`, `qa/check_versions.ps1:64`, `qa/check_vmf_widget_types.ps1:130`, `tools/gen-name-map/gen-name-map.ps1:437` (all `-notlike "*\tweaker\*"`); `qa/check_loc_description_titles.ps1:40` and `qa/check_loc_tags.ps1:78` (`$dir.Name -eq 'tweaker'`); `qa/check_loc_tags.ps1:165` (`-like 'tweaker/*'`); `qa/check_hook_test_coverage.ps1:62` and `qa/check_native_resource_safety.ps1:39` (regex `(^|/)tweaker/scripts/`).
- Repo convention: retired mods live under `_archive/` on disk and are NOT committed (`.gitignore:99-101` ignores `_archive/`). `_archive/README.md` lists `tweaker/` under "Not touched (yet)" pending maintainer sign-off: see GT-D5.
- `tweaker/.build/` (27 MB) is untracked build output, ignored by `**/.build/` (`.gitignore:2`).

**Steps.**
1. Preconditions: `git grep -n "get_mod(\"t\")" -- "*.lua" ":!tweaker"` prints nothing; `git ls-files tweaker` lists exactly 9 files. If either differs, stop.
2. Copy the whole `tweaker/` directory (tracked files and `.build/`) to `_archive/tweaker_legacy_20260424/` on disk. Verify the copy has the 9 tracked files. Then `git rm -r tweaker` and move (do not delete) the leftover untracked `tweaker/.build/` away so that no `tweaker/` directory remains; it is already in the copy.
3. Remove the 15 exclusion clauses listed in Context. Delete only the `tweaker` clause and keep the neighbours (`_archive`, `.temp`, `sample_*`): for example `qa/check_loc_tags.ps1:78` becomes `if ($dir.Name.StartsWith('_')) { continue }`, `:165` becomes `if (-not $relative) { continue }`, `qa/check_native_resource_safety.ps1:39` keeps its `_archive` half, `qa/check_hook_test_coverage.ps1:62` is deleted. Fix the comments that mention the exclusion (`qa/check_event_register_signature.ps1:31,106`, `qa/check_logging.ps1:71`, `qa/check_unpack_safety.ps1:24`, `qa/check_pipeline_state.ps1:10`).
4. Update references: `README.md:42` (keep the Workshop link; say the source is in git history at `5c0fd6d3`), `CLAUDE.md:181,313`, `DEVELOPMENT.md:18,45,413,469`, the comment at `tools/mod-inventory.psd1:35-36`, `docs/LOCALIZATION_STANDARD.md:693`, and move the `tweaker/` bullet in `_archive/README.md` from "Not touched (yet)" into the table.
5. Run the QA self-tests and the quick suite (commands below) and fix any fixture that named the legacy directory.

**Acceptance (machine, no human).**
- OFFLINE: `git ls-files tweaker` prints nothing. `git grep -nF "\tweaker\" -- qa tools` prints nothing. `git grep -n "'tweaker'" -- qa tools` prints nothing. `git grep -n "(^|/)tweaker/" -- qa tools` prints nothing. `git grep -n "'tweaker/\*'" -- qa` prints nothing. `pwsh -NoProfile -File qa/run_selftests.ps1` exits 0. `pwsh -NoProfile -File qa/run_all.ps1 -Quick` reports no failure that is absent on the base commit.
- RIG: none.
- Evidence class: S.

**Guardrails.** Do not upload, hide, or edit Workshop item 3704660429. Do not `git add -f` anything under `_archive/`. Do not change any data entry in `tools/mod-inventory.psd1`. Patterns such as `weapon_tweaker` and `*_tweaker` are other mods: touch only the clauses listed. Delete nothing from disk.

**Stop and escalate if.** A script outside the list reads `tweaker/` at run time. A QA check starts failing on a different mod after an exclusion is removed (that exclusion was hiding something else): restore that one clause and report it.

---

## Owner decisions

The owner is unavailable. Proceed on the default; write the decision id in the pull request when a card relies on it.

| Id | Question | Conservative default an agent assumes |
|---|---|---|
| GT-D1 | May other players ask a gt host to win, fail or restart, respawn them, honour their godmode, or spawn enemies? | Only when the host ticks one new option, default OFF, in both the dev and the public build (WP-GT-01). AI takeover requests stay as they are. |
| GT-D2 | Should host melee lag compensation be on by default? | No. Off by default with a one-time reset for existing users (WP-GT-02). It may return to ON only after a two-machine rig run passes for #1034 and WP-GT-09 has landed. |
| GT-D3 | Who approves and publishes the public-tree halves of WP-GT-01 and WP-GT-02? | The maintainer. Agents prepare the stable hunk on its own branch as "Mode A" (`docs/PROMOTION_PROCESS.md:89-110`), do not set `VT2_PROMOTION`, do not write the approval comment, do not pick a version number for upload, and do not publish. The dev halves land without waiting. |
| GT-D4 | Should the always-on engine guards be narrowed or removed? | Not yet. They stay ON for players; the rig runs with them OFF and reports what breaks (WP-GT-05). Revisit with the counters. |
| GT-D5 | Archive the legacy `tweaker` directory, and what about its Workshop item? | Archive the directory (reversible with `git revert`; history at `5c0fd6d3`). Leave Workshop item 3704660429 and its description untouched (WP-GT-11). |
| GT-D6 | May presence-only regression checks be deleted? | Yes, except checks whose name cites an open issue, and anything referenced by `tools/verify/*.psd1` or a rig script (WP-GT-07). |
| GT-D7 | On the three Verminious Dreams levels in Chaos Wastes, which mod owns curse lighting when both vdl and Chaos Wastes Tweaker are loaded? | No change. Both layers stay as they are; only the world gate lands (WP-GT-08). |
| GT-D8 | Boss spawn spheres and bot leash lines draw with `LineObject`, which the repo's own notes say may not render in retail (`GTD/_gt_debug_highlights.lua:11-27`). Port, delete or keep? | Keep unchanged. WP-GT-03 must preserve them exactly. A rig still (`T.shot`) with the options on goes to the human list. |
| GT-D9 | Should General Tweaker be split into several Workshop items? | No. One item; internal refactors only. |
