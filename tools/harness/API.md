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
| `T.first_bot_unit(timeout)` | lib/actor.lua | the first alive bot unit (`T.bots` order), waiting up to `timeout` (30 s); INCONCLUSIVE without one (the keep has no bots) | `PlayerManager.bots` | CONV, D4 | api-selftest |
| `T.ext(unit, system)` | driver | `ScriptUnit.has_extension` in the main update, or INCONCLUSIVE | engine `ScriptUnit` | CONV, all packs | mission-smoke, api-selftest |
| `T.spawn(breed, offset, timeout)` | driver | queues one enemy next to the hero, returns the unit once alive; killed at cleanup | `ConflictDirector.spawn_queued_unit` (`scripts/managers/conflict_director/conflict_director_testify.lua:18-22`, `conflict_director.lua:1732`, `:2144`) | CONV, all packs | mission-smoke |
| `T.kill(unit)` | driver | kills a unit with the game's helper | `AiUtils.kill_unit` (`scripts/unit_extensions/human/ai_player_unit/ai_utils.lua:1326`) | none | mission-smoke |
| `T.teleport(unit, position)` | driver | moves a unit with a `teleport_to` locomotion; `position` is `{ x, y, z }` or a box (made into a Vector3 in the same main update that calls `teleport_to`, driver 0.4.7) or a Vector3 (passed as it is, so it must be alive in that update: one returned by an earlier `T.main` is a dead temporary); refreshes the unit's `POSITION_LOOKUP` entry first, which the main update would otherwise see as the previous frame's dead Vector3 (driver 0.4.8, README "main update" note) | `PlayerUnitLocomotionExtension.teleport_to` (`scripts/unit_extensions/default_player_unit/player_unit_locomotion_extension.lua:1005`) | D5 | api-selftest |
| `T.invincible(on)` | driver | sets the hero's `is_invincible`; restored at cleanup | `GenericHealthExtension.get_is_invincible` (`scripts/unit_extensions/generic/generic_health_extension.lua:496-512`) | none | mission-smoke, api-selftest |
| `T.end_level(result)` | driver | ends the level as host (`"fail"` or complete) | `GameModeManager.complete_level` / `fail_level` (`game_mode_manager.lua:636`, `:645`) | none | offline |
| `T.return_to_keep(timeout)` | driver | loads the keep and waits until it is ready | `GameMechanismManager.debug_load_level` (`scripts/managers/game_mode/game_mechanism_manager.lua:880-892`) | none | offline |
| `T.pickup(name, offset)` | lib/actor.lua | drops pickup `name` (an `AllPickups` key, e.g. `"healing_draught"`) next to the hero, raycast down from 1 m above hero + `offset` (default `{ 1, 0, 0 }`); host only; INCONCLUSIVE when nothing spawned (its package may not be loaded in the level); removed at cleanup if still lying (`PICKUP` line) | `PickupSystem.buff_spawn_pickup` (`scripts/entity_system/systems/pickups/pickup_system.lua:1181-1206`, as `buff_templates.lua:1695` drops one at a player); names `scripts/settings/equipment/pickups.lua:939-952`; removal `_delete_pickup` (`pickup_system.lua:1451-1457`) | CONV, D1, D3, D4, D5, CLOSED | api-selftest |
| `T.as_bot(unit)` | lib/actor.lua | a driver for a bot's input: `tap_attack`, `hold_attack`, `defend`, `fire`, `fire_hold`, `charge_shot`, `activate_ability`, `melee_push`, `dodge`, `interact`, `weapon_reload` (each `(frames)`: one update of input per frame, repeat to hold) and `wield(slot_name)`; `bot.input` is the extension. The bot's own behaviour keeps running; the case asserts the effect (`BOT INPUT` lines) | `PlayerBotInput` methods (`scripts/unit_extensions/human/player_bot_unit/player_bot_input.lua:262-319`), turned into input by `_update_actions` (`:85`, wield `:202-220`) | CONV, D1, D3, D4, D5 | api-selftest |

