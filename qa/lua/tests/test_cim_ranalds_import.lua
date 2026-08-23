return function(H, repo_root)
    local root = repo_root .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local catalog = assert(loadfile(root .. "_cim_ranalds_catalog.lua"))()
    local importer_module = assert(loadfile(root .. "_cim_ranalds_import.lua"))()

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
        local talents_value = { 3, 3, 3, 3, 3, 3 }
        local removed, registered, finalized = {}, {}, {}
        local mirror = {
            remove_item = function(_, bid) removed[#removed + 1] = bid; inventory[bid] = nil end,
        }
        local items = {
            _backend_mirror = mirror,
            get_item_from_id = function(_, bid) return inventory[bid] end,
        }
        local talents = {
            get_talent_tree = function() return { {1,2,3}, {1,2,3}, {1,2,3}, {1,2,3}, {1,2,3}, {1,2,3} } end,
            get_talents = function() local out = {}; for i=1,6 do out[i]=talents_value[i] end; return out end,
            set_talents = function(_, career, picks)
                if options.fail_talents and picks[1] ~= 3 then error("talent failure") end
                talents_value = {}; for i=1,6 do talents_value[i]=picks[i] end
            end,
        }
        local managers = { backend = {
            get_interface = function(_, name) return name == "items" and items or talents end,
            dirtify_interfaces = function() end,
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
                if options.fail_equip_slot == slot and bid:match("^new") then return false, "forced" end
                equipped[slot] = bid; return true
            end,
            _cim_finalize_exact_loadout = function(_, values)
                finalized[#finalized + 1] = values
                if options.throw_finalize and values.slot_melee:match("^new") then error("finalize exception") end
                if options.fail_finalize and values.slot_melee:match("^new") then return false, "forced" end
                return true
            end,
            _cim_register_crafts_batch = function(entries)
                if options.fail_register then return false, "forced" end
                for bid, row in pairs(entries) do registered[bid] = row end
                if options.throw_register then error("register exception") end
                return true
            end,
            _cim_unregister_crafts_batch = function(ids)
                if options.fail_unregister then return false, "forced" end
                for i=1,#ids do registered[ids[i]] = nil end
                return true
            end,
            _cim_item_requires_unowned_dlc = function() return false end,
        }
        local contract = {
            validate_provider = function() return true, {} end,
            canonical_item_key = function(item) return item.key or (item.data and item.data.key) end,
        }
        local next_guid = 0
        local importer = importer_module.install({ mod = mod, catalog = catalog, contract = contract,
            inject_item = function(record, bid)
                if options.fail_inject_at and next_guid == options.fail_inject_at then return nil, "forced" end
                inventory[bid] = { key = record.item_key, data = masters[record.item_key] }
                if options.throw_inject_at and next_guid == options.throw_inject_at then error("inject exception") end
                return bid
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
            talents=function() return talents_value end, finalized=finalized }
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
