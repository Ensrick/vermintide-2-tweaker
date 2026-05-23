--[[
weapon_tweaker_big_rebalance_defs.lua
======================================

DEFINITIONS for every NEW DamageProfileTemplate, ExplosionTemplate, and
BuffTemplate that wt registers as part of Core's Big Rebalance.

Sourced verbatim from `_big_rebalance_extract/source/weapon_changes.lua`
and the inventories. Definitions are pure data — registration order /
gating happens in weapon_tweaker_big_rebalance.lua.
]]

local mod = get_mod("wt")

local DEFS = {}

-- ============================================================
-- NEW DAMAGE PROFILE TEMPLATES (wt-owned)
-- ============================================================

DEFS.damage_profiles = {}

DEFS.damage_profiles.gs_1h_heavy = {
    charge_value = "heavy_attack",
    shield_break = true,
    armor_modifier = {
        attack = { 1, 0.8, 2.5, 1, 0.75, 1 },
        impact = { 1, 0.6, 1, 1, 0.75 },
    },
    critical_strike = {
        attack_armor_power_modifer = { 1, 0.8, 2.5, 1, 1, 1 },
        impact_armor_power_modifer = { 1, 0.8, 1, 1, 1, 0.5 },
    },
    cleave_distribution = { attack = 0.075, impact = 0.075 },
    default_target = {
        attack_template = "slashing_smiter",
        boost_curve_type = "smiter_curve",
        boost_curve_coefficient = 2,
        boost_curve_coefficient_headshot = 1.5,
        power_distribution = { attack = 0.45, impact = 0.25 },
    },
    targets = {
        [2] = {
            boost_curve_type = "tank_curve",
            attack_template = "light_blunt_tank",
            power_distribution = { attack = 0.1, impact = 0.1 },
        },
    },
}

DEFS.damage_profiles.tb_two_handed_sword_heavy = {
    charge_value = "heavy_attack",
    armor_modifier = {
        attack = { 1, 0.2, 2, 1, 0.5 },
        impact = { 1, 0.5, 0.5, 1, 1 },
    },
    critical_strike = {
        attack_armor_power_modifer = { 1, 0.4, 2.5, 1, 0.5 },
        impact_armor_power_modifer = { 1, 0.5, 0.5, 1, 1 },
    },
    cleave_distribution = { attack = 0.75, impact = 0.4 },
    default_target = {
        boost_curve_type = "linesman_curve",
        attack_template = "light_slashing_linesman",
        boost_curve_coefficient_headshot = 0.75,
        power_distribution = { attack = 0.14, impact = 0.05 },
    },
    targets = {
        { attack_template = "heavy_slashing_linesman", boost_curve_type = "linesman_curve",
          boost_curve_coefficient = 2, boost_curve_coefficient_headshot = 1,
          power_distribution = { attack = 0.45, impact = 0.275 } },
        { attack_template = "heavy_slashing_linesman", boost_curve_type = "linesman_curve",
          boost_curve_coefficient_headshot = 1,
          power_distribution = { attack = 0.4, impact = 0.15 },
          armor_modifier = {
              attack = { 1, 0.2, 2, 1, 0.5 },
              impact = { 1, 0.5, 0.5, 1, 1 },
          } },
        { boost_curve_type = "linesman_curve", attack_template = "slashing_linesman",
          power_distribution = { attack = 0.25, impact = 0.1 } },
        { boost_curve_type = "linesman_curve", attack_template = "slashing_linesman",
          power_distribution = { attack = 0.15, impact = 0.075 } },
    },
}

DEFS.damage_profiles.gs_heavy_slashing_smiter = {
    charge_value = "heavy_attack",
    shield_break = true,
    armor_modifier = {
        attack = { 1, 0.5, 1.5, 1, 0.75 },
        impact = { 1, 1, 1, 1, 0.75 },
    },
    critical_strike = {
        attack_armor_power_modifer = { 1, 0.75, 1.5, 1, 1 },
        impact_armor_power_modifer = { 1, 1, 1, 1, 1 },
    },
    cleave_distribution = { attack = 0.075, impact = 0.075 },
    default_target = {
        attack_template = "heavy_slashing_smiter",
        boost_curve_type = "ninja_curve",
        boost_curve_coefficient = 0.75,
        boost_curve_coefficient_headshot = 1.5,
        power_distribution = { attack = 0.65, impact = 0.25 },
    },
    targets = {
        [2] = {
            boost_curve_type = "smiter_curve",
            attack_template = "stab_smiter",
            power_distribution = { attack = 0.2, impact = 0.1 },
        },
    },
}

