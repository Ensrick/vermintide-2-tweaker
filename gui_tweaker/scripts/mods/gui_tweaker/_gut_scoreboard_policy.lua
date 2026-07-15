-- Engine-free catalog/snapshot classifier for issue #272. The live diagnostics
-- module feeds it vanilla ScoreboardHelper data; offline Lua 5.1 QA exercises
-- malformed and complete shapes without constructing game managers.
local M = {}
M.MAX_NATIVE_TOPICS = 11

function M.inspect_catalog(topics, groups)
    local result = {
        topic_count = 0,
        grouped_count = 0,
        duplicate_count = 0,
        unresolved_count = 0,
        malformed_count = 0,
        names = {},
    }
    if type(topics) ~= "table" or type(groups) ~= "table" then
        result.malformed_count = 1
        return result
    end

    local by_name = {}
    for i, topic in ipairs(topics) do
        result.topic_count = result.topic_count + 1
        if type(topic) ~= "table" or type(topic.name) ~= "string"
                or type(topic.display_text) ~= "string" then
            result.malformed_count = result.malformed_count + 1
        else
            if by_name[topic.name] then
                result.duplicate_count = result.duplicate_count + 1
            else
                by_name[topic.name] = true
                result.names[#result.names + 1] = topic.name
            end
            local scalar = type(topic.stat_type) == "string"
            local composite = type(topic.stat_types) == "table" and #topic.stat_types > 0
            if scalar == composite then
                result.malformed_count = result.malformed_count + 1
            end
        end
    end

    for _, group in ipairs(groups) do
        if type(group) ~= "table" or type(group.stats) ~= "table" then
            result.malformed_count = result.malformed_count + 1
        else
            for _, name in ipairs(group.stats) do
                result.grouped_count = result.grouped_count + 1
                if not by_name[name] then
                    result.unresolved_count = result.unresolved_count + 1
                end
            end
        end
    end
    table.sort(result.names)
    return result
end

function M.inspect_snapshot(players)
    local result = {
        player_count = 0,
        score_count = 0,
        malformed_players = 0,
        nonnumeric_scores = 0,
    }
    if type(players) ~= "table" then
        result.malformed_players = 1
        return result
    end
    for _, player in pairs(players) do
        result.player_count = result.player_count + 1
        if type(player) ~= "table" or type(player.group_scores) ~= "table" then
            result.malformed_players = result.malformed_players + 1
        else
            for _, scores in pairs(player.group_scores) do
                if type(scores) ~= "table" then
                    result.malformed_players = result.malformed_players + 1
                else
                    for _, score in ipairs(scores) do
                        result.score_count = result.score_count + 1
                        if type(score) ~= "table" or type(score.score) ~= "number" then
                            result.nonnumeric_scores = result.nonnumeric_scores + 1
                        end
                    end
                end
            end
        end
    end
    return result
end

local function _definition_at(definitions, path)
    local node = definitions
    if type(path) == "string" then path = { path } end
    if type(path) ~= "table" then return nil end
    for i = 1, #path do
        node = type(node) == "table" and node[path[i]] or nil
        if node == nil then return nil end
    end
    return node
end

function M.inspect_hotjoin_coverage(topics, definitions)
    local result = { covered = {}, gaps = {}, unresolved = {} }
    if type(topics) ~= "table" or type(definitions) ~= "table" then
        result.unresolved[1] = "catalog"
        return result
    end
    for _, topic in ipairs(topics) do
        local paths = topic.stat_types or { topic.stat_type }
        local resolved = true
        local synced = true
        for _, path in ipairs(paths) do
            local definition = _definition_at(definitions, path)
            if type(definition) ~= "table" then
                resolved = false
            elseif definition.sync_on_hot_join ~= true then
                synced = false
            end
        end
        local target = not resolved and result.unresolved
            or (synced and result.covered or result.gaps)
        target[#target + 1] = topic.name
    end
    table.sort(result.covered)
    table.sort(result.gaps)
    table.sort(result.unresolved)
    return result
end

-- Return the exact leaf statistic paths consumed by ScoreboardHelper. This is
-- deliberately narrower than copying a player's StatisticsDatabase row: a
-- disconnect repair must never retain backend/progression statistics.
function M.collect_stat_paths(topics, limit)
    local paths, seen = {}, {}
    limit = tonumber(limit) or 64
    if type(topics) ~= "table" or limit < 1 then return paths end
    for _, topic in ipairs(topics) do
        local candidates = type(topic) == "table" and topic.stat_types
            or nil
        if type(candidates) ~= "table" then
            candidates = { type(topic) == "table" and topic.stat_type or nil }
        end
        for _, candidate in ipairs(candidates) do
            local path = type(candidate) == "string" and { candidate }
                or candidate
            if type(path) == "table" and #path > 0 then
                local valid, key, copy = true, {}, {}
                for i = 1, #path do
                    if type(path[i]) ~= "string" then valid = false break end
                    copy[i], key[i] = path[i], path[i]
                end
                key = valid and table.concat(key, "\31") or nil
                if key and not seen[key] then
                    seen[key] = true
                    paths[#paths + 1] = copy
                    if #paths >= limit then return paths end
                end
            end
        end
    end
    return paths
end

function M.capture_stat_values(paths, read_value, limit)
    local records = {}
    limit = tonumber(limit) or 64
    if type(paths) ~= "table" or type(read_value) ~= "function" then
        return records
    end
    for _, path in ipairs(paths) do
        if #records >= limit then break end
        local ok, value = pcall(read_value, path)
        if ok and type(value) == "number" then
            local copy = {}
            for i = 1, #path do copy[i] = path[i] end
            records[#records + 1] = { path = copy, value = value }
        end
    end
    return records
end

function M.restore_stat_values(records, write_value, limit)
    local restored = 0
    limit = tonumber(limit) or 64
    if type(records) ~= "table" or type(write_value) ~= "function" then
        return restored
    end
    for _, record in ipairs(records) do
        if restored >= limit then break end
        if type(record) == "table" and type(record.path) == "table"
                and type(record.value) == "number" then
            local ok = pcall(write_value, record.path, record.value)
            if ok then restored = restored + 1 end
        end
    end
    return restored
end

local function _score_map(player)
    local scores = {}
    for _, group in pairs(type(player) == "table" and player.group_scores or {}) do
        for _, entry in ipairs(type(group) == "table" and group or {}) do
            if type(entry) == "table" and type(entry.stat_name) == "string"
                    and type(entry.score) == "number" then
                scores[entry.stat_name] = entry.score
            end
        end
    end
    return scores
end

-- Build the bounded, renderer-neutral model shared by the live Tab page and a
-- future end-screen page. No StatisticsDatabase or engine object crosses this
-- boundary, so presentation ordering cannot mutate the native snapshot.
function M.build_native_page(players, topics, sort_topic, limit)
    local page = { topics = {}, players = {} }
    limit = math.min(math.max(tonumber(limit) or 4, 1), 4)

    local seen_topics = {}
    for _, topic in ipairs(type(topics) == "table" and topics or {}) do
        if type(topic) == "table" and type(topic.name) == "string"
                and type(topic.display_text) == "string"
                and not seen_topics[topic.name]
                and #page.topics < M.MAX_NATIVE_TOPICS then
            seen_topics[topic.name] = true
            page.topics[#page.topics + 1] = {
                name = topic.name,
                display_text = topic.display_text,
            }
        end
    end

    for stats_id, player in pairs(type(players) == "table" and players or {}) do
        if type(player) == "table" and type(player.name) == "string" then
            page.players[#page.players + 1] = {
                stats_id = tostring(stats_id),
                name = player.name,
                scores = _score_map(player),
            }
        end
    end

    table.sort(page.players, function(a, b)
        if sort_topic and sort_topic ~= "player_name" then
            local av, bv = a.scores[sort_topic], b.scores[sort_topic]
            local a_has, b_has = type(av) == "number", type(bv) == "number"
            -- Missing rows are incomplete snapshots, never a winning zero (or
            -- negative infinity). Keep them last for both ascending and
            -- descending statistics.
            if a_has ~= b_has then return a_has end
            if a_has and av ~= bv then
                -- Vanilla treats lower damage taken as better; every other
                -- exposed sort follows the ordinary descending scoreboard rule.
                if sort_topic == "damage_taken" then return av < bv end
                return av > bv
            end
        end
        local an, bn = string.lower(a.name), string.lower(b.name)
        if an ~= bn then return an < bn end
        return a.stats_id < b.stats_id
    end)

    while #page.players > limit do table.remove(page.players) end
    return page
end

return M
