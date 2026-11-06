local mod = get_mod("gt")
local _gt365_policy = mod:dofile("scripts/mods/general_tweaker/_gt_bot_ale_policy")
local _gt365_smart_claims = setmetatable({}, { __mode = "k" })

-- Focused owner for the two AIBotGroupSystem pickup hooks. Extracted from
-- _gt_bot_fixes.lua so that module remains below the repository file-size gate.
-- Bots and AIBotGroupSystem are host-owned; no RPC is involved.

-- Issue #364: Bardin's Survival Ale benefits human players only. Use the exact
-- engine pickup identity rather than reserving every slot_level_event item.
local function _gt_bot_pickup_name_is_reserved(pickup_name)
    return pickup_name == "bardin_survival_ale"
end
mod._gt_bot_pickup_name_is_reserved = _gt_bot_pickup_name_is_reserved

local function _gt_bot_pickup_is_reserved(pickup_unit)
    if not (pickup_unit and Unit.alive(pickup_unit)) then
        return false
    end

    local pickup_extension = ScriptUnit.has_extension(pickup_unit, "pickup_system")
    return pickup_extension
        and _gt_bot_pickup_name_is_reserved(pickup_extension.pickup_name)
        and not _gt365_smart_claims[pickup_unit]
        or false
end
mod._gt_bot_pickup_is_reserved = _gt_bot_pickup_is_reserved

mod._gt_rt_register("gt364_survival_ale_reserved_for_humans", function()
    local is_reserved = mod._gt_bot_pickup_name_is_reserved
    if not is_reserved("bardin_survival_ale") then
        return "bardin_survival_ale is not reserved"
    end
    if is_reserved("damage_boost_potion") or is_reserved("frag_grenade_t1") or is_reserved(nil) then
        return "ordinary mule pickup was incorrectly reserved"
    end
end)

