return function(H, repo_root)
    local helper = dofile(repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_acquisition.lua")

    H.test("CWV migration removes only authored legacy auto-grants", function()
        local ids = helper.legacy_auto_grant_ids({
            { item_key = "cwv_one" },
            { item_key = "cwv_two", instances = 2 },
            { item_key = "cwv_skin", skin_only = true, instances = 9 },
        })
        H.truthy(ids.cwv_one_001)
        H.truthy(ids.cwv_two_001)
        H.truthy(ids.cwv_two_002)
        H.equal(ids.cwv_two_100, nil)
        H.equal(ids.cwv_skin_001, nil)
    end)

    H.test("CWV migration preserves exact CIM persistence", function()
        local ids = { cwv_one_001 = true }
        H.truthy(helper.should_remove("cwv_one_001", ids, function() return false end))
        H.equal(helper.should_remove("cwv_one_001", ids, function(id)
            return id == "cwv_one_001"
        end), false)
        H.equal(helper.should_remove("cwv_one_100", ids, function() return false end), false)
        H.equal(helper.should_remove("cwv_one_uuid", ids, function() return false end), false)
    end)

    H.test("CWV source separates registration from acquisition", function()
        local path = repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        H.equal(source:find('add_mod_items_to_local_backend(entries, "character_weapon_variants")', 1, true), nil)
        H.truthy(source:find("entry.cwv_definition = backend_id == nil", 1, true))
        H.truthy(source:find("legacy_auto_grant_ids(_variant_definitions)", 1, true))
    end)

    H.test("CWV #273 keeps exact owners through Chaos Wastes conversion", function()
        local policy = dofile(repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_deus_identity.lua")
        local definitions = {
            { item_key = "cwv_wh_dual_axes", base_weapon = "dr_dual_wield_axes" },
            { item_key = "cwv_es_axe_shield", base_weapon = "dr_shield_axe" },
            { item_key = "cwv_skin_only", base_weapon = "dr_1h_axe", skin_only = true },
			{ item_key = "cwv_retired", base_weapon = "dr_1h_axe", cwv_retired = true },
        }
        local item_master_list = {
            cwv_wh_dual_axes = {
                key = "cwv_wh_dual_axes",
                template = "cwv_dual_axes_template",
                item_type = "cwv_wh_dual_axes",
                skin_combination_table = "cwv_wh_dual_axes_skins",
            },
            cwv_es_axe_shield = {
                key = "cwv_es_axe_shield",
                template = "cwv_axe_shield_template",
                item_type = "cwv_es_axe_shield",
                skin_combination_table = "cwv_es_axe_shield_skins",
            },
        }
        local mapping = {
            dr_dual_wield_axes = "deus_dr_dual_wield_axes",
            dr_shield_axe = "deus_dr_shield_axe",
            dr_1h_axe = "deus_dr_1h_axe",
        }
        local baked = { { "trait_melee" } }
        local deus_weapons = {
            deus_dr_dual_wield_axes = {
                base_item = "dr_dual_wield_axes",
                property_table_name = "deus_melee",
                trait_table_name = "deus_melee",
                baked_trait_combinations = baked,
            },
            deus_dr_shield_axe = {
                base_item = "dr_shield_axe",
                property_table_name = "deus_melee",
                trait_table_name = "deus_shield_melee",
                baked_trait_combinations = baked,
            },
            deus_dr_1h_axe = { base_item = "dr_1h_axe" },
        }

        local report = policy.install(definitions, item_master_list, mapping, deus_weapons, true)
        H.equal(report.installed, 2)
        H.equal(mapping.cwv_wh_dual_axes, "deus_cwv_wh_dual_axes")
        H.equal(mapping.cwv_es_axe_shield, "deus_cwv_es_axe_shield")
        H.equal(mapping.cwv_skin_only, nil)
		H.equal(mapping.cwv_retired, nil)

        local dual_deus = deus_weapons.deus_cwv_wh_dual_axes
        H.equal(dual_deus.base_item, "cwv_wh_dual_axes")
        H.equal(dual_deus.property_table_name, "deus_melee")
        H.equal(dual_deus.baked_trait_combinations, baked)
        -- This mirrors DeusWeaponGeneration.create_item: data is resolved from
        -- the dedicated row's base_item and therefore retains every CWV axis.
        local generated_data = item_master_list[dual_deus.base_item]
        H.equal(generated_data.key, "cwv_wh_dual_axes")
        H.equal(generated_data.template, "cwv_dual_axes_template")
        H.equal(generated_data.item_type, "cwv_wh_dual_axes")
        H.equal(generated_data.skin_combination_table, "cwv_wh_dual_axes_skins")

        local again = policy.install(definitions, item_master_list, mapping, deus_weapons, true)
        H.equal(again.installed, 0)
        H.equal(again.existing, 2)

        local mixed = policy.install(definitions, item_master_list, mapping, deus_weapons, false)
        H.equal(mixed.degraded, 2)
        H.equal(mapping.cwv_wh_dual_axes, "deus_dr_dual_wield_axes")
        H.equal(mapping.cwv_es_axe_shield, "deus_dr_shield_axe")
        H.equal(deus_weapons.deus_cwv_wh_dual_axes.base_item, "cwv_wh_dual_axes")
    end)
end
