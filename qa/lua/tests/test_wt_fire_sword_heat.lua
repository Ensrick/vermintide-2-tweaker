return function(H, repo_root)
	local path = repo_root .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_fire_sword_heat.lua"
	local policy = dofile(path)

	local function clone(value, seen)
		if type(value) ~= "table" then return value end
		seen = seen or {}
		if seen[value] then return seen[value] end
		local copy = {}; seen[value] = copy
		for key, child in pairs(value) do copy[clone(key, seen)] = clone(child, seen) end
		return copy
	end


	H.test("WT Dev #942 config uses absolute heat defaults and clamps inputs", function()
		local config = policy.config({
			[policy.ENABLED_SETTING] = true,
			[policy.CLEAVE_SETTING] = 99,
			[policy.DAMAGE_SETTING] = -5,
			[policy.ARMOR_THRESHOLD_SETTING] = 120,
		})
		H.equal(config.enabled, true)
		H.equal(config.cleave_per_heat, 0.05)
		H.equal(config.damage_per_heat, 0)
		H.equal(config.armor_enabled, true)
		H.equal(config.armor_threshold, 100)
		H.equal(policy.config({}, false).cleave_per_heat, 0.02)
		H.equal(policy.config({}, false).damage_per_heat, 0.01)
		H.equal(policy.config({ [policy.ENABLED_SETTING] = true }, true).enabled, false)
	end)

	H.test("WT Dev #942 heat reader is bounded and failure-safe", function()
		H.equal(policy.heat_value(nil), 0)
		H.equal(policy.heat_value({ current_overcharge_status = function() return 30, 20, 40 end }), 30)
		H.equal(policy.heat_value({ current_overcharge_status = function() return 70, 20, 60 end }), 60)
		H.equal(policy.heat_value({ current_overcharge_status = function() error("bad extension") end }), 0)
	end)

	H.test("WT Dev #942 scales only marked direct melee and never an unmarked burn", function()
		local config = policy.config({ [policy.ENABLED_SETTING] = true })
		local direct = { _wt_fire_sword_heat_direct = true }
		local burn = { dot_template_name = "burning_dot_1tick" }
		H.equal(policy.scale_direct_damage(10, direct, 25, config), 12.5)
		H.equal(policy.scale_cleave_power(100, direct, 25, config), 150)
		H.equal(policy.scale_direct_damage(10, burn, 25, config), 10)
		H.equal(policy.scale_cleave_power(100, burn, 25, config), 100)
		H.equal(policy.scale_direct_damage(10, direct, 0, config), 10)
	end)

	H.test("WT Dev #942 profile transaction is deterministic parity-gated and reversible", function()
		local slash = { armor_modifier = "armor_light", marker = "slash" }
		local stab = { armor_modifier = "armor_stab", marker = "stab" }
		local heavy = { armor_modifier = "armor_heavy", marker = "heavy" }
		local profiles = {
			slash = slash, stab = stab, heavy = heavy,
		}
		local power = {
			armor_light = { attack = { 1, 0 } },
			armor_stab = { attack = { 1, 0.25 } },
			armor_heavy = { attack = { 1, 0.3 } },
			armor_modifier_linesman_H = { attack = { 1, 0.3 } },
		}
		local actions = {
			light_swing = { kind = "sweep", charge_value = "light_attack", damage_profile = "slash" },
			light_stab = { kind = "sweep", charge_value = "light_attack", damage_profile = "stab" },
			heavy = { kind = "sweep", charge_value = "heavy_attack", damage_profile = "heavy" },
			burn = { kind = "buff", damage_profile = "burning_dot_1tick" },
		}
		local weapons = { [policy.TEMPLATE] = { actions = { action_one = actions } } }
		local registered, fallback = {}, {}
		local state = policy.new()
		local count = state:apply(true, weapons, profiles, power, clone,
			function(name) registered[#registered + 1] = name end, fallback, true)
		H.equal(count, 3)
		H.equal(actions.light_swing.damage_profile, "wt_fire_heat_light_slash")
		H.equal(actions.light_stab.damage_profile, "wt_fire_heat_light_stab")
		H.equal(actions.heavy.damage_profile, "wt_fire_heat_direct_heavy")
		H.equal(actions.burn.damage_profile, "burning_dot_1tick")
		H.equal(profiles.wt_fire_heat_light_slash._wt_fire_sword_heat_direct, true)
		H.equal(profiles.wt_fire_heat_light_slash_armor.armor_modifier,
			"armor_modifier_linesman_H")
		H.equal(profiles.wt_fire_heat_light_stab_armor, nil,
			"an already armor-capable stab must not receive a replacement")
		H.equal(state:profile_for_heat(actions.light_swing.damage_profile, 25,
			policy.config({ [policy.ENABLED_SETTING] = true })), actions.light_swing.damage_profile)
		H.equal(state:profile_for_heat(actions.light_swing.damage_profile, 25.1,
			policy.config({ [policy.ENABLED_SETTING] = true })),
			"wt_fire_heat_light_slash_armor")
		H.equal(fallback.wt_fire_heat_light_slash_armor, "slash")

		state:apply(true, weapons, profiles, power, clone, nil, fallback, false)
		H.equal(actions.light_swing.damage_profile, "slash")
		H.equal(actions.light_stab.damage_profile, "stab")
		H.equal(actions.heavy.damage_profile, "heavy")
		state:apply(false, weapons, profiles, power, clone, nil, fallback, true)
		H.equal(actions.light_swing.damage_profile, "slash")
		H.truthy(#registered >= 4, "all private profiles must register deterministically")
	end)
end
