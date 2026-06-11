local mod = get_mod("gt")
local M = {}

-- ============================================================================
-- Message of the Day (migrated from lobby_tweaker 2026-05-25; lt v0.1.7-dev).
-- ============================================================================
-- Host-side. When a peer joins the party, send the configured MOTD to that
-- peer via chat and/or popup. Self and bots are skipped. Once-per-peer-per-
-- session is the default; flip the setting to re-send on every party-join
-- event (useful when a peer reconnects and you want them re-greeted).
--
-- Cross-peer delivery: vanilla `chat_manager:add_local_system_message` and
-- `popup_manager:queue_popup` are LOCAL ONLY. To make a remote joiner see
-- the MOTD, we send a VMF mod-to-mod RPC ("gt_lobby_motd_show") and the
-- receiver renders it locally. Joiners without general_tweaker installed
-- will NOT see the MOTD -- there is no vanilla path for a host to push a
-- system message to a remote chat HUD.
--
-- RPC payload cliff: VMF packs all args into one JSON string parameter,
-- and the Stingray engine caps each RPC string parameter at 500 chars
-- (network_utils.lua:93 STRING_MAX). The full MOTD text is sent as a
-- single string arg, so we split it into <=400-char chunks per line group
-- and stream them with a session id. See memory `vmf-rpc-string-cap`.
--
-- RPC schema versioning (VMF_RECIPES.md S 10, Issue #43): first positional
-- arg of every send IS `mod.GT_LOBBY_RPC_SCHEMA`; receiver validates and
-- drops mismatched payloads with a `_dbg_alert`. Bump
-- `mod.GT_LOBBY_RPC_SCHEMA` (defined in general_tweaker.lua) when the
-- payload shape of any gt_lobby_* RPC changes.

-- ----------------------------------------------------------------------------
-- Forward declarations (Lua 5.1 -- declare before use)
-- ----------------------------------------------------------------------------
local _show_motd_locally
local _send_motd_to_peer
local _on_player_joined_party
local _rpc_motd_chunk

-- ----------------------------------------------------------------------------
-- State
-- ----------------------------------------------------------------------------
-- Set of peer_ids already greeted this session. Cleared on hot-reload (module
-- re-loads, table re-initialises). Survives lobby teardown -- intentional, the
-- "session" here is the host process lifetime, matching the setting name.
local _greeted_peers = {}

-- Inbound chunk buffers, keyed by sender_peer_id. session id resets on every
-- broadcast so partial buffers from a stale send are discarded the moment the
-- next one starts.
local _inbound = {}

local CHUNK_SIZE = 400

-- ----------------------------------------------------------------------------
-- Debug helpers (defer to gt's helpers exposed on mod)
-- ----------------------------------------------------------------------------
local function _dbg_alert(fmt, ...)
    if type(mod._gt_dbg_alert) == "function" then
        mod._gt_dbg_alert(fmt, ...)
    elseif mod:get("enable_debug_logging") then
        mod:info("[gt:dbg] " .. fmt, ...)
        mod:echo("[gt] " .. fmt, ...)
    end
end

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------
local function _split_lines(s)
    local out = {}
    if type(s) ~= "string" or s == "" then return out end
    -- Author writes "\n" in the VMF text widget; VMF stores it as a literal
    -- backslash-n in the string. Honour both literal newlines and the escaped
    -- form so the widget UX matches the in-game render.
    s = s:gsub("\\n", "\n")
    for line in (s .. "\n"):gmatch("([^\n]*)\n") do
        out[#out + 1] = line
    end
    -- Drop trailing empty line caused by the appended "\n".
    if out[#out] == "" then out[#out] = nil end
    return out
end

local function _is_host()
    local pm = Managers.player
    return pm and pm.is_server == true
end

-- ----------------------------------------------------------------------------
-- Local render (runs on whoever receives the MOTD -- host preview or remote)
-- ----------------------------------------------------------------------------
_show_motd_locally = function(text, want_chat, want_popup)
    if not text or text == "" then return end

    if want_chat and Managers.chat and Managers.chat.add_local_system_message then
        local lines = _split_lines(text)
        for i = 1, #lines do
            local line = lines[i]
            if line ~= "" then
                Managers.chat:add_local_system_message(1, line, true)
            end
        end
    end

    if want_popup and Managers.popup and Managers.popup.queue_popup then
        local topic = mod:localize("gt_lobby_motd_popup_topic")
        if not topic or topic == "" or topic:find("^<") then
            topic = "Message of the Day"
        end
        Managers.popup:queue_popup(text, topic, "ok", Localize("popup_choice_ok"))
    end
end

-- ----------------------------------------------------------------------------
-- RPC: receive a chunk, reassemble, render
-- ----------------------------------------------------------------------------
-- Payload shape: (sender_peer_id, schema_version, session, seq, total,
-- want_chat_int, want_popup_int, chunk_str).
-- v0.2.60-dev (lt-merge): inserted GT_LOBBY_RPC_SCHEMA as first payload arg
-- per VMF_RECIPES § 10 (Issue #43). On schema mismatch, drop the message;
-- no state mutation, no crash. Ints used for booleans because VMF network
-- encoding round-trips numbers more cheaply.
_rpc_motd_chunk = function(sender_peer_id, schema_version, session, seq, total, want_chat_int, want_popup_int, chunk_str)
    local expected = mod.GT_LOBBY_RPC_SCHEMA
    if schema_version ~= expected then
        _dbg_alert("[rpc:schema] gt_lobby_motd_show mismatch from peer=%s: peer sent v%s, we expect v%s. Dropping.",
            tostring(sender_peer_id), tostring(schema_version), tostring(expected))
        return
    end
    if type(session) ~= "number" or type(seq) ~= "number"
       or type(total) ~= "number" or type(chunk_str) ~= "string" then
        return
    end
    local key = tostring(sender_peer_id)
    local entry = _inbound[key]
    if not entry or entry.session ~= session then
        entry = {
            session = session, total = total, received = 0, chunks = {},
            want_chat = want_chat_int == 1,
            want_popup = want_popup_int == 1,
        }
        _inbound[key] = entry
    end
    if entry.chunks[seq] == nil then
        entry.chunks[seq] = chunk_str
        entry.received = entry.received + 1
    end
    if entry.received < entry.total then return end

    local pieces = {}
    for i = 1, entry.total do pieces[i] = entry.chunks[i] or "" end
    _inbound[key] = nil
    local text = table.concat(pieces)
    _show_motd_locally(text, entry.want_chat, entry.want_popup)
end

mod:network_register("gt_lobby_motd_show", _rpc_motd_chunk)

-- ----------------------------------------------------------------------------
-- Send MOTD to a single peer (chunked)
-- ----------------------------------------------------------------------------
_send_motd_to_peer = function(target_peer_id, text, want_chat, want_popup)
    if not text or text == "" then return end
    local total = math.ceil(#text / CHUNK_SIZE)
    if total < 1 then total = 1 end
    local session = math.floor(os.time() % 1000000) * 100 + math.random(0, 99)
    local wc = want_chat and 1 or 0
    local wp = want_popup and 1 or 0
    for seq = 1, total do
        local lo = (seq - 1) * CHUNK_SIZE + 1
        local hi = math.min(seq * CHUNK_SIZE, #text)
        local chunk = text:sub(lo, hi)
        mod:network_send("gt_lobby_motd_show", target_peer_id,
            mod.GT_LOBBY_RPC_SCHEMA,   -- VMF_RECIPES § 10: first positional arg, always
            session, seq, total, wc, wp, chunk)
    end
end

-- ----------------------------------------------------------------------------
-- party-join event handler
-- ----------------------------------------------------------------------------
_on_player_joined_party = function(peer_id, local_player_id, party_id, slot_id, is_bot)
    -- Honour the master toggle at call time (NOT via gated registration).
    if not mod:get("gt_lobby_motd_enabled") then return end
    if not _is_host() then return end
    if is_bot then return end

    -- Skip self -- host should never get its own MOTD on join.
    local own = Network and Network.peer_id and Network.peer_id() or nil
    if own and peer_id == own then return end

    -- Spectator / non-keep parties (party_id 0 is the keep heroes party in
    -- adventure; versus splits across multiple parties). For MVP we greet
    -- every human joiner regardless of party -- host can disable the feature
    -- in versus if it's noisy.
    local _ = party_id; local __ = slot_id; local ___ = local_player_id

    if mod:get("gt_lobby_motd_once_per_peer_per_session") and _greeted_peers[peer_id] then
        return
    end
    _greeted_peers[peer_id] = true

    local text = mod:get("gt_lobby_motd_text")
    if not text or text == "" then return end

    local want_chat = mod:get("gt_lobby_motd_send_chat") and true or false
    local want_popup = mod:get("gt_lobby_motd_send_popup") and true or false
    if not (want_chat or want_popup) then return end

    _send_motd_to_peer(peer_id, text, want_chat, want_popup)
end

-- ----------------------------------------------------------------------------
-- state.event registration
-- ----------------------------------------------------------------------------
-- `Managers.state.event` is built per game state (StateInGame, StateLoading,
-- StateTitleScreen). The "on_player_joined_party" event is triggered from
-- `party_manager.lua:562` which runs only during StateInGame. The event
-- manager is rebuilt on every state transition, so we must re-register on
-- every fresh handle via gt's central update registry.
local _last_state_event = nil
local function _update_register(_dt)
    local ev = Managers.state and Managers.state.event
    if ev and ev ~= _last_state_event then
        _last_state_event = ev
        -- Stingray ev:register expects (object, event_name, METHOD_NAME_STRING).
        -- Function-value 3rd arg triggers "No function found with name '[function]'".
        mod.gt_lobby_motd_on_player_joined_party = _on_player_joined_party
        ev:register(mod, "on_player_joined_party", "gt_lobby_motd_on_player_joined_party")
    end
end

if type(mod._gt_register_update) == "function" then
    mod._gt_register_update("gt_lobby_motd_register_event", _update_register)
end

-- Immediate attempt in case state.event already exists at module load
-- (hot-reload mid-mission).
if Managers.state and Managers.state.event then
    _last_state_event = Managers.state.event
    mod.gt_lobby_motd_on_player_joined_party = _on_player_joined_party
    Managers.state.event:register(mod, "on_player_joined_party", "gt_lobby_motd_on_player_joined_party")
end

-- ----------------------------------------------------------------------------
-- Chat command: preview MOTD locally on the host (renamed lt_motd_test ->
-- gt_lobby_motd_test per merge)
-- ----------------------------------------------------------------------------
mod:command("gt_lobby_motd_test", "Preview MOTD locally (host only)", function()
    local text = mod:get("gt_lobby_motd_text")
    if not text or text == "" then
        Managers.chat:add_local_system_message(1, "[gt:lobby] gt_lobby_motd_text is empty.", true)
        return
    end
    local want_chat = mod:get("gt_lobby_motd_send_chat") and true or false
    local want_popup = mod:get("gt_lobby_motd_send_popup") and true or false
    if not (want_chat or want_popup) then
        Managers.chat:add_local_system_message(1, "[gt:lobby] Both chat and popup are disabled.", true)
        return
    end
    _show_motd_locally(text, want_chat, want_popup)
end)

-- ----------------------------------------------------------------------------
-- Chat command: set MOTD text (replaces the v0.2.61 removed text_input widget,
-- which was an invalid VMF type and caused widget#103 failure on data.lua load)
-- ----------------------------------------------------------------------------
mod:command("gt_lobby_motd_set", "Set the MOTD text (host-side; sent to joiners when enabled)", function(...)
    local text = table.concat({...}, " ")
    if text == "" then
        mod:echo("[gt_lobby_motd] Current MOTD: %s", tostring(mod:get("gt_lobby_motd_text") or "(empty)"))
        mod:echo("Usage: /gt_lobby_motd_set <text>")
        return
    end
    mod:set("gt_lobby_motd_text", text)
    mod:echo("[gt_lobby_motd] MOTD set to: %s", text)
    mod:info("[gt:lobby:motd] set text len=%d via /gt_lobby_motd_set", #text)
end)

mod:command("gt_lobby_motd_clear", "Clear the MOTD text (host-side)", function()
    mod:set("gt_lobby_motd_text", "")
    mod:echo("[gt_lobby_motd] MOTD cleared.")
    mod:info("[gt:lobby:motd] cleared via /gt_lobby_motd_clear")
end)

-- ----------------------------------------------------------------------------
-- Exports (for other modules to call if needed)
-- ----------------------------------------------------------------------------
M.show_locally = _show_motd_locally
M.send_to_peer = _send_motd_to_peer
M.reset_session = function() _greeted_peers = {} end

return M
