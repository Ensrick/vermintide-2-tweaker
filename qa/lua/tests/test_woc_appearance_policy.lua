return function(H, repo_root)
	local policy = dofile(repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_appearance_policy.lua")

	H.test("WOC #613 owns explicit Blightreaper 1P and 3P units", function()
		H.equal(policy.UNIT_1P, "units/woc_blightreaper/blightreaper")
		H.equal(policy.UNIT_3P, "units/woc_blightreaper/blightreaper_3p")
		local one = assert(io.open(repo_root .. "/weapons_of_chaos/" .. policy.UNIT_1P .. ".unit", "rb"))
		one:close()
		local three = assert(io.open(repo_root .. "/weapons_of_chaos/" .. policy.UNIT_3P .. ".unit", "rb"))
		three:close()
	end)

	H.test("WOC #613 package collector aliases without changing render units", function()
		local names = { "before", policy.UNIT_1P, policy.UNIT_3P, "after" }
		local same, count = policy.alias_collected_packages(names)
		H.equal(same, names)
		H.equal(count, 2)
		H.equal(names[2], policy.VANILLA_1P)
		H.equal(names[3], policy.VANILLA_3P)
	end)

	H.test("WOC #613 uses the base-game runed sword as package and shader donor", function()
		H.truthy(policy.VANILLA_1P:find("wpn_emp_sword_02_t1_runed_01", 1, true))
		H.equal(policy.DONOR_MATERIAL_1P, policy.VANILLA_1P)
		H.equal(policy.DONOR_MATERIAL_3P, policy.VANILLA_3P)
		H.equal(policy.pulse_descriptor("1p").material, policy.DONOR_MATERIAL_1P)
		H.equal(policy.pulse_descriptor("3p").material, policy.DONOR_MATERIAL_3P)
	end)

	H.test("WOC #613 network package aliases are forward-only", function()
		local lookup = {
			[policy.VANILLA_1P] = 41,
			[policy.VANILLA_3P] = 42,
			[41] = policy.VANILLA_1P,
			[42] = policy.VANILLA_3P,
		}
		H.equal(policy.install_network_package_aliases(lookup), 2)
		H.equal(lookup[policy.UNIT_1P], 41)
		H.equal(lookup[policy.UNIT_3P], 42)
		H.equal(lookup[41], policy.VANILLA_1P)
		H.equal(lookup[42], policy.VANILLA_3P)
	end)

	H.test("WOC #595 fade adapter construction fails closed", function()
		local reports = {}
		local deps = { marker = "deps" }
		local live, ok, reason = policy.new_fade_adapter({
			new = function(received)
				return {
					deps = received,
					enroll = function() return true, { reason = "applied" } end,
				}
			end,
		}, deps, function(row) reports[#reports + 1] = row end)
		H.equal(ok, true)
		H.equal(reason, "ready")
		H.equal(live.deps, deps)
		H.equal(#reports, 0)

		local fallback, missing_ok, missing_reason = policy.new_fade_adapter(nil, deps,
			function(row) reports[#reports + 1] = row end)
		H.equal(missing_ok, false)
		H.equal(missing_reason, "module_unavailable")
		H.equal(reports[1], "module_unavailable")
		local applied, report = fallback:enroll("owner", "owner_wield")
		H.equal(applied, false)
		H.equal(report.edge, "owner_wield")
		H.equal(report.reason, "adapter_unavailable")
		H.equal(report.error, "module_unavailable")

		local throwing = setmetatable({}, {
			__index = function() error("planted member failure") end,
		})
		local guarded, guarded_ok, guarded_reason = policy.new_fade_adapter(
			throwing, deps, function() error("planted reporter failure") end)
		H.equal(guarded_ok, false)
		H.equal(guarded_reason, "constructor_unavailable")
		H.equal(type(guarded.enroll), "function")

		local malformed, malformed_ok, malformed_reason = policy.new_fade_adapter({
			new = function() return {} end,
		}, deps)
		H.equal(malformed_ok, false)
		H.equal(malformed_reason, "adapter_shape_invalid")
		H.equal(type(malformed.enroll), "function")
	end)

	H.test("WOC #595 runtime helper loader contains missing packages", function()
		local paths, checks, reports = {}, {}, {}
		local fade_module = {
			new = function(deps)
				return { deps = deps, enroll = function() return true end }
			end,
		}
		local residency_module = { resource_resident = function() return true end }
		local loader = {
			dofile = function(_, path)
				paths[#paths + 1] = path
				if path:find("appearance_fade", 1, true) then return fade_module end
				return residency_module
			end,
		}
		local fade, residency = policy.load_runtime_helpers(
			loader, { marker = "deps" },
			function(name, check) checks[name] = check end,
			function(fmt, ...) reports[#reports + 1] = string.format(fmt, ...) end)
		H.equal(#paths, 2)
		H.equal(fade.deps.marker, "deps")
		H.equal(residency, residency_module)
		H.equal(#reports, 0)
		local live_check = checks.issue595_required_runtime_helpers_loaded
		H.equal(type(live_check), "function")
		H.equal(pcall(live_check), true)

		local failed_check
		local fallback, missing = policy.load_runtime_helpers({
			dofile = function() error("planted package miss") end,
		}, {}, function(_, check) failed_check = check end, function() end)
		H.equal(missing, nil)
		H.equal(fallback:enroll("owner", "owner_wield"), false)
		H.equal(pcall(failed_check), false)
	end)

	H.test("WOC #613 master package reaches model material and texture roots", function()
		local path = repo_root .. "/weapons_of_chaos/resource_packages/weapons_of_chaos/weapons_of_chaos.package"
		local file = assert(io.open(path, "rb"))
		local source = file:read("*a"); file:close()
		H.truthy(source:find('"units/woc_blightreaper/blightreaper"', 1, true))
		H.truthy(source:find('"units/woc_blightreaper/blightreaper_3p"', 1, true))
		H.truthy(source:find('"textures/woc_blightreaper/blightreaper_albedo"', 1, true))
		H.truthy(source:find('"textures/woc_blightreaper/blightreaper_noise"', 1, true))
		H.truthy(source:find('"textures/woc_blightreaper/blightreaper_packed"', 1, true))
	end)

	H.test("WOC #613 pins canonical all-perspective transform", function()
		H.equal(policy.TRANSFORM.scale[1], 0.9)
		H.equal(policy.TRANSFORM.scale[2], 0.9)
		H.equal(policy.TRANSFORM.scale[3], 0.9)
		H.equal(policy.TRANSFORM_1P.scale[1], 0.8)
		H.equal(policy.TRANSFORM_1P.scale[2], 0.8)
		H.equal(policy.TRANSFORM_1P.scale[3], 0.8)
		H.equal(policy.TRANSFORM_1P.offset, policy.TRANSFORM.offset)
		H.equal(policy.TRANSFORM_1P.rotation, policy.TRANSFORM.rotation)
		H.equal(policy.transform_for("1p"), policy.TRANSFORM_1P)
		H.equal(policy.transform_for("3p"), policy.TRANSFORM)
		H.equal(policy.TRANSFORM.rotation[1], -180)
		H.equal(policy.TRANSFORM.rotation[2], -90)
		H.equal(policy.TRANSFORM.rotation[3], -90)
		H.equal(policy.TRANSFORM.offset[1], 0)
		H.equal(policy.TRANSFORM.offset[2], 0)
		H.equal(policy.TRANSFORM.offset[3], -0.3)
	end)

	H.test("WOC #613 canonicalizes only exact relic item-unit descriptors", function()
		local vanilla = { right_hand_unit = "vanilla", left_hand_unit = "offhand" }
		local same, changed = policy.canonicalize_item_units(vanilla, false)
		H.equal(same, vanilla)
		H.equal(changed, false)
		H.equal(vanilla.right_hand_unit, "vanilla")

		same, changed = policy.canonicalize_item_units(vanilla, true)
		H.equal(same, vanilla)
		H.equal(changed, true)
		H.equal(vanilla.right_hand_unit, policy.UNIT_1P)
		H.equal(vanilla.left_hand_unit, nil)
	end)

	H.test("WOC #613 runtime covers inventory, husk, character, and item previews", function()
		local main = assert(io.open(repo_root
			.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua", "rb"))
		local main_source = main:read("*a"); main:close()
		local preview = assert(io.open(repo_root
			.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_mod_unit_preview.lua", "rb"))
		local preview_source = preview:read("*a"); preview:close()
		H.truthy(main_source:find('mod:hook("GearUtils", "spawn_inventory_unit"', 1, true))
		H.truthy(main_source:find('mod:hook(BackendUtils, "get_item_units"', 1, true))
		H.truthy(main_source:find('_appearance.canonicalize_item_units(item_units, true)',
			1, true))
		H.truthy(main_source:find('[WOC:613] spawn identity', 1, true))
		H.truthy(main_source:find('_wa.apply(unit_3p, _appearance.transform_for("3p"), "3p"', 1, true))
		H.truthy(main_source:find('_wa.apply(unit_1p, _appearance.transform_for("1p"), "1p"', 1, true))
		H.truthy(main_source:find('[WOC:712] unit census', 1, true))
		H.truthy(main_source:find('Unit.num_scene_graph_items', 1, true))
		H.truthy(main_source:find('Unit.num_meshes', 1, true))
		H.truthy(main_source:find('Application.can_get, "material", descriptor.material', 1, true))
		H.truthy(main_source:find('Application.can_get, "texture", binding.texture', 1, true))
		H.truthy(preview_source:find('mod:hook("HeroPreviewer", "_spawn_item"', 1, true))
		H.truthy(preview_source:find('mod:hook("MenuWorldPreviewer", "_spawn_item"', 1, true))
		H.truthy(preview_source:find('mod:hook("LootItemUnitPreviewer", "spawn_units"', 1, true))
		H.truthy(preview_source:find(
			'local perspective = name == policy.UNIT_3P and "3p" or "1p"', 1, true))
		H.truthy(preview_source:find(
			'pcall(appearance.apply,', 1, true))
	end)
end
