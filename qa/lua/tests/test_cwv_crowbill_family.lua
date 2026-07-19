return function(H, repo_root)
    local family = dofile(repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_crowbill_family.lua")

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function exists(path)
        local file = io.open(path, "rb")
        if file then file:close() end
        return file ~= nil
    end

    local function row_for(catalog, key)
        for _, row in ipairs(catalog or {}) do
            if row.key == key then return row end
        end
    end

    local source_root = repo_root .. "/../Vermintide-2-Source-Code/scripts/settings/equipment/"
    H.test_if(exists(source_root .. "item_master_list_paperweight.lua"),
        "CWV Crowbill source keys match vanilla definitions", function()
        H.equal(family.SOURCE_ITEM, "bw_1h_crowbill")
        H.equal(family.SOURCE_TEMPLATE, "one_handed_crowbill")
        H.equal(family.SOURCE_SKIN_TABLE, "bw_1h_crowbill_skins")
        local iml = read(source_root .. "item_master_list_paperweight.lua")
        local template = read(source_root .. "weapon_templates/1h_crowbills.lua")
        H.truthy(iml:find("ItemMasterList.bw_1h_crowbill =", 1, true))
        H.truthy(iml:find('skin_combination_table = "bw_1h_crowbill_skins"', 1, true))
        H.truthy(iml:find('template = "one_handed_crowbill"', 1, true))
        H.truthy(template:find("one_handed_crowbill = weapon_template", 1, true))
        end, "optional decompiled vanilla source is not present in this clean clone")

    H.test("CWV Crowbill identities defaults fallback and approved models are exact", function()
        H.equal(#family.VARIANTS, 2)
        H.equal(family.VARIANTS[1].key, "cwv_es_imperial_crowbill")
        H.equal(#family.VARIANTS[1].default_careers, 8)
        H.equal(family.VARIANTS[2].key, "cwv_dr_dawi_crowbill")
        H.equal(#family.VARIANTS[2].default_careers, 4)
        H.equal(#family.ALL_CAREERS, 20)
        H.equal(family.PLACEHOLDER_UNIT,
            "units/weapons/player/wpn_brw_crowbill_01/wpn_brw_crowbill_01")
        H.equal(family.PLACEHOLDER_UNIT:find("units/cwv_", 1, true), nil)
        H.equal(#family.MODELS, 6)
        H.equal(#family.usable_models(), 6)
        local imperial_default = family.model_for_variant("cwv_es_imperial_crowbill")
        local dawi_default = family.model_for_variant("cwv_dr_dawi_crowbill")
        H.equal(imperial_default.source_asset_id, "parelaxel_medieval_war_hammer")
        H.equal(imperial_default.right_hand_unit,
            "units/cwv_crowbill/imperial_01/imperial_01")
        H.equal(dawi_default.source_asset_id, "soidev_war_hammer")
        H.equal(dawi_default.right_hand_unit,
            "units/cwv_crowbill/dawi_01/dawi_01")
        H.deep_equal(dawi_default.right_hand_scale_multiplier_3p, { 0.5, 0.5, 0.5 })
        H.deep_equal(dawi_default.right_hand_rotation_3p, { -90, -90, -90 })
        H.equal(dawi_default.right_hand_scale, nil)
        H.equal(dawi_default.right_hand_rotation, nil)
        H.deep_equal(dawi_default.right_hand_rotation_1p, { -90, -90, -90 })
        local master = read(repo_root
            .. "/character_weapon_variants/resource_packages/character_weapon_variants/character_weapon_variants.package")
        local variants_seen = {}
        for _, model in ipairs(family.MODELS) do
            H.truthy(family.is_usable_model(model))
            H.truthy(model.right_hand_unit:find("units/cwv_crowbill/", 1, true) == 1)
            variants_seen[model.variant_key] = true
            H.truthy(master:find('"' .. model.right_hand_unit .. '"', 1, true))
            H.truthy(master:find('"' .. model.right_hand_unit .. '_3p"', 1, true))
            local root = repo_root .. "/character_weapon_variants/" .. model.right_hand_unit
            for _, suffix in ipairs({ ".fbx", ".unit", "_3p.fbx", "_3p.unit", ".material" }) do
                local file = io.open(root .. suffix, "rb")
                H.truthy(file, root .. suffix .. " must exist")
                if file then file:close() end
            end
        end
        H.equal(variants_seen.cwv_es_imperial_crowbill, true)
        H.equal(variants_seen.cwv_dr_dawi_crowbill, true)
        H.equal(master:lower():find("italian", 1, true), nil)
        H.equal(master:find("1b159f52cb9646f98b31b0da98f79e97", 1, true), nil)
    end)

    H.test("CWV Crowbill preview and inventory aliases are forward-only", function()
        local lookup = {
            [family.NETWORK_PACKAGE_ALIAS_1P] = 301,
            [family.NETWORK_PACKAGE_ALIAS_3P] = 302,
            [301] = family.NETWORK_PACKAGE_ALIAS_1P,
            [302] = family.NETWORK_PACKAGE_ALIAS_3P,
        }
        H.equal(family.install_network_package_aliases(lookup), 12)
        for _, model in ipairs(family.MODELS) do
            H.equal(family.preview_package_alias(model.right_hand_unit), family.PREVIEW_PACKAGE_ALIAS)
            H.equal(family.preview_package_alias(model.right_hand_unit .. "_3p"), family.PREVIEW_PACKAGE_ALIAS)
            H.equal(lookup[model.right_hand_unit], 301)
            H.equal(lookup[model.right_hand_unit .. "_3p"], 302)
        end
        H.equal(lookup[301], family.NETWORK_PACKAGE_ALIAS_1P)
        H.equal(lookup[302], family.NETWORK_PACKAGE_ALIAS_3P)
    end)

    H.test("Imperial Crowbill Model 05 owns its reviewed all-surface transform", function()
        local target = row_for(family.MODELS, "cwv_es_imperial_crowbill_skin_05")
        H.truthy(target)
        H.deep_equal(target.right_hand_scale, { 0.45, 0.45, 0.45 })
        H.deep_equal(target.right_hand_offset, { 0, -0.03, -0.20 })
        H.deep_equal(target.right_hand_rotation, { -90, -90, -90 })
        H.equal(target.right_hand_scale_3p, nil)
        H.equal(target.right_hand_offset_3p, nil)
        H.equal(target.right_hand_rotation_3p, nil)
        H.equal(target.right_hand_scale_1p, nil)
        H.equal(target.right_hand_offset_1p, nil)
        H.equal(target.right_hand_rotation_1p, nil)
        for _, control in ipairs(family.MODELS) do
            if control ~= target and control.key ~= "cwv_dr_dawi_crowbill_skin" then
                H.equal(control.right_hand_scale, nil)
                H.equal(control.right_hand_offset, nil)
                H.equal(control.right_hand_rotation, nil)
            end
        end
        local main = require("cwv_source").combined(repo_root)
        H.truthy(main:find("issue604_imperial_crowbill_model05_transform", 1, true))
        H.truthy(main:find("for _, model in ipairs(_om.crowbill_family.usable_models()) do", 1, true))
        H.truthy(main:find("_crowbill_transform_by_unit[model.right_hand_unit]", 1, true))
    end)

    H.test("Dawi Crowbill Model 01 halves its settled 3P baseline", function()
        local target = row_for(family.MODELS, "cwv_dr_dawi_crowbill_skin")
        H.truthy(target)
        H.deep_equal(target.right_hand_scale_multiplier_3p, { 0.5, 0.5, 0.5 })
        H.deep_equal(target.right_hand_rotation_3p, { -90, -90, -90 })
		H.equal(target.right_hand_offset, nil)
		H.equal(target.right_hand_scale_3p, nil)
		H.equal(target.right_hand_scale_1p, nil)
		H.equal(target.right_hand_scale, nil)
		H.equal(target.right_hand_rotation, nil)
		H.deep_equal(target.right_hand_rotation_1p, { -90, -90, -90 })
        local main = require("cwv_source").combined(repo_root)
        H.truthy(main:find("issue604_dawi_crowbill_model01_transform", 1, true))
        H.truthy(main:find("transform scheduled surface=", 1, true))
		H.truthy(main:find('"pre_repair"', 1, true))
		H.truthy(main:find('"post_final"', 1, true))
		H.truthy(main:find("local resolved, baseline = relative:resolve", 1, true))
		H.truthy(main:find("spec.scale_multiplier, spec.identity_token", 1, true))
		H.truthy(main:find('_cwv_forget_crowbill_transform_unit(wielded_unit, "destroy_wielded")', 1, true))
		H.truthy(main:find('_cwv_forget_crowbill_transform_unit(unit, "item_preview_destroy")', 1, true))
		H.truthy(main:find("transform_map = _transform_map", 1, true))
		H.truthy(main:find("skin_transform_map = _skin_transform_map", 1, true))
		H.truthy(main:find("crowbill_transform_by_unit = _crowbill_transform_by_unit", 1, true))
		H.truthy(main:find("local _transform_map = ctx.transform_map", 1, true))
		H.truthy(main:find("local _skin_transform_map = ctx.skin_transform_map", 1, true))
		H.truthy(main:find("local _crowbill_transform_by_unit = ctx.crowbill_transform_by_unit", 1, true))
        H.truthy(main:find("_cwv_select_husk_transform_def(hand, exact,", 1, true))
        H.truthy(main:find("_cwv_husk_transform_apply_plan(hand, def, def_source)", 1, true))
        H.truthy(main:find('def_source == "exact_unit_mismatch"', 1, true))
        H.truthy(main:find("Dawi remote transform leaked into the untuned Imperial control", 1, true))
        H.truthy(main:find("TRANSFORM MISS surface=create_equipment", 1, true))
        H.truthy(main:find("_resolve_cwv_def(item_data, result.skin, result.right_hand_unit_name)", 1, true))
        for _, surface in ipairs({ "owner_1p", "owner_3p", "remote_husk",
                "inventory_preview", "item_browser" }) do
            H.truthy(main:find('"' .. surface .. '"', 1, true),
                "missing transform delivery consumer: " .. surface)
        end
		H.truthy(main:find("total_limit = 96", 1, true))
		H.truthy(main:find("per_model_limit = 16", 1, true))
    end)

    H.test("Dawi remote husk selects the exact model and preserves an untuned control", function()
        local policy = dofile(repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_husk_transform_policy.lua")
        local by_unit, by_variant = {}, {}
        for _, model in ipairs(family.MODELS) do
            local applied = {}
            for key, value in pairs(model) do applied[key] = value end
            applied.crowbill_model_key = model.key
            by_unit[model.right_hand_unit] = applied
            by_variant[model.variant_key] = by_variant[model.variant_key] or model
        end
        local bound = policy.bind({
            find_def = function(key) return by_variant[key] end,
            resolve_def = function() return nil end,
            resolve_field = function(def, field) return def[field] end,
            model_by_unit = by_unit,
        })
        local dawi = row_for(family.MODELS, "cwv_dr_dawi_crowbill_skin")
        local exact = { variant_key = dawi.variant_key, right_hand_unit = dawi.right_hand_unit }
        local selected, source = bound.select("right", exact, {}, nil, dawi.right_hand_unit)
        local plan = bound.plan("right", selected, source)
        H.equal(selected.crowbill_model_key, dawi.key)
        H.equal(source, "exact_model")
        H.equal(plan.scale, nil)
        H.deep_equal(plan.scale_multiplier, { 0.5, 0.5, 0.5 })
        H.deep_equal(plan.rotation, { -90, -90, -90 })
        H.equal(plan.durable, true)
        H.equal(bound.select("right", exact, {}, nil, family.PLACEHOLDER_UNIT), nil)

		local imperial = row_for(family.MODELS, "cwv_es_imperial_crowbill_skin_05")
		local imperial_def, imperial_source = bound.select("right", {
			variant_key = imperial.variant_key, right_hand_unit = imperial.right_hand_unit,
		}, {}, nil, imperial.right_hand_unit)
		local imperial_plan = bound.plan("right", imperial_def, imperial_source)
		H.equal(imperial_source, "exact_model")
		H.deep_equal(imperial_plan.scale, { 0.45, 0.45, 0.45 })
		H.equal(imperial_plan.scale_multiplier, nil)
		H.deep_equal(imperial_plan.offset, { 0, -0.03, -0.20 })
		H.deep_equal(imperial_plan.rotation, { -90, -90, -90 })
		H.equal(imperial_plan.durable, true)

        local control = row_for(family.MODELS, "cwv_es_imperial_crowbill_skin")
        local control_def, control_source = bound.select("right", {
            variant_key = control.variant_key, right_hand_unit = control.right_hand_unit,
        }, {}, nil, control.right_hand_unit)
        local control_plan = bound.plan("right", control_def, control_source)
        H.equal(control_source, "exact_model")
        H.equal(control_plan.should_apply, false)
        H.equal(control_plan.durable, false)
        H.equal(control_plan.scale_multiplier, nil)

        local native_def, native_source = bound.select("right", nil,
            { name = family.SOURCE_ITEM }, nil, family.PLACEHOLDER_UNIT)
        H.equal(native_def, nil)
        H.equal(native_source, "miss")
        H.equal(bound.plan("right", native_def, native_source), nil)
    end)

    H.test("CWV Crowbill hammer-mode seam preserves the authored contract", function()
        local mode = family.HAMMER_MODE
        local policy = dofile(repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_crowbill_hammer_mode.lua")
        H.equal(family.HAMMER_MODE_FAMILY, "cwv_crowbill_hammer_mode")
        H.equal(mode.weapon_special_toggle, true)
        H.equal(mode.default_mode, "crowbill")
        H.deep_equal(mode.model_flip_axis, { 0, 0, 1 })
        H.equal(mode.rotation_degrees, 180)
        H.equal(mode.same_moveset_and_timing, true)
        H.equal(mode.attack_cleave_multiplier, 1.60)
        H.equal(mode.impact_cleave_multiplier, 1.60)
        H.equal(mode.direct_damage_multiplier, 0.85)
        H.equal(mode.light_attacks_armor_piercing, false)
        H.equal(mode.vanilla_sienna_optional, true)
        H.equal(policy.SOURCE_TEMPLATE_KEY, family.SOURCE_TEMPLATE)
        H.deep_equal(policy.MODEL_FLIP_AXIS, mode.model_flip_axis)
        H.equal(policy.MODEL_FLIP_DEGREES, mode.rotation_degrees)
        H.equal(policy.HAMMER_CLEAVE_MULT, mode.attack_cleave_multiplier)
        H.equal(policy.HAMMER_DAMAGE_MULT, mode.direct_damage_multiplier)
        for _, variant in ipairs(family.VARIANTS) do
            H.equal(variant.crowbill_mode_family, family.HAMMER_MODE_FAMILY)
        end
    end)

    H.test("CWV Crowbills are CIM definitions not automatic grants", function()
        local main = require("cwv_source").combined(repo_root)
        for _, variant in ipairs(family.VARIANTS) do
            H.truthy(main:find('item_key        = "' .. variant.key .. '"', 1, true))
            H.truthy(main:find(variant.key .. "_skins", 1, true))
        end
        H.truthy(main:find("entry.cwv_definition = backend_id == nil", 1, true))
        H.truthy(main:find("entry.crowbill_mode_family = def.crowbill_mode_family", 1, true))
        H.truthy(main:find("mod._cwv_crowbill_hammer_mode = _om.crowbill_hammer_mode", 1, true))
        H.equal(main:find('add_mod_items_to_local_backend(entries, "character_weapon_variants")', 1, true), nil)
    end)

    H.test("WT owns all-career Crowbill controls with exact defaults", function()
        local catalog = dofile(repo_root
            .. "/weapon_tweaker/scripts/mods/weapon_tweaker/wt_cwv_variant_catalog.lua")
        for _, variant in ipairs(family.VARIANTS) do
            local row = row_for(catalog, variant.key)
            H.truthy(row, variant.key .. " absent from WT catalog")
            H.equal(#row.careers, 20)
            H.deep_equal(row.default_careers, variant.default_careers)
            H.deep_equal(row.authored_careers, variant.default_careers)
            H.equal(#row.conditional_careers, 20 - #variant.default_careers)
        end
    end)

    H.test("Cosmetics owns distinct Crowbill item and skin contracts", function()
        local cosmetics = dofile(repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_cwv_family_contract.lua")
        for _, variant in ipairs(family.VARIANTS) do
            local contract = cosmetics.get(variant.key)
            H.truthy(contract, variant.key .. " Cosmetics contract missing")
            H.equal(contract.item_type, variant.key)
            H.equal(contract.skin_table, variant.key .. "_skins")
            H.equal(contract.primary_source, family.SOURCE_ITEM)
            H.equal(cosmetics.icon_ownership(variant.key), "primary")
        end
    end)

    H.test("Chaos Wastes creates dedicated Crowbill identities", function()
        local deus = dofile(repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_deus_identity.lua")
        local definitions, items = {}, {}
        for _, variant in ipairs(family.VARIANTS) do
            definitions[#definitions + 1] = {
                item_key = variant.key,
                base_weapon = family.SOURCE_ITEM,
            }
            items[variant.key] = {
                cwv_variant = true,
                item_type = variant.key,
                template = family.SOURCE_TEMPLATE,
            }
        end
        local mapping = { [family.SOURCE_ITEM] = "deus_bw_1h_crowbill" }
        local deus_weapons = {
            deus_bw_1h_crowbill = {
                base_item = family.SOURCE_ITEM,
                property_table_name = "deus_melee",
                trait_table_name = "deus_melee",
            },
        }
        local report = deus.install(definitions, items, mapping, deus_weapons, true)
        H.equal(report.installed, 2)
        for _, variant in ipairs(family.VARIANTS) do
            H.equal(mapping[variant.key], "deus_" .. variant.key)
            H.equal(deus_weapons["deus_" .. variant.key].base_item, variant.key)
        end
    end)

    H.test("Crowbill checklist covers every model and pose surface", function()
        local doc = read(repo_root .. "/character_weapon_variants/CROWBILL_FAMILY.md")
        for _, surface in ipairs({
            "Owner first person", "Owner local third person", "Bot", "Remote husk",
            "Inventory-screen character preview", "Lobby character presentation",
            "End-of-mission score/team preview", "Illusion/Athanor preview",
        }) do
            H.truthy(doc:find(surface, 1, true), "missing Crowbill surface: " .. surface)
        end
        H.truthy(doc:find("No downloaded or custom mesh path", 1, true))
    end)
end
