-- #916: property-keyed burn scrub for CWV's Sienna-donor clones (maul_template).
return function(H, repo_root)
	local scrub = dofile(repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_burn_scrub.lua")

	local function deep_clone(t)
		if type(t) ~= "table" then return t end
		local c = {}
		for k, v in pairs(t) do c[k] = deep_clone(v) end
		return c
	end

	-- Resolved-table fixtures shaped like vanilla 6.11.3
	-- (power_level_templates.lua:5697-5930): burn on default_target, burn on
	-- a list target, a sparse `[2]` targets table, and clean profiles.
	local function profiles()
		return {
			mace_1h_heavy_smiter_vertical = {
				charge_value = "heavy_attack", shield_break = true,
				default_target = { attack_template = "slashing_smiter",
					dot_template_name = "burning_dot_3tick", dot_balefire_variant = true,
					power_distribution = { attack = 0.3, impact = 0.3 } },
				targets = { [2] = { attack_template = "light_blunt_tank" } },
			},
			mace_1h_heavy_tank_diag = {
				charge_value = "heavy_attack",
				default_target = { attack_template = "light_blunt_tank" },
				targets = {
					{ attack_template = "heavy_blunt_tank",
						dot_template_name = "burning_dot_2tick_slow_unstackable",
						dot_balefire_variant = true,
						power_distribution = { attack = 0.15, impact = 0.3 } },
					{ attack_template = "light_blunt_tank" },
				},
			},
			mace_1h_light_tank_horizontal = {
				charge_value = "light_attack",
				default_target = { attack_template = "light_blunt_tank" },
				targets = { { attack_template = "light_blunt_tank" } },
			},
			light_push = { charge_value = "action_push", default_target = {} },
			medium_push = { charge_value = "action_push", default_target = {} },
			medium_blunt_smiter_1h = { charge_value = "heavy_attack", default_target = {} },
			medium_blunt_tank_1h = { charge_value = "heavy_attack", default_target = {} },
			light_blunt_smiter_burning = { charge_value = "heavy_attack",
				default_target = { dot_template_name = "burning_dot_1tick" } },
		}
	end

	local function donor()
		return {
			actions = {
				action_one = {
					heavy_attack = { damage_profile = "mace_1h_heavy_smiter_vertical" },
					heavy_attack_left = { damage_profile = "mace_1h_heavy_tank_diag" },
					heavy_attack_right_up = { damage_profile = "mace_1h_heavy_tank_diag" },
					light_attack_right = { damage_profile = "mace_1h_light_tank_horizontal" },
					push = { damage_profile_inner = "medium_push", damage_profile_outer = "light_push" },
				},
				action_two = { block = { kind = "block" } },
			},
		}
	end

	local function run_scrub(dps, template, wire)
		local registered = {}
		local swapped, names, failures = scrub.scrub_template(template, {
			profiles = dps, prefix = "cwv_maul_", deep_clone = deep_clone,
			register = function(new_name, clone, source_name)
				registered[#registered + 1] = new_name
				dps[new_name] = clone
				wire[new_name] = source_name
				return true
			end,
		})
		return swapped, names, failures, registered
	end

	H.test("#916 burn predicate mirrors parse_dot_name at all three levels", function()
		local dps = profiles()
		H.equal(scrub.profile_dot(dps.mace_1h_heavy_smiter_vertical), "burning_dot_3tick")
		H.equal(scrub.profile_dot(dps.mace_1h_heavy_tank_diag), "burning_dot_2tick_slow_unstackable")
		H.equal(scrub.profile_burns({ dot_template_name = "x", default_target = {} }), true)
		H.equal(scrub.profile_burns(dps.mace_1h_light_tank_horizontal), false)
		H.equal(scrub.profile_burns(nil), false)
		-- Sparse targets (vanilla starts some lists at [2]) are still scanned.
		H.equal(scrub.profile_burns({ default_target = {}, targets = { [2] = { dot_template_name = "y" } } }), true)
		-- Unresolved names resolve through PowerLevelTemplates.
		H.equal(scrub.profile_burns({ default_target = "dt" }, { dt = { dot_template_name = "z" } }), true)
	end)

	H.test("#916 scrub rewrites every burning slot to a dot-free same-shape copy", function()
		local dps, wire = profiles(), {}
		local template = deep_clone(donor())
		local swapped, names, failures, registered = run_scrub(dps, template, wire)
		H.equal(swapped, 3)
		H.deep_equal(names, { "mace_1h_heavy_smiter_vertical", "mace_1h_heavy_tank_diag" })
		H.deep_equal(failures, {})
		H.equal(#registered, 2, "each burning profile registered exactly once")
		local one = template.actions.action_one
		H.equal(one.heavy_attack.damage_profile, "cwv_maul_mace_1h_heavy_smiter_vertical")
		H.equal(one.heavy_attack_left.damage_profile, "cwv_maul_mace_1h_heavy_tank_diag")
		H.equal(one.heavy_attack_right_up.damage_profile, "cwv_maul_mace_1h_heavy_tank_diag")
		H.equal(one.light_attack_right.damage_profile, "mace_1h_light_tank_horizontal")
		H.equal(one.push.damage_profile_inner, "medium_push")
		local smiter = dps.cwv_maul_mace_1h_heavy_smiter_vertical
		H.equal(scrub.profile_burns(smiter), false)
		H.equal(smiter.default_target.dot_balefire_variant, nil)
		H.equal(smiter.default_target.power_distribution.attack, 0.3, "damage shape kept")
		H.equal(smiter.shield_break, true)
		H.equal(smiter.targets[2].attack_template, "light_blunt_tank")
		local tank = dps.cwv_maul_mace_1h_heavy_tank_diag
		H.equal(tank.targets[1].dot_template_name, nil)
		H.equal(tank.targets[1].power_distribution.impact, 0.3)
		-- Vanilla rows stay untouched (clone-local scrub).
		H.equal(dps.mace_1h_heavy_smiter_vertical.default_target.dot_template_name, "burning_dot_3tick")
		H.equal(dps.mace_1h_heavy_tank_diag.targets[1].dot_template_name, "burning_dot_2tick_slow_unstackable")
		H.equal(scrub.verify(donor(), template, {
			profiles = dps, prefix = "cwv_maul_", wire_sources = wire }), nil)
	end)

	H.test("#916 failed registration leaves the slot unswapped and reports it", function()
		local dps = profiles()
		local template = deep_clone(donor())
		local swapped, names, failures = scrub.scrub_template(template, {
			profiles = dps, prefix = "cwv_maul_", deep_clone = deep_clone,
			register = function() return false end,
		})
		H.equal(swapped, 0)
		H.deep_equal(names, {})
		H.deep_equal(failures, { "mace_1h_heavy_smiter_vertical", "mace_1h_heavy_tank_diag" })
		H.equal(template.actions.action_one.heavy_attack.damage_profile, "mace_1h_heavy_smiter_vertical")
	end)

	H.test("#916 live-donor check fails the stale name-keyed scrub and donor mutation", function()
		local dps, wire = profiles(), {}
		-- The pre-fix shape: a clone whose name-keyed swap matched nothing.
		local failure = scrub.verify(donor(), deep_clone(donor()), {
			profiles = dps, prefix = "cwv_maul_", wire_sources = wire })
		H.truthy(failure and failure:find("burn profile reachable from the clone", 1, true), failure)

		local template = deep_clone(donor())
		run_scrub(dps, template, wire)
		local mutated = donor()
		mutated.actions.action_one.light_attack_right.damage_profile = "cwv_maul_x"
		failure = scrub.verify(mutated, template, {
			profiles = dps, prefix = "cwv_maul_", wire_sources = wire })
		H.truthy(failure and failure:find("donor mutated", 1, true), failure)

		failure = scrub.verify(donor(), template, {
			profiles = dps, prefix = "cwv_maul_", wire_sources = {} })
		H.truthy(failure and failure:find("no #423 wire source", 1, true), failure)
	end)

	H.test("#916 a donor without fire passes with nothing to protect", function()
		local dps = profiles()
		local clean = { actions = { action_one = {
			light = { damage_profile = "mace_1h_light_tank_horizontal" } } } }
		local failure, burning = scrub.verify(clean, deep_clone(clean), {
			profiles = dps, prefix = "cwv_maul_", wire_sources = {} })
		H.equal(failure, nil)
		H.equal(burning, 0)
	end)

	H.test("#916 wire source prefers a qualifying non-burning analog", function()
		local dps = profiles()
		local analogs = {
			mace_1h_heavy_smiter_vertical = "medium_blunt_smiter_1h",
			mace_1h_heavy_tank_diag = "light_blunt_smiter_burning",   -- burns: rejected
			mace_1h_light_tank_horizontal = "medium_blunt_tank_1h",   -- charge mismatch
		}
		H.deep_equal({ scrub.wire_source("mace_1h_heavy_smiter_vertical", analogs, dps) },
			{ "medium_blunt_smiter_1h", "analog" })
		H.deep_equal({ scrub.wire_source("mace_1h_heavy_tank_diag", analogs, dps) },
			{ "mace_1h_heavy_tank_diag", "donor" })
		H.deep_equal({ scrub.wire_source("mace_1h_light_tank_horizontal", analogs, dps) },
			{ "mace_1h_light_tank_horizontal", "donor" })
		H.deep_equal({ scrub.wire_source("unlisted", analogs, dps) }, { "unlisted", "donor" })
	end)

	-- Optional provenance: run the scrub against the decompiled vanilla donor
	-- and profile tables, loaded in a sandbox.
	local source_root = (os.getenv("VT2_SOURCE_ROOT")
		or ((os.getenv("USERPROFILE") or "") .. "/source/repos/Vermintide-2-Source-Code"))
	local function read(relative)
		local file = io.open(source_root .. "/" .. relative, "rb")
		if not file then return nil end
		local text = file:read("*a")
		file:close()
		return (text:gsub("^\239\187\191", ""))
	end
	local wizard_path = "scripts/settings/equipment/weapon_templates/1h_hammers_wizard.lua"
	H.test_if(read(wizard_path) ~= nil,
		"#916 optional vanilla scan: every burning Morningstar profile is scrubbed", function()
			local stub_mt
			stub_mt = { __index = function(t, k) local v = setmetatable({}, stub_mt); rawset(t, k, v); return v end }
			local env = setmetatable({}, { __index = function(t, k)
				local v = _G[k]
				if v ~= nil then return v end
				v = setmetatable({}, stub_mt)
				rawset(t, k, v)
				return v
			end })
			env.table = setmetatable({ clone = deep_clone,
				merge = function(a, b) for k, v in pairs(b) do a[k] = v end return a end }, { __index = table })
			env.fassert = function(c, ...) if not c then error(string.format(...)) end end
			env.DLCUtils = { require_list = function() end, map_list = function() end }
			local function load_in_env(relative)
				local text = assert(read(relative), relative)
				local chunk = assert(loadstring(text, relative))
				setfenv(chunk, env)
				return chunk()
			end
			env.require = function(p) return load_in_env(p .. ".lua") end
			load_in_env("scripts/settings/equipment/power_level_templates.lua")
			load_in_env("scripts/settings/equipment/damage_profile_templates.lua")
			local wizard = load_in_env(wizard_path).one_handed_hammer_wizard_template_1
			local dps = rawget(env, "DamageProfileTemplates")
			local template, wire = deep_clone(wizard), {}
			local _, names = run_scrub(dps, template, wire)
			H.deep_equal(names, { "mace_1h_heavy_smiter_vertical", "mace_1h_heavy_tank_diag",
				"mace_1h_light_smiter_vertical" })
			local failure, burning = scrub.verify(wizard, template, {
				profiles = dps, prefix = "cwv_maul_", wire_sources = wire })
			H.equal(failure, nil)
			H.equal(burning, 5)
			local analogs = scrub.MAUL_WIRE_ANALOG
			for donor_name, analog in pairs(analogs) do
				H.deep_equal({ scrub.wire_source(donor_name, analogs, dps) }, { analog, "analog" },
					"vanilla analog qualifies: " .. donor_name)
			end
		end, "decompiled VT2 source not found")
end
