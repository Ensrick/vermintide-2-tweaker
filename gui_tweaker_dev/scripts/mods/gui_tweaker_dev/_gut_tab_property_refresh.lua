-- Refresh local equipped weapon properties in the held-Tab display cache (#245).
local mod = get_mod("gut_dev")
local Policy = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_tab_property_policy")
local talent_ok, TalentRefresh = pcall(mod.dofile, mod,
    "scripts/mods/gui_tweaker_dev/_gut_tab_talent_refresh")
local window = rawget(_G, "IngamePlayerListUI")
local slots = { "slot_melee", "slot_ranged" }
local log_count = 0
local hook_installed = false

local function refresh_local(self)
    local manager = Managers and Managers.player
    local loadouts = manager and manager:player_loadouts()
    local items = Managers and Managers.backend
        and Managers.backend:get_interface("items")
    if type(loadouts) ~= "table" or not items then return 0 end

    local changed = 0
    for _, player_data in ipairs(self._players or {}) do
        local player = player_data.player
        local unit = player and player.player_unit
        if player and player.local_player and unit and ALIVE[unit] then
            local inventory = ScriptUnit.has_extension(unit, "inventory_system")
            local equipment = inventory and inventory:equipment()
            local cached = loadouts[player:unique_id()]
            for _, slot_name in ipairs(slots) do
                local slot = equipment and equipment.slots and equipment.slots[slot_name]
                local backend_id = slot and slot.item_data and slot.item_data.backend_id
                local cached_item = cached and cached[slot_name]
                local live_item = backend_id and items:get_item_from_id(backend_id)
                local apply, properties = Policy.refresh(cached_item, live_item)
                if apply then
                    cached_item.properties = properties
                    changed = changed + 1
                    if log_count < Policy.MAX_LOGS then
                        log_count = log_count + 1
                        mod:info("[gut:245] slot=%s backend_id=%s properties=%s refresh=%d/%d",
                            slot_name, tostring(backend_id),
                            Policy.fingerprint(properties), log_count, Policy.MAX_LOGS)
                    end
                end
            end
        end
    end
    return changed
end

if window and type(window._update_dynamic_widget_information) == "function" then
    mod:hook(window, "_update_dynamic_widget_information", function(func, self, dt, t)
        if self._active == true then
            local now = tonumber(t) or 0
            if not self._gut245_next_refresh or now >= self._gut245_next_refresh then
                self._gut245_next_refresh = now + Policy.INTERVAL
                refresh_local(self)
            end
        end
        local result = func(self, dt, t)
        if talent_ok and type(TalentRefresh) == "table" then
            TalentRefresh.refresh(self)
        end
        return result
    end)
    hook_installed = true
end

return {
    policy = Policy,
    refresh_local = refresh_local,
    rt_checks = {
        {
            name = "issue245_tab_weapon_property_refresh",
            fn = function()
                if not hook_installed then
                    return "IngamePlayerListUI dynamic-update hook missing"
                end
                if Policy.INTERVAL < 0.25 or Policy.MAX_LOGS > 16 then
                    return "refresh/log performance bounds drifted"
                end
                local changed, values = Policy.refresh({ key = "weapon", properties = { a = 1 } },
                    { key = "weapon", properties = { a = 2 } })
                if not changed or not values or values.a ~= 2 then
                    return "property refresh policy failed"
                end
                return nil
            end,
        },
        {
            name = "issue250_deus_tab_talent_module_loaded",
            fn = function()
                if not talent_ok or type(TalentRefresh) ~= "table" then
                    return "Tab talent normalization module failed to load: "
                        .. tostring(TalentRefresh)
                end
                local check = TalentRefresh.rt_checks and TalentRefresh.rt_checks[1]
                return check and check.fn() or "Tab talent runtime check missing"
            end,
        },
    },
}
