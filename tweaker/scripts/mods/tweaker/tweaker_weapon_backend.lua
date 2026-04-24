local M = {}

local function feature_enabled(mod, setting_id, default_value)
    local value = mod:get(setting_id)
    if value == nil then
        return default_value ~= false
    end

    return value == true
end

function M.install(mod, weapon_unlock_map, apply_weapon_unlocks)
    mod.loadout_cache = mod.loadout_cache or {}

    local function is_mod_unlocked_weapon(career_name, weapon_key)
        if not career_name or not weapon_key then
            return false
        end

        local career_weapons = weapon_unlock_map[career_name]
        if not career_weapons then
            return false
        end

        for _, unlocked_key in ipairs(career_weapons) do
            if unlocked_key == weapon_key and mod:get("unlock_" .. career_name .. "_" .. weapon_key) then
                return true
            end
        end

        return false
    end

    local function get_cached_backend_item(items_interface, career_name, slot_name)
        local slots = mod.loadout_cache[career_name]
        local backend_id = slots and slots[slot_name]
        if not backend_id then
            return nil, nil
        end

        local item = items_interface:get_item_from_id(backend_id)
        if not item then
            slots[slot_name] = nil
            return nil, nil
        end

        return backend_id, item
    end

    mod.update = function()
        if not mod._applied_unlocks and ItemMasterList then
            mod._applied_unlocks = true
            apply_weapon_unlocks()
        end

        if not mod.done_hooking_backend and Managers.backend and Managers.backend._interfaces["items"] then
            mod.done_hooking_backend = true
            local items_interface = Managers.backend:get_interface("items")

            mod:hook(items_interface, "set_loadout_item", function(func, self, backend_id, career_name, slot_name)
                if not feature_enabled(mod, "enable_weapon_backend_hooks", true) then
                    if mod.loadout_cache[career_name] then
                        mod.loadout_cache[career_name][slot_name] = nil
                    end

                    return func(self, backend_id, career_name, slot_name)
                end

                local item_data = self:get_item_from_id(backend_id)
                local weapon_key = item_data and (item_data.key or (item_data.data and item_data.data.key))

                if is_mod_unlocked_weapon(career_name, weapon_key) then
                    mod.loadout_cache[career_name] = mod.loadout_cache[career_name] or {}
                    mod.loadout_cache[career_name][slot_name] = backend_id

                    return
                end

                if mod.loadout_cache[career_name] then
                    mod.loadout_cache[career_name][slot_name] = nil
                end

                return func(self, backend_id, career_name, slot_name)
            end)

            mod:hook(items_interface, "get_loadout", function(func, self)
                local loadout = func(self)
                if not feature_enabled(mod, "enable_weapon_backend_hooks", true) then
                    return loadout
                end

                for career_name, slots in pairs(mod.loadout_cache) do
                    if loadout[career_name] then
                        for slot_name in pairs(slots) do
                            local cached_id, item = get_cached_backend_item(self, career_name, slot_name)
                            local weapon_key = item and (item.key or (item.data and item.data.key))

                            if cached_id and is_mod_unlocked_weapon(career_name, weapon_key) then
                                loadout[career_name][slot_name] = cached_id
                            else
                                slots[slot_name] = nil
                            end
                        end
                    end
                end

                return loadout
            end)

            mod:hook(items_interface, "get_loadout_item_id", function(func, self, career_name, slot_name)
                if not feature_enabled(mod, "enable_weapon_backend_hooks", true) then
                    return func(self, career_name, slot_name)
                end

                local cached_id, item = get_cached_backend_item(self, career_name, slot_name)
                local weapon_key = item and (item.key or (item.data and item.data.key))

                if cached_id and is_mod_unlocked_weapon(career_name, weapon_key) then
                    return cached_id
                end

                return func(self, career_name, slot_name)
            end)
        end
    end

    mod:hook(BackendUtils, "can_wield_item", function(func, item_data, career_name)
        if not feature_enabled(mod, "enable_weapon_ui_hooks", true) then
            return func(item_data, career_name)
        end

        local weapon_key = item_data.key or (item_data.data and item_data.data.key)
        if is_mod_unlocked_weapon(career_name, weapon_key) then
            return true
        end

        return func(item_data, career_name)
    end)

    mod:hook(ItemGridUI, "_on_category_index_change", function(func, self, index, keep_page_index)
        local results = { func(self, index, keep_page_index) }
        if not feature_enabled(mod, "enable_weapon_ui_hooks", true) then
            return unpack(results)
        end

        local settings = self._category_settings[index]
        if settings then
            local item_filter = settings.item_filter
            local career_name = self._career_name

            if (item_filter == "( slot_type == melee ) and item_rarity ~= magic" or item_filter == "( slot_type == ranged ) and item_rarity ~= magic") and weapon_unlock_map[career_name] then
                local extra_filter = ""

                for _, weapon_key in ipairs(weapon_unlock_map[career_name]) do
                    if mod:get("unlock_" .. career_name .. "_" .. weapon_key) then
                        extra_filter = extra_filter .. " or item_key == \"" .. weapon_key .. "\""
                    end
                end

                if extra_filter ~= "" then
                    settings.item_filter = "(" .. item_filter .. ")" .. extra_filter
                end
            end
        end

        return unpack(results)
    end)
end

return M
