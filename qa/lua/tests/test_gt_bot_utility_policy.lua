return function(H, repo_root)
    local root = repo_root .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/"
    local Policy = assert(loadfile(root .. "_gt_bot_utility_policy.lua"))()

    local function numeric_consideration(input)
        return {
            blackboard_input = input,
            max_value = 40,
            spline = { 0, 0.1, 1, 1 },
        }
    end

    H.test("GT bot follow repairs missing ally distance before arithmetic", function()
        local follow = { distance_to_target = numeric_consideration("ally_distance") }
        local action = { action_weight = 1, considerations = follow }
        local blackboard = { utility_actions = { follow = {} } }

        local ready, repaired = Policy.prepare_utility_inputs(action, "follow", blackboard, follow)
        H.truthy(ready)
        H.equal(repaired, "ally_distance")
        H.equal(blackboard.ally_distance, math.huge)

        local ok = pcall(function()
            return (blackboard.ally_distance - 0) / 40
        end)
        H.truthy(ok, "repaired follow value must be numeric before vanilla arithmetic")
        H.equal(Policy.normalize_ally_distance(nil), math.huge)
        H.equal(Policy.normalize_ally_distance(12.5), 12.5)
    end)

    H.test("GT utility guard fails unknown numeric inputs closed", function()
        local attack = { range = numeric_consideration("unknown_range") }
        local action = { action_weight = 1, considerations = attack }
        local blackboard = { utility_actions = { attack = {} } }

        local ready, reason = Policy.prepare_utility_inputs(action, "attack", blackboard, {})
        H.equal(ready, false)
        H.equal(reason, "numeric_input.unknown_range")
        H.equal(blackboard.unknown_range, nil)

        blackboard.unknown_range = 7
        H.truthy(Policy.prepare_utility_inputs(action, "attack", blackboard, {}))
        H.equal(blackboard.unknown_range, 7)
    end)

    H.test("GT utility guard permits nil condition inputs", function()
        local considerations = {
            target_changed = {
                blackboard_input = "target_changed",
                is_condition = true,
            },
        }
        local action = { action_weight = 1, considerations = considerations }
        local blackboard = { utility_actions = { idle = {} } }
        H.truthy(Policy.prepare_utility_inputs(action, "idle", blackboard, {}))
    end)

    H.test("GT utility hook has one bot-owned fail-closed registration", function()
        local function read(path)
            local file = assert(io.open(path, "rb"))
            local source = file:read("*a")
            file:close()
            return source
        end

        local bot_source = read(root .. "_gt_bot_fixes.lua")
        local spawner_source = read(root .. "_gt_creature_spawner.lua")
        H.truthy(bot_source:find('mod:hook(Utility, "get_action_utility"', 1, true))
        H.truthy(bot_source:find("return 0", 1, true))
        H.truthy(bot_source:find("return nil, math.huge, nil, nil", 1, true))
        H.equal(spawner_source:find('mod:hook(Utility, "get_action_utility"', 1, true), nil)
    end)
end
