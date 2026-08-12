return function(H, repo_root)
    local base = repo_root .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
    local state_module = assert(dofile(base .. "_cos_offhand_state_runtime.lua"))
    local apply_module = assert(dofile(base .. "_cos_offhand_apply_runtime.lua"))

    local function state_fixture(saved)
        local options, selections, logs = {}, {}, {}
        local bridge_option = {
            name = "Shield",
            armoury_key = "ak_shield",
            vanilla_skin = "skin_shield",
            target_item_type = "weapon_type",
            intended_unit = "units/shield",
            authored_family = "family",
            variant_kind = "unit",
        }
        local bridge = {
            registered = true,
            la_offhand_options_by_weapon_type = {
                weapon_type = { left_hand_unit = { bridge_option } },
            },
            normalize_weapon_type = function(value) return value end,
        }
        local mod = {
            _la_option_icon_policy = {
                index_by_target = function()
                    return {
                        weapon_type = {
                            left_hand_unit = { ak_shield = bridge_option },
                        },
                    }
                end,
                lookup = function(index, item_type, hand, key)
                    return index[item_type] and index[item_type][hand]
                        and index[item_type][hand][key]
                end,
                resolve_for_item = function(record) return record end,
            },
            info = function(_, fmt, ...)
                logs[#logs + 1] = string.format(fmt, ...)
            end,
        }
        local items = {
            get_item_from_id = function(_, id)
                if id == "bid-1" then
                    return { data = { item_type = "weapon_type" }, skin = "skin_red" }
                end
            end,
        }
        local owner = state_module.install(mod, {
            la_bridge = bridge,
            la_persist = { get_saved_offhands = function() return saved or {} end },
            offhand_names = {
                merge_unique = function(pool, candidate)
                    for _, value in ipairs(pool) do
                        if value.la_armoury_key == candidate.la_armoury_key then return false end
                    end
                    pool[#pool + 1] = candidate
                    return true
                end,
            },
            decorate_shield_option = function(option) option.decorated = true end,
            offhand_options = options,
            offhand_selection = selections,
            preload_offhand_package = function() end,
            preload_offhand_for_option = function() end,
            get_mod = function() return nil end,
            get_managers = function()
                return {
                    backend = {
                        _interfaces = { items = items },
                        get_interface = function() return items end,
                    },
                }
            end,
            get_item_master_list = function() return {} end,
            now = function() return 10 end,
        })
        return mod, owner, options, selections, logs
    end

    H.test("cos offhand state merge is idempotent and preserves provenance", function()
        local _, owner, options, _, logs = state_fixture()
        owner.merge_la_offhand_options()
        owner.merge_la_offhand_options()
        local row = options.weapon_type.left_hand_unit[1]
        H.equal(#options.weapon_type.left_hand_unit, 1)
        H.equal(row.la_armoury_key, "ak_shield")
        H.equal(row.authored_family, "family")
        H.equal(row.variant_kind, "unit")
        H.equal(row.decorated, true)
        H.equal(#logs, 1)
    end)

    H.test("cos offhand restore rebuilds one exact-instance selection", function()
        local saved = {
            ["bid-1"] = {
                left_hand_unit = { armoury_key = "ak_shield" },
            },
        }
        local mod, owner, _, selections = state_fixture(saved)
        owner.merge_la_offhand_options()
        mod._la_restore_offhand_selections()
        H.equal(selections["bid-1"].left_hand_unit.la_armoury_key, "ak_shield")
        H.equal(selections["bid-1"].left_hand_unit.target_item_type, "weapon_type")
        H.equal(mod._la_self_rebroadcast_pending, true)
        H.equal(mod._la_offhand_restore_done, true)
    end)

    H.test("cos dual receiver compatibility fails closed for foreign units", function()
        local mod = state_fixture()
        mod._independent_dual_item_types = { dual = true }
        mod._ensure_independent_dual_pool = function()
            return { left_hand_unit = { { unit = "units/allowed" } } }
        end
        H.equal(mod._dual_offhand_unit_allowed("ordinary", "right_hand_unit", "x"), true)
        H.equal(mod._dual_offhand_unit_allowed("dual", "right_hand_unit", "units/allowed"), false)
        H.equal(mod._dual_offhand_unit_allowed("dual", "left_hand_unit", "units/foreign"), false)
        H.equal(mod._dual_offhand_unit_allowed("dual", "left_hand_unit", "units/allowed"), true)
    end)

    H.test("cos offhand apply refuses paint on a mismatched authored mesh", function()
        local paints, traces = 0, {}
        local mod = {
            _la_instance_policy = {
                selection_owned = function() return true end,
                preview_target_matches = function(path) return path == "units/authored" end,
            },
            _la_deus_weapon_yield = function() return false end,
        }
        local owner = apply_module.install(mod, {
            la_bridge = {
                registered = true,
                resolve_texture_receiver = function() return nil end,
                apply_offhand_to_unit = function() paints = paints + 1; return true end,
            },
            dbg = function() end,
            trace = function() end,
            trace_paint = function(_, _, _, _, _, outcome)
                traces[#traces + 1] = outcome
            end,
            unit_mesh_name = function() return "units/foreign" end,
            is_unit = function() return true end,
            offhand_selection = {
                bid = { left_hand_unit = { la_armoury_key = "ak" } },
            },
            offhand_session_state = { migrate_legacy = function() end },
            get_offhand_options = function()
                return { left_hand_unit = { { la_armoury_key = "ak" } } }
            end,
            resolve_authored_offhand_variant = function()
                return { new_units = { "units/authored", "units/authored_3p" } }
            end,
            get_item_master_list = function() return {} end,
            get_active_customization_backend_id = function() return nil end,
        })
        local claimed, painted = owner.apply_la_offhand_to_units(
            {}, { item_type = "weapon", backend_id = "bid" }, { "unit" }, true,
            nil, "hero_previewer", { "units/foreign" })
        H.equal(claimed, true)
        H.equal(painted, true)
        H.equal(paints, 0)
        H.equal(traces[1], "SKIP-mesh-mismatch")
    end)
end
