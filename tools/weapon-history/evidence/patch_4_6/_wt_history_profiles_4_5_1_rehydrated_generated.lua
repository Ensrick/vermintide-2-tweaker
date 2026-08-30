-- Rehydrated from immutable source revisions; do not hand-edit.
return {
    new_revision = "b38754a3bd61983118215359845d5b4fe5005014",
    old_revision = "0cec9547152a395c4f35f75288f29d8b18b8294f",
    profiles = {
        shortbow_hagbane = {
            armor_modifier_far = {
                attack = {
                    [1] = 1,
                    [2] = 0,
                    [3] = 1,
                    [4] = 1,
                    [5] = 1,
                    [6] = 0,
                },
                impact = {
                    [1] = 1,
                    [2] = 0.10000000000000001,
                    [3] = 1,
                    [4] = 1,
                    [5] = 1,
                    [6] = 0,
                },
            },
            armor_modifier_near = {
                attack = {
                    [1] = 1,
                    [2] = 0,
                    [3] = 1,
                    [4] = 1,
                    [5] = 1,
                    [6] = 0,
                },
                impact = {
                    [1] = 1,
                    [2] = 0.29999999999999999,
                    [3] = 1,
                    [4] = 1,
                    [5] = 1,
                    [6] = 0,
                },
            },
            charge_value = "projectile",
            cleave_distribution = {
                attack = 0.050000000000000003,
                impact = 0.050000000000000003,
            },
            critical_strike = {
                attack_armor_power_modifer = {
                    [1] = 1,
                    [2] = 0.25,
                    [3] = 1.5,
                    [4] = 1,
                    [5] = 1.5,
                    [6] = 0.25,
                },
                impact_armor_power_modifer = {
                    [1] = 1,
                    [2] = 0.29999999999999999,
                    [3] = 1.5,
                    [4] = 1,
                    [5] = 1.5,
                    [6] = 0.25,
                },
            },
            default_target = {
                attack_template = "arrow_machinegun",
                boost_curve_coefficient = 0.5,
                boost_curve_type = "ninja_curve",
                dot_template_name = "arrow_poison_dot",
                power_distribution_far = {
                    attack = 0.074999999999999997,
                    impact = 0.10000000000000001,
                },
                power_distribution_near = {
                    attack = 0.10000000000000001,
                    impact = 0.14999999999999999,
                },
                range_dropoff_settings = {
                    dropoff_end = 30,
                    dropoff_start = 10,
                },
            },
            ignore_stagger_reduction = true,
            no_stagger_damage_reduction_ranged = true,
            require_damage_for_dot = true,
            targets = {},
        },
        shortbow_hagbane_charged = {
            armor_modifier_far = {
                attack = {
                    [1] = 1,
                    [2] = 0,
                    [3] = 1,
                    [4] = 1,
                    [5] = 1,
                    [6] = 0,
                },
                impact = {
                    [1] = 1,
                    [2] = 0.10000000000000001,
                    [3] = 1,
                    [4] = 1,
                    [5] = 1,
                    [6] = 0,
                },
            },
            armor_modifier_near = {
                attack = {
                    [1] = 1,
                    [2] = 0.20000000000000001,
                    [3] = 1.5,
                    [4] = 1,
                    [5] = 1.5,
                    [6] = 0,
                },
                impact = {
                    [1] = 1,
                    [2] = 1,
                    [3] = 1.5,
                    [4] = 1,
                    [5] = 1.5,
                    [6] = 0,
                },
            },
            charge_value = "projectile",
            cleave_distribution = {
                attack = 0.050000000000000003,
                impact = 0.050000000000000003,
            },
            critical_strike = {
                attack_armor_power_modifer = {
                    [1] = 1,
                    [2] = 0.25,
                    [3] = 1.5,
                    [4] = 1,
                    [5] = 1.5,
                    [6] = 0.25,
                },
                impact_armor_power_modifer = {
                    [1] = 1,
                    [2] = 0.29999999999999999,
                    [3] = 1.5,
                    [4] = 1,
                    [5] = 1.5,
                    [6] = 0.25,
                },
            },
            default_target = {
                attack_template = "arrow_machinegun",
                boost_curve_coefficient = 0.5,
                boost_curve_type = "ninja_curve",
                dot_template_name = "arrow_poison_dot",
                power_distribution_far = {
                    attack = 0.074999999999999997,
                    impact = 0.20000000000000001,
                },
                power_distribution_near = {
                    attack = 0.10000000000000001,
                    impact = 0.25,
                },
                range_dropoff_settings = {
                    dropoff_end = 30,
                    dropoff_start = 10,
                },
            },
            ignore_stagger_reduction = true,
            no_stagger_damage_reduction_ranged = true,
            require_damage_for_dot = true,
            targets = {},
        },
    },
}
