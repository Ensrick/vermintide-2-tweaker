-- Pure mission-availability contract for issue 626.
--
-- This module is require'd by both the early VMF data file and the runtime
-- mission-menu adapter, so it must stay engine-free: no get_mod, Managers, or
-- direct global reads. The runtime module supplies the current LevelSettings,
-- AreaSettings, ActSettings, and campaign tables explicitly.

local M = {}

M.AREA_KEY = "celebrate"
M.ACT_KEY = "act_celebrate"

local PRESENTATION_KEYS = {
    "exclude_from_area_selection",
    "sort_order",
    "display_name",
    "description_text",
    "long_description_text",
    "level_image",
}

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

-- `AreaSettings.celebrate` is a dormant container, not a finished menu tile:
-- vanilla leaves it named and illustrated as Bogenhafen with sort_order 0.
-- Reuse the resident Feast presentation already carried by the stock
-- dwarf_fest area / level while vanilla constructs the area widgets, then let
-- the runtime adapter restore every field. No custom asset is introduced and
-- no global campaign identity changes.
function M.apply_area_presentation(level_settings, area_settings)
    local target = type(area_settings) == "table" and rawget(area_settings, M.AREA_KEY)
    local feast_area = type(area_settings) == "table" and rawget(area_settings, "dwarf_fest")
    local feast_level = type(level_settings) == "table" and rawget(level_settings, "dlc_dwarf_fest")
    if type(target) ~= "table" or type(feast_level) ~= "table" then
        return nil, "stock Feast presentation unavailable"
    end

    local display_name = type(feast_area) == "table" and feast_area.display_name
        or feast_level.display_name
    local description_text = type(feast_area) == "table" and feast_area.description_text
        or feast_level.description_text
    local level_image = type(feast_area) == "table" and feast_area.level_image
        or feast_level.level_image
    if type(display_name) ~= "string" or display_name == ""
        or type(description_text) ~= "string" or description_text == ""
        or type(level_image) ~= "string" or level_image == "" then
        return nil, "stock Feast presentation incomplete"
    end

    local snapshot = { target = target, present = {}, values = {} }
    for i = 1, #PRESENTATION_KEYS do
        local key = PRESENTATION_KEYS[i]
        snapshot.present[key] = rawget(target, key) ~= nil
        snapshot.values[key] = target[key]
    end

    local highest = 0
    for key, area in pairs(area_settings) do
        if key ~= M.AREA_KEY and type(area) == "table"
            and area.exclude_from_area_selection ~= true
            and type(area.sort_order) == "number"
            and area.sort_order > highest then
            highest = area.sort_order
        end
    end

    target.exclude_from_area_selection = false
    target.sort_order = highest + 1
    target.display_name = display_name
    target.description_text = description_text
    target.long_description_text = feast_level.description_text
    target.level_image = level_image

    local visible = 0
    for _, area in pairs(area_settings) do
        if type(area) == "table" and area.exclude_from_area_selection ~= true then
            visible = visible + 1
        end
    end
    return snapshot, {
        display_name = target.display_name,
        sort_order = target.sort_order,
        visible_count = visible,
    }
end

function M.restore_area_presentation(snapshot)
    if type(snapshot) ~= "table" or type(snapshot.target) ~= "table" then return false end
    for i = 1, #PRESENTATION_KEYS do
        local key = PRESENTATION_KEYS[i]
        if snapshot.present[key] then
            snapshot.target[key] = snapshot.values[key]
        else
            snapshot.target[key] = nil
        end
    end
    return true
end

-- Returns true when a LevelSettings entry is complete enough to advertise and
-- register: keyed to itself, in the celebrate act, with a non-empty package
-- list for LevelTransitionHandler to load (level_transition_handler.lua:518-572).
local function _level_ok(level, id)
    return type(level) == "table"
        and level.level_id == id
        and level.act == M.ACT_KEY
        and type(level.packages) == "table"
        and #level.packages > 0
end

-- Visibility gate (issue 626 fix): fail closed before advertising a mission,
-- but require ONLY the tables the menus actually read. Area selection reads
-- AreaSettings (start_game_window_area_selection.lua:91-95); mission selection
-- reads LevelSettings + ActSettings (with arithmetic on act sorting,
-- start_game_window_mission_selection.lua:108-134,156-160) and the acts listed
-- on the selected area. The previous gate also demanded four NetworkLookup
-- tables (level_keys / mission_ids / act_keys / unlockable_level_keys) that no
-- menu reads, so a lookup mismatch blocked both hooks with only a printf:
-- exactly "toggle on, nothing shows". NetworkLookup is deliberately neither
-- consulted nor mutated here: the vanilla wire tables already carry both
-- levels from boot (network_lookup.lua:1239-1248, built from LevelSettings),
-- and modded NetworkLookup keys on vanilla RPCs CTD non-mod peers
-- (issue 278, issue 371).
function M.validate_contract(level_settings, area_settings, act_settings)
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
    elseif type(act.sorting) ~= "number" then
        problems[#problems + 1] = "ActSettings.act_celebrate.sorting not a number"
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
    end

    return #problems == 0, problems
end

-- Idempotent campaign-table registration fallback (issue 626). Vanilla's boot
-- pass already registers every valid celebrate level into UnlockableLevels,
-- GameActs, and MapPresentationActs (level_unlock_settings.lua:100-135), so on
-- a healthy install this appends nothing. It repairs only an install where
-- that pass genuinely missed an allowlisted level, mirroring the vanilla
-- registration shape. Per-peer safety: these are LOCAL campaign/presentation
-- tables; the wire tables (NetworkLookup.level_keys / mission_ids / act_keys /
-- unlockable_level_keys) were built from LevelSettings / GameActs /
-- UnlockableLevels at BOOT (network_lookup.lua:1239-1259), before any mod
-- loads, so appends here can never extend or reorder a NetworkLookup table.
-- The caller must run this unconditionally at mod load (never toggle-gated),
-- so every Event Tweaker peer applies the identical append at the same time.
function M.ensure_campaign_registration(level_settings, unlockable_levels, game_acts, map_presentation_acts)
    local appended = {}
    for i = 1, #M.ALLOWLIST do
        local id = M.ALLOWLIST[i].id
        local level = type(level_settings) == "table" and rawget(level_settings, id)
        -- Only a well-formed stock definition may be registered; a missing or
        -- malformed LevelSettings entry stays fail-closed at the visibility gate.
        if _level_ok(level, id) then
            if type(unlockable_levels) == "table" and not _contains(unlockable_levels, id) then
                unlockable_levels[#unlockable_levels + 1] = id
                appended[#appended + 1] = "UnlockableLevels+" .. id
            end
            if type(game_acts) == "table" then
                if type(game_acts[M.ACT_KEY]) ~= "table" then
                    game_acts[M.ACT_KEY] = {}
                end
                if not _contains(game_acts[M.ACT_KEY], id) then
                    game_acts[M.ACT_KEY][#game_acts[M.ACT_KEY] + 1] = id
                    appended[#appended + 1] = "GameActs." .. M.ACT_KEY .. "+" .. id
                end
            end
            if type(map_presentation_acts) == "table" and not _contains(map_presentation_acts, M.ACT_KEY) then
                map_presentation_acts[#map_presentation_acts + 1] = M.ACT_KEY
                appended[#appended + 1] = "MapPresentationActs+" .. M.ACT_KEY
            end
        end
    end
    return appended
end

-- Return a new outer map and replace only act_celebrate. Every unrelated act
-- table is retained by identity: the menu adapter never rewrites another
-- act's level list, and the view-local map never leaks back into globals.
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
