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

	local function one_hand_axe_template()
		local template = axe_template()
		template.weapon_type = "AXE_1H"
		template.buff_type = "MELEE_1H"
		template.state_machine =
			"units/beings/player/first_person_base/state_machines/melee/1h_axe"
		return template
	end

	H.test("WT #621 discovers single 1H Axe clones by capability and excludes neighboring axe families", function()
		local single = one_hand_axe_template()
		local clone_template = clone(single)
		local dual = clone(single)
		dual.left_hand_unit = "axe_offhand"
		dual.state_machine = "units/beings/player/first_person_base/state_machines/melee/dual_axes"
		local shield = clone(single)
		shield.left_hand_unit = "shield"
		shield.weapon_type = "AXE_1H_SHIELD"
		shield.state_machine = "units/beings/player/first_person_base/state_machines/melee/1h_axe_shield"
		local two_hand = clone(single)
		two_hand.weapon_type = "AXE_2H"
		two_hand.buff_type = "MELEE_2H"
		two_hand.state_machine = "units/beings/player/first_person_base/state_machines/melee/2h_hammer"
		H.equal(policy.is_one_hand_axe_template(single), true)
		H.equal(policy.is_one_hand_axe_template(clone_template), true)
		H.equal(policy.is_one_hand_axe_template(dual), false)
		H.equal(policy.is_one_hand_axe_template(shield), false)
		H.equal(policy.is_one_hand_axe_template(two_hand), false)
	end)

	H.test("WT #621 1H Axe cleave clones private profiles, registers deterministically, and restores", function()
		local native, compatible_clone = one_hand_axe_template(), one_hand_axe_template()
		local excluded_dual = one_hand_axe_template()
		excluded_dual.left_hand_unit = "offhand"
		excluded_dual.state_machine = "units/beings/player/first_person_base/state_machines/melee/dual_axes"
		local profiles = {
			axe_light = { cleave_distribution = "cleave_light", marker = "source" },
			axe_bopp = { cleave_distribution = { attack = 3, impact = 5 } },
			axe_heavy = { cleave_distribution = "cleave_heavy" },
		}
		local powers = {
			cleave_light = { attack = 2, impact = 4 },
			cleave_heavy = { attack = 6, impact = 8 },
		}
		local registered, fallback = {}, {}
		local state = policy.new()
		local template_count = state:apply_one_hand_axe_cleave(true, {
			z_compatible_clone = compatible_clone,
			a_native = native,
			dual_wield_axes_template_1 = excluded_dual,
		}, profiles, powers, clone, function(key) registered[#registered + 1] = key end,
			fallback, true)
		H.equal(template_count, 2)
		H.equal(native.actions.action_one.light_attack_left.damage_profile,
			"wt_1h_axe_cleave_90_axe_light")
		H.equal(compatible_clone.actions.action_one.heavy_attack.damage_profile_left,
			"wt_1h_axe_cleave_90_axe_heavy")
		H.equal(excluded_dual.actions.action_one.light_attack_left.damage_profile, "axe_light")
		H.truthy(math.abs(powers[profiles.wt_1h_axe_cleave_90_axe_light.cleave_distribution].attack - 1.8) < 0.000001)
		H.truthy(math.abs(profiles.wt_1h_axe_cleave_90_axe_bopp.cleave_distribution.impact - 4.5) < 0.000001)
		H.equal(profiles.axe_light.marker, "source")
		H.equal(powers.cleave_light.attack, 2)
		H.deep_equal(registered, {
			"wt_1h_axe_cleave_90_axe_bopp",
			"wt_1h_axe_cleave_90_axe_heavy",
			"wt_1h_axe_cleave_90_axe_light",
		})
		H.equal(fallback.wt_1h_axe_cleave_90_axe_heavy, "axe_heavy")

		state:apply_one_hand_axe_cleave(false, { native = native, clone = compatible_clone },
			profiles, powers, clone, nil, fallback, true)
		H.equal(native.actions.action_one.light_attack_left.damage_profile, "axe_light")
		H.equal(compatible_clone.actions.action_one.heavy_attack.damage_profile_right, "axe_heavy")
	end)

	H.test("WT #621 holds vanilla profile pointers until peer parity is confirmed", function()
		local axe = one_hand_axe_template()
		local profiles = { axe_light = { cleave_distribution = { attack = 1, impact = 1 } },
			axe_bopp = { cleave_distribution = { attack = 1, impact = 1 } },
			axe_heavy = { cleave_distribution = { attack = 1, impact = 1 } } }
		local state = policy.new()
		state:apply_one_hand_axe_cleave(true, { single = axe }, profiles, {}, clone, nil, {}, false)
		H.equal(axe.actions.action_one.light_attack_left.damage_profile, "axe_light")
		state:apply_one_hand_axe_cleave(true, { single = axe }, profiles, {}, clone, nil, {}, true)
		H.equal(axe.actions.action_one.light_attack_left.damage_profile,
			"wt_1h_axe_cleave_90_axe_light")
	end)

	H.test("WT #622 Cog Hammer speed nerf touches only four heavy releases and restores nil fields", function()
		local function action(scale) return { kind = "sweep", anim_time_scale = scale } end
		local actions = {
			heavy_attack_left = action(0.99), heavy_attack_right = action(0.99),
			heavy_attack_left_charged = action(nil), heavy_attack_right_charged = action(nil),
			light_attack_left = action(0.9), light_attack_left_charged = action(0.9),
			light_attack_bopp = action(0.99), push = { kind = "push_stagger" },
			default = { kind = "melee_start" },
		}
		local state = policy.new()
		state:apply_cog_heavy_speed(true, {
			two_handed_cog_hammers_template_1 = { actions = { action_one = actions } },
		})
		H.truthy(math.abs(actions.heavy_attack_left.anim_time_scale - 0.9) < 0.000001)
		H.truthy(math.abs(actions.heavy_attack_left_charged.anim_time_scale - (1 / 1.1)) < 0.000001)
		H.equal(actions.light_attack_left.anim_time_scale, 0.9)
		H.equal(actions.light_attack_left_charged.anim_time_scale, 0.9)
		H.equal(actions.light_attack_bopp.anim_time_scale, 0.99)
		H.equal(actions.push.anim_time_scale, nil)
		state:apply_cog_heavy_speed(true, {
			two_handed_cog_hammers_template_1 = { actions = { action_one = actions } },
		})
		H.truthy(math.abs(actions.heavy_attack_left.anim_time_scale - 0.9) < 0.000001)
		state:apply_cog_heavy_speed(false, {})
		H.equal(actions.heavy_attack_left.anim_time_scale, 0.99)
		H.equal(actions.heavy_attack_left_charged.anim_time_scale, nil)
	end)

	H.test("WT #623 native Mace and Sword slows L1/L2 and heavies without touching CWV reverse clone", function()
		local function action(scale) return { kind = "sweep", anim_time_scale = scale } end
		local native_actions = {
			light_attack_left_diagonal = action(0.945), light_attack_right = action(1.035),
			heavy_attack = action(1.035), heavy_attack_2 = action(1.035),
			light_attack_right_diagonal = action(1.035), light_attack_left = action(0.9),
			light_attack_bopp = action(0.9), push = { kind = "push_stagger" },
		}
		local cwv_actions = clone(native_actions)
		local weapons = {
			dual_wield_hammer_sword_template = { actions = { action_one = native_actions } },
			sword_and_mace_template = { actions = { action_one = cwv_actions } },
		}
		local state = policy.new()
		state:apply_mace_sword_speed(true, weapons)
		H.truthy(math.abs(native_actions.light_attack_left_diagonal.anim_time_scale - (0.945 / 1.1)) < 0.000001)
		H.truthy(math.abs(native_actions.light_attack_right.anim_time_scale - (1.035 / 1.1)) < 0.000001)
		H.truthy(math.abs(native_actions.heavy_attack_2.anim_time_scale - (1.035 / 1.1)) < 0.000001)
		H.equal(native_actions.light_attack_right_diagonal.anim_time_scale, 1.035)
		H.equal(native_actions.light_attack_left.anim_time_scale, 0.9)
		H.equal(native_actions.light_attack_bopp.anim_time_scale, 0.9)
		H.equal(cwv_actions.light_attack_left_diagonal.anim_time_scale, 0.945)
		state:apply_mace_sword_speed(false, weapons)
		H.equal(native_actions.light_attack_left_diagonal.anim_time_scale, 0.945)
		H.equal(native_actions.heavy_attack.anim_time_scale, 1.035)
	end)

	H.test("WT #664 Executioner's Sword applies exact 1.30x only to light headshots", function()
		local source = {
			charge_value = "light_attack", marker = "vanilla",
			default_target = { power_distribution = { attack = 0.075, impact = 0.05 } },
			targets = { { power_distribution = { attack = 0.2, impact = 0.25 } } },
		}
		local profiles = { medium_slashing_linesman_executioner = source }
		local light_left = { kind = "sweep", damage_profile = "medium_slashing_linesman_executioner" }
		local light_right = { kind = "sweep", damage_profile = "medium_slashing_linesman_executioner" }
		local bopp = { kind = "sweep", damage_profile = "medium_slashing_linesman_executioner" }
		local heavy = { kind = "sweep", damage_profile = "heavy_slashing_smiter_executioner" }
		local template = { actions = { action_one = {
			light_attack_left = light_left, light_attack_right = light_right,
			light_attack_bopp = bopp, heavy_attack_left = heavy,
			push = { kind = "push_stagger" }, default = { kind = "melee_start" },
		} } }
		local registered, fallback = {}, {}
		local state = policy.new()
		local count = state:apply_executioner_light_headshot(true, {
			two_handed_swords_executioner_template_1 = template,
		}, profiles, clone, function(key) registered[key] = true end, fallback, true)
		H.equal(count, 3)
		H.equal(light_left.damage_profile, policy.EXECUTIONER_BONUS_PROFILE)
		H.equal(light_right.damage_profile, policy.EXECUTIONER_BONUS_PROFILE)
		H.equal(bopp.damage_profile, policy.EXECUTIONER_BONUS_PROFILE)
		H.equal(heavy.damage_profile, "heavy_slashing_smiter_executioner")
		local custom = profiles[policy.EXECUTIONER_BONUS_PROFILE]
		H.equal(custom.marker, "vanilla")
		H.equal(source._wt_executioner_light_headshot_multiplier, nil)
		H.equal(registered[policy.EXECUTIONER_BONUS_PROFILE], true)
		H.equal(fallback[policy.EXECUTIONER_BONUS_PROFILE], policy.EXECUTIONER_SOURCE_PROFILE)
		H.equal(policy.scale_executioner_headshot_damage(100, "headshot", custom), 130)
		H.equal(policy.scale_executioner_headshot_damage(100, "torso", custom), 100)
		H.equal(policy.scale_executioner_headshot_damage(100, "headshot", source), 100)

		state:apply_executioner_light_headshot(true, {
			two_handed_swords_executioner_template_1 = template,
		}, profiles, clone, nil, fallback, true)
		H.equal(light_left.damage_profile, policy.EXECUTIONER_BONUS_PROFILE)
		state:apply_executioner_light_headshot(false, {
			two_handed_swords_executioner_template_1 = template,
		}, profiles, clone, nil, fallback, true)
		H.equal(light_left.damage_profile, "medium_slashing_linesman_executioner")
		H.equal(light_right.damage_profile, "medium_slashing_linesman_executioner")
		H.equal(bopp.damage_profile, "medium_slashing_linesman_executioner")
	end)

	H.test("WT #664 Executioner's Sword profile waits for peer parity and remains cross-career template scoped", function()
		local profiles = { medium_slashing_linesman_executioner = {
			charge_value = "light_attack", default_target = {}, targets = {},
		} }
		local action = { kind = "sweep", damage_profile = "medium_slashing_linesman_executioner" }
		local template = { actions = { action_one = { light_attack_left = action } } }
		local state = policy.new()
		state:apply_executioner_light_headshot(true, {
			two_handed_swords_executioner_template_1 = template,
		}, profiles, clone, nil, {}, false)
		H.equal(action.damage_profile, "medium_slashing_linesman_executioner")
		state:apply_executioner_light_headshot(true, {
			two_handed_swords_executioner_template_1 = template,
		}, profiles, clone, nil, {}, true)
		H.equal(action.damage_profile, policy.EXECUTIONER_BONUS_PROFILE)
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

	H.test("WT #621/#622/#623 settings default off and share the canonical balance lifecycle", function()
		local data = read(repo_root
			.. "/weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker_data.lua")
		for _, id in ipairs({
			policy.ONE_HAND_AXE_CLEAVE_SETTING,
			policy.COG_HAMMER_HEAVY_SPEED_SETTING,
			policy.MACE_SWORD_SPEED_SETTING,
			policy.EXECUTIONER_LIGHT_HEADSHOT_SETTING,
		}) do
			local at = assert(data:find('setting_id = "' .. id .. '"', 1, true))
			local row = data:sub(at, at + 220)
			H.truthy(row:find("default_value = false", 1, true))
		end
		local source = read(repo_root
			.. "/weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua")
		H.truthy(source:find("apply_one_hand_axe_cleave", 1, true))
		H.truthy(source:find("apply_cog_heavy_speed", 1, true))
		H.truthy(source:find("apply_mace_sword_speed", 1, true))
		H.truthy(source:find("apply_executioner_light_headshot", 1, true))
		H.truthy(source:find("scale_executioner_headshot_damage", 1, true))
		local parity = read(repo_root
			.. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt431_damage_profile_parity.lua")
		H.truthy(parity:find("mod._wt_apply_axe_balance", 1, true))
	end)
end
