> [!WARNING]
> ⚠ **SUPERSEDED** — this snapshot is from 2026-05-01 (71 days old).
> Recent state may differ. Kept for historical context — verify against current
> code before acting on findings. Remove this banner manually after a refresh
> or move the doc to `_archive/audits/2026-05-01/`.
# General Tweaker Code Review (2026-05-24)

**Version reviewed:** `0.2.48-dev` (per `MOD_VERSION` at `general_tweaker.lua:3` and `itemV2.cfg:1`)

Scope: `general_tweaker/` excluding `bundleV2/`. Files inspected:

- `general_tweaker.mod`
- `itemV2.cfg`
- `scripts/mods/general_tweaker/general_tweaker.lua` (4,231 lines)
- `scripts/mods/general_tweaker/general_tweaker_data.lua` (675 lines)
- `scripts/mods/general_tweaker/general_tweaker_localization.lua` (502 lines)
- `CHANGELOG.md`

## Mod purpose

General Tweaker is the host-side / local-side utility umbrella in the Tweaker series. Internal mod id `gt`, Workshop id 3713619122, visibility `public`. Where wt/ct/etc. target specific game systems, gt is the catch-all bag of "things I want one chat command away in any mission": third-person camera + freecam + noclip, godmode (damage + disablers + invisibility), keep-menus-in-mission, friendly fire toggle, duplicate careers, enemy-spawn block, AI takeover (hand your character to a bot), pause / time scale, ultimate cooldown caps, infinite ammo / stamina, base crit & move-speed sliders, Grail Knight quest picker, ready-up shortcut, HUD-hide modes, plus a sizeable creature-spawner port (Aussiemon's CreatureSpawner, ~2,500 → 3,500 line range) and item-spawner port. Round it out with diagnostic dumps (`/dump_glossary`, `/dump_cosmetics`, `/dump_items_by_slot`, `/dump_level`) and an in-mod regression smoke test (`/gt_regression_test`).

In short: this is the single-file kitchen sink. It is intentionally monolithic — every feature can disable itself via its own setting/toggle and most reach into vanilla state via narrow hooks rather than touching the world model. The bulk of new lines since the last review (2026-05-01, when it sat at ~408 lines) come from porting Janoti's "Hacks" feature set and Aussiemon's CreatureSpawner. The mod is now `public` (was `private` at last review).

## Architecture overview

### File structure (VMB layout)

```
general_tweaker/
├── general_tweaker.mod                # VMF entry, registers as "gt"
├── itemV2.cfg                         # Workshop title/desc (title carries MOD_VERSION suffix)
├── bundleV2/                          # Build output
├── resource_packages/general_tweaker/general_tweaker.package
└── scripts/mods/general_tweaker/
    ├── general_tweaker.lua            # All logic (4231 lines)
    ├── general_tweaker_data.lua       # VMF widget tree (675 lines)
    └── general_tweaker_localization.lua # en strings (502 lines)
```

No per-feature subsystem files. Everything is one mega-file partitioned by `-- =====` banner comments. The repo CLAUDE.md does suggest splitting into `_<feature>.lua` modules, and Issue #2 explicitly flags this file (3839 lines at the time of issue creation, 4231 now) as over the 2500-line hard limit.

### Main systems (banner-delimited sections in `general_tweaker.lua`)

| Lines (approx) | Section |
|---|---|
| 1–82 | Forward declarations + MOD_VERSION + load echo + regression-test scaffold |
| 84–251 | Third-person camera (snapshot/restore + over_shoulder/zoom node mutation) |
| 253–334 | Free camera (FreeFlightManager entry/exit + locomotion freeze) |
| 336–501 | Noclip (script_driven_no_mover state + WASD/Space/Ctrl velocity injection) |
| 503–599 | Keep menus in missions (InventorySettings + IngameUI hotkeys + ESC menu layout patch) |
| 600–698 | Global callbacks: `on_game_state_changed`, `on_setting_changed`, `on_disabled` |
| 700–878 | Dump commands (glossary, cosmetics, unstuck) |
| 880–995 | Godmode (invisibility + add_damage_network + add_damage_network_player + disabler-state block + fall damage block) |
| 996–1086 | Disable / clear enemy spawns (ConflictDirector hooks + script_data ai_* flags + destroy_all_units) |
| 1088–1148 | Open inventory in mission (direct `hero_view_force` transition) |
| 1150–1164 | Friendly fire toggle (hooks `allow_friendly_fire_ranged`/`_melee`) |
| 1166–1309 | Level control (gt_win / gt_fail / gt_restart / gt_kill_bots / gt_die / gt_fix_sound / gt_bot_toggle) |
| 1311–1332 | Duplicate careers (3 ProfileSynchronizer hooks) |
| 1334–1364 | `/dump_items_by_slot` |
| 1366–1624 | AI takeover (host+client human↔bot hot-swap via VMF RPC + deferred host self-toggle) |
| 1626–1703 | Pause / time-scale (debug_manager:set_time_scale wraps) |
| 1705–1779 | Ult controls (gt_ult_reset + per-frame cooldown clamps for player & bots) |
| 1781–1971 | Buffs / stat tweaks (infinite ammo, infinite stamina, giga power, base crit, move speed) |
| 1973–1990 | Layered `mod.update` (chain #1: tp timer → post-spawn reapply → noclip-state → infinite-ammo → AI-host-pending) |
| 1992–2089 | Player-state toggles (inn_dmg, cloak, unkillable) + engine-error nil guards (`unregister_fog_volume`, `Unit.get_data`) |
| 2091–2232 | Skip cutscenes (auto-skip + deferred tick) + intro monologue disable |
| 2234–2290 | More corpses (RagdollSettings min/max) |
| 2292–2347 | Grail Knight quest picker (hook `_generate_quest_pool`) |
| 2349–2392 | Ready Up Now (skip Bridge of Shadows countdown + auto-ready on vote pass) |
| 2394–2528 | Hide UI (4 modes: off/partial/complete/camera) + layered update chain #N for mode enforcement |
| 2529–3491 | Creature Spawner (port of Aussiemon's CreatureSpawner — units list, hooks, grudge marks, save slots, ~25 defensive crash hooks) |
| 3492–3637 | Item Spawner (port of Vermintide-Mods/ItemSpawner — pickup cycle + spawn via vanilla RPC) |
| 3639–4174 | `/dump_level` (single command, 10 sections — identity, worlds/units, pickups, deus units, interactables, breed roster, terror events, UI surfaces, HUD) |
| 4176–4230 | `_rt_register` calls feeding `/gt_regression_test` |

### Hook points (`mod:hook` / `mod:hook_safe` targets)

| Target | Section | Style |
|---|---|---|
| `PlayerUnitFirstPerson.set_first_person_mode` | TP | string |
| `PlayerUnitFirstPerson.extensions_ready` | TP + godmode/noclip reapply | string |
| `FreeFlightManager._exit_free_flight` | Freecam | `hook_safe`, string |
| `PlayerUnitLocomotionExtension.update_script_driven_no_mover_movement` | Noclip | string |
| `IngameUI.handle_menu_hotkeys` | Keep-menus-in-mission | string |
| `GenericStatusExtension.update_falling` | Godmode (fall damage) | string |
| `DamageUtils.add_damage_network` / `.add_damage_network_player` | Godmode | string |
| `GenericStateMachine.change_state` | Godmode (disabler states) | string |
| `ConflictDirector.spawn_queued_unit` / `.spawn_unit_immediate` / `.update` | Spawn block + Creature Spawner | string |
| `DamageUtils.allow_friendly_fire_ranged` / `_melee` | FF | string |
| 3× `ProfileSynchronizer` hooks | Duplicate careers | string |
| `CareerExtension.update` | Ult caps (player + bot) | `hook_safe`, table |
| `ProfileRequester.request_profile`, `GameModeInn._cb_start_menu_closed` | Crit-default sync on career switch | `hook_safe`, table |
| `GenericStatusExtension.add_fatigue_points` | Infinite stamina | table |
| `VolumetricsFlowCallbacks.unregister_fog_volume`, `Unit.get_data` | Engine-error nil guards | table |
| `CutsceneSystem.flow_cb_cutscene_effect`, `flow_cb_activate_cutscene_logic`, `skip_pressed` | Skip cutscenes | table-guarded `if CutsceneSystem then` |
| `ShowCursorStack.pop` | Cutscene-skip cursor underflow guard | table |
| `PassiveAbilityQuestingKnight._generate_quest_pool` | GK quests | table-guarded |
| `VoteManager.rpc_client_complete_vote` | Auto-ready on vote pass | `hook_safe`, table-guarded |
| `GameModeBase.game_mode_hud_disabled` | Hide UI | string |
| Creature Spawner: `StateIngame.update`, `AISystem.update_brains`, `AIGroupSystem.update`, `AiBreedSnippets.reward_boss_kill_loot`, `AiUtils.update_aggro`, `ProjectileEtherealSkullLocomotionExtension.init`, `BTEnterHooks.warlord_defensive_on_enter`, 4× `BTSpawnAllies`, 2× `Breeds.chaos_exalted_sorcerer_drachenfels`, `BTConditions.transitioned_one_third_health`, 3× `BTLootRatFleeAction`, `NavigationGroupManager.a_star_cached_between_positions`, `LocomotionUtils.pos_on_mesh`, `GwNavQueries.inside_position_from_outside_position`, `Unit.create_actor`, `BTSkulkAroundAction.get_new_skulk_goal`, `BuffSystem.add_buff`, `World.spawn_unit`, `EnemyPackageLoader.request_breed` | Creature Spawner (all `if Class then` guarded) | mostly table |

That is ~50 distinct hook registrations. The Creature Spawner port supplies the bulk of those.

### Update loop pattern

`mod.update` is rebuilt FIVE times via the layered `local _orig = mod.update; mod.update = function(dt) _orig(dt); ... end` pattern (lines 231, 466, 1977, 2181, 2515). Order:

1. TP reapply timer (line 231 initial def)
2. Post-spawn godmode/noclip reapply (chained at 466)
3. Infinite ammo 1Hz refresh + AI host-pending consumer (chained at 1977)
4. Cutscene auto-skip deferred-tick (chained at 2181)
5. Hide-UI per-frame component force-hide + camera-mode visibility (chained at 2515)

This works but is fragile to reorder. Any new feature wanting an update tick must follow the same idiom or one will silently never fire.

## Risk hotspots

1. **`_pause_active` forward-reference bug (NEW finding, latent).** `on_game_state_changed` at line 632 writes `_pause_active = false`, but the `local _pause_active = false` declaration is at line 1644. Because Lua resolves free-name references at the closure's compile time (at chunk load), and `on_game_state_changed` is compiled before line 1644 executes, the assignment at line 632 binds to a GLOBAL `_pause_active`, not the file-local. The pause/time-scale code at lines 1656/1668 reads the file-local. So: when the host enters a new mission while paused, the engine wipes the time scale (vanilla behavior), but `_pause_active` in the local scope is never cleared — the next `/gt_pause` press will think the game is paused (it isn't) and apply the NORMAL time scale, leaving the user thinking the toggle is one off. Fix: add `local _pause_active` to the forward-decl block near the top of the file (line 17–48 area), exactly like `_apply_godmode` / `_ai_handle_toggle_change` / `_apply_script_data_no_enemies` are forward-declared.

2. **Layered `mod.update` chain is order-sensitive and undocumented.** Five separate `mod.update = function(dt) _orig(dt); ... end` rewraps at lines 231 / 466 / 1977 / 2181 / 2515. Each new feature has to follow this pattern or it silently never ticks. There is no central registry of subscribers, no per-section "this is tick consumer #N" inline header, and no regression check that all five are still wired. If a future refactor consolidates feature blocks, an editor can easily delete the wrapping chain for a section and only notice when the feature stops working under specific conditions (e.g. infinite ammo not refreshing the buff on bots).

3. **Cross-feature state mutations on `script_data` and engine settings have inconsistent restore-on-disable behavior.** `on_disabled` (line 696) only restores camera offsets. It does NOT restore:
   - `script_data.disable_breed_freeze_opt` / `skippable_cutscenes` / `disable_level_intro_dialogue` / `player_unkillable` / all 9 `ai_*_disabled` flags
   - `RagdollSettings.{min,max}_num_ragdolls`
   - `BuffTemplates.power_level_unbalance.buffs[1].multiplier`
   - `CareerSettings[name].attributes.base_critical_strike_chance`
   - `PlayerUnitMovementSettings.move_speed` (+ closed-upvalue per-unit settings)
   - `InventorySettings.inventory_loadout_access_supported_game_modes`
   - `DamageUtils.is_in_inn`
   - `GameSettingsDevelopment.disable_free_flight`
   - The injected ESC-menu inventory entry in `menu_layouts.in_game.{alone,host,client}`
   
   The mod has `is_togglable = true`, so a user disabling it mid-session leaves persistent global mutations behind until the next game restart. Most are low-blast-radius, but the giga-power 1000x multiplier and the move-speed override visibly outlive the toggle. Either widen `on_disabled` to undo every mutation, or document explicitly that disable does not unwind runtime state.

4. **Public visibility + giga-power / infinite-ammo / disabler-immunity at host level.** The mod went from `private` to `public` (per `itemV2.cfg:6`). Several toggles (giga power 1000x talent multiplier, infinite ammo for ALL players when host applies it, host-side godmode invincibility, host-side inn-damage flip) are now reachable by anyone who subscribes. Not a bug per se, but worth noting: in public/random lobbies, the host's settings affect every connected client. The infinite-ammo apply loop iterates `human_and_bot_players()` and force-applies the `twitch_no_overcharge_no_ammo_reloads` buff to every player on host — clients have no opt-out except leaving the lobby.

5. **`debug.getupvalue` on `PlayerUnitMovementSettings.unregister_unit` (line 1965).** This is the closed-upvalue trick to reach the per-unit settings table. It works as long as Fatshark doesn't reorder the upvalues. There is no fallback if `debug.getupvalue` returns nothing — the slider would silently only apply to newly-spawned units. Low risk (the function has been stable for years) but undocumented dependency on internal codegen ordering.

6. **AI takeover host self-toggle teardown.** `_ai_swap_human_to_bot` for the host destroys the local Player, tears down `assign_unit_ownership`, and recreates via `add_player`. There is no test coverage for this round-trip surviving every game state (mid-revive, mid-throw-grenade, mid-vortex, mid-cutscene). The deferred-by-one-tick design is a partial guard (lets the current frame finish reading input before destroying the Player owning it) but unit testing here is a manual matter.

7. **`InventorySettings.inventory_loadout_access_supported_game_modes` is force-flipped on EVERY `/gt_inv` call (lines 1131–1138), even if `mission_inventory_enabled` is off.** The comment claims "idempotent" but this is a permanent global mutation: once you run `/gt_inv` once in a session, those three game modes stay enabled for the rest of the session even after toggling the VMF widget off. Subsequent calls to `_patch_inventory_access` with the setting off will restore the nil values, but only via `on_setting_changed` or `on_game_state_changed`. If a user just toggles the widget off without crossing a state change, the force-flip remains.

8. **Chaos Wastes crash guard in `/gt_inv` (line 1122–1126).** This is a documented avoidance of crash GUID `fa1ec6f8-7385-4221-869b-ed4f2893c97c`. The check only covers `mechanism == "deus"`. It does NOT block the VMF widget toggle from running through the same code path — so a user with `mission_inventory_enabled = true` in CW will see the toggle apply (setting modes.deus = true), then when they try the inventory hotkey it'll fire `/gt_inv` which bails — but the inventory entry on the ESC menu (added at line 561) is still present, and if they click it via the menu path, the same crash GUID applies. Either remove the ESC-menu entry in CW or short-circuit the menu transition as well.

9. **`/dump_glossary` and other dump commands iterate `ItemMasterList` / `SPProfiles` without DLC gating.** Not a runtime crash risk (these are diagnostic dumps to the console log), but the dumped output mixes DLC-owned and unowned content. Anyone consuming the dump for catalog purposes would need to dedupe by DLC ownership separately. Documentation-only call-out.

10. **Defensive logging is uneven.** Hooks like the Drachenfels boss replacement (`run_on_spawn`, lines 3215–3312, ~100 lines verbatim from Lupo's upstream) have no defensive logging — a single nil deref in there is a silent crash with no context. The Creature Spawner cluster as a whole leans hard on `if Class then mod:hook(...)` guards (good) but the hook bodies themselves are mostly bare. The mod's own pattern (used in `/dump_level`) of `safe(name, fn)` + `pcall` would harden the Drachenfels block too but is not applied there.

## QA status

- **In-mod regression smoke test (`/gt_regression_test`):** three checks registered (lines 4186–4229). Two test the cutscene-skip wiring (presence of `_pending_auto_skip_system` marker, `mod:get("gt_skip_cutscenes_enabled")` not erroring); one tests the v0.2.47 `rawget` conversion on `NetworkLookup.pickup_names`. Coverage is narrow — only the issues the user explicitly burned on in the last few patches have checks. No checks for: tp camera node mutation, godmode disabler block, AI takeover round-trip, layered mod.update ordering, the `_pause_active` forward-reference described above, or the on_disabled restore behavior.

- **Manual regression checklist** lives in `REGRESSION_CHECKLIST.md` (sibling file). Worth keeping in sync as new features land — it has not been updated in this review.

- **Logging conventions:** the mod uses `mod:info(...)` and `mod:echo(...)` consistently. AI-takeover paths and infinite-ammo/noclip flows have decent breadcrumbs. Creature Spawner port and Drachenfels boss replacement are sparse on internal logging.

- **No lint-known regressions.** The `tools/lint/regression-lint.ps1 strict-table-lookup` pass is clean per CHANGELOG v0.2.47.

## Open follow-ups

- **Issue #2** (`8 Lua files over 2500-line hard limit (file-size refactor batch)`, label: audit/refactor) — `general_tweaker.lua` is explicitly listed at 3839 lines (now 4231). Split candidates: `_camera.lua` (tp + freecam + noclip), `_godmode.lua`, `_ai_takeover.lua`, `_creature_spawner.lua` (largest single block, ~960 lines), `_item_spawner.lua`, `_level_dump.lua`, `_dump_commands.lua`. The forward-declaration block at the top of the file is the seam for moving any "module that on_setting_changed dispatches into" into its own file (same pattern `_gt_cs_on_setting_changed` already uses).

- **No other GitHub issue currently references general_tweaker by name.** Issues #1, #3, #4, #6, #7 are about other mods. The `_pause_active` forward-ref bug above, the `on_disabled` restore gap, and the public-visibility blast radius are all unfiled — these are candidates for new issues if you want them tracked rather than living only in this review.

- **TODO comments in source:** the inline `REVIEW:` / `CLARIFY:` markers from the previous review at lines 241–245 (`/tp` command double-applies `_apply_tp` redundantly with `on_setting_changed`) and lines 802–809 (`dump_cosmetics` captures `inventory_icon` but never writes it) are still present and still accurate.

## Notable correctness wins since last review (2026-05-01)

- TP camera sliders (`tp_distance`, `tp_height`, `tp_side_offset`) are now actually wired — `_patch_camera_offset` reads them all (line 142–144).
- The `mission_inventory_enabled` half-implementation is fixed: the ESC-menu inventory entry (line 561) is now injected in addition to the `InventorySettings` patch, and a separate `/gt_inv` command bypasses the hotkey gates entirely via `Managers.ui:handle_transition("hero_view_force", ...)`.
- Godmode now covers both `add_damage_network` AND `add_damage_network_player`, plus disabler-state transitions (`GenericStateMachine.change_state` with 6-state blocklist), plus fall damage at source (`update_falling.ignore_next_fall_damage = true`). Multi-path coverage now matches the doc.
- The TP tooltip's wrong chat prefix (`'t tp'` → `'gt tp'`) is corrected in the current localization.
- `_apply_godmode` and related helpers use the forward-declaration pattern (file-top `local _apply_godmode` + later assignment) deliberately and the rationale is comment-documented at lines 18–22 / 903–905. Good defensive idiom.
- `on_game_state_changed` resets per-session flags (`_tp_enabled`, `_noclip_active`, `ai_takeover_enabled`, `_ai_saved_state`) on level transitions — addresses the "stale state leaks across missions" risk that was implicit in the v0.1 review.

## Notes for future agents

- The mod is now `public` visibility — Workshop ID 3713619122. Do not change `visibility` without explicit user instruction (see `feedback_workshop_metadata_user_dictates.md`).
- `gt.mod` is renamed to `general_tweaker.mod` but still registers via `new_mod("gt", ...)`; settings persist across the rename.
- The `_pause_active` forward-reference bug is the most urgent finding — one-line fix (add to the forward-decl block) but currently latent.
- When adding a new feature with a tick consumer, follow the existing layered `mod.update` wrap idiom precisely. Re-check by chasing `mod.update = function` greps after the edit.
- Do not remove the `if Class then` guards in front of Creature Spawner hooks — that pattern protects against early-boot ordering (gt loads before some BT/AI tables exist).
- The five `pcall` rings inside `_apply_tp` / `_apply_freecam` / `_apply_godmode` / `_apply_freecam_freeze_player` and the deep `pcall(function() ... end)` wrapper in the cutscene deferred-skip block are load-bearing — keep them in any refactor.
