local mod = get_mod("gt_dev")
local _gt347_core = mod:dofile("scripts/mods/general_tweaker_dev/_gt_chest_pickup_probe_core")
local _gt347_state = _gt347_core.new()
local _gt347_tracked = setmetatable({}, { __mode = "k" })

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
    return pickup_extension and _gt_bot_pickup_name_is_reserved(pickup_extension.pickup_name) or false
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

-- Issue #347 diagnostic: ordinary chest contents live on the pickup path, but
-- vanilla's human interactor explicitly rejects a pickup when
-- GenericUnitInteractorExtension._check_if_interactable_in_chest raycasts a
-- `filter_interactable_in_chest` collision. Bots use the exclusive-interaction
-- path, which bypasses that human check. We therefore need runtime evidence to
-- distinguish four different failures: absent from AIBotGroupSystem's available
-- set, no navmesh approach, false can_loot, or failed consumption. One explicit
-- host command arms at most 32 classification raycasts and 16 deduplicated log
-- records. No blackboard, interaction, pickup, or chest state is mutated.
local function _gt347_record(identity, phase, fmt, ...)
    local stored, capped = _gt347_core.record(_gt347_state, identity, phase, {})
    if stored then
        pcall(printf, "[gt:347] phase=%s " .. fmt, tostring(phase), ...)
    end
    if capped then
        pcall(printf, "[gt:347] trace complete records=%d classifications=%d",
            _gt347_state.count, _gt347_state.classifications)
    end
end

local function _gt347_pickup_name(pickup_unit)
    local ext = pickup_unit and Unit.alive(pickup_unit)
        and ScriptUnit.has_extension(pickup_unit, "pickup_system")
    return ext and ext.pickup_name or "?"
end

local function _gt347_is_inside_chest(bot_unit, blackboard, pickup_unit)
    local identity = tostring(pickup_unit)
    if not _gt347_core.take_classification(_gt347_state, identity) then
        return false
    end

    local interactor = blackboard and blackboard.interaction_extension
    local bot_pos = bot_unit and POSITION_LOOKUP[bot_unit]
    if not (interactor and bot_pos
            and type(interactor._check_if_interactable_in_chest) == "function") then
        return false
    end

    local ok, inside = pcall(interactor._check_if_interactable_in_chest,
        interactor, pickup_unit, bot_pos)
    return ok and inside == true
end

local function _gt347_probe_available(self, category, available_by_side)
    if not _gt347_state.armed then
        return
    end

    local total = 0
    for _, side_available in pairs(available_by_side or {}) do
        if category == "mule" then
            for _, pickups in pairs(side_available or {}) do
                for _ in pairs(pickups or {}) do total = total + 1 end
            end
        else
            for _ in pairs(side_available or {}) do total = total + 1 end
        end
    end
    _gt347_record("census", category .. "_census_" .. total,
        "category=%s available=%d", category, total)

    local bot_ai_data = self and self._bot_ai_data
    for side_id, side_available in pairs(available_by_side or {}) do
        local side_bots = bot_ai_data and bot_ai_data[side_id]
        if side_bots then
            for bot_unit, data in pairs(side_bots) do
                local blackboard = data and data.blackboard
                local function inspect(pickup_unit)
                    if pickup_unit and Unit.alive(pickup_unit)
                            and _gt347_is_inside_chest(bot_unit, blackboard, pickup_unit) then
                        _gt347_tracked[pickup_unit] = true
                        local assigned = category == "mule"
                            and blackboard.mule_pickup == pickup_unit
                            or category == "health" and blackboard.health_pickup == pickup_unit
                        local pickup_pos = POSITION_LOOKUP[pickup_unit]
                        local bot_pos = POSITION_LOOKUP[bot_unit]
                        local dist = pickup_pos and bot_pos and Vector3.distance(bot_pos, pickup_pos) or -1
                        _gt347_record(tostring(pickup_unit), "available_inside_chest",
                            "category=%s pickup=%s assigned=%s dist=%.2f",
                            category, tostring(_gt347_pickup_name(pickup_unit)),
                            tostring(assigned), dist)
                    end
                end

                if category == "mule" then
                    for _, pickups in pairs(side_available or {}) do
                        for pickup_unit in pairs(pickups or {}) do inspect(pickup_unit) end
                    end
                else
                    for pickup_unit in pairs(side_available or {}) do inspect(pickup_unit) end
                end
                break -- one bot perspective is sufficient for the chest raycast
            end
        end
    end
