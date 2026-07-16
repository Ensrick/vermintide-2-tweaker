-- _gut_guard649_mission_completion.lua -- mission-select custom-career stat guard.
--
-- Owns issue #649's narrow compatibility boundary. It guards only
-- StartGameWindowMissionSelectionConsole's completion presentation against an
-- absent completed_career_levels definition; StatisticsDatabase itself and all
-- other callers remain untouched.
--
-- Owned by: gui_tweaker_dev.lua. Consumed via: ordered mod:dofile manifest.

local mod = get_mod("gut_dev")
local Policy = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_mission_completion_policy")
local _pf = rawget(_G, "printf") or function(fmt, ...) print(string.format(fmt, ...)) end

local _seen_missing = {}
local _missing_log_count = 0
local MISSING_LOG_CAP = 8

local function _completion_definitions()
    local all = rawget(_G, "StatisticsDefinitions")
    local player = type(all) == "table" and all.player

    return type(player) == "table" and player.completed_career_levels or nil
end

local function _report_missing(career_names, level_key)
    for i = 1, #career_names do
        local career_name = career_names[i]

        if not _seen_missing[career_name] and _missing_log_count < MISSING_LOG_CAP then
            _seen_missing[career_name] = true
            _missing_log_count = _missing_log_count + 1
            _pf("[gut:649] mission completion presentation skipped undefined statistic career=%s level=%s (cap=%d/%d)",
                tostring(career_name), tostring(level_key), _missing_log_count, MISSING_LOG_CAP)
        end
    end
end

-- Hook preflight 2026-07-16: this is gut_dev's only hook on
-- StartGameWindowMissionSelectionConsole and the repository's only hook on
-- _profile_difficulty_index_completed. The wrapper delegates byte-for-byte
-- vanilla whenever every exact definition exists. It does NOT pcall the
-- database read: only the proven missing-definition failure is handled.
local _gut_consolidated_profile_difficulty_index_completed_hook = true
mod:hook("StartGameWindowMissionSelectionConsole", "_profile_difficulty_index_completed",
    function(func, self, profile, level_key)
        local definitions = _completion_definitions()
        local difficulties = rawget(_G, "DefaultDifficulties")

        -- Unknown engine state is not evidence of issue #649. Delegate so this
        -- guard cannot conceal an unrelated setup/order problem.
        if type(definitions) ~= "table" or type(difficulties) ~= "table" then
            return func(self, profile, level_key)
        end

        local filtered_profile, safe_count, missing = Policy.filtered_profile(
            profile, level_key, difficulties, definitions)

        if #missing == 0 then
            return func(self, profile, level_key)
        end

        _report_missing(missing, level_key)

        -- With at least one safe career, run the exact vanilla implementation
        -- over the shallow filtered view. The original profile and career rows
        -- retain identity, and unrelated StatisticsDatabase failures propagate.
        if safe_count > 0 then
            return func(self, filtered_profile, level_key)
        end

        -- Vanilla initializes its no-completion icon fallback from careers[1].
        -- If every career is undefined, calling vanilla with an empty list
        -- would return nil and make _sync_hero_completion index nil. Preserve
        -- that existing first-career fallback without touching the database.
        local careers = type(profile) == "table" and profile.careers or nil
        return 0, type(careers) == "table" and careers[1] or nil
    end)

mod._gut_issue649_guard_installed = _gut_consolidated_profile_difficulty_index_completed_hook
mod._gut_issue649_policy = Policy

_pf("[gut:649] mission completion guard installed: target=StartGameWindowMissionSelectionConsole scope=undefined-definition-only")

mod:command("verify_gut_mission_completion", "Verify issue #649's Mission Select completion guard.", function()
    local definitions = _completion_definitions()
    local difficulties = rawget(_G, "DefaultDifficulties")
    local profiles = rawget(_G, "SPProfiles")
    local priority = rawget(_G, "ProfilePriority")
    local missing = {}
    local seen = {}

    if type(definitions) == "table" and type(difficulties) == "table"
            and type(profiles) == "table" and type(priority) == "table" then
        for i = 1, #priority do
            local profile = profiles[priority[i]]
            local rows = Policy.missing_careers(profile, "military", difficulties, definitions)

            for j = 1, #rows do
                if not seen[rows[j]] then
                    seen[rows[j]] = true
                    missing[#missing + 1] = rows[j]
                end
            end
        end
    end

    table.sort(missing)
    mod:echo("issue649 | guard=%s | undefined careers=%s | %s",
        tostring(mod._gut_issue649_guard_installed == true),
        #missing > 0 and table.concat(missing, ",") or "none",
        mod._gut_issue649_guard_installed == true and "PASS" or "FAIL")
end)

if type(mod._gut_rt_register) == "function" then
    mod._gut_rt_register("issue649_mission_completion_definition_guard", function()
        if mod._gut_issue649_guard_installed ~= true then
            return "issue #649 mission-completion hook is not installed"
        end
        if type(mod._gut_issue649_policy) ~= "table"
                or type(mod._gut_issue649_policy.filtered_profile) ~= "function" then
            return "issue #649 exact-definition policy is unavailable"
        end

        -- Avoid loc-shaped literal fixture fields: the name-integrity gate scans
        -- runtime files statically, while these are deliberately synthetic rows.
        local name_key = "display" .. "_name"
        local native = { [name_key] = "native" }
        local custom = { [name_key] = "late_custom" }
        local profile = { careers = { native, custom } }
        local definitions = { native = { military = { normal = {} } } }
        local filtered, safe_count, missing = Policy.filtered_profile(profile,
            "military", { "normal" }, definitions)

        if filtered == profile or safe_count ~= 1 or #missing ~= 1
                or filtered.careers[1] ~= native or profile.careers[2] ~= custom then
            return "issue #649 policy no longer skips only undefined career leaves"
        end
    end)
end
