-- Engine-free policy for the bounded issue #659 Raise Dead trace.

local M = {}

M.LIMITS = {
    target = 4,
    finish = 4,
    spawn_pet = 8,
    spawn_server = 8,
}

function M.new()
    return { counts = {} }
end

function M.should_trace(in_hub, is_local, is_bot)
    return in_hub == true and is_local == true and is_bot ~= true
end

function M.take(state, phase)
    local limit = M.LIMITS[phase]
    if not state or not limit then
        return false, 0
    end

    local count = state.counts[phase] or 0
    if count >= limit then
        return false, count
    end

    count = count + 1
    state.counts[phase] = count

    return true, count
end


function M.classify_finish(valid, reason, sub_action)
    if valid ~= true then
        return "target-invalid"
    end
    if reason ~= "new_interupting_action" then
        return "finish-reason"
    end
    if sub_action ~= "spawn_summon_area" then
        return "finish-sub-action"
    end

    return "spawn-branch"
end


return M
