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

function M.add_character_parity(character, weapon_types)
    if character ~= "Kruber" then return false end
    for _, item_type in ipairs(M.KRUBER_SHIELD_ITEM_TYPES) do
        weapon_types[item_type] = true
    end
    return true
end

return M
