-- _crt_damage_classification.lua -- pure damage-category policy shared by crt.
--
-- Centralizes the #334 self-DoT / chip / AOE classification and extends it with
-- the source-verified Ratling identities needed by Focused Spirit (#472). This
-- module has no engine or mod dependency so its exact boundary is unit-tested.
--
-- Owned by: career_tweaker.lua manifest. Consumed by:
-- career_tweaker_armor_overcharge.lua through mod._crt.damage_classification.

local M = {}

local DOT_SOURCE = "dot_debuff"

local DAMAGE_TYPES_AOE = {
    plague_face     = true,
    poison          = true,
    vomit_face      = true,
    vomit_ground    = true,
    warpfire_face   = true,
    warpfire_ground = true,
}

local RATLING_SOURCES = {
    skaven_ratling_gunner = true,
    vs_ratling_gunner     = true,
}

function M.is_chip_or_aoe(damage_source, damage_type)
    return damage_source == DOT_SOURCE
        or (damage_type ~= nil and DAMAGE_TYPES_AOE[damage_type] == true)
end

function M.is_self_dot(attacker_unit, attacked_unit, damage_type)
    return damage_type == "wounded_dot"
        and attacker_unit ~= nil
        and attacker_unit == attacked_unit
end

function M.focused_spirit_ignores(attacker_unit, attacked_unit, damage_source, damage_type)
    return M.is_chip_or_aoe(damage_source, damage_type)
        or M.is_self_dot(attacker_unit, attacked_unit, damage_type)
        or RATLING_SOURCES[damage_source] == true
end

return M
