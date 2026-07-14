-- _cos_wire.lua -- custom weapon-skin wire-safety senders.
--
-- Owns the issue #421 null-and-restore boundary around every vanilla
-- rpc_add_equipment sender that reads a live equipment skin. Custom illusion
-- keys are never allowed onto vanilla's strict NetworkLookup wire; the local
-- slot is restored immediately after the vanilla continuation returns. This
-- coercion is unconditional and must never be gated by a setting.
--
-- Owned by: cosmetics_tweaker.lua entry point. Consumed via: mod:dofile, after
-- _cos_illusions has populated mod._cos.custom_skin_keys.

local COS = mod._cos
local _custom_skin_keys = COS.custom_skin_keys

-- v0.9.75-dev: pure wrapper around the shipped sender boundary so the runtime
-- regression suite can drive the exact null-and-restore path without a network
-- session. Preserve up to four vanilla return values.
local function _wire_null_custom_skins(slots, send_fn, context)
    local saved
    for _, slot_data in pairs(slots) do
        local skin = slot_data and slot_data.skin
        if skin and _custom_skin_keys[skin] then
            saved = saved or {}
            saved[slot_data] = skin
            slot_data.skin = nil
            pcall(printf, "[cos:421] wire skin null (%s): %s -> n/a",
                tostring(context or "?"), tostring(skin))
        end
    end
    local r1, r2, r3, r4 = send_fn()
    if saved then
        for slot_data, skin in pairs(saved) do
            slot_data.skin = skin
        end
    end
    return r1, r2, r3, r4
end

-- These established mod fields are frozen regression/documentation surface.
mod._cos_wire_null_custom_skins = _wire_null_custom_skins
mod._cos_skin_wire_surfaces = {}

-- Initial player equipment broadcast.
mod:hook("SimpleInventoryExtension", "game_object_initialized", function(func, self, unit, unit_go_id)
    local slots = self and self._equipment and self._equipment.slots
    if not slots then
        return func(self, unit, unit_go_id)
    end
    return _wire_null_custom_skins(slots, function()
        return func(self, unit, unit_go_id)
    end, "game_object_initialized")
end)
mod._cos_skin_wire_surfaces.game_object_initialized = true

-- Mid-session equip/loadout respawn broadcast. equipment_to_spawn is one
-- slot-shaped table, so wrap it for the shared pairs() traversal.
mod:hook("SimpleInventoryExtension", "_spawn_resynced_loadout", function(func, self, equipment_to_spawn, skip_wield)
    if not (equipment_to_spawn and equipment_to_spawn.skin) then
        return func(self, equipment_to_spawn, skip_wield)
    end
    return _wire_null_custom_skins({ equipment_to_spawn }, function()
        return func(self, equipment_to_spawn, skip_wield)
    end, "spawn_resynced_loadout")
end)
mod._cos_skin_wire_surfaces.spawn_resynced_loadout = true

-- Host replay to a joining peer.
mod:hook("GearUtils", "hot_join_sync", function(func, peer_id, unit, equipment, additional_items)
    local slots = equipment and equipment.slots
    if not slots then
        return func(peer_id, unit, equipment, additional_items)
    end
    return _wire_null_custom_skins(slots, function()
        return func(peer_id, unit, equipment, additional_items)
    end, "hot_join_sync")
end)
mod._cos_skin_wire_surfaces.hot_join_sync = true

