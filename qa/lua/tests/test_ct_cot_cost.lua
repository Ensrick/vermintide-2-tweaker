return function(H, repo_root)
    local root = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local Policy = assert(loadfile(root .. "_ct_cot_cost_policy.lua"))()

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local content = file:read("*a")
        file:close()
        return content
    end

    H.test("CT Chest of Trials cost sanitizes to a bounded 25-coin grid", function()
        H.equal(Policy.sanitize_cost(nil), 100)
        H.equal(Policy.sanitize_cost(1), 25)
        H.equal(Policy.sanitize_cost(112), 100)
        H.equal(Policy.sanitize_cost(113), 125)
        H.equal(Policy.sanitize_cost(5000), 1000)
        H.equal(Policy.sanitize_cost(0 / 0), 100)
    end)

    H.test("CT Chest of Trials cost gates only WAITING activation", function()
        H.deep_equal({ Policy.activation_plan(false, Policy.WAITING, 0, 100) },
            { true, 0, "passthrough" })
        H.deep_equal({ Policy.activation_plan(true, 2, 0, 100) },
            { true, 0, "passthrough" })
        H.deep_equal({ Policy.activation_plan(true, Policy.WAITING, 99, 100) },
            { false, 0, "insufficient_coins" })
        H.deep_equal({ Policy.activation_plan(true, Policy.WAITING, 100, 100) },
            { true, 100, "charge" })
        H.equal(Policy.transition_committed(Policy.WAITING, 2), true)
        H.equal(Policy.transition_committed(Policy.WAITING, Policy.WAITING), false)
    end)

    H.test("CT Chest of Trials cost uses one host transaction and no new RPC", function()
        local runtime = read(root .. "_ct_cot_cost.lua")
        local _, hooks = runtime:gsub('mod:hook%("DeusCursedChestExtension", "on_server_interact"', "")
        H.equal(hooks, 1)
        H.truthy(runtime:find("player_manager:owner(interactor_unit)", 1, true))
        H.truthy(runtime:find("Managers.player.is_server", 1, true))
        H.truthy(runtime:find("player.bot_player", 1, true))
        H.truthy(runtime:find("set_player_soft_currency", 1, true))
        H.truthy(runtime:find("transition_committed", 1, true))
        H.truthy(runtime:find("refund", 1, true))
        H.equal(runtime:find("network_send", 1, true), nil)
        H.equal(runtime:find("network_register", 1, true), nil)
        H.equal(runtime:find("NetworkLookup", 1, true), nil)
    end)

    H.test("CT Chest of Trials cost setting and prompt compose with existing hooks", function()
        local data = read(root .. "chaos_wastes_tweaker_dev_data.lua")
        local early = read(root .. "_ct_cot_early_reward.lua")
        local main = read(root .. "chaos_wastes_tweaker_dev.lua")
        H.truthy(data:find('setting_id%s*=%s*"cot_cost_enabled"'))
        H.truthy(data:find('setting_id%s*=%s*"cot_cost_amount"'))
        H.truthy(data:find('range%s*=%s*{%s*25,%s*1000%s*}'))
        H.truthy(data:find('setting_id%s*=%s*"cot_cost_amount".-step%s*=%s*25'))
        H.truthy(early:find("mod._ct_cot_cost_action_key", 1, true))
        H.truthy(main:find('key == "ct_cot_cost_action"', 1, true))
        H.truthy(main:find('scripts/mods/chaos_wastes_tweaker_dev/_ct_cot_cost', 1, true))
    end)
end
