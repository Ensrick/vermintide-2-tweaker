-- ============================================================================
-- SHARED LIBRARY -- official loadout guard, VERSION 1 (issues 402 / 1688)
-- ----------------------------------------------------------------------------
-- MASTER SOURCE: tools/shared_lib/_lib_official_loadout_guard.lua
-- DO NOT EDIT COPIES. Consumers are declared in tools/shared_lib/manifest.psd1
-- and synchronized by sync-shared-libs.ps1. The file is copied into each mod so
-- every Workshop bundle remains fully standalone; it is never a runtime
-- dependency on another mod.
-- ============================================================================
-- Purpose: keep backend ids that a mod owns (items that exist only in the
-- local mirror) out of the career-data diff that vanilla commits to the
-- official backend through updateHeroAttributes.
--
-- Engine facts (Vermintide-2-Source-Code):
--   * scripts/managers/backend_playfab/playfab_mirror_base.lua:2885 is the only
--     caller of _check_career_data(careers_data, career_data_mirror); its third
--     return, dirty_hero_data, is JSON-encoded at :2889-2896 and, for oversized
--     payloads, later at :2992-2993.
--   * :3409-3628 stores dirty_hero_data[hero].careers[career].loadouts[tostring(i)]
--     as references to the live careers_data loadout tables (:3523, :3541).
--
-- The guard substitutes owned ids with the server-side (mirror) value for the
-- duration of the vanilla call, detaches the returned loadout tables so the
-- later encode cannot see the live values, then restores the owned ids so the
-- item stays equipped for the session.
--
-- Pure: no engine globals, no hooks. The consumer installs the hook.
-- ============================================================================

local M = { VERSION = 1 }

local function owned(is_owned_id, value)
    local ok, result = pcall(is_owned_id, value)
    return ok and result == true
end

local function mirror_value(mirror_career, i, key)
    if type(mirror_career) ~= "table" then return nil end
    local row = mirror_career[i]
    if type(row) == "table" and row[key] ~= nil then
        return row[key]
    end
    local first = mirror_career[1]
    if type(first) == "table" then
        return first[key]
    end
    return nil
end

-- Replace every owned string value in careers_data[career][i] with the mirror
-- value of the same loadout, else loadout 1's mirror value. Returns the
-- substitutions and the number of owned values that had no mirror value.
function M.scrub(careers_data, career_data_mirror, is_owned_id)
    local subs, unsafe = {}, 0
    if type(careers_data) ~= "table" or type(is_owned_id) ~= "function" then
        return subs, unsafe
    end
    local mirror_root = type(career_data_mirror) == "table" and career_data_mirror or {}
    for career, loadouts in pairs(careers_data) do
        if type(loadouts) == "table" then
            local mirror_career = mirror_root[career]
            for i, loadout in pairs(loadouts) do
                if type(loadout) == "table" then
                    for key, value in pairs(loadout) do
                        if type(value) == "string" and owned(is_owned_id, value) then
                            local replacement = mirror_value(mirror_career, i, key)
                            if replacement == nil then
                                unsafe = unsafe + 1
                            else
                                subs[#subs + 1] = { career, i, key, value }
                                loadout[key] = replacement
                            end
                        end
                    end
                end
            end
        end
    end
    return subs, unsafe
end

-- Replace every hero.careers[career].loadouts[k] table with a shallow copy.
function M.detach(dirty_hero_data)
    if type(dirty_hero_data) ~= "table" then return end
    for _, hero in pairs(dirty_hero_data) do
        local careers = type(hero) == "table" and hero.careers
        if type(careers) == "table" then
            for _, career in pairs(careers) do
                local loadouts = type(career) == "table" and career.loadouts
                if type(loadouts) == "table" then
                    for k, loadout in pairs(loadouts) do
                        if type(loadout) == "table" then
                            local copy = {}
                            for field, value in pairs(loadout) do
                                copy[field] = value
                            end
                            loadouts[k] = copy
                        end
                    end
                end
            end
        end
    end
end

-- Write every substituted original value back.
function M.restore(careers_data, subs)
    if type(careers_data) ~= "table" or type(subs) ~= "table" then return end
    for n = #subs, 1, -1 do
        local sub = subs[n]
        local loadouts = careers_data[sub[1]]
        local loadout = type(loadouts) == "table" and loadouts[sub[2]]
        if type(loadout) == "table" then
            loadout[sub[3]] = sub[4]
        end
    end
end

-- Hook body for _check_career_data. Returns func's three values unchanged
-- (the third detached); re-raises func's error after restoring.
function M.wrap(func, self, careers_data, career_data_mirror, is_owned_id, report)
    local subs, unsafe = M.scrub(careers_data, career_data_mirror, is_owned_id)
    local ok, dirty, characters_data, dirty_hero_data = pcall(func, self, careers_data, career_data_mirror)
    if ok then
        M.detach(dirty_hero_data)
    end
    M.restore(careers_data, subs)
    if (#subs > 0 or unsafe > 0) and type(report) == "function" then
        pcall(report, #subs, unsafe)
    end
    if not ok then
        error(dirty, 0)
    end
    return dirty, characters_data, dirty_hero_data
end

return M
