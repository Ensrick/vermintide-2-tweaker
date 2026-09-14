-- _gut_custom_stat_sync_policy.lua - engine-free #1573 custom-topic snapshot policy.
--
-- #1448's `_gut_boss_damage_sync_policy.lua` already owns the exact positional
-- envelope, bounded chunk reassembly, per-peer host sessions, the readiness
-- pull with its retry cap, and response authentication/ordering. The #1573
-- transport binds those functions unchanged to a second exact channel. This
-- module owns only what differs for the #1570-#1572 rows: the channel
-- identity, the positional four-topic payload shape with its caps, and the
-- detached per-player cell projection the presenter consumes. It never reads
-- or mutates StatisticsDefinitions, NetworkLookup, a ledger, or a wire.
-- Owned by: _gut_custom_stat_sync.lua. Consumed via: mod:dofile.
local M = {}

M.CHANNEL = "gut_custom_stat_snapshot_v1"
M.SCHEMA = 1
M.MAX_PLAYERS = 4
M.MAX_TOPICS = 4
M.MAX_VALUE = 1000000000
M.MAX_TOPIC_BYTES = 64
M.MAX_PLAYER_ID_BYTES = 64
-- Shared with the #1448 wire policy; the transport refuses to load on drift.
M.MAX_PAYLOAD_BYTES = 1024
M.MAX_PACKED_BYTES = 400

-- Canonical wire order. Must equal the `_gut_custom_stats_policy.TOPICS`
-- names; the transport and the offline suite both assert that parity.
M.TOPICS = {
    "friendly_fire_damage",
    "melee_damage_dealt",
    "ranged_damage_dealt",
    "permanent_health_restored",
}

local TOPIC_SET = {}
for _, name in ipairs(M.TOPICS) do TOPIC_SET[name] = true end

local function _finite(value)
    return type(value) == "number" and value == value
        and value < math.huge and value > -math.huge
end

local function _integer(value, minimum, maximum)
    return _finite(value) and value == math.floor(value)
        and value >= minimum and value <= maximum
end

local function _bounded_string(value, maximum)
    return type(value) == "string" and #value > 0 and #value <= maximum
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

local function _hash_bytes(bytes)
    local hash = 5381
    for i = 1, #bytes do
        hash = (hash * 33 + string.byte(bytes, i)) % 4294967296
    end
    return string.format("%08x", hash)
end

function M.valid_player_id(player_id)
    return _bounded_string(player_id, M.MAX_PLAYER_ID_BYTES)
        and player_id:match("^[%w%._:%-]+$") ~= nil
end

function M.valid_topic(name)
    return _bounded_string(name, M.MAX_TOPIC_BYTES) and TOPIC_SET[name] == true
end

function M.valid_value(value)
    return _finite(value) and value >= 0 and value <= M.MAX_VALUE
end

local function _sorted_unique_ids(player_ids)
    local count, reason = _dense_count(player_ids, M.MAX_PLAYERS)
    if not count then return nil, "players-" .. reason end
    if count < 1 then return nil, "player-count" end
    local ids, seen = {}, {}
    for i = 1, count do
        local player_id = player_ids[i]
        if not M.valid_player_id(player_id) then return nil, "player-id" end
        if seen[player_id] then return nil, "duplicate-player" end
        seen[player_id] = true
        ids[i] = player_id
    end
    table.sort(ids)
    return ids, nil, count
end

-- Host projection. `player_ids` is the bounded current roster (at most four
-- stable stats IDs) and `scores` is the ledger owner's detached
-- {[stats_id] = {[topic] = value}} answer for exactly those players. Every
-- topic travels in canonical order, positionally aligned with the sorted
-- player list, so the client never infers a missing cell from a gap.
function M.build_snapshot(player_ids, scores)
    local ids, reason = _sorted_unique_ids(player_ids)
    if not ids then return nil, reason end
    if type(scores) ~= "table" then return nil, "scores" end
    local topics = {}
    for t, name in ipairs(M.TOPICS) do
        local values = {}
        for i, player_id in ipairs(ids) do
            local row = rawget(scores, player_id)
            if type(row) ~= "table" then return nil, "missing-player" end
            local value = rawget(row, name)
            if not M.valid_value(value) then return nil, "value" end
            values[i] = value
        end
        topics[t] = { name = name, values = values }
    end
    return { players = ids, topics = topics }