-- Halberd TB family (5 entries)
DEFS.damage_profiles.tb_halberd_light_slash = {
    default_target = "default_target_axe_linesman_M",
    critical_strike = "critical_strike_axe_linesman_M",
    charge_value = "light_attack",
    armor_modifier = "armor_modifier_axe_linesman_M",
    cleave_distribution = { attack = 0.4, impact = 0.25 },
    targets = {
        { attack_template = "heavy_slashing_linesman", boost_curve_type = "linesman_curve",
          boost_curve_coefficient_headshot = 1.5,
          power_distribution = { attack = 0.25, impact = 0.2 },
          armor_modifier = {
              attack = { 1.25, 0.3, 1.5, 1, 0.75 },
              impact = { 0.9, 0.75, 1, 1, 0.75 },
          } },
        { attack_template = "heavy_slashing_linesman", boost_curve_type = "linesman_curve",
          boost_curve_coefficient_headshot = 1.5,
          power_distribution = { attack = 0.2, impact = 0.15 } },
        { attack_template = "slashing_linesman", boost_curve_type = "linesman_curve",
          power_distribution = { attack = 0.15, impact = 0.1 } },
    },
}

DEFS.damage_profiles.tb_halberd_light_stab = {
    default_target = "default_target_axe_linesman_M",
    critical_strike = "critical_strike_axe_linesman_M",
    charge_value = "light_attack",
    armor_modifier = "armor_modifier_axe_linesman_M",
    melee_boost_override = 2.5,
    cleave_distribution = { attack = 0.4, impact = 0.25 },
    targets = {
        { attack_template = "heavy_slashing_linesman", boost_curve_type = "linesman_curve",
          boost_curve_coefficient_headshot = 1.5,
          power_distribution = { attack = 0.25, impact = 0.2 } },
        { attack_template = "slashing_linesman", boost_curve_type = "linesman_curve",
          power_distribution = { attack = 0.2, impact = 0.15 } },
    },
}

DEFS.damage_profiles.tb_halberd_heavy_slash = {
    default_target = "default_target_axe_linesman_H",
    critical_strike = "critical_strike_axe_linesman_H",
    charge_value = "heavy_attack",
    armor_modifier = "armor_modifier_axe_linesman_H",
    cleave_distribution = { attack = 0.6, impact = 0.35 },
    targets = {
        { attack_template = "heavy_slashing_linesman", boost_curve_type = "linesman_curve",
          boost_curve_coefficient_headshot = 1.5,
          power_distribution = { attack = 0.4, impact = 0.275 } },
        { attack_template = "heavy_slashing_linesman", boost_curve_type = "linesman_curve",
          boost_curve_coefficient_headshot = 1.5,
          power_distribution = { attack = 0.3, impact = 0.2 } },
        { attack_template = "slashing_linesman", boost_curve_type = "linesman_curve",
          power_distribution = { attack = 0.2, impact = 0.15 } },
    },
}

DEFS.damage_profiles.tb_halberd_heavy_stab = {
    default_target = "default_target_axe_linesman_H",
    critical_strike = "critical_strike_axe_linesman_H",
    charge_value = "heavy_attack",
    armor_modifier = "armor_modifier_axe_linesman_H",
    melee_boost_override = 2.5,
    cleave_distribution = { attack = 0.4, impact = 0.25 },
    targets = {
        { attack_template = "heavy_slashing_linesman", boost_curve_type = "linesman_curve",
          boost_curve_coefficient_headshot = 1.5,
          power_distribution = { attack = 0.45, impact = 0.275 } },
        { attack_template = "slashing_linesman", boost_curve_type = "linesman_curve",
          power_distribution = { attack = 0.3, impact = 0.15 } },
    },
}

