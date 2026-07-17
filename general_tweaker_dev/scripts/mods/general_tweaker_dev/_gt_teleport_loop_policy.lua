-- Pure policy for issue #385: retain the first close-range no-path unstick,
-- but rate-limit repeated executions while the bot remains below its leash.

local M = {}

M.NO_PATH_RETRY_S = 5.0
M.AID_TRACE_WINDOW_S = 3.0

function M.should_suppress_no_path(distance_m, leash_m, now, last_no_path_t)
    if type(distance_m) ~= "number" or type(leash_m) ~= "number"
            or type(now) ~= "number" or type(last_no_path_t) ~= "number" then
        return false
    end
    if distance_m >= leash_m then return false end
    local age = now - last_no_path_t
    return age >= 0 and age < M.NO_PATH_RETRY_S
end

function M.is_no_path_reason(reason)
    return reason == "vanilla_no_path" or reason == "backward_no_path"
end

-- Issues #139/#384: retain the exact identity present at a veto long enough
-- for the execution-side teleport hook to correlate a later action. This is
-- ordinary Lua data only: engine unit handles are treated as opaque identity
-- tokens and no behavior decision reads this record.
function M.make_aid_veto_trace(now, aid_unit, follow_unit, reason)
    if type(now) ~= "number" or aid_unit == nil then return nil end
    return {
        t = now,
        aid_unit = aid_unit,
        follow_unit = follow_unit,
        reason = reason,
    }
end

function M.correlate_aid_veto(trace, now, current_aid_unit)
    if type(trace) ~= "table" or type(trace.t) ~= "number"
            or type(now) ~= "number" then
        return nil, nil
    end
    local age = now - trace.t
    if age < 0 or age > M.AID_TRACE_WINDOW_S then
        return nil, nil
    end
    return age, trace.aid_unit == current_aid_unit
end

return M
