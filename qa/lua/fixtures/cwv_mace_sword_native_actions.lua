-- Exact native93dea shared prerequisites for the detached #645 fixture only.
-- scripts/settings/action_templates.lua:6-27 and154-213, in that order.
-- Native callbacks are retained; constructor QA does not invoke engine bodies.
return [==[
ActionTemplates.wield = {
	default = {
		action_priority = 2,
		keep_buffer = true,
		kind = "wield",
		total_time = 0,
		uninterruptible = true,
		weapon_action_hand = "either",
		wield_cooldown = 0.35,
		condition_func = function (action_user, input_extension)
			local inventory_extension = ScriptUnit.extension(action_user, "inventory_system")

			return inventory_extension:can_wield()
		end,
		chain_condition_func = function (action_user, input_extension)
			local inventory_extension = ScriptUnit.extension(action_user, "inventory_system")

			return inventory_extension:can_wield()
		end,
		allowed_chain_actions = {},
	},
}
ActionTemplates.action_inspect = {
	default = {
		kind = "dummy",
		total_time = 1,
		weapon_action_hand = "either",
		condition_func = function (action_user, input_extension, ammo_extension)
			if ammo_extension and ammo_extension:is_reloading() then
				return false
			end

			if Managers.input:is_device_active("gamepad") then
				local level_key = Managers.state.game_mode:level_key()
				local level_settings = LevelSettings[level_key]

				if level_settings.hub_level and not MotionControlSettings.use_motion_controls then
					return true
				else
					return false
				end
			else
				return true
			end
		end,
		allowed_chain_actions = {
			{
				end_time = 0,
				input = "action_inspect_hold",
				start_time = 0,
			},
			{
				action = "action_inspect",
				auto_chain = true,
				start_time = 0,
				sub_action = "action_inspect_hold",
			},
		},
	},
	action_inspect_hold = {
		anim_end_event = "inspect_end",
		anim_event = "inspect_start",
		can_abort_reload = false,
		cooldown = 0.15,
		hold_input = "action_inspect_hold",
		kind = "dummy",
		minimum_hold_time = 0.3,
		weapon_action_hand = "either",
		anim_end_event_condition_func = function (unit, end_reason)
			return end_reason ~= "new_interupting_action"
		end,
		total_time = math.huge,
		allowed_chain_actions = {},
		weapon_sway_settings = {
			camera_look_sensitivity = 1,
			lerp_speed = 10,
			look_sensitivity = 1.5,
			recentering_lerp_speed = 0,
			sway_range = 1,
		},
	},
}
]==]