DEFS.damage_profiles.tb_halberd_light_chop = {
    default_target = "default_target_axe_linesman_M",
    critical_strike = "critical_strike_axe_linesman_M",
    charge_value = "light_attack",
    armor_modifier = "armor_modifier_axe_linesman_M",
    shield_break = true,
    melee_boost_override = 2.5,
    cleave_distribution = { attack = 0.5, impact = 0.25 },
    targets = {
        { attack_template = "heavy_slashing_linesman", boost_curve_type = "linesman_curve",
          boost_curve_coefficient_headshot = 1.5,
          power_distribution = { attack = 0.3, impact = 0.2 } },
        { attack_template = "slashing_linesman", boost_curve_type = "linesman_curve",
          power_distribution = { attack = 0.2, impact = 0.15 } },
    },
}

DEFS.damage_profiles.medium_blunt_smiter_bop_pick = {
    charge_value = "light_attack",
    cleave_distribution = { attack = 0.5, impact = 0.4 },
    armor_modifier = {
        attack = { 1, 0.8, 2.5, 0.75, 1, 0.6 },
        impact = { 1, 0.8, 1, 1, 1 },
    },
    critical_strike = {
        attack_armor_power_modifer = { 1, 1, 2.5, 1, 1, 1 },
        impact_armor_power_modifer = { 1, 1, 1, 1, 1.5 },
    },
    default_target = {
        boost_curve_type = "smiter_curve",
        attack_template = "blunt_smiter",
        boost_curve_coefficient = 2,
        power_distribution = { attack = 0.5, impact = 0.25 },
    },
    targets = {
        [2] = {
            boost_curve_type = "tank_curve",
            attack_template = "light_blunt_tank",
            power_distribution = { attack = 0.1, impact = 0.1 },
        },
    },
}

DEFS.damage_profiles.falchion_heavy = {
    charge_value = "heavy_attack",
    shield_break = true,
    melee_boost_override = 5,
    armor_modifier = "armor_modifier_slashing_smiter_H",
    critical_strike = "critical_strike_slashing_smiter_H",
    cleave_distribution = "cleave_distribution_slashing_smiter_H",
    default_target = {
        attack_template = "heavy_slashing_smiter",
        boost_curve_type = "smiter_curve",
        boost_curve_coefficient = 2,
        boost_curve_coefficient_headshot = 1.5,
        power_distribution = { attack = 0.65, impact = 0.4 },
    },
    targets = {
        [2] = {
            boost_curve_type = "tank_curve",
            attack_template = "light_blunt_tank",
            power_distribution = { attack = 0.15, impact = 0.1 },
        },
    },
}

DEFS.damage_profiles.heavy_dash = {
    charge_value = "heavy_attack",
    shield_break = true,
    armor_modifier = {
        attack = { 1, 0.5, 2, 1, 0.5, 0.5 },
        impact = { 1, 1, 1, 1, 1.5, 1 },
    },
    critical_strike = {
        attack_armor_power_modifer = { 1, 0.5, 2, 1, 0.75, 1 },
        impact_armor_power_modifer = { 1, 1, 1, 1, 1.5, 1 },
    },
    cleave_distribution = { attack = 0.1, impact = 0.5 },
    default_target = {
        attack_template = "blunt_smiter",
        boost_curve_type = "smiter_curve",
        boost_curve_coefficient = 2,
        boost_curve_coefficient_headshot = 1.5,
        power_distribution = { attack = 0.4, impact = 1.5 },
    },
}

DEFS.damage_profiles.glaive_uppercut = {
    charge_value = "heavy_attack",
    shield_break = true,
    armor_modifier = {
        attack = { 1, 0.5, 2.5, 1, 0.75 },
        impact = { 1, 1, 1, 1, 1, 0.5 },
    },
    critical_strike = {
        attack_armor_power_modifer = { 1, 0.75, 2.5, 1, 1 },
        impact_armor_power_modifer = { 1, 1, 1, 1, 1.5, 0.5 },
    },
    cleave_distribution = { attack = 0.1, impact = 0.1 },
    default_target = {
        attack_template = "heavy_slashing_smiter",
        boost_curve_type = "smiter_curve",
        boost_curve_coefficient = 2,
        boost_curve_coefficient_headshot = 1.5,
        power_distribution = { attack = 0.55, impact = 0.3 },
    },
    targets = {
        [2] = {
            boost_curve_type = "tank_curve",
            attack_template = "light_blunt_tank",
            power_distribution = { attack = 0.1, impact = 0.1 },
        },
    },
}

