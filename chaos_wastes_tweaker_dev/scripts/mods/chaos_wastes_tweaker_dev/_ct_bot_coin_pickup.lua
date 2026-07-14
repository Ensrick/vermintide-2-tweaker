-- _ct_bot_coin_pickup.lua - Pure polling/claim policy for bot coin pickup (#331).
--
-- Keeps the engine-free timing, identity, range, and short-lived claim rules
-- testable without VT2. The runtime adapter lives in _ct_blessed_bots.lua so
-- CT retains exactly one PlayerBotBase.update hook.
--
-- Owned by: _ct_blessed_bots.lua. Consumed via: mod:dofile.
local M = {
    pickup_name = "deus_soft_currency",
    range = 10,
    poll_interval = 1,
    claim_ttl = 1.5,
}

function M.poll_due(t, next_t)
    t = tonumber(t) or 0
    next_t = tonumber(next_t) or 0
    return t >= next_t, t + M.poll_interval
end

function M.can_claim(pickup_name, claim_until, t)
    if pickup_name ~= M.pickup_name then return false end
    claim_until = tonumber(claim_until) or 0
    t = tonumber(t) or 0
    return claim_until <= t
end

function M.claim_until(t)
    return (tonumber(t) or 0) + M.claim_ttl
end

return M
