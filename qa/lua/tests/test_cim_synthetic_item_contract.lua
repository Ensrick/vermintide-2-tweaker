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

    H.test("CIM #628 provider contract accepts CWV and reserves WOC relic keys", function()
        local providers = {
            cwv_dr_dawi_mace = master("cwv_variant"),
            cwv_dr_dawi_mace_shield = master("cwv_variant"),
            cwv_dr_dawi_dual_maces = master("cwv_variant"),
            cwv_es_longsword = master("cwv_variant"),
        }
        for key, row in pairs(providers) do
            local ok, problems, provider = contract.validate_provider(key, row)
            H.truthy(ok, key .. " rejected: " .. table.concat(problems, ","))
            H.equal(provider, "cwv")
        end

		local ok, problems, provider = contract.validate_provider(
			"woc_blightreaper", master("woc_variant"))
		H.equal(ok, false)
		H.equal(provider, "woc")
		H.deep_equal(problems, { "immutable_relic" })
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
        local row = master("cwv_variant")
        local first = assert(contract.normalize_record("owned_1", {
            item_key = "cwv_dr_dawi_mace",
            properties = { power_vs_chaos = 1 },
            traits = { "melee_attack_speed_on_crit" },
            rarity = "modded",
        }, row))
        local second = assert(contract.normalize_record("owned_1", first, row))
        H.deep_equal(second, first)
        H.equal(second.schema_version, contract.SCHEMA_VERSION)
        H.equal(second.owner, "cim")
        H.equal(second.provider, "cwv")
        H.equal(second.slot_type, "melee")

        local args = {
            item_master_list = { cwv_dr_dawi_mace = row },
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

    H.test("CIM #628 salvage trace fingerprints state changes and deduplicates refreshes", function()
        local base = {
            is_equipped = false,
            is_equipped_by_any_loadout = false,
            is_favorite = false,
            backend_dirty = false,
        }
        local a = contract.salvage_trace_fingerprint("owned_1", true, true, nil, base)
        local b = contract.salvage_trace_fingerprint("owned_1", true, true, nil, base)
        H.equal(a, b)
        H.truthy(a:find("owned_1|visible|eligible", 1, true))

        local c = contract.salvage_trace_fingerprint("owned_1", false, false, "loadout", {
            is_equipped_by_any_loadout = true,
        })
        H.truthy(c ~= a, "saved-loadout rejection must emit a new diagnostic state")
        H.truthy(c:find("hidden|rejected|loadout|unequipped|saved", 1, true))
    end)

    H.test("CIM #628 keyed salvage recovery enforces all ownership exclusions", function()
        local row = master("cwv_variant")
        local function record(backend_id, item_key)
            return assert(contract.normalize_record(backend_id, {
                item_key = item_key or "cwv_dr_dawi_mace",
                rarity = "modded",
            }, row))
        end
        local function item(backend_id)
            return {
                backend_id = backend_id,
                ItemId = "cwv_dr_dawi_mace",
                rarity = "modded",
                data = row,
            }
        end

        local keyed = {
            ["uuid-eligible"] = item("uuid-eligible"),
            ["uuid-active-other-career"] = item("uuid-active-other-career"),
            ["uuid-saved-other-career"] = item("uuid-saved-other-career"),
            ["uuid-favorite"] = item("uuid-favorite"),
            ["uuid-query-error"] = item("uuid-query-error"),
            ["woc_blightreaper_001"] = {
                backend_id = "woc_blightreaper_001",
                ItemId = "woc_blightreaper",
                rarity = "modded",
                data = {
                    slot_type = "melee",
                    woc_variant = true,
                    woc_unique_relic = true,
                },
            },
        }
        local records = {
            ["uuid-eligible"] = record("uuid-eligible"),
            ["uuid-active-other-career"] = record("uuid-active-other-career"),
            ["uuid-saved-other-career"] = record("uuid-saved-other-career"),
            ["uuid-favorite"] = record("uuid-favorite"),
            ["uuid-query-error"] = record("uuid-query-error"),
            ["woc_blightreaper_001"] = {
                backend_id = "woc_blightreaper_001",
                item_key = "woc_blightreaper",
                owner = contract.OWNER,
                schema_version = contract.SCHEMA_VERSION,
                rarity = "modded",
                slot_type = "melee",
            },
        }
        local traces = {}
        local result = contract.recover_salvage_items(keyed, {}, {
            get_record = function(backend_id)
                return records[backend_id]
            end,
            get_equipped_careers = function(backend_id)
                if backend_id == "uuid-query-error" then error("unavailable") end
                if backend_id == "uuid-active-other-career" then
                    return { "es_mercenary" }
                end
                return {}
            end,
            get_saved_loadouts = function(backend_id)
                if backend_id == "uuid-saved-other-career" then
                    return { "dr_ranger:loadout_3" }
                end
                return {}
            end,
            is_favorite = function(backend_id)
                return backend_id == "uuid-favorite"
            end,
            trace = function(traced_item, _, _, visible, eligible, reason,
                    careers, loadouts)
                traces[traced_item.backend_id] = {
                    visible = visible,
                    eligible = eligible,
                    reason = reason,
                    careers = careers,
                    loadouts = loadouts,
                }
            end,
        })

        H.equal(#result, 1)
        H.equal(result[1].backend_id, "uuid-eligible")
        H.equal(traces["uuid-active-other-career"].reason, "equipped")
        H.deep_equal(traces["uuid-active-other-career"].careers, { "es_mercenary" })
        H.equal(traces["uuid-saved-other-career"].reason, "loadout")
        H.deep_equal(traces["uuid-saved-other-career"].loadouts,
            { "dr_ranger:loadout_3" })
        H.equal(traces["uuid-favorite"].reason, "favorite")
        H.equal(traces["uuid-query-error"].reason, "equipped")
        H.equal(traces["woc_blightreaper_001"].reason, "immutable_relic")
    end)

    H.test("CIM #628 keyed salvage recovery fails closed and is idempotent", function()
        local row = master("cwv_variant")
        local function record(backend_id)
            return assert(contract.normalize_record(backend_id, {
                item_key = "cwv_dr_dawi_mace",
                rarity = "modded",
            }, row))
        end
        local function instance(backend_id)
            return {
                ItemInstanceId = backend_id,
                ItemId = "cwv_dr_dawi_mace",
                rarity = "modded",
                data = row,
            }
        end
        local function recover(backend_id, access, result)
            access.get_record = function(id)
                return id == backend_id and record(backend_id) or nil
            end
            access.get_equipped_careers = access.get_equipped_careers
                or function() return {} end
            access.get_saved_loadouts = access.get_saved_loadouts
                or function() return {} end
            return contract.recover_salvage_items(
                { arbitrary_string_key = instance(backend_id) },
                result or {}, access)
        end

        local result = recover("saved-throw", {
            get_saved_loadouts = function() error("saved query unavailable") end,
            is_favorite = function() return false end,
        })
        H.equal(#result, 0)

        result = recover("saved-non-table", {
            get_saved_loadouts = function() return "not-a-list" end,
            is_favorite = function() return false end,
        })
        H.equal(#result, 0)

        result = recover("favorite-throw", {
            is_favorite = function() error("favorite query unavailable") end,
        })
        H.equal(#result, 0)

        -- An UNCOERCED non-boolean verdict stays fail-closed at the contract
        -- boundary: coercion is the accessor's job (_cim_inventory_filter.lua
        -- routes through contract.coerce_favorite_verdict; vanilla-shape
        -- cases below lock the runtime path).
        result = recover("favorite-non-boolean", {
            is_favorite = function() return "false" end,
        })
        H.equal(#result, 0)

        result = recover("favorite-helper-missing", {})
        H.equal(#result, 0)

        -- #628 regression: the REAL vanilla helper shape.
        -- ItemHelper.is_favorite_backend_id ends `return favorite_item_ids
        -- and favorite_item_ids[item_id]` (item_helper.lua:453) - NIL for a
        -- non-favorited item, never false. Routed through the same coercion
        -- the runtime accessor uses, the row MUST recover; the pre-fix raw
        -- pass-through rejected every recovered row verdict=favorite.
        local favorite_item_ids = nil   -- no favorites ever recorded
        result = recover("favorite-vanilla-nil", {
            is_favorite = function(backend_id)
                return contract.coerce_favorite_verdict(
                    favorite_item_ids and favorite_item_ids[backend_id])
            end,
        })
        H.equal(#result, 1,
            "vanilla nil (non-favorited) verdict must not reject recovery")

        -- Favorited direction: vanilla stores a truthy marker, not
        -- necessarily boolean true; coercion must still reject the row.
        result = recover("favorite-vanilla-truthy", {
            is_favorite = function(backend_id)
                local ids = { ["favorite-vanilla-truthy"] = 1 }
                return contract.coerce_favorite_verdict(ids[backend_id])
            end,
        })
        H.equal(#result, 0,
            "coerced truthy favorite verdict must stay salvage-ineligible")

        H.equal(contract.coerce_favorite_verdict(nil), false)
        H.equal(contract.coerce_favorite_verdict(false), false)
        H.equal(contract.coerce_favorite_verdict(true), true)
        H.equal(contract.coerce_favorite_verdict(1), true)

        result = recover("item-instance-id-appended", {
            is_favorite = function() return false end,
        })
        H.equal(#result, 1,
            "ItemInstanceId-only keyed-map values must be recovered")
        H.equal(result[1].ItemInstanceId, "item-instance-id-appended")
        result = recover("item-instance-id-appended", {
            is_favorite = function() return false end,
        }, result)
        H.equal(#result, 1,
            "recovery must be idempotent across repeated UI refreshes")

        local existing = instance("item-instance-id-preexisting")
        result = recover("item-instance-id-preexisting", {
            is_favorite = function() return false end,
        }, { existing })
        H.equal(#result, 1,
            "ItemInstanceId-only rows must dedupe against vanilla's result")
        H.equal(result[1], existing)
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

    H.test("CIM #524 picker role separates selectors from exact instances", function()
        H.equal(contract.craft_picker_role({
            rarity = "default",
            data = { slot_type = "melee", cwv_key = "cwv_es_longsword" },
        }), "selector")
        H.equal(contract.craft_picker_role({
            rarity = "modded",
            data = { slot_type = "melee", cwv_key = "cwv_es_longsword" },
        }), "instance")
        H.equal(contract.craft_picker_role({
            CustomData = { rarity = "modded" },
            data = { slot_type = "necklace" },
        }), "instance")
        H.equal(contract.craft_picker_role({
            rarity = "unique", data = { slot_type = "hat" },
        }), "other")
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
        local contract_source = read("_cim_synthetic_item_contract.lua")
        H.truthy(entry:find("contract.build_mirror_payload(normalized", 1, true))
        H.truthy(forge:find("contract.build_mirror_payload(record", 1, true))
        H.truthy(importer:find("contract.build_mirror_payload(record", 1, true))
        H.truthy(forge:find(
            "delete_owned_ids = mod._cim277_delete_owned_ids", 1, true))
        H.truthy(filter:find("contract.recover_salvage_items", 1, true))
        H.truthy(contract_source:find("for _, item in pairs(items) do", 1, true),
            "canonical salvage adapter must enumerate the backend-id keyed map")
        H.equal(contract_source:find("for _, item in ipairs(items) do", 1, true), nil,
            "canonical salvage adapter must not treat the backend map as an array")
        H.truthy(filter:find("[cim:628] salvage_state", 1, true),
            "exact salvage rejection diagnostic is not wired")
        H.equal(filter:find("REGARDLESS of equip / loadout / favorite", 1, true), nil)
        -- issues 524/628 identity unification: the acquisition selector must
        -- consume both exact identity and picker-row role from one contract.
        H.truthy(selector:find("function M.set_identity_contract", 1, true))
        H.truthy(forge:find("template_selector.set_identity_contract(_contract)", 1, true))
    end)
end
