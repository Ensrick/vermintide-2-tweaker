return function(H, repo_root)
	local policy = dofile(repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_mace_hammer_identity.lua")
	local function read(path)
		local file = assert(io.open(path, "rb"))
		local source = file:read("*a")
		file:close()
		return source
	end
	local function count(source, needle)
		local hits, offset = 0, 1
		while true do
			local found = source:find(needle, offset, true)
			if not found then return hits end
			hits = hits + 1
			offset = found + #needle
		end
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

	local function fixture_template(profile, scale)
		return {
			actions = {
				action_one = {
					light = { kind = "sweep", damage_profile = profile, anim_time_scale = scale },
					charge = { kind = "melee_start", anim_time_scale = 0.9 },
					shield = { kind = "shield_slam", damage_profile = "shield_slam", anim_time_scale = 0.6 },
					push = { kind = "push_stagger", damage_profile_inner = "push", anim_time_scale = 0.8 },
				},
				action_wield = { default = { kind = "wield", anim_time_scale = 0.7 } },
			},
		}
	end

	H.test("CWV #599 scope excludes every two-handed and mixed family", function()
		H.equal(policy.MACE_SPEED_MULT, 1.05)
		H.equal(policy.HAMMER_DAMAGE_MULT, 1.125)
		H.equal(policy.HAMMER_CLEAVE_MULT, 0.75)
		local all = table.concat(policy.MACE_TEMPLATE_KEYS, ",")
			.. "," .. table.concat(policy.HAMMER_TEMPLATE_KEYS, ",")
		H.equal(all:find("two_handed", 1, true), nil)
		H.equal(all:find("maul", 1, true), nil)
		H.equal(all:find("hammer_book", 1, true), nil)
		H.equal(all:find("hammer_sword", 1, true), nil)
		H.truthy(all:find("one_handed_hammer_shield_priest_template", 1, true))
		H.truthy(all:find("dual_wield_hammers_priest_template", 1, true))
	end)

	H.test("CWV #599 mace speed affects attack cadence only and restores nil exactly", function()
		local weapons = {}
		for _, key in ipairs(policy.MACE_TEMPLATE_KEYS) do weapons[key] = fixture_template("mace_hit") end
		local state = policy.new()
		state:apply(true, weapons, {}, {}, clone)
		for _, key in ipairs(policy.MACE_TEMPLATE_KEYS) do
			local actions = weapons[key].actions
			H.equal(actions.action_one.light.anim_time_scale, 1.05)
			H.truthy(math.abs(actions.action_one.charge.anim_time_scale - 0.945) < 0.000001)
			H.truthy(math.abs(actions.action_one.shield.anim_time_scale - 0.63) < 0.000001)
			H.equal(actions.action_one.push.anim_time_scale, 0.8)
			H.equal(actions.action_wield.default.anim_time_scale, 0.7)
		end
		-- Re-applying ON is idempotent, then OFF restores the absent field.
		state:apply(true, weapons, {}, {}, clone)
		H.equal(weapons[policy.MACE_TEMPLATE_KEYS[1]].actions.action_one.light.anim_time_scale, 1.05)
		state:apply(false, weapons, {}, {}, clone)
		H.equal(weapons[policy.MACE_TEMPLATE_KEYS[1]].actions.action_one.light.anim_time_scale, nil)
	end)

	H.test("CWV #599 hammer profiles clone damage and cleave without changing stagger or source", function()
		local weapons = {}
		for _, key in ipairs(policy.HAMMER_TEMPLATE_KEYS) do weapons[key] = fixture_template("hammer_hit", 1.2) end
		local damage_profiles = {
			hammer_hit = {
				cleave_distribution = "cleave_hammer",
				default_target = "target_hammer",
				targets = "targets_hammer",
				critical_strike = "critical_hammer",
			},
		}
		local power_levels = {
			cleave_hammer = { attack = 4, impact = 8 },
			target_hammer = { power_distribution = { attack = 10, impact = 20 } },
			targets_hammer = { { power_distribution = { attack = 6, impact = 12 } } },
			critical_hammer = { power_distribution = { attack = 8, impact = 16 } },
		}
		local registered, recorded = {}, {}
		local state = policy.new()
		state:apply(true, weapons, damage_profiles, power_levels, clone,
			function(generated, source) recorded[generated] = source end,
			function(generated) registered[generated] = true end)

		local action = weapons[policy.HAMMER_TEMPLATE_KEYS[1]].actions.action_one.light
		H.equal(action.damage_profile, "cwv_mhi_hammer_hit")
		H.equal(action.anim_time_scale, 1.2)
		H.equal(recorded.cwv_mhi_hammer_hit, "hammer_hit")
		H.equal(registered.cwv_mhi_hammer_hit, true)
		local generated = damage_profiles.cwv_mhi_hammer_hit
		H.equal(power_levels[generated.cleave_distribution].attack, 3)
		H.equal(power_levels[generated.cleave_distribution].impact, 6)
		H.equal(power_levels[generated.default_target].power_distribution.attack, 11.25)
		H.equal(power_levels[generated.default_target].power_distribution.impact, 20)
		H.equal(power_levels[generated.targets][1].power_distribution.attack, 6.75)
		H.equal(power_levels[generated.targets][1].power_distribution.impact, 12)
		H.equal(power_levels[generated.critical_strike].power_distribution.attack, 9)
		H.equal(power_levels[generated.critical_strike].power_distribution.impact, 16)
		-- Vanilla rows remain byte-for-byte-equivalent at the tuned leaves.
		H.equal(power_levels.cleave_hammer.attack, 4)
		H.equal(power_levels.target_hammer.power_distribution.attack, 10)
		H.equal(power_levels.target_hammer.power_distribution.impact, 20)
		H.equal(weapons[policy.HAMMER_TEMPLATE_KEYS[1]].actions.action_one.push.damage_profile_inner, "push")
		H.equal(weapons[policy.HAMMER_TEMPLATE_KEYS[1]].actions.action_one.shield.damage_profile, "shield_slam")
		state:apply(false, weapons, damage_profiles, power_levels, clone)
		H.equal(action.damage_profile, "hammer_hit")
	end)

	H.test("CWV #599 Dual Maces isolate the Dual Hammers moveset", function()
		local source = fixture_template("dual_hammer_hit", 1)
		local weapons = { dual_wield_hammers_template = source }
		local state = policy.new()
		local ok = state:ensure_cwv_dual_mace_template(weapons, clone)
		H.equal(ok, true)
		H.truthy(weapons.cwv_dual_maces_template ~= source)
		weapons.cwv_dual_maces_template.actions.action_one.light.anim_time_scale = 3
		H.equal(source.actions.action_one.light.anim_time_scale, 1)
	end)

	H.test("CWV #599 composes with the canonical lifecycle callback owners", function()
		local source = read(repo_root
			.. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua")
		H.equal(count(source, "mod.on_enabled = function()"), 1)
		H.equal(count(source, "mod.on_disabled = function()"), 1)
		H.equal(count(source, "mod.on_unload = function()"), 1)
		H.equal(count(source, "function mod.on_enabled()"), 0)
		H.equal(count(source, "function mod.on_disabled()"), 0)
		local enabled_at = assert(source:find("mod.on_enabled = function()", 1, true))
		local disabled_at = assert(source:find("mod.on_disabled = function()", enabled_at, true))
		local unload_at = assert(source:find("mod.on_unload = function()", disabled_at, true))
		local next_section = assert(source:find("-- (2) Variant equip event", unload_at, true))
		local enabled = source:sub(enabled_at, disabled_at - 1)
		local disabled = source:sub(disabled_at, unload_at - 1)
		local unload = source:sub(unload_at, next_section - 1)
		H.truthy(enabled:find('_om._acquire_dual_weapon_fp_residency("mod_enabled")', 1, true))
		H.truthy(enabled:find("_om._apply_mace_hammer_identity(", 1, true))
		H.truthy(disabled:find("_om._apply_mace_hammer_identity(false)", 1, true))
		H.truthy(disabled:find('_om._release_dual_weapon_fp_residency("mod_disabled")', 1, true))
		H.truthy(unload:find("_om._apply_mace_hammer_identity(false)", 1, true))
		H.truthy(unload:find('_om._release_dual_weapon_fp_residency("mod_unload")', 1, true))
	end)
end
