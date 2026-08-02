-- Issue #942 engine adapter. Owns settings, profile registration, overcharge
-- lookup, and the two bounded sweep hooks; policy remains engine-free.
local M = {}

function M.install(mod, policy, state)
	local runtime = { config = policy.config({}) }
	local setting_ids = {
		[policy.ENABLED_SETTING] = true,
		[policy.CLEAVE_SETTING] = true,
		[policy.DAMAGE_SETTING] = true,
		[policy.ARMOR_SETTING] = true,
		[policy.ARMOR_THRESHOLD_SETTING] = true,
	}
	local profile_fields = { "damage_profile", "damage_profile_left", "damage_profile_right" }
	local cleave_context

	function runtime:is_setting(setting_id)
		return setting_ids[setting_id] == true
	end

	local function setting_values()
		local values = {}
		for id in pairs(setting_ids) do values[id] = mod:get(id) end
		return values
	end

	local function register_profile(name)
		local lookup = NetworkLookup and NetworkLookup.damage_profiles
		if type(name) ~= "string" or not lookup or rawget(lookup, name) then return end
		local index = #lookup + 1
		rawset(lookup, index, name)
		rawset(lookup, name, index)
	end

	function runtime:heat(unit)
		if not unit or not Unit.alive(unit) then return 0 end
		local ok, extension = pcall(ScriptUnit.has_extension, unit, "overcharge_system")
		return ok and policy.heat_value(extension) or 0
	end

	function runtime:apply(force_off)
		self.config = policy.config(setting_values(), force_off)
		if type(Weapons) ~= "table" or type(DamageProfileTemplates) ~= "table"
				or type(PowerLevelTemplates) ~= "table" then return end
		mod._wt431_custom_profile_fallback = mod._wt431_custom_profile_fallback or {}
		local parity_allowed = type(mod._wt431_profiles_allowed) == "function"
			and mod._wt431_profiles_allowed() == true
		local count = state:apply(self.config.enabled, Weapons, DamageProfileTemplates,
			PowerLevelTemplates, function(value) return table.clone(value, true) end,
			register_profile, mod._wt431_custom_profile_fallback, parity_allowed)
		pcall(printf, "[wt:942] applied: actions=%d enabled=%s parity=%s cleave=%.3f damage=%.3f armor=%s threshold=%.1f",
			count, tostring(self.config.enabled), tostring(parity_allowed),
			self.config.cleave_per_heat, self.config.damage_per_heat,
			tostring(self.config.armor_enabled), self.config.armor_threshold)
	end

	function runtime:scale_direct_damage(damage, profile, attacker_unit)
		return policy.scale_direct_damage(damage, profile, self:heat(attacker_unit), self.config)
	end

	mod._wt_apply_fire_sword_heat = function(force_off) runtime:apply(force_off) end

	if rawget(_G, "ActionUtils") then
		mod:hook(ActionUtils, "get_max_targets", function(func, damage_profile, cleave_power_level, ...)
			local context = cleave_context
			if context and context.profile == damage_profile then
				cleave_power_level = policy.scale_cleave_power(cleave_power_level,
					damage_profile, context.heat, context.config)
			end
			return func(damage_profile, cleave_power_level, ...)
		end)
	end

	local action_sweep = rawget(_G, "ActionSweep")
	if action_sweep then
		mod:hook(action_sweep, "client_owner_start_action", function(func, self, new_action, t,
				chain_action_data, power_level, action_init_data)
			local heat, originals = runtime:heat(self.owner_unit), {}
			for _, field in ipairs(profile_fields) do
				local name = new_action and new_action[field]
				if type(name) == "string" then
					local selected = state:profile_for_heat(name, heat, runtime.config)
					if selected ~= name then originals[field], new_action[field] = name, selected end
				end
			end
			local profile = new_action and new_action.damage_profile
				and DamageProfileTemplates[new_action.damage_profile]
			local previous = cleave_context
			if type(profile) == "table" and profile._wt_fire_sword_heat_direct == true then
				cleave_context = { profile = profile, heat = heat, config = runtime.config }
			end
			local ok, err = pcall(func, self, new_action, t, chain_action_data,
				power_level, action_init_data)
			cleave_context = previous
			for field, name in pairs(originals) do new_action[field] = name end
			if not ok then error(err) end
		end)
	end

	runtime:apply(false)
	return runtime
end

return M
