return function(H, repo_root)
    local mod_root = repo_root .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local entry_path = mod_root .. "crafting_in_modded_dev.lua"
    local module_path = mod_root .. "_cim_regression_checks.lua"

    local function read_all(path)
        local file = assert(io.open(path, "rb"))
        local text = file:read("*a")
        file:close()
        return text
    end

    H.test("CIM entry delegates regression registrations exactly once", function()
        local entry = read_all(entry_path)
        local _, dofile_count = entry:gsub(
            "scripts/mods/crafting_in_modded_dev/_cim_regression_checks", "")
        H.equal(dofile_count, 1)
        H.equal(entry:find('_rt_register("issue277_', 1, true), nil)

        local line_count = 0
        for _ in (entry .. "\n"):gmatch("[^\n]*\n") do line_count = line_count + 1 end
        H.truthy(line_count <= 7636, "CIM entry exceeded frozen 7,636-line baseline")
    end)

    H.test("CIM regression module preserves registration order", function()
        local install = assert(loadfile(module_path))()
        local names = {}
        local checks = {}
        local seen = {}
        local function register(name, check)
            H.equal(type(name), "string")
            H.equal(type(check), "function")
            H.equal(seen[name], nil, "duplicate regression registration")
            seen[name] = true
            names[#names + 1] = name
            checks[#checks + 1] = check
        end

        local noop = function() end
        install({
            mod = {},
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
        })

        H.equal(names[1], "issue277_bulk_cleanup_exact_owner_transaction")
        H.equal(names[#names], "issue562_auto_equip_contract")
        H.truthy(seen.issue83_dynamic_forge_widget_material_closure,
            "issue 83 dynamic-widget closure check missing")
        H.truthy(seen.issue703_athanor_cwv_rows_unlocked,
            "issue 703 Athanor CWV false-lock check missing")
        H.truthy(seen.issue787_cim_dual_axes_authored_icon,
            "issue 787 authored Dual Axes icon check missing")
        H.truthy(seen.issue682_provider_gate_routing,
            "issue 682 provider-gate routing check missing")
        H.truthy(seen.issue959_accessory_property_layers_are_independent,
            "issue 959 accessory property layer check missing")
        H.truthy(seen.issue628_salvage_state_diagnostic,
            "issue 628 exact salvage-state diagnostic check missing")
        H.equal(#names, 81, "regression registration set changed")
        local ok, result = pcall(checks[1])
        H.truthy(ok, "registered checks did not close over the supplied mod object")
        H.equal(type(result), "string")
    end)

    H.test("CIM regression checks never reload hook-owning modules", function()
        local source = read_all(module_path)
        H.equal(
            source:find('pcall(mod.dofile, mod, "scripts/mods/crafting_in_modded_dev/modded_rarities")', 1, true),
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
