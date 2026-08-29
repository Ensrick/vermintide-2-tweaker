return function(H, repo_root)
    local policy_path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_boss_damage_sync_policy.lua"
    local score_policy_path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_scoreboard_policy.lua"
    local runtime_path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_boss_damage_sync.lua"
    local mod_root = repo_root .. "/gui_tweaker_dev/"
    local Policy = assert(loadfile(policy_path))()
    local ScorePolicy = assert(loadfile(score_policy_path))()

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

    local function player(stats_id, name, boss)
        return {
            stats_id = stats_id,
            name = name,
            group_scores = {
                offense = {
                    { stat_name = "kills_total", score = 2 },
                    { stat_name = Policy.TOPIC, score = boss },
                },
            },
        }
    end

    local function valid_snapshot(rows)
        local values = {}
        for i, row in ipairs(rows or {
            { "peer-a:1", 41 },
            { "peer-b:1", 17 },
        }) do
            values[i] = { player_id = row[1], value = row[2] }
        end
        return {
            topics = {
                { name = Policy.TOPIC, values = values },
            },
        }
    end

    local function expect_snapshot_rejection(snapshot, known, expected)
        local verdict, reason = Policy.validate_snapshot(snapshot, known)
        H.equal(verdict, nil)
        H.equal(reason, expected)
    end

    H.test("GUT #1448 exact schema accepts the host's grouped vanilla snapshot", function()
        H.equal(Policy.CHANNEL, "gut_boss_damage_snapshot_v1")
        H.equal(Policy.SCHEMA, 1)
        H.equal(Policy.MAX_PACKED_BYTES, 400)
        local request_ok = Policy.validate_envelope(1, Policy.REQUEST,
            "mission-1", 1, 0, 0, 0, "")
        H.equal(request_ok, true)
        local snapshot_ok = Policy.validate_envelope(1, Policy.SNAPSHOT,
            "mission-1", 1, 1, 1, 12, "payload-data")
        H.equal(snapshot_ok, true)
        local wrong_schema, reason = Policy.validate_envelope(2, Policy.REQUEST,
            "mission-1", 1, 0, 0, 0, "")
        H.equal(wrong_schema, false)
        H.equal(reason, "schema")

        local worst_wire = assert(Policy.packed_message_bytes(
            Policy.SCHEMA, Policy.SNAPSHOT,
            string.rep("g", Policy.MAX_GENERATION_BYTES),
            Policy.MAX_SEQUENCE, Policy.MAX_CHUNKS, Policy.MAX_CHUNKS,
            Policy.MAX_PAYLOAD_BYTES, string.rep('"', Policy.CHUNK_BYTES)))
        H.equal(worst_wire, 392,
            "exact VMF cjson argument array must remain below the native cap")
        H.truthy(worst_wire <= Policy.MAX_PACKED_BYTES)

        local native = {
            ["peer-b:1"] = player("peer-b:1", "Bravo", 17),
            ["peer-a:1"] = player("peer-a:1", "Alpha", 41),
        }
        local snapshot = assert(Policy.extract_grouped_snapshot(native))
        H.equal(snapshot.topics[1].name, Policy.TOPIC)
        H.equal(snapshot.topics[1].values[1].player_id, "peer-a:1")
        H.equal(snapshot.topics[1].values[1].value, 41)
        local known = assert(Policy.known_players(native))
        local verdict = assert(Policy.validate_snapshot(snapshot, known))
        H.equal(verdict.player_count, 2)
        H.equal(verdict.topic_count, 1)
        H.equal(verdict.scores["peer-a:1"], 41)
        H.truthy(verdict.fingerprint:match("^[0-9a-f]+$") ~= nil)
    end)

    H.test("GUT #1448 envelope bounds generation sequence strings and payload", function()
        local cases = {
            { 1, Policy.REQUEST, "", 1, 0, 0, 0, "", "generation" },
            { 1, Policy.REQUEST, string.rep("g", 65), 1, 0, 0, 0, "", "generation" },
            { 1, Policy.REQUEST, "bad\nvalue", 1, 0, 0, 0, "", "generation" },
            { 1, Policy.REQUEST, "g", 0, 0, 0, 0, "", "sequence" },
            { 1, Policy.REQUEST, "g", 1.5, 0, 0, 0, "", "sequence" },
            { 1, Policy.REQUEST, "g", Policy.MAX_SEQUENCE + 1, 0, 0, 0, "", "sequence" },
            { 1, Policy.REQUEST, "g", 1, 1, 0, 0, "", "request-shape" },
            { 1, Policy.SNAPSHOT, "g", 1, 0, 1, 1, "x", "part" },
            { 1, Policy.SNAPSHOT, "g", 1, 1, Policy.MAX_CHUNKS + 1, 1, "x", "total" },
            { 1, Policy.SNAPSHOT, "g", 1, 1, 1, Policy.MAX_PAYLOAD_BYTES + 1, "x", "payload-size" },
            { 1, Policy.SNAPSHOT, "g", 1, 1, 1, 1, string.rep("x", Policy.CHUNK_BYTES + 1), "chunk" },
        }
        for _, case in ipairs(cases) do
            local ok, reason = Policy.validate_envelope(
                case[1], case[2], case[3], case[4], case[5], case[6],
                case[7], case[8])
            H.equal(ok, false)
            H.equal(reason, case[9])
        end
        H.equal(Policy.chunk_payload(string.rep("x", Policy.MAX_PAYLOAD_BYTES + 1)), nil)
    end)

    H.test("GUT #1448 validator rejects malformed unknown duplicate and oversized rows", function()
        local known = { ["peer-a:1"] = true, ["peer-b:1"] = true }

        expect_snapshot_rejection({}, known, "snapshot-shape")
        expect_snapshot_rejection({ topics = {}, extra = true }, known,
            "snapshot-shape")
        expect_snapshot_rejection({ topics = {} }, known, "topic-count")
        expect_snapshot_rejection({ topics = {
            { name = Policy.TOPIC, values = {} },
            { name = Policy.TOPIC, values = {} },
        } }, known, "topics-invalid-index")
        expect_snapshot_rejection({ topics = {
            { name = string.rep("t", Policy.MAX_TOPIC_BYTES + 1), values = {
                { player_id = "peer-a:1", value = 1 },
            } },
        } }, known, "topic-name")
        expect_snapshot_rejection(valid_snapshot({ { "unknown:1", 2 } }),
            known, "unknown-player")
        expect_snapshot_rejection(valid_snapshot({
            { "peer-a:1", 2 }, { "peer-a:1", 3 },
        }), known, "duplicate-player")
        expect_snapshot_rejection(valid_snapshot({
            { "peer-a:1", 1 }, { "peer-b:1", 2 }, { "c:1", 3 },
            { "d:1", 4 }, { "e:1", 5 },
        }), known, "players-invalid-index")
        expect_snapshot_rejection(valid_snapshot({
            { string.rep("p", Policy.MAX_PLAYER_ID_BYTES + 1), 1 },
        }), known, "player-id")
        expect_snapshot_rejection({ topics = {
            { name = Policy.TOPIC, values = {
                { player_id = "peer-a:1", value = 1, extra = true },
            } },
        } }, known, "player-shape")
        local sparse = valid_snapshot({ { "peer-a:1", 1 } })
        sparse.topics[1].values[3] = sparse.topics[1].values[1]
        sparse.topics[1].values[1] = nil
        expect_snapshot_rejection(sparse, known, "players-sparse-array")
    end)

    H.test("GUT #1448 validator rejects NaN infinity negative and over-cap values", function()
        local known = { ["peer-a:1"] = true }
        local bad_values = {
            0 / 0,
            1 / 0,
            -1 / 0,
            -0.01,
            Policy.MAX_VALUE + 1,
        }
        for _, value in ipairs(bad_values) do
            expect_snapshot_rejection(valid_snapshot({ { "peer-a:1", value } }),
                known, "value")
        end
        local native = { a = player("peer-a:1", "Alpha", 0 / 0) }
        local snapshot, reason = Policy.extract_grouped_snapshot(native)
        H.equal(snapshot, nil)
        H.equal(reason, "value")
    end)

    H.test("GUT #1448 chunks reassemble out of order and reject conflicting duplicates", function()
        local payload = string.rep("a", Policy.CHUNK_BYTES + 17)
            .. string.rep("b", Policy.CHUNK_BYTES + 17)
        local chunks = assert(Policy.chunk_payload(payload))
        H.equal(#chunks, 3)
        local state = assert(Policy.new_reassembly("generation", 4,
            #chunks, #payload))
        local complete, reason = Policy.accept_chunk(state, 2, #chunks,
            #payload, chunks[2])
        H.equal(complete, nil)
        H.equal(reason, "pending")
        complete, reason = Policy.accept_chunk(state, 2, #chunks,
            #payload, chunks[2])
        H.equal(complete, nil)
        H.equal(reason, "duplicate")
        complete, reason = Policy.accept_chunk(state, 1, #chunks,
            #payload, chunks[1])
        H.equal(reason, "pending")
        complete, reason = Policy.accept_chunk(state, 3, #chunks,
            #payload, chunks[3])
        H.equal(reason, "complete")
        H.equal(complete, payload)

        local conflict = assert(Policy.new_reassembly("generation", 5, 1, 1))
        Policy.accept_chunk(conflict, 1, 1, 1, "x")
        local _, conflict_reason = Policy.accept_chunk(conflict, 1, 1, 1, "y")
        H.equal(conflict_reason, "conflict")
    end)

    H.test("GUT #1448 authenticates the current host and orders generations and sequences", function()
        local function verdict(host, sender, current_generation, pending,
                accepted_generation, accepted, message_generation, sequence,
                expected)
            local ok, reason = Policy.classify_response(host, sender,
                current_generation, pending, accepted_generation, accepted,
                message_generation, sequence)
            H.equal(ok, expected == "accept")
            H.equal(reason, expected)
        end
        verdict(nil, "host", "g2", 3, "g2", 2, "g2", 3, "missing-host")
        verdict("host", "forged", "g2", 3, "g2", 2, "g2", 3, "non-host")
        verdict("host", "host", "g2", 3, "g2", 2, "g1", 3, "stale-generation")
        verdict("host", "host", "g2", 3, "g2", 2, "g2", 2, "duplicate")
        verdict("host", "host", "g2", 4, "g2", 2, "g2", 3, "stale-sequence")
        verdict("host", "host", "g2", 3, "g2", 2, "g2", 4, "out-of-order-sequence")
        verdict("host", "host", "g2", 3, "g2", 2, "g2", 3, "accept")
        verdict("host", "host", "g3", 1, "g2", 1, "g3", 1, "accept")
    end)

    H.test("GUT #1448 readiness retries lost traffic to a hard cap and re-handshakes", function()
        local pings, sends, sent_sequences = 0, 0, {}
        local state = assert(Policy.new_pull("generation", 1, 0))
        local function ping() pings = pings + 1 end
        local function send(_, generation, sequence)
            sends = sends + 1
            sent_sequences[#sent_sequences + 1] = generation .. ":" .. sequence
            return true
        end
        local times = { 0, 0.4, 1.15, 1.55, 2.30, 2.70, 3.45, 3.85 }
        for _, now in ipairs(times) do
            Policy.step_pull(state, now, "host-peer", ping, send)
        end
        H.equal(pings, Policy.MAX_RETRIES)
        H.equal(sends, Policy.MAX_RETRIES)
        for _, identity in ipairs(sent_sequences) do
            H.equal(identity, "generation:1",
                "lost request/response retries must keep one idempotent identity")
        end
        H.truthy(state.terminal)
        H.equal(state.reason, "retry-cap")
        Policy.step_pull(state, 99, "host-peer", ping, send)
        H.equal(sends, Policy.MAX_RETRIES,
            "a no-GUT peer must not receive unbounded traffic")

        local missing, missing_pings, missing_sends =
            assert(Policy.new_pull("generation", 2, 0)), 0, 0
        for _, now in ipairs({ 0, 0.75, 1.5, 2.25 }) do
            Policy.step_pull(missing, now, nil,
                function() missing_pings = missing_pings + 1 end,
                function() missing_sends = missing_sends + 1 end)
        end
        H.truthy(missing.terminal)
        H.equal(missing.reason, "missing-host")
        H.equal(missing_pings, Policy.MAX_RETRIES)
        H.equal(missing_sends, 0)

        local recovered = assert(Policy.new_pull("generation", 3, 5))
        local recovery_sends = 0
        local function recovery_send()
            recovery_sends = recovery_sends + 1
            return true
        end
        Policy.step_pull(recovered, 5, "host-peer", ping, recovery_send)
        Policy.step_pull(recovered, 5.4, "host-peer", ping, recovery_send)
        -- The first request or response is lost; the same sequence is retried.
        Policy.step_pull(recovered, 6.2, "host-peer", ping, recovery_send)
        Policy.step_pull(recovered, 6.61, "host-peer", ping, recovery_send)
        H.equal(recovery_sends, 2)
        local recovered_ok = Policy.acknowledge_pull(recovered, "generation", 3)
        H.equal(recovered_ok, true)
        H.truthy(recovered.complete)

        local rehandshake = assert(Policy.new_pull("generation", 4, 10))
        Policy.step_pull(rehandshake, 10, "host-peer", ping, send)
        Policy.step_pull(rehandshake, 10.4, "host-peer", ping, send)
        local accepted, reason = Policy.acknowledge_pull(
            rehandshake, "generation", 4)
        H.equal(accepted, true)
        H.equal(reason, "accepted")
        accepted, reason = Policy.acknowledge_pull(
            rehandshake, "generation", 4)
        H.equal(accepted, true)
        H.equal(reason, "duplicate")
    end)

    H.test("GUT #1448 host sessions preserve replay identity and bound fresh work", function()
        local malformed, malformed_reason = Policy.plan_host_request({},
            "generation-a", 1, 0, 1)
        H.equal(malformed, nil)
        H.equal(malformed_reason, "session-shape")
        local state = Policy.new_host_session()
        local response1 = { chunks = { "one" }, payload_size = 3 }
        local plan = assert(Policy.plan_host_request(state, "generation-a", 1,
            0, 1))
        H.equal(plan.kind, "build")
        H.truthy(Policy.reserve_host_build(state, plan, 0))
        H.truthy(Policy.commit_host_response(state, plan, response1, 0))
        H.truthy(Policy.record_host_send(state, 0))

        local rejected, reason = Policy.plan_host_request(state,
            "generation-a", 1, 0, 1)
        H.equal(rejected, nil)
        H.equal(reason, "rate-send")
        local replay = assert(Policy.plan_host_request(state,
            "generation-a", 1, Policy.RESPONSE_SEND_FLOOR, 1))
        H.equal(replay.kind, "replay")
        H.equal(replay.response, response1,
            "an exact retry must retain the immutable response table")
        Policy.record_host_send(state, Policy.RESPONSE_SEND_FLOOR)

        rejected, reason = Policy.plan_host_request(state,
            "generation-a", 2, Policy.RESPONSE_SEND_FLOOR * 2, 1)
        H.equal(rejected, nil)
        H.equal(reason, "rate-build")
        plan = assert(Policy.plan_host_request(state, "generation-a", 2,
            Policy.FRESH_BUILD_FLOOR, 1))
        H.equal(plan.kind, "build")
        local response2 = { chunks = { "two" }, payload_size = 3 }
        Policy.reserve_host_build(state, plan, Policy.FRESH_BUILD_FLOOR)
        Policy.commit_host_response(state, plan, response2,
            Policy.FRESH_BUILD_FLOOR)
        Policy.record_host_send(state, Policy.FRESH_BUILD_FLOOR)

        rejected, reason = Policy.plan_host_request(state,
            "generation-a", 4,
            Policy.FRESH_BUILD_FLOOR + Policy.RESPONSE_SEND_FLOOR, 1)
        H.equal(rejected, nil)
        H.equal(reason, "sequence-gap")

        -- One real roster epoch may bypass the two-second extraction floor,
        -- but never the response-send floor.
        plan = assert(Policy.plan_host_request(state, "generation-a", 3,
            Policy.FRESH_BUILD_FLOOR + Policy.RESPONSE_SEND_FLOOR, 2))
        H.equal(plan.kind, "build")
        H.equal(plan.roster_bypass, true)
        Policy.reserve_host_build(state, plan,
            Policy.FRESH_BUILD_FLOOR + Policy.RESPONSE_SEND_FLOOR)
        Policy.commit_host_response(state, plan,
            { chunks = { "three" }, payload_size = 5 },
            Policy.FRESH_BUILD_FLOOR + Policy.RESPONSE_SEND_FLOOR)
        Policy.record_host_send(state,
            Policy.FRESH_BUILD_FLOOR + Policy.RESPONSE_SEND_FLOOR)

        local new_at = Policy.FRESH_BUILD_FLOOR * 2
            + Policy.RESPONSE_SEND_FLOOR
        plan = assert(Policy.plan_host_request(state, "generation-b", 1,
            new_at, 2))
        Policy.reserve_host_build(state, plan, new_at)
        Policy.commit_host_response(state, plan,
            { chunks = { "new" }, payload_size = 3 }, new_at)
        Policy.record_host_send(state, new_at)
        rejected, reason = Policy.plan_host_request(state, "generation-a", 1,
            new_at + Policy.RESPONSE_SEND_FLOOR, 2)
        H.equal(rejected, nil)
        H.equal(reason, "retired-generation")
        rejected, reason = Policy.plan_host_request(state, "generation-c", 2,
            new_at + Policy.RESPONSE_SEND_FLOOR, 2)
        H.equal(rejected, nil)
        H.equal(reason, "new-generation-sequence")
    end)

    H.test("GUT #1448 roster fingerprints include bots and ignore table order", function()
        local a = {
            human = player("human:1", "Human", 1),
            bot = player("bot:1", "Bot", 0),
        }
        local b = {
            [9] = player("bot:1", "Bot", 0),
            [2] = player("human:1", "Human", 1),
        }
        local first, _, first_count = Policy.roster_fingerprint(a)
        local second, _, second_count = Policy.roster_fingerprint(b)
        H.equal(first, second)
        H.equal(first_count, 2)
        H.equal(second_count, 2)
        b[9] = player("replacement-bot:1", "Replacement", 0)
        local changed = assert(Policy.roster_fingerprint(b))
        H.truthy(changed ~= first,
            "a bot replacement must advance the same bounded roster axis")
    end)

    H.test("GUT #1448 replaces only matching boss cells and preserves native fallback", function()
        local players = {
            ["peer-a:1"] = player("peer-a:1", "Alpha", 12),
            ["peer-b:1"] = player("peer-b:1", "Bravo", 5),
        }
        local topics = {
            {
                name = Policy.TOPIC,
                display_text = "scoreboard_topic_damage_dealt_bosses",
                stat_type = Policy.TOPIC,
            },
        }
        local fallback = ScorePolicy.build_native_model(players, topics, {
            sort_topic = "player_name",
        })
        H.equal(fallback.players[1].scores[Policy.TOPIC], 12)
        H.equal(fallback.players[2].scores[Policy.TOPIC], 5)

        local options = {
            sort_topic = "player_name",
            boss_scores = { ["peer-a:1"] = 90 },
        }
        local tab = ScorePolicy.build_native_model(players, topics, options)
        local finish = ScorePolicy.build_native_model(players, topics, options)
        H.equal(tab.players[1].scores[Policy.TOPIC], 90,
            "late-join partial native subtotal must be replaced")
        H.equal(tab.players[2].scores[Policy.TOPIC], 5,
            "a player without a compatible host row keeps native fallback")
        H.equal(tab.fingerprint, finish.fingerprint,
            "held-Tab and end-screen models must agree")

        local no_double_add = ScorePolicy.build_native_model(players, topics, {
            sort_topic = "player_name",
            boss_scores = { ["peer-a:1"] = 12 },
        })
        H.equal(no_double_add.players[1].scores[Policy.TOPIC], 12,
            "#437's restored host value must replace exactly once, never add")

        local native_wins = ScorePolicy.build_native_model(players, topics, {
            sort_topic = "player_name",
            boss_scores = { ["peer-a:1"] = 6 },
            boss_score_mode = "max",
        })
        H.equal(native_wins.players[1].scores[Policy.TOPIC], 12,
            "a stale sidecar must not lower the newer native final row")
        local sidecar_wins = ScorePolicy.build_native_model(players, topics, {
            sort_topic = "player_name",
            boss_scores = { ["peer-a:1"] = 91 },
            boss_score_mode = "max",
        })
        H.equal(sidecar_wins.players[1].scores[Policy.TOPIC], 91,
            "a newer host sidecar must repair a partial native final row")
        local invalid_sidecar = ScorePolicy.build_native_model(players, topics, {
            sort_topic = "player_name",
            boss_scores = { ["peer-a:1"] = 0 / 0 },
            boss_score_mode = "max",
        })
        H.equal(invalid_sidecar.players[1].scores[Policy.TOPIC], 12)
    end)

    local function simple_codec()
        local function encode(snapshot)
            local topic = snapshot.topics[1]
            local parts = { topic.name }
            for _, row in ipairs(topic.values) do
                parts[#parts + 1] = row.player_id .. "=" .. tostring(row.value)
            end
            return table.concat(parts, "|")
        end
        local function decode(payload)
            local parts = {}
            for part in payload:gmatch("[^|]+") do parts[#parts + 1] = part end
            local snapshot = { topics = { { name = parts[1], values = {} } } }
            for i = 2, #parts do
                local player_id, value = parts[i]:match("^([^=]+)=(.+)$")
                snapshot.topics[1].values[#snapshot.topics[1].values + 1] = {
                    player_id = player_id,
                    value = tonumber(value),
                }
            end
            return snapshot
        end
        return { encode = encode, decode = decode }
    end

    H.test("GUT #1448 real adapter rejects forged responses and resets mission host peer state", function()
        local previous = {}
        local global_names = {
            "get_mod", "Managers", "ScoreboardHelper", "cjson", "printf",
            "Application",
        }
        for _, name in ipairs(global_names) do previous[name] = rawget(_G, name) end

        local state = {
            host = "host-peer",
            logs = {},
            sends = {},
            pings = 0,
            joins = 0,
            group_reads = 0,
            players = {},
        }
        local long_ids = {
            "peer-a:" .. string.rep("a", 57),
            "peer-b:" .. string.rep("b", 57),
            "peer-c:" .. string.rep("c", 57),
            "peer-d:" .. string.rep("d", 57),
        }
        for i, stats_id in ipairs(long_ids) do
            H.equal(#stats_id, Policy.MAX_PLAYER_ID_BYTES)
            state.players[stats_id] = player(stats_id, "Peer " .. i, i)
        end
        local fake_mod = { settings = { gut_scoreboard_live_native = false } }
        function fake_mod:dofile(path)
            return assert(loadfile(mod_root .. path .. ".lua"))()
        end
        function fake_mod:get(setting_id) return self.settings[setting_id] end
        function fake_mod:network_register(channel, callback)
            state.channel, state.receiver = channel, callback
        end
        function fake_mod:network_send(...)
            local channel, target, schema, kind, generation, sequence, part,
                total, payload_size, chunk = ...
            state.sends[#state.sends + 1] = {
                channel = channel, target = target, schema = schema, kind = kind,
                generation = generation, sequence = sequence, part = part,
                total = total, payload_size = payload_size, chunk = chunk,
                argc = select("#", ...),
            }
        end
        function fake_mod.on_user_joined()
            state.joins = state.joins + 1
        end

        rawset(_G, "get_mod", function(name)
            if name == "gut_dev" then return fake_mod end
            if name == "VMF" then
                return { ping_vmf_users = function() state.pings = state.pings + 1 end }
            end
        end)
        rawset(_G, "Managers", {
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
        })
        rawset(_G, "ScoreboardHelper", {
            get_grouped_topic_statistics = function()
                state.group_reads = state.group_reads + 1
                return state.players
            end,
        })
        rawset(_G, "cjson", simple_codec())
        rawset(_G, "printf", function(fmt, ...)
            state.logs[#state.logs + 1] = string.format(fmt, ...)
        end)
        rawset(_G, "Application", nil)

        local ok, failure = pcall(function()
            local api = assert(loadfile(runtime_path))()
            H.equal(state.channel, Policy.CHANNEL)
            H.equal(api.rt_checks[1].name,
                "issue1448_host_boss_damage_snapshot_sync")
            H.equal(api.rt_checks[1].fn(), nil,
                "named runtime check must execute the real validator/model path")
            fake_mod.on_game_state_changed("enter", "StateIngame")
            for _ = 1, 6 do fake_mod.update(Policy.ROSTER_POLL_DELAY) end
            H.equal(state.group_reads, 0,
                "a disabled client must not poll grouped scoreboard data")
            H.equal(#state.sends, 0,
                "a disabled client must not start readiness traffic")

            -- Arm sequence one, disable before the handshake delay can emit,
            -- then re-enable. The new pull must retire the unsent identity and
            -- begin a fresh generation at sequence one, which a fresh host
            -- session can accept.
            fake_mod.settings.gut_scoreboard_live_native = true
            fake_mod.on_setting_changed("gut_scoreboard_live_native")
            fake_mod.update(0)
            H.equal(#state.sends, 0)
            fake_mod.settings.gut_scoreboard_live_native = false
            fake_mod.on_setting_changed("gut_scoreboard_live_native")
            fake_mod.settings.gut_scoreboard_live_native = true
            fake_mod.on_setting_changed("gut_scoreboard_live_native")
            fake_mod.update(0)
            fake_mod.update(Policy.HANDSHAKE_DELAY)
            local request = state.sends[#state.sends]
            H.equal(request.argc, 10,
                "installed sender must use the exact ten-field VMF call")
            H.equal(request.channel, Policy.CHANNEL)
            H.equal(request.schema, Policy.SCHEMA,
                "schema must be the first user payload field")
            H.equal(request.kind, Policy.REQUEST)
            H.equal(request.target, "host-peer")
            H.truthy(Policy.valid_generation(request.generation))
            H.truthy(request.generation:match("^g1%-2%-") ~= nil,
                "re-enable must allocate a fresh second mission generation")
            H.equal(request.sequence, 1)
            local fresh_host = Policy.new_host_session()
            local fresh_plan = assert(Policy.plan_host_request(fresh_host,
                request.generation, request.sequence, 0, 0))
            H.equal(fresh_plan.kind, "build",
                "a fresh host session must accept the re-enabled request")
            H.equal(request.part, 0)
            H.equal(request.total, 0)
            H.equal(request.payload_size, 0)
            H.equal(request.chunk, "")
            H.truthy(assert(Policy.packed_message_bytes(
                request.schema, request.kind, request.generation,
                request.sequence, request.part, request.total,
                request.payload_size, request.chunk)) <= Policy.MAX_PACKED_BYTES)

            local payload = simple_codec().encode(valid_snapshot({
                { long_ids[1], 910000000 },
                { long_ids[2], 810000000 },
                { long_ids[3], 710000000 },
                { long_ids[4], 610000000 },
            }))
            local chunks = assert(Policy.chunk_payload(payload))
            H.equal(#chunks, 3,
                "four realistic bounded stats_id rows must cross a wire chunk")
            H.truthy(#payload <= Policy.MAX_PAYLOAD_BYTES)
            for _, chunk in ipairs(chunks) do
                H.truthy(#chunk <= Policy.CHUNK_BYTES)
                local wire_bytes = assert(Policy.packed_message_bytes(
                    Policy.SCHEMA, Policy.SNAPSHOT, request.generation,
                    request.sequence, _, #chunks, #payload, chunk))
                H.truthy(wire_bytes <= Policy.MAX_PACKED_BYTES,
                    "the complete VMF-packed argument array must stay below 400")
            end
            state.receiver("forged-peer", Policy.SCHEMA, Policy.SNAPSHOT,
                request.generation, request.sequence, 1, #chunks, #payload, chunks[1])
            H.equal(api.current_scores(), nil)

            -- Exercise the callback installed by network_register, rather than
            -- only the pure planner: a missing prefix cannot leak a partial
            -- snapshot, exact duplicates are no-ops, and a same-index tamper
            -- clears the assembly atomically.
            state.receiver("host-peer", Policy.SCHEMA, Policy.SNAPSHOT,
                request.generation, request.sequence, 2, #chunks, #payload, chunks[2])
            H.equal(api.current_scores(), nil)
            state.receiver("host-peer", Policy.SCHEMA, Policy.SNAPSHOT,
                request.generation, request.sequence, 2, #chunks, #payload, chunks[2])
            H.equal(api.current_scores(), nil)
            local tampered = chunks[2]:sub(1, #chunks[2] - 1) .. "x"
            state.receiver("host-peer", Policy.SCHEMA, Policy.SNAPSHOT,
                request.generation, request.sequence, 2, #chunks, #payload, tampered)
            H.equal(api.current_scores(), nil)

            -- Reordered clean chunks form one complete snapshot only after all
            -- parts arrive following the rejected assembly.
            state.receiver("host-peer", Policy.SCHEMA, Policy.SNAPSHOT,
                request.generation, request.sequence, 2, #chunks, #payload, chunks[2])
            H.equal(api.current_scores(), nil)
            state.receiver("host-peer", Policy.SCHEMA, Policy.SNAPSHOT,
                request.generation, request.sequence, 3, #chunks, #payload, chunks[3])
            H.equal(api.current_scores(), nil)
            state.receiver("host-peer", Policy.SCHEMA, Policy.SNAPSHOT,
                request.generation, request.sequence, 1, #chunks, #payload, chunks[1])
            H.equal(api.current_scores()[long_ids[1]], 910000000)
            H.equal(api.current_scores()[long_ids[4]], 610000000)

            -- VMF reports a host-owned bot removal through the host peer before
            -- vanilla has changed the physical peer. The installed callback may
            -- schedule a roster read, but it must not blank accepted authority.
            fake_mod.on_user_left({
                network_id = function() return "host-peer" end,
            })
            H.equal(api.current_scores()[long_ids[1]], 910000000,
                "an early host-bot leave callback must retain the accepted row")

            -- A bot/no-GUT roster replacement is discovered from stable stats
            -- rows, not VMF discovery callbacks. Rotate the request generation,
            -- reject old chunks, and keep the last accepted display until the
            -- replacement snapshot is complete.
            local prior_generation = request.generation
            local prior_chunk = chunks[1]
            state.players[long_ids[4]] = nil
            local replacement_id = "bot-replacement:1"
            state.players[replacement_id] = player(replacement_id,
                "Replacement Bot", 4)
            fake_mod.update(Policy.ROSTER_POLL_DELAY)
            H.equal(api.current_scores()[long_ids[1]], 910000000,
                "roster refresh must not blank an accepted display")
            fake_mod.update(Policy.HANDSHAKE_DELAY)
            request = state.sends[#state.sends]
            H.truthy(request.generation ~= prior_generation)
            H.equal(request.sequence, 1)
            state.receiver("host-peer", Policy.SCHEMA, Policy.SNAPSHOT,
                prior_generation, 1, 1, 1, #prior_chunk, prior_chunk)
            H.equal(api.current_scores()[long_ids[1]], 910000000)

            payload = simple_codec().encode(valid_snapshot({
                { long_ids[1], 91 },
                { long_ids[2], 81 },
                { long_ids[3], 71 },
                { replacement_id, 61 },
            }))
            chunks = assert(Policy.chunk_payload(payload))
            for part, chunk in ipairs(chunks) do
                state.receiver("host-peer", Policy.SCHEMA, Policy.SNAPSHOT,
                    request.generation, request.sequence, part, #chunks,
                    #payload, chunk)
            end
            H.equal(api.current_scores()[replacement_id], 61)
            H.equal(api.current_scores()[long_ids[4]], nil)

            -- An idempotent duplicate, stale generation, and future sequence
            -- cannot replace the accepted row.
            state.receiver("host-peer", Policy.SCHEMA, Policy.SNAPSHOT,
                request.generation, request.sequence, 1, #chunks, #payload, chunks[1])
            state.receiver("host-peer", Policy.SCHEMA, Policy.SNAPSHOT,
                "old-generation", request.sequence, 1, #chunks, #payload, chunks[1])
            state.receiver("host-peer", Policy.SCHEMA, Policy.SNAPSHOT,
                request.generation, request.sequence + 1,
                1, #chunks, #payload, chunks[1])
            H.equal(api.current_scores()[long_ids[1]], 91)

            -- Let the installed readiness owner refresh into a no-response
            -- peer and hit the hard four-send cap. VMF pongs arrive before,
            -- during, and after those attempts; none may rearm the terminal
            -- pull or rotate its generation.
            fake_mod.update(Policy.REFRESH_DELAY)
            fake_mod.update(0) -- retire the acknowledged pull and arm refresh
            local refresh_generation = request.generation
            local before_retry_sends = #state.sends
            local host_player = {
                network_id = function() return "host-peer" end,
            }
            for _ = 1, Policy.MAX_RETRIES * 2 do
                fake_mod.on_user_joined(host_player)
                fake_mod.update(Policy.RETRY_DELAY)
                fake_mod.on_user_joined(host_player)
            end
            local capped_sends = #state.sends
            H.equal(capped_sends - before_retry_sends, Policy.MAX_RETRIES,
                "installed mixed/no-GUT path must emit exactly four attempts")
            local terminal_request = state.sends[capped_sends]
            H.equal(terminal_request.generation, refresh_generation)
            for _ = 1, Policy.MAX_RETRIES * 2 do
                fake_mod.on_user_joined(host_player)
                fake_mod.update(Policy.RETRY_DELAY)
            end
            H.equal(#state.sends, capped_sends,
                "delayed VMF pongs must not rearm a terminal pull")
            H.truthy(state.joins >= Policy.MAX_RETRIES * 4,
                "the fixture must exercise repeated installed pong callbacks")

            state.host = "migrated-host"
            fake_mod.update(0.01)
            H.equal(api.current_scores(), nil,
                "host migration must retire the old host's snapshot")

            state.host = "host-peer"
            fake_mod.on_game_state_changed("exit", "StateIngame")
            H.equal(api.current_scores(), nil)
            fake_mod.on_game_state_changed("enter", "StateIngame")
            fake_mod.on_user_left({
                network_id = function() return "host-peer" end,
            })
            H.equal(api.current_scores(), nil,
                "an early leave callback without accepted data keeps fallback")

            local saw_non_host, saw_generation, saw_order, saw_conflict =
                false, false, false, false
            for _, line in ipairs(state.logs) do
                saw_non_host = saw_non_host or line:find("reason=non-host", 1, true) ~= nil
                saw_generation = saw_generation
                    or line:find("reason=stale-generation", 1, true) ~= nil
                saw_order = saw_order
                    or line:find("reason=out-of-order-sequence", 1, true) ~= nil
                saw_conflict = saw_conflict
                    or line:find("reason=conflict", 1, true) ~= nil
            end
            H.truthy(saw_non_host)
            H.truthy(saw_generation)
            H.truthy(saw_order)
            H.truthy(saw_conflict)
            H.truthy(#state.logs <= 24)
        end)

        for _, name in ipairs(global_names) do rawset(_G, name, previous[name]) end
        if not ok then error(failure, 0) end
    end)

    H.test("GUT #1448 host replays one cached response per duplicate request", function()
        local previous = {}
        local global_names = {
            "get_mod", "Managers", "ScoreboardHelper", "cjson", "printf",
            "Application",
        }
        for _, name in ipairs(global_names) do previous[name] = rawget(_G, name) end

        local state = {
            logs = {}, sends = {}, encodes = 0, group_reads = 0, joins = 0,
            players = {
                ["host-peer:1"] = player("host-peer:1", "Host", 41),
                ["client-peer:1"] = player("client-peer:1", "Client", 17),
            },
        }
        local fake_mod = { settings = { gut_scoreboard_live_native = false } }
        function fake_mod:dofile(path)
            return assert(loadfile(mod_root .. path .. ".lua"))()
        end
        function fake_mod:get(setting_id) return self.settings[setting_id] end
        function fake_mod:network_register(channel, callback)
            state.channel, state.receiver = channel, callback
        end
        function fake_mod:network_send(...)
            local sent = { ... }
            sent.argc = select("#", ...)
            state.sends[#state.sends + 1] = sent
        end
        function fake_mod.on_user_joined()
            state.joins = state.joins + 1
        end
        local client_player = {
            network_id = function() return "client-peer" end,
        }
        rawset(_G, "get_mod", function(name)
            return name == "gut_dev" and fake_mod or nil
        end)
        rawset(_G, "Managers", {
            mechanism = {
                current_mechanism_name = function() return "adventure" end,
                server_peer_id = function() return "host-peer" end,
            },
            player = {
                is_server = true,
                statistics_db = function() return {} end,
                human_players = function() return { client = client_player } end,
            },
            state = { network = { profile_synchronizer = {} } },
        })
        rawset(_G, "ScoreboardHelper", {
            get_grouped_topic_statistics = function()
                state.group_reads = state.group_reads + 1
                return state.players
            end,
        })
        local codec = simple_codec()
        local encode = codec.encode
        codec.encode = function(value)
            state.encodes = state.encodes + 1
            return encode(value)
        end
        rawset(_G, "cjson", codec)
        rawset(_G, "printf", function(fmt, ...)
            state.logs[#state.logs + 1] = string.format(fmt, ...)
        end)
        rawset(_G, "Application", nil)

        local ok, failure = pcall(function()
            assert(loadfile(runtime_path))()
            fake_mod.on_game_state_changed("enter", "StateIngame")
            for _ = 1, 8 do fake_mod.update(Policy.ROSTER_POLL_DELAY) end
            H.equal(state.group_reads, 0,
                "a default-off host with no requester must not poll grouped scores")
            state.receiver("forged-peer", Policy.SCHEMA, Policy.REQUEST,
                "mission-a", 1, 0, 0, 0, "")
            H.equal(#state.sends, 0)
            H.equal(state.group_reads, 0,
                "an unauthenticated request must not activate host polling")
            state.receiver("client-peer", Policy.SCHEMA, Policy.REQUEST,
                "mission-a", 2, 0, 0, 0, "")
            H.equal(state.group_reads, 0,
                "an impossible first sequence must not activate host polling")

            state.receiver("client-peer", Policy.SCHEMA, Policy.REQUEST,
                "mission-a", 1, 0, 0, 0, "")
            local first_count = #state.sends
            H.truthy(first_count > 0)
            H.equal(state.encodes, 1)
            local first_payload = {}
            for i = 1, first_count do
                local sent = state.sends[i]
                H.equal(sent.argc, 10,
                    "installed host sender must keep the exact wire signature")
                H.equal(sent[1], Policy.CHANNEL)
                H.equal(sent[2], "client-peer")
                H.equal(sent[3], Policy.SCHEMA)
                H.equal(sent[4], Policy.SNAPSHOT)
                H.equal(sent[5], "mission-a")
                H.equal(sent[6], 1)
                H.equal(sent[7], i)
                H.equal(sent[8], first_count)
                H.truthy(sent[9] <= Policy.MAX_PAYLOAD_BYTES)
                H.truthy(#sent[10] <= Policy.CHUNK_BYTES)
                H.truthy(assert(Policy.packed_message_bytes(
                    sent[3], sent[4], sent[5], sent[6], sent[7], sent[8],
                    sent[9], sent[10])) <= Policy.MAX_PACKED_BYTES)
                first_payload[i] = sent[10]
            end

            -- VMF callbacks fire before vanilla physical removal and for
            -- repeated discovery joins. Neither callback may discard the
            -- immutable response for this exact request identity.
            state.players["host-peer:1"].group_scores.offense[2].score = 99
            fake_mod.on_user_left(client_player)
            fake_mod.on_user_joined(client_player)
            fake_mod.update(Policy.RESPONSE_SEND_FLOOR)
            state.receiver("client-peer", Policy.SCHEMA, Policy.REQUEST,
                "mission-a", 1, 0, 0, 0, "")
            H.equal(#state.sends, first_count * 2)
            H.equal(state.encodes, 1,
                "early leave/discovery callbacks plus duplicate must not rebuild")
            H.equal(state.joins, 1)
            for i = 1, first_count do
                H.equal(state.sends[first_count + i][10], first_payload[i],
                    "duplicate request must replay cached bytes")
            end

            -- Same-tick authenticated floods cannot consume fresh extraction
            -- or response bandwidth, regardless of the supplied identity.
            local after_duplicate = #state.sends
            for i = 1, 100 do
                state.receiver("client-peer", Policy.SCHEMA, Policy.REQUEST,
                    "mission-a", 1, 0, 0, 0, "")
                state.receiver("client-peer", Policy.SCHEMA, Policy.REQUEST,
                    "mission-a", 2 + i, 0, 0, 0, "")
                state.receiver("client-peer", Policy.SCHEMA, Policy.REQUEST,
                    "flood-" .. i, 1, 0, 0, 0, "")
            end
            H.equal(#state.sends, after_duplicate)
            H.equal(state.encodes, 1)

            fake_mod.update(Policy.RESPONSE_SEND_FLOOR)
            state.receiver("client-peer", Policy.SCHEMA, Policy.REQUEST,
                "mission-a", 1, 0, 0, 0, "")
            local after_replay = #state.sends
            H.equal(after_replay, after_duplicate + first_count)
            H.equal(state.encodes, 1)

            -- A fresh contiguous sequence waits for both floors.
            state.receiver("client-peer", Policy.SCHEMA, Policy.REQUEST,
                "mission-a", 2, 0, 0, 0, "")
            H.equal(#state.sends, after_replay)
            fake_mod.update(Policy.RESPONSE_SEND_FLOOR)
            state.receiver("client-peer", Policy.SCHEMA, Policy.REQUEST,
                "mission-a", 2, 0, 0, 0, "")
            local after_new = #state.sends
            H.truthy(after_new > after_replay)
            H.equal(state.encodes, 2)

            -- A client reload may rotate to sequence one, but it is subject to
            -- the same extraction floor and retires the old generation.
            state.receiver("client-peer", Policy.SCHEMA, Policy.REQUEST,
                "mission-b", 1, 0, 0, 0, "")
            H.equal(#state.sends, after_new)
            fake_mod.update(Policy.RESPONSE_SEND_FLOOR)
            state.receiver("client-peer", Policy.SCHEMA, Policy.REQUEST,
                "mission-b", 1, 0, 0, 0, "")
            H.equal(#state.sends, after_new)
            fake_mod.update(Policy.FRESH_BUILD_FLOOR - Policy.RESPONSE_SEND_FLOOR)
            state.receiver("client-peer", Policy.SCHEMA, Policy.REQUEST,
                "mission-b", 1, 0, 0, 0, "")
            local after_generation = #state.sends
            H.truthy(after_generation > after_new)
            H.equal(state.encodes, 3)
            fake_mod.update(Policy.RESPONSE_SEND_FLOOR)
            state.receiver("client-peer", Policy.SCHEMA, Policy.REQUEST,
                "mission-a", 1, 0, 0, 0, "")
            state.receiver("client-peer", Policy.SCHEMA, Policy.REQUEST,
                "future-generation", 3, 0, 0, 0, "")
            H.equal(#state.sends, after_generation)

            -- A real human/bot scoreboard-row change permits exactly one
            -- early fresh build under a new roster epoch.
            state.players["bot-peer:1"] = player("bot-peer:1", "Bot", 0)
            fake_mod.update(Policy.ROSTER_POLL_DELAY)
            state.receiver("client-peer", Policy.SCHEMA, Policy.REQUEST,
                "mission-b", 2, 0, 0, 0, "")
            local after_roster = #state.sends
            H.truthy(after_roster > after_generation)
            H.equal(state.encodes, 4)

            fake_mod.on_game_state_changed("exit", "StateIngame")
            fake_mod.on_game_state_changed("enter", "StateIngame")
            state.receiver("client-peer", Policy.SCHEMA, Policy.REQUEST,
                "mission-c", 1, 0, 0, 0, "")
            H.truthy(#state.sends > after_roster,
                "mission reset must retire the prior peer generation cache")
        end)

        for _, name in ipairs(global_names) do rawset(_G, name, previous[name]) end
        if not ok then error(failure, 0) end
    end)

    H.test("GUT #1448 source owns one mod channel and no vanilla wire or damage hook", function()
        local runtime = read(runtime_path)
        local policy = read(policy_path)
        local live = read(repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_scoreboard_live.lua")
        local entry = read(repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/gui_tweaker_dev.lua")
        local stable_entry = read(repo_root
            .. "/gui_tweaker/scripts/mods/gui_tweaker/gui_tweaker.lua")
        local stable_live = read(repo_root
            .. "/gui_tweaker/scripts/mods/gui_tweaker/_gut_scoreboard_live.lua")
        local retention = read(repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_scoreboard_retention.lua")
        local revive = read(repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_revive_scoreboard.lua")

        H.equal(count_plain(runtime, "mod:network_register("), 1)
        H.equal(count_plain(runtime, "mod:hook("), 0)
        H.equal(count_plain(runtime, "mod:hook_safe("), 0)
        H.truthy(policy:find('M.CHANNEL = "gut_boss_damage_snapshot_v1"', 1, true) ~= nil)
        H.truthy(entry:find("local GUT_RPC_SCHEMA = 1", 1, true) ~= nil)
        H.truthy(entry:find("_gut_boss_damage_sync", 1, true) ~= nil)
        H.truthy(live:find("options.boss_scores = boss_scores", 1, true) ~= nil)
        H.truthy(live:find("end_boss_scores", 1, true) ~= nil)

        for _, source in ipairs({ runtime, policy }) do
            local executable = source:gsub("%-%-[^\n]*", "")
            H.equal(executable:find("NetworkLookup", 1, true), nil)
            H.equal(executable:find("StatisticsDefinitions", 1, true), nil)
            H.equal(executable:find("DamageUtils", 1, true), nil)
            H.equal(executable:find("register_damage", 1, true), nil)
            H.equal(executable:find("rpc_players_session_score", 1, true), nil)
            H.equal(executable:find("rpc_sync_statistics", 1, true), nil)
        end
        H.equal(stable_entry:find("_gut_boss_damage_sync", 1, true), nil)
        H.equal(stable_live:find("boss_scores", 1, true), nil)
        H.truthy(retention:find("issue437_adventure_scoreboard_retention", 1, true) ~= nil)
        H.truthy(revive:find("issue438_on_yer_feet_revive_credit", 1, true) ~= nil)
    end)
end
