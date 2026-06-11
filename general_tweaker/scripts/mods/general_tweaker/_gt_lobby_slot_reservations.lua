local mod = get_mod("gt")
local M = {}

-- ============================================================================
-- Slot Reservations (migrated from lobby_tweaker 2026-05-25; lt v0.1.7-dev).
-- ============================================================================
-- Persistent steam_id -> slot_index (1..4) map. When the feature is enabled
-- and a non-reserved peer joins while reservations are pending (i.e. at least
-- one reservation exists for a steam_id NOT currently in the lobby), the
-- joiner is immediately kicked. Reserved peers are always allowed.
--
-- Host-only. All handlers bail when `Managers.player.is_server` is false.
--
-- Persistence key:  "gt_lobby_sr_reservations" = { [steam_id_string] = slot_index, ... }
-- Master toggle:    "gt_lobby_slot_reservations_enabled"
-- Chat commands:    /gt_lobby_reserve, /gt_lobby_unreserve, /gt_lobby_reservations

local STORAGE_KEY = "gt_lobby_sr_reservations"
local TOGGLE_KEY  = "gt_lobby_slot_reservations_enabled"
local TAG         = "[gt:lobby]"

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

local function _load()
    local t = mod:get(STORAGE_KEY)
    if type(t) ~= "table" then t = {} end
    return t
end

local function _save(t)
    mod:set(STORAGE_KEY, t)
end

local function _normalize_id(s)
    if s == nil then return nil end
    s = tostring(s)
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return nil end
    return s
end

local function _parse_slot(s)
    if s == nil then return nil end
    local n = tonumber(s)
    if not n then return nil end
    n = math.floor(n)
    if n < 1 or n > 4 then return nil end
    return n
end

-- Peers currently connected to the lobby (host included), keyed by steam_id
-- string. Uses the party_manager player list since it covers everyone with a
-- party slot regardless of mission/keep state.
local function _peers_in_lobby()
    local set = {}
    local pm = Managers.player
    if not pm then return set end
    local players = pm:human_and_bot_players()
    if players then
        for _, p in pairs(players) do
            if p and not p.bot_player and p.peer_id then
                set[tostring(p:network_id() or p.peer_id)] = true
                set[tostring(p.peer_id)] = true
            end
        end
    end
    return set
end

-- Are any reservations pending? "Pending" = reservation steam_id is NOT
-- currently in the lobby. If everyone reserved is already here, no slot is
-- being held open, so we don't gate joiners.
local function _has_pending_reservation(reservations, lobby_peers)
    for steam_id, _slot in pairs(reservations) do
        if not lobby_peers[steam_id] then
            return true
        end
    end
    return false
end

local function _kick_peer(peer_id)
    local net_mgr = Managers.state and Managers.state.network
    local server  = net_mgr and net_mgr.network_server
    if server and server.kick_peer then
        server:kick_peer(peer_id)
        return true
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Join handler
-- ---------------------------------------------------------------------------

local function _on_player_joined_party(peer_id, local_player_id, party_id, slot_id, is_bot)
    if is_bot then return end
    if not mod:get(TOGGLE_KEY) then return end
    if not _is_host() then return end
    if not peer_id then return end

    local reservations = _load()
    if not next(reservations) then return end

    local joiner_id = tostring(peer_id)
    -- Reserved peers are always allowed in, full stop.
    if reservations[joiner_id] then return end

    local lobby_peers = _peers_in_lobby()
    if not _has_pending_reservation(reservations, lobby_peers) then return end

    if _kick_peer(peer_id) then
        _chat(TAG .. " Reserved slot - try again later.")
        mod:echo(TAG .. " Kicked " .. joiner_id .. " (slot reserved).")
    else
        mod:echo(TAG .. " WARN: no NetworkServer handle; could not kick " .. joiner_id)
    end
end

-- ---------------------------------------------------------------------------
-- Chat commands (host-only). Renamed lt_* -> gt_lobby_* per merge.
-- ---------------------------------------------------------------------------

