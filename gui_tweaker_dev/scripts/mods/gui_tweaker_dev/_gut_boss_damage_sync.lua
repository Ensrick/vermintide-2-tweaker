-- _gut_boss_damage_sync.lua - #1448 host boss-subtotal snapshot transport.
--
-- Clients pull aggregate snapshots from the current host through one exact
-- versioned VMF channel. The host reads ScoreboardHelper's vanilla grouped
-- damage_dealt_bosses row; this module owns no damage hook, parallel ledger,
-- vanilla RPC, StatisticsDefinitions, or NetworkLookup mutation.
local mod = get_mod("gut_dev")
local Contract = mod:dofile(
    "scripts/mods/gui_tweaker_dev/_gut_boss_damage_sync_policy")
local ScorePolicy = mod:dofile(
    "scripts/mods/gui_tweaker_dev/_gut_scoreboard_policy")
local root_schema = rawget(mod, "_GUT_RPC_SCHEMA")
if root_schema ~= nil and root_schema ~= Contract.SCHEMA then
    error("GUT RPC schema disagrees with the boss snapshot contract")
end

local M = { rt_checks = {} }
local RECEIPT_CAP = 23
local RUNTIME_RECEIPT_CAP = 1
local receipt_count = 0
local clock = 0
local active = false
local mission_counter = 0
local generation_counter = 0
local generation
local next_sequence = 0
local pull
local pull_terminal_reported = false
local assembly
local accepted
local next_refresh
local observed_host
local observed_host_set = false
local observed_server
local host_cache = {}
local roster_fingerprint
local roster_epoch = 0
local next_roster_poll = 0
local runtime_reported = false

local function _receipt(fmt, ...)
    if receipt_count >= RECEIPT_CAP then return end
    receipt_count = receipt_count + 1
    if not pcall(printf, "[gut:1448] raw evidence=%d/%d " .. fmt,
            receipt_count, RECEIPT_CAP, ...) then
        pcall(printf, "[gut:1448] raw evidence=%d/%d format-error",
            receipt_count, RECEIPT_CAP)
    end
end

local function _drop(reason, sender_peer_id, message_generation, sequence)
    _receipt("event=drop reason=%s sender=%s generation=%s sequence=%s",
        tostring(reason), tostring(sender_peer_id),
        tostring(message_generation):sub(1, Contract.MAX_GENERATION_BYTES),
        tostring(sequence))
end

local function _managers()
    return rawget(_G, "Managers")
end

local function _is_server()
    local managers = _managers()
    local player_manager = managers and managers.player
    return player_manager and player_manager.is_server == true or false
end

local function _is_adventure()
    local managers = _managers()
    local mechanism = managers and managers.mechanism
    if not mechanism or type(mechanism.current_mechanism_name) ~= "function" then
        return false
    end
    local ok, name = pcall(mechanism.current_mechanism_name, mechanism)
    return ok and name == "adventure"
end

local function _field_or_call(owner, field)
    if owner == nil then return nil end
    local read_ok, value = pcall(function() return owner[field] end)
    if not read_ok then return nil end
    if type(value) == "function" then
        local ok, result = pcall(value, owner)
        return ok and result or nil
    end
    return value
end

-- Canonical host identity first, followed by the documented network-client /
-- network-server readiness fallback. There is deliberately no invented
-- "server" VMF recipient alias.
local function _host_peer_id()
    local managers = _managers()
    local mechanism = managers and managers.mechanism
    local host = _field_or_call(mechanism, "server_peer_id")
    if not host then
        local network = managers and managers.state and managers.state.network
        host = _field_or_call(network and network.network_client, "server_peer_id")
            or _field_or_call(network and network.network_server, "server_peer_id")
    end
    if host == nil then return nil end
    host = tostring(host)
    return #host > 0 and #host <= Contract.MAX_PLAYER_ID_BYTES and host or nil
end

local function _player_peer_id(player)
    if type(player) ~= "table" then return nil end
    if type(player.network_id) == "function" then
        local ok, peer_id = pcall(player.network_id, player)
        if ok and peer_id ~= nil then return tostring(peer_id) end
    end
    local peer_id = rawget(player, "peer_id")
    return peer_id ~= nil and tostring(peer_id) or nil
end

