return function(H, repo_root)
    local path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_hidden_passive_policy.lua"
    local Policy = assert(loadfile(path))()

    local function read(file_path)
        local file = assert(io.open(file_path, "rb"))
        local value = file:read("*a")
        file:close()
        return value
    end

    local runtime_path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_hidden_passives.lua"
    local localization_path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/gui_tweaker_dev_localization.lua"

    local function with_runtime_wrapper(run)
        local saved = {
            get_mod = get_mod,
            FindProfileIndex = FindProfileIndex,
            CareerUtils = CareerUtils,
            SPProfiles = SPProfiles,
            HeroWindowTalents = HeroWindowTalents,
            HeroWindowTalentsConsole = HeroWindowTalentsConsole,
        }
        local native_a = { display_name = "native_a", description = "native_a_desc" }
        local native_b = { display_name = "native_b", description = "native_b_desc" }
        local original = { native_a, native_b }
        local passive = {
            buffs = { "victor_witchhunter_headshot_multiplier_increase" },
            perks = original,
        }
        local career = {
            name = "wh_captain",
            attributes = { base_critical_strike_chance = 0.1 },
            passive_ability = passive,
        }
        local pc_class = { _populate_career_info = function() end }
        local console_class = { _populate_career_info = function() end }
        local wrappers = {}
        local fake_mod = {}

        function fake_mod:dofile(path)
            local full_path = repo_root .. "/gui_tweaker_dev/" .. path .. ".lua"
            return assert(loadfile(full_path))()
        end

        function fake_mod:hook(class, method, wrapper)
            H.equal(method, "_populate_career_info")
            wrappers[class] = wrapper
        end

        function fake_mod:get()
            return true
        end

        function fake_mod:command()
        end

        function fake_mod:info()
        end

        get_mod = function()
            return fake_mod
        end
        FindProfileIndex = function()
            return 1
        end
        CareerUtils = {
            get_passive_ability_by_career = function(settings)
                return settings.passive_ability
            end,
        }
        SPProfiles = { { careers = { career } } }
        HeroWindowTalents = pc_class
        HeroWindowTalentsConsole = console_class

        local loaded, load_error = pcall(function()
            return assert(loadfile(runtime_path))()
        end)
        local ok, run_error
        if loaded then
            ok, run_error = pcall(run, {
                pc = wrappers[pc_class],
                console = wrappers[console_class],
                self = { hero_name = "witch_hunter", career_index = 1 },
                passive = passive,
                original = original,
                native_a = native_a,
                native_b = native_b,
            })
        end

        get_mod = saved.get_mod
        FindProfileIndex = saved.FindProfileIndex
        CareerUtils = saved.CareerUtils
        SPProfiles = saved.SPProfiles
        HeroWindowTalents = saved.HeroWindowTalents
        HeroWindowTalentsConsole = saved.HeroWindowTalentsConsole

        if not loaded then
            error(load_error)
        end
        if not ok then
            error(run_error)
        end
    end

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

    H.test("GUT #153 presentation rows use the native Perks collection", function()
        local native_a, native_b = { display_name = "a" }, { display_name = "b" }
        local native = { native_a, native_b }
        local entries = {
            { title_key = "title", description_key = "description" },
            { title_key = "title_2", description_key = "description_2" },
        }
        local rows = Policy.presentation_perks(native, entries, 6, {})
        H.equal(#rows, 4)
        H.equal(rows[1], native_a)
        H.equal(rows[2], native_b)
        H.equal(rows[3].display_name, "title")
        H.equal(rows[4].description, "description_2")
        H.equal(#native, 2, "the gameplay-owned passive list must remain unchanged")
    end)

    H.test("GUT #153 compact PC layout combines overflow without dropping either bonus", function()
        local rows = Policy.presentation_perks({ {}, {} }, {
            { title_key = "one", description_key = "one_desc" },
            { title_key = "two", description_key = "two_desc" },
        }, 3, { title_key = "combined", description_key = "combined_desc" })
        H.equal(#rows, 3)
        H.equal(rows[3].display_name, "combined")
        H.equal(rows[3].description, "combined_desc")
        H.equal(rows[3]._gut_hidden_passive, true)
    end)

    H.test("GUT #153 production source never writes passive description", function()
        local source = read(runtime_path)
        H.equal(string.find(source, "passive_description_text", 1, true), nil)
        H.truthy(string.find(source, "passive.perks = Policy.presentation_perks", 1, true))
        H.truthy(string.find(source, "passive.perks = original", 1, true))
        H.truthy(string.find(source, "pcall(func, self", 1, true))
    end)

    H.test("GUT #153 production wrapper presents ordered rows and restores after success", function()
        with_runtime_wrapper(function(fixture)
            local seen
            local result = fixture.console(function(self)
                H.equal(self, fixture.self)
                seen = fixture.passive.perks
                H.equal(seen[1], fixture.native_a)
                H.equal(seen[2], fixture.native_b)
                H.equal(seen[3].display_name, "gut_hidden_passive_whc_headshot_name")
                H.equal(seen[4].display_name, "gut_hidden_passive_whc_crit_name")
                H.equal(seen[3]._gut_hidden_passive, true)
                H.equal(seen[4]._gut_hidden_passive, true)
                return "vanilla-result"
            end, fixture.self)
            H.equal(result, "vanilla-result")
            H.equal(fixture.passive.perks, fixture.original)
            H.equal(#fixture.original, 2)
            H.truthy(seen ~= fixture.original)
        end)
    end)

    H.test("GUT #153 production wrapper restores before propagating an error", function()
        with_runtime_wrapper(function(fixture)
            local inside_rows
            local ok, err = pcall(fixture.console, function()
                inside_rows = fixture.passive.perks
                error("planted vanilla failure")
            end, fixture.self)
            H.equal(ok, false)
            H.truthy(string.find(tostring(err), "planted vanilla failure", 1, true))
            H.equal(#inside_rows, 4)
            H.equal(fixture.passive.perks, fixture.original)
            H.equal(#fixture.original, 2)
        end)
    end)

    H.test("GUT #153 repeated production calls remain idempotent", function()
        with_runtime_wrapper(function(fixture)
            local observed = {}
            for call = 1, 2 do
                fixture.console(function()
                    local rows = fixture.passive.perks
                    observed[call] = {
                        count = #rows,
                        first_hidden = rows[3].display_name,
                        second_hidden = rows[4].display_name,
                    }
                end, fixture.self)
                H.equal(fixture.passive.perks, fixture.original)
                H.equal(#fixture.original, 2)
            end
            H.equal(observed[1].count, 4)
            H.equal(observed[2].count, 4)
            H.equal(observed[1].first_hidden, observed[2].first_hidden)
            H.equal(observed[1].second_hidden, observed[2].second_hidden)
        end)
    end)

    H.test("GUT #153 exact English identities and descriptions stay pinned", function()
        local localization = assert(loadfile(localization_path))()
        H.equal(localization.gut_hidden_passive_whc_headshot_name.en, "Power of Sigmar")
        H.equal(localization.gut_hidden_passive_whc_headshot_desc.en,
            "+25%% headshot damage.")
        H.equal(localization.gut_hidden_passive_whc_crit_name.en, "Sigmar's Charm")
        H.equal(localization.gut_hidden_passive_whc_crit_desc.en,
            "+5%% base critical-strike chance.")
        H.equal(localization.gut_hidden_passive_whc_combined_name.en,
            "Power of Sigmar & Sigmar's Charm")
        H.equal(localization.gut_hidden_passive_whc_combined_desc.en,
            "+25%% headshot damage and +5%% base critical-strike chance.")
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
