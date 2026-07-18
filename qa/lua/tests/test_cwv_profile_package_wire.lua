return function(H, repo_root)
	local module_path = repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_profile_package_wire.lua"
	local policy = assert(loadfile(module_path))()

	local original_template = { name = "sword_and_mace_template" }
	local original_units = {
		right_hand_unit = "units/custom/sword",
		left_hand_unit = "units/custom/mace",
	}
	local base_item = {
		template = "dual_hammer_sword_template",
		right_hand_unit = "units/vanilla/mace_04",
		left_hand_unit = "units/vanilla/sword_06",
		right_hand_unit_override = { es_mercenary = "units/vanilla/mace_merc" },
		ammo_unit = "units/vanilla/ammo",
		ammo_unit_3p = "units/vanilla/ammo_3p",
	}
	local base_template = { name = "dual_hammer_sword_template" }
	local master = { es_dual_wield_hammer_sword = base_item }
	local markers = setmetatable({}, { __mode = "k" })

	H.test("CWV #491 remote package collection selects the vanilla wire base", function()
		H.equal(policy.mark(markers, original_units, "cwv_es_sword_and_mace",
			"es_dual_wield_hammer_sword"), true)
		local template, units, shadowed, marker = policy.select_inputs(
			original_template, original_units, false, "es_mercenary", markers,
			master, function(item)
				H.equal(item, base_item)
				return base_template
			end)
		H.equal(shadowed, true)
		H.equal(template, base_template)
		H.equal(units.right_hand_unit, "units/vanilla/mace_merc")
		H.equal(units.left_hand_unit, "units/vanilla/sword_06")
		H.equal(units.ammo_unit, "units/vanilla/ammo")
		H.equal(units.ammo_unit_3p, "units/vanilla/ammo_3p")
		H.equal(marker.variant_key, "cwv_es_sword_and_mace")
		H.equal(marker.base_item_key, "es_dual_wield_hammer_sword")
		-- Selection never mutates the authored CWV render units.
		H.equal(original_units.right_hand_unit, "units/custom/sword")
		H.equal(original_units.left_hand_unit, "units/custom/mace")
	end)

	H.test("CWV #491 owner first-person collection remains authored", function()
		local called = false
		local template, units, shadowed = policy.select_inputs(
			original_template, original_units, true, "es_mercenary", markers,
			master, function() called = true return base_template end)
		H.equal(template, original_template)
		H.equal(units, original_units)
		H.equal(shadowed, false)
		H.equal(called, false)
	end)

	H.test("CWV #491 unmarked and invalid shadows fail closed", function()
		local native_units = { right_hand_unit = "units/vanilla/native" }
		local template, units, shadowed = policy.select_inputs(
			original_template, native_units, false, "es_mercenary", markers,
			master, function() error("must not resolve") end)
		H.equal(template, original_template)
		H.equal(units, native_units)
		H.equal(shadowed, false)

		local missing = {}
		policy.mark(markers, missing, "cwv_missing", "missing_base")
		template, units, shadowed = policy.select_inputs(original_template,
			missing, false, "es_mercenary", markers, master, function()
				error("must not resolve")
			end)
		H.equal(template, original_template)
		H.equal(units, missing)
		H.equal(shadowed, false)
	end)

	H.test("CWV #491 main installs one marker-to-package shadow path", function()
		local main_path = repo_root
			.. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua"
		local file = assert(io.open(main_path, "rb"))
		local text = file:read("*a")
		file:close()
		H.truthy(text:find('_om.profile_package_wire = mod:dofile', 1, true))
		H.truthy(text:find('_om.profile_package_wire.mark_runtime(result, cwv_key', 1, true))
		H.truthy(text:find('_om.profile_package_wire })', 1, true))
		local bridge_path = repo_root
			.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_mod_unit_preview.lua"
		local bridge_file = assert(io.open(bridge_path, "rb"))
		local bridge = bridge_file:read("*a")
		bridge_file:close()
		H.truthy(bridge:find('mod:hook(WeaponUtils, "get_weapon_packages"', 1, true))
		H.truthy(bridge:find("one_policy.select_package_inputs", 1, true))
	end)
end
