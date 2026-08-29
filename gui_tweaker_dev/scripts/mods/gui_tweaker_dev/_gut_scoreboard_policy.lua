-- _gut_scoreboard_policy.lua - engine-free scoreboard model and retention policy.
--
-- Owns detached topic validation, paging, visibility, sorting, fingerprints,
-- supplemental scalar reads, and bounded statistic path copies for #272/#1414.
-- Owned by: gui_tweaker_dev.lua. Consumed via: mod:dofile from scoreboard modules.
local M = {}
M.ROWS_PER_PAGE = 11
M.MAX_PAGES = 4
M.MAX_TOPICS = M.ROWS_PER_PAGE * M.MAX_PAGES

-- These two native scalar leaves are already hot-join synchronized, but are
-- deliberately absent from ScoreboardHelper's fixed eleven-row wire. Callers
-- build detached rows from StatisticsDatabase instead of extending that wire.
M.SUPPLEMENTAL_TOPICS = {
    {
        name = "aidings",
        display_text = "gut_scoreboard_topic_aidings",
        stat_type = "aidings",
        supplemental = true,
        mod_localized = true,
    },
    {
        name = "times_revived",
        display_text = "gut_scoreboard_topic_times_revived",
        stat_type = "times_revived",
        supplemental = true,
        mod_localized = true,
    },
}

local function _copy_path(path)
    local copy = {}
    for i = 1, #path do copy[i] = path[i] end
    return copy
end

local function _copy_topic(topic)
    if type(topic) ~= "table" then return topic end
    local copy = {
        name = topic.name,
        display_text = topic.display_text,
        stat_type = topic.stat_type,
        supplemental = topic.supplemental == true,
        mod_localized = topic.mod_localized == true,
    }
    if type(topic.stat_types) == "table" then
        copy.stat_types = {}
        for i, path in ipairs(topic.stat_types) do
            copy.stat_types[i] = type(path) == "table" and _copy_path(path) or path
        end
    end
    return copy
end

