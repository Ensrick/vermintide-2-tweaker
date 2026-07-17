return function(H, repo_root)
    local root = repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local contract = assert(loadfile(root .. "_cim_synthetic_item_contract.lua"))()
    local catalog = assert(loadfile(root .. "_cim_template_catalog.lua"))()
    local cleanup = assert(loadfile(root .. "_cim_bulk_cleanup_core.lua"))()

	H.test("CIM #637 rejects WOC unique relic definitions", function()
		local relic = {
			woc_variant = true,
			woc_unique_relic = true,
			slot_type = "melee",
			can_wield = { "es_mercenary" },
			template = "one_handed_swords_template_1",
			item_type = "woc_blightreaper",
			inventory_icon = "es_1h_sword_01",
		}
		local ok, problems, provider = contract.validate_provider("woc_blightreaper", relic)
		H.equal(ok, false)
		H.equal(provider, "woc")
		H.equal(problems[1], "immutable_relic")
		H.truthy(contract.is_immutable_relic(relic))
		H.truthy(contract.is_immutable_relic({ data = relic }))
		H.truthy(contract.is_immutable_relic({
			CustomData = { woc_unique_relic = "true" },
		}))
		H.truthy(contract.is_immutable_relic({
			CustomData = { woc_unique_relic = true },
		}))
	end)

    local function master(marker)
        local row = {
            slot_type = "melee",
            can_wield = { "dr_ranger" },
            template = "one_handed_hammer_template_1",
            item_type = "test_weapon",
            inventory_icon = "icon_test_weapon",
        }
        row[marker] = true
        return row
    end

    H.test("CIM #628 provider contract covers Dawi, older CWV, and WOC keys", function()
        local providers = {
            cwv_dr_dawi_mace = master("cwv_variant"),
            cwv_dr_dawi_mace_shield = master("cwv_variant"),
            cwv_dr_dawi_dual_maces = master("cwv_variant"),
            cwv_es_longsword = master("cwv_variant"),
            woc_blightreaper = master("woc_variant"),
        }
        for key, row in pairs(providers) do
            local ok, problems, provider = contract.validate_provider(key, row)
            H.truthy(ok, key .. " rejected: " .. table.concat(problems, ","))
            H.truthy(provider == "cwv" or provider == "woc")
        end
    end)

    H.test("CIM #628 malformed provider rows fail before catalog UI", function()
        local malformed = master("cwv_variant")
        malformed.template = nil
        malformed.inventory_icon = nil
        local cache, report = catalog.build({
            item_master_list = { cwv_dr_dawi_mace = malformed },
            career_name = "dr_ranger",
            craftable_slot_types = { melee = true },
            validate_provider = function(key, row)
                return contract.validate_provider(key, row)
            end,
        })
        H.equal(next(cache), nil)
        H.equal(#report.rejected_providers, 1)
        H.equal(report.rejected_providers[1].key, "cwv_dr_dawi_mace")
        H.deep_equal(report.rejected_providers[1].problems,
            { "template", "inventory_icon" })
    end)

    H.test("CIM #628 canonical rebuild is idempotent", function()
        local row = master("woc_variant")
        local first = assert(contract.normalize_record("owned_1", {
            item_key = "woc_blightreaper",
            properties = { power_vs_chaos = 1 },
            traits = { "melee_attack_speed_on_crit" },
            rarity = "modded",
        }, row))
        local second = assert(contract.normalize_record("owned_1", first, row))
        H.deep_equal(second, first)
        H.equal(second.schema_version, contract.SCHEMA_VERSION)
        H.equal(second.owner, "cim")
        H.equal(second.provider, "woc")
        H.equal(second.slot_type, "melee")

        local args = {
            item_master_list = { woc_blightreaper = row },
            career_name = "dr_ranger",
            craftable_slot_types = { melee = true },
            validate_provider = function(key, candidate)
                return contract.validate_provider(key, candidate)
            end,
        }
        local cache_a, report_a = catalog.build(args)
        local cache_b, report_b = catalog.build(args)
        H.deep_equal(cache_b, cache_a)
        H.deep_equal(report_b, report_a)
    end)

    H.test("CIM #628 mirror payload preserves one exact identity", function()
        local row = master("cwv_variant")
        local record = assert(contract.normalize_record("cwv_dr_dawi_mace_100", {
            item_key = "cwv_dr_dawi_mace",
            properties = { crit_chance = 1 },
            traits = { "melee_attack_speed_on_crit" },
            power_level = 300,
            rarity = "modded",
        }, row))
        local payload, err, normalized = contract.build_mirror_payload(
            record, row, function() return "encoded" end)
        H.equal(err, nil)
        H.equal(payload.ItemId, record.item_key)
        H.equal(payload.ItemInstanceId, record.backend_id)
        H.equal(payload.CustomData.rarity, "modded")
        H.equal(payload.CustomData.properties, "encoded")
        H.equal(payload.CustomData.cim_acquisition_key, record.item_key)
        H.equal(payload.CustomData.cim_provider, "cwv")
        H.equal(payload.CustomData.cwv_key, record.item_key)
        H.equal(normalized.backend_id, record.backend_id)
    end)

    H.test("CIM #628 salvage eligibility preserves every vanilla exclusion", function()
        local row = master("cwv_variant")
        local record = assert(contract.normalize_record("owned_1", {
            item_key = "cwv_dr_dawi_mace",
            rarity = "modded",
        }, row))
        local item = {
            backend_id = "owned_1",
            ItemId = "cwv_dr_dawi_mace",
            rarity = "modded",
            data = row,
        }
        H.truthy(contract.is_salvage_eligible(item, record, {}))
        H.equal(contract.is_salvage_eligible(item, record, { is_equipped = true }), false)
        H.equal(contract.is_salvage_eligible(item, record,
            { is_equipped_by_any_loadout = true }), false)
        H.equal(contract.is_salvage_eligible(item, record, { is_favorite = true }), false)

        for _, rarity in ipairs({ "default", "promo", "magic" }) do
            item.rarity = rarity
            H.equal(contract.is_salvage_eligible(item, record, {}), false,
                rarity .. " must not be salvageable")
        end
        item.rarity = "modded"
        item.backend_id = "different_instance"
        H.equal(contract.is_salvage_eligible(item, record, {}), false)
    end)

    H.test("CIM #628 deletion partitions exact owned instances once", function()
        local owned, foreign = contract.partition_exact_ids(
            { "owned_a", "foreign", "owned_a", "owned_b" },
            { owned_a = {}, owned_b = {} })
        H.deep_equal(owned, { "owned_a", "owned_b" })
        H.deep_equal(foreign, { "foreign" })
    end)

    H.test("CIM #628 exact deletion cleanup clears every owned reference", function()
        local loadouts = {
            dr_ranger = {
                slot_melee = "delete_me",
                slot_ranged = "keep_me",
            },
            es_knight = {
                [1] = { slot_melee = "delete_me" },
                [2] = { slot_melee = "keep_me", slot_ranged = "delete_me" },
            },
        }
        local skins = { delete_me = "skin_delete", keep_me = "skin_keep" }
        H.truthy(cleanup.clear_loadout_refs(loadouts, { "delete_me" }))
        H.truthy(cleanup.clear_map_keys(skins, { "delete_me" }))
        H.equal(loadouts.dr_ranger.slot_melee, nil)
        H.equal(loadouts.dr_ranger.slot_ranged, "keep_me")
        H.equal(loadouts.es_knight[1].slot_melee, nil)
        H.equal(loadouts.es_knight[2].slot_ranged, nil)
        H.equal(loadouts.es_knight[2].slot_melee, "keep_me")
        H.equal(skins.delete_me, nil)
        H.equal(skins.keep_me, "skin_keep")
    end)

    H.test("CIM #628 canonical identity unifies base-keyed CWV rows", function()
        -- Variant encoded only in the backend id (legacy CWV blacksmith shape).
        H.equal(contract.canonical_item_key({
            backend_id = "cwv_es_longsword_100", key = "es_bastard_sword",
        }), "cwv_es_longsword")
        -- The self-identifying data.cwv_key wins over the inherited base key.
        H.equal(contract.canonical_item_key({
            backend_id = "opaque",
            data = { key = "es_bastard_sword", cwv_key = "cwv_es_longsword" },
        }), "cwv_es_longsword")
        -- A synthetic selector's exact craft key wins over everything.
        H.equal(contract.canonical_item_key({
            cim_acquisition_key = "cwv_dr_dawi_dual_maces", key = "dr_dual_hammers",
        }), "cwv_dr_dawi_dual_maces")
        -- A reconstructed UUID mirror may expose only base weapon fields plus
        -- the exact CIM CustomData stamp. This is the #484 Old Musket shape.
        H.equal(contract.canonical_item_key({
            ItemInstanceId = "48400000-0000-4000-8000-000000000484",
            key = "es_handgun",
            data = { key = "es_handgun" },
            CustomData = {
                cim_acquisition_key = "cwv_es_musket_old",
                cwv_key = "cwv_es_musket_old",
            },
        }), "cwv_es_musket_old")
        -- Ordinary vanilla identity is unchanged.
        H.equal(contract.canonical_item_key({
            ItemId = "es_1h_sword", key = "es_1h_sword",
        }), "es_1h_sword")
    end)

    H.test("CIM #628 normalization consumes the canonical identity ladder", function()
        local shapes = {
            {
                bid = "48400000-0000-4000-8000-000000000484",
                input = {
                    key = "es_handgun",
                    CustomData = { cim_acquisition_key = "cwv_es_musket_old" },
                },
                expected = "cwv_es_musket_old",
            },
            {
                bid = "opaque",
                input = {
                    key = "es_bastard_sword",
                    data = { cwv_key = "cwv_es_longsword" },
                },
                expected = "cwv_es_longsword",
            },
            {
                bid = "cwv_dr_dawi_mace_100",
                input = { key = "dr_1h_hammer" },
                expected = "cwv_dr_dawi_mace",
            },
        }
        for i = 1, #shapes do
            local shape = shapes[i]
            H.equal(contract.canonical_item_key(shape.input, shape.bid), shape.expected)
            local record, err = contract.normalize_record(shape.bid, shape.input)
            H.equal(err, nil)
            H.equal(record.item_key, shape.expected)
        end
    end)

    H.test("CIM #628 base-keyed CWV instance stays salvage-eligible", function()
        local row = master("cwv_variant")
        local record = assert(contract.normalize_record("cwv_es_longsword_100", {
            item_key = "cwv_es_longsword",
            rarity = "modded",
        }, row))
        -- The live mirror item presents CWV's inherited BASE key; the variant
        -- survives only in the backend-id band. Before the identity unification
        -- the salvage filter resolved this to "es_bastard_sword" and rejected it
        -- as not-owned, so the crafted weapon never reached the Salvage grid.
        local item = {
            backend_id = "cwv_es_longsword_100",
            key = "es_bastard_sword",
            rarity = "modded",
            data = { slot_type = "melee", key = "es_bastard_sword" },
        }
        H.truthy(contract.is_salvage_eligible(item, record, {}))
        H.equal(contract.is_salvage_eligible(item, record, { is_equipped = true }), false)
        H.equal(contract.is_salvage_eligible(item, record,
            { is_equipped_by_any_loadout = true }), false)
        H.equal(contract.is_salvage_eligible(item, record, { is_favorite = true }), false)
    end)

    H.test("CIM #628 production paths consume the shared contract", function()
        local function read(name)
            local file = assert(io.open(root .. name, "rb"))
            local source = file:read("*a")
            file:close()
            return source
        end
        local entry = read("crafting_in_modded_dev.lua")
        local forge = read("standard_forge.lua")
        local filter = read("_cim_inventory_filter.lua")
        local importer = read("saveweapon_import.lua")
        local selector = read("_cim_template_selector.lua")
        H.truthy(entry:find("contract.build_mirror_payload(normalized", 1, true))
        H.truthy(forge:find("contract.build_mirror_payload(record", 1, true))
        H.truthy(importer:find("contract.build_mirror_payload(record", 1, true))
        H.truthy(forge:find("mod._cim277_delete_owned_ids(owned)", 1, true))
        H.truthy(filter:find("contract.is_salvage_eligible", 1, true))
        H.equal(filter:find("REGARDLESS of equip / loadout / favorite", 1, true), nil)
        -- issue 628 identity unification: the acquisition selector must read the
        -- contract's one canonical resolver, injected at standard_forge load.
        H.truthy(selector:find("function M.set_canonical_key_resolver", 1, true))
        H.truthy(forge:find(
            "template_selector.set_canonical_key_resolver(_contract.canonical_item_key)",
            1, true))
    end)
end
