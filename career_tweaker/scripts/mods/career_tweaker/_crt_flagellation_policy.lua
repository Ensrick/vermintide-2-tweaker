-- _crt_flagellation_policy.lua - Pure issue #447 resolution/conversion policy.
--
-- Resolves the live Devotion talent by its localized title rather than a stale
-- internal-name guess, and calculates conversion from realized THP gain.
-- Runtime proc scoping and health mutation live in _crt_flagellation.lua.
--
-- Owned by: _crt_flagellation.lua. Consumed via: mod:dofile and offline QA.

local M = { ratio = 0.5 }

function M.conversion_amount(before_temp, after_temp, permanent_health)
    local gained = math.max(0, (tonumber(after_temp) or 0) - (tonumber(before_temp) or 0))
    local permanent = math.max(0, tonumber(permanent_health) or 0)
    return math.min(permanent, gained * M.ratio), gained
end

function M.resolve_devotion(candidates, localize)
    if type(candidates) ~= "table" or type(localize) ~= "function" then return nil end
    for i = 1, #candidates do
        local candidate = candidates[i]
        local title = candidate and candidate.display_name
        local ok, localized = pcall(localize, title)
        if candidate and (candidate.name == "victor_zealot_devotion"
            or (ok and type(localized) == "string" and localized:lower() == "devotion")) then
            return candidate
        end
    end
    return nil
end

return M
