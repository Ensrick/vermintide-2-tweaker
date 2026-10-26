-- Exact source snapshots: game6.13.0 93dea911; prior balance = reviewed WT55.
return {
clone = [====[
table.clone = function (t, skip_metatable)
	local clone = {}

	if not skip_metatable then
		local mt = getmetatable(t)

		assert(mt == nil or mt.__mt_cloneable, "Metatables will be sliced off")
	end

	for key, value in pairs(t) do
		if type(value) ~= "table" or is_class_instance(value) then
			clone[key] = value
		else
			clone[key] = table.clone(value, skip_metatable)
		end
	end

	return clone
end
]====],
is_class_instance = [====[
function is_class_instance(object)
	if type(object) ~= "table" then
		return false
	end

	local metatable = getmetatable(object)

	if metatable == nil then
		return false
	end

	return rawget(metatable, "___is_class_metatable___") == true
end]====],
donor = [====[
local sniper_dropoff_ranges = {
	dropoff_end = 50,
	dropoff_start = 30,
}
DamageProfileTemplates.shot_sniper = {
	charge_value = "instant_projectile",
	no_stagger_damage_reduction_ranged = true,
	shield_break = true,
	critical_strike = {
		attack_armor_power_modifer = {
			1,
			1.4,
			1.5,
			1,
			0.75,
			0.6,
		},
		impact_armor_power_modifer = {
			1,
			1,
			1,
			1,
			1,
			1,
		},
	},
	armor_modifier_near = {
		attack = {
			1,
			1.2,
			1.5,
			1,
			0.75,
			0.5,
		},
		impact = {
			1,
			1,
			1,
			1,
			1,
			1,
		},
	},
	armor_modifier_far = {
		attack = {
			1,
			1,
			1,
			1,
			0.75,
			0.25,
		},
		impact = {
			1,
			1,
			1,
			1,
			1,
			0.75,
		},
	},
	cleave_distribution = {
		attack = 0.3,
		impact = 0.3,
	},
	default_target = {
		attack_template = "shot_sniper",
		boost_curve_coefficient = 1,
		boost_curve_coefficient_headshot = 1,
		boost_curve_type = "smiter_curve",
		headshot_boost_boss = 0.5,
		power_distribution_near = {
			attack = 1,
			impact = 0.5,
		},
		power_distribution_far = {
			attack = 0.8,
			impact = 0.5,
		},
		range_modifier_settings = sniper_dropoff_ranges,
	},
}]====],
brace = [====[
-- chunkname: @scripts/settings/equipment/weapon_templates/brace_of_pistols.lua

local weapon_template = {}

weapon_template.actions = {
	action_one = {
		default = {
			aim_assist_auto_hit_chance = 0.5,
			aim_assist_max_ramp_multiplier = 0.3,
			aim_assist_ramp_decay_delay = 0.2,
			aim_assist_ramp_multiplier = 0.1,
			alert_sound_range_fire = 12,
			alert_sound_range_hit = 2,
			ammo_usage = 1,
			anim_event = "attack_shoot",
			anim_event_secondary = "reload",
			apply_recoil = true,
			charge_value = "bullet_hit",
			fire_time = 0,
			headshot_multiplier = 2,
			hit_effect = "bullet_impact",
			kind = "handgun",
			range = 100,
			reload_time = 0.1,
			reload_when_out_of_ammo = true,
			speed = 16000,
			total_time = 1,
			total_time_secondary = 2,
			allowed_chain_actions = {
				{
					action = "action_wield",
					input = "action_wield",
					start_time = 0.4,
					sub_action = "default",
				},
				{
					action = "action_one",
					chain_ready_sound = "weapon_gun_ready",
					input = "action_one",
					release_required = "action_one_hold",
					sound_time_offset = -0.05,
					start_time = 0.75,
					sub_action = "default",
				},
				{
					action = "action_one",
					input = "action_one_hold",
					start_time = 0.75,
					sub_action = "default",
				},
				{
					action = "action_two",
					input = "action_two_hold",
					start_time = 0.4,
					sub_action = "default",
				},
				{
					action = "weapon_reload",
					input = "weapon_reload",
					start_time = 0.75,
					sub_action = "default",
				},
				{
					action = "action_three",
					input = "action_three",
					start_time = 0.6,
					sub_action = "default",
				},
				{
					action = "weapon_reload",
					auto_chain = true,
					start_time = 0.8,
					sub_action = "auto_reload",
				},
			},
			enter_function = function (attacker_unit, input_extension)
				input_extension:clear_input_buffer()

				return input_extension:reset_release_input()
			end,
			projectile_info = Projectiles.pistol_shot,
			impact_data = {
				damage_profile = "shot_carbine",
			},
			recoil_settings = {
				climb_duration = 0.1,
				horizontal_climb = 0,
				restore_duration = 0.25,
				vertical_climb = 2,
				climb_function = math.easeInCubic,
				restore_function = math.ease_out_quad,
			},
		},
		fast_shot = {
			aim_assist_auto_hit_chance = 0.75,
			aim_assist_max_ramp_multiplier = 0.3,
			aim_assist_ramp_decay_delay = 0.1,
			aim_assist_ramp_multiplier = 0.05,
			alert_sound_range_fire = 12,
			alert_sound_range_hit = 2,
			ammo_usage = 1,
			anim_event = "attack_shoot_fast",
			apply_recoil = true,
			charge_value = "bullet_hit",
			fire_time = 0,
			headshot_multiplier = 2,
			hit_effect = "bullet_impact",
			hold_input = "action_two_hold",
			kind = "handgun",
			minimum_hold_time = 0.2,
			range = 100,
			reload_time = 0.1,
			reload_when_out_of_ammo = true,
			speed = 16000,
			spread_template_override = "pistol_special",
			total_time = 1,
			buff_data = {
				{
					buff_name = "planted_fast_decrease_movement",
					external_multiplier = 0.85,
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
					chain_ready_sound = "weapon_gun_ready",
					input = "action_one",
					release_required = "action_one_hold",
					sound_time_offset = -0.05,
					start_time = 0.25,
					sub_action = "fast_shot",
				},
				{
					action = "action_one",
					input = "action_one_hold",
					start_time = 0.25,
					sub_action = "fast_shot",
				},
				{
					action = "weapon_reload",
					input = "weapon_reload",
					start_time = 0.2,
					sub_action = "default",
				},
				{
					blocker = true,
					input = "action_two_hold",
					start_time = 0,
				},
				{
					action = "weapon_reload",
					auto_chain = true,
					start_time = 0,
					sub_action = "auto_reload",
				},
			},
			enter_function = function (attacker_unit, input_extension)
				input_extension:clear_input_buffer()

				return input_extension:reset_release_input()
			end,
			projectile_info = Projectiles.pistol_shot,
			impact_data = {
				damage_profile = "shot_carbine",
			},
			recoil_settings = {
				climb_duration = 0.1,
				horizontal_climb = 0,
				restore_duration = 0.25,
				vertical_climb = 2,
				climb_function = math.easeInCubic,
				restore_function = math.ease_out_quad,
			},
		},
		special_action_shoot = {
			aim_assist_auto_hit_chance = 0.5,
			aim_assist_max_ramp_multiplier = 0.3,
			aim_assist_ramp_decay_delay = 0.2,
			aim_assist_ramp_multiplier = 0.1,
			alert_sound_range_fire = 12,
			alert_sound_range_hit = 2,
			ammo_usage = 1,
			anim_event = "attack_shoot",
			anim_event_secondary = "reload",
			apply_recoil = true,
			charge_value = "bullet_hit",
			fire_time = 0,
			headshot_multiplier = 2,
			hit_effect = "bullet_impact",
			kind = "handgun",
			range = 100,
			reload_time = 0.1,
			reload_when_out_of_ammo = true,
			speed = 16000,
			total_time = 1,
			total_time_secondary = 2,
			allowed_chain_actions = {
				{
					action = "action_wield",
					input = "action_wield",
					start_time = 0.4,
					sub_action = "default",
				},
				{
					action = "action_one",
					chain_ready_sound = "weapon_gun_ready",
					input = "action_one",
					release_required = "action_one_hold",
					sound_time_offset = -0.05,
					start_time = 0.75,
					sub_action = "default",
				},
				{
					action = "action_one",
					input = "action_one_hold",
					start_time = 0.75,
					sub_action = "default",
				},
				{
					action = "action_two",
					input = "action_two_hold",
					start_time = 0.4,
					sub_action = "default",
				},
				{
					action = "weapon_reload",
					input = "weapon_reload",
					start_time = 0.75,
					sub_action = "default",
				},
				{
					action = "action_three",
					input = "action_three",
					start_time = 0.6,
					sub_action = "default",
				},
				{
					action = "weapon_reload",
					auto_chain = true,
					start_time = 0.8,
					sub_action = "auto_reload",
				},
			},
			enter_function = function (attacker_unit, input_extension)
				input_extension:clear_input_buffer()

				return input_extension:reset_release_input()
			end,
			projectile_info = Projectiles.pistol_shot,
			impact_data = {
				damage_profile = "shot_carbine",
			},
			recoil_settings = {
				climb_duration = 0.1,
				horizontal_climb = 0,
				restore_duration = 0.25,
				vertical_climb = 2,
				climb_function = math.easeInCubic,
				restore_function = math.ease_out_quad,
			},
		},
	},
	action_two = {
		default = {
			allow_hold_toggle = true,
			ammo_requirement = 1,
			anim_end_event = "attack_finished",
			anim_event = "lock_target",
			can_abort_reload = true,
			hold_input = "action_two_hold",
			kind = "dummy",
			minimum_hold_time = 0.2,
			spread_template_override = "pistol_special",
			anim_end_event_condition_func = function (unit, end_reason)
				return end_reason ~= "new_interupting_action"
			end,
			total_time = math.huge,
			buff_data = {
				{
					buff_name = "planted_fast_decrease_movement",
					external_multiplier = 0.85,
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
					start_time = 0,
					sub_action = "fast_shot",
				},
				{
					action = "action_one",
					input = "action_one_hold",
					start_time = 0.25,
					sub_action = "fast_shot",
				},
				{
					action = "weapon_reload",
					input = "weapon_reload",
					start_time = 0,
					sub_action = "default",
				},
				{
					blocker = true,
					input = "action_two_hold",
					start_time = 0,
				},
				{
					action = "weapon_reload",
					auto_chain = true,
					start_time = 0,
					sub_action = "auto_reload",
				},
			},
			condition_func = function (unit, input_extension, ammo_extension)
				if ammo_extension and ammo_extension:total_remaining_ammo() <= 0 then
					return false
				end

				return true
			end,
		},
	},
	action_three = {
		default = {
			ammo_requirement = 1,
			anim_end_event = "attack_finished",
			anim_event = "special_action",
			can_abort_reload = true,
			kind = "dummy",
			total_time = 1.71,
			anim_end_event_condition_func = function (unit, end_reason)
				return end_reason ~= "new_interupting_action"
			end,
			allowed_chain_actions = {
				{
					action = "action_wield",
					input = "action_wield",
					start_time = 0.4,
					sub_action = "default",
				},
				{
					action = "action_one",
					end_time = 1.68,
					input = "action_one",
					release_required = "action_one_hold",
					start_time = 0.75,
					sub_action = "special_action_shoot",
				},
				{
					action = "action_one",
					end_time = 1.68,
					input = "action_one_hold",
					start_time = 0.75,
					sub_action = "special_action_shoot",
				},
				{
					action = "action_one",
					input = "action_one",
					release_required = "action_one_hold",
					start_time = 1.7,
					sub_action = "default",
				},
				{
					action = "action_two",
					input = "action_two_hold",
					start_time = 0.4,
					sub_action = "default",
				},
				{
					action = "weapon_reload",
					input = "weapon_reload",
					start_time = 0.75,
					sub_action = "default",
				},
				{
					action = "action_three",
					input = "action_three",
					start_time = 0.8,
					sub_action = "default",
				},
			},
			condition_func = function (unit, input_extension, ammo_extension)
				if ammo_extension and ammo_extension:total_remaining_ammo() <= 0 then
					return false
				end

				return true
			end,
		},
	},
	weapon_reload = {
		default = {
			kind = "reload",
			total_time = 0,
			weapon_action_hand = "either",
			condition_func = function (action_user, input_extension)
				local inventory_extension = ScriptUnit.extension(action_user, "inventory_system")
				local status_extension = ScriptUnit.extension(action_user, "status_system")
				local ammo_extension
				local zooming = status_extension:is_zooming()

				if zooming then
					return false
				end

				local equipment = inventory_extension:equipment()

				if equipment.right_hand_wielded_unit ~= nil and ScriptUnit.has_extension(equipment.right_hand_wielded_unit, "ammo_system") then
					ammo_extension = ScriptUnit.extension(equipment.right_hand_wielded_unit, "ammo_system")
				elseif equipment.left_hand_wielded_unit ~= nil and ScriptUnit.has_extension(equipment.left_hand_wielded_unit, "ammo_system") then
					ammo_extension = ScriptUnit.extension(equipment.left_hand_wielded_unit, "ammo_system")
				end

				return ammo_extension and ammo_extension:can_reload()
			end,
			chain_condition_func = function (action_user, input_extension)
				local inventory_extension = ScriptUnit.extension(action_user, "inventory_system")
				local status_extension = ScriptUnit.extension(action_user, "status_system")
				local ammo_extension
				local zooming = status_extension:is_zooming()

				if zooming then
					return false
				end

				local equipment = inventory_extension:equipment()

				if equipment.right_hand_wielded_unit ~= nil and ScriptUnit.has_extension(equipment.right_hand_wielded_unit, "ammo_system") then
					ammo_extension = ScriptUnit.extension(equipment.right_hand_wielded_unit, "ammo_system")
				elseif equipment.left_hand_wielded_unit ~= nil and ScriptUnit.has_extension(equipment.left_hand_wielded_unit, "ammo_system") then
					ammo_extension = ScriptUnit.extension(equipment.left_hand_wielded_unit, "ammo_system")
				end

				return ammo_extension and ammo_extension:can_reload()
			end,
			allowed_chain_actions = {},
		},
		auto_reload = {
			kind = "reload",
			total_time = 0,
			weapon_action_hand = "either",
			condition_func = function (action_user, input_extension)
				local inventory_extension = ScriptUnit.extension(action_user, "inventory_system")
				local status_extension = ScriptUnit.extension(action_user, "status_system")
				local ammo_extension
				local zooming = status_extension:is_zooming()

				if zooming then
					return false
				end

				local equipment = inventory_extension:equipment()

				if equipment.right_hand_wielded_unit ~= nil and ScriptUnit.has_extension(equipment.right_hand_wielded_unit, "ammo_system") then
					ammo_extension = ScriptUnit.extension(equipment.right_hand_wielded_unit, "ammo_system")
				elseif equipment.left_hand_wielded_unit ~= nil and ScriptUnit.has_extension(equipment.left_hand_wielded_unit, "ammo_system") then
					ammo_extension = ScriptUnit.extension(equipment.left_hand_wielded_unit, "ammo_system")
				end

				return ammo_extension and ammo_extension:ammo_count() == 0 and ammo_extension:can_reload()
			end,
			chain_condition_func = function (action_user, input_extension)
				local inventory_extension = ScriptUnit.extension(action_user, "inventory_system")
				local status_extension = ScriptUnit.extension(action_user, "status_system")
				local ammo_extension
				local zooming = status_extension:is_zooming()

				if zooming then
					return false
				end

				local equipment = inventory_extension:equipment()

				if equipment.right_hand_wielded_unit ~= nil and ScriptUnit.has_extension(equipment.right_hand_wielded_unit, "ammo_system") then
					ammo_extension = ScriptUnit.extension(equipment.right_hand_wielded_unit, "ammo_system")
				elseif equipment.left_hand_wielded_unit ~= nil and ScriptUnit.has_extension(equipment.left_hand_wielded_unit, "ammo_system") then
					ammo_extension = ScriptUnit.extension(equipment.left_hand_wielded_unit, "ammo_system")
				end

				return ammo_extension and ammo_extension:ammo_count() == 0 and ammo_extension:can_reload()
			end,
			allowed_chain_actions = {},
		},
	},
	action_inspect = ActionTemplates.action_inspect,
	action_wield = ActionTemplates.wield,
}
weapon_template.action_on_wield = {
	action = "weapon_reload",
	sub_action = "default",
}
weapon_template.ammo_data = {
	ammo_hand = "right",
	ammo_per_clip = 12,
	ammo_per_reload = 2,
	max_ammo = 30,
	play_reload_anim_on_wield_reload = true,
	reload_on_ammo_pickup = true,
	reload_time = 1,
}
weapon_template.attack_meta_data = {
	aim_at_node = "j_head",
	can_charge_shot = false,
	effective_against = bit.bor(BreedCategory.Berserker, BreedCategory.Special, BreedCategory.Armored),
}
weapon_template.default_spread_template = "brace_of_pistols"
weapon_template.spread_lerp_speed = 5
weapon_template.right_hand_unit = ""
weapon_template.right_hand_attachment_node_linking = AttachmentNodeLinking.pistol.right
weapon_template.left_hand_unit = ""
weapon_template.left_hand_attachment_node_linking = AttachmentNodeLinking.pistol.left
weapon_template.display_unit = "units/weapons/weapon_display/display_pistols"
weapon_template.wield_anim = "to_dual_pistol"
weapon_template.state_machine = "units/beings/player/first_person_base/state_machines/ranged/dual_pistol"
weapon_template.reload_event = "reload"
weapon_template.crosshair_style = "default"
weapon_template.gui_texture = "hud_weapon_icon_repeating_handgun"
weapon_template.buff_type = "RANGED"
weapon_template.weapon_type = "BRACE_OF_PISTOLS"
weapon_template.dodge_count = 100
weapon_template.buffs = {
	change_dodge_distance = {
		external_optional_multiplier = 1.25,
	},
	change_dodge_speed = {
		external_optional_multiplier = 1.25,
	},
}
weapon_template.aim_assist_settings = {
	aim_at_node = "j_spine",
	always_auto_aim = true,
	base_multiplier = 0.15,
	effective_max_range = 10,
	max_range = 22,
	no_aim_input_multiplier = 0,
	breed_scalars = {
		skaven_clan_rat = 1,
		skaven_slave = 1,
		skaven_storm_vermin = 0.25,
	},
}
weapon_template.wwise_dep_right_hand = {
	"wwise/pistol",
}
weapon_template.wwise_dep_left_hand = {
	"wwise/pistol",
}
weapon_template.weapon_diagram = {
	light_attack = {
		[DamageTypes.ARMOR_PIERCING] = 5,
		[DamageTypes.CLEAVE] = 2,
		[DamageTypes.SPEED] = 4,
		[DamageTypes.STAGGER] = 2,
		[DamageTypes.DAMAGE] = 5,
	},
	heavy_attack = {
		[DamageTypes.ARMOR_PIERCING] = 5,
		[DamageTypes.CLEAVE] = 1,
		[DamageTypes.SPEED] = 6,
		[DamageTypes.STAGGER] = 2,
		[DamageTypes.DAMAGE] = 6,
	},
}
weapon_template.tooltip_keywords = {
	"weapon_keyword_high_damage",
	"weapon_keyword_rapid_fire",
	"weapon_keyword_versatile",
}
weapon_template.tooltip_compare = {
	light = {
		action_name = "action_one",
		sub_action_name = "default",
	},
	heavy = {
		action_name = "action_one",
		sub_action_name = "fast_shot",
	},
}
weapon_template.tooltip_detail = {
	light = {
		action_name = "action_one",
		sub_action_name = "default",
	},
	heavy = {
		action_name = "action_one",
		sub_action_name = "fast_shot",
	},
}
weapon_template.tooltip_special_action_description = "special_action_brace_of_pistols"

return {
	brace_of_pistols_template_1 = table.clone(weapon_template),
}
]====],
prior_balance = [====[
-- Toggle-gated weapon rebalance owner (#1159).
--
-- Extracted verbatim from the entry: the Authentic Brace of Pistols override,
-- the issue #348 Kruber Empire one-handed sword push-combo revert, and the
-- Warrior Priest greathammer punch buff. Each rewrites a vanilla Weapons.*
-- template in place at load behind its own VMF checkbox, and two of them
-- register a cloned damage profile.
--
-- The entry keeps a bare dofile at the former execution position, and that
-- position is load-bearing: wt_authentic_pistol and wt_priest_punch_buffed
-- append to NetworkLookup.damage_profiles, so their append ORDER (after
-- _wt_brett_sword_shield_buff's clone, before the axe-balance clones near the
-- end of the entry) is the process-local index every wt peer must agree on.
-- Moving the dofile would renumber the wire - BUG_CLASSES 64.
--
-- Both clones stay registered even with their toggle OFF (PROJECT_STANDARDS
-- 9.3 gated-registration divergence) and record a wire-safe vanilla fallback
-- for the issue-431 send floor; only the template repoint is toggle-gated.
-- The Priest punch tail now commits its profile/lookup/fallback atomically
-- through _wt_priest_punch_owner at the same registration position (#428).
-- Offline evidence: qa/lua/tests/test_wt_template_patch_owners.lua.

local mod = get_mod("wt")

-- Late-binding accessor: the entry's file-scope _dbg does not cross the chunk
-- boundary; mod._wt.dbg is the same function it published far above this
-- module's load position.
local _dbg = mod._wt.dbg

-- ============================================================
-- Authentic Brace of Pistols — toggleable flintlock-style override
-- ============================================================
-- Patches `Weapons.brace_of_pistols_template_1` in place when the
-- `authentic_brace_of_pistols` VMF setting is ON at mod init. Five
-- changes, all toggleable via the one setting:
--
--   1. Damage: every firing sub-action's `impact_data.damage_profile`
--      switches from `shot_carbine` (vanilla brace) to a clone of
--      `shot_sniper` (Kruber's handgun) with the near→far dropoff
--      flattened AND cleave_distribution halved (≈2x penetration:
--      from ~3 targets → ~6). Plus `ignore_shield_hit = true` on the
--      sub-action, which is what lets the handgun ignore shields.
--      Combined effect: armor-piercing, shield-breaking, full damage at
--      all ranges, passes through ~6 enemies.
--   2. Right-click is left vanilla. Lock-target / fast_shot rapid-fire
--      kept intact. (Previous revisions tried to disable or replace it
--      with a handgun-style zoom — both reverted in v0.12.15 because
--      rapid fire was reachable via paths we couldn't fully exorcise.
--      v0.12.19-v0.12.21 instead make secondary fire deliberately less
--      accurate than primary — see step 5. Speed was slowed in v0.12.19
--      then brought back to vanilla in v0.12.21 — see step 7.)
--   3. Manual reload re-enabled (v0.12.19). User wants single-shot
--      manual reload back; `weapon_reload.default` condition_funcs are
--      left vanilla. `auto_reload` chain is unchanged.
--   4. Ammo: `ammo_per_clip = 6`, `ammo_per_reload = 1`, `max_ammo = 12`.
--      Six rounds in the mag, six rounds in reserve, reloads one shot at
--      a time. (Vanilla: clip 12 / reload 2 / max 30. v0.12.16-v0.12.18:
--      clip 12 / reload 12 / max 12, no-reserve.) Each manual reload
--      animation loads one round; player can keep tapping R to top up
--      the clip one round at a time, can interrupt with a shot. Matches
--      a flintlock-pistol-bandolier feel.
--   6. (Removed in v0.12.15) fast_shot chain rewrite. Reverted along with
--      step 2; rapid fire is allowed.
--   7. Action speed: PRIMARY/all-other actions run at 2x speed (mult 0.5);
--      SECONDARY FIRE (`action_one.fast_shot` rapid-fire cadence) runs at
--      VANILLA speed (mult 1.0 — was 2.0 in v0.12.19-v0.12.20; user asked
--      to double it in v0.12.21). Chain-into-fast_shot start_times from
--      any source action also use the slow mult, so entering rapid fire
--      from RMB now takes the vanilla delay. Walks `tpl.actions[*][*]`
--      and scales `total_time`, `total_time_secondary`, `fire_time`,
--      `minimum_hold_time`, `cooldown`, `reload_time`, and every chain
--      `start_time`. 0/math.huge are skipped. The split walker is kept
--      even though mult=1.0 is a no-op, so future re-tunes (1.3, 1.5,
--      etc.) don't need a rewrite.
--   5. Spread: dramatically less accurate, with secondary fire MUCH
--      more inaccurate than primary. Default brace spread cloned +
--      widened by `_AUTHENTIC_BRACE_PRIMARY_SPREAD_MULT` (2.0);
--      `pistol_special` spread (used by RMB lock-target AND rapid-fire
--      shots) cloned + widened by `_AUTHENTIC_BRACE_SECONDARY_SPREAD_MULT`
--      (9.0 = 4.5× the primary multiplier). Primary clone is set as
--      `default_spread_template`; secondary clone overrides
--      `spread_template_override` on EVERY sub-action of every action
--      that pointed to `pistol_special` (action_two.default lock-target
--      and action_one.[default|fast_shot|special_action_shoot]). The
--      walk over every action — instead of only action_one — is what
--      makes the reticle jump to the full wide size the moment RMB is
--      pressed, instead of the prior two-step "RMB jump to vanilla
--      pistol_special, then LMB jump to wider clone".
--
-- All five patches are template-level globals so the change applies
-- to every wielder (Saltzpyre native + Kruber via WT cross-access).
-- A restart is required to toggle off because the in-place patches
-- can't be cleanly reverted without snapshotting + restoring vanilla.

local function _wt_clone_shot_sniper_no_dropoff()
    if not DamageProfileTemplates then return nil end
    local source = DamageProfileTemplates.shot_sniper
    if not source then return nil end
    local key = "wt_authentic_pistol"
    if DamageProfileTemplates[key] then return key end

    local clone = table.clone(source, true)

    -- Flatten near/far dropoff: mirror near values to far so range no
    -- longer reduces damage. shot_sniper has separate `armor_modifier_near`
    -- vs `armor_modifier_far` and per-target `power_distribution_near`
    -- vs `power_distribution_far`.
    if clone.armor_modifier_near then
        clone.armor_modifier_far = table.clone(clone.armor_modifier_near, true)
    end
    if clone.default_target then
        if clone.default_target.power_distribution_near then
            clone.default_target.power_distribution_far = table.clone(clone.default_target.power_distribution_near, true)
        end
        -- range_modifier_settings is the curve that interpolates between
        -- near and far. With both endpoints equal we don't strictly need
        -- to remove it, but clearing it makes the no-dropoff intent
        -- explicit.
        clone.default_target.range_modifier_settings = nil
    end

    -- Double penetration. `cleave_distribution.attack` / `.impact` is the
    -- fraction of cleave power consumed per target hit; halving each value
    -- lets projectiles pass through ~2x as many enemies before running
    -- out of cleave. shot_sniper vanilla is 0.3/0.3 (≈3 targets);
    -- wt_authentic_pistol becomes 0.15/0.15 (≈6 targets).
    if clone.cleave_distribution then
        if type(clone.cleave_distribution.attack) == "number" then
            clone.cleave_distribution.attack = clone.cleave_distribution.attack / 2
        end
        if type(clone.cleave_distribution.impact) == "number" then
            clone.cleave_distribution.impact = clone.cleave_distribution.impact / 2
        end
    end

    DamageProfileTemplates[key] = clone

    -- Register in NetworkLookup.damage_profiles. The lookup is built once at
    -- game load (network_lookup.lua:2203) and frozen with an __index metatable
    -- that errors on missing keys. PlayerProjectileUnitExtension (line 92)
    -- looks up `NetworkLookup.damage_profiles[impact_data.damage_profile]` at
    -- projectile spawn — without this registration every brace shot crashes
    -- with "Table damage_profiles does not contain key: wt_authentic_pistol",
    -- which is exactly what made v0.12.6 silently no-op. Same pattern CWV uses
    -- for its custom damage-profile clones (character_weapon_variants.lua:1364).
    if NetworkLookup and NetworkLookup.damage_profiles and not rawget(NetworkLookup.damage_profiles, key) then
        local tbl = NetworkLookup.damage_profiles
        local idx = #tbl + 1
        rawset(tbl, idx, key)
        rawset(tbl, key, idx)
    end

    -- issue 431: record the clone SOURCE as this profile's wire-safe fallback.
    -- The send_rpc_attack_hit floor (_wt431_damage_profile_parity.lua) coerces
    -- the custom id back to this vanilla id if it would ever ride the wire
    -- while a peer without wt is present. Belt-and-suspenders `or {}` because
    -- registration sites run before the parity module loads.
    mod._wt431_custom_profile_fallback = mod._wt431_custom_profile_fallback or {}
    mod._wt431_custom_profile_fallback[key] = "shot_sniper"

    return key
end

-- issue 431: parity-gated repoint for the authentic-brace damage profile.
-- _apply_authentic_brace_mode snapshots each firing sub-action's vanilla
-- damage_profile into mod._wt431_brace_profile_slots (once, at apply time);
-- this function (re)points them at wt_authentic_pistol only while every other
-- human peer is confirmed to run wt, and restores the vanilla keys the moment
-- one is not (a non-wt peer would fatal decoding our appended NetworkLookup
-- index off rpc_attack_hit -- BUG_CLASSES 31). No-op until the mode has been
-- applied (slots empty). Called from _apply_authentic_brace_mode and from the
-- issue-431 peer-parity callbacks (_wt431_damage_profile_parity.lua). The rest
-- of the authentic-brace mode (ammo/spread/speed) never rides a lookup index,
-- so it stays applied regardless of parity.
mod._wt431_brace_repoint = function()
    local slots = mod._wt431_brace_profile_slots
    if type(slots) ~= "table" then return end
    local allowed = type(mod._wt431_profiles_allowed) == "function"
        and mod._wt431_profiles_allowed() == true
    for i = 1, #slots do
        local s = slots[i]
        if type(s.impact_data) == "table" then
            s.impact_data.damage_profile = allowed and s.custom or s.original
        end
    end
end

-- Primary spread mult: applied to the default brace spread used by
-- single-shot LMB (action_one.default). 2× wider than vanilla.
-- Dialled back from 3× per user feel-test 2026-05-22 — single-shot LMB
-- felt too inaccurate for the primary mode of fire. Secondary mult stays at 9×.
local _AUTHENTIC_BRACE_PRIMARY_SPREAD_MULT = 2.0
-- Secondary spread mult: applied to pistol_special, which both
-- action_two.default (lock-target / RMB aim) and action_one.fast_shot
-- (rapid-fire shot) override to via `spread_template_override`. 9×
-- (dialled back from 12× in v0.12.26 — final tune per user).
local _AUTHENTIC_BRACE_SECONDARY_SPREAD_MULT = 9.0

local function _wt_scale_spread(t, mult)
    for k, v in pairs(t) do
        if type(v) == "table" then
            _wt_scale_spread(v, mult)
        elseif type(v) == "number" then
            t[k] = v * mult
        end
    end
end

local function _wt_clone_spread_wider(source_key, dest_key, mult)
    if not SpreadTemplates then return nil end
    local source = SpreadTemplates[source_key]
    if not source then return nil end
    if SpreadTemplates[dest_key] then return dest_key end
    local clone = table.clone(source, true)
    _wt_scale_spread(clone, mult)
    SpreadTemplates[dest_key] = clone
    return dest_key
end

local function _wt_clone_brace_spread_wider()
    -- Default-stance spread (used by single-shot from action_one.default).
    -- Brace spread template is nested two levels deep (continuous/immediate →
    -- still/moving/etc → max_pitch/max_yaw/immediate_pitch/immediate_yaw).
    return _wt_clone_spread_wider("brace_of_pistols",
        "wt_authentic_brace_of_pistols_spread",
        _AUTHENTIC_BRACE_PRIMARY_SPREAD_MULT)
end

local function _wt_clone_pistol_special_spread_wider()
    -- pistol_special is what fast_shot (rapid-fire, action_two→fast_shot
    -- chain) uses via `spread_template_override`. Secondary mult (higher)
    -- so rapid fire is noticeably less accurate than single shots.
    return _wt_clone_spread_wider("pistol_special",
        "wt_authentic_brace_pistol_special_spread",
        _AUTHENTIC_BRACE_SECONDARY_SPREAD_MULT)
end

local function _apply_authentic_brace_mode()
    if not Weapons or not Weapons.brace_of_pistols_template_1 then
        mod:warning("[wt authentic-brace] brace_of_pistols_template_1 not found — patch skipped")
        return
    end
    local tpl = Weapons.brace_of_pistols_template_1

    -- 1) Damage profile + shield/armor piercing on all firing sub-actions.
    local damage_profile_key = _wt_clone_shot_sniper_no_dropoff()
    if not damage_profile_key then
        mod:warning("[wt authentic-brace] failed to clone shot_sniper — bailing")
        return
    end
    if tpl.actions and tpl.actions.action_one then
        -- issue 431: snapshot the vanilla damage_profile keys ONCE, then route
        -- the repoint through mod._wt431_brace_repoint so the peer-parity gate
        -- can revert/re-apply it live. The snapshot guard keeps a hypothetical
        -- second apply from capturing our own custom key as "original".
        mod._wt431_brace_profile_slots = mod._wt431_brace_profile_slots or {}
        local slots = mod._wt431_brace_profile_slots
        local first_apply = (#slots == 0)
        for _, sub_name in ipairs({ "default", "fast_shot", "special_action_shoot" }) do
            local sub = tpl.actions.action_one[sub_name]
            if sub then
                if sub.impact_data and first_apply then
                    slots[#slots + 1] = {
                        impact_data = sub.impact_data,
                        original    = sub.impact_data.damage_profile,
                        custom      = damage_profile_key,
                    }
                end
                sub.ignore_shield_hit = true
            end
        end
        mod._wt431_brace_repoint()
    end

    -- 2) (Removed in v0.12.15) Right-click is left alone — vanilla brace
    -- lock-target / fast_shot rapid-fire kept intact. The previous attempts
    -- to swap it for a handgun-style optical zoom and to scrub the
    -- fast_shot rapid-fire chain were both reverted: the user reported the
    -- rapid-fire path was reachable through paths we never tracked down,
    -- and would rather lean into the rapid-fire than keep chasing it. The
    -- accuracy reduction in step (5) compensates by making rapid fire
    -- highly inaccurate.

    -- 3) Manual reload re-enabled (v0.12.19). Earlier revisions disabled
    -- weapon_reload.default by stubbing its condition_funcs with
    -- _disable_action so the only reload path was the auto-load-empty
    -- chain. The user has changed their mind: they want manual reload
    -- back, one shot at a time. We leave weapon_reload.default at vanilla
    -- (no condition_func override) and rely on ammo_per_reload=1 (step 4)
    -- for the single-shot-per-cycle behavior.

    -- 4) Ammo: 6 in the mag, 6 in reserve, reload one shot at a time.
    -- ammo_per_clip = 6 (mag size, the number you can fire before reload
    -- is required), max_ammo = 12 (mag + reserve, total carry), so reserve
    -- = max_ammo - ammo_per_clip = 6. ammo_per_reload = 1 means each
    -- reload animation cycle loads one round; the player can interrupt
    -- with a shot at any time (vanilla brace already supports this via
    -- weapon_reload.default's chain into action_one) or keep tapping R to
    -- top up the clip one round at a time.
    if tpl.ammo_data then
        tpl.ammo_data.ammo_per_clip = 6
        tpl.ammo_data.ammo_per_reload = 1
        tpl.ammo_data.max_ammo = 12
    end

    -- 6) (Removed in v0.12.15) fast_shot chain rewrite was reverted along
    -- with the right-click aim mutation in step (2). Rapid fire is allowed
    -- to remain reachable through whatever vanilla path the engine uses;
    -- v0.12.19 makes secondary fire deliberately slower (step 7) and less
    -- accurate (step 5) instead of trying to block it.

    -- 7) Action speed: PRIMARY/all-other actions run at 2x speed
    -- (_FAST_MULT = 0.5 → halved timings). SECONDARY FIRE
    -- (action_one.fast_shot — the rapid-fire shot triggered by RMB-hold)
    -- runs at VANILLA speed (_SLOW_MULT = 1.0 → no scaling). This was
    -- 2.0 (50% of vanilla, i.e. 2x slower) in v0.12.19-v0.12.20; user
    -- felt that was too slow, asked to double the speed in v0.12.21 →
    -- 1.0 lands secondary fire at vanilla pacing while primary stays
    -- at 2x. Net: secondary is half the speed of primary, but at the
    -- vanilla cadence the engine ships with. Chain start_times use:
    --   * SLOW if the chain's SOURCE sub-action is secondary (so internal
    --     fast_shot pacing — the self-loop at start_time=0.25 — stays at
    --     vanilla 0.25s, giving ~4 shots/sec).
    --   * SLOW if the chain's TARGET sub-action is fast_shot (so the
    --     RMB-into-rapid-fire chain from action_two.default at
    --     start_time=0.25 also stays vanilla).
    --   * FAST otherwise.
    -- Skip 0/math.huge — neither "instant" nor "hold-forever" semantics
    -- should be scaled. With _SLOW_MULT=1.0 the "slow" branches are
    -- effectively no-ops; the structure is retained so the asymmetry
    -- can be re-tuned (e.g. back to 1.5 / 2.0) without rewriting the
    -- walker.
    local _FAST_MULT = 0.5  -- 2x speed for primary / non-secondary actions
    local _SLOW_MULT = 1.0  -- vanilla speed for secondary fire (was 2.0 in v0.12.19-v0.12.20)
    local function _is_secondary_sub(action_name, sub_name)
        return action_name == "action_one" and sub_name == "fast_shot"
    end
    local function _chain_targets_secondary(chain, source_action_name)
        -- chain.action is the target action; if absent it defaults to the
        -- source action's name (per ActionUtils chain resolution).
        local target_action = chain.action or source_action_name
        return target_action == "action_one" and chain.sub_action == "fast_shot"
    end
    local function _scale_time(field, mult)
        if type(field) ~= "number" then return field end
        if field == 0 or field == math.huge then return field end
        return field * mult
    end
    if tpl.actions then
        for action_name, sub_actions in pairs(tpl.actions) do
            for sub_name, sub in pairs(sub_actions) do
                if type(sub) == "table" then
                    local is_secondary = _is_secondary_sub(action_name, sub_name)
                    local sub_mult = is_secondary and _SLOW_MULT or _FAST_MULT
                    sub.total_time           = _scale_time(sub.total_time, sub_mult)
                    sub.total_time_secondary = _scale_time(sub.total_time_secondary, sub_mult)
                    sub.fire_time            = _scale_time(sub.fire_time, sub_mult)
                    sub.minimum_hold_time    = _scale_time(sub.minimum_hold_time, sub_mult)
                    sub.cooldown             = _scale_time(sub.cooldown, sub_mult)
                    sub.reload_time          = _scale_time(sub.reload_time, sub_mult)
                    if sub.allowed_chain_actions then
                        for _, chain in ipairs(sub.allowed_chain_actions) do
                            local chain_mult
                            if is_secondary or _chain_targets_secondary(chain, action_name) then
                                chain_mult = _SLOW_MULT
                            else
                                chain_mult = _FAST_MULT
                            end
                            chain.start_time = _scale_time(chain.start_time, chain_mult)
                        end
                    end
                end
            end
        end
    end

    -- 5) Spread: dramatically less accurate. Both the default spread (single
    -- shot from action_one.default) AND the pistol_special spread (used by
    -- fast_shot rapid-fire via `spread_template_override`) are widened by
    -- the same multiplier. Without the second clone, holding RMB + LMB
    -- enters rapid fire which falls back to vanilla pistol_special spread
    -- and the "dramatic" feel only shows on single shots.
    local spread_key = _wt_clone_brace_spread_wider()
    if spread_key then
        tpl.default_spread_template = spread_key
    end
    -- Replace `spread_template_override = "pistol_special"` everywhere it
    -- appears on the template, not just in action_one. Critically this
    -- catches `action_two.default` (the RMB lock-target / aim action)
    -- which vanilla also overrides to pistol_special. v0.12.20 and earlier
    -- only patched action_one.[default|fast_shot|special_action_shoot] —
    -- that meant pressing RMB jumped the reticle to the vanilla
    -- pistol_special max spread (≈1.0), and then pressing LMB triggered
    -- action_one.fast_shot which jumped it again to our wider clone
    -- (≈1.0 × secondary_mult). The user saw this as the reticle
    -- "unnaturally going from small to large" — a two-step jump on RMB
    -- then LMB. With this patch the override on action_two.default uses
    -- the same wider clone, so the reticle jumps to the correct (large)
    -- size the moment the player takes aim. `override_spread_template`
    -- in `weapon_spread_extension.lua:168-177` instantly sets
    -- `current_pitch = state_settings.max_pitch`, so no lerp is visible.
    local rapid_spread_key = _wt_clone_pistol_special_spread_wider()
    if rapid_spread_key and tpl.actions then
        for _, sub_actions in pairs(tpl.actions) do
            for _, sub in pairs(sub_actions) do
                if type(sub) == "table" and sub.spread_template_override == "pistol_special" then
                    sub.spread_template_override = rapid_spread_key
                end
            end
        end
    end

    mod:info("[wt authentic-brace] applied: damage=%s, primary_spread=%s (%sx), secondary_spread=%s (%sx, applied to ALL pistol_special overrides incl. action_two.default), ammo=6/12 (reload 1 at a time, manual reload re-enabled), primary-speed=2x, secondary-fire-speed=vanilla (slow_mult=1.0)",
        damage_profile_key,
        tostring(spread_key), tostring(_AUTHENTIC_BRACE_PRIMARY_SPREAD_MULT),
        tostring(rapid_spread_key), tostring(_AUTHENTIC_BRACE_SECONDARY_SPREAD_MULT))