## Mods, commands and regression rows

| Helper | Status | What it does | Wraps | Packs | Rig |
|---|---|---|---|---|---|
| `T.cmd(name, ...)` | driver | runs a mod chat command in the main update and returns the lines it printed | `vmf.run_command` (`Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/commands.lua:153`) | CONV, all packs | sweep-public, sweep-dev |
| `T.commands(prefix)` | driver | the registered command names | `vmf.get_commands_list` (`commands.lua:131`) | none | smoke plans, sweep, api-selftest |
| `T.expect_rt(mod_id, check)` | driver | assertion on a row `/<mod>_regression_test` echoed earlier in this boot (PASS/XPASS pass; FAIL/XFAIL/BAD-SHAPE fail; SKIP or missing = INCONCLUSIVE) | VMF `echo` capture | CONV, all packs | issue cases (WP-H-03) |
| `T.set(mod_id, setting, value)` | lib/settings.lua | changes one mod option with the mod's own setter and its `on_setting_changed`; the value before the case's first change is put back at cleanup; returns the old value (`SET`, `SET RESTORE` lines) | `VMFMod:set(id, value, notify_mod)` (`Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/settings.lua:46-61`; event `modules/core/events.lua:79-84`) | CONV, all packs | api-selftest |

## UI

No OS input: views open and close through IngameUI transitions and a press sets a hotspot field, as the game's own test hooks do. A view the case opened and left open is closed at cleanup. Closing the hero view makes the game commit (`hero_view.lua:523`); the write shield holds the official rows.

| Helper | Status | What it does | Wraps | Packs | Rig |
|---|---|---|---|---|---|
| `T.open_view(name, params, transition, timeout)` | lib/ui.lua | opens the view `name` (a key of `ingame_ui.views`, e.g. `"hero_view"`) through the `"<name>_force"` transition (or `transition`), waits until it is the current view and returns it; `params` go to the view's `on_enter` (hero view: `menu_state_name`, `menu_sub_state_name`); a missing UI, view or transition, or a refused transition, is INCONCLUSIVE (`VIEW OPEN` line) | `IngameUI.handle_transition` (`scripts/ui/views/ingame_ui.lua:919-974`), transitions `scripts/ui/views/ingame_ui_settings.lua:441-443`; as `scripts/tests/testify_snippets.lua:76-86`; UI from `UIManager.ingame_ui` (`scripts/managers/ui/ui_manager.lua:240`) | CONV, D1, D2, D3, D4 | api-selftest |
| `T.close_view(timeout)` | lib/ui.lua | closes the current view with `exit_menu` and waits until none is current (`VIEW CLOSE` line) | `exit_menu` (`ingame_ui_settings.lua:506-518`), as `HeroView.exit` (`scripts/ui/views/hero_view/hero_view.lua:576-589`) | none | api-selftest |
| `T.widget(owner, name)` | lib/ui.lua | a widget (with its `content` table) of an open view, one of its states or windows: `owner` is the view's name or any of those tables (`_widgets_by_name` or `widgets_by_name`); INCONCLUSIVE when missing | `_widgets_by_name` (e.g. `scripts/ui/views/hero_view/states/hero_view_state_overview.lua:177-190`; C1 row 39) | CONV, D1, D2, D3 | api-selftest |
| `T.press(owner, widget, hotspot, field, frames)` | lib/ui.lua | sets `content[hotspot][field] = true` in the main update (`hotspot` defaults to `button_hotspot`, else `hotspot`; `field` to `on_release`), then waits up to `frames` updates (10) for it to go false again and returns whether it did; an unread press is reset. Also `T.press(widget, hotspot, field, frames)`. The case asserts the effect (`PRESS` line) | `UIUtils.is_button_pressed` reads and clears `on_release` (`scripts/helpers/ui_utils.lua:381-389`); the game's test hook sets `on_right_click` the same way (`scripts/ui/views/hero_view/windows/hero_window_cosmetics_inventory_testify.lua:7-9`; C1 row 40) | D2, D4 | api-selftest |

