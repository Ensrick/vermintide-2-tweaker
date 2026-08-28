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
            PlayerUnitStatusSettings = {}, Weapons = {},
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

    H.test("WT #1436 generated Patch 5.2 catalog passes strict schema validation", function()
        local catalog = assert(loadfile(script_root .. "_wt_history_5_2_catalog.lua"))()
        local valid, validation_error = Policy.validate(catalog)
        H.equal(validation_error, nil)
        H.equal(valid, true)
        H.equal(catalog.schema, 2)
        H.equal(#catalog.families, 14)
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
    end)

    H.test("WT #1436 menu and localization share the generated family catalog", function()
        local catalog = assert(loadfile(script_root .. "_wt_history_5_2_catalog.lua"))()
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
        end
    end)

    H.test("WT #1436 data decoration inserts one history group and fails closed", function()
        local catalog = catalog_fixture()
        local loads = 0
        local mod = {}
        function mod:dofile(path)
            H.equal(path, CatalogUI.GENERATED_MODULE)
            loads = loads + 1
            return catalog
        end
        local first = { setting_id = "first" }
        local second = { setting_id = "second" }
        local data = { options = { widgets = { first, second } } }

        H.equal(CatalogUI.decorate_menu(mod, data), data)
        H.equal(data.options.widgets[1], first)
        H.equal(data.options.widgets[2].setting_id, "wt_history_patch_versions")
        H.equal(data.options.widgets[3], second)
        H.equal(loads, 1)
        H.equal(CatalogUI.decorate_menu(mod, data), data)
        H.equal(#data.options.widgets, 3)
        H.equal(loads, 1, "re-decoration must not reload or duplicate the group")

        local malformed = { options = {} }
        H.equal(CatalogUI.decorate_menu(mod, malformed), malformed)
        H.equal(loads, 1, "malformed menu data must not load the generated catalog")
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
            local catalog = assert(loadfile(stream.root
                .. "_wt_history_5_2_catalog.lua"))()
            local loads = 0
            local mod = {}
            function mod:dofile(path)
                H.equal(path, catalog_ui.GENERATED_MODULE)
                loads = loads + 1
                return catalog
            end
            local availability = { setting_id = "weapon_availability" }
            local overrides = { setting_id = "weapon_overrides" }
            local data = { options = { widgets = { availability, overrides } } }
            H.equal(catalog_ui.decorate_menu(mod, data), data)
            H.equal(data.options.widgets[1], availability)
            H.equal(data.options.widgets[2].setting_id,
                "wt_history_patch_versions")
            H.equal(#data.options.widgets[2].sub_widgets, 14)
            H.equal(data.options.widgets[3], overrides)
            H.equal(loads, 1)
            H.equal(catalog_ui.decorate_menu(mod, data), data)
            H.equal(#data.options.widgets, 3,
                stream.namespace .. " must not duplicate its history group")
            H.equal(loads, 1,
                stream.namespace .. " must reuse its generated-catalog cache")
        end
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
