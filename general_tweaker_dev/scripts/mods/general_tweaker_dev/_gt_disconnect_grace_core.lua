-- Pure bounded trace planner for issue #309. Engine-free for offline tests.

local M = {}

M.SAMPLE_OFFSETS = { 0.05, 0.25, 1, 3, 10, 30 }
M.MAX_RECORDS = 10 -- pre + post + six samples + one rejoin + one spare

function M.new()
    return {
        armed = false,
        active = nil,
    }
end

function M.arm(state)
    state.armed = true
    state.active = nil
end

function M.begin(state, peer_id, slot_id, now)
    if not state.armed or state.active then
        return nil
    end

    state.armed = false
    state.active = {
        peer_id = peer_id,
        slot_id = slot_id,
        started_at = now,
        next_sample = 1,
        records = {},
    }

    return state.active
end

function M.record(trace, phase, now, snapshot)
    if not trace or #trace.records >= M.MAX_RECORDS then
        return false
    end

    trace.records[#trace.records + 1] = {
        phase = phase,
        elapsed = math.max(0, now - trace.started_at),
        snapshot = snapshot,
    }

    return true
end

function M.take_due(state, now)
    local trace = state.active
    if not trace then
        return nil
    end

    local offset = M.SAMPLE_OFFSETS[trace.next_sample]
    if not offset or now < trace.started_at + offset then
        return nil
    end

    trace.next_sample = trace.next_sample + 1
    return trace, offset
end

function M.note_rejoin(state, peer_id, now, snapshot)
    local trace = state.active
    if not trace or trace.peer_id ~= peer_id then
        return false
    end

    return M.record(trace, "rejoin", now, snapshot)
end

function M.finish_if_complete(state)
    local trace = state.active
    if trace and trace.next_sample > #M.SAMPLE_OFFSETS then
        state.active = nil
        return trace
    end

    return nil
end

return M
