return function(H, repo_root)
    local policy = dofile(repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_greataxe.lua")

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    H.test("CWV #597 Greataxe replaces Poleaxe with exact Bardin behavior", function()
        H.equal(policy.ITEM_KEY, "cwv_es_greataxe")
        H.equal(policy.BASE_WEAPON, "dr_2h_axe")
        H.equal(policy.TEMPLATE_KEY, "cwv_greataxe_template")
        local source = read(repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua")
        H.truthy(source:find("table.clone(Weapons.two_handed_axes_template_1, true)", 1, true))
        H.equal(source:find("_POLEAXE_SPEED_MULT", 1, true), nil)
        H.equal(source:find("_POLEAXE_POWER_MULT", 1, true), nil)
        H.equal(source:find('item_key        = "cwv_es_poleaxe"', 1, true), nil)
    end)

    H.test("CWV #597 Greataxe uses WT's exact Kruber 3P redirects", function()
        H.equal(policy.ANIM_REMAP_3P.attack_swing_up, "attack_swing_left")
        H.equal(policy.ANIM_REMAP_3P.attack_swing_heavy_left_diagonal, "attack_swing_heavy")
        H.equal(policy.ANIM_REMAP_3P.attack_swing_heavy_right_diagonal, "attack_swing_heavy_right")
        local source = read(repo_root
            .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_anim_remap_data.lua")
        H.truthy(source:find('attack_swing_up                   = "attack_swing_left"', 1, true))
        H.truthy(source:find('attack_swing_heavy_left_diagonal  = "attack_swing_heavy"', 1, true))
        H.truthy(source:find('attack_swing_heavy_right_diagonal = "attack_swing_heavy_right"', 1, true))
    end)

    H.test("CWV #597 Greataxe authors Kruber and WT controls all careers", function()
        H.equal(#policy.DEFAULT_CAREERS, 4)
        H.equal(#policy.ALL_CAREERS, 20)
        H.equal(#policy.conditional_careers(), 16)
        local catalog = dofile(repo_root
            .. "/weapon_tweaker/scripts/mods/weapon_tweaker/wt_cwv_variant_catalog.lua")
        local row
        for _, candidate in ipairs(catalog) do
            if candidate.key == policy.ITEM_KEY then row = candidate; break end
        end
        H.truthy(row)
        H.equal(#row.careers, 20)
        H.equal(#row.default_careers, 4)
        H.equal(#row.authored_careers, 4)
        H.equal(#row.conditional_careers, 16)
    end)

    H.test("CWV #597 packages five exact licensed model rows", function()
        H.equal(#policy.MODELS, 5)
        for index, model in ipairs(policy.MODELS) do
            local id = string.format("%02d", index)
            local unit_root = "units/cwv_es_greataxe/axe_" .. id .. "/axe_" .. id
            H.equal(model.key, "cwv_es_greataxe_skin_" .. id)
            H.equal(model.display_name, "Greataxe Model " .. id)
            H.equal(model.right_hand_unit, unit_root)
            for _, suffix in ipairs({ ".fbx", ".unit", "_3p.fbx", "_3p.unit", ".material" }) do
                local handle = io.open(repo_root .. "/character_weapon_variants/" .. unit_root .. suffix, "rb")
                H.truthy(handle, unit_root .. suffix .. " must be packaged")
                if handle then handle:close() end
            end
        end
    end)

    H.test("CWV #597 Greataxe model manifest rejects incomplete rows", function()
        local original = policy.MODELS
        policy.MODELS = {}
        for _, row in ipairs(original) do policy.MODELS[#policy.MODELS + 1] = row end
        policy.MODELS[#policy.MODELS + 1] = { key = "missing_name", right_hand_unit = "units/test" }
        policy.MODELS[#policy.MODELS + 1] = {
            key = "cwv_es_greataxe_skin_test",
            display_name = "Greataxe Test Model",
            right_hand_unit = "units/cwv_es_greataxe/axe_test/axe_test",
        }
        local usable = policy.usable_models()
        H.equal(#usable, #original + 1)
        H.equal(usable[#usable].key, "cwv_es_greataxe_skin_test")
        policy.MODELS = original
    end)

	H.test("CWV #597 custom preview packages borrow a vanilla global anchor", function()
		local anchor = "units/weapons/player/wpn_dw_2h_axe_01_t1/wpn_dw_2h_axe_01_t1_3p"
		H.equal(policy.PREVIEW_PACKAGE_ALIAS, anchor)
		local master = read(repo_root
			.. "/character_weapon_variants/resource_packages/character_weapon_variants/character_weapon_variants.package")
		for _, model in ipairs(policy.MODELS) do
			H.equal(policy.preview_package_alias(model.right_hand_unit), anchor)
			H.equal(policy.preview_package_alias(model.right_hand_unit .. "_3p"), anchor)
			-- The mod-scoped master owns residency; the vanilla alias is only
			-- the previewer's globally discoverable lifetime reference.
			H.truthy(master:find('"' .. model.right_hand_unit .. '"', 1, true))
			H.truthy(master:find('"' .. model.right_hand_unit .. '_3p"', 1, true))
		end
		H.equal(master:find("package = [", 1, true), nil,
			"custom preview units must be flattened into the runtime root")
		for id = 1, 5 do
			local suffix = string.format("axe_%02d", id)
			H.truthy(master:find('"units/cwv_es_greataxe/' .. suffix .. '/' .. suffix .. '"', 1, true))
			H.truthy(master:find('"textures/cwv_es_greataxe/' .. suffix .. '/*"', 1, true))
		end
		H.equal(policy.preview_package_alias("units/vanilla/control_3p"), nil)
	end)

	H.test("CWV #597 preview bridge guards package load spawn and unload", function()
		local source = read(repo_root
			.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_mod_unit_preview.lua")
		H.truthy(source:find('mod:hook("LootItemUnitPreviewer", "load_package"', 1, true))
		H.truthy(source:find('mod:hook("LootItemUnitPreviewer", "_unload_packages"', 1, true))
		H.truthy(source:find('mod:hook("HeroPreviewer", "_load_packages"', 1, true))
		H.truthy(source:find("Application.can_get, \"unit\"", 1, true))
		H.truthy(source:find("apply_loot_fallbacks", 1, true))
	end)

	H.test("CWV #597 Greataxe package names encode as vanilla wire identities", function()
		local one_p = policy.NETWORK_PACKAGE_ALIAS_1P
		local three_p = policy.NETWORK_PACKAGE_ALIAS_3P
		local lookup = {
			[one_p] = 101,
			[three_p] = 202,
			[101] = one_p,
			[202] = three_p,
		}
		local aliases = policy.network_package_aliases()
		H.equal(policy.install_network_package_aliases(lookup), 10)
		for _, model in ipairs(policy.MODELS) do
			H.equal(aliases[model.right_hand_unit], one_p)
			H.equal(aliases[model.right_hand_unit .. "_3p"], three_p)
			H.equal(lookup[model.right_hand_unit], 101)
			H.equal(lookup[model.right_hand_unit .. "_3p"], 202)
		end
		-- Never hijack reverse decode: peers receive resident vanilla packages.
		H.equal(lookup[101], one_p)
		H.equal(lookup[202], three_p)
	end)

	H.test("CWV #597 ProfileSynchronizer collection borrows vanilla packages only", function()
		local model = policy.MODELS[1]
		local custom_1p = model.right_hand_unit
		local custom_3p = custom_1p .. "_3p"
		local control = "units/weapons/player/control/control_3p"
		local packages = { custom_1p, control, custom_3p }

		local result, replaced = policy.alias_collected_packages(packages)
		H.equal(result, packages)
		H.equal(replaced, 2)
		H.equal(packages[1], policy.NETWORK_PACKAGE_ALIAS_1P)
		H.equal(packages[2], control)
		H.equal(packages[3], policy.NETWORK_PACKAGE_ALIAS_3P)

		-- Package collection must never rewrite the authored render unit.
		H.equal(model.right_hand_unit, custom_1p)
		H.equal(policy.collected_package_alias(control), nil)

		local bridge = read(repo_root
			.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_mod_unit_preview.lua")
		H.truthy(bridge:find('mod:hook(WeaponUtils, "get_weapon_packages"', 1, true))
		H.truthy(bridge:find("policy.alias_collected_packages(package_names)", 1, true))
	end)

	H.test("CWV #597 Greataxe wire aliases fail closed without vanilla indices", function()
		local lookup = setmetatable({}, {
			__index = function(_, key) error("strict lookup: " .. tostring(key)) end,
		})
		H.equal(policy.install_network_package_aliases(lookup), 0)
		for custom_path in pairs(policy.network_package_aliases()) do
			H.equal(rawget(lookup, custom_path), nil)
		end
	end)
end
