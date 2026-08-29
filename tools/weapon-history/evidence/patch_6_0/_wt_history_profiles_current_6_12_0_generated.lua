-- Rehydrated from immutable source revisions; do not hand-edit.
return {
    new_revision = "da0bbdaf6af1ca7e8c96e7892a3416a4aa8a7f87",
    old_revision = "f64ecd2495bd26b1b0a4d296970bef0a0d7a06a9",
    profiles = {
        staff_fireball_charged = {
            armor_modifier = {
                attack = {
                    [1] = 1,
                    [2] = 1,
                    [3] = 4,
                    [4] = 1,
                    [5] = 1,
                    [6] = 0,
                },
                impact = {
                    [1] = 1,
                    [2] = 0.5,
                    [3] = 1,
                    [4] = 1,
                    [5] = 1,
                    [6] = 0,
                },
            },
            charge_value = "projectile",
            cleave_distribution = {
                attack = 1,
                impact = 1,
            },
            critical_strike = {
                attack_armor_power_modifer = {
                    [1] = 1,
                    [2] = 1,
                    [3] = 4,
                    [4] = 1,
                    [5] = 1,
                    [6] = 0.25,
                },
                impact_armor_power_modifer = {
                    [1] = 1,
                    [2] = 0.80000000000000004,
                    [3] = 1,
                    [4] = 1,
                    [5] = 1,
                    [6] = 0.25,
                },
            },
            default_target = {
                attack_template = "fireball",
                boost_curve_coefficient = 1,
                boost_curve_type = "ninja_curve",
                dot_balefire_variant = true,
                dot_template_name = "burning_dot_1tick",
                power_distribution_far = {
                    attack = 0.29999999999999999,
                    impact = 0.25,
                },
                power_distribution_near = {
                    attack = 0.29999999999999999,
                    impact = 0.5,
                },
                range_modifier_settings = {
                    dropoff_end = 15,
                    dropoff_start = 8,
                },
            },
            name = "staff_fireball_charged",
            no_stagger_damage_reduction_ranged = true,
            targets = {},
        },
    },
}
