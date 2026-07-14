-- Pure target-eligibility policy for issue #523. Engine-free so the host-side
-- selector's wounded/non-wounded and Zealot rules can be pinned offline.
local Policy = {}

local function threshold_fraction(value, fallback)
    local percent = tonumber(value)
    if percent == nil then
        percent = fallback
    end
    percent = math.max(0, math.min(100, percent))
    return percent / 100
end

function Policy.is_eligible(health_percent, wounded, is_zealot, options)
    if type(health_percent) ~= "number" or type(options) ~= "table" then
        return false
    end

    wounded = wounded == true
    is_zealot = is_zealot == true

    if is_zealot then
        if wounded then
            if options.heal_wounded_zealot ~= true then
                return false
            end
        elseif options.exclude_zealot == true then
            return false
        end
    end

    local setting = wounded and options.wounded_percent or options.regular_percent
    local fallback = wounded and 100 or 15
    local threshold = threshold_fraction(setting, fallback)
    return threshold > 0 and health_percent <= threshold
end

return Policy
