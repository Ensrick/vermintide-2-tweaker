-- Engine-free policy for Issue #63: bounded Chest of Trials activation cost.

local M = {
    WAITING = 1,
    MIN_COST = 0,
    MAX_COST = 1000,
    DEFAULT_COST = 0,
    STEP = 25,
}

function M.sanitize_cost(value)
    value = tonumber(value) or M.DEFAULT_COST
    if value ~= value then value = M.DEFAULT_COST end
    value = math.floor(value / M.STEP + 0.5) * M.STEP
    return math.max(M.MIN_COST, math.min(M.MAX_COST, value))
end

function M.activation_plan(state, balance, configured_cost)
    local cost = M.sanitize_cost(configured_cost)
    if state ~= M.WAITING or cost == 0 then return true, 0, "passthrough" end
    balance = tonumber(balance)
    if not balance then return false, 0, "balance_unavailable" end
    if balance < cost then return false, 0, "insufficient_coins" end
    return true, cost, "charge"
end

-- #825 one-time settings migration. The old UI stored a default amount of 100
-- beside a separate enable checkbox. Preserve a deliberately enabled cost, but
-- collapse disabled/fresh legacy state to the new absolute zero sentinel.
function M.migrate_legacy(legacy_enabled, legacy_amount)
    if legacy_enabled == nil then return M.DEFAULT_COST, "fresh" end
    if legacy_enabled ~= true then return 0, "legacy_disabled" end
    return M.sanitize_cost(legacy_amount), "legacy_enabled"
end

function M.transition_committed(before_state, after_state)
    return before_state == M.WAITING and after_state ~= M.WAITING
end

return M