DEFS.damage_profiles.repeating_crossbow_elf_projectile = {
    charge_value = "projectile",
    no_stagger_damage_reduction_ranged = true,
    armor_modifier = {
        attack = { 1, 0.3, 2.5, 0.4, 0.75, 0.075 },
        impact = { 1, 1, 1, 1, 1 },
    },
    critical_strike = {
        attack_armor_power_modifer = { 1, 0.6, 3.5, 0.5, 1, 0.1 },
        impact_armor_power_modifer = { 1, 1, 1, 1, 1.5 },
    },
    cleave_distribution = { attack = 0.4, impact = 0.4 },
    default_target = {
        attack_template = "crossbow_repeating",
        boost_curve_type = "ranged_curve",
        boost_curve_coefficient_headshot = 1.5,
        power_distribution = { attack = 0.275, impact = 0.1 },
    },
}

DEFS.damage_profiles.shot_sniper_pistol_burst = {
    charge_value = "projectile",
    armor_modifier_near = {
        attack = { 1, 0.5, 1.5, 0.5, 1, 0.075 },
        impact = { 1, 1, 1, 1, 1 },
    },
    armor_modifier_far = {
        attack = { 1, 0.2, 0.5, 0.25, 0.5, 0.05 },
        impact = { 1, 1, 0.75, 1, 1 },
    },
    critical_strike = {
        attack_armor_power_modifer = { 1, 1, 1.5, 1, 1, 0.1 },
        impact_armor_power_modifer = { 1, 1, 1, 1, 1.5 },
    },
    cleave_distribution = { attack = 0.5, impact = 0.5 },
    default_target = {
        attack_template = "pistol_sniper",
        boost_curve_type = "ranged_curve",
        boost_curve_coefficient_headshot = 1.5,
        power_distribution_near = { attack = 0.6, impact = 0.4 },
        power_distribution_far = { attack = 0.3, impact = 0.2 },
        range_modifier_settings = { min_range = 5, max_range = 15 },
    },
}

DEFS.damage_profiles.shot_shotgun_cbr = {
    charge_value = "projectile",
    armor_modifier = {
        attack = { 1, 0.5, 1.25, 0.5, 1, 0.1 },
        impact = { 1, 1, 1, 1, 1 },
    },
    critical_strike = {
        attack_armor_power_modifer = { 1, 1, 1.5, 1, 1, 0.15 },
        impact_armor_power_modifer = { 1, 1, 1, 1, 1.5 },
    },
    cleave_distribution = { attack = 0.2, impact = 0.5 },
    default_target = {
        attack_template = "shotgun_cbr",
        boost_curve_type = "ranged_curve",
        boost_curve_coefficient_headshot = 1.5,
        power_distribution = { attack = 0.4, impact = 0.4 },
    },
}

DEFS.damage_profiles.grudge_action_three = {
    charge_value = "projectile",
    armor_modifier = {
        attack = { 1, 0.65, 1.75, 1, 1, 0.25 },
        impact = { 1, 1, 1, 1, 1 },
    },
    critical_strike = {
        attack_armor_power_modifer = { 1, 1, 2, 1, 1, 0.4 },
        impact_armor_power_modifer = { 1, 1, 1, 1, 1.5 },
    },
    cleave_distribution = { attack = 0.5, impact = 0.5 },
    default_target = {
        attack_template = "shotgun_cbr",
        boost_curve_type = "ranged_curve",
        boost_curve_coefficient_headshot = 1.5,
        power_distribution = { attack = 0.6, impact = 0.5 },
    },
}