-- Construct a private catalog. ScoreboardHelper remains byte-for-byte vanilla:
-- no topic is appended to its catalog and num_stats_per_player stays eleven.
function M.build_topic_registry(native_topics)
    local registry = {}
    for _, topic in ipairs(type(native_topics) == "table" and native_topics or {}) do
        registry[#registry + 1] = _copy_topic(topic)
    end
    for _, topic in ipairs(M.SUPPLEMENTAL_TOPICS) do
        registry[#registry + 1] = _copy_topic(topic)
    end
    return registry
end

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

local function _detached_row(rows, stats_id)
    return type(rows) == "table"
        and (rawget(rows, tostring(stats_id)) or rawget(rows, stats_id)) or nil
end

local function _score_map(player, supplemental_scores, boss_scores, stats_id,
        boss_score_mode)
    local scores = {}
    for _, group in pairs(type(player) == "table" and player.group_scores or {}) do
        for _, entry in ipairs(type(group) == "table" and group or {}) do
            if type(entry) == "table" and type(entry.stat_name) == "string"
                    and type(entry.score) == "number" then
                scores[entry.stat_name] = entry.score
            end
        end
    end
    local supplement = _detached_row(supplemental_scores, stats_id)
    if type(supplement) == "table" then
        for _, topic in ipairs(M.SUPPLEMENTAL_TOPICS) do
            local value = rawget(supplement, topic.name)
            if type(value) == "number" then scores[topic.name] = value end
        end
    end
    -- #1448 overlays only the detached presentation cell. The native grouped
    -- row remains the fallback, and StatisticsDatabase / vanilla score payloads
    -- are never rewritten. The transport validator already owns stricter caps;
    -- this final model seam independently requires a finite non-negative value.
    local boss = _detached_row(boss_scores, stats_id)
    if type(boss) == "number" and boss == boss
            and boss < math.huge and boss > -math.huge and boss >= 0 then
        local native = scores.damage_dealt_bosses
        if boss_score_mode == "max" and type(native) == "number"
                and native == native and native < math.huge
                and native > -math.huge and native >= 0 then
            scores.damage_dealt_bosses = math.max(native, boss)
        else
            scores.damage_dealt_bosses = boss
        end
    end
    return scores
end

-- Read the two detached scalar leaves for only the already-selected renderer
-- rows. The reader is dependency-injected so missing/throwing databases are
-- contained and the engine-free tests execute the production boundary.
function M.read_supplemental_scores(player_rows, read_value, limit)
    local result = {}
    limit = math.min(math.max(tonumber(limit) or 4, 0), 4)
    if type(player_rows) ~= "table" or type(read_value) ~= "function" then
        return result
    end
    local visited = 0
    for _, player in ipairs(player_rows) do
        if visited >= limit then break end
        local stats_id = type(player) == "table" and player.stats_id or nil
        if stats_id ~= nil then
            visited = visited + 1
            local values = {}
            for _, topic in ipairs(M.SUPPLEMENTAL_TOPICS) do
                local ok, value = pcall(read_value, stats_id, topic.stat_type)
                if ok and type(value) == "number" then
                    values[topic.name] = value
                end
            end
            result[tostring(stats_id)] = values
        end
    end
    return result
end

function M.clamp_page(value, page_count)
    page_count = math.floor(tonumber(page_count) or 0)
    if page_count < 1 then return 0 end
    local page = math.floor(tonumber(value) or 1)
    if page < 1 then return 1 end
    if page > page_count then return page_count end
    return page
end

function M.next_page(value, page_count)
    page_count = math.floor(tonumber(page_count) or 0)
    if page_count < 1 then return 1 end
    local page = M.clamp_page(value, page_count)
    return (page % page_count) + 1
end

local function _append_fingerprint(parts, value)
    local text = tostring(value)
    parts[#parts + 1] = tostring(#text) .. ":" .. text
end

local function _model_fingerprint(model)
    local parts = {}
    _append_fingerprint(parts, "gut-scoreboard-model-v1")
    _append_fingerprint(parts, model.selected_page)
    _append_fingerprint(parts, model.page_count)
    _append_fingerprint(parts, model.preferred_sort)
    _append_fingerprint(parts, model.effective_sort)
    _append_fingerprint(parts, model.overflow_count)
    _append_fingerprint(parts, model.duplicate_count)
    _append_fingerprint(parts, model.malformed_count)
    for _, topic in ipairs(model.topics) do
        _append_fingerprint(parts, topic.name)
        _append_fingerprint(parts, topic.display_text)
        _append_fingerprint(parts, topic.visible and 1 or 0)
        _append_fingerprint(parts, topic.mod_localized and 1 or 0)
    end
    for _, name in ipairs(model.overflow_topics) do
        _append_fingerprint(parts, name)
    end
    for _, player in ipairs(model.players) do
        _append_fingerprint(parts, player.stats_key)
        _append_fingerprint(parts, player.name)
        for _, topic in ipairs(model.topics) do
            local value = player.scores[topic.name]
            _append_fingerprint(parts, type(value) == "number" and value or "missing")
        end
    end

    local hash = 5381
    local bytes = table.concat(parts, "|")
    for i = 1, #bytes do
        hash = (hash * 33 + string.byte(bytes, i)) % 4294967296
    end
    return string.format("%08x", hash)
end

-- Build the bounded renderer-neutral model shared by Tab and the end screen.
-- Every source table is copied; no StatisticsDatabase or native snapshot
-- object crosses the boundary. The first 44 unique valid topics are rendered
-- across four pages and later valid topics are reported as explicit overflow.
function M.build_native_model(players, topics, options)
    options = type(options) == "table" and options or {}
    local model = {
        topics = {},
        visible_topics = {},
        overflow_topics = {},
        pages = {},
        players = {},
        overflow_count = 0,
        duplicate_count = 0,
        malformed_count = 0,
        preferred_sort = type(options.sort_topic) == "string"
            and options.sort_topic or "player_name",
    }
    local player_limit = math.min(math.max(tonumber(options.player_limit) or 4, 1), 4)
    local visibility = type(options.visibility) == "table" and options.visibility or {}

    local seen_topics = {}
    for _, topic in ipairs(type(topics) == "table" and topics or {}) do
        if type(topic) ~= "table" or type(topic.name) ~= "string"
                or topic.name == "" or type(topic.display_text) ~= "string"
                or topic.display_text == "" then
            model.malformed_count = model.malformed_count + 1
        elseif seen_topics[topic.name] then
            model.duplicate_count = model.duplicate_count + 1
        else
            seen_topics[topic.name] = true
            if #model.topics < M.MAX_TOPICS then
                local copy = {
                    name = topic.name,
                    display_text = topic.display_text,
                    visible = rawget(visibility, topic.name) ~= false,
                    mod_localized = topic.mod_localized == true,
                }
                model.topics[#model.topics + 1] = copy
                if copy.visible then
                    model.visible_topics[#model.visible_topics + 1] = copy
                end
            else
                model.overflow_count = model.overflow_count + 1
                model.overflow_topics[#model.overflow_topics + 1] = topic.name
            end
        end
    end

    local visible_names = { player_name = true }
    for _, topic in ipairs(model.visible_topics) do visible_names[topic.name] = true end
    model.effective_sort = visible_names[model.preferred_sort]
        and model.preferred_sort or "player_name"

    for stats_id, player in pairs(type(players) == "table" and players or {}) do
        if type(player) == "table" and type(player.name) == "string" then
            local source_id = player.stats_id ~= nil and player.stats_id or stats_id
            model.players[#model.players + 1] = {
                stats_id = source_id,
                stats_key = tostring(source_id),
                name = player.name,
                scores = _score_map(player, options.supplemental_scores,
                    options.boss_scores, source_id, options.boss_score_mode),
            }
        end
    end

    table.sort(model.players, function(a, b)
        local sort_topic = model.effective_sort
        if sort_topic ~= "player_name" then
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
        return a.stats_key < b.stats_key
    end)

    while #model.players > player_limit do table.remove(model.players) end

    for i = 1, #model.visible_topics, M.ROWS_PER_PAGE do
        local page = {
            number = #model.pages + 1,
            topics = {},
            players = model.players,
        }
        local last = math.min(i + M.ROWS_PER_PAGE - 1, #model.visible_topics)
        for j = i, last do page.topics[#page.topics + 1] = model.visible_topics[j] end
        model.pages[#model.pages + 1] = page
    end
    model.page_count = #model.pages
    model.selected_page = M.clamp_page(options.selected_page, model.page_count)
    model.selected = model.pages[model.selected_page]
    model.all_hidden = #model.visible_topics == 0
    model.fingerprint = _model_fingerprint(model)
    return model
end

return M
