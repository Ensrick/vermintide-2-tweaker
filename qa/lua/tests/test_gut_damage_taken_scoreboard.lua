return function(H, repo_root)
    local path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_damage_taken_scoreboard_policy.lua"
    local policy = dofile(path)
    local function read(relative)
        local file = assert(io.open(repo_root .. "/" .. relative, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    H.test("GUT #1151 gives Damage Taken credit to the lowest positive score", function()
        local rows = { offense = {
            { stat_name = "damage_taken", highscore = 0,
                player_scores = { alpha = 60, beta = 15, gamma = 42 } },
        } }
        local changed = policy.repair(rows)
        H.equal(rows.offense[1].highscore, 15)
        H.equal(#changed, 1)
        H.equal(changed[1].old, 0)
        H.equal(changed[1].new, 15)
        H.equal(changed[1].count, 3)
    end)

    H.test("GUT #1151 preserves ties, zeroes, and unrelated scoreboard rows", function()
        local rows = { offense = {
            { stat_name = "damage_taken", highscore = 9,
                player_scores = { 9, 9, 30 } },
            { stat_name = "kills_total", highscore = 99,
                player_scores = { 1, 99 } },
        } }
        H.equal(#policy.repair(rows), 0)
        H.equal(rows.offense[1].highscore, 9)
        H.equal(rows.offense[2].highscore, 99)

        rows.offense[1].player_scores = { 8, 0, 20 }
        policy.repair(rows)
        H.equal(rows.offense[1].highscore, 0)
    end)

    H.test("GUT #1151 policy fails inert on malformed partial score data", function()
        H.equal(#policy.repair(nil), 0)
        local rows = { bad = false, defense = {
            { stat_name = "damage_taken", highscore = 0, player_scores = { "x" } },
        } }
        H.equal(#policy.repair(rows), 0)
        H.equal(rows.defense[1].highscore, 0)
    end)

    H.test("GUT #1151 runtime owns the post-vanilla accumulation seam", function()
        local runtime = read(
            "gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_damage_taken_scoreboard.lua")
        local entry = read(
            "gui_tweaker_dev/scripts/mods/gui_tweaker_dev/gui_tweaker_dev.lua")
        H.truthy(runtime:find(
            'mod:hook_safe("EndViewStateScore", "_group_scores_by_player_and_topic"',
            1, true))
        H.truthy(runtime:find("Policy.repair(score_panel_scores)", 1, true))
        H.truthy(runtime:find("DIAGNOSTIC_CAP = 8", 1, true))
        H.truthy(runtime:find(
            'name = "issue1151_damage_taken_green_circle_minimum"', 1, true))
        H.truthy(entry:find(
            'scripts/mods/gui_tweaker_dev/_gut_damage_taken_scoreboard', 1, true))
        H.truthy(entry:find("_rt_register(check.name, check.fn)", 1, true))
    end)
end
