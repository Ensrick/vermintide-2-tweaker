return function(H, repo_root)
	local policy = dofile(repo_root
		.. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_axe_balance.lua")
	local function read(path)
		local file = assert(io.open(path, "rb"))
		local source = file:read("*a")
		file:close()
		return source
	end

	local function clone(value, seen)
		if type(value) ~= "table" then return value end
		seen = seen or {}
		if seen[value] then return seen[value] end
		local copy = {}
		seen[value] = copy
		for key, child in pairs(value) do copy[clone(key, seen)] = clone(child, seen) end
		return copy
	end

	local function axe_template()
		return {
			actions = { action_one = {
				light_attack_left = {
					kind = "sweep", additional_critical_strike_chance = 0,
					damage_profile = "axe_light",
				},
				light_attack_up = {
					kind = "sweep", additional_critical_strike_chance = 0.1,
					damage_profile = "axe_light",
				},
				light_attack_bopp = {
					kind = "sweep", damage_profile_left = "axe_bopp",
					damage_profile_right = "axe_bopp",
				},
				heavy_attack = {
					kind = "sweep", additional_critical_strike_chance = 0,
					damage_profile_left = "axe_heavy",
					damage_profile_right = "axe_heavy",
				},
				default = { kind = "melee_start" },
				push = { kind = "push_stagger", damage_profile_inner = "push" },
			} },
		}
	end

	H.test("WT #601 Greataxe light crit floors at ten percent and optionally includes the CWV clone", function()
		local native, cwv = axe_template(), axe_template()
		local weapons = {
			two_handed_axes_template_1 = native,
			cwv_greataxe_template = cwv,
		}
		local state = policy.new()
		state:apply_greataxe_crit(true, weapons)
		for _, template in ipairs({ native, cwv }) do
			local actions = template.actions.action_one
			H.equal(actions.light_attack_left.additional_critical_strike_chance, 0.1)
			H.equal(actions.light_attack_up.additional_critical_strike_chance, 0.1)
			H.equal(actions.light_attack_bopp.additional_critical_strike_chance, 0.1)
			H.equal(actions.heavy_attack.additional_critical_strike_chance, 0)
		end
		state:apply_greataxe_crit(true, weapons)
		H.equal(native.actions.action_one.light_attack_up.additional_critical_strike_chance, 0.1)
		state:apply_greataxe_crit(false, weapons)
		H.equal(native.actions.action_one.light_attack_left.additional_critical_strike_chance, 0)
		H.equal(native.actions.action_one.light_attack_up.additional_critical_strike_chance, 0.1)
		H.equal(native.actions.action_one.light_attack_bopp.additional_critical_strike_chance, nil)
	end)

	H.test("WT #601 light crit preserves a stronger authored bonus", function()
		local native = axe_template()
		native.actions.action_one.light_attack_left.additional_critical_strike_chance = 0.15
		local state = policy.new()
		state:apply_greataxe_crit(true, { two_handed_axes_template_1 = native })
		H.equal(native.actions.action_one.light_attack_left.additional_critical_strike_chance, 0.15)
		state:apply_greataxe_crit(false, { two_handed_axes_template_1 = native })
		H.equal(native.actions.action_one.light_attack_left.additional_critical_strike_chance, 0.15)
	end)

	H.test("WT #601 Dual Axes light crit excludes heavy and utility actions", function()
		local dual = axe_template()
		local state = policy.new()
		state:apply_dual_crit(true, { dual_wield_axes_template_1 = dual })
		local actions = dual.actions.action_one
		H.equal(actions.light_attack_left.additional_critical_strike_chance, 0.1)
		H.equal(actions.light_attack_bopp.additional_critical_strike_chance, 0.1)
		H.equal(actions.heavy_attack.additional_critical_strike_chance, 0)
		H.equal(actions.default.additional_critical_strike_chance, nil)
		H.equal(actions.push.additional_critical_strike_chance, nil)
	end)

	H.test("WT #601 Dual Axes cleave clones all direct profiles and restores exactly", function()
		local dual = axe_template()
		local damage_profiles = {
			axe_light = { cleave_distribution = "cleave_light", marker = "light" },
			axe_bopp = { cleave_distribution = { attack = 3, impact = 5 }, marker = "bopp" },
			axe_heavy = { cleave_distribution = "cleave_heavy", marker = "heavy" },
		}
		local power_levels = {
			cleave_light = { attack = 2, impact = 4 },
			cleave_heavy = { attack = 6, impact = 8 },
		}
		local registered = {}
		local state = policy.new()
		state:apply_dual_cleave(true, { dual_wield_axes_template_1 = dual },
			damage_profiles, power_levels, clone,
			function(generated) registered[generated] = true end)
		local actions = dual.actions.action_one
		H.equal(actions.light_attack_left.damage_profile, "wt_axe_cleave_axe_light")
		H.equal(actions.light_attack_bopp.damage_profile_left, "wt_axe_cleave_axe_bopp")
		H.equal(actions.light_attack_bopp.damage_profile_right, "wt_axe_cleave_axe_bopp")
		H.equal(actions.heavy_attack.damage_profile_left, "wt_axe_cleave_axe_heavy")
		H.equal(power_levels[damage_profiles.wt_axe_cleave_axe_light.cleave_distribution].attack, 2.2)
		H.equal(power_levels[damage_profiles.wt_axe_cleave_axe_heavy.cleave_distribution].impact, 8.8)
		H.truthy(math.abs(damage_profiles.wt_axe_cleave_axe_bopp.cleave_distribution.attack - 3.3) < 0.000001)
		H.equal(damage_profiles.wt_axe_cleave_axe_bopp.marker, "bopp")
		H.equal(power_levels.cleave_light.attack, 2)
		H.equal(damage_profiles.axe_bopp.cleave_distribution.attack, 3)
		H.equal(registered.wt_axe_cleave_axe_light, true)
		H.equal(actions.push.damage_profile_inner, "push")
		state:apply_dual_cleave(false, { dual_wield_axes_template_1 = dual },
			damage_profiles, power_levels, clone)
		H.equal(actions.light_attack_left.damage_profile, "axe_light")
		H.equal(actions.light_attack_bopp.damage_profile_left, "axe_bopp")
		H.equal(actions.heavy_attack.damage_profile_right, "axe_heavy")
	end)

	H.test("WT #601 Dual Axes crit and cleave toggles remain independent", function()
		local dual = axe_template()
		local weapons = { dual_wield_axes_template_1 = dual }
		local profiles = { axe_light = { cleave_distribution = { attack = 1, impact = 1 } } }
		local state = policy.new()
		state:apply_dual_crit(true, weapons)
		state:apply_dual_cleave(true, weapons, profiles, {}, clone)
		state:apply_dual_crit(false, weapons)
		H.equal(dual.actions.action_one.light_attack_left.additional_critical_strike_chance, 0)
		H.equal(dual.actions.action_one.light_attack_left.damage_profile, "wt_axe_cleave_axe_light")
		state:apply_dual_cleave(false, weapons, profiles, {}, clone)
		H.equal(dual.actions.action_one.light_attack_left.damage_profile, "axe_light")
	end)

	H.test("WT #601 settings default on and compose with canonical lifecycle", function()
		local data = read(repo_root
			.. "/weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker_data.lua")
		for _, id in ipairs({
			policy.GREATAXE_LIGHT_CRIT_SETTING,
			policy.DUAL_AXES_LIGHT_CRIT_SETTING,
			policy.DUAL_AXES_CLEAVE_SETTING,
		}) do
			local at = assert(data:find('setting_id = "' .. id .. '"', 1, true))
			local row = data:sub(at, at + 220)
			H.truthy(row:find("default_value = true", 1, true))
		end
		local source = read(repo_root
			.. "/weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua")
		H.truthy(source:find("mod._wt_apply_axe_balance(nil, false)", 1, true))
		H.truthy(source:find("mod._wt_apply_axe_balance(nil, true)", 1, true))
		H.truthy(source:find("mod._wt_apply_axe_balance(setting_id, false)", 1, true))
		local cwv_data = read(repo_root .. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants_data.lua")
		H.equal(cwv_data:find(policy.GREATAXE_LIGHT_CRIT_SETTING, 1, true), nil)
	end)
end
