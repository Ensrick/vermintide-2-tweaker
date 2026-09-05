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

    H.test("CIM #1141 Temper-Craft accepts only provider-proven CWV seeds", function()
        local cwv = dofile(repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_acquisition.lua")
        local key = "cwv_es_dual_swords"
        local donor_key = "we_dual_wield_swords"
        local row = master("cwv_variant")
        row.cwv_key = key
        row.cwv_definition = true
        row.key = donor_key
        row.name = donor_key
        local item_master_list = { [key] = row }
        local ledger = {}
        local live
        local function seed(backend_id)
            local entry = {
                key = donor_key, name = donor_key, cwv_variant = true,
                cwv_definition = false, cwv_key = key,
                rarity = "default",
                mod_data = {
                    backend_id = backend_id, ItemInstanceId = backend_id,
                    rarity = "default", power_level = 5,
                    traits = {}, properties = {},
                    CustomData = { rarity = "default", power_level = "5",
                        traits = "[]", properties = "{}" },
                },
            }
            live = {
                IsModItem = true, CreatedBy = "character_weapon_variants",
                backend_id = backend_id, ItemInstanceId = backend_id,
                key = donor_key, ItemId = donor_key,
                rarity = "default", power_level = 5,
                traits = {}, properties = {},
                CustomData = { rarity = "default", power_level = "5",
                    traits = "[]", properties = "{}" },
                data = entry,
            }
            ledger = { [backend_id] = assert(cwv.protect_seed_identity(
                backend_id, key, entry, row)) }
        end
        local provider = cwv.new_seed_identity_provider({
            registered_keys = { [key] = row },
            get_protected_seed_ids = function() return ledger end,
            get_item_master_list = function() return item_master_list end,
            get_backend_item = function() return live end,
        })

        for _, suffix in ipairs({ "000", "001" }) do
            local backend_id = key .. "_" .. suffix
            seed(backend_id)
            local source, reason = contract.resolve_temper_craft_source(
                { data = { key = donor_key } }, live,
                backend_id, provider)
            H.equal(reason, nil)
            H.equal(source.item_key, key)
            H.equal(source.proof.backend_id, backend_id)

            -- BackendInterfaceItemPlayfab recursively clones the raw mirror
            -- row for UI presentation.  The provider must authenticate its
            -- private raw source while the consumer accepts an equivalent,
            -- independently allocated projection.
            local function clone(value)
                if type(value) ~= "table" then return value end
                local result = {}
                for child_key, child in pairs(value) do
                    result[child_key] = clone(child)
                end
                return result
            end
            local projected = clone(live)
            H.truthy(projected ~= live and projected.data ~= live.data)
            source, reason = contract.resolve_temper_craft_source(
                projected, projected, backend_id, provider)
            H.equal(reason, nil)
            H.equal(source.item_key, key)
            H.equal(source.proof.backend_id, backend_id)

            local matching = {
                key = "we_dual_wield_swords",
                cwv_key = key,
                backend_id = backend_id,
                data = { key = donor_key },
            }
            source = contract.resolve_temper_craft_source(
                matching, live, backend_id, provider)
            H.equal(source.item_key, key)

            local method_provider = {
                schema = provider.schema,
                owner = provider.owner,
                capability = provider.capability,
            }
            method_provider.resolve = function(self, id)
                H.equal(self, method_provider)
                return provider:resolve(id)
            end
            source = contract.resolve_temper_craft_source(
                matching, live, backend_id, method_provider)
            H.equal(source.item_key, key)
        end

        local backend_id = key .. "_001"
        seed(backend_id)
        local conflicting = {
            key = donor_key,
            cwv_key = "cwv_es_longsword",
            data = { key = donor_key },
        }
        local resolved, reason = contract.resolve_temper_craft_source(
            conflicting, live, backend_id, provider)
        H.equal(resolved, nil)
        H.equal(reason, "cwv_source_stamp_conflict")

        for _, backend_id in ipairs({
            key .. "_002", key .. "_100", key .. "_999", "foreign_001",
        }) do
            resolved, reason = contract.resolve_temper_craft_source({
                cwv_key = key,
                key = "we_dual_wield_swords",
                data = row,
            }, live, backend_id, provider)
            H.equal(resolved, nil)
            H.truthy(reason:find("cwv_provider:", 1, true))
        end

        resolved, reason = contract.resolve_temper_craft_source(
            live, live, key .. "_001", nil)
        H.equal(resolved, nil)
        H.equal(reason, "cwv_provider_unavailable")
        local throwing = {
            schema = contract.CWV_SEED_IDENTITY_SCHEMA,
            owner = contract.CWV_SEED_IDENTITY_OWNER,
            capability = contract.CWV_SEED_IDENTITY_CAPABILITY,
            resolve = function() error("provider failure") end,
        }
        resolved, reason = contract.resolve_temper_craft_source(
            live, live, key .. "_001", throwing)
        H.equal(resolved, nil)
        H.equal(reason, "cwv_provider_exception")

        seed(key .. "_001")
        local hidden = {
            backend_id = key .. "_001", key = donor_key, cwv_key = key,
            data = { key = donor_key,
                CustomData = { cwv_key = "cwv_es_longsword" } },
        }
        resolved, reason = contract.resolve_temper_craft_source(
            hidden, live, key .. "_001", provider)
        H.equal(resolved, nil)
        H.equal(reason, "cwv_source_stamp_conflict")
        hidden.data.CustomData.cwv_key = false
        resolved, reason = contract.resolve_temper_craft_source(
            hidden, live, key .. "_001", provider)
        H.equal(resolved, nil)
        H.equal(reason, "cwv_selected_semantic_stamp_conflict")

        local mixed_donor = {
            backend_id = key .. "_001",
            key = "bw_1h_sword",
            cwv_key = key,
        }
        resolved, reason = contract.resolve_temper_craft_source(
            mixed_donor, live, key .. "_001", provider)
        H.equal(resolved, nil)
        H.equal(reason, "cwv_selected_semantic_key_conflict")

        resolved, reason = contract.resolve_temper_craft_source(
            hidden, nil, key .. "_001", provider)
        H.equal(resolved, nil)
        H.equal(reason, "cwv_live_item_unavailable")
    end)

    H.test("CIM #1141 Temper source leaves non-CWV providers unchanged", function()
        local cases = {
            { bid = "vanilla-bid", item = { key = "es_1h_sword" },
              expected = "es_1h_sword" },
            { bid = "pusfume-bid", item = { ItemId = "pusfume_claw" },
              expected = "pusfume_claw" },
            { bid = "external-bid", item = { item_key = "community_halberd" },
              expected = "community_halberd" },
            { bid = "donor-only", item = { key = "we_dual_wield_swords" },
              expected = "we_dual_wield_swords" },
        }
        for _, case in ipairs(cases) do
            local resolved, reason = contract.resolve_temper_craft_source(
                case.item, case.item, case.bid, nil)
            H.equal(reason, nil)
            H.equal(resolved.item_key, case.expected)
        end
        local woc, woc_reason = contract.resolve_temper_craft_source(
            { key = "woc_blightreaper" }, { key = "woc_blightreaper" },
            "woc-bid", nil)
        H.equal(woc, nil)
        H.equal(woc_reason, "immutable_relic")

        local tampered = {
            schema = contract.CWV_SEED_IDENTITY_SCHEMA,
            owner = contract.CWV_SEED_IDENTITY_OWNER,
            capability = contract.CWV_SEED_IDENTITY_CAPABILITY,
            resolve = function(_, backend_id)
                return {
                    schema = contract.CWV_SEED_IDENTITY_SCHEMA,
                    owner = contract.CWV_SEED_IDENTITY_OWNER,
                    capability = contract.CWV_SEED_IDENTITY_CAPABILITY,
                    backend_id = backend_id,
                    item_key = "cwv_es_dual_swords",
                    fingerprint = "forged",
                }, nil
            end,
        }
        local resolved, reason = contract.resolve_temper_craft_source({
            cwv_key = "cwv_es_dual_swords",
        }, { cwv_key = "cwv_es_dual_swords" },
            "cwv_es_dual_swords_001", tampered)
        H.equal(resolved, nil)
        H.equal(reason, "cwv_provider_proof_mismatch")
    end)

    H.test("CIM #1141 mirror ownership contains partial writes and exact rollback", function()
        local master_ref = {}
        local function payload(backend_id, item_key)
            return {
                ItemId = item_key,
                ItemInstanceId = backend_id,
                CustomData = {
                    cim_acquisition_key = item_key,
                    cim_provider = "cwv",
                    cwv_key = item_key,
                    rarity = "modded",
                    power_level = "300",
                    traits = "[]",
                    properties = "{}",
                },
            }
        end
        local function record(backend_id, item_key)
            return {
                backend_id = backend_id,
                item_key = item_key,
                rarity = "modded",
                power_level = 300,
                traits = {},
                properties = {},
                provider = "cwv",
                _mirror_master = master_ref,
            }
        end
        local function hydrate(item, backend_id)
            item.backend_id, item.key, item.data = backend_id, item.ItemId,
                master_ref
            item.rarity, item.power_level = "modded", 300
            item.traits, item.properties = {}, {}
        end
        local mirror = { _inventory_items = {} }
        function mirror:add_item(backend_id, item)
            self._inventory_items[backend_id] = item
            hydrate(item, backend_id)
        end
        function mirror:remove_item(backend_id)
            self._inventory_items[backend_id] = nil
        end

        local backend_id, item_key = "new-guid", "cwv_es_dual_swords"
        local added, reason, token, _, rollback = contract.inject_mirror_item(
            mirror, backend_id, payload(backend_id, item_key),
            function() return "nonce-one" end, record(backend_id, item_key))
        H.equal(reason, nil)
        H.truthy(added)
        H.truthy(contract.validate_mirror_ownership_token(
            token, backend_id, item_key))
        H.truthy(rollback())
        H.equal(mirror._inventory_items[backend_id], nil)

        local owned_payload = payload(backend_id, item_key)
        added, reason, token, _, rollback = contract.inject_mirror_item(
            mirror, backend_id, owned_payload,
            function() return "nonce-replacement" end,
            record(backend_id, item_key))
        H.truthy(added)
        local replacement = payload(backend_id, item_key)
        replacement.CustomData.cim_injection_owner = "cim"
        replacement.CustomData.cim_injection_schema = tostring(
            contract.MIRROR_OWNERSHIP_SCHEMA)
        replacement.CustomData.cim_injection_nonce = "nonce-replacement"
        hydrate(replacement, backend_id)
        mirror._inventory_items[backend_id] = replacement
        local replacement_removed, replacement_reason = rollback()
        H.equal(replacement_removed, false)
        H.equal(replacement_reason, "mirror_identity_mismatch")
        H.equal(mirror._inventory_items[backend_id], replacement)

        mirror._inventory_items[backend_id] = {
            ItemId = "foreign_item", ItemInstanceId = backend_id,
        }
        added, reason = contract.inject_mirror_item(
            mirror, backend_id, payload(backend_id, item_key),
            function() return "nonce-two" end, record(backend_id, item_key))
        H.equal(added, nil)
        H.equal(reason, "backend_id_exists")
        local forged_token = {
            schema = contract.MIRROR_OWNERSHIP_SCHEMA,
            owner = contract.OWNER,
            capability = contract.MIRROR_OWNERSHIP_CAPABILITY,
            backend_id = backend_id,
            item_key = item_key,
            nonce = "forged-nonce",
            payload = mirror._inventory_items[backend_id],
            fingerprint = "cim-mirror-item-v2|" .. backend_id .. "|"
                .. item_key .. "|forged-nonce",
        }
        local removed, remove_reason = contract.rollback_mirror_item(
            mirror, backend_id, forged_token)
        H.equal(removed, false)
        H.equal(remove_reason, "ownership_token")
        H.equal(mirror._inventory_items[backend_id].ItemId, "foreign_item")

        mirror._inventory_items[backend_id] = nil
        function mirror:add_item(id, item)
            self._inventory_items[id] = item
            hydrate(item, id)
            error("post-store callback failed")
        end
        local cleaned
        added, reason, token, cleaned = contract.inject_mirror_item(
            mirror, backend_id, payload(backend_id, item_key),
            function() return "nonce-three" end, record(backend_id, item_key))
        H.equal(added, nil)
        H.truthy(reason:find("post-store callback failed", 1, true))
        H.equal(token, nil)
        H.equal(cleaned, true)
        H.equal(mirror._inventory_items[backend_id], nil)

        -- A normal return is not evidence that the native remover performed
        -- its side effect.  Failed injection cleanup must still raw-delete the
        -- exact object CIM just issued.
        function mirror:remove_item() end
        function mirror:add_item(id, item)
            self._inventory_items[id] = item
            hydrate(item, id)
            error("add failed after no-op remover store")
        end
        added, reason, token, cleaned = contract.inject_mirror_item(
            mirror, backend_id, payload(backend_id, item_key),
            function() return "nonce-noop-cleanup" end,
            record(backend_id, item_key))
        H.equal(added, nil)
        H.truthy(reason:find("no-op remover", 1, true))
        H.equal(token, nil)
        H.equal(cleaned, true)
        H.equal(mirror._inventory_items[backend_id], nil)

        -- The same postcondition applies to a later explicit rollback.
        function mirror:add_item(id, item)
            self._inventory_items[id] = item
            hydrate(item, id)
        end
        added, reason, token, _, rollback = contract.inject_mirror_item(
            mirror, backend_id, payload(backend_id, item_key),
            function() return "nonce-noop-rollback" end,
            record(backend_id, item_key))
        H.truthy(added)
        H.equal(reason, nil)
        H.truthy(rollback())
        H.equal(mirror._inventory_items[backend_id], nil)

        -- An engine add callback may store the exact row, then throw, while
        -- its paired remove callback also throws before deletion.  Exact
        -- object identity remains sufficient to contain only our own write.
        function mirror:remove_item()
            error("remove failed before delete")
        end
        function mirror:add_item(id, item)
            self._inventory_items[id] = item
            hydrate(item, id)
            error("add failed after store")
        end
        added, reason, token, cleaned = contract.inject_mirror_item(
            mirror, backend_id, payload(backend_id, item_key),
            function() return "nonce-double-throw" end,
            record(backend_id, item_key))
        H.equal(added, nil)
        H.truthy(reason:find("add failed after store", 1, true))
        H.equal(token, nil)
        H.equal(cleaned, true)
        H.equal(mirror._inventory_items[backend_id], nil)

        -- A delete-then-throw callback is successful containment because the
        -- exact owned row is already absent at the postcondition boundary.
        function mirror:add_item(id, item)
            self._inventory_items[id] = item
            hydrate(item, id)
        end
        function mirror:remove_item(id)
            self._inventory_items[id] = nil
            error("remove failed after delete")
        end
        added, reason, token, _, rollback = contract.inject_mirror_item(
            mirror, backend_id, payload(backend_id, item_key),
            function() return "nonce-delete-throw" end,
            record(backend_id, item_key))
        H.truthy(added)
        local removed_after_throw, delete_throw_reason = rollback()
        H.equal(removed_after_throw, true)
        H.equal(delete_throw_reason, nil)
        H.equal(mirror._inventory_items[backend_id], nil)

        function mirror:add_item(id, item)
            self._inventory_items[id] = item
            hydrate(item, id)
            item.CustomData.cim_injection_nonce = nil
            error("marker stripped after store")
        end
        added, reason, token, cleaned = contract.inject_mirror_item(
            mirror, backend_id, payload(backend_id, item_key),
            function() return "nonce-stripped" end,
            record(backend_id, item_key))
        H.equal(added, nil)
        H.truthy(reason:find("marker stripped after store", 1, true))
        H.equal(cleaned, true)
        H.equal(mirror._inventory_items[backend_id], nil)

        function mirror:add_item(id, item)
            self._inventory_items[id] = item
        end
        added, reason, token, cleaned = contract.inject_mirror_item(
            mirror, backend_id, payload(backend_id, item_key),
            function() return "nonce-unhydrated" end,
            record(backend_id, item_key))
        H.equal(added, nil)
        H.truthy(reason:find("mirror_postcondition", 1, true))
        H.equal(cleaned, true)
        H.equal(mirror._inventory_items[backend_id], nil)

        function mirror:add_item(id, item)
            self._inventory_items[id] = item
            hydrate(item, id)
            item.data = {}
        end
        added, reason, token, cleaned = contract.inject_mirror_item(
            mirror, backend_id, payload(backend_id, item_key),
            function() return "nonce-wrong-master" end,
            record(backend_id, item_key))
        H.equal(added, nil)
        H.truthy(reason:find("mirror_postcondition", 1, true))
        H.equal(cleaned, true)
        H.equal(mirror._inventory_items[backend_id], nil)

        function mirror:add_item(id, item)
            self._inventory_items[id] = {
                ItemId = item.ItemId, ItemInstanceId = id,
                CustomData = {
                    cim_acquisition_key = item.ItemId,
                    cim_injection_owner = "cim",
                    cim_injection_schema = tostring(
                        contract.MIRROR_OWNERSHIP_SCHEMA),
                    cim_injection_nonce = "foreign-nonce",
                },
            }
        end
        added, reason, token, cleaned = contract.inject_mirror_item(
            mirror, backend_id, payload(backend_id, item_key),
            function() return "nonce-four" end, record(backend_id, item_key))
        H.equal(added, nil)
        H.truthy(reason:find("mirror_postcondition", 1, true))
        H.equal(cleaned, false)
        H.equal(mirror._inventory_items[backend_id].CustomData.cim_injection_nonce,
            "foreign-nonce")

        mirror._inventory_items[backend_id] = nil
        function mirror:add_item(id, item)
            self._inventory_items[id] = item
            hydrate(item, id)
            item.data = { CustomData = { cim_acquisition_key = "foreign" } }
        end
        added, reason, token, cleaned = contract.inject_mirror_item(
            mirror, backend_id, payload(backend_id, item_key),
            function() return "nonce-five" end, record(backend_id, item_key))
        H.equal(added, nil)
        H.truthy(reason:find("mirror_postcondition", 1, true))
        H.equal(cleaned, true)
        H.equal(mirror._inventory_items[backend_id], nil)
    end)

    H.test("CIM #1141 failed mirror adds contain row and cache as one transaction", function()
        local backend_id, item_key = "failed-add-guid", "cwv_es_dual_swords"
        local master_ref = master("cwv_variant")
        master_ref.cwv_key = item_key
        local normalized = assert(contract.normalize_record(backend_id, {
            item_key = item_key, rarity = "modded", power_level = 300,
            traits = {}, properties = {}, via_mirror = true,
        }, master_ref))
        local nonce_index = 0
        local function build_payload()
            local payload, payload_error, mirror_record =
                contract.build_mirror_payload(normalized, master_ref,
                    function() return "{}" end)
            H.equal(payload_error, nil)
            return payload, mirror_record
        end
        local function nonce()
            nonce_index = nonce_index + 1
            return "failed-add-nonce-" .. nonce_index
        end
        local function hydrate(item)
            item.backend_id, item.key, item.data = backend_id, item.ItemId,
                master_ref
            item.rarity, item.power_level = "modded", 300
            item.traits, item.properties = {}, {}
        end

        local function run(add_item, refresh)
            local mirror = { _inventory_items = {}, add_item = add_item }
            function mirror:remove_item(id) self._inventory_items[id] = nil end
            local payload, mirror_record = build_payload()
            local added, reason = contract.inject_and_refresh_mirror_item(
                mirror, backend_id, payload, nonce, mirror_record, refresh)
            return added, reason, mirror
        end

        local refreshes = 0
        local added, reason, mirror = run(function(self, id, item)
            self._inventory_items[id] = item
            hydrate(item)
            error("stored then threw")
        end, function()
            refreshes = refreshes + 1
            return true
        end)
        H.equal(added, nil)
        H.truthy(reason:find("stored then threw", 1, true))
        H.equal(refreshes, 1)
        H.equal(mirror._inventory_items[backend_id], nil)

        refreshes = 0
        added, reason, mirror = run(function(self, id, item)
            self._inventory_items[id] = item
            hydrate(item)
            error("stored before rejected refresh")
        end, function()
            refreshes = refreshes + 1
            return false, "cache rejected"
        end)
        H.equal(added, nil)
        H.truthy(reason:find(
            "post-cleanup-refresh=failed:cache rejected", 1, true))
        H.equal(refreshes, 1)
        H.equal(mirror._inventory_items[backend_id], nil)

        refreshes = 0
        added, reason, mirror = run(function(self, id, item)
            self._inventory_items[id] = item
            hydrate(item)
            error("stored before throwing refresh")
        end, function()
            refreshes = refreshes + 1
            error("cache exploded")
        end)
        H.equal(added, nil)
        H.truthy(reason:find(
            "post-cleanup-refresh=failed:", 1, true))
        H.truthy(reason:find("cache exploded", 1, true))
        H.equal(refreshes, 1)
        H.equal(mirror._inventory_items[backend_id], nil)

        refreshes = 0
        added, reason, mirror = run(function()
            error("threw before store")
        end, function()
            refreshes = refreshes + 1
            return true
        end)
        H.equal(added, nil)
        H.truthy(reason:find("threw before store", 1, true))
        H.equal(refreshes, 1)
        H.equal(mirror._inventory_items[backend_id], nil)

        local replacement = { owner = "foreign" }
        refreshes = 0
        added, reason, mirror = run(function(self, id)
            self._inventory_items[id] = replacement
            error("foreign replacement won")
        end, function()
            refreshes = refreshes + 1
            return true
        end)
        H.equal(added, nil)
        H.truthy(reason:find("cleanup=failed", 1, true))
        H.equal(refreshes, 0)
        H.equal(mirror._inventory_items[backend_id], replacement)
    end)

    H.test("CIM #1141 owned Temper rows require exact persisted and injection identity", function()
        local backend_id, item_key = "owned-cwv", "cwv_dr_dawi_mace"
        local row = master("cwv_variant")
        row.cwv_key = item_key
        local input = {
            item_key = item_key,
            rarity = "modded",
            power_level = 300,
            traits = {},
            properties = {},
            via_mirror = true,
        }
        local normalized = assert(contract.normalize_record(
            backend_id, input, row))
        local payload, payload_error, mirror_record =
            contract.build_mirror_payload(normalized, row,
                function() return "{}" end)
        H.equal(payload_error, nil)
        local mirror = { _inventory_items = {} }
        function mirror:add_item(id, item)
            self._inventory_items[id] = item
            item.backend_id, item.key, item.data = id, item.ItemId, row
            item.rarity, item.power_level = "modded", 300
            item.traits, item.properties = {}, {}
        end
        function mirror:remove_item(id) self._inventory_items[id] = nil end
        local added = contract.inject_mirror_item(mirror, backend_id, payload,
            function() return "owned-temper-nonce" end, mirror_record)
        H.truthy(added)
        local live = mirror._inventory_items[backend_id]
        local valid, reason = contract.validate_temper_owned_instance(
            live, backend_id, normalized, row)
        H.equal(valid, true)
        H.equal(reason, nil)

        local saved_nonce = live.CustomData.cim_injection_nonce
        live.CustomData.cim_injection_nonce = nil
        valid, reason = contract.validate_temper_owned_instance(
            live, backend_id, normalized, row)
        H.equal(valid, false)
        H.equal(reason, "owned_injection_proof")
        live.CustomData.cim_injection_nonce = saved_nonce

        live.data.CustomData = { cwv_key = "cwv_es_longsword" }
        valid, reason = contract.validate_temper_owned_instance(
            live, backend_id, normalized, row)
        H.equal(valid, false)
        H.equal(reason, "owned_semantic_stamp")
        live.data.CustomData = nil

        local foreign_record = {}
        for key, value in pairs(normalized) do foreign_record[key] = value end
        foreign_record.owner = "foreign"
        valid, reason = contract.validate_temper_owned_instance(
            live, backend_id, foreign_record, row)
        H.equal(valid, false)
        H.equal(reason, "owned_schema")

        -- Copied CIM stamps cannot turn a differently hydrated native item
        -- into the persisted instance.
        local saved_item_id, saved_key, saved_data = live.ItemId, live.key,
            live.data
        live.ItemId = "cwv_es_longsword"
        valid, reason = contract.validate_temper_owned_instance(
            live, backend_id, normalized, row)
        H.equal(valid, false)
        H.equal(reason, "owned_native_identity")
        live.ItemId = saved_item_id
        live.key = "cwv_es_longsword"
        valid, reason = contract.validate_temper_owned_instance(
            live, backend_id, normalized, row)
        H.equal(valid, false)
        H.equal(reason, "owned_native_identity")
        live.key = saved_key
        live.data = master("cwv_variant")
        valid, reason = contract.validate_temper_owned_instance(
            live, backend_id, normalized, row)
        H.equal(valid, false)
        H.equal(reason, "owned_master_identity")
        live.data = saved_data

    end)

    H.test("CIM #1141 legacy MIL Apply authenticates the real builder/backend shape", function()
        local function deep_clone(value, seen)
            if type(value) ~= "table" then return value end
            seen = seen or {}
            if seen[value] then return seen[value] end
            local copy = {}
            seen[value] = copy
            for key, child in pairs(value) do
                copy[deep_clone(key, seen)] = deep_clone(child, seen)
            end
            return copy
        end
        local saved = {
            get_mod = rawget(_G, "get_mod"),
            ItemMasterList = rawget(_G, "ItemMasterList"),
            WeaponSkins = rawget(_G, "WeaponSkins"),
            printf = rawget(_G, "printf"),
            clone = table.clone,
        }
        local backend_id, item_key = "legacy-cwv", "cwv_dr_dawi_mace"
        local registered = master("cwv_variant")
        registered.key, registered.name = "dr_1h_hammer", "dr_1h_hammer"
        registered.cwv_key = item_key
        registered.can_wield = { "dr_ranger", "dr_slayer" }
        local fake_mod = {
            _cim_synthetic_item_contract = contract,
            echo = function() end,
        }
        local ok, failure = pcall(function()
            rawset(_G, "get_mod", function() return fake_mod end)
            rawset(_G, "ItemMasterList", { [item_key] = registered })
            rawset(_G, "WeaponSkins", { skins = {} })
            rawset(_G, "printf", function() end)
            table.clone = function(value) return deep_clone(value) end
            local build = assert(loadfile(root .. "_cim_mil_entry_builder.lua"))()
            local entry = assert(build({
                item_key = item_key,
                rarity = "modded",
                power_level = 300,
                traits = {},
                properties = {},
                via_mirror = false,
            }, backend_id))

            -- Exact production algorithm from MoreItemsLibrary.lua:317-351.
            local backend = { CustomData = {} }
            local mod_data = entry.mod_data or {}
            for key in pairs(backend) do
                if mod_data[key] then backend[key] = mod_data[key] end
            end
            backend.IsModItem = true
            backend.CreatedBy = "crafting_in_modded_dev"
            backend.backend_id = mod_data.backend_id
            backend.ItemInstanceId = mod_data.ItemInstanceId
            backend.ItemId = mod_data.ItemId or entry.key or entry.name
            backend.key = mod_data.key or entry.key or entry.name
            backend.data = entry
            backend.CustomData.rarity = "modded"
            backend.rarity = "modded"

            local record = assert(contract.normalize_record(backend_id, {
                item_key = item_key,
                rarity = "modded",
                via_mirror = false,
            }, registered))
            local presented = deep_clone(backend)
            local valid, reason = contract.validate_temper_owned_instance(
                presented, backend_id, record, registered, backend)
            H.equal(valid, true)
            H.equal(reason, nil)
            H.equal(backend.ItemId, registered.key)
            H.equal(backend.key, registered.key)
            H.equal(backend.data == registered, false)

            -- WT legitimately edits this mutable compatibility field in place.
            registered.can_wield = { "dr_slayer", "dr_ranger", "dr_ironbreaker" }
            valid, reason = contract.validate_temper_owned_instance(
                presented, backend_id, record, registered, backend)
            H.equal(valid, true)
            H.equal(reason, nil)

            local replacement_master = deep_clone(registered)
            valid, reason = contract.validate_temper_owned_instance(
                presented, backend_id, record, replacement_master, backend)
            H.equal(valid, false)
            H.equal(reason, "owned_legacy_issuance")

            local copied = deep_clone(backend)
            valid, reason = contract.validate_temper_owned_instance(
                copied, backend_id, record, registered, copied)
            H.equal(valid, false)
            H.equal(reason, "owned_legacy_issuance")

            local saved_key = backend.key
            backend.key = item_key
            valid, reason = contract.validate_temper_owned_instance(
                backend, backend_id, record, registered, backend)
            H.equal(valid, false)
            H.equal(reason, "owned_native_identity")
            backend.key = saved_key

            local saved_cwv_key = entry.cwv_key
            entry.cwv_key = "cwv_foreign"
            valid, reason = contract.validate_temper_owned_instance(
                backend, backend_id, record, registered, backend)
            H.equal(valid, false)
            H.equal(reason, "owned_semantic_stamp")
            entry.cwv_key = saved_cwv_key
        end)
        rawset(_G, "get_mod", saved.get_mod)
        rawset(_G, "ItemMasterList", saved.ItemMasterList)
        rawset(_G, "WeaponSkins", saved.WeaponSkins)
        rawset(_G, "printf", saved.printf)
        table.clone = saved.clone
        if not ok then error(failure) end
    end)

    H.test("CIM #1141 failed post-add refresh clears raw row and partial UI cache", function()
        local backend_id, item_key = "refresh-guid", "cwv_es_dual_swords"
        local master_ref = master("cwv_variant")
        master_ref.cwv_key = item_key
        local normalized = assert(contract.normalize_record(backend_id, {
            item_key = item_key, rarity = "modded", power_level = 300,
            traits = {}, properties = {}, via_mirror = true,
        }, master_ref))
        local payload, _, mirror_record = contract.build_mirror_payload(
            normalized, master_ref, function() return "{}" end)
        local mirror = { _inventory_items = {} }
        function mirror:add_item(id, item)
            self._inventory_items[id] = item
            item.backend_id, item.key, item.data = id, item.ItemId, master_ref
            item.rarity, item.power_level = "modded", 300
            item.traits, item.properties = {}, {}
        end
        function mirror:remove_item(id) self._inventory_items[id] = nil end
        local added, _, _, _, rollback = contract.inject_mirror_item(
            mirror, backend_id, payload,
            function() return "refresh-nonce" end, mirror_record)
        H.truthy(added)

        local cache, calls = {}, 0
        local completed, reason = contract.complete_mirror_injection_refresh(
            function()
                calls = calls + 1
                cache[backend_id] = mirror._inventory_items[backend_id]
                if calls == 1 then error("partial cache rebuild") end
                return true
            end,
            rollback)
        H.equal(completed, nil)
        H.truthy(reason:find("partial cache rebuild", 1, true))
        H.truthy(reason:find("rollback=complete", 1, true))
        H.truthy(reason:find("post-cleanup-refresh=complete", 1, true))
        H.equal(calls, 2)
        H.equal(mirror._inventory_items[backend_id], nil)
        H.equal(cache[backend_id], nil)

        payload, _, mirror_record = contract.build_mirror_payload(
            normalized, master_ref, function() return "{}" end)
        added, _, _, _, rollback = contract.inject_mirror_item(
            mirror, backend_id, payload,
            function() return "refresh-reject-nonce" end, mirror_record)
        H.truthy(added)
        calls = 0
        completed, reason = contract.complete_mirror_injection_refresh(
            function()
                calls = calls + 1
                if calls == 1 then return false, "explicit rejection" end
                return true
            end,
            rollback)
        H.equal(completed, nil)
        H.truthy(reason:find("explicit rejection", 1, true))
        H.truthy(reason:find("post-cleanup-refresh=complete", 1, true))
        H.equal(mirror._inventory_items[backend_id], nil)
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
        H.truthy(forge:find("_direct_craft_owner.commit(", 1, true))
        H.truthy(importer:find("_direct_craft_owner.commit(", 1, true))
        H.equal(forge:find("self._backend_mirror.add_item", 1, true), nil)
        H.equal(importer:find("mirror:remove_item", 1, true), nil)
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
