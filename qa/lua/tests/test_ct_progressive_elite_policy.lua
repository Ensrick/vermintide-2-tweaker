return function(H, repo_root)
    local Policy = assert(loadfile(repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_progressive_elite_policy.lua"))()

    H.test("CT #323 elite modifier chance follows mission progression", function()
        H.equal(Policy.rate(0), 0)
        H.equal(Policy.rate(1), 5)
        H.equal(Policy.rate(2), 10)
        H.equal(Policy.rate(3), 15)
        H.equal(Policy.rate(4), 20)
        H.equal(Policy.rate(100), 20)
    end)

    H.test("CT #323 candidate classifier excludes monsters and trash", function()
        H.equal(Policy.classify_breed({ elite = true }), "elite")
        H.equal(Policy.classify_breed({ special = true }), "special")
        H.equal(Policy.classify_breed({ boss = true, elite = true }), "other")
        H.equal(Policy.classify_breed({}), "other")
        H.equal(Policy.classify_breed(nil), "other")
    end)

    H.test("CT #323 deterministic sampler respects exact rate boundaries", function()
        local bucket = Policy.bucket(42, "chaos_warrior")
        H.equal(bucket >= 0 and bucket < 100, true)
        H.equal(Policy.would_apply(42, "chaos_warrior", 0), false)
        H.equal(Policy.would_apply(42, "chaos_warrior", 100), bucket < 20)
        H.equal(Policy.bucket(42, "chaos_warrior"), bucket)
    end)

    H.test("CT #323 catalog separates boss-only from elite-proven modifiers", function()
        local enhancements, boss = {}, {}
        for _, row in ipairs(Policy.CATALOG) do
            enhancements[row.name] = {}
            if row.tier == "boss_unproven" then boss[row.name] = true end
        end
        local result = Policy.inspect_catalog(enhancements, boss)
        H.equal(result.total, 15)
        H.equal(result.templates, 15)
        H.equal(result.boss_catalog, 13)
        H.equal(result.boss_registered, 13)
        H.equal(result.elite_source_proven, 2)
        H.equal(#result.missing, 0)
    end)

    -- ------------------------------------------------------------------
    -- #323 CT slice: rate table, elite-only selector, allowlist exclusivity
    -- ------------------------------------------------------------------
    local function templates_from_catalog()
        local templates = { elite_base = { name = "elite_base" } }
        local boss = {}
        for _, row in ipairs(Policy.CATALOG) do
            templates[row.name] = { name = row.name }
            if row.tier == "boss_unproven" then boss[row.name] = true end
        end
        return templates, boss
    end

    H.test("CT #323 rate table is 0/5/10/15/20 by default and rescales with the step", function()
        H.deep_equal(Policy.rate_table(), { 0, 5, 10, 15, 20 })
        H.deep_equal(Policy.rate_table(5), { 0, 5, 10, 15, 20 })
        H.equal(Policy.rate_label(5), "0/5/10/15/20")
        H.equal(Policy.rate_label(nil), "0/5/10/15/20")
        H.equal(Policy.rate_label("junk"), "0/5/10/15/20")
        H.deep_equal(Policy.rate_table(10), { 0, 10, 20, 30, 40 })
        H.deep_equal(Policy.rate_table(0), { 0, 0, 0, 0, 0 })
        H.deep_equal(Policy.rate_table(25), { 0, 25, 50, 75, 100 })
        H.equal(Policy.rate(9, 25), 100)
        H.equal(Policy.rate(3, 99), 75, "step clamps to 25")
        H.equal(Policy.rate(2, -5), 0, "negative step clamps to 0")
        H.equal(Policy.rate(2, "7"), 14, "numeric strings are accepted")
        H.equal(Policy.rate(2, 4.6), 10, "steps round to whole percent")
        H.equal(Policy.clamp_step(nil), Policy.DEFAULT_STEP_PERCENT)
        H.equal(Policy.DEFAULT_STEP_PERCENT, 5)
        H.equal(Policy.MAX_STEPS, 4)
    end)

    H.test("CT #323 allowlist is exactly the two source-proven elite recipes", function()
        H.deep_equal(Policy.ELITE_RECIPES, { "shockwave", "ignore_death_aura" })
        H.equal(Policy.BASE_RECIPE, "elite_base")
        H.equal(Policy.is_elite_recipe("shockwave"), true)
        H.equal(Policy.is_elite_recipe("ignore_death_aura"), true)
        H.equal(Policy.is_elite_recipe("elite_base"), false)
        for _, row in ipairs(Policy.CATALOG) do
            H.equal(Policy.is_elite_recipe(row.name), row.tier == "elite_source_proven",
                row.name)
        end
    end)

    H.test("CT #323 selector applies only allowlisted recipes to ordinary elites under the rate", function()
        local templates, boss = templates_from_catalog()
        local elite = { elite = true, name = "chaos_warrior" }
        local seen, applied = {}, 0
        for depth = 0, 6 do
            for roll = 0, 99 do
                for pick = 1, 2 do
                    local list, recipe = Policy.enhancements_for(depth, roll, elite, pick, templates)
                    if list then
                        applied = applied + 1
                        H.equal(boss[recipe], nil, "boss mark selected: " .. tostring(recipe))
                        H.equal(Policy.is_elite_recipe(recipe), true, tostring(recipe))
                        H.equal(#list, 2)
                        H.equal(list[1], templates.elite_base)
                        H.equal(list[2], templates[recipe])
                        H.equal(roll < Policy.rate(depth), true, "selected above the rate")
                        seen[recipe] = true
                    else
                        H.equal(roll >= Policy.rate(depth), true, "missing below the rate")
                    end
                    H.equal(Policy.enhancements_for(depth, roll,
                        { special = true, name = "skaven_gutter_runner" }, pick, templates), nil,
                        "special selected")
                    H.equal(Policy.enhancements_for(depth, roll,
                        { boss = true, elite = true, name = "chaos_troll" }, pick, templates), nil,
                        "monster selected")
                    H.equal(Policy.enhancements_for(depth, roll,
                        { name = "skaven_slave" }, pick, templates), nil, "trash selected")
                    H.equal(Policy.enhancements_for(depth, roll, nil, pick, templates), nil)
                end
            end
        end
        H.equal(seen.shockwave, true)
        H.equal(seen.ignore_death_aura, true)
        -- (0 + 5 + 10 + 15 + 20 + 20 + 20) rolls x 2 picks
        H.equal(applied, 180)
    end)

    H.test("CT #323 recipe pick is normalized so no other catalog row is reachable", function()
        local templates = templates_from_catalog()
        local elite = { elite = true, name = "chaos_warrior" }
        for pick = -5, 20 do
            local _, recipe = Policy.enhancements_for(4, 0, elite, pick, templates)
            H.equal(Policy.is_elite_recipe(recipe), true, "pick " .. pick)
        end
        local _, recipe = Policy.enhancements_for(4, 0, elite, "x", templates)
        H.equal(recipe, "shockwave")
        H.equal(Policy.select_recipe(4, "x", 1), nil, "non-numeric roll never selects")
        H.equal(Policy.select_recipe(4, -1, 1), nil, "negative roll never selects")
        H.equal(Policy.select_recipe(4, 19, 2), "ignore_death_aura")
        H.equal(Policy.select_recipe(4, 20, 2), nil)
        H.equal(Policy.select_recipe(0, 0, 1), nil, "first map is always zero percent")
    end)

    H.test("CT #323 selector refuses a half-registered template set", function()
        local elite = { elite = true, name = "chaos_warrior" }
        H.equal(Policy.enhancements_for(4, 0, elite, 1, { elite_base = {} }), nil)
        H.equal(Policy.enhancements_for(4, 0, elite, 1, { shockwave = {} }), nil)
        H.equal(Policy.enhancements_for(4, 0, elite, 1, { elite_base = true, shockwave = {} }), nil)
        H.equal(Policy.enhancements_for(4, 0, elite, 1, nil), nil)
        H.equal(Policy.enhancements_for(4, 0, elite, 1, "BreedEnhancements"), nil)
    end)

    H.test("CT #323 spawn-derived selection is deterministic and step-aware", function()
        local templates = templates_from_catalog()
        local elite = { elite = true, name = "chaos_warrior" }
        local a, ra = Policy.enhancements_for_spawn(42, elite, 4, templates)
        local b, rb = Policy.enhancements_for_spawn(42, elite, 4, templates)
        H.equal(ra, rb)
        H.deep_equal(a, b)
        H.equal(Policy.enhancements_for_spawn(42, elite, 0, templates), nil)
        H.equal(Policy.enhancements_for_spawn(42, elite, 4, templates, 0), nil, "step 0 disables")
        local hits = 0
        for index = 1, 400 do
            if Policy.enhancements_for_spawn(index, elite, 4, templates, 25) then
                hits = hits + 1
            end
            local expected = Policy.would_apply(index, elite.name, 4)
            local list = Policy.enhancements_for_spawn(index, elite, 4, templates)
            H.equal(list ~= nil, expected, "spawn " .. index)
            local pick = Policy.recipe_index(index, elite.name)
            H.equal(pick >= 1 and pick <= 2, true)
            if list then
                H.equal(list[2].name, Policy.ELITE_RECIPES[pick])
            end
            H.equal(Policy.enhancements_for_spawn(index, { special = true, name = "s" }, 4,
                templates, 25), nil, "special at 100 percent")
        end
        H.equal(hits, 400, "step 25 at depth 4 is 100 percent")
        H.equal(Policy.bucket(7, "chaos_warrior"), Policy.hash(7, "chaos_warrior") % 100)
    end)

    H.test("CT #323 grudge name index stays inside vanilla's 1..16384 draw and is deterministic", function()
        H.equal(Policy.NAME_INDEX_RANGE, 16384)
        for index = 1, 500 do
            for _, name in ipairs({ "chaos_warrior", "skaven_storm_vermin", "beastmen_bestigor" }) do
                local value = Policy.name_index(index, name)
                H.equal(value >= 1 and value <= 16384, true, name .. " " .. index)
                H.equal(value, Policy.name_index(index, name))
                H.equal(value, Policy.hash(index, name) % 16384 + 1)
            end
        end
    end)

    H.test("CT #323 sequential spawn ids spread evenly across every elite breed", function()
        -- Each breed name is hashed with the id, so interleaved spawns of one
        -- breed must still land on the requested rate instead of a bucket subset.
        local breeds = {
            "chaos_warrior", "chaos_raider", "chaos_berzerker", "chaos_bulwark",
            "skaven_storm_vermin", "skaven_storm_vermin_commander",
            "skaven_storm_vermin_with_shield", "skaven_plague_monk", "beastmen_bestigor",
        }
        for _, name in ipairs(breeds) do
            local distinct, hits, picks = {}, 0, { 0, 0 }
            for index = 1, 2000 do
                distinct[Policy.bucket(index, name)] = true
                if Policy.would_apply(index, name, 4) then hits = hits + 1 end
                local pick = Policy.recipe_index(index, name)
                picks[pick] = picks[pick] + 1
            end
            local count = 0
            for _ in pairs(distinct) do count = count + 1 end
            H.equal(count, 100, name .. " visits every bucket")
            H.equal(hits >= 360 and hits <= 440, true, name .. " 20 percent rate: " .. hits)
            H.equal(picks[1] >= 900 and picks[2] >= 900, true, name .. " recipe split")
        end
    end)
end
