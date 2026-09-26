-- Issue #916: pure burn predicate + template burn scrub for Sienna-donor clones.
--
-- Keyed on the burn PROPERTY, never on vanilla profile names: 6.11.3 renamed
-- every Sienna 1h-mace profile (1h_hammers_wizard.lua:236/374/514/914/1053) and
-- a name-keyed swap map silently went inert. The predicate mirrors the engine's
-- own dot lookup, parse_dot_name (damage_utils.lua:3753-3777): a hit's dot comes
-- from targets[target_index], else default_target, else the profile itself. A
-- profile "burns" when ANY of those levels carries dot_template_name. targets
-- is sparse in vanilla (power_level_templates.lua:5707 starts at [2]), so every
-- scan here uses pairs, never ipairs. Engine-free; runs in the offline suite.

local M = {}

-- Every sub-action field vanilla weapon templates use to name a damage profile
-- (sweep, push, slam; the complete `damage_profile*` set in weapon_templates/).
M.PROFILE_FIELDS = {
	"damage_profile",
	"damage_profile_left",
	"damage_profile_right",
	"damage_profile_inner",
	"damage_profile_outer",
	"damage_profile_aoe",
	"damage_profile_target",
}

-- Fields parse_dot_name reads (damage_utils.lua:3758-3772).
local DOT_FIELDS = { "dot_template_name", "dot_balefire_variant" }

-- Engine profiles hold resolved tables by mod-load time
-- (damage_profile_templates.lua:5570-5616); tolerate an unresolved name.
local function resolve(value, power_level_templates)
	if type(value) == "string" and type(power_level_templates) == "table" then
		return power_level_templates[value]
	end
	return value
end

-- Returns the first dot_template_name reachable from `dp`, or nil.
function M.profile_dot(dp, power_level_templates)
	if type(dp) ~= "table" then return nil end
	if dp.dot_template_name then return dp.dot_template_name end
	local default_target = resolve(dp.default_target, power_level_templates)
	if type(default_target) == "table" and default_target.dot_template_name then
		return default_target.dot_template_name
	end
	local targets = resolve(dp.targets, power_level_templates)
	if type(targets) == "table" then
		for _, target in pairs(targets) do
			if type(target) == "table" and target.dot_template_name then
				return target.dot_template_name
			end
		end
	end
	return nil
end

function M.profile_burns(dp, power_level_templates)
	return M.profile_dot(dp, power_level_templates) ~= nil
end

local function strip(target)
	for _, field in ipairs(DOT_FIELDS) do target[field] = nil end
end

-- Deep-clones `dp` with every dot field removed at all three levels. Target
-- tables are cloned too, so the vanilla PowerLevelTemplates rows the donor
-- shares are never mutated.
function M.scrubbed_clone(dp, deep_clone, power_level_templates)
	local clone = deep_clone(dp)
	strip(clone)
	local default_target = resolve(clone.default_target, power_level_templates)
	if type(default_target) == "table" then
		if default_target == dp.default_target or type(clone.default_target) == "string" then
			default_target = deep_clone(default_target)
		end
		strip(default_target)
		clone.default_target = default_target
	end
	local targets = resolve(clone.targets, power_level_templates)
	if type(targets) == "table" then
		if targets == dp.targets or type(clone.targets) == "string" then
			targets = deep_clone(targets)
		end
		for _, target in pairs(targets) do
			if type(target) == "table" then strip(target) end
		end
		clone.targets = targets
	end
	return clone
end

-- Calls fn(group_name, sub_name, sub_action, field, profile_name) for every
-- damage-profile reference in a weapon template's action graph.
function M.each_profile_ref(template, fn)
	if type(template) ~= "table" or type(template.actions) ~= "table" then return end
	for group_name, action_group in pairs(template.actions) do
		if type(action_group) == "table" then
			for sub_name, sub_action in pairs(action_group) do
				if type(sub_action) == "table" then
					for _, field in ipairs(M.PROFILE_FIELDS) do
						local name = sub_action[field]
						if type(name) == "string" then
							fn(group_name, sub_name, sub_action, field, name)
						end
					end
				end
			end
		end
	end
end

