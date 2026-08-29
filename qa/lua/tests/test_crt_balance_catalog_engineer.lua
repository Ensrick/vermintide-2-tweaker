return function(H, repo_root)
    local base = repo_root .. "/career_tweaker/scripts/mods/career_tweaker/"
    local build = assert(loadfile(base .. "_crt_balance_catalog_engineer.lua"))()
    local perk_module = "scripts/unit_extensions/default_player_unit/buffs/settings/buff_perk_names"

    local function definitions(make_stub)
        return build({
            make_stub = make_stub or function()
                return { _crt_pending = true }
            end,
        })
    end

    local function with_engine_globals(body, preload)
        local saved = {
            BuffTemplates = rawget(_G, "BuffTemplates"),
            AttackTypes = rawget(_G, "AttackTypes"),
            Talents = rawget(_G, "Talents"),
            TalentIDLookup = rawget(_G, "TalentIDLookup"),
            loaded = package.loaded[perk_module],
            preload = package.preload[perk_module],
        }

        package.loaded[perk_module] = nil
        package.preload[perk_module] = preload or function()
            return { guaranteed_crit = "guaranteed_crit" }
        end

        local ok, err = xpcall(body, debug.traceback)

        _G.BuffTemplates = saved.BuffTemplates
        _G.AttackTypes = saved.AttackTypes
        _G.Talents = saved.Talents
        _G.TalentIDLookup = saved.TalentIDLookup
        package.loaded[perk_module] = saved.loaded
        package.preload[perk_module] = saved.preload

        if not ok then
            error(err, 0)
        end
    end

    local function engineer_talents()
        local original_buffs = { "bardin_engineer_2_1_cooldown" }
        local original_values = { { value = 80 } }
        local talent = {
            buffs = original_buffs,
            icon = "original_icon",
            description = "original_description",
            description_values = original_values,
        }
        _G.Talents = { dwarf_ranger = { [1] = talent } }
        _G.TalentIDLookup = {
            bardin_engineer_improved_explosives = {
                hero_name = "dwarf_ranger",
                talent_id = 1,
            },
        }
        return talent, original_buffs, original_values
    end

    H.test("CRT Engineer catalogue validates its only injected dependency", function()
        local ok, err = pcall(build, nil)
        H.equal(ok, false)
        H.truthy(tostring(err):find("context required", 1, true))

        ok, err = pcall(build, {})
        H.equal(ok, false)
        H.truthy(tostring(err):find("make_stub required", 1, true))
    end)

    H.test("CRT Engineer catalogue returns exactly the three moved definitions", function()
        local defs = definitions()
        local count = 0
        for _ in pairs(defs) do
            count = count + 1
        end
        H.equal(count, 3)

        local ordnance = assert(defs.rework_dr_engineer_ingenious_ordnance_240s)
        H.equal(ordnance.character, "bardin")
        H.equal(ordnance.career, "dr_engineer")
        H.deep_equal(ordnance.patches, {
            { buff = "bardin_engineer_2_1_cooldown", field = "duration", value = 240 },
        })

        local leading = assert(defs.rework_dr_engineer_leading_shots)
        H.equal(leading.character, "bardin")
        H.equal(leading.career, "dr_engineer")
        H.deep_equal(leading.patches, {})
        H.equal(type(leading.custom_apply), "function")
        H.equal(type(leading.custom_restore), "function")

        local steam = assert(defs.rework_dr_engineer_full_head_of_steam_4pct)
        H.equal(steam.character, "bardin")
        H.equal(steam.career, "dr_engineer")
        H.deep_equal(steam.patches, {
            { buff = "bardin_engineer_4_1_buff", field = "multiplier", value = 0.04 },
        })
    end)

    H.test("CRT Leading Shots preserves apply and restore behavior", function()
        with_engine_globals(function()
            local stub_count = 0
            local defs = definitions(function()
                stub_count = stub_count + 1
                return { _crt_pending = true, stub_id = stub_count }
            end)
            local leading = defs.rework_dr_engineer_leading_shots
            local talent, original_buffs, original_values = engineer_talents()
            _G.BuffTemplates = {}
            _G.AttackTypes = {
                projectile = "projectile",
                instant_projectile = "instant_projectile",
                heavy_instant_projectile = "heavy_instant_projectile",
            }

            local saved = {}
            leading.custom_apply(saved)

            local counter = assert(BuffTemplates.crt_engineer_leading_shots_counter).buffs[1]
            H.equal(counter.buff_to_add, "crt_engineer_leading_shots_accumulator")
            H.equal(counter.valid_attack_types.projectile, true)
            H.equal(counter.valid_attack_types.instant_projectile, true)
            H.equal(counter.valid_attack_types.heavy_instant_projectile, true)
            H.equal(assert(BuffTemplates.crt_engineer_leading_shots_accumulator).buffs[1].max_stacks, 4)
            H.equal(
                assert(BuffTemplates.crt_engineer_leading_shots_crit).buffs[1].perks[1],
                "guaranteed_crit")
            H.deep_equal(talent.buffs, { "crt_engineer_leading_shots_counter" })
            H.equal(talent.icon, "bardin_engineer_ranged_crit_count")
            H.equal(talent.display_name, "crt_engineer_leading_shots_name")
            H.equal(talent.description, "crt_engineer_leading_shots_desc")
            H.deep_equal(talent.description_values, { { value = 4 } })

            leading.custom_restore(saved)

            H.equal(talent.buffs, original_buffs)
            H.equal(talent.icon, "original_icon")
            H.equal(talent.display_name, nil)
            H.equal(talent.description, "original_description")
            H.equal(talent.description_values, original_values)
            H.equal(BuffTemplates.crt_engineer_leading_shots_counter.stub_id, 1)
            H.equal(BuffTemplates.crt_engineer_leading_shots_accumulator.stub_id, 2)
            H.equal(BuffTemplates.crt_engineer_leading_shots_crit.stub_id, 3)
            H.equal(stub_count, 3)
        end)
    end)

    H.test("CRT Leading Shots leaves pre-existing buff templates owned by their registrar", function()
        with_engine_globals(function()
            local defs = definitions(function()
                error("restore stub must not run for pre-existing templates")
            end)
            local leading = defs.rework_dr_engineer_leading_shots
            local talent = engineer_talents()
            _G.AttackTypes = {
                projectile = "projectile",
                instant_projectile = "instant_projectile",
                heavy_instant_projectile = "heavy_instant_projectile",
            }
            local counter = { buffs = { { name = "existing_counter" } } }
            local accumulator = { buffs = { { name = "existing_accumulator" } } }
            local crit = { buffs = { { name = "existing_crit" } } }
            _G.BuffTemplates = {
                crt_engineer_leading_shots_counter = counter,
                crt_engineer_leading_shots_accumulator = accumulator,
                crt_engineer_leading_shots_crit = crit,
            }

            local saved = {}
            leading.custom_apply(saved)
            leading.custom_restore(saved)

            H.equal(BuffTemplates.crt_engineer_leading_shots_counter, counter)
            H.equal(BuffTemplates.crt_engineer_leading_shots_accumulator, accumulator)
            H.equal(BuffTemplates.crt_engineer_leading_shots_crit, crit)
            H.equal(talent.icon, "original_icon")
        end)
    end)

    H.test("CRT Leading Shots restores only missing or pending template rows", function()
        with_engine_globals(function()
            local stub_count = 0
            local defs = definitions(function()
                stub_count = stub_count + 1
                return { _crt_pending = true, stub_id = stub_count }
            end)
            local leading = defs.rework_dr_engineer_leading_shots
            engineer_talents()
            _G.AttackTypes = {
                projectile = "projectile",
                instant_projectile = "instant_projectile",
                heavy_instant_projectile = "heavy_instant_projectile",
            }
            local existing_counter = { buffs = { { name = "existing_counter" } } }
            _G.BuffTemplates = {
                crt_engineer_leading_shots_counter = existing_counter,
                crt_engineer_leading_shots_accumulator = { _crt_pending = true },
            }

            local saved = {}
            leading.custom_apply(saved)
            H.equal(BuffTemplates.crt_engineer_leading_shots_counter, existing_counter)
            H.equal(saved.ls_created_crt_engineer_leading_shots_counter, nil)
            H.equal(saved.ls_created_crt_engineer_leading_shots_accumulator, true)
            H.equal(saved.ls_created_crt_engineer_leading_shots_crit, true)

            leading.custom_restore(saved)
            H.equal(BuffTemplates.crt_engineer_leading_shots_counter, existing_counter)
            H.equal(BuffTemplates.crt_engineer_leading_shots_accumulator.stub_id, 1)
            H.equal(BuffTemplates.crt_engineer_leading_shots_crit.stub_id, 2)
            H.equal(stub_count, 2)
        end)
    end)

    H.test("CRT Leading Shots missing globals and throwing perk load do not leak mutations", function()
        with_engine_globals(function()
            local leading = definitions().rework_dr_engineer_leading_shots
            local talent, original_buffs, original_values = engineer_talents()
            local templates = { untouched = {} }
            _G.BuffTemplates = templates
            _G.AttackTypes = nil

            local saved = {}
            leading.custom_apply(saved)
            H.equal(_G.BuffTemplates, templates)
            H.equal(talent.buffs, original_buffs)
            H.equal(talent.description_values, original_values)
            H.deep_equal(saved, {})
        end)

        local marker = {}
        with_engine_globals(function()
            local leading = definitions().rework_dr_engineer_leading_shots
            local talent, original_buffs, original_values = engineer_talents()
            local templates = { untouched = {} }
            _G.BuffTemplates = templates
            _G.AttackTypes = { projectile = "projectile" }
            local saved = {}

            local ok, err = pcall(leading.custom_apply, saved)
            H.equal(ok, false)
            H.equal(err, marker)
            H.equal(_G.BuffTemplates, templates)
            H.equal(talent.buffs, original_buffs)
            H.equal(talent.description_values, original_values)
            H.deep_equal(saved, {})
        end, function()
            error(marker)
        end)
    end)

    H.test("CRT Full Head of Steam rewrites and restores every matching tooltip value", function()
        with_engine_globals(function()
            local steam = definitions().rework_dr_engineer_full_head_of_steam_4pct
            local values = {
                { value = 0.15 },
                { value = 3 },
                { value = 0.15 },
            }
            _G.Talents = { dwarf_ranger = { [7] = { description_values = values } } }
            _G.TalentIDLookup = {
                bardin_engineer_power_on_max_pump = {
                    hero_name = "dwarf_ranger",
                    talent_id = 7,
                },
            }

            local saved = {}
            steam.custom_apply(saved)
            H.equal(values[1].value, 0.04)
            H.equal(values[2].value, 3)
            H.equal(values[3].value, 0.04)
            H.equal(saved.fhos_dv_1, 0.15)
            H.equal(saved.fhos_dv_3, 0.15)

            steam.custom_restore(saved)
            H.equal(values[1].value, 0.15)
            H.equal(values[2].value, 3)
            H.equal(values[3].value, 0.15)
            H.equal(saved.fhos_dv_1, nil)
            H.equal(saved.fhos_dv_3, nil)
        end)
    end)
end