local function _known_human_peer(peer_id)
    if type(peer_id) ~= "string" then return false end
    local managers = _managers()
    local player_manager = managers and managers.player
    if not player_manager or type(player_manager.human_players) ~= "function" then
        return false
    end
    local ok, players = pcall(player_manager.human_players, player_manager)
    if not ok or type(players) ~= "table" then return false end
    for _, player in pairs(players) do
        if _player_peer_id(player) == peer_id then return true end
    end
    return false
end

local function _statistics_database()
    local managers = _managers()
    local player_manager = managers and managers.player
    if not player_manager or type(player_manager.statistics_db) ~= "function" then
        return nil
    end
    local ok, database = pcall(player_manager.statistics_db, player_manager)
    return ok and database or nil
end

local function _grouped_players()
    local helper = rawget(_G, "ScoreboardHelper")
    local managers = _managers()
    local network = managers and managers.state and managers.state.network
    local database = _statistics_database()
    local synchronizer = network and network.profile_synchronizer
    if type(helper) ~= "table"
            or type(helper.get_grouped_topic_statistics) ~= "function"
            or not database or not synchronizer then
        return nil, "not-ready"
    end
    local ok, players = pcall(helper.get_grouped_topic_statistics,
        database, synchronizer, nil)
    if not ok or type(players) ~= "table" then return nil, "not-ready" end
    return players
end

local function _reset_roster()
    roster_fingerprint = nil
    roster_epoch = 0
    next_roster_poll = clock
end

-- VMF's on_user_joined callback is also a discovery-pong callback, so it is
-- not a physical-roster boundary. Poll the scoreboard's bounded stable stats
-- IDs instead; these rows include humans and bots and are already required by
-- the snapshot producer/consumer.
local function _poll_roster(force)
    if not force and clock < next_roster_poll then return false end
    next_roster_poll = clock + Contract.ROSTER_POLL_DELAY
    local players = _grouped_players()
    if not players then return false end
    local fingerprint = Contract.roster_fingerprint(players)
    if not fingerprint then return false end
    if roster_fingerprint == nil then
        roster_fingerprint = fingerprint
        roster_epoch = 1
        return false
    end
    if fingerprint == roster_fingerprint then return false end
    local prior = roster_fingerprint
    roster_fingerprint = fingerprint
    roster_epoch = roster_epoch + 1
    _receipt("event=roster-change old=%s new=%s epoch=%d",
        tostring(prior), tostring(fingerprint), roster_epoch)
    return true
end

local function _codec(method, value)
    local codec = rawget(_G, "cjson")
    local fn = type(codec) == "table" and rawget(codec, method) or nil
    if type(fn) ~= "function" then return nil, "codec-unavailable" end
    local ok, result = pcall(fn, value)
    if not ok or (method == "encode" and type(result) ~= "string")
            or (method == "decode" and type(result) ~= "table") then
        return nil, "codec-failed"
    end
    return result
end

local function _send_request(host_peer_id, request_generation, sequence)
    local wire_bytes, wire_reason = Contract.packed_message_bytes(
        Contract.SCHEMA, Contract.REQUEST, request_generation, sequence,
        0, 0, 0, "")
    if not wire_bytes or wire_bytes > Contract.MAX_PACKED_BYTES then
        _drop("request-wire-" .. tostring(wire_reason or wire_bytes),
            host_peer_id, request_generation, sequence)
        return false
    end
    local ok = pcall(mod.network_send, mod, Contract.CHANNEL, host_peer_id,
        Contract.SCHEMA, Contract.REQUEST, request_generation, sequence,
        0, 0, 0, "")
    if ok then
        _receipt("event=request target=%s generation=%s sequence=%d",
            tostring(host_peer_id), tostring(request_generation), sequence)
    end
    return ok
end

local function _ping_vmf_users()
    local vmf = get_mod("VMF")
    if vmf and type(vmf.ping_vmf_users) == "function" then
        pcall(vmf.ping_vmf_users)
    end
end

