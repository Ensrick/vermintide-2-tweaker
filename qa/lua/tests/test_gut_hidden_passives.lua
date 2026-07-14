return function(H, repo_root)
    local path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_hidden_passive_policy.lua"
    local Policy = assert(loadfile(path))()

    H.test("GUT #153 resolves both source-backed WHC hidden passives", function()
        local entries = Policy.entries("wh_captain", {
            attributes = { base_critical_strike_chance = 0.1 },
        }, {
            buffs = { "victor_witchhunter_headshot_multiplier_increase" },
        })
        H.equal(#entries, 2)
        H.equal(entries[1].id, "whc_headshot_multiplier")
        H.equal(entries[2].id, "whc_base_crit")
    end)

    H.test("GUT #153 fails closed when source signatures drift", function()
        local entries = Policy.entries("wh_captain", {
            attributes = { base_critical_strike_chance = 0.05 },
        }, { buffs = {} })
        H.equal(#entries, 0)
        H.equal(#Policy.entries("es_mercenary", {}, {}), 0)
    end)

    H.test("GUT #153 description append is bounded and idempotent", function()
        local entries = {
            { title_key = "title", description_key = "description" },
        }
        local function loc(key) return "loc:" .. key end
        local once = Policy.append_description("base", "Innate Perks", entries, loc)
        local twice = Policy.append_description(once, "Innate Perks", entries, loc)
        H.truthy(string.find(once, "\nInnate Perks\n", 1, true) ~= nil)
        H.truthy(string.find(once, "loc:title — loc:description", 1, true) ~= nil)
        H.equal(twice, once)
    end)

    H.test("GUT #153 audit remains deterministic", function()
        local result = Policy.inspect({
            { name = "wh_captain", attributes = { base_critical_strike_chance = 0.1 } },
            { name = "es_mercenary" },
        }, {
            wh_captain = {
                buffs = { "victor_witchhunter_headshot_multiplier_increase" },
                perks = { {}, {} },
            },
            es_mercenary = { buffs = {}, perks = { {} } },
        })
        H.equal(result.career_count, 2)
        H.equal(result.catalogued_count, 1)
        H.equal(result.records[1].name, "es_mercenary")
        H.equal(result.records[2].hidden_count, 2)
    end)
end
