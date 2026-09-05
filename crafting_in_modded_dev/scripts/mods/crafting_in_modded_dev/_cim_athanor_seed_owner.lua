-- Owns the Weapon Select -> Properties identity handoff for Athanor crafting.
-- CWV Blacksmith seeds retain their vanilla donor key, so native
-- get_item_from_key(cwv_key) cannot find them. The Temper runtime publishes one
-- provider-authenticated resolver; both list synchronization and presentation
-- must consume that exact result instead of fabricating an owned-looking row.

local function install(ctx)
    assert(type(ctx) == "table", "Athanor seed owner requires context")
    local mod = assert(ctx.mod, "Athanor seed owner requires mod")
    local is_active = assert(ctx.is_active, "Athanor seed owner requires active accessor")
    local contract = assert(ctx.contract, "Athanor seed owner requires contract")
    local get_temper_state = ctx.get_temper_state or function()
        return mod._cim_temper_runtime_state
    end
    local get_item_from_key = ctx.get_item_from_key or function(item_key)
        local managers = rawget(_G, "Managers")
        local backend = managers and managers.backend
        local items = backend and backend:get_interface("items")
        return items and items:get_item_from_key(item_key) or nil
    end
    local get_master = ctx.get_master or function(item_key)
        local list = rawget(_G, "ItemMasterList")
        return type(list) == "table" and rawget(list, item_key) or nil
    end
    local clone = ctx.clone or function(value) return table.clone(value) end
    local localize = ctx.localize or function(key) return Localize(key) end

    local state = {}

    local function resolve_cwv_seed(item_key)
        if contract.is_cwv_provider_key(item_key) ~= true then
            return nil, nil, false, "not_cwv"
        end
        local temper = get_temper_state()
        local resolver = type(temper) == "table" and temper.resolve_cwv_seed
            or nil
        if type(resolver) ~= "function" then
            return nil, nil, true, "temper_resolver_unavailable"
        end
        local called, item, backend_id, proof_or_reason = pcall(
            resolver, item_key)
        if not called then
            return nil, nil, true, "temper_resolver_exception"
        end
        if type(item) ~= "table" or type(backend_id) ~= "string"
                or backend_id == "" then
            return nil, nil, true, proof_or_reason or "seed_unavailable"
        end
        return item, backend_id, true, nil
    end
    state.resolve_cwv_seed = resolve_cwv_seed

    mod:hook("HeroWindowWeaveForgeWeapons", "_sync_backend_loadout",
        function(func, self)
            func(self)
            if not is_active() then return end
            local scrollbar = self._scrollbars and self._scrollbars.weapons
            local widgets = scrollbar and scrollbar.list_widgets
            local selected_seen, selected_is_cwv = false, false
            local selected_backend_id = nil
            if widgets then
                for _, widget in ipairs(widgets) do
                    local content = widget.content
                    content.level_title, content.power_text = "", ""
                    content.power_title = ""
                    local _, backend_id, is_cwv = resolve_cwv_seed(content.key)
                    if is_cwv then
                        content.locked = backend_id == nil
                        content.backend_id = backend_id
                        content.equipped = false
                        content.equipped_in_another_slot = false
                        local hotspot = content.button_hotspot
                        if hotspot and hotspot.is_selected then
                            selected_seen = true
                            selected_is_cwv = true
                            selected_backend_id = backend_id
                        end
                    elseif content.button_hotspot
                            and content.button_hotspot.is_selected then
                        selected_seen = true
                    end
                end
            end
            if selected_seen then
                self._cim1141_cwv_selection = selected_is_cwv
                self._cim1141_seed_available = not selected_is_cwv
                    or selected_backend_id ~= nil
                if selected_is_cwv then
                    self._selected_backend_id = selected_backend_id
                end
                self:_update_equip_button_status(
                    not selected_is_cwv or selected_backend_id ~= nil, false)
            end
        end)

    mod:hook("HeroWindowWeaveForgeWeapons", "_present_item",
        function(func, self, item_key, activate_spin)
            if not is_active() then return func(self, item_key, activate_spin) end

            local viewport = self._viewport_data
            if viewport and viewport.item_previewer then
                viewport.item_previewer:destroy()
                viewport.item_previewer = nil
            end

            local item, backend_id, is_cwv = resolve_cwv_seed(item_key)
            if not is_cwv then
                item = get_item_from_key(item_key)
                backend_id = type(item) == "table" and item.backend_id or nil
            end
            local display_item = item
            if not display_item then
                local master = get_master(item_key)
                if type(master) ~= "table" then return nil end
                local item_data = clone(master)
                item_data.key = item_key
                display_item = { data = item_data, key = item_key }
            end
            if type(display_item.data) ~= "table" or type(viewport) ~= "table" then
                return nil
            end

            local previewer = self:_create_item_previewer(
                viewport.widget, display_item, activate_spin)
            viewport.item_previewer = previewer
            viewport.item = display_item

            local base_power = mod._cim_base_power and mod._cim_base_power()
                or 300
            local input_power = display_item.power_level or base_power
            local power_text = tostring(base_power)
            if input_power ~= base_power then
                power_text = tostring(input_power) .. " > " .. tostring(base_power)
            end
            local widgets = self._widgets_by_name
            widgets.viewport_level_value.content.visible = false
            widgets.viewport_level_title.content.visible = false
            widgets.viewport_power_value.content.text = power_text
            widgets.viewport_power_title.content.visible = true
            widgets.viewport_power_value.content.visible = true
            widgets.viewport_title.content.text = localize(
                display_item.data.display_name)
            widgets.viewport_sub_title.content.text = localize(
                display_item.data.item_type)

            local selectable = not is_cwv or backend_id ~= nil
            self._cim1141_cwv_selection = is_cwv
            self._cim1141_seed_available = selectable
            self:_set_presentation_locked_state(not selectable)
            self._selected_item_locked = not selectable
            self:_setup_weapon_stats(display_item)
            if is_cwv then return backend_id end
            return item_key
        end)

    mod:hook("HeroWindowWeaveForgeWeapons", "_set_presentation_locked_state",
        function(func, self, locked)
            if not is_active() then return func(self, locked) end
            local unavailable = self._cim1141_cwv_selection == true
                and self._cim1141_seed_available ~= true
            return func(self, unavailable)
        end)

    mod:hook("HeroWindowWeaveForgeWeapons", "_update_equip_button_status",
        function(func, self, equipable_item, is_item_equipped)
            if not is_active() then
                return func(self, equipable_item, is_item_equipped)
            end
            local viewport = self._viewport_data
            local button = viewport and viewport.equip_button
            if not button then return end
            local enabled = self._selected_item_id ~= nil
            if self._cim1141_cwv_selection == true then
                enabled = enabled and self._cim1141_seed_available == true
                    and type(self._selected_backend_id) == "string"
                    and self._selected_backend_id ~= ""
            end
            button.content.button_hotspot.disable_button = not enabled
            button.content.title_text = "CRAFT"
        end)

    mod:hook("HeroWindowWeaveForgeWeapons", "_on_list_index_selected",
        function(func, self, index)
            if not is_active() then return func(self, index) end
            local scrollbar = self._scrollbars.weapons
            local widgets = scrollbar.list_widgets
            for i, widget in ipairs(widgets) do
                local content = widget.content
                local selected = i == index
                content.button_hotspot.is_selected = selected
                if selected then
                    self._selected_backend_id = self:_present_item(content.key)
                    self._selected_item_id = content.key
                end
            end
            self._selected_list_index = index
            self:_update_equip_button_status(
                self._selected_backend_id ~= nil, false)
        end)

    return state
end

return install
