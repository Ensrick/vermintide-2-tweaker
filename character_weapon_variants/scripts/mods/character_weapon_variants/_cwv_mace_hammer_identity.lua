-- Issue #599: one-handed mace/hammer identity policy.
--
-- Engine-free by design: the runtime supplies Weapons, damage-profile tables,
-- and a clone callback. The module owns every snapshot and generated profile,
-- so toggling the feature never compounds multipliers or mutates vanilla
-- DamageProfileTemplates/PowerLevelTemplates rows in place.
local M = {}

M.SETTING_ID = "enable_cwv_mace_hammer_identity"
M.MACE_SPEED_MULT = 1.05
M.HAMMER_DAMAGE_MULT = 1.125
M.HAMMER_CLEAVE_MULT = 0.75
M.CWV_DUAL_MACE_TEMPLATE = "cwv_dual_maces_template"

-- Semantic families, not a name-pattern scan. In particular this excludes
-- all two-handed hammer templates, the visually two-handed CWV Maul, Warrior
-- Priest Hammer and Tome, and the mixed Mace and Sword weapon.
M.MACE_TEMPLATE_KEYS = {
	"one_handed_hammer_template_1",        -- Kruber Mace
	"one_handed_hammer_wizard_template_1", -- Sienna Mace
	"one_handed_hammer_shield_template_1", -- Kruber Mace and Shield
	M.CWV_DUAL_MACE_TEMPLATE,               -- both CWV Dual Maces items
}

M.HAMMER_TEMPLATE_KEYS = {
	"one_handed_hammer_template_2",               -- Bardin Hammer
	"one_handed_hammer_priest_template",          -- Saltzpyre Skull-Splitter
	"one_handed_hammer_shield_template_2",        -- Bardin Hammer and Shield
	"one_handed_hammer_shield_priest_template",   -- Skull-Splitter and Shield
	"dual_wield_hammers_template",                 -- Bardin Dual Hammers
	"dual_wield_hammers_priest_template",          -- Saltzpyre Dual Skull-Splitters
}

local function _each_sub_action(template, fn)
	for action_name, action_group in pairs((template and template.actions) or {}) do
		if type(action_group) == "table" then
			for sub_action_name, sub_action in pairs(action_group) do
				if type(sub_action) == "table" then
					fn(sub_action, action_name, sub_action_name)
				end
			end
		end
	end
end

local function _is_direct_attack(sub_action)
	-- Ordinary pushes use damage_profile_inner/damage_profile_outer and have no
	-- direct damage_profile. Requiring sweep keeps charge, block, wield, inspect,
	-- and other utility actions outside the balance pass.
	return sub_action.kind == "sweep" and type(sub_action.damage_profile) == "string"
end

local function _is_attack_timing(sub_action)
	-- Charge/start actions and shield-slam releases are part of the weapon's
	-- attack cadence. Ordinary push remains `push_stagger` and is excluded.
	return sub_action.kind == "melee_start"
		or sub_action.kind == "sweep"
		or sub_action.kind == "shield_slam"
end

local function _scale_power_distribution(row, damage_mult)
	if type(row) ~= "table" then return end
	local distribution = row.power_distribution
	if type(distribution) == "table" and type(distribution.attack) == "number" then
		distribution.attack = distribution.attack * damage_mult
	end
end

local function _scale_target_value(value, power_levels, clone, generated_key, damage_mult)
	if type(value) == "string" then
		local source = power_levels and power_levels[value]
		if type(source) ~= "table" then return value end
		local key = generated_key .. "_" .. value
		if not power_levels[key] then
			local copy = clone(source)
			_scale_power_distribution(copy, damage_mult)
			for _, target in ipairs(copy) do _scale_power_distribution(target, damage_mult) end
			power_levels[key] = copy
		end
		return key
	elseif type(value) == "table" then
		_scale_power_distribution(value, damage_mult)
		for _, target in ipairs(value) do _scale_power_distribution(target, damage_mult) end
	end
	return value
end

local function _scale_cleave(value, power_levels, clone, generated_key, cleave_mult)
	if type(value) == "string" then
		local source = power_levels and power_levels[value]
		if type(source) ~= "table" then return value end
		local key = generated_key .. "_" .. value
		if not power_levels[key] then
			local copy = clone(source)
			if type(copy.attack) == "number" then copy.attack = copy.attack * cleave_mult end
			if type(copy.impact) == "number" then copy.impact = copy.impact * cleave_mult end
			power_levels[key] = copy
		end
		return key
	elseif type(value) == "table" then
		if type(value.attack) == "number" then value.attack = value.attack * cleave_mult end
		if type(value.impact) == "number" then value.impact = value.impact * cleave_mult end
	end
	return value
end

function M.new()
	local state = {
		enabled = false,
		speed_snapshots = {},
		profile_snapshots = {},
		generated_profiles = {},
	}

	function state:ensure_cwv_dual_mace_template(weapons, clone)
		if not weapons or weapons[M.CWV_DUAL_MACE_TEMPLATE] then return true end
		local source = weapons.dual_wield_hammers_template
		if type(source) ~= "table" then return false, "dual_wield_hammers_template missing" end
		weapons[M.CWV_DUAL_MACE_TEMPLATE] = clone(source)
		return true
	end

	function state:_balanced_profile(source_name, damage_profiles, power_levels, clone, record_source)
		local cached = self.generated_profiles[source_name]
		if cached then return cached end
		local source = damage_profiles and damage_profiles[source_name]
		if type(source) ~= "table" then return source_name end

		local key = "cwv_mhi_" .. source_name
		if not damage_profiles[key] then
			local copy = clone(source)
			copy.cleave_distribution = _scale_cleave(copy.cleave_distribution,
				power_levels, clone, key .. "_cleave", M.HAMMER_CLEAVE_MULT)
			for _, field in ipairs({ "default_target", "targets", "critical_strike" }) do
				copy[field] = _scale_target_value(copy[field], power_levels, clone,
					key .. "_" .. field, M.HAMMER_DAMAGE_MULT)
			end
			damage_profiles[key] = copy
		end
		if record_source then record_source(key, source_name) end
		self.generated_profiles[source_name] = key
		return key
	end

	function state:apply(enabled, weapons, damage_profiles, power_levels, clone, record_source, register_profile)
		enabled = not not enabled
		if enabled == self.enabled then return end

		if enabled then
			for _, template_key in ipairs(M.MACE_TEMPLATE_KEYS) do
				_each_sub_action(weapons and weapons[template_key], function(action)
					if _is_attack_timing(action) then
						self.speed_snapshots[action] = {
							had_value = action.anim_time_scale ~= nil,
							value = action.anim_time_scale,
						}
						action.anim_time_scale = (action.anim_time_scale or 1) * M.MACE_SPEED_MULT
					end
				end)
			end

			for _, template_key in ipairs(M.HAMMER_TEMPLATE_KEYS) do
				_each_sub_action(weapons and weapons[template_key], function(action)
					if _is_direct_attack(action) then
						self.profile_snapshots[action] = action.damage_profile
						local balanced = self:_balanced_profile(action.damage_profile,
							damage_profiles, power_levels, clone, record_source)
						action.damage_profile = balanced
						if register_profile then register_profile(balanced) end
					end
				end)
			end
		else
			for action, snapshot in pairs(self.speed_snapshots) do
				action.anim_time_scale = snapshot.had_value and snapshot.value or nil
			end
			for action, source_name in pairs(self.profile_snapshots) do
				action.damage_profile = source_name
			end
			self.speed_snapshots = {}
			self.profile_snapshots = {}
		end

		self.enabled = enabled
	end

	return state
end

return M
