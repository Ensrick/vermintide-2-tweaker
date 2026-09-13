-- _cos_weave_frame_catalog.lua -- issue #1000 resident Weave frame provider.
--
-- Owns the deterministic Season 5-10 portrait-frame catalog shared by Tweaker:
-- Cosmetics and a future Modded Progression rotation. The decompiled game
-- atlases declare all 24 inventory and 24 HUD sprites, but vanilla registers no
-- item, cosmetic, portrait-template or numeric wire identity after Season 4.
-- This module is data-only: it never mutates engine tables, never registers a
-- frame, and never touches NetworkLookup. Censuses take the live tables and
-- lookups as arguments so they stay engine-free and unit-testable.
--
-- Owned by: _cos_unlocks.lua (the portrait-frame owner).
-- Consumed via: get_mod("cosmetics_tweaker")._cos.weave_frames (api_version 1).

local M = {
    api_version = 1,
    source_kind = "vanilla_atlas",
    registered = false,
    native_wire_safe = false,
}

-- The wind labels follow the guide matrix linked from issue #1000. Vanilla
-- source identifies these unregistered rows only by season number.
local SEASONS = {
    { number = 5, wind = "Ghyran" },
    { number = 6, wind = "Azyr" },
    { number = 7, wind = "Ulgu" },
    { number = 8, wind = "Shyish" },
    { number = 9, wind = "Ghur" },
    { number = 10, wind = "Chamon" },
}

-- Atlas suffixes are exact (gui_items_atlas.lua / gui_hud_atlas.lua); the
-- 40/80/120 thresholds come from the same guide matrix.
local TIERS = {
    { key = "quickplay", display = "Quickplay", weave_threshold = nil },
    { key = "tier_1", display = "40", weave_threshold = 40 },
    { key = "tier_2", display = "80", weave_threshold = 80 },
    { key = "tier_3", display = "120", weave_threshold = 120 },
}

local ENTRIES = {}
local BY_KEY = {}

local function _copy(source)
    if source == nil then
        return nil
    end
    local result = {}
    for key, value in pairs(source) do
        result[key] = value
    end
    return result
end

for season_index = 1, #SEASONS do
    local season = SEASONS[season_index]
    local season_token = string.format("%02d", season.number)
    for tier_index = 1, #TIERS do
        local tier = TIERS[tier_index]
        local key = "frame_season_" .. season_token .. "_" .. tier.key
        local entry = {
            key = key,
            season = season.number,
            wind = season.wind,
            tier = tier.key,
            tier_display = tier.display,
            weave_threshold = tier.weave_threshold,
            inventory_icon = "icon_portrait_" .. key,
            hud_texture = "portrait_" .. key,
            -- Vanilla's Season 4 rows use portrait_<key>_name/_description.
            vanilla_display_name_key = "portrait_" .. key .. "_name",
            vanilla_description_key = "portrait_" .. key .. "_description",
            source_kind = M.source_kind,
        }
        ENTRIES[#ENTRIES + 1] = entry
        BY_KEY[key] = entry
    end
end

function M.count()
    return #ENTRIES
end

-- Snapshots, so one consumer cannot mutate the provider another mod observes.
-- This is the compatibility boundary for api_version 1.
function M.entries()
    local result = {}
    for index = 1, #ENTRIES do
        result[index] = _copy(ENTRIES[index])
    end
    return result
end

function M.get(key)
    return _copy(BY_KEY[key])
end

function M.seasons()
    local result = {}
    for index = 1, #SEASONS do
        result[index] = _copy(SEASONS[index])
    end
    return result
end

function M.tiers()
    local result = {}
    for index = 1, #TIERS do
        result[index] = _copy(TIERS[index])
    end
    return result
end

-- Registration-gap census. The numeric lookup is counted separately because
-- filling it is never safe without a native fallback and a semantic mod-peer
-- transport.
function M.census(item_master, cosmetics, frame_settings, cosmetic_lookup)
    local report = {
        total = #ENTRIES,
        item_master_missing = 0,
        cosmetics_missing = 0,
        frame_settings_missing = 0,
        network_lookup_missing = 0,
    }
    for index = 1, #ENTRIES do
        local key = ENTRIES[index].key
        if type(item_master) ~= "table" or rawget(item_master, key) == nil then
            report.item_master_missing = report.item_master_missing + 1
        end
        if type(cosmetics) ~= "table" or rawget(cosmetics, key) == nil then
            report.cosmetics_missing = report.cosmetics_missing + 1
        end
        if type(frame_settings) ~= "table" or rawget(frame_settings, key) == nil then
            report.frame_settings_missing = report.frame_settings_missing + 1
        end
        if type(cosmetic_lookup) ~= "table" or rawget(cosmetic_lookup, key) == nil then
            report.network_lookup_missing = report.network_lookup_missing + 1
        end
    end
    return report
end

-- Live-build atlas census. has_atlas_entry is the game's
-- UIAtlasHelper.has_atlas_settings_by_texture_name (or a test double); a
-- missing or throwing predicate counts as absent.
function M.atlas_census(has_atlas_entry)
    local report = { total = #ENTRIES, inventory_present = 0, hud_present = 0 }
    if type(has_atlas_entry) ~= "function" then
        return report
    end
    for index = 1, #ENTRIES do
        local entry = ENTRIES[index]
        local ok_icon, icon = pcall(has_atlas_entry, entry.inventory_icon)
        if ok_icon and icon == true then
            report.inventory_present = report.inventory_present + 1
        end
        local ok_hud, hud = pcall(has_atlas_entry, entry.hud_texture)
        if ok_hud and hud == true then
            report.hud_present = report.hud_present + 1
        end
    end
    return report
end

local function _resolved(localize, key)
    local ok, text = pcall(localize, key)
    return ok and type(text) == "string" and text ~= "" and text ~= key
        and text:sub(1, 1) ~= "<"
end

-- Vanilla-localization census for the Season 4 key convention. A resolved
-- name means naming can reuse vanilla text instead of authored copy.
function M.localization_census(localize)
    local report = { total = #ENTRIES, names_resolved = 0, descriptions_resolved = 0 }
    if type(localize) ~= "function" then
        return report
    end
    for index = 1, #ENTRIES do
        local entry = ENTRIES[index]
        if _resolved(localize, entry.vanilla_display_name_key) then
            report.names_resolved = report.names_resolved + 1
        end
        if _resolved(localize, entry.vanilla_description_key) then
            report.descriptions_resolved = report.descriptions_resolved + 1
        end
    end
    return report
end

return M
