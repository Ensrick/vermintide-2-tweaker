-- Filtered from a source-qualified generated profile snapshot.
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
				attack = 0.075,
				impact = 0.075,
			},
			critical_strike = {
				attack_armor_power_modifer = {
					[1] = 1,
					[2] = 1,
					[3] = 2.1,
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
					attack = 0.1,
					impact = 0.075,
				},
			},
			melee_boost_override = 4,
			name = "light_slashing_smiter_stab_dual",
			targets = {
				[1] = {
					armor_modifier = {
						attack = {
							[1] = 1,
							[2] = 0.8,
							[3] = 2.1,
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
						attack = 0.24,
						impact = 0.1,
					},
				},
			},
		},
		medium_slashing_tank_1h_finesse = {
			armor_modifier = {
				attack = {
					[1] = 1,
					[2] = 0.35,
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
				attack = 0.3,
				impact = 0.8,
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
					attack = 0.05,
					impact = 0.05,
				},
			},
			name = "medium_slashing_tank_1h_finesse",
			stagger_duration_modifier = 1.5,
			targets = {
				[1] = {
					armor_modifier = {
						attack = {
							[1] = 1,
							[2] = 0.6,
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
						attack = 0.32,
						impact = 0.2,
					},
				},
				[2] = {
					attack_template = "blunt_tank",
					boost_curve_coefficient_headshot = 2,
					boost_curve_type = "tank_curve",
					power_distribution = {
						attack = 0.18,
						impact = 0.18,
					},
				},
				[3] = {
					attack_template = "light_blunt_tank",
					boost_curve_type = "tank_curve",
					power_distribution = {
						attack = 0.15,
						impact = 0.15,
					},
				},
			},
		},
	},
}
