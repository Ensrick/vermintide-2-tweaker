local mod = get_mod("gt_dev")

-- ============================================================================
-- Bot Options -- AI teammate behavior fixes
-- ============================================================================
-- Three independent, default-OFF, host-side fixes for long-standing bot AI
-- gaps. Bots only exist on the host (server), so every hook here is effectively
-- server-side; none registers a network event or sends an RPC, so none can
-- crash a non-modded lobby member. All gate on their own VMF toggle.
--
-- Source citations below are into the decompiled vanilla source at
-- C:\Users\danjo\source\repos\Vermintide-2-Source-Code (verified 2026-06-16).
-- ============================================================================

local ScriptUnit = ScriptUnit
local POSITION_LOOKUP = POSITION_LOOKUP
local HEALTH_ALIVE = HEALTH_ALIVE
local Vector3 = Vector3
local BackendUtils = BackendUtils
local Unit = Unit
local Managers = Managers
local ALIVE = ALIVE

-- ----------------------------------------------------------------------------
-- FIX 1: Necromancer bot can't hand off potions (skull occupies slot_potion)
-- ----------------------------------------------------------------------------
-- WHAT
--   A Necromancer (bw_necromancer) carries a non-droppable "skull"
--   (bw_necromancer_career_utility_weapon, slot_type="potion",
--   is_not_droppable=true) that becomes the PRIMARY item in slot_potion at
--   spawn (career_settings_shovel.lua additional_inventory -> add_equipment
--   because the slot is empty, simple_inventory_extension.lua:143-154). When
--   she later picks up a real potion, the slot is occupied by the skull, so the
--   potion goes to ADDITIONAL storage (_additional_items["slot_potion"].items).
--
--   Every bot potion-handoff check reads only the PRIMARY slot item:
--     * scoring: player_bot_base.lua:881-888 reads get_slot_data("slot_potion")
--       -> skull template -> can_give_other == nil -> bot never offers a potion.
--     * give interaction: interactions.lua give_item keys off the WIELDED /
--       primary item (get_wielded_slot_item_template:1694, transfer:1640-1660,
--       gate template.can_give_other:1646/1705).
--   A human works around this by tapping the potion wield key, which promotes
--   the real potion from storage to primary (swap_equipment_from_storage). The
--   bot never does that cycle, so the skull stays primary and the handoff is
--   impossible.
--
-- FIX
--   Do the human's cycle FOR the bot: whenever a Necromancer bot has a real
--   (giveable) potion sitting in slot_potion storage while the non-giveable
--   skull is primary, promote the potion to primary
--   (swap_equipment_from_storage, simple_inventory_extension.lua:2434). Once the
--   real potion is primary, ALL the vanilla logic just works -- scoring, the
--   give interaction, and the bot drinking its own potion. The skull moves to
--   storage (harmless for a bot; bots don't use the Necromancer utility skull).
--   Throttled to ~1s; idempotent (once the potion is primary it has
--   can_give_other and the promote condition is false).
-- Find the nearest ALIVE hero/bot ally to `unit` (excludes self). Returns the
-- ally unit or nil. Source: side.PLAYER_AND_BOT_UNITS (side_manager.lua), the
-- same roster the vanilla bot aid-picker walks.
local function _gt_nearest_alive_ally(unit)
    local side_manager = Managers.state.side
    local side = side_manager and side_manager.side_by_unit[unit]
    if not side then
        return nil
    end
    local units = side.PLAYER_AND_BOT_UNITS
    local self_pos = POSITION_LOOKUP[unit]
    if not self_pos then
        return nil
    end
    local best, best_d
    for i = 1, #units do
        local u = units[i]
        if u ~= unit and HEALTH_ALIVE[u] then
            local p = POSITION_LOOKUP[u]
            if p then
                local d = Vector3.distance_squared(self_pos, p)
                if not best_d or d < best_d then
                    best_d = d
                    best = u
                end
            end
        end
    end
    return best
end

-- Navmesh-valid position of a unit -- the same source vanilla's teleport check
-- reads (bt_bot_conditions.lua:1232 last_position_on_navmesh). Falls back to the
-- raw position lookup if the whereabouts extension is missing.
local function _gt_navmesh_pos(target_unit)
    if not target_unit then
        return nil
    end
    local wb = ScriptUnit.has_extension(target_unit, "whereabouts_system")
    local p = wb and wb:last_position_on_navmesh()
    return p or POSITION_LOOKUP[target_unit]
end

-- FIX 1 body, extracted into a tick fn so the SINGLE PlayerBotBase.update hook
-- below can drive it alongside the other per-frame bot features. Unchanged
-- logic; see the FIX 1 header above for the full rationale + citations.
local function _gt_necro_potion_tick(self, unit, blackboard, t)
    -- Throttle: this runs per-bot per-frame; once a second is plenty.
    local next_t = blackboard._gt_necro_promote_t or 0
    if t < next_t then
        return
    end
    blackboard._gt_necro_promote_t = t + 1.0

    local career_extension = blackboard.career_extension
    if not career_extension or career_extension:career_name() ~= "bw_necromancer" then
        return
    end

    local inventory_extension = blackboard.inventory_extension
    if not inventory_extension then
        return
    end

    local primary = inventory_extension:get_slot_data("slot_potion")
    if not primary then
        return
    end

    local primary_template = inventory_extension:get_item_template(primary)
    if primary_template and primary_template.can_give_other then
        return
    end

    local stored = inventory_extension:get_additional_items("slot_potion")
    if not stored then
        return
    end

    local has_giveable_potion = false
    for i = 1, #stored do
        local item_data = stored[i]
        local template = item_data and BackendUtils.get_item_template(item_data)
        if template and template.can_give_other then
            has_giveable_potion = true
            break
        end
    end

    if has_giveable_potion then
        inventory_extension:swap_equipment_from_storage("slot_potion", SwapFromStorageType.First, primary.item_data)

        if mod:get("enable_debug_logging") then
            mod:info("[gt:bot] promoted Necromancer bot potion to primary so it can hand off / drink it")
        end
    end
end

-- ----------------------------------------------------------------------------
-- FIX 4: Bots auto pull-up from ledge-hang after a few seconds
-- ----------------------------------------------------------------------------
-- WHAT
--   The ledge-hanging character state has NO self-rescue path -- it waits for
--   another unit's `pull_up` interaction or, after
--   PlayerUnitMovementSettings.ledge_hanging.time_until_fall_down = 30s, drops
--   the hanger (player_character_state_ledge_hanging.lua:91-111). A bot left
--   hanging just hangs until a human comes back.
-- FIX
--   After the configured delay of continuous ledge-hang, do the engine's own
--   pull-up: StatusUtils.set_pulled_up_network(bot, true, helper)
--   (status_utils.lua:84). The state polls is_pulled_up() every frame (line 91)
--   and transitions to leave_ledge_hanging_pull_up. set_pulled_up needs an ALIVE
--   helper unit for its dialogue branch (generic_status_extension.lua:1462), so
--   we credit the nearest alive ally; if none is alive we skip (no one to pull
--   you up). Host-side only.
local function _gt_ledge_pullup_tick(self, unit, blackboard, t)
    local status_extension = blackboard.status_extension or ScriptUnit.has_extension(unit, "status_system")
    if not status_extension or not status_extension:get_is_ledge_hanging() then
        blackboard._gt_ledge_since = nil
        return
    end
    if status_extension:is_pulled_up() then
        blackboard._gt_ledge_since = nil
        return
    end

    local since = blackboard._gt_ledge_since
    if not since then
        blackboard._gt_ledge_since = t
        return
    end

    local delay = mod:get("gt_bot_ledge_pullup_delay") or 3.0
    if t - since < delay then
        return
    end

    local helper = _gt_nearest_alive_ally(unit)
    if not helper then
        return
    end

    StatusUtils.set_pulled_up_network(unit, true, helper)
    blackboard._gt_ledge_since = nil

    if mod:get("enable_debug_logging") then
        mod:info("[gt:bot] pulled bot up from ledge after %.1fs", delay)
    end
end

-- ----------------------------------------------------------------------------
-- FIX 5: Bots stuck on a ladder teleport to a teammate
-- ----------------------------------------------------------------------------
-- WHAT
--   Bot pathing can wedge on ladder smart-object transitions. The bot's
--   PlayerBotNavigation tracks the active transition as `_current_transition`
--   with `.type == "ladder"` and an entry timestamp `.t`
--   (player_bot_navigation.lua:276-339). A wedged bot keeps that ladder
--   transition active far longer than a normal climb.
-- FIX
--   When a bot has sat on a ladder transition longer than the configured delay,
--   teleport it to the followed teammate's last navmesh position using the same
--   primitives the vanilla teleport node uses (bt_bot_teleport_to_ally_action.lua
--   :82-98): locomotion:teleport_to + fall-damage suppression + navigation
--   :teleport. Host-side only.
local function _gt_ladder_unstick_tick(self, unit, blackboard, t)
    local nav = blackboard.navigation_extension
    local transition = nav and nav._current_transition
    if not (transition and transition.type == "ladder") then
        blackboard._gt_ladder_since = nil
        return
    end

    local since = blackboard._gt_ladder_since
    if not since then
        blackboard._gt_ladder_since = t
        return
    end

    local delay = mod:get("gt_bot_ladder_unstick_delay") or 5.0
    if t - since < delay then
        return
    end

    -- Prefer the unit the bot is following; fall back to nearest alive ally.
    local group_ext = blackboard.ai_bot_group_extension
    local follow_unit = group_ext and group_ext.data and group_ext.data.follow_unit
    local anchor = (follow_unit and HEALTH_ALIVE[follow_unit] and follow_unit) or _gt_nearest_alive_ally(unit)
    local pos = _gt_navmesh_pos(anchor)
    local locomotion = blackboard.locomotion_extension
    if not (pos and locomotion and nav) then
        return
    end

    locomotion:teleport_to(pos)
    local status_extension = blackboard.status_extension
    if status_extension then
        status_extension:set_falling_height(true, pos.z)
        status_extension:set_ignore_next_fall_damage(true)
    end
    nav:teleport(pos)
    if blackboard.ai_extension and blackboard.ai_extension.clear_failed_paths then
        blackboard.ai_extension:clear_failed_paths()
    end
    blackboard._gt_ladder_since = nil

    if mod:get("enable_debug_logging") then
        mod:info("[gt:bot] teleported bot off a stuck ladder after %.1fs", delay)
    end
end

-- ----------------------------------------------------------------------------
-- FIX 6: Bots instantly grab their targeted/pinged pickup (no walking)
-- ----------------------------------------------------------------------------
-- WHAT
--   Bots normally walk to within 3.2m before looting (BTConditions.can_loot,
--   bt_bot_conditions.lua:877). Vanilla already has a failsafe: when an ordered
--   pickup has no navmesh path, player_bot_base.lua:1606-1633 sets
--   `forced_pickup_unit`, and can_loot then bypasses the distance gate because
--   `is_forced_pickup = forced_pickup_unit == interaction_unit` short-circuits
--   the `max_dist > dist` checks (bt_bot_conditions.lua:884-890).
-- FIX
--   Make that failsafe always-on for a bot's CURRENT pickup candidate: point
--   both `interaction_unit` and `forced_pickup_unit` at the live candidate
--   (mule/ordered first, then health, then ammo). is_forced_pickup then trips
--   and the bot loots from where it stands. We skip when the bot has an aid
--   target so we never stomp a revive interaction. EXPERIMENTAL -- verify
--   in-game. Host-side only.
local function _gt_instant_pickup_tick(self, unit, blackboard, t)
    if blackboard.target_ally_need_type then
        return
    end
    local pickup = blackboard.mule_pickup or blackboard.health_pickup or blackboard.ammo_pickup
    if not (pickup and Unit.alive(pickup)) then
        return
    end
    blackboard.interaction_unit = pickup
    blackboard.forced_pickup_unit = pickup
end

-- ----------------------------------------------------------------------------
-- CONSOLIDATION SITE: _gt_bot_update_consolidated
-- ----------------------------------------------------------------------------
-- The SINGLE PlayerBotBase.update hook. VMF silently drops a second hook on the
-- same (Class, method), so every per-frame bot feature dispatches from here,
-- each gated on its own toggle. DO NOT add another PlayerBotBase.update hook --
-- add a gated `_gt_*_tick` fn above and a line below instead.
mod:hook_safe("PlayerBotBase", "update", function (self, unit, input, dt, context, t)
    local blackboard = self._blackboard
    if not blackboard then
        return
    end

    if mod:get("gt_bot_necro_potion_handoff") then
        _gt_necro_potion_tick(self, unit, blackboard, t)
    end
    if mod:get("gt_bot_ledge_pullup") then
        _gt_ledge_pullup_tick(self, unit, blackboard, t)
    end
    if mod:get("gt_bot_ladder_unstick") then
        _gt_ladder_unstick_tick(self, unit, blackboard, t)
    end
    if mod:get("gt_bot_instant_pickup") then
        _gt_instant_pickup_tick(self, unit, blackboard, t)
    end
end)

-- ----------------------------------------------------------------------------
-- FIX 2: Ironbreaker bot won't revive while its ult/ability is active
-- ----------------------------------------------------------------------------
-- WHAT
--   The Ironbreaker bot ult (player_bots_settings.lua use_ability.dr_ironbreaker)
--   has a `wait_action = { input = "defend" }` and an `end_condition` tied to
--   the `bardin_ironbreaker_activated_ability` buff (lines ~118-130). So after
--   popping the ult the bot HOLDS the ability action (blocking) for the full
--   buff duration. While that ability action runs,
--   BTConditions.can_activate_ability (bt_bot_conditions.lua:607-629) returns
--   true via the `is_using_ability` short-circuit (line 628), so the bot's
--   behaviour-tree selector stays parked on the ability node and never re-enters
--   the higher-priority revive node (bt_bot.lua:14-32). Net effect: a downed
--   ally is ignored for the whole ult duration.
--
-- FIX
--   When an ally actually needs aid, make can_activate_ability return false for
--   an Ironbreaker that is mid-ult, so the ability node yields and the revive
--   node runs. The ult is a timed BUFF applied by _run_ability
--   (career_ability_dr_ironbreaker.lua) -- it KEEPS ticking for its duration; we
--   only stop the bot from standing around blocking. The ability is on cooldown
--   after use, so can_use_activated_ability() is false and the bot won't re-pop
--   it -- it just fights/revives normally with the damage-reduction buff up.
mod:hook("BTConditions", "can_activate_ability", function (func, blackboard, args)
    local result = func(blackboard, args)

    if not result then
        return result
    end

    if not mod:get("gt_bot_ironbreaker_revive_in_ult") then
        return result
    end

    local career_extension = blackboard.career_extension
    if not career_extension or career_extension:career_name() ~= "dr_ironbreaker" then
        return result
    end

    local ability_data = blackboard.activate_ability_data
    if not (ability_data and ability_data.is_using_ability) then
        return result
    end

    -- Only yield the ult-hold for a genuine aid need (revive / ledge / hook;
    -- "knocked_down" also covers awaiting-respawn relabeled by FIX 3 below).
    if blackboard.target_ally_needs_aid then
        local need_type = blackboard.target_ally_need_type
        if need_type == "knocked_down" or need_type == "ledge" or need_type == "hook" then
            if mod:get("enable_debug_logging") then
                mod:info("[gt:bot-ib] yielding Ironbreaker ult-hold to aid ally (need=%s)", tostring(need_type))
            end
            return false
        end
    end

    return result
end)

-- ----------------------------------------------------------------------------
-- FIX 3: Bots don't rescue allies awaiting (assisted) respawn
-- ----------------------------------------------------------------------------
-- WHAT
--   PlayerBotBase._select_ally_by_utility (player_bot_base.lua:843-1008) is the
--   bot's ally-aid picker. Line 903 explicitly EXCLUDES any ally for whom
--   status_ext:is_ready_for_assisted_respawn() is true from the entire aid
--   evaluation, and no aid branch handles that state. So bots never go free a
--   teammate who is waiting to be rescued at a respawn point -- including after
--   the bot itself respawns and re-evaluates targets.
--
-- FIX
--   Wrap the picker. After the vanilla call, if it found no higher-priority aid
--   and the toggle is on, scan for an ally who IS ready for assisted respawn and
--   reachable, and return it labelled "knocked_down". The bot's revive branch
--   (bt_bot.lua:14-32, condition can_revive) then drives navigation + the
--   interact action. Crucially the revive bot-action has NO forced `input`
--   (player_bots_settings.lua revive = { aim_node="j_head", use_block_interaction
--   =true }), so bt_bot_interact_action.lua:71 fires the CONTEXTUAL interaction,
--   which the engine resolves to `assisted_respawn` on an awaiting-rescue ally
--   (interactions.lua:562, gated on is_ready_for_assisted_respawn). can_revive
--   (bt_bot_conditions.lua:735-766) accepts the relabel: it keys on need_type
--   == "knocked_down" + interaction safety, and the awaiting ally's health is 0
--   so the threat-gate (health > 0.3) is skipped.
--
--   This wrapper calls the original first, so it composes with other bot mods
--   that also hook _select_ally_by_utility. It only ADDS a target when vanilla
--   found nothing more urgent.
mod:hook("PlayerBotBase", "_select_ally_by_utility", function (func, self, unit, blackboard, breed, t)
    local ally, real_dist, need_type, look_at = func(self, unit, blackboard, breed, t)

    if not mod:get("gt_bot_rescue_awaiting") then
        return ally, real_dist, need_type, look_at
    end

    -- Never override an already-found higher/equal-priority aid.
    if need_type == "knocked_down" or need_type == "ledge" or need_type == "hook" then
        return ally, real_dist, need_type, look_at
    end

    local side_manager = Managers.state.side
    local side = side_manager and side_manager.side_by_unit[unit]
    if not side then
        return ally, real_dist, need_type, look_at
    end

    local debug_on = mod:get("enable_debug_logging")
    local player_and_bot_units = side.PLAYER_AND_BOT_UNITS
    local self_pos = POSITION_LOOKUP[unit]
    local best_unit, best_dist
    local considered, blocked_path, not_alive = 0, 0, 0

    for k = 1, #player_and_bot_units do
        local player_unit = player_and_bot_units[k]

        if player_unit ~= unit then
            local status_ext = ScriptUnit.has_extension(player_unit, "status_system")
            local ready = status_ext and status_ext:is_ready_for_assisted_respawn()

            if ready then
                -- DIAGNOSTIC (v0.2.85-dev): log every awaiting-rescue candidate with the
                -- two gates that decide whether we can rescue it, so a repro tells us
                -- exactly why no pick happens: considered=0 => the CW respawn state
                -- never sets is_ready_for_assisted_respawn; health_alive=false => the
                -- HEALTH_ALIVE gate is wrong for this state; aid_path=false => pathing
                -- to the respawn spot is disallowed.
                considered = considered + 1
                local alive = HEALTH_ALIVE[player_unit] and true or false
                local _, allowed_aid_path = self:_ally_path_allowed(unit, player_unit, t)

                if debug_on then
                    mod:info("[gt:bot-rescue] candidate idx=%d ready=true health_alive=%s aid_path=%s",
                        k, tostring(alive), tostring(allowed_aid_path and true or false))
                end

                if not alive then
                    not_alive = not_alive + 1
                elseif not allowed_aid_path then
                    blocked_path = blocked_path + 1
                else
                    local d = Vector3.distance(self_pos, POSITION_LOOKUP[player_unit])
                    if not best_dist or d < best_dist then
                        best_dist = d
                        best_unit = player_unit
                    end
                end
            end
        end
    end

    if debug_on and considered > 0 then
        local next_t = blackboard._gt_rescue_log_t or 0
        if t >= next_t then
            blackboard._gt_rescue_log_t = t + 2.0
            mod:info("[gt:bot-rescue] awaiting=%d picked=%s not_health_alive=%d path_blocked=%d prior_need=%s",
                considered, best_unit and "yes" or "no", not_alive, blocked_path, tostring(need_type))
        end
    end

    if best_unit then
        -- Relabel as knocked_down so the existing revive branch handles it; the
        -- contextual interaction resolves to assisted_respawn on this ally.
        return best_unit, best_dist, "knocked_down", false
    end

    return ally, real_dist, need_type, look_at
end)

-- ----------------------------------------------------------------------------
-- FIX 7: Tighter bot follow leash (configurable teleport distance)
-- ----------------------------------------------------------------------------
-- Vanilla teleports a bot to its follow target only at >= 40 m
-- (FOLLOW_TELEPORT_DISTANCE_SQ = 1600, bt_bot_conditions.lua:1206 + 1241). This
-- lets a configurable, tighter distance trigger the SAME teleport so bots stay
-- closer. We call the original first (the 40 m rule + all its gates still
-- apply); only if it declined do we re-check the identical gates with our
-- distance. The aid exception is preserved (target_ally_need_type / priority
-- target => never teleport), so a bot going for a revive still ignores the
-- leash. Faithful re-implementation of bt_bot_conditions.lua:1208-1241.
mod:hook("BTConditions", "should_teleport", function (func, blackboard)
    if func(blackboard) then
        return true
    end
    if not mod:get("gt_bot_follow_distance_enabled") then
        return false
    end

    local dist_m = mod:get("gt_bot_follow_distance_m") or 40.0
    if dist_m >= 40.0 then
        -- Not tighter than vanilla's 40 m; nothing to add.
        return false
    end

    local group_ext = blackboard.ai_bot_group_extension
    local follow_unit = group_ext and group_ext.data and group_ext.data.follow_unit
    if not ALIVE[follow_unit] or blackboard.has_teleported then
        return false
    end

    local self_unit = blackboard.unit
    local conflict_director = Managers.state.conflict
    local self_segment = conflict_director:get_player_unit_segment(self_unit) or 1
    local target_segment = conflict_director:get_player_unit_segment(follow_unit)
    if not target_segment or target_segment < self_segment then
        return false
    end

    local has_priority_target = blackboard.target_unit and blackboard.target_unit == blackboard.priority_target_enemy
    if blackboard.target_ally_need_type or has_priority_target then
        return false
    end

    local self_wb = ScriptUnit.has_extension(self_unit, "whereabouts_system")
    local follow_wb = ScriptUnit.has_extension(follow_unit, "whereabouts_system")
    local self_position = self_wb and self_wb:last_position_on_navmesh()
    local follow_position = follow_wb and follow_wb:last_position_on_navmesh()
    if not self_position or not follow_position then
        return false
    end

    return Vector3.distance_squared(self_position, follow_position) >= dist_m * dist_m
end)

-- ----------------------------------------------------------------------------
-- FIX 8: Don't fail the mission while a bot is still alive
-- ----------------------------------------------------------------------------
-- GameModeAdventure.evaluate_end_conditions calls
-- GameModeHelper.side_is_dead("heroes", ignore_bots = true)
-- (game_mode_adventure.lua:92), so the run is declared lost when all HUMANS are
-- down even if a bot is alive and standing. We force ignore_bots = false for the
-- "heroes" side so a living bot counts -- the mission only ends when no teammate
-- (human OR bot) remains. Pairs with "Bots rescue allies awaiting respawn". The
-- wipe check runs server-side (GameModeManager.server_update), so this is
-- effectively host-side.
mod:hook("GameModeHelper", "side_is_dead", function (func, side_name, ignore_bots)
    if mod:get("gt_bot_mission_fail_prevention") and side_name == "heroes" then
        return func(side_name, false)
    end
    return func(side_name, ignore_bots)
end)
