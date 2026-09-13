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

-- #598 owner-only Cursed chrome. The caller proves the current local human,
-- slot owner and exact equipped id; definition rarity and wire item keys are
-- deliberately not fallbacks. Only a locally registered texture is eligible.
Core.owner_cursed_texture = function(item, backend_id, textures, resource_available)
    if type(item) ~= "table" or type(backend_id) ~= "string" or backend_id == ""
            or rawget(item, "backend_id") ~= backend_id
            or rawget(item, "rarity") ~= "cursed" then return nil end
    local texture = type(textures) == "table" and rawget(textures, "cursed")
    if type(texture) ~= "string" or texture == ""
            or type(resource_available) ~= "function"
            or resource_available(texture) ~= true then return nil end
    return texture
end

local OWNER_FRAME_FIELDS = {
    { "slot_melee_rarity_texture", "slot_melee_applied" },
    { "slot_ranged_rarity_texture", "slot_ranged_applied" },
}
local NIL_FRAME = {}

-- Retain only the two widget fields we own, never a backend/loadout item.
-- Restore before any fallible context read: dead/transitioning rows must not
-- keep our old custom frame when vanilla skips that row's refresh.
Core.restore_owner_frames = function(content, previous)
    for _, fields in ipairs(OWNER_FRAME_FIELDS) do
        local field, applied = fields[1], fields[2]
        local old = previous[field]
        if old ~= nil then
            if rawget(content, field) == previous[applied] then
                if old == NIL_FRAME then rawset(content, field, nil)
                else rawset(content, field, old) end
            end
            previous[field] = nil
            previous[applied] = nil
        end
    end
end

Core.apply_owner_frame = function(content, slot_name, texture, previous)
    local field = slot_name .. "_rarity_texture"
    local old = rawget(content, field)
    previous[field] = old == nil and NIL_FRAME or old
    previous[slot_name .. "_applied"] = texture
    rawset(content, field, texture)
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
