-- Generated from decompiled source revisions; do not hand-edit.
return {
    new_revision = "67d593c4f98653e1d511105b6adeebb5d6619c58",
    old_revision = "90c7c21adb7aa2b7de5fcdca5094727895fbeb1a",
    profiles = {
        light_slashing_linesman_dual_medium = {
            armor_modifier = {
                attack = {
                    [1] = 1,
                    [2] = 0.25,
                    [3] = 2,
                    [4] = 1,
                    [5] = 1,
                },
                impact = {
                    [1] = 1,
                    [2] = 0.25,
                    [3] = 0.5,
                    [4] = 1,
                    [5] = 1,
                },
            },
            charge_value = "heavy_attack",
            cleave_distribution = {
                attack = 0.25,
                impact = 0.20000000000000001,
            },
            critical_strike = {
                attack_armor_power_modifer = {
                    [1] = 1,
                    [2] = 0.5,
                    [3] = 2.5,
                    [4] = 1,
                    [5] = 1,
                },
                impact_armor_power_modifer = {
                    [1] = 1,
                    [2] = 0.75,
                    [3] = 0.5,
                    [4] = 1,
                    [5] = 1,
                },
            },
            default_target = {
                attack_template = "light_slashing_linesman",
                boost_curve_type = "linesman_curve",
                power_distribution = {
                    attack = 0.074999999999999997,
                    impact = 0.050000000000000003,
                },
            },
            melee_boost_override = 4,
            targets = {
                [1] = {
                    armor_modifier = {
                        attack = {
                            [1] = 1,
                            [2] = 0.40000000000000002,
                            [3] = 2,
                            [4] = 1,
                            [5] = 1,
                        },
                        impact = {
                            [1] = 1,
                            [2] = 0.5,
                            [3] = 0.5,
                            [4] = 1,
                            [5] = 1,
                        },
                    },
                    attack_template = "light_slashing_linesman_hs",
                    boost_curve_coefficient_headshot = 2,
                    boost_curve_type = "ninja_curve",
                    power_distribution = {
                        attack = 0.14999999999999999,
                        impact = 0.125,
                    },
                },
                [2] = {
                    attack_template = "light_slashing_linesman",
                    boost_curve_coefficient_headshot = 1,
                    boost_curve_type = "linesman_curve",
                    power_distribution = {
                        attack = 0.125,
                        impact = 0.074999999999999997,
                    },
                },
            },
        },
        light_slashing_smiter_stab_dual = {
            armor_modifier = {
                attack = {
                    [1] = 1,
                    [2] = 0.75,
                    [3] = 2.25,
                    [4] = 1,
                    [5] = 0.75,
                },
                impact = {
                    [1] = 1,
                    [2] = 1,
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
                    [2] = 1,
                    [3] = 2.5,
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
                boost_curve_coefficient = 0.75,
                boost_curve_coefficient_headshot = 2,
                boost_curve_type = "smiter_curve",
                power_distribution = {
                    attack = 0.10000000000000001,
                    impact = 0.074999999999999997,
                },
            },
            melee_boost_override = 3.5,
            targets = {
                [1] = {
                    armor_modifier = {
                        attack = {
                            [1] = 1,
                            [2] = 0.80000000000000004,
                            [3] = 2.5,
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
                    attack_template = "stab_smiter",
                    boost_curve_coefficient = 1.5,
                    boost_curve_coefficient_headshot = 2,
                    boost_curve_type = "smiter_curve",
                    power_distribution = {
                        attack = 0.23999999999999999,
                        impact = 0.10000000000000001,
                    },
                },
            },
        },
    },
}
