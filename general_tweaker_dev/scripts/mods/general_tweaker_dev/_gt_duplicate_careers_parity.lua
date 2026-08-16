local mod = get_mod("gt_dev")
local M = {}

-- _gt_duplicate_careers_parity.lua - host-authority channel for Allow
-- Duplicate Careers (issue #1150).
--
-- Owned by: general_tweaker_dev.lua entry point (dofile'd from the gt_lobby_*
-- module block). Consumed via: mod._gt_dupc_effective_session /
-- mod._gt_dupc_effective_for_lobby, called from the three Duplicate-Careers
-- ProfileSynchronizer hook bodies in _gt_level_control.lua.
--
-- #1150 shape: all three Duplicate-Careers hooks read the LOCAL
-- mod:get("allow_duplicate_careers"), but two of the hooked surfaces run on
-- CLIENT machines (hero-select availability via get_profile_index_reservation
-- -> GameMechanismManager.profile_available_for_peer, character_selection_
-- state_character.lua:350; and the static is_free_in_lobby consumed by
-- popup_profile_picker.lua:430 + matchmaking_manager.lua:1561 + the lobby
-- browser). A client with the toggle OFF therefore blocked its own duplicate
-- selection even when the host allows it, and a client with the toggle ON
-- wrongly previewed occupied heroes as free under a disallowing host. The
-- reservation DECISION was always host-side (try_reserve_profile_for_peer
-- fasserts is_server, profile_synchronizer.lua:457) - only the client-side
-- preview gates were wrong.
--
-- TRANSPORT (patterned on _gt_lobby_modded_manifest / _gt_lobby_appearance_
-- parity): the HOST publishes its setting into Steam lobby_data under
-- gtw_dupc ("1"/"0"); clients read it back per lobby id via
-- LobbyInternal.get_lobby_data_from_id_by_key. WIRE SAFETY: lobby_data is
-- Steam metadata, not a game RPC - zero new networked sends, zero
-- NetworkLookup surface, hash-neutral (VMF_RECIPES section 10 by
-- construction). Unlike the manifest publisher, the flag is MERGED into
-- LobbyHost:get_stored_lobby_data() and re-set (the vanilla idiom,
-- matchmaking_manager mutates the stored table in place), so the stored
-- vanilla keys are never replaced by a keys-only table; publish is skipped
-- while the stored table is nil so this module is never the first writer.
-- Republish is value-driven (stored value ~= current setting), which also
-- self-heals a recreated lobby whose fresh stored table lacks the key.
--
-- FAIL CLOSED: when the host's state is unknown (vanilla host, gt-less host,
-- key not yet readable), every gate falls through to vanilla behavior - the
-- pure decision core is _gt_dupc_policy.lua (offline-tested both directions).
--
-- No mod:hook anywhere in this module (whole-mod grep before adding: the only
-- Duplicate-Careers hooks stay in _gt_level_control.lua). Publisher rides
-- gt's central update registry; readers are pull-based from the hook bodies.

local Policy = mod:dofile("scripts/mods/general_tweaker_dev/_gt_dupc_policy")

local LOBBY_KEY       = Policy.LOBBY_KEY
local POLL_INTERVAL_S = 1.0
local CACHE_TTL_S     = 1.0
local CACHE_MAX_IDS   = 64
local ABSENT          = false -- cache sentinel: key confirmed absent (vs never read)

local _poll_accum  = 0
local _cache       = {} -- lobby_id -> { v = "1"/"0"/ABSENT, t = clock }
local _cache_count = 0

local function _clock() return os.clock() or 0 end

-- Host detection (same probe order as _gt_lobby_modded_manifest._is_host).
local function _is_host()
    local sn = Managers and Managers.state and Managers.state.network
    if sn and sn.is_server == true then return true end
    local pm = Managers and Managers.player
    return (pm and pm.is_server == true) or false
end

