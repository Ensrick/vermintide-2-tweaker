local mod = get_mod("lobby_tweaker")
local M = {}

-- ============================================================================
-- Message of the Day
-- ============================================================================
-- Host-side. When a peer joins the party, send the configured MOTD to that
-- peer via chat and/or popup. Self and bots are skipped. Once-per-peer-per-
-- session is the default; flip the setting to re-send on every party-join
-- event (useful when a peer reconnects and you want them re-greeted).
--
-- Cross-peer delivery: vanilla `chat_manager:add_local_system_message` and
-- `popup_manager:queue_popup` are LOCAL ONLY. To make a remote joiner see
-- the MOTD, we send a VMF mod-to-mod RPC ("lt_motd_show") and the receiver
-- renders it locally. Joiners without lobby_tweaker installed will NOT see
-- the MOTD — there is no vanilla path for a host to push a system message
-- to a remote chat HUD. Documented as a known limitation; the Phase 2
-- manifest feature is the long-term answer (tell the joiner what they're
-- missing so they can install lobby_tweaker too).
--
-- RPC payload cliff: VMF packs all args into one JSON string parameter,
-- and the Stingray engine caps each RPC string parameter at 500 chars
-- (network_utils.lua:93 STRING_MAX). The full MOTD text is sent as a
-- single string arg, so we split it into <=400-char chunks per line group
-- and stream them with a session id. See memory `vmf-rpc-string-cap`.

-- ----------------------------------------------------------------------------
-- Forward declarations (Lua 5.1 — declare before use)
-- ----------------------------------------------------------------------------
local _show_motd_locally
local _send_motd_to_peer
local _on_player_joined_party
local _rpc_motd_chunk

-- ----------------------------------------------------------------------------
-- State
-- ----------------------------------------------------------------------------
-- Set of peer_ids already greeted this session. Cleared on hot-reload (module
-- re-loads, table re-initialises). Survives lobby teardown — intentional, the
-- "session" here is the host process lifetime, matching the setting name.
local _greeted_peers = {}

-- Inbound chunk buffers, keyed by sender_peer_id. session id resets on every
-- broadcast so partial buffers from a stale send are discarded the moment the
-- next one starts.
local _inbound = {}

local CHUNK_SIZE = 400

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
-- Local render (runs on whoever receives the MOTD — host preview or remote)
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
        local topic = mod:localize("motd_popup_topic")
        if not topic or topic == "" or topic:find("^<") then
            topic = "Message of the Day"
        end
        Managers.popup:queue_popup(text, topic, "ok", Localize("popup_choice_ok"))
    end
end

-- ----------------------------------------------------------------------------
-- RPC: receive a chunk, reassemble, render
-- ----------------------------------------------------------------------------
-- Payload shape: (sender_peer_id, session, seq, total, want_chat_int,
-- want_popup_int, chunk_str). Ints used instead of bools because VMF
-- network encoding round-trips numbers more cheaply than booleans.
_rpc_motd_chunk = function(sender_peer_id, session, seq, total, want_chat_int, want_popup_int, chunk_str)
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

mod:network_register("lt_motd_show", _rpc_motd_chunk)

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
        mod:network_send("lt_motd_show", target_peer_id, session, seq, total, wc, wp, chunk)
    end
end

-- ----------------------------------------------------------------------------
-- party-join event handler
-- ----------------------------------------------------------------------------
_on_player_joined_party = function(peer_id, local_player_id, party_id, slot_id, is_bot)
    -- Honour the master toggle at call time (NOT via gated registration).
    if not mod:get("motd_enabled") then return end
    if not _is_host() then return end
    if is_bot then return end

    -- Skip self — host should never get its own MOTD on join.
    local own = Network and Network.peer_id and Network.peer_id() or nil
    if own and peer_id == own then return end

    -- Spectator / non-keep parties (party_id 0 is the keep heroes party in
    -- adventure; versus splits across multiple parties). For MVP we greet
    -- every human joiner regardless of party — host can disable the feature
    -- in versus if it's noisy. Documented as a follow-up.
    local _ = party_id; local __ = slot_id; local ___ = local_player_id

    if mod:get("motd_once_per_peer_per_session") and _greeted_peers[peer_id] then
        return
    end
    _greeted_peers[peer_id] = true

    local text = mod:get("motd_text")
    if not text or text == "" then return end

    local want_chat = mod:get("motd_send_chat") and true or false
    local want_popup = mod:get("motd_send_popup") and true or false
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
-- every fresh handle. mod.update is VMF's per-tick callback; cheap pointer
-- compare gates the re-register.
local _last_state_event = nil
local _prev_update = mod.update
mod.update = function(dt)
    if _prev_update then _prev_update(dt) end
    local ev = Managers.state and Managers.state.event
    if ev and ev ~= _last_state_event then
        _last_state_event = ev
        ev:register(mod, "on_player_joined_party", _on_player_joined_party)
    end
end

-- Immediate attempt in case state.event already exists at module load
-- (hot-reload mid-mission).
if Managers.state and Managers.state.event then
    _last_state_event = Managers.state.event
    Managers.state.event:register(mod, "on_player_joined_party", _on_player_joined_party)
end

-- ----------------------------------------------------------------------------
-- Chat command: preview MOTD locally on the host
-- ----------------------------------------------------------------------------
mod:command("lt_motd_test", "Preview MOTD locally (host only)", function()
    local text = mod:get("motd_text")
    if not text or text == "" then
        Managers.chat:add_local_system_message(1, "[lobby_tweaker] motd_text is empty.", true)
        return
    end
    local want_chat = mod:get("motd_send_chat") and true or false
    local want_popup = mod:get("motd_send_popup") and true or false
    if not (want_chat or want_popup) then
        Managers.chat:add_local_system_message(1, "[lobby_tweaker] Both chat and popup are disabled.", true)
        return
    end
    _show_motd_locally(text, want_chat, want_popup)
end)

-- ----------------------------------------------------------------------------
-- Exports (for other modules to call if needed)
-- ----------------------------------------------------------------------------
M.show_locally = _show_motd_locally
M.send_to_peer = _send_motd_to_peer
M.reset_session = function() _greeted_peers = {} end

return M
