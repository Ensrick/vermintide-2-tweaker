-- Issue #601: independent Greataxe / Dual Axes identity policies.
-- Engine-free; runtime supplies weapon/profile tables and cloning/registration.
local M = {}

M.GREATAXE_LIGHT_CRIT_SETTING = "enable_cwv_greataxe_light_crit"
M.DUAL_AXES_LIGHT_CRIT_SETTING = "enable_cwv_dual_axes_light_crit"
M.DUAL_AXES_CLEAVE_SETTING = "enable_cwv_dual_axes_cleave"
M.LIGHT_CRIT_FLOOR = 0.10 -- percentage points, not a multiplier
M.CLEAVE_MULT = 1.10

M.GREATAXE_TEMPLATES = {
	"two_handed_axes_template_1",
	"cwv_greataxe_template",
}
M.DUAL_AXES_TEMPLATES = {
	"dual_wield_axes_template_1",
}

local function _each_sub_action(template, fn)
	for _, action_group in pairs((template and template.actions) or {}) do
		if type(action_group) == "table" then
			for sub_action_name, sub_action in pairs(action_group) do
				if type(sub_action) == "table" then fn(sub_action_name, sub_action) end
			end
		end
	end
end

local function _is_light_release(name, action)
	return action.kind == "sweep"
		and type(name) == "string"
		and name:find("light_attack_", 1, true) == 1
end

local function _is_direct_attack(action)
	if action.kind ~= "sweep" then return false end
	return type(action.damage_profile) == "string"
		or type(action.damage_profile_left) == "string"
		or type(action.damage_profile_right) == "string"
end

local function _scale_cleave(value, power_levels, clone, generated_key)
	if type(value) == "string" then
		local source = power_levels and power_levels[value]
		if type(source) ~= "table" then return value end
		local key = generated_key .. "_" .. value
		if not power_levels[key] then
			local copy = clone(source)
			if type(copy.attack) == "number" then copy.attack = copy.attack * M.CLEAVE_MULT end
			if type(copy.impact) == "number" then copy.impact = copy.impact * M.CLEAVE_MULT end
			power_levels[key] = copy
		end
		return key
	elseif type(value) == "table" then
		if type(value.attack) == "number" then value.attack = value.attack * M.CLEAVE_MULT end
		if type(value.impact) == "number" then value.impact = value.impact * M.CLEAVE_MULT end
	end
	return value
end

function M.new()
	local state = {
		greataxe_crit_enabled = false,
		dual_crit_enabled = false,
		dual_cleave_enabled = false,
		greataxe_crit_originals = {},
		dual_crit_originals = {},
		dual_profile_originals = {},
		generated_profiles = {},
	}

	local function apply_crit(self, enabled, weapons, template_keys, originals, flag)
		enabled = not not enabled
		if enabled == self[flag] then return end
		if enabled then
			for _, template_key in ipairs(template_keys) do
				_each_sub_action(weapons and weapons[template_key], function(name, action)
					if _is_light_release(name, action) then
						originals[action] = {
							had_value = action.additional_critical_strike_chance ~= nil,
							value = action.additional_critical_strike_chance,
						}
						local authored = action.additional_critical_strike_chance or 0
						action.additional_critical_strike_chance =
							math.max(authored, M.LIGHT_CRIT_FLOOR)
					end
				end)
			end
		else
			for action, original in pairs(originals) do
				action.additional_critical_strike_chance =
					original.had_value and original.value or nil
			end
			for action in pairs(originals) do originals[action] = nil end
		end
		self[flag] = enabled
	end

	function state:apply_greataxe_crit(enabled, weapons)
		apply_crit(self, enabled, weapons, M.GREATAXE_TEMPLATES,
			self.greataxe_crit_originals, "greataxe_crit_enabled")
	end

	function state:apply_dual_crit(enabled, weapons)
		apply_crit(self, enabled, weapons, M.DUAL_AXES_TEMPLATES,
			self.dual_crit_originals, "dual_crit_enabled")
	end

	function state:_cleave_profile(source_name, damage_profiles, power_levels,
			clone, record_source)
		local cached = self.generated_profiles[source_name]
		if cached then return cached end
		local source = damage_profiles and damage_profiles[source_name]
		if type(source) ~= "table" then return source_name end
		local key = "cwv_axe_cleave_" .. source_name
		if not damage_profiles[key] then
			local copy = clone(source)
			copy.cleave_distribution = _scale_cleave(copy.cleave_distribution,
				power_levels, clone, key)
			damage_profiles[key] = copy
		end
		if record_source then record_source(key, source_name) end
		self.generated_profiles[source_name] = key
		return key
	end

	function state:apply_dual_cleave(enabled, weapons, damage_profiles,
			power_levels, clone, record_source, register_profile)
		enabled = not not enabled
		if enabled == self.dual_cleave_enabled then return end
		if enabled then
			for _, template_key in ipairs(M.DUAL_AXES_TEMPLATES) do
				_each_sub_action(weapons and weapons[template_key], function(_, action)
					if _is_direct_attack(action) then
						local fields = {}
						for _, field in ipairs({
							"damage_profile", "damage_profile_left", "damage_profile_right",
						}) do
							local source_name = action[field]
							if type(source_name) == "string" then
								fields[field] = source_name
								local balanced = self:_cleave_profile(source_name,
									damage_profiles, power_levels, clone, record_source)
								action[field] = balanced
								if register_profile then register_profile(balanced) end
							end
						end
						self.dual_profile_originals[action] = fields
					end
				end)
			end
		else
			for action, fields in pairs(self.dual_profile_originals) do
				for field, source_name in pairs(fields) do action[field] = source_name end
			end
			self.dual_profile_originals = {}
		end
		self.dual_cleave_enabled = enabled
	end

	return state
end

return M