-- LobbyHost candidates (verified vs Vermintide-2-Source-Code:
-- game_network_manager.lua:50, network_server.lua:55, matchmaking_manager.lua
-- :637 - duck-typed on set_lobby_data because mm.lobby is a LobbyClient when
-- joining). Same resolution as the manifest publisher.
local function _get_lobby_host()
    local sn = Managers and Managers.state and Managers.state.network
    if sn then
        if sn._lobby_host then return sn._lobby_host end
        if sn.network_server and sn.network_server.lobby_host then
            return sn.network_server.lobby_host
        end
    end
    local mm = Managers and Managers.matchmaking
    if mm and mm.lobby and type(mm.lobby.set_lobby_data) == "function" then
        return mm.lobby
    end
    return nil
end

-- Host-side publish: merge gtw_dupc into the stored lobby data when the stored
-- value disagrees with the live setting. Returns true when a write happened.
local function _publish()
    if not _is_host() then return false end
    local lobby_host = _get_lobby_host()
    if not (lobby_host
            and type(lobby_host.set_lobby_data) == "function"
            and type(lobby_host.get_stored_lobby_data) == "function") then
        return false
    end
    local value = Policy.serialize(mod:get("allow_duplicate_careers") and true or false)
    local wrote = false
    local ok, err = pcall(function()
        local stored = lobby_host:get_stored_lobby_data()
        -- nil stored table = vanilla has not initialized lobby data yet; never
        -- be the first writer (a keys-only table would become the stored one).
        if type(stored) ~= "table" then return end
        if stored[LOBBY_KEY] == value then return end
        stored[LOBBY_KEY] = value
        lobby_host:set_lobby_data(stored)
        wrote = true
    end)
    if not ok then
        mod:info("[gt:1150] dupc publish failed: %s", tostring(err))
        return false
    end
    return wrote
end

-- Read a lobby's advertised flag by id, TTL-cached (the popup evaluates five
-- heroes per frame; one Steam query per second per lobby is plenty).
local function _lobby_flag_by_id(lobby_id)
    if not lobby_id then return nil end
    local now = _clock()
    local hit = _cache[lobby_id]
    if hit and (now - hit.t) < CACHE_TTL_S then
        if hit.v == ABSENT then return nil end
        return hit.v
    end
    local v = nil
    local LI = rawget(_G, "LobbyInternal")
    if LI and LI.get_lobby_data_from_id_by_key then
        local ok, raw = pcall(LI.get_lobby_data_from_id_by_key, lobby_id, LOBBY_KEY)
        if ok and raw ~= nil and raw ~= "" then v = tostring(raw) end
    end
    if not hit then
        if _cache_count >= CACHE_MAX_IDS then
            _cache, _cache_count = {}, 0 -- bounded: browser sweeps stay small
        end
        _cache_count = _cache_count + 1
    end
    _cache[lobby_id] = { v = v or ABSENT, t = now }
    return v
end

-- Session lobby id as seen from a CLIENT. Primary: the failed-join reveal's
-- exported helper (matchmaking_session_lobby). Fallback for the join-time
-- popup window, before session registration: matchmaking's active lobby.
local function _session_lobby_id()
    local fn = mod._gt_lobby_safe_lobby_id
    if type(fn) == "function" then
        local ok, id = pcall(fn)
        if ok and id then return id end
    end
    local mm = Managers and Managers.matchmaking
    local lobby = mm and mm.active_lobby and mm:active_lobby()
    if lobby then
        if lobby.get_stored_lobby_data then
            local ok, d = pcall(function() return lobby:get_stored_lobby_data() end)
            if ok and type(d) == "table" and d.id then return d.id end
        end
        if lobby.id then
            local ok, id = pcall(function() return lobby:id() end)
            if ok and id then return id end
        end
    end
    return nil
end

-- Effective gate for session-scoped hook bodies (no lobby_data at the call
-- site): host follows its own setting, a client follows the host's advertised
-- state, unknown fails closed to vanilla.
local function _effective_session()
    local is_server = _is_host()
    local local_on = mod:get("allow_duplicate_careers") and true or false
    local host_adv = nil
    if not is_server then
        host_adv = _lobby_flag_by_id(_session_lobby_id())
    end
    return Policy.effective_session(is_server, local_on, host_adv)
