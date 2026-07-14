-- Pure state-copy policy for issue #465. Runtime hooks supply the DeusRunState;
-- this module owns bounded cloning, wire-safe filtering, and the exact fields
-- transferred between a departing human, their replacement bot, and a joiner.
local M = {}

local MAX_DEPTH = 6
local MAX_ENTRIES = 256

local function clone(value, depth, budget)
    if type(value) ~= "table" then return value end
    depth = depth or 0
    if depth >= MAX_DEPTH or budget.left <= 0 then return nil end

    local out = {}
    for key, child in pairs(value) do
        if budget.left <= 0 then break end
        budget.left = budget.left - 1
        out[clone(key, depth + 1, budget)] = clone(child, depth + 1, budget)
    end
    return out
end

function M.profile_key(profile_index, career_index)
    if type(profile_index) ~= "number" or profile_index <= 0 then return nil end
    if type(career_index) ~= "number" or career_index <= 0 then return nil end
    return tostring(profile_index) .. ":" .. tostring(career_index)
end

function M.same_identity(a_profile, a_career, b_profile, b_career)
    return M.profile_key(a_profile, a_career) ~= nil
        and a_profile == b_profile and a_career == b_career
end

function M.capture(run_state, peer_id, local_player_id, profile_index, career_index)
    if not run_state or not peer_id or not local_player_id or not M.profile_key(profile_index, career_index) then
        return nil, "missing identity or run state"
    end

    local budget = { left = MAX_ENTRIES }
    return {
        profile_index = profile_index,
        career_index = career_index,
        power_ups = clone(run_state:get_player_power_ups(peer_id, local_player_id, profile_index, career_index) or {}, 0, budget) or {},
        persistent_buffs = clone(run_state:get_player_persistent_buffs(peer_id, local_player_id, profile_index, career_index) or {}, 0, budget) or {},
        coins = run_state:get_player_soft_currency(peer_id, local_player_id) or 0,
        slot_melee = run_state:get_player_loadout(peer_id, local_player_id, profile_index, career_index, "slot_melee"),
        slot_ranged = run_state:get_player_loadout(peer_id, local_player_id, profile_index, career_index, "slot_ranged"),
    }
end

function M.wire_safe_copy(snapshot, wire_safe, is_modded_power_up, is_ct_buff)
    if not snapshot then return nil, 0, 0 end
    local budget = { left = MAX_ENTRIES }
    local out = clone(snapshot, 0, budget) or {}
    if wire_safe then return out, 0, 0 end

    local power_ups, removed_power_ups = {}, 0
    for i = 1, #(out.power_ups or {}) do
        local power_up = out.power_ups[i]
        if power_up and is_modded_power_up and is_modded_power_up(power_up.name) then
            removed_power_ups = removed_power_ups + 1
        else
            power_ups[#power_ups + 1] = power_up
        end
    end
    out.power_ups = power_ups

    local persistent, removed_buffs = {}, 0
    for i = 1, #(out.persistent_buffs or {}) do
        local buff_name = out.persistent_buffs[i]
        if is_ct_buff and is_ct_buff(buff_name) then
            removed_buffs = removed_buffs + 1
        else
            persistent[#persistent + 1] = buff_name
        end
    end
    out.persistent_buffs = persistent
    return out, removed_power_ups, removed_buffs
end

function M.apply(run_state, peer_id, local_player_id, profile_index, career_index, snapshot, coin_override)
    if not run_state or not snapshot or not M.profile_key(profile_index, career_index) then
        return false, "missing target identity, snapshot, or run state"
    end

    run_state:set_player_power_ups(peer_id, local_player_id, profile_index, career_index, snapshot.power_ups or {})
    run_state:set_player_persistent_buffs(peer_id, local_player_id, profile_index, career_index, snapshot.persistent_buffs or {})
    run_state:set_player_loadout(peer_id, local_player_id, profile_index, career_index, "slot_melee", snapshot.slot_melee)
    run_state:set_player_loadout(peer_id, local_player_id, profile_index, career_index, "slot_ranged", snapshot.slot_ranged)
    run_state:set_player_soft_currency(peer_id, local_player_id, coin_override == nil and snapshot.coins or coin_override)
    run_state:set_profile_initialized(peer_id, local_player_id, profile_index, career_index, true)
    run_state:set_peer_initialized(peer_id, true)
    return true
end

return M
