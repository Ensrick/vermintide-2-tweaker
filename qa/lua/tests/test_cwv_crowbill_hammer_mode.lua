return function(H, repo_root)
	local policy = dofile(repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_crowbill_hammer_mode.lua")

	local function clone(value, seen)
		if type(value) ~= "table" then return value end
		seen = seen or {}
		if seen[value] then return seen[value] end
		local copy = {}
		seen[value] = copy
		for key, child in pairs(value) do copy[clone(key, seen)] = clone(child, seen) end
		return copy
	end

	local profiles_by_action = {
		heavy_attack = "crow_heavy",
		heavy_attack_left = "crow_heavy",
		heavy_attack_right_up = "crow_heavy_diag",
		light_attack_left = "shared_burn_light",
		light_attack_right = "crow_light_diag",
		light_attack_last = "shared_pointy_light",
		light_attack_upper = "crow_light_flat",
		light_attack_bopp = "crow_light_upper",
	}

	local function fixture()
		local action_one = {
			default = { kind = "melee_start", anim_time_scale = 0.95, total_time = math.huge },
			push = { kind = "push_stagger", damage_profile_inner = "medium_push" },
		}
		local damage_profiles, power_levels = {}, {}
		for action_name, profile_name in pairs(profiles_by_action) do
			action_one[action_name] = {
				kind = "sweep",
				damage_profile = profile_name,
				anim_time_scale = action_name:find("heavy", 1, true) and 1.14 or 1.045,
				total_time = 1.5,
				damage_window_start = 0.2,
				damage_window_end = 0.4,
			}
			if not damage_profiles[profile_name] then
				damage_profiles[profile_name] = {
					charge_value = action_name:find("light", 1, true) and "light_attack" or "heavy_attack",
					cleave_distribution = "cleave_" .. profile_name,
					armor_modifier = "armor_" .. profile_name,
					critical_strike = "crit_" .. profile_name,
					default_target = "default_" .. profile_name,
					targets = "targets_" .. profile_name,
				}
				power_levels["cleave_" .. profile_name] = { attack = 2, impact = 3 }
				power_levels["armor_" .. profile_name] = {
					attack = { 1, 0.75, 1, 1, 0.5, 0.25 }, impact = { 1, 1, 1, 1, 1, 0.5 },
				}
				power_levels["crit_" .. profile_name] = {
					attack_armor_power_modifer = { 1, 1, 2, 1, 1 },
				}
				power_levels["default_" .. profile_name] = {
					power_distribution = { attack = 10, impact = 20 },
				}
				power_levels["targets_" .. profile_name] = {
					{
						armor_modifier = { attack = { 1, 1, 2, 1, 1, 0.5 } },
						power_distribution = { attack = 30, impact = 40 },
					},
					{ power_distribution = { attack = 5, impact = 6 } },
				}
			end
		end
		return {
			actions = { action_one = action_one, action_two = { default = { kind = "block" } } },
			wield_anim = "to_1h_crowbill",
			state_machine = "units/first_person/1h_crowbill",
		}, damage_profiles, power_levels
	end

	H.test("CWV Crowbill hammer clone covers exact Sienna release actions", function()
		H.equal(policy.SOURCE_TEMPLATE_KEY, "one_handed_crowbill")
		local count = 0
		for _ in pairs(policy.DIRECT_ACTIONS) do count = count + 1 end
		H.equal(count, 8)
		H.equal(policy.DIRECT_ACTIONS.light_attack_bopp, "light")
		H.equal(policy.DIRECT_ACTIONS.heavy_attack_right_up, "heavy")
		H.equal(policy.DIRECT_ACTIONS.push, nil)
	end)

	H.test("CWV Crowbill hammer clone scales direct damage and both cleave axes", function()
		local source, damage_profiles, power_levels = fixture()
		local source_copy = clone(source)
		local profile_copy = clone(damage_profiles)
		local power_copy = clone(power_levels)
		local recorded, registered = {}, {}
		local hammer, generated = policy.build_hammer_template(source, damage_profiles,
			power_levels, clone,
			function(key, original) recorded[key] = original end,
			function(key) registered[key] = true end)
		H.truthy(hammer)

		for action_name, original_profile in pairs(profiles_by_action) do
			local info = generated[action_name]
			H.equal(info.source, original_profile)
			H.equal(hammer.actions.action_one[action_name].damage_profile, info.generated)
			H.equal(recorded[info.generated], original_profile)
			H.equal(registered[info.generated], true)
			local profile = damage_profiles[info.generated]
			H.equal(power_levels[profile.cleave_distribution].attack, 3.2)
			H.truthy(math.abs(power_levels[profile.cleave_distribution].impact - 4.8) < 0.000001)
			H.equal(power_levels[profile.default_target].power_distribution.attack, 8.5)
			H.equal(power_levels[profile.default_target].power_distribution.impact, 20)
			H.equal(power_levels[profile.targets][1].power_distribution.attack, 25.5)
			H.equal(power_levels[profile.targets][1].power_distribution.impact, 40)
		end

		-- Donor action graph/timings and every vanilla profile/power row are exact.
		for action_name in pairs(profiles_by_action) do
			H.equal(source.actions.action_one[action_name].damage_profile,
				source_copy.actions.action_one[action_name].damage_profile)
			H.equal(hammer.actions.action_one[action_name].anim_time_scale,
				source.actions.action_one[action_name].anim_time_scale)
			H.equal(hammer.actions.action_one[action_name].total_time, 1.5)
		end
		H.deep_equal(damage_profiles.crow_heavy, profile_copy.crow_heavy)
		H.deep_equal(power_levels.cleave_crow_heavy, power_copy.cleave_crow_heavy)
		H.equal(hammer.actions.action_one.push.damage_profile_inner, "medium_push")
		H.equal(hammer.wield_anim, "to_1h_crowbill")
	end)

	H.test("CWV Crowbill hammer lights lose armor piercing but heavies retain it", function()
		local source, damage_profiles, power_levels = fixture()
		local hammer, generated = policy.build_hammer_template(source, damage_profiles,
			power_levels, clone)
		for action_name, info in pairs(generated) do
			local profile = damage_profiles[info.generated]
			local armor = power_levels[profile.armor_modifier]
			local first = power_levels[profile.targets][1]
			if policy.LIGHT_ACTIONS[action_name] then
				H.equal(armor.attack[2], 0)
				H.equal(armor.attack[6], 0)
				H.equal(first.armor_modifier.attack[2], 0)
				H.equal(first.armor_modifier.attack[6], 0)
			else
				H.equal(armor.attack[2], 0.75)
				H.equal(first.armor_modifier.attack[2], 1)
			end
		end
		H.truthy(hammer)
	end)

	H.test("CWV Crowbill generated rows are deterministic and never compound", function()
		local source, damage_profiles, power_levels = fixture()
		local first, generated_first = policy.build_hammer_template(source, damage_profiles,
			power_levels, clone)
		local second, generated_second = policy.build_hammer_template(source, damage_profiles,
			power_levels, clone)
		for action_name, first_info in pairs(generated_first) do
			H.equal(generated_second[action_name].generated, first_info.generated)
			local profile = damage_profiles[first_info.generated]
			H.equal(power_levels[profile.cleave_distribution].attack, 3.2)
			H.equal(first.actions.action_one[action_name].damage_profile,
				second.actions.action_one[action_name].damage_profile)
		end
	end)

	H.test("CWV Crowbill mode state emits one bounded transition and validates peers", function()
		local state = policy.new()
		local identity = "peer:slot_melee:cwv_imperial_crowbill_001"
		H.equal(state:mode(identity), policy.MODE_PICK)
		local mode, payload, err, changed = state:toggle(identity)
		H.equal(mode, policy.MODE_HAMMER)
		H.equal(err, nil)
		H.equal(changed, true)
		H.equal(payload.channel, policy.CHANNEL)
		H.equal(payload.schema, 1)
		H.equal(payload.identity, identity)
		H.equal(payload.mode, policy.MODE_HAMMER)
		local no_change, no_payload = state:set_mode(identity, policy.MODE_HAMMER)
		H.equal(no_change, false)
		H.equal(no_payload, nil)

		local remote = policy.new()
		local applied, remote_err = remote:apply_remote(payload)
		H.equal(applied, true)
		H.equal(remote_err, nil)
		H.equal(remote:mode(identity), policy.MODE_HAMMER)
		local duplicate = remote:apply_remote(payload)
		H.equal(duplicate, false)
		local bad, _, bad_err = state:set_mode(string.rep("x", 97), policy.MODE_PICK)
		H.equal(bad, false)
		H.equal(bad_err, "invalid identity")
	end)

	H.test("CWV Crowbill model flip is exact local haft-axis rotation", function()
		local pick = policy.rotation_for_mode(policy.MODE_PICK)
		local hammer = policy.rotation_for_mode(policy.MODE_HAMMER)
		H.deep_equal(pick.axis, { 0, 0, 1 })
		H.equal(pick.degrees, 0)
		H.deep_equal(hammer.axis, { 0, 0, 1 })
		H.equal(hammer.degrees, 180)
		H.equal(policy.rotation_for_mode("invalid"), nil)
	end)
end
