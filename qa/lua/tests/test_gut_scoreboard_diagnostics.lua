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
        local page = Policy.build_native_page(players, topics, "damage_dealt", 4)
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
        local page = Policy.build_native_page(source, {
            { name = "damage_taken", display_text = "taken" },
        }, "damage_taken", 4)
        H.equal(page.players[1].name, "Alpha")
        H.equal(page.players[3].name, "Missing")
        page.players[1].scores.damage_taken = 999
        H.equal(source.b.group_scores.offense[1].score, 10)
    end)

    H.test("GUT #272 native topic model is unique and hard capped", function()
        local topics = {}
        for i = 1, 15 do
            topics[#topics + 1] = { name = "stat_" .. i, display_text = "label_" .. i }
        end
        topics[#topics + 1] = { name = "stat_1", display_text = "duplicate" }
        local page = Policy.build_native_page({}, topics, "player_name", 4)
        H.equal(#page.topics, Policy.MAX_NATIVE_TOPICS)
        H.equal(page.topics[1].display_text, "label_1")
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

    H.test("GUT #272 stable and dev scoreboard presenters stay semantically identical", function()
        local stable = read(repo_root
            .. "/gui_tweaker/scripts/mods/gui_tweaker/_gut_scoreboard_live.lua")
        local dev = read(repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_scoreboard_live.lua")
        dev = dev:gsub("gui_tweaker_dev", "gui_tweaker")
            :gsub('get_mod%("gut_dev"%)', 'get_mod("gut")')
        H.equal(stable, dev,
            "public and dev scoreboard behavior may differ only by stream identity")

        local stable_loc = assert(loadfile(repo_root
            .. "/gui_tweaker/scripts/mods/gui_tweaker/gui_tweaker_localization.lua"))()
        local dev_loc = assert(loadfile(repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/gui_tweaker_dev_localization.lua"))()
        for _, key in ipairs({ "gut_scoreboard_live_title", "gut_scoreboard_live_statistic" }) do
            H.equal(stable_loc[key].en, dev_loc[key].en,
                "scoreboard chrome localization drifted for " .. key)
        end
    end)
end