DEFS.damage_profiles.blunder_action_three = {
    charge_value = "projectile",
    armor_modifier = {
        attack = { 1, 0.5, 1.5, 0.75, 1, 0.2 },
        impact = { 1, 1, 1, 1, 1 },
    },
    critical_strike = {
        attack_armor_power_modifer = { 1, 1, 1.75, 1, 1, 0.3 },
        impact_armor_power_modifer = { 1, 1, 1, 1, 1.5 },
    },
    cleave_distribution = { attack = 0.45, impact = 0.45 },
    default_target = {
        attack_template = "shotgun_cbr",
        boost_curve_type = "ranged_curve",
        boost_curve_coefficient_headshot = 1.5,
        power_distribution = { attack = 0.5, impact = 0.45 },
    },
}

DEFS.damage_profiles.beam_blast = {
    charge_value = "projectile",
    no_damage_reduction_aoe = true,
    armor_modifier = {
        attack = { 1, 0.5, 0.5, 0.5, 1, 0.1 },
        impact = { 1, 1, 1, 1, 1 },
    },
    critical_strike = {
        attack_armor_power_modifer = { 1, 1, 0.75, 1, 1, 0.15 },
        impact_armor_power_modifer = { 1, 1, 1, 1, 1.5 },
    },
    cleave_distribution = { attack = 0.3, impact = 0.4 },
    default_target = {
        attack_template = "beam_staff",
        boost_curve_type = "ranged_curve",
        dot_template_name = "burning_1W_dot",
        power_distribution = { attack = 0.5, impact = 0.3 },
    },
}

DEFS.damage_profiles.mace_sword_bopp = {
    stagger_duration_modifier = 1.5,
    charge_value = "light_attack",
    critical_strike = {
        attack_armor_power_modifer = { 1, 0.5, 2, 1, 1 },
        impact_armor_power_modifer = { 1, 1, 0.5, 1, 1 },
    },
    cleave_distribution = { attack = 0.2, impact = 0.2 },
    armor_modifier = {
        attack = { 1, 0.5, 1.5, 1, 0.5 },
        impact = { 1, 1, 0.5, 1, 1 },
    },
    default_target = {
        boost_curve_type = "tank_curve",
        attack_template = "light_blunt_tank",
        power_distribution = { attack = 0.25, impact = 0.4 },
    },
}

DEFS.damage_profiles.mace_sword_heavy = {
    charge_value = "heavy_attack",
    melee_boost_override = 6,
    armor_modifier = {
        attack = { 1, 0.6, 2, 1, 0.75 },
        impact = { 1, 0.75, 0.5, 1, 1 },
    },
    critical_strike = {
        attack_armor_power_modifer = { 1, 0.75, 2.5, 1, 1 },
        impact_armor_power_modifer = { 1, 1, 0.5, 1, 1 },
    },
    cleave_distribution = { attack = 0.1, impact = 0.1 },
    default_target = {
        attack_template = "heavy_slashing_smiter",
        boost_curve_type = "smiter_curve",
        boost_curve_coefficient = 2,
        boost_curve_coefficient_headshot = 1.5,
        power_distribution = { attack = 0.55, impact = 0.3 },
    },
}

DEFS.damage_profiles.medium_slashing_tank_1h_new = {
    charge_value = "heavy_attack",
    armor_modifier = {
        attack = { 1, 0.5, 2, 1, 0.75 },
        impact = { 1, 0.5, 0.5, 1, 0.75 },
    },
    critical_strike = "critical_strike_stab_smiter_H",
    cleave_distribution = "cleave_distribution_tank_L",
    default_target = {
        boost_curve_type = "tank_curve",
        attack_template = "light_blunt_tank",
        power_distribution = { attack = 0.05, impact = 0.05 },
    },
    targets = {
        { boost_curve_coefficient_headshot = 1.5, boost_curve_type = "ninja_curve",
          attack_template = "blunt_tank",
          armor_modifier = {
              attack = { 1, 0.65, 2, 1, 0.75 },
              impact = { 1, 1, 0.5, 1, 0.75 },
          },
          power_distribution = { attack = 0.35, impact = 0.2 } },
        { boost_curve_type = "ninja_curve", boost_curve_coefficient_headshot = 1.5,
          attack_template = "blunt_tank",
          power_distribution = { attack = 0.18, impact = 0.18 } },
        { boost_curve_type = "ninja_curve", attack_template = "light_blunt_tank",
          power_distribution = { attack = 0.15, impact = 0.15 } },
    },
}

