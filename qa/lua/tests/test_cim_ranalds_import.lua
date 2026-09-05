return function(H, repo_root)
    local root = repo_root .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local catalog = assert(loadfile(root .. "_cim_ranalds_catalog.lua"))()
    local importer_module = assert(loadfile(root .. "_cim_ranalds_import.lua"))()
    local synthetic_contract = assert(loadfile(
        root .. "_cim_synthetic_item_contract.lua"))()

    local function fixture(options)
        options = options or {}
        local inventory = {
            old_melee = { data = { key = "es_1h_sword", slot_type = "melee" }, key = "es_1h_sword" },
            old_ranged = { data = { key = "es_handgun", slot_type = "ranged" }, key = "es_handgun" },
            old_necklace = { data = { key = "necklace_base", slot_type = "necklace" }, key = "necklace_base" },
            old_ring = { data = { key = "ring_base", slot_type = "ring" }, key = "ring_base" },
            old_trinket = { data = { key = "trinket_base", slot_type = "trinket" }, key = "trinket_base" },
        }
        local previous = { slot_melee = "old_melee", slot_ranged = "old_ranged",
            slot_necklace = "old_necklace", slot_ring = "old_ring", slot_trinket_1 = "old_trinket" }
        local equipped = {}; for key, value in pairs(previous) do equipped[key] = value end
        local masters = {
            es_1h_sword = { slot_type = "melee", can_wield = { "es_mercenary" },
                property_table_name = "melee", trait_table_name = "melee" },
            es_handgun = { slot_type = "ranged", can_wield = { "es_mercenary" },
                property_table_name = "ranged", trait_table_name = "ranged_ammo" },
            necklace_base = { slot_type = "necklace", property_table_name = "defence_accessory", trait_table_name = "defence_accessory" },
            ring_base = { slot_type = "ring", property_table_name = "offence_accessory", trait_table_name = "offence_accessory" },
            trinket_base = { slot_type = "trinket", property_table_name = "utility_accessory", trait_table_name = "utility_accessory" },
        }
        if options.item_required_dlc then
            masters.es_1h_sword.required_dlc = options.item_required_dlc
        end
        local property_combinations = {
            melee = { exotic = { { "attack_speed", "crit_chance" } } },
            ranged = { exotic = { { "crit_chance", "power_vs_skaven" } } },
            defence_accessory = { exotic = { { "stamina", "health" } } },
            offence_accessory = { exotic = { { "attack_speed", "power_vs_chaos" } } },
            utility_accessory = { exotic = { { "ability_cooldown_reduction", "crit_chance" } } },
        }
        local trait_combinations = {
            melee = { { "melee_attack_speed_on_crit" } },
            ranged_ammo = { { "ranged_replenish_ammo_headshot" } },
            defence_accessory = { { "necklace_damage_taken_reduction_on_heal" } },
            offence_accessory = { { "ring_potion_duration" } },
            utility_accessory = { { "trinket_grenade_damage_taken" } },
        }
        local item_cache = {}
        for key, value in pairs(inventory) do item_cache[key] = value end
        local talents_value = { 3, 3, 3, 3, 3, 3 }
        local removed, registered, finalized, created_order = {}, {}, {}, {}
        local refreshes, dirties = 0, 0
        local unregister_calls = 0
        local rollback_started = false
        local registration_complete = false
        local preexisting_craft = options.preexisting_craft_id and {
            owner = "preexisting",
        } or nil
        if preexisting_craft then
            registered[options.preexisting_craft_id] = preexisting_craft
        end
        local mirror = {
            _inventory_items = inventory,
            add_item = function(_, bid, item)
                if options.noop_add_at == #created_order + 1 then return end
                inventory[bid] = item
                local record = options.pending_record
                item.backend_id = bid
                item.key = item.ItemId
                item.data = masters[item.ItemId]
                item.rarity = record.rarity
                item.power_level = record.power_level
                item.traits = {}
                for i = 1, #record.traits do item.traits[i] = record.traits[i] end
                item.properties = {}
                for key, value in pairs(record.properties) do
                    item.properties[key] = value
                end
                item.skin = record.skin
                if options.throw_add_at == #created_order + 1 then
                    error("add exception")
                end
            end,
            remove_item = function(_, bid)
                rollback_started = true
                removed[#removed + 1] = bid
                if options.noop_remove then return end
                if options.throw_remove_before then error("remove exception") end
                inventory[bid] = nil
                if options.throw_remove_after then error("remove delete exception") end
            end,
        }
        local items = {
            _backend_mirror = mirror,
            get_item_from_id = function(_, bid) return item_cache[bid] end,
            _refresh = function()
                refreshes = refreshes + 1
                if options.throw_cleanup_refresh and rollback_started then
                    error("refresh exception")
                end
                if options.noop_cleanup_refresh and rollback_started then return end
                item_cache = {}
                for key, value in pairs(inventory) do item_cache[key] = value end
            end,
        }
        local talents = {
            get_talent_tree = function() return { {1,2,3}, {1,2,3}, {1,2,3}, {1,2,3}, {1,2,3}, {1,2,3} } end,
            get_talents = function() local out = {}; for i=1,6 do out[i]=talents_value[i] end; return out end,
            set_talents = function(_, career, picks)
                if options.fail_talents and picks[1] ~= 3 then error("talent failure") end
                if options.throw_restore_talents and picks[1] == 3 then
                    error("talent restore exception")
                end
                if options.fail_restore_talents and picks[1] == 3 then
                    return false, "talent restore rejected"
                end
                talents_value = {}; for i=1,6 do talents_value[i]=picks[i] end
            end,
        }
        local managers = { backend = {
            get_interface = function(_, name) return name == "items" and items or talents end,
            dirtify_interfaces = function()
                dirties = dirties + 1
                if options.throw_cleanup_dirtify and rollback_started then
                    error("dirtify exception")
                end
            end,
        }, unlock = {
            dlc_exists = function() return options.dlc_exists ~= false end,
            is_dlc_unlocked = function() return options.dlc_owned ~= false end,
        } }
        local mod = {
            _cim_base_power = function() return 300 end,
            _cim_snapshot_exact_loadout = function()
                local slots = {}; for key,value in pairs(equipped) do slots[key]=value end
                return { index = 1, slots = slots }
            end,
            _cim_write_exact_loadout_item = function(_, slot, bid)
                if options.throw_equip_slot == slot and bid:match("^new") then error("equip exception") end
                if options.fail_equip_slot == slot and bid:match("^new") then
                    if options.replace_persisted_on_equip_failure then
                        registered.new1 = { owner = "replacement" }
                    end
                    return false, "forced"
                end
                if options.throw_restore_slot == slot and not bid:match("^new") then
                    error("restore exception")
                end
                if options.fail_restore_slot == slot and not bid:match("^new") then
                    return false, "restore rejected"
                end
                equipped[slot] = bid; return true
            end,
            _cim_finalize_exact_loadout = function(_, values)
                finalized[#finalized + 1] = values
                if options.throw_finalize and values.slot_melee:match("^new") then error("finalize exception") end
                if options.fail_finalize and values.slot_melee:match("^new") then return false, "forced" end
                if options.throw_restore_finalize
                        and not values.slot_melee:match("^new") then
                    error("finalize restore exception")
                end
                if options.fail_restore_finalize
                        and not values.slot_melee:match("^new") then
                    return false, "finalize restore rejected"
                end
                return true
            end,
            _cim_register_crafts_batch = function(entries)
                if options.replace_before_register_failure then
                    local bid = created_order[1]
                    local replacement = { key = "foreign", data = { key = "foreign" } }
                    inventory[bid], item_cache[bid] = replacement, replacement
                end
                if options.fail_register then return false, "forced" end
                if options.throw_register then error("register exception") end
                local proof = {}
                for bid, row in pairs(entries) do
                    registered[bid] = row
                    proof[bid] = row
                end
                registration_complete = true
                if options.replace_persisted_after_register then
                    registered.new1 = { owner = "replacement" }
                end
                if options.throw_register_after_publish then
                    error("register post-publish exception")
                end
                if options.register_without_proof then return true end
                return true, proof
            end,
            _cim_unregister_crafts_batch = function(ids)
                unregister_calls = unregister_calls + 1
                if options.fail_unregister then return false, "forced" end
                if options.throw_unregister then error("unregister exception") end
                if options.noop_unregister then return true end
                for i=1,#ids do registered[ids[i]] = nil end
                return true
            end,
            _cim_get_craft = function(bid)
                if options.throw_get_craft_after_register
                        and registration_complete then
                    error("persisted read exception")
                end
                return registered[bid]
            end,
            _cim_item_requires_unowned_dlc = function() return false end,
        }
        local contract = synthetic_contract
        local next_guid = 0
        local importer = importer_module.install({ mod = mod, catalog = catalog, contract = contract,
            inject_item = function(record, bid)
                if options.fail_inject_at and next_guid == options.fail_inject_at then return nil, "forced" end
                if options.throw_inject_at and next_guid == options.throw_inject_at then error("inject exception") end
                local normalized, normalize_error = contract.gate_record(
                    "mirror_injection", bid, record, masters[record.item_key])
                if not normalized then return nil, normalize_error end
                local payload, payload_error, mirror_record =
                    contract.build_mirror_payload(normalized,
                        masters[record.item_key], function() return "encoded" end)
                if not payload then return nil, payload_error end
                options.pending_record = mirror_record
                local added, add_error, token, _, rollback =
                    contract.inject_mirror_item(mirror, bid, payload,
                        function() return "nonce-" .. bid end, mirror_record)
                options.pending_record = nil
                if not added then return nil, add_error end
                created_order[#created_order + 1] = bid
                item_cache[bid] = inventory[bid]
                if options.invalid_token_at == next_guid then token = {} end
                if options.missing_rollback_at == next_guid then rollback = nil end
                return bid, nil, token, rollback
            end,
            guid = function()
                next_guid = next_guid + 1
                return options.duplicate_guid and "new1" or "new" .. next_guid
            end,
            get_managers = function() return managers end,
            get_globals = function() return { ItemMasterList = masters,
                CareerSettings = { es_mercenary = {} },
                WeaponProperties = { combinations = property_combinations },
                WeaponTraits = { combinations = trait_combinations, traits = {} } } end,
        })
        local build = assert(catalog.normalize_document({ name = "x/builds/test", fields = {
            careerId=1, name="Test", username="Author", likeCount=1, dateModified="2026",
            talent1=1,talent2=2,talent3=3,talent4=1,talent5=2,talent6=3,
            primaryWeapon={id=15,property1Id=1,property2Id=4,traitId=6},
            secondaryWeapon={id=56,property1Id=1,property2Id=3,traitId=2},
            necklace={property1Id=1,property2Id=3,traitId=1},
            charm={property1Id=1,property2Id=4,traitId=2},
            trinket={property1Id=1,property2Id=2,traitId=3},
        } }))
        return { importer=importer, build=build, equipped=equipped, previous=previous,
            inventory=inventory, removed=removed, registered=registered,
            talents=function() return talents_value end, finalized=finalized,
            refreshes=function() return refreshes end,
            dirties=function() return dirties end,
            cached=function(bid) return item_cache[bid] end,
            created_order=created_order,
            unregister_calls=function() return unregister_calls end,
            preexisting_craft=preexisting_craft }
    end

    H.test("Ranald importer preflights and atomically applies five slots plus six talents", function()
        local f = fixture()
        local plan, err = f.importer.preflight(f.build)
        H.equal(err, nil); H.equal(plan.career_name, "es_mercenary")
        local ok, result = f.importer.apply(f.build)
        H.equal(ok, true); H.equal(#result.backend_ids, 5)
        for _, slot in ipairs(importer_module.SLOT_ORDER) do H.truthy(f.equipped[slot]:match("^new")) end
        H.deep_equal(f.talents(), {1,2,3,1,2,3})
        local count = 0; for _ in pairs(f.registered) do count = count + 1 end
        H.equal(count, 5); H.equal(#f.removed, 0); H.equal(#f.finalized, 1)
        local necklace = f.registered[result.by_slot.slot_necklace]
        H.equal(necklace.traits[1], "necklace_damage_taken_reduction_on_heal")
        H.equal(necklace.properties.stamina, 1.0)
        H.equal(necklace.properties.health, 1.0)
    end)

    H.test("Ranald importer rejects an illegal roll before creating anything", function()
        local f = fixture()
        f.build.slots.slot_melee.property2_id = 8
        local ok, err = f.importer.apply(f.build)
        H.equal(ok, false); H.truthy(err:find("illegal property pair", 1, true))
        H.equal(next(f.registered), nil); H.equal(#f.removed, 0)
        H.deep_equal(f.equipped, f.previous)
    end)

    H.test("Ranald importer fails closed on unavailable or unowned item DLC", function()
        local unavailable = fixture({ item_required_dlc = "lake", dlc_exists = false })
        local ok, reason = unavailable.importer.apply(unavailable.build)
        H.equal(ok, false)
        H.truthy(reason:find("item DLC status unavailable", 1, true))
        H.equal(next(unavailable.registered), nil)

        local unowned = fixture({ item_required_dlc = "lake", dlc_owned = false })
        ok, reason = unowned.importer.apply(unowned.build)
        H.equal(ok, false)
        H.truthy(reason:find("item DLC is not owned", 1, true))
        H.equal(next(unowned.registered), nil)
    end)

    H.test("Ranald importer restores every surface after a mid-loadout failure", function()
        local f = fixture({ fail_equip_slot = "slot_necklace" })
        local ok, err = f.importer.apply(f.build)
        H.equal(ok, false); H.truthy(err:find("equip slot_necklace", 1, true))
        H.deep_equal(f.equipped, f.previous)
        H.deep_equal(f.talents(), {3,3,3,3,3,3})
        H.equal(next(f.registered), nil); H.equal(#f.removed, 5)
        H.equal(#f.finalized, 1, "rollback must refresh the original live weapon units")
    end)

    H.test("Ranald importer cleans all mirror rows when batch persistence rejects", function()
        local f = fixture({ fail_register = true })
        local ok, err = f.importer.apply(f.build)
        H.equal(ok, false); H.truthy(err:find("persist", 1, true))
        H.deep_equal(f.equipped, f.previous)
        H.equal(#f.removed, 5); H.equal(next(f.registered), nil)
        H.equal(f.refreshes(), 1)
        H.equal(f.dirties(), 1)
        H.equal(f.unregister_calls(), 0,
            "a rejected candidate-first batch must never unregister foreign state")
    end)

    H.test("Ranald importer rejects an occupied generated persistence identity", function()
        local f = fixture({ preexisting_craft_id = "new1" })
        local ok, reason = f.importer.apply(f.build)
        H.equal(ok, false)
        H.truthy(reason:find("identity allocation occupied: new1", 1, true),
            reason)
        H.equal(f.registered.new1, f.preexisting_craft)
        H.equal(#f.created_order, 0)
        H.equal(#f.removed, 0)
        H.equal(f.unregister_calls(), 0)
    end)

    H.test("Ranald importer retains uncertain post-registration persistence", function()
        for _, scenario in ipairs({
                { throw_register_after_publish = true },
                { register_without_proof = true },
                { throw_get_craft_after_register = true },
                { replace_persisted_after_register = true },
            }) do
            local f = fixture(scenario)
            local call_ok, imported, reason = pcall(f.importer.apply, f.build)
            H.equal(call_ok, true, "registration uncertainty escaped importer")
            H.equal(imported, false)
            H.truthy(reason:find("persist", 1, true), reason)
            for i = 1, 5 do
                local bid = "new" .. i
                H.truthy(f.registered[bid])
                H.truthy(f.inventory[bid])
                H.truthy(f.cached(bid))
            end
            H.equal(#f.removed, 0)
            H.equal(f.unregister_calls(), 0)
        end
    end)

    H.test("Ranald importer rolls back prior exact rows after a later-slot injection failure", function()
        local f = fixture({ fail_inject_at = 3 })
        local ok, reason = f.importer.apply(f.build)
        H.equal(ok, false)
        H.truthy(reason:find("create slot_necklace", 1, true), reason)
        H.equal(#f.created_order, 2)
        H.equal(#f.removed, 2)
        H.equal(f.inventory.new1, nil)
        H.equal(f.inventory.new2, nil)
        H.equal(f.cached("new1"), nil)
        H.equal(f.cached("new2"), nil)
        H.equal(f.refreshes(), 1)
        H.equal(next(f.registered), nil)
        H.deep_equal(f.equipped, f.previous)
    end)

    H.test("Ranald importer contains native no-op and throwing add paths", function()
        for _, scenario in ipairs({
                { noop_add_at = 3 },
                { throw_add_at = 3 },
            }) do
            local f = fixture(scenario)
            local call_ok, imported, reason = pcall(f.importer.apply, f.build)
            H.equal(call_ok, true, "native add failure escaped importer")
            H.equal(imported, false)
            H.truthy(reason:find("create slot_necklace", 1, true), reason)
            H.equal(#f.created_order, 2)
            for i = 1, 3 do
                H.equal(f.inventory["new" .. i], nil)
                H.equal(f.cached("new" .. i), nil)
            end
            H.equal(f.refreshes(), 1)
            H.equal(next(f.registered), nil)
            H.deep_equal(f.equipped, f.previous)
        end
    end)

    H.test("Ranald importer uses canonical rollback for no-op and throwing removers", function()
        for _, scenario in ipairs({
                { noop_remove = true },
                { throw_remove_before = true },
                { throw_remove_after = true },
            }) do
            scenario.fail_register = true
            local f = fixture(scenario)
            local call_ok, imported, reason = pcall(f.importer.apply, f.build)
            H.equal(call_ok, true, "remover failure escaped importer")
            H.equal(imported, false)
            H.truthy(reason:find("persist", 1, true), reason)
            for i = 1, 5 do
                H.equal(f.inventory["new" .. i], nil)
                H.equal(f.cached("new" .. i), nil)
            end
            H.equal(#f.removed, 5)
            H.equal(f.refreshes(), 1)
            H.equal(next(f.registered), nil)
        end
    end)

    H.test("Ranald importer preserves a foreign replacement during failed persistence cleanup", function()
        local f = fixture({
            fail_register = true,
            replace_before_register_failure = true,
        })
        local ok, reason = f.importer.apply(f.build)
        H.equal(ok, false)
        H.truthy(reason:find("cleanup failed", 1, true), reason)
        H.truthy(reason:find("mirror_identity_mismatch", 1, true), reason)
        H.equal(f.inventory.new1.key, "foreign")
        H.equal(f.cached("new1").key, "foreign")
        for i = 2, 5 do
            H.equal(f.inventory["new" .. i], nil)
            H.equal(f.cached("new" .. i), nil)
        end
        H.equal(#f.removed, 4,
            "replacement must be rejected before the native remover is called")
        H.equal(f.refreshes(), 1)
    end)

    H.test("Ranald importer contains no-op and throwing cleanup refreshes", function()
        for _, scenario in ipairs({
                { noop_cleanup_refresh = true,
                  expected = "refresh_postcondition" },
                { throw_cleanup_refresh = true,
                  expected = "refresh exception" },
            }) do
            scenario.fail_register = true
            local f = fixture(scenario)
            local call_ok, imported, reason = pcall(f.importer.apply, f.build)
            H.equal(call_ok, true, "refresh failure escaped importer")
            H.equal(imported, false)
            H.truthy(reason:find("cleanup failed", 1, true), reason)
            H.truthy(reason:find(scenario.expected, 1, true), reason)
            for i = 1, 5 do H.equal(f.inventory["new" .. i], nil) end
            H.equal(f.refreshes(), 1)
        end
    end)

    H.test("Ranald importer rejects missing or invalid injector ownership evidence", function()
        for _, scenario in ipairs({
                { invalid_token_at = 3 },
                { missing_rollback_at = 3 },
            }) do
            local f = fixture(scenario)
            local ok, reason = f.importer.apply(f.build)
            H.equal(ok, false)
            H.truthy(reason:find("ownership proof rejected", 1, true), reason)
            for i = 1, 3 do
                H.equal(f.inventory["new" .. i], nil)
                H.equal(f.cached("new" .. i), nil)
            end
            H.equal(next(f.registered), nil)
            H.equal(f.refreshes(), 1)
        end
    end)

    H.test("Ranald importer compensates a talent write exception", function()
        local f = fixture({ fail_talents = true })
        local ok, err = f.importer.apply(f.build)
        H.equal(ok, false); H.truthy(err:find("talents", 1, true))
        H.deep_equal(f.equipped, f.previous)
        H.deep_equal(f.talents(), {3,3,3,3,3,3})
        H.equal(#f.removed, 5); H.equal(next(f.registered), nil)
    end)

    H.test("Ranald importer reports a failed compensation without corrupting rows", function()
        local f = fixture({ fail_equip_slot = "slot_necklace", fail_unregister = true })
        local call_ok, imported, reason = pcall(f.importer.apply, f.build)
        H.equal(call_ok, true)
        H.equal(imported, false)
        H.truthy(reason:find("rollback failed", 1, true))
        H.truthy(reason:find("unregister:forced", 1, true))
        H.deep_equal(f.equipped, f.previous)
        local registered_count, mirror_count = 0, 0
        for bid in pairs(f.registered) do
            registered_count = registered_count + 1
            if f.inventory[bid] then mirror_count = mirror_count + 1 end
        end
        H.equal(registered_count, 5)
        H.equal(mirror_count, 5,
            "failed persistent cleanup must retain coherent mirror rows")
    end)

    H.test("Ranald importer preserves persisted replacements and hostile unregister paths", function()
        for _, scenario in ipairs({
                { replace_persisted_on_equip_failure = true,
                  expected = "persisted_identity_mismatch" },
                { noop_unregister = true,
                  expected = "persisted_remove_postcondition" },
                { throw_unregister = true,
                  expected = "unregister:" },
            }) do
            scenario.fail_equip_slot = "slot_necklace"
            local f = fixture(scenario)
            local call_ok, imported, reason = pcall(f.importer.apply, f.build)
            H.equal(call_ok, true, "persistence cleanup failure escaped importer")
            H.equal(imported, false)
            H.truthy(reason:find("rollback failed", 1, true), reason)
            H.truthy(reason:find(scenario.expected, 1, true), reason)
            for i = 1, 5 do
                local bid = "new" .. i
                H.truthy(f.registered[bid])
                H.truthy(f.inventory[bid])
                H.truthy(f.cached(bid))
            end
            H.equal(#f.removed, 0)
            if scenario.replace_persisted_on_equip_failure then
                H.equal(f.registered.new1.owner, "replacement")
                H.equal(f.unregister_calls(), 0)
            else
                H.equal(f.unregister_calls(), 1)
            end
        end
    end)

    H.test("Ranald importer retains coherent rows when a restoration surface fails", function()
        for _, scenario in ipairs({
                {
                    options = {
                        fail_equip_slot = "slot_necklace",
                        fail_restore_slot = "slot_melee",
                    },
                    reason = "slot_melee:restore rejected",
                },
                {
                    options = {
                        fail_talents = true,
                        throw_restore_talents = true,
                    },
                    reason = "talent restore exception",
                },
                {
                    options = {
                        fail_finalize = true,
                        fail_restore_finalize = true,
                    },
                    reason = "finalize:finalize restore rejected",
                },
            }) do
            local f = fixture(scenario.options)
            local call_ok, imported, reason = pcall(f.importer.apply, f.build)
            H.equal(call_ok, true, "restoration failure escaped importer")
            H.equal(imported, false)
            H.truthy(reason:find("rollback failed", 1, true), reason)
            H.truthy(reason:find(scenario.reason, 1, true), reason)
            H.equal(#f.removed, 0,
                "rollback must not delete rows that restored state may reference")
            local registered_count = 0
            for i = 1, 5 do
                local bid = "new" .. i
                H.truthy(f.inventory[bid])
                H.truthy(f.cached(bid))
                H.truthy(f.registered[bid])
                registered_count = registered_count + 1
            end
            H.equal(registered_count, 5)
            H.equal(f.refreshes(), 0)
        end
    end)

    H.test("Ranald importer contains every throwing mutation boundary", function()
        for _, scenario in ipairs({
                { options = { throw_inject_at = 3 }, reason = "create slot_necklace" },
                { options = { throw_register = true }, reason = "persist" },
                { options = { throw_equip_slot = "slot_ring" }, reason = "equip slot_ring" },
                { options = { throw_finalize = true }, reason = "live equip" },
            }) do
            local f = fixture(scenario.options)
            local call_ok, imported, reason = pcall(f.importer.apply, f.build)
            H.equal(call_ok, true, "mutation exception escaped importer")
            H.equal(imported, false)
            H.truthy(reason:find(scenario.reason, 1, true), reason)
            H.deep_equal(f.equipped, f.previous)
            H.deep_equal(f.talents(), {3,3,3,3,3,3})
            H.equal(next(f.registered), nil)
        end
    end)

    H.test("Ranald importer rejects duplicate generated identities before commit", function()
        local f = fixture({ duplicate_guid = true })
        local ok, reason = f.importer.apply(f.build)
        H.equal(ok, false); H.equal(reason, "identity allocation failed")
        H.deep_equal(f.equipped, f.previous)
        H.equal(next(f.registered), nil)
        H.equal(f.inventory.new1, nil)
    end)
end
