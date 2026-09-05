-- Generated from decompiled source revisions; do not hand-edit.
local sets = {
	{
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
				attack = 0.2,
				impact = 0.2,
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
					attack = 0.05,
					impact = 0.175,
				},
			},
			dot_balefire_variant = true,
			dot_template_name = "burning_magma_dot",
			no_stagger = true,
			no_stagger_damage_reduction_ranged = true,
			target_radius = {
				[1] = 0.3,
				[2] = 0.8,
			},
			targets = {
				[1] = {
					attack_template = "wizard_staff_geiser_magma",
					boost_curve_coefficient = 1,
					boost_curve_type = "ninja_curve",
					power_distribution = {
						attack = 0.3,
						impact = 0.7,
					},
				},
				[2] = {
					attack_template = "wizard_staff_geiser_magma",
					boost_curve_coefficient = 1,
					boost_curve_type = "ninja_curve",
					power_distribution = {
						attack = 0.125,
						impact = 0.35,
					},
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
					[2] = 0.2,
					[3] = 0.4,
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
				attack = 0.1,
				impact = 0.1,
			},
			critical_strike = {
				attack_armor_power_modifer = {
					[1] = 1,
					[2] = 0.3,
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
					attack = 0.1,
					impact = 0.1,
				},
				power_distribution_near = {
					attack = 0.2,
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
	},
	{
		heavy_javelin_smiter_stab_bleed = {
			armor_modifier = {
				attack = {
					[1] = 1,
					[2] = 0.3,
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
				attack = 0.075,
				impact = 0.075,
			},
			critical_strike = {
				attack_armor_power_modifer = {
					[1] = 1,
					[2] = 0.5,
					[3] = 2.3,
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
					attack = 0.2,
					impact = 0.15,
				},
			},
			targets = {
				[1] = {
					armor_modifier = {
						attack = {
							[1] = 1,
							[2] = 0.45,
							[3] = 2,
							[4] = 1,
							[5] = 0.75,
						},
						impact = {
							[1] = 1,
							[2] = 0.65,
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
						attack = 0.45,
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
				attack = 0.075,
				impact = 0.075,
			},
			critical_strike = {
				attack_armor_power_modifer = {
					[1] = 1,
					[2] = 0.4,
					[3] = 2.3,
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
				attack = 0.075,
				impact = 0.075,
			},
			critical_strike = {
				attack_armor_power_modifer = {
					[1] = 1,
					[2] = 0.4,
					[3] = 2.3,
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
		thrown_javelin = {
			armor_modifier_far = {
				attack = {
					[1] = 1,
					[2] = 0.7,
					[3] = 1.1,
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
					[2] = 0.7,
					[3] = 1.1,
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
				attack = 0.8,
				impact = 0.8,
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
				boost_curve_coefficient_headshot = 1.6,
				boost_curve_type = "smiter_curve",
				power_distribution_far = {
					attack = 0.8,
					impact = 0.85,
				},
				power_distribution_near = {
					attack = 0.8,
					impact = 0.85,
				},
				range_modifier_settings = { ref = "sniper_dropoff_ranges" },
			},
			no_stagger_damage_reduction_ranged = true,
			shield_break = true,
		},
	},
}
local profiles = {}

for _, source_profiles in ipairs(sets) do
	for name, profile in pairs(source_profiles) do
		profiles[name] = profile
	end
end

return {
	new_revision = "c5e4968b",
	old_revision = "8224b443",
	profile_sources = {
		geiser_magma = "scripts/settings/dlcs/morris/damage_profile_templates_dlc_morris.lua",
		heavy_javelin_smiter_stab_bleed = "scripts/settings/equipment/damage_profile_templates_dlc_woods.lua",
		medium_javelin_smiter_stab = "scripts/settings/equipment/damage_profile_templates_dlc_woods.lua",
		medium_javelin_smiter_stab_bleed = "scripts/settings/equipment/damage_profile_templates_dlc_woods.lua",
		staff_magma = "scripts/settings/dlcs/morris/damage_profile_templates_dlc_morris.lua",
		thrown_javelin = "scripts/settings/equipment/damage_profile_templates_dlc_woods.lua",
	},
	profiles = profiles,
}
