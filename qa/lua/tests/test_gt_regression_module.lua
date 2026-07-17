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

        H.equal(#names, 82)
        H.equal(names[1], "gt_pickup_lookup_uses_rawget")
        H.equal(names[#names], "issue241_noclip_boundary_routes")
    end)

    H.test("GT entry point owns only the regression harness", function()
        local main = read("general_tweaker_dev.lua")
        local module = read("_gt_regression_checks.lua")
        H.truthy(main:find('mod:dofile("scripts/mods/general_tweaker_dev/_gt_regression_checks")', 1, true))
        H.equal(select(2, main:gsub('_rt_register%(', '')), 2)
        H.equal(select(2, module:gsub('_rt_register%(', '')), 82)
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
end
