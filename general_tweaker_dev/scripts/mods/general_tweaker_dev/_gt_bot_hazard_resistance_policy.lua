local M = {}

M.STACK_LIFETIME = 2
M.RESISTANCE_PER_STACK = 0.20
M.MAX_STACKS = 5

function M.classify(damage_source, damage_type)
    if damage_type == "gas" or damage_source == "skaven_poison_wind_globadier" then
        return "gas"
    end
    if damage_type == "warpfire_ground" or damage_type == "warpfire_face" then
        return "warpfire"
    end
    return nil
end

-- `state` is one bot's table of per-hazard expiry arrays. Every stack owns its
-- own two-second lifetime. The hit that creates a stack is not reduced by that
-- new stack; only stacks active before the hit contribute resistance.
function M.apply_hit(state, hazard, damage, now)
    if type(state) ~= "table" or type(hazard) ~= "string"
        or type(damage) ~= "number" or damage <= 0 or type(now) ~= "number" then
        return damage, 0, 0
    end

    local expiries = state[hazard]
    if type(expiries) ~= "table" then
        expiries = {}
        state[hazard] = expiries
    end
    for i = #expiries, 1, -1 do
        if expiries[i] <= now then table.remove(expiries, i) end
    end

    local active_before = #expiries
    local multiplier = math.max(0, 1 - active_before * M.RESISTANCE_PER_STACK)
    local scaled = damage * multiplier

    if #expiries >= M.MAX_STACKS then table.remove(expiries, 1) end
    expiries[#expiries + 1] = now + M.STACK_LIFETIME
    return scaled, active_before, #expiries
end

return M