DEFS.damage_profiles.light_slashing_linesman_flat_new = {
    charge_value = "light_attack",
    armor_modifier = {
        attack = { 1, 0.3, 2, 1, 1 },
        impact = { 1, 0.3, 0.5, 1, 1 },
    },
    cleave_distribution = { attack = 0.35, impact = 0.2 },
    critical_strike = {
        attack_armor_power_modifer = { 1, 0.3, 2.5, 1, 1 },
        impact_armor_power_modifer = { 1, 0.5, 0.5, 1, 1 },
    },
    default_target = {
        boost_curve_type = "linesman_curve",
        attack_template = "light_slashing_linesman",
        power_distribution = { attack = 0.15, impact = 0.05 },
    },
    targets = {
        { boost_curve_coefficient_headshot = 2, boost_curve_type = "ninja_curve",
          boost_curve_coefficient = 2,
          attack_template = "light_slashing_linesman_hs",
          power_distribution = { attack = 0.225, impact = 0.1 } },
        { boost_curve_type = "ninja_curve", boost_curve_coefficient_headshot = 2,
          attack_template = "light_slashing_linesman",
          power_distribution = { attack = 0.175, impact = 0.075 } },
    },
}

-- Moonbow charged DoT damage profile (assigned new in BR)
DEFS.damage_profiles.we_deus_01_charged = {
    charge_value = "projectile",
    armor_modifier = {
        attack = { 1, 1, 0.25, 1, 0.5, 0.075 },
        impact = { 1, 1, 1, 1, 1 },
    },
    critical_strike = {
        attack_armor_power_modifer = { 1, 1, 0.5, 1, 1, 0.1 },
        impact_armor_power_modifer = { 1, 1, 1, 1, 1.5 },
    },
    cleave_distribution = { attack = 0.5, impact = 0.5 },
    default_target = {
        attack_template = "longbow_arrow",
        boost_curve_type = "ranged_curve",
        boost_curve_coefficient_headshot = 1.5,
        dot_template_name = "we_deus_01_dot_special_charged",
        power_distribution = { attack = 0.85, impact = 0.4 },
    },
}

-- Simple placeholder profiles (orphan / utility entries from BR)
DEFS.damage_profiles.dummy = {
    charge_value = "action_push",
    armor_modifier = { attack = { 1, 1, 1, 1, 1 }, impact = { 1, 1, 1, 1, 1 } },
    critical_strike = {
        attack_armor_power_modifer = { 1, 1, 1, 1, 1 },
        impact_armor_power_modifer = { 1, 1, 1, 1, 1 },
    },
    cleave_distribution = { attack = 0.1, impact = 0.1 },
    default_target = {
        attack_template = "light_blunt_tank",
        boost_curve_type = "tank_curve",
        power_distribution = { attack = 0, impact = 0.1 },
    },
}

DEFS.damage_profiles.dot_low_damage = {
    charge_value = "n/a",
    no_stagger = true,
    armor_modifier = {
        attack = { 1, 1, 1, 1, 1, 1 },
        impact = { 0, 0, 0, 0, 0, 0 },
    },
    cleave_distribution = { attack = 1, impact = 1 },
    default_target = {
        attack_template = "burning",
        boost_curve_type = "tank_curve",
        boost_curve_coefficient = 0.2,
        damage_type = "burninating",
        power_distribution = { attack = 0.5, impact = 0.1 },
    },
}

DEFS.damage_profiles.dot_low_low_damage = {
    charge_value = "n/a",
    no_stagger = true,
    armor_modifier = {
        attack = { 1, 1, 1, 1, 1, 1 },
        impact = { 0, 0, 0, 0, 0, 0 },
    },
    cleave_distribution = { attack = 1, impact = 1 },
    default_target = {
        attack_template = "burning",
        boost_curve_type = "tank_curve",
        boost_curve_coefficient = 0.1,
        damage_type = "burninating",
        power_distribution = { attack = 0.25, impact = 0.1 },
    },
}

