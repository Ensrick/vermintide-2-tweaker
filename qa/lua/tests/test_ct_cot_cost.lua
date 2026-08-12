return function(H, repo_root)
    local CTSource = dofile(repo_root .. "/qa/lua/ct_source.lua")
    local root = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local Policy = assert(loadfile(root .. "_ct_cot_cost_policy.lua"))()

local function read(path)
        if tostring(path):find("chaos_wastes_tweaker_dev.lua", 1, true) then
            return CTSource.expanded(repo_root)
        end
        local file = assert(io.open(path, "rb"))
        local content = file:read("*a")
        file:close()
        return content
    end

    H.test("CT Chest of Trials cost sanitizes to a bounded 25-coin grid", function()
        H.equal(Policy.sanitize_cost(nil), 0)
        H.equal(Policy.sanitize_cost(0), 0)
        H.equal(Policy.sanitize_cost(1), 0)
        H.equal(Policy.sanitize_cost(13), 25)
        H.equal(Policy.sanitize_cost(112), 100)
        H.equal(Policy.sanitize_cost(113), 125)
        H.equal(Policy.sanitize_cost(5000), 1000)
        H.equal(Policy.sanitize_cost(0 / 0), 0)
    end)

    H.test("CT Chest of Trials cost gates only WAITING activation", function()
        H.deep_equal({ Policy.activation_plan(Policy.WAITING, nil, 0) },
            { true, 0, "passthrough" })
        H.deep_equal({ Policy.activation_plan(2, 0, 100) },
            { true, 0, "passthrough" })
        H.deep_equal({ Policy.activation_plan(Policy.WAITING, 99, 100) },
            { false, 0, "insufficient_coins" })
        H.deep_equal({ Policy.activation_plan(Policy.WAITING, 100, 100) },
            { true, 100, "charge" })
        H.equal(Policy.transition_committed(Policy.WAITING, 2), true)
        H.equal(Policy.transition_committed(Policy.WAITING, Policy.WAITING), false)
    end)

    H.test("CT Chest of Trials legacy enable pair migrates to one absolute amount", function()
        H.deep_equal({ Policy.migrate_legacy(nil, nil) }, { 0, "fresh" })
        H.deep_equal({ Policy.migrate_legacy(false, 100) }, { 0, "legacy_disabled" })
        H.deep_equal({ Policy.migrate_legacy(true, 112) }, { 100, "legacy_enabled" })
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
        local runtime = read(root .. "_ct_cot_cost.lua")
        local early = read(root .. "_ct_cot_early_reward.lua")
        local main = read(root .. "chaos_wastes_tweaker_dev.lua")
        H.equal(data:find('setting_id%s*=%s*"cot_cost_enabled"'), nil)
        H.truthy(data:find('setting_id%s*=%s*"cot_cost_amount"'))
        H.truthy(data:find('default_value%s*=%s*0,%s*range%s*=%s*{%s*0,%s*1000%s*}'))
        H.truthy(runtime:find('mod:get("cot_cost_absolute_migrated")', 1, true))
        H.truthy(early:find("mod._ct_cot_cost_action_key", 1, true))
        H.truthy(main:find('key == "ct_cot_cost_action"', 1, true))
        H.truthy(main:find('scripts/mods/chaos_wastes_tweaker_dev/_ct_cot_cost', 1, true))
    end)


    H.test("CT trial cost uses 25-coin Mod Tweaker steps on both presentation paths", function()
        local view = read(repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_view.lua")
        local state = read(repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_state.lua")
        for _, source in ipairs({ view, state }) do
            H.truthy(source:find("cot_cost_amount = 25", 1, true))
        end
    end)

    H.test("CT trial cost localization stays concise and behavior-first", function()
        local loc = read(root .. "chaos_wastes_tweaker_dev_localization.lua")
        local title = loc:match('cot_cost_amount%s*=%s*{%s*en%s*=%s*"([^"]+)"')
        local tooltip = loc:match('cot_cost_amount_tooltip%s*=%s*{%s*en%s*=%s*"([^"]+)"')
        H.equal(title, "Trial Chest Cost")
        H.equal(tooltip,
            "Charges this many Pilgrim's Coins to the player who starts the trial. Set to 0 for free activation.")
        local title_words = select(2, title:gsub("%S+", ""))
        local tooltip_words = select(2, tooltip:gsub("%S+", ""))
        local sentences = select(2, tooltip:gsub("[.!?]", ""))
        H.truthy(title_words <= 6)
        H.truthy(tooltip_words <= 30)
        H.truthy(sentences <= 2)
        H.equal(tooltip:find("slider", 1, true), nil)
        H.equal(tooltip:find("runtime", 1, true), nil)
        H.equal(tooltip:find(title .. ":", 1, true), nil)
    end)
end