end

-- audit 2026-06-07 (PROJECT_STANDARDS §9.3 gated-registration divergence):
-- ALWAYS register the custom damage profile into NetworkLookup at load — even
-- when the toggle is OFF — so wt_authentic_pistol resolves to the SAME network
-- index on every peer running this wt version, regardless of each peer's toggle
-- state. Only the template PATCHING (usage) below stays gated. Without this, a
-- host with the brace ON and a client with it OFF diverge on the
-- damage_profiles index -> "Table damage_profiles does not contain key" crash /
-- silent wrong-damage desync when a networked brace shot is decoded.
-- (_wt_clone_shot_sniper_no_dropoff is idempotent; same load timing as before.)
-- RESIDUAL: full cross-MOD-SET determinism (a peer that also runs CWV/other
-- NetworkLookup appenders vs one that doesn't) still requires routing through
-- bt's shared sorted registry — the proper long-term fix, tracked as follow-up.
-- Regression: wt_authentic_pistol_profile_registered_unconditionally.
if not _wt_clone_shot_sniper_no_dropoff() then
    -- Ungated (mod:warning): if the profile can't register at load (tables not
    -- ready), a networked brace shot would desync / crash on the other peer when
    -- the toggle is on. Surface it without requiring Debug Logging.
    mod:warning("[wt:authentic-brace] wt_authentic_pistol damage-profile registration failed at load (DamageProfileTemplates/NetworkLookup not ready)")
