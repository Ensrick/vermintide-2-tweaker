return function(H, repo_root)
	local bridge = dofile(repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_mod_unit_preview.lua")
	local appearance = dofile(repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_exact_appearance.lua")
	local custom_a = "units/cwv_crowbill/imperial_01/imperial_01_3p"
	local custom_b = "units/cwv_crowbill/imperial_02/imperial_02_3p"
	local alias = "units/weapons/player/wpn_brw_crowbill_01/wpn_brw_crowbill_01_3p"
	local function alias_for(key)
		if key == custom_a or key == custom_b then return alias end
	end

	H.test("CWV #604 repairs a wrapper-bypassed custom preview lease", function()
		local previewer = {
			_loaded_packages = { [custom_a] = true },
			_packages_to_load = { [custom_a] = true },
		}
		local acquired = 0
		local report = bridge.reconcile_for_unload(previewer, alias_for, function()
			acquired = acquired + 1
			return true
		end)

		H.equal(acquired, 1)
		H.equal(report.repaired, 1)
		H.equal(report.mapped, 1)
		H.equal(report.failed, 0)
		H.equal(rawget(previewer._loaded_packages, custom_a), nil)
		H.equal(rawget(previewer._packages_to_load, custom_a), nil)
		H.equal(previewer._loaded_packages[alias], true)
		H.equal(previewer._packages_to_load[alias], false)
	end)

	H.test("CWV #604 treats completed false pending state as owned teardown work", function()
		local previewer = {
			_loaded_packages = {},
			_packages_to_load = { [custom_a] = false },
		}
		local acquired = 0
		local report = bridge.reconcile_for_unload(previewer, alias_for, function()
			acquired = acquired + 1
			return true
		end)

		H.equal(acquired, 1)
		H.equal(report.mapped, 1)
		H.equal(rawget(previewer._packages_to_load, custom_a), nil)
		H.equal(previewer._loaded_packages[alias], true)
		H.equal(previewer._packages_to_load[alias], false)
	end)

	H.test("CWV #604 deduplicates one borrowed alias lease per previewer", function()
		local previewer = {
			_loaded_packages = { [custom_a] = true, [custom_b] = true },
			_packages_to_load = { [custom_a] = false, [custom_b] = false },
		}
		local acquired = 0
		local report = bridge.reconcile_for_unload(previewer, alias_for, function()
			acquired = acquired + 1
			return true
		end)

		H.equal(acquired, 1)
		H.equal(report.repaired, 1)
		H.equal(report.mapped, 2)
		H.equal(previewer._loaded_packages[alias], true)
	end)

	H.test("CWV #604 reuses an acquired lease and reconciliation is repeat-safe", function()
		local previewer = {
			_loaded_packages = { [custom_a] = true },
			_packages_to_load = { [custom_a] = false },
			_cwv_preview_alias_leases = {
				[alias] = { acquired = true, complete = true, customs = { [custom_a] = true } },
			},
		}
		local acquired = 0
		local first = bridge.reconcile_for_unload(previewer, alias_for, function()
			acquired = acquired + 1
			return true
		end)
		local second = bridge.reconcile_for_unload(previewer, alias_for, function()
			acquired = acquired + 1
			return true
		end)

		H.equal(acquired, 0)
		H.equal(first.mapped, 1)
		H.equal(second.mapped, 0)
		H.equal(second.repaired, 0)
	end)

	H.test("CWV #604 failed repair drops only the unowned custom unload key", function()
		local control = "units/vanilla/control_3p"
		local previewer = {
			_loaded_packages = { [custom_a] = true, [control] = true },
			_packages_to_load = { [custom_a] = true, [control] = false },
		}
		local report = bridge.reconcile_for_unload(previewer, alias_for, function()
			return false
		end)

		H.equal(report.failed, 1)
		H.equal(report.mapped, 0)
		H.equal(rawget(previewer._loaded_packages, custom_a), nil)
		H.equal(rawget(previewer._packages_to_load, custom_a), nil)
		H.equal(previewer._loaded_packages[control], true)
		H.equal(previewer._packages_to_load[control], false)
		H.equal(rawget(previewer._loaded_packages, alias), nil)
	end)

	H.test("CWV #604 teardown ownership is idempotent", function()
		local previewer = {}
		H.equal(bridge.claim_teardown(previewer), true)
		H.equal(bridge.claim_teardown(previewer), false)
	end)

	H.test("CWV #597 loot fallback marks the exact vanilla row for downstream containment", function()
		local previewer = { _cwv_preview_unit_fallbacks = { [custom_a] = alias } }
		local rows = { { unit_name = custom_a } }
		bridge.apply_loot_fallbacks(previewer, rows)
		H.equal(rows[1].unit_name, alias)
		H.equal(rows[1][bridge.FALLBACK_MARKER], alias)
	end)

	H.test("CWV #604 production hooks balance bypass shared alias async and repeat lifecycle", function()
		local saved = {
			get_mod = get_mod, WeaponUtils = WeaponUtils, Application = Application,
			Managers = Managers, printf = printf,
		}
		local hooks, commands = {}, {}
		local mod = {}
		function mod:hook(target, method, wrapper)
			local owner = type(target) == "string" and target or "WeaponUtils"
			hooks[owner .. "." .. method] = wrapper
		end
		function mod:command(name, _, fn) commands[name] = fn end
		function mod:error() end
		function mod:echo() end

		local pm = { refs = {}, loads = 0, unloads = 0, auto_complete = true }
		function pm:load(name, _, cb)
			self.loads = self.loads + 1
			self.refs[name] = (self.refs[name] or 0) + 1
			if cb then
				if self.auto_complete then cb() else self.pending_callback = cb end
			end
		end
		function pm:unload(name)
			self.unloads = self.unloads + 1
			local count = assert(self.refs[name], "unload without acquired reference: " .. tostring(name))
			if count == 1 then
				self.refs[name] = nil
			else
				self.refs[name] = count - 1
			end
		end

		get_mod = function() return mod end
		WeaponUtils = { get_weapon_packages = function() return {} end }
		local units_resident = true
		local closure_ready = true
		Application = { can_get = function(kind, name)
			if kind == "unit" then return units_resident and alias_for(name) ~= nil end
			return false
		end }
		Managers = { package = pm }
		printf = function() end

		bridge.install({
			MODELS = {
				{ right_hand_unit = custom_a:gsub("_3p$", "") },
				{ right_hand_unit = custom_b:gsub("_3p$", "") },
			},
			preview_package_alias = alias_for,
			preview_resource_ready = function(name)
				return closure_ready and units_resident and alias_for(name) ~= nil,
					closure_ready and "ready" or "material_missing"
			end,
			alias_collected_packages = function(values) return values end,
		})
		local load_hook = assert(hooks["LootItemUnitPreviewer.load_package"])
		local unload_hook = assert(hooks["LootItemUnitPreviewer._unload_packages"])
		local hero_load_hook = assert(hooks["HeroPreviewer._load_packages"])
		local menu_load_hook = assert(hooks["MenuWorldPreviewer._load_packages"])
		local downstream_calls = 0
		local function vanilla_unload(value)
			downstream_calls = downstream_calls + 1
			for key in pairs(value._loaded_packages or {}) do pm:unload(key) end
			for key, pending in pairs(value._packages_to_load or {}) do
				if pending then pm:unload(key) end
			end
		end
		local function new_previewer()
			local value = { _loaded_packages = {}, _packages_to_load = {} }
			function value:_on_load_complete(key)
				self._loaded_packages[key] = true
				self._packages_to_load[key] = false
			end
			return value
		end

		-- #604: class() copies the parent's method, so both preview classes must
		-- independently translate the custom package before PackageManager sees it.
		local function exercise_character_preview(wrapper)
			local package_names = { custom_a }
			local previewer = {
				_item_info_by_slot = {
					melee = { spawn_data = { { right_hand = true, unit_name = custom_a } } },
				},
			}
			local downstream
			wrapper(function(_, names) downstream = names[1] end, previewer, package_names)
			return downstream, previewer._item_info_by_slot.melee.spawn_data[1]
		end
		local hero_package, hero_row = exercise_character_preview(hero_load_hook)
		local menu_package, menu_row = exercise_character_preview(menu_load_hook)
		closure_ready = false
		local partial_package, partial_row = exercise_character_preview(menu_load_hook)
		closure_ready = true
		units_resident = false
		local missing_package, missing_row = exercise_character_preview(menu_load_hook)
		local fallback_descriptor = assert(appearance.resolve_spawn_descriptor({
			variant = { item_key = "cwv_missing", right_hand_unit = custom_a:gsub("_3p$", "") },
			base = { right_hand_unit = alias:gsub("_3p$", "") },
		}))
		local fallback_rewrites = appearance.apply_spawn_descriptor(
			fallback_descriptor, { missing_row }, function(unit) return unit .. "_3p" end,
			"hand_flags")

		local bypassed = new_previewer()
		bypassed._loaded_packages[custom_a] = true
		bypassed._packages_to_load[custom_a] = true
		unload_hook(vanilla_unload, bypassed)
		local bypass_loads, bypass_unloads = pm.loads, pm.unloads
		unload_hook(vanilla_unload, bypassed)

		local shared = new_previewer()
		load_hook(function() error("custom load delegated") end, shared, custom_a)
		load_hook(function() error("custom load delegated") end, shared, custom_b)
		local shared_load_delta = pm.loads - bypass_loads
		local shared_a_loaded = shared._loaded_packages[custom_a]
		local shared_b_loaded = shared._loaded_packages[custom_b]
		unload_hook(vanilla_unload, shared)

		pm.auto_complete = false
		local async = new_previewer()
		load_hook(function() error("custom load delegated") end, async, custom_a)
		local retained_callback = assert(pm.pending_callback)
		unload_hook(vanilla_unload, async)
		retained_callback()

		local results = {
			command = type(commands.verify_cwv_preview_bridge) == "function",
			bypass_loads = bypass_loads, bypass_unloads = bypass_unloads,
			downstream_calls = downstream_calls, shared_load_delta = shared_load_delta,
			shared_a_loaded = shared_a_loaded, shared_b_loaded = shared_b_loaded,
			async_custom_loaded = rawget(async._loaded_packages, custom_a),
			remaining_alias_refs = pm.refs[alias],
			hero_package = hero_package, hero_spawn = hero_row.unit_name,
			menu_package = menu_package, menu_spawn = menu_row.unit_name,
			partial_package = partial_package, partial_spawn = partial_row.unit_name,
			partial_marker = partial_row[bridge.FALLBACK_MARKER],
			missing_package = missing_package, missing_spawn = missing_row.unit_name,
			missing_marker = missing_row[bridge.FALLBACK_MARKER],
			fallback_rewrites = fallback_rewrites,
		}

		get_mod, WeaponUtils, Application = saved.get_mod, saved.WeaponUtils, saved.Application
		Managers, printf = saved.Managers, saved.printf

		H.equal(results.command, true)
		H.equal(results.bypass_loads, 1)
		H.equal(results.bypass_unloads, 1)
		H.equal(results.downstream_calls, 3)
		H.equal(results.shared_load_delta, 1)
		H.equal(results.shared_a_loaded, true)
		H.equal(results.shared_b_loaded, true)
		H.equal(results.async_custom_loaded, nil)
		H.equal(results.remaining_alias_refs, nil)
		H.equal(results.hero_package, alias)
		H.equal(results.hero_spawn, custom_a)
		H.equal(results.menu_package, alias)
		H.equal(results.menu_spawn, custom_a)
		H.equal(results.partial_package, alias)
		H.equal(results.partial_spawn, alias,
			"a resident custom unit with an incomplete material closure must fall back")
		H.equal(results.partial_marker, alias)
		H.equal(results.missing_package, alias)
		H.equal(results.missing_spawn, alias)
		H.equal(results.missing_marker, alias)
		H.equal(results.fallback_rewrites, 0,
			"MenuWorld fallback row must survive the later safe mesh-swap pass")
	end)
end
