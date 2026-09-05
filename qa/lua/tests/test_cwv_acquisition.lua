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

    H.test("CWV #1141 seed provider proves only exact registered seed identities", function()
        local key = "cwv_es_dual_swords"
        local donor_key = "we_dual_wield_swords"
        local master = {
            [key] = {
                cwv_variant = true, cwv_definition = true,
                cwv_key = key, key = donor_key, name = donor_key,
            },
        }
        local registered = { [key] = master[key] }
        local function fixture(backend_id)
            local seed_entry = {
                key = donor_key, name = donor_key, cwv_variant = true,
                cwv_definition = false, cwv_key = key,
                rarity = "default",
                mod_data = {
                    backend_id = backend_id, ItemInstanceId = backend_id,
                    rarity = "default", power_level = 5,
                    traits = {}, properties = {},
                    CustomData = {
                        rarity = "default", power_level = "5",
                        traits = "[]", properties = "{}",
                    },
                },
            }
            local live = {
                IsModItem = true, CreatedBy = "character_weapon_variants",
                backend_id = backend_id, ItemInstanceId = backend_id,
                key = donor_key, ItemId = donor_key,
                rarity = "default", power_level = 5,
                traits = {}, properties = {},
                CustomData = {
                    rarity = "default", power_level = "5",
                    traits = "[]", properties = "{}",
                },
                data = seed_entry,
            }
            local protected = assert(helper.protect_seed_identity(
                backend_id, key, seed_entry, master[key]))
            return live, { [backend_id] = protected }
        end

        for _, suffix in ipairs({ "000", "001" }) do
            local backend_id = key .. "_" .. suffix
            local donor, ledger = fixture(backend_id)
            local proof, reason = helper.resolve_protected_seed(
                backend_id, donor, registered, ledger, master)
            H.equal(reason, nil)
            H.equal(proof.item_key, key)
            H.equal(proof.schema, helper.SEED_IDENTITY_SCHEMA)
            H.equal(proof.owner, helper.SEED_IDENTITY_OWNER)
            H.equal(proof.capability, helper.SEED_IDENTITY_CAPABILITY)
            H.equal(proof.backend_id, backend_id)
            H.equal(proof.item_key, key)
        end

        for _, backend_id in ipairs({
            key .. "_002", key .. "_100", key .. "_abc", "foreign_001",
        }) do
            local donor, ledger = fixture(backend_id)
            local resolved, reason = helper.resolve_protected_seed(
                backend_id, donor, registered, ledger, master)
            H.equal(resolved, nil)
            H.equal(reason, "seed_band")
        end

        local backend_id = key .. "_001"
        local donor, ledger = fixture(backend_id)
        local resolved, reason = helper.resolve_protected_seed(
            backend_id, donor, registered, {}, master)
        H.equal(resolved, nil)
        H.equal(reason, "seed_not_protected")
        resolved, reason = helper.resolve_protected_seed(
            backend_id, donor, registered,
            { [backend_id] = { item_key = "cwv_es_longsword",
                seed_entry = ledger[backend_id].seed_entry } }, master)
        H.equal(resolved, nil)
        H.equal(reason, "seed_not_protected")

        local conflicting; conflicting, ledger = fixture(backend_id)
        conflicting.cwv_key = "cwv_es_longsword"
        resolved, reason = helper.resolve_protected_seed(
            backend_id, conflicting, registered, ledger, master)
        H.equal(resolved, nil)
        H.equal(reason, "stamp_conflict")

        local backend_alias; backend_alias, ledger = fixture(backend_id)
        backend_alias.key = backend_id
        backend_alias.ItemId = backend_id
        resolved, reason = helper.resolve_protected_seed(
            backend_id, backend_alias, registered, ledger, master)
        H.equal(resolved, nil)
        H.equal(reason, "seed_donor_mismatch")

        local hidden; hidden, ledger = fixture(backend_id)
        hidden.data.CustomData = { cwv_key = "cwv_es_longsword" }
        resolved, reason = helper.resolve_protected_seed(
            backend_id, hidden, registered, ledger, master)
        H.equal(resolved, nil)
        H.equal(reason, "stamp_conflict")

        local shape_mutations = {
            function(item) item.data.CustomData = { rarity = "modded" } end,
            function(item) item.data.mod_data.power_level = 300 end,
            function(item) item.data.mod_data.traits = { "foreign" } end,
            function(item) item.data.mod_data.properties = { power = 1 } end,
            function(item) item.data.mod_data.CustomData.skin = "foreign_skin" end,
        }
        for _, mutate in ipairs(shape_mutations) do
            local malformed; malformed, ledger = fixture(backend_id)
            mutate(malformed)
            resolved, reason = helper.resolve_protected_seed(
                backend_id, malformed, registered, ledger, master)
            H.equal(resolved, nil)
            H.truthy(reason == "seed_shape_mismatch"
                or reason == "seed_required_shape_mismatch"
                or reason == "seed_skin_mismatch")
        end

        local required_shape_mutations = {
            function(item) item.CustomData = false end,
            function(item) item.data.mod_data = false end,
            function(item) item.data.mod_data.CustomData = false end,
        }
        for _, mutate in ipairs(required_shape_mutations) do
            local malformed; malformed, ledger = fixture(backend_id)
            mutate(malformed)
            resolved, reason = helper.resolve_protected_seed(
                backend_id, malformed, registered, ledger, master)
            H.equal(resolved, nil)
            H.truthy(reason == "seed_required_shape_mismatch"
                or reason == "seed_provenance_mismatch")
        end

        local foreign; foreign, ledger = fixture(backend_id)
        foreign.CreatedBy = "foreign_mod"
        resolved, reason = helper.resolve_protected_seed(
            backend_id, foreign, registered, ledger, master)
        H.equal(resolved, nil)
        H.equal(reason, "seed_provenance_mismatch")

        local replacement; replacement, ledger = fixture(backend_id)
        local original_master = master[key]
        local mimic = {}
        for field, value in pairs(original_master) do mimic[field] = value end
        master[key] = mimic
        resolved, reason = helper.resolve_protected_seed(
            backend_id, replacement, registered, ledger, master)
        H.equal(resolved, nil)
        H.equal(reason, "provider_row_replaced")
        master[key] = original_master

        local bad_master; bad_master, ledger = fixture(backend_id)
        original_master.name = "foreign_donor"
        resolved, reason = helper.resolve_protected_seed(
            backend_id, bad_master, registered, ledger, master)
        H.equal(resolved, nil)
        H.equal(reason, "provider_row_mismatch")
        original_master.name = donor_key

        local bad_name; bad_name, ledger = fixture(backend_id)
        bad_name.data.name = "foreign_donor"
        resolved, reason = helper.resolve_protected_seed(
            backend_id, bad_name, registered, ledger, master)
        H.equal(resolved, nil)
        H.equal(reason, "seed_provenance_mismatch")

        for _, bad_value in ipairs({ "foreign_donor", false }) do
            local nested; nested, ledger = fixture(backend_id)
            nested.data.mod_data.ItemId = bad_value
            resolved, reason = helper.resolve_protected_seed(
                backend_id, nested, registered, ledger, master)
            H.equal(resolved, nil)
            H.equal(reason, "semantic_key_conflict")
        end
    end)

    H.test("CWV #1141 seed provider samples its live proven ledger", function()
        local key, backend_id = "cwv_es_dual_swords", "cwv_es_dual_swords_001"
        local donor_key = "we_dual_wield_swords"
        local master = { [key] = {
            cwv_variant = true, cwv_definition = true, cwv_key = key,
            key = donor_key, name = donor_key,
        } }
        local seed_entry = {
            key = donor_key, name = donor_key,
            cwv_variant = true, cwv_definition = false,
            cwv_key = key, rarity = "default",
            mod_data = {
                backend_id = backend_id, ItemInstanceId = backend_id,
                rarity = "default", power_level = 5,
                traits = {}, properties = {},
                CustomData = { rarity = "default", power_level = "5",
                    traits = "[]", properties = "{}" },
            },
        }
        local ledger = { [backend_id] = assert(helper.protect_seed_identity(
            backend_id, key, seed_entry, master[key])) }
        local live = {
            IsModItem = true, CreatedBy = "character_weapon_variants",
            backend_id = backend_id, ItemInstanceId = backend_id,
            key = donor_key, ItemId = donor_key,
            rarity = "default", power_level = 5,
            traits = {}, properties = {},
            CustomData = { rarity = "default", power_level = "5",
                traits = "[]", properties = "{}" },
            data = seed_entry,
        }
        local provider = helper.new_seed_identity_provider({
            registered_keys = { [key] = master[key] },
            get_protected_seed_ids = function() return ledger end,
            get_item_master_list = function() return master end,
            get_backend_item = function(id)
                H.equal(id, backend_id)
                return live
            end,
        })
        local sample, sample_error = provider:sample()
        H.equal(sample_error, nil)
        H.equal(sample.backend_id, backend_id)
        H.equal(sample.item_key, key)
        H.equal(sample.item, nil)
        H.equal(sample.proof.donor_key, donor_key)
        H.equal(sample.proof.fingerprint,
            "cwv-blacksmith-seed-v2|" .. backend_id .. "|" .. key
                .. "|" .. donor_key)
        local transaction_ok, transaction_error, proven =
            helper.validate_seed_transaction(provider, ledger)
        H.truthy(transaction_ok)
        H.equal(transaction_error, nil)
        H.equal(proven, 1)
        H.equal(provider:sample(key).item_key, key)
        local absent, absent_reason = provider:sample("cwv_es_longsword")
        H.equal(absent, nil)
        H.equal(absent_reason, "protected_seed_key_unavailable")

        ledger = { [backend_id] = {
            backend_id = backend_id,
            item_key = "cwv_es_longsword",
            donor_key = donor_key,
            donor_name = donor_key,
            registered_master = master[key],
            seed_ref = seed_entry,
        } }
        H.equal(provider:sample(), nil)

        live.CreatedBy = "foreign_mod"
        local invalid, invalid_reason, accepted =
            helper.validate_seed_transaction(provider, ledger)
        H.equal(invalid, false)
        H.truthy(type(invalid_reason) == "string")
        H.equal(accepted, 0)

        local unavailable = helper.new_seed_identity_provider({
            registered_keys = {},
            get_protected_seed_ids = function() error("ledger") end,
            get_item_master_list = function() return {} end,
            get_backend_item = function() return {} end,
        })
        local _, sample_reason = unavailable.resolve({}, backend_id)
        H.equal(sample_reason, "protected_seed_ledger_unavailable")
    end)

    H.test("CWV #1141 seed registration canonicalizes raw mirror authority", function()
        local backend_id = "cwv_one_001"
        local seed_entry = {
            name = "donor", key = "donor", slot_type = "melee",
            mod_data = { backend_id = backend_id },
        }
        local raw_item, dirty = nil, 0
        local mil = {}
        function mil:add_mod_items_to_local_backend(rows, owner)
            H.equal(owner, "character_weapon_variants")
            H.equal(rows[1], seed_entry)
            raw_item = {
                rarity = "modded", power_level = 300,
                traits = { "foreign" }, properties = { power = 1 },
                skin = "foreign", CustomData = {
                    rarity = "modded", power_level = "300",
                    traits = "[foreign]", properties = "{power:1}",
                    skin = "foreign",
                },
            }
        end
        local mirror = { get_all_inventory_items = function()
            return { [backend_id] = raw_item }
        end }
        local items = { make_dirty = function() dirty = dirty + 1 end }
        local report = helper.register_seed_interfaces({ seed_entry }, 1,
            mil, items, mirror, "character_weapon_variants")
        H.truthy(report.ok)
        H.equal(report.canonicalized, 1)
        H.equal(raw_item.rarity, "default")
        H.equal(raw_item.power_level, 5)
        H.equal(raw_item.skin, nil)
        H.equal(raw_item.CustomData.rarity, "default")
        H.equal(dirty, 1)
    end)

    H.test("CWV #592 seed cardinality diagnostic reads its published owner", function()
        local path = repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_regression_render.lua"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find(
            "tostring(_om._cwv_blacksmith_seed_count)", 1, true))
        H.equal(source:find(
            "tostring(mod._cwv_blacksmith_seed_count)", 1, true), nil)
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
        -- #1159: the clone constructor and the deferred registration pass moved
        -- from the entry to _cwv_item_registration_owner, so this gate follows
        -- the code. The entry-side absence assertions below keep a second copy
        -- from reappearing.
        local path = repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_item_registration_owner.lua"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find("mod._cwv_acquisition.register_seed_interfaces(", 1, true))
        H.truthy(source:find("mod._cwv_acquisition.validate_seed_transaction(", 1, true))
        H.truthy(source:find("mirror:get_all_inventory_items()", 1, true),
            "provider authority must come from the raw backend mirror")
        H.truthy(source:find("local _registered_key_flags = {}", 1, true))
        H.truthy(source:find("registered_keys = _registered_key_flags", 1, true),
            "public diagnostics must not expose protected master references")
        H.truthy(source:find("entry.cwv_definition = backend_id == nil", 1, true))
        H.truthy(source:find("mod._cwv_acquisition.plan_removals(", 1, true))
        local entry_path = repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua"
        local entry_file = assert(io.open(entry_path, "rb"))
        local entry_source = entry_file:read("*a")
        entry_file:close()
        H.equal(entry_source:find("mod._cwv_acquisition.register_seed_interfaces(", 1, true), nil,
            "entry must not re-register Blacksmith seeds")
        H.equal(entry_source:find("entry.cwv_definition = backend_id == nil", 1, true), nil,
            "entry must not re-declare the definition/instance split")
        H.equal(entry_source:find("mod._cwv_acquisition.plan_removals(", 1, true), nil,
            "entry must not re-plan legacy removals")
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
