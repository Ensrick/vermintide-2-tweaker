return function(H, repo_root)
    local path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_loadout_slot_policy.lua"
    local Policy = assert(loadfile(path))()

    local function career(slot_ranged)
        return {
            es_knight = {
                item_slot_types_by_slot_name = {
                    slot_melee = { "melee" },
                    slot_ranged = slot_ranged,
                    slot_hat = { "hat" },
                },
            },
            dr_slayer = {
                item_slot_types_by_slot_name = {
                    slot_melee = { "melee" },
                    slot_ranged = { "melee", "ranged" },
                },
            },
            es_questingknight = {
                item_slot_types_by_slot_name = {
                    slot_melee = { "melee" },
                    slot_ranged = { "melee", "ranged" },
                },
            },
        }
    end

    H.test("GUT loadout policy follows live Foot Knight secondary capability", function()
        local settings = career({ "ranged" })
        local cwv_item = {
            slot_type = "melee",
            can_wield = { "es_knight" },
            backend_id = "cwv_es_greataxe_001",
        }

        local ok = Policy.validate(cwv_item, "slot_ranged", "es_knight", settings)
        H.equal(ok, false, "melee must be rejected before the CRT capability exists")

        table.insert(settings.es_knight.item_slot_types_by_slot_name.slot_ranged, 1, "melee")
        ok = Policy.validate(cwv_item, "slot_ranged", "es_knight", settings)
        H.equal(ok, true, "live CRT capability must be observed without reload")
        H.equal(cwv_item.backend_id, "cwv_es_greataxe_001", "CWV identity must remain exact")

        table.remove(settings.es_knight.item_slot_types_by_slot_name.slot_ranged, 1)
        ok = Policy.validate(cwv_item, "slot_ranged", "es_knight", settings)
        H.equal(ok, false, "toggle-off capability removal must be observed without reload")
    end)

    H.test("GUT loadout policy preserves native dual-melee careers", function()
        local settings = career({ "ranged" })
        local slayer_item = { slot_type = "melee", can_wield = { "dr_slayer" } }
        local grail_item = { slot_type = "melee", can_wield = { "es_questingknight" } }

        H.equal(Policy.validate(slayer_item, "slot_ranged", "dr_slayer", settings), true)
        H.equal(Policy.validate(grail_item, "slot_ranged", "es_questingknight", settings), true)
    end)

    H.test("GUT loadout policy accepts WT and CWV by capability not key", function()
        local settings = career({ "melee", "ranged" })
        local wt_item = { key = "foreign_wt_weapon", slot_type = "melee", can_wield = { "es_knight" } }
        local cwv_item = { key = "cwv_es_infantry_spear", slot_type = "melee", can_wield = { "es_knight" } }

        H.equal(Policy.validate(wt_item, "slot_ranged", "es_knight", settings), true)
        H.equal(Policy.validate(cwv_item, "slot_ranged", "es_knight", settings), true)
    end)

    H.test("GUT loadout policy rejects absent capabilities and wield permission", function()
        local settings = career({ "melee", "ranged" })
        local wrong_career = { slot_type = "melee", can_wield = { "dr_slayer" } }
        local wrong_type = { slot_type = "ranged", can_wield = { "es_knight" } }

        H.equal(Policy.validate(wrong_career, "slot_ranged", "es_knight", settings), false)
        H.equal(Policy.validate(wrong_type, "slot_hat", "es_knight", settings), false)
        H.equal(Policy.validate(wrong_type, "slot_ranged", "missing_career", settings), false)
        H.equal(Policy.validate(wrong_type, "missing_slot", "es_knight", settings), false)
        H.equal(Policy.validate(nil, "slot_ranged", "es_knight", settings), false)
    end)
end
