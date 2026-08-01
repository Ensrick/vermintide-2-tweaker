# general_tweaker_dev - engine contact surface

## Godmode Blightstorm capture boundary (#1009, 0.2.257-dev)

| Surface | Ownership and invariant |
|---|---|
| `StatusUtils.set_in_vortex_network` | Server-authored Blightstorm status/RPC seam. Godmode rejects only the entering edge for a human player when the source positively owns the enemy `VortexExtension`, returning the native false result before status, RPC, and captured-player table writes. Exit cleanup, non-Godmode behavior, and Sister of the Thorn's separately registered `SummonedVortexExtension` remain vanilla. [src: `scripts/helpers/status_utils.lua:278-297`; `scripts/unit_extensions/ai_supplementary/vortex_extension.lua:615-631`; `scripts/settings/dlcs/woods/woods_common_settings.lua:174-184`] |

## Host-side melee latency compensation (#1034, 0.2.256-dev)

| Surface | Ownership and invariant |
|---|---|
| `GameNetworkManager:ping_by_peer` | Host-only RTT source. The mod samples it through `Managers.state.network`, applies a per-peer EMA, and caps the grace window at 350 ms. Clients send no custom latency value. [src: `scripts/managers/network/game_network_manager.lua:82-85,176-192`] |
| `BTMeleeOverlapAttackAction.hit_player` | Common ordinary-melee impact owner. GT defers the whole player impact so damage, block result, push, and hit callbacks resolve together; the original method remains the authority at the deadline. [src: `scripts/entity_system/systems/behaviour/nodes/bt_melee_overlap_attack_action.lua:638-676`] |
| `AiUtils.damage_target` | Shared final AI-damage helper and fallback for legacy/direct blockable AI melee paths not owned by the overlap action. Host players, bots, already-blocked damage, disabled targets, and unblockable/non-melee paths delegate immediately. The shared queue is globally bounded to 256 and overflow fails open. [src: `scripts/unit_extensions/human/ai_player_unit/ai_utils.lua:258-390`] |
| `DamageUtils.check_block` | Re-run once at the compensated deadline so the host's current blocking state, facing, fatigue cost, `ai_unblockable` perk, block RPC, and attacker blocked state remain vanilla-owned. [src: `scripts/helpers/damage_utils.lua:2697-2765`] |
| `StatusSystem.rpc_set_blocking` / `.rpc_status_change_bool` | Post-observe the vanilla host receivers after authoritative block/dodge state updates. A valid rising edge resolves matching queued hits immediately, so a short input is not lost before the deadline. No custom defense RPC or client claim is accepted. [src: `scripts/entity_system/systems/status/status_system.lua:278-302,430-445`; `scripts/unit_extensions/default_player_unit/states/player_character_state_dodging.lua:285-297`] |
| `AiUtils.stagger` | Wrapped per `(enemy, attacker)` epoch. The epoch advances only when vanilla actually changes the enemy's stagger state; rejected stagger requests do not count. A stagger caused by the targeted remote player during that hit's grace window cancels only that queued hit, while unrelated ally/environment staggers do not satisfy the condition. [src: `scripts/unit_extensions/human/ai_player_unit/ai_utils.lua:1108-1161`] |

## Live player stat HUD (#797, 0.2.255-dev)

| Surface | Ownership and invariant |
|---|---|
| `BuffExtension._buffs`, `_stat_buffs` | Read only. Active buff parent/child identity and `stat_buff_index` are joined to the exact retained stage key. No add/remove/apply call is made. |
| `BuffExtension.apply_buffs_to_value` equation | Reproduced only for finite deterministic stages: ordered nonzero stages first, then retained root multiplier/bonus. Proc/function/table stages fail closed as `UNSUPPORTED`, avoiding PRD/proc side effects. |
| `HeroStatisticsTemplate`, `ActionUtils`, `DamageUtils`, status/career consumers | Health/stamina getters are authoritative and any remainder outside retained stat stages is disclosed as an unattributed reconciling delta. `GenericStatusExtension.update` derives stamina regeneration as `FATIGUE_POINTS_DEGEN_AMOUNT / authoritative max_fatigue_points * MAX_FATIGUE` (`1.5 / max * 100`) before applying `fatigue_regen`; a missing live max fails closed. `CareerExtension.start_activated_ability_cooldown` consumes current cooldown, cost, refund, and optional modified cost before applying `activated_cooldown`, so the HUD exposes that stat only as an activation factor rather than multiplying the maximum cooldown. Movement final fails closed because `PlayerCharacterStateWalking` additionally consumes stance, `StatusExtension.current_move_speed_multiplier`, `current_movement_speed_scale`, and `player_speed_scale`; `PlayerUnitMovementSettings.move_speed` alone is never called effective. Action time scale is split into exact default-value chain/action (`is_animation=false`) and animation (`is_animation=true`) consumers, including the native chain-window OR animation-window charge-time truth table. The action-settings critical path is shown separately; its effective final fails closed because call-site runtime overrides are unobservable. Power/damage/cleave/block/ammo/reload entries are labeled exact factors; target/profile-dependent effective finals fail closed as `UNSUPPORTED`. |
| `WeaponUnitExtension.current_action_settings.lookup_data` | Read-only action/sub-action/item-template identity plus active action damage profile. It is part of the lifecycle cache identity. |
| Existing singleton `IngameHud.update` owner | Draw dispatch only; no additional HUD hook. Bottom anchors avoid the existing top-left bot HUD and top-right Godmode indicator. |
| Cache/page bounds | 4 Hz samples, 256 stat types, 1,024 stages, 1,024 active sources, and 18 wrapped expanded body lines per navigable page. Enumeration is capped before key sorting/allocation; truncation is visible and absent rows fail closed. Missing units and native health/status dead states clear retained panel state even while the engine unit remains alive. Provenance rebuilds only when unit/equipment/action/buff identity changes; metrics expose rebuild/sample/format/allocation counts. |

What vanilla VT2/Stingray does at every seam `gt_dev` touches, and why the mod is
there. This is the per-mod companion to the subsystem set in `docs/engine/`
(read `docs/engine/README.md` for house style). It does **not** re-explain a
subsystem the engine docs own - it names the seam, cites the vanilla behavior,
and links out. Decompile paths are relative to
`C:\Users\danjo\source\repos\Vermintide-2-Source-Code`; `gt` line numbers are in
the named `general_tweaker_dev/scripts/mods/general_tweaker_dev/*.lua` module.
`§N` = a `docs/BUG_CLASSES.md` class; `#N` / "issue N" = a GitHub issue.
Grep-verified 2026-07-12 against the decompile and the mod source (the bot,
world-lifecycle, lobby and godmode citations were opened and confirmed line by
line; the remaining `[src:]` citations are carried from the cited `gt_dev`
module comments, which cite the decompile in turn).

**Dev/stable relationship.** This documents `general_tweaker_dev` (`gt_dev`,
MOD_VERSION `0.2.257-dev`, friends-only Workshop 3733367409), the ACTIVE working
stream. `general_tweaker/` (`gt`, public Workshop 3713619122) is its read-only
public twin; per repo `CLAUDE.md` all in-flight work happens in the dev dir and
promotion is a separate user-triggered action, so this doc cites only `gt_dev`
line numbers. The dev-stream `IS_DEV_STREAM` gate (`mod == get_mod("gt".."_dev")`)
is engineered to survive the dev->stable promotion `sed`, so every always-on
diagnostic disables itself in the stable clone.

