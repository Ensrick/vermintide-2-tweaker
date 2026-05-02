local M = {}

-- CLARIFY: separate feature_enabled implementation from the one in
-- weapon_tweaker.lua because this module receives `mod` as a parameter
-- (it's a sub-module, not the mod's own scope). Both implementations use the
-- same "nil setting => fall back to default_value" pattern; default_value=true
-- means "feature enabled by default".
-- POTENTIAL BUG (LOW): `default_value ~= false` returns true if default_value
-- is nil OR true. So `feature_enabled(mod, "x")` (no default supplied) returns
-- true. Callers below all pass `true` explicitly so this is harmless, but the
-- behavior diverges from the same-named function in weapon_tweaker.lua which
-- treats omitted default as "enabled by default" (same effective result).
local function feature_enabled(mod, setting_id, default_value)
    local value = mod:get(setting_id)
    if value == nil then
        return default_value ~= false
    end

    return value == true
end

-- CLARIFY: invoked once at the bottom of weapon_tweaker.lua (~L3043). Sets
-- up backend hooks. Note: `apply_weapon_unlocks` is passed in but never
-- called from this module — only retained because it might be needed for
-- legacy code paths or future use. Could be dropped from the signature.
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

    M._filter_dirty = false

    function M.refresh_on_setting_change(mod)
        if Managers.backend and Managers.backend._interfaces["items"] then
            local items_interface = Managers.backend:get_interface("items")
            for career_name, slots in pairs(mod.loadout_cache) do
                for slot_name, backend_id in pairs(slots) do
                    local item = items_interface:get_item_from_id(backend_id)
                    local weapon_key = item and (item.key or (item.data and item.data.key))
                    if not weapon_key or not is_mod_unlocked_weapon(career_name, weapon_key) then
                        slots[slot_name] = nil
                    end
                end
                if not next(slots) then
                    mod.loadout_cache[career_name] = nil
                end
            end
        end

        M._filter_dirty = true
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

    -- CLARIFY: deferred initialization. Two one-shot guards:
    --   1. _applied_unlocks: apply_weapon_unlocks needs ItemMasterList loaded.
    --      Runs once when ItemMasterList is first available.
    --   2. done_hooking_backend: backend hooks need the items_interface INSTANCE
    --      (not class). Hooking an instance method is required because the
    --      class-form hook on `BackendInterfaceItemPlayfab.set_loadout_item`
    --      can collide with weave-mode interface usage and other mods. Runs
    --      once when Managers.backend has interfaces created (in the lobby).
    -- VMF schedules `mod.update` every frame so the conditions are polled.
    mod.update = function()
        if not mod._applied_unlocks and ItemMasterList then
            mod._applied_unlocks = true
            apply_weapon_unlocks()
        end

        if not mod.done_hooking_backend and Managers.backend and Managers.backend._interfaces["items"] then
            mod.done_hooking_backend = true
            local items_interface = Managers.backend:get_interface("items")

            -- CLARIFY: when the user equips a CROSS-CAREER (mod-unlocked)
            -- weapon, we INTERCEPT the call and store the backend_id in our
            -- own per-career cache instead of letting the original method
            -- write it to PlayFab. The original would either reject the cross-
            -- career equip or silently revert it on next sync. The cache is
            -- read back in get_loadout_item_id / get_loadout to make the
            -- equipped item appear correct in UI and gameplay.
            -- POTENTIAL BUG (LOW): the hook signature accepts 4 args but the
            -- vanilla method takes 5 (with `optional_loadout_index`). Versus
            -- mode and other code paths that pass loadout_index would have
            -- their 5th arg dropped here when our hook short-circuits with
            -- `return` (line 95-100 below). Pass `...` through to be safe.
            -- POTENTIAL BUG (LOW): vanilla returns `true`/`false`. Our
            -- short-circuit `return` returns nil. Most callers ignore the
            -- return, but `BackendInterfaceVersusPlayfab.set_loadout_item`
            -- (L111 in versus_playfab) returns this value to its caller —
            -- nil gets propagated. Probably fine since most callsites
            -- truthy-check, not `== true`.
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

            -- CLARIFY: read-side mirror of set_loadout_item. When the equipped
            -- weapon for a (career, slot) is in our cache AND still passes
            -- is_mod_unlocked_weapon (settings haven't been disabled), return
            -- our cached backend_id; otherwise fall through to vanilla.
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

    -- POTENTIAL BUG (LOW): table-form hook on `ItemGridUI`. If `ItemGridUI`
    -- isn't loaded yet at the moment M.install() runs (called from
    -- weapon_tweaker.lua bottom — after all top-level requires), this would
    -- raise "argument 'obj' should have the 'string/table' type, not 'nil'".
    -- ItemGridUI is loaded by inventory UI dependencies which load early, so
    -- this has not failed in practice. But the safer pattern is the
    -- string-form `mod:hook("ItemGridUI", ...)` per CLAUDE.md.
    mod:hook(ItemGridUI, "_on_category_index_change", function(func, self, index, keep_page_index)
        if feature_enabled(mod, "enable_weapon_ui_hooks", true) then
            if M._filter_dirty and self._category_settings then
                for _, s in ipairs(self._category_settings) do
                    if s._base_item_filter then
                        s.item_filter = s._base_item_filter
                        s._base_item_filter = nil
                    end
                end
                M._filter_dirty = false
            end

            local settings = self._category_settings and self._category_settings[index]
            if settings then
                local career_name = self._career_name
                local weapon_map = weapon_unlock_map[career_name]

                if settings._base_item_filter then
                    settings.item_filter = settings._base_item_filter
                end

                -- CLARIFY: only patch the filter when it's the EXACT vanilla
                -- "melee/ranged adventure mode" filter string. If a different
                -- mod or game mode (Versus, weave, etc.) has changed the
                -- filter, leave it alone — appending `or item_key == "..."`
                -- to a non-matching filter would change semantics.
                local base_filter = settings.item_filter
                if (base_filter == "( slot_type == melee ) and item_rarity ~= magic" or base_filter == "( slot_type == ranged ) and item_rarity ~= magic") and weapon_map then
                    local extra_filter = ""
                    for _, weapon_key in ipairs(weapon_map) do
                        if mod:get("unlock_" .. career_name .. "_" .. weapon_key) then
                            extra_filter = extra_filter .. " or item_key == \"" .. weapon_key .. "\""
                        end
                    end

                    if extra_filter ~= "" then
                        settings._base_item_filter = base_filter
                        settings.item_filter = "(" .. base_filter .. ")" .. extra_filter
                    end
                end
            end
        end

        return func(self, index, keep_page_index)
    end)
end

return M

