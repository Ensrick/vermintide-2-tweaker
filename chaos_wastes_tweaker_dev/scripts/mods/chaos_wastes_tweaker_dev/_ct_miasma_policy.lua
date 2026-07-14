-- _ct_miasma_policy.lua - Pure value and owner policy for issue #361.
--
-- Keeps slider bounds and permanent-carrier selection testable without the
-- game. Runtime mutation and the live mutator wrapper live in _ct_miasma.lua.
--
-- Owned by: _ct_miasma.lua. Consumed via: mod:dofile and offline QA.

local M = {
    radius_min = 2,
    radius_max = 30,
    interval_min = 0.1,
    interval_max = 5,
}

local function clamp(value, low, high, fallback)
    value = tonumber(value) or fallback
    if value < low then return low end
    if value > high then return high end
    return value
end

function M.radius(value)
    return clamp(value, M.radius_min, M.radius_max, 8)
end

function M.interval(value)
    return clamp(value, M.interval_min, M.interval_max, 1.3)
end

function M.select_owner(current_owner, carriers, is_alive)
    if type(carriers) == "table" and carriers[1] ~= nil then
        return carriers[1], carriers[1] ~= current_owner
    end
    if current_owner ~= nil and is_alive(current_owner) then
        return current_owner, false
    end
    return nil, current_owner ~= nil
end

return M
