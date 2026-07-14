return function(H, repo_root)
    local policy_path = repo_root .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_ale_policy.lua"
    local Policy = assert(loadfile(policy_path))()

    local function member(fraction)
        return {
            defence_stacks = 3,
            attack_stacks = 3,
            defence_remaining_fraction = fraction,
            attack_remaining_fraction = fraction,
        }
    end

    H.test("gt smart ale requires every team member at full fresh stacks", function()
        H.equal(Policy.team_ready({ member(0.51), member(1) }, 3, 0.5), true)
        local team = { member(0.9), member(0.9) }
        team[2].defence_stacks = 2
        H.equal(Policy.team_ready(team, 3, 0.5), false)
        team[2].defence_stacks = 3
        team[2].attack_stacks = 2
        H.equal(Policy.team_ready(team, 3, 0.5), false)
    end)

    H.test("gt smart ale uses strict half-duration boundary and fails closed", function()
        H.equal(Policy.team_ready({ member(0.5) }, 3, 0.5), false)
        H.equal(Policy.team_ready({ member(0.50001) }, 3, 0.5), true)
        H.equal(Policy.team_ready({}, 3, 0.5), false)
        H.equal(Policy.team_ready(nil, 3, 0.5), false)
        local invalid = member(0.9)
        invalid.attack_remaining_fraction = nil
        H.equal(Policy.team_ready({ invalid }, 3, 0.5), false)
    end)

    H.test("gt smart ale stays in the consolidated bounded pickup hook", function()
        local runtime_path = repo_root .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_pickups.lua"
        local file = assert(io.open(runtime_path, "rb"))
        local source = file:read("*a")
        file:close()
        local _, count = source:gsub('mod:hook_safe%("AIBotGroupSystem", "_update_mule_pickups"', "")
        H.equal(count, 1)
        H.truthy(source:find("_GT365_SCAN_INTERVAL = 0.5", 1, true))
        H.truthy(source:find("_gt365_smart_claims[best_pickup] = true", 1, true))

        local data_path = repo_root .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/general_tweaker_dev_data.lua"
        local data_file = assert(io.open(data_path, "rb"))
        local data = data_file:read("*a")
        data_file:close()
        H.truthy(data:find('setting_id    = "gt_bot_smart_ale"', 1, true))
        H.truthy(data:find('setting_id    = "gt_bot_smart_ale"', 1, true)
            < data:find('default_value = false', data:find('setting_id    = "gt_bot_smart_ale"', 1, true), true))
    end)
end
