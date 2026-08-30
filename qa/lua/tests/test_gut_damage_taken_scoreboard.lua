return function(H, repo_root)
    local function read(relative)
        local file = assert(io.open(repo_root .. "/" .. relative, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local streams = {
        {
            label = "public",
            root = "gui_tweaker/scripts/mods/gui_tweaker",
            entry = "gui_tweaker.lua",
            mod_id = "gut",
        },
        {
            label = "Dev",
            root = "gui_tweaker_dev/scripts/mods/gui_tweaker_dev",
            entry = "gui_tweaker_dev.lua",
            mod_id = "gut_dev",
        },
    }

    local policies = {}
    for _, stream in ipairs(streams) do
        policies[stream.label] = dofile(repo_root .. "/" .. stream.root
            .. "/_gut_damage_taken_scoreboard_policy.lua")
    end

    for _, stream in ipairs(streams) do
        local current = stream
        local policy = policies[current.label]

        H.test("GUT #1151 " .. current.label
            .. " gives Damage Taken credit to the lowest positive score", function()
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

        H.test("GUT #1151 " .. current.label
            .. " preserves ties, zeroes, and unrelated scoreboard rows", function()
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

        H.test("GUT #1151 " .. current.label
            .. " fails inert on malformed partial score data", function()
            H.equal(#policy.repair(nil), 0)
            local rows = { bad = false, defense = {
                { stat_name = "damage_taken", highscore = 0,
                    player_scores = { "x" } },
            } }
            H.equal(#policy.repair(rows), 0)
            H.equal(rows.defense[1].highscore, 0)
        end)

        H.test("GUT #1151 " .. current.label
            .. " runtime owns the post-vanilla accumulation seam", function()
            local runtime = read(current.root
                .. "/_gut_damage_taken_scoreboard.lua")
            local entry = read(current.root .. "/" .. current.entry)
            H.truthy(runtime:find(
                'local mod = get_mod("' .. current.mod_id .. '")', 1, true))
            H.truthy(runtime:find(
                'mod:hook_safe("EndViewStateScore", "_group_scores_by_player_and_topic"',
                1, true))
            H.truthy(runtime:find("Policy.repair(score_panel_scores)", 1, true))
            H.truthy(runtime:find("DIAGNOSTIC_CAP = 8", 1, true))
            H.truthy(runtime:find(
                'name = "issue1151_damage_taken_green_circle_minimum"', 1, true))
            local module_root = current.root:match("(scripts/mods/.+)$")
            local marker = module_root .. "/_gut_damage_taken_scoreboard"
            local _, count = entry:gsub(marker, "")
            H.equal(count, 1)
            H.truthy(entry:find("_rt_register(check.name, check.fn)", 1, true))
        end)
    end

    H.test("GUT #1151 public policy is byte-identical to verified Dev", function()
        H.equal(read(streams[1].root
            .. "/_gut_damage_taken_scoreboard_policy.lua"),
            read(streams[2].root
                .. "/_gut_damage_taken_scoreboard_policy.lua"))
    end)

    H.test("GUT #1151 public runtime differs only by stream identity", function()
        local public_runtime = read(streams[1].root
            .. "/_gut_damage_taken_scoreboard.lua")
        local dev_runtime = read(streams[2].root
            .. "/_gut_damage_taken_scoreboard.lua")
        local normalized = dev_runtime:gsub("gui_tweaker_dev", "gui_tweaker")
            :gsub("gut_dev", "gut")
        H.equal(public_runtime, normalized)
    end)
end
