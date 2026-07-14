return function(H, repo_root)
    local core = dofile(repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_bulk_cleanup_core.lua")

    H.test("CIM bulk cleanup classifies exact owned weapons only", function()
        local forged = {
            cim_melee = { item_key = "sword" },
            cim_ranged = { item_key = "bow" },
            cim_accessory = { item_key = "necklace" },
            cim_missing = { item_key = "disabled_mod_weapon" },
        }
        local item_master = {
            sword = { slot_type = "melee" },
            bow = { slot_type = "ranged" },
            necklace = { slot_type = "necklace" },
            -- A rarity-only or prefix-only item is deliberately absent from
            -- `forged`, so it can never enter the delete set.
            cwv_definition = { slot_type = "melee", rarity = "modded" },
        }
        local weapons, non_weapons, unresolved = core.classify(forged, item_master)
        H.deep_equal(weapons, { "cim_melee", "cim_ranged" })
        H.deep_equal(non_weapons, { "cim_accessory" })
        H.deep_equal(unresolved, { "cim_missing" })
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
end
