-- Rehydrated from immutable source revisions; do not hand-edit.
return {
    new_revision = "c5e4968b",
    old_revision = "4f496970",
    profiles = {
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
                    [3] = 2.1000000000000001,
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
            melee_boost_override = 4,
            name = "light_slashing_smiter_stab_dual",
            targets = {
                [1] = {
                    armor_modifier = {
                        attack = {
                            [1] = 1,
                            [2] = 0.80000000000000004,
                            [3] = 2.1000000000000001,
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
        medium_slashing_tank_1h_finesse = {
            armor_modifier = {
                attack = {
                    [1] = 1,
                    [2] = 0.34999999999999998,
                    [3] = 1,
                    [4] = 1,
                    [5] = 0.75,
                },
                impact = {
                    [1] = 1,
                    [2] = 1,
                    [3] = 0.5,
                    [4] = 1,
                    [5] = 0.75,
                },
            },
            charge_value = "heavy_attack",
            cleave_distribution = {
                attack = 0.29999999999999999,
                impact = 0.80000000000000004,
            },
            critical_strike = {
                attack_armor_power_modifer = {
                    [1] = 1,
                    [2] = 0.5,
                    [3] = 1,
                    [4] = 1,
                    [5] = 1,
                },
                impact_armor_power_modifer = {
                    [1] = 1,
                    [2] = 1,
                    [3] = 0.5,
                    [4] = 1,
                    [5] = 1,
                },
            },
            default_target = {
                attack_template = "light_slashing_tank",
                boost_curve_type = "tank_curve",
                power_distribution = {
                    attack = 0.050000000000000003,
                    impact = 0.050000000000000003,
                },
            },
            name = "medium_slashing_tank_1h_finesse",
            stagger_duration_modifier = 1.5,
            targets = {
                [1] = {
                    armor_modifier = {
                        attack = {
                            [1] = 1,
                            [2] = 0.59999999999999998,
                            [3] = 1,
                            [4] = 1,
                            [5] = 0.75,
                        },
                        impact = {
                            [1] = 1,
                            [2] = 1,
                            [3] = 0.5,
                            [4] = 1,
                            [5] = 0.75,
                        },
                    },
                    attack_template = "blunt_tank",
                    boost_curve_coefficient_headshot = 2,
                    boost_curve_type = "tank_curve",
                    power_distribution = {
                        attack = 0.32000000000000001,
                        impact = 0.20000000000000001,
                    },
                },
                [2] = {
                    attack_template = "blunt_tank",
                    boost_curve_coefficient_headshot = 2,
                    boost_curve_type = "tank_curve",
                    power_distribution = {
                        attack = 0.17999999999999999,
                        impact = 0.17999999999999999,
                    },
                },
                [3] = {
                    attack_template = "light_blunt_tank",
                    boost_curve_type = "tank_curve",
                    power_distribution = {
                        attack = 0.14999999999999999,
                        impact = 0.14999999999999999,
                    },
                },
            },
        },
    },
}