mod:command("gt_lobby_reserve", "Reserve a lobby slot for a Steam ID. Usage: /gt_lobby_reserve <steam_id> <slot 1-4>",
    function(steam_id_arg, slot_arg)
        if not _is_host() then
            mod:echo(TAG .. " /gt_lobby_reserve: host only.")
            return
        end
        local steam_id = _normalize_id(steam_id_arg)
        local slot     = _parse_slot(slot_arg)
        if not steam_id then
            mod:echo(TAG .. " /gt_lobby_reserve: missing or invalid steam_id.")
            return
        end
        if not slot then
            mod:echo(TAG .. " /gt_lobby_reserve: slot must be 1, 2, 3, or 4.")
            return
        end
        local reservations = _load()
        reservations[steam_id] = slot
        _save(reservations)
        mod:echo(TAG .. " Reserved slot " .. slot .. " for " .. steam_id .. ".")
    end)

mod:command("gt_lobby_unreserve", "Remove a slot reservation. Usage: /gt_lobby_unreserve <steam_id>",
    function(steam_id_arg)
        if not _is_host() then
            mod:echo(TAG .. " /gt_lobby_unreserve: host only.")
            return
        end
        local steam_id = _normalize_id(steam_id_arg)
        if not steam_id then
            mod:echo(TAG .. " /gt_lobby_unreserve: missing or invalid steam_id.")
            return
        end
        local reservations = _load()
        if reservations[steam_id] == nil then
            mod:echo(TAG .. " /gt_lobby_unreserve: no reservation for " .. steam_id .. ".")
            return
        end
        reservations[steam_id] = nil
        _save(reservations)
        mod:echo(TAG .. " Removed reservation for " .. steam_id .. ".")
    end)

mod:command("gt_lobby_reservations", "List current slot reservations.", function()
    local reservations = _load()
    if not next(reservations) then
        mod:echo(TAG .. " No reservations.")
        return
    end
    -- Sort by slot then steam_id for stable output.
    local rows = {}
    for steam_id, slot in pairs(reservations) do
        rows[#rows + 1] = { steam_id = steam_id, slot = slot }
    end
    table.sort(rows, function(a, b)
        if a.slot ~= b.slot then return a.slot < b.slot end
        return a.steam_id < b.steam_id
    end)
    mod:echo(TAG .. " Slot reservations (" .. #rows .. "):")
    local lobby_peers = _peers_in_lobby()
    for _, r in ipairs(rows) do
        local present = lobby_peers[r.steam_id] and " [present]" or " [pending]"
        mod:echo(string.format("  slot %d  %s%s", r.slot, r.steam_id, present))
    end
end)

-- ---------------------------------------------------------------------------
-- Event registration: Managers.state.event is rebuilt on every game-state
-- transition (StateInGame, StateLoading, StateTitleScreen...). A boot-time
-- register is silently dropped after the first map load, so we pointer-compare
-- the current event manager via gt's central update consumer registry and
-- re-register when it changes. Uses gt's _register_update (exposed on the mod
-- table at boot) to avoid the legacy `_prev_update = mod.update` chain that
-- gt's Issue #16 refactor replaced.
-- ---------------------------------------------------------------------------

local _last_state_event = nil
local function _update_register(_dt)
    local ev = Managers.state and Managers.state.event
    if ev and ev ~= _last_state_event then
        _last_state_event = ev
        -- Stingray ev:register expects (object, event_name, METHOD_NAME_STRING).
        -- Passing a function value here triggers
        -- "No function found with name '[function]' on supplied object".
        -- Attach the callback as a method on `mod` first, then register by name.
        mod.gt_lobby_slot_reservations_on_player_joined_party = _on_player_joined_party
        ev:register(mod, "on_player_joined_party", "gt_lobby_slot_reservations_on_player_joined_party")
    end
end

-- gt exposes its update registrar via mod._gt_register_update (see
-- general_tweaker.lua, "mod.update subscriber registry" section).
if type(mod._gt_register_update) == "function" then
    mod._gt_register_update("gt_lobby_slot_reservations_register_event", _update_register)
end

if Managers.state and Managers.state.event then
    _last_state_event = Managers.state.event
    mod.gt_lobby_slot_reservations_on_player_joined_party = _on_player_joined_party
    Managers.state.event:register(mod, "on_player_joined_party", "gt_lobby_slot_reservations_on_player_joined_party")
end

M.on_player_joined_party = _on_player_joined_party

return M
