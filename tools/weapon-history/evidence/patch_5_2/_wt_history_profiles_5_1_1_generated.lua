-- Rehydrated from immutable source revisions; do not hand-edit.
return {
    new_revision = "25fd7b84",
    old_revision = "8224b443",
    profiles = {
        heavy_slashing_linesman = {
            armor_modifier = {
                attack = {
                    [1] = 1,
                    [2] = 0.29999999999999999,
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
            charge_value = "heavy_attack",
            cleave_distribution = {
                attack = 0.75,
                impact = 0.40000000000000002,
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
                    [2] = 0.5,
                    [3] = 0.5,
                    [4] = 1,
                    [5] = 1,
                },
            },
            default_target = {
                attack_template = "light_slashing_linesman",
                boost_curve_coefficient_headshot = 0.25,
                boost_curve_type = "linesman_curve",
                power_distribution = {
                    attack = 0.074999999999999997,
                    impact = 0.050000000000000003,
                },
            },
            name = "heavy_slashing_linesman",
            targets = {
                [1] = {
                    attack_template = "heavy_slashing_linesman",
                    boost_curve_coefficient = 2,
                    boost_curve_coefficient_headshot = 1,
                    boost_curve_type = "linesman_curve",
                    power_distribution = {
                        attack = 0.45000000000000001,
                        impact = 0.27500000000000002,
                    },
                },
                [2] = {
                    attack_template = "heavy_slashing_linesman",
                    boost_curve_coefficient_headshot = 1,
                    boost_curve_type = "linesman_curve",
                    power_distribution = {
                        attack = 0.25,
                        impact = 0.14999999999999999,
                    },
                },
                [3] = {
                    attack_template = "slashing_linesman",
                    boost_curve_type = "linesman_curve",
                    power_distribution = {
                        attack = 0.14999999999999999,
                        impact = 0.10000000000000001,
                    },
                },
                [4] = {
                    attack_template = "slashing_linesman",
                    boost_curve_type = "linesman_curve",
                    power_distribution = {
                        attack = 0.125,
                        impact = 0.074999999999999997,
                    },
                },
            },
        },
        light_slashing_linesman_finesse = {
            armor_modifier = {
                attack = {
                    [1] = 1,
                    [2] = 0,
                    [3] = 2,
                    [4] = 1,
                    [5] = 1,
                },
                impact = {
                    [1] = 1,
                    [2] = 0.29999999999999999,
                    [3] = 0.5,
                    [4] = 1,
                    [5] = 1,
                },
            },
            charge_value = "light_attack",
            cleave_distribution = {
                attack = 0.34999999999999998,
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
                    [2] = 0.5,
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
            name = "light_slashing_linesman_finesse",
            targets = {
                [1] = {
                    attack_template = "light_slashing_linesman_hs",
                    boost_curve_coefficient = 2,
                    boost_curve_coefficient_headshot = 2,
                    boost_curve_type = "linesman_curve",
                    power_distribution = {
                        attack = 0.17499999999999999,
                        impact = 0.10000000000000001,
                    },
                },
                [2] = {
                    attack_template = "light_slashing_linesman",
                    boost_curve_coefficient_headshot = 2,
                    boost_curve_type = "linesman_curve",
                    power_distribution = {
                        attack = 0.125,
                        impact = 0.074999999999999997,
                    },
                },
            },
        },
        medium_slashing_smiter_1h_axe = {
            armor_modifier = {
                attack = {
                    [1] = 1,
                    [2] = 0.80000000000000004,
                    [3] = 2,
                    [4] = 1,
                    [5] = 0.75,
                    [6] = 1,
                },
                impact = {
                    [1] = 1,
                    [2] = 0.80000000000000004,
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
                    [2] = 0.80000000000000004,
                    [3] = 2.5,
                    [4] = 1,
                    [5] = 1,
                    [6] = 1,
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
                attack_template = "slashing_smiter",
                boost_curve_coefficient = 2,
                boost_curve_type = "smiter_curve",
                power_distribution = {
                    attack = 0.40000000000000002,
                    impact = 0.25,
                },
            },
            name = "medium_slashing_smiter_1h_axe",
            shield_break = true,
            targets = {
                [2] = {
                    attack_template = "light_blunt_tank",
                    boost_curve_type = "tank_curve",
                    power_distribution = {
                        attack = 0.10000000000000001,
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
                            [2] = 0.5,
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
                        attack = 0.29999999999999999,
                        impact = 0.20000000000000001,
                    },
                },
                [2] = {
                    attack_template = "blunt_tank",
                    boost_curve_coefficient_headshot = 2,
                    boost_curve_type = "tank_curve",
                    power_distribution = {
                        attack = 0.10000000000000001,
                        impact = 0.14999999999999999,
                    },
                },
                [3] = {
                    attack_template = "light_blunt_tank",
                    boost_curve_type = "tank_curve",
                    power_distribution = {
                        attack = 0.074999999999999997,
                        impact = 0.10000000000000001,
                    },
                },
            },
        },
    },
}
