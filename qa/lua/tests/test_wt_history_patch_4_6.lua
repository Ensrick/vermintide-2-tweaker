-- Source-bound catalog coverage for the Patch 4.6 Hagbane history slice.

local function register(H, repo_root)
    local script_root = repo_root
        .. "/weapon_tweaker/scripts/mods/weapon_tweaker/"
    local Policy = assert(loadfile(script_root .. "_wt_history_policy.lua"))()

    local function read_file(path)
        local file = assert(io.open(path, "rb"))
        local content = file:read("*a")
        file:close()
        return content
    end

    H.test("WT #1436 generated Patch 4.6 catalog is Hagbane-only and source bounded", function()
        local catalog = assert(loadfile(script_root .. "_wt_history_4_6_catalog.lua"))()
        local source_catalog = assert(loadfile(repo_root
            .. "/tools/weapon-history/evidence/patch_4_6/"
            .. "_wt_history_4_6_source_catalog.lua"))()
        local expected_source_paths = {
            "scripts/settings/equipment/power_level_templates.lua",
            "scripts/settings/equipment/damage_profile_templates.lua",
            "scripts/settings/dlcs/morris/damage_profile_templates_dlc_morris.lua",
            "scripts/settings/equipment/damage_profile_templates_dlc_cog.lua",
            "scripts/settings/equipment/damage_profile_templates_dlc_woods.lua",
            "scripts/settings/equipment/weapon_templates/shortbows_hagbane.lua",
        }
        H.equal(#source_catalog.source_files, 6)
        for index, path in ipairs(expected_source_paths) do
            local row = source_catalog.source_files[index]
            H.equal(row.path, path)
            H.truthy(row.historical_blob and row.historical_blob:match("^[0-9a-f]+$"))
            H.truthy(row.post_blob and row.post_blob:match("^[0-9a-f]+$"))
            H.truthy(row.current_blob and row.current_blob:match("^[0-9a-f]+$"))
        end
        H.deep_equal(source_catalog.source_root_exclusions, {
            {
                path = "scripts/settings/equipment/weapon_templates/shortbows_hagbane.lua",
                reason = "presentation_only",
                root = "weapon_diagram",
            },
        })
        local valid, validation_error = Policy.validate(catalog)
        H.equal(validation_error, nil)
        H.equal(valid, true)
        H.equal(catalog.catalog_id, "wt_history_patch_4_6_hagbane_v1")
        H.equal(catalog.current_source.revision,
            "25fd7b8433e839b678d1c98a7a9af80918cbc252")
        H.deep_equal(catalog.generation, {
            adjacent_operation_count = 2,
            excluded_operation_count = 2,
            global_operations = 0,
            profile_route_count = 2,
            unsupported_count = 0,
        })
        H.equal(#catalog.families, 1)
        local family = catalog.families[1]
        H.equal(family.id, "hagbane_shortbow")
        H.equal(family.setting_id, "wt_history_hagbane_shortbow")
        H.deep_equal(family.templates, { "shortbow_hagbane_template_1" })
        local state = family.states["4_5_1"]
        H.deep_equal(state.operations, {})
        H.deep_equal(state.profile_names, {
            "shortbow_hagbane", "shortbow_hagbane_charged",
        })
        H.deep_equal(state.direct_profile_names, state.profile_names)
        H.equal(catalog.states["4_5_1"].official_patch_notes,
            "https://www.vermintide.com/news/patch-46-patch-notes")

        for _, name in ipairs(state.profile_names) do
            local profile = assert(catalog.profile_specs["4_5_1"][name])
            H.equal(profile.private_name, "wt_hist_4_5_1_" .. name)
            H.equal(profile.source_revision,
                "0cec9547152a395c4f35f75288f29d8b18b8294f")
            H.equal(profile.source_blob,
                "6653fb47c9ee40611bc0525fd62bc7f927c17fdf")
            H.equal(profile.current_source_blob,
                "e8330328d0085f6aee09e0495ba88fdc0211d5aa")
            H.equal(rawget(profile.historical_profile,
                "allow_dot_finesse_hit"), nil)
            H.equal(type(profile.historical_profile.default_target
                .range_modifier_settings), "table",
                "private profile must retain the current 6.12 schema")
            H.equal(rawget(profile.historical_profile.default_target,
                "range_dropoff_settings"), nil,
                "private profile must not restore the obsolete 4.5.1 schema")
        end
        H.equal(read_file(script_root .. "_wt_history_4_6_catalog.lua"),
            read_file(repo_root
                .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/"
                .. "_wt_history_4_6_catalog.lua"),
            "public and dev must carry byte-identical pure Patch 4.6 data")
    end)
end

return register
