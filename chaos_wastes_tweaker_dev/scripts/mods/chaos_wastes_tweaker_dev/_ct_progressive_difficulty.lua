-- _ct_progressive_difficulty.lua -- pure advanced policy for issue #460.

local M = {}

M.TIERS = {
    "normal", "hard", "harder", "hardest", "cataclysm",
    "cataclysm_2", "cataclysm_3", "cataclysm_4", "cataclysm_5",
}

function M.step_count(completed_level_count)
    local completed = math.max(0, math.floor(tonumber(completed_level_count) or 0))
    if completed >= 4 then return 2 end -- map 5+
    if completed >= 2 then return 1 end -- maps 3-4
    return 0
end

local function registered(key, difficulties, lookup)
    local index = type(lookup) == "table" and rawget(lookup, key) or nil
    return type(index) == "number"
        and type(difficulties) == "table"
        and rawget(difficulties, index) == key
end

function M.cap_tier(difficulties, lookup)
    -- Prefer the requested Cata 5 ceiling when another installed system has
    -- registered it; vanilla's highest available tier is Cata 3.
    for i = #M.TIERS, 1, -1 do
        local key = M.TIERS[i]
        if registered(key, difficulties, lookup) then return i, key end
    end
    return nil
end

function M.difficulty(start_key, completed_level_count, difficulties, lookup)
    if type(difficulties) ~= "table" or type(lookup) ~= "table" then return start_key end
    local start_tier
    for i = 1, #M.TIERS do
        if M.TIERS[i] == start_key then start_tier = i; break end
    end
    local cap_tier = M.cap_tier(difficulties, lookup)
    if not start_tier or not cap_tier or not registered(start_key, difficulties, lookup) then
        return start_key
    end
    local key = M.TIERS[math.min(start_tier + M.step_count(completed_level_count), cap_tier)]
    return registered(key, difficulties, lookup) and key or start_key
end

function M.coin_multiplier(base_multiplier, reduction_percent, completed_level_count)
    local base = tonumber(base_multiplier) or 1
    if M.step_count(completed_level_count) == 0 then return base end
    local reduction = tonumber(reduction_percent) or -25
    reduction = math.max(-100, math.min(0, reduction))
    return math.max(0, base * (1 + reduction / 100))
end

return M
