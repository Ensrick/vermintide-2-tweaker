-- _gt_godmode_outgoing_policy.lua -- pure Godmode outgoing-damage policy.
--
-- This module owns #549's final positive-damage gate and #1008's narrowly
-- scoped armor-rejection gate. It stays engine-free for offline Lua 5.1
-- coverage; the live caller supplies vanilla-resolved armor/profile values.

local M = {}

local ARMORED = 2
local SUPER_ARMOR = 6

function M.should_override_final(damage, is_enemy, attacker_active, source_active)
    return type(damage) == "number" and damage > 0 and is_enemy == true
        and (attacker_active == true or source_active == true)
end

function M.is_armored_target(target_armor, primary_armor)
    return target_armor == ARMORED
        or target_armor == SUPER_ARMOR
        or primary_armor == ARMORED
        or primary_armor == SUPER_ARMOR
end

function M.should_override_armor_zero(damage, is_invincible, profile_no_damage,
        is_enemy, attacker_active, target_armor, primary_armor,
        attack_armor_modifier, attack_power_multiplier, target_is_hero)
    return damage == 0
        and not is_invincible
        and not profile_no_damage
        and is_enemy == true
        and attacker_active == true
        and not target_is_hero
        and type(attack_armor_modifier) == "number"
        and attack_armor_modifier == 0
        and type(attack_power_multiplier) == "number"
        and attack_power_multiplier > 0
        and M.is_armored_target(target_armor, primary_armor)
end

return M
