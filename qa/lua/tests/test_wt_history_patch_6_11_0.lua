-- Patch 6.11.0 source-exact Longbow, shared Hammer/Mace, and Kerillian
-- Swiftbow coverage (#1436).

local function read_file(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

local function register(H, repo_root)
    local script_root = repo_root
        .. "/weapon_tweaker/scripts/mods/weapon_tweaker/"
    local Policy = assert(loadfile(script_root .. "_wt_history_policy.lua"))()
    local Runtime = assert(loadfile(script_root .. "_wt_history_runtime.lua"))()
    local CatalogUI = assert(loadfile(script_root .. "_wt_history_catalog.lua"))()

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

    local function with_empty_profile_globals(body)
        local had_profiles = rawget(_G, "DamageProfileTemplates") ~= nil
        local prior_profiles = rawget(_G, "DamageProfileTemplates")
        local had_lookup = rawget(_G, "NetworkLookup") ~= nil
        local prior_lookup = rawget(_G, "NetworkLookup")
        local had_printf = rawget(_G, "printf") ~= nil
        local prior_printf = rawget(_G, "printf")
        rawset(_G, "DamageProfileTemplates", {})
        rawset(_G, "NetworkLookup", { damage_profiles = {} })
        rawset(_G, "printf", function() end)
        local result = { xpcall(body, debug.traceback) }
        rawset(_G, "DamageProfileTemplates",
            had_profiles and prior_profiles or nil)
        rawset(_G, "NetworkLookup", had_lookup and prior_lookup or nil)
        rawset(_G, "printf", had_printf and prior_printf or nil)
        if not result[1] then error(result[2], 0) end
        return unpack(result, 2)
    end

    local function mod_fixture(hammer_state)
        local mod = {}
        function mod:get(setting_id)
            if setting_id == "wt_history_one_handed_hammer_shared" then
                return hammer_state
            end
            return "current"
        end
        mod._wt431_profiles_allowed = function() return true end
        return mod
    end

    local function hammer_roots(overrides)
        overrides = overrides or {}
        local templates = {}
        local references = {}
        for _, name in ipairs({
            "one_handed_hammer_template_1",
            "one_handed_hammer_template_2",
            "one_handed_hammer_priest_template",
        }) do
            local metadata = { marker = name }
            local template = {
                block_angle = 120,
                dodge_count = 4,
                metadata = metadata,
            }
            for key, value in pairs(overrides[name] or {}) do
                template[key] = value
            end
            templates[name] = template
            references[name] = { metadata = metadata, template = template }
        end
        return {
            BuffTemplates = {},
            ExplosionTemplates = {},
            PlayerUnitStatusSettings = {},
            VortexTemplates = {},
            Weapons = templates,
        }, references
    end

    H.test("WT #1436 Patch 6.11.0 catalog pins three bounded families", function()
        local catalog = assert(loadfile(script_root
            .. "_wt_history_6_11_0_catalog.lua"))()
        local valid, validation_error = Policy.validate(catalog)
        H.equal(validation_error, nil)
        H.equal(valid, true)
        H.equal(catalog.schema, 2)
        H.equal(catalog.catalog_id, "wt_history_patch_6_11_0_v3")
        H.equal(catalog.current_id, "current")
        H.equal(catalog.current_source.revision,
            "25fd7b8433e839b678d1c98a7a9af80918cbc252")
        H.equal(#catalog.families, 3)
        H.equal(next(catalog.profile_specs), nil)
        H.equal(next(catalog.derived_profiles), nil)

        local family = catalog.families[1]
        H.equal(family.id, "kruber_longbow")
        H.equal(family.setting_id, "wt_history_kruber_longbow")
        H.deep_equal(family.templates, {
            "longbow_empire_template",
            "longbow_empire_tutorial_template",
        })
        H.deep_equal(family.state_order, { "6_10_0" })
        H.equal(catalog.states["6_10_0"].display_name,
            "Game Version 6.10.0")
        H.equal(catalog.states["6_10_0"].source_revision,
            "5ff26df11311ba011f3313b9b232ed0d8b64b921")
        H.equal(catalog.states["6_10_0"].official_patch_notes,
            "https://forums.fatsharkgames.com/t/weapon-balance-update-patch-6-11-0-patch-notes/121528")

        local state = family.states["6_10_0"]
        H.deep_equal(state.profile_names, {})
        H.deep_equal(state.direct_profile_names, {})
        H.equal(#state.operations, 2)
        for index, template in ipairs(family.templates) do
            local row = state.operations[index]
            H.equal(row.root, "Weapons")
            H.equal(row.template, template)
            H.deep_equal(row.path, {
                "actions", "action_two", "default", "aim_zoom_delay",
            })
            H.equal(row.expected_current, 0.22)
            H.equal(row.result, 2)
            H.equal(row.expected_present, true)
            H.equal(row.result_present, true)
            H.equal(row.family_id, family.id)
            H.equal(row.state_id, "6_10_0")
            H.equal(row.official_change_id,
                "P6110-KRUBER-LONGBOW-AUTOZOOM")
            H.equal(row.change_class, "official_weapon_balance")
            H.equal(row.source_revision,
                "5ff26df11311ba011f3313b9b232ed0d8b64b921")
            H.equal(row.source_blob,
                "6408a36495e3c78e9a9ed2dbc91a913c512d9aed")
            H.equal(row.current_source_blob,
                "a4685fbd52464f3a65ade77776a85a131dea8476")
            H.equal(row.source_path,
                "scripts/settings/equipment/weapon_templates/longbows_empire.lua")
        end
        local hammer = catalog.families[2]
        H.equal(hammer.id, "one_handed_hammer_shared")
        H.equal(hammer.setting_id, "wt_history_one_handed_hammer_shared")
        H.deep_equal(hammer.templates, {
            "one_handed_hammer_template_1",
            "one_handed_hammer_template_2",
            "one_handed_hammer_priest_template",
        })
        H.deep_equal(hammer.state_order, { "6_10_0" })
        local hammer_state = hammer.states["6_10_0"]
        H.deep_equal(hammer_state.profile_names, {})
        H.deep_equal(hammer_state.direct_profile_names, {})
        H.equal(#hammer_state.operations, 6)
        for template_index, template in ipairs(hammer.templates) do
            for path_index, path in ipairs({ "block_angle", "dodge_count" }) do
                local operation_index = (template_index - 1) * 2 + path_index
                local hammer_row = hammer_state.operations[operation_index]
                H.equal(hammer_row.root, "Weapons")
                H.equal(hammer_row.template, template)
                H.deep_equal(hammer_row.path, { path })
                H.equal(hammer_row.expected_current,
                    path == "block_angle" and 120 or 4)
                H.equal(hammer_row.result, path == "block_angle" and 90 or 3)
                H.equal(hammer_row.expected_present, true)
                H.equal(hammer_row.result_present, true)
                H.equal(hammer_row.family_id, hammer.id)
                H.equal(hammer_row.state_id, "6_10_0")
                H.equal(hammer_row.official_change_id,
                    "P6110-1HH-BLOCK-DODGE")
                H.equal(hammer_row.change_class, "official_weapon_balance")
                H.equal(hammer_row.source_revision,
                    "5ff26df11311ba011f3313b9b232ed0d8b64b921")
                H.equal(hammer_row.current_source_blob,
                    template == "one_handed_hammer_priest_template"
                        and "dbea759457f3949b685e9e98dfd98cf4063de488"
                        or "a67eb83ad27bcb86f0b88f52dcf8d4a5c8650c6d")
                H.equal(hammer_row.source_blob,
                    template == "one_handed_hammer_priest_template"
                        and "abc4699a266616fda0d5f9bbb81a665efac7c7e5"
                        or "2a6b000b2d322fa980c4ec2262dc4e36599af9eb")
            end
        end
        H.deep_equal(catalog.generation, {
            adjacent_operation_count = 9,
            global_operations = 0,
            profile_route_count = 0,
            unsupported_count = 0,
        })

        local group = assert(CatalogUI.build_widgets(catalog))
        H.equal(#group.sub_widgets, 3)
        for index, widget in ipairs(group.sub_widgets) do
            H.equal(widget.default_value, "current")
            H.deep_equal(widget.options, {
                { text = "wt_history_state_current", value = "current" },
                index == 3 and {
                    text = "wt_history_state_6_10_0_swiftbow_ammunition",
                    value = "6_10_0_swiftbow_ammunition",
                } or { text = "wt_history_state_6_10_0", value = "6_10_0" },
            })
        end
        local localization = assert(CatalogUI.build_localization(catalog))
        H.equal(localization.wt_history_family_kruber_longbow.en,
            "Kruber's Longbow")
        H.equal(localization.wt_history_family_one_handed_hammer_shared.en,
            "One-handed Hammer/Mace (Kruber, Bardin, and Saltzpyre)")
        H.equal(localization.wt_history_state_6_10_0.en,
            "Game Version 6.10.0")
        H.equal(localization.wt_history_family_kerillian_swiftbow.en,
            "Kerillian's Swiftbow")
        H.equal(localization.wt_history_state_6_10_0_swiftbow_ammunition.en,
            "Game Version 6.10.0 (Ammunition Only)")
        local swiftbow = catalog.families[3]
        H.equal(swiftbow.id, "kerillian_swiftbow")
        H.equal(swiftbow.setting_id, "wt_history_kerillian_swiftbow")
        H.deep_equal(swiftbow.templates, { "shortbow_template_1" })
        H.deep_equal(swiftbow.state_order, { "6_10_0_swiftbow_ammunition" })
        H.equal(swiftbow.states["6_10_0"], nil,
            "the unqualified state is not exposed as a whole Swiftbow preset")
        local ammunition = swiftbow.states["6_10_0_swiftbow_ammunition"]
        H.deep_equal(ammunition.profile_names, {})
        H.deep_equal(ammunition.direct_profile_names, {})
        H.deep_equal(ammunition.operations, { {
            change_class = "official_weapon_balance",
            current_source_blob = "67e3fa824500fb0129591d0ec698c8a872974623",
            expected_current = 60,
            expected_present = true,
            family_id = "kerillian_swiftbow",
            official_change_id = "P6110-KERILLIAN-SWIFTBOW-MAX-AMMO",
            official_summary = "Patch 6.11.0 increased the maximum ammunition of Kerillian's Swiftbow.",
            path = { "ammo_data", "max_ammo" },
            result = 50,
            result_present = true,
            root = "Weapons",
            source_blob = "8e2a9fc4338e456e8f40d4c1d4578d2b2ecd185e",
            source_path = "scripts/settings/equipment/weapon_templates/shortbows.lua",
            source_revision = "5ff26df11311ba011f3313b9b232ed0d8b64b921",
            state_id = "6_10_0_swiftbow_ammunition",
            template = "shortbow_template_1",
        } })
        H.equal(read_file(script_root .. "_wt_history_6_11_0_catalog.lua"),
            read_file(repo_root
                .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/"
                .. "_wt_history_6_11_0_catalog.lua"),
            "public and dev must carry byte-identical pure Patch 6.11.0 data")
    end)

    H.test("WT #1436 Hammer/Mace applies six leaves atomically and restores", function()
        with_empty_profile_globals(function()
            local catalog = assert(loadfile(script_root
                .. "_wt_history_6_11_0_catalog.lua"))()

            local current_roots, current_refs = hammer_roots()
            local current_before = clone(current_roots)
            local current_runtime = Runtime.install({
                catalog = catalog,
                mod = mod_fixture("current"),
                policy = Policy,
                roots = current_roots,
            })
            H.equal(current_runtime.fatal_error, nil)
            H.equal(current_runtime.last_error, nil)
            H.equal(#(current_runtime.ledgers.one_handed_hammer_shared or {}), 0)
            H.deep_equal(current_roots, current_before)
            for name, refs in pairs(current_refs) do
                H.equal(current_roots.Weapons[name], refs.template)
                H.equal(refs.template.metadata, refs.metadata)
            end

            local roots, refs = hammer_roots()
            local before = clone(roots)
            local runtime = Runtime.install({
                catalog = catalog,
                mod = mod_fixture("6_10_0"),
                policy = Policy,
                roots = roots,
            })
            H.equal(runtime.fatal_error, nil)
            H.equal(runtime.last_error, nil)
            H.equal(#runtime.ledgers.one_handed_hammer_shared, 6)
            for name, identity in pairs(refs) do
                H.equal(identity.template.block_angle, 90)
                H.equal(identity.template.dodge_count, 3)
                H.equal(roots.Weapons[name], identity.template)
                H.equal(identity.template.metadata, identity.metadata)
            end
            local ledger = runtime.ledgers.one_handed_hammer_shared
            local reapplied = assert(runtime:reapply())
            H.equal(reapplied.changed, false)
            H.equal(reapplied.writes, 6)
            H.equal(runtime.ledgers.one_handed_hammer_shared, ledger)
            local restored = assert(runtime:restore())
            H.equal(restored.changed, true)
            H.equal(restored.refused, 0)
            H.equal(restored.writes, 0)
            H.deep_equal(roots, before)
            for name, identity in pairs(refs) do
                H.equal(roots.Weapons[name], identity.template)
                H.equal(identity.template.metadata, identity.metadata)
            end

            local foreign_roots = hammer_roots({
                one_handed_hammer_template_2 = { dodge_count = 99 },
            })
            local foreign_before = clone(foreign_roots)
            local foreign_runtime = Runtime.install({
                catalog = catalog,
                mod = mod_fixture("6_10_0"),
                policy = Policy,
                roots = foreign_roots,
            })
            H.equal(foreign_runtime.fatal_error, nil)
            H.truthy(foreign_runtime.last_error
                and foreign_runtime.last_error:find(
                    "current guard mismatch", 1, true) ~= nil)
            H.equal(#(foreign_runtime.ledgers.one_handed_hammer_shared or {}), 0)
            H.deep_equal(foreign_roots, foreign_before,
                "one foreign leaf must refuse all six writes")

            local missing_roots = hammer_roots()
            missing_roots.Weapons.one_handed_hammer_priest_template = nil
            local missing_before = clone(missing_roots)
            local missing_runtime = Runtime.install({
                catalog = catalog,
                mod = mod_fixture("6_10_0"),
                policy = Policy,
                roots = missing_roots,
            })
            H.equal(missing_runtime.fatal_error, nil)
            H.truthy(missing_runtime.last_error ~= nil)
            H.equal(#(missing_runtime.ledgers.one_handed_hammer_shared or {}), 0)
            H.deep_equal(missing_roots, missing_before,
                "one missing template must refuse all six writes")
        end)
    end)

    local function swiftbow_fixture(state, mutate)
        local roots, references = hammer_roots()
        local ammo = { max_ammo = 60, ammo_per_clip = 1, reload_time = 0.2 }
        local action = { damage_profile = "arrow_sniper" }
        local template = { ammo_data = ammo, actions = { action_one = action } }
        roots.Weapons.shortbow_template_1 = template
        roots.Weapons.shortbow_hagbane_template_1 = { ammo_data = { max_ammo = 40 } }
        if mutate then mutate(roots, template) end
        local before = clone(roots)
        local mod = mod_fixture("current")
        function mod:get(setting_id)
            if setting_id == "wt_history_kerillian_swiftbow" then return state end
            return "current"
        end
        local runtime = Runtime.install({
            catalog = assert(loadfile(script_root .. "_wt_history_6_11_0_catalog.lua"))(),
            mod = mod, policy = Policy, roots = roots,
        })
        return runtime, roots, before, template, ammo, action, references, mod
    end

    H.test("WT #1436 Swiftbow Current performs no writes or profile registration", function()
        with_empty_profile_globals(function()
            local runtime, roots, before, template, ammo, action = swiftbow_fixture("current")
            H.equal(runtime.fatal_error, nil)
            H.equal(runtime.last_error, nil)
            H.equal(#(runtime.ledgers.kerillian_swiftbow or {}), 0)
            H.deep_equal(roots, before)
            H.equal(roots.Weapons.shortbow_template_1, template)
            H.equal(template.ammo_data, ammo)
            H.equal(template.actions.action_one, action)
            H.deep_equal(DamageProfileTemplates, {})
            H.deep_equal(NetworkLookup.damage_profiles, {})
        end)
    end)

    H.test("WT #1436 Swiftbow restores only capacity and exact identities", function()
        with_empty_profile_globals(function()
            local runtime, roots, before, template, ammo, action, references =
                swiftbow_fixture("6_10_0_swiftbow_ammunition")
            H.equal(runtime.fatal_error, nil)
            H.equal(runtime.last_error, nil)
            H.equal(ammo.max_ammo, 50)
            H.equal(#runtime.ledgers.kerillian_swiftbow, 1)
            local expected = clone(before)
            expected.Weapons.shortbow_template_1.ammo_data.max_ammo = 50
            H.deep_equal(roots, expected)
            local ledger = runtime.ledgers.kerillian_swiftbow
            H.equal(assert(runtime:reapply()).changed, false)
            H.equal(runtime.ledgers.kerillian_swiftbow, ledger)
            H.equal(ammo.max_ammo, 50, "repeat application must not stack")
            for name, refs in pairs(references) do
                H.equal(roots.Weapons[name], refs.template)
                H.equal(refs.template.metadata, refs.metadata)
            end
            local restored = assert(runtime:restore())
            H.equal(restored.refused, 0)
            H.deep_equal(roots, before)
            H.equal(roots.Weapons.shortbow_template_1, template)
            H.equal(template.ammo_data, ammo)
            H.equal(template.actions.action_one, action)
            H.deep_equal(DamageProfileTemplates, {})
            H.deep_equal(NetworkLookup.damage_profiles, {})
        end)
    end)

    for _, case in ipairs({
        { name = "missing template", mutate = function(roots)
            roots.Weapons.shortbow_template_1 = nil
        end },
        { name = "missing ammo table", mutate = function(_, template)
            template.ammo_data = nil
        end },
        { name = "missing capacity", mutate = function(_, template)
            template.ammo_data.max_ammo = nil
        end },
        { name = "foreign capacity", mutate = function(_, template)
            template.ammo_data.max_ammo = 99
        end },
    }) do
        H.test("WT #1436 Swiftbow refuses " .. case.name .. " before mutation", function()
            with_empty_profile_globals(function()
                local runtime, roots, before = swiftbow_fixture(
                    "6_10_0_swiftbow_ammunition", case.mutate)
                H.equal(runtime.fatal_error, nil)
                H.truthy(runtime.last_error ~= nil)
                H.equal(#(runtime.ledgers.kerillian_swiftbow or {}), 0)
                H.deep_equal(roots, before)
                H.deep_equal(DamageProfileTemplates, {})
                H.deep_equal(NetworkLookup.damage_profiles, {})
            end)
        end)
    end

    H.test("WT #1436 Swiftbow selection is startup-only and rejects unqualified state", function()
        with_empty_profile_globals(function()
            local runtime, roots, _, _, ammo, _, _, mod = swiftbow_fixture("current")
            function mod:get(setting_id)
                return setting_id == "wt_history_kerillian_swiftbow"
                    and "6_10_0_swiftbow_ammunition" or "current"
            end
            assert(runtime:reapply())
            H.equal(ammo.max_ammo, 60, "changed preference waits for restart")
            runtime:restore()
            local invalid, invalid_roots, invalid_before = swiftbow_fixture("6_10_0")
            H.equal(invalid.boot_selections.wt_history_kerillian_swiftbow, "current")
            H.equal(#(invalid.ledgers.kerillian_swiftbow or {}), 0)
            H.deep_equal(invalid_roots, invalid_before)
            H.equal(roots.Weapons.shortbow_template_1.ammo_data, ammo)
        end)
    end)

    H.test("WT #1436 Swiftbow composes independently with both existing families", function()
        with_empty_profile_globals(function()
            local roots = hammer_roots()
            for _, name in ipairs({ "longbow_empire_template", "longbow_empire_tutorial_template" }) do
                roots.Weapons[name] = {
                    actions = { action_two = { default = { aim_zoom_delay = 0.22 } } },
                }
            end
            roots.Weapons.shortbow_template_1 = {
                ammo_data = { max_ammo = 60, reload_time = 0.2 },
            }
            local before = clone(roots)
            local mod = mod_fixture("current")
            function mod:get(setting_id)
                return setting_id == "wt_history_kerillian_swiftbow"
                    and "6_10_0_swiftbow_ammunition" or "6_10_0"
            end
            local runtime = Runtime.install({
                catalog = assert(loadfile(script_root .. "_wt_history_6_11_0_catalog.lua"))(),
                mod = mod, policy = Policy, roots = roots,
            })
            H.equal(runtime.last_error, nil)
            H.equal(#runtime.ledgers.kruber_longbow, 2)
            H.equal(#runtime.ledgers.one_handed_hammer_shared, 6)
            H.equal(#runtime.ledgers.kerillian_swiftbow, 1)
            H.equal(roots.Weapons.shortbow_template_1.ammo_data.max_ammo, 50)
            H.equal(roots.Weapons.longbow_empire_template.actions.action_two.default.aim_zoom_delay, 2)
            H.equal(roots.Weapons.one_handed_hammer_template_1.block_angle, 90)
            -- An ordinary tweak applied after startup owns only its own leaf.
            -- Reconciliation must retain that overlay without re-stacking history.
            roots.Weapons.shortbow_template_1.ammo_data.reload_time = 0.1
            assert(runtime:reapply())
            H.equal(roots.Weapons.shortbow_template_1.ammo_data.max_ammo, 50)
            H.equal(roots.Weapons.shortbow_template_1.ammo_data.reload_time, 0.1)
            H.equal(assert(runtime:restore()).refused, 0)
            before.Weapons.shortbow_template_1.ammo_data.reload_time = 0.1
            H.deep_equal(roots, before,
                "all history restores exactly without erasing a later independent tweak")
        end)
    end)

    H.test("WT #1436 Patch 6.11.0 history installs before ordinary adapters", function()
        for _, stream in ipairs({
            {
                file = repo_root
                    .. "/weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua",
                history = "scripts/mods/weapon_tweaker/_wt_history_owner",
                ordinary = "scripts/mods/weapon_tweaker/_wt_cross_char_template_patches",
            },
            {
                file = repo_root
                    .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/weapon_tweaker_dev.lua",
                history = "scripts/mods/weapon_tweaker_dev/_wt_history_owner",
                ordinary = "scripts/mods/weapon_tweaker_dev/_wt_cross_char_template_patches",
            },
        }) do
            local source = read_file(stream.file)
            local history_at = assert(source:find(stream.history, 1, true))
            local ordinary_at = assert(source:find(stream.ordinary, 1, true))
            H.truthy(history_at < ordinary_at,
                "history must establish the selected baseline before ordinary WT adapters")
        end
    end)
end

return register
