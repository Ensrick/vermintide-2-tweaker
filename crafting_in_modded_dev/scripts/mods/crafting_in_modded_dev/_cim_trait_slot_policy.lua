-- Pure Chaos Wastes trait-category policy.
--
-- Vermintide does not put a slot_type on individual traits. Eligibility is
-- encoded by the WeaponTraits.combinations category containing the trait, so
-- CIM must preserve those exact category families when widening a reroll pool.
local M = {}

local MELEE_CATEGORIES = {
    deus_melee = true,
    deus_shield_melee = true,
    deus_heavy_melee = true,
}

local RANGED_CATEGORIES = {
    deus_ranged = true,
    deus_ranged_ammo = true,
    deus_ranged_heat = true,
    ranged_energy = true,
    deus_ranged_energy = true,
    deus_trollhammer_torpedo = true,
}

function M.category_slot(category)
    if MELEE_CATEGORIES[category] then return "melee" end
    if RANGED_CATEGORIES[category] then return "ranged" end
    return nil
end

function M.category_matches_slot(category, slot_type)
    return M.category_slot(category) == slot_type
end

return M
