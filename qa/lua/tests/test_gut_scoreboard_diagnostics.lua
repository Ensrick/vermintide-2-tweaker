return function(H, repo_root)
    local path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_scoreboard_policy.lua"
    local Policy = assert(loadfile(path))()

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
end
