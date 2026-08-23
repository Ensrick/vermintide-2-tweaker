return function(H, repo_root)
    local root = repo_root .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/"

    local function read(name)
        local file = assert(io.open(root .. name, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    H.test("GT regression extraction preserves registration order and count", function()
        local module = dofile(root .. "_gt_regression_checks.lua")
        local names = {}
        module.install({}, function(name, check)
            H.equal(type(check), "function")
            names[#names + 1] = name
        end, {
            CT_GT_PICKUP_LOOKUP_RAWGET_MARKER_v0_2_48 = "gt-pickup-lookup-rawget-hardened",
            CT_GT_AI_CLIENT_SEND_MARKER_v0_2_52 = "gt-ai-client-send-vmf-rehandshake",
            dbg = function() end,
            dbg_alert = function() end,
        })

        H.equal(#names, 83)
        H.equal(names[1], "gt_pickup_lookup_uses_rawget")
        H.equal(names[#names], "issue241_noclip_boundary_routes")
    end)

    H.test("GT entry point owns only the regression harness", function()
        local main = read("general_tweaker_dev.lua")
        local module = read("_gt_regression_checks.lua")
        H.truthy(main:find('mod:dofile("scripts/mods/general_tweaker_dev/_gt_regression_checks")', 1, true))
        H.equal(select(2, main:gsub('_rt_register%(', '')), 2)
        H.equal(select(2, module:gsub('_rt_register%(', '')), 83)
    end)

    H.test("GT bot update extraction preserves the singleton dispatcher", function()
        local bot_main = read("_gt_bot_fixes.lua")
        local update = read("_gt_bot_update_fixes.lua")
        H.truthy(bot_main:find(
            'mod:dofile("scripts/mods/general_tweaker_dev/_gt_bot_update_fixes")',
            1, true))
        H.equal(select(2, bot_main:gsub('mod:hook_safe%("PlayerBotBase", "update"', '')), 0)
        H.equal(select(2, update:gsub('mod:hook_safe%("PlayerBotBase", "update"', '')), 1)
        H.truthy(update:find("_gt_bot_update_consolidated", 1, true))
        for _, consumer in ipairs({
            "_gt_necro_potion_tick",
            "_gt_ledge_pullup_tick",
            "_gt_ladder_unstick_tick",
            "_gt_instant_pickup_tick",
            "_gt_drink_potion_tick",
            "_gt_btlab_observe_update",
            "_gt492_aid_stall_tick",
        }) do
            H.truthy(update:find(consumer, 1, true), consumer .. " dispatcher route missing")
        end
    end)

    H.test("GT bot aid extraction preserves its ordered owner boundary", function()
        local bot_main = read("_gt_bot_fixes.lua")
        local owner = read("_gt_bot_aid_owner.lua")
        local load_at = assert(bot_main:find(
            'mod:dofile("scripts/mods/general_tweaker_dev/_gt_bot_aid_owner")', 1, true))
        local melee_enter_at = assert(bot_main:find(
            'mod:hook("BTBotMeleeAction", "enter"', 1, true))
        local teleport_at = assert(bot_main:find(
            'mod:hook("BTConditions", "should_teleport"', 1, true))
        H.truthy(melee_enter_at < load_at)
        H.truthy(load_at < teleport_at)
        H.equal(select(2, bot_main:gsub(
            'mod:dofile%("scripts/mods/general_tweaker_dev/_gt_bot_aid_owner"%)', '')), 1)
        H.equal(select(2, bot_main:gsub('mod:hook%("BTConditions", "can_activate_ability"', '')), 0)
        H.equal(select(2, bot_main:gsub('mod:hook%("PlayerBotBase", "_select_ally_by_utility"', '')), 0)
        H.equal(select(2, owner:gsub('mod:hook%("BTConditions", "can_activate_ability"', '')), 1)
        H.equal(select(2, owner:gsub('mod:hook%("PlayerBotBase", "_select_ally_by_utility"', '')), 1)
    end)
end
