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

-- Independent coverage oracle for #1122. Production widens only the explicit
-- category families above, so this census deliberately starts from live trait
-- metadata instead of calling category_slot before deciding what is relevant.
-- A crafting-disabled trait is the engine-authored signal for a Chaos Wastes
-- boon family. Any such family with no slot mapping is actionable drift.
function M.unmapped_boon_categories(combinations, traits)
    local missing = {}
    if type(combinations) ~= "table" or type(traits) ~= "table" then
        return missing
    end
    for category, pool in pairs(combinations) do
        if type(category) == "string"
            and M.category_slot(category) == nil
            and type(pool) == "table"
        then
            for _, entry in ipairs(pool) do
                local key = type(entry) == "table" and entry[1] or nil
                local trait = key and traits[key]
                if type(trait) == "table" and trait.crafting_disabled == true then
                    missing[#missing + 1] = category
                    break
                end
            end
        end
    end
    table.sort(missing)
    return missing
end

return M
