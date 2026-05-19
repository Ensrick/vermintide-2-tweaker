local mod = get_mod("lobby_tweaker")

-- ============================================================================
-- Session Ignore List
-- ============================================================================
-- Two tiers:
--   * Session  -> mod._session_ignore[steam_id] = true     (in-memory, host-only)
--   * Persist  -> mod:set("si_persistent", { [sid] = true }) via VMF settings
--
-- On player joining the host's party, if their Steam ID (peer_id) is in either
-- tier we kick them and announce in chat. The handler honors the per-feature
-- toggle `session_ignore_enabled` at fire time (not gated at registration —
-- the toggle is meant to be flippable mid-session without a hash change).
-- ============================================================================

mod._session_ignore       = mod._session_ignore       or {}
mod._si_last_kicked       = mod._si_last_kicked       or nil   -- for /lt_ignore_last

local M = {}

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------

local function _is_host()
    local pm = Managers.player
    return pm and pm.is_server and true or false
end

local function _say(msg)
    if Managers.chat and Managers.chat.add_local_system_message then
        -- channel_id 1 = local; `true` pops the chat window
        Managers.chat:add_local_system_message(1, "[Lobby Tweaker] " .. msg, true)
    else
        mod:echo("[Lobby Tweaker] " .. msg)
    end
end

local function _persistent()
    return mod:get("si_persistent") or {}
end

local function _set_persistent(t)
    mod:set("si_persistent", t, true)   -- 3rd arg = save settings file
end

local function _is_ignored(sid)
    if not sid then return false end
    if mod._session_ignore[sid] then return true end
    local p = _persistent()
    return p[sid] == true
end

-- Returns NetworkServer or nil. Path verified against
-- scripts/managers/admin/dedicated_server_commands.lua:197.
local function _network_server()
    local sn = Managers.state and Managers.state.network
    return sn and sn.network_server or nil
end

local function _kick(sid, reason)
    local ns = _network_server()
    if not ns or not ns.kick_peer then
        mod:echo("[Lobby Tweaker] cannot kick " .. tostring(sid) .. " (no NetworkServer)")
        return false
    end
    ns:kick_peer(sid)
    mod._si_last_kicked = sid
    _say(string.format("Kicked %s: %s.", tostring(sid), reason or "on ignore list"))
    return true
end

-- Resolve a chat-typed argument (could be a Steam ID, a substring of one, or
-- a player display name) against the current party / player set. Returns the
-- matched Steam ID string or nil.
local function _resolve_arg_to_sid(arg)
    if not arg or arg == "" then return nil end

    -- If the arg looks numeric (digits only, possibly long) treat as Steam ID.
    if arg:match("^%d+$") then return arg end

    -- Otherwise try by display name. human_and_bot_players() returns a peer-keyed
    -- table of Player objects in vanilla; iterate values defensively.
    local pm = Managers.player
    if not pm or not pm.human_and_bot_players then return nil end
    local arg_low = string.lower(arg)
    for _, player in pairs(pm:human_and_bot_players()) do
        if player and not player.bot_player then
            local pid    = player:network_id() or player.peer_id
            local name   = player:name() or ""
            if pid and string.lower(name):find(arg_low, 1, true) then
                return tostring(pid)
            end
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- event handler — on_player_joined_party
-- ---------------------------------------------------------------------------

local function _on_player_joined_party(peer_id, local_player_id, party_id, slot_id, is_bot)
    if is_bot then return end
    if not _is_host() then return end
    if not mod:get("session_ignore_enabled") then return end
    if not peer_id or not _is_ignored(peer_id) then return end
    _kick(peer_id, "on ignore list")
end

-- Register on every game-state entry. The event manager is rebuilt between
-- state transitions, so a single boot-time register would silently drop after
-- the first map load. Use mod.on_game_state_changed if needed; here we lazily
-- (re)register on first call to a helper too.
local _registered_for = nil
local function _ensure_event_registered()
    local em = Managers.state and Managers.state.event
    if not em then return end
    if _registered_for == em then return end
    em:register(mod, "on_player_joined_party", _on_player_joined_party)
    _registered_for = em
end

mod.on_game_state_changed = function(status, state)
    if status == "enter" then
        _ensure_event_registered()
    end
end

-- Try once at file load too (covers reload-into-keep case where state is up).
_ensure_event_registered()

-- ---------------------------------------------------------------------------
-- chat commands  (all host-only; client invocations bail silently with a hint)
-- ---------------------------------------------------------------------------

local function _require_host()
    if _is_host() then return true end
    _say("This command is host-only.")
    return false
end

mod:command("lt_ignore", "Add a player to the session ignore list (Steam ID or name).", function(arg)
    if not _require_host() then return end
    local sid = _resolve_arg_to_sid(arg)
    if not sid then _say("Could not resolve '" .. tostring(arg) .. "' to a peer.") return end
    mod._session_ignore[sid] = true
    _say("Session-ignored " .. sid .. ".")
    -- Kick immediately if they're currently in the lobby.
    if _is_ignored(sid) then _kick(sid, "added to ignore list") end
end)

mod:command("lt_ignore_persist", "Add a Steam ID to the persistent ignore list.", function(arg)
    if not _require_host() then return end
    local sid = _resolve_arg_to_sid(arg)
    if not sid then _say("Could not resolve '" .. tostring(arg) .. "' to a peer.") return end
    local p = _persistent()
    p[sid] = true
    _set_persistent(p)
    _say("Persistently ignored " .. sid .. ".")
    if _is_ignored(sid) then _kick(sid, "added to persistent ignore list") end
end)

mod:command("lt_unignore", "Remove a Steam ID from both ignore tiers.", function(arg)
    if not _require_host() then return end
    if not arg or arg == "" then _say("Usage: /lt_unignore <steam_id>") return end
    local sid = tostring(arg)
    mod._session_ignore[sid] = nil
    local p = _persistent()
    if p[sid] then p[sid] = nil; _set_persistent(p) end
    _say("Removed " .. sid .. " from ignore list.")
end)

mod:command("lt_ignored", "Print the session + persistent ignore lists.", function()
    if not _require_host() then return end
    local s_keys, p_keys = {}, {}
    for k, _ in pairs(mod._session_ignore) do s_keys[#s_keys + 1] = k end
    for k, _ in pairs(_persistent())          do p_keys[#p_keys + 1] = k end
    table.sort(s_keys); table.sort(p_keys)
    _say("Session ignore (" .. #s_keys .. "): " .. (s_keys[1] and table.concat(s_keys, ", ") or "(none)"))
    _say("Persistent ignore (" .. #p_keys .. "): " .. (p_keys[1] and table.concat(p_keys, ", ") or "(none)"))
end)

mod:command("lt_ignore_last", "Re-add the most recently kicked-by-host peer to the session ignore list.", function()
    if not _require_host() then return end
    local sid = mod._si_last_kicked
    if not sid then _say("No recent host-kicked peer recorded this session.") return end
    mod._session_ignore[sid] = true
    _say("Re-ignored " .. sid .. ".")
end)

-- ---------------------------------------------------------------------------
-- public API for sibling features (e.g. kick-on-idle could share _kick / _say)
-- ---------------------------------------------------------------------------

M.is_ignored          = _is_ignored
M.network_server      = _network_server
M.kick                = _kick
M.say                 = _say
M.resolve_arg_to_sid  = _resolve_arg_to_sid
M.is_host             = _is_host

return M
