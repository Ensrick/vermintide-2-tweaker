local register_runtime = require("test_wt_history_runtime")

local function register(H, repo_root)
    local script_root = repo_root
        .. "/weapon_tweaker/scripts/mods/weapon_tweaker/"
    local Policy = assert(loadfile(script_root .. "_wt_history_policy.lua"))()
    local Runtime = assert(loadfile(script_root .. "_wt_history_runtime.lua"))()
    local HistoryOwner = assert(loadfile(script_root .. "_wt_history_owner.lua"))()
    local CatalogUI = assert(loadfile(script_root .. "_wt_history_catalog.lua"))()
    local AxeBalance = assert(loadfile(script_root .. "_wt_axe_balance.lua"))()

    local HASH_A = string.rep("a", 40)
    local HASH_B = string.rep("b", 40)
    local HASH_C = string.rep("c", 40)

    local function read_file(path)
        local file = assert(io.open(path, "rb"))
        local content = file:read("*a")
        file:close()
        return content
    end

    local function count_plain(source, needle)
        local count, cursor = 0, 1
        while true do
            local at = source:find(needle, cursor, true)
            if not at then return count end
            count = count + 1
            cursor = at + #needle
        end
    end

    local function clone(value, seen)
        if type(value) ~= "table" then return value end
        seen = seen or {}
        if seen[value] then return seen[value] end
        local copy = {}
        seen[value] = copy
        for key, child in pairs(value) do
            copy[clone(key, seen)] = clone(child, seen)
        end
        return copy
    end

    local function operation(path, expected, result)
        return {
            change_class = "official_weapon_balance",
            current_source_blob = HASH_C,
            expected_current = expected,
            expected_present = true,
            family_id = "elf_one_handed_axe",
            official_change_id = "P520-ELF1HA-MOVESET",
            official_summary = "Synthetic source-exact test operation.",
            path = path,
            result = result,
            result_present = true,
            root = "Weapons",
            source_blob = HASH_B,
            source_path = "scripts/settings/equipment/weapon_templates/1h_axes_wood_elf.lua",
            source_revision = HASH_A,
            state_id = "5_1_1",
            template = "we_1h_axe_template_1",
        }
    end

    local function catalog_fixture()
        local expected_tuning = { attack_speed = 1, cleave = { 1, 2 } }
        local historical_tuning = { attack_speed = 0.8, cleave = { 2, 3 } }
        local historical_profile = {
            default_target = { power_distribution = { attack = 5, impact = 2 } },
            targets = {
                { power_distribution = { attack = 6, impact = 3 } },
            },
        }
        return {
            catalog_id = "wt_history_test_v1",
            current_id = "current",
            current_source = {
                display_name = "Current (Test)",
                label = "current test anchor",
                revision = HASH_C,
            },
            derived_profiles = {},
            families = {
                {
                    display_name = "Kerillian's One-handed Axe",
                    id = "elf_one_handed_axe",
                    label_key = "wt_history_family_elf_one_handed_axe",
                    setting_id = "wt_history_elf_one_handed_axe",
                    state_order = { "5_1_1" },
                    states = {
                        ["5_1_1"] = {
                            atomic_group = "P520-ELF1HA-MOVESET",
                            direct_profile_names = { "native_profile" },
                            operations = {
                                operation({ "stats", "tuning" },
                                    expected_tuning, historical_tuning),
                                operation({ "stats", "tempo" }, 10, 8),
                            },
                            profile_names = { "native_profile" },
                        },
                    },
                    templates = { "we_1h_axe_template_1" },
                },
            },
            profile_specs = {
                ["5_1_1"] = {
                    native_profile = {
                        change_class = "official_weapon_balance",
                        current_source_blob = HASH_C,
                        historical_profile = historical_profile,
                        native_name = "native_profile",
                        official_change_id = "P520-ELF1HA-MOVESET",
                        official_summary = "Synthetic source-exact test profile.",
                        private_name = "wt_hist_5_1_1_native_profile",
                        source_blob = HASH_B,
                        source_path = "scripts/settings/equipment/damage_profile_templates.lua",
                        source_revision = HASH_A,
                        state_id = "5_1_1",
                    },
                },
            },
            schema = 2,
            states = {
                ["5_1_1"] = {
                    change_class = "official_weapon_balance",
                    display_name = "Game Version 5.1.1",
                    label_key = "wt_history_state_5_1_1",
                    official_patch_notes = "https://example.invalid/patch-5-2",
                    source_revision = HASH_A,
                },
            },
        }
    end

    local function roots_fixture()
        local original_tuning = { attack_speed = 1, cleave = { 1, 2 } }
        local roots = {
            BuffTemplates = {},
            ExplosionTemplates = {},
            PlayerUnitStatusSettings = {},
            VortexTemplates = {},
            Weapons = {
                we_1h_axe_template_1 = {
                    actions = {
                        action_one = {
                            default = { damage_profile = "native_profile" },
                        },
                    },
                    stats = { tempo = 10, tuning = original_tuning },
                },
            },
        }
        return roots, original_tuning
    end

    local function deepwood_roots_fixture(values)
        values = values or {}
        local life_priorities = {
            chaos_bulwark = values.staff_life or 1,
            chaos_tether_sorcerer = 1,
            chaos_warrior = 1,
        }
        local versus_priorities = {
            chaos_bulwark = values.staff_life_vs or 1,
            chaos_tether_sorcerer = 1,
            chaos_warrior = 1,
        }
        local vortex_reductions = {
            chaos_bulwark = values.vortex or 0.5,
            chaos_warrior = 0.5,
        }
        local life_metadata = { marker = "life sibling" }
        local versus_metadata = { marker = "versus sibling" }
        local vortex_metadata = { marker = "vortex sibling" }
        local roots = {
            BuffTemplates = {},
            ExplosionTemplates = {},
            PlayerUnitStatusSettings = {},
            VortexTemplates = {
                spirit_storm = {
                    metadata = vortex_metadata,
                    reduce_duration_per_breed = vortex_reductions,
                    time_of_life = { 8, 8 },
                },
            },
            Weapons = {
                staff_life = {
                    actions = { action_two = { default = {
                        prioritized_breeds = life_priorities,
                    } } },
                    metadata = life_metadata,
                },
                staff_life_vs = {
                    actions = { action_two = { default = {
                        prioritized_breeds = versus_priorities,
                    } } },
                    metadata = versus_metadata,
                },
            },
        }
        return roots, {
            life_metadata = life_metadata,
            life_priorities = life_priorities,
            versus_metadata = versus_metadata,
            versus_priorities = versus_priorities,
            vortex_metadata = vortex_metadata,
            vortex_reductions = vortex_reductions,
        }
    end

    local function lookup_fixture()
        return { [1] = "native_profile", native_profile = 1 }
    end

    local function with_profile_globals(body)
        local prior_profiles = rawget(_G, "DamageProfileTemplates")
        local prior_lookup = rawget(_G, "NetworkLookup")
        local prior_printf = rawget(_G, "printf")
        local native = {
            default_target = { power_distribution = { attack = 3, impact = 1 } },
            targets = {},
        }
        rawset(_G, "DamageProfileTemplates", { native_profile = native })
        rawset(_G, "NetworkLookup", { damage_profiles = lookup_fixture() })
        rawset(_G, "printf", function() end)
        local outcome = { xpcall(function() return body(native) end, debug.traceback) }
        rawset(_G, "DamageProfileTemplates", prior_profiles)
        rawset(_G, "NetworkLookup", prior_lookup)
        rawset(_G, "printf", prior_printf)
        if not outcome[1] then error(outcome[2], 0) end
        return unpack(outcome, 2)
    end

    local function with_named_profile_globals(profiles, body)
        local prior_profiles = rawget(_G, "DamageProfileTemplates")
        local prior_lookup = rawget(_G, "NetworkLookup")
        local prior_printf = rawget(_G, "printf")
        local names = {}
        for name in pairs(profiles) do names[#names + 1] = name end
        table.sort(names)
        local lookup = {}
        for index, name in ipairs(names) do
            lookup[index], lookup[name] = name, index
        end
        rawset(_G, "DamageProfileTemplates", profiles)
        rawset(_G, "NetworkLookup", { damage_profiles = lookup })
        rawset(_G, "printf", function() end)
        local outcome = { xpcall(body, debug.traceback) }
        rawset(_G, "DamageProfileTemplates", prior_profiles)
        rawset(_G, "NetworkLookup", prior_lookup)
        rawset(_G, "printf", prior_printf)
        if not outcome[1] then error(outcome[2], 0) end
        return unpack(outcome, 2)
    end

    local function mod_fixture(selections, parity)
        local mod = { selections = selections or {}, records = {} }
        function mod:get(setting_id) return self.selections[setting_id] end
        function mod:info(format, ...)
            self.records[#self.records + 1] = string.format(format, ...)
        end
        mod._wt431_profiles_allowed = function() return parity.value == true end
        return mod
    end

    local function locate_operation(roots, row)
        local parent = roots[row.root]
        if row.root == "Weapons" then parent = parent[row.template] end
        for index = 1, #row.path - 1 do parent = parent[row.path[index]] end
        return parent, row.path[#row.path]
    end

    local function materialize_expected_roots(state)
        local roots = {
            BuffTemplates = {}, ExplosionTemplates = {},
            PlayerUnitStatusSettings = {}, VortexTemplates = {}, Weapons = {},
        }
        local originals = {}
        for index, row in ipairs(state.operations) do
            local parent = roots[row.root]
            if row.root == "Weapons" then
                parent[row.template] = parent[row.template] or {}
                parent = parent[row.template]
            end
            for path_index = 1, #row.path - 1 do
                local key = row.path[path_index]
                parent[key] = parent[key] or {}
                parent = parent[key]
            end
            local key = row.path[#row.path]
            local value
            if row.expected_present then value = clone(row.expected_current) end
            parent[key] = value
            originals[index] = { key = key, parent = parent, value = value }
        end
        return roots, originals
    end

    local function generated_catalogs(catalog_ui, root)
        local by_path = {}
        for _, path in ipairs(catalog_ui.GENERATED_MODULES) do
            local filename = assert(path:match("([^/]+)$")) .. ".lua"
            by_path[path] = assert(loadfile(root .. filename))()
        end
        local ledger_path = catalog_ui.COMPLETENESS_LEDGER_MODULE
        local ledger_filename = assert(ledger_path:match("([^/]+)$")) .. ".lua"
        by_path[ledger_path] = assert(loadfile(root .. ledger_filename))()
        return by_path
    end

    local function load_default_catalog(catalog_ui, root)
        local by_path = generated_catalogs(catalog_ui, root)
        local paths = {}
        local mod = {}
        function mod:dofile(path)
            paths[#paths + 1] = path
            return assert(by_path[path], "unexpected generated module " .. tostring(path))
        end
        local catalog, catalog_error = catalog_ui.load(mod)
        return assert(catalog, catalog_error), mod, paths
    end

    local function catalog_counts(catalog)
        local counts = {
            families = #catalog.families,
            family_states = 0,
            operations = 0,
            profiles = 0,
            derived_profiles = 0,
            states = 0,
        }
        for _ in pairs(catalog.states) do counts.states = counts.states + 1 end
        for _, family in ipairs(catalog.families) do
            for _, state_id in ipairs(family.state_order) do
                counts.family_states = counts.family_states + 1
                counts.operations = counts.operations
                    + #family.states[state_id].operations
            end
        end
        for _, specs in pairs(catalog.profile_specs) do
            for _ in pairs(specs) do counts.profiles = counts.profiles + 1 end
        end
        for _, specs in pairs(catalog.derived_profiles) do
            for _ in pairs(specs) do
                counts.derived_profiles = counts.derived_profiles + 1
            end
        end
        return counts
    end

    H.test("WT #1529 6.12.1 provenance refresh preserves the gameplay census", function()
        local by_path = generated_catalogs(CatalogUI, script_root)
        local totals = {
            catalogs = #CatalogUI.GENERATED_MODULES,
            families = 0,
            family_states = 0,
            operations = 0,
            states = 0,
        }
        local family_ids = {}
        local state_ids = {}
        for _, path in ipairs(CatalogUI.GENERATED_MODULES) do
            local catalog = assert(by_path[path])
            local valid, validation_error = Policy.validate(catalog)
            H.equal(validation_error, nil)
            H.equal(valid, true)
            H.equal(catalog.current_source.revision,
                "25fd7b8433e839b678d1c98a7a9af80918cbc252")
            H.equal(catalog.current_source.display_name,
                "Current (Game Version 6.12.1)")
            H.equal(catalog.current_source.label, "6.12.1 source anchor")
            local counts = catalog_counts(catalog)
            totals.family_states = totals.family_states + counts.family_states
            totals.operations = totals.operations + counts.operations
            for _, family in ipairs(catalog.families) do
                family_ids[family.id] = true
            end
            for state_id in pairs(catalog.states) do state_ids[state_id] = true end
        end
        for _ in pairs(family_ids) do totals.families = totals.families + 1 end
        for _ in pairs(state_ids) do totals.states = totals.states + 1 end

        H.deep_equal(totals, {
            catalogs = 13,
            families = 26,
            family_states = 38,
            operations = 236,
            states = 15,
        })
        local ledger = assert(by_path[CatalogUI.COMPLETENESS_LEDGER_MODULE])
        H.equal(ledger.current_revision,
            "25fd7b8433e839b678d1c98a7a9af80918cbc252")
        H.deep_equal(ledger.totals, totals,
            "provenance refresh must not alter the pinned gameplay census")
    end)

    H.test("WT #1436 generated Patch 5.2 catalog passes strict schema validation", function()
        local catalog = assert(loadfile(script_root .. "_wt_history_5_2_catalog.lua"))()
        local valid, validation_error = Policy.validate(catalog)
        H.equal(validation_error, nil)
        H.equal(valid, true)
        H.equal(catalog.schema, 2)
        H.equal(#catalog.families, 14)
    end)

    H.test("WT #1436 generated Patch 6.0 catalog is an exact 11-plus-1 slice", function()
        local catalog = assert(loadfile(script_root .. "_wt_history_6_0_catalog.lua"))()
        local valid, validation_error = Policy.validate(catalog)
        H.equal(validation_error, nil)
        H.equal(valid, true)
        H.equal(catalog.catalog_id, "wt_history_patch_6_0_v1")
        H.equal(catalog.current_source.revision,
            "25fd7b8433e839b678d1c98a7a9af80918cbc252")
        H.equal(#catalog.families, 3)
        H.equal(next(catalog.derived_profiles), nil)
        H.deep_equal(catalog.generation, {
            adjacent_operation_count = 11,
            global_operations = 0,
            profile_route_count = 1,
            unsupported_count = 0,
        })
        H.equal(catalog.states["5_6_1"].display_name, "Game Version 5.6.1")
        H.equal(catalog.states["5_6_1"].source_revision,
            "f64ecd2495bd26b1b0a4d296970bef0a0d7a06a9")
        H.equal(catalog.states["5_6_1"].official_patch_notes,
            "https://www.vermintide.com/news/versus-launch-patch-5-7-0")

        local by_id = {}
        for _, family in ipairs(catalog.families) do by_id[family.id] = family end
        local shield = assert(by_id.kruber_sword_and_shield)
        H.equal(shield.setting_id, "wt_history_kruber_sword_and_shield")
        H.deep_equal(shield.templates, { "one_handed_sword_shield_template_1" })
        H.equal(#shield.states["5_6_1"].operations, 5)
        local breton = assert(by_id.kruber_bretonnian_sword_and_shield)
        H.deep_equal(breton.templates, { "one_handed_sword_shield_template_2" })
        H.equal(#breton.states["5_6_1"].operations, 6)

        local expected = {
            damage_window_end = { current = 0.32, historical = 0.28 },
            damage_window_start = { current = 0.22, historical = 0.18 },
            dedicated_target_range = { current = 2.8, historical = 2.5 },
            range_mod = { current = { 1.3, 1.5 }, historical = 1.2 },
            range_mod_add = { current = { 0.2, 0.25 }, absent = true },
            sweep_z_offset = { current = -0.035, absent = true },
        }
        for family_index, family in ipairs({ shield, breton }) do
            local seen = {}
            for _, row in ipairs(family.states["5_6_1"].operations) do
                H.deep_equal({ row.path[1], row.path[2], row.path[3] }, {
                    "actions", "action_one", "light_attack_stab_postpush",
                })
                local leaf = row.path[4]
                local wanted = assert(expected[leaf])
                seen[leaf] = true
                local current = type(wanted.current) == "table"
                    and wanted.current[family_index] or wanted.current
                H.equal(row.expected_current, current)
                H.equal(row.expected_present, true)
                H.equal(row.result_present, not wanted.absent)
                H.equal(row.result, wanted.historical)
                H.equal(row.family_id, family.id)
                H.equal(row.state_id, "5_6_1")
                H.equal(row.change_class, "official_weapon_balance")
                H.equal(row.source_revision,
                    "f64ecd2495bd26b1b0a4d296970bef0a0d7a06a9")
            end
            H.equal(seen.sweep_z_offset == true, family_index == 2)
        end

        local fireball = assert(by_id.sienna_fireball_staff)
        H.deep_equal(fireball.templates, { "staff_fireball_fireball_template_1" })
        H.deep_equal(fireball.states["5_6_1"].operations, {})
        H.deep_equal(fireball.states["5_6_1"].profile_names,
            { "staff_fireball_charged" })
        H.deep_equal(fireball.states["5_6_1"].direct_profile_names,
            { "staff_fireball_charged" })
        local profile = catalog.profile_specs["5_6_1"].staff_fireball_charged
        H.equal(profile.private_name, "wt_hist_5_6_1_staff_fireball_charged")
        H.equal(profile.current_source_blob,
            "e8330328d0085f6aee09e0495ba88fdc0211d5aa")
        H.equal(profile.source_blob,
            "e5d56cfb8de366baf1a946f70566ea052688c969")
        H.equal(profile.historical_profile.armor_modifier.attack[5], 0.1)
        H.equal(profile.historical_profile.armor_modifier.attack[4], 1)
        H.equal(profile.historical_profile.armor_modifier.attack[6], 0)
        H.equal(read_file(script_root .. "_wt_history_6_0_catalog.lua"),
            read_file(repo_root
                .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/"
                .. "_wt_history_6_0_catalog.lua"),
            "public and dev must carry byte-identical pure Patch 6.0 data")
    end)

    H.test("WT #1436 Patch 4.6 Hagbane routes are atomic and parity gated", function()
        local catalog = assert(loadfile(script_root .. "_wt_history_4_6_catalog.lua"))()
        local family = catalog.families[1]
        local function roots(default_name, charged_name)
            return {
                BuffTemplates = {}, ExplosionTemplates = {},
                PlayerUnitStatusSettings = {}, VortexTemplates = {},
                Weapons = { shortbow_hagbane_template_1 = { actions = {
                    action_one = {
                        default = { impact_data = {
                            damage_profile = default_name,
                        } },
                        shoot_charged = { impact_data = {
                            damage_profile = charged_name,
                        } },
                    },
                } } },
            }
        end
        with_named_profile_globals({
            shortbow_hagbane = { marker = "native default" },
            shortbow_hagbane_charged = { marker = "native charged" },
        }, function()
            local parity = { value = true }
            local current_roots = roots(
                "shortbow_hagbane", "shortbow_hagbane_charged")
            local current_runtime = Runtime.install({
                catalog = catalog,
                mod = mod_fixture({}, parity),
                policy = Policy,
                roots = current_roots,
            })
            H.equal(current_runtime.fatal_error, nil)
            H.equal(#(current_runtime.ledgers[family.id] or {}), 0)
            H.equal(current_roots.Weapons.shortbow_hagbane_template_1.actions
                .action_one.default.impact_data.damage_profile,
                "shortbow_hagbane")

            local historical_roots = roots(
                "shortbow_hagbane", "shortbow_hagbane_charged")
            local historical_runtime = Runtime.install({
                catalog = catalog,
                mod = mod_fixture({
                    [family.setting_id] = "4_5_1",
                }, parity),
                policy = Policy,
                roots = historical_roots,
            })
            H.equal(historical_runtime.last_error, nil)
            H.equal(#historical_runtime.ledgers[family.id], 2)
            H.equal(historical_roots.Weapons.shortbow_hagbane_template_1.actions
                .action_one.default.impact_data.damage_profile,
                "wt_hist_4_5_1_shortbow_hagbane")
            H.equal(historical_roots.Weapons.shortbow_hagbane_template_1.actions
                .action_one.shoot_charged.impact_data.damage_profile,
                "wt_hist_4_5_1_shortbow_hagbane_charged")
            H.equal(historical_runtime:restore().refused, 0)
            H.equal(historical_roots.Weapons.shortbow_hagbane_template_1.actions
                .action_one.default.impact_data.damage_profile,
                "shortbow_hagbane")

            parity.value = false
            local mixed_roots = roots(
                "shortbow_hagbane", "shortbow_hagbane_charged")
            local mixed_runtime = Runtime.install({
                catalog = catalog,
                mod = mod_fixture({
                    [family.setting_id] = "4_5_1",
                }, parity),
                policy = Policy,
                roots = mixed_roots,
            })
            H.equal(mixed_runtime.last_error, nil)
            H.equal(#mixed_runtime.ledgers[family.id], 2)
            H.equal(mixed_roots.Weapons.shortbow_hagbane_template_1.actions
                .action_one.default.impact_data.damage_profile,
                "shortbow_hagbane",
                "mixed peers must receive the exact native fallback identity")
            H.equal(mixed_roots.Weapons.shortbow_hagbane_template_1.actions
                .action_one.shoot_charged.impact_data.damage_profile,
                "shortbow_hagbane_charged")

            parity.value = true
            local hostile_roots = roots("shortbow_hagbane", "unexpected_profile")
            local hostile_runtime = Runtime.install({
                catalog = catalog,
                mod = mod_fixture({
                    [family.setting_id] = "4_5_1",
                }, parity),
                policy = Policy,
                roots = hostile_roots,
            })
            H.truthy(hostile_runtime.last_error and hostile_runtime.last_error:find(
                "native profile route not found shortbow_hagbane_charged", 1, true))
            H.equal(#(hostile_runtime.ledgers[family.id] or {}), 0)
            H.equal(hostile_roots.Weapons.shortbow_hagbane_template_1.actions
                .action_one.default.impact_data.damage_profile,
                "shortbow_hagbane",
                "failed two-route preflight must commit no partial write")
        end)
    end)

    H.test("WT #1436 generated Patch 6.6 catalog pins one atomic Deepwood boundary", function()
        local catalog = assert(loadfile(script_root .. "_wt_history_6_6_catalog.lua"))()
        local valid, validation_error = Policy.validate(catalog)
        H.equal(validation_error, nil)
        H.equal(valid, true)
        H.equal(catalog.schema, 2)
        H.equal(catalog.catalog_id, "wt_history_patch_6_6_v1")
        H.equal(catalog.current_source.revision,
            "25fd7b8433e839b678d1c98a7a9af80918cbc252")
        H.equal(#catalog.families, 1)
        H.equal(next(catalog.profile_specs), nil)
        H.equal(next(catalog.derived_profiles), nil)

        local family = catalog.families[1]
        H.equal(family.id, "deepwood_staff")
        H.equal(family.setting_id, "wt_history_deepwood_staff")
        H.equal(family.authority, "server")
        H.deep_equal(family.templates, { "staff_life", "staff_life_vs" })
        H.deep_equal(family.state_order, { "6_5_4" })
        H.equal(catalog.states["6_5_4"].source_revision,
            "5a74a378502353b075cbe0c3abe37da07f1d9bc9")
        H.equal(catalog.states["6_5_4"].official_patch_notes,
            "https://forums.fatsharkgames.com/t/new-map-the-well-of-dreams-live-now-skulls-in-game-event-patch-6-6-0-hotfix-6-6-1/108063")

        local state = family.states["6_5_4"]
        H.equal(state.atomic_group, "P660-DEEPWOOD-BULWARK-LIFT")
        H.deep_equal(state.profile_names, {})
        H.deep_equal(state.direct_profile_names, {})
        H.equal(#state.operations, 3)
        H.deep_equal(state.operations[1].path, {
            "spirit_storm", "reduce_duration_per_breed", "chaos_bulwark",
        })
        H.equal(state.operations[1].root, "VortexTemplates")
        H.equal(state.operations[1].template, nil)
        H.equal(state.operations[1].expected_current, 0.5)
        H.equal(state.operations[1].source_blob,
            "bd140b12581c0621a82edd735ae9cf7903f54ddc")
        for index = 2, 3 do
            local row = state.operations[index]
            H.equal(row.root, "Weapons")
            H.equal(row.template, index == 2 and "staff_life" or "staff_life_vs")
            H.deep_equal(row.path, {
                "actions", "action_two", "default", "prioritized_breeds",
                "chaos_bulwark",
            })
            H.equal(row.expected_current, 1)
            H.equal(row.source_blob,
                "33b16c2f162cf43af0cc7e2451098fd50dc6b1e2")
        end
        for _, row in ipairs(state.operations) do
            H.equal(row.expected_present, true)
            H.equal(row.result_present, false)
            H.equal(rawget(row, "result"), nil)
            H.equal(row.family_id, family.id)
            H.equal(row.state_id, "6_5_4")
            H.equal(row.official_change_id, "P660-DEEPWOOD-BULWARK-LIFT")
            H.equal(row.change_class, "official_weapon_balance")
        end
        H.deep_equal(catalog.generation, {
            adjacent_operation_count = 3,
            global_operations = 1,
            profile_route_count = 0,
            unsupported_count = 0,
        })
        H.equal(read_file(script_root .. "_wt_history_6_6_catalog.lua"),
            read_file(repo_root
                .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/"
                .. "_wt_history_6_6_catalog.lua"),
            "public and dev must carry byte-identical pure Patch 6.6 data")
    end)

    H.test("WT #1436 generated Patch 6.8 catalog pins one exact Greatsword change", function()
        local catalog = assert(loadfile(script_root .. "_wt_history_6_8_catalog.lua"))()
        local valid, validation_error = Policy.validate(catalog)
        H.equal(validation_error, nil)
        H.equal(valid, true)
        H.equal(catalog.schema, 2)
        H.equal(catalog.catalog_id, "wt_history_patch_6_8_v1")
        H.equal(catalog.current_source.revision,
            "25fd7b8433e839b678d1c98a7a9af80918cbc252")
        H.equal(#catalog.families, 1)
        H.equal(next(catalog.profile_specs), nil)
        H.equal(next(catalog.derived_profiles), nil)

        local family = catalog.families[1]
        H.equal(family.id, "elf_greatsword")
        H.equal(family.setting_id, "wt_history_elf_greatsword")
        H.deep_equal(family.templates, { "two_handed_swords_wood_elf_template" })
        H.deep_equal(family.state_order, { "6_7_2" })
        H.equal(catalog.states["6_7_2"].source_revision,
            "b7c15fc61a3b34fae7d1e2de47f52198e26851ce")
        H.equal(catalog.states["6_7_2"].official_patch_notes,
            "https://forums.fatsharkgames.com/t/geheimnisnacht-and-the-skull-of-blosphoros-return-patch-6-8-0-hotfix-6-8-1/113884")

        local state = family.states["6_7_2"]
        H.deep_equal(state.profile_names, {})
        H.deep_equal(state.direct_profile_names, {})
        H.equal(#state.operations, 1)
        local row = state.operations[1]
        H.equal(row.root, "Weapons")
        H.equal(row.template, "two_handed_swords_wood_elf_template")
        H.deep_equal(row.path, {
            "actions", "action_one", "heavy_attack_down_first", "range_mod",
        })
        H.equal(row.expected_current, 1.55)
        H.equal(row.result, 1.45)
        H.equal(row.expected_present, true)
        H.equal(row.result_present, true)
        H.equal(row.family_id, family.id)
        H.equal(row.state_id, "6_7_2")
        H.equal(row.official_change_id, "P680-ELF-GS-H1-RANGE")
        H.equal(row.change_class, "official_weapon_balance")
        H.equal(row.source_revision,
            "b7c15fc61a3b34fae7d1e2de47f52198e26851ce")
        H.equal(row.source_blob,
            "be321d9239d7c0200102f005785587fd5d2dbf3c")
        H.equal(row.current_source_blob,
            "9d95add8cf0f06d1c52042e13d5f83912b7f3dd9")
        H.equal(row.source_path,
            "scripts/settings/equipment/weapon_templates/2h_swords_wood_elf.lua")
        H.deep_equal(catalog.generation, {
            adjacent_operation_count = 1,
            global_operations = 0,
            profile_route_count = 0,
            unsupported_count = 0,
        })
    end)

    H.test("WT #1436 default catalog composes every bounded patch exactly once", function()
        local catalog, mod, paths = load_default_catalog(CatalogUI, script_root)
        local expected_paths = clone(CatalogUI.GENERATED_MODULES)
        expected_paths[#expected_paths + 1] = CatalogUI.COMPLETENESS_LEDGER_MODULE
        H.deep_equal(paths, expected_paths)
        H.deep_equal(catalog.generation.catalogs, {
            "wt_history_patch_2_0_6_v1",
            "wt_history_patch_2_0_9_1_halberd_v1",
            "wt_history_patch_2_0_10_sword_and_dagger_v1",
            "wt_history_patch_3_1_v1", "wt_history_patch_3_2_v1",
            "wt_history_patch_5_2_v1", "wt_history_patch_6_0_v1",
            "wt_history_patch_6_6_v1", "wt_history_patch_6_8_v1",
            "wt_history_patch_6_11_0_kruber_longbow_v1",
            "wt_history_patch_6_11_2_reversions_v2",
            "wt_history_patch_4_1_1_v1", "wt_history_patch_4_6_hagbane_v1",
        })
        H.deep_equal(catalog_counts(catalog), {
            derived_profiles = 1,
            families = 26,
            family_states = 38,
            operations = 236,
            profiles = 18,
            states = 15,
        })
        local axe_falchion, elf_axe, halberd, handgun, kruber, longbow, masterwork,
            sword_dagger, tuskgor
        for _, family in ipairs(catalog.families) do
            if family.id == "elf_one_handed_axe" then elf_axe = family end
            if family.id == "kruber_sword_and_shield" then kruber = family end
            if family.id == "masterwork_pistol" then masterwork = family end
            if family.id == "tuskgor_spear" then tuskgor = family end
            if family.id == "handgun_shared" then handgun = family end
            if family.id == "kruber_halberd" then halberd = family end
            if family.id == "kruber_longbow" then longbow = family end
            if family.id == "sword_and_dagger" then sword_dagger = family end
            if family.id == "axe_and_falchion" then axe_falchion = family end
        end
        H.deep_equal(assert(kruber).state_order, { "5_1_1", "5_2_0", "5_6_1" })
        H.deep_equal(assert(masterwork).state_order, { "4_0_1", "5_2_0" })
        H.deep_equal(assert(elf_axe).state_order, { "3_1_0", "5_1_1", "5_2_0" })
        H.deep_equal(assert(tuskgor).state_order, { "pre_3_1_delta" })
        H.deep_equal(assert(handgun).state_order, { "2_0_5" })
        H.deep_equal(assert(halberd).state_order, { "2_0_9" })
        H.deep_equal(assert(longbow).state_order, { "6_10_0" })
        H.deep_equal(assert(sword_dagger).state_order, { "2_0_9_1", "5_2_0" })
        H.deep_equal(assert(axe_falchion).state_order, { "6_11_1" })
        local valid, validation_error = Policy.validate(catalog)
        H.equal(validation_error, nil)
        H.equal(valid, true)

        local cached, cached_error = CatalogUI.load(mod)
        H.equal(cached_error, nil)
        H.equal(cached, catalog)
        H.equal(#paths, 14, "default composite must reuse its cache")
    end)

    H.test("WT #1436 completeness ledger fails closed on census and scope drift", function()
        local by_path = generated_catalogs(CatalogUI, script_root)
        local catalogs = {}
        for _, path in ipairs(CatalogUI.GENERATED_MODULES) do
            catalogs[#catalogs + 1] = clone(by_path[path])
        end
        local original = assert(by_path[CatalogUI.COMPLETENESS_LEDGER_MODULE])
        local projection = assert(CatalogUI.validate_completeness(
            catalogs, clone(original)))
        H.equal(projection.pre_3_1_delta, "adjacent_delta")
        H.equal(projection["5_1_1"], "complete_direct_historical_baseline")

        local function rejects(mutator, needle)
            local hostile = clone(original)
            mutator(hostile)
            local accepted, refusal = CatalogUI.validate_completeness(
                catalogs, hostile)
            H.equal(accepted, nil)
            H.truthy(refusal and refusal:find(needle, 1, true),
                "wrong completeness refusal: " .. tostring(refusal))
        end
        rejects(function(value) value.schema = 2 end, "identity is invalid")
        rejects(function(value) value.catalogs[13] = nil end, "catalog count drift")
        rejects(function(value)
            value.catalogs[14] = clone(value.catalogs[13])
        end, "catalog count drift")
        rejects(function(value)
            value.catalogs[2] = clone(value.catalogs[1])
        end, "catalog is duplicated")
        rejects(function(value)
            value.catalogs[1].family_states[1].operations = 2
        end, "family-state drift")
        rejects(function(value)
            value.catalogs[1].family_states[2] = clone(
                value.catalogs[1].family_states[1])
        end, "declaration is invalid")
        rejects(function(value)
            value.catalogs[1].projection_kind = "complete_direct_historical_baseline"
        end, "scope contract is invalid")
        rejects(function(value)
            value.catalogs[1].exclusions[1].reason = ""
        end, "exclusion is invalid")
        rejects(function(value)
            value.catalogs[1].unexpected = true
        end, "unexpected key")
        rejects(function(value) value.totals.operations = 235 end,
            "aggregate totals drift")

        local extra_state_catalogs = clone(catalogs)
        extra_state_catalogs[1].states.unowned = clone(
            extra_state_catalogs[1].states["2_0_5"])
        local accepted, refusal = CatalogUI.validate_completeness(
            extra_state_catalogs, clone(original))
        H.equal(accepted, nil)
        H.truthy(refusal and refusal:find("unowned state", 1, true))

        H.equal(read_file(script_root .. "_wt_history_completeness_ledger.lua"),
            read_file(repo_root
                .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/"
                .. "_wt_history_completeness_ledger.lua"),
            "public and dev must carry a byte-identical completeness ledger")
    end)

    H.test("WT #1436 Patch 6.0 applies, reads back, and restores exact state", function()
        local catalog = assert(loadfile(script_root .. "_wt_history_6_0_catalog.lua"))()
        local historical = catalog.profile_specs["5_6_1"]
            .staff_fireball_charged.historical_profile
        local native_profile = clone(historical)
        native_profile.armor_modifier.attack[5] = 1

        local function roots_fixture_6_0()
            local shield_postpush = {
                damage_window_end = 0.32, damage_window_start = 0.22,
                dedicated_target_range = 2.8, range_mod = 1.3,
                range_mod_add = 0.2, sibling = { owner = "kruber" },
            }
            local breton_postpush = {
                damage_window_end = 0.32, damage_window_start = 0.22,
                dedicated_target_range = 2.8, range_mod = 1.5,
                range_mod_add = 0.25, sweep_z_offset = -0.035,
                sibling = { owner = "breton" },
            }
            local fireball_action = {
                damage_profile = "staff_fireball_charged",
                sibling = { owner = "fireball" },
            }
            local roots = {
                BuffTemplates = {}, ExplosionTemplates = {},
                PlayerUnitStatusSettings = {}, VortexTemplates = {},
                Weapons = {
                    one_handed_sword_shield_template_1 = { actions = {
                        action_one = { light_attack_stab_postpush = shield_postpush },
                    } },
                    one_handed_sword_shield_template_2 = { actions = {
                        action_one = { light_attack_stab_postpush = breton_postpush },
                    } },
                    staff_fireball_fireball_template_1 = { actions = {
                        action_one = { shoot_charged = fireball_action },
                    } },
                },
            }
            return roots, {
                breton = breton_postpush, fireball = fireball_action,
                shield = shield_postpush,
            }
        end

        with_named_profile_globals({
            staff_fireball_charged = native_profile,
        }, function()
            local roots, refs = roots_fixture_6_0()
            local before = clone(roots)
            local native_before = clone(native_profile)
            local mod = mod_fixture({
                wt_history_kruber_sword_and_shield = "5_6_1",
                wt_history_kruber_bretonnian_sword_and_shield = "5_6_1",
                wt_history_sienna_fireball_staff = "5_6_1",
            }, { value = true })
            local runtime = Runtime.install({
                catalog = catalog, mod = mod, policy = Policy, roots = roots,
            })

            H.equal(runtime.fatal_error, nil)
            H.equal(runtime.last_error, nil)
            H.equal(runtime:verify(), nil)
            H.equal(#runtime.ledgers.kruber_sword_and_shield, 5)
            H.equal(#runtime.ledgers.kruber_bretonnian_sword_and_shield, 6)
            H.equal(#runtime.ledgers.sienna_fireball_staff, 1)
            H.equal(refs.shield.damage_window_start, 0.18)
            H.equal(refs.shield.damage_window_end, 0.28)
            H.equal(refs.shield.dedicated_target_range, 2.5)
            H.equal(refs.shield.range_mod, 1.2)
            H.equal(rawget(refs.shield, "range_mod_add"), nil)
            H.equal(refs.breton.damage_window_start, 0.18)
            H.equal(refs.breton.damage_window_end, 0.28)
            H.equal(refs.breton.dedicated_target_range, 2.5)
            H.equal(refs.breton.range_mod, 1.2)
            H.equal(rawget(refs.breton, "range_mod_add"), nil)
            H.equal(rawget(refs.breton, "sweep_z_offset"), nil)
            H.equal(refs.fireball.damage_profile,
                "wt_hist_5_6_1_staff_fireball_charged")
            local private = DamageProfileTemplates[refs.fireball.damage_profile]
            H.equal(private.armor_modifier.attack[5], 0.1)
            H.equal(private.armor_modifier.attack[4], 1)
            H.equal(private.armor_modifier.attack[6], 0)
            H.deep_equal(native_profile, native_before,
                "private registration must not mutate the native profile")

            local restored = assert(runtime:restore())
            H.equal(restored.refused, 0)
            H.equal(restored.changed, true)
            H.deep_equal(roots, before)
            H.equal(roots.Weapons.one_handed_sword_shield_template_1.actions
                .action_one.light_attack_stab_postpush, refs.shield)
            H.equal(roots.Weapons.one_handed_sword_shield_template_2.actions
                .action_one.light_attack_stab_postpush, refs.breton)
            H.equal(roots.Weapons.staff_fireball_fireball_template_1.actions
                .action_one.shoot_charged, refs.fireball)
            H.equal(runtime:verify(),
                "kruber_sword_and_shield historical selection has no ledger")
            local second = assert(runtime:restore())
            H.equal(second.changed, false)
            H.deep_equal(roots, before)
        end)

        local hostile_cases = {
            {
                family = "kruber_sword_and_shield",
                mutate = function(refs) refs.shield.range_mod_add = 0.201 end,
                setting = "wt_history_kruber_sword_and_shield",
            },
            {
                family = "kruber_bretonnian_sword_and_shield",
                mutate = function(refs) refs.breton.sweep_z_offset = -0.036 end,
                setting = "wt_history_kruber_bretonnian_sword_and_shield",
            },
        }
        for _, case in ipairs(hostile_cases) do
            with_named_profile_globals({
                staff_fireball_charged = clone(native_profile),
            }, function()
                local roots, refs = roots_fixture_6_0()
                case.mutate(refs)
                local before = clone(roots)
                local runtime = Runtime.install({
                    catalog = catalog,
                    mod = mod_fixture({ [case.setting] = "5_6_1" }, { value = true }),
                    policy = Policy, roots = roots,
                })
                H.truthy(runtime.last_error and runtime.last_error:find(
                    "current guard mismatch", 1, true) ~= nil)
                H.equal(#(runtime.ledgers[case.family] or {}), 0)
                H.deep_equal(roots, before,
                    case.family .. " must reject before its first write")
            end)
        end

        with_named_profile_globals({
            staff_fireball_charged = clone(native_profile),
        }, function()
            local roots, refs = roots_fixture_6_0()
            refs.fireball.damage_profile = "renamed_profile"
            local before = clone(roots)
            local runtime = Runtime.install({
                catalog = catalog,
                mod = mod_fixture({
                    wt_history_sienna_fireball_staff = "5_6_1",
                }, { value = true }),
                policy = Policy, roots = roots,
            })
            H.truthy(runtime.last_error and runtime.last_error:find(
                "native profile route not found staff_fireball_charged", 1, true))
            H.equal(#(runtime.ledgers.sienna_fireball_staff or {}), 0)
            H.deep_equal(roots, before,
                "missing Fireball route must reject before gameplay writes")
        end)

        with_named_profile_globals({
            staff_fireball_charged = clone(native_profile),
        }, function()
            local roots, refs = roots_fixture_6_0()
            local runtime = Runtime.install({
                catalog = catalog,
                mod = mod_fixture({
                    wt_history_sienna_fireball_staff = "5_6_1",
                }, { value = false }),
                policy = Policy, roots = roots,
            })
            H.equal(runtime.last_error, nil)
            H.equal(refs.fireball.damage_profile, "staff_fireball_charged",
                "unproven peers must retain the native Fireball profile")
            H.equal(runtime.active.sienna_fireball_staff.parity, false)
            H.equal(runtime:verify(), nil)
        end)
    end)

    H.test("WT #1436 policy preserves all non-vacuous boolean presence transitions", function()
        local catalog = catalog_fixture()
        local family = catalog.families[1]
        local state = family.states["5_1_1"]
        state.profile_names = {}
        state.direct_profile_names = {}
        state.atomic_group = "BOOLEAN-PRESENCE-TRUTH-TABLE"
        state.operations = {}

        local cases = {
            { id = "absent_to_false", expected_present = false,
                result_present = true, result = false },
            { id = "absent_to_true", expected_present = false,
                result_present = true, result = true },
            { id = "false_to_absent", expected_present = true, expected = false,
                result_present = false },
            { id = "false_to_true", expected_present = true, expected = false,
                result_present = true, result = true },
            { id = "true_to_absent", expected_present = true, expected = true,
                result_present = false },
            { id = "true_to_false", expected_present = true, expected = true,
                result_present = true, result = false },
        }
        local roots = {
            BuffTemplates = {}, ExplosionTemplates = {},
            PlayerUnitStatusSettings = {}, VortexTemplates = {},
            Weapons = { we_1h_axe_template_1 = { stats = {} } },
        }
        local stats = roots.Weapons.we_1h_axe_template_1.stats
        for index, case in ipairs(cases) do
            local row = operation({ "stats", case.id }, case.expected, case.result)
            row.expected_present = case.expected_present
            if not case.expected_present then row.expected_current = nil end
            row.result_present = case.result_present
            if not case.result_present then row.result = nil end
            row.official_change_id = "BOOLEAN-PRESENCE-" .. index
            state.operations[index] = row
            if case.expected_present then stats[case.id] = case.expected end
        end

        local plan, plan_error = Policy.build_family_plan(
            catalog, family, "5_1_1", roots)
        H.truthy(plan, tostring(plan_error))
        H.equal(#plan, #cases)
        for index, case in ipairs(cases) do
            local entry = plan[index]
            H.equal(entry.original_present, case.expected_present, case.id)
            H.equal(rawget(entry, "original_value") ~= nil,
                case.expected_present, case.id .. " original presence")
            H.equal(entry.original_value, case.expected, case.id .. " original value")
            H.equal(rawget(entry, "applied_value") ~= nil,
                case.result_present, case.id .. " applied presence")
            H.equal(entry.applied_value, case.result, case.id .. " applied value")
            H.equal(rawget(entry, "applied_snapshot") ~= nil,
                case.result_present, case.id .. " snapshot presence")
            H.equal(entry.applied_snapshot, case.result,
                case.id .. " snapshot value")
        end

        local ledger = assert(Policy.commit(plan))
        for _, case in ipairs(cases) do
            H.equal(rawget(stats, case.id) ~= nil, case.result_present,
                case.id .. " committed presence")
            H.equal(rawget(stats, case.id), case.result,
                case.id .. " committed value")
        end
        H.equal(Policy.restore(ledger), true)
        for _, case in ipairs(cases) do
            H.equal(rawget(stats, case.id) ~= nil, case.expected_present,
                case.id .. " restored presence")
            H.equal(rawget(stats, case.id), case.expected,
                case.id .. " restored value")
        end
    end)

    H.test("WT #1436 catalog merge rejects every cross-catalog identity collision", function()
        local patch_5_2 = assert(loadfile(script_root
            .. "_wt_history_5_2_catalog.lua"))()
        local patch_6_8 = assert(loadfile(script_root
            .. "_wt_history_6_8_catalog.lua"))()

        local function rejected(mutator, needle)
            local left, right = clone(patch_5_2), clone(patch_6_8)
            mutator(left, right)
            local merged, merge_error = CatalogUI.merge({ left, right })
            H.equal(merged, nil)
            H.truthy(type(merge_error) == "string"
                and merge_error:find(needle, 1, true) ~= nil,
                "wrong merge rejection for " .. needle .. ": " .. tostring(merge_error))
        end

        local function rejects_catalogs(catalogs, needle)
            local merged, merge_error = CatalogUI.merge(catalogs)
            H.equal(merged, nil)
            H.truthy(type(merge_error) == "string"
                and merge_error:find(needle, 1, true) ~= nil,
                "wrong hostile-array rejection for " .. needle .. ": "
                    .. tostring(merge_error))
        end

        rejected(function(left, right) right.catalog_id = left.catalog_id end,
            "duplicate catalog id")
        rejected(function(_, right)
            right.current_source.revision = string.rep("f", 40)
        end, "unsupported or mismatched shape")
        rejected(function(left, right)
            right.states["5_1_1"] = clone(left.states["5_1_1"])
        end, "duplicate history state")
        rejected(function(left, right)
            right.profile_specs["5_1_1"] = clone(left.profile_specs["5_1_1"])
        end, "duplicate profile state")
        rejected(function(left, right)
            right.derived_profiles["5_1_1"] = clone(
                left.derived_profiles["5_1_1"])
        end, "duplicate derived-profile state")
        rejected(function(left, right)
            right.families[1].id = left.families[1].id
        end, "history family identity mismatch setting_id")
        rejected(function(left, right)
            right.families[1].setting_id = left.families[1].setting_id
        end, "duplicate history setting")
        rejected(function(left, right)
            right.families[1].label_key = left.families[1].label_key
        end, "duplicate history localization key")
        rejected(function(left, right)
            right.states["6_7_2"].label_key = left.states["5_1_1"].label_key
        end, "duplicate history localization key")
        rejected(function(_, right)
            right.families[1].label_key = right.states["6_7_2"].label_key
        end, "duplicate history localization key")
        rejected(function(left, right)
            right.families[1].templates[1] = left.families[1].templates[1]
        end, "duplicate or invalid history template")

        rejects_catalogs("not-an-array", "not an array")
        rejects_catalogs({
            [1] = clone(patch_5_2),
            [3] = clone(patch_6_8),
        }, "dense array")
        rejects_catalogs({ named = clone(patch_5_2) }, "dense array")

        local sparse_families = clone(patch_6_8)
        sparse_families.families[2] = sparse_families.families[1]
        sparse_families.families[1] = nil
        rejects_catalogs({ clone(patch_5_2), sparse_families },
            "history families must be a dense array")
        local non_array_families = clone(patch_6_8)
        non_array_families.families = "not-an-array"
        rejects_catalogs({ clone(patch_5_2), non_array_families },
            "unsupported or mismatched shape")

        local sparse_templates = clone(patch_6_8)
        sparse_templates.families[1].templates[2] =
            sparse_templates.families[1].templates[1]
        sparse_templates.families[1].templates[1] = nil
        rejects_catalogs({ clone(patch_5_2), sparse_templates },
            "history family templates must be a dense array")
        local non_array_templates = clone(patch_6_8)
        non_array_templates.families[1].templates = "not-an-array"
        rejects_catalogs({ clone(patch_5_2), non_array_templates },
            "history family identity is incomplete")

        local mod = { dofile = function() error("must not load") end }
        local duplicate, duplicate_error = CatalogUI.load(mod, {
            CatalogUI.GENERATED_MODULES[1], CatalogUI.GENERATED_MODULES[1],
        })
        H.equal(duplicate, nil)
        H.truthy(duplicate_error:find("duplicated", 1, true) ~= nil)
        local sparse, sparse_error = CatalogUI.load(mod, {
            [1] = CatalogUI.GENERATED_MODULES[1],
            [3] = CatalogUI.GENERATED_MODULES[2],
        })
        H.equal(sparse, nil)
        H.truthy(sparse_error:find("dense array", 1, true) ~= nil)
    end)

    H.test("WT #1436 catalog merge coalesces only exact family fragments", function()
        local source = assert(loadfile(script_root
            .. "_wt_history_6_8_catalog.lua"))()

        local function fragment(catalog_id, state_id, label_key, source_revision)
            local catalog = clone(source)
            local family = catalog.families[1]
            local old_state_id = family.state_order[1]
            local family_state = family.states[old_state_id]
            local state = catalog.states[old_state_id]
            catalog.catalog_id = catalog_id
            catalog.states[old_state_id] = nil
            catalog.states[state_id] = state
            state.display_name = "Game Version " .. state_id
            state.label_key = label_key
            state.source_revision = source_revision
            family.state_order = { state_id }
            family.states[old_state_id] = nil
            family.states[state_id] = family_state
            for _, row in ipairs(family_state.operations) do
                row.official_change_id = "TEST-" .. state_id
                row.source_revision = source_revision
                row.state_id = state_id
            end
            return catalog
        end

        local left = fragment("fragment_left", "6_7_2",
            "wt_history_state_6_7_2", HASH_A)
        local right = fragment("fragment_right", "6_0_0",
            "wt_history_state_6_0_0", HASH_B)
        left.profile_specs["6_7_2"] = {
            native_profile = { historical_profile = { attack = 1 } },
        }
        right.profile_specs["6_0_0"] = {
            native_profile = { historical_profile = { attack = 2 } },
        }
        left.derived_profiles["6_7_2"] = {
            derived_profile = { derivation = { source = "left" } },
        }
        right.derived_profiles["6_0_0"] = {
            derived_profile = { derivation = { source = "right" } },
        }
        local left_before, right_before = clone(left), clone(right)
        local merged, merge_error = CatalogUI.merge({ left, right })
        H.equal(merge_error, nil)
        H.equal(#merged.families, 1)
        H.deep_equal(merged.families[1].state_order, { "6_0_0", "6_7_2" })
        H.truthy(merged.families[1].states["6_7_2"] ~= nil)
        H.truthy(merged.families[1].states["6_0_0"] ~= nil)
        H.deep_equal(left, left_before, "left input catalog must remain immutable")
        H.deep_equal(right, right_before, "right input catalog must remain immutable")

        merged.families[1].state_order[1] = "mutated"
        merged.families[1].states["6_0_0"].operations[1].result = -1
        merged.current_source.display_name = "Mutated source"
        merged.states["6_7_2"].display_name = "Mutated left state"
        merged.states["6_0_0"].display_name = "Mutated right state"
        merged.profile_specs["6_7_2"].native_profile
            .historical_profile.attack = -1
        merged.profile_specs["6_0_0"].native_profile
            .historical_profile.attack = -1
        merged.derived_profiles["6_7_2"].derived_profile
            .derivation.source = "mutated"
        merged.derived_profiles["6_0_0"].derived_profile
            .derivation.source = "mutated"
        H.deep_equal(left, left_before,
            "merged family edits must not alias the left input catalog")
        H.deep_equal(right, right_before,
            "merged family edits must not alias the right input catalog")

        merged = assert(CatalogUI.merge({ clone(left), clone(right) }))
        local group = assert(CatalogUI.build_widgets(merged))
        H.equal(#group.sub_widgets, 1)
        H.equal(group.sub_widgets[1].setting_id,
            left.families[1].setting_id)
        H.deep_equal(group.sub_widgets[1].options, {
            { text = "wt_history_state_current", value = "current" },
            { text = "wt_history_state_6_0_0", value = "6_0_0" },
            { text = "wt_history_state_6_7_2", value = "6_7_2" },
        })

        local reversed = assert(CatalogUI.merge({ clone(right), clone(left) }))
        H.deep_equal(reversed.families[1].state_order, { "6_0_0", "6_7_2" })
        H.equal(#reversed.families, 1)

        local repeat_merge = assert(CatalogUI.merge({ clone(left), clone(right) }))
        H.deep_equal(repeat_merge, assert(CatalogUI.merge({
            clone(left), clone(right),
        })), "same ordered inputs must compose deterministically")

        local function rejected(mutator, needle)
            local hostile_left, hostile_right = clone(left), clone(right)
            mutator(hostile_left.families[1], hostile_right.families[1],
                hostile_left, hostile_right)
            local hostile, hostile_error = CatalogUI.merge({
                hostile_left, hostile_right,
            })
            H.equal(hostile, nil)
            H.truthy(type(hostile_error) == "string"
                and hostile_error:find(needle, 1, true) ~= nil,
                "wrong fragment rejection for " .. needle .. ": "
                    .. tostring(hostile_error))
        end

        rejected(function(_, family) family.setting_id = "different_setting" end,
            "identity mismatch setting_id")
        rejected(function(_, family) family.label_key = "different_label" end,
            "identity mismatch label_key")
        rejected(function(_, family) family.display_name = "Different Family" end,
            "identity mismatch display_name")
        rejected(function(_, family) family.authority = "server" end,
            "identity mismatch authority")
        rejected(function(_, family)
            family.templates = { "different_template" }
        end, "identity mismatch templates")
        rejected(function(_, family)
            family.id = "different_family"
            family.setting_id = "different_family_setting"
            family.label_key = "different_family_label"
        end, "duplicate or invalid history template")

        rejected(function(_, family, _, hostile_right)
            local replacement = hostile_right.states["6_0_0"]
            hostile_right.states["6_0_0"] = nil
            hostile_right.states["6_7_2"] = replacement
            family.states["6_0_0"] = nil
            family.states["6_7_2"] = family.states["6_7_2"] or {
                direct_profile_names = {}, operations = {}, profile_names = {},
            }
            family.state_order = { "6_7_2" }
        end, "duplicate history state")

        rejected(function(_, _, hostile_left, hostile_right)
            hostile_left.profile_specs["profile_path"] = { sentinel = true }
            hostile_right.profile_specs["profile_path"] = { sentinel = true }
        end, "duplicate profile state")
    end)

    H.test("WT #1436 generated guards retain pinned source-literal precision", function()
        local catalog = assert(loadfile(script_root .. "_wt_history_5_2_catalog.lua"))()
        local pinned
        for _, family in ipairs(catalog.families) do
            if family.id == "elf_one_handed_axe" then
                for _, row in ipairs(family.states["5_1_1"].operations) do
                    if table.concat(row.path, ".")
                            == "actions.action_one.light_attack_bopp.baked_sweep" then
                        pinned = row.expected_current[1][1]
                    end
                end
            end
        end
        H.equal(pinned, 0.2866666666666667,
            "current 6.12.1 source literal must survive evidence and catalog generation")
        H.truthy(pinned ~= 0.28666666666667,
            "the former Lua 5.1 tostring truncation must remain detectable")
    end)

    H.test("WT #1436 schema rejects ambiguous profile and state declarations", function()
        local duplicate = catalog_fixture()
        duplicate.families[1].states["5_1_1"].profile_names = {
            "native_profile", "native_profile",
        }
        local valid, validation_error = Policy.validate(duplicate)
        H.equal(valid, nil)
        H.truthy(validation_error:find("duplicate family profile", 1, true))

        local unlisted = catalog_fixture()
        unlisted.families[1].states.unlisted = clone(
            unlisted.families[1].states["5_1_1"])
        valid, validation_error = Policy.validate(unlisted)
        H.equal(valid, nil)
        H.truthy(validation_error:find("family state missing from order", 1, true))

        local missing_direct = catalog_fixture()
        missing_direct.families[1].states["5_1_1"].direct_profile_names = nil
        valid, validation_error = Policy.validate(missing_direct)
        H.equal(valid, nil)
        H.truthy(validation_error:find("missing direct profile routes", 1, true))

        local unknown_authority = catalog_fixture()
        unknown_authority.families[1].authority = "client"
        valid, validation_error = Policy.validate(unknown_authority)
        H.equal(valid, nil)
        H.truthy(validation_error:find("unsupported family authority", 1, true))

        local localization_collision = catalog_fixture()
        localization_collision.families[1].label_key =
            localization_collision.states["5_1_1"].label_key
        valid, validation_error = Policy.validate(localization_collision)
        H.equal(valid, nil)
        H.truthy(validation_error:find(
            "duplicate history localization key", 1, true))
    end)

    local function patch_6_6_collision_catalog(mutate_path, reverse_order)
        local catalog = assert(loadfile(script_root .. "_wt_history_6_6_catalog.lua"))()
        local original = catalog.families[1]
        local collision = clone(original)
        collision.id = "deepwood_staff_collision"
        collision.setting_id = "wt_history_deepwood_staff_collision"
        collision.label_key = "wt_history_family_deepwood_staff_collision"
        collision.templates = { "synthetic_collision_template" }
        local operation = clone(original.states["6_5_4"].operations[1])
        operation.family_id = collision.id
        if mutate_path then mutate_path(operation.path) end
        collision.states["6_5_4"].operations = { operation }
        catalog.families = reverse_order and { collision, original }
            or { original, collision }
        return catalog
    end

    H.test("WT #1436 runtime rejects cross-family global-root ownership before writes", function()
        local cases = {
            {
                expected = "cross-family target collision",
                name = "exact",
            },
            {
                expected = "cross-family target collision",
                name = "exact reverse",
                reverse = true,
            },
            {
                expected = "cross-family ancestor/descendant target conflict",
                mutate = function(path) path[#path] = nil end,
                name = "ancestor",
            },
            {
                expected = "cross-family ancestor/descendant target conflict",
                mutate = function(path) path[#path + 1] = "synthetic_child" end,
                name = "descendant",
            },
        }
        for _, case in ipairs(cases) do
            with_profile_globals(function()
                local catalog = patch_6_6_collision_catalog(case.mutate, case.reverse)
                local roots = deepwood_roots_fixture()
                local before = clone(roots)
                local mod = mod_fixture({
                    wt_history_deepwood_staff = "6_5_4",
                    wt_history_deepwood_staff_collision = "6_5_4",
                }, { value = true })
                local runtime = Runtime.install({
                    catalog = catalog,
                    is_server = function() return true end,
                    mod = mod,
                    policy = Policy,
                    roots = roots,
                })

                H.truthy(runtime.fatal_error
                    and runtime.fatal_error:find(case.expected, 1, true), case.name)
                H.equal(runtime.last_error, runtime.fatal_error)
                H.equal(runtime.registration.count, 0)
                H.equal(mod._wt431_custom_profile_fallback, nil,
                    case.name .. " must fail before profile registration")
                H.equal(next(runtime.ledgers), nil)
                H.equal(next(runtime.active), nil)
                H.deep_equal(roots, before,
                    case.name .. " must fail before every gameplay write")

                local reapplied, reapply_error = runtime:reapply()
                H.equal(reapplied, nil)
                H.equal(reapply_error, runtime.fatal_error)
                local restored, restore_error = runtime:restore()
                H.equal(restored, nil)
                H.equal(restore_error, runtime.fatal_error)
                H.deep_equal(roots, before,
                    case.name .. " fatal runtime must remain inert")
            end)
        end
    end)

    H.test("WT #1436 one family may reuse targets across alternative states", function()
        local catalog = assert(loadfile(script_root .. "_wt_history_6_6_catalog.lua"))()
        local family = catalog.families[1]
        local alternative_id = "6_5_4_alternative"
        local alternative_state = clone(family.states["6_5_4"])
        for _, operation in ipairs(alternative_state.operations) do
            operation.state_id = alternative_id
        end
        family.state_order[2] = alternative_id
        family.states[alternative_id] = alternative_state
        catalog.states[alternative_id] = clone(catalog.states["6_5_4"])
        catalog.states[alternative_id].display_name = "Alternative source state"
        catalog.states[alternative_id].label_key = "wt_history_state_6_5_4_alternative"

        local valid, validation_error = Policy.validate(catalog)
        H.equal(valid, true)
        H.equal(validation_error, nil)
    end)

    H.test("WT #1436 menu and localization share the composite family catalog", function()
        local catalog = load_default_catalog(CatalogUI, script_root)
        local group = assert(CatalogUI.build_widgets(catalog))
        local loc = assert(CatalogUI.build_localization(catalog))
        H.equal(group.setting_id, "wt_history_patch_versions")
        H.equal(#group.sub_widgets, #catalog.families)
        H.truthy(loc.wt_history_patch_versions_description.en
            :find("historical balance projection", 1, true) ~= nil)
        H.truthy(loc.wt_history_state_3_1_0.en
            :find("bounded patch delta", 1, true) ~= nil)
        H.truthy(loc.wt_history_state_5_1_1.en
            :find("bounded patch delta", 1, true) == nil,
            "complete direct historical baseline must not be mislabeled as adjacent")
        for index, family in ipairs(catalog.families) do
            local widget = group.sub_widgets[index]
            H.equal(widget.setting_id, family.setting_id)
            H.equal(widget.default_value, "current")
            H.equal(widget.options[1].value, "current")
            H.equal(widget.options[1].text, "wt_history_state_current")
            H.equal(#widget.options, #family.state_order + 1)
            H.equal(loc[family.setting_id].en, family.display_name)
            H.truthy(loc[family.setting_id .. "_description"].en
                :find("restart", 1, true) ~= nil)
            if family.id == "deepwood_staff" then
                H.truthy(loc[family.setting_id .. "_description"].en
                    :find("hosting or playing solo", 1, true) ~= nil)
            end
        end
    end)

    H.test("WT #1436 data decoration inserts one history group and fails closed", function()
        local by_path = generated_catalogs(CatalogUI, script_root)
        local loads = 0
        local mod = {}
        function mod:dofile(path)
            loads = loads + 1
            return assert(by_path[path], "unexpected generated module " .. tostring(path))
        end
        local first = { setting_id = "first" }
        local second = { setting_id = "second" }
        local data = { options = { widgets = { first, second } } }

        H.equal(CatalogUI.decorate_menu(mod, data), data)
        H.equal(data.options.widgets[1], first)
        H.equal(data.options.widgets[2].setting_id, "wt_history_patch_versions")
        H.equal(#data.options.widgets[2].sub_widgets, 26)
        H.equal(data.options.widgets[3], second)
        H.equal(loads, 14)
        H.equal(CatalogUI.decorate_menu(mod, data), data)
        H.equal(#data.options.widgets, 3)
        H.equal(loads, 14, "re-decoration must not reload or duplicate the group")

        local malformed = { options = {} }
        H.equal(CatalogUI.decorate_menu(mod, malformed), malformed)
        H.equal(loads, 14, "malformed menu data must not load generated catalogs")
    end)

    H.test("WT #1436 public and dev data surfaces return one index-two history group", function()
        local streams = {
            {
                namespace = "weapon_tweaker",
                root = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/",
            },
            {
                namespace = "weapon_tweaker_dev",
                root = repo_root .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/",
            },
        }
        for _, stream in ipairs(streams) do
            local data_path = stream.root .. stream.namespace .. "_data.lua"
            local source = read_file(data_path)
            local module_path = "scripts/mods/" .. stream.namespace
                .. "/_wt_history_catalog"
            local exact_return = "return mod:dofile(\"" .. module_path
                .. "\").decorate_menu(mod, data)"
            H.equal(count_plain(source, exact_return), 1,
                stream.namespace .. " must delegate its final return exactly once")
            H.truthy(source:match(exact_return:gsub("([^%w])", "%%%1") .. "%s*$") ~= nil,
                stream.namespace .. " history decoration must remain the final return")

            local catalog_ui = assert(loadfile(stream.root
                .. "_wt_history_catalog.lua"))()
            local by_path = generated_catalogs(catalog_ui, stream.root)
            local loads = 0
            local mod = {}
            function mod:dofile(path)
                loads = loads + 1
                return assert(by_path[path],
                    "unexpected generated module " .. tostring(path))
            end
            local availability = { setting_id = "weapon_availability" }
            local overrides = { setting_id = "weapon_overrides" }
            local data = { options = { widgets = { availability, overrides } } }
            H.equal(catalog_ui.decorate_menu(mod, data), data)
            H.equal(data.options.widgets[1], availability)
            H.equal(data.options.widgets[2].setting_id,
                "wt_history_patch_versions")
            H.equal(#data.options.widgets[2].sub_widgets, 26)
            H.equal(data.options.widgets[3], overrides)
            H.equal(loads, 14)
            H.equal(catalog_ui.decorate_menu(mod, data), data)
            H.equal(#data.options.widgets, 3,
                stream.namespace .. " must not duplicate its history group")
            H.equal(loads, 14,
                stream.namespace .. " must reuse its generated-catalog cache")
        end
    end)

    register_runtime(H, {
        AxeBalance = AxeBalance,
        HistoryOwner = HistoryOwner,
        Policy = Policy,
        Runtime = Runtime,
        catalog_fixture = catalog_fixture,
        clone = clone,
        deepwood_roots_fixture = deepwood_roots_fixture,
        materialize_expected_roots = materialize_expected_roots,
        mod_fixture = mod_fixture,
        roots_fixture = roots_fixture,
        script_root = script_root,
        with_profile_globals = with_profile_globals,
    })
end

return register
