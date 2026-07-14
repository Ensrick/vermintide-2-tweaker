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

return M
