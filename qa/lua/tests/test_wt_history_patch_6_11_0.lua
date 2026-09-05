-- Patch 6.11.0 source-exact Kruber Longbow catalog coverage (#1436).

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
    local CatalogUI = assert(loadfile(script_root .. "_wt_history_catalog.lua"))()

    H.test("WT #1436 generated Patch 6.11.0 catalog pins both Longbow routes", function()
        local catalog = assert(loadfile(script_root
            .. "_wt_history_6_11_0_catalog.lua"))()
        local valid, validation_error = Policy.validate(catalog)
        H.equal(validation_error, nil)
        H.equal(valid, true)
        H.equal(catalog.schema, 2)
        H.equal(catalog.catalog_id,
            "wt_history_patch_6_11_0_kruber_longbow_v1")
        H.equal(catalog.current_id, "current")
        H.equal(catalog.current_source.revision,
            "25fd7b8433e839b678d1c98a7a9af80918cbc252")
        H.equal(#catalog.families, 1)
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
        H.deep_equal(catalog.generation, {
            adjacent_operation_count = 2,
            global_operations = 0,
            profile_route_count = 0,
            unsupported_count = 0,
        })

        local group = assert(CatalogUI.build_widgets(catalog))
        H.equal(#group.sub_widgets, 1)
        H.equal(group.sub_widgets[1].default_value, "current")
        H.deep_equal(group.sub_widgets[1].options, {
            { text = "wt_history_state_current", value = "current" },
            { text = "wt_history_state_6_10_0", value = "6_10_0" },
        })
        local localization = assert(CatalogUI.build_localization(catalog))
        H.equal(localization.wt_history_family_kruber_longbow.en,
            "Kruber's Longbow")
        H.equal(localization.wt_history_state_6_10_0.en,
            "Game Version 6.10.0")
        H.equal(read_file(script_root .. "_wt_history_6_11_0_catalog.lua"),
            read_file(repo_root
                .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/"
                .. "_wt_history_6_11_0_catalog.lua"),
            "public and dev must carry byte-identical pure Patch 6.11.0 data")
    end)

    H.test("WT #1436 Longbow history installs before ordinary weapon adapters", function()
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