## Career and loadout

Every change goes through the game's own setters (the ones the hero view and the game's test hooks call), never a backend commit; the change sits in the backend mirror and the write shield (WP-H-14) holds it back from the game's next commit. Each change is undone at cleanup.

| Helper | Status | What it does | Wraps | Packs | Rig |
|---|---|---|---|---|---|
| `T.career(profile, career, timeout)` | lib/inventory.lua | switches the local hero to `career` of hero `profile` (e.g. `"empire_soldier"`, `"es_mercenary"`) and waits until the player reports it with a new living unit, which it returns; INCONCLUSIVE when the career is not unlocked; the career before the case's first switch is requested again at cleanup without waiting (a later case that needs a career calls `T.career` itself). The card calls it `T.set_career`; the packs use `T.career` (`CAREER`, `CAREER RESTORE` lines) | `GameNetworkManager.request_profile` (`scripts/managers/network/game_network_manager.lua:358`, as `scripts/game_state/state_ingame_testify.lua:98` calls it); unlock: `scripts/settings/profiles/career_settings.lua:23-39`; the game records the selection at `scripts/game_state/components/profile_synchronizer.lua:747` | D2, D4 | api-selftest |
| `T.equip(career, slot, item)` | lib/inventory.lua | equips an owned item (backend id or item key) in a loadout slot of `career` (nil: the career played) and, when that career is played, shows it on the hero the way the hero view does; the item before the case's first change of that career and slot is put back at cleanup; returns the backend id (`EQUIP`, `EQUIP RESTORE` lines). The card writes `T.equip(slot, item)`; D2 and D4 pass the career first | `BackendUtils.set_loadout_item` (`scripts/managers/backend/backend_utils.lua:22`); then as `HeroViewStateOverview._set_loadout_item` and `post_update` (`scripts/ui/views/hero_view/states/hero_view_state_overview.lua:1116-1131`, `:705-724`): `SimpleInventoryExtension.create_equipment_in_slot` (`scripts/unit_extensions/default_player_unit/inventory/simple_inventory_extension.lua:1372`), `create_attachment_in_slot`, `set_equipped_frame` | D2, D4 | api-selftest |
| `T.loadout(career)` | lib/inventory.lua | read-only: the backend id in every loadout slot (`stored_in_backend`) of a career (nil: the career played) | `BackendUtils.get_loadout_item_id` (`backend_utils.lua:14`); slots `scripts/settings/inventory_settings.lua:15-100` | none | api-selftest |
| `T.backend_items(filter)` | lib/inventory.lua | read-only: the owned backend items for which `filter(item)` is true, as a list (items carry `backend_id`, `key`, `data`) | `get_all_backend_items` (`scripts/managers/backend_playfab/backend_interface_item_playfab.lua:431`; fields `playfab_mirror_base.lua:1784-1786`) | none | api-selftest |

## Wire

| Helper | Status | What it does | Wraps | Packs | Rig |
|---|---|---|---|---|---|
| `T.transmit_spy(rpc_names)` | lib/wire.lua | records every call of the network transmit's senders whose RPC is `rpc_names` (a name, a list, or nil for all) and passes each call through; returns `spy` with `calls` (`{ rpc, via, n, args }`, args after `rpc_name`, engine values as text), `count(name)` and `stop()` (also at cleanup; a wrapper installed on top after the start is left in place). A solo host still calls the senders, so the ids recorded are the ones a client would receive (D1 primitive P7; D1 calls it `T.spy`) (`SPY START`, `SPY STOP` lines) | `NetworkTransmit.send_rpc*` (`scripts/network/network_transmit.lua:169-533`) on `Managers.state.network.network_transmit` (`scripts/managers/network/game_network_manager.lua:109`) | D1 | api-selftest |

