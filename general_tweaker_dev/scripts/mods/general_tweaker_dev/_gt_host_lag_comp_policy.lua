local P = {}

P.HARD_MAX_MS = 350
P.DEFAULT_MAX_MS = 250
P.MAX_PENDING = 256
P.PING_EMA_ALPHA = 0.2

local function _finite_number(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function _clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

function P.configured_cap_seconds(configured_ms)
    local value = _finite_number(configured_ms) and configured_ms or P.DEFAULT_MAX_MS
    return _clamp(value, 0, P.HARD_MAX_MS) / 1000
end

function P.smooth_ping_seconds(previous, sample, configured_ms)
    if not _finite_number(sample) or sample < 0 then
        return nil, previous
    end

    local cap = P.configured_cap_seconds(configured_ms)
    local bounded = _clamp(sample, 0, cap)
    local smoothed

    if _finite_number(previous) and previous >= 0 then
        smoothed = previous + (bounded - previous) * P.PING_EMA_ALPHA
    else
        smoothed = bounded
    end

    return _clamp(smoothed, 0, cap), smoothed
end

function P.is_eligible(context)
    return context.enabled
        and context.is_server
        and context.target_is_remote_human
        and context.attacker_is_ai
        and context.action_has_fatigue
        and not context.action_unblockable
        and not context.already_blocked_damage
        and not context.target_disabled
end

function P.cancel_reason(context)
    if not context.target_alive then return "target_invalid" end
    if not context.attacker_alive then return "attacker_dead" end
    if context.attacker_staggered_by_target then return "stagger" end
    if context.target_dodging then return "dodge" end
    if context.target_blocked then return "block" end
    return nil
end

return P
