return function(H, repo_root)
    local context_path = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_pilgrimage_context.lua"
    local Context = assert(loadfile(context_path))()

    H.test("CT #461 exact Pilgrimage Chamber level policy", function()
        H.truthy(Context.is_level("morris_hub"))
        H.equal(Context.is_level("inn_level"), false)
        H.equal(Context.is_level("dlc_morris_map"), false)
        H.equal(Context.is_level("pat_forest"), false)
        H.equal(Context.is_level(nil), false)
    end)

    H.test("CT #461 chamber resolver fails closed at unavailable engine seams", function()
        local managers = {
            level_transition_handler = {
                get_current_level_key = function() return "morris_hub" end,
            },
        }
        H.truthy(Context.is_current(managers))
        managers.level_transition_handler.get_current_level_key = function() return "inn_level" end
        H.equal(Context.is_current(managers), false)
        managers.level_transition_handler.get_current_level_key = function() error("not ready") end
        H.equal(Context.is_current(managers), false)
        H.equal(Context.is_current(nil), false)
    end)

    H.test("CT #461 and #505 consume one shared chamber context", function()
        local mission_path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_dev_mission.lua"
        local mf = assert(io.open(mission_path, "rb"))
        local mission = mf:read("*a"); mf:close()
        H.truthy(mission:find('_ct_pilgrimage_context', 1, true))
        H.truthy(mission:find('mod._ct_in_pilgrimage_chamber = in_pilgrimage_chamber', 1, true))
        H.truthy(mission:find('mod._ct505_in_pilgrimage_chamber = in_pilgrimage_chamber', 1, true))
    end)

    H.test("CT #461 builds by chamber context without duplicating the shared draw hook", function()
        local main_path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua"
        local f = assert(io.open(main_path, "rb"))
        local source = f:read("*a"); f:close()
        local setup = assert(source:find('mod:hook_safe("IngamePlayerListUI", "_setup_deed_reward_data"', 1, true))
        local draw = assert(source:find('mod:hook_safe("IngamePlayerListUI", "_draw"', setup, true))
        local setup_body = source:sub(setup, draw - 1)
        H.truthy(setup_body:find('mod._ct_in_pilgrimage_chamber', 1, true))
        H.equal(setup_body:find('if not mod._ct_preparing_cw_expedition()', 1, true), nil,
            "queued expedition must not gate the pre-queue chamber preview")
        H.truthy(setup_body:find('source=%s queued=%s', 1, true),
            "bounded diagnostics must record effective source and queue state")
        local _, draw_hooks = source:gsub('mod:hook_safe%("IngamePlayerListUI", "_draw"', "")
        H.equal(draw_hooks, 1, "#461/#533/#571 must retain one shared draw hook")
        H.truthy(source:find('pcall(mod._ct_diag_tab_native533.capture, self)', draw, true))
        H.truthy(source:find('pcall(mod._ct_layout_deus_collectibles, self)', draw, true))
    end)
end
