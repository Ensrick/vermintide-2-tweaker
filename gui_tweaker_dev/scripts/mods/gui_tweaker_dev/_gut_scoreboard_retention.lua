-- Adventure disconnect/rejoin scoreboard retention (#437).
--
-- Vanilla unregisters (and deletes) the player's StatisticsDatabase row, then
-- registers an empty row when the same peer returns. Deus repairs that boundary
-- with save_persisted_score/restore_persisted_score; Adventure does not. This
-- module applies the same shape to only ScoreboardHelper's leaf paths, on the
-- Adventure host, for the lifetime of one StateIngame session.
local mod = get_mod("gut_dev")
local Policy = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_scoreboard_policy")
local M = { rt_checks = {} }

local MAX_PLAYERS = 8
local MAX_PATHS = 64
local LOG_CAP = 16
local retained, order = {}, {}
local active, log_count = false, 0

local function _enabled()
    return mod:get("gut_preserve_disconnected_scoreboard") ~= false
end

local function _is_adventure_host()
    if not active or not _enabled() then return false end
    local managers = rawget(_G, "Managers")
    local player = managers and managers.player
    local mechanism = managers and managers.mechanism
    if not player or player.is_server ~= true or not mechanism
            or type(mechanism.current_mechanism_name) ~= "function" then
        return false
    end
    local ok, name = pcall(mechanism.current_mechanism_name, mechanism)
    return ok and name == "adventure"
end

local function _log(fmt, ...)
    if log_count >= LOG_CAP then return end
    log_count = log_count + 1
    printf("[gut:437] " .. fmt, ...)
end

local function _clear(reason)
    retained, order = {}, {}
    if reason then _log("cleared reason=%s", tostring(reason)) end
end

local function _paths()
    local helper = rawget(_G, "ScoreboardHelper")
    return Policy.collect_stat_paths(helper and helper.scoreboard_topic_stats,
        MAX_PATHS)
end

local function _capture(database, stats_id)
    if not _is_adventure_host() or stats_id == nil then return end
    local paths = _paths()
    local records = Policy.capture_stat_values(paths, function(path)
        return database:get_stat(stats_id, unpack(path, 1, #path))
    end, MAX_PATHS)
    if #records == 0 then return end

    if not retained[stats_id] then
        if #order >= MAX_PLAYERS then
            retained[table.remove(order, 1)] = nil
        end
        order[#order + 1] = stats_id
    end
    retained[stats_id] = records
    _log("captured stats_id=%s fields=%d players=%d",
        tostring(stats_id), #records, #order)
end

local function _restore(database, stats_id)
    if not _is_adventure_host() or stats_id == nil then return end
    local records = retained[stats_id]
    if not records then return end
    retained[stats_id] = nil
    for i = #order, 1, -1 do
        if order[i] == stats_id then table.remove(order, i) break end
    end
    local restored = Policy.restore_stat_values(records, function(path, value)
        local args = {}
        for i = 1, #path do args[i] = path[i] end
        args[#args + 1] = value
        database:set_non_persistent_stat(stats_id, unpack(args, 1, #args))
    end, MAX_PATHS)
    _log("restored stats_id=%s fields=%d remaining=%d",
        tostring(stats_id), restored, #order)
end

-- Capture must occur before vanilla unregister deletes statistics[id]. Register
-- can restore in a post-hook because vanilla has just created the empty row.
mod:hook("StatisticsDatabase", "unregister", function(func, self, stats_id, ...)
    _capture(self, stats_id)
    return func(self, stats_id, ...)
end)

mod:hook_safe("StatisticsDatabase", "register", function(self, stats_id)
    _restore(self, stats_id)
end)

local prev_state = mod.on_game_state_changed
mod.on_game_state_changed = function(status, state_name)
    if prev_state then prev_state(status, state_name) end
    if state_name ~= "StateIngame" then return end
    if status == "enter" then
        _clear(nil)
        active = true
    elseif status == "exit" then
        active = false
        _clear("StateIngame_exit")
    end
end

local prev_setting = mod.on_setting_changed
mod.on_setting_changed = function(setting_id)
    if prev_setting then prev_setting(setting_id) end
    if setting_id == "gut_preserve_disconnected_scoreboard" and not _enabled() then
        _clear("disabled")
    end
end

local prev_disabled = mod.on_disabled
mod.on_disabled = function(...)
    if prev_disabled then prev_disabled(...) end
    active = false
    _clear(nil)
end

M.rt_checks[#M.rt_checks + 1] = {
    name = "issue437_adventure_scoreboard_retention",
    fn = function()
        if MAX_PLAYERS > 8 or MAX_PATHS > 64 or LOG_CAP > 16 then
            return "retention bounds drifted"
        end
        if type(Policy.collect_stat_paths) ~= "function"
                or type(Policy.capture_stat_values) ~= "function"
                or type(Policy.restore_stat_values) ~= "function" then
            return "scoreboard retention policy incomplete"
        end
    end,
}

return M
