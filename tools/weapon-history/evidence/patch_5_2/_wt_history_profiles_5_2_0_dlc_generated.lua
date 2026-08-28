-- Rehydrated from immutable source revisions; do not hand-edit.
return {
    new_revision = "c5e4968b",
    old_revision = "4f496970",
    profile_sources = {
        shot_sniper_pistol = "scripts/settings/equipment/damage_profile_templates_dlc_cog.lua",
    },
    profiles = {
        shot_sniper_pistol = {
            armor_modifier_far = {
                attack = {
                    [1] = 1,
                    [2] = 1,
                    [3] = 1,
                    [4] = 1,
                    [5] = 0.75,
                    [6] = 0,
                },
                impact = {
                    [1] = 1,
                    [2] = 1,
                    [3] = 1,
                    [4] = 1,
                    [5] = 1,
                    [6] = 0,
                },
            },
            armor_modifier_near = {
                attack = {
                    [1] = 1,
                    [2] = 1.2,
                    [3] = 1.5,
                    [4] = 1,
                    [5] = 0.75,
                    [6] = 0,
                },
                impact = {
                    [1] = 1,
                    [2] = 1,
                    [3] = 1,
                    [4] = 1,
                    [5] = 1,
                    [6] = 0,
                },
            },
            charge_value = "instant_projectile",
            cleave_distribution = {
                attack = 0.29999999999999999,
                impact = 0.29999999999999999,
            },
            critical_strike = {
                attack_armor_power_modifer = {
                    [1] = 1,
                    [2] = 1.3999999999999999,
                    [3] = 1.5,
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
                    [6] = 1,
                },
            },
            default_target = {
                attack_template = "shot_sniper",
                boost_curve_coefficient = 1,
                boost_curve_coefficient_headshot = 1,
                boost_curve_type = "smiter_curve",
                headshot_boost_boss = 0.5,
                power_distribution_far = {
                    attack = 0.5,
                    impact = 0.5,
                },
                power_distribution_near = {
                    attack = 1,
                    impact = 0.5,
                },
                range_modifier_settings = {
                    dropoff_end = 15,
                    dropoff_start = 8,
                },
            },
            no_stagger_damage_reduction_ranged = true,
            shield_break = true,
        },
    },
}
