-- _gut_boss_damage_sync_policy.lua - engine-free #1448 wire/model policy.
--
-- The transport owns one exact, versioned VMF channel. This policy validates
-- its fixed envelope, reassembles bounded payload chunks, extracts vanilla's
-- already-grouped boss subtotal, and accepts only current known player rows.
-- It never reads or mutates StatisticsDefinitions, NetworkLookup, or a damage
-- transaction.
local M = {}

M.CHANNEL = "gut_boss_damage_snapshot_v1"
M.SCHEMA = 1
M.REQUEST = "request"
M.SNAPSHOT = "snapshot"
M.TOPIC = "damage_dealt_bosses"

M.MAX_PLAYERS = 4
M.MAX_TOPICS = 1
M.MAX_GENERATION_BYTES = 64
M.MAX_PLAYER_ID_BYTES = 64
M.MAX_TOPIC_BYTES = 64
M.MAX_SEQUENCE = 2147483647
M.MAX_VALUE = 1000000000
M.MAX_PAYLOAD_BYTES = 1024
M.MAX_PACKED_BYTES = 400
M.CHUNK_BYTES = 144
M.MAX_CHUNKS = 8
M.MAX_RETRIES = 4
M.HANDSHAKE_DELAY = 0.4
M.RETRY_DELAY = 0.75
M.REFRESH_DELAY = 2.0
M.SNAPSHOT_TTL = 10.0
M.ROSTER_POLL_DELAY = 0.5
M.RESPONSE_SEND_FLOOR = M.RETRY_DELAY
M.FRESH_BUILD_FLOOR = M.REFRESH_DELAY
M.MAX_GENERATIONS_PER_SESSION = 16

local function _finite(value)
    return type(value) == "number" and value == value
        and value < math.huge and value > -math.huge
end

local function _integer(value, minimum, maximum)
    return _finite(value) and value == math.floor(value)
        and value >= minimum and value <= maximum
end

