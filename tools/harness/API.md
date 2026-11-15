# Rig test API (`T`)

Every helper a rig case may call, in one table (WP-H-06). A case gets `T` as the argument of its `run(T)`; see `docs/program/CONVENTIONS.md` section 3 for the case and verdict rules.

Where helpers live:

- **driver**: `tools/harness/driver/vt2_rig_driver.lua`, function `new_T`.
- **lib/&lt;group&gt;.lua**: a helper group under `tools/harness/driver/lib/`. Every `*.lua` there travels with the plan (`New-RigProfile.ps1 -LibDir`, set by `run.ps1`), returns `install(T, ctx)`, and is installed into each case's `T` after the driver's own helpers. `ctx` holds the case (`ctx.case.id`, `ctx.case.cleanups`), `record`, `out`, `q`, `now()`, `find_mod`, `local_player`, `local_hero` and `level_key`. A group that does not load prints `LIB id=<group> ok=false`; its helpers stay nil, so a case calling one ends as ERROR.
- **planned**: named by the card or a verification pack, not built yet. A case must not call it (the stub check rejects it) or must guard with `if T.<name> then`.

Rules every helper keeps (card WP-H-06 guardrails): no backend commit call, no save written, no OS input. Engine calls that take a unit run in the main update through `T.main` (they fail inside the case coroutine). Whatever a helper changes is undone when the case ends (`case.cleanups`, newest first, also after ERROR and TIMEOUT; one `CLEANUP id=<case> actions=<n> errors=<n>` line).

`qa/check_runtime_scripts.ps1` keeps this table honest: every `T.<name>` used outside a comment in `qa/runtime/**/*.lua` and every name in the stub `qa/runtime/_stub/T.lua` must be a row, a row whose status is not `planned...` must be defined by the driver or a group, and a planned row must not be.

Packs column: CONV = `docs/program/CONVENTIONS.md` section 3; D1 to D5 and CLOSED = `docs/program/vp/<name>.md`. Wraps column: engine paths are under `Vermintide-2-Source-Code/`; C1 row N = `docs/audits/2026-11-13_FORMAL_AUDIT/evidence/C1.md` section 4.3 row N. Rig column: committed plans whose cases call the helper; "offline" means only the Lua suites (`qa/lua/tests/test_rig_driver.lua`, `qa/lua/tests/test_rig_api_*.lua`) exercise it so far.

## Flow and assertions

| Helper | Status | What it does | Wraps | Packs | Rig |
|---|---|---|---|---|---|
| `T.step(label)` | driver | names the next action (`STEP` line) | none | CONV, D1, D2, CLOSED | every plan |
| `T.note(key, value)` | driver | free evidence line (`NOTE`) | none | CONV, all packs | every plan |
| `T.wait(seconds)` | driver | yields until the driver clock has advanced | none | CONV, D1, D3, D4, D5 | shield-equip, sweep, api-selftest |
| `T.frames(n)` | driver | yields n updates | none | CONV, D1, D2 | api-selftest |
| `T.wait_until(fn, timeout, label)` | driver | yields until `fn()` is truthy; a FAIL assertion on timeout | none | CONV, all packs | mission-smoke, api-selftest |
| `T.require(cond, label)` | driver | precondition; false ends the case INCONCLUSIVE | none | CONV, all packs | shield-equip, api-selftest |
| `T.expect(cond, label)` | driver | assertion; the case continues after a failure | none | CONV, D4, D5 | every plan |
| `T.expect_eq(got, want, label)` | driver | equality assertion with got/want in the line | none | CONV, D3 | every plan |
| `T.expect_near(got, want, tol, label)` | driver | numeric assertion within `tol` (default 0.001) | none | CONV, D2 | api-selftest |
| `T.case_id` | driver | field: the plan's id of this case | none | none | api-selftest |
| `T.nonce` | driver | field: the run nonce (matches `plan.nonce`) | none | none | smoke plans, api-selftest |
| `T.main(fn, ...)` | driver | runs `fn` in the main update, outside the case coroutine, and returns its results; an error there is raised in the case | none | none | mission-smoke, api-selftest |

## World and units

