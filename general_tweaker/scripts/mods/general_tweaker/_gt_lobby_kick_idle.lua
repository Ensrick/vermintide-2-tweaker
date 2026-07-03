local mod = get_mod("gt")
local M = {}

-- ============================================================================
-- Kick on Idle (migrated from lobby_tweaker 2026-05-25; lt v0.1.7-dev).
-- ============================================================================
-- Host-only. While the host is in a hub (keep) level, every TICK_SEC we
-- snapshot each non-host, non-bot player_unit's world position. If a player's
-- position hasn't moved more than POS_EPSILON across `threshold_minutes`, they
-- get a 60s warning in chat and are then kicked.
--
-- Per-peer idle timing is derived from position deltas because vanilla
-- `Managers.input.last_active_time` is local-only.
--
-- Persistence:
--   "gt_lobby_ki_whitelist" = { [steam_id_string] = true, ... }
-- Toggles / numerics (live in _data.lua):
--   "gt_lobby_kick_idle_enabled", "gt_lobby_kick_idle_threshold_minutes",
--   "gt_lobby_ki_warn_seconds"

local TAG          = "[gt:lobby]"
local STORAGE_KEY  = "gt_lobby_ki_whitelist"
local TOGGLE_KEY   = "gt_lobby_kick_idle_enabled"
local THRESH_KEY   = "gt_lobby_kick_idle_threshold_minutes"
local WARN_KEY     = "gt_lobby_ki_warn_seconds"
local TICK_SEC     = 30          -- position-sample cadence
local POS_EPSILON  = 0.05        -- metres; below this counts as "didn't move"
local POS_EPS_SQ   = POS_EPSILON * POS_EPSILON

-- Per-peer state:
--   _idle[peer_id] = {
--       last_pos    = Vector3 box (last sample),
--       idle_for    = seconds the peer has held still,
--       warned      = boolean, true once we've chatted the warning,
--       last_seen   = seconds since last position sample (for cleanup),
--   }
local _idle = {}
local _accum = 0  -- seconds accumulated towards the next TICK_SEC sample

-- ---------------------------------------------------------------------------
-- Helpers (declared above their first use -- Lua 5.1 forward-reference rule)
-- ---------------------------------------------------------------------------

local function _is_host()
    return Managers.player and Managers.player.is_server and true or false
end

local function _chat(msg)
    if Managers.chat and Managers.chat.add_local_system_message then
        Managers.chat:add_local_system_message(1, msg, true)
    end
end

local function _load_whitelist()
    local t = mod:get(STORAGE_KEY)
    if type(t) ~= "table" then t = {} end
    return t
end

local function _save_whitelist(t)
    mod:set(STORAGE_KEY, t)
end

local function _normalize_id(s)
    if s == nil then return nil end
    s = tostring(s):gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return nil end
    return s
end

local function _in_keep()
    local lth = Managers.level_transition_handler
    if lth and lth.in_hub_level then
        return lth:in_hub_level() and true or false
    end
    -- Fallback: explicit known keep keys.
    local gm = Managers.state and Managers.state.game_mode
    if gm and gm.level_key then
        local k = gm:level_key()
        return k == "inn_level" or k == "magnus_tower" or k == "prologue_level"
    end
    return false
end

local function _kick(peer_id)
    local net_mgr = Managers.state and Managers.state.network
    local server  = net_mgr and net_mgr.network_server
    if server and server.kick_peer then
        server:kick_peer(peer_id)
        return true
    end
    return false
end

local function _threshold_seconds()
    local m = tonumber(mod:get(THRESH_KEY)) or 10
    if m < 1 then m = 1 end
    if m > 60 then m = 60 end
    return m * 60
end

local function _warn_seconds()
    local s = tonumber(mod:get(WARN_KEY)) or 60
    if s < 10 then s = 10 end
    if s > 180 then s = 180 end
    return s
end

local function _player_world_pos(player)
    local unit = player.player_unit
    if not unit or not Unit.alive(unit) then return nil end
    return Unit.world_position(unit, 0)
end

local function _peer_label(player)
    return tostring(player:network_id() or player.peer_id or "?")
end

local function _reset_all_timers(reason)
    _idle = {}
    _accum = 0
    if reason then mod:echo(TAG .. " idle timers reset (" .. reason .. ").") end
end

-- ---------------------------------------------------------------------------
-- Tick: one sample pass every TICK_SEC seconds while host is in keep
-- ---------------------------------------------------------------------------

