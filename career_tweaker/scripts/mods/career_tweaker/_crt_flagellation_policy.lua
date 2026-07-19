-- _crt_flagellation_policy.lua - Pure issue #447 resolution/conversion policy.
--
-- Resolves the live Devotion talent from raw localization data using the
-- vanilla title key rule: Localize(display_name or name)
-- (scripts/ui/views/hero_view/windows/hero_window_talents.lua:328). Only the
-- three thp_* Zealot talents carry a display_name field
-- (talent_settings_victor.lua:1408/1420/1432); every other talent's title loc
-- key IS its internal name. Conversion math from realized THP gain also lives
-- here. Runtime proc scoping and health mutation live in _crt_flagellation.lua.
--
-- Owned by: _crt_flagellation.lua. Consumed via: mod:dofile and offline QA.

local M = { ratio = 0.5 }

function M.conversion_amount(before_temp, after_temp, permanent_health)
    local gained = math.max(0, (tonumber(after_temp) or 0) - (tonumber(before_temp) or 0))
    local permanent = math.max(0, tonumber(permanent_health) or 0)
    return math.min(permanent, gained * M.ratio), gained
end

-- Vanilla title key for a talent row (hero_window_talents.lua:328).
function M.display_key(candidate)
    if type(candidate) ~= "table" then return nil end
    return candidate.display_key or candidate.display_name or candidate.name
end

-- The engine wraps unknown loc keys in angle brackets instead of failing
-- (foundation/scripts/managers/localization/localization_manager.lua:3-5,
-- used by lookup at :94). Such a result means the key did not resolve.
function M.is_unresolved_title(title)
    return type(title) ~= "string" or title == ""
        or title:find("^<.*>$") ~= nil
end

local function normalized(title)
    local text = title:lower():gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

-- Returns (match, census). census = { candidates, resolved, unresolved,
-- matches, rows = { { name, display_key, title|nil } ... } }. A candidate
-- matches by canonical internal name or by localized title "Devotion"; the
-- match is returned only when EXACTLY ONE candidate matched, so a duplicated
-- localized title can never retarget an arbitrary talent (issue #447 retest
-- note: resolve exactly one canonical talent identity). The matched candidate
-- is annotated with its localized title for the runtime census line.
function M.resolve_devotion(candidates, localize)
    local census = { candidates = 0, resolved = 0, unresolved = 0, matches = 0, rows = {} }
    if type(candidates) ~= "table" or type(localize) ~= "function" then
        return nil, census
    end
    census.candidates = #candidates
    local match = nil
    for i = 1, #candidates do
        local candidate = candidates[i]
        local key = M.display_key(candidate)
        local ok, title = pcall(localize, key)
        if not ok or M.is_unresolved_title(title) then
            title = nil
            census.unresolved = census.unresolved + 1
        else
            census.resolved = census.resolved + 1
        end
        census.rows[i] = {
            name = candidate and candidate.name,
            display_key = key,
            title = title,
        }
        if candidate and (candidate.name == "victor_zealot_devotion"
            or (title and normalized(title) == "devotion")) then
            census.matches = census.matches + 1
            if not match then
                candidate.title = title
                match = candidate
            end
        end
    end
    if census.matches ~= 1 then
        return nil, census
    end
    return match, census
end

return M
