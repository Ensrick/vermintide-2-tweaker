-- Pure policy for the Starting Coins baseline.
--
-- A numeric VMF setting is authoritative even when it is zero. Invalid values
-- fail open to the vanilla rollover argument rather than inventing currency.

local M = {
    MIN = 0,
    MAX = 3000,
    MARKER = "starting_coins:exact-total-including-zero-v2",
}

function M.resolve(configured, vanilla_value)
    if type(configured) ~= "number"
        or configured ~= configured
        or configured < M.MIN
        or configured > M.MAX
        or configured ~= math.floor(configured) then
        return vanilla_value, false
    end
    return configured, true
end

return M
