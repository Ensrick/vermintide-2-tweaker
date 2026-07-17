return function(H, repo_root)
	local policy = dofile(repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_dawi_maces.lua")
	local identity = dofile(repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_mace_hammer_identity.lua")

	local function read(path)
		local file = assert(io.open(path, "rb"))
		local source = file:read("*a")
		file:close()
		return source
	end

	local function row_for(catalog, key)
		for _, row in ipairs(catalog) do
			if row.key == key then return row end
		end
	end

	H.test("CWV #602 Dawi Mace identities and source movesets are canonical", function()
		H.equal(#policy.VARIANTS, 3)
		H.equal(policy.VARIANTS[1].key, "cwv_dr_dawi_mace")
		H.equal(policy.VARIANTS[1].base_weapon, "es_1h_mace")
		H.equal(policy.VARIANTS[1].template, "one_handed_hammer_template_1")
		H.equal(policy.VARIANTS[2].key, "cwv_dr_dawi_mace_shield")
		H.equal(policy.VARIANTS[2].base_weapon, "es_mace_shield")
		H.equal(policy.VARIANTS[2].template, "one_handed_hammer_shield_template_1")
		H.equal(policy.VARIANTS[3].key, "cwv_dr_dawi_dual_maces")
		H.equal(policy.VARIANTS[3].base_weapon, "dr_dual_wield_hammers")
		H.equal(policy.VARIANTS[3].template, "cwv_dual_maces_template")
	end)

	H.test("CWV #602 Dawi placeholders are resident vanilla assets only", function()
		H.equal(policy.PLACEHOLDER_MACE,
			"units/weapons/player/wpn_dw_hammer_01_t1/wpn_dw_hammer_01_t1")
		H.equal(policy.PLACEHOLDER_SHIELD,
			"units/weapons/player/wpn_dw_shield_01_t1/wpn_dw_shield_01")
		H.equal(policy.PLACEHOLDER_MACE:find("units/cwv_", 1, true), nil)
		H.equal(policy.PLACEHOLDER_SHIELD:find("units/cwv_", 1, true), nil)
		local source = read(repo_root
			.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_dawi_maces.lua")
		H.equal(source:lower():find("tower_mace", 1, true), nil)
		H.equal(source:find("units/cwv_", 1, true), nil)
	end)

	H.test("CWV #602 blocked model candidates stay audited and unpackaged", function()
		local audit = read(repo_root
			.. "/character_weapon_variants/tools/DAWI_MACE_ASSET_AUDIT.md")
		H.truthy(audit:find("7cc646d8e8084a5fb2961855bca284e8", 1, true))
		H.truthy(audit:find(
			"7929EADFF79A10BF6C5FC8C568EEE8F3E6F367C8DA2713274D3392FC4F4ADF2D",
			1, true))
		H.truthy(audit:find(
			"6D4CF23FF13C38AEED071DD3899FDF2DB6303C501C8EEEC04923923395C2CABF",
			1, true))
		H.truthy(audit:find(
			"F692447957312B18C976897BF50409108EEC8E3799DB023C75B5BE622F1CE0B8",
			1, true))
		H.truthy(audit:find(
			"16054F14B2A9E3CFB98915BD027C89AD9F74D76976AAE080689F6C2D376FC655",
			1, true))
		H.truthy(audit:find("500,000 polygons", 1, true))
		H.truthy(audit:find("issue #628", 1, true))
		H.truthy(audit:find("Empirical unblock routes", 1, true))

		local package = read(repo_root
			.. "/character_weapon_variants/resource_packages/character_weapon_variants/character_weapon_variants.package")
		H.equal(package:lower():find("tower_mace", 1, true), nil)
		H.equal(package:lower():find("uuid_model", 1, true), nil)
		H.equal(package:find("units/cwv_dr_dawi_mace", 1, true), nil)
	end)

	H.test("CWV #602 Bardin defaults and WT optional ownership are exact", function()
		H.equal(#policy.ALL_CAREERS, 20)
		H.equal(#policy.NATIVE_ONE_HANDED, 3)
		H.equal(#policy.NATIVE_SHIELD, 2)
		local catalog = dofile(repo_root
			.. "/weapon_tweaker/scripts/mods/weapon_tweaker/wt_cwv_variant_catalog.lua")
		for _, variant in ipairs(policy.VARIANTS) do
			local row = row_for(catalog, variant.key)
			H.truthy(row, variant.key .. " absent from WT catalog")
			H.equal(#row.careers, 20)
			H.equal(#row.default_careers, #variant.default_careers)
			H.equal(#row.authored_careers, #variant.default_careers)
			H.equal(#row.conditional_careers,
				20 - #variant.default_careers)
		end
	end)

	H.test("CWV #602 composes with #599 once by shared template identity", function()
		local mace_templates = {}
		for _, key in ipairs(identity.MACE_TEMPLATE_KEYS) do mace_templates[key] = true end
		for _, variant in ipairs(policy.VARIANTS) do
			H.equal(mace_templates[variant.template], true,
				variant.template .. " must remain in the canonical mace family")
		end
		local source = read(repo_root
			.. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua")
		H.equal(source:find("cwv_dawi_mace_template", 1, true), nil)
		H.equal(source:find("cwv_dawi_mace_shield_template", 1, true), nil)
	end)

	H.test("CWV #602 registers exact CIM and Cosmetics skin contracts", function()
		local source = read(repo_root
			.. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua")
		for _, variant in ipairs(policy.VARIANTS) do
			H.truthy(source:find('item_key        = "' .. variant.key .. '"', 1, true))
			H.truthy(source:find(variant.key .. '_skins', 1, true))
		end
		H.truthy(source:find('cwv_dr_dawi_dual_maces        = "units/weapons/weapon_display/display_dual_hammers"', 1, true))
		H.truthy(source:find('cwv_dr_dawi_mace_shield       = "units/weapons/weapon_display/display_shield_hammer"', 1, true))
	end)
end
