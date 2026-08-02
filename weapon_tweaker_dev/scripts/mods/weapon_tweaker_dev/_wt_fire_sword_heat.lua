-- Issue #942: heat-scaled Fire Sword melee policy.
-- Engine-free. The entry owns hooks, settings, and extension lookup.
local M = {}

M.ENABLED_SETTING = "wt_fire_sword_heat_scaling"
M.CLEAVE_SETTING = "wt_fire_sword_heat_cleave_per_point"
M.DAMAGE_SETTING = "wt_fire_sword_heat_damage_per_point"
M.ARMOR_SETTING = "wt_fire_sword_heat_light_armor"
M.ARMOR_THRESHOLD_SETTING = "wt_fire_sword_heat_armor_threshold"
M.TEMPLATE = "flaming_sword_template_1"
M.PROFILE_PREFIX = "wt_fire_heat_"
M.DEFAULT_CLEAVE_PERCENT = 2
M.DEFAULT_DAMAGE_PERCENT = 1
M.DEFAULT_ARMOR_THRESHOLD = 25
M.MAX_PERCENT_PER_POINT = 5
M.MAX_HEAT = 100

local PROFILE_FIELDS = { "damage_profile", "damage_profile_left", "damage_profile_right" }

local function clamp(value, low, high, fallback)
	value = tonumber(value)
	if not value then return fallback end
	return math.max(low, math.min(high, value))
end

function M.config(values, force_off)
	values = type(values) == "table" and values or {}
	local armor = values[M.ARMOR_SETTING]
	if armor == nil then armor = true end
	return {
		enabled = not force_off and values[M.ENABLED_SETTING] == true,
		cleave_per_heat = clamp(values[M.CLEAVE_SETTING], 0, M.MAX_PERCENT_PER_POINT,
			M.DEFAULT_CLEAVE_PERCENT) / 100,
		damage_per_heat = clamp(values[M.DAMAGE_SETTING], 0, M.MAX_PERCENT_PER_POINT,
			M.DEFAULT_DAMAGE_PERCENT) / 100,
		armor_enabled = armor == true,
		armor_threshold = clamp(values[M.ARMOR_THRESHOLD_SETTING], 0, M.MAX_HEAT,
			M.DEFAULT_ARMOR_THRESHOLD),
	}
end

function M.heat_value(extension)
	if type(extension) ~= "table" or type(extension.current_overcharge_status) ~= "function" then
		return 0
	end
	local ok, value, _, maximum = pcall(extension.current_overcharge_status, extension)
	if not ok or type(value) ~= "number" then return 0 end
	local upper = type(maximum) == "number" and math.max(0, maximum) or M.MAX_HEAT
	return math.max(0, math.min(upper, value))
end

function M.scale_direct_damage(damage, profile, heat, config)
	if type(damage) ~= "number" or type(profile) ~= "table"
			or profile._wt_fire_sword_heat_direct ~= true then return damage end
	config = config or {}
	heat = tonumber(heat) or 0
	if config.enabled ~= true or heat <= 0 then return damage end
	return damage * (1 + heat * (tonumber(config.damage_per_heat) or 0))
end

function M.scale_cleave_power(power, profile, heat, config)
	if type(power) ~= "number" or type(profile) ~= "table"
			or profile._wt_fire_sword_heat_direct ~= true then return power end
	config = config or {}
	heat = tonumber(heat) or 0
	if config.enabled ~= true or heat <= 0 then return power end
	return power * (1 + heat * (tonumber(config.cleave_per_heat) or 0))
end

local function profile_key(source, light, hot)
	return M.PROFILE_PREFIX .. (light and "light_" or "direct_")
		.. source .. (hot and "_armor" or "")
end

local function each_action(template, fn)
	for _, group in pairs(type(template) == "table" and template.actions or {}) do
		if type(group) == "table" then
			for name, action in pairs(group) do
				if type(action) == "table" then fn(name, action) end
			end
		end
	end
end

local function armor_attack(profile, power_levels)
	local modifier = profile and profile.armor_modifier
	if type(modifier) == "string" then modifier = power_levels and power_levels[modifier] end
	return type(modifier) == "table" and type(modifier.attack) == "table"
		and tonumber(modifier.attack[2]) or 0
end

