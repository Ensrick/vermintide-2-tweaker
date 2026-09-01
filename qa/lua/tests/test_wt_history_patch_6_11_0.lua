-- Patch 6.11.0 source-exact Longbow and shared Hammer/Mace coverage (#1436).

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

    H.test("WT #1436 Patch 6.11.0 catalog pins Longbow and Hammer/Mace", function()
        local catalog = assert(loadfile(script_root
            .. "_wt_history_6_11_0_catalog.lua"))()
        local valid, validation_error = Policy.validate(catalog)
        H.equal(validation_error, nil)
        H.equal(valid, true)
        H.equal(catalog.schema, 2)
        H.equal(catalog.catalog_id, "wt_history_patch_6_11_0_v2")
        H.equal(catalog.current_id, "current")
        H.equal(catalog.current_source.revision,
            "038498af2b565bcb10bf5ed225638293a7640c83")
        H.equal(#catalog.families, 2)
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
            adjacent_operation_count = 8,
            global_operations = 0,
            profile_route_count = 0,
            unsupported_count = 0,
        })

        local group = assert(CatalogUI.build_widgets(catalog))
        H.equal(#group.sub_widgets, 2)
        for _, widget in ipairs(group.sub_widgets) do
            H.equal(widget.default_value, "current")
            H.deep_equal(widget.options, {
                { text = "wt_history_state_current", value = "current" },
                { text = "wt_history_state_6_10_0", value = "6_10_0" },
            })
        end
        local localization = assert(CatalogUI.build_localization(catalog))
        H.equal(localization.wt_history_family_kruber_longbow.en,
            "Kruber's Longbow")
        H.equal(localization.wt_history_family_one_handed_hammer_shared.en,
            "One-handed Hammer/Mace (Kruber, Bardin, and Saltzpyre)")
        H.equal(localization.wt_history_state_6_10_0.en,
            "Game Version 6.10.0")
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
