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

    -- The 21 live Zealot talent internal names (talent_settings_victor.lua,
    -- Talents.witch_hunter). Only the three thp_* rows carry display_name
    -- (:1408/:1420/:1432); every other title loc key IS the internal name
    -- (hero_window_talents.lua:328 - Localize(display_name or name)).
    local ZEALOT_NAMES = {
        "victor_zealot_activated_ability_cooldown_stack_on_hit",
        "victor_zealot_activated_ability_ignore_death",
        "victor_zealot_activated_ability_power_on_hit",
        "victor_zealot_attack_speed_on_health_percent",
        "victor_zealot_bloodlust_2",
        "victor_zealot_crit_count",
        "victor_zealot_heal_share",
        "victor_zealot_linesman_unbalance",
        "victor_zealot_max_stamina_on_damage_taken",
        "victor_zealot_move_speed_on_damage_taken",
        "victor_zealot_passive_damage_taken",
        "victor_zealot_passive_healing_received",
        "victor_zealot_passive_move_speed",
        "victor_zealot_power",
        "victor_zealot_power_level_unbalance",
        "victor_zealot_reaper",
        "victor_zealot_reduced_damage_taken",
        "victor_zealot_smiter_unbalance",
        "victor_zealot_thp_linesman",
        "victor_zealot_thp_smiter",
        "victor_zealot_thp_tank",
    }
    local THP_DISPLAY_NAMES = {
        victor_zealot_thp_linesman = "thp_linesman_buff_name",
        victor_zealot_thp_smiter = "thp_smiter_buff_name",
        victor_zealot_thp_tank = "thp_tank_buff_name",
    }
    local DEVOTION_INTERNAL = "victor_zealot_move_speed_on_damage_taken"

    local function retail_candidates()
        local rows = {}
        for i = 1, #ZEALOT_NAMES do
            local name = ZEALOT_NAMES[i]
            rows[i] = {
                name = name,
                -- Mirrors the production bake in _crt_flagellation.lua.
                display_key = THP_DISPLAY_NAMES[name] or name,
                description = name .. "_desc",
            }
        end
        return rows
    end

    local function retail_localize(devotion_key)
        return function(key)
            if key == devotion_key then return "Devotion" end
            if type(key) ~= "string" then error("Localize on non-string") end
            return "Title of " .. key
        end
    end

    H.test("CRT #447 retail shape (display_name nil) resolves via the name key", function()
        local found, census = P.resolve_devotion(retail_candidates(),
            retail_localize(DEVOTION_INTERNAL))
        H.truthy(found, "retail-shaped table must resolve")
        H.equal(found.name, DEVOTION_INTERNAL)
        H.equal(found.title, "Devotion")
        H.equal(census.candidates, 21)
        H.equal(census.resolved, 21)
        H.equal(census.unresolved, 0)
        H.equal(census.matches, 1)
        for i = 1, #census.rows do
            H.truthy(census.rows[i].title, "resolved census titles must be non-nil")
            H.truthy(census.rows[i].display_key, "census display keys must be non-nil")
        end
    end)

    H.test("CRT #447 loc fallback shape <key> counts as unresolved, never crashes", function()
        local found, census = P.resolve_devotion(retail_candidates(), function(key)
            return "<" .. tostring(key) .. ">"
        end)
        H.equal(found, nil)
        H.equal(census.candidates, 21)
        H.equal(census.resolved, 0)
        H.equal(census.unresolved, 21)
        H.equal(census.rows[1].title, nil)
        found, census = P.resolve_devotion(retail_candidates(), function()
            error("loc unavailable")
        end)
        H.equal(found, nil)
        H.equal(census.unresolved, 21)
    end)

    H.test("CRT #447 duplicated Devotion title resolves nothing (exactly-one rule)", function()
        local rows = retail_candidates()
        local localize = retail_localize(DEVOTION_INTERNAL)
        local found, census = P.resolve_devotion(rows, function(key)
            if key == "victor_zealot_power" then return "Devotion" end
            return localize(key)
        end)
        H.equal(found, nil)
        H.equal(census.matches, 2)
    end)

    H.test("CRT #447 title match trims and case-folds; display_key wins over fallbacks", function()
        local found = P.resolve_devotion(retail_candidates(), function(key)
            return key == DEVOTION_INTERNAL and "  DEVOTION  " or ("Title of " .. key)
        end)
        H.equal(found.name, DEVOTION_INTERNAL)
        H.equal(P.display_key({ display_key = "a", display_name = "b", name = "c" }), "a")
        H.equal(P.display_key({ display_name = "b", name = "c" }), "b")
        H.equal(P.display_key({ name = "c" }), "c")
        H.truthy(P.is_unresolved_title("<victor_zealot_power>"))
        H.truthy(P.is_unresolved_title(nil))
        H.truthy(P.is_unresolved_title(""))
        H.equal(P.is_unresolved_title("Devotion"), false)
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
        -- #447 resolution contract: candidates bake the vanilla title key
        -- (display_name or name, hero_window_talents.lua:328), resolution is
        -- idempotent via try_resolve, and a failed boot arms the lazy retry.
        H.truthy(source:find("display_key = talent.display_name or name", 1, true))
        H.truthy(source:find("function state.try_resolve()", 1, true))
        H.truthy(source:find("state.lazy_retry_pending = true", 1, true))
        H.truthy(source:find('evidence("census candidates=%d resolved=%d unresolved=%d matches=%d"', 1, true))
        H.truthy(source:find('evidence("Devotion unresolved candidates=%d; feature inert"', 1, true))
        local hooks_path = repo_root
            .. "/career_tweaker/scripts/mods/career_tweaker/_career_tweaker_balance_hooks.lua"
        f = assert(io.open(hooks_path, "rb"))
        local hooks_source = f:read("*a")
        f:close()
        H.truthy(hooks_source:find("flagellation.lazy_retry_pending and flagellation.try_resolve", 1, true),
            "consolidated Localize hook must carry the #447 lazy retry")
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
