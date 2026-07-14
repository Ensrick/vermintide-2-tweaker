-- Engine-free Crowbill pick/hammer mode policy.
--
-- This deliberately does not register items, hook Weapon Special, or send RPCs.
-- It builds an isolated hammer-mode clone of Sienna's exact Crowbill template
-- and provides a bounded transition registry for the eventual runtime owner.
local M = {}

M.SOURCE_TEMPLATE_KEY = "one_handed_crowbill"
M.HAMMER_TEMPLATE_KEY = "cwv_crowbill_hammer_template"
M.MODE_PICK = "pick"
M.MODE_HAMMER = "hammer"
M.HAMMER_CLEAVE_MULT = 1.60
M.HAMMER_DAMAGE_MULT = 0.85
M.MODEL_FLIP_AXIS = { 0, 0, 1 } -- local haft/longitudinal axis
M.MODEL_FLIP_DEGREES = 180
M.CHANNEL = "cwv_crowbill_mode_v1"
M.SCHEMA = 1
M.MAX_IDENTITY_LENGTH = 96

-- Audited from VT2 source `weapon_templates/1h_crowbills.lua`. Only release
-- attacks carry a direct `damage_profile`; starts, block, push and wield stay
-- byte-for-byte identical to the donor template.
M.DIRECT_ACTIONS = {
	heavy_attack = "heavy",
	heavy_attack_left = "heavy",
	heavy_attack_right_up = "heavy",
	light_attack_left = "light",
	light_attack_right = "light",
	light_attack_last = "light",
	light_attack_upper = "light",
	light_attack_bopp = "light",
}

M.LIGHT_ACTIONS = {
	light_attack_left = true,
	light_attack_right = true,
	light_attack_last = true,
	light_attack_upper = true,
	light_attack_bopp = true,
}

local PROFILE_POWER_FIELDS = {
	"armor_modifier",
	"cleave_distribution",
	"critical_strike",
	"default_target",
	"targets",
}

local function _valid_mode(mode)
	return mode == M.MODE_PICK or mode == M.MODE_HAMMER
end

local function _valid_identity(identity)
	return type(identity) == "string"
		and #identity > 0
		and #identity <= M.MAX_IDENTITY_LENGTH
		and identity:match("^[%w_:%-%.]+$") ~= nil
end

local function _safe_key(value)
	return tostring(value):gsub("[^%w_]", "_")
end

local function _scale_attack_power(row)
	if type(row) ~= "table" then return end
	local power = row.power_distribution
	if type(power) == "table" and type(power.attack) == "number" then
		power.attack = power.attack * M.HAMMER_DAMAGE_MULT
	end
	for _, child in ipairs(row) do
		_scale_attack_power(child)
	end
end

local function _remove_light_ap(row)
	if type(row) ~= "table" then return end
	local armor = row.armor_modifier
	local attack = type(armor) == "table" and armor.attack
	if type(attack) == "table" then
		-- Armor type 2 is normal armor; type 6 is super armor where present.
		-- Zero matches vanilla one-handed hammer light-attack semantics.
		attack[2] = 0
		if attack[6] ~= nil then attack[6] = 0 end
	end
	for _, child in ipairs(row) do
		_remove_light_ap(child)
	end
end

local function _clone_power_reference(value, field, source_profile, power_levels, clone)
	if type(value) ~= "string" then
		return clone(value)
	end
	local source = power_levels and power_levels[value]
	if type(source) ~= "table" then return value end
	local key = "cwv_crowbill_hammer_power_" .. _safe_key(source_profile)
		.. "_" .. field .. "_" .. _safe_key(value)
	if not power_levels[key] then power_levels[key] = clone(source) end
	return key
end