local function _send_cached_response(peer_id, response)
    for part, chunk in ipairs(response.chunks) do
        local wire_bytes = Contract.packed_message_bytes(
            Contract.SCHEMA, Contract.SNAPSHOT, response.generation,
            response.sequence, part, #response.chunks,
            response.payload_size, chunk)
        if not wire_bytes or wire_bytes > Contract.MAX_PACKED_BYTES then
            return false
        end
        local ok = pcall(mod.network_send, mod, Contract.CHANNEL, peer_id,
            Contract.SCHEMA, Contract.SNAPSHOT, response.generation,
            response.sequence, part, #response.chunks,
            response.payload_size, chunk)
        if not ok then return false end
    end
    return true
end

local function _build_host_response(message_generation, sequence)
    local players, reason = _grouped_players()
    if not players then return nil, reason end
    local snapshot
    snapshot, reason = Contract.extract_grouped_snapshot(players)
    if not snapshot then return nil, reason end
    local payload
    payload, reason = _codec("encode", snapshot)
    if not payload then return nil, reason end
    local chunks
    chunks, reason = Contract.chunk_payload(payload)
    if not chunks then return nil, reason end
    return {
        generation = message_generation,
        sequence = sequence,
        payload_size = #payload,
        chunks = chunks,
    }
end

