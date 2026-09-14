return function(H, repo_root)
    -- #1573: the #1570-#1572 host ledger rows reach non-host peers through one
    -- separate exact channel that binds #1448's wire policy unchanged. Pure
    -- projection/validation policy, the real client and host adapters driven
    -- through the same minimal VMF/engine seam as test_gut_boss_damage_sync,
    -- the ledger owner's non-host routing, and source invariants.
    local mod_root = repo_root .. "/gui_tweaker_dev/"
    local scripts = mod_root .. "scripts/mods/gui_tweaker_dev/"
    local wire_path = scripts .. "_gut_boss_damage_sync_policy.lua"
    local policy_path = scripts .. "_gut_custom_stat_sync_policy.lua"
    local runtime_path = scripts .. "_gut_custom_stat_sync.lua"
    local owner_path = scripts .. "_gut_custom_stats.lua"
    local Wire = assert(loadfile(wire_path))()
    local Policy = assert(loadfile(policy_path))()
    local CustomPolicy = assert(loadfile(scripts .. "_gut_custom_stats_policy.lua"))()
    local ScorePolicy = assert(loadfile(scripts .. "_gut_scoreboard_policy.lua"))()
    local FF, MELEE, RANGED, HEALTH = CustomPolicy.FRIENDLY_FIRE, CustomPolicy.MELEE,
        CustomPolicy.RANGED, CustomPolicy.PERMANENT_HEALTH

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count_plain(source, needle)
        local count, offset = 0, 1
        while true do
            local at = source:find(needle, offset, true)
            if not at then return count end
            count = count + 1
            offset = at + #needle
        end
    end

    -- A deterministic cjson stand-in: compact JSON, "%.14g" numbers, sorted
    -- object keys, so payload-size claims are measured on real JSON bytes.
    local function json_codec()
        local encode
        local function encode_string(value)
            return '"' .. value:gsub('[\\"]', function(c) return "\\" .. c end) .. '"'
        end
        local function is_array(value)
            local count = 0
            for _ in pairs(value) do count = count + 1 end
            return count == #value
        end
        encode = function(value)
            local kind = type(value)
            if kind == "string" then return encode_string(value) end
            if kind == "number" then return string.format("%.14g", value) end
            if kind == "boolean" then return tostring(value) end
            if kind ~= "table" then return "null" end
            local parts = {}
            if is_array(value) and #value > 0 then
                for _, item in ipairs(value) do parts[#parts + 1] = encode(item) end
                return "[" .. table.concat(parts, ",") .. "]"
            end
            local keys = {}
            for key in pairs(value) do keys[#keys + 1] = tostring(key) end
            table.sort(keys)
            for _, key in ipairs(keys) do
                parts[#parts + 1] = encode_string(key) .. ":" .. encode(value[key])
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
        local function decode(text)
            local pos = 1
            local parse
            local function skip() pos = text:find("%S", pos) or #text + 1 end
            local function parse_string()
                local out, i = {}, pos + 1
                while true do
                    local c = text:sub(i, i)
                    if c == "" then error("unterminated string") end
                    if c == '"' then break end
                    if c == "\\" then i = i + 1; c = text:sub(i, i) end
                    out[#out + 1] = c
                    i = i + 1
                end
                pos = i + 1
                return table.concat(out)
            end
            parse = function()
                skip()
                local c = text:sub(pos, pos)
                if c == "{" then
                    local object = {}
                    pos = pos + 1
                    skip()
                    if text:sub(pos, pos) == "}" then pos = pos + 1; return object end
                    while true do
                        skip()
                        local key = parse_string()
                        skip()
                        assert(text:sub(pos, pos) == ":", "expected colon")
                        pos = pos + 1
                        object[key] = parse()
                        skip()
                        local sep = text:sub(pos, pos)
                        pos = pos + 1
                        if sep == "}" then return object end
                        assert(sep == ",", "expected comma")
                    end
                elseif c == "[" then
                    local array = {}
                    pos = pos + 1
                    skip()
                    if text:sub(pos, pos) == "]" then pos = pos + 1; return array end
                    while true do
                        array[#array + 1] = parse()
                        skip()
                        local sep = text:sub(pos, pos)
                        pos = pos + 1
                        if sep == "]" then return array end
                        assert(sep == ",", "expected comma")
                    end
                elseif c == '"' then
                    return parse_string()
                else
                    local token = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
                    if token then
                        pos = pos + #token
                        return assert(tonumber(token))
                    end
                    for literal, value in pairs({ ["true"] = true, ["false"] = false }) do
                        if text:sub(pos, pos + #literal - 1) == literal then
                            pos = pos + #literal
                            return value
                        end
                    end
                    if text:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil end
                    error("unexpected token at " .. pos)
                end
            end
            local value = parse()
            return value
        end
        return { encode = encode, decode = decode }
    end

    local function player(stats_id, name, damage)
        return {
            stats_id = stats_id,
            name = name,
            group_scores = {
                offense = {
                    { stat_name = "kills_total", score = 2 },
                    { stat_name = "damage_dealt", score = damage or 0 },
                },
            },
        }
    end

    local function rows_to_scores(rows)
        local scores = {}
        for _, row in ipairs(rows) do
            scores[row[1]] = {
                [FF] = row[2], [MELEE] = row[3], [RANGED] = row[4], [HEALTH] = row[5],
            }
        end
        return scores
    end

    local function ids_of(rows)
        local ids = {}
        for i, row in ipairs(rows) do ids[i] = row[1] end
        return ids
    end

    local function valid_snapshot(rows)
        rows = rows or { { "peer-a:1", 1, 41, 5, 9 }, { "peer-b:1", 0, 17, 2, 0 } }
        return assert(Policy.build_snapshot(ids_of(rows), rows_to_scores(rows)))
    end

    local function expect_rejection(snapshot, known, expected)
        local verdict, reason = Policy.validate_snapshot(snapshot, known)
        H.equal(verdict, nil, expected)
        H.equal(reason, expected)
    end

    H.test("GUT #1573 separate exact channel shares the #1448 schema caps and custom topics", function()
        H.equal(Policy.CHANNEL, "gut_custom_stat_snapshot_v1")
        H.truthy(Policy.CHANNEL ~= Wire.CHANNEL, "the custom rows own a second channel")
        H.equal(Policy.SCHEMA, Wire.SCHEMA)
        H.equal(Policy.MAX_PAYLOAD_BYTES, Wire.MAX_PAYLOAD_BYTES)
        H.equal(Policy.MAX_PACKED_BYTES, Wire.MAX_PACKED_BYTES)
        H.equal(Policy.MAX_PLAYERS, Wire.MAX_PLAYERS)
        H.equal(Policy.MAX_PLAYER_ID_BYTES, Wire.MAX_PLAYER_ID_BYTES)
        H.equal(Policy.MAX_TOPICS, 4)
        H.equal(#Policy.TOPICS, #CustomPolicy.TOPICS)
        for i, topic in ipairs(CustomPolicy.TOPICS) do
            H.equal(Policy.TOPICS[i], topic.name, "wire topic order mirrors the ledger policy")
            H.truthy(Policy.valid_topic(topic.name))
        end
        H.equal(Policy.valid_topic("damage_dealt"), false, "native topics never travel here")

        local worst_wire = assert(Wire.packed_message_bytes(
            Policy.SCHEMA, Wire.SNAPSHOT,
            string.rep("g", Wire.MAX_GENERATION_BYTES),
            Wire.MAX_SEQUENCE, Wire.MAX_CHUNKS, Wire.MAX_CHUNKS,
            Policy.MAX_PAYLOAD_BYTES, string.rep('"', Wire.CHUNK_BYTES)))
        H.equal(worst_wire, 392,
            "the exact VMF cjson argument array must remain below the native cap")
        H.truthy(worst_wire <= Policy.MAX_PACKED_BYTES)

        -- Four maximal stats IDs, every topic, and the longest "%.14g" value
        -- text still fit the #1448 chunk plan without touching its constants.
        local rows = {}
        for i = 1, Policy.MAX_PLAYERS do
            local id = "peer-" .. i .. ":" .. string.rep(string.char(96 + i), 57)
            H.equal(#id, Policy.MAX_PLAYER_ID_BYTES)
            rows[i] = { id, 1.2345678901234e-05, 999999999.9999, 1000000000, 0.5 }
        end
        local codec = json_codec()
        local payload = codec.encode(valid_snapshot(rows))
        H.truthy(#payload > Wire.CHUNK_BYTES, "a realistic snapshot spans several chunks")
        H.truthy(#payload <= Policy.MAX_PAYLOAD_BYTES,
            "worst-case four-topic payload must fit the shared payload cap: " .. #payload)
        local chunks = assert(Wire.chunk_payload(payload))
        H.truthy(#chunks <= Wire.MAX_CHUNKS)
        H.deep_equal(codec.decode(payload), valid_snapshot(rows), "codec round trip")
        H.equal(Wire.chunk_payload(string.rep("x", Policy.MAX_PAYLOAD_BYTES + 1)), nil,
            "an oversized payload is refused before any send")
    end)

    H.test("GUT #1573 host projection sorts the roster and emits every topic positionally", function()
        local snapshot = valid_snapshot({
            { "peer-b:1", 0, 17, 2, 0 },
            { "peer-a:1", 1, 41, 5, 9 },
        })
        H.deep_equal(snapshot.players, { "peer-a:1", "peer-b:1" })
        H.equal(#snapshot.topics, 4)
        H.equal(snapshot.topics[2].name, MELEE)
        H.deep_equal(snapshot.topics[2].values, { 41, 17 })
        H.deep_equal(snapshot.topics[1].values, { 1, 0 }, "real zeros travel as zeros")

        local scores = rows_to_scores({ { "peer-a:1", 1, 2, 3, 4 } })
        local function refused(ids, ledger, expected)
            local built, reason = Policy.build_snapshot(ids, ledger)
            H.equal(built, nil, expected)
            H.equal(reason, expected)
        end
        refused({}, scores, "player-count")
        refused({ "peer-a:1", "peer-a:1" }, scores, "duplicate-player")
        refused({ "bad id" }, scores, "player-id")
        refused({ "peer-a:1", "peer-b:1" }, scores, "missing-player")
        refused({ "a:1", "b:1", "c:1", "d:1", "e:1" }, scores, "players-invalid-index")
        refused({ "peer-a:1" }, "ledger", "scores")
        for _, bad in ipairs({ 0 / 0, 1 / 0, -1, Policy.MAX_VALUE + 1, "7", nil }) do
            local ledger = rows_to_scores({ { "peer-a:1", 1, 2, 3, 4 } })
            ledger["peer-a:1"][RANGED] = bad
            refused({ "peer-a:1" }, ledger, "value")
        end
        local missing = rows_to_scores({ { "peer-a:1", 1, 2, 3, 4 } })
        missing["peer-a:1"][HEALTH] = nil
        refused({ "peer-a:1" }, missing, "value")
    end)

    H.test("GUT #1573 validator rejects malformed unknown duplicate and oversized rows", function()
        local known = { ["peer-a:1"] = true, ["peer-b:1"] = true }
        local verdict = assert(Policy.validate_snapshot(valid_snapshot(), known))
        H.equal(verdict.player_count, 2)
        H.equal(verdict.topic_count, 4)
        H.equal(verdict.scores["peer-a:1"][MELEE], 41)
        H.equal(verdict.scores["peer-b:1"][HEALTH], 0)
        H.truthy(verdict.fingerprint:match("^[0-9a-f]+$") ~= nil)

        expect_rejection({}, known, "snapshot-shape")
        expect_rejection({ players = {}, topics = {}, extra = 1 }, known, "snapshot-shape")
        expect_rejection(valid_snapshot(), nil, "known-players")
        expect_rejection({ players = "peer-a:1", topics = {} }, known, "snapshot-shape")
        expect_rejection({ players = {}, topics = "none" }, known, "snapshot-shape")
        expect_rejection({ players = {}, topics = {} }, known, "player-count")
        expect_rejection({ players = { "bad id" }, topics = {} }, known, "player-id")
        expect_rejection({ players = { string.rep("p", Policy.MAX_PLAYER_ID_BYTES + 1) },
            topics = {} }, known, "player-id")
        expect_rejection({ players = { "peer-a:1", "peer-a:1" }, topics = {} }, known,
            "duplicate-player")
        expect_rejection({ players = { "peer-a:1", "unknown:1" }, topics = {} }, known,
            "unknown-player")
        expect_rejection({ players = { "a:1", "b:1", "c:1", "d:1", "e:1" }, topics = {} },
            { ["a:1"] = true, ["b:1"] = true, ["c:1"] = true, ["d:1"] = true, ["e:1"] = true },
            "players-invalid-index")
        expect_rejection({ players = { "peer-a:1" }, topics = {} }, known, "topic-count")
        expect_rejection({ players = { "peer-a:1" }, topics = {
            { name = FF, values = { 1 } }, { name = MELEE, values = { 1 } },
            { name = RANGED, values = { 1 } }, { name = HEALTH, values = { 1 } },
            { name = FF, values = { 1 } },
        } }, known, "topics-invalid-index")
        expect_rejection({ players = { "peer-a:1" }, topics = { { name = FF } } }, known,
            "values-not-table")
        expect_rejection({ players = { "peer-a:1" }, topics = {
            { name = FF, values = { 1 }, extra = true },
        } }, known, "topic-shape")
        expect_rejection({ players = { "peer-a:1" }, topics = {
            { name = "damage_dealt", values = { 1 } },
        } }, known, "topic-name")
        expect_rejection({ players = { "peer-a:1" }, topics = {
            { name = string.rep("t", Policy.MAX_TOPIC_BYTES + 1), values = { 1 } },
        } }, known, "topic-name")
        expect_rejection({ players = { "peer-a:1" }, topics = {
            { name = FF, values = { 1 } }, { name = FF, values = { 2 } },
        } }, known, "duplicate-topic")
        expect_rejection({ players = { "peer-a:1", "peer-b:1" }, topics = {
            { name = FF, values = { 1 } },
        } }, known, "value-count")
        local sparse = { players = { "peer-a:1", "peer-b:1" }, topics = {
            { name = FF, values = { [1] = 1, [3] = 2 } },
        } }
        expect_rejection(sparse, known, "values-sparse-array")
        for _, bad in ipairs({ 0 / 0, 1 / 0, -1 / 0, -0.01, Policy.MAX_VALUE + 1, "1" }) do
            expect_rejection({ players = { "peer-a:1" }, topics = {
                { name = FF, values = { bad } },
            } }, known, "value")
        end

        local partial = assert(Policy.validate_snapshot({ players = { "peer-b:1" }, topics = {
            { name = HEALTH, values = { 12.5 } },
        } }, known))
        H.equal(partial.topic_count, 1)
        H.equal(partial.scores["peer-b:1"][HEALTH], 12.5)
        H.equal(partial.scores["peer-b:1"][MELEE], nil,
            "a topic the host did not acknowledge stays unavailable")
    end)

    H.test("GUT #1573 acknowledged cells replace only matching rows and keep native fallback", function()
        local native = {}
        local names = {
            "kills_elites", "kills_specials", "kills_total", "kills_melee",
            "kills_ranged", "damage_taken", "damage_dealt",
            "damage_dealt_bosses", "headshots", "saves", "revives",
        }
        for i, name in ipairs(names) do
            native[i] = { name = name, display_text = "scoreboard_topic_" .. name, stat_type = name }
        end
        local topics = ScorePolicy.build_topic_registry(native, CustomPolicy.TOPICS)
        H.equal(#topics, 17)
        local players = {
            ["peer-a:1"] = player("peer-a:1", "Alpha", 80),
            ["peer-b:1"] = player("peer-b:1", "Bravo", 30),
            ["peer-c:1"] = player("peer-c:1", "Charlie", 10),
        }
        local known = { ["peer-a:1"] = true, ["peer-b:1"] = true, ["peer-c:1"] = true }
        local verdict = assert(Policy.validate_snapshot({
            players = { "peer-a:1", "peer-b:1" },
            topics = {
                { name = MELEE, values = { 41, 17 } },
                { name = HEALTH, values = { 9, 0 } },
            },
        }, known))
        local model_players = {
            { stats_id = "peer-a:1" }, { stats_id = "peer-b:1" }, { stats_id = "peer-c:1" },
        }
        local custom_scores = Policy.scores_for_players(verdict.scores, model_players, 4)
        H.equal(custom_scores["peer-c:1"], nil, "an unacknowledged player gets no row")
        H.equal(custom_scores["peer-a:1"][FF], nil, "an unacknowledged topic gets no cell")
        custom_scores["peer-a:1"][MELEE] = 999
        H.equal(verdict.scores["peer-a:1"][MELEE], 41, "the projection is a detached copy")
        custom_scores["peer-a:1"][MELEE] = 41
        local bounded = Policy.scores_for_players(verdict.scores, {
            { stats_id = "x:1" }, { stats_id = "y:1" }, { stats_id = "z:1" },
            { stats_id = "w:1" }, { stats_id = "peer-a:1" },
        }, 9)
        H.equal(bounded["peer-a:1"], nil, "at most four presenter rows are visited")
        H.deep_equal(Policy.scores_for_players(nil, model_players, 4), {})

        local options = {
            selected_page = 2,
            sort_topic = "player_name",
            custom_scores = custom_scores,
        }
        local tab = ScorePolicy.build_native_model(players, topics, options)
        local finish = ScorePolicy.build_native_model(players, topics, options)
        local fallback = ScorePolicy.build_native_model(players, topics, {
            selected_page = 2,
            sort_topic = "player_name",
        })
        local function cell(model, stats_id, topic)
            for _, row in ipairs(model.players) do
                if row.stats_key == stats_id then return row.scores[topic] end
            end
        end
        H.equal(tab.page_count, 2)
        H.equal(cell(tab, "peer-a:1", MELEE), 41, "acknowledged host cell replaces the gap")
        H.equal(cell(tab, "peer-b:1", MELEE), 17)
        H.equal(cell(tab, "peer-b:1", HEALTH), 0, "an acknowledged zero is a real zero")
        H.equal(cell(tab, "peer-a:1", FF), nil, "unacknowledged topic stays unavailable")
        H.equal(cell(tab, "peer-c:1", MELEE), nil, "unacknowledged player stays unavailable")
        H.equal(cell(tab, "peer-a:1", "damage_dealt"), 80, "native rows are never rewritten")
        H.equal(tab.fingerprint, finish.fingerprint, "held-Tab and end-screen models agree")
        H.equal(cell(fallback, "peer-a:1", MELEE), nil,
            "no compatible snapshot keeps every custom cell unavailable")
        H.equal(cell(fallback, "peer-a:1", "damage_dealt"), 80)
    end)

    local GLOBAL_NAMES = {
        "get_mod", "Managers", "ScoreboardHelper", "cjson", "printf", "Application",
    }

    local function with_globals(values, body)
        local previous = {}
        for _, name in ipairs(GLOBAL_NAMES) do previous[name] = rawget(_G, name) end
        for _, name in ipairs(GLOBAL_NAMES) do rawset(_G, name, values[name]) end
        local ok, failure = pcall(body)
        for _, name in ipairs(GLOBAL_NAMES) do rawset(_G, name, previous[name]) end
        if not ok then error(failure, 0) end
    end

    local function new_fake_mod(settings)
        local state = { logs = {}, sends = {}, pings = 0, joins = 0, group_reads = 0,
            registered = {} }
        local fake_mod = { settings = settings }
        function fake_mod:dofile(path)
            return assert(loadfile(mod_root .. path .. ".lua"))()
        end
        function fake_mod:get(setting_id) return self.settings[setting_id] end
        function fake_mod:network_register(channel, callback)
            assert(state.channel == nil, "one channel per module")
            state.channel, state.receiver = channel, callback
        end
        function fake_mod:network_send(...)
            local sent = { ... }
            sent.argc = select("#", ...)
            state.sends[#state.sends + 1] = sent
        end
        function fake_mod.on_user_joined() state.joins = state.joins + 1 end
        fake_mod._gut_rt_register = function(name, fn)
            state.registered[#state.registered + 1] = { name = name, fn = fn }
        end
        return fake_mod, state
    end

    local function saw(logs, needle)
        for _, line in ipairs(logs) do
            if line:find(needle, 1, true) then return true end
        end
        return false
    end

    H.test("GUT #1573 real client adapter authenticates orders reassembles retries and falls back", function()
        local fake_mod, state = new_fake_mod({
            gut_scoreboard_live_native = false,
            gut_scoreboard_custom_stats = false,
        })
        state.host = "host-peer"
        state.players = {}
        local long_ids = {}
        for i = 1, 4 do
            local id = "peer-" .. i .. ":" .. string.rep(string.char(96 + i), 57)
            H.equal(#id, Policy.MAX_PLAYER_ID_BYTES)
            long_ids[i] = id
            state.players[id] = player(id, "Peer " .. i, i)
        end
        local codec = json_codec()
        local function snapshot_rows(rows)
            return codec.encode(valid_snapshot(rows))
        end
        with_globals({
            get_mod = function(name)
                if name == "gut_dev" then return fake_mod end
                if name == "VMF" then
                    return { ping_vmf_users = function() state.pings = state.pings + 1 end }
                end
            end,
            Managers = {
                mechanism = {
                    current_mechanism_name = function() return "adventure" end,
                    server_peer_id = function() return state.host end,
                },
                player = {
                    is_server = false,
                    statistics_db = function() return {} end,
                    human_players = function() return {} end,
                },
                state = { network = { profile_synchronizer = {} } },
            },
            ScoreboardHelper = {
                get_grouped_topic_statistics = function()
                    state.group_reads = state.group_reads + 1
                    return state.players
                end,
            },
            cjson = codec,
            printf = function(fmt, ...) state.logs[#state.logs + 1] = string.format(fmt, ...) end,
            Application = nil,
        }, function()
            local api = assert(loadfile(runtime_path))()
            H.equal(state.channel, Policy.CHANNEL)
            H.equal(fake_mod._gut_custom_stat_sync, api, "the child publishes its API")
            H.equal(api.wire.CHANNEL, Wire.CHANNEL, "the wire policy is #1448's module")
            H.equal(#state.registered, 1)
            H.equal(state.registered[1].name, "issue1573_client_custom_statistics_sync")
            H.equal(api.rt_checks[1].fn(), nil,
                "named runtime check must execute the real projection/validator/model path")
            H.equal(api.rt_checks[1].fn(), nil, "repeat")
            local runtime_receipts = 0
            for _, line in ipairs(state.logs) do
                if line:find("event=runtime-check", 1, true) then
                    runtime_receipts = runtime_receipts + 1
                end
            end
            H.equal(runtime_receipts, 1, "one bounded runtime receipt")

            fake_mod.on_game_state_changed("enter", "StateIngame")
            for _ = 1, 6 do fake_mod.update(Wire.ROSTER_POLL_DELAY) end
            H.equal(state.group_reads, 0, "a disabled client never polls grouped scores")
            H.equal(#state.sends, 0)

            -- Only the expanded scoreboard: the custom rows stay opt-in.
            fake_mod.settings.gut_scoreboard_live_native = true
            fake_mod.on_setting_changed("gut_scoreboard_live_native")
            fake_mod.update(0)
            fake_mod.update(Wire.HANDSHAKE_DELAY)
            H.equal(#state.sends, 0, "Host Statistics off means no request")
            fake_mod.settings.gut_scoreboard_custom_stats = true
            fake_mod.on_setting_changed("gut_scoreboard_custom_stats")
            fake_mod.update(0)
            fake_mod.update(Wire.HANDSHAKE_DELAY)
            local request = state.sends[#state.sends]
            H.truthy(request ~= nil, "both options on starts the readiness pull")
            H.equal(request.argc, 10, "installed sender uses the exact ten-field VMF call")
            H.equal(request[1], Policy.CHANNEL)
            H.equal(request[2], "host-peer")
            H.equal(request[3], Policy.SCHEMA)
            H.equal(request[4], Wire.REQUEST)
            H.truthy(Wire.valid_generation(request[5]))
            H.truthy(request[5]:match("^c1%-") ~= nil, "custom generations are namespaced")
            H.equal(request[6], 1)
            H.equal(request[7], 0)
            H.equal(request[8], 0)
            H.equal(request[9], 0)
            H.equal(request[10], "")
            H.truthy(state.pings >= 1, "VMF re-handshake precedes the request")
            local generation = request[5]

            local payload = snapshot_rows({
                { long_ids[1], 910000000, 810000000, 710000000, 610000000 },
                { long_ids[2], 1, 2, 3, 4 },
                { long_ids[3], 0, 0, 0, 0 },
                { long_ids[4], 5.5, 6.5, 7.5, 8.5 },
            })
            local chunks = assert(Wire.chunk_payload(payload))
            H.truthy(#chunks >= 3, "four bounded rows with four topics cross several chunks")
            for part, chunk in ipairs(chunks) do
                H.truthy(assert(Wire.packed_message_bytes(Policy.SCHEMA, Wire.SNAPSHOT,
                    generation, 1, part, #chunks, #payload, chunk)) <= Policy.MAX_PACKED_BYTES)
            end
            local function deliver(sender, gen, seq, part, chunk, total, size)
                state.receiver(sender, Policy.SCHEMA, Wire.SNAPSHOT, gen, seq, part,
                    total or #chunks, size or #payload, chunk)
            end
            local function score(id, topic)
                local scores = api.current_scores({ { stats_id = id } })
                return scores and scores[id] and scores[id][topic]
            end

            deliver("forged-peer", generation, 1, 1, chunks[1])
            H.equal(api.current_scores({ { stats_id = long_ids[1] } }), nil)
            deliver("host-peer", generation, 1, 2, chunks[2])
            H.equal(api.current_scores({ { stats_id = long_ids[1] } }), nil,
                "a partial assembly never leaks")
            deliver("host-peer", generation, 1, 2, chunks[2])
            local tampered = chunks[2]:sub(1, #chunks[2] - 1) .. "x"
            deliver("host-peer", generation, 1, 2, tampered)
            H.equal(api.current_scores({ { stats_id = long_ids[1] } }), nil)
            for part = #chunks, 1, -1 do
                deliver("host-peer", generation, 1, part, chunks[part])
                if part > 1 then
                    H.equal(api.current_scores({ { stats_id = long_ids[1] } }), nil,
                        "no cell is exposed before the final chunk")
                end
            end
            H.equal(score(long_ids[1], FF), 910000000, "reordered chunks complete one snapshot")
            H.equal(score(long_ids[4], HEALTH), 8.5)
            H.equal(score(long_ids[3], MELEE), 0, "an acknowledged zero is shown as zero")
            H.equal(api.current_scores({ { stats_id = "absent:1" } })["absent:1"], nil)

            -- Duplicate, stale generation and future sequence cannot replace it.
            deliver("host-peer", generation, 1, 1, chunks[1])
            deliver("host-peer", "old-generation", 1, 1, chunks[1])
            deliver("host-peer", generation, 2, 1, chunks[1])
            H.equal(score(long_ids[1], FF), 910000000)

            -- Refresh at sequence two; a snapshot naming a player outside the
            -- local roster is rejected whole and the prior display survives.
            fake_mod.update(Wire.REFRESH_DELAY)
            fake_mod.update(0)
            fake_mod.update(Wire.HANDSHAKE_DELAY)
            request = state.sends[#state.sends]
            H.equal(request[5], generation)
            H.equal(request[6], 2)
            local stranger = snapshot_rows({ { long_ids[1], 1, 1, 1, 1 }, { "stranger:1", 2, 2, 2, 2 } })
            local stranger_chunks = assert(Wire.chunk_payload(stranger))
            for part, chunk in ipairs(stranger_chunks) do
                deliver("host-peer", generation, 2, part, chunk, #stranger_chunks, #stranger)
            end
            H.equal(score(long_ids[1], FF), 910000000, "unknown roster row keeps prior display")
            H.truthy(saw(state.logs, "reason=unknown-player"))
            local refreshed = snapshot_rows({ { long_ids[1], 11, 12, 13, 14 } })
            local refreshed_chunks = assert(Wire.chunk_payload(refreshed))
            for part, chunk in ipairs(refreshed_chunks) do
                deliver("host-peer", generation, 2, part, chunk, #refreshed_chunks, #refreshed)
            end
            H.equal(score(long_ids[1], RANGED), 13, "a valid later sequence replaces the row")
            H.equal(score(long_ids[2], FF), nil, "a player the host stopped acknowledging is unavailable")

            -- Mixed/no-GUT host: the next refresh gets no answer. Exactly four
            -- attempts, VMF pongs never rearm, and the stale display expires.
            fake_mod.update(Wire.REFRESH_DELAY)
            fake_mod.update(0)
            local before_retry = #state.sends
            local host_player = { network_id = function() return "host-peer" end }
            for _ = 1, Wire.MAX_RETRIES * 2 do
                fake_mod.on_user_joined(host_player)
                fake_mod.update(Wire.RETRY_DELAY)
                fake_mod.on_user_joined(host_player)
            end
            H.equal(#state.sends - before_retry, Wire.MAX_RETRIES,
                "installed mixed/no-GUT path emits exactly four attempts")
            for _ = 1, Wire.MAX_RETRIES * 2 do
                fake_mod.on_user_joined(host_player)
                fake_mod.update(Wire.RETRY_DELAY)
            end
            H.equal(#state.sends - before_retry, Wire.MAX_RETRIES,
                "delayed VMF pongs must not rearm a terminal pull")
            fake_mod.update(Wire.SNAPSHOT_TTL)
            H.equal(api.current_scores({ { stats_id = long_ids[1] } }), nil,
                "an expired snapshot falls back to unavailable rows")
            fake_mod.update(Wire.RETRY_DELAY)
            H.equal(#state.sends - before_retry, Wire.MAX_RETRIES,
                "a terminal client sends nothing more")

            -- Disabling Host Statistics retires an armed identity; re-enable
            -- starts a fresh generation at sequence one.
            fake_mod.settings.gut_scoreboard_custom_stats = false
            fake_mod.on_setting_changed("gut_scoreboard_custom_stats")
            fake_mod.settings.gut_scoreboard_custom_stats = true
            fake_mod.on_setting_changed("gut_scoreboard_custom_stats")
            fake_mod.update(0)
            fake_mod.update(Wire.HANDSHAKE_DELAY)
            request = state.sends[#state.sends]
            H.truthy(request[5] ~= generation)
            H.equal(request[6], 1)
            local fresh_host = Wire.new_host_session()
            H.equal(assert(Wire.plan_host_request(fresh_host, request[5], 1, 0, 0)).kind, "build")

            local fresh = snapshot_rows({ { long_ids[1], 21, 22, 23, 24 } })
            local fresh_chunks = assert(Wire.chunk_payload(fresh))
            for part, chunk in ipairs(fresh_chunks) do
                deliver("host-peer", request[5], 1, part, chunk, #fresh_chunks, #fresh)
            end
            H.equal(score(long_ids[1], MELEE), 22)
            state.host = "migrated-host"
            fake_mod.update(0.01)
            H.equal(api.current_scores({ { stats_id = long_ids[1] } }), nil,
                "host migration retires the old host's snapshot")
            state.host = "host-peer"
            fake_mod.on_game_state_changed("exit", "StateIngame")
            H.equal(api.current_scores({ { stats_id = long_ids[1] } }), nil)
            fake_mod.on_game_state_changed("enter", "StateIngame")
            fake_mod.on_user_left(host_player)
            H.equal(api.current_scores({ { stats_id = long_ids[1] } }), nil)

            H.truthy(saw(state.logs, "reason=non-host"))
            H.truthy(saw(state.logs, "reason=stale-generation"))
            H.truthy(saw(state.logs, "reason=out-of-order-sequence"))
            H.truthy(saw(state.logs, "reason=conflict"))
            H.truthy(saw(state.logs, "[gut:1573] raw"))
            H.truthy(#state.logs <= 24, "raw receipts stay under the process cap")
        end)
    end)

    H.test("GUT #1573 real host adapter answers authenticated requests from the ledger owner", function()
        local fake_mod, state = new_fake_mod({
            gut_scoreboard_live_native = false,
            gut_scoreboard_custom_stats = false,
        })
        state.mechanism = "adventure"
        state.players = {
            ["host-peer:1"] = player("host-peer:1", "Host", 41),
            ["client-peer:1"] = player("client-peer:1", "Client", 17),
        }
        state.ledger = {
            ["host-peer:1"] = { [FF] = 3, [MELEE] = 41, [RANGED] = 5, [HEALTH] = 20 },
        }
        state.ledger_reads = 0
        state.ledger_available = true
        fake_mod._gut_custom_stats = {
            current_scores = function(rows)
                state.ledger_reads = state.ledger_reads + 1
                if not state.ledger_available then return nil end
                local scores = {}
                for _, row in ipairs(rows) do
                    local ledger = state.ledger[row.stats_id]
                    scores[row.stats_id] = {
                        [FF] = ledger and ledger[FF] or 0,
                        [MELEE] = ledger and ledger[MELEE] or 0,
                        [RANGED] = ledger and ledger[RANGED] or 0,
                        [HEALTH] = ledger and ledger[HEALTH] or 0,
                    }
                end
                return scores
            end,
        }
        local client_player = { network_id = function() return "client-peer" end }
        local codec = json_codec()
        state.encodes = 0
        local encode = codec.encode
        codec.encode = function(value)
            state.encodes = state.encodes + 1
            return encode(value)
        end
        with_globals({
            get_mod = function(name) return name == "gut_dev" and fake_mod or nil end,
            Managers = {
                mechanism = {
                    current_mechanism_name = function() return state.mechanism end,
                    server_peer_id = function() return "host-peer" end,
                },
                player = {
                    is_server = true,
                    statistics_db = function() return {} end,
                    human_players = function() return { client = client_player } end,
                },
                state = { network = { profile_synchronizer = {} } },
            },
            ScoreboardHelper = {
                get_grouped_topic_statistics = function()
                    state.group_reads = state.group_reads + 1
                    return state.players
                end,
            },
            cjson = codec,
            printf = function(fmt, ...) state.logs[#state.logs + 1] = string.format(fmt, ...) end,
            Application = nil,
        }, function()
            assert(loadfile(runtime_path))()
            local function request(peer, gen, seq)
                state.receiver(peer, Policy.SCHEMA, Wire.REQUEST, gen, seq, 0, 0, 0, "")
            end
            fake_mod.on_game_state_changed("enter", "StateIngame")
            for _ = 1, 8 do fake_mod.update(Wire.ROSTER_POLL_DELAY) end
            H.equal(state.group_reads, 0, "a host with no requester never polls grouped scores")
            request("forged-peer", "mission-a", 1)
            H.equal(#state.sends, 0, "an unauthenticated request gets nothing")
            request("client-peer", "mission-a", 2)
            H.equal(#state.sends, 0, "an impossible first sequence gets nothing")
            H.equal(state.ledger_reads, 0)

            request("client-peer", "mission-a", 1)
            local first_count = #state.sends
            H.truthy(first_count > 0)
            H.equal(state.encodes, 1)
            H.equal(state.ledger_reads, 1)
            local parts = {}
            for i = 1, first_count do
                local sent = state.sends[i]
                H.equal(sent.argc, 10, "installed host sender keeps the exact wire signature")
                H.equal(sent[1], Policy.CHANNEL)
                H.equal(sent[2], "client-peer")
                H.equal(sent[3], Policy.SCHEMA)
                H.equal(sent[4], Wire.SNAPSHOT)
                H.equal(sent[5], "mission-a")
                H.equal(sent[6], 1)
                H.equal(sent[7], i)
                H.equal(sent[8], first_count)
                H.truthy(sent[9] <= Policy.MAX_PAYLOAD_BYTES)
                H.truthy(#sent[10] <= Wire.CHUNK_BYTES)
                H.truthy(assert(Wire.packed_message_bytes(sent[3], sent[4], sent[5], sent[6],
                    sent[7], sent[8], sent[9], sent[10])) <= Policy.MAX_PACKED_BYTES)
                parts[i] = sent[10]
            end
            local payload = table.concat(parts)
            H.equal(#payload, state.sends[1][9])
            local decoded = codec.decode(payload)
            local verdict = assert(Policy.validate_snapshot(decoded,
                assert(Wire.known_players(state.players))))
            H.deep_equal(decoded.players, { "client-peer:1", "host-peer:1" },
                "the host emits the sorted current roster")
            H.equal(verdict.topic_count, 4)
            H.equal(verdict.scores["host-peer:1"][MELEE], 41)
            H.equal(verdict.scores["client-peer:1"][MELEE], 0,
                "a known player without a ledger row travels as a real zero")

            -- Duplicate requests replay the immutable cached bytes.
            state.ledger["host-peer:1"][MELEE] = 99
            fake_mod.on_user_left(client_player)
            fake_mod.on_user_joined(client_player)
            fake_mod.update(Wire.RESPONSE_SEND_FLOOR)
            request("client-peer", "mission-a", 1)
            H.equal(#state.sends, first_count * 2)
            H.equal(state.encodes, 1)
            H.equal(state.ledger_reads, 1, "a replay never re-reads the ledger")
            for i = 1, first_count do
                H.equal(state.sends[first_count + i][10], parts[i])
            end
            -- A short same-tick flood (the receipt cap keeps the later
            -- evidence lines readable; the boss suite proves the long flood).
            local after_duplicate = #state.sends
            for i = 1, 3 do
                request("client-peer", "mission-a", 1)
                request("client-peer", "mission-a", 2 + i)
                request("client-peer", "flood-" .. i, 1)
            end
            H.equal(#state.sends, after_duplicate, "same-tick floods are rate-bounded")
            H.equal(state.encodes, 1)

            -- A fresh contiguous sequence waits for both floors, then reflects
            -- the newer ledger value.
            fake_mod.update(Wire.FRESH_BUILD_FLOOR)
            request("client-peer", "mission-a", 2)
            H.truthy(#state.sends > after_duplicate)
            H.equal(state.encodes, 2)
            local latest = {}
            for i = after_duplicate + 1, #state.sends do latest[#latest + 1] = state.sends[i][10] end
            local latest_decoded = codec.decode(table.concat(latest))
            H.equal(latest_decoded.topics[2].name, MELEE)
            H.equal(latest_decoded.topics[2].values[2], 99)

            -- The ledger owner may be unavailable; no partial answer is sent.
            local before_unavailable = #state.sends
            state.ledger_available = false
            fake_mod.update(Wire.FRESH_BUILD_FLOOR)
            request("client-peer", "mission-a", 3)
            H.equal(#state.sends, before_unavailable)
            H.truthy(saw(state.logs, "reason=host-ledger-unavailable"))
            state.ledger_available = true

            -- Outside Adventure the host answers nothing.
            state.mechanism = "deus"
            fake_mod.update(Wire.FRESH_BUILD_FLOOR)
            request("client-peer", "mission-a", 3)
            H.equal(#state.sends, before_unavailable)
            H.truthy(saw(state.logs, "reason=request-role"))
            state.mechanism = "adventure"

            fake_mod.on_game_state_changed("exit", "StateIngame")
            fake_mod.on_game_state_changed("enter", "StateIngame")
            request("client-peer", "mission-b", 1)
            H.truthy(#state.sends > before_unavailable,
                "mission reset retires the prior peer session")
        end)
    end)

    H.test("GUT #1573 ledger owner routes non-host reads to the accepted host snapshot", function()
        local fake_mod, state = new_fake_mod({
            gut_scoreboard_live_native = true,
            gut_scoreboard_custom_stats = true,
        })
        fake_mod.hooks = {}
        function fake_mod:hook(class_name, method_name, callback)
            self.hooks[class_name .. "." .. method_name] = callback
        end
        fake_mod._gut_scoreboard_retention = { add_listener = function() return true end }
        state.players = {
            ["host-peer:1"] = player("host-peer:1", "Host", 41),
            ["client-peer:1"] = player("client-peer:1", "Client", 17),
        }
        local codec = json_codec()
        local player_manager = {
            is_server = false,
            statistics_db = function() return {} end,
            human_players = function() return {} end,
            players = function() return {} end,
        }
        with_globals({
            get_mod = function(name)
                if name == "gut_dev" then return fake_mod end
                if name == "VMF" then return { ping_vmf_users = function() end } end
            end,
            Managers = {
                mechanism = {
                    current_mechanism_name = function() return "adventure" end,
                    server_peer_id = function() return "host-peer" end,
                },
                player = player_manager,
                state = { network = { profile_synchronizer = {} } },
            },
            ScoreboardHelper = {
                get_grouped_topic_statistics = function() return state.players end,
            },
            cjson = codec,
            printf = function(fmt, ...) state.logs[#state.logs + 1] = string.format(fmt, ...) end,
            Application = nil,
        }, function()
            local owner = assert(loadfile(owner_path))()
            H.equal(fake_mod._gut_custom_stats, owner)
            H.equal(type(fake_mod._gut_custom_stat_sync), "table",
                "the ledger owner loads its transport child")
            H.equal(state.channel, Policy.CHANNEL)
            H.equal(#state.registered, 4)
            H.equal(state.registered[4].name, "issue1573_client_custom_statistics_sync")
            H.equal(saw(state.logs, "sync module failed"), false)

            local rows = { { stats_id = "host-peer:1" }, { stats_id = "client-peer:1" } }
            H.equal(owner.current_scores(rows), nil, "no mission yet")
            fake_mod.on_game_state_changed("enter", "StateIngame")
            H.equal(owner.current_scores(rows), nil,
                "a client without an accepted snapshot shows unavailable rows")
            fake_mod.update(0)
            fake_mod.update(Wire.HANDSHAKE_DELAY)
            local request = state.sends[#state.sends]
            H.equal(request[1], Policy.CHANNEL)
            local payload = codec.encode(valid_snapshot({
                { "client-peer:1", 0, 17, 2, 0 },
                { "host-peer:1", 3, 41, 5, 20 },
            }))
            local chunks = assert(Wire.chunk_payload(payload))
            for part, chunk in ipairs(chunks) do
                state.receiver("host-peer", Policy.SCHEMA, Wire.SNAPSHOT, request[5],
                    request[6], part, #chunks, #payload, chunk)
            end
            local scores = assert(owner.current_scores(rows))
            H.equal(scores["host-peer:1"][MELEE], 41,
                "the owner's presenter API now answers from the host snapshot")
            H.equal(scores["client-peer:1"][HEALTH], 0)
            H.equal(scores["host-peer:1"].damage_dealt, nil)

            -- The recording host keeps answering from its own ledger.
            player_manager.is_server = true
            local host_scores = assert(owner.current_scores(rows))
            H.equal(host_scores["host-peer:1"][MELEE], 0,
                "the host path reads the local ledger, never the snapshot")
            player_manager.is_server = false
            H.equal(assert(owner.current_scores(rows))["host-peer:1"][MELEE], 41)

            fake_mod.on_game_state_changed("exit", "StateIngame")
            H.equal(owner.current_scores(rows), nil)
        end)
    end)

    H.test("GUT #1573 source owns one separate mod channel and no vanilla wire or damage hook", function()
        local runtime = read(runtime_path)
        local policy = read(policy_path)
        local owner = read(owner_path)
        local live = read(scripts .. "_gut_scoreboard_live.lua")
        local entry = read(scripts .. "gui_tweaker_dev.lua")
        local stable_entry = read(repo_root .. "/gui_tweaker/scripts/mods/gui_tweaker/gui_tweaker.lua")
        local stable_live = read(repo_root .. "/gui_tweaker/scripts/mods/gui_tweaker/_gut_scoreboard_live.lua")

        H.equal(count_plain(runtime, "mod:network_register("), 1)
        H.equal(count_plain(runtime, "mod:hook("), 0)
        H.equal(count_plain(runtime, "mod:hook_safe("), 0)
        H.truthy(policy:find('M.CHANNEL = "gut_custom_stat_snapshot_v1"', 1, true) ~= nil)
        H.truthy(runtime:find('"scripts/mods/gui_tweaker_dev/_gut_boss_damage_sync_policy"', 1, true) ~= nil,
            "the transport binds the #1448 wire policy module")
        H.truthy(runtime:find("Contract.CHANNEL == Wire.CHANNEL", 1, true) ~= nil,
            "load-time parity refuses a shared channel")
        H.truthy(owner:find('"scripts/mods/gui_tweaker_dev/_gut_custom_stat_sync"', 1, true) ~= nil,
            "the ledger owner loads the transport child")
        H.truthy(owner:find('rawget(mod, "_gut_custom_stat_sync")', 1, true) ~= nil,
            "non-host reads route through the child")
        H.truthy(entry:find("local GUT_RPC_SCHEMA = 1", 1, true) ~= nil)
        H.truthy(entry:find('"scripts/mods/gui_tweaker_dev/_gut_custom_stats"', 1, true) ~= nil)
        H.equal(entry:find("_gut_custom_stat_sync", 1, true), nil,
            "the entry point stays within its size ceiling; the owner loads the child")
        H.truthy(live:find("options.custom_scores", 1, true) ~= nil)

        for _, source in ipairs({ runtime, policy }) do
            local executable = source:gsub("%-%-[^\n]*", "")
            H.equal(executable:find("NetworkLookup", 1, true), nil)
            H.equal(executable:find("StatisticsDefinitions", 1, true), nil)
            H.equal(executable:find("DamageUtils", 1, true), nil)
            H.equal(executable:find("register_damage", 1, true), nil)
            H.equal(executable:find("rpc_players_session_score", 1, true), nil)
            H.equal(executable:find("rpc_sync_statistics", 1, true), nil)
        end
        H.equal(stable_entry:find("_gut_custom_stat", 1, true), nil)
        H.equal(stable_live:find("custom_scores", 1, true), nil)
    end)
end
