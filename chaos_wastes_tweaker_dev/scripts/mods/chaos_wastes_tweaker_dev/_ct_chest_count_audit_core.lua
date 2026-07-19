-- Engine-free classifier for the settled Chest-of-Trials count audit (#349).
-- `actual` is counted at DeusCursedChestExtension.extensions_ready; `census`
-- is counted after PickupSystem._spawn_pickup returns. Comparing them only
-- after the spawn pass settles distinguishes pickup-path and raw level units.

local M = {}

function M.begin(state, level_id)
    if type(state) ~= "table" then return end
    state.level_id = level_id
    state.actual = 0
    state.finalized = false
end

function M.appeared(state, level_id)
    if type(state) ~= "table" then return nil end
    if state.level_id ~= level_id then M.begin(state, level_id) end
    state.actual = state.actual + 1
    return state.actual
end

function M.classify(actual, cap, census)
    if type(actual) ~= "number" or type(cap) ~= "number" or type(census) ~= "number" then
        return "invalid"
    end
    if actual > cap then
        if actual > census then return "over_cap_raw_level_units" end
        if actual == census then return "over_cap_pickup_path" end
        return "over_cap_count_order_mismatch"
    end
    if actual > census then return "within_cap_raw_level_units" end
    if actual < census then return "within_cap_count_order_mismatch" end
    return "within_cap_pickup_path"
end

function M.finalize(state, level_id, cap, census)
    if type(state) ~= "table" or state.level_id ~= level_id or state.finalized then
        return nil
    end
    state.finalized = true
    return M.classify(state.actual, cap, census), state.actual
end

-- issue 132 / issue 60 (v0.7.298-dev): pure cross-path reconciliation planner.
-- `appearance` is the per-mission list of chest units in extensions_ready order
-- (every spawn path); `pickup_set` is the set (unit -> true) of units that came
-- through PickupSystem._spawn_pickup (provably unit_spawner-owned network
-- pickups, the only class the engine's own delete path covers -
-- pickup_system.lua:1451-1455 mark_for_deletion). `cap` is the host's effective
-- cursed-chest cap. `is_alive` / `is_prunable` are injected predicates
-- (Unit.alive / state-still-WAITING at the live site; plain functions in tests).
-- Returns a plan table: `prune` = units to delete, chosen from the END of the
-- appearance order so the earliest-placed chests survive; `alive_n` = live
-- count before pruning; `over_n` = how many over cap; `unprunable_n` = over-cap
-- residue that cannot be safely deleted (raw baked level units or non-WAITING
-- chests). Never plans a prune below the cap and never plans units outside
-- `pickup_set`.
function M.reconcile_plan(appearance, pickup_set, cap, is_alive, is_prunable)
    local plan = { prune = {}, alive_n = 0, over_n = 0, unprunable_n = 0 }
    if type(appearance) ~= "table" or type(pickup_set) ~= "table"
            or type(cap) ~= "number" or cap < 0 then
        return plan
    end
    local alive = {}
    for i = 1, #appearance do
        local u = appearance[i]
        if u ~= nil and (not is_alive or is_alive(u)) then
            alive[#alive + 1] = u
        end
    end
    plan.alive_n = #alive
    local excess = #alive - cap
    if excess <= 0 then return plan end
    plan.over_n = excess
    for i = #alive, 1, -1 do
        if #plan.prune >= excess then break end
        local u = alive[i]
        if pickup_set[u] and (not is_prunable or is_prunable(u)) then
            plan.prune[#plan.prune + 1] = u
        end
    end
    plan.unprunable_n = excess - #plan.prune
    return plan
end

return M
