-- Generated from immutable decompiled source revisions; do not hand-edit.
return {
	new_revision = "c5e4968b1fbb00c49884e56d640ef990a9c04dd0",
	old_revision = "c96aa3858011ecd557d55d80b66fe3bb8342eeb2",
	profile_sources = {throwing_axe_charged = "scripts/settings/equipment/damage_profile_templates.lua", },
	profiles = {
		throwing_axe_charged = {
			armor_modifier_far = {attack = {1, 0.6, 1, 1, 0.75, 0.25, }, impact = {1, 1, 1, 1, 1, 0.5, }, },
			armor_modifier_near = {attack = {1, 0.8, 1, 1, 0.75, 0.25, }, impact = {1, 1, 1, 1, 1, 0.75, }, },
			charge_value = "projectile",
			cleave_distribution = {attack = 0.4, impact = 0.4, },
			critical_strike = {attack_armor_power_modifer = {1, 1, 1, 1, 0.75, 0.5, }, impact_armor_power_modifer = {1, 1, 1, 1, 1, 0.75, }, },
			default_target = {
				attack_template = "throwing_axe",
				boost_curve_coefficient = 1,
				boost_curve_coefficient_headshot = 1,
				boost_curve_type = "smiter_curve",
				power_distribution_far = {attack = 0.5, impact = 0.75, },
				power_distribution_near = {attack = 0.8, impact = 0.85, },
				range_dropoff_settings = {dropoff_end = 30, dropoff_start = 15, },
			},
			no_stagger_damage_reduction_ranged = true,
			shield_break = true,
			targets = { },
		},
	},
}