end

local function _fingerprint(rows)
    local parts = { "gut-custom-snapshot-v1" }
    for _, row in ipairs(rows) do
        parts[#parts + 1] = tostring(#row.player_id) .. ":" .. row.player_id
        for _, name in ipairs(M.TOPICS) do
            local value = rawget(row.values, name)
            parts[#parts + 1] = value ~= nil and tostring(value) or "-"
        end
    end
    return _hash_bytes(table.concat(parts, "|"))
end

-- Client validation against the known current roster. A partial topic list is
-- acceptable (those cells simply stay unavailable); an unknown, duplicate or
-- oversized player, topic, count or value rejects the whole snapshot.
function M.validate_snapshot(snapshot, known_players)
    if not _only_keys(snapshot, { players = true, topics = true })
            or type(snapshot.players) ~= "table"
            or type(snapshot.topics) ~= "table" then
        return nil, "snapshot-shape"
    end
    if type(known_players) ~= "table" then return nil, "known-players" end

    local player_count, player_reason = _dense_count(snapshot.players, M.MAX_PLAYERS)
    if not player_count then return nil, "players-" .. player_reason end
    if player_count < 1 then return nil, "player-count" end
    local ids, seen = {}, {}
    for i = 1, player_count do
        local player_id = snapshot.players[i]
        if not M.valid_player_id(player_id) then return nil, "player-id" end
        if seen[player_id] then return nil, "duplicate-player" end
        if rawget(known_players, player_id) ~= true then
            return nil, "unknown-player"
        end
        seen[player_id] = true
        ids[i] = player_id
    end

    local topic_count, topic_reason = _dense_count(snapshot.topics, M.MAX_TOPICS)
    if not topic_count then return nil, "topics-" .. topic_reason end
    if topic_count < 1 then return nil, "topic-count" end
    local scores = {}
    for _, player_id in ipairs(ids) do scores[player_id] = {} end
    local seen_topics = {}
    for t = 1, topic_count do
        local topic = snapshot.topics[t]
        if not _only_keys(topic, { name = true, values = true }) then
            return nil, "topic-shape"
        end
        if not M.valid_topic(topic.name) then return nil, "topic-name" end
        if seen_topics[topic.name] then return nil, "duplicate-topic" end
        seen_topics[topic.name] = true
        local value_count, value_reason = _dense_count(topic.values, M.MAX_PLAYERS)
        if not value_count then return nil, "values-" .. value_reason end
        if value_count ~= player_count then return nil, "value-count" end
        for i = 1, value_count do
            local value = topic.values[i]
            if not M.valid_value(value) then return nil, "value" end
            scores[ids[i]][topic.name] = value
        end
    end

    local rows = {}
    for _, player_id in ipairs(ids) do
        rows[#rows + 1] = { player_id = player_id, values = scores[player_id] }
    end
    table.sort(rows, function(a, b) return a.player_id < b.player_id end)
    return {
        scores = scores,
        rows = rows,
        player_count = player_count,
        topic_count = topic_count,
        fingerprint = _fingerprint(rows),
    }
end

-- Presenter projection: only players present in the accepted snapshot receive
-- a detached row, and each row carries only acknowledged finite cells. A
-- player or topic the host did not acknowledge stays absent, so the presenter
-- keeps rendering it unavailable rather than a fabricated zero.
function M.scores_for_players(scores, players, limit)
    local result = {}
    if type(scores) ~= "table" or type(players) ~= "table" then return result end
    limit = math.min(math.max(math.floor(tonumber(limit) or M.MAX_PLAYERS), 0),
        M.MAX_PLAYERS)
    local visited = 0
    for _, player in ipairs(players) do
        if visited >= limit then break end
        local stats_id = type(player) == "table" and player.stats_id or nil
        if stats_id ~= nil then
            visited = visited + 1
            local key = tostring(stats_id)
            local row = rawget(scores, key)
            if type(row) == "table" then
                local copy = {}
                for _, name in ipairs(M.TOPICS) do
                    local value = rawget(row, name)
                    if M.valid_value(value) then copy[name] = value end
                end
                result[key] = copy
            end
        end
    end
    return result
end

return M
