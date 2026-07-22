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
    if cim_metadata_capable ~= true or is_modded == nil then return wire_rarity end
    if is_modded == true then return "modded" end

    -- #598/#921: `false` is authoritative metadata, not absence of metadata.
    -- The preceding item in this peer/slot may already have been promoted to
    -- `modded`; normalize that cached presentation back to the vanilla-safe
    -- rarity carried on the wire when the slot changes to a non-modded item.
    if wire_rarity == "modded" then return "unique" end
    return wire_rarity
end

-- A locally resolved Cosmetics descriptor is authoritative for presentation
-- only. It is produced from Cosmetics' parity-gated peer cache and must win
-- over the primary-skin icon above; nil keeps the existing safe result.
Core.choose_presentation = function(primary_icon, cosmetic_descriptor)
    if type(cosmetic_descriptor) ~= "table" then
        return primary_icon, nil, "primary_skin"
    end
    return cosmetic_descriptor.icon or primary_icon,
        cosmetic_descriptor.display_name, "cosmetics_components"
end

return Core