function M.new()
	local state = {
		originals = setmetatable({}, { __mode = "k" }),
		hot_by_base = {},
		active = false,
	}

	function state:apply(enabled, weapons, profiles, power_levels, clone, register,
			fallback_map, parity_allowed)
		local template = weapons and weapons[M.TEMPLATE]
		if type(template) ~= "table" or type(profiles) ~= "table" or type(clone) ~= "function" then
			return 0
		end
		local targets, definitions = {}, {}
		each_action(template, function(_, action)
			local direct = action.kind == "sweep" or action.kind == "charged_sweep"
				or action.kind == "shield_slam"
			if not direct then return end
			local light = action.charge_value == "light_attack"
			local originals = self.originals[action]
			if not originals then
				originals = {}
				for _, field in ipairs(PROFILE_FIELDS) do
					if type(action[field]) == "string" then originals[field] = action[field] end
				end
				self.originals[action] = originals
			end
			for field, source in pairs(originals) do
				local base = profile_key(source, light, false)
				definitions[base] = { source = source, light = light }
				targets[#targets + 1] = { action = action, field = field, source = source, base = base }
			end
		end)

		local keys = {}
		for key in pairs(definitions) do keys[#keys + 1] = key end
		table.sort(keys)
		for _, key in ipairs(keys) do
			local row = definitions[key]
			local source = profiles[row.source]
			if type(source) == "table" then
				if type(profiles[key]) ~= "table" then
					local copy = clone(source)
					copy._wt_fire_sword_heat_direct = true
					copy._wt_fire_sword_heat_light = row.light
					profiles[key] = copy
				end
				if fallback_map then fallback_map[key] = row.source end
				if register then register(key) end
				if row.light and armor_attack(source, power_levels) <= 0
						and type(power_levels and power_levels.armor_modifier_linesman_H) == "table" then
					local hot = profile_key(row.source, true, true)
					if type(profiles[hot]) ~= "table" then
						local copy = clone(profiles[key])
						copy.armor_modifier = "armor_modifier_linesman_H"
						profiles[hot] = copy
					end
					self.hot_by_base[key] = hot
					if fallback_map then fallback_map[hot] = row.source end
					if register then register(hot) end
				end
			end
		end

		local apply_custom = enabled == true and parity_allowed == true
		for _, target in ipairs(targets) do
			target.action[target.field] = apply_custom and target.base or target.source
		end
		self.active = apply_custom
		return #targets
	end

	function state:profile_for_heat(name, heat, config)
		if not self.active or type(name) ~= "string" then return name end
		config = config or {}
		if config.enabled == true and config.armor_enabled == true
				and (tonumber(heat) or 0) > (tonumber(config.armor_threshold) or math.huge) then
			return self.hot_by_base[name] or name
		end
		return name
	end

    return state
end

function M.register_regression(register, clone)
    register("issue942_fire_sword_heat_boundary", function()
        local slash = { armor_modifier = "armor_light", marker = "source" }
        local profiles = { slash = slash }
        local power = {
            armor_light = { attack = { 1, 0 } },
            armor_modifier_linesman_H = { attack = { 1, 0.3 } },
        }
        local light = { kind = "sweep", charge_value = "light_attack", damage_profile = "slash" }
        local burn = { kind = "buff", damage_profile = "burning_dot_1tick" }
        local weapons = { [M.TEMPLATE] = {
            actions = { action_one = { light = light, burn = burn } },
        } }
        local fallback = {}
        local state = M.new()
        local count = state:apply(true, weapons, profiles, power, clone, nil, fallback, true)
        local config = M.config({ [M.ENABLED_SETTING] = true })
        local custom = profiles.wt_fire_heat_light_slash
        if count ~= 1 or light.damage_profile ~= "wt_fire_heat_light_slash"
                or burn.damage_profile ~= "burning_dot_1tick" or not custom
                or custom._wt_fire_sword_heat_direct ~= true
                or slash._wt_fire_sword_heat_direct ~= nil then
            return "#942 direct-melee isolation or burn exclusion drifted"
        end
        if math.abs(M.scale_direct_damage(100, custom, 25, config) - 125) > 0.000001
                or math.abs(M.scale_cleave_power(100, custom, 25, config) - 150) > 0.000001
                or M.scale_direct_damage(100, slash, 25, config) ~= 100 then
            return "#942 default absolute-heat scaling drifted"
        end
        if state:profile_for_heat(light.damage_profile, 25, config) ~= light.damage_profile
                or state:profile_for_heat(light.damage_profile, 25.1, config)
                    ~= "wt_fire_heat_light_slash_armor" then
            return "#942 strict armor-threshold boundary drifted"
        end
        state:apply(false, weapons, profiles, power, clone, nil, fallback, true)
        if light.damage_profile ~= "slash" then
            return "#942 disable did not restore the exact source profile"
        end
    end)
end

return M
