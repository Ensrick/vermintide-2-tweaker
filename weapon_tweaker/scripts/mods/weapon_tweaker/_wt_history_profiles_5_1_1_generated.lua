-- Filtered from a source-qualified generated profile snapshot.
return {
	new_revision = "c5e4968b",
	old_revision = "8224b443",
	profiles = {
		heavy_slashing_linesman = {
			armor_modifier = {
				attack = {
					[1] = 1,
					[2] = 0.3,
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
				impact = 0.4,
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
					attack = 0.075,
					impact = 0.05,
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
						attack = 0.45,
						impact = 0.275,
					},
				},
				[2] = {
					attack_template = "heavy_slashing_linesman",
					boost_curve_coefficient_headshot = 1,
					boost_curve_type = "linesman_curve",
					power_distribution = {
						attack = 0.25,
						impact = 0.15,
					},
				},
				[3] = {
					attack_template = "slashing_linesman",
					boost_curve_type = "linesman_curve",
					power_distribution = {
						attack = 0.15,
						impact = 0.1,
					},
				},
				[4] = {
					attack_template = "slashing_linesman",
					boost_curve_type = "linesman_curve",
					power_distribution = {
						attack = 0.125,
						impact = 0.075,
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
					[2] = 0.3,
					[3] = 0.5,
					[4] = 1,
					[5] = 1,
				},
			},
			charge_value = "light_attack",
			cleave_distribution = {
				attack = 0.35,
				impact = 0.2,
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
					attack = 0.075,
					impact = 0.05,
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
						attack = 0.175,
						impact = 0.1,
					},
				},
				[2] = {
					attack_template = "light_slashing_linesman",
					boost_curve_coefficient_headshot = 2,
					boost_curve_type = "linesman_curve",
					power_distribution = {
						attack = 0.125,
						impact = 0.075,
					},
				},
			},
		},
		medium_slashing_smiter_1h_axe = {
			armor_modifier = {
				attack = {
					[1] = 1,
					[2] = 0.8,
					[3] = 2,
					[4] = 1,
					[5] = 0.75,
					[6] = 1,
				},
				impact = {
					[1] = 1,
					[2] = 0.8,
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
					[2] = 0.8,
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
					attack = 0.4,
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
						attack = 0.1,
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
						attack = 0.3,
						impact = 0.2,
					},
				},
				[2] = {
					attack_template = "blunt_tank",
					boost_curve_coefficient_headshot = 2,
					boost_curve_type = "tank_curve",
					power_distribution = {
						attack = 0.1,
						impact = 0.15,
					},
				},
				[3] = {
					attack_template = "light_blunt_tank",
					boost_curve_type = "tank_curve",
					power_distribution = {
						attack = 0.075,
						impact = 0.1,
					},
				},
			},
		},
	},
}
