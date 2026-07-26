-- _cim_accessory_property_runtime.lua — Athanor accessory property UI adapter.
--
-- Owns the consolidated HeroWindowWeaveProperties property-row population,
-- exact-row removal, and category-clear hooks. Category arithmetic remains in
-- the pure policy module; this adapter only bridges that policy to VT2 state.
--
-- Owned by: crafting_in_modded_dev.lua. Installs once during mod initialization.

return function(context)
    local mod = context.mod
    local policy = context.policy
    local is_custom_forge_active = context.is_custom_forge_active

    local function selected_item(window)
        return window._selected_item and window:_selected_item()
    end

    -- #239 blanks CIM's fake zero-cost label. #959 recomputes accessory usage
    -- within the entry category's authored ten-slot layer; vanilla aggregates
    -- every slot stored under the key (hero_window_weave_properties.lua:718-740).
    mod:hook_safe("HeroWindowWeaveProperties", "_populate_menu_option_widget", function(self, entry_data, menu_option)
        if not is_custom_forge_active() then return end
        local widget = entry_data and entry_data.widget
        if not widget then return end

        if menu_option == "property"
            and policy.layer_for_category(entry_data.category)
            and not selected_item(self)
        then
            local property_key = entry_data.key
            local current_properties = self._loadout and self._loadout.property
            local slot_indices = current_properties and current_properties[property_key]
            if property_key then
                local used_amount = policy.count_slots(
                    slot_indices, entry_data.category, policy.LAYER_SIZE)
                local managers = rawget(_G, "Managers")
                local backend_interface_weaves = managers.backend:get_interface("weaves")
                local costs = backend_interface_weaves:get_property_mastery_costs(property_key)
                local weave_properties = rawget(_G, "WeaveProperties")
                local property_data = weave_properties.properties[property_key]
                local ui_utils = rawget(_G, "UIUtils")

                widget.content.used_amount = used_amount
                widget.content.total_uses = #costs
                widget.content.total_value_text = ui_utils.get_weave_property_value_text(
                    property_key, property_data, costs, used_amount)
                entry_data.next_cost = used_amount < #costs
                    and costs[used_amount + 1]
                    or nil
            end
        end

        if widget.content then
            widget.content.price_text = ""
        end
        local price_icon = widget.style and widget.style.price_icon
        if price_icon and price_icon.color then price_icon.color[1] = 0 end
    end)

    -- Vanilla receives active_menu_category from its caller but ignores it and
    -- returns the final aggregate property index (:2402-2423,2483-2501).
    mod:hook("HeroWindowWeaveProperties", "_find_slot_by_key", function(func, self, key, menu_option, menu_category)
        if is_custom_forge_active()
            and menu_option == "property"
            and policy.layer_for_category(menu_category)
            and not selected_item(self)
        then
            local loadout_keys = self._loadout and self._loadout[menu_option]
            local slot_indices = loadout_keys and loadout_keys[key]
            local index = policy.last_slot(
                slot_indices, menu_category, policy.LAYER_SIZE)
            local type_slots = self._slots and self._slots[menu_option]
            return index and type_slots and type_slots[index] or nil
        end
        return func(self, key, menu_option, menu_category)
    end)

    mod:hook("HeroWindowWeaveProperties", "_can_clear_slots", function(func, self, menu_option, menu_category)
        if is_custom_forge_active()
            and menu_option == "property"
            and policy.layer_for_category(menu_category)
            and not selected_item(self)
        then
            local properties = self._loadout and self._loadout.property
            return #policy.collect_property_slots(
                properties, menu_category, policy.LAYER_SIZE) > 0
        end
        return func(self, menu_option, menu_category)
    end)

    -- Vanilla Clear selects keys by category membership, then removes every
    -- index under those keys (:2540-2632). With CIM's widened categories that
    -- crosses accessory layers, so submit only the active layer's exact slots.
    mod:hook("HeroWindowWeaveProperties", "_clear_slots", function(func, self, menu_option, menu_category)
        if is_custom_forge_active()
            and menu_option == "property"
            and policy.layer_for_category(menu_category)
            and not selected_item(self)
        then
            local properties = self._loadout and self._loadout.property
            local removals = policy.collect_property_slots(
                properties, menu_category, policy.LAYER_SIZE)
            local managers = rawget(_G, "Managers")
            local backend_interface_weaves = managers.backend:get_interface("weaves")

            for _, removal in ipairs(removals) do
                backend_interface_weaves:remove_loadout_property(
                    self._career_name, removal.property_key, removal.slot_index, nil)
            end
            self:_sync_backend_loadout()
            return
        end
        return func(self, menu_option, menu_category)
    end)

    mod.CIM959_ACCESSORY_PROPERTY_LAYER_MARKER = true
end