DEFS.damage_profiles.heavy_poison_aoe = {
    charge_value = "n/a",
    no_stagger = true,
    armor_modifier = {
        attack = { 1, 1, 0, 0, 1, 0 },
        impact = { 0, 0, 0, 0, 0, 0 },
    },
    cleave_distribution = { attack = 1, impact = 1 },
    default_target = {
        attack_template = "burning",
        boost_curve_type = "tank_curve",
        damage_type = "poison",
        power_distribution = { attack = 0.5, impact = 0.1 },
    },
}

DEFS.damage_profiles.heavy_poison = {
    charge_value = "n/a",
    no_stagger = true,
    armor_modifier = {
        attack = { 1, 1, 0, 0, 1, 0 },
        impact = { 0, 0, 0, 0, 0, 0 },
    },
    cleave_distribution = { attack = 1, impact = 1 },
    default_target = {
        attack_template = "burning",
        boost_curve_type = "tank_curve",
        damage_type = "poison",
        power_distribution = { attack = 0.75, impact = 0.1 },
    },
}

DEFS.damage_profiles.long_burn_explosion = {
    charge_value = "explosion",
    no_friendly_fire = true,
    armor_modifier = {
        attack = { 1, 1, 0.5, 0.5, 1, 0.1 },
        impact = { 1, 1, 1, 1, 1 },
    },
    cleave_distribution = { attack = 1, impact = 1 },
    default_target = {
        attack_template = "drakegun",
        boost_curve_type = "ranged_curve",
        dot_template_name = "burning_1W_dot_drakegun",
        power_distribution = { attack = 0.3, impact = 0.2 },
    },
}

DEFS.damage_profiles.long_burn_explosion_glance = {
    charge_value = "explosion",
    no_friendly_fire = true,
    armor_modifier = {
        attack = { 1, 1, 0.5, 0.5, 1, 0.1 },
        impact = { 1, 1, 1, 1, 1 },
    },
    cleave_distribution = { attack = 1, impact = 1 },
    default_target = {
        attack_template = "drakegun",
        boost_curve_type = "ranged_curve",
        dot_template_name = "burning_1W_dot_drakegun",
        power_distribution = { attack = 0.15, impact = 0.1 },
    },
}

DEFS.damage_profiles.melee_kill_explosion = {
    charge_value = "explosion",
    no_friendly_fire = true,
    armor_modifier = {
        attack = { 1, 1, 1, 1, 1, 0.3 },
        impact = { 1, 1, 1, 1, 1 },
    },
    cleave_distribution = { attack = 1, impact = 1 },
    default_target = {
        attack_template = "light_blunt_tank",
        boost_curve_type = "tank_curve",
        power_distribution = { attack = 0.3, impact = 0.3 },
    },
}

DEFS.damage_profiles.melee_kill_explosion_glance = {
    charge_value = "explosion",
    no_friendly_fire = true,
    armor_modifier = {
        attack = { 1, 1, 1, 1, 1, 0.15 },
        impact = { 1, 1, 1, 1, 1 },
    },
    cleave_distribution = { attack = 1, impact = 1 },
    default_target = {
        attack_template = "light_blunt_tank",
        boost_curve_type = "tank_curve",
        power_distribution = { attack = 0.15, impact = 0.15 },
    },
}

DEFS.damage_profiles.weak_bomb_explosion = {
    charge_value = "explosion",
    armor_modifier = {
        attack = { 1, 1, 1, 1, 1, 0.5 },
        impact = { 1, 1, 1, 1, 1 },
    },
    cleave_distribution = { attack = 1, impact = 1 },
    default_target = {
        attack_template = "frag_grenade",
        boost_curve_type = "ranged_curve",
        power_distribution = { attack = 0.5, impact = 0.5 },
    },
}

DEFS.damage_profiles.burning_dot_weak_bomb = {
    charge_value = "n/a",
    no_stagger = true,
    armor_modifier = {
        attack = { 1, 1, 0.5, 0.5, 1, 0.1 },
        impact = { 0, 0, 0, 0, 0, 0 },
    },
    cleave_distribution = { attack = 1, impact = 1 },
    default_target = {
        attack_template = "burning",
        boost_curve_type = "tank_curve",
        damage_type = "burninating",
        power_distribution = { attack = 0.3, impact = 0.1 },
    },
}

