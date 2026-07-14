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