end
if mod:get("authentic_brace_of_pistols") then
    _apply_authentic_brace_mode()
end

-- ============================================================
-- Issue #348 -- revert Patch 6.11.0 Kruber 1h sword push-attack combo
-- ============================================================
-- Game v6.11.0 (Vermintide-2-Source-Code @abe82ab4, 2026-05-18) reworked
-- Kruber's Empire one-handed sword (`Weapons.one_handed_swords_template_1`).
-- The relevant change: the push-attack (`light_attack_bopp`) combo continuation
-- was repointed from `default` (-> first light `light_attack_left`, a horizontal
-- sweep, good for hordes) to `default_left` (-> third light `light_attack_last`,
-- the single-target overhead). The user finds the overhead-terminated combo worse
-- for horde work and wants the pre-6.11.0 chain back.
--
-- The revert below restores the EXACT v6.10.0 `light_attack_bopp.allowed_chain_actions`
-- table, verified verbatim from the decompile at commit 5ff26df1
-- (`git diff 5ff26df1 abe82ab4 -- .../1h_swords.lua`). Only the push-attack chain
-- is reverted; 6.11.0's other, unrelated changes to this sword (dodge_count 3->6,
-- the third light's damage_profile, movement multipliers) are deliberately LEFT as
-- current -- the issue is only about the combo routing.
--
-- Wire-safe by construction: this only re-routes `sub_action` between vanilla
-- action names (`default`, `default_left`, `light_attack_*`) that exist in the
-- base template on every peer. No NetworkLookup key is added and no damage profile
-- is repointed, so a peer without the mod cannot diverge or crash (PROJECT_STANDARDS
-- §9.3; same wire class as the ungated Big Rebalance chain edits). No peer-parity
-- gate needed. Scope note: only Kruber's Empire sword changed in 6.11.0 -- Sienna's
-- flaming sword (`flaming_sword_template_1`, `1h_swords_wizard.lua`) was NOT touched,
-- so there is nothing to revert on her side.
--
-- Applied once at init when the toggle is on (mirrors `authentic_brace_of_pistols`);
-- toggling requires a restart, which the option description states. Mutates the
-- shared template global in place -- intended, since the chain is a property of the
-- weapon and should revert for every career that wields it.
local function _patch_kruber_1h_sword_push_combo_revert()
    if not Weapons or not Weapons.one_handed_swords_template_1 then
        pcall(printf, "[wt:348] skip: Weapons.one_handed_swords_template_1 missing (revert not applied)")
        return
    end
    local ao = Weapons.one_handed_swords_template_1.actions
        and Weapons.one_handed_swords_template_1.actions.action_one
    local bopp = ao and ao.light_attack_bopp
    if not (bopp and bopp.allowed_chain_actions) then
        pcall(printf, "[wt:348] skip: light_attack_bopp chain missing on one_handed_swords_template_1")
        return
    end
    -- Pre-6.11.0 (v6.10.0 @5ff26df1) light_attack_bopp.allowed_chain_actions, verbatim.
    bopp.allowed_chain_actions = {
        { action = "action_one",   end_time = 1.2, input = "action_one",      release_required = "action_two_hold", start_time = 0.55, sub_action = "default" },
        { action = "action_one",   end_time = 1.2, input = "action_one_hold", release_required = "action_two_hold", start_time = 0.55, sub_action = "default" },
        { action = "action_one",                   input = "action_one",                                            start_time = 0.85, sub_action = "default" },
        { action = "action_two",                   input = "action_two_hold",                                       start_time = 0.55, sub_action = "default" },
        { action = "action_wield",                 input = "action_wield",                                          start_time = 0.5,  sub_action = "default" },
    }
    pcall(printf, "[wt:348] reverted Kruber Empire 1h sword push-attack combo to pre-6.11.0 (light_attack_bopp -> default first-light sweep)")
    _dbg("[wt:tpl_patch] event=applied template=one_handed_swords_template_1 feature=revert_push_combo issue=348")