## Chaos Wastes

For cases in a `"deus:<level_key>"` arena (a run level, e.g. `pat_mountain_wastes_path1`); the `"deus"` arena is the hub, where no run exists. Paths under `scripts/managers/game_mode/mechanisms/` unless given.

| Helper | Status | What it does | Wraps | Packs | Rig |
|---|---|---|---|---|---|
| `T.deus_run_controller()` | lib/deus.lua | the current run's DeusRunController, or INCONCLUSIVE outside a run | `DeusMechanism.get_deus_run_controller` (`deus_mechanism.lua:523-525`) | WP-H-05 card | deus-smoke |
| `T.grant_boon(name, rarity)` | lib/deus.lua | grants one boon (a `DeusPowerUpTemplates` key; rarity default `"rare"`) to the local player; it stays for the run (`BOON GRANT` line) | `DeusPowerUpUtils.generate_specific_power_up` + `DeusRunController.add_power_ups`, as `scripts/game_state/state_ingame_testify.lua:185-197` (`deus_run_controller.lua:1126`) | WP-H-05 card | deus-smoke |
| `T.has_boon(name, rarity)` | lib/deus.lua | whether the local player holds that boon in this run | `DeusRunController.has_power_up_by_name` (`deus_run_controller.lua:1523-1535`) | WP-H-05 card | deus-smoke |
| `T.deus_coins()` | lib/deus.lua | the local player's coins in this run | `DeusRunController.get_player_soft_currency` (`deus_run_controller.lua:925-927`) | WP-H-05 card | deus-smoke |
| `T.set_deus_coins(n)` | lib/deus.lua | sets them; the value before the case's first change is put back at cleanup (`DEUS COINS` lines) | `DeusRunState.set_player_soft_currency` (`deus_run_state.lua:575-579`) | WP-H-05 card | deus-smoke |

## Backend, shared helpers and evidence

| Helper | Status | What it does | Wraps | Packs | Rig |
|---|---|---|---|---|---|
| `T.shield()` | driver | a copy of what the backend write shield counted so far | none (WP-H-14) | none | shield-equip, api-selftest |
| `T.shared(name)` | driver | a shared helper table from `qa/runtime/_shared/<name>.lua`, or INCONCLUSIVE | none | none | shield-equip, api-selftest |
| `T.shot(label)` | lib/shot.lua | records that the case asked for a still (`SHOT ... captured=false`) and returns false; the capture is WP-H-10 | none yet | CONV, all packs | api-selftest |

## Planned

Not built yet. `T.previewer` and `T.score_previewers` need the field path from an open view to its previewers resolved once in the game (D2 marks it `[unverified]`); `T.hero_input` needs a way to feed the local hero's input extension without OS input, not chosen yet. Until then a case that needs one starts with `T.require`.

| Helper | Status | What it does | Wraps | Packs | Rig |
|---|---|---|---|---|---|
| `T.previewer()` | planned: UI | the live `MenuWorldPreviewer` of the open view (field path `[unverified]`, D2) | not chosen yet | D2 | none |
| `T.score_previewers()` | planned: UI | the `TeamPreviewer.hero_previewers` list (field path `[unverified]`, D2) | not chosen yet | D2 | none |
| `T.hero_input(action)` | planned: actor input | feeds the local hero's input extension (cases start with `T.require`) | not chosen yet | D2 | none |

## Adding a helper

1. Write it in a group under `tools/harness/driver/lib/` (or the driver for flow control), with the decompile or framework citation of the call it wraps next to it.
2. Add its name to `NAMES` in `qa/runtime/_stub/T.lua` and change its row here from `planned...` to the group file.
3. Add an offline test to `qa/lua/tests/test_rig_api_<group>.lua` (list the suite in `qa/lua/run.lua`), using the simulated game of `qa/lua/tests/_rig_driver_env.lua`.
4. Add a case that calls it once to `qa/runtime/plans/api-selftest.json`.