local function _receive_request(sender_peer_id, message_generation, sequence)
    if not active or not _is_server() or not _is_adventure() then
        return _drop("request-role", sender_peer_id, message_generation, sequence)
    end
    if not _known_human_peer(sender_peer_id) then
        return _drop("unknown-request-peer", sender_peer_id,
            message_generation, sequence)
    end

    local session = host_cache[sender_peer_id]
    if type(session) ~= "table" then
        -- Do not let an authenticated but structurally impossible first
        -- sequence activate the lazy host poll for a default-off feature.
        if sequence ~= 1 then
            return _drop("request-new-generation-sequence", sender_peer_id,
                message_generation, sequence)
        end
        session = Contract.new_host_session()
        host_cache[sender_peer_id] = session
        -- The default-off feature owns no background host poll. Establish the
        -- bounded roster epoch only after a valid first request creates the
        -- session. Subsequent polling is update-owned at the same floor.
        _poll_roster(false)
    end
    local plan, plan_reason = Contract.plan_host_request(session,
        message_generation, sequence, clock, roster_epoch)
    if not plan then
        return _drop("request-" .. tostring(plan_reason), sender_peer_id,
            message_generation, sequence)
    end
    if plan.kind == "replay" then
        Contract.record_host_send(session, clock)
        local sent = _send_cached_response(sender_peer_id, plan.response)
        return _receipt("event=response-duplicate target=%s generation=%s sequence=%d chunks=%d sent=%s",
            sender_peer_id, message_generation, sequence,
            #plan.response.chunks, tostring(sent))
    end

    Contract.reserve_host_build(session, plan, clock)

    local response, reason = _build_host_response(message_generation, sequence)
    if not response then
        return _drop("host-" .. tostring(reason), sender_peer_id,
            message_generation, sequence)
    end
    local committed, commit_reason = Contract.commit_host_response(
        session, plan, response, clock)
    if not committed then
        return _drop("host-" .. tostring(commit_reason), sender_peer_id,
            message_generation, sequence)
    end
    Contract.record_host_send(session, clock)
    local sent = _send_cached_response(sender_peer_id, response)
    _receipt("event=response target=%s generation=%s sequence=%d chunks=%d bytes=%d roster_epoch=%d bypass=%s sent=%s",
        sender_peer_id, message_generation, sequence, #response.chunks,
        response.payload_size, roster_epoch, tostring(plan.roster_bypass),
        tostring(sent))
end

local function _copy_scores(scores)
    local copy, count = {}, 0
    for player_id, value in pairs(type(scores) == "table" and scores or {}) do
        if count >= Contract.MAX_PLAYERS then break end
        if Contract.valid_player_id(player_id) and type(value) == "number" then
            copy[player_id] = value
            count = count + 1
        end
    end
    return count > 0 and copy or nil
end

local function _accept_payload(sender_peer_id, message_generation, sequence,
        payload)
    local decoded, reason = _codec("decode", payload)
    if not decoded then return false, reason end
    local players
    players, reason = _grouped_players()
    if not players then return false, reason end
    local known
    known, reason = Contract.known_players(players)
    if not known then return false, reason end
    local verdict
    verdict, reason = Contract.validate_snapshot(decoded, known)
    if not verdict then return false, reason end
    local acknowledged, ack_reason = Contract.acknowledge_pull(
        pull, message_generation, sequence)
    if not acknowledged then return false, "ack-" .. tostring(ack_reason) end
    accepted = {
        generation = message_generation,
        sequence = sequence,
        host_peer_id = sender_peer_id,
        scores = verdict.scores,
        fingerprint = verdict.fingerprint,
        player_count = verdict.player_count,
        received_at = clock,
        expires_at = clock + Contract.SNAPSHOT_TTL,
    }
    assembly = nil
    next_refresh = clock + Contract.REFRESH_DELAY
    pull_terminal_reported = false
    _receipt("event=accepted sender=%s generation=%s sequence=%d players=%d bytes=%d fp=%s",
        sender_peer_id, message_generation, sequence, verdict.player_count,
        #payload, verdict.fingerprint)
    return true
end

local function _receive_snapshot(sender_peer_id, message_generation, sequence,
        part, total, payload_size, chunk)
    if not active or _is_server() or not _is_adventure() then
        return _drop("snapshot-role", sender_peer_id, message_generation, sequence)
    end
    local host = _host_peer_id()
    if not host then
        return _drop("missing-host", sender_peer_id, message_generation, sequence)
    end
    local ordered, order_reason = Contract.classify_response(
        host, sender_peer_id, generation, pull and pull.sequence,
        accepted and accepted.generation, accepted and accepted.sequence,
        message_generation, sequence)
    if not ordered then
        if order_reason == "duplicate" then
            return _receipt("event=duplicate sender=%s generation=%s sequence=%d",
                sender_peer_id, message_generation, sequence)
        end
        return _drop(order_reason, sender_peer_id,
            message_generation, sequence)
    end

    if not assembly then
        local reason
        assembly, reason = Contract.new_reassembly(
            message_generation, sequence, total, payload_size)
        if not assembly then
            return _drop(reason, sender_peer_id, message_generation, sequence)
        end
    elseif assembly.generation ~= message_generation
            or assembly.sequence ~= sequence or assembly.total ~= total
            or assembly.payload_size ~= payload_size then
        assembly = nil
        return _drop("assembly-mismatch", sender_peer_id,
            message_generation, sequence)
    end

    local payload, reason = Contract.accept_chunk(
        assembly, part, total, payload_size, chunk)
    if reason == "duplicate" or reason == "pending" then return end
    if not payload then
        assembly = nil
        return _drop(reason, sender_peer_id, message_generation, sequence)
    end
    local ok, accept_reason = _accept_payload(sender_peer_id,
        message_generation, sequence, payload)
    if not ok then
        assembly = nil
        return _drop(accept_reason, sender_peer_id, message_generation, sequence)
    end
end

mod:network_register(Contract.CHANNEL, function(sender_peer_id, schema, kind,
        message_generation, sequence, part, total, payload_size, chunk)
    sender_peer_id = sender_peer_id ~= nil and tostring(sender_peer_id) or ""
    local valid, reason = Contract.validate_envelope(schema, kind,
        message_generation, sequence, part, total, payload_size, chunk)
    if not valid then
        return _drop(reason, sender_peer_id, message_generation, sequence)
    end
    if kind == Contract.REQUEST then
        return _receive_request(sender_peer_id, message_generation, sequence)
    end
    return _receive_snapshot(sender_peer_id, message_generation, sequence,
        part, total, payload_size, chunk)
end)

local function _new_generation()
    generation_counter = generation_counter + 1
    local application = rawget(_G, "Application")
    local launched = application and rawget(application, "time_since_launch")
    local stamp = math.floor(clock * 1000)
    if type(launched) == "function" then
        local ok, value = pcall(launched)
        if ok and type(value) == "number" and value == value then
            stamp = math.floor(value * 1000)
        end
    end
    generation = string.format("g%d-%d-%d",
        mission_counter, generation_counter, stamp)
    next_sequence = 0
end

local function _start_pull(reset_generation, preserve_accepted)
    if reset_generation or not Contract.valid_generation(generation) then
        _new_generation()
        if not preserve_accepted then accepted = nil end
    end
    if next_sequence >= Contract.MAX_SEQUENCE then
        _new_generation()
        accepted = nil
    end
    next_sequence = next_sequence + 1
    pull = Contract.new_pull(generation, next_sequence, clock)
    assembly = nil
    next_refresh = nil
    pull_terminal_reported = false
end

local function _clear_client(clear_generation)
    pull = nil
    assembly = nil
    accepted = nil
    next_refresh = nil
    pull_terminal_reported = false
    if clear_generation then
        generation = nil
        next_sequence = 0
    end
end

local function _scoreboard_enabled()
    return mod:get("gut_scoreboard_live_native") == true
end

local function _update_client()
    local host = _host_peer_id()
    if not observed_host_set then
        observed_host, observed_host_set = host, true
    elseif host ~= observed_host then
        _receipt("event=reset reason=host-change old=%s new=%s",
            tostring(observed_host), tostring(host))
        observed_host = host
        host_cache = {}
        _clear_client(true)
        if _scoreboard_enabled() then _start_pull(true) end
    end

    if not _scoreboard_enabled() then return end
    if accepted and clock > accepted.expires_at then
        _receipt("event=fallback reason=snapshot-expired generation=%s sequence=%d",
            accepted.generation, accepted.sequence)
        accepted = nil
    end
    if not pull and not accepted then _start_pull(false) end
    if accepted and not pull and next_refresh and clock >= next_refresh then
        _start_pull(false)
    end
    if pull and not pull.complete then
        Contract.step_pull(pull, clock, host, _ping_vmf_users, _send_request)
        if pull.terminal and not pull_terminal_reported then
            pull_terminal_reported = true
            _receipt("event=fallback reason=%s generation=%s sequence=%d attempts=%d",
                tostring(pull.reason), pull.generation, pull.sequence,
                pull.attempts)
        end
    elseif pull and pull.complete then
        pull = nil
    end
end

local previous_update = mod.update
mod.update = function(dt, ...)
    if previous_update then previous_update(dt, ...) end
    if type(dt) == "number" and dt == dt and dt > 0 then clock = clock + dt end
    if not active or not _is_adventure() then return end
    local server = _is_server()
    if observed_server == nil then
        observed_server = server
    elseif observed_server ~= server then
        _receipt("event=reset reason=host-role-change old_server=%s new_server=%s",
            tostring(observed_server), tostring(server))
        observed_server = server
        host_cache = {}
        observed_host = _host_peer_id()
        observed_host_set = true
        _clear_client(true)
        _reset_roster()
        if not server and _scoreboard_enabled() then _start_pull(true) end
    end
    local roster_changed = false
    if server then
        -- A host begins polling only after one authenticated requester exists.
        -- Sessions remain bounded and live until mission/role teardown; VMF's
        -- early on_user_left callback is not a physical-peer authority.
        if next(host_cache) ~= nil then
            roster_changed = _poll_roster(false)
        end
    elseif _scoreboard_enabled()
            and ((pull and not pull.terminal) or accepted ~= nil) then
        -- Disabled and terminal no-snapshot clients do no grouped-score work.
        roster_changed = _poll_roster(false)
    end
    if roster_changed and not server and _scoreboard_enabled() then
        local preserve_accepted = accepted ~= nil
        pull, assembly, next_refresh = nil, nil, nil
        _start_pull(true, preserve_accepted)
        _receipt("event=reset reason=roster-change generation=%s sequence=%d preserve=%s",
            tostring(generation), next_sequence, tostring(preserve_accepted))
    end
    if server then return end
    _update_client()
end

-- The live presenter is earlier in this callback chain. On StateIngame exit it
-- copies the accepted boss row into its end-screen sidecar before this owner
-- clears mission/host/peer state.
local previous_state_changed = mod.on_game_state_changed
mod.on_game_state_changed = function(status, state_name, ...)
    if previous_state_changed then previous_state_changed(status, state_name, ...) end
    if state_name ~= "StateIngame" then return end
    if status == "enter" then
        mission_counter = mission_counter + 1
        active = true
        host_cache = {}
        observed_host = _host_peer_id()
        observed_host_set = true
        observed_server = _is_server()
        _clear_client(true)
        _reset_roster()
        if not _is_server() and _scoreboard_enabled() then _start_pull(true) end
        _receipt("event=reset reason=mission-enter mission=%d host=%s",
            mission_counter, tostring(observed_host))
    elseif status == "exit" then
        active = false
        host_cache = {}
        observed_host, observed_host_set = nil, false
        observed_server = nil
        _clear_client(true)
        _reset_roster()
        _receipt("event=reset reason=mission-exit mission=%d",
            mission_counter)
    end
end

local previous_user_left = mod.on_user_left
mod.on_user_left = function(player, ...)
    if previous_user_left then previous_user_left(player, ...) end
    local peer_id = _player_peer_id(player)
    if not peer_id then return end
    -- VMF fires this before vanilla removes a player and also for a bot that
    -- shares a still-present human peer. It is therefore only a prompt for the
    -- stable stats-id roster poll. Canonical host-id observation below owns a
    -- real host departure; host request sessions remain bounded until teardown.
    next_roster_poll = clock
    _receipt("event=peer-left-observed peer=%s", peer_id)
end

local previous_setting_changed = mod.on_setting_changed
mod.on_setting_changed = function(setting_id, ...)
    if previous_setting_changed then previous_setting_changed(setting_id, ...) end
    if setting_id ~= "gut_scoreboard_live_native" or not active or _is_server() then
        return
    end
    if _scoreboard_enabled() then
        if not pull then _start_pull(true) end
    else
        -- A request may have been armed but not yet reached the host. Retire its
        -- complete identity so re-enable starts at sequence one in a fresh
        -- generation rather than stranding a new host session on sequence two.
        _clear_client(true)
        _reset_roster()
    end
end

local previous_disabled = mod.on_disabled
mod.on_disabled = function(...)
    if previous_disabled then previous_disabled(...) end
    active = false
    host_cache = {}
    observed_host, observed_host_set = nil, false
    observed_server = nil
    _clear_client(true)
    _reset_roster()
end

function M.current_scores()
    if not active or _is_server() or not accepted
            or accepted.host_peer_id ~= _host_peer_id()
            or clock > accepted.expires_at then
        return nil
    end
    return _copy_scores(accepted.scores)
end

M.contract = Contract

M.rt_checks[#M.rt_checks + 1] = {
    name = "issue1448_host_boss_damage_snapshot_sync",
    fn = function()
        local native_players = {
            ["peer-host:1"] = {
                stats_id = "peer-host:1",
                name = "Host",
                group_scores = {
                    offense = {
                        { stat_name = Contract.TOPIC, score = 7 },
                    },
                },
            },
        }
        local extracted, reason = Contract.extract_grouped_snapshot(native_players)
        if not extracted then return "host grouped extraction failed: " .. tostring(reason) end
        extracted.topics[1].values[1].value = 91
        local known = Contract.known_players(native_players)
        local verdict
        verdict, reason = Contract.validate_snapshot(extracted, known)
        if not verdict or verdict.scores["peer-host:1"] ~= 91 then
            return "real snapshot validator rejected the synthetic host row: "
                .. tostring(reason)
        end
        local topics = {
            {
                name = Contract.TOPIC,
                display_text = "scoreboard_topic_damage_dealt_bosses",
                stat_type = Contract.TOPIC,
            },
        }
        local options = {
            sort_topic = "player_name",
            boss_scores = verdict.scores,
        }
        local tab = ScorePolicy.build_native_model(native_players, topics, options)
        local finish = ScorePolicy.build_native_model(native_players, topics, options)
        local fallback = ScorePolicy.build_native_model(native_players, topics, {
            sort_topic = "player_name",
        })
        local player = tab.players and tab.players[1]
        local fallback_player = fallback.players and fallback.players[1]
        if not player or player.scores[Contract.TOPIC] ~= 91
                or not fallback_player or fallback_player.scores[Contract.TOPIC] ~= 7 then
            return "authoritative overlay/native fallback model path failed"
        end
        if tab.fingerprint ~= finish.fingerprint then
            return "Tab/end model fingerprints diverged"
        end
        if not runtime_reported then
            runtime_reported = true
            pcall(printf, "[gut:1448] raw runtime=1/%d event=runtime-check schema=%d channel=%s players=%d native=%d host=%d tab_fp=%s end_fp=%s verdict=PASS",
                RUNTIME_RECEIPT_CAP,
                Contract.SCHEMA, Contract.CHANNEL, verdict.player_count,
                fallback_player.scores[Contract.TOPIC],
                player.scores[Contract.TOPIC], tab.fingerprint,
                finish.fingerprint)
        end
    end,
}

return M
