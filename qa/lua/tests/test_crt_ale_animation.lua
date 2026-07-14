return function(H, repo_root)
    local balance_path = repo_root
        .. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker_balance.lua"
    local file = assert(io.open(balance_path, "rb"))
    local source = file:read("*a")
    file:close()

    H.test("CRT Ranger ale compresses action and animation through one native scale", function()
        H.truthy(source:find("rework_dr_ranger_ale_one_second_drink = {", 1, true))
        H.truthy(source:find("action.anim_time_scale = 1.9", 1, true))
        H.equal(source:find("action.total_time =", 1, true), nil,
            "the authored 1.9-second source duration should remain canonical")
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
end