local function _tick(elapsed)
    if not mod:get(TOGGLE_KEY) then return end
    if not _is_host() then return end
    if not _in_keep() then
        if next(_idle) ~= nil then _reset_all_timers() end
        return
    end

    local threshold = _threshold_seconds()
    local warn_sec  = _warn_seconds()
    local whitelist = _load_whitelist()
    local host_peer = Network.peer_id and Network.peer_id() or nil
    local players   = Managers.player:human_and_bot_players()
    if not players then return end

    local seen_now = {}
    for _, p in pairs(players) do
        repeat
            if not p then break end
            if p.bot_player then break end
            if p.remote == false and (p.peer_id == host_peer or p.local_player) then break end
            local peer_id = p.peer_id
            if not peer_id then break end
            if host_peer and peer_id == host_peer then break end

            local sid = _peer_label(p)
            if whitelist[sid] or whitelist[tostring(peer_id)] then break end

            local pos = _player_world_pos(p)
            if not pos then break end

            local state = _idle[peer_id]
            if not state then
                _idle[peer_id] = { last_pos = Vector3Box(pos), idle_for = 0, warned = false }
            else
                local prev = state.last_pos:unbox()
                if Vector3.distance_squared(prev, pos) < POS_EPS_SQ then
                    state.idle_for = state.idle_for + elapsed
                else
                    state.idle_for = 0
                    state.warned = false
                    state.last_pos:store(pos)
                end

                if not state.warned and state.idle_for >= (threshold - warn_sec) then
                    state.warned = true
                    _chat(TAG .. " " .. sid .. " idle - kicking in " .. warn_sec .. "s.")
                end
                if state.idle_for >= threshold then
                    if _kick(peer_id) then
                        _chat(TAG .. " Kicked " .. sid .. " for being idle.")
                        mod:echo(TAG .. " kicked idle peer " .. sid)
                    end
                    _idle[peer_id] = nil
                    break
                end
            end
            seen_now[peer_id] = true
        until true
    end

    -- Drop entries for peers that left the lobby.
    for peer_id, _ in pairs(_idle) do
        if not seen_now[peer_id] then _idle[peer_id] = nil end
    end
end

-- ---------------------------------------------------------------------------
-- Tick consumer -- gt's central update registry (see general_tweaker.lua
-- "mod.update subscriber registry" section). Fires every frame; we sample
-- every TICK_SEC.
-- ---------------------------------------------------------------------------

local function _tick_consumer(dt)
    dt = dt or 0
    _accum = _accum + dt
    if _accum < TICK_SEC then return end
    local elapsed = _accum
    _accum = 0
    _tick(elapsed)
end

if type(mod._gt_register_update) == "function" then
    mod._gt_register_update("gt_lobby_kick_idle", _tick_consumer)
end

-- ---------------------------------------------------------------------------
-- Chat commands (renamed lt_* -> gt_lobby_* per merge)
-- ---------------------------------------------------------------------------

mod:command("lobby_idle_whitelist", "Whitelist a Steam ID from idle-kicks. Usage: /lobby_idle_whitelist <steam_id>",
    function(steam_id_arg)
        local sid = _normalize_id(steam_id_arg)
        if not sid then
            mod:echo(TAG .. " /lobby_idle_whitelist: missing or invalid steam_id.")
            return
        end
        local wl = _load_whitelist()
        wl[sid] = true
        _save_whitelist(wl)
        mod:echo(TAG .. " idle-whitelisted " .. sid .. ".")
    end)

mod:command("lobby_idle_unwhitelist", "Remove a Steam ID from idle-kick whitelist. Usage: /lobby_idle_unwhitelist <steam_id>",
    function(steam_id_arg)
        local sid = _normalize_id(steam_id_arg)
        if not sid then
            mod:echo(TAG .. " /lobby_idle_unwhitelist: missing or invalid steam_id.")
            return
        end
        local wl = _load_whitelist()
        if wl[sid] == nil then
            mod:echo(TAG .. " /lobby_idle_unwhitelist: " .. sid .. " not on whitelist.")
            return
        end
        wl[sid] = nil
        _save_whitelist(wl)
        mod:echo(TAG .. " removed " .. sid .. " from idle whitelist.")
    end)

mod:command("lobby_idle_status", "Show idle-kick tracker (deltas + timers).", function()
    if not _is_host() then
        mod:echo(TAG .. " /lobby_idle_status: host only.")
        return
    end
    local threshold = _threshold_seconds()
    mod:echo(TAG .. " idle tracker (threshold " .. threshold .. "s, in_keep=" .. tostring(_in_keep()) .. "):")
    if not next(_idle) then
        mod:echo("  (no tracked peers)")
    else
        for peer_id, st in pairs(_idle) do
            mod:echo(string.format("  %s  idle_for=%.1fs  warned=%s", tostring(peer_id), st.idle_for, tostring(st.warned)))
        end
    end
    local wl = _load_whitelist()
    if next(wl) then
        local names = {}
        for sid, _ in pairs(wl) do names[#names + 1] = sid end
        table.sort(names)
        mod:echo(TAG .. " whitelist (" .. #names .. "): " .. table.concat(names, ", "))
    end
end)

-- Expose for parent module / tests.
M.tick                  = _tick
M.reset_all_timers      = _reset_all_timers

return M
