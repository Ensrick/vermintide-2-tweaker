return function(H, repo_root)
    local policy_path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_scoreboard_policy.lua"
    local Policy = assert(loadfile(policy_path))()

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    H.test("GUT scoreboard inventory resolves scalar and composite topics", function()
        local topics = {
            { name = "kills", display_text = "kills_loc", stat_type = "kills_total" },
            { name = "boss", display_text = "boss_loc", stat_types = {
                { "damage_dealt_per_breed", "rat_ogre" },
            } },
        }
        local result = Policy.inspect_catalog(topics, {
            { group_name = "offense", stats = { "kills", "boss" } },
        })
        H.equal(result.topic_count, 2)
        H.equal(result.grouped_count, 2)
        H.equal(result.malformed_count, 0)
        H.equal(result.duplicate_count, 0)
        H.equal(result.unresolved_count, 0)
        H.equal(table.concat(result.names, ","), "boss,kills")
    end)

    H.test("GUT scoreboard inventory detects catalog drift", function()
        local result = Policy.inspect_catalog({
            { name = "kills", display_text = "a", stat_type = "kills_total" },
            { name = "kills", display_text = "b", stat_type = "kills_total" },
            { name = "broken", display_text = "c", stat_type = "x", stat_types = { { "y" } } },
        }, {
            { group_name = "offense", stats = { "kills", "missing" } },
        })
        H.equal(result.duplicate_count, 1)
        H.equal(result.unresolved_count, 1)
        H.equal(result.malformed_count, 1)
    end)

    H.test("GUT scoreboard snapshot audit is bounded and shape-safe", function()
        local result = Policy.inspect_snapshot({
            one = { group_scores = { offense = {
                { stat_name = "kills", score = 4 },
                { stat_name = "damage", score = "bad" },
            } } },
            two = {},
        })
        H.equal(result.player_count, 2)
        H.equal(result.score_count, 2)
        H.equal(result.malformed_players, 1)
        H.equal(result.nonnumeric_scores, 1)
    end)

    H.test("GUT scoreboard inventory exposes composite hot-join gaps", function()
        local topics = {
            { name = "kills", stat_type = "kills_total" },
            { name = "elites", stat_types = {
                { "kills_per_breed", "elite" },
            } },
            { name = "boss_damage", stat_types = {
                { "damage_dealt_per_breed", "boss" },
            } },
        }
        local coverage = Policy.inspect_hotjoin_coverage(topics, {
            kills_total = { sync_on_hot_join = true },
            kills_per_breed = { elite = { sync_on_hot_join = true } },
            damage_dealt_per_breed = { boss = { value = 0 } },
        })
        H.equal(table.concat(coverage.covered, ","), "elites,kills")
        H.equal(table.concat(coverage.gaps, ","), "boss_damage")
        H.equal(#coverage.unresolved, 0)
    end)

    H.test("GUT scoreboard retention collects exact deduplicated leaf paths", function()
        local paths = Policy.collect_stat_paths({
            { stat_type = "kills_total" },
            { stat_type = "kills_total" },
            { stat_types = {
                { "damage_dealt_per_breed", "rat_ogre" },
                { "damage_dealt_per_breed", "stormfiend" },
            } },
        }, 64)
        H.equal(#paths, 3)
        H.equal(table.concat(paths[1], "/"), "kills_total")
        H.equal(table.concat(paths[3], "/"), "damage_dealt_per_breed/stormfiend")
    end)

    H.test("GUT scoreboard retention snapshots numbers only and detaches paths", function()
        local source = { { "kills_total" }, { "bad" }, { "revives" } }
        local values = { kills_total = 9, bad = "not-a-score", revives = 2 }
        local records = Policy.capture_stat_values(source, function(path)
            return values[path[1]]
        end, 64)
        source[1][1] = "mutated"
        H.equal(#records, 2)
        H.equal(records[1].path[1], "kills_total")
        H.equal(records[1].value, 9)
    end)

    H.test("GUT scoreboard retention restores exact paths within cap", function()
        local writes = {}
        local count = Policy.restore_stat_values({
            { path = { "kills_total" }, value = 9 },
            { path = { "damage_dealt_per_breed", "rat_ogre" }, value = 123 },
            { path = { "bad" }, value = "skip" },
        }, function(path, value)
            writes[#writes + 1] = table.concat(path, "/") .. "=" .. value
        end, 2)
        H.equal(count, 2)
        H.equal(table.concat(writes, ","),
            "kills_total=9,damage_dealt_per_breed/rat_ogre=123")
    end)

    H.test("GUT #272 native page is deterministic and capped to four players", function()
        local topics = {
            { name = "damage_dealt", display_text = "damage" },
            { name = "damage_taken", display_text = "taken" },
        }
        local players = {}
        for i, name in ipairs({ "Echo", "Delta", "Charlie", "Bravo", "Alpha" }) do
            players["id" .. i] = { name = name, group_scores = { offense = {
                { stat_name = "damage_dealt", score = i * 10 },
                { stat_name = "damage_taken", score = 60 - i * 10 },
            } } }
        end
        local model = Policy.build_native_model(players, topics, {
            sort_topic = "damage_dealt",
            player_limit = 4,
            selected_page = 1,
        })
        local page = model.selected
        H.equal(#page.players, 4)
        H.equal(page.players[1].name, "Alpha")
        H.equal(page.players[4].name, "Delta")
        H.equal(page.topics[2].name, "damage_taken")
    end)

    H.test("GUT #272 native page preserves snapshot and damage-taken ordering", function()
        local source = {
            a = { name = "Zulu", group_scores = { offense = {
                { stat_name = "damage_taken", score = 30 },
            } } },
            b = { name = "Alpha", group_scores = { offense = {
                { stat_name = "damage_taken", score = 10 },
            } } },
            c = { name = "Missing", group_scores = { offense = {} } },
        }
        local model = Policy.build_native_model(source, {
            { name = "damage_taken", display_text = "taken" },
        }, {
            sort_topic = "damage_taken",
            player_limit = 4,
            selected_page = 1,
        })
        local page = model.selected
        H.equal(page.players[1].name, "Alpha")
        H.equal(page.players[3].name, "Missing")
        page.players[1].scores.damage_taken = 999
        H.equal(source.b.group_scores.offense[1].score, 10)
    end)

    H.test("GUT #272 native topic model is unique and paged without loss", function()
        local topics = {}
        for i = 1, 15 do
            topics[#topics + 1] = { name = "stat_" .. i, display_text = "label_" .. i }
        end
        topics[#topics + 1] = { name = "stat_1", display_text = "duplicate" }
        local model = Policy.build_native_model({}, topics, {
            sort_topic = "player_name",
            player_limit = 4,
            selected_page = 2,
        })
        H.equal(#model.topics, 15)
        H.equal(model.page_count, 2)
        H.equal(#model.pages[1].topics, Policy.ROWS_PER_PAGE)
        H.equal(#model.pages[2].topics, 4)
        H.equal(model.pages[1].topics[1].display_text, "label_1")
        H.equal(model.duplicate_count, 1)
    end)

    H.test("GUT #272 native pages own bounded draw seams and no transport", function()
        local live_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_scoreboard_live.lua"
        local live = read(live_path)
        local _, tab_hooks = live:gsub('mod:hook_safe%("IngamePlayerListUI", "_draw"', "")
        local _, end_hooks = live:gsub('mod:hook_safe%("EndViewStateScore", "draw"', "")
        H.equal(tab_hooks, 1)
        H.equal(end_hooks, 1)
        H.truthy(live:find("get_grouped_topic_statistics", 1, true) ~= nil)
        H.truthy(live:find("UTF8Utils", 1, true) ~= nil)
        H.truthy(live:find("is_root = true", 1, true) ~= nil)
        H.truthy(live:find('"player_" .. column .. "_row_" .. row', 1, true) ~= nil)
        H.equal(live:find('table.concat(labels, "\\n")', 1, true), nil)
        H.equal(live:find('table.concat(lines, "\\n")', 1, true), nil)
        H.equal(live:find("network_register", 1, true), nil)
        H.equal(live:find("rpc_", 1, true), nil)
    end)

    H.test("GUT #272 stable preserves the live baseline while dev owns the unverified renderer", function()
        local stable = read(repo_root
            .. "/gui_tweaker/scripts/mods/gui_tweaker/_gut_scoreboard_live.lua")
        local dev = read(repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_scoreboard_live.lua")

        -- Public stable is intentionally pinned to the last live 0.2.281
        -- implementation until #272's later renderer is user-verified. Do not let a
        -- dev/stable parity assertion silently promote that unverified source again.
        H.truthy(stable:find(
            'mod._GUT272_NATIVE_TAB_MARKER = "gut-272-native-helper-snapshot-bounded-four-by-eleven"',
            1, true) ~= nil, "stable presenter lost its last-live identity")
        H.truthy(stable:find('table.concat(labels, "\\n")', 1, true) ~= nil,
            "stable presenter no longer matches the last-live multiline layout")
        H.truthy(stable:find('table.concat(lines, "\\n")', 1, true) ~= nil,
            "stable presenter no longer matches the last-live player columns")
        H.equal(stable:find("is_root = true", 1, true), nil,
            "stable presenter acquired the unverified dev renderer root")
        H.equal(stable:find('"player_" .. column .. "_row_" .. row', 1, true), nil,
            "stable presenter acquired the unverified dev per-cell renderer")

        -- The newer renderer remains covered where it actually lives: dev only.
        H.truthy(dev:find("is_root = true", 1, true) ~= nil,
            "dev presenter lost its explicit root")
        H.truthy(dev:find(
            '"player_" .. column .. "_row_" .. row', 1, true) ~= nil,
            "dev presenter lost per-cell values")
        H.equal(dev:find('table.concat(labels, "\\n")', 1, true), nil,
            "dev presenter restored multiline labels")
        H.equal(dev:find('table.concat(lines, "\\n")', 1, true), nil,
            "dev presenter restored TSV rows")
        H.truthy(dev:find("type(external.is_enabled) == \"function\"", 1, true) ~= nil,
            "dev presenter lost enabled-aware external handoff")
        H.truthy(dev:find("enabled == false", 1, true) ~= nil,
            "dev presenter suppresses itself for a disabled external mod")
    end)
end