local function _hammer_profile(source_name, is_light, damage_profiles, power_levels,
		clone, record_source, register_profile)
	local source = damage_profiles and damage_profiles[source_name]
	if type(source) ~= "table" then return nil, "missing damage profile: " .. tostring(source_name) end

	local key = "cwv_crowbill_hammer_" .. _safe_key(source_name)
	if not damage_profiles[key] then
		local profile = clone(source)
		for _, field in ipairs(PROFILE_POWER_FIELDS) do
			if profile[field] ~= nil then
				profile[field] = _clone_power_reference(profile[field], field, source_name,
					power_levels, clone)
			end
		end

		local cleave = type(profile.cleave_distribution) == "string"
			and power_levels[profile.cleave_distribution] or profile.cleave_distribution
		if type(cleave) == "table" then
			if type(cleave.attack) == "number" then
				cleave.attack = cleave.attack * M.HAMMER_CLEAVE_MULT
			end
			if type(cleave.impact) == "number" then
				cleave.impact = cleave.impact * M.HAMMER_CLEAVE_MULT
			end
		end

		for _, field in ipairs({ "default_target", "targets" }) do
			local row = type(profile[field]) == "string" and power_levels[profile[field]] or profile[field]
			_scale_attack_power(row)
			if is_light then _remove_light_ap(row) end
		end
		if is_light then
			local armor = type(profile.armor_modifier) == "string"
				and power_levels[profile.armor_modifier] or profile.armor_modifier
			if type(armor) == "table" and type(armor.attack) == "table" then
				armor.attack[2] = 0
				if armor.attack[6] ~= nil then armor.attack[6] = 0 end
			end
		end
		damage_profiles[key] = profile
	end

	if record_source then record_source(key, source_name) end
	if register_profile then register_profile(key, damage_profiles[key]) end
	return key
end

function M.build_hammer_template(source_template, damage_profiles, power_levels, clone,
		record_source, register_profile)
	if type(source_template) ~= "table" then return nil, "Crowbill source template missing" end
	if type(clone) ~= "function" then return nil, "clone callback missing" end
	local template = clone(source_template)
	local generated = {}
	local action_one = template.actions and template.actions.action_one
	if type(action_one) ~= "table" then return nil, "Crowbill action_one missing" end

	for action_name, class in pairs(M.DIRECT_ACTIONS) do
		local action = action_one[action_name]
		if type(action) ~= "table" or type(action.damage_profile) ~= "string" then
			return nil, "Crowbill direct action missing: " .. action_name
		end
		local source_name = action.damage_profile
		local key, err = _hammer_profile(source_name, class == "light", damage_profiles,
			power_levels, clone, record_source, register_profile)
		if not key then return nil, err end
		action.damage_profile = key
		generated[action_name] = { source = source_name, generated = key, class = class }
	end

	return template, generated
end

function M.rotation_for_mode(mode)
	if not _valid_mode(mode) then return nil end
	return {
		axis = { M.MODEL_FLIP_AXIS[1], M.MODEL_FLIP_AXIS[2], M.MODEL_FLIP_AXIS[3] },
		degrees = mode == M.MODE_HAMMER and M.MODEL_FLIP_DEGREES or 0,
	}
end

function M.new()
	local state = { modes = {} }

	function state:mode(identity)
		return self.modes[identity] or M.MODE_PICK
	end

	function state:set_mode(identity, mode)
		if not _valid_identity(identity) then return false, nil, "invalid identity" end
		if not _valid_mode(mode) then return false, nil, "invalid mode" end
		if self:mode(identity) == mode then return false, nil end
		if mode == M.MODE_PICK then self.modes[identity] = nil else self.modes[identity] = mode end
		return true, {
			channel = M.CHANNEL,
			schema = M.SCHEMA,
			identity = identity,
			mode = mode,
		}
	end

	function state:toggle(identity)
		local next_mode = self:mode(identity) == M.MODE_PICK and M.MODE_HAMMER or M.MODE_PICK
		local changed, payload, err = self:set_mode(identity, next_mode)
		return next_mode, payload, err, changed
	end

	function state:apply_remote(payload)
		if type(payload) ~= "table" or payload.channel ~= M.CHANNEL
				or payload.schema ~= M.SCHEMA then
			return false, "invalid envelope"
		end
		local changed, _, err = self:set_mode(payload.identity, payload.mode)
		return changed, err
	end

	function state:clear(identity)
		self.modes[identity] = nil
	end

	return state
end

return M
