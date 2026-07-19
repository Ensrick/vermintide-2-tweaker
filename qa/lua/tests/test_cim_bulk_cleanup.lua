return function(H, repo_root)
    local cim_root = repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local core = dofile(cim_root .. "_cim_bulk_cleanup_core.lua")
    local contract = dofile(cim_root .. "_cim_synthetic_item_contract.lua")

    local function owned(item_key, via_mirror)
        return {
            owner = "cim", schema_version = 1, item_key = item_key,
            via_mirror = via_mirror,
        }
    end

    H.test("CIM bulk cleanup deletes exact owned weapons and accessories", function()
        local forged = {
            cim_melee = owned("sword", true),
            cim_ranged = owned("bow", true),
            cim_necklace = owned("necklace_item", true),
            cim_charm = owned("charm_item", true),
            cim_trinket = owned("trinket_item", true),
            cim_hat = owned("hat_item", true),
            cim_missing = owned("disabled_mod_weapon", true),
            cim_unstamped = { item_key = "sword" },
        }
        local item_master = {
            sword = { slot_type = "melee" },
            bow = { slot_type = "ranged" },
            necklace_item = { slot_type = "necklace" },
            charm_item = { slot_type = "ring" },
            trinket_item = { slot_type = "trinket" },
            hat_item = { slot_type = "hat" },
            -- Ordinary backend items and rarity/prefix lookalikes are absent
            -- from CIM's forged map and therefore cannot become candidates.
            vanilla_sword = { slot_type = "melee" },
            vanilla_charm = { slot_type = "ring" },
            cwv_definition = { slot_type = "melee", rarity = "modded" },
        }
        local crafts, retained, unresolved = core.classify(forged, item_master, contract)
        H.deep_equal(crafts, {
            "cim_charm", "cim_melee", "cim_necklace", "cim_ranged", "cim_trinket",
        })
        H.deep_equal(retained, { "cim_hat" })
        H.deep_equal(unresolved, { "cim_missing", "cim_unstamped" })
    end)

    H.test("CIM bulk cleanup classifier fails closed outside exact ownership", function()
        local masters = {
            weapon = { slot_type = "melee" },
            accessory = { slot_type = "ring" },
        }
        H.equal(#core.classify({ a = owned("weapon", true) }, masters, contract), 1)
        H.equal(#core.classify({ a = owned("accessory", true) }, masters, contract), 1)
        H.equal(#core.classify({}, masters, contract), 0)
        H.equal(#core.classify({ a = owned("weapon", true) }, {}, contract), 0)
        H.equal(#core.classify({ a = owned("weapon", true) }, masters, nil), 0)
        H.equal(#core.classify({ a = owned("weapon", true) }, masters, {
            classify_owned_record = function() return "owned" end,
        }), 0)
        H.equal(#core.classify({ a = owned("weapon", true) }, masters, {
            canonical_item_key = function() error("key drift") end,
            classify_owned_record = function() return "owned" end,
        }), 0)
        H.equal(#core.classify({ [""] = owned("weapon", true) }, masters, contract), 0)
        H.equal(#core.classify({ a = {} }, masters, contract), 0)
        H.equal(#core.classify({ a = "malformed" }, masters, contract), 0)
        H.equal(#core.classify(nil, nil, contract), 0)
    end)

    H.test("CIM craftable slot scope includes all three accessory families", function()
        H.equal(contract.is_craftable_slot_type("melee"), true)
        H.equal(contract.is_craftable_slot_type("ranged"), true)
        H.equal(contract.is_craftable_slot_type("necklace"), true)
        H.equal(contract.is_craftable_slot_type("ring"), true)
        H.equal(contract.is_craftable_slot_type("trinket"), true)
        H.equal(contract.is_craftable_slot_type("hat"), false)
        H.equal(contract.is_craftable_slot_type(nil), false)
    end)

    H.test("CIM bulk cleanup fails closed on equipped or uncertain state", function()
        local ids = { "a", "b", "c" }
        local deletable, blocked, uncertain = core.partition_equipped(ids, function(id)
            if id == "a" then return false end
            if id == "b" then return true end
            return nil
        end)
        H.deep_equal(deletable, { "a" })
        H.deep_equal(blocked, { "b" })
        H.deep_equal(uncertain, { "c" })
    end)

    H.test("CIM bulk cleanup confirmation signature is order independent", function()
        H.equal(core.signature({ "b", "a" }), core.signature({ "a", "b" }))
        H.equal(core.signature({ "a" }) == core.signature({ "a", "b" }), false)
    end)

    H.test("CIM bulk cleanup preview fingerprints exact cleanup identity", function()
        local records = {
            a = owned("weapon", true),
            b = owned("accessory", true),
        }
        local masters = {
            weapon = { slot_type = "melee" },
            accessory = { slot_type = "ring" },
        }
        local baseline = core.snapshot_signature({ "b", "a" }, records, masters, contract)
        H.equal(baseline, core.snapshot_signature({ "a", "b" }, records, masters, contract))

        records.a.properties = { crit_chance = 0.05 }
        H.equal(baseline, core.snapshot_signature({ "a", "b" }, records, masters, contract))

        records.a.item_key = "accessory"
        H.equal(baseline == core.snapshot_signature({ "a", "b" }, records, masters, contract), false)
        records.a.item_key = "weapon"
        records.a.via_mirror = false
        H.equal(baseline == core.snapshot_signature({ "a", "b" }, records, masters, contract), false)
        records.a.via_mirror = true
        masters.weapon.slot_type = "ranged"
        H.equal(baseline == core.snapshot_signature({ "a", "b" }, records, masters, contract), false)

        H.equal(core.snapshot_signature({ "a" }, records, masters, nil), nil)
        H.equal(core.snapshot_signature({ "missing" }, records, masters, contract), nil)
    end)

    H.test("CIM bulk cleanup clears only targeted persistence references", function()
        local loadout = {
            flat = { slot_melee = "delete_a", slot_ranged = "keep" },
            indexed = { [1] = { slot_melee = "delete_b", slot_ranged = "keep_2" } },
        }
        local overrides = { delete_a = "skin_a", keep = "skin_keep" }
        H.truthy(core.clear_loadout_refs(loadout, { "delete_a", "delete_b" }))
        H.truthy(core.clear_map_keys(overrides, { "delete_a", "delete_b" }))
        H.equal(loadout.flat.slot_melee, nil)
        H.equal(loadout.flat.slot_ranged, "keep")
        H.equal(loadout.indexed[1].slot_melee, nil)
        H.equal(loadout.indexed[1].slot_ranged, "keep_2")
        H.equal(overrides.delete_a, nil)
        H.equal(overrides.keep, "skin_keep")
    end)

    H.test("CIM bulk cleanup runtime shares classification at every destructive seam", function()
        local function read(name)
            local file = assert(io.open(cim_root .. name, "rb"))
            local source = file:read("*a")
            file:close()
            return source
        end
        local entry = read("crafting_in_modded_dev.lua")
        local source = read("_cim_bulk_cleanup_command.lua")
        H.truthy(entry:find(
            "scripts/mods/crafting_in_modded_dev/_cim_bulk_cleanup_command", 1, true))
        H.truthy(source:find(
            "core.classify(forged, item_master, contract)", 1, true))
        H.truthy(source:find(
            "core.snapshot_signature(", 1, true))
        H.truthy(entry:find(
            "pcall(contract.classify_owned_record,", 1, true))
        H.truthy(source:find(
            'type(current) ~= "table" or type(saved) ~= "table"', 1, true))
        H.truthy(source:find(
            'Delete every unequipped CIM-crafted weapon and accessory', 1, true))
    end)
end
