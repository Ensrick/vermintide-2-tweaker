return function(H, repo_root)
    local balance_path = repo_root
        .. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker_balance.lua"
    local file = assert(io.open(balance_path, "rb"))
    local source = file:read("*a")
    file:close()

    H.test("CRT Ranger ale derives one native scale for a 0.75-second target", function()
        H.truthy(source:find("rework_dr_ranger_ale_one_second_drink = {", 1, true))
        H.truthy(source:find("local stock_duration = action and tonumber(action.total_time)", 1, true))
        H.truthy(source:find("local target_duration = 0.75", 1, true))
        H.truthy(source:find("action.anim_time_scale = stock_duration / target_duration", 1, true))
        H.equal(source:find("action.total_time =", 1, true), nil,
            "the authored 1.9-second source duration should remain canonical")

        local stock_duration = 1.9
        local target_duration = 0.75
        local scale = stock_duration / target_duration
        H.truthy(math.abs(scale - 2.5333333333333) < 0.000001)
        H.truthy(math.abs(stock_duration / scale - target_duration) < 0.000001)
    end)

    H.test("CRT Ranger ale speed rework restores absent and authored scales exactly", function()
        H.truthy(source:find("saved.ale_anim_time_scale_had_value = action.anim_time_scale ~= nil", 1, true))
        H.truthy(source:find("saved.ale_anim_time_scale_original = action.anim_time_scale", 1, true))
        H.truthy(source:find("and saved.ale_anim_time_scale_original or nil", 1, true))
    end)

    H.test("CRT Ranger ale setting is opt-in and lifecycle-wired", function()
        local data_path = repo_root
            .. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker_data.lua"
        local data_file = assert(io.open(data_path, "rb"))
        local data = data_file:read("*a")
        data_file:close()
        local setting = assert(data:find(
            'setting_id = "rework_dr_ranger_ale_one_second_drink"', 1, true))
        H.truthy(data:find("default_value = false", setting, true))
    end)

    H.test("CRT Ranger ale localization names and explains the faster duration", function()
        local loc_path = repo_root
            .. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker_localization.lua"
        local loc_file = assert(io.open(loc_path, "rb"))
        local loc = loc_file:read("*a")
        loc_file:close()
        H.truthy(loc:find("Ranger Veteran: Faster Ale Drinking Animation", 1, true))
        H.truthy(loc:find("from 1.9 seconds to 0.75 seconds", 1, true))
        H.equal(loc:find("One-second ale drinking", 1, true), nil)
    end)
end
