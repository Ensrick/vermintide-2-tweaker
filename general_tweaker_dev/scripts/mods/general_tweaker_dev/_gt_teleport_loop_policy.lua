-- Pure policy for issue #385: retain the first close-range no-path unstick,
-- but rate-limit repeated executions while the bot remains below its leash.

local M = {}

M.NO_PATH_RETRY_S = 5.0

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

return M