end

if mod:get("wt_revert_1h_sword_push_combo") then
    _patch_kruber_1h_sword_push_combo_revert()
end

-- ============================================================
-- Warrior Priest punch buff (Reckoner Greathammer special)
-- ============================================================
-- Toggle that TRIPLES stagger and DOUBLES damage of the Warrior Priest 2h
-- hammer's special attack -- the "punch" (anim attack_slam) reached via the
-- weapon's push-stagger special. The punch action lives on the priest hammer
-- template (Weapons.two_handed_hammer_priest_template) and vanilla points at the
-- shared `light_blunt_smiter_stab` damage profile -- which other weapons also
-- use, so we must NOT mutate it in place. Instead we register a private cloned
-- profile (`wt_priest_punch_buffed`) with the punch's damage (power_distribution
-- .attack x2) and stagger (.impact x3) scaled on its default_target + targets,
-- then repoint ONLY the punch action's damage_profile at it while the toggle is
-- on (restoring the original key when off).
--
-- Like wt_authentic_pistol, the profile is registered into NetworkLookup
-- UNCONDITIONALLY at load (gated registration would desync the network index
-- between a host with the toggle on and a client with it off -- PROJECT_STANDARDS
-- §9.3). Only the action repoint is toggle-gated.
do
    local owner, reason = mod:dofile("scripts/mods/weapon_tweaker/_wt_priest_punch_owner").install(mod)
    if not owner then
        pcall(printf, "[wt:428] priest-punch transaction rejected (%s); owned registration/repoint not installed", tostring(reason))
    end
end
]====],
}
