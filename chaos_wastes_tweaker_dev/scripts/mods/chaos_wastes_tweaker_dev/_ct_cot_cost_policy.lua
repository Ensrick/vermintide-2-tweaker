-- Engine-free policy for Issue #63: bounded Chest of Trials activation cost.

local M = {
    WAITING = 1,
    MIN_COST = 25,
    MAX_COST = 1000,
    DEFAULT_COST = 100,
}

function M.sanitize_cost(value)
    value = tonumber(value) or M.DEFAULT_COST
    if value ~= value then value = M.DEFAULT_COST end
    value = math.floor(value / 25 + 0.5) * 25
    return math.max(M.MIN_COST, math.min(M.MAX_COST, value))
end

function M.activation_plan(enabled, state, balance, configured_cost)
    if enabled ~= true or state ~= M.WAITING then return true, 0, "passthrough" end
    balance = tonumber(balance)
    if not balance then return false, 0, "balance_unavailable" end
    local cost = M.sanitize_cost(configured_cost)
    if balance < cost then return false, 0, "insufficient_coins" end
    return true, cost, "charge"
end

function M.transition_committed(before_state, after_state)
    return before_state == M.WAITING and after_state ~= M.WAITING
end

return M
