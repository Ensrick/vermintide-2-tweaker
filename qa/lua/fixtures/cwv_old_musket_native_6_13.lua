-- AUTO-GENERATED exact native fixture -- DO NOT HAND-EDIT. See adjacent provenance JSON.
-- Exact portable source-qualified Old Musket inputs, game6.13 / 93dea911a4cc464a0eb51cfdc3a443297bfc4550.
-- Resolved four donors captured through native raw definitions + exact PowerLevel resolution.
-- This data/code fixture is never bundled or executed by a game mod.
return {
handguns = [====[
-- chunkname: @scripts/settings/equipment/weapon_templates/handguns.lua

local weapon_template = {}

weapon_template.actions = {
	action_wield = ActionTemplates.wield,
	action_one = {
		default = {
			active_reload_time = 0.35,
			aim_assist_max_ramp_multiplier = 1,
			aim_assist_ramp_decay_delay = 0.1,
			aim_assist_ramp_multiplier = 0.3,
			alert_sound_range_fire = 10,
			alert_sound_range_hit = 2,
			ammo_usage = 1,
			anim_event = "attack_shoot",
			anim_event_last_ammo = "attack_shoot_last",
			anim_event_no_ammo_left = "attack_shoot_last",
			anim_event_secondary = "reload",
			apply_recoil = true,
			charge_value = "light_attack",
			damage_profile = "shot_sniper",
			damage_window_end = 0,
			damage_window_start = 0.1,
			fire_time = 0,
			headshot_multiplier = 2,
			hit_effect = "bullet_impact",
			ignore_shield_hit = true,
			kind = "handgun",
			ranged_attack = true,
			reload_when_out_of_ammo = true,
			total_time = 0.5,
			total_time_secondary = 2,
			allowed_chain_actions = {
				{
					action = "action_wield",
					input = "action_wield",
					start_time = 0.66,
					sub_action = "default",
				},
				{
					action = "action_one",
					input = "action_one",
					start_time = 0.66,
					sub_action = "default",
				},
				{
					action = "action_one",
					input = "action_one_hold",
					start_time = 0.66,
					sub_action = "default",
				},
				{
					action = "action_two",
					input = "action_two_hold",
					start_time = 0.66,
					sub_action = "default",
				},
				{
					action = "weapon_reload",
					input = "weapon_reload",
					start_time = 0.35,
					sub_action = "default",
				},
			},
			enter_function = function (attacker_unit, input_extension)
				input_extension:clear_input_buffer()
			end,
			recoil_settings = {
				climb_duration = 0.2,
				horizontal_climb = 0,
				restore_duration = 0.3,
				vertical_climb = 3,
				climb_function = math.easeInCubic,
				restore_function = math.ease_out_quad,
			},
		},
		zoomed_shot = {
			active_reload_time = 0.35,
			aim_assist_auto_hit_chance = 0.5,
			aim_assist_max_ramp_multiplier = 1,
			aim_assist_ramp_decay_delay = 0.1,
			aim_assist_ramp_multiplier = 0.3,
			alert_sound_range_fire = 10,
			alert_sound_range_hit = 2,
			ammo_usage = 1,
			anim_end_event = "to_unzoom",
			anim_event = "attack_shoot",
			anim_event_last_ammo = "attack_shoot_last",
			anim_event_no_ammo_left = "attack_shoot_last",
			apply_recoil = true,
			charge_value = "light_attack",
			damage_profile = "shot_sniper",
			damage_window_end = 0,
			damage_window_start = 0.1,
			fire_time = 0,
			headshot_multiplier = 3,
			hit_effect = "bullet_impact",
			hold_input = "action_two_hold",
			ignore_shield_hit = true,
			kind = "handgun",
			minimum_hold_time = 0.66,
			ranged_attack = true,
			reload_when_out_of_ammo = true,
			total_time = 0.8,
			anim_end_event_condition_func = function (unit, end_reason)
				return end_reason ~= "new_interupting_action"
			end,
			allowed_chain_actions = {
				{
					action = "action_wield",
					input = "action_wield",
					start_time = 0.6,
					sub_action = "default",
				},
				{
					action = "action_one",
					input = "action_one",
					release_required = "action_two_hold",
					start_time = 0.7,
					sub_action = "default",
				},
				{
					action = "action_two",
					input = "action_two_hold",
					start_time = 0.7,
					sub_action = "default",
					end_time = math.huge,
				},
				{
					action = "weapon_reload",
					input = "weapon_reload",
					start_time = 0,
					sub_action = "default",
				},
			},
			recoil_settings = {
				climb_duration = 0.2,
				horizontal_climb = 0,
				restore_duration = 0.3,
				vertical_climb = 3,
				climb_function = math.easeInCubic,
				restore_function = math.ease_out_quad,
			},
		},
	},
	action_two = {
		default = {
			aim_assist_max_ramp_multiplier = 1,
			aim_assist_ramp_decay_delay = 0.3,
			aim_assist_ramp_multiplier = 0.6,
			aim_at_gaze_setting = "tobii_aim_at_gaze_handgun",
			allow_hold_toggle = true,
			ammo_requirement = 1,
			anim_end_event = "to_unzoom",
			anim_event = "to_zoom",
			can_abort_reload = false,
			cooldown = 0.3,
			hold_input = "action_two_hold",
			keep_buffer = true,
			kind = "aim",
			minimum_hold_time = 0.3,
			reset_aim_assist_on_exit = true,
			anim_end_event_condition_func = function (unit, end_reason)
				return end_reason ~= "new_interupting_action"
			end,
			total_time = math.huge,
			buff_data = {
				{
					buff_name = "planted_charging_decrease_movement",
					external_multiplier = 0.25,
					start_time = 0,
				},
			},
			allowed_chain_actions = {
				{
					action = "action_wield",
					input = "action_wield",
					start_time = 0,
					sub_action = "default",
				},
				{
					action = "action_one",
					input = "action_one",
					start_time = 0.4,
					sub_action = "zoomed_shot",
				},
				{
					action = "weapon_reload",
					input = "weapon_reload",
					start_time = 0,
					sub_action = "default",
				},
			},
			zoom_condition_function = function ()
				return true
			end,
			unzoom_condition_function = function (end_reason)
				return end_reason ~= "new_interupting_action"
			end,
			condition_func = function (unit, input_extension, ammo_extension)
				if ammo_extension and (ammo_extension:total_remaining_ammo() <= 0 or ammo_extension:is_reloading()) then
					return false
				end

				return true
			end,
		},
	},
	weapon_reload = ActionTemplates.reload,
	action_inspect = ActionTemplates.action_inspect,
}
weapon_template.ammo_data = {
	ammo_hand = "right",
	ammo_per_clip = 1,
	ammo_per_reload = 1,
	max_ammo = 16,
	play_reload_anim_on_wield_reload = true,
	reload_on_ammo_pickup = true,
	reload_time = 1.5,
	should_update_anim_ammo = true,
}
weapon_template.attack_meta_data = {
	aim_at_node = "j_spine1",
	aim_at_node_charged = "j_head",
	can_charge_shot = true,
	charge_above_range = 30,
	charge_when_obstructed = false,
	charged_attack_action_name = "zoomed_shot",
	ignore_enemies_for_obstruction = true,
	minimum_charge_time = 0.45,
	effective_against = bit.bor(BreedCategory.Berserker, BreedCategory.Special, BreedCategory.Armored, BreedCategory.Shielded),
}
action_anim_overrides = {
	animation_variation_id = 1,
}
weapon_template.default_spread_template = "handgun"
weapon_template.spread_lerp_speed = 5
weapon_template.spread_lerp_speed_zoom = 3.75
weapon_template.right_hand_unit = ""
weapon_template.right_hand_attachment_node_linking = AttachmentNodeLinking.rifles
weapon_template.display_unit = "units/weapons/weapon_display/display_1h_handguns"
weapon_template.wield_anim = "to_handgun"
weapon_template.wield_anim_no_ammo = "to_handgun_noammo"
weapon_template.state_machine = "units/beings/player/first_person_base/state_machines/ranged/handgun"
weapon_template.crosshair_style = "default"
weapon_template.reload_event = "reload"
weapon_template.buff_type = "RANGED"
weapon_template.weapon_type = "HANDGUN"
weapon_template.no_dodge = true
weapon_template.buffs = {
	change_dodge_distance = {
		external_optional_multiplier = 1,
	},
	change_dodge_speed = {
		external_optional_multiplier = 1,
	},
}
weapon_template.aim_assist_settings = {
	always_auto_aim = true,
	base_multiplier = 0.15,
	effective_max_range = 10,
	max_range = 22,
	no_aim_input_multiplier = 0,
	target_node = "j_spine1",
	breed_scalars = {
		skaven_clan_rat = 1,
		skaven_slave = 1,
		skaven_storm_vermin = 0.25,
	},
}
weapon_template.weapon_diagram = {
	light_attack = {
		[DamageTypes.ARMOR_PIERCING] = 7,
		[DamageTypes.CLEAVE] = 1,
		[DamageTypes.SPEED] = 1,
		[DamageTypes.STAGGER] = 3,
		[DamageTypes.DAMAGE] = 7,
	},
	heavy_attack = {
		[DamageTypes.ARMOR_PIERCING] = 0,
		[DamageTypes.CLEAVE] = 0,
		[DamageTypes.SPEED] = 0,
		[DamageTypes.STAGGER] = 0,
		[DamageTypes.DAMAGE] = 0,
	},
}
weapon_template.wwise_dep_right_hand = {
	"wwise/handgun",
}
weapon_template.tooltip_keywords = {
	"weapon_keyword_high_damage",
	"weapon_keyword_sniper",
	"weapon_keyword_headshotting",
}
weapon_template.tooltip_compare = {
	light = {
		action_name = "action_one",
		sub_action_name = "default",
	},
	heavy = {
		action_name = "action_one",
		sub_action_name = "zoomed_shot",
	},
}
weapon_template.tooltip_detail = {
	light = {
		action_name = "action_one",
		sub_action_name = "default",
	},
	heavy = {
		action_name = "action_two",
		sub_action_name = "default",
	},
}

local handgun_es = table.clone(weapon_template)
local handgun_dr = table.clone(weapon_template)

handgun_dr.wield_anim = "to_handgun_dr"
handgun_dr.wield_anim_no_ammo = "to_handgun_dr_noammo"
handgun_dr.state_machine = "units/beings/player/first_person_base/state_machines/ranged/handgun_dr"

local handgun_vs = table.clone(weapon_template)

handgun_vs.ammo_data = {
	ammo_hand = "right",
	ammo_per_clip = 1,
	ammo_per_reload = 1,
	max_ammo = 13,
	play_reload_anim_on_wield_reload = true,
	reload_on_ammo_pickup = true,
	reload_time = 1.5,
	should_update_anim_ammo = true,
}

local handgun_vs_dr = table.clone(handgun_vs)

handgun_vs_dr.wield_anim = "to_handgun_dr"
handgun_vs_dr.wield_anim_no_ammo = "to_handgun_dr_noammo"
handgun_vs_dr.state_machine = "units/beings/player/first_person_base/state_machines/ranged/handgun_dr"

return {
	handgun_template_1 = table.clone(handgun_es),
	handgun_template_2 = table.clone(handgun_dr),
	handgun_template_1_vs = table.clone(handgun_vs),
	handgun_template_2_vs = table.clone(handgun_vs_dr),
}
]====],
tuskgor = [====[
-- chunkname: @scripts/settings/equipment/weapon_templates/2h_heavy_spears.lua

local push_radius = 2.75
local time_mod = 0.8
local weapon_template = {}

weapon_template.actions = {
	action_one = {
		default = {
			anim_end_event = "attack_finished",
			anim_event = "attack_swing_charge_stab",
			attack_hold_input = "action_one_hold",
			kind = "melee_start",
			anim_end_event_condition_func = function (unit, end_reason)
				return end_reason ~= "new_interupting_action" and end_reason ~= "action_complete"
			end,
			total_time = math.huge,
			buff_data = {
				{
					buff_name = "planted_charging_decrease_movement",
					end_time = 0.4,
					external_multiplier = 0.85,
					start_time = 0,
				},
				{
					buff_name = "planted_fast_decrease_movement",
					external_multiplier = 1.1,
					start_time = 0.4,
				},
			},
			allowed_chain_actions = {
				{
					action = "action_one",
					end_time = 0.3,
					input = "action_one_release",
					start_time = 0,
					sub_action = "light_attack_left",
				},
				{
					action = "action_one",
					force_release_input = "action_one_hold",
					input = "action_one_release",
					start_time = 0.45,
					sub_action = "heavy_attack_left",
				},
				{
					action = "action_two",
					input = "action_two_hold",
					start_time = 0,
					sub_action = "default",
				},
				{
					action = "action_wield",
					input = "action_wield",
					start_time = 0,
					sub_action = "default",
				},
			},
		},
		default_left = {
			anim_end_event = "attack_finished",
			anim_event = "attack_swing_charge",
			kind = "melee_start",
			anim_end_event_condition_func = function (unit, end_reason)
				return end_reason ~= "new_interupting_action" and end_reason ~= "action_complete"
			end,
			total_time = math.huge,
			buff_data = {
				{
					buff_name = "planted_charging_decrease_movement",
					end_time = 0.4,
					external_multiplier = 0.85,
					start_time = 0,
				},
				{
					buff_name = "planted_fast_decrease_movement",
					external_multiplier = 1.1,
					start_time = 0.4,
				},
			},
			allowed_chain_actions = {
				{
					action = "action_one",
					end_time = 0.3,
					input = "action_one_release",
					start_time = 0,
					sub_action = "light_attack_right",
				},
				{
					action = "action_one",
					force_release_input = "action_one_hold",
					input = "action_one_release",
					start_time = 0.5,
					sub_action = "heavy_attack_tank",
				},
				{
					action = "action_two",
					input = "action_two_hold",
					start_time = 0,
					sub_action = "default",
				},
				{
					action = "action_wield",
					input = "action_wield",
					start_time = 0,
					sub_action = "default",
				},
				{
					blocker = true,
					end_time = 1.5,
					input = "action_one_hold",
					start_time = 0.3,
				},
				{
					action = "action_one",
					auto_chain = true,
					start_time = 0.6,
					sub_action = "heavy_attack_tank",
				},
			},
		},
		default_last_1 = {
			anim_end_event = "attack_finished",
			anim_event = "attack_swing_charge",
			kind = "melee_start",
			anim_end_event_condition_func = function (unit, end_reason)
				return end_reason ~= "new_interupting_action" and end_reason ~= "action_complete"
			end,
			total_time = math.huge,
			buff_data = {
				{
					buff_name = "planted_charging_decrease_movement",
					end_time = 0.4,
					external_multiplier = 0.85,
					start_time = 0,
				},
				{
					buff_name = "planted_fast_decrease_movement",
					external_multiplier = 1.1,
					start_time = 0.4,
				},
			},
			allowed_chain_actions = {
				{
					action = "action_one",
					end_time = 0.3,
					input = "action_one_release",
					start_time = 0,
					sub_action = "light_attack_stab_1",
				},
				{
					action = "action_one",
					force_release_input = "action_one_hold",
					input = "action_one_release",
					start_time = 0.45,
					sub_action = "heavy_attack_tank",
				},
				{
					action = "action_two",
					input = "action_two_hold",
					start_time = 0,
					sub_action = "default",
				},
				{
					action = "action_wield",
					input = "action_wield",
					start_time = 0,
					sub_action = "default",
				},
				{
					blocker = true,
					end_time = 1.5,
					input = "action_one_hold",
					start_time = 0.3,
				},
				{
					action = "action_one",
					auto_chain = true,
					start_time = 0.6,
					sub_action = "heavy_attack_tank",
				},
			},
		},
		default_last_2 = {
			anim_end_event = "attack_finished",
			anim_event = "attack_swing_charge",
			kind = "melee_start",
			anim_end_event_condition_func = function (unit, end_reason)
				return end_reason ~= "new_interupting_action" and end_reason ~= "action_complete"
			end,
			total_time = math.huge,
			buff_data = {
				{
					buff_name = "planted_charging_decrease_movement",
					external_multiplier = 0.75,
					start_time = 0,
				},
			},
			allowed_chain_actions = {
				{
					action = "action_one",
					end_time = 0.3,
					input = "action_one_release",
					start_time = 0,
					sub_action = "light_attack_stab_2",
				},
				{
					action = "action_one",
					force_release_input = "action_one_hold",
					input = "action_one_release",
					start_time = 0.45,
					sub_action = "heavy_attack_tank",
				},
				{
					action = "action_two",
					input = "action_two_hold",
					start_time = 0,
					sub_action = "default",
				},
				{
					action = "action_wield",
					input = "action_wield",
					start_time = 0,
					sub_action = "default",
				},
				{
					blocker = true,
					end_time = 1.5,
					input = "action_one_hold",
					start_time = 0.3,
				},
				{
					action = "action_one",
					auto_chain = true,
					start_time = 0.6,
					sub_action = "heavy_attack_tank",
				},
			},
		},
		heavy_attack_tank = {
			additional_critical_strike_chance = 0,
			anim_end_event = "attack_finished",
			anim_event = "attack_swing_heavy_left",
			damage_profile = "heavy_slashing_tank",
			damage_window_end = 0.27,
			damage_window_start = 0.19,
			dedicated_target_range = 3,
			first_person_hit_anim = "hit_right_shake",
			height_mod = 5,
			hit_effect = "melee_hit_sword_1h",
			hit_shield_stop_anim = "attack_hit",
			impact_sound_event = "stab_hit",
			kind = "sweep",
			no_damage_impact_sound_event = "stab_hit_armour",
			push_radius = 3,
			range_mod = 1.35,
			range_mod_add = 0.5,
			sweep_z_offset = 0.1,
			total_time = 1.5,
			weapon_up_offset_mod = -0.25,
			width_mod = 30,
			anim_end_event_condition_func = function (unit, end_reason)
				return end_reason ~= "new_interupting_action" and end_reason ~= "action_complete"
			end,
			anim_time_scale = time_mod * 1,
			buff_data = {
				{
					buff_name = "planted_fast_decrease_movement",
					end_time = 0.3,
					external_multiplier = 1.75,
					start_time = 0,
				},
				{
					buff_name = "planted_fast_decrease_movement",
					end_time = 0.75,
					external_multiplier = 0.5,
					start_time = 0.3,
				},
			},
			allowed_chain_actions = {
				{
					action = "action_one",
					doubleclick_window = 0,
					input = "action_one",
					release_required = "action_one_hold",
					start_time = 0.5,
					sub_action = "default",
				},
				{
					action = "action_one",
					doubleclick_window = 0,
					input = "action_one_hold",
					release_required = "action_one_hold",
					start_time = 0.5,
					sub_action = "default",
				},
				{
					action = "action_two",
					input = "action_two_hold",
					start_time = 0.5,
					sub_action = "default",
				},
				{
					action = "action_two",
					end_time = 0.15,
					input = "action_two_hold",
					start_time = 0,
					sub_action = "default",
				},
				{
					action = "action_wield",
					input = "action_wield",
					start_time = 0.5,
					sub_action = "default",
				},
			},
			enter_function = function (attacker_unit, input_extension)
				return input_extension:reset_release_input()
			end,
			hit_mass_count = TANK_HIT_MASS_COUNT,
			baked_sweep = {
				{
					0.15666666666666668,
					0.7794848680496216,
					-0.0007534027099609375,
					-0.06832551956176758,
					-0.3141167163848877,
					-0.552521288394928,
					0.25650113821029663,
					-0.7281882762908936,
				},
				{
					0.1811111111111111,
					0.7343336343765259,
					0.0073871612548828125,
					-0.17690253257751465,
					-0.2667536735534668,
					-0.6340987682342529,
					0.24134309589862823,
					-0.6844813823699951,
				},
				{
					0.20555555555555557,
					0.29144442081451416,
					0.8203849792480469,
					-0.17725253105163574,
					0.3299006521701813,
					-0.6370298266410828,
					-0.24259202182292938,
					-0.6530755758285522,
				},
				{
					0.23,
					-0.25031423568725586,
					0.9407052993774414,
					-0.14596617221832275,
					-0.49835851788520813,
					0.45024383068084717,
					0.620097279548645,
					0.4054611325263977,
				},
				{
					0.2544444444444445,
					-0.5164668560028076,
					0.5813837051391602,
					-0.1578688621520996,
					-0.6040778160095215,
					0.28232312202453613,
					0.7211363315582275,
					0.18800553679466248,
				},
				{
					0.2788888888888889,
					-0.5456023216247559,
					0.13760948181152344,
					-0.16015398502349854,
					-0.6594530344009399,
					0.11889182776212692,
					0.742139458656311,
					-0.014682469889521599,
				},
				{
					0.30333333333333334,
					-0.5448378920555115,
					0.033034324645996094,
					-0.17033588886260986,
					-0.6799610257148743,
					0.08537144958972931,
					0.7270162105560303,
					-0.04256992042064667,
				},
			},
		},
		heavy_attack_left = {
			additional_critical_strike_chance = 0,
			anim_end_event = "attack_finished",
			anim_event = "attack_swing_heavy_stab",
			charge_value = "heavy_attack",
			damage_profile = "heavy_slashing_smiter_stab_polearm",
			damage_window_end = 0.35,
			damage_window_start = 0.26,
			dedicated_target_range = 2.8,
			first_person_hit_anim = "hit_left_shake",
			hit_armor_anim = "attack_hit",
			hit_effect = "melee_hit_sword_1h",
			hit_shield_stop_anim = "attack_hit",
			hit_stop_anim = "attack_hit",
			impact_sound_event = "slashing_hit",
			kind = "sweep",
			no_damage_impact_sound_event = "slashing_hit_armour",
			range_mod = 1.35,
			range_mod_add = 1,
			sweep_z_offset = 0.15,
			total_time = 1.5,
			use_precision_sweep = false,
			weapon_up_offset_mod = -0.5,
			width_mod = 25,
			anim_end_event_condition_func = function (unit, end_reason)
				return end_reason ~= "new_interupting_action" and end_reason ~= "action_complete"
			end,
			anim_time_scale = time_mod * 1.05,
			buff_data = {
				{
					buff_name = "planted_fast_decrease_movement",
					end_time = 0.3,
					external_multiplier = 1.85,
					start_time = 0,
				},
				{
					buff_name = "planted_fast_decrease_movement",
					end_time = 0.75,
					external_multiplier = 0.5,
					start_time = 0.3,
				},
			},
			allowed_chain_actions = {
				{
					action = "action_one",
					doubleclick_window = 0,
					input = "action_one",
					release_required = "action_one_hold",
					start_time = 0.55,
					sub_action = "default_last_1",
				},
				{
					action = "action_one",
					doubleclick_window = 0,
					input = "action_one_hold",
					release_required = "action_one_hold",
					start_time = 0.55,
					sub_action = "default_last_1",
				},
				{
					action = "action_two",
					input = "action_two_hold",
					start_time = 0.5,
					sub_action = "default",
				},
				{
					action = "action_two",
					end_time = 0.15,
					input = "action_two_hold",
					start_time = 0,
					sub_action = "default",
				},
				{
					action = "action_wield",
					input = "action_wield",
					start_time = 0.5,
					sub_action = "default",
				},
			},
			enter_function = function (attacker_unit, input_extension)
				return input_extension:reset_release_input()
			end,
			baked_sweep = {
				{
					0.22666666666666668,
					-0.2676389217376709,
					-0.16475772857666016,
					-0.3952113389968872,
					0.2779823839664459,
					-0.53691565990448,
					-0.5582191944122314,
					-0.5681889057159424,
				},
				{
					0.25277777777777777,
					-0.19676637649536133,
					0.570216178894043,
					-0.25373589992523193,
					0.49959737062454224,
					-0.4534851610660553,
					-0.43555310368537903,
					-0.5958583354949951,
				},
				{
					0.2788888888888889,
					-0.14124178886413574,
					0.9971733093261719,
					-0.16448664665222168,
					0.5512819886207581,
					-0.3934764862060547,
					-0.3694900572299957,
					-0.6361929774284363,
				},
				{
					0.305,
					-0.1338711977005005,
					1.0418834686279297,
					-0.16223740577697754,
					0.5079681873321533,
					-0.4352867007255554,
					-0.4125145673751831,
					-0.618324875831604,
				},
				{
					0.3311111111111111,
					-0.13216924667358398,
					1.0449895858764648,
					-0.1715928316116333,
					0.4652595818042755,
					-0.48912665247917175,
					-0.46807006001472473,
					-0.5702623128890991,
				},
				{
					0.3572222222222222,
					-0.1230630874633789,
					1.042515754699707,
					-0.18150365352630615,
					0.41138091683387756,
					-0.5479035973548889,
					-0.5293218493461609,
					-0.5003856420516968,
				},
				{
					0.3833333333333333,
					-0.10934078693389893,
					1.0376720428466797,
					-0.19166433811187744,
					-0.3486274480819702,
					0.5973131060600281,
					0.5855737924575806,
					0.422823041677475,
				},
			},
		},
		light_attack_left = {
			additional_critical_strike_chance = 0,
			aim_assist_max_ramp_multiplier = 0.8,
			aim_assist_ramp_decay_delay = 0.1,
			aim_assist_ramp_multiplier = 0.5,
			anim_end_event = "attack_finished",
			anim_event = "attack_swing_right",
			damage_profile = "medium_spear_smiter_stab",
			damage_window_end = 0.34,
			damage_window_start = 0.23,
			dedicated_target_range = 2.8,
			height_mod = 5,
			hit_armor_anim = "attack_hit",
			hit_effect = "melee_hit_sword_1h",
			hit_shield_stop_anim = "attack_hit",
			impact_sound_event = "stab_hit",
			kind = "sweep",
			no_damage_impact_sound_event = "stab_hit_armour",
			range_mod = 1.35,
			range_mod_add = 1,
			sweep_z_offset = 0.05,
			total_time = 2.5,
			uninterruptible = true,
			use_precision_sweep = true,
			weapon_up_offset_mod = -0.5,
			width_mod = 30,
			anim_end_event_condition_func = function (unit, end_reason)
				return end_reason ~= "new_interupting_action" and end_reason ~= "action_complete"
			end,
			anim_time_scale = time_mod * 0.95,
			buff_data = {
				{
					buff_name = "planted_fast_decrease_movement",
					end_time = 0.25,
					external_multiplier = 1.3,
					start_time = 0,
				},
				{
					buff_name = "planted_fast_decrease_movement",
					end_time = 0.5,
					external_multiplier = 0.7,
					start_time = 0.25,
				},
			},
			allowed_chain_actions = {
				{
					action = "action_one",
					end_time = 1.1,
					input = "action_one",
					release_required = "action_one_hold",
					start_time = 0.4,
					sub_action = "default_last_1",
				},
				{
					action = "action_one",
					end_time = 1.1,
					input = "action_one_hold",
					release_required = "action_one_hold",
					start_time = 0.4,
					sub_action = "default_last_1",
				},
				{
					action = "action_one",
					input = "action_one",
					start_time = 1,
					sub_action = "default",
				},
				{
					action = "action_two",
					input = "action_two_hold",
					start_time = 0,
					sub_action = "default",
				},
				{
					action = "action_wield",
					input = "action_wield",
					start_time = 0.5,
					sub_action = "default",
				},
			},
			baked_sweep = {
				{
					0.19666666666666668,
					0.008028626441955566,
					0.2489013671875,
					-0.3074302673339844,
					0.6778017282485962,
					-0.04507540538907051,
					-0.03575539216399193,
					-0.7329902052879333,
				},
				{
					0.22611111111111112,
					-0.02705550193786621,
					0.7245082855224609,
					-0.17972135543823242,
					0.6477677226066589,
					-0.09821726381778717,
					-0.13964064419269562,
					-0.742462694644928,
				},
				{
					0.2555555555555556,
					0.024181604385375977,
					1.029313087463379,
					-0.13399064540863037,
					0.6350173354148865,
					-0.19154173135757446,
					-0.18326234817504883,
					-0.7255892157554626,
				},
				{
					0.28500000000000003,
					0.02608346939086914,
					1.044600486755371,
					-0.12580525875091553,
					0.6314035058021545,
					-0.19628985226154327,
					-0.1909303367137909,
					-0.7254967093467712,
				},
				{
					0.31444444444444447,
					0.029326438903808594,
					1.0247249603271484,
					-0.11837542057037354,
					0.6224663257598877,
					-0.19808459281921387,
					-0.19449755549430847,
					-0.731757402420044,
				},
				{
					0.3438888888888889,
					0.033881545066833496,
					0.9631595611572266,
					-0.11820900440216064,
					0.598878800868988,
					-0.21428775787353516,
					-0.21448618173599243,
					-0.7412291169166565,
				},
				{
					0.37333333333333335,
					0.036568403244018555,
					0.8754673004150391,
					-0.13302850723266602,
					0.5693584084510803,
					-0.23443123698234558,
					-0.24145931005477905,
					-0.7500469088554382,
				},
			},
		},
		light_attack_right = {
			additional_critical_strike_chance = 0,
			aim_assist_max_ramp_multiplier = 0.8,
			aim_assist_ramp_decay_delay = 0.1,
			aim_assist_ramp_multiplier = 0.5,
			anim_end_event = "attack_finished",
			anim_event = "attack_swing_down_left",
			damage_profile = "medium_slashing_linesman_spear",
			damage_window_end = 0.4,
			damage_window_start = 0.35,
			dedicated_target_range = 2.8,
			height_mod = 5,
			hit_armor_anim = "attack_hit",
			hit_effect = "melee_hit_sword_1h",
			hit_shield_stop_anim = "attack_hit",
			hit_stop_anim = "attack_hit",
			impact_sound_event = "slashing_hit",
			kind = "sweep",
			no_damage_impact_sound_event = "slashing_hit_armour",
			range_mod = 1.35,
			range_mod_add = 0.25,
			sweep_z_offset = 0.25,
			total_time = 2.5,
			uninterruptible = true,
			use_precision_sweep = false,
			weapon_up_offset_mod = 0,
			width_mod = 30,
			anim_end_event_condition_func = function (unit, end_reason)
				return end_reason ~= "new_interupting_action" and end_reason ~= "action_complete"
			end,
			anim_time_scale = time_mod * 1.1,
			buff_data = {
				{
					buff_name = "planted_fast_decrease_movement",
					end_time = 0.25,
					external_multiplier = 1.3,
					start_time = 0,
				},
				{
					buff_name = "planted_fast_decrease_movement",
					end_time = 0.5,
					external_multiplier = 0.7,
					start_time = 0.25,
				},
			},
			allowed_chain_actions = {
				{
					action = "action_one",
					end_time = 1.35,
					input = "action_one",
					release_required = "action_one_hold",
					start_time = 0.65,
					sub_action = "default_last_2",
				},
				{
					action = "action_one",
					end_time = 1.35,
					input = "action_one_hold",
					release_required = "action_one_hold",
					start_time = 0.65,
					sub_action = "default_last_2",
				},
				{
					action = "action_one",
					input = "action_one",
					start_time = 1.3,
					sub_action = "default",
				},
				{
					action = "action_two",
					input = "action_two_hold",
					start_time = 0.5,
					sub_action = "default",
				},
				{
					action = "action_two",
					end_time = 0.15,
					input = "action_two_hold",
					start_time = 0,
					sub_action = "default",
				},
				{
					action = "action_wield",
					input = "action_wield",
					start_time = 0.5,
					sub_action = "default",
				},
			},
			enter_function = function (attacker_unit, input_extension)
				return input_extension:reset_release_input()
			end,
			baked_sweep = {
				{
					0.31666666666666665,
					0.5823971033096313,
					0.22487258911132812,
					0.20524930953979492,
					-0.15105022490024567,
					-0.35181570053100586,
					0.08757807314395905,
					-0.9196410775184631,
				},
				{
					0.3361111111111111,
					0.5978356599807739,
					0.2806224822998047,
					0.1995004415512085,
					-0.1633412092924118,
					-0.382678747177124,
					0.08950524032115936,
					-0.9049118757247925,
				},
				{
					0.35555555555555557,
					0.48498332500457764,
					0.605743408203125,
					0.06056714057922363,
					0.10162675380706787,
					-0.4111544191837311,
					-0.05810223147273064,
					-0.9040178060531616,
				},
				{
					0.375,
					-0.053287506103515625,
					0.8395957946777344,
					-0.21017980575561523,
					0.5460003018379211,
					-0.2857076823711395,
					-0.3721582293510437,
					-0.6940843462944031,
				},
				{
					0.39444444444444443,
					-0.38806724548339844,
					0.5849847793579102,
					-0.3655219078063965,
					0.708229660987854,
					-0.1790706217288971,
					-0.523059070110321,
					-0.4390372633934021,
				},
				{
					0.41388888888888886,
					-0.4282907247543335,
					0.3613109588623047,
					-0.41774606704711914,
					0.753360390663147,
					-0.16944415867328644,
					-0.5717397332191467,
					-0.27721914649009705,
				},
				{
					0.43333333333333335,
					-0.49891388416290283,
					0.2909736633300781,
					-0.4632033109664917,
					0.7509186267852783,
					-0.06506925076246262,
					-0.5812844038009644,
					-0.30658718943595886,
				},
			},
		},
		light_attack_stab_1 = {
			additional_critical_strike_chance = 0,
			aim_assist_max_ramp_multiplier = 0.8,
			aim_assist_ramp_decay_delay = 0.1,
			aim_assist_ramp_multiplier = 0.5,
			anim_end_event = "attack_finished",
			anim_event = "attack_swing_stab_lh",
			damage_profile = "medium_spear_smiter_stab",
			damage_window_end = 0.35,
			damage_window_start = 0.3,
			dedicated_target_range = 2.8,
			height_mod = 5,
			hit_armor_anim = "attack_hit",
			hit_effect = "melee_hit_sword_1h",
			hit_shield_stop_anim = "attack_hit",
			impact_sound_event = "stab_hit",
			kind = "sweep",
			no_damage_impact_sound_event = "stab_hit_armour",
			range_mod = 1.35,
			range_mod_add = 1,
			total_time = 2.5,
			uninterruptible = true,
			use_precision_sweep = true,
			weapon_up_offset_mod = -0.5,
			width_mod = 30,
			anim_end_event_condition_func = function (unit, end_reason)
				return end_reason ~= "new_interupting_action" and end_reason ~= "action_complete"
			end,
			anim_time_scale = time_mod * 0.85,
			buff_data = {
				{
					buff_name = "planted_fast_decrease_movement",
					end_time = 0.25,
					external_multiplier = 1.1,
					start_time = 0,
				},
				{
					buff_name = "planted_fast_decrease_movement",
					end_time = 0.5,
					external_multiplier = 0.6,
					start_time = 0.25,
				},
			},
			allowed_chain_actions = {
				{
					action = "action_one",
					end_time = 1.125,
					input = "action_one",
					release_required = "action_one_hold",
					start_time = 0.425,
					sub_action = "default_left",
				},
				{
					action = "action_one",
					end_time = 1.125,
					input = "action_one_hold",
					release_required = "action_one_hold",
					start_time = 0.425,
					sub_action = "default_left",
				},
				{
					action = "action_one",
					input = "action_one",
					start_time = 1,
					sub_action = "default",
				},
				{
					action = "action_two",
					input = "action_two_hold",
					start_time = 0.425,
					sub_action = "default",
				},
				{
					action = "action_two",
					end_time = 0.2,
					input = "action_two_hold",
					start_time = 0,
					sub_action = "default",
				},
				{
					action = "action_wield",
					input = "action_wield",
					start_time = 0.4,
					sub_action = "default",
				},
			},
			baked_sweep = {
				{
					0.26666666666666666,
					-0.8384718298912048,
					-1.4760942459106445,
					0.0011044740676879883,
					-0.07398690283298492,
					0.7059394717216492,
					0.6508823037147522,
					0.26930972933769226,
				},
				{
					0.2861111111111111,
					-0.5670022368431091,
					-0.47643089294433594,
					-0.005642414093017578,
					-0.08230125904083252,
					0.7011156678199768,
					0.6622886061668396,
					0.25107210874557495,
				},
				{
					0.3055555555555555,
					-0.29829204082489014,
					0.6144495010375977,
					-0.0021227598190307617,
					-0.0983009785413742,
					0.6987364292144775,
					0.6646027565002441,
					0.24577952921390533,
				},
				{
					0.32499999999999996,
					-0.15347766876220703,
					1.1020011901855469,
					-0.046198368072509766,
					-0.11474600434303284,
					0.7067400217056274,
					0.6635962128639221,
					0.2167765349149704,
				},
				{
					0.34444444444444444,
					-0.1395777463912964,
					1.1267356872558594,
					-0.04041290283203125,
					-0.11571420729160309,
					0.6950896382331848,
					0.671852707862854,
					0.22819846868515015,
				},
				{
					0.3638888888888889,
					-0.12897884845733643,
					1.1463298797607422,
					-0.06283795833587646,
					-0.11792200803756714,
					0.689225435256958,
					0.6782465577125549,
					0.22593003511428833,
				},
				{
					0.3833333333333333,
					-0.1268787384033203,
					1.151026725769043,
					-0.07476222515106201,
					-0.11915021389722824,
					0.6854234933853149,
					0.6824883818626404,
					0.2240704894065857,
				},
			},
		},
		light_attack_stab_2 = {
			additional_critical_strike_chance = 0,
			aim_assist_max_ramp_multiplier = 0.8,
			aim_assist_ramp_decay_delay = 0.1,
			aim_assist_ramp_multiplier = 0.5,
			anim_end_event = "attack_finished",
			anim_event = "attack_swing_stab_02",
			damage_profile = "medium_spear_smiter_stab",
			damage_window_end = 0.23,
			damage_window_start = 0.18,
			dedicated_target_range = 2.8,
			height_mod = 5,
			hit_armor_anim = "attack_hit",
			hit_effect = "melee_hit_sword_1h",
			hit_shield_stop_anim = "attack_hit",
			impact_sound_event = "stab_hit",
			kind = "sweep",
			no_damage_impact_sound_event = "stab_hit_armour",
			range_mod = 1.35,
			range_mod_add = 1,
			total_time = 2.5,
			uninterruptible = true,
			use_precision_sweep = true,
			weapon_up_offset_mod = -0.5,
			width_mod = 30,
			anim_end_event_condition_func = function (unit, end_reason)
				return end_reason ~= "new_interupting_action" and end_reason ~= "action_complete"
			end,
			anim_time_scale = time_mod * 1,
			buff_data = {
				{
					buff_name = "planted_fast_decrease_movement",
					end_time = 0.25,
					external_multiplier = 1.1,
					start_time = 0,
				},
				{
					buff_name = "planted_fast_decrease_movement",
					end_time = 0.5,
					external_multiplier = 0.6,
					start_time = 0.25,
				},
			},
			allowed_chain_actions = {
				{
					action = "action_one",
					input = "action_one_hold",
					release_required = "action_one_hold",
					start_time = 0.45,
					sub_action = "default",
				},
				{
					action = "action_one",
					input = "action_one",
					release_required = "action_one_hold",
					start_time = 0.45,
					sub_action = "default",
				},
				{
					action = "action_two",
					input = "action_two_hold",
					start_time = 0,
					sub_action = "default",
				},
				{
					action = "action_wield",
					input = "action_wield",
					start_time = 0.4,
					sub_action = "default",
				},
			},
			baked_sweep = {
				{
					0.14666666666666667,
					-0.39311492443084717,
					-0.5856552124023438,
					-0.3936830759048462,
					-0.26863986253738403,
					0.592030942440033,
					0.6429774761199951,
					0.40486058592796326,
				},
				{
					0.16611111111111113,
					-0.3041602373123169,
					-0.05975151062011719,
					-0.3281681537628174,
					0.3355526924133301,
					-0.533738911151886,
					-0.5363714694976807,
					-0.5610995888710022,
				},
				{
					0.18555555555555556,
					-0.1962137222290039,
					0.5826997756958008,
					-0.23983120918273926,
					0.48632341623306274,
					-0.46581026911735535,
					-0.4370131194591522,
					-0.5962632298469543,
				},
				{
					0.20500000000000002,
					-0.13424444198608398,
					0.9689950942993164,
					-0.15601778030395508,
					0.5428183674812317,
					-0.3969467878341675,
					-0.3694576919078827,
					-0.6413130760192871,
				},
				{
					0.22444444444444445,
					-0.1347179412841797,
					1.0272045135498047,
					-0.15884935855865479,
					0.5285305976867676,
					-0.4114686846733093,
					-0.388177752494812,
					-0.632982611656189,
				},
				{
					0.2438888888888889,
					-0.13342607021331787,
					1.0443286895751953,
					-0.16366326808929443,
					0.49978163838386536,
					-0.4439685046672821,
					-0.42573896050453186,
					-0.6098005175590515,
				},
				{
					0.26333333333333336,
					-0.13266968727111816,
					1.045243263244629,
					-0.17048418521881104,
					0.471110999584198,
					-0.4804118275642395,
					-0.46366602182388306,
					-0.5764310956001282,
				},
			},
		},
		light_attack_bopp = {
			additional_critical_strike_chance = 0,
			anim_end_event = "attack_finished",
			anim_event = "attack_swing_heavy_left",
			damage_profile = "heavy_slashing_tank",
			damage_window_end = 0.27,
			damage_window_start = 0.19,
			dedicated_target_range = 3,
			first_person_hit_anim = "hit_right_shake",
			height_mod = 5,
			hit_effect = "melee_hit_sword_1h",
			hit_shield_stop_anim = "attack_hit",
			impact_sound_event = "stab_hit",
			kind = "sweep",
			no_damage_impact_sound_event = "stab_hit_armour",
			push_radius = 3,
			range_mod = 1.35,
			range_mod_add = 0.5,
			sweep_z_offset = 0.1,
			total_time = 1.5,
			weapon_up_offset_mod = -0.25,
			width_mod = 30,
			anim_end_event_condition_func = function (unit, end_reason)
				return end_reason ~= "new_interupting_action" and end_reason ~= "action_complete"
			end,
			anim_time_scale = time_mod * 1,
			buff_data = {
				{
					buff_name = "planted_fast_decrease_movement",
					end_time = 0.3,
					external_multiplier = 1.75,
					start_time = 0,
				},
				{
					buff_name = "planted_fast_decrease_movement",
					end_time = 0.75,
					external_multiplier = 0.5,
					start_time = 0.3,
				},
			},
			allowed_chain_actions = {
				{
					action = "action_one",
					input = "action_one_hold",
					release_required = "action_two_hold",
					start_time = 0.45,
					sub_action = "default",
				},
				{
					action = "action_one",
					input = "action_one",
					release_required = "action_two_hold",
					start_time = 0.45,
					sub_action = "default",
				},
				{
					action = "action_two",
					input = "action_two_hold",
					start_time = 0.45,
					sub_action = "default",
				},
				{
					action = "action_wield",
					input = "action_wield",
					start_time = 0.45,
					sub_action = "default",
				},
			},
			enter_function = function (attacker_unit, input_extension)
				return input_extension:reset_release_input()
			end,
			hit_mass_count = TANK_HIT_MASS_COUNT,
			baked_sweep = {
				{
					0.15666666666666668,
					0.7791174650192261,
					0.0023984909057617188,
					-0.06520962715148926,
					-0.3119320869445801,
					-0.5508407354354858,
					0.25485214591026306,
					-0.7309741973876953,
				},
				{
					0.1811111111111111,
					0.7353841066360474,
					0.00592803955078125,
					-0.17639625072479248,
					-0.2673724889755249,
					-0.633711040019989,
					0.24208888411521912,
					-0.6843356490135193,
				},
				{
					0.20555555555555557,
					0.28557443618774414,
					0.8227014541625977,
					-0.1771775484085083,
					0.33348575234413147,
					-0.6347479224205017,
					-0.2453875094652176,
					-0.652431845664978,
				},
				{
					0.23,
					-0.2746642827987671,
					0.9351987838745117,
					-0.14795994758605957,
					-0.5022382736206055,
					0.44495585560798645,
					0.6266806721687317,
					0.3962857723236084,
				},
				{
					0.2544444444444445,
					-0.51859050989151,
					0.5645160675048828,
					-0.15850496292114258,
					-0.6075025200843811,
					0.27481767535209656,
					0.7233586311340332,
					0.17935532331466675,
				},
				{
					0.2788888888888889,
					-0.5451748967170715,
					0.14356422424316406,
					-0.1604752540588379,
					-0.6590734124183655,
					0.12081519514322281,
					0.7422080636024475,
					-0.012375323101878166,
				},
				{
					0.30333333333333334,
					-0.5448150038719177,
					0.032813072204589844,
					-0.17058002948760986,
					-0.680173397064209,
					0.08531393110752106,
					0.7268244624137878,
					-0.04256707429885864,
				},
			},
		},
		push = {
			anim_end_event = "attack_finished",
			anim_event = "attack_push",
			charge_value = "action_push",
			damage_profile_inner = "medium_push",
			damage_profile_outer = "light_push",
			damage_window_end = 0.2,
			damage_window_start = 0.05,
			dedicated_target_range = 2.8,
			hit_effect = "melee_hit_sword_1h",
			impact_sound_event = "slashing_hit",
			kind = "push_stagger",
			no_damage_impact_sound_event = "slashing_hit_armour",
			outer_push_angle = 180,
			push_angle = 100,
			total_time = 0.8,
			weapon_action_hand = "right",
			anim_end_event_condition_func = function (unit, end_reason)
				return end_reason ~= "new_interupting_action" and end_reason ~= "action_complete"
			end,
			buff_data = {
				{
					buff_name = "planted_decrease_movement",
					external_multiplier = 0.75,
					start_time = 0,
				},
			},
			allowed_chain_actions = {
				{
					action = "action_one",
					doubleclick_window = 0,
					input = "action_one",
					release_required = "action_two_hold",
					start_time = 0.25,
					sub_action = "default",
				},
				{
					action = "action_one",
					doubleclick_window = 0,
					input = "action_one_hold",
					release_required = "action_two_hold",
					start_time = 0.25,
					sub_action = "default",
				},
				{
					action = "action_one",
					doubleclick_window = 0,
					end_time = 0.8,
					input = "action_one_hold",
					start_time = 0.25,
					sub_action = "light_attack_bopp",
					hold_required = {
						"action_two_hold",
						"action_one_hold",
					},
				},
				{
					action = "action_two",
					input = "action_two_hold",
					start_time = 0.4,
					sub_action = "default",
				},
				{
					action = "action_wield",
					input = "action_wield",
					start_time = 0.4,
					sub_action = "default",
				},
			},
			push_radius = push_radius,
			chain_condition_func = function (attacker_unit, input_extension)
				local status_extension = ScriptUnit.extension(attacker_unit, "status_system")

				return not status_extension:fatigued()
			end,
		},
	},
	action_two = {
		default = {
			anim_end_event = "parry_finished",
			anim_event = "parry_pose",
			cooldown = 0.15,
			hold_input = "action_two_hold",
			kind = "block",
			minimum_hold_time = 0.2,
			anim_end_event_condition_func = function (unit, end_reason)
				return end_reason ~= "new_interupting_action"
			end,
			total_time = math.huge,
			enter_function = function (attacker_unit, input_extension, remaining_time)
				return input_extension:reset_release_input_with_delay(remaining_time)
			end,
			buff_data = {
				{
					buff_name = "planted_decrease_movement",
					external_multiplier = 0.8,
					start_time = 0,
				},
			},
			allowed_chain_actions = {
				{
					action = "action_wield",
					input = "action_wield",
					start_time = 0.2,
					sub_action = "default",
				},
				{
					action = "action_one",
					doubleclick_window = 0,
					input = "action_one",
					start_time = 0.2,
					sub_action = "push",
					hold_required = {
						"action_two_hold",
					},
				},
				{
					action = "action_one",
					doubleclick_window = 0,
					input = "action_one",
					release_required = "action_two_hold",
					start_time = 0.2,
					sub_action = "default",
				},
			},
		},
	},
	action_inspect = ActionTemplates.action_inspect,
	action_wield = ActionTemplates.wield,
}
weapon_template.right_hand_unit = "units/weapons/player/wpn_empire_short_sword/wpn_empire_short_sword"
weapon_template.right_hand_attachment_node_linking = AttachmentNodeLinking.polearm
weapon_template.display_unit = "units/weapons/weapon_display/display_2h_heavy_spears"
weapon_template.wield_anim = "to_polearm"
weapon_template.state_machine = "units/beings/player/first_person_base/state_machines/melee/polearm"
weapon_template.buff_type = "MELEE_2H"
weapon_template.weapon_type = "POLEARM"
weapon_template.max_fatigue_points = 8
weapon_template.dodge_count = 3
weapon_template.block_angle = 180
weapon_template.outer_block_angle = 360
weapon_template.block_fatigue_point_multiplier = 0.5
weapon_template.outer_block_fatigue_point_multiplier = 2
weapon_template.buffs = {
	change_dodge_distance = {
		external_optional_multiplier = 1,
	},
	change_dodge_speed = {
		external_optional_multiplier = 1,
	},
}
weapon_template.attack_meta_data = {
	tap_attack = {
		arc = 0,
	},
	hold_attack = {
		arc = 2,
	},
}
weapon_template.aim_assist_settings = {
	base_multiplier = 0,
	effective_max_range = 4,
	max_range = 5,
	no_aim_input_multiplier = 0,
	breed_scalars = {
		skaven_clan_rat = 0.5,
		skaven_slave = 0.5,
		skaven_storm_vermin = 1,
	},
}
weapon_template.weapon_diagram = {
	light_attack = {
		[DamageTypes.ARMOR_PIERCING] = 3,
		[DamageTypes.CLEAVE] = 2,
		[DamageTypes.SPEED] = 3,
		[DamageTypes.STAGGER] = 3,
		[DamageTypes.DAMAGE] = 4,
	},
	heavy_attack = {
		[DamageTypes.ARMOR_PIERCING] = 3,
		[DamageTypes.CLEAVE] = 4,
		[DamageTypes.SPEED] = 2,
		[DamageTypes.STAGGER] = 3,
		[DamageTypes.DAMAGE] = 4,
	},
}
weapon_template.tooltip_keywords = {
	"weapon_keyword_fast_attacks",
	"weapon_keyword_versatile",
	"weapon_keyword_high_agility",
}
weapon_template.tooltip_compare = {
	light = {
		action_name = "action_one",
		sub_action_name = "light_attack_left",
	},
	heavy = {
		action_name = "action_one",
		sub_action_name = "heavy_attack_left",
	},
}
weapon_template.tooltip_detail = {
	light = {
		action_name = "action_one",
		sub_action_name = "default",
	},
	heavy = {
		action_name = "action_one",
		sub_action_name = "default",
	},
	push = {
		action_name = "action_one",
		sub_action_name = "push",
	},
}
weapon_template.wwise_dep_right_hand = {
	"wwise/two_handed_axes",
}

return {
	two_handed_heavy_spears_template = weapon_template,
}
]====],
handgun_post_update = [====[
ActionHandgun.client_owner_post_update = function (self, dt, t, world, can_damage)
	local weapon_unit = self.weapon_unit
	local owner_unit = self.owner_unit
	local current_action = self.current_action

	if self.state == "waiting_to_shoot" and t >= self.time_to_shoot then
		self.state = "shooting"

		if self.ammo_extension and not self.extra_buff_shot and self.ammo_usage then
			local ammo_usage = self.ammo_usage

			self.ammo_extension:use_ammo(ammo_usage)
		end

		local overcharge_type = self.overcharge_type

		if overcharge_type then
			local overcharge_amount = PlayerUnitStatusSettings.overcharge_values[overcharge_type] * (self.charge_multiplier or 1)
			local buff_extension = ScriptUnit.extension(owner_unit, "buff_system")

			if self._is_critical_strike and buff_extension:has_buff_perk("no_overcharge_crit") then
				overcharge_amount = 0
			end

			self.overcharge_extension:add_charge(overcharge_amount)
		end

		if self.uses_ability_cooldown then
			self.career_extension:reduce_activated_ability_cooldown(-self.ammo_usage)
		end
	end

	if self.state == "shooting" then
		local add_spread = not self.extra_buff_shot

		if self:_update_extra_shots(self.owner_buff_extension, 1) then
			self.state = "waiting_to_shoot"
			self.time_to_shoot = t + 0.1
			self.extra_buff_shot = true
		else
			self.state = "shot"
		end

		if not Managers.player:owner(self.owner_unit).bot_player then
			Managers.state.controller_features:add_effect("rumble", {
				rumble_effect = "handgun_fire",
			})
		end

		local first_person_extension = ScriptUnit.extension(owner_unit, "first_person_system")
		local position, rotation = first_person_extension:get_projectile_start_position_rotation()

		if current_action.fire_at_gaze_setting and ScriptUnit.has_extension(owner_unit, "eyetracking_system") then
			local eyetracking_extension = ScriptUnit.extension(owner_unit, "eyetracking_system")

			if eyetracking_extension:get_is_feature_enabled("tobii_fire_at_gaze") then
				rotation = eyetracking_extension:gaze_rotation()
			end
		end

		local spread_extension = self.spread_extension

		if spread_extension then
			rotation = spread_extension:get_randomised_spread(rotation)

			if add_spread then
				spread_extension:set_shooting()
			end
		end

		local physics_world = World.get_data(world, "physics_world")
		local auto_hit_chance = current_action.aim_assist_auto_hit_chance or 0
		local direction

		if auto_hit_chance >= math.random() and Managers.input:is_device_active("gamepad") and ScriptUnit.has_extension(owner_unit, "smart_targeting_system") then
			local targeting_extension = ScriptUnit.extension(owner_unit, "smart_targeting_system")
			local targeting_data = targeting_extension:get_targeting_data()
			local target_position = targeting_data.target_position

			if target_position then
				direction = Vector3.normalize(target_position - position)
			end
		end

		direction = direction or Quaternion.forward(rotation)

		local result

		if current_action.projectile_info then
			local angle = ActionUtils.pitch_from_rotation(rotation)
			local speed = current_action.speed
			local target_vector = Vector3.normalize(Vector3.flat(Quaternion.forward(rotation)))
			local lookup_data = current_action.lookup_data

			ActionUtils.spawn_player_projectile(owner_unit, position, rotation, 0, angle, target_vector, speed, self.item_name, lookup_data.item_template_name, lookup_data.action_name, lookup_data.sub_action_name, self._is_critical_strike, self.power_level)
		else
			if current_action.ray_against_large_hitbox then
				result = PhysicsWorld.immediate_raycast_actors(physics_world, position, direction, "static_collision_filter", "filter_player_ray_projectile_static_only", "dynamic_collision_filter", "filter_player_ray_projectile_ai_only", "dynamic_collision_filter", "filter_player_ray_projectile_hitbox_only", "dynamic_collision_filter", "filter_enemy_trigger")
			else
				result = PhysicsWorld.immediate_raycast_actors(physics_world, position, direction, "static_collision_filter", "filter_player_ray_projectile_static_only", "dynamic_collision_filter", "filter_player_ray_projectile_ai_only", "dynamic_collision_filter", "filter_player_ray_projectile_hitbox_only")
			end

			local is_server = self.is_server

			if result then
				DamageUtils.process_projectile_hit(world, self.item_name, owner_unit, is_server, result, current_action, direction, true, nil, nil, self._is_critical_strike, self.power_level)
			end
		end

		if self.current_action.reset_aim_on_attack then
			first_person_extension:reset_aim_assist_multiplier()
		end

		local fire_sound_event = self.current_action.fire_sound_event

		if fire_sound_event then
			first_person_extension:play_hud_sound_event(fire_sound_event)
		end

		if current_action.alert_sound_range_fire then
			Managers.state.entity:system("ai_system"):alert_enemies_within_range(owner_unit, POSITION_LOOKUP[owner_unit], current_action.alert_sound_range_fire)
		end

		local hit_position = result and result[#result][1] or position + direction * 100

		Unit.set_flow_variable(weapon_unit, "hit_position", hit_position)
		Unit.set_flow_variable(weapon_unit, "trail_life", Vector3.length(hit_position - position) * 0.1)
		Unit.flow_event(weapon_unit, "lua_bullet_trail")
		Unit.flow_event(weapon_unit, "lua_bullet_trail_set")
	end

	if self.state == "shot" and self.active_reload_time then
		local input_extension = ScriptUnit.extension(owner_unit, "input_system")

		if t > self.active_reload_time then
			local ammo_extension = self.ammo_extension

			if (input_extension:get("weapon_reload") or input_extension:get_buffer("weapon_reload")) and ammo_extension:can_reload() then
				local status_extension = ScriptUnit.extension(owner_unit, "status_system")

				status_extension:set_zooming(false)

				local weapon_extension = ScriptUnit.extension(weapon_unit, "weapon_system")

				weapon_extension:stop_action("reload")
			end
		elseif input_extension:get("weapon_reload") then
			input_extension:add_buffer("weapon_reload", 0)
		end
	end
end
]====],
resolved_profiles = {["heavy_slashing_smiter_stab_polearm"]={["armor_modifier"]={["attack"]={[1]=1,[2]=0.29999999999999999,[3]=2,[4]=1,[5]=0.75},["impact"]={[1]=1,[2]=0.5,[3]=1,[4]=1,[5]=0.75}},["charge_value"]="heavy_attack",["cleave_distribution"]={["attack"]=0.074999999999999997,["impact"]=0.074999999999999997},["critical_strike"]={["attack_armor_power_modifer"]={[1]=1,[2]=0.5,[3]=2.5,[4]=1,[5]=1},["impact_armor_power_modifer"]={[1]=1,[2]=1,[3]=1,[4]=1,[5]=1}},["default_target"]={["attack_template"]="heavy_stab_smiter",["boost_curve_coefficient"]=0.75,["boost_curve_coefficient_headshot"]=1,["boost_curve_type"]="ninja_curve",["power_distribution"]={["attack"]=0.20000000000000001,["impact"]=0.14999999999999999}},["melee_boost_override"]=2.5,["targets"]={[1]={["armor_modifier"]={["attack"]={[1]=1,[2]=0.45000000000000001,[3]=2,[4]=1,[5]=0.75},["impact"]={[1]=1,[2]=0.65000000000000002,[3]=1,[4]=1,[5]=0.75}},["attack_template"]="heavy_stab_smiter",["boost_curve_coefficient"]=0.75,["boost_curve_coefficient_headshot"]=2,["boost_curve_type"]="ninja_curve",["power_distribution"]={["attack"]=0.45000000000000001,["impact"]=0.25}}}},["heavy_slashing_tank"]={["armor_modifier"]={["attack"]={[1]=1,[2]=0,[3]=1.5,[4]=1,[5]=0.75},["impact"]={[1]=1,[2]=1,[3]=1,[4]=1,[5]=0.75}},["charge_value"]="heavy_attack",["cleave_distribution"]={["attack"]=0.29999999999999999,["impact"]=0.80000000000000004},["critical_strike"]={["attack_armor_power_modifer"]={[1]=1,[2]=0.59999999999999998,[3]=2,[4]=1,[5]=1},["impact_armor_power_modifer"]={[1]=1,[2]=1,[3]=1,[4]=1,[5]=1}},["default_target"]={["attack_template"]="heavy_slashing_tank",["boost_curve_type"]="tank_curve",["power_distribution"]={["attack"]=0.050000000000000003,["impact"]=0.125}},["stagger_duration_modifier"]=1.8,["targets"]={[1]={["armor_modifier"]={["attack"]={[1]=1,[2]=0.5,[3]=2,[4]=1,[5]=0.75},["impact"]={[1]=1.5,[2]=1,[3]=1,[4]=1,[5]=0.75}},["attack_template"]="slashing_tank",["boost_curve_type"]="tank_curve",["power_distribution"]={["attack"]=0.27500000000000002,["impact"]=0.29999999999999999}},[2]={["attack_template"]="slashing_tank",["boost_curve_type"]="tank_curve",["power_distribution"]={["attack"]=0.14999999999999999,["impact"]=0.22500000000000001}},[3]={["attack_template"]="light_slashing_tank",["boost_curve_type"]="tank_curve",["power_distribution"]={["attack"]=0.074999999999999997,["impact"]=0.20000000000000001}}}},["medium_slashing_linesman_spear"]={["armor_modifier"]={["attack"]={[1]=1,[2]=0,[3]=2,[4]=1,[5]=1},["impact"]={[1]=1,[2]=0.29999999999999999,[3]=0.5,[4]=1,[5]=1}},["charge_value"]="light_attack",["cleave_distribution"]={["attack"]=0.34999999999999998,["impact"]=0.20000000000000001},["critical_strike"]={["attack_armor_power_modifer"]={[1]=1,[2]=0.5,[3]=2.5,[4]=1,[5]=1},["impact_armor_power_modifer"]={[1]=1,[2]=0.5,[3]=0.5,[4]=1,[5]=1}},["default_target"]={["attack_template"]="light_slashing_linesman",["boost_curve_type"]="linesman_curve",["power_distribution"]={["attack"]=0.074999999999999997,["impact"]=0.050000000000000003}},["targets"]={[1]={["attack_template"]="slashing_linesman",["boost_curve_coefficient_headshot"]=4,["boost_curve_type"]="linesman_curve",["power_distribution"]={["attack"]=0.17499999999999999,["impact"]=0.20000000000000001}},[2]={["attack_template"]="slashing_linesman",["boost_curve_coefficient_headshot"]=3,["boost_curve_type"]="linesman_curve",["power_distribution"]={["attack"]=0.125,["impact"]=0.17499999999999999}},[3]={["attack_template"]="light_slashing_linesman",["boost_curve_coefficient_headshot"]=2.5,["boost_curve_type"]="linesman_curve",["power_distribution"]={["attack"]=0.10000000000000001,["impact"]=0.10000000000000001}}}},["medium_spear_smiter_stab"]={["armor_modifier"]={["attack"]={[1]=1,[2]=0.25,[3]=2.25,[4]=1,[5]=0.75},["impact"]={[1]=1,[2]=0.75,[3]=1,[4]=1,[5]=0.75}},["charge_value"]="heavy_attack",["cleave_distribution"]={["attack"]=0.074999999999999997,["impact"]=0.074999999999999997},["critical_strike"]={["attack_armor_power_modifer"]={[1]=1,[2]=0.40000000000000002,[3]=2.5,[4]=1,[5]=1},["impact_armor_power_modifer"]={[1]=1,[2]=1,[3]=1,[4]=1,[5]=1}},["default_target"]={["attack_template"]="stab_smiter",["boost_curve_coefficient"]=1,["boost_curve_coefficient_headshot"]=1.5,["boost_curve_type"]="ninja_curve",["power_distribution"]={["attack"]=0.25,["impact"]=0.25}},["melee_boost_override"]=2.5,["targets"]={}}},
}
