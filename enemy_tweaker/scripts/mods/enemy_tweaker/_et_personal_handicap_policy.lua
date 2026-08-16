-- Engine-free policy for Issue #61: a personal combat handicap that never
-- pretends client-local code can change the host-authoritative simulation.

local M = {}

M.RANKS = {
    normal = 2,
    hard = 3,
    harder = 4,
    hardest = 5,
    cataclysm = 6,
    cataclysm_2 = 7,
    cataclysm_3 = 8,
}

-- A bounded approximation, not a replacement difficulty. Spawn composition,
-- enemy health/AI, wounds, friendly fire, and healing remain host difficulty.
local BY_RANK_DELTA = {
    [0] = { incoming = 1.00, outgoing = 1.00 },
    [1] = { incoming = 1.08, outgoing = 0.95 },
    [2] = { incoming = 1.25, outgoing = 0.85 },
    [3] = { incoming = 1.25, outgoing = 0.85 },
}

function M.sanitize_preset(value)
    if value == "off" or M.RANKS[value] then return value end
    return "off"
end

-- #61 host gate: the HOST decides whether OTHER players' requested handicaps
-- apply at all ("Allow personal handicaps", default off). The host's own
-- preset is the host's own setting and is never gated. Evaluated at the
-- damage chokepoint, so toggling the gate mid-session takes effect on the
-- next hit with no re-request round trip.
function M.effective_preset(is_host_own_preset, host_allows_others, requested_preset)
    requested_preset = M.sanitize_preset(requested_preset)
    if is_host_own_preset then return requested_preset end
    if not host_allows_others then return "off" end
    return requested_preset
end

function M.factors(host_difficulty, requested_difficulty)
    requested_difficulty = M.sanitize_preset(requested_difficulty)
    local host_rank = M.RANKS[host_difficulty]
    local requested_rank = M.RANKS[requested_difficulty]
    if not host_rank or not requested_rank or requested_rank <= host_rank then
        return 1, 1, 0
    end
    local delta = math.min(3, requested_rank - host_rank)
    local factors = BY_RANK_DELTA[delta]
    return factors.incoming, factors.outgoing, delta
end

function M.scale_damage(damage, multiplier)
    damage = tonumber(damage)
    if not damage or damage <= 0 then return damage end
    return damage * multiplier
end

return M