-- Rewrites every burning profile reference in `template` (already a private
-- clone) to a scrubbed `prefix .. name` profile.
-- opts: profiles (DamageProfileTemplates), power_levels, prefix, deep_clone,
--       register(new_name, clone, source_name) -> bool.
-- Returns (swapped_refs, scrubbed_profile_names_sorted, failures_sorted).
function M.scrub_template(template, opts)
	local profiles = opts.profiles
	local scrubbed, failed = {}, {}
	local swapped = 0
	M.each_profile_ref(template, function(_, _, sub_action, field, name)
		if scrubbed[name] == nil and failed[name] == nil then
			local dp = type(profiles) == "table" and profiles[name] or nil
			if not M.profile_burns(dp, opts.power_levels) then return end
			local new_name = opts.prefix .. name
			local ok = profiles[new_name] ~= nil
			if not ok then
				ok = opts.register(new_name,
					M.scrubbed_clone(dp, opts.deep_clone, opts.power_levels), name) and true or false
			end
			if ok then scrubbed[name] = new_name else failed[name] = true end
		end
		if scrubbed[name] then
			sub_action[field] = scrubbed[name]
			swapped = swapped + 1
		end
	end)
	local names, failures = {}, {}
	for name in pairs(scrubbed) do names[#names + 1] = name end
	for name in pairs(failed) do failures[#failures + 1] = name end
	table.sort(names)
	table.sort(failures)
	return swapped, names, failures
end

-- Live-donor contract behind the #916 regression check. Reads the donor as the
-- engine loaded it (no name fixture), so a vanilla rename cannot strand it.
-- opts: profiles, power_levels, prefix, wire_sources (cwv name -> vanilla).
-- Returns (failure_or_nil, burning_donor_refs). Zero burning donor refs is a
-- PASS: vanilla dropped the fire, so there is nothing left to scrub.
function M.verify(donor, clone, opts)
	local profiles, power_levels = opts.profiles, opts.power_levels
	if type(profiles) ~= "table" then return "DamageProfileTemplates not loaded", 0 end
	local failure
	M.each_profile_ref(clone, function(group, sub, _, field, name)
		if not failure and M.profile_burns(profiles[name], power_levels) then
			failure = string.format("burn profile reachable from the clone: %s.%s.%s = %s (%s)",
				group, sub, field, name, M.profile_dot(profiles[name], power_levels))
		end
	end)
	if failure then return failure, 0 end
	local burning = 0
	M.each_profile_ref(donor, function(group, sub, _, field, name)
		if failure then return end
		if name:sub(1, 4) == "cwv_" then
			failure = string.format("donor mutated: %s.%s.%s = %s", group, sub, field, name)
			return
		end
		if not M.profile_burns(profiles[name], power_levels) then return end
		burning = burning + 1
		local clone_group = type(clone.actions) == "table" and clone.actions[group] or nil
		local clone_sub = type(clone_group) == "table" and clone_group[sub] or nil
		local got = type(clone_sub) == "table" and clone_sub[field] or nil
		local want = opts.prefix .. name
		if got ~= want then
			failure = string.format("donor burn %s.%s.%s = %s not scrubbed (clone has %s, want %s)",
				group, sub, field, name, tostring(got), want)
		elseif type(profiles[want]) ~= "table" then
			failure = "scrubbed profile not registered: " .. want
		elseif type(opts.wire_sources) ~= "table" or type(opts.wire_sources[want]) ~= "string" then
			failure = "scrubbed profile has no #423 wire source: " .. want
		end
	end)
	return failure, burning
end

-- #423 wire fallback for maul_template's scrubbed profiles: the vanilla id a
-- non-CWV host decodes. Same charge_value and target shape, no burn (checked
-- against 6.11.3 by the optional vanilla scan in test_cwv_burn_scrub.lua).
M.MAUL_WIRE_ANALOG = {
	-- 1h_hammers.lua heavy smiter: heavy_attack, shield_break.
	mace_1h_heavy_smiter_vertical = "medium_blunt_smiter_1h",
	-- 1h_hammers_shield.lua heavy tank: heavy_attack, 3 targets, stagger 1.5.
	mace_1h_heavy_tank_diag       = "medium_blunt_tank_1h",
	-- 1h_hammers.lua light smiter: light_attack.
	mace_1h_light_smiter_vertical = "light_blunt_smiter",
}

-- Picks the vanilla id a non-CWV host decodes for a scrubbed profile (#423
-- wire fallback). Prefer the declared same-shape non-burning analog; accept it
-- only when it exists, does not burn, and shares charge_value with the donor.
-- Otherwise fall back to the burning donor itself (damage parity over fire).
function M.wire_source(donor_name, analogs, profiles, power_levels)
	local analog = type(analogs) == "table" and analogs[donor_name] or nil
	local donor = type(profiles) == "table" and profiles[donor_name] or nil
	local candidate = analog and profiles[analog] or nil
	if type(candidate) == "table" and type(donor) == "table"
			and not M.profile_burns(candidate, power_levels)
			and candidate.charge_value == donor.charge_value then
		return analog, "analog"
	end
	return donor_name, "donor"
end

return M
