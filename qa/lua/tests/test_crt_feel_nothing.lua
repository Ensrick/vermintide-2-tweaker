return function(H, repo_root)
    local base = repo_root .. "/career_tweaker/scripts/mods/career_tweaker/"

    local function read(name)
        local file = assert(io.open(base .. name, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local balance = read("career_tweaker_balance.lua")
    local data = read("career_tweaker_data.lua")
    local localization = read("career_tweaker_localization.lua")
    local hooks = read("_career_tweaker_balance_hooks.lua")
    local regression = read("_crt_regression.lua")

    H.test("CRT #999 uses the native one-stack duration refresh path", function()
        H.truthy(balance:find("rework_wh_zealot_feel_nothing_refresh = {", 1, true))
        H.truthy(balance:find(
            '{ buff = "victor_zealot_activated_ability_ignore_death", field = "refresh_durations", value = true }',
            1, true))
        H.equal(balance:find('mod:hook("CareerAbilityWHZealot"', 1, true), nil,
            "the fix must not add a second ability hook or custom timer")
    end)

    H.test("CRT #999 setting and player-facing text are complete", function()
        H.truthy(data:find('setting_id = "rework_wh_zealot_feel_nothing_refresh"', 1, true))
        H.truthy(localization:find("rework_wh_zealot_feel_nothing_refresh_description", 1, true))
        H.truthy(hooks:find('["victor_zealot_activated_ability_ignore_death_desc"]', 1, true))
        H.truthy(hooks:find('setting = "rework_wh_zealot_feel_nothing_refresh"', 1, true))
    end)

    H.test("CRT #999 runtime regression checks authored and live buff shape", function()
        H.truthy(regression:find('_rt_register("issue999_feel_nothing_refresh"', 1, true))
        H.truthy(regression:find("sub.max_stacks ~= 1 or sub.duration ~= 5", 1, true))
        H.truthy(regression:find("sub.refresh_durations ~= true", 1, true))
    end)
end