-- ----------------------------------------------------------------------------
-- FIX 10 (#297 item 8, v0.2.182-dev): Greedy pickup -- bots grab potions/bombs/
-- health items even while a nearby human's matching slot is empty
-- ----------------------------------------------------------------------------
-- WHAT (all citations into the decompiled vanilla source, verified 2026-07-04)
--   Mule items (potions/bombs/etc.): AIBotGroupSystem._update_mule_pickups
--   (ai_bot_group_system.lua:1891-2048) counts `num_players` = alive humans
--   whose `slot_name` slot is EMPTY with an available pickup within 20 m of
--   them (max_pickup_dist_sq = 400, :1894; count loop :1983-2010) and only
--   auto-assigns `blackboard.mule_pickup` to bots when `num_players == 0`
--   (:2012). So while ANY nearby human could still take the item, every bot
--   leaves it on the ground -- even when the humans don't want it.
--
--   Health items: AIBotGroupSystem._update_health_pickups (:2050-2361) gathers
--   the side's health pickups (:2063-2073, split into can_heal_self items and
--   auxiliary slot items) and then RESERVES one item per alive human whose
--   slot_healthkit is empty: the human's nearest item is REMOVED from the
--   assignable pool (:2104-2141; heal items :2116-2127, aux :2128-2140 -- with
--   NO distance cap on the human). Only the leftovers are permutation-assigned
--   to bots (find_permutation :2216 / :2309), which writes bb.health_pickup
--   (:2227 / :2319) and sets bb.allowed_to_take_health_pickup = true only when
--   the item is within MAX_PICKUP_RANGE = 15 of the bot's follow position
--   (:1847; range check :2236 / :2328). Every bot's allowed flag is force-reset
--   to false at the top of the bot loop (:2164). Net effect: with 4 medkits on
--   the floor and 4 empty-slot humans, the bots claim nothing.
--
-- FIX
--   hook_safe post-passes on BOTH functions. Fresh (Class, method) pairs --
--   duplicate-hook pre-flight grep of the whole mod dir (2026-07-04) found the
--   only other AIBotGroupSystem hooks are _assign_destination_points (FIX 9,
--   _gt_bot_fixes.lua) and _update_urgent_targets (_gt_improved_bot_combat.lua). When
--   the master + gt_bot_greedy_pickup are on, re-run the vanilla assignment
--   logic WITHOUT the human-slot gates, assigning only to bots vanilla left
--   empty-handed and honoring vanilla's own distance rules, so bots claim the
--   items and (via vanilla's give-to-ally utility scoring,
--   player_bot_base.lua:881-917, plus FIX 6's instant grab) carry and hand
--   them to players instead of leaving floor loot to despawn behind the team.
--
--   KEPT INTACT (deliberately):
--   * force_use_health_pickup (:2355-2358) is never written by us -- a bot
--     still only SELF-uses its medkit when every human is healthier than the
--     lowest-HP bot, and :2145-2146 zeroes lowest_human_hp_percent while any
--     human is knocked down / wounded, which blocks bot self-healing while a
--     human is dying nearby. Greedy changes who CARRIES the item, not who gets
--     healed with it.
--   * Vanilla's per-tick retention/cleanup still applies: our mule assignment
--     survives the alive+follow-distance retention check (:1948) and is
--     re-marked assigned (:1961); health assignments are wiped and re-derived
--     by vanilla every tick (:2164, :2256-2266), so flipping the toggle off
--     reverts within one tick (a residual mule claim just gets consumed or
--     dropped by the same vanilla rules as any ordered pickup).
--   * The allowed_to_take_health_pickup follow-range gate (:2236) is mirrored,
--     so greedy bots still only fetch items near the team's path -- no
--     cross-map detours.
--   Host-side only (bots + this system are server-side); no RPC; nil-guarded.
GT_BOT_GREEDY_PICKUP_MARKER_v0_2_182 = "gt-bot-greedy-pickup-mule-health-postpass"

local function _gt_greedy_pickup_on()
    return mod:get("gt_bot_behavior_improvements") and mod:get("gt_bot_greedy_pickup")
end

-- Issue #365: an ale may leave the #364 human reservation only while every
-- active member of this side has all three copies of both ale sub-buffs and
-- each refreshed stack has strictly more than half of its duration remaining.
-- The pickup itself auto-wields and invokes action_one/default, so vanilla owns
-- consumption (pickups.lua:741-758); this code only makes one eligible pickup a
-- bot's normal mule target. The census is capped at the side roster and cached
-- for half a second, with every missing/invalid engine surface failing closed.
local _GT365_MAX_STACKS = 3
local _GT365_MIN_REMAINING = 0.5
local _GT365_SCAN_INTERVAL = 0.5
local _gt365_ready_cache = {}

local function _gt365_enabled()
    return mod:get("gt_bot_behavior_improvements") and mod:get("gt_bot_smart_ale")
end

local function _gt365_stack_observation(buff_extension, buff_name, t)
    local stacks = buff_extension:get_stacking_buff(buff_name)
    if type(stacks) ~= "table" or #stacks == 0 then
        return 0, nil
    end

    -- refresh_durations=true refreshes every existing stack together
    -- (buff_extension.lua:520-533), so the top stack is representative.
    local top = stacks[#stacks]
    local duration = top and tonumber(top.duration)
    local end_time = top and tonumber(top.end_time)
    if not end_time and top and duration and tonumber(top.start_time) then
        end_time = tonumber(top.start_time) + duration
    end
    if not duration or duration <= 0 or not end_time then
        return #stacks, nil
    end

    return #stacks, (end_time - t) / duration
end

local function _gt365_observe_team(side, t)
    local units = side and side.PLAYER_AND_BOT_UNITS
    if type(units) ~= "table" or #units == 0 then
        return nil
    end

    local observations = {}
    for i = 1, #units do
        local unit = units[i]
        if not (unit and Unit.alive(unit)) then
            return nil
        end
        local buff_extension = ScriptUnit.has_extension(unit, "buff_system")
        if not (buff_extension and type(buff_extension.get_stacking_buff) == "function") then
            return nil
        end
        local defence_stacks, defence_remaining = _gt365_stack_observation(buff_extension, "ale_defence", t)
        local attack_stacks, attack_remaining = _gt365_stack_observation(buff_extension, "ale_attack_speed", t)
        observations[#observations + 1] = {
            defence_stacks = defence_stacks,
            attack_stacks = attack_stacks,
            defence_remaining_fraction = defence_remaining,
            attack_remaining_fraction = attack_remaining,
        }
    end
    return observations
end

local function _gt365_side_ready(side_id, t)
    local cached = _gt365_ready_cache[side_id]
    if cached and t < cached.next_scan then
        return cached.ready
    end

    local ready = false
    local side_manager = Managers.state.side
    local side = side_manager and side_manager:get_side(side_id)
    if side then
        local ok, observations = pcall(_gt365_observe_team, side, t)
        ready = ok and _gt365_policy.team_ready(
            observations, _GT365_MAX_STACKS, _GT365_MIN_REMAINING) or false
    end
    _gt365_ready_cache[side_id] = { ready = ready, next_scan = t + _GT365_SCAN_INTERVAL }
    return ready
end

local function _gt365_pickup_is_ale(pickup_unit)
    if not (pickup_unit and Unit.alive(pickup_unit)) then
        return false
    end
    local extension = ScriptUnit.has_extension(pickup_unit, "pickup_system")
    return extension and extension.pickup_name == "bardin_survival_ale" or false
end

local function _gt_claimed_mule_pickups(side_bot_data)
    local claimed = {}
    for _, data in pairs(side_bot_data or {}) do
        local bb = data.blackboard
        if bb and bb.mule_pickup then
            claimed[bb.mule_pickup] = true
        end
        if data.pickup_orders then
            for _, order in pairs(data.pickup_orders) do
                if order and order.unit then
                    claimed[order.unit] = true
                end
            end
        end
    end
    return claimed
end

local function _gt365_assign_smart_ale(side_id, side_bot_data, side_available, t, max_pickup_dist_sq)
    if not (_gt365_enabled() and _gt365_side_ready(side_id, t)) then
        return
    end

    local available_ales = side_available and side_available.slot_level_event
    if not available_ales then
        return
    end

    local claimed = _gt_claimed_mule_pickups(side_bot_data)
    for bot_unit, data in pairs(side_bot_data) do
        local blackboard = data.blackboard
        local inventory_extension = blackboard and blackboard.inventory_extension
        local order = data.pickup_orders and data.pickup_orders.slot_level_event
        local has_item = inventory_extension and inventory_extension:get_slot_data("slot_level_event")
        local can_hold_more = inventory_extension and inventory_extension:can_store_additional_item("slot_level_event")
        if inventory_extension and not blackboard.mule_pickup
                and (not has_item or can_hold_more) and not order then
            local best_pickup, best_distance_sq
            for pickup_unit in pairs(available_ales) do
                if not claimed[pickup_unit] and _gt365_pickup_is_ale(pickup_unit) then
                    local pickup_pos = POSITION_LOOKUP[pickup_unit]
                    local bot_pos = POSITION_LOOKUP[bot_unit]
                    if pickup_pos and bot_pos then
                        local bot_distance_sq = Vector3.distance_squared(bot_pos, pickup_pos)
                        local follow_distance_sq = Vector3.distance_squared(data.follow_position or bot_pos, pickup_pos)
                        if follow_distance_sq < max_pickup_dist_sq
                                and (not best_distance_sq or bot_distance_sq < best_distance_sq) then
                            best_pickup = pickup_unit
                            best_distance_sq = bot_distance_sq
                        end
                    end
                end
            end
            if best_pickup then
                -- Narrow exception to #364: only this approved live unit stops
                -- being "reserved" for the instant-pickup consumer this frame.
                _gt365_smart_claims[best_pickup] = true
                blackboard.mule_pickup = best_pickup
                blackboard.mule_pickup_dist_squared = best_distance_sq
                claimed[best_pickup] = true
            end
        end
    end
end

mod._gt_rt_register("issue365_smart_bot_ale_policy", function()
    local ready = {
        { defence_stacks = 3, attack_stacks = 3,
          defence_remaining_fraction = 0.51, attack_remaining_fraction = 1 },
    }
    if not _gt365_policy.team_ready(ready, 3, 0.5) then
        return "valid full-stack team rejected"
    end
    ready[1].attack_remaining_fraction = 0.5
    if _gt365_policy.team_ready(ready, 3, 0.5) then
        return "50-percent boundary was not strict"
    end
    if type(_gt365_assign_smart_ale) ~= "function" then
        return "smart ale assignment missing"
    end
end)

local function _gt_clear_reserved_mule_claims(bot_ai_data)
    if not bot_ai_data then
        return
    end

    for side_id = 1, #bot_ai_data do
        local side_bot_data = bot_ai_data[side_id]
        if side_bot_data then
            for _, data in pairs(side_bot_data) do
                local blackboard = data.blackboard
                local mule_pickup = blackboard and blackboard.mule_pickup
                if _gt_bot_pickup_is_reserved(mule_pickup) then
                    if blackboard.interaction_unit == mule_pickup then
                        blackboard.interaction_unit = nil
                    end
                    if blackboard.forced_pickup_unit == mule_pickup then
                        blackboard.forced_pickup_unit = nil
                    end
                    blackboard.mule_pickup = nil
                    blackboard.mule_pickup_dist_squared = nil
                end
            end
        end
    end
end

mod:hook_safe("AIBotGroupSystem", "_update_mule_pickups", function (self, dt, t)
    local bot_ai_data = self._bot_ai_data
    -- Revoke last tick's narrow exemptions before clearing any ale claim that
    -- no longer meets the fresh/cached all-team policy.
    _gt365_smart_claims = setmetatable({}, { __mode = "k" })
    -- Reservation is unconditional: vanilla can assign mule pickups when no
    -- human has an empty matching slot, even when gt's greedy option is off.
    _gt_clear_reserved_mule_claims(bot_ai_data)

    local available_mule_pickups = self._available_mule_pickups
    if not (bot_ai_data and available_mule_pickups) then
        return
    end
    local max_pickup_dist_sq = 400   -- vanilla's own local (ai_bot_group_system.lua:1894)

    for side_id = 1, #bot_ai_data do
        local side_bot_data = bot_ai_data[side_id]
        local side_available = available_mule_pickups[side_id]
        if side_bot_data and side_available then
            -- Rebuild the "already claimed" set (vanilla's ASSIGNED_MULE_PICKUPS_TEMP
            -- :1889 is a file-local we cannot read): every pickup some bot's
            -- blackboard already targets plus every explicit pickup order.
            local claimed = _gt_claimed_mule_pickups(side_bot_data)

            -- Mimic the vanilla assignment loop (:2013-2043) minus the
            -- num_players == 0 gate (:2012). available_pickups was already
            -- pruned of dead/expired entries by the vanilla pass this tick
            -- (:1975-1981); Unit.alive is re-checked anyway (cheap, safe).
            for slot_name, available_pickups in pairs(side_available) do
                for bot_unit, data in pairs(side_bot_data) do
                    local blackboard = data.blackboard
                    local inventory_extension = blackboard and blackboard.inventory_extension
                    if inventory_extension then
                        local order = data.pickup_orders and data.pickup_orders[slot_name]
                        local has_item = inventory_extension:get_slot_data(slot_name)
                        local can_hold_more = inventory_extension:can_store_additional_item(slot_name)

                        -- Same per-bot eligibility as vanilla (:2020).
                        if _gt_greedy_pickup_on() and not blackboard.mule_pickup and (not has_item or can_hold_more) and not order then
                            local best_pickup_dist_sq = math.huge
                            local best_pickup

                            for pickup_unit in pairs(available_pickups) do
                                if not claimed[pickup_unit] and Unit.alive(pickup_unit) and not _gt_bot_pickup_is_reserved(pickup_unit) then
                                    local pickup_pos = POSITION_LOOKUP[pickup_unit]
                                    local bot_pos = POSITION_LOOKUP[bot_unit]
                                    if pickup_pos and bot_pos then
                                        -- Vanilla distance rules (:2028-2031): the pickup must
                                        -- lie within 20 m of the bot's follow point (400 sq);
                                        -- nearest-to-the-bot wins.
                                        local bot_dist_sq = Vector3.distance_squared(bot_pos, pickup_pos)
                                        local follow_dist_sq = Vector3.distance_squared(data.follow_position or bot_pos, pickup_pos)
                                        if follow_dist_sq < max_pickup_dist_sq and bot_dist_sq < best_pickup_dist_sq then
                                            best_pickup = pickup_unit
                                            best_pickup_dist_sq = bot_dist_sq
                                        end
                                    end
                                end
                            end

                            if best_pickup then
                                -- Same blackboard writes as vanilla (:2038-2041).
                                blackboard.mule_pickup = best_pickup
                                blackboard.mule_pickup_dist_squared = best_pickup_dist_sq
                                claimed[best_pickup] = true

                                mod:debug("[gt:bot-greedy] bot claimed a %s mule pickup vanilla left for empty-slot humans", tostring(slot_name))
                            end
                        end
                    end
                end
            end

            -- Consolidated into this singleton AIBotGroupSystem hook. This path
            -- is independent of generic greedy pickup but still sits under the
            -- Bot Behavior Improvements master and its own default-off toggle.
            _gt365_assign_smart_ale(side_id, side_bot_data, side_available, t, max_pickup_dist_sq)
        end
    end
end)

mod:hook_safe("AIBotGroupSystem", "_update_health_pickups", function (self, dt, t)
    if not _gt_greedy_pickup_on() then
        return
    end
    local bot_ai_data = self._bot_ai_data
    local available_health_pickups = self._available_health_pickups
    if not (bot_ai_data and available_health_pickups) then
        return
    end
    local max_pickup_range = 15   -- vanilla's MAX_PICKUP_RANGE (ai_bot_group_system.lua:1847)

    for side_id = 1, #bot_ai_data do
        local side_bot_data = bot_ai_data[side_id]
        local available_pickups = available_health_pickups[side_id]
        if side_bot_data and available_pickups then
            -- "Already claimed" = vanilla's own assignments this tick
            -- (bb.health_pickup written at :2227 / :2252 / :2319) plus explicit
            -- slot_healthkit pickup orders (:2080-2096).
            local claimed = {}
            for _, data in pairs(side_bot_data) do
                local bb = data.blackboard
                if bb and bb.health_pickup then
                    claimed[bb.health_pickup] = true
                end
                local reservation = data.pickup_orders and data.pickup_orders.slot_healthkit
                if reservation and reservation.unit then
                    claimed[reservation.unit] = true
                end
            end

            -- Assign the leftovers -- exactly the items the human-reservation
            -- pass (:2104-2141) withheld from the bot permutation solver -- to
            -- bots vanilla left empty-handed. available_pickups was pruned of
            -- dead/expired entries by the vanilla pass this tick (:2063-2065).
            for bot_unit, data in pairs(side_bot_data) do
                local bb = data.blackboard
                local inventory_extension = bb and bb.inventory_extension
                local status_ext = data.status_extension
                -- Same bot eligibility as vanilla's valid-bot filter (:2174):
                -- alive, not parked at a respawn point, with room in
                -- slot_healthkit (empty, or stackable per can_store_additional_item).
                if inventory_extension and not bb.health_pickup
                        and HEALTH_ALIVE[bot_unit]
                        and not (status_ext and status_ext:is_ready_for_assisted_respawn()) then
                    local has_item = inventory_extension:get_slot_data("slot_healthkit")
                    local can_hold_more = inventory_extension:can_store_additional_item("slot_healthkit")
                    if not has_item or can_hold_more then
                        local bot_pos = POSITION_LOOKUP[bot_unit]
                        local best_pickup, best_dist
                        if bot_pos then
                            for pickup_unit in pairs(available_pickups) do
                                if not claimed[pickup_unit] and Unit.alive(pickup_unit) then
                                    local pickup_pos = POSITION_LOOKUP[pickup_unit]
                                    if pickup_pos then
                                        local d = Vector3.distance(bot_pos, pickup_pos)
                                        if not best_dist or d < best_dist then
                                            best_dist = d
                                            best_pickup = pickup_unit
                                        end
                                    end
                                end
                            end
                        end

                        if best_pickup then
                            -- Same blackboard writes as vanilla (:2227-2242),
                            -- INCLUDING the follow-range gate on
                            -- allowed_to_take_health_pickup (:2236): greedy bots
                            -- still only fetch items within 15 m of the team's
                            -- path, never detouring across the map.
                            bb.health_pickup = best_pickup
                            bb.health_dist = best_dist
                            bb.health_pickup_valid_until = math.huge
                            claimed[best_pickup] = true

                            local pickup_pos = POSITION_LOOKUP[best_pickup]
                            local follow_pos = data.follow_position
                            local ref_dist = (follow_pos and pickup_pos) and Vector3.distance(follow_pos, pickup_pos) or best_dist
                            bb.allowed_to_take_health_pickup = ref_dist < max_pickup_range

                            if bb.allowed_to_take_health_pickup then
                                mod:debug("[gt:bot-greedy] bot claimed a health pickup vanilla reserved for empty-slot humans (%.1fm)", best_dist)
                            end
                        end
                    end
                end
            end
        end
    end
end)