end

-- Effective gate for is_free_in_lobby: the evaluated lobby's own flag wins
-- (direct key when the finder handed us the full data table, else a by-id
-- read); an id-less table (popup_profile_picker's makeshift one) falls back
-- to session semantics.
local function _effective_for_lobby(lobby_data)
    local lobby_adv = nil
    if type(lobby_data) == "table" then
        local direct = lobby_data[LOBBY_KEY]
        if direct ~= nil and direct ~= "" then
            lobby_adv = tostring(direct)
        elseif lobby_data.id then
            lobby_adv = _lobby_flag_by_id(lobby_data.id)
        end
    end
    local is_server = _is_host()
    local local_on = mod:get("allow_duplicate_careers") and true or false
    local session_adv = nil
    if lobby_adv == nil and not is_server then
        session_adv = _lobby_flag_by_id(_session_lobby_id())
    end
    return Policy.effective_for_lobby(lobby_adv, is_server, local_on, session_adv)
end

mod._gt_dupc_effective_session   = _effective_session
mod._gt_dupc_effective_for_lobby = _effective_for_lobby

-- Publisher rides gt's central per-frame update registry (1 s cadence; the
-- value-driven publish makes the steady-state tick a no-op).
local function _tick(dt)
    _poll_accum = _poll_accum + (dt or 0)
    if _poll_accum < POLL_INTERVAL_S then return end
    _poll_accum = 0
    _publish()
end

if type(mod._gt_register_update) == "function" then
    mod._gt_register_update("gt_duplicate_careers_parity", _tick)
end

-- Read-only diagnostic, mirrors /lobby_appearance_parity: show what each side
-- of the channel currently resolves to.
mod:command("dupc_state", "Show the Allow Duplicate Careers host/client effective state", function()
    local is_server = _is_host()
    local local_on = mod:get("allow_duplicate_careers") and true or false
    local sid = _session_lobby_id()
    local adv = (not is_server) and _lobby_flag_by_id(sid) or nil
    mod:echo(string.format(
        "[gt] duplicate careers: role=%s local=%s host_advertised=%s effective=%s",
        is_server and "host" or "client",
        tostring(local_on),
        adv == nil and "unknown" or tostring(adv),
        tostring(_effective_session())))
end)

-- Runtime regression check (issue #1150, PROJECT_STANDARDS section 15).
if type(mod._gt_rt_register) == "function" then
    mod._gt_rt_register("issue1150_dupc_host_authority", function()
        if type(mod._gt_dupc_effective_session) ~= "function"
                or type(mod._gt_dupc_effective_for_lobby) ~= "function" then
            return "duplicate-careers effective-gate exports missing"
        end
        if mod._GT_1150_DUPC_HOST_AUTHORITY_MARKER ~= "gt-1150-dupc-host-authority-v1" then
            return "level-control hooks no longer route through the host-authority gate (marker absent)"
        end
        -- Both #1150 directions on the live policy: host ON / client OFF
        -- allows; host OFF (or unknown) / client ON blocks.
        if Policy.effective_session(false, false, "1") ~= true then
            return "client with toggle OFF does not follow an allowing host"
        end
        if Policy.effective_session(false, true, nil) ~= false then
            return "client with toggle ON relaxes the gate without host consent"
        end
        if Policy.effective_session(false, true, "0") ~= false then
            return "client ignores an explicitly disallowing host"
        end
        if Policy.effective_session(true, true, nil) ~= true
                or Policy.effective_session(true, false, "1") ~= false then
            return "host no longer follows its own local setting"
        end
    end)
end

-- Exports for the regression suite / manual drive.
M.publish            = _publish
M.effective_session  = _effective_session
M.effective_for_lobby = _effective_for_lobby
M.lobby_flag_by_id   = _lobby_flag_by_id
return M
