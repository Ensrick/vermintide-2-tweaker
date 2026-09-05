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
            local value = row.expected_present and clone(row.expected_current) or nil
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

    H.test("WT #1436 generated Patch 5.2 catalog passes strict schema validation", function()
        local catalog = assert(loadfile(script_root .. "_wt_history_5_2_catalog.lua"))()
        local valid, validation_error = Policy.validate(catalog)
        H.equal(validation_error, nil)
        H.equal(valid, true)
        H.equal(catalog.schema, 2)
        H.equal(#catalog.families, 14)
    end)

    H.test("WT #1436 generated Patch 6.6 catalog pins one atomic Deepwood boundary", function()
        local catalog = assert(loadfile(script_root .. "_wt_history_6_6_catalog.lua"))()
        local valid, validation_error = Policy.validate(catalog)
        H.equal(validation_error, nil)
        H.equal(valid, true)
        H.equal(catalog.schema, 2)
        H.equal(catalog.catalog_id, "wt_history_patch_6_6_v1")
        H.equal(catalog.current_source.revision,
            "c5e4968b1fbb00c49884e56d640ef990a9c04dd0")
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
            "c5e4968b1fbb00c49884e56d640ef990a9c04dd0")
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

    H.test("WT #1436 default catalog composes Patch 5.2, 6.6, and 6.8 exactly once", function()
        local catalog, mod, paths = load_default_catalog(CatalogUI, script_root)
        H.deep_equal(paths, CatalogUI.GENERATED_MODULES)
        H.deep_equal(catalog.generation.catalogs, {
            "wt_history_patch_5_2_v1", "wt_history_patch_6_6_v1",
            "wt_history_patch_6_8_v1",
        })
        H.deep_equal(catalog_counts(catalog), {
            derived_profiles = 1,
            families = 16,
            family_states = 24,
            operations = 186,
            profiles = 13,
            states = 5,
        })
        local valid, validation_error = Policy.validate(catalog)
        H.equal(validation_error, nil)
        H.equal(valid, true)

        local cached, cached_error = CatalogUI.load(mod)
        H.equal(cached_error, nil)
        H.equal(cached, catalog)
        H.equal(#paths, 3, "default composite must reuse its cache")
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
        end, "duplicate history family")
        rejected(function(left, right)
            right.families[1].setting_id = left.families[1].setting_id
        end, "duplicate history setting")
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
            "current c5e4968 source literal must survive evidence and catalog generation")
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
        H.equal(#data.options.widgets[2].sub_widgets, 16)
        H.equal(data.options.widgets[3], second)
        H.equal(loads, 3)
        H.equal(CatalogUI.decorate_menu(mod, data), data)
        H.equal(#data.options.widgets, 3)
        H.equal(loads, 3, "re-decoration must not reload or duplicate the group")

        local malformed = { options = {} }
        H.equal(CatalogUI.decorate_menu(mod, malformed), malformed)
        H.equal(loads, 3, "malformed menu data must not load generated catalogs")
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
            H.equal(#data.options.widgets[2].sub_widgets, 16)
            H.equal(data.options.widgets[3], overrides)
            H.equal(loads, 3)
            H.equal(catalog_ui.decorate_menu(mod, data), data)
            H.equal(#data.options.widgets, 3,
                stream.namespace .. " must not duplicate its history group")
            H.equal(loads, 3,
                stream.namespace .. " must reuse its generated-catalog cache")
        end
    end)

    H.test("WT #1436 Patch 6.5.4 applies and restores one atomic host projection", function()
        with_profile_globals(function()
            local catalog = assert(loadfile(script_root
                .. "_wt_history_6_6_catalog.lua"))()

            local current_roots, current_refs = deepwood_roots_fixture()
            local current_before = clone(current_roots)
            local current_runtime = Runtime.install({
                catalog = catalog,
                is_server = function() return false end,
                mod = mod_fixture({ wt_history_deepwood_staff = "current" },
                    { value = true }),
                policy = Policy,
                roots = current_roots,
            })
            H.equal(current_runtime.fatal_error, nil)
            H.equal(current_runtime:verify(), nil)
            H.equal(#(current_runtime.ledgers.deepwood_staff or {}), 0)
            H.deep_equal(current_roots, current_before,
                "Current must remain a no-op even on a client")
            H.equal(current_refs.life_metadata,
                current_roots.Weapons.staff_life.metadata)

            local roots, refs = deepwood_roots_fixture()
            local before = clone(roots)
            local runtime = Runtime.install({
                catalog = catalog,
                is_server = function() return true end,
                mod = mod_fixture({ wt_history_deepwood_staff = "6_5_4" },
                    { value = true }),
                policy = Policy,
                roots = roots,
            })
            H.equal(runtime.fatal_error, nil)
            H.equal(runtime.last_error, nil)
            H.equal(runtime:verify(), nil)
            H.equal(#runtime.ledgers.deepwood_staff, 3)
            H.equal(refs.life_priorities.chaos_bulwark, nil)
            H.equal(refs.versus_priorities.chaos_bulwark, nil)
            H.equal(refs.vortex_reductions.chaos_bulwark, nil)
            H.equal(refs.life_priorities.chaos_tether_sorcerer, 1,
                "later Deepwood targeting rows must survive the old projection")
            H.equal(refs.versus_priorities.chaos_tether_sorcerer, 1,
                "the Versus clone must preserve later targeting rows too")
            H.equal(refs.life_priorities.chaos_warrior, 1)
            H.equal(refs.versus_priorities.chaos_warrior, 1)
            H.equal(refs.vortex_reductions.chaos_warrior, 0.5)
            H.equal(roots.Weapons.staff_life.metadata, refs.life_metadata)
            H.equal(roots.Weapons.staff_life_vs.metadata, refs.versus_metadata)
            H.equal(roots.VortexTemplates.spirit_storm.metadata,
                refs.vortex_metadata)

            local restored = assert(runtime:restore())
            H.equal(restored.refused, 0)
            H.equal(restored.changed, true)
            H.deep_equal(roots, before,
                "restore must recover all three exact current leaves")
            H.equal(refs.life_priorities.chaos_bulwark, 1)
            H.equal(refs.versus_priorities.chaos_bulwark, 1)
            H.equal(refs.vortex_reductions.chaos_bulwark, 0.5)
            H.equal(assert(runtime:restore()).changed, false)
        end)
    end)

    H.test("WT #1436 Patch 6.6 preflight and client authority both fail before writes", function()
        with_profile_globals(function()
            local catalog = assert(loadfile(script_root
                .. "_wt_history_6_6_catalog.lua"))()

            local mismatch_roots, mismatch_refs = deepwood_roots_fixture({
                staff_life_vs = 2,
            })
            local mismatch_before = clone(mismatch_roots)
            local mismatch_runtime = Runtime.install({
                catalog = catalog,
                is_server = function() return true end,
                mod = mod_fixture({ wt_history_deepwood_staff = "6_5_4" },
                    { value = true }),
                policy = Policy,
                roots = mismatch_roots,
            })
            H.truthy(mismatch_runtime.last_error
                and mismatch_runtime.last_error:find(
                    "current guard mismatch", 1, true) ~= nil)
            H.equal(#(mismatch_runtime.ledgers.deepwood_staff or {}), 0)
            H.deep_equal(mismatch_roots, mismatch_before,
                "a late staff_life_vs guard mismatch must leak zero earlier removals")
            H.equal(mismatch_refs.vortex_reductions.chaos_bulwark, 0.5)
            H.equal(mismatch_refs.life_priorities.chaos_bulwark, 1)
            H.equal(mismatch_refs.versus_priorities.chaos_bulwark, 2)

            local client_roots, client_refs = deepwood_roots_fixture()
            local client_before = clone(client_roots)
            local client_runtime = Runtime.install({
                catalog = catalog,
                is_server = function() return false end,
                mod = mod_fixture({ wt_history_deepwood_staff = "6_5_4" },
                    { value = true }),
                policy = Policy,
                roots = client_roots,
            })
            H.truthy(client_runtime.last_error
                and client_runtime.last_error:find(
                    "server authority required", 1, true) ~= nil)
            H.equal(#(client_runtime.ledgers.deepwood_staff or {}), 0)
            H.deep_equal(client_roots, client_before,
                "a joining client must not project any host-owned Deepwood leaf")
            H.equal(client_refs.life_priorities.chaos_bulwark, 1)
            H.equal(client_refs.versus_priorities.chaos_bulwark, 1)
            H.equal(client_refs.vortex_reductions.chaos_bulwark, 0.5)
        end)
    end)

    H.test("WT #1436 Patch 6.6 authority loss restores before refusing", function()
        with_profile_globals(function()
            local catalog = assert(loadfile(script_root
                .. "_wt_history_6_6_catalog.lua"))()
            local roots, refs = deepwood_roots_fixture()
            local before = clone(roots)
            local server = true
            local runtime = Runtime.install({
                catalog = catalog,
                is_server = function() return server end,
                mod = mod_fixture({ wt_history_deepwood_staff = "6_5_4" },
                    { value = true }),
                policy = Policy,
                roots = roots,
            })
            H.equal(runtime:verify(), nil)
            H.equal(refs.life_priorities.chaos_bulwark, nil)

            server = false
            local refused = assert(runtime:reapply())
            H.equal(refused.refused, 1)
            H.equal(refused.changed, true,
                "authority-loss restoration is a gameplay change")
            H.deep_equal(roots, before,
                "role loss must restore the exact host-owned projection")
            H.equal(#(runtime.ledgers.deepwood_staff or {}), 0)

            server = true
            local reapplied = assert(runtime:reapply())
            H.equal(reapplied.refused, 0)
            H.equal(reapplied.changed, true)
            H.equal(runtime.last_error, nil)
            H.equal(runtime:verify(), nil)
            H.equal(refs.life_priorities.chaos_bulwark, nil)
        end)
    end)

    H.test("WT #1436 Patch 6.7.2 changes only Greatsword first-heavy range", function()
        with_profile_globals(function()
            local catalog = assert(loadfile(script_root
                .. "_wt_history_6_8_catalog.lua"))()

            local function roots_with_range(range_mod)
                local heavy_sibling = { damage_profile = "heavy_slashing_linesman" }
                local light_sibling = { range_mod = 1.25 }
                local template_sibling = { marker = "preserve exact identity" }
                local heavy = {
                    damage_profile = heavy_sibling.damage_profile,
                    range_mod = range_mod,
                    total_time = 1.4,
                }
                local template = {
                    actions = {
                        action_one = {
                            heavy_attack_down_first = heavy,
                            light_attack_left = light_sibling,
                        },
                    },
                    metadata = template_sibling,
                    weapon_type = "SWORD_2H",
                }
                return {
                    BuffTemplates = {},
                    ExplosionTemplates = {},
                    PlayerUnitStatusSettings = {},
                    Weapons = {
                        two_handed_swords_wood_elf_template = template,
                    },
                }, {
                    heavy = heavy,
                    light_sibling = light_sibling,
                    template = template,
                    template_sibling = template_sibling,
                }
            end

            local current_roots, current_refs = roots_with_range(1.55)
            local current_before = clone(current_roots)
            local current_mod = mod_fixture({
                wt_history_elf_greatsword = "current",
            }, { value = true })
            local current_runtime = Runtime.install({
                catalog = catalog,
                mod = current_mod,
                policy = Policy,
                roots = current_roots,
            })
            H.equal(current_runtime.fatal_error, nil)
            H.equal(current_runtime:verify(), nil)
            H.equal(#(current_runtime.ledgers.elf_greatsword or {}), 0)
            H.deep_equal(current_roots, current_before,
                "Current must perform no gameplay writes")
            H.equal(current_roots.Weapons.two_handed_swords_wood_elf_template,
                current_refs.template)
            H.equal(current_refs.template.metadata, current_refs.template_sibling)
            local current_restore = assert(current_runtime:restore())
            H.equal(current_restore.changed, false)
            H.deep_equal(current_roots, current_before,
                "restoring an already-current family must remain a no-op")

            local history_roots, history_refs = roots_with_range(1.55)
            local history_before = clone(history_roots)
            local expected_historical = clone(history_before)
            expected_historical.Weapons.two_handed_swords_wood_elf_template
                .actions.action_one.heavy_attack_down_first.range_mod = 1.45
            local history_mod = mod_fixture({
                wt_history_elf_greatsword = "6_7_2",
            }, { value = true })
            local history_runtime = Runtime.install({
                catalog = catalog,
                mod = history_mod,
                policy = Policy,
                roots = history_roots,
            })
            H.equal(history_runtime.fatal_error, nil)
            H.equal(history_runtime.last_error, nil)
            H.equal(history_runtime:verify(), nil)
            H.equal(#history_runtime.ledgers.elf_greatsword, 1)
            H.deep_equal(history_roots, expected_historical,
                "6.7.2 must alter only heavy_attack_down_first.range_mod")
            H.equal(history_refs.heavy.range_mod, 1.45)
            H.equal(history_refs.heavy.total_time, 1.4)
            H.equal(history_refs.light_sibling,
                history_refs.template.actions.action_one.light_attack_left)
            H.equal(history_refs.template_sibling, history_refs.template.metadata)

            local restored = assert(history_runtime:restore())
            H.equal(restored.refused, 0)
            H.equal(restored.changed, true)
            H.deep_equal(history_roots, history_before,
                "history restore must recover the exact current source state")
            H.equal(history_refs.heavy.range_mod, 1.55)
            local second_restore = assert(history_runtime:restore())
            H.equal(second_restore.changed, false)
            H.deep_equal(history_roots, history_before,
                "repeated restore must not introduce writes")

            local mismatch_roots, mismatch_refs = roots_with_range(1.56)
            local mismatch_before = clone(mismatch_roots)
            local mismatch_mod = mod_fixture({
                wt_history_elf_greatsword = "6_7_2",
            }, { value = true })
            local mismatch_runtime = Runtime.install({
                catalog = catalog,
                mod = mismatch_mod,
                policy = Policy,
                roots = mismatch_roots,
            })
            H.equal(mismatch_runtime.fatal_error, nil)
            H.truthy(mismatch_runtime.last_error
                and mismatch_runtime.last_error:find(
                    "current guard mismatch", 1, true) ~= nil)
            H.equal(#(mismatch_runtime.ledgers.elf_greatsword or {}), 0)
            H.deep_equal(mismatch_roots, mismatch_before,
                "guard mismatch must refuse before the first mutation")
            H.equal(mismatch_refs.heavy.range_mod, 1.56)
            H.equal(mismatch_refs.light_sibling,
                mismatch_refs.template.actions.action_one.light_attack_left)
            H.equal(mismatch_refs.template_sibling, mismatch_refs.template.metadata)
        end)
    end)

    H.test("WT #1436 Current registers profiles but performs no gameplay writes", function()
        with_profile_globals(function()
            local catalog = catalog_fixture()
            local roots, original_tuning = roots_fixture()
            local parity = { value = false }
            local mod = mod_fixture({ wt_history_elf_one_handed_axe = "current" }, parity)
            local template = roots.Weapons.we_1h_axe_template_1
            local runtime = Runtime.install({
                catalog = catalog, mod = mod, policy = Policy, roots = roots,
            })

            H.equal(runtime.fatal_error, nil)
            H.equal(runtime:verify(), nil)
            H.equal(#(runtime.ledgers.elf_one_handed_axe or {}), 0)
            H.equal(template.stats.tuning, original_tuning,
                "Current must preserve exact native table identity")
            H.equal(template.stats.tempo, 10)
            H.equal(template.actions.action_one.default.damage_profile, "native_profile")
            H.truthy(DamageProfileTemplates.wt_hist_5_1_1_native_profile ~= nil,
                "private profiles must be catalogued before #431 fingerprints them")
        end)
    end)

    H.test("WT #1436 family preflight guard failure performs zero gameplay writes", function()
        with_profile_globals(function()
            local catalog = catalog_fixture()
            local roots, original_tuning = roots_fixture()
            local template = roots.Weapons.we_1h_axe_template_1
            template.stats.tempo = 999
            local parity = { value = false }
            local mod = mod_fixture({ wt_history_elf_one_handed_axe = "5_1_1" }, parity)
            local runtime = Runtime.install({
                catalog = catalog, mod = mod, policy = Policy, roots = roots,
            })

            H.truthy(runtime.last_error
                and runtime.last_error:find("current guard mismatch", 1, true))
            H.equal(#(runtime.ledgers.elf_one_handed_axe or {}), 0)
            H.equal(template.stats.tuning, original_tuning,
                "an earlier valid operation must not leak past a later failed guard")
            H.equal(template.stats.tempo, 999)
            H.equal(template.actions.action_one.default.damage_profile, "native_profile")
        end)
    end)

    H.test("WT #1436 missing direct profile route refuses the whole family", function()
        with_profile_globals(function()
            local catalog = catalog_fixture()
            local roots, original_tuning = roots_fixture()
            local template = roots.Weapons.we_1h_axe_template_1
            template.actions.action_one.default.damage_profile = "renamed_profile"
            local parity = { value = true }
            local mod = mod_fixture({ wt_history_elf_one_handed_axe = "5_1_1" }, parity)
            local runtime = Runtime.install({
                catalog = catalog, mod = mod, policy = Policy, roots = roots,
            })

            H.truthy(runtime.last_error
                and runtime.last_error:find("native profile route not found native_profile",
                    1, true))
            H.equal(#(runtime.ledgers.elf_one_handed_axe or {}), 0,
                "a missing direct route must refuse before any family commit")
            H.equal(template.stats.tuning, original_tuning)
            H.equal(template.stats.tempo, 10)
            H.equal(template.actions.action_one.default.damage_profile, "renamed_profile")
        end)
    end)

    H.test("WT #1436 settings are restart-latched and never hot-apply", function()
        with_profile_globals(function()
            local catalog = catalog_fixture()
            local roots, original_tuning = roots_fixture()
            local parity = { value = false }
            local mod = mod_fixture({ wt_history_elf_one_handed_axe = "current" }, parity)
            local runtime = Runtime.install({
                catalog = catalog, mod = mod, policy = Policy, roots = roots,
            })
            mod.selections.wt_history_elf_one_handed_axe = "5_1_1"
            H.equal(runtime:on_setting_changed("wt_history_elf_one_handed_axe"), true)
            H.equal(runtime.pending.wt_history_elf_one_handed_axe, true)
            H.equal(roots.Weapons.we_1h_axe_template_1.stats.tuning, original_tuning)
            H.equal(roots.Weapons.we_1h_axe_template_1.stats.tempo, 10)
            H.equal(runtime:on_setting_changed("unrelated_setting"), false)

            mod.selections.wt_history_elf_one_handed_axe = "current"
            H.equal(runtime:on_setting_changed("wt_history_elf_one_handed_axe"), true)
            H.equal(runtime.pending.wt_history_elf_one_handed_axe, nil)
        end)
    end)

    H.test("WT #1436 lifecycle owner reconciles history before ordinary overlays", function()
        local events = {}
        local runtime = {
            reapply = function()
                events[#events + 1] = "history_reapply"
                return { refused = 0 }
            end,
            restore = function()
                events[#events + 1] = "history_restore"
                return { refused = 0 }
            end,
        }
        local catalog = catalog_fixture()
        local policy = {}
        local runtime_config
        local modules = {
            ["test/_wt_history_catalog"] = {
                load = function() return catalog end,
            },
            ["test/_wt_history_policy"] = policy,
            ["test/_wt_history_runtime"] = {
                install = function(config)
                    runtime_config = config
                    return runtime
                end,
            },
        }
        local mod = {}
        function mod:dofile(path) return assert(modules[path], path) end
        function mod._wt_apply_axe_balance(_, revert)
            events[#events + 1] = revert and "axe_revert" or "axe_reapply"
        end
        function mod._wt_reset_axe_balance_baselines()
            events[#events + 1] = "axe_reset"
            return true
        end

        local owner = HistoryOwner.install({ mod = mod, module_root = "test/" })
        H.equal(owner.runtime, runtime)
        H.equal(mod._wt_history_runtime, runtime)
        H.equal(runtime_config.catalog, catalog)
        H.equal(runtime_config.policy, policy)
        H.equal(type(runtime_config.is_server), "function")
        H.equal(type(runtime_config.roots), "function")

        H.equal(owner:reconcile("test"), true)
        H.deep_equal(events, {
            "axe_revert", "axe_reset", "history_reapply", "axe_reapply",
        })
        events = {}
        H.equal(owner:restore(), true)
        H.deep_equal(events, { "axe_revert", "axe_reset", "history_restore" })
        H.equal(type(mod._wt_reconcile_history_owner_stack), "function")
    end)

    H.test("WT #1436 private profile registration is idempotent and isolated", function()
        with_profile_globals(function(native_profile)
            local catalog = catalog_fixture()
            local roots = roots_fixture()
            local parity = { value = false }
            local mod = mod_fixture({ wt_history_elf_one_handed_axe = "current" }, parity)
            local first = Runtime.install({
                catalog = catalog, mod = mod, policy = Policy, roots = roots,
            })
            local private = DamageProfileTemplates.wt_hist_5_1_1_native_profile
            local lookup_count = #NetworkLookup.damage_profiles
            local second = Runtime.install({
                catalog = catalog, mod = mod, policy = Policy, roots = roots,
            })

            H.equal(first.registration.count, 1)
            H.equal(second.registration.count, 1)
            H.equal(DamageProfileTemplates.wt_hist_5_1_1_native_profile, private,
                "idempotent install must retain the registered object")
            H.equal(#NetworkLookup.damage_profiles, lookup_count,
                "idempotent install must not append another network row")
            H.equal(NetworkLookup.damage_profiles[private.name], lookup_count)
            H.truthy(private ~= catalog.profile_specs["5_1_1"].native_profile.historical_profile)
            H.truthy(private ~= native_profile)
            H.truthy(private.default_target
                ~= catalog.profile_specs["5_1_1"].native_profile.historical_profile.default_target)
            private.default_target.power_distribution.attack = 123
            H.equal(catalog.profile_specs["5_1_1"].native_profile
                .historical_profile.default_target.power_distribution.attack, 5,
                "registered mutations must not contaminate generated evidence")
            H.equal(native_profile.default_target.power_distribution.attack, 3,
                "registered mutations must not contaminate the native fallback")
            H.equal(mod._wt431_custom_profile_fallback[private.name], "native_profile")
        end)
    end)

    H.test("WT #1436 profile assignment gates on parity and lifecycle replacement reapplies", function()
        with_profile_globals(function()
            local catalog = catalog_fixture()
            local roots, original_tuning = roots_fixture()
            local old_roots = roots
            local parity = { value = false }
            local mod = mod_fixture({ wt_history_elf_one_handed_axe = "5_1_1" }, parity)
            local runtime = Runtime.install({
                catalog = catalog, mod = mod, policy = Policy,
                roots = function() return roots end,
            })
            local old_template = roots.Weapons.we_1h_axe_template_1
            H.equal(runtime:verify(), nil)
            H.equal(old_template.stats.tempo, 8)
            H.equal(old_template.actions.action_one.default.damage_profile, "native_profile",
                "mixed/mismatched peers must retain the native profile")
            H.equal(runtime.active.elf_one_handed_axe.parity, false)

            parity.value = true
            local parity_result = assert(runtime:reapply())
            H.equal(parity_result.refused, 0)
            H.equal(old_template.actions.action_one.default.damage_profile,
                "wt_hist_5_1_1_native_profile")
            H.equal(runtime:verify(), nil)

            local replacement_tuning
            roots, replacement_tuning = roots_fixture()
            local replacement = roots.Weapons.we_1h_axe_template_1
            local lifecycle_result = assert(runtime:reapply())
            H.equal(lifecycle_result.refused, 0)
            H.equal(old_roots.Weapons.we_1h_axe_template_1.stats.tuning, original_tuning,
                "reapply must restore the exact superseded native reference")
            H.equal(old_template.stats.tempo, 10)
            H.equal(old_template.actions.action_one.default.damage_profile, "native_profile")
            H.equal(replacement.stats.tempo, 8)
            H.equal(replacement.actions.action_one.default.damage_profile,
                "wt_hist_5_1_1_native_profile")
            H.equal(runtime:verify(), nil)

            local restore_result = assert(runtime:restore())
            H.equal(restore_result.refused, 0)
            H.equal(replacement.stats.tuning, replacement_tuning,
                "disable restore must preserve the exact replacement baseline reference")
            H.equal(replacement.stats.tempo, 10)
            H.equal(replacement.actions.action_one.default.damage_profile, "native_profile")
        end)
    end)

    H.test("WT #1436 generated Elf Axe moveset is one exact atomic plan", function()
        local catalog = assert(loadfile(script_root .. "_wt_history_5_2_catalog.lua"))()
        local family
        for _, candidate in ipairs(catalog.families) do
            if candidate.id == "elf_one_handed_axe" then family = candidate end
        end
        H.truthy(family, "generated catalog must own Elf 1H Axe")
        local state = family.states["5_1_1"]
        H.equal(state.atomic_group, "P520-ELF1HA-MOVESET")
        H.truthy(#state.operations > 1)

        local roots, originals = materialize_expected_roots(state)
        local corrupt = originals[#originals]
        rawset(corrupt.parent, corrupt.key, { deliberately = "wrong" })
        local rejected, rejection = Policy.build_family_plan(
            catalog, family, "5_1_1", roots, { validated = true })
        H.equal(rejected, nil)
        H.truthy(rejection and rejection:find("current guard mismatch", 1, true))
        for index = 1, #originals - 1 do
            H.equal(rawget(originals[index].parent, originals[index].key),
                originals[index].value,
                "failed atomic preflight must not touch any earlier Elf Axe member")
        end

        rawset(corrupt.parent, corrupt.key, corrupt.value)
        local plan = assert(Policy.build_family_plan(
            catalog, family, "5_1_1", roots, { validated = true }))
        H.equal(#plan, #state.operations,
            "the entire source-exact moveset must commit as one plan")
        local ledger = assert(Policy.commit(plan))
        H.equal(Policy.ledger_status(ledger, roots), "same")
        H.equal(Policy.restore(ledger), true)
        for index, original in ipairs(originals) do
            H.equal(rawget(original.parent, original.key), original.value,
                "restore must recover exact pre-patch reference at operation " .. index)
        end
    end)

    H.test("WT #1436 nested mutation loses history restore ownership", function()
        local catalog = catalog_fixture()
        local roots, original_tuning = roots_fixture()
        local family = catalog.families[1]
        local plan = assert(Policy.build_family_plan(
            catalog, family, "5_1_1", roots))
        local ledger = assert(Policy.commit(plan))
        local applied_tuning = roots.Weapons.we_1h_axe_template_1.stats.tuning

        H.equal(Policy.ledger_status(ledger, roots), "same")
        applied_tuning.cleave[1] = 999
        H.equal(Policy.ledger_status(ledger, roots), "drift",
            "in-place mutation of a history-owned table must be detected")

        local restored, restore_error = Policy.restore(ledger)
        H.equal(restored, nil,
            "history must not overwrite a value whose nested ownership was lost")
        H.truthy(restore_error
            and restore_error:find("restore ownership lost", 1, true))
        H.equal(roots.Weapons.we_1h_axe_template_1.stats.tuning, applied_tuning,
            "failed restore must leave the third-party-mutated reference untouched")
        H.equal(original_tuning.cleave[1], 1,
            "history application and drift must not mutate the native baseline")
    end)

    H.test("WT #1436 historical 1H Axe profiles prewarm and compose safely", function()
        local state = AxeBalance.new()
        local history_name = "wt_hist_5_1_1_medium_slashing_smiter_1h_axe"
        local native_name = "medium_slashing_smiter_1h_axe"
        local weapon = {
            actions = { action_one = { light_attack_left = {
                damage_profile = history_name, kind = "sweep",
            } } },
            buff_type = "MELEE_1H",
            state_machine = "units/beings/player/first_person_base/state_machines/melee/1h_axe",
            weapon_type = "AXE_1H",
        }
        local weapons = { one_hand_axe_template_1 = weapon }
        local profiles = {
            [native_name] = { cleave_distribution = { attack = 1, impact = 2 } },
            [history_name] = { cleave_distribution = { attack = 3, impact = 4 } },
        }
        local power_levels, registered = {}, {}
        local fallbacks = { [history_name] = native_name }
        local function register(name) registered[name] = true end
        state:apply_one_hand_axe_cleave(false, weapons, profiles, power_levels,
            clone, register, fallbacks, false, { history_name })
        local derived = "wt_1h_axe_cleave_90_" .. history_name
        H.truthy(profiles[derived] ~= nil,
            "history composition profile must exist before #431 capture")
        H.equal(fallbacks[derived], native_name,
            "derived history profile must fall back directly to a native donor")
        H.equal(registered[derived], true)

        state:apply_one_hand_axe_cleave(true, weapons, profiles, power_levels,
            clone, register, fallbacks, true, { history_name })
        H.equal(weapon.actions.action_one.light_attack_left.damage_profile, derived)
        state:apply_one_hand_axe_cleave(false, weapons, profiles, power_levels,
            clone, register, fallbacks, false, { history_name })
        H.equal(weapon.actions.action_one.light_attack_left.damage_profile, history_name)
        H.equal(state:reset_baselines(), true)
    end)
end

return register
