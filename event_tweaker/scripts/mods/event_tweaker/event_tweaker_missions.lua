-- Pure mission-availability contract for issue 626.
--
-- This module is require'd by both the early VMF data file and the runtime
-- mission-menu adapter, so it must stay engine-free: no get_mod, Managers, or
-- global table writes. The runtime module supplies the current LevelSettings,
-- AreaSettings, ActSettings, and NetworkLookup tables explicitly.

local M = {}

M.AREA_KEY = "celebrate"
M.ACT_KEY = "act_celebrate"

-- Deliberately closed. A future event level must be source-audited and added
-- here before Event Tweaker will expose it; sharing act_celebrate is not enough.
M.ALLOWLIST = {
    {
        id = "dlc_dwarf_fest",
        setting_id = "mission_dlc_dwarf_fest",
    },
    {
        id = "dlc_celebrate_crawl",
        setting_id = "mission_dlc_celebrate_crawl",
    },
}

local function _contains(list, value)
    if type(list) ~= "table" then return false end
    for i = 1, #list do
        if list[i] == value then return true end
    end
    return false
end

local function _lookup_has(lookup, key)
    return type(lookup) == "table" and rawget(lookup, key) ~= nil
end

function M.any_enabled(get)
    for i = 1, #M.ALLOWLIST do
        if get(M.ALLOWLIST[i].setting_id) == true then return true end
    end
    return false
end

function M.enabled_ids(get)
    local ids = {}
    for i = 1, #M.ALLOWLIST do
        local entry = M.ALLOWLIST[i]
        if get(entry.setting_id) == true then
            ids[#ids + 1] = entry.id
        end
    end
    return ids
end

-- Fail closed before advertising a mission. The selected level crosses the
-- vanilla mission/act lookup wire and LevelTransitionHandler later loads every
-- package listed on LevelSettings[level_key]; none of those contracts are safe
-- to synthesize from a menu hook.
function M.validate_contract(level_settings, area_settings, act_settings, network_lookup)
    local problems = {}
    local area = type(area_settings) == "table" and rawget(area_settings, M.AREA_KEY)
    local act = type(act_settings) == "table" and rawget(act_settings, M.ACT_KEY)

    if type(area) ~= "table" then
        problems[#problems + 1] = "AreaSettings.celebrate missing"
    elseif not _contains(area.acts, M.ACT_KEY) then
        problems[#problems + 1] = "AreaSettings.celebrate lacks act_celebrate"
    end
    if type(act) ~= "table" then
        problems[#problems + 1] = "ActSettings.act_celebrate missing"
    end

    local level_keys = type(network_lookup) == "table" and network_lookup.level_keys
    local mission_ids = type(network_lookup) == "table" and network_lookup.mission_ids
    local act_keys = type(network_lookup) == "table" and network_lookup.act_keys
    local unlockable_keys = type(network_lookup) == "table" and network_lookup.unlockable_level_keys

    if not _lookup_has(act_keys, M.ACT_KEY) then
        problems[#problems + 1] = "NetworkLookup.act_keys lacks act_celebrate"
    end

    for i = 1, #M.ALLOWLIST do
        local id = M.ALLOWLIST[i].id
        local level = type(level_settings) == "table" and rawget(level_settings, id)
        if type(level) ~= "table" then
            problems[#problems + 1] = "LevelSettings." .. id .. " missing"
        else
            if level.level_id ~= id then
                problems[#problems + 1] = "LevelSettings." .. id .. ".level_id mismatch"
            end
            if level.act ~= M.ACT_KEY then
                problems[#problems + 1] = "LevelSettings." .. id .. ".act mismatch"
            end
            if type(level.packages) ~= "table" or #level.packages == 0 then
                problems[#problems + 1] = "LevelSettings." .. id .. ".packages empty"
            end
        end
        if not _lookup_has(level_keys, id) then
            problems[#problems + 1] = "NetworkLookup.level_keys lacks " .. id
        end
        if not _lookup_has(mission_ids, id) then
            problems[#problems + 1] = "NetworkLookup.mission_ids lacks " .. id
        end
        if not _lookup_has(unlockable_keys, id) then
            problems[#problems + 1] = "NetworkLookup.unlockable_level_keys lacks " .. id
        end
    end

    return #problems == 0, problems
end

-- Return a new outer map and replace only act_celebrate. Every unrelated act
-- table is retained by identity, which is the no-global-campaign-mutation
-- invariant this feature is built around.
function M.filter_levels_by_act(levels_by_act, level_settings, get)
    local filtered = {}
    for act_key, levels in pairs(levels_by_act or {}) do
        filtered[act_key] = levels
    end

    local selected = {}
    for i = 1, #M.ALLOWLIST do
        local entry = M.ALLOWLIST[i]
        if get(entry.setting_id) == true then
            local level = type(level_settings) == "table" and rawget(level_settings, entry.id)
            if type(level) == "table" then selected[#selected + 1] = level end
        end
    end
    filtered[M.ACT_KEY] = selected
    return filtered
end

return M