`gt` is a **broad utility bundle**, not a deep render mod: ~30 `_gt_*` feature
modules covering bot-AI gap fixes, a host-executed creature spawner (clients
request over the mod's `gt_cs_request` RPC, #693), in-world debug
draw, host-side lobby moderation, godmode/noclip/cheat toggles, and combat/QoL
tweaks. Unlike `cwv`/`wt`/`cosmetics` it barely touches the item/mesh/wire path;
its engine contact clusters into four surfaces - the bot behaviour tree, the
world/state lifecycle, the host lobby/session seams, and the player
damage/movement/camera path - each with its own subsystem note below.

## Hook table

~117 registration sites across ~32 modules, grouped below into rows-of-concern.
`[hook]` = full wrapper (`mod:hook`, can rewrite args/returns); `[safe]` =
`mod:hook_safe` (post-callback, no override, chains across mods); `[tbl]` =
table-form hook against a plain-table / data-table target (nil-guarded); `[rpc]`
= `mod:network_register` (a VMF network event, not a class hook). Because gt has
many single-owner per-frame features, several concerns are **consolidated** into
one hook per `(Class, method)` and dispatched internally - VMF silently drops a
second hook on the same pair (repo `CLAUDE.md` NON-NEGOTIABLE 8), so the
consolidation is load-bearing, flagged in the trap column.

### Surface 1a - Bot aid / revive / teleport priority (owner docs: `docs/engine/02`, `/07`; `_gt_bot_fixes.lua`, `_gt_improved_bot_combat.lua`)

The freshly load-bearing cluster: issues 139 / 448 / 492 all live here. Every
bot-AI feature is host-side (bot brains run server-authoritative) and defaults
OFF except the two ungated crash fixes.

| Class.method (kind) | Vanilla behavior at the seam | Why gt hooks it | Trap / invariant |
|---|---|---|---|
| `BTConditions.should_teleport` [hook] `_gt_bot_fixes.lua:1815` | The teleport-to-follow-target decision; returns true only at >=40 m (`FOLLOW_TELEPORT_DISTANCE_SQ = 1600`), and returns false early while an ally needs aid or a priority enemy is targeted [src: `scripts/entity_system/systems/behaviour/nodes/bot/bt_bot_conditions.lua:1208-1241`, aid gate `:1226-1228`, distance gate `:1241`] | Tighter leash (FIX 7) + backward-segment override (issue 142) + a BLANKET aid veto (#139) so a split-team down never yanks the bot off the downed ally; also the Bot Teleport Lab observe/veto dispatch | CAPTURE the vanilla decision, do NOT early-return it, so the lab veto layer can override even a vanilla-40 m TRUE; the #139 veto is the FINAL word, #492 bailout steps it aside. v0.2.243 records bot + aid + follow identity at the veto for bounded execution correlation; distinct `(Class,method)` from the `run` hook below so no dup collision |
| `BTConditions.cant_reach_ally` [hook] `_gt_bot_fixes.lua` | Drives the separate `teleport_no_path` node after sustained failed paths; unlike `should_teleport`, it has no distance floor [src: `scripts/entity_system/systems/behaviour/nodes/bot/bt_bot_conditions.lua:1167-1203`; tree node `scripts/entity_system/systems/behaviour/bt_bot.lua:431-435`] | Backward no-return bypass (#515), exact no-path reason attribution, and a five-second retry bound only for repeated no-path teleports below the configured leash (#385) | Preserve the first unstick and vanilla forward verdict; never apply the retry bound to outside-leash or ordinary distance-trigger branches |
| `BTBotTeleportToAllyAction.run` [hook] `_gt_bot_fixes.lua:2023` | The teleport action itself: flips `has_teleported` and snaps the bot to its follow target | FIX 7 confirmation + #139 decision probe + the lab's pre/post position boxing and tether-yank block | CONVERTED from `hook_safe` to a full `mod:hook`. Pre/post uses immediate `Unit.world_position`, not `POSITION_LOOKUP` (which stays stale through the wrapped action); aid-adjacent actions emit one `[gt:139:chain] TELEPORT` row with the recent veto, final selector, and #492 bailout identity |
| `PlayerBotBase._select_ally_by_utility` [hook] `_gt_bot_fixes.lua:797` | The bot's ally-aid picker; vanilla has a dormant `in_need_of_heal` selection at `player_bot_base.lua:843-1008`, while `BTConditions.can_heal_player` owns the final proximity/threat/interaction gate [src: `bt_bot_conditions.lua:773-807`] | Rescue awaiting-respawn allies (FIX 3), bound that pick by #300's range policy, force revive/rescue priority (FIX 3b), apply #492's suppress-pick, and #523-select an eligible hurt human for the existing `heal_other` node | Calls the original FIRST. #523 only returns native need type `in_need_of_heal`; `bt_bot.lua:87-93` retains `BTBotInteractAction`, and gt never calls `DamageUtils.heal_network`. Wounded/non-wounded and Zealot eligibility lives in pure `_gt_bot_heal_policy.lua`; navigation, channel, consumption, healing, and networking remain vanilla. Awaiting rescue reads `side:player_units()` [src: `scripts/managers/side.lua:222`] rather than filtered `PLAYER_AND_BOT_UNITS` [src: `side_manager.lua:338-339`] |
| `Utility.get_action_utility` [hook] `_gt_bot_fixes.lua` | Multiplies action considerations; every non-condition input is subtracted/divided without a nil/type guard [src: `scripts/entity_system/systems/behaviour/utility/utility.lua:22-51`]. `AISystem` seeds `ally_distance=math.huge` [src: `scripts/entity_system/systems/ai/ai_system.lua:543-552`] | Ungated crash guard: restore only the exact player-follow distance sentinel and reject any other malformed numeric action before arithmetic | Owned by bot fixes, not Creature Spawner. Valid actions delegate unchanged; condition nil retains vanilla false semantics; unknown numeric inputs return utility zero without a generic +/-infinity write. `_select_ally_by_utility` also preserves `math.huge` on every GT no-target branch |
| `BTConditions.can_activate_ability` [hook] `_gt_bot_fixes.lua:750` | Career-ability gate; the `is_using_ability` short-circuit keeps the BT parked on the ability node so the higher-priority revive node is never re-entered [src: `bt_bot_conditions.lua:607-629`, revive selector at `bt_bot.lua:14-32`] | FIX 2: yield the ability node to revive when an ally needs aid (an Ironbreaker mid-ult would otherwise never revive) | Only yields for knocked_down / ledge / hook need types; the ult is a timed buff that keeps ticking and the ability is on cooldown, so it will not re-pop |
| `BuffFunctionTemplates.functions.deus_knockdown_damage_immunity_aura_func` [hook,tbl] `_gt_bot_fixes.lua:2233` | The CW knockdown-immunity boon aura: the carrier grants an invulnerable no-duration buff to downed allies, gated on `is_ready_for_assisted_respawn()` but NEVER on the carrier's own downed state [src: `scripts/settings/dlcs/morris/morris_buff_settings.lua:872-921`] | FIX 11 (issue 448, SOFT-LOCK): two downed boon-carrying bots make each other permanently invulnerable and the run soft-locks; skip the grant tick and strip self-granted buffs while a bot owner is knocked down | The buff extension resolves `update_func` DYNAMICALLY each tick [src: `scripts/unit_extensions/default_player_unit/buffs/buff_extension.lua:794`] so the table-form hook intercepts every tick; nil-guarded on `BuffFunctionTemplates.functions[key]`; strip gated on `buff.attacker_unit == owner` so a STANDING carrier's aura is untouched; only other `BuffFunctionTemplates` hook is `apply_huntsman_activated_ability` (`_gt_solo_qol.lua:497`) |
| `GameModeHelper.side_is_dead` [hook] `_gt_bot_fixes.lua:1594` | Wipe check; `GameModeAdventure` calls `side_is_dead("heroes", ignore_bots=true)` so the run is lost when all humans are down even if a bot lives [src: `scripts/game_mode/game_mode_adventure.lua:92`] | FIX 8: force `ignore_bots=false` for "heroes" so a living bot counts and the wipe is averted | Runs server-side (`GameModeManager.server_update`), host-only by nature |
| `GenericStatusExtension.set_block_broken` [hook] `_gt_bot_fixes.lua:2149` | Early-returns when the block-broken value is unchanged [src: `scripts/unit_extensions/generic/generic_status_extension.lua:994-996`] | Replicant port: announce a bot's guard break to chat (rising-edge only) | Full `mod:hook` so it reads `self.block_broken` BEFORE vanilla flips it; different method from `update_falling`, no dup |
| `BTBotMeleeAction.enter` [hook] `_gt_bot_fixes.lua:175` / `BTBotMeleeAction.run` [hook] `_gt_improved_bot_combat.lua:209` | Enter/tick the bot melee action; both deref `wielded_item_template` unguarded (`enter` at `:83`, `run` via `_update_melee`) [src: `scripts/entity_system/systems/behaviour/nodes/bot/bt_bot_melee_action.lua:70-92`] | FIX 0 (CRASH, UNGATED, two halves): a nil `slot_data` mid weapon-swap fatals the deref; `enter` replicates the always-safe setup and leaves `wielded_item_template=nil` without calling `func`, `run` bails `"done","evaluate"` when the template is nil | Both UNGATED - the crash is toggle-independent; `run` is the ONLY gt hook on that pair (the ping-attacking-elite feature is merged into the same body) |

### Surface 1b - Bot follow / pickup distribution + combat (owner: `docs/engine/07`; `_gt_bot_fixes.lua`, `_gt_improved_bot_combat.lua`)

Issue #298 control contract: `gt_improved_bot_combat` remains the host-side
master. Six default-on child gates independently own attack choice, elite ping,
special chase, gunner cover, boss focus, and career-ability timing. Chase,
gunner, and boss distances are configured in meters and squared exactly once at
the existing `Vector3.distance_squared` comparison boundaries. The nil-weapon
melee-action crash guard remains ungated.

| Class.method (kind) | Vanilla behavior | Why gt hooks it | Trap / invariant |
|---|---|---|---|
| `AIBotGroupSystem._assign_destination_points` [safe] `_gt_bot_fixes.lua:2439` | Points EVERY bot's `follow_unit` at ONE selected human per side; the candidate build drops disabled players from the follow set unless EVERY player is down [src: `scripts/entity_system/systems/ai/ai_bot_group_system.lua:695-719`, per-bot write `:1119-1120`] | FIX 9: split bots round-robin among humans / follow-host mode + issue 383 fan-point recompute; also the lab's D2 follow-tracker dispatch | `hook_safe` (post) so it composes; the lab CANNOT re-hook this pair (VMF drop), so D2 dispatches at each FINAL exit after temporary orders, configured follow mode, and dormant lab override. It stamps the exact selector identity later consumed by the action and logs only aid-adjacent changes |
| `SocialWheelUI._open_menu` [hook] / `PingSystem._handle_chat` [safe] `_gt_bot_command_wheel.lua` | The social wheel chooses its category and page at open, then sends a pre-registered social event; Adventure has `world_markers=false`, so its close path sends a social message instead of the raycast position [src: `scripts/settings/game_mode_settings.lua:41-45`; `scripts/ui/social_wheel/social_wheel_ui.lua:669-824,1485-1523`; `scripts/entity_system/systems/ping/ping_system.lua:315-379`] | #359 adds a host-only second page using four existing Versus event IDs, then maps them to bounded urgent-target, follow, and hold-position orders; #600 copies the live wheel context's already-raycast position before Adventure discards it | Never mutate `NetworkLookup` or add an RPC. Temporary follow writes dispatch through the singleton `_assign_destination_points` hook above; `Wait` copies the reused context box into a fresh `Vector3Box`, uses vanilla `AIBotGroupExtension.set_hold_position` [src: `scripts/entity_system/systems/ai/ai_bot_group_system.lua:32-53`], and clears only GT's matching token |
| `AIBotGroupSystem._update_mule_pickups` [safe] `_gt_bot_pickups.lua` / `_update_health_pickups` [safe] `_gt_bot_pickups.lua` | Assign carryable pickups to bots; mule only when `num_players==0`, health reserves one item per empty-slot human before leftovers go to bots [src: `ai_bot_group_system.lua:1891-2048` / `:2050-2361`] | FIX 10 greedy pickup: re-run assignment minus the `num_players==0` gate (mule) / hand leftovers to empty-handed bots inside the follow-range gate (health); #364 reserves exact `bardin_survival_ale`, whose `slot_level_event` pickup auto-wields and invokes its use action [src: `scripts/settings/equipment/pickups.lua:741-758`]; #365 narrowly permits one live ale target when every active teammate has three `ale_defence` + `ale_attack_speed` stacks with strictly over half duration [src: `buff_templates.lua:5323-5345`; `buff_extension.lua:520-533,603-614,1253-1260`] | One consolidated mule hook; rebuilds a local `claimed` set because vanilla's `ASSIGNED_MULE_PICKUPS_TEMP` file-local is unreadable [src: `:1889`]. #365's census is roster-bounded, 0.5 s cached, fail-closed, and exempts only approved units from #364's reservation; leaves `force_use_health_pickup` untouched [src: `:2355-2358`] - these paths change who CARRIES, while vanilla owns consumption/healing |
| `PlayerBotBase._find_pickup_position_on_navmesh` / `BTConditions.can_loot` [hook]; `InteractionDefinitions.pickup_object.server.stop` / `.chest.server.stop` [safe] `_gt_bot_pickups.lua` | Humans call `_check_if_interactable_in_chest` after their raycast, but bots given an exclusive interaction bypass that human gate [src: `generic_unit_interactor_extension.lua:96-218,335-360`]; bot pickup approach, loot eligibility, and successful consumption are separate seams [src: `player_bot_base.lua:1702-1760`; `bt_bot_conditions.lua:877-891`; `interactions.lua:876-925`] | #347 bounded diagnostic classifies available pickups through vanilla's exact chest raycast and observes nav, loot, and stop results | Observation only, host-command armed, 32 classifications / 16 deduplicated records; ordinary chest contents are controlled by authored compiled level flow unavailable in the Lua source, so never infer that directly firing chest flow or forcing an unassigned pickup is safe |
| `AIBotGroupSystem._update_urgent_targets` [hook] `_gt_improved_bot_combat.lua:311` | Treats monsters as top-priority urgent, tunnelling bots onto them | Only add a boss as urgent when close (`15*15`), not invincible/defensive, and the bot is not mid-crowd (unless the boss targets the bot) | Replicates vanilla non-boss scoring via `_calculate_opportunity_utility`; one of only three `AIBotGroupSystem` hooks in the repo |
| `AiUtils.calculate_bot_threat_time` [hook] `_gt_bot_fixes.lua:132` | Returns `start_time+start_delay, duration-start_delay` (a random bot reaction delay) [src: `scripts/utils/ai_utils.lua:723-739`] | Replicant port: return raw `start_time, duration` so bots dodge telegraphed attacks immediately | Real snapshot/restore of the vanilla table on toggle (the source mod's `on_disabled` is author-flagged broken) |
| `BTBotMeleeAction._choose_attack` [hook] / `PlayerBotBase._enemy_path_allowed` [hook] / `PlayerBotBase._in_line_of_fire` [hook] `_gt_improved_bot_combat.lua` | Bot attack selection / chase-path allow / take-cover-from-ranged test | Smarter attack choice, configurable special chase, only take cover from close in-lane shooters; #488 observes shield/Ratling state before the feature gate | Behavior remains gated on `gt_improved_bot_combat` and falls back to vanilla when off. The #488 observer is mutation-free, deduplicated, and capped at 12 state shapes; suppressing cover is not treated as proof the BT will wield or block. |
| `BTConditions.can_activate.<es_mercenary / es_huntsman / we_maidenguard / we_shade / wh_captain / bw_unchained>` [hook,tbl] `_gt_improved_bot_combat.lua:397-491` | Per-career bot ult can-activate gate | Ult timing: pop sooner as the nearby group is hurt / on a prioritized rescue / on stamina/overcharge thresholds | Table-form on `BTConditions.can_activate[key]`, guarded per-key; Ironbreaker DELIBERATELY not hooked here (gt's revive-in-ult owns it) |
| `BTBotShootAction.run` [safe] `_gt_improved_bot_combat.lua:222` / `PingTargetExtension.set_pinged` [safe] `:126` | Bot ranged tick / engine ping clear | Ping the attacking elite from the shoot node; clear gt's `_pinged_by_bot` record when the engine clears the ping | `hook_safe`; ping record only acts on `pinged==false` |

### Surface 1c - Bot roster: keep-fill + disable-solo (owner: `docs/engine/08`; `_gt_bots_keep.lua`)

| Class.method (kind) | Vanilla behavior | Why gt hooks it | Trap / invariant |
|---|---|---|---|
| `GameModeInn.server_update` / `GameModeInnDeus.server_update` [safe] `_gt_bots_keep.lua:261-262` | Inn/CW-hub tick; does NOT call `_handle_bots`, so keep slots stay empty | Bots-in-Keep FILL: drive `_bik_fill` post-call (revived v0.2.146 by porting Photo Mode's inn-bot lifecycle) | Both classes carry their own copy of the inherited method (`class()` copies at definition, `docs/engine/01`) so each is hooked; fires only once the session is running so the old slot-1 startup race (Bug 2) cannot recur |
| `GameModeInn.cleanup_game_mode_units` / `GameModeInnDeus.` [safe] `_gt_bots_keep.lua:273-274` | Called by `StateIngame.on_exit` before `check_venture_end` destroys venture stats [src: `scripts/game_state/state_ingame.lua:1911`,`:2119`] | TEARDOWN: `_remove_bot_instant` unregisters each keep bot's stat in time (fixes the "Stat id not unregistered" fassert, Bug 1) | UNCONDITIONAL (not toggle-gated) so bots are always cleaned even if the setting is flipped off mid-session |
| `PassiveAbilityNecromancerCharges._on_talents_changed` / `.extensions_ready` [safe] `_gt_bots_keep.lua` | `extensions_ready` registers events and immediately invokes `_on_talents_changed`; that method sets `_pets_forbidden_in_level = pets_forbidden_in_hub and is_in_inn_level`, and `spawn_pet` then early-returns [src: `scripts/settings/dlcs/shovel/passive_ability_necromancer_charges.lua:56-78,108-110,201-203`] | Necromancer keep skeletons: reconcile the initialized extension at both the vanilla flag-write and the completed extension lifecycle; clear the hub gate for humans, and for bots only while Bots in Keep is enabled | One engine-free idempotent policy owns all cases (#659). Each `(Class,method)` pair is hooked once; bounded phase/before/after evidence distinguishes a missed callback from an already-clear flag; mission/non-hub state remains unchanged |
| `ActionCareerBWNecromancerRaiseDeadTargeting._get_projectile_position` [hook] / `.finish` [safe] / `PassiveAbilityNecromancerCharges.spawn_pet` [safe] / `._spawn_pet_server` [hook] `_gt_necro_keep_trace.lua` | Targeting accepts a cast only when the projectile ground target resolves onto nav; `finish` enters the spawn branch only for `_valid`, `new_interupting_action`, and `spawn_summon_area`; the passive then queues a pet and the server snaps it to nav before calling `ConflictDirector.spawn_queued_unit` [src: `scripts/settings/dlcs/shovel/action_career_bw_necromancer_raise_dead_targeting.lua:68-126,128-188`; `passive_ability_necromancer_charges.lua:201-244,348-437`] | #659 next-boundary diagnostic after log #940 proved the local human lifecycle hooks run with the hub-ban field already falsey while four career-skill wields produce no conflict-queue record | Observation-only, local-human hub only, independently capped at 4/4/8/8 rows. Full wrappers call vanilla exactly once and preserve returns; no fallback target or spawn mutation is introduced until the first failing seam is measured |
| `GameModeAdventure._handle_bots` / `GameModeDeus.` / `GameModeWeave.` [hook] `_gt_bots_keep.lua:425-427` | Reads `script_data.ai_bots_disabled` at the top; clears bots and early-returns when true [src: `game_mode_adventure.lua:371`] | Disable-Bots (Solo) enforce: re-assert the flag from the live setting every tick | Never write the bare `script_data` NAME (`= script_data or {}` shadows the real `_G.script_data` in the VMF env, #194) - `rawget(_G,"script_data")` then field-mutate |
| `AdventureSpawning.force_update_spawn_positions` [hook] `_gt_bots_keep.lua:434` | Positions bot units; can fatal when no bots exist | Crash guard: `pcall(func, ...)` while Disable-Bots is on | The crash was latent pre-fix (the flag never actually suppressed bots); host-only |

### Surface 2a - Creature spawner: keep-enable + AI/nav/BT crash guards (owner: `docs/engine/07`, `/04`; `_gt_creature_spawner.lua`, all `[tbl]`)

Ported from Aussiemon's CreatureSpawner; every hook is table-form on a global
resolved after main, most wrapped in `if <Class> then`.

| Class.method (kind) | Vanilla behavior | Why gt hooks it | Trap / invariant |
|---|---|---|---|
| `ConflictDirector.update` [hook,tbl] `_gt_creature_spawner.lua:607` | Full CD tick (AI tracking, pacing, spawn queue) | Keep-spawn strip-down: run only `update_spawn_queue` + lazily build `horde_spawner`/`specials_pacing` so spawn commands work in the keep | DISTINCT from the consolidated `ConflictDirector.spawn_queued_unit` hook that STAYS in main (keyed per-method) |
| `StateIngame.update` [safe,tbl] `_gt_creature_spawner.lua:626` | Main ingame tick | Set `script_data.disable_breed_freeze_opt = in_keep` so keep-spawned units are not dropped by the breed-freeze optimizer | - |
| `AISystem.update_brains` [hook,tbl] `:634` / `AIGroupSystem.update` [hook,tbl] `:646` | Tick AI brains / ambush waves | Two-toggle AI gate (`gt_cs_mission_ai` vs `gt_cs_keep_ai`); zero `members_n`/`num_spawned_members` on init groups when mission AI is off | - |
| `World.spawn_unit` [hook,tbl] `:1052` / `Unit.create_actor` [hook,tbl] `:988` | Spawn a unit by name / create a physics actor | Missing-unit guard: fall back to `units/hub_elements/empty` when `Application.can_get("unit",name)` is false; block only `id == -1` `create_actor` in the keep (crashes the actor allocator) | `World.spawn_unit`/`Unit.create_actor` always loaded so unguarded; `Unit.create_actor` DISTINCT from `Unit.get_data` in `_gt_hacks.lua` (keyed per-method) |
| `BTLootRatFleeAction.enter/run/leave` / `NavigationGroupManager.a_star_cached_between_positions` / `LocomotionUtils.pos_on_mesh` / `GwNavQueries.inside_position_from_outside_position` / `BTSkulkAroundAction.get_new_skulk_goal` [hook,tbl] `:966-995` | Loot-rat flee, A* pathfind, navmesh snap/query, skulk goal | Keep-nav crash suite: short-circuit each in the keep (no navmesh exists there) and return the safe sentinel | The five-hook crash chain documented upstream; each returns vanilla's expected shape (`false`/`"running"`/`nil`) |
| `BuffSystem.add_buff` [hook,tbl] `:1038` / `EnemyPackageLoader.request_breed` [hook,tbl] `:1063` | Add buff (allocates a server-controlled buff id) / request a breed package | Server buff-cap detector (back off grudge-mark modifiers near `NetworkConstants.server_controlled_buff_id.max`); force `ignore_breed_limits=true` so debug spawns load packages on demand | Guarded on `NetworkConstants.server_controlled_buff_id` |
| `AiUtils.update_aggro` / `AiBreedSnippets.reward_boss_kill_loot` / `ProjectileEtherealSkullLocomotionExtension.init` / `BTEnterHooks.warlord_defensive_on_enter` / `BTSpawnAllies.*` / `Utility.get_action_utility` [hook,tbl] `:662-737,:1007` | Aggro/loot/summon/spawn-allies/utility ticks that assume mission-only blackboard state | Defensive init + POSITION_LOOKUP nil-guards so a keep-spawned or homeless unit does not fatal on a nil field | `reward_boss_kill_loot` gates its `POSITION_LOOKUP[unit].z` read in a `pcall`; `Utility.get_action_utility` instantiates missing `utility_actions[name]` data |
| `gt_cs_request` / `gt_cs_ack` [rpc] `_gt_creature_spawner.lua` | - | Client->host creature spawn/destroy requests, run host-authoritative (only the host drains the CD spawn queue, `state_ingame.lua:950-958`); host re-validates breed/numbers/grudge keys and acks the result line back to the requester (#693) | Schema-tagged `mod.GT_CS_RPC_SCHEMA`; sent to the mechanism-resolved host peer (literal `"server"` is a no-op, `docs/VMF_RECIPES.md` §3); degrades silently when the host lacks gt |

### Surface 2b - Boss spawn-anywhere + first-tick BT health nil-guards (`_gt_creature_spawner.lua`)

| Class.method (kind) | Vanilla behavior | Why gt hooks it | Trap / invariant |
|---|---|---|---|
| `Breeds.chaos_exalted_sorcerer_drachenfels.run_on_spawn` / `.run_on_death` [hook,tbl] `_gt_creature_spawner.lua:750`/`:849` | Nurgloth boss init/death; builds a spell state machine using `level_analysis` nodes that exist only in `dlc_castle` | Lupo-authored replacement: rebuild the spell/blackboard state line-for-line but skip the arena-only nodes so the sorcerer spawns anywhere | `run_on_spawn` ports the vanilla boss-intro invincibility verbatim - writes `health_ext.is_invincible = true` on each hero via `ScriptUnit.extension(...,"health_system")` (UNGUARDED, no `has_extension`), set-only, relies on vanilla boss flow to clear |
| `BTConditions.transitioned_one_third_health` [hook,tbl] `_gt_creature_spawner.lua:890` | Has the boss passed the 1/3-health transition | Outside `dlc_castle` pass vanilla's return through unaltered (issue #275); inside defer to vanilla | The OLD `(in_arena and func()) or true` body collapsed to constant-true and forced the final-offense phase at full health in the real arena - now `mod._gt_cs_one_third_wrapper` is multi-return-safe |
| `BTConditions.at_half_health / at_one_third_health / at_two_thirds_health / at_one_fifth_health / at_three_fifths_health / can_transition_half_health / can_transition_one_third_health / less_than_one_health` [hook,tbl] `_gt_creature_spawner.lua:949-956` | Compare `blackboard.current_health_percent` (or raw `current_health`) to a threshold | #59 first-tick nil-guard for ANY boss BT: between `run_on_spawn` and the first health-blackboard tick the field is nil and a bare `nil < number` crashes [src: `scripts/entity_system/systems/behaviour/nodes/bt_conditions.lua:309`] | Guards bias to FALSE ("threshold not reached yet"); `less_than_one_health` uses the raw variant; per-(breed,condition) deduped `printf("[gt_bt:#59] ...")` |

### Surface 2c - Debug draw + auto-dump probes (owner: `docs/engine/08`, `/09`; `_gt_debug_highlights.lua`, `_gt_debug_probes.lua`)

`_gt_debug_highlights.lua` (#302) draws its overlay from a `hook_safe("IngameUI",
"update")` (grep-verified singleton; the existing `IngameHud.update` hook is
`_gt_melee_warning`'s). It does NOT use `LineObject`: a raw `LineObject.dispatch`
into `level_world` renders NOTHING in retail (Fatshark's release drawers are the
no-op `DebugDrawerRelease`, `debug_manager.lua:103` + `debug_drawer_release.lua`;
`Debug.active = BUILD ~= "release"`, `debug.lua:9`) - proven by
`console-2026-07-12-22.03.01` dispatching 48-60 boxes/frame with nothing on
screen. Instead it renders the way the shipped HUD does: project each world point
with `Camera.world_to_screen` (front-dot guarded, `world_marker_ui.lua:359`) and
draw 2D lines on a `World.create_screen_gui` (gw_fonts, can_get-guarded #293/#295)
with `ScriptGUI.hud_line` (`script_gui.lua:45`). Box = 8 projected `Unit.box`
corners + 12 edges; aggro = projected ground circle; head = camera-facing square.
Screen gui released under the §32 world-identity gate (`live == w`) via
`World.destroy_gui`. `_gt_saved_positions.lua` / `_gt_item_spawner.lua` register
NO class hooks - they drive off gt's shared `mod._gt_register_update` tick or chat
commands (see subsystem note 2). The probe hooks below are observation-only.

`_gt_bot_teleport_lab.lua` adds one mod-to-mod RPC channel for debug-draw
sharing (issue 534): `gt_draw_leash` [rpc], schema-tagged `mod.GT_DRAW_RPC_SCHEMA`
(first positional arg, drops mismatches per `docs/VMF_RECIPES.md` §10). The HOST
packs its bot leash lines (bot->follow, bot->host) as raw world positions in
integer decimeters into one `|`-joined string (<~200 chars, under the 500-char
RPC cap §4) and broadcasts to `"others"` at ~6-7 Hz when `gt_devtools_leash_lines`
+ `gt_devtools_share_draws` are both on; every gt peer with `gt_devtools_share_draws`
on redraws the last snapshot each frame via a new `shared_draw`
`mod._gt_register_update` consumer with its OWN LineObject (own
`mod._gt_shared_line_object` handle under the same §32 identity-gated lifecycle
as `_clear_and_null`), expiring after 1 s. Leash lines are the only shared draw:
they are host-exclusive (bots + `follow_unit` are server-side), whereas the debug
highlights enumerate per-peer entities every peer already draws locally and the
bot HUD is fixed-pixel screen text. Bots exist only on the host, so the host is
the sole source; the consumer skips the render on the host to avoid double-draw.

| Class.method (kind) | Vanilla behavior | Why gt hooks it | Trap / invariant |
|---|---|---|---|
| `HeroView.on_enter/on_exit` / `HeroWindowItemCustomization.on_enter/on_exit` / `IngameUI.handle_transition` / `HeroViewStateOverview.set_layout_by_name/on_enter/_change_window` [hook] `_gt_debug_probes.lua:160-885` | Keep menu view/window transitions | Auto-dump crash-triage context (backend_id/slot/key, transition names) on the paths that produced `fa1ec6f8`/`ef637399` | Full `mod:hook` with `return func(self,...)` so the observation chains with other mods that hook the same views |
| `LevelTransitionHandler.load_current_level` [hook] `_gt_debug_probes.lua:211` | Request a level's resource load | Log the level_key on load | Full `mod:hook` DELIBERATELY - BossTimer / keyPickupMessage / Loremaster's Armoury already `hook_safe` this, a 4th `hook_safe` would silently shadow theirs (VMF no-chain) |
| `PlayerManager.add_remote_player / remove_player / relinquish_unit_ownership` [safe] `_gt_debug_probes.lua:703-752` / `CharacterStateHelper.change_camera_state` [safe] `:729` | Player join/leave/clean-death teardown; the single funnel dead/respawn uses to push observer<->follow [src: `scripts/utils/player_character_state_helper.lua:1822`] | Auto-capture an AI/slot dump on join/leave and on observer/follow transitions (hands-free CW death/respawn capture) | `hook_safe` - observation only; `change_camera_state` early-returns for bots at `:1823` |
| `PeerStates.Disconnecting.on_enter` [hook,tbl] `_gt_disconnect_grace_diag.lua` | Synchronously removes the channel peer from `GameSession`, calls `GameNetworkManager.remove_peer` (which removes all peer-owned Player objects), notifies the game mode, then clears the peer's party slot [src: `scripts/network/peer_states.lua:520-582`; `scripts/managers/network/game_network_manager.lua:814-825`; `scripts/managers/network/party_manager.lua:821-835`] | Issue #309 observation-only trace: one explicit host arm captures pre/post player, unit and slot state plus six bounded replacement-bot samples; the existing `add_remote_player` singleton dispatches exact-peer reconnect evidence | No grace mutation yet: delaying this seam would also defer EAC, game-object, profile, party and mechanism cleanup. Cap is 10 records/one event; runtime `issue309_disconnect_grace_diagnostics_armed`. Adventure/Deus fill an empty slot with a new host-owned bot later in `_handle_bots` [src: `game_mode_adventure.lua:364-422`; `game_mode_deus.lua:520-578`] |
| `StateTitleScreenInitNetwork._connected_to_steam` / `BackendManagerPlayFab._update_error_handling` / `NetworkClient.update` [hook] `_gt_diag_disconnect_failure.lua` | The title state reads `Steam.connected()` before sign-in; backend error handling flips `_is_disconnected` after the error popup resolves; the network client records channel failure reasons and connecting timeout [src: `scripts/game_state/title_screen_substates/win32/state_title_screen_init_network.lua:82-94`; `scripts/managers/backend_playfab/backend_manager_playfab.lua:439-475`; `scripts/network/network_client.lua:332-345,372-382`] | Issue #753 always-on dev diagnostics correlate the three measured states at their transition edges so a real service incident distinguishes Steam unavailable, PlayFab disconnected, and P2P failure while both services still report live | Read-only and transition-only: no recovery, RPC, popup, or engine-state mutation. Full wrappers preserve every vanilla return with explicit result counts. `[gt:753] observed=` labels measurements rather than claiming the external root cause; runtime `issue753_disconnect_failure_diagnostics_armed`. |
| `BackendInterfaceItemPlayfab.refresh_bot_loadouts` [safe] `_gt_debug_probes.lua:608` + `<live itf>.refresh_bot_loadouts` [safe,tbl] `:629` | Refresh bot loadouts | Capture bot-loadout resolution; the class hook is a documented DEAD path under LA (14 vanilla runs, 0 class-hook fires) so a table hook on the live `get_interface("items")` clone is installed on demand | Two DIFFERENT targets (class vs post-LA instance) so no VMF collision; hook the resolved instance, not cold `_G` (memory `reference_cim_equip_capture_la_dispatch`) |
| `AIGroupTemplates.spline_patrol.update` [hook,tbl] `_gt_debug_probes.lua:666` | Spline-patrol formation tick; `update_units` reads `POSITION_LOOKUP[member]` | Patrol-formation crash probe: NAME any member whose `POSITION_LOOKUP` is missing/wrong-type BEFORE vanilla crashes | LOG ONLY, no guard - the crash still produces its backtrace |

### Surface 3a - ProfileSynchronizer reservations + end-of-level (owner: `docs/engine/11`, `/08`; `_gt_level_control.lua`)

| Class.method (kind) | Vanilla behavior | Why gt hooks it | Trap / invariant |
|---|---|---|---|
| `ProfileSynchronizer.get_persistent_profile_index_reservation` [hook] `_gt_level_control.lua:179` | Returns a peer's persistent profile-index reservation; `_award_end_of_level_rewards` reads it as `SPProfiles[reservation]` [src: `scripts/game_state/state_ingame_running.lua:768`] | After a host `/win`, a client's own reservation races to nil/0 and vanilla does `SPProfiles[nil].display_name` -> crash; return the local player's REAL profile ONLY when stale AND it is our own peer AND a valid local profile exists | The v0.2.103 SOURCE fix; healthy reservations pass through untouched; client-local, no host desync (fires only for our peer) |
| `StateInGameRunning._award_end_of_level_rewards` [hook] `_gt_level_control.lua:198` | Awards end-of-level rewards, reading the reservation-derived profile [src: `state_ingame_running.lua:768`] | Last-resort net: wrap in `pcall`, skip-with-warning if the profile is genuinely unresolvable (no local player) rather than crash | Belt-and-suspenders with the reservation hook above; the v0.2.101 temporary-shim approach crashed inside `ExperienceSettings.get_experience(nil)` (`f32490ac`) and was replaced |
| `ProfileSynchronizer.get_profile_index_reservation` [hook] `:399` / `try_reserve_profile_for_peer` [hook] `:404` / `is_free_in_lobby` [hook] `:413` | Report whether a `(party, profile)` is reserved / try to reserve / whether a profile is free in the lobby | Duplicate Careers: when `allow_duplicate_careers` is set, report unreserved / force-reserve-true / free-true so multiple peers share a career | `is_free_in_lobby` is a STATIC function (no `self`) [src: `scripts/network/profile_synchronizer.lua:860`] - the wrapper signature intentionally omits `self` |
| `gt_level_control` [rpc] `_gt_level_control.lua:128` / `gt_respawn_request` [rpc] `:330` | - | Client->host level-control verbs (`complete/fail/retry_level`) and respawn requests, run host-authoritative | Sent to the mechanism-resolved host peer (`Managers.mechanism:server_peer_id()`); literal `"server"` recipient is a no-op (`docs/VMF_RECIPES.md` §10); NOT schema-tagged (scalar payloads) |

### Surface 3b - Lobby manifest / MOTD / moderation (owner: `docs/engine/03`; `docs/VMF_RECIPES.md` §10; the `_gt_lobby_*.lua` set)

Most lobby features ride vanilla lobby/session objects DIRECTLY (Steam
lobby_data, `kick_peer`, EventManager) rather than hooking a class - see
subsystem note 3. The two class/RPC seams:

| Class.method (kind) | Vanilla behavior | Why gt hooks it | Trap / invariant |
|---|---|---|---|
| `StateLoading.create_popup` [hook] `_gt_lobby_failed_join_reveal.lua:356` | Builds the failed-join error popup [src: `scripts/game_state/state_loading.lua:2447`] | On `error_key == "failure_start_join_server_incorrect_hash"`, substitute an enriched popup listing missing/mismatched mods (pulled from the host's lobby_data manifest) + an Open-Workshop button | Explicit arity capture `n = 3 + select("#",...)` then `unpack(args,1,n)` because leading `header/action/right_button` are often nil while trailing `string.format` varargs are present (`docs/VMF_RECIPES.md` §2a); early-outs to vanilla while `Managers.account:leaving_game()` (#72); successful takeover routes through tested `_take_over_enriched_popup` and NEVER assigns `self._popup_id` (double-consume race would hang). Tier-a #72 source invariant rejects a direct assignment anywhere in the module. |
| `gt_lobby_motd_show` [rpc] `_gt_lobby_motd.lua:156` | - | Host pushes a Message-of-the-Day to a joining peer's chat/popup - vanilla `chat_manager:add_local_system_message` / `popup:queue_popup` are LOCAL ONLY so an RPC is the only remote path | Schema tag `mod.GT_LOBBY_RPC_SCHEMA` is the FIRST positional arg (receiver validates and drops mismatches); text chunked to <=400 chars with a session id because the engine caps each RPC string at 500 [src: `scripts/network/network_utils.lua:93`] |

### Surface 3c - AI takeover (owner: `docs/engine/02`, `/11`; `_gt_ai_takeover.lua`)

| Class.method (kind) | Vanilla behavior | Why gt hooks it | Trap / invariant |
|---|---|---|---|
| `gt_ai_toggle_request` / `gt_ai_toggle_result` [rpc] `_gt_ai_takeover.lua` | - | A client asks the host to enter/reclaim keep-slot takeover; the authenticated host replies with its actual active state | Schema v2; sender peer is authoritative and a mismatched payload peer/local id is rejected. Result receiver accepts only the current host. Reason strings cap at 120 bytes and repeated requests are idempotent. |
| `GameModeBase._add_bot_to_party` / mode `_remove_bot` / `force_respawn` [direct composition] `_gt_ai_takeover.lua` | Add/remove a real host bot and drive the native player spawn state [src: `scripts/managers/game_mode/game_modes/game_mode_base.lua:79-135`; Adventure `force_respawn`: `game_mode_adventure.lua:283-292`; Deus `:440-449`; Weave `game_mode_weave.lua:276-285`] | Reserve the human Player/profile/party slot, let one ordinary bot yield its slot when vanilla filled the party, place one temporary same-profile bot there, enter observer, then restore/reclaim | Exact modes are Adventure/Deus/Weave. A four-human party, dead/missing humans, absent APIs, and unsupported modes fail before despawn. Another takeover bot is never displaced. No `remove_player`, human party/profile reassignment, locomotion override, custom lookup, or per-frame transport. |

### Surface 4a - Godmode + enemy-spawn control (owner: `docs/engine/10`, `/07`; `general_tweaker_dev.lua`)

Godmode is a networked damage-suppression state, not a health-ext flag - see
subsystem note 4.

| Class.method (kind) | Vanilla behavior | Why gt hooks it | Trap / invariant |
|---|---|---|---|
| `DamageUtils.add_damage_network` [hook] `general_tweaker_dev.lua:1014` / `add_damage_network_player` [hook] `:1032` | Apply already-final damage on the authoritative machine (liquids/DoTs/bombs via `damage_source`; explosion/profile path) [src: `scripts/helpers/damage_utils.lua:1745`, `:1864`] | Godmode HP block: return `0` when `_gt_godmode_active(attacked_unit)`. PLUS #469 bot-AOE immunity MERGED into both bodies (single-hook discipline): return `0` for a host-owned BOT hit by a curated hazard (`mod._gt_bot_aoe_immune_sources` on the network funnel, `mod._gt_bot_aoe_immune_profiles` on the player funnel), gated live on `gt_bot_behavior_improvements` + `gt_bot_aoe_immunity` and `Managers.player.is_server` | Static fns, no `self`; `_gt_godmode_active` answers HUMANS ONLY - bots are owned by the host peer, so a bare peer check made every host bot invincible (regression fixed v0.2.91). #469 identity split: the liquid/DoT funnel keys on `damage_source` (`lamp_oil_fire`), the explosion funnel keys on `damage_profile.name` because timed explosions pass the shared `"undefined"` damage_source [src: `timed_explosion_extension.lua:125`]; nothing rides the wire (host applies bot damage). Pins: `gt_bot469_aoe_immunity_wired` in-game + `test_gt_bot_hazard_resistance.lua` offline |
| `DamageUtils.apply_buffs_to_damage` [hook] `general_tweaker_dev.lua` (#549/#488) | Populates victim units and applies target/attacker mitigation before both damage funnels perform their authoritative health writes [src: `scripts/helpers/damage_utils.lua:2134-2450`; consumers `:1783-1831`, `:1916-1987`] | After vanilla side effects, #488 applies host-bot gas/warpfire resistance from active prior stacks; #549 then returns 9999 for a positive enemy hit whose human attacker has Godmode + the child toggle | GT's ONLY hook on this pair. #488 uses weak-key per-unit/per-type expiry arrays (2 s, 20%, cap 5), no custom buff/RPC, and leaves first/other/human hits unchanged. #549 remains the final outgoing override. |
| `StatusUtils.set_in_vortex_network` [hook] `general_tweaker_dev.lua` (#1009) | On the server, set `in_vortex`, broadcast `rpc_status_change_bool`, and return success [src: `scripts/helpers/status_utils.lua:278-297`]; Blightstorm adds the player to its captured-player table only on a true return [src: `scripts/unit_extensions/ai_supplementary/vortex_extension.lua:615-631`] | Reject only the `in_vortex == true` entering edge for a human resolved by `_gt_godmode_active` and a source unit positively owning the enemy `VortexExtension`; return false before status/RPC/capture mutation | GT's only hook on this pair. Exit cleanup, non-Godmode behavior, outside-radius attraction, Sister of the Thorn's `area_damage_system`-owned `SummonedVortexExtension`, and unrelated status transitions remain vanilla. No broad movement or invulnerability hook. |
| `GenericStatusExtension.update_falling` [hook] `general_tweaker_dev.lua:779` | Client-side fall-damage trigger; checks `ignore_next_fall_damage` before sending the RPC | Godmode fall block for the client-self case (the `add_damage_network` hook only covers host-self); set `ignore_next_fall_damage=true` for the local player under godmode | Blocks at the source before the RPC is sent |
| `GenericStateMachine.change_state` [hook] `general_tweaker_dev.lua:832` | The chokepoint every `csm:change_state` funnels through | Godmode disabler block: drop the transition into any `_DISABLER_STATES` (pounced/grabbed/hanging-cage) for the local player - disablers bypass the damage pipeline so the DamageUtils hooks alone do not stop them | NOT blocked: stunned/staggered/ledge_hanging/overpowered/knocked_down/dead |
| `gt_godmode_state` [rpc] `general_tweaker_dev.lua:703` | - | Each peer broadcasts its godmode state keyed by peer_id so the authoritative host can suppress a client's damage; #549 adds an optional strike-damage child flag on the same heartbeat | Schema-validated; `_GT_GODMODE_TIMEOUT = 9.0` (~3 missed 3 s heartbeats); self-healing rebroadcast via `mod.update` because a cold client->host VMF send can drop during mission-load bot churn (re-handshakes `ping_vmf_users` first); optional trailing flag keeps the schema-1 base payload backward-tolerant |
| `PlayerUnitFirstPerson.extensions_ready` [safe] `general_tweaker_dev.lua:312` | Fires on the LOCAL player's own spawn (bots use `PlayerBotUnitFirstPerson`, husks have no 1P ext) | Schedule the godmode+noclip post-spawn re-apply once per local spawn (`_post_spawn_reapply_timer=0.5`) | gt's ONLY hook on this method (the camera copy left with #191); re-apply is timer-driven, NOT a `GenericStatusExtension.extensions_ready` hook (at that timing `player.player_unit` is unassigned) |
| `ConflictDirector.spawn_queued_unit` [hook] `general_tweaker_dev.lua:859` / `spawn_unit_immediate` [hook] `:876` | Deferred (pacing) / synchronous (terror-event) enemy spawn | Disable Enemy Spawns: return when `disable_enemy_spawns` | `spawn_queued_unit` is CONSOLIDATED - also calls `mod._gt_solo_on_spawn_queued` (assassin/packmaster warning) and a necro pet-skeleton probe, merged because VMF drops a 2nd hook |

### Surface 4b - Noclip + movement + engine nil-guards (owner: `docs/engine/04`; `_gt_noclip.lua`, `_gt_hacks.lua`, main)

Third-person camera, freecam, and the `set_first_person_mode` cutscene-yield
seam all MIGRATED to `gui_tweaker` (gut) on 2026-06-29 (#191); noclip is the only
body-movement/camera-adjacent feature still in gt_dev.

| Class.method (kind) | Vanilla behavior | Why gt hooks it | Trap / invariant |
|---|---|---|---|
| `PlayerUnitLocomotionExtension.update_script_driven_no_mover_movement` [hook] `_gt_noclip.lua:112` | Applies whatever `velocity_wanted` the state machine wrote, teleporting the unit without touching the mover (the chaos-grab state) | Commandeer this state for the local noclip player: compute WASD/Space/Ctrl velocity projected through `first_person_system:current_rotation()` and write `velocity_*` + `Unit.set_local_position` | Per-frame heartbeat re-asserts `loco.state = "script_driven_no_mover"` (ledge/ladder transitions call `enable_script_driven_movement` and hand control back to the wall-respecting mover); on OFF, `Mover.set_position` before re-enabling or the next `Mover.move` yanks the player back |
| `AISimpleExtension.init` [safe] / `AiHuskBaseExtension.init` [safe] `_gt_dummy_collision.lua` | Copy `breed.player_locomotion_constrain_radius` to each authoritative/husk AI extension; local player movement later reads it in `PlayerUnitLocomotionExtension` (`player_unit_locomotion_extension.lua:463-534`) | #304 snapshots the training dummy's native 0.7 radius and clears only the per-unit value while the local toggle is enabled in an inn level | Exact `breed.name == "training_dummy"` + `DamageUtils.is_in_inn == true` scope; both authority views are needed because avoidance is local; never disables actors/hitzones and sends no RPC; restore on OFF/state change/mod disable |
| `CharacterStateHelper.is_ledge_hanging` / `will_be_ledge_hanging`, `HealthSystem.suicide`, `PlayerUnitHealthExtension.entered_kill_volume`, `NetworkTransmit.send_rpc_server` [hooks] `_gt_noclip.lua` | Ledge tests; host `z<-240` suicide; authored kill-volume `rpc_request_insta_kill`; client `z<-240` `rpc_suicide` | Return false or suppress the exact local boundary-death route while noclip is active (#241) | Every gate requires the local player and active noclip. The network hook checks only `rpc_suicide` with the local unit's exact go-id; all other traffic passes through without allocation. Each encountered route logs once per noclip episode. The broad `PlayerUnitHealthExtension.die` funnel remains vanilla so ordinary combat deaths are not masked. |
| `AICommanderExtension._update_units` [hook] `general_tweaker_dev.lua:531` / `PlayerWhereaboutsExtension.update` [hook] `_gt_hacks.lua:507` / `RoundStartedSystem._players_left_start_area` [hook] `_gt_hacks.lua:523` | Read `POSITION_LOOKUP[unit]` then feed nav queries / commander pos math | AI-takeover despawn-race guards: a human->bot swap leaves a unit without a `POSITION_LOOKUP` entry for a tick -> `nil + Vector3` or a nil arg to `GwNavQueries.triangle_from_position` fatals; skip the tick until the position exists | Always-on host-side guards; `_update_units` is `rawget`-guarded; `_players_left_start_area` returns `false` ("round not started") if ANY tracked unit lacks a position |
| `VolumetricsFlowCallbacks.unregister_fog_volume` [hook,tbl] `_gt_hacks.lua:485` / `Unit.get_data` [hook,tbl] `:491` | Unregister a fog volume by `params.unit` / read unit data | Nil-guards: bail on a dead/nil `unit` to suppress engine-error spam during mid-cleanup | `Unit.get_data` DISTINCT from the spawner's `Unit.create_actor` (per-method) |

### Surface 4c - Cheat / QoL body writes (`_gt_hacks.lua`, `_gt_godmode_qol.lua`, `_gt_hp_smoothing.lua`)

| Class.method (kind) | Vanilla behavior | Why gt hooks it | Trap / invariant |
|---|---|---|---|
| `GenericStatusExtension.add_fatigue_points` [hook,tbl] `_gt_hacks.lua` (section 5.2) | Adds fatigue (stamina cost) on blocks/dodges/pushes; runs ONLY on the unit's owning machine (`blocked_attack` gates on `not player.remote`, the fn Crashify-rejects remote players) | Infinite stamina: short-circuit when active. MERGED issue 529 godmode stamina gate: drops enemy/hazard fatigue types (self-action allowlist `mod._GT_529_SELF_FATIGUE_TYPES` + positive-cost check) when `mod._gt_godmode_active(self.unit)` | Always-on wrapper flagged by `_gt_stamina_active` so it never re-registers (VMF errors on duplicate registration). Owner-side write = local godmode flag is the authority as host AND client; skipping the call also skips the fatigue-max `set_block_broken`, so guard breaks stop too. rt-check `gt529_godmode_stamina_gate_wired` |
| Vanilla `twitch_no_overcharge_no_ammo_reloads` buff (no new hook) `_gt_hacks.lua` (#549) | Reload omits reserve-ammo subtraction and overcharge addition returns early while the owner carries the buff [src: `generic_ammo_user_extension.lua:160-176`; `player_unit_overcharge_extension.lua:343-368`] | Existing `/infinite_ammo` owner plus Godmode's local-only child are reconciled as independent sources of the same buff | Consumption-side; no `_max_ammo`/network cap mutation. Command remains host-wide, Godmode child owner-only; removing one source preserves the other |
| `CareerExtension.update` [safe,tbl] `_gt_hacks.lua:203` | Per-tick ability cooldown update | Player/bot ult-cooldown cap: clamp `ability.cooldowns[k]` to the slider max | Replicates the decaying-charge index + `set_activated_ability_cooldown_unpaused` 1:1 so the ability HUD does not desync |
| `ProfileRequester.request_profile` [safe,tbl] `_gt_hacks.lua:390` / `GameModeInn._cb_start_menu_closed` [safe,tbl] `:391` | Career/profile switch / keep start-menu close | Re-sync the base-crit slider to the new career's vanilla value | Table-form, nil-guarded per #70 defensive load-order |
| `DamageUtils.allow_friendly_fire_ranged` [hook] `_gt_godmode_qol.lua:90` / `allow_friendly_fire_melee` [hook] `:95` | Gate deciding whether ranged/melee friendly fire is allowed | Return false when `disable_friendly_fire` is set | Different methods from godmode so no dup; the godmode BODY stays in main (this module explicitly is NOT godmode) |
| `UnitSpawner.destroy_game_object_unit` / `BreedFreezer.rpc_breed_freeze_units` [hooks] `_gt_client_ragdolls.lua` | Client teardown for a host-destroyed game object / client mirror that parks and reuses pooled trash husks | #332 snapshots a dead AI husk as a bounded client-local visual corpse before either authoritative removal route | Client only; exact dead non-player AI + active network/game mode; frozen units defer to vanilla. The ORIGINAL network unit and RPC remain unchanged. The clone has no extensions/game object/NetworkUnit identity and is non-colliding/static. A per-spawner FIFO deletes its oldest clone through `mark_for_deletion` above the slider cap. Host path and all living/non-AI objects are untouched. [src: `scripts/network/unit_spawner.lua:492-507`; `scripts/managers/conflict_director/breed_freezer.lua:273-295,323-378`; authoritative-only death watch `scripts/unit_extensions/generic/death_reactions.lua:386-411`; husk update has no death-watch push `:507-522`] |
| `UnitFrameUI.set_total_health_percentage` [safe] `_gt_hp_smoothing.lua:79` / `UnitFrameUI.update` [safe] `_gt_hp_smoothing.lua:89` | Receives the incoming HUD health fraction / per-frame bar lerp | Ease the local player's own HUD bar-drop under latency (batched `rpc_add_damage`), snap on heal/knockdown/death | STRICTLY cosmetic - only writes `content.total_health_bar.bar_value`, never any health extension; only `_frame_type == "player"` |

### Surface 5 - Combat / QoL / UI (owner: `docs/engine/09`, `/10`; the remaining `_gt_*` modules)

| Class.method (kind) | Vanilla behavior | Why gt hooks it | Trap / invariant |
|---|---|---|---|
| `GameModeAdventure.evaluate_end_conditions` [hook] `_gt_solo_qol.lua:69` / `GameModeDeus.` `:70` / `GameModeWeave.` `:71` | Evaluate round end; returns `(ended, reason, reason_data)` | Auto-restart on wipe: rewrite `reason=="lost"` -> `"reload"` so the mission restarts in place | Captures & forwards the THIRD return so a non-restart end is not stripped [src: `scripts/game_mode/game_mode_manager.lua:800`]; `"reload"` is valid per each mechanism |
| `AiUtils.generic_mutator_explosion` [hook] `_gt_solo_qol.lua:307` / `AreaDamageSystem.rpc_create_explosion` [hook] `:321` | HOST renders the Explosive-mutator burst then broadcasts / CLIENT RPC receiver renders its own burst | Purple mutator-explosion suppression (#332): filter by template name on host, skip the local render on client | Host hook forwards vanilla's 4th arg `do_damage` (the 3-arg call silently passed nil); the client hook is a networked RPC receiver gated `not self.is_server` so the host's re-broadcast to OTHER clients is untouched - purely cosmetic, no authoritative damage |
| `MoodHandler.set_mood` [hook] `_gt_solo_qol.lua:445` / `apply_environment_variables` [safe] `:335` / `BuffExtension._play_screen_effect` [hook] `:474` / `BuffFunctionTemplates.functions.apply_huntsman_activated_ability` [hook,tbl] `:497` | Enable/disable a mood, apply shading-env vars, play a screenspace FX, Huntsman FOV punch + flow + hud sound | Neuter ult/downed screen effects; disable fog / sun shadows | `set_mood` swallows ONLY the ENABLE calls (`if value`) so toggling mid-effect cannot strand a mood on; the Huntsman hook temporarily nops `Unit.flow_event`/`play_remote_hud_sound_event`, `pcall`s, and restores in ALL cases (re-raises via `error(...,0)`) with a count-preserving `_pack`/`unpack` (`docs/VMF_RECIPES.md` §2a) |
| `EnemyRecycler.update` [hook] `_gt_solo_qol.lua:350` | Per-frame boss/threat recycler tick | Boss path-progress readout + spawn-sphere debug draw | Probes `wm:has_world("level_world")` first because `WorldManager.world()` FASSERTS on a missing world [src: `foundation/scripts/managers/world/world_manager.lua:111-115`] (#459); recreates its `LineObject` when the world changes so it never reuses a stale handle |
| `BTSpawningAction.enter` [safe] `_gt_solo_qol.lua:211` / `DialogueSystem._update_currently_playing_dialogues` [hook] `:223` / `<ability_class/action_class>._play_vo` [hook] `:261`/`:273` / `_G.Localize` [hook] `:133` / `PlayerHud.set_current_location` [hook] `:143` / `AreaIndicatorUI.update` [hook] `:151` | Spawn VO, dialogue tick, ult VO, loc lookup, HUD location text, area-indicator draw | Assassin/packmaster spawn warnings + disable-ult-VO + flash fake `ASSASSIN_WARNING_`/`PACK_WARNING_` keys | `_play_vo` de-dupes shared `ability_class` (VMF would drop a 2nd) + nil-guards `career.activated_ability` (the crash the source TrueSoloQoL trips on Versus entries); assassin/packmaster warning is MERGED into main's `spawn_queued_unit`, not re-hooked |
| `AnimationSystem.anim_event` [safe] `_gt_melee_warning.lua:228` | Fires a state-machine anim event; the single convergence where the host's local anim AND the client-received `rpc_anim_event` re-invoke both land [src: `scripts/entity_system/systems/animation/animation_system.lua:119`, receiver `:375`] | Detect enemy melee windups (per-breed `_ATTACK_DELAYS`) to cue an early dodge (#308) | RPC dispatch is DYNAMIC (`network_event_delegate.lua:52` re-looks-up `object[cb]`) so the class hook catches the wire path too; the 4th arg `skip_sync` marks the re-invoke; `event_name` is already a plain string, no NetworkLookup decode |
| `IngameHud.update` [safe] `_gt_melee_warning.lua` | Per-frame HUD composite | SINGLE draw dispatcher: #308's four-edge red warning flash plus #381's persistent local `GODMODE` text consumer, each on its own `hud_scale_fit` scenegraph | `_gt_melee_warning.lua` remains the sole hook owner; #381 exports a draw function and never rehooks. Both acquire the renderer from the live in-game UI context. The indicator uses `materials/fonts/arial`, the proven HUD text path, and a canvas-clamped upper-right layout; the sound-cue side still probes `has_world` before `WwiseWorld.trigger_event` |
| `ContextAwarePingExtension._check_raycast` [hook] `_gt_prioritize_specials.lua:74` / `PlayerUnitSmartTargetingExtension.update_opt2` [safe] `:124` / `ActionTrueFlightBowAim.client_owner_post_update` [hook] `:173` | Ping raycast pick / aim-assist target pick / true-flight homing lock | Bias each toward `breed.special` enemies (tag / Deepwood staff / Soulstealer staff) | Client-side, per-local-player, no RPC; `ActionTrueFlightBowAim` is gated to `staff_death` because Waywatcher career arrows INHERIT the method and must not be biased; every body `pcall`-degrades to vanilla |
| `PassiveAbilityQuestingKnight._generate_quest_pool` [hook,tbl] `_gt_misc_features.lua:103` / `VoteManager.rpc_client_complete_vote` [safe] `:172` | Generate the Grail Knight quest pool / networked vote-completion RPC | Reorder chosen quests to the FRONT (keeps a valid pool past index 3) / auto-ready on a passed vote (`countdown_completed`) | Vote hook: all clients receive the RPC but the underlying call is server-guarded, gated on `is_server` to keep the echo accurate |
| `LevelUnlockUtils.weave_unlocked` [hook] `_gt_weave_unlock.lua:29` | Gates weave selection AND joining; true only for completed weaves [src: `scripts/settings/level_unlock_settings.lua:490`] | Unlock every OWNED weave so any can be picked/joined | Replicates vanilla's DLC gate (`level_unlock_settings.lua:503-509`) - never unlocks the Winds-of-Magic paywall, only progression; unknown key defers to vanilla |
| `TrainingDummyHealthExtension.add_damage` [safe] `_gt_probe_dummy_hits.lua:76` | Every damage event on a keep training dummy; also where the floating number is drawn [src: `scripts/unit_extensions/generic/training_dummy_health_extension.lua:56`] | Passive DEFAULT-ON probe (#198): bucket hits per `(dummy,attacker,source)` in a 0.2 s window and print one `[198:dummy]` line per swing | `hook_safe` observe-only, never reads/alters damage; signature mirrors vanilla's 17 args |

## Subsystem notes (how the vanilla flow runs, for gt's cases)

Each note is the minimum needed to read the hooks above; the owning `docs/engine`
doc carries the full architecture.

### The bot behaviour tree firing order (owner: `docs/engine/07`; the #139/#448/#492 surface)

A bot's top-level `BotBehaviors.default` is a `BTSelector` whose children are
evaluated in priority order every frame [src:
`scripts/entity_system/systems/behaviour/bt_bot.lua:7`+]. The revive selector
(`condition = "can_revive"`) sits near the top [src: `bt_bot.lua:14-32`]; the
"teleport_out_of_range" node (`BTBotTeleportToAllyAction`, `condition =
"should_teleport"`) sits far below it, after the priority-combat node [src:
`bt_bot.lua:305`, teleport node `:308-312`]. So a frame is spent on the
highest-priority node whose condition passes. Three failure modes gt fixes all
come from this ordering:

- **#448 soft-lock:** the CW knockdown-immunity boon aura grants
  `invulnerable` to any ally that `is_ready_for_assisted_respawn()` but never
  checks the CARRIER's own downed state [src: `morris_buff_settings.lua:872-921`],
  so two downed boon-carrying bots make each other permanently invulnerable and
  no revive can complete. FIX 11 skips the grant tick while a bot owner is
  knocked down (the `update_func` is resolved dynamically each tick [src:
  `buff_extension.lua:794`], so a table hook on the function intercepts it).
- **#139 leash yank:** `should_teleport` returns true at >=40 m and otherwise
  false while `target_ally_need_type` is set or a priority enemy is targeted
  [src: `bt_bot_conditions.lua:1208-1241`, gate `:1226-1228`, distance `:1241`],
  but the follow-candidate build in `AIBotGroupSystem._update_move_targets`
  drops disabled players from the follow set unless EVERY player is down [src:
  `ai_bot_group_system.lua:695-719`], so on a split-team down the `follow_unit`
  flips to a living far player and the leash yanks the bot AWAY from the downed
  ally. gt's fix is a BLANKET aid veto captured at the `should_teleport` seam
  (FIX 7 hook), not an early-return, so the lab layer can still override.
- **#492 revive stall:** `can_revive` keys on `target_ally_need_type ==
  "knocked_down"` [src: `bt_bot_conditions.lua:738`], but the picker
  `_update_target_ally` skips the utility ally-picker entirely on a
  priority-enemy frame [src: `player_bot_base.lua:698`], so a bot on a priority
  target never sets `target_ally_need_type` and never re-enters revive. FIX 3 /
  #492 relabel awaiting-respawn allies and suppress the priority pick so the
  revive node re-activates.

The **Bot Teleport Lab** (`_gt_bot_teleport_lab.lua`) is the diagnostics harness
for this surface. It registers ZERO class hooks of its own: VMF drops a second
hook on a pair gt already owns, so the lab instead exposes `mod._gt_btlab_*`
observer functions and `_gt_bot_fixes.lua` calls them from inside its existing
`should_teleport` / `BTBotTeleportToAllyAction.run` / `PlayerBotBase.update` /
`_assign_destination_points` hook bodies (dispatch resolves on the `mod` table at
call time, so load order is irrelevant). Its only own engine tick is the draw
layer, a registered `mod.update` consumer (not a class hook). This merge-dispatch
pattern - one hook per pair, internal fan-out - is the mod-wide discipline; the
retired F1..F10 bisection candidates stay in code, gated off behind
`_BTLAB_FIXES_ARMED = false`.

Issue #139/#384 attribution is event-correlated rather than follow-scoped as of
v0.2.243-dev: `[gt:139:chain] FOLLOW` captures the final selector result only on
aid-adjacent changes; `VETO` retains that bot/aid/follow identity for three
seconds; `TELEPORT` joins it to the action reason and #492 bailout state. The
action-side position pair is sampled from `Unit.world_position` because the
v0.2.241 co-op log empirically showed `POSITION_LOOKUP` unchanged inside the
wrapped action and updated only in the following D3 tick.

### World lifecycle, dead-world AV, and the POSITION_LOOKUP dead-temporary class (owner: `docs/engine/08`, `/04`; §32)

`mod.update` consumers keep ticking BETWEEN game states, where `level_world`
does not exist, so any world-touching draw code must guard the lifecycle.
`WorldManager.world(name)` FASSERTS on a missing world [src:
`world_manager.lua:111-115`] - `has_world` [src: `:107-108`] is the safe probe.
Passing `has_world` is still not enough: a NEW same-named world does not validate
an OLD cached handle, and resetting/dispatching a `LineObject` into a destroyed
world is a C-level access violation `pcall` cannot catch (§32, #459).
`_gt_debug_highlights.lua` carries the canonical guard set - `_world()` probes
`has_world` before `world()`, and `_clear()` only resets/dispatches when the
cached world handle is IDENTICAL to the live `level_world` (`live == w`), else it
logs "cached world is dead" and drops. The state teardown ordering that makes
this necessary is exit-notify-before-teardown: `GameStateMachine._change_state`
fires `Managers.mod:on_game_state_changed("exit", ...)` BEFORE the super changes
state and tears the world down [src:
`scripts/game_state/game_state_machine.lua:13-27`, exit notify `:17-18`], so gt's
`on_game_state_changed` chain is the last safe point to touch the old world.
`EnemyRecycler.update` (`_gt_solo_qol.lua`) and the melee-warning sound cue carry
the same `has_world`-first guard.

A related class is the POSITION_LOOKUP dead-temporary (#337): the local player's
`POSITION_LOOKUP[unit]` entry is a dead frame-pool `Vector3` handle in every
mod-reachable phase (`mod.update` fires at the TOP of the frame from
`ModManager:update`, the same window chat commands run in), so reading it throws
`"Vector3 expected, got userdata"`. Three modules avoid it: `_gt_saved_positions.lua`
seeds a LIVE destination `Vector3` into `POSITION_LOOKUP[unit]` synchronously
before `teleport_to` (whose last line reads `.z` via `set_falling_height`);
`_gt_debug_highlights.lua` reads live `Unit.world_position` instead; and
`_gt_debug_probes.lua`'s patrol probe NAMES the offending member before vanilla
derefs it.

### Host lobby / session seams (owner: `docs/engine/03`, `/11`; `docs/VMF_RECIPES.md` §10)

gt's lobby moderation rides vanilla lobby/session objects DIRECTLY rather than
hooking classes:

- **Manifest publish/consume via Steam lobby_data.** The host serializes its
  loaded-mod list into chunked `ltw_*` lobby-data keys and publishes via
  `LobbyHost:set_lobby_data` [src: `scripts/network/lobby/lobby_host.lua:139`];
  the `LobbyHost` is discovered in priority order (`network._lobby_host`,
  `network_server.lobby_host`, then `matchmaking.lobby` DUCK-TYPED on
  `set_lobby_data` because the same field is a `LobbyClient` when joining) [src:
  `scripts/managers/matchmaking/matchmaking_manager.lua:637`]. The failed-join
  reader pulls it back with `LobbyInternal.get_lobby_data_from_id_by_key` and
  `Managers.lobby:get_lobby("matchmaking_session_lobby")`. The `ltw_` key prefix
  is deliberately retained (not renamed `gtw_`) for cross-compat with legacy
  `lobby_tweaker` peers.
- **Kick via `network_server:kick_peer`.** All three moderation features
  (idle-kick, ignore-list, slot-reservations) resolve
  `Managers.state.network.network_server` and call `:kick_peer(peer_id)`
  [verified against `scripts/managers/admin/dedicated_server_commands.lua:197`].
  Idle detection uses per-peer world-position deltas
  (`Unit.world_position` + `Vector3Box` + `distance_squared`) because vanilla
  `Managers.input.last_active_time` is local-only and cannot read remote peers.
  Note the LOBBY slot-reservations feature gates purely by kicking on join; it
  does NOT hook `ProfileSynchronizer` (that surface is the separate
  end-of-level/duplicate-careers cluster in `_gt_level_control.lua`).
- **Join trigger via a single EventManager dispatch.** Vanilla fires
  `on_player_joined_party` from `scripts/managers/party/party_manager.lua:562`.
  `Managers.state.event` (EventManager) keys callbacks by `(object, event_name)`,
  so three lobby modules each registering `(mod, "on_player_joined_party")` was
  last-writer-wins (§3b). gt registers the pair ONCE
  (`mod.gt_lobby_on_player_joined_party`) and fans out to each module's handler
  in registration order; it re-registers on every game-state transition because
  `Managers.state.event` is rebuilt each transition.

The mod-to-mod RPC channels (`gt_lobby_motd_show`, `gt_ai_toggle_request`,
`gt_level_control`/`gt_respawn_request`, `gt_cs_request`/`gt_cs_ack`) are all
keyed by mod-id, so dev and stable are automatically isolated - a session must
pin every peer to the SAME stream or the lobby/MOTD/slot/creature-spawner
surface cannot talk (repo `CLAUDE.md` "per-mod-id RPC channels" caveat). MOTD,
AI, and the creature spawner tag `mod.GT_LOBBY_RPC_SCHEMA` /
`mod.GT_AI_RPC_SCHEMA` / `mod.GT_CS_RPC_SCHEMA` as the first positional arg
and drop schema mismatches (`docs/VMF_RECIPES.md` §10).

### Godmode is networked damage-suppression, not a health flag (owner: `docs/engine/10`)

gt's player godmode does NOT write `is_invincible` or a `godmode` health-ext
field (the only `is_invincible` write in the mod is the ported Nurgloth
boss-intro invincibility inside the creature spawner). Invincibility is the sum
of four suppressions, all keyed on `_gt_godmode_active(unit)`: `DamageUtils.
add_damage_network` / `add_damage_network_player` return `0`; `update_falling`
sets `ignore_next_fall_damage`; and `GenericStateMachine.change_state` drops
disabler-state transitions (disablers bypass the damage pipeline).
`StatusUtils.set_in_vortex_network` separately rejects only the enemy
Blightstorm entering edge before the status, RPC, and captured-player-table
mutation. Because damage
to a player is resolved on the AUTHORITATIVE machine (the host for a client's
unit), a client's local godmode flag is invisible to the host, so each peer
broadcasts its state over the `gt_godmode_state` RPC keyed by peer_id with a
heartbeat clock (`_GT_GODMODE_TIMEOUT = 9.0`). The predicate answers HUMAN player
units ONLY - bots are owned by the host's peer_id, so an un-narrowed peer check
made every host bot invincible (regression v0.2.91). The AI-perception cue is a
separate `status_ext:set_invisible(..., "gt_godmode")` under its own reason
namespace [checked against `scripts/utils/perception_utils.lua:381`].

## What the engine will NOT let us do (dead ends, already paid for)

Distilled from the module headers and `docs/BUG_CLASSES.md` - do not re-discover.

- **A `mod.update` consumer cannot safely touch `level_world` unconditionally.**
  It ticks between game states where the world is gone; `WorldManager.world`
  FASSERTS and a `LineObject` into a freed world is an uncatchable AV. There is
  no "is the world alive" call that also validates a cached handle - you must
  keep the handle and compare identity (`live == w`) yourself (§32, #459).
- **`POSITION_LOOKUP` is unusable for the local player outside the entity-update
  phase.** Its entries are dead frame-pool `Vector3` handles in every
  mod-reachable phase; `PositionLookupSystem.update` is a no-op and no Lua write
  refreshes the player entry per frame. Read live `Unit.world_position` /
  `Unit.local_position`, or seed a live destination `Vector3` before a call that
  will read `.z` (#337).
- **You cannot re-hook a `(Class, method)` gt already owns.** VMF silently drops
  the second registration (repo `CLAUDE.md` NON-NEGOTIABLE 8). The Bot Teleport
  Lab, the assassin/packmaster warning, and the necro pet probe are all
  merge-dispatched into an existing hook body, not re-hooked. Adding a fresh
  `hook_safe` on `AIBotGroupSystem._assign_destination_points` (already FIX 9's)
  or on `ConflictDirector.spawn_queued_unit` (already main's) is the exact trap
  the lint catches.
- **Do NOT write the bare `script_data` global name.** `script_data =
  script_data or {}` rawsets a PRIVATE empty table into the VMF mod environment
  that permanently shadows the real `_G.script_data`, so a Disable-Bots flag
  never flips (#194). Always `rawget(_G, "script_data")` then field-mutate.
- **The AI-takeover convert-in-place swap is a dead end.** Converting a human to
  a bot in place produced owner-less units (client kept controlling a unit the
  host orphaned), ownership desync, and a string of despawn-race crashes
  (v0.2.113-.115). #247 replaces it with an engine-native keep-slot flow:
  despawn only the unit, enter the vanilla observer flow, let a real host bot
  fill one yielded/free slot, and reclaim by native force-respawn. The safety guards
  exposed by the retired approach
  (`AICommanderExtension._update_units`, `PlayerWhereaboutsExtension.update`,
  `RoundStartedSystem._players_left_start_area`) stay live regardless.
- **`Breeds.chaos_exalted_sorcerer_drachenfels` cannot fight outside `dlc_castle`
  unmodified.** Its BT reads arena-only `level_analysis` nodes; the fix rebuilds
  the spell/blackboard state line-for-line minus those nodes. The naive
  `(in_arena and func()) or true` gate on `transitioned_one_third_health`
  collapses to constant-true and breaks the REAL arena fight (#275) - the wrapper
  must pass vanilla's return through unaltered.
- **`hook_safe` cannot read pre-mutation state, and a raise in a `hook_safe`
  cannot be caught by the mod.** `BTBotTeleportToAllyAction.run` was converted
  from `hook_safe` to a full `mod:hook` precisely so the lab could box the bot
  position before AND after the snap; `set_block_broken` is a full hook so it
  reads `self.block_broken` before vanilla flips it.

## #749 borrowed-renderer residency boundary

Both direct `World.create_screen_gui` owners (bot teleport lab and debug
highlights) now require strict V2 proof for `materials/fonts/gw_fonts` in the
current live world. Failure defers only the optional overlay; it never changes
gameplay or a third-party renderer.

## Doc maintenance

Follows `docs/engine/README.md` maintenance rules: if a gt hook moves, a guard is
added, or a cited vanilla line drifts after a game patch, edit the affected row
in the SAME commit. Line numbers are against the 2026-07-12 decompile and
`gt_dev` module source - match crash logs by function name, not line. This
documents `general_tweaker_dev` (the active dev stream); never cite stable
`general_tweaker/` line numbers - promotion is user-triggered and the two streams
drift. Structural template is `character_weapon_variants/ENGINE_SURFACE.md`; keep
the section shape (hook table -> subsystem notes -> dead ends) stable.
