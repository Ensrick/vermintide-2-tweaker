-- Pure issue-246 policy: reconcile the Hold-Tab loadout item with the exact
-- skin identity already synchronized onto the live inventory equipment slot.

local Core = {}

Core.resolve = function(item, equipment, slot_name, weapon_skins, local_resource_available)
    if type(item) ~= "table" or type(equipment) ~= "table"
            or type(equipment.slots) ~= "table" then
        return false, nil, nil, "equipment_unavailable"
    end

    local slot = equipment.slots[slot_name]
    if type(slot) ~= "table" then
        return false, nil, nil, "slot_unavailable"
    end

    local skin = slot.skin
    if skin == nil or skin == "n/a" then
        return true, nil, nil, "default_skin"
    end
    if type(skin) ~= "string" or type(weapon_skins) ~= "table" then
        return false, nil, nil, "skin_registry_unavailable"
    end

    local skin_data = weapon_skins[skin]
    local icon = type(skin_data) == "table" and skin_data.inventory_icon
    if type(icon) ~= "string" or icon == "" then
        return false, skin, nil, "skin_icon_unavailable"
    end
    -- #598: a synchronized skin name is identity, not proof that this peer
    -- owns the icon's atlas/package. Only the renderer's local registry may
    -- authorize a custom resource. Failure retains the vanilla-safe wire icon.
    if type(local_resource_available) == "function"
            and local_resource_available(icon, skin_data) ~= true then
        return false, skin, nil, "skin_icon_resource_unavailable"
    end

    return true, skin, icon, "exact_skin"
end

-- Safe presentation metadata is independent from resource identity. The
-- vanilla loadout RPC always carries `unique`; a same-schema CIM side-channel
-- may locally restore the frame without sending an atlas/material name.
Core.resolve_rarity = function(wire_rarity, cim_metadata_capable, is_modded)
    if cim_metadata_capable == true and is_modded == true then return "modded" end
    return wire_rarity
end

return Core
