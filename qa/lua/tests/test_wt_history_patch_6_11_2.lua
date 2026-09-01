-- Hotfix 6.11.2 source-exact Sienna Dagger catalog coverage (#1436).

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

    H.test("WT #1436 generated Hotfix 6.11.2 catalog pins one exact Dagger change", function()
        local catalog = assert(loadfile(script_root
            .. "_wt_history_6_11_2_catalog.lua"))()
        local valid, validation_error = Policy.validate(catalog)
        H.equal(validation_error, nil)
        H.equal(valid, true)
        H.equal(catalog.schema, 2)
        H.equal(catalog.catalog_id,
            "wt_history_patch_6_11_2_sienna_dagger_v1")
        H.equal(catalog.current_id, "current")
        H.equal(catalog.current_source.revision,
            "038498af2b565bcb10bf5ed225638293a7640c83")
        H.equal(#catalog.families, 1)
        H.equal(next(catalog.profile_specs), nil)
        H.equal(next(catalog.derived_profiles), nil)

        local family = catalog.families[1]
        H.equal(family.id, "sienna_dagger")
        H.equal(family.setting_id, "wt_history_sienna_dagger")
        H.deep_equal(family.templates, { "one_handed_daggers_template_1" })
        H.deep_equal(family.state_order, { "6_11_1" })
        H.equal(catalog.states["6_11_1"].display_name,
            "Game Version 6.11.1")
        H.equal(catalog.states["6_11_1"].source_revision,
            "1a0a4e0caf5c119bfe8d42a4d1bc23b34a7b005e")
        H.equal(catalog.states["6_11_1"].official_patch_notes,
            "https://forums.fatsharkgames.com/t/hotfix-6-11-2-2nd-of-june-hotfix-6-11-3/122090")

        local state = family.states["6_11_1"]
        H.deep_equal(state.profile_names, {})
        H.deep_equal(state.direct_profile_names, {})
        H.equal(#state.operations, 1)
        local row = state.operations[1]
        H.equal(row.root, "Weapons")
        H.equal(row.template, "one_handed_daggers_template_1")
        H.deep_equal(row.path, {
            "actions", "action_one", "heavy_attack_right", "damage_profile",
        })
        H.equal(row.expected_current, "medium_burning_smiter_stab_H")
        H.equal(row.result, "dagger_h1_medium_smiter_diag")
        H.equal(row.expected_present, true)
        H.equal(row.result_present, true)
        H.equal(row.family_id, family.id)
        H.equal(row.state_id, "6_11_1")
        H.equal(row.official_change_id, "P6112-SIENNA-DAGGER-H2")
        H.equal(row.change_class, "official_weapon_balance")
        H.equal(row.source_revision,
            "1a0a4e0caf5c119bfe8d42a4d1bc23b34a7b005e")
        H.equal(row.source_blob,
            "656ef0ffac628d707d13adbf3c4a8950aec7fca7")
        H.equal(row.current_source_blob,
            "fcfeecee65342ae8b3bb4a75a57e248c3a677b1e")
        H.equal(row.source_path,
            "scripts/settings/equipment/weapon_templates/1h_dagger_wizard.lua")
        H.deep_equal(catalog.generation, {
            adjacent_operation_count = 1,
            global_operations = 0,
            profile_route_count = 0,
            unsupported_count = 0,
        })

        local group = assert(CatalogUI.build_widgets(catalog))
        H.equal(#group.sub_widgets, 1)
        H.equal(group.sub_widgets[1].default_value, "current")
        H.deep_equal(group.sub_widgets[1].options, {
            { text = "wt_history_state_current", value = "current" },
            { text = "wt_history_state_6_11_1", value = "6_11_1" },
        })
        H.equal(read_file(script_root .. "_wt_history_6_11_2_catalog.lua"),
            read_file(repo_root
                .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/"
                .. "_wt_history_6_11_2_catalog.lua"),
            "public and dev must carry byte-identical pure Hotfix 6.11.2 data")
    end)
end

return register
