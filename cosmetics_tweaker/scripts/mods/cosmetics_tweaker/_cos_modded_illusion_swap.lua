-- Modded-realm illusion-swap owner.
--
-- This module owns the complete local crafting bypass used when CIM is absent.
-- Keeping its eight hooks and mutable request state together prevents a second
-- entry-point registration from splitting selection, crafting, and completion.

local M = {}

M.HOOK_COUNT = 8

function M.install(mod, deps)
    if mod._cos_modded_illusion_swap_owner then
        return mod._cos_modded_illusion_swap_owner
    end

    local get_mod = assert(deps.get_mod)
    local _skin_requires_unowned_dlc = assert(deps.skin_requires_unowned_dlc)
    local _custom_skin_keys = assert(deps.custom_skin_keys)
    local GlowPicker = assert(deps.glow_picker)
    local _refresh_glow_editor_button = assert(deps.refresh_glow_editor_button)
    local _dbg = assert(deps.debug)
    local _trace = assert(deps.trace)
    local _fake_skin_backend_ids = {}
    local _pending_local_craft

    local function _cim_owns_illusion_swap()
        return get_mod("cim") ~= nil
    end

    mod:hook("BackendInterfaceItemPlayfab", "get_weapon_skin_from_skin_key", function(func, self, skin_key)
        local id, item = func(self, skin_key)
        if id then return id, item end

        -- ItemMasterList.__index Crashifies on unknown keys. Illusion grids can
        -- hand us LA or CT keys which are not ItemMasterList members.
        local iml_entry = rawget(ItemMasterList, skin_key)
        local handle_vanilla_eac = script_data["eac-untrusted"] and iml_entry
            and not _skin_requires_unowned_dlc(skin_key)
            and not _cim_owns_illusion_swap()
        if _custom_skin_keys[skin_key] or handle_vanilla_eac then
            local fake_id = "ct_fake_" .. skin_key
            _fake_skin_backend_ids[fake_id] = skin_key
            return fake_id, {
                skin = skin_key,
                ItemId = skin_key,
                data = iml_entry,
                key = skin_key,
                rarity = iml_entry and iml_entry.rarity or "exotic",
            }
        end
    end)

    mod:hook("HeroWindowItemCustomization", "_enable_craft_button", function(func, self, enable, disable_edges)
        if _cim_owns_illusion_swap() then return func(self, enable, disable_edges) end
        if mod:get("apply_trace") then
            _dbg("[apply-trace] _enable_craft_button enable=%s recipe=%s skin_dirty=%s eac=%s",
                tostring(enable), tostring(self._current_recipe_name),
                tostring(self._skin_dirty), tostring(script_data["eac-untrusted"]))
        end
        if enable and script_data["eac-untrusted"] and self._current_recipe_name == "apply_weapon_skin" then
            local saved = script_data["eac-untrusted"]
            script_data["eac-untrusted"] = false
            func(self, enable, disable_edges)
            script_data["eac-untrusted"] = saved
            return
        end
        func(self, enable, disable_edges)
        if not enable and self._current_recipe_name == "apply_weapon_skin" then
            local widget = self._widgets_by_name and self._widgets_by_name.craft_button
            if widget and widget.content and widget.content.button_hotspot then
                widget.content.button_hotspot.is_held = false
                widget.content.button_hotspot.input_pressed = false
            end
        end
    end)

    mod:hook("HeroWindowItemCustomization", "_on_illusion_index_pressed", function(func, self, index, ignore_item_spawn, mark_as_equipped)
        local widget = self._illusion_widgets and self._illusion_widgets[index]
        if _cim_owns_illusion_swap() then
            local picked_skin = widget and widget.content and widget.content.skin_key
            if picked_skin then
                if GlowPicker.is_open() and not GlowPicker.is_open_for(
                    self._item_backend_id, { skin = picked_skin }) then
                    GlowPicker.close()
                end
                _refresh_glow_editor_button(self, picked_skin)
            end
            return func(self, index, ignore_item_spawn, mark_as_equipped)
        end

        _trace("INPUT PRESS illusion-grid index=%s skin=%s ignore_spawn=%s mark_equipped=%s bid=%s",
            tostring(index), tostring(widget and widget.content and widget.content.skin_key),
            tostring(ignore_item_spawn), tostring(mark_as_equipped), tostring(self._item_backend_id))
        if mod:get("apply_trace") then
            local picked_skin = widget and widget.content and widget.content.skin_key
            local current_item = self:_get_item(self._item_backend_id)
            local current_skin = current_item and current_item.skin
            if (not current_skin or current_skin == "") and current_item
                and current_item.backend_id and Managers and Managers.backend then
                local items_iface = Managers.backend:get_interface("items")
                if items_iface and items_iface.get_skin then
                    current_skin = items_iface:get_skin(current_item.backend_id)
                end
            end
            local default_skin = current_item and current_item.key
                and WeaponSkins.default_skins[current_item.key]
            local effective_current = current_skin or default_skin
            _dbg("[apply-trace] _on_illusion_index_pressed picked=%s current=%s default=%s differs=%s ignore_spawn=%s locked=%s",
                tostring(picked_skin), tostring(current_skin), tostring(default_skin),
                tostring(picked_skin ~= effective_current), tostring(ignore_item_spawn),
                tostring(widget and widget.content and widget.content.locked))
        end

        if script_data["eac-untrusted"] and not ignore_item_spawn
            and widget and widget.content then
            local skin_key = widget.content.skin_key
            if not _skin_requires_unowned_dlc(skin_key) then
                widget.content.locked = false
            end
        end

        local picked_skin = widget and widget.content and widget.content.skin_key
        if picked_skin and WeaponSkins and WeaponSkins.skins then
            local entry = WeaponSkins.skins[picked_skin]
            if entry then
                mod:info("[illusion-probe] item_bid=%s picked_skin=%s matching_item=%s material_settings=%s rarity=%s",
                    tostring(self._item_backend_id), tostring(picked_skin),
                    tostring(entry.matching_item_key), tostring(entry.material_settings_name),
                    tostring(entry.rarity))
            end
        end

        if picked_skin then
            local bid = self._item_backend_id
            if GlowPicker.is_open() and not GlowPicker.is_open_for(bid, { skin = picked_skin }) then
                GlowPicker.close()
            end
            _refresh_glow_editor_button(self, picked_skin)
        end

        return func(self, index, ignore_item_spawn, mark_as_equipped)
    end)

    mod:hook("HeroWindowItemCustomization", "_update_state_craft_button", function(func, self, recipe_name, ...)
        if _cim_owns_illusion_swap() then return func(self, recipe_name, ...) end
        if script_data["eac-untrusted"] and recipe_name == "apply_weapon_skin" then
            local saved = script_data["eac-untrusted"]
            script_data["eac-untrusted"] = false
            local result = func(self, recipe_name, ...)
            script_data["eac-untrusted"] = saved
            return result
        end
        return func(self, recipe_name, ...)
    end)

    mod:hook("BackendInterfaceCraftingPlayfab", "craft", function(func, self, career_name, item_backend_ids, recipe_override)
        if _cim_owns_illusion_swap() or not script_data["eac-untrusted"] then
            return func(self, career_name, item_backend_ids, recipe_override)
        end

        local backend_items = Managers.backend:get_interface("items")
        local weapon_backend_id, skin_key
        for _, bid in ipairs(item_backend_ids) do
            if _fake_skin_backend_ids[bid] then
                skin_key = _fake_skin_backend_ids[bid]
            else
                local item = backend_items:get_item_from_id(bid)
                if not item then
                    local fake_items = backend_items:get_all_fake_backend_items()
                    item = fake_items and fake_items[bid]
                end
                if item then
                    local slot_type = item.data and item.data.slot_type
                    if slot_type == "melee" or slot_type == "ranged" then
                        weapon_backend_id = bid
                    elseif slot_type == "weapon_skin" then
                        skin_key = item.skin or item.key
                    end
                end
            end
        end

        if not weapon_backend_id or not skin_key then
            return func(self, career_name, item_backend_ids, recipe_override)
        end
        if _skin_requires_unowned_dlc(skin_key) then
            mod:echo("Cannot apply illusion — requires DLC you don't own.")
            return func(self, career_name, item_backend_ids, recipe_override)
        end

        local mirror = self._backend_mirror
        local weapon_item = mirror._inventory_items and mirror._inventory_items[weapon_backend_id]
        if not weapon_item then
            return func(self, career_name, item_backend_ids, recipe_override)
        end

        weapon_item.skin = skin_key
        weapon_item.bypass_skin_ownership_check = true
        if weapon_item.CustomData then weapon_item.CustomData.skin = skin_key end

        local id = self:_new_id()
        _pending_local_craft = { interface = self, id = id }
        mod:info("Applied illusion '%s' locally (modded realm bypass)", skin_key)
        return id, { name = "apply_weapon_skin" }
    end)

    mod:hook_safe("BackendInterfaceCraftingPlayfab", "update", function(self, dt)
        if _cim_owns_illusion_swap() then return end
        if _pending_local_craft and _pending_local_craft.interface == self then
            self._craft_requests[_pending_local_craft.id] = {}
            Managers.backend:dirtify_interfaces()
            _pending_local_craft = nil
        end
    end)

    -- Malformed local-craft stubs have no backend id. Re-present the current
    -- item instead of allowing vanilla to dereference result[1][1].
    mod:hook("HeroWindowItemCustomization", "_upgrade_item_craft_complete", function(func, self, result)
        if self and self._item_backend_id then
            mod._offhand_committed = mod._offhand_committed or {}
            mod._offhand_committed[self._item_backend_id] = true
        end
        if result and result[1] and result[1][1] then return func(self, result) end
        local item = self._item_backend_id and self:_get_item(self._item_backend_id)
        if item then
            self:_present_item(item, nil, { 0, 2, 0 })
            self._parent:_set_loadout_item(item, self._equipment_slot_name)
            self:_state_setup_upgrade()
            self:_setup_availble_states(item)
        end
    end)

    mod:hook_safe("HeroWindowItemCustomization", "_apply_weapon_skin_craft_complete", function(self, result)
        if self and self._item_backend_id then
            mod._offhand_committed = mod._offhand_committed or {}
            mod._offhand_committed[self._item_backend_id] = true
            _trace("CRAFT apply_weapon_skin_craft_complete committed offhand bid=%s",
                tostring(self._item_backend_id))
            if mod._cos925_publish_and_refresh then
                pcall(mod._cos925_publish_and_refresh, self, "weapon-skin-apply")
            end
        end
    end)

    local owner = {
        hook_count = M.HOOK_COUNT,
        owns_illusion_swap = _cim_owns_illusion_swap,
    }
    mod._cos_modded_illusion_swap_owner = owner
    return owner
end

return M