| Helper | Status | What it does | Wraps | Packs | Rig |
|---|---|---|---|---|---|
| `T.find_mod(name)` | driver | the VMF mod object or nil | `get_mod` (`Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/vmf_mod_manager.lua:135`) | none | smoke plans, api-selftest |
| `T.local_player()` | driver | the local player | `PlayerManager.local_player` (`Vermintide-2-Source-Code/scripts/managers/player/player_manager.lua:580`) | none | smoke plans, shield-equip, api-selftest |
| `T.local_hero(timeout)` | driver | waits until the local hero unit is alive and returns it | `player.player_unit`, `Unit.alive` | CONV, D1, D3, D5, CLOSED | smoke plans, mission-smoke, api-selftest |
| `T.level_key()` | driver | the current level key (`inn_level` in the keep) | `GameModeManager.level_key` (`scripts/managers/game_mode/game_mode_manager.lua:897`) | none | smoke plans, mission-smoke, api-selftest |
| `T.bots()` | driver | the alive bot units | `PlayerManager.bots` (`player_manager.lua:602`) | CONV, D3, CLOSED | mission-smoke, api-selftest |
| `T.first_bot_unit()` | planned: actor input | the first alive bot unit, waiting until one exists | `PlayerManager.bots` | CONV, D4 | none |
| `T.ext(unit, system)` | driver | `ScriptUnit.has_extension` in the main update, or INCONCLUSIVE | engine `ScriptUnit` | CONV, all packs | mission-smoke, api-selftest |
| `T.spawn(breed, offset, timeout)` | driver | queues one enemy next to the hero, returns the unit once alive; killed at cleanup | `ConflictDirector.spawn_queued_unit` (`scripts/managers/conflict_director/conflict_director_testify.lua:18-22`, `conflict_director.lua:1732`, `:2144`) | CONV, all packs | mission-smoke |
| `T.kill(unit)` | driver | kills a unit with the game's helper | `AiUtils.kill_unit` (`scripts/unit_extensions/human/ai_player_unit/ai_utils.lua:1326`) | none | mission-smoke |
| `T.teleport(unit, position)` | driver | moves a unit with a `teleport_to` locomotion | `PlayerUnitLocomotionExtension.teleport_to` (`scripts/unit_extensions/default_player_unit/player_unit_locomotion_extension.lua:1005`) | D5 | offline |
| `T.invincible(on)` | driver | sets the hero's `is_invincible`; restored at cleanup | `GenericHealthExtension.get_is_invincible` (`scripts/unit_extensions/generic/generic_health_extension.lua:496-512`) | none | mission-smoke |
| `T.end_level(result)` | driver | ends the level as host (`"fail"` or complete) | `GameModeManager.complete_level` / `fail_level` (`game_mode_manager.lua:636`, `:645`) | none | offline |
| `T.return_to_keep(timeout)` | driver | loads the keep and waits until it is ready | `GameMechanismManager.debug_load_level` (`scripts/managers/game_mode/game_mechanism_manager.lua:880-892`) | none | offline |
| `T.pickup(name, offset)` | planned: actor input | spawns a pickup next to the hero, tracked for cleanup | not chosen yet | CONV, D1, D3, D4, D5, CLOSED | none |

## Mods, commands and regression rows

| Helper | Status | What it does | Wraps | Packs | Rig |
|---|---|---|---|---|---|
| `T.cmd(name, ...)` | driver | runs a mod chat command in the main update and returns the lines it printed | `vmf.run_command` (`Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/commands.lua:153`) | CONV, all packs | sweep-public, sweep-dev |
| `T.commands(prefix)` | driver | the registered command names | `vmf.get_commands_list` (`commands.lua:131`) | none | smoke plans, sweep, api-selftest |
| `T.expect_rt(mod_id, check)` | driver | assertion on a row `/<mod>_regression_test` echoed earlier in this boot (PASS/XPASS pass; FAIL/XFAIL/BAD-SHAPE fail; SKIP or missing = INCONCLUSIVE) | VMF `echo` capture | CONV, all packs | issue cases (WP-H-03) |
| `T.set(mod_id, setting, value)` | lib/settings.lua | changes one mod option with the mod's own setter and its `on_setting_changed`; the value before the case's first change is put back at cleanup; returns the old value (`SET`, `SET RESTORE` lines) | `VMFMod:set(id, value, notify_mod)` (`Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/settings.lua:46-61`; event `modules/core/events.lua:79-84`) | CONV, all packs | api-selftest |

## Career and loadout

Every change goes through the game's own setters (the ones the hero view and the game's test hooks call), never a backend commit; the change sits in the backend mirror and the write shield (WP-H-14) holds it back from the game's next commit. Each change is undone at cleanup.

