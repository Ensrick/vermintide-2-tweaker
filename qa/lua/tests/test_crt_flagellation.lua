return function(H, repo_root)
    local P = dofile(repo_root
        .. "/career_tweaker/scripts/mods/career_tweaker/_crt_flagellation_policy.lua")

    H.test("CRT #447 converts half the realized THP without exceeding green HP", function()
        local amount, gained = P.conversion_amount(10, 14, 100)
        H.equal(gained, 4)
        H.equal(amount, 2)
        amount, gained = P.conversion_amount(14, 14, 100)
        H.equal(gained, 0)
        H.equal(amount, 0)
        amount = P.conversion_amount(0, 10, 3)
        H.equal(amount, 3)
    end)

    H.test("CRT #447 resolves Devotion by live title or canonical identity", function()
        local rows = {
            { name = "victor_zealot_other", display_name = "other" },
            { name = "victor_zealot_live_name", display_name = "devotion_key" },
        }
        local found = P.resolve_devotion(rows, function(key)
            return key == "devotion_key" and "Devotion" or "Other"
        end)
        H.equal(found.name, "victor_zealot_live_name")
        found = P.resolve_devotion({ { name = "victor_zealot_devotion" } }, function() return "?" end)
        H.equal(found.name, "victor_zealot_devotion")
    end)

    H.test("CRT #447 production scopes conversion to level-5 proc windows", function()
        local path = repo_root
            .. "/career_tweaker/scripts/mods/career_tweaker/_crt_flagellation.lua"
        local f = assert(io.open(path, "rb"))
        local source = f:read("*a")
        f:close()
        H.truthy(source:find('mod:hook("PlayerUnitHealthExtension", "add_heal"', 1, true))
        H.truthy(source:find("proc_context[unit]", 1, true))
        H.truthy(source:find("self:convert_to_temp(amount)", 1, true))
        H.truthy(source:find('mod:get("rework_wh_zealot_flagellation")', 1, true))
        local _, count = source:gsub('mod:hook%("PlayerUnitHealthExtension", "add_heal"', "")
        H.equal(count, 1)
    end)

    H.test("CRT #447 is catalogued and mutexed as a Zealot THP alternative", function()
        local balance_path = repo_root
            .. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker_balance.lua"
        local main_path = repo_root
            .. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker.lua"
        local f = assert(io.open(balance_path, "rb"))
        local balance = f:read("*a")
        f:close()
        f = assert(io.open(main_path, "rb"))
        local main = f:read("*a")
        f:close()
        H.truthy(balance:find("rework_wh_zealot_flagellation = {", 1, true))
        H.truthy(main:find('mutex.declare("zealot_thp_conversions"', 1, true))
        H.truthy(main:find('"rework_wh_zealot_ability_green_to_thp"', 1, true))
        H.truthy(main:find('"rework_wh_zealot_flagellation"', 1, true))
    end)
end