local function _bounded_string(value, maximum, allow_empty)
    return type(value) == "string"
        and (allow_empty or #value > 0) and #value <= maximum
        and value:find("[%z\1-\31\127]", 1) == nil
end

local function _only_keys(value, allowed)
    if type(value) ~= "table" then return false end
    for key in pairs(value) do
        if not allowed[key] then return false end
    end
    return true
end

local function _dense_count(value, maximum)
    if type(value) ~= "table" then return nil, "not-table" end
    local count, highest = 0, 0
    for key in pairs(value) do
        if not _integer(key, 1, maximum) then return nil, "invalid-index" end
        count = count + 1
        if key > highest then highest = key end
    end
    if count ~= highest then return nil, "sparse-array" end
    for i = 1, highest do
        if rawget(value, i) == nil then return nil, "sparse-array" end
    end
    return count
end

function M.valid_generation(generation)
    return _bounded_string(generation, M.MAX_GENERATION_BYTES, false)
        and generation:match("^[%w%._:%-]+$") ~= nil
end

function M.valid_sequence(sequence)
    return _integer(sequence, 1, M.MAX_SEQUENCE)
end

function M.valid_player_id(player_id)
    return _bounded_string(player_id, M.MAX_PLAYER_ID_BYTES, false)
        and player_id:match("^[%w%._:%-]+$") ~= nil
end

-- Every message uses the same exact positional envelope:
-- schema, kind, generation, sequence, part, total, payload_size, chunk.
function M.validate_envelope(schema, kind, generation, sequence, part, total,
        payload_size, chunk)
    if schema ~= M.SCHEMA then return false, "schema" end
    if kind ~= M.REQUEST and kind ~= M.SNAPSHOT then return false, "kind" end
    if not M.valid_generation(generation) then return false, "generation" end
    if not M.valid_sequence(sequence) then return false, "sequence" end

    if kind == M.REQUEST then
        if part ~= 0 or total ~= 0 or payload_size ~= 0 or chunk ~= "" then
            return false, "request-shape"
        end
        return true
    end

    if not _integer(part, 1, M.MAX_CHUNKS) then return false, "part" end
    if not _integer(total, 1, M.MAX_CHUNKS) or part > total then
        return false, "total"
    end
    if not _integer(payload_size, 1, M.MAX_PAYLOAD_BYTES) then
        return false, "payload-size"
    end
    if not _bounded_string(chunk, M.CHUNK_BYTES, false) then
        return false, "chunk"
    end
    return true
end

local function _json_string_bytes(value)
    local bytes = 2 -- surrounding quotes
    for i = 1, #value do
        local byte = string.byte(value, i)
        bytes = bytes + ((byte == 34 or byte == 92) and 2 or 1)
    end
    return bytes
end

-- VMF serializes these eight user arguments as cjson.encode({...}) into one
-- native string field. The inputs above exclude control bytes, and every
-- locally produced text byte is ASCII, so quote/backslash doubling is the only
-- expansion. Return its exact packed size before any network_send call.
function M.packed_message_bytes(schema, kind, generation, sequence, part, total,
        payload_size, chunk)
    local valid, reason = M.validate_envelope(schema, kind, generation,
        sequence, part, total, payload_size, chunk)
    if not valid then return nil, reason end
    return 9 -- two brackets plus seven commas
        + #tostring(schema) + #tostring(sequence) + #tostring(part)
        + #tostring(total) + #tostring(payload_size)
        + _json_string_bytes(kind) + _json_string_bytes(generation)
        + _json_string_bytes(chunk)
end

function M.chunk_payload(payload)
    if type(payload) ~= "string" or #payload < 1
            or #payload > M.MAX_PAYLOAD_BYTES then
        return nil, "payload-size"
    end
    local chunks = {}
    for offset = 1, #payload, M.CHUNK_BYTES do
        chunks[#chunks + 1] = payload:sub(offset, offset + M.CHUNK_BYTES - 1)
    end
    if #chunks < 1 or #chunks > M.MAX_CHUNKS then
        return nil, "chunk-count"
    end
    return chunks
end

function M.new_reassembly(generation, sequence, total, payload_size)
    if not M.valid_generation(generation) then return nil, "generation" end
    if not M.valid_sequence(sequence) then return nil, "sequence" end
    if not _integer(total, 1, M.MAX_CHUNKS) then return nil, "total" end
    if not _integer(payload_size, 1, M.MAX_PAYLOAD_BYTES) then
        return nil, "payload-size"
    end
    return {
        generation = generation,
        sequence = sequence,
        total = total,
        payload_size = payload_size,
        chunks = {},
        received = 0,
        bytes = 0,
    }
end

function M.accept_chunk(state, part, total, payload_size, chunk)
    if type(state) ~= "table" or not _integer(part, 1, M.MAX_CHUNKS)
            or total ~= state.total or payload_size ~= state.payload_size
            or part > total or not _bounded_string(chunk, M.CHUNK_BYTES, false) then
        return nil, "chunk-header"
    end
    local prior = state.chunks[part]
    if prior ~= nil then
        if prior == chunk then return nil, "duplicate" end
        return nil, "conflict"
    end
    if state.bytes + #chunk > state.payload_size
            or state.bytes + #chunk > M.MAX_PAYLOAD_BYTES then
        return nil, "payload-overrun"
    end
    state.chunks[part] = chunk
    state.received = state.received + 1
    state.bytes = state.bytes + #chunk
    if state.received ~= state.total then return nil, "pending" end
    if state.bytes ~= state.payload_size then return nil, "payload-length" end
    local payload = table.concat(state.chunks, "", 1, state.total)
    if #payload ~= state.payload_size then return nil, "payload-length" end
    return payload, "complete"
end

local function _stats_id(source_id, player)
    local value = type(player) == "table" and player.stats_id or source_id
    if type(value) ~= "string" then value = tostring(value or "") end
    return value
end

function M.known_players(players)
    if type(players) ~= "table" then return nil, "players" end
    local known, count = {}, 0
    for source_id, player in pairs(players) do
        if type(player) ~= "table" then return nil, "player-row" end
        local player_id = _stats_id(source_id, player)
        if not M.valid_player_id(player_id) then return nil, "player-id" end
        if known[player_id] then return nil, "duplicate-player" end
        count = count + 1
        if count > M.MAX_PLAYERS then return nil, "player-count" end
        known[player_id] = true
    end
    if count < 1 then return nil, "player-count" end
    return known, nil, count
end

local function _hash_bytes(bytes)
    local hash = 5381
    for i = 1, #bytes do
        hash = (hash * 33 + string.byte(bytes, i)) % 4294967296
    end
    return string.format("%08x", hash)
end

-- Scoreboard rows cover humans and bots, so this fingerprint observes roster
-- changes that VMF's same-mod discovery callback cannot distinguish from a
-- repeated pong. It is intentionally derived from stable stats IDs only.
function M.roster_fingerprint(players)
    local known, reason, count = M.known_players(players)
    if not known then return nil, reason end
    local ids = {}
    for player_id in pairs(known) do ids[#ids + 1] = player_id end
    table.sort(ids)
    local parts = { "gut-roster-v1", tostring(count) }
    for _, player_id in ipairs(ids) do
        parts[#parts + 1] = tostring(#player_id) .. ":" .. player_id
    end
    return _hash_bytes(table.concat(parts, "|")), nil, count
end

-- Read only ScoreboardHelper's grouped output. The host already produced this
-- subtotal from the vanilla damage_dealt_per_breed leaves, including #437's
-- restored row; no hit hook or second ledger is involved.
function M.extract_grouped_snapshot(players)
    local known, reason, player_count = M.known_players(players)
    if not known then return nil, reason end
    local values = {}
    for source_id, player in pairs(players) do
        local player_id = _stats_id(source_id, player)
        local found
        for _, group in pairs(type(player.group_scores) == "table"
                and player.group_scores or {}) do
            if type(group) ~= "table" then return nil, "group-row" end
            for _, score in ipairs(group) do
                if type(score) ~= "table" then return nil, "score-row" end
                if score.stat_name == M.TOPIC then
                    if found ~= nil then return nil, "duplicate-topic-value" end
                    found = score.score
                end
            end
        end
        if not _finite(found) or found < 0 or found > M.MAX_VALUE then
            return nil, "value"
        end
        values[#values + 1] = { player_id = player_id, value = found }
    end
    table.sort(values, function(a, b) return a.player_id < b.player_id end)
    if #values ~= player_count then return nil, "player-count" end
    return {
        topics = {
            { name = M.TOPIC, values = values },
        },
    }
end

local function _fingerprint(rows)
    local parts = { "gut-boss-snapshot-v1" }
    for _, row in ipairs(rows) do
        parts[#parts + 1] = tostring(#row.player_id) .. ":" .. row.player_id
        parts[#parts + 1] = tostring(row.value)
    end
    return _hash_bytes(table.concat(parts, "|"))
end

function M.validate_snapshot(snapshot, known_players)
    if not _only_keys(snapshot, { topics = true })
            or type(snapshot.topics) ~= "table" then
        return nil, "snapshot-shape"
    end
    local topic_count, array_reason = _dense_count(snapshot.topics, M.MAX_TOPICS)
    if not topic_count then return nil, "topics-" .. array_reason end
    if topic_count ~= 1 then return nil, "topic-count" end

    local topic = snapshot.topics[1]
    if not _only_keys(topic, { name = true, values = true }) then
        return nil, "topic-shape"
    end
    if not _bounded_string(topic.name, M.MAX_TOPIC_BYTES, false)
            or topic.name ~= M.TOPIC then
        return nil, "topic-name"
    end
    if type(known_players) ~= "table" then return nil, "known-players" end

    local player_count, player_reason = _dense_count(topic.values, M.MAX_PLAYERS)
    if not player_count then return nil, "players-" .. player_reason end
    if player_count < 1 then return nil, "player-count" end
    local rows, seen = {}, {}
    for i = 1, player_count do
        local row = topic.values[i]
        if not _only_keys(row, { player_id = true, value = true }) then
            return nil, "player-shape"
        end
        if not M.valid_player_id(row.player_id) then return nil, "player-id" end
        if seen[row.player_id] then return nil, "duplicate-player" end
        if rawget(known_players, row.player_id) ~= true then
            return nil, "unknown-player"
        end
        if not _finite(row.value) or row.value < 0 or row.value > M.MAX_VALUE then
            return nil, "value"
        end
        seen[row.player_id] = true
        rows[#rows + 1] = { player_id = row.player_id, value = row.value }
    end
    table.sort(rows, function(a, b) return a.player_id < b.player_id end)
    local scores = {}
    for _, row in ipairs(rows) do scores[row.player_id] = row.value end
    return {
        scores = scores,
        rows = rows,
        player_count = #rows,
        topic_count = topic_count,
        fingerprint = _fingerprint(rows),
    }
end

-- One bounded host-side session per requesting peer. A response is immutable
-- for its exact (generation, sequence) identity. Discovery pongs never reset
-- this state; a real mission/peer teardown remains the lifecycle owner.
function M.new_host_session()
    return {
        generation = nil,
        generation_count = 0,
        retired_generations = {},
        last_sequence = 0,
        response = nil,
        roster_epoch = 0,
        last_build_attempt_at = nil,
        last_build_at = nil,
        last_send_at = nil,
    }
end

local function _too_soon(now, then_at, floor)
    return then_at ~= nil and now - then_at < floor
end

-- Classify before any grouped-stat read, JSON encode, chunk allocation, or
-- network send. Contiguous sequences and the two time floors keep even an
-- authenticated same-mod peer from turning this aggregate endpoint into
-- per-frame host work. A genuine roster epoch may bypass the build floor once;
-- it never bypasses the response-send floor.
function M.plan_host_request(state, generation, sequence, now, roster_epoch)
    if type(state) ~= "table" then return nil, "session" end
    if type(state.retired_generations) ~= "table"
            or not _integer(state.generation_count, 0,
                M.MAX_GENERATIONS_PER_SESSION)
            or not _integer(state.last_sequence, 0, M.MAX_SEQUENCE)
            or (state.generation ~= nil
                and not M.valid_generation(state.generation))
            or (state.roster_epoch ~= nil
                and not _integer(state.roster_epoch, 0, M.MAX_SEQUENCE))
            or (state.last_build_attempt_at ~= nil
                and not _finite(state.last_build_attempt_at))
            or (state.last_build_at ~= nil and not _finite(state.last_build_at))
            or (state.last_send_at ~= nil and not _finite(state.last_send_at)) then
        return nil, "session-shape"
    end
    if not M.valid_generation(generation) then return nil, "generation" end
    if not M.valid_sequence(sequence) then return nil, "sequence" end
    if not _finite(now) then return nil, "clock" end
    if not _integer(roster_epoch, 0, M.MAX_SEQUENCE) then
        return nil, "roster-epoch"
    end

    if _too_soon(now, state.last_send_at, M.RESPONSE_SEND_FLOOR) then
        return nil, "rate-send"
    end

    if state.generation == generation then
        if sequence < state.last_sequence then return nil, "stale-sequence" end
        if sequence == state.last_sequence then
            if type(state.response) ~= "table" then return nil, "missing-cache" end
            return {
                kind = "replay",
                generation = generation,
                sequence = sequence,
                roster_epoch = state.roster_epoch,
                response = state.response,
            }
        end
        if sequence ~= state.last_sequence + 1 then
            return nil, "sequence-gap"
        end
    else
        if state.retired_generations[generation] then
            return nil, "retired-generation"
        end
        if sequence ~= 1 then return nil, "new-generation-sequence" end
        if state.generation_count >= M.MAX_GENERATIONS_PER_SESSION then
            return nil, "generation-cap"
        end
    end

    local roster_changed = state.generation ~= nil
        and state.roster_epoch ~= roster_epoch
    if _too_soon(now, state.last_build_attempt_at, M.FRESH_BUILD_FLOOR)
            and not roster_changed then
        return nil, "rate-build"
    end
    return {
        kind = "build",
        generation = generation,
        sequence = sequence,
        roster_epoch = roster_epoch,
        roster_bypass = roster_changed,
    }
end

function M.reserve_host_build(state, plan, now)
    if type(state) ~= "table" or type(plan) ~= "table"
            or plan.kind ~= "build" or not _finite(now) then
        return false, "reservation"
    end
    state.last_build_attempt_at = now
    return true
end

function M.commit_host_response(state, plan, response, now)
    if type(state) ~= "table" or type(plan) ~= "table"
            or plan.kind ~= "build" or type(response) ~= "table"
            or not _finite(now) then
        return false, "commit"
    end
    if state.generation ~= plan.generation then
        if state.generation ~= nil then
            state.retired_generations[state.generation] = true
        end
        state.generation_count = state.generation_count + 1
    end
    state.generation = plan.generation
    state.last_sequence = plan.sequence
    state.response = response
    state.roster_epoch = plan.roster_epoch
    state.last_build_at = now
    return true
end

function M.record_host_send(state, now)
    if type(state) ~= "table" or not _finite(now) then
        return false, "send"
    end
    state.last_send_at = now
    return true
end

function M.new_pull(generation, sequence, now)
    if not M.valid_generation(generation) then return nil, "generation" end
    if not M.valid_sequence(sequence) then return nil, "sequence" end
    now = _finite(now) and now or 0
    return {
        generation = generation,
        sequence = sequence,
        attempts = 0,
        discovery_attempts = 0,
        phase = "handshake",
        next_at = now,
        complete = false,
        terminal = false,
    }
end

-- Dependency-injected retry owner used unchanged by the live adapter and the
-- offline lost-request/lost-response tests. A response is the acknowledgement;
-- duplicate responses are idempotent through acknowledge_pull below.
function M.step_pull(state, now, host_peer_id, ping, send)
    if type(state) ~= "table" or state.complete or state.terminal then
        return false, "inactive"
    end
    now = _finite(now) and now or 0
    if now < state.next_at then return false, "waiting" end

    if state.phase == "handshake" then
        state.discovery_attempts = state.discovery_attempts + 1
        if type(ping) == "function" then pcall(ping) end
        if not M.valid_player_id(host_peer_id) then
            if state.discovery_attempts >= M.MAX_RETRIES then
                state.terminal = true
                state.reason = "missing-host"
            else
                state.next_at = now + M.RETRY_DELAY
            end
            return false, "missing-host"
        end
        state.host_peer_id = host_peer_id
        state.phase = "send"
        state.next_at = now + M.HANDSHAKE_DELAY
        return false, "handshake"
    end

    if state.phase ~= "send" or host_peer_id ~= state.host_peer_id then
        state.terminal = true
        state.reason = "host-changed"
        return false, "host-changed"
    end
    state.attempts = state.attempts + 1
    local emitted = false
    if type(send) == "function" then
        local ok, result = pcall(send, host_peer_id, state.generation, state.sequence)
        emitted = ok and result ~= false
    end
    if state.attempts >= M.MAX_RETRIES then
        state.terminal = true
        state.reason = "retry-cap"
    else
        state.phase = "handshake"
        state.next_at = now + M.RETRY_DELAY
    end
    return emitted, emitted and "sent" or "send-failed"
end

function M.acknowledge_pull(state, generation, sequence)
    if type(state) ~= "table" or generation ~= state.generation
            or sequence ~= state.sequence then
        return false, "mismatch"
    end
    if state.complete then return true, "duplicate" end
    state.complete = true
    state.terminal = false
    state.reason = nil
    return true, "accepted"
end

-- Authenticate and order a client response before allocating a chunk buffer.
-- The live adapter uses this verdict verbatim; tests can therefore plant
-- forged hosts, stale generations, duplicates, and future/out-of-order rows
-- without mocking VMF.
function M.classify_response(current_host, sender_peer_id, current_generation,
        pending_sequence, accepted_generation, accepted_sequence, message_generation,
        message_sequence)
    if not M.valid_player_id(current_host) then
        return false, "missing-host"
    end
    if sender_peer_id ~= current_host then return false, "non-host" end
    if message_generation ~= current_generation then
        return false, "stale-generation"
    end
    if not M.valid_sequence(message_sequence) then return false, "sequence" end
    if accepted_generation == message_generation
            and M.valid_sequence(accepted_sequence) then
        if message_sequence == accepted_sequence then return false, "duplicate" end
        if message_sequence < accepted_sequence then return false, "stale-sequence" end
    end
    if not M.valid_sequence(pending_sequence) then
        return false, "unexpected-sequence"
    end
    if message_sequence < pending_sequence then return false, "stale-sequence" end
    if message_sequence > pending_sequence then return false, "out-of-order-sequence" end
    return true, "accept"
end

return M
