return function(H, repo_root)
    local policy = dofile(repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_accessory_property_policy.lua")

    H.test("CIM accessory property usage stays inside its ten-slot layer", function()
        local health = { 11, 12, 13, 14, 15 }
        H.equal(policy.count_slots(health, "offence_accessory", 10), 0)
        H.equal(policy.count_slots(health, "defence_accessory", 10), 5)
        H.equal(policy.count_slots(health, "utility_accessory", 10), 0)

        health[#health + 1] = 1
        H.equal(policy.count_slots(health, "offence_accessory", 10), 1)
        H.equal(policy.count_slots(health, "defence_accessory", 10), 5)
    end)

    H.test("CIM accessory right-click resolves only the active category", function()
        local health = { 11, 12, 1, 13, 2 }
        H.equal(policy.last_slot(health, "offence_accessory", 10), 2)
        H.equal(policy.last_slot(health, "defence_accessory", 10), 13)
        H.equal(policy.last_slot(health, "utility_accessory", 10), nil)
    end)

    H.test("CIM accessory clear plan removes only the active category", function()
        local properties = {
            weave_health = { 1, 11, 12, 21 },
            weave_attack_speed = { 2, 13, 22 },
        }
        local defence = policy.collect_property_slots(
            properties, "defence_accessory", 10)
        H.equal(#defence, 3)
        H.equal(defence[1].slot_index, 11)
        H.equal(defence[1].property_key, "weave_health")
        H.equal(defence[2].slot_index, 12)
        H.equal(defence[3].slot_index, 13)

        local unknown = policy.collect_property_slots(properties, "weapon", 10)
        H.equal(#unknown, 0)
    end)

    H.test("CIM accessory property storage applies use caps per layer", function()
        local properties = {
            weave_health = { 11, 12, 13, 14, 15 },
        }

        local slots, stored, reason, layer_uses = policy.store_property_slot(
            properties, "weave_health", 1, 5, 10)
        H.equal(stored, true)
        H.equal(reason, "stored")
        H.equal(layer_uses, 1)
        H.equal(#slots, 6)
        H.equal(slots[6], 1)

        for slot_index = 2, 5 do
            policy.store_property_slot(
                properties, "weave_health", slot_index, 5, 10)
        end
        slots, stored, reason, layer_uses = policy.store_property_slot(
            properties, "weave_health", 6, 5, 10)
        H.equal(stored, false)
        H.equal(reason, "cap")
        H.equal(layer_uses, 5)
        H.equal(#slots, 10)

        slots, stored, reason = policy.store_property_slot(
            properties, "weave_attack_speed", 11, 5, 10)
        H.equal(stored, false)
        H.equal(reason, "occupied")
        H.equal(#slots, 0)
    end)

    H.test("CIM weapon property storage retains the global use cap", function()
        local properties = {
            weave_health = { 11, 12, 13, 14, 15 },
        }
        local slots, stored, reason = policy.store_property_slot(
            properties, "weave_health", 1, 5, nil)
        H.equal(stored, false)
        H.equal(reason, "cap")
        H.equal(#slots, 5)
    end)

    H.test("CIM distinct-property capacity is isolated per accessory layer", function()
        local properties = {
            weave_health = { 11 },
            weave_attack_speed = { 1 },
            weave_crit_chance = { 2 },
        }
        H.equal(policy.property_present_in_scope(
            properties.weave_health, 1, 10), false)
        H.equal(policy.property_present_in_scope(
            properties.weave_health, 12, 10), true)
        H.equal(policy.count_distinct_properties(properties, 3, 10), 2)
        H.equal(policy.count_distinct_properties(properties, 12, 10), 1)
        H.equal(policy.count_distinct_properties(properties, 3, nil), 3)
    end)

    H.test("CIM production wires all category-aware issue 959 seams", function()
        local entry_path = repo_root
            .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua"
        local runtime_path = repo_root
            .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_accessory_property_runtime.lua"
        local f = assert(io.open(entry_path, "rb"))
        local entry_source = f:read("*a")
        f:close()
        f = assert(io.open(runtime_path, "rb"))
        local runtime_source = f:read("*a")
        f:close()
        H.truthy(entry_source:find("_cim_accessory_property_runtime", 1, true))
        H.truthy(runtime_source:find("CIM959_ACCESSORY_PROPERTY_LAYER_MARKER", 1, true))
        H.truthy(runtime_source:find('"_find_slot_by_key"', 1, true))
        H.truthy(runtime_source:find('"_can_clear_slots"', 1, true))
        H.truthy(runtime_source:find('"_clear_slots"', 1, true))
        H.truthy(entry_source:find(
            "item_backend_id == nil and _AMULET_LAYER_SIZE or nil", 1, true))
        H.truthy(entry_source:find("count_distinct_properties", 1, true))
        H.truthy(entry_source:find("[cim:959] property store", 1, true))
    end)

    H.test("CIM runtime adapter keeps picker removal and Clear category-aware", function()
        local runtime = dofile(repo_root
            .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_accessory_property_runtime.lua")
        local hooks, safe_hooks = {}, {}
        local mod = {}
        function mod:hook(class_name, method_name, callback)
            hooks[class_name .. "." .. method_name] = callback
        end
        function mod:hook_safe(class_name, method_name, callback)
            safe_hooks[class_name .. "." .. method_name] = callback
        end

        local old_managers = rawget(_G, "Managers")
        local old_properties = rawget(_G, "WeaveProperties")
        local old_ui_utils = rawget(_G, "UIUtils")
        local removed = {}
        _G.Managers = {
            backend = {
                get_interface = function()
                    return {
                        get_property_mastery_costs = function() return { 0, 0, 0, 0, 0 } end,
                        remove_loadout_property = function(_, _, key, index)
                            removed[#removed + 1] = { key = key, index = index }
                        end,
                    }
                end,
            },
        }
        _G.WeaveProperties = {
            properties = {
                weave_health = { description_values = { { value_type = "percent" } } },
            },
        }
        _G.UIUtils = {
            get_weave_property_value_text = function(_, _, _, used)
                return tostring(used)
            end,
        }

        local ok, err = xpcall(function()
            runtime({ mod = mod, policy = policy, is_custom_forge_active = function() return true end })
            H.equal(mod.CIM959_ACCESSORY_PROPERTY_LAYER_MARKER, true)

            local window = {
                _loadout = { property = { weave_health = { 11, 12, 13, 14, 15, 1 } } },
                _slots = { property = {} },
                _career_name = "empire_soldier",
                _selected_item = function() return nil end,
                _sync_backend_loadout = function(self)
                    self.synced = (self.synced or 0) + 1
                end,
            }
            window._slots.property[1] = { index = 1 }
            window._slots.property[15] = { index = 15 }

            local populate = safe_hooks[
                "HeroWindowWeaveProperties._populate_menu_option_widget"]
            local charm = {
                key = "weave_health",
                category = "offence_accessory",
                widget = {
                    content = {},
                    style = { price_icon = { color = { 255, 255, 255, 255 } } },
                },
            }
            populate(window, charm, "property")
            H.equal(charm.widget.content.used_amount, 1)
            H.equal(charm.next_cost, 0)

            local trait = {
                widget = {
                    content = { price_text = "Cost: 0" },
                    style = { price_icon = { color = { 255, 255, 255, 255 } } },
                },
            }
            populate(window, trait, "trait")
            H.equal(trait.widget.content.price_text, "")
            H.equal(trait.widget.style.price_icon.color[1], 0)

            local find_slot = hooks["HeroWindowWeaveProperties._find_slot_by_key"]
            H.equal(find_slot(function() return "fallback" end, window,
                "weave_health", "property", "offence_accessory").index, 1)
            H.equal(find_slot(function() return "fallback" end, window,
                "weave_health", "property", "defence_accessory").index, 15)

            local can_clear = hooks["HeroWindowWeaveProperties._can_clear_slots"]
            H.equal(can_clear(function() return false end, window,
                "property", "offence_accessory"), true)

            local clear = hooks["HeroWindowWeaveProperties._clear_slots"]
            clear(function() error("accessory Clear fell through") end, window,
                "property", "offence_accessory")
            H.equal(#removed, 1)
            H.equal(removed[1].key, "weave_health")
            H.equal(removed[1].index, 1)
            H.equal(window.synced, 1)
        end, debug.traceback)

        _G.Managers = old_managers
        _G.WeaveProperties = old_properties
        _G.UIUtils = old_ui_utils
        if not ok then error(err) end
    end)

    H.test("CIM #959 faked mastery costs survive the layered global use count", function()
        local costs = policy.build_zero_mastery_costs(5)
        H.equal(#costs, 5)
        H.equal(costs[1], 0)
        H.equal(costs[5], 0)
        -- Vanilla paints each occupied slot with the GLOBAL per-key count
        -- (hero_window_weave_properties.lua:1594-1637); with 5 charm + 1
        -- necklace entries that is 6, and a nil here aborted the repaint.
        H.equal(costs[6], 0)
        H.equal(costs[15], 0)
        -- Bounded: past cap*LAYER_COUNT reads stay nil so ipairs terminates.
        H.equal(costs[16], nil)
        H.equal(costs[0], nil)
        H.equal(costs.foo, nil)

        local stamina_costs = policy.build_zero_mastery_costs(2)
        H.equal(#stamina_costs, 2)
        H.equal(stamina_costs[6], 0)
        H.equal(stamina_costs[7], nil)
    end)

    H.test("CIM #959 amulet re-seed merges sibling layers under one key", function()
        local seeded = {}
        local next_slot, dropped = policy.seed_property_indices(
            seeded, "weave_health", 1, 5, 0, 10)
        H.equal(next_slot, 6)
        H.equal(dropped, 0)

        -- Second accessory, same key: must APPEND, not overwrite (the reopen
        -- bleed that wiped the first accessory's entries and then its item).
        next_slot, dropped = policy.seed_property_indices(
            seeded, "weave_health", 11, 2, 10, 10)
        H.equal(next_slot, 13)
        H.equal(dropped, 0)
        H.equal(#seeded.weave_health, 7)
        H.equal(policy.count_slots(seeded.weave_health, "offence_accessory", 10), 5)
        H.equal(policy.count_slots(seeded.weave_health, "defence_accessory", 10), 2)

        -- Clamp: an over-valued accessory can never spill into its sibling.
        next_slot, dropped = policy.seed_property_indices(
            seeded, "weave_attack_speed", 9, 4, 0, 10)
        H.equal(next_slot, 11)
        H.equal(dropped, 2)
        H.equal(#seeded.weave_attack_speed, 2)
        H.equal(policy.count_slots(seeded.weave_attack_speed, "defence_accessory", 10), 0)

        -- Invalid input degrades to a no-op instead of corrupting the seed.
        local before = #seeded.weave_health
        policy.seed_property_indices(seeded, "weave_health", nil, 1, 0, 10)
        H.equal(#seeded.weave_health, before)
    end)
end
