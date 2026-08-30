return function(H, repo_root)
    local mod_root = repo_root .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local entry_path = mod_root .. "crafting_in_modded_dev.lua"
    local core_module_path = mod_root .. "_cim_regression_checks.lua"
    local cleanup_module_path = mod_root .. "_cim_regression_cleanup.lua"
    local surfaces_module_path = mod_root .. "_cim_regression_forge_surfaces.lua"

    local expected_order = {
        "issue277_bulk_cleanup_exact_owner_transaction",
        "issue959_accessory_property_layers_are_independent",
        "issue246_tab_preview_exact_skin_icon",
        "weave_talent_forge_level_guard_present",
        "pool_excludes_scrubbed",
        "forge_preview_accepts_resident_3p_unit",
        "issue882_athanor_preview_placement",
        "forge_preview_la_diagnostics_armed",
        "single_on_enter_hook_per_class",
        "rpc_sync_loadout_unknown_id_guard",
        "wire_rarity_rewrite_ungated",
        "weave_forge_hides_cost_readout",
        "modded_loadout_round_trip_save_then_clear",
        "forged_weapons_round_trip",
        "restore_after_playfab_inventory_populated",
        "issue563_vanilla_skin_override_exact_backend_id",
        "inventory_property_count_within_cap",
        "cwv_bounded_seed_is_single_acquisition_selector",
        "issue524_cwv_selector_bounded",
        "issue524_all_cwv_blacksmith_selectors",
        "issue524_native_craft_families_deduplicated",
        "issue682_provider_gate_routing",
        "issue628_salvage_state_diagnostic",
        "issue703_athanor_cwv_rows_unlocked",
        "issue624_keep_forge_interaction",
        "issue617_athanor_icon_resource_closure",
        "issue787_cim_dual_axes_authored_icon",
        "modded_loadout_has_no_stale_entries",
        "dbg_helpers_two_channel",
        "localization_format_safe",
        "issue244_athanor_literal_property_values",
        "stamina_movespeed_clamp_at_overcap",
        "picker_caps_persisted_slot_array",
        "read_chokepoint_caps_grid_occupancy",
        "default_property_cap_is_five_bubbles",
        "action_rejection_uses_warning_channel",
        "morris_hub_passes_open_forge_gate",
        "trim_logging_emits_per_item_detail",
        "no_duplicate_hook_safe_registrations",
        "accessories_label_on_overview",
        "overview_btn_render_target",
        "forge_tooltip_no_equipped_compare",
        "issue521_tooltip_follows_hovered_weapon",
        "adventure_visible_preserves_availability_and_clears_mechanism",
        "versus_twin_rehidden_from_inventory",
        "overview_btns_created_when_forge_opened",
        "accessory_panel_module_loaded",
        "issue1117_bulk_accessory_button_layout",
        "accessory_panel_built_when_accessories_opened",
        "backendutils_capture_installed",
        "persist_loadouts_gate_off_is_passthrough",
        "reequip_live_api_ok",
        "forge_preview_guard_present",
        "weave_category_pool_guard_present",
        "forge_freedom_settings_and_helpers_present",
        "native_pool_seeded_into_picker_with_toggles_off",
        "cw_trait_pool_includes_boons",
        "issue414_cw_traits_preserve_slot_family",
        "default_trait_pool_excludes_boons_when_toggles_off",
        "trait_twin_stub_has_display_name",
        "trait_twin_copies_description_pair",
        "forge_freedom_restore_is_safe",
        "heroview_hdr_renderer_guard_failsafe",
        "heroview_hdr_failed_setup_sweeps_leaked_worlds",
        "heroview_hdr_not_forcebuilt_in_mission",
        "issue83_dynamic_forge_widget_material_closure",
        "hdr_glow_widgets_suppressed_in_mission",
        "hdr_cluster_glow_resuppressed_on_props_enter",
        "skilltree_ring_widgets_suppressed_in_mission",
        "hdr_bloom_setscalar_skipped_in_mission",
        "hdr_upgrade_anim_skipped_in_mission",
        "forge_preview_guard_allows_loaded_weapon",
        "rpc_schema_gate_drops_on_mismatch",
        "issue921_tab_rarity_state_is_tristate",
        "issue88_inventory_access_flip_is_scoped",
        "issue96_allow_in_mission_widget_moved_to_gut",
        "forge_mission_env_picker_prefers_resident",
        "customization_variation_pin_decision",
        "open_forge_gate_honors_allow_in_mission",
        "cim390_cwv_craft_render_fix",
        "console_craft_item_nil_recipe_resolves",
        "issue562_auto_equip_contract",
    }

    local function read_all(path)
        local file = assert(io.open(path, "rb"))
        local text = file:read("*a")
        file:close()
        return text
    end

    local function nonblank_lines(text)
        local count = 0
        for line in (text .. "\n"):gmatch("([^\n]*)\n") do
            if line:find("%S") then count = count + 1 end
        end
        return count
    end

    local noop = function() end

    local function make_context(register)
        return {
            mod = {
                _cim_weave_economy_source_anchor = noop,
                _cim_accessory_property_source_anchor = noop,
                _cim_forge_ui_owner = { apply_ui_polish = noop },
            },
            rt_register = register,
            rt_src_read = noop,
            dbg = noop,
            dbg_alert = noop,
            bubble_cap = noop,
            value_for_bubbles = noop,
            cap_grid_property_arrays = noop,
            ensure_item_adventure_visible = noop,
            forge_load = noop,
            is_in_keep = noop,
            store_property_slot = noop,
            accessory_property_policy = {
                count_slots = noop,
                last_slot = noop,
                collect_property_slots = noop,
            },
            accessory_panel = {},
            overview_btn_render_field = "bottom_hdr_widgets",
            overview_drawn_fields = {},
            get_custom_forge_active = function() return false end,
            get_forged_weapons = function() return {} end,
            set_forged_weapons = noop,
            get_modded_loadout = function() return {} end,
            set_modded_loadout = noop,
            modded_loadout_load = noop,
            rpc_schema = 1,
        }
    end

    H.test("CIM entry loads every regression installer before registration", function()
        local entry = read_all(entry_path)
        local cleanup_path = "scripts/mods/crafting_in_modded_dev/_cim_regression_cleanup"
        local core_path = "scripts/mods/crafting_in_modded_dev/_cim_regression_checks"
        local surfaces_path =
            "scripts/mods/crafting_in_modded_dev/_cim_regression_forge_surfaces"
        local _, cleanup_count = entry:gsub(cleanup_path, "")
        local _, core_count = entry:gsub(core_path, "")
        local _, surfaces_count = entry:gsub(surfaces_path, "")
        H.equal(cleanup_count, 1)
        H.equal(core_count, 1)
        H.equal(surfaces_count, 1)

        local cleanup_load = assert(entry:find(cleanup_path, 1, true))
        local core_load = assert(entry:find(core_path, 1, true))
        local surfaces_load = assert(entry:find(surfaces_path, 1, true))
        local first_install = assert(entry:find(
            "_install_cleanup_regression_checks(_regression_context)", 1, true))
        H.truthy(cleanup_load < core_load and core_load < surfaces_load,
            "regression chunks must load in cleanup/core/surfaces order")
        H.truthy(surfaces_load < first_install,
            "all chunks must load before the first installer can register checks")
        H.equal(entry:find('_rt_register("issue277_', 1, true), nil)
        H.truthy(nonblank_lines(entry) <= 1427,
            "CIM entry exceeded its decomposition-contract ceiling")
    end)

    H.test("CIM regression split preserves the exact 82-check stream", function()
        local cleanup_install = assert(loadfile(cleanup_module_path))()
        local core_install = assert(loadfile(core_module_path))()
        local surfaces_install = assert(loadfile(surfaces_module_path))()
        local names, checks, seen = {}, {}, {}
        local function register(name, check)
            H.equal(type(name), "string")
            H.equal(type(check), "function")
            H.equal(seen[name], nil, "duplicate regression registration")
            seen[name] = true
            names[#names + 1] = name
            checks[#checks + 1] = check
        end

        local context = make_context(register)
        cleanup_install(context)
        H.equal(#names, 3, "cleanup registration boundary changed")
        local support = core_install(context)
        H.equal(#names, 36, "core registration boundary changed")
        H.equal(type(support), "table")
        H.equal(type(support.with_loadout_sandbox), "function")
        context.with_loadout_sandbox = support.with_loadout_sandbox
        H.equal(context.with_loadout_sandbox, support.with_loadout_sandbox,
            "child did not receive the exact core helper identity")
        surfaces_install(context)

        H.deep_equal(names, expected_order, "ordered regression snapshot changed")
        H.equal(#names, 82)
        H.equal(names[3], "issue246_tab_preview_exact_skin_icon")
        H.equal(names[4], "weave_talent_forge_level_guard_present")
        H.equal(names[36], "action_rejection_uses_warning_channel")
        H.equal(names[37], "morris_hub_passes_open_forge_gate")
        H.equal(names[82], "issue562_auto_equip_contract")

        local ok, result = pcall(checks[1])
        H.truthy(ok, "registered checks did not close over the supplied mod object")
        H.equal(type(result), "string")
    end)

    H.test("CIM forge-surface installer fails before partial registration", function()
        local install = assert(loadfile(surfaces_module_path))()
        local required = {
            "mod",
            "rt_register",
            "rt_src_read",
            "ensure_item_adventure_visible",
            "is_in_keep",
            "rpc_schema",
            "with_loadout_sandbox",
            "get_custom_forge_active",
            "get_forged_weapons",
            "get_modded_loadout",
            "set_modded_loadout",
        }

        H.equal(pcall(install, nil), false)
        for _, missing in ipairs(required) do
            local registrations = 0
            local context = make_context(function() registrations = registrations + 1 end)
            context.with_loadout_sandbox = noop
            context[missing] = nil
            local ok = pcall(install, context)
            H.equal(ok, false, "missing " .. missing .. " did not fail closed")
            H.equal(registrations, 0,
                "missing " .. missing .. " left a partial registration suffix")
        end
    end)

    H.test("CIM split ownership and source anchors remain exact", function()
        local core = read_all(core_module_path)
        local surfaces = read_all(surfaces_module_path)
        local weave_owner = read_all(mod_root .. "_cim_weave_economy.lua")
        local accessory_owner = read_all(mod_root .. "_cim_accessory_property_runtime.lua")
        local forge_owner = read_all(mod_root .. "_cim_forge_ui_owner.lua")

        H.truthy(weave_owner:find("mod._cim_weave_economy_source_anchor", 1, true))
        H.truthy(accessory_owner:find(
            "mod._cim_accessory_property_source_anchor", 1, true))
        H.truthy(forge_owner:find("state.exports.apply_ui_polish", 1, true))
        H.truthy(core:find(
            'pcall(debug.getinfo, _weave_economy_source_anchor, "S")', 1, true))
        H.truthy(core:find(
            'pcall(debug.getinfo, _accessory_property_source_anchor, "S")', 1, true))
        H.truthy(surfaces:find(
            'pcall(debug.getinfo, _forge_ui_source_anchor, "S")', 1, true))
        H.equal(core:find("_forge_ui_source_anchor", 1, true), nil)
        H.equal(core:find("morris_hub_passes_open_forge_gate", 1, true), nil)
        H.equal(core:find("issue562_auto_equip_contract", 1, true), nil)
        H.truthy(surfaces:find("morris_hub_passes_open_forge_gate", 1, true))
        H.truthy(surfaces:find("issue562_auto_equip_contract", 1, true))
        H.equal(core:find('pcall(debug.getinfo, _rt_register, "S")', 1, true), nil)
        H.equal(surfaces:find('pcall(debug.getinfo, _rt_register, "S")', 1, true), nil)
        H.truthy(nonblank_lines(core) <= 1500, "core regression owner regrew past target")
        H.truthy(nonblank_lines(surfaces) <= 1500,
            "forge-surface regression owner exceeded target")
    end)

    H.test("CIM regression checks never reload hook-owning modules", function()
        local source = read_all(core_module_path)
            .. "\n" .. read_all(surfaces_module_path)
        H.equal(
            source:find(
                'pcall(mod.dofile, mod, "scripts/mods/crafting_in_modded_dev/modded_rarities")',
                1, true),
            nil,
            "regression check must not re-execute modded_rarities.lua; it owns live VMF hooks"
        )
        H.truthy(
            source:find("mod._cim_rarity_loc_overrides", 1, true),
            "accessories-label check should read the side-effect-free API table"
        )

        local rarity_source = read_all(mod_root .. "modded_rarities.lua")
        H.truthy(
            rarity_source:find("if mod._cim_modded_rarities_api then", 1, true),
            "modded_rarities.lua must stay idempotent because it owns hook registrations"
        )
    end)
end
