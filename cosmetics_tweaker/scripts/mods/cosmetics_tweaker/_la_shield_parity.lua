-- Pure data policy for Loremaster's Armour shield availability.
local M = {}

-- Keep this complete catalogue as the single source of truth consumed by
-- bridge code, runtime diagnostics, and offline QA.
M.KRUBER_SHIELD_ITEM_TYPES = {
    "es_1h_sword_shield",
    "es_1h_mace_shield",
    "es_1h_sword_shield_breton",
    "es_deus_01",
    "cwv_es_axe_shield",
    "cwv_es_longsword_shield",
    "cwv_es_warpriest_hammer_shield",
}

-- Mesh-family provenance is load-bearing for texture-only LA variants.
-- Bretonnian textures are authored for the heater-shield UVs and cannot be
-- painted onto an Empire shield. Custom-unit variants carry their own mesh and
-- may still fan out across the complete Kruber catalogue.
M.KRUBER_SHIELD_FAMILIES = {
    empire = {
        "es_1h_sword_shield",
        "es_1h_mace_shield",
        "es_deus_01",
        "cwv_es_axe_shield",
        "cwv_es_longsword_shield",
        "cwv_es_warpriest_hammer_shield",
    },
    breton = {
        "es_1h_sword_shield_breton",
    },
}

-- Weavebound and Shyish shield skins use dedicated magic units whose shader
-- does not expose Loremasters' normal diffuse slot.  When a texture-only LA
-- heraldry is selected, route that magic unit to the geometrically identical
-- non-magic receiver in the SAME UV family.  Keep this an exact allow-list:
-- guessing from a generic `_magic` suffix risks painting Bretonnian heraldry
-- onto an Empire mesh (the #204/#266 regression).
local MAGIC_TEXTURE_RECEIVERS = {
    breton = {
        ["units/weapons/player/wpn_emp_gk_shield_01/wpn_emp_gk_shield_01_magic_01"] =
            "units/weapons/player/wpn_emp_gk_shield_01/wpn_emp_gk_shield_01",
    },
    empire = {
        ["units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04_magic_01"] =
            "units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04",
        ["units/weapons/player/wpn_es_deus_shield_02/wpn_es_deus_shield_02_magic"] =
            "units/weapons/player/wpn_es_deus_shield_02/wpn_es_deus_shield_02",
    },
}

function M.magic_texture_receiver(authored_family, unit_path)
    local family = MAGIC_TEXTURE_RECEIVERS[authored_family]
    return family and family[unit_path] or nil
end

function M.add_compatible_targets(character, variant_kind, authored_family, weapon_types)
    if character ~= "Kruber" then return false end
    local targets = variant_kind == "unit"
        and M.KRUBER_SHIELD_ITEM_TYPES
        or M.KRUBER_SHIELD_FAMILIES[authored_family]
    if not targets then return false end
    for _, item_type in ipairs(targets) do
        weapon_types[item_type] = true
    end
    return true
end

return M