| Helper | Status | What it does | Wraps | Packs | Rig |
|---|---|---|---|---|---|
| `T.career(profile, career, timeout)` | lib/inventory.lua | switches the local hero to `career` of hero `profile` (e.g. `"empire_soldier"`, `"es_mercenary"`) and waits until the player reports it with a new living unit, which it returns; INCONCLUSIVE when the career is not unlocked; the career before the case's first switch is requested again at cleanup without waiting (a later case that needs a career calls `T.career` itself). The card calls it `T.set_career`; the packs use `T.career` (`CAREER`, `CAREER RESTORE` lines) | `GameNetworkManager.request_profile` (`scripts/managers/network/game_network_manager.lua:358`, as `scripts/game_state/state_ingame_testify.lua:98` calls it); unlock: `scripts/settings/profiles/career_settings.lua:23-39`; the game records the selection at `scripts/game_state/components/profile_synchronizer.lua:747` | D2, D4 | api-selftest |
| `T.equip(career, slot, item)` | lib/inventory.lua | equips an owned item (backend id or item key) in a loadout slot of `career` (nil: the career played) and, when that career is played, shows it on the hero the way the hero view does; the item before the case's first change of that career and slot is put back at cleanup; returns the backend id (`EQUIP`, `EQUIP RESTORE` lines). The card writes `T.equip(slot, item)`; D2 and D4 pass the career first | `BackendUtils.set_loadout_item` (`scripts/managers/backend/backend_utils.lua:22`); then as `HeroViewStateOverview._set_loadout_item` and `post_update` (`scripts/ui/views/hero_view/states/hero_view_state_overview.lua:1116-1131`, `:705-724`): `SimpleInventoryExtension.create_equipment_in_slot` (`scripts/unit_extensions/default_player_unit/inventory/simple_inventory_extension.lua:1372`), `create_attachment_in_slot`, `set_equipped_frame` | D2, D4 | api-selftest |
| `T.loadout(career)` | lib/inventory.lua | read-only: the backend id in every loadout slot (`stored_in_backend`) of a career (nil: the career played) | `BackendUtils.get_loadout_item_id` (`backend_utils.lua:14`); slots `scripts/settings/inventory_settings.lua:15-100` | none | api-selftest |
| `T.backend_items(filter)` | lib/inventory.lua | read-only: the owned backend items for which `filter(item)` is true, as a list (items carry `backend_id`, `key`, `data`) | `get_all_backend_items` (`scripts/managers/backend_playfab/backend_interface_item_playfab.lua:431`; fields `playfab_mirror_base.lua:1784-1786`) | none | api-selftest |

## Backend, shared helpers and evidence

| Helper | Status | What it does | Wraps | Packs | Rig |
|---|---|---|---|---|---|
| `T.shield()` | driver | a copy of what the backend write shield counted so far | none (WP-H-14) | none | shield-equip, api-selftest |
| `T.shared(name)` | driver | a shared helper table from `qa/runtime/_shared/<name>.lua`, or INCONCLUSIVE | none | none | shield-equip, api-selftest |
| `T.shot(label)` | lib/shot.lua | records that the case asked for a still (`SHOT ... captured=false`) and returns false; the capture is WP-H-10 | none yet | CONV, all packs | api-selftest |

## Planned groups (WP-H-06 step 2, one pull request each)

| Helper | Status | What it does | Wraps | Packs | Rig |
|---|---|---|---|---|---|
| `T.open_view(name, params)` | planned: UI | opens a UI view and waits until it is active | `IngameUI.handle_transition` (`scripts/ui/views/ingame_ui.lua:919`; C1 row 39) | CONV, D1, D2, D3, D4 | none |
| `T.widget(view, name)` | planned: UI | a widget's content table of an open view | widget `content` tables (C1 row 39) | CONV, D1, D2, D3 | none |
| `T.press(view, widget, hotspot)` | planned: UI | sets a hotspot field (`on_pressed`, `on_right_click`) on an open view's widget | `scripts/ui/views/hero_view/windows/hero_window_cosmetics_inventory_testify.lua:7-9` (C1 row 40) | D2, D4 | none |
| `T.close_view()` | planned: UI | closes the open view | not chosen yet | none | none |
| `T.previewer()` | planned: UI | the live `MenuWorldPreviewer` of the open view (field path `[unverified]`, D2) | not chosen yet | D2 | none |
| `T.score_previewers()` | planned: UI | the `TeamPreviewer.hero_previewers` list (field path `[unverified]`, D2) | not chosen yet | D2 | none |
| `T.as_bot(unit)` | planned: actor input | drives a bot's input: `tap_attack`, `hold_attack`, `defend`, `fire`, `charge_shot`, `activate_ability`, `wield(slot)` | `PlayerBotInput` methods (`scripts/unit_extensions/human/player_bot_unit/player_bot_input.lua:262-325`) | CONV, D1, D3, D4, D5 | none |
| `T.hero_input(action)` | planned: actor input | feeds the local hero's input extension (cases start with `T.require`) | not chosen yet | D2 | none |
| `T.transmit_spy(rpc_name)` | planned: wire | records the arguments passed to `network_transmit` for one RPC during a step (D1 calls it `T.spy`) | `NetworkTransmit.send_rpc*` (`scripts/network/network_transmit.lua:169-371`) | D1 | none |

## Adding a helper

1. Write it in a group under `tools/harness/driver/lib/` (or the driver for flow control), with the decompile or framework citation of the call it wraps next to it.
2. Add its name to `NAMES` in `qa/runtime/_stub/T.lua` and change its row here from `planned...` to the group file.
3. Add an offline test to `qa/lua/tests/test_rig_api_<group>.lua` (list the suite in `qa/lua/run.lua`), using the simulated game of `qa/lua/tests/_rig_driver_env.lua`.
4. Add a case that calls it once to `qa/runtime/plans/api-selftest.json`.
