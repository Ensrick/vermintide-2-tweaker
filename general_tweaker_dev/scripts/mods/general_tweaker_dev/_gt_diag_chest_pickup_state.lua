-- _gt_chest_pickup_probe_core.lua -- bounded issue #347 trace state.
--
-- Engine-free planner used by the live bot-pickup probe and offline tests.
-- One explicit arm owns a finite raycast budget and a deduplicated record cap.

local M = {}

M.MAX_RECORDS = 16
M.MAX_CLASSIFICATIONS = 32

function M.new()
    return {
        armed = false,
        count = 0,
        classifications = 0,
        seen = {},
        classified = {},
        records = {},
    }
end

function M.arm(state)
    state.armed = true
    state.count = 0
    state.classifications = 0
    state.seen = {}
    state.classified = {}
    state.records = {}
end

function M.take_classification(state, identity)
    if not state.armed or state.classified[identity]
            or state.classifications >= M.MAX_CLASSIFICATIONS then
        return false
    end

    state.classified[identity] = true
    state.classifications = state.classifications + 1
    return true
end

function M.record(state, identity, phase, data)
    if not state.armed or state.count >= M.MAX_RECORDS then
        return false, state.count >= M.MAX_RECORDS
    end

    local token = tostring(identity) .. "|" .. tostring(phase)
    if state.seen[token] then
        return false, false
    end

    state.seen[token] = true
    state.count = state.count + 1
    state.records[state.count] = {
        identity = identity,
        phase = phase,
        data = data,
    }

    local capped = state.count >= M.MAX_RECORDS
    if capped then
        state.armed = false
    end

    return true, capped
end


return M