-- New: WW Trueflight Piercing Shot ammo profile (registered for both bases)
DEFS.damage_profiles.arrow_sniper_trueflight = {
    charge_value = "projectile",
    max_friendly_damage = 5,
    armor_modifier = {
        attack = { 1, 1, 2, 0.5, 1, 1 },
        impact = { 1, 1, 1, 1, 1 },
    },
    critical_strike = {
        attack_armor_power_modifer = { 1, 1, 2.5, 1, 1, 1 },
        impact_armor_power_modifer = { 1, 1, 1, 1, 1.5 },
    },
    cleave_distribution = { attack = 0.4, impact = 0.4 },
    default_target = {
        attack_template = "longbow_arrow",
        boost_curve_type = "ninja_curve",
        boost_curve_coefficient_headshot = 2,
        power_distribution = { attack = 0.7, impact = 0.4 },
    },
}

-- Replacement profiles for shield slam (assigned to DamageProfileTemplates
-- directly in BR — we treat them as "registrations" so master pre-load
-- creates them even if not yet referenced).
DEFS.damage_profiles.shield_slam_target = {
    stagger_duration_modifier = 1.75,
    shield_break = true,
    charge_value = "heavy_attack",
    critical_strike = {
        attack_armor_power_modifer = { 1, 0.5, 2, 1, 1 },
        impact_armor_power_modifer = { 1, 1, 0.5, 1, 2 },
    },
    default_target = {
        boost_curve_type = "tank_curve",
        attack_template = "heavy_blunt_fencer",
        power_distribution = { attack = 0.2, impact = 0.375 },
    },
    armor_modifier = {
        attack = { 1, 0.3, 2, 1, 0.75 },
        impact = { 1, 0.8, 1, 1, 2, 1.25 },
    },
}

DEFS.damage_profiles.shield_slam = {
    stagger_duration_modifier = 1.75,
    charge_value = "heavy_attack",
    armor_modifier = "armor_modifier_slam_tank_M",
    critical_strike = {
        attack_armor_power_modifer = { 1, 0.5, 2, 1, 1 },
        impact_armor_power_modifer = { 1, 1, 0.5, 1, 1.5 },
    },
    default_target = {
        boost_curve_type = "tank_curve",
        attack_template = "heavy_blunt_fencer",
        power_distribution = { attack = 0.2, impact = 0.2 },
    },
}

-- ============================================================
-- EXPLOSION TEMPLATES (wt-owned)
-- ============================================================
DEFS.explosions = {}

-- Scholar skull-shot AOE explosion
DEFS.explosions.overcharge_explosion_skull = {
    name = "overcharge_explosion_skull",
    aoe = {
        radius = 4,
        duration = 0.2,
        damage_interval = 0.2,
        damage_profile = "overcharge_explosion",
        create_nav_tag_volume = false,
        nav_tag_volume_layer = "fire_grenade",
        attack_template = "drakegun",
    },
    explosion = {
        radius = 4,
        radius_min = 1,
        radius_max = 4,
        max_damage_radius = 2,
        attack_template = "drakegun",
        damage_profile = "overcharge_explosion",
        sound_event_name = "fireball_explode",
        effect_name = "fx/scholar_skull_explosion",
        no_prop_damage = true,
        no_friendly_fire = true,
    },
}

-- ============================================================
-- BUFF TEMPLATES (wt-owned, registered via mod.add_buff_template)
-- ============================================================
DEFS.buffs = {}

DEFS.buffs.aoe_heavy_poison_dot = {
    name = "aoe_heavy_poison_dot",
    refresh_durations = true,
    max_stacks = 1,
    duration = 4,
    perks = { "ninja_poisoning" },
    dot_template_name = "heavy_poison",
}

DEFS.buffs.burning_dot_fire_grenade = {
    name = "burning_dot_fire_grenade",
    refresh_durations = true,
    max_stacks = 1,
    duration = 6,
    time_between_dot_damages = 1,
    perks = { "team_burn" },
    damage_type = "burninating",
}

DEFS.buffs.long_burn_low_damage = {
    name = "long_burn_low_damage",
    refresh_durations = true,
    max_stacks = 1,
    duration = 6,
    time_between_dot_damages = 1,
    damage_type = "burninating",
}

return DEFS
