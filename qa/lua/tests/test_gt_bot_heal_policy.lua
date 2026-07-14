return function(H, repo_root)
    local path = repo_root .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_heal_policy.lua"
    local Policy = assert(loadfile(path))()
    local defaults = { regular_percent = 15, wounded_percent = 100,
        exclude_zealot = true, heal_wounded_zealot = true }

    H.test("gt bot heal policy separates ordinary and wounded thresholds", function()
        H.truthy(Policy.is_eligible(0.15, false, false, defaults))
        H.equal(Policy.is_eligible(0.151, false, false, defaults), false)
        H.truthy(Policy.is_eligible(1.0, true, false, defaults))
        local custom = { regular_percent = 0, wounded_percent = 40,
            exclude_zealot = false, heal_wounded_zealot = true }
        H.equal(Policy.is_eligible(0.01, false, false, custom), false)
        H.equal(Policy.is_eligible(0, false, false, custom), false)
        H.truthy(Policy.is_eligible(0.4, true, false, custom))
        H.equal(Policy.is_eligible(0.41, true, false, custom), false)
    end)

    H.test("gt bot heal policy protects Zealot except explicit wounded allowance", function()
        H.equal(Policy.is_eligible(0.05, false, true, defaults), false)
        H.truthy(Policy.is_eligible(0.75, true, true, defaults))
        local custom = { regular_percent = 100, wounded_percent = 100,
            exclude_zealot = false, heal_wounded_zealot = false }
        H.truthy(Policy.is_eligible(0.75, false, true, custom))
        H.equal(Policy.is_eligible(0.01, true, true, custom), false)
    end)

    H.test("gt bot heal runtime retains native heal-other path", function()
        local runtime = repo_root .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua"
        local file = assert(io.open(runtime, "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find('return heal_unit, heal_dist, "in_need_of_heal", false', 1, true))
        H.truthy(source:find('if _gt_heal_allies_active and need_type == "in_need_of_heal"', 1, true))
        H.equal(source:find('mod:hook("BTConditions", "can_heal_player"', 1, true), nil)
        H.equal(source:find('DamageUtils.heal_network(', 1, true), nil)
    end)
end
