-- cosmetics_tweaker Loremaster diagnostic command owner.
-- Loaded after the LA preview hooks, preserving command registration order.
local M = {}

function M.install(mod, deps)
    local LA_BRIDGE = deps.la_bridge
    local _local_career_name = deps.local_career_name
    local _flush_log = deps.flush_log

mod:command("la_dump", "List LA-bridge cloned items", function() LA_BRIDGE.debug_dump() end)

mod:command("la_trace", "Toggle LA-bridge hook tracing (1/0)", function(arg)
    LA_BRIDGE.trace = (arg == "1" or arg == "on" or arg == "true")
    mod:echo("[la_bridge] trace = " .. tostring(LA_BRIDGE.trace))
end)

mod:command("la_force", "Force-apply LA variant to equipped hat. Usage: /la_force <armoury_key>", function(armoury_key)
    if not armoury_key then mod:echo("usage: /la_force <armoury_key>"); return end
    LA_BRIDGE.force_apply(armoury_key)
end)

mod:command("la_attach", "Dump player attachments (unit_name/skin_name/hand_unit per node)", function()
    LA_BRIDGE.dump_player_attachments()
end)

mod:command("la_loadout", "Dump current loadout for diagnostic", function()
    if not Managers.backend then mod:echo("no backend"); return end
    local items_iface = Managers.backend:get_interface("items")
    if not items_iface then mod:echo("no items iface"); return end

    mod:echo("[la_loadout] gate_installed=%s bridge_active=%s registered=%s",
        tostring(LA_BRIDGE._gate_installed), tostring(LA_BRIDGE._bridge_active), tostring(LA_BRIDGE.registered))
    mod:echo("[la_loadout] loadout_cache entries: %d", (function()
        local n = 0; for _ in pairs(mod.loadout_cache) do n = n + 1 end; return n end)())

    local loadout = items_iface:get_loadout()
    for career, slots in pairs(loadout or {}) do
        if type(slots) == "table" and slots.slot_hat then
            local hat_id = slots.slot_hat
            local is_clone = LA_BRIDGE.backend_to_armoury[hat_id] ~= nil
            mod:echo("  %s slot_hat = %s (clone=%s)", career, tostring(hat_id), tostring(is_clone))
            if is_clone then
                mod:echo("    -> armoury=%s vanilla=%s", tostring(LA_BRIDGE.backend_to_armoury[hat_id]), tostring(LA_BRIDGE.backend_to_vanilla[hat_id]))
            end
        end
    end

    local n_clones = 0
    for _ in pairs(LA_BRIDGE.backend_to_armoury) do n_clones = n_clones + 1 end
    mod:echo("[la_loadout] %d clones registered", n_clones)

    local LA = get_mod("Loremasters-Armoury")
    if LA then
        local pq, aq, lq = 0, 0, 0
        if LA.preview_queue then for _ in pairs(LA.preview_queue) do pq = pq + 1 end end
        if LA.armory_preview_queue then for _ in pairs(LA.armory_preview_queue) do aq = aq + 1 end end
        if LA.level_queue then for _ in pairs(LA.level_queue) do lq = lq + 1 end end
        mod:echo("[la_loadout] LA queues: preview=%d armory=%d level=%d", pq, aq, lq)
    end
end)

mod:command("la_hats", "List all hat items for the current career (vanilla vs clone)", function()
    if not Managers.backend then mod:echo("no backend"); return end
    local items_iface = Managers.backend:get_interface("items")
    if not items_iface then mod:echo("no items iface"); return end

    local career_name = _local_career_name()
    mod:echo("[la_hats] career=%s", tostring(career_name))

    local all_items = items_iface:get_all_backend_items()
    if not all_items then mod:echo("[la_hats] no items"); return end

    local equipped_hat_bid = nil
    if items_iface.get_loadout_item_id then
        equipped_hat_bid = items_iface:get_loadout_item_id(career_name, "slot_hat")
    end

    local n_vanilla, n_clone = 0, 0
    for bid, item in pairs(all_items) do
        local data = item.data or (ItemMasterList and rawget(ItemMasterList, item.key or bid))
        if data and data.slot_type == "hat" then
            local can = data.can_wield
            local wieldable = false
            if can then
                for _, c in ipairs(can) do
                    if c == career_name then wieldable = true; break end
                end
            end
            if wieldable then
                local is_clone = LA_BRIDGE.backend_to_armoury[bid] ~= nil
                local rarity = item.rarity or (data and data.rarity) or "?"
                local key = item.key or "?"
                local eq = (bid == equipped_hat_bid) and " [EQUIPPED]" or ""
                if is_clone then
                    n_clone = n_clone + 1
                    mod:echo("  CLONE  bid=%s rarity=%s ak=%s%s", bid, rarity, tostring(LA_BRIDGE.backend_to_armoury[bid]), eq)
                else
                    n_vanilla = n_vanilla + 1
                    mod:echo("  VANILLA bid=%s key=%s rarity=%s%s", bid, key, rarity, eq)
                end
                mod:info("[la_hats] bid=%s key=%s rarity=%s clone=%s eq=%s", bid, key, rarity, tostring(is_clone), eq)
            end
        end
    end
    mod:echo("[la_hats] %d vanilla + %d clones for %s", n_vanilla, n_clone, tostring(career_name))

    local cache_hat = mod.loadout_cache[career_name] and mod.loadout_cache[career_name]["slot_hat"]
    mod:echo("[la_hats] cache slot_hat=%s (is_clone=%s)", tostring(cache_hat), tostring(cache_hat and LA_BRIDGE.backend_to_armoury[cache_hat] ~= nil))
    mod:echo("[la_hats] gate_installed=%s", tostring(LA_BRIDGE._gate_installed))

    local raw_bid = nil
    if items_iface.get_loadout_item_id then
        local save = mod.loadout_cache
        mod.loadout_cache = {}
        raw_bid = items_iface:get_loadout_item_id(career_name, "slot_hat")
        mod.loadout_cache = save
    end
    mod:echo("[la_hats] raw server slot_hat=%s", tostring(raw_bid))

    _flush_log()
end)

end

return M
