return function(H, repo_root)
    local policy_path = repo_root
        .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_godmode_indicator_policy.lua"
    local Policy = assert(loadfile(policy_path))()

    H.test("GT Godmode indicator is exact-boolean gated", function()
        H.equal(Policy.visible(true), true)
        H.equal(Policy.visible(false), false)
        H.equal(Policy.visible(nil), false)
        H.equal(Policy.visible(1), false)
    end)

    H.test("GT Godmode indicator stays in the upper-right HUD canvas", function()
        local normal = Policy.layout(120)
        H.equal(normal.text_x, 1780)
        H.equal(normal.text_y, 1035)
        H.truthy(normal.background_x >= 0)
        H.truthy(normal.background_x + normal.background_width <= Policy.CANVAS_WIDTH)

        local clamped = Policy.layout(9999)
        H.equal(clamped.background_width, Policy.MAX_TEXT_WIDTH + Policy.PADDING * 2)
        H.truthy(clamped.background_x >= 0)
    end)

    H.test("GT Godmode indicator shares the singleton HUD hook", function()
        local hud_path = repo_root
            .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_melee_warning.lua"
        local file = assert(io.open(hud_path, "rb"))
        local source = file:read("*a")
        file:close()
        local _, hook_count = source:gsub('mod:hook_safe%("IngameHud", "update"', "")
        H.equal(hook_count, 1)
        H.truthy(source:find("mod._gt_godmode_indicator_draw", 1, true))

        local indicator_path = repo_root
            .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_godmode_indicator.lua"
        local indicator_file = assert(io.open(indicator_path, "rb"))
        local indicator = indicator_file:read("*a")
        indicator_file:close()
        H.equal(indicator:find('mod:hook_safe("IngameHud"', 1, true), nil)
        H.truthy(indicator:find('mod:get("godmode_enabled")', 1, true))
    end)
end
