-- _gut_mission_completion_policy.lua -- exact-path mission completion policy.
--
-- Keeps issue #649's compatibility decision engine-free and testable. The
-- mission-select UI may enumerate a custom career added after vanilla built
-- StatisticsDefinitions; only that undefined leaf is skipped. Defined leaves
-- still use StatisticsDatabase and any other read failure remains visible.
--
-- Owned by: _gut_guard649_mission_completion.lua. Consumed via: mod:dofile.
--
-- Source provenance (2026-07-16 decompile):
--   statistics_definitions.lua:556-576 builds completed_career_levels only for
--   CareerSettings present when that file executes.
--   start_game_window_mission_selection_console.lua:503-524 reads every
--   profile career without checking that exact definition path first.

local M = {}

local function _definition_exists(definitions, career_name, level_key, difficulty_key)
    if type(definitions) ~= "table" then
        return false
    end

    local career = definitions[career_name]
    local level = type(career) == "table" and career[level_key]

    return type(level) == "table" and level[difficulty_key] ~= nil
end

M.definition_exists = _definition_exists

-- Returns the unique career names for which at least one exact completion
-- definition is absent. This is presentation-only; no StatisticsDatabase row
-- is created or mutated.
function M.missing_careers(profile, level_key, difficulties, definitions)
    local missing = {}
    local seen = {}
    local careers = type(profile) == "table" and profile.careers or nil

    if type(careers) ~= "table" or type(difficulties) ~= "table" then
        return missing
    end

    for j = 1, #careers do
        local career_name = careers[j] and careers[j].display_name
        if career_name ~= nil then
            for i = 1, #difficulties do
                if not _definition_exists(definitions, career_name, level_key, difficulties[i]) then
                    if not seen[career_name] then
                        seen[career_name] = true
                        missing[#missing + 1] = career_name
                    end
                    break
                end
            end
        end
    end

    return missing
end

-- Returns a shallow profile copy whose careers all have the exact definition
-- coverage vanilla will read. The source profile and its career rows are never
-- mutated. When nothing is missing, the original profile identity is returned
-- so the caller can run vanilla byte-for-byte unchanged.
function M.filtered_profile(profile, level_key, difficulties, definitions)
    local careers = type(profile) == "table" and profile.careers or nil

    if type(careers) ~= "table" or type(difficulties) ~= "table" then
        return profile, 0, {}
    end

    local missing = M.missing_careers(profile, level_key, difficulties, definitions)

    if #missing == 0 then
        return profile, #careers, missing
    end

    local omitted = {}

    for i = 1, #missing do
        omitted[missing[i]] = true
    end

    local filtered = {}

    for k, value in pairs(profile) do
        filtered[k] = value
    end

    local profile_meta = getmetatable(profile)

    -- SPProfiles are ordinary tables in vanilla. Preserve an ordinary
    -- metatable when present, but do not pass a protected __metatable token to
    -- setmetatable (that would turn a compatibility guard into a new error).
    if type(profile_meta) == "table" then
        setmetatable(filtered, profile_meta)
    end
    filtered.careers = {}

    for i = 1, #careers do
        local career = careers[i]
        local career_name = career and career.display_name

        if career_name ~= nil and not omitted[career_name] then
            filtered.careers[#filtered.careers + 1] = career
        end
    end

    return filtered, #filtered.careers, missing
end

return M
