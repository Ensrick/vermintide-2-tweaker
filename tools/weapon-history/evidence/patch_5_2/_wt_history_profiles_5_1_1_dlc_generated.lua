-- Rehydrated from immutable source revisions; do not hand-edit.
return {
    new_revision = "038498af",
    old_revision = "8224b443",
    profile_sources = {
        geiser_magma = "scripts/settings/dlcs/morris/damage_profile_templates_dlc_morris.lua",
        heavy_javelin_smiter_stab_bleed = "scripts/settings/equipment/damage_profile_templates_dlc_woods.lua",
        medium_javelin_smiter_stab = "scripts/settings/equipment/damage_profile_templates_dlc_woods.lua",
        medium_javelin_smiter_stab_bleed = "scripts/settings/equipment/damage_profile_templates_dlc_woods.lua",
        staff_magma = "scripts/settings/dlcs/morris/damage_profile_templates_dlc_morris.lua",
        thrown_javelin = "scripts/settings/equipment/damage_profile_templates_dlc_woods.lua",
    },
    profiles = {
        geiser_magma = {
            armor_modifier = {
                attack = {
                    [1] = 1,
                    [2] = 0.5,
                    [3] = 1,
                    [4] = 1,
                    [5] = 1,
                    [6] = 0,
                },
                impact = {
                    [1] = 1,
                    [2] = 1.5,
                    [3] = 1,
                    [4] = 1,
                    [5] = 1,
                    [6] = 0.5,
                },
            },
            attack_template = "wizard_staff_geiser_magma",
            charge_value = "aoe",
            cleave_distribution = {
                attack = 0.20000000000000001,
                impact = 0.20000000000000001,
            },
            critical_strike = {
                attack_armor_power_modifer = {
                    [1] = 1,
                    [2] = 0.5,
                    [3] = 1,
                    [4] = 1,
                    [5] = 1,
                    [6] = 0.25,
                },
                impact_armor_power_modifer = {
                    [1] = 1,
                    [2] = 1.5,
                    [3] = 1,
                    [4] = 1,
                    [5] = 1,
                    [6] = 0.5,
                },
            },
            default_target = {
                attack_template = "wizard_staff_geiser_magma",
                boost_curve_coefficient = 1,
                boost_curve_type = "ninja_curve",
                power_distribution = {
                    attack = 0.050000000000000003,
                    impact = 0.17499999999999999,
                },
            },
            dot_balefire_variant = true,
            dot_template_name = "burning_magma_dot",
            no_stagger = true,
            no_stagger_damage_reduction_ranged = true,
            target_radius = {
                [1] = 0.29999999999999999,
                [2] = 0.80000000000000004,
            },
            targets = {
                [1] = {
                    attack_template = "wizard_staff_geiser_magma",
                    boost_curve_coefficient = 1,
                    boost_curve_type = "ninja_curve",
                    power_distribution = {
                        attack = 0.29999999999999999,
                        impact = 0.69999999999999996,
                    },
                },
                [2] = {
                    attack_template = "wizard_staff_geiser_magma",
                    boost_curve_coefficient = 1,
                    boost_curve_type = "ninja_curve",
                    power_distribution = {
                        attack = 0.125,
                        impact = 0.34999999999999998,
                    },
                },
            },
        },
        heavy_javelin_smiter_stab_bleed = {
            armor_modifier = {
                attack = {
                    [1] = 1,
                    [2] = 0.29999999999999999,
                    [3] = 2,
                    [4] = 1,
                    [5] = 0.75,
                },
                impact = {
                    [1] = 1,
                    [2] = 0.5,
                    [3] = 1,
                    [4] = 1,
                    [5] = 0.75,
                },
            },
            charge_value = "heavy_attack",
            cleave_distribution = {
                attack = 0.074999999999999997,
                impact = 0.074999999999999997,
            },
            critical_strike = {
                attack_armor_power_modifer = {
                    [1] = 1,
                    [2] = 0.5,
                    [3] = 2.2999999999999998,
                    [4] = 1,
                    [5] = 1,
                },
                impact_armor_power_modifer = {
                    [1] = 1,
                    [2] = 1,
                    [3] = 1,
                    [4] = 1,
                    [5] = 1,
                },
            },
            default_target = {
                attack_template = "heavy_stab_smiter",
                boost_curve_coefficient = 0.75,
                boost_curve_coefficient_headshot = 1,
                boost_curve_type = "ninja_curve",
                power_distribution = {
                    attack = 0.20000000000000001,
                    impact = 0.14999999999999999,
                },
            },
            targets = {
                [1] = {
                    armor_modifier = {
                        attack = {
                            [1] = 1,
                            [2] = 0.45000000000000001,
                            [3] = 2,
                            [4] = 1,
                            [5] = 0.75,
                        },
                        impact = {
                            [1] = 1,
                            [2] = 0.65000000000000002,
                            [3] = 1,
                            [4] = 1,
                            [5] = 0.75,
                        },
                    },
                    attack_template = "heavy_stab_smiter",
                    boost_curve_coefficient = 0.75,
                    boost_curve_coefficient_headshot = 2,
                    boost_curve_type = "ninja_curve",
                    power_distribution = {
                        attack = 0.45000000000000001,
                        impact = 0.25,
                    },
                },
            },
        },
        medium_javelin_smiter_stab = {
            armor_modifier = {
                attack = {
                    [1] = 1,
                    [2] = 0.25,
                    [3] = 2.25,
                    [4] = 1,
                    [5] = 0.75,
                },
                impact = {
                    [1] = 1,
                    [2] = 0.75,
                    [3] = 1,
                    [4] = 1,
                    [5] = 0.75,
                },
            },
            charge_value = "light_attack",
            cleave_distribution = {
                attack = 0.074999999999999997,
                impact = 0.074999999999999997,
            },
            critical_strike = {
                attack_armor_power_modifer = {
                    [1] = 1,
                    [2] = 0.40000000000000002,
                    [3] = 2.2999999999999998,
                    [4] = 1,
                    [5] = 1,
                },
                impact_armor_power_modifer = {
                    [1] = 1,
                    [2] = 1,
                    [3] = 1,
                    [4] = 1,
                    [5] = 1,
                },
            },
            default_target = {
                attack_template = "stab_smiter",
                boost_curve_coefficient = 1,
                boost_curve_coefficient_headshot = 2.5,
                boost_curve_type = "ninja_curve",
                power_distribution = {
                    attack = 0.25,
                    impact = 0.125,
                },
            },
        },
        medium_javelin_smiter_stab_bleed = {
            armor_modifier = {
                attack = {
                    [1] = 1,
                    [2] = 0.25,
                    [3] = 2.25,
                    [4] = 1,
                    [5] = 0.75,
                },
                impact = {
                    [1] = 1,
                    [2] = 0.75,
                    [3] = 1,
                    [4] = 1,
                    [5] = 0.75,
                },
            },
            charge_value = "light_attack",
            cleave_distribution = {
                attack = 0.074999999999999997,
                impact = 0.074999999999999997,
            },
            critical_strike = {
                attack_armor_power_modifer = {
                    [1] = 1,
                    [2] = 0.40000000000000002,
                    [3] = 2.2999999999999998,
                    [4] = 1,
                    [5] = 1,
                },
                impact_armor_power_modifer = {
                    [1] = 1,
                    [2] = 1,
                    [3] = 1,
                    [4] = 1,
                    [5] = 1,
                },
            },
            default_target = {
                attack_template = "stab_smiter",
                boost_curve_coefficient = 1,
                boost_curve_coefficient_headshot = 2.5,
                boost_curve_type = "ninja_curve",
                dot_template_name = "weapon_bleed_dot_javelin",
                power_distribution = {
                    attack = 0.25,
                    impact = 0.125,
                },
            },
        },
        staff_magma = {
            armor_modifier_far = {
                attack = {
                    [1] = 1,
                    [2] = 0,
                    [3] = 0.25,
                    [4] = 0.75,
                    [5] = 1,
                    [6] = 0,
                },
                impact = {
                    [1] = 1,
                    [2] = 0.5,
                    [3] = 0.5,
                    [4] = 0,
                    [5] = 1,
                    [6] = 0.5,
                },
            },
            armor_modifier_near = {
                attack = {
                    [1] = 1,
                    [2] = 0.20000000000000001,
                    [3] = 0.40000000000000002,
                    [4] = 0.75,
                    [5] = 1,
                    [6] = 0,
                },
                impact = {
                    [1] = 1,
                    [2] = 0.75,
                    [3] = 3,
                    [4] = 0,
                    [5] = 1,
                    [6] = 0.75,
                },
            },
            charge_value = "instant_projectile",
            cleave_distribution = {
                attack = 0.10000000000000001,
                impact = 0.10000000000000001,
            },
            critical_strike = {
                attack_armor_power_modifer = {
                    [1] = 1,
                    [2] = 0.29999999999999999,
                    [3] = 0.5,
                    [4] = 1,
                    [5] = 1,
                    [6] = 0,
                },
                impact_armor_power_modifer = {
                    [1] = 1,
                    [2] = 1,
                    [3] = 1,
                    [4] = 1,
                    [5] = 1,
                    [6] = 0.5,
                },
            },
            default_target = {
                attack_template = "staff_magma",
                boost_curve_coefficient = 0.75,
                boost_curve_coefficient_headshot = 0.75,
                boost_curve_type = "linesman_curve",
                power_distribution_far = {
                    attack = 0.10000000000000001,
                    impact = 0.10000000000000001,
                },
                power_distribution_near = {
                    attack = 0.20000000000000001,
                    impact = 0.25,
                },
                range_modifier_settings = {
                    dropoff_end = 15,
                    dropoff_start = 8,
                },
            },
            no_stagger_damage_reduction_ranged = true,
            shield_break = true,
        },
        thrown_javelin = {
            armor_modifier_far = {
                attack = {
                    [1] = 1,
                    [2] = 0.69999999999999996,
                    [3] = 1.1000000000000001,
                    [4] = 1,
                    [5] = 0.75,
                    [6] = 0.25,
                },
                impact = {
                    [1] = 1,
                    [2] = 1,
                    [3] = 1,
                    [4] = 1,
                    [5] = 1,
                    [6] = 0.5,
                },
            },
            armor_modifier_near = {
                attack = {
                    [1] = 1,
                    [2] = 0.69999999999999996,
                    [3] = 1.1000000000000001,
                    [4] = 1,
                    [5] = 0.75,
                    [6] = 0.25,
                },
                impact = {
                    [1] = 1,
                    [2] = 1,
                    [3] = 1,
                    [4] = 1,
                    [5] = 1,
                    [6] = 0.75,
                },
            },
            charge_value = "projectile",
            cleave_distribution = {
                attack = 0.80000000000000004,
                impact = 0.80000000000000004,
            },
            critical_strike = {
                attack_armor_power_modifer = {
                    [1] = 1,
                    [2] = 1,
                    [3] = 1.3,
                    [4] = 1,
                    [5] = 0.75,
                    [6] = 0.5,
                },
                impact_armor_power_modifer = {
                    [1] = 1,
                    [2] = 1,
                    [3] = 1,
                    [4] = 1,
                    [5] = 1,
                    [6] = 0.75,
                },
            },
            default_target = {
                attack_template = "projectile_javelin",
                boost_curve_coefficient = 1,
                boost_curve_coefficient_headshot = 1.6000000000000001,
                boost_curve_type = "smiter_curve",
                power_distribution_far = {
                    attack = 0.80000000000000004,
                    impact = 0.84999999999999998,
                },
                power_distribution_near = {
                    attack = 0.80000000000000004,
                    impact = 0.84999999999999998,
                },
                range_modifier_settings = { ref = "sniper_dropoff_ranges" },
            },
            no_stagger_damage_reduction_ranged = true,
            shield_break = true,
        },
    },
}