end

mod:command("gt_chest_pickup_probe", "Arm one bounded closed-chest bot-pickup trace", function()
    if not (Managers.player and Managers.player.is_server) then
        mod:echo("[gt] Closed-chest pickup probe must be armed by the host.")
        return
    end
    _gt347_core.arm(_gt347_state)
    _gt347_tracked = setmetatable({}, { __mode = "k" })
    mod:echo("[gt] Closed-chest pickup trace armed. Approach one closed chest with a bot, wait, then open it.")
    pcall(printf, "[gt:347] ARMED max_records=%d max_classifications=%d instant_pickup=%s greedy_pickup=%s",
        _gt347_core.MAX_RECORDS, _gt347_core.MAX_CLASSIFICATIONS,
        tostring(mod:get("gt_bot_instant_pickup")), tostring(mod:get("gt_bot_greedy_pickup")))
end)

-- Duplicate-hook preflight: no existing gt hook targets either pair. The first
-- wrapper observes the nav result; the second observes vanilla's boolean and
-- returns it unchanged.
mod:hook("PlayerBotBase", "_find_pickup_position_on_navmesh", function(func, self, nav_world, self_pos, pickup_unit, pickup_attempt)
    local result = func(self, nav_world, self_pos, pickup_unit, pickup_attempt)
    if _gt347_state.armed and _gt347_tracked[pickup_unit] then
        _gt347_record(tostring(pickup_unit), "nav_result",
            "pickup=%s result=%s blacklist=%s path_failed=%s",
            tostring(_gt347_pickup_name(pickup_unit)), tostring(result ~= nil),
            tostring(pickup_attempt and pickup_attempt.blacklist),
            tostring(pickup_attempt and pickup_attempt.path_failed))
    end
    return result
end)

mod:hook(BTConditions, "can_loot", function(func, blackboard)
    local result = func(blackboard)
    local pickup_unit = blackboard and blackboard.interaction_unit
    if _gt347_state.armed and _gt347_tracked[pickup_unit] then
        _gt347_record(tostring(pickup_unit), "can_loot",
            "pickup=%s result=%s forced=%s health=%s mule=%s ammo=%s",
            tostring(_gt347_pickup_name(pickup_unit)), tostring(result),
            tostring(blackboard.forced_pickup_unit == pickup_unit),
            tostring(blackboard.health_pickup == pickup_unit),
            tostring(blackboard.mule_pickup == pickup_unit),
            tostring(blackboard.ammo_pickup == pickup_unit))
    end
    return result
end)

mod:hook_safe(InteractionDefinitions.pickup_object.server, "stop", function(world, interactor_unit, interactable_unit, data, config, t, result)
    if _gt347_state.armed and _gt347_tracked[interactable_unit] then
        _gt347_record(tostring(interactable_unit), "pickup_stop",
            "pickup=%s result=%s", tostring(_gt347_pickup_name(interactable_unit)),
            tostring(InteractionResult[result] or result))
    end
end)

mod:hook_safe(InteractionDefinitions.chest.server, "stop", function(world, interactor_unit, interactable_unit, data, config, t, result)
    if _gt347_state.armed then
        _gt347_record(tostring(interactable_unit), "chest_stop",
            "result=%s", tostring(InteractionResult[result] or result))
    end
end)

mod._gt_rt_register("issue347_closed_chest_pickup_diagnostics", function()
    local ok = _gt347_core.MAX_RECORDS == 16
        and _gt347_core.MAX_CLASSIFICATIONS == 32
        and type(_gt347_probe_available) == "function"
    return ok, ok and "bounded availability/nav/loot/consume trace wired" or "closed-chest trace wiring incomplete"
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
    -- Reservation is unconditional: vanilla can assign mule pickups when no
    -- human has an empty matching slot, even when gt's greedy option is off.
    _gt_clear_reserved_mule_claims(bot_ai_data)

    _gt347_probe_available(self, "mule", self._available_mule_pickups)

    if not _gt_greedy_pickup_on() then
        return
    end
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
            local claimed = {}
            for _, data in pairs(side_bot_data) do
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
                        if not blackboard.mule_pickup and (not has_item or can_hold_more) and not order then
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
        end
    end
end)

mod:hook_safe("AIBotGroupSystem", "_update_health_pickups", function (self, dt, t)
    _gt347_probe_available(self, "health", self._available_health_pickups)
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
