return function(H, repo_root)
	local root = repo_root .. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/"
	local catalog = dofile(root .. "_woc_boss_weapon_catalog.lua")

	local function category(unit_name)
		return { { unit_name = unit_name } }
	end

	local function fixture()
		return {
			breeds = {
				chaos_exalted_sorcerer_drachenfels = {
					default_inventory_template = "chaos_exalted_sorcerer_drachenfels",
				},
				chaos_exalted_sorcerer = {
					default_inventory_template = "chaos_exalted_sorcerer",
				},
				chaos_exalted_champion_warcamp = {
					default_inventory_template = "exalted_axe",
				},
				skaven_storm_vermin_warlord = {
					default_inventory_template = "warlord_dual_setups",
				},
				skaven_grey_seer = { has_inventory = false },
			},
			inventories = {
				chaos_exalted_sorcerer_drachenfels = { items = { category(
					"units/weapons/enemy/wpn_chaos_sorcerer_scythe/wpn_chaos_sorcerer_scythe_01") } },
				chaos_exalted_sorcerer = { items = { category(
					"units/weapons/enemy/wpn_chaos_sorcerer_stick/wpn_sorcerer_stick") } },
				exalted_axe = { items = { category(
					"units/weapons/enemy/wpn_chaos_set/wpn_chaos_2h_axe_03") } },
				warlord_dual_setups = {
					multiple_configurations = { "halberd", "dual" },
				},
				halberd = { items = { category(
					"units/weapons/enemy/wpn_skaven_set/wpn_skaven_halberd_stormvermin_champion") } },
				dual = { items = {
					category("units/weapons/enemy/wpn_skaven_set/wpn_skaven_sword_dual_left"),
					category("units/weapons/enemy/wpn_skaven_set/wpn_skaven_sword_dual_right"),
				} },
			},
			is_resident = function(unit_name)
				return unit_name:find("scythe", 1, true) ~= nil
			end,
		}
	end

	H.test("WOC boss catalogue exposes explicit source and registration facets", function()
		H.equal(catalog.ROWS, catalog.SOURCE_ROWS)
		H.equal(#catalog.SOURCE_ROWS, 7)
		H.truthy(type(catalog.audit) == "function")
		H.truthy(type(catalog.get) == "function")
		H.truthy(type(catalog.registration_readiness) == "function")
	end)

	H.test("WOC #614 catalogue pins source-backed Skarrik halberd identity", function()
		local row = catalog.get("skarrik_halberd")
		H.equal(row.issue, 614)
		H.equal(row.base_weapon, "es_halberd")
		H.equal(row.base_template, "two_handed_halberds_template_1")
		H.equal(row.wire_fallback, "es_halberd")
		H.equal(row.native_units.right,
			"units/weapons/enemy/wpn_skaven_set/wpn_skaven_halberd_stormvermin_champion")
		H.equal(row.authored_units.right_1p,
			"units/woc_skarrik_halberd/skarrik_halberd")
		H.equal(row.authored_units.right_3p,
			"units/woc_skarrik_halberd/skarrik_halberd_3p")
		H.equal(row.asset.export_sha256,
			"4BDA4ED14BDA32B3560BCB7BF0BF256274539BE67ECEECD4D0B9A7713180865F")
		H.equal(row.asset.stage, "authored")
		H.equal(row.asset.material,
			"units/woc_skarrik_dual_swords/skarrik_swords")
		H.equal(row.asset.material_owner_issue, 615)
	end)

	H.test("WOC #615 catalogue preserves both Skarrik sword hands", function()
		local row = catalog.get("skarrik_dual_swords")
		H.equal(row.issue, 615)
		H.equal(row.base_weapon, "we_dual_wield_swords")
		H.equal(row.base_template, "dual_wield_swords_template_1")
		H.truthy(row.native_units.left:find("_left", 1, true))
		H.truthy(row.native_units.right:find("_right", 1, true))
		H.truthy(row.authored_units.left_1p ~= row.authored_units.right_1p)
	end)

	H.test("WOC #614/#615 rows agree on the mod-owned Skarrik material", function()
		-- The owned closure is proven by the authored unit files
		-- (skarrik_sword_right.unit:2, skarrik_halberd.unit:2) and shipped as
		-- units/woc_skarrik_dual_swords/skarrik_swords.material.
		local swords = catalog.get("skarrik_dual_swords")
		local halberd = catalog.get("skarrik_halberd")
		H.equal(swords.asset.material,
			"units/woc_skarrik_dual_swords/skarrik_swords")
		H.equal(swords.asset.material_owner_issue, 615)
		H.equal(swords.asset.material, halberd.asset.material)
		-- The native enemy family stays recorded as provenance only, never as
		-- the owned material path.
		H.equal(swords.asset.native_material,
			"units/weapons/enemy/wpn_skaven_set/wpn_skaven_set")
		H.truthy(swords.asset.material ~= swords.asset.native_material)
	end)

	H.test("WOC #642 registration descriptors map exported boss identities", function()
		local expected = {
			nurgloth_scythe = "wpn_chaos_sorcerer_scythe_01",
			burblespue_staff = "wpn_sorcerer_stick",
			bodvarr_axe = "wpn_chaos_2h_axe_03",
		}
		for id, suffix in pairs(expected) do
			local row = catalog.get(id)
			H.equal(row.issue, 642)
			H.truthy(row.native_units.right:find(suffix, 1, true))
			H.equal(row.asset.stage, "exported")
			H.equal(#row.asset.export_sha256, 64)
		end
	end)

	H.test("WOC source facet is unique and excludes keep trophy props", function()
		local seen = {}
		for i = 1, #catalog.SOURCE_ROWS do
			local row = catalog.SOURCE_ROWS[i]
			H.equal(seen[row.id], nil)
			seen[row.id] = true
			if row.unit then
				H.equal(row.unit:find("units/props/inn/hub_trophy", 1, true), nil)
			end
		end
	end)

	H.test("WOC source audit resolves every authored boss inventory row", function()
		local results = catalog.audit(fixture())
		for i = 1, 6 do
			H.equal(results[i].breed_present, true)
			H.equal(results[i].inventory_match, true)
			H.equal(results[i].unit_match, true)
			H.equal(results[i].status, "source_mapped")
		end
		H.equal(results[1].resident, true)
		H.equal(results[2].resident, false)
	end)

	H.test("WOC residency column is honest about the missing runtime probe", function()
		-- PackageManager:has_loaded keys on package names (decompile
		-- package_manager.lua:286-294); the rows record unit paths, so the
		-- runtime path must report unknown rather than a fabricated false.
		H.equal(catalog.RESIDENCY_UNKNOWN,
			"unknown(package-level probe unavailable)")
		H.equal(catalog.residency_label(nil), catalog.RESIDENCY_UNKNOWN)
		H.equal(catalog.residency_label(true), "true")
		H.equal(catalog.residency_label(false), "false")

		-- Without an injected probe (the runtime configuration), every row's
		-- resident field stays nil - no boolean claim is synthesized.
		local args = fixture()
		args.is_resident = nil
		local results = catalog.audit(args)
		for i = 1, #results do
			H.equal(results[i].resident, nil)
		end
	end)

	H.test("WOC source audit keeps Rasknitt explicitly deferred", function()
		local row = catalog.audit(fixture())[7]
		H.equal(row.id, "rasknitt_deferred")
		H.equal(row.expected_inventory, false)
		H.equal(row.expected_unit, false)
		H.equal(row.inventory_match, true)
		H.equal(row.status, "deferred_no_inventory")
	end)

	H.test("WOC source audit fails closed on source drift", function()
		local args = fixture()
		args.breeds.chaos_exalted_champion_warcamp.default_inventory_template = "wrong"
		local row = catalog.audit(args)[3]
		H.equal(row.inventory_match, false)
		H.equal(row.unit_match, false)
		H.equal(row.status, "source_drift")
	end)

	H.test("WOC boss catalogue returns isolated descriptor copies", function()
		local first = catalog.get("skarrik_halberd")
		first.native_units.right = "mutated"
		first.asset.texture_hashes[1] = "mutated"
		local second = catalog.get("skarrik_halberd")
		H.truthy(second.native_units.right ~= "mutated")
		H.truthy(second.asset.texture_hashes[1] ~= "mutated")
	end)

	H.test("WOC boss catalogue keeps unadopted assets registration-inert", function()
		for _, row in ipairs(catalog.all()) do
			if row.id ~= "blightreaper" then
				local ready, reason = catalog.registration_readiness(row,
					function() return true end)
				H.equal(ready, false)
				H.equal(reason, "registration_disabled")
			end
		end
	end)

	H.test("WOC authored-resource diagnostic observes disabled candidates", function()
		local results = catalog.authored_snapshot(function(name)
			return name:find("woc_skarrik_halberd", 1, true) ~= nil
		end)
		local halberd
		for i = 1, #results do
			if results[i].id == "skarrik_halberd" then halberd = results[i] end
		end
		H.truthy(halberd)
		H.equal(halberd.registration_enabled, false)
		H.equal(halberd.status, "authored_resources_present")
		H.equal(#halberd.required, 2)
		H.equal(#halberd.missing, 0)
	end)

	H.test("WOC authored-resource diagnostic fails closed on probe errors", function()
		local results = catalog.authored_snapshot(function()
			error("probe unavailable")
		end)
		local halberd
		for i = 1, #results do
			if results[i].id == "skarrik_halberd" then halberd = results[i] end
		end
		H.equal(halberd.status, "authored_resources_missing")
		H.equal(#halberd.missing, 2)
	end)

	H.test("WOC boss catalogue requires complete authored resource closure", function()
		local row = catalog.get("blightreaper")
		local ready, reason = catalog.registration_readiness(row, function(name)
			return name:find("_3p", 1, true) == nil
		end)
		H.equal(ready, false)
		H.truthy(reason:find("resource_missing:", 1, true) == 1)

		ready, reason = catalog.registration_readiness(row, function() return true end)
		H.equal(ready, true)
		H.equal(reason, nil)
	end)

	H.test("WOC boss catalogue diagnostic is packaged and mutation-free", function()
		local function read(path)
			local file = assert(io.open(path, "rb"))
			local source = file:read("*a")
			file:close()
			return source
		end
		local module = read(root .. "_woc_boss_weapon_catalog.lua")
		local main = read(root .. "weapons_of_chaos.lua")
		local package = read(repo_root
			.. "/weapons_of_chaos/resource_packages/weapons_of_chaos/weapons_of_chaos.package")
		H.equal(module:find("mod:hook", 1, true), nil)
		H.equal(module:find("spawn_queued_unit", 1, true), nil)
		H.equal(module:find("package_manager:load", 1, true), nil)
		-- The unit-path residency probe must stay dead: has_loaded keys on
		-- package names, so probing it with unit paths always read false.
		-- (Comments may cite has_loaded; the CALL form must be absent.)
		H.equal(module:find(":has_loaded(", 1, true), nil)
		H.equal(module:find("resident_now=", 1, true), nil)
		H.truthy(module:find("residency=%s", 1, true))
		H.truthy(main:find('mod:command("woc_boss_catalog"', 1, true))
		H.truthy(main:find("_boss_weapon_catalog.emit_runtime()", 1, true))
		H.truthy(main:find("_boss_weapon_catalog.emit_authored_runtime()", 1, true))
		H.truthy(package:find(
			'"scripts/mods/weapons_of_chaos/_woc_boss_weapon_catalog"', 1, true))
		H.truthy(package:find(
			'"units/woc_skarrik_halberd/skarrik_halberd"', 1, true))
		H.truthy(package:find(
			'"units/woc_skarrik_halberd/skarrik_halberd_3p"', 1, true))
	end)
end
