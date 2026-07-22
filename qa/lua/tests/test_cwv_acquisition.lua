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

    H.test("CWV seeds exactly one collision-safe Blacksmith identity", function()
        local def = { item_key = "cwv_one" }
        H.truthy(helper.is_seed_eligible(def))
        H.equal(helper.blacksmith_seed_id(def, function() return false end), "cwv_one_001")
        H.equal(helper.blacksmith_seed_id(def, function(id)
            return id == "cwv_one_001"
        end), "cwv_one_000")
        H.equal(helper.blacksmith_seed_id(def, function(id)
            return id == "cwv_one_001" or id == "cwv_one_000"
        end), nil)
		H.equal(helper.blacksmith_seed_id(def, function()
			error("ownership store unavailable")
		end), nil)
		H.equal(helper.blacksmith_seed_id(def, function(id)
			if id == "cwv_one_001" then return true end
			error("fallback ownership unavailable")
		end), nil)
        H.equal(helper.blacksmith_seed_id({ item_key = "cwv_skin", skin_only = true }), nil)
        H.equal(helper.blacksmith_seed_id({ item_key = "cwv_old", cwv_retired = true }), nil)

        local legacy = { cwv_one_001 = true, cwv_one_002 = true }
        local protected = { cwv_one_001 = true }
        H.equal(helper.should_remove("cwv_one_001", legacy,
            function() return false end, protected), false)
        H.truthy(helper.should_remove("cwv_one_002", legacy,
            function() return false end, protected))

        local bounded = helper.legacy_auto_grant_ids({ def })
        H.truthy(bounded.cwv_one_000)
        H.truthy(bounded.cwv_one_001)
        H.truthy(helper.should_remove("cwv_one_000", bounded,
            function() return false end, { cwv_one_001 = true }))
        H.equal(helper.should_remove("cwv_one_000", bounded,
            function(id) return id == "cwv_one_000" end,
            { cwv_one_001 = true }), false)
    end)

    H.test("CWV seed builder owns exact vanilla Blacksmith shape", function()
        local original = { item_key = "cwv_one", traits = { "old" }, properties = { old = 1 } }
        local built, seed_id = helper.build_seed(original, function(definition, backend_id)
            return { definition = definition, mod_data = { backend_id = backend_id } }
        end, function(value)
            local copy = {}
            for key, field in pairs(value) do copy[key] = field end
            return copy
        end, function() return false end)
        H.equal(seed_id, "cwv_one_001")
        H.equal(built.definition.rarity, "default")
        H.equal(built.definition.power_level, 5)
        H.equal(next(built.definition.traits), nil)
        H.equal(next(built.definition.properties), nil)
        H.truthy(built.definition.no_skin)
        H.equal(original.rarity, nil)

        local missing, collision_id, reason = helper.build_seed(original,
            function() error("must not build") end,
            function(value) return value end,
            function(id) return id == "cwv_one_001" or id == "cwv_one_000" end)
        H.equal(missing, nil)
        H.equal(collision_id, nil)
        H.equal(reason, "no collision-safe identity")
    end)

    H.test("CWV seed registration canonicalizes the live backend row", function()
        local live = { CustomData = { skin = "old" }, skin = "old" }
        local added = 0
        local report = helper.register_seeds({
            { mod_data = { backend_id = "cwv_one_001" } },
        }, 1, function(rows)
            added = #rows
        end, function(id)
            H.equal(id, "cwv_one_001")
            return live
        end)
        H.truthy(report.ok)
        H.equal(report.canonicalized, 1)
        H.equal(added, 1)
        H.equal(live.rarity, "default")
        H.equal(live.power_level, 5)
        H.equal(live.skin, nil)
        H.equal(live.CustomData.rarity, "default")
        H.equal(live.CustomData.power_level, "5")

        local failed = helper.register_seeds({
            { mod_data = { backend_id = "cwv_one_001" } },
        }, 1, function() error("MIL failure") end, function()
            error("must not fetch after registration failure")
        end)
        H.equal(failed.ok, false)
        H.equal(failed.failed, 1)
        H.truthy(failed.error:find("MIL failure", 1, true))

        local missing = helper.register_seeds({
            { mod_data = { backend_id = "cwv_one_001" } },
        }, 1, function() end, function() return nil end)
        H.equal(missing.ok, false)
        H.equal(missing.failed, 1)

		local malformed_live = { CustomData = "corrupt", rarity = "old", power_level = 300 }
		local malformed = helper.register_seeds({
			{ mod_data = { backend_id = "cwv_one_001" } },
		}, 1, function() end, function() return malformed_live end)
		H.equal(malformed.ok, false)
		H.equal(malformed.failed, 1)
		H.equal(malformed_live.rarity, "old")
		H.equal(malformed_live.power_level, 300)
    end)

	H.test("CWV CIM owner probe fails closed when a store throws", function()
		local probe = helper.owner_probe({
			_cim_get_craft = function() error("store unavailable") end,
		})
		H.equal(probe("cwv_one_001"), nil)
		local winning = helper.owner_probe({
			_cim_get_craft = function() error("store unavailable") end,
		}, {
			_cim_get_craft = function(id)
				return id == "cwv_one_001" and { backend_id = id } or nil
			end,
		})
		H.equal(winning("cwv_one_001"), true)
	end)

    H.test("CWV removal planning is finite sorted and ownership safe", function()
        local removals = helper.plan_removals({
            { item_key = "cwv_two", instances = 2 },
            { item_key = "cwv_one" },
        }, { retired_001 = true }, function(id)
            return id == "cwv_two_002"
        end, { cwv_one_001 = true })
        H.equal(table.concat(removals, ","),
            "cwv_one_000,cwv_two_000,cwv_two_001,retired_001")
    end)

    H.test("CWV source registers one bounded Blacksmith seed per definition", function()
        local path = repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find("mod._cwv_acquisition.register_seed_interfaces(", 1, true))
        H.truthy(source:find("entry.cwv_definition = backend_id == nil", 1, true))
        H.truthy(source:find("mod._cwv_acquisition.plan_removals(", 1, true))
        local helper_path = repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_acquisition.lua"
        local helper_file = assert(io.open(helper_path, "rb"))
        local helper_source = helper_file:read("*a")
        helper_file:close()
        H.truthy(helper_source:find("mil:add_mod_items_to_local_backend(rows, owner_name)", 1, true))
        H.truthy(helper_source:find('seed_definition.power_level = 5', 1, true))
        H.truthy(helper_source:find('seed_definition.rarity = "default"', 1, true))
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
