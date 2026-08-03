-- _cim_regression_cleanup.lua - cleanup and exact identity runtime checks.

return function(context)
    local mod = context.mod
    local register = context.rt_register
    local src_read = context.rt_src_read
    local accessory_property_policy = context.accessory_property_policy

    register("issue277_bulk_cleanup_exact_owner_transaction", function()
        local core = mod._cim277_bulk_core
        local deletion = mod._cim277_owned_deletion
        if type(core) ~= "table" or type(core.classify) ~= "function"
                or type(core.snapshot_signature) ~= "function"
                or type(core.partition_equipped) ~= "function"
                or type(core.clear_loadout_refs) ~= "function"
                or type(deletion) ~= "table"
                or type(deletion.execute) ~= "function"
                or deletion.MARKER ~= "cim_owned_deletion_transaction_v2"
                or type(mod._cim277_delete_owned_ids) ~= "function"
                or mod.CIM277_BULK_CLEANUP_MARKER_v0_8_68 ~= true then
            return "#277 cleanup policy/runtime wiring missing"
        end

        local contract = mod._cim_synthetic_item_contract
        local function owned(item_key, via_mirror)
            return {
                owner = "cim", schema_version = 1, item_key = item_key,
                via_mirror = via_mirror,
            }
        end
        local records = {
            owned_weapon = owned("weapon", true),
            owned_accessory = owned("accessory", true),
            owned_out_of_scope = owned("cosmetic", true),
            owned_missing = owned("missing", true),
            owned_unstamped = { item_key = "weapon" },
        }
        local masters = {
            weapon = { slot_type = "melee" },
            accessory = { slot_type = "necklace" },
            cosmetic = { slot_type = "hat" },
            rarity_only_not_owned = { slot_type = "ranged", rarity = "modded" },
        }
        local crafts, retained, unresolved = core.classify(records, masters, contract)
        if #crafts ~= 2 or crafts[1] ~= "owned_accessory" or crafts[2] ~= "owned_weapon"
                or #retained ~= 1 or retained[1] ~= "owned_out_of_scope"
                or #unresolved ~= 2 or unresolved[1] ~= "owned_missing"
                or unresolved[2] ~= "owned_unstamped" then
            return "exact-owner craft classification failed"
        end
        local no_contract = core.classify({ owned_weapon = owned("weapon", true) },
            masters, nil)
        if #no_contract ~= 0 then
            return "classify must delete nothing without the identity contract"
        end

        -- Execute the owning pure transaction, not a source needle copied from its
        -- former inline implementation.
        local rt_records = { rt_delete = owned("weapon", true) }
        local rt_loadouts = { rt_career = { slot_melee = "rt_delete" } }
        local rt_overrides = { rt_delete = "rt_skin" }
        local rt_inventory = { rt_delete = { backend_id = "rt_delete" } }
        local rt_new = { rt_delete = "exact-marker" }
        local rt_new_by_career = {
            rt_career = { melee = { rt_delete = "exact-career-marker" } },
        }
        local removed, delete_err = deletion.execute({
            records = rt_records,
            item_master = masters,
            contract = contract,
            inventory_items = rt_inventory,
            new_item_ids = rt_new,
            new_item_ids_by_career = rt_new_by_career,
            loadouts = rt_loadouts,
            clear_loadout_refs = core.clear_loadout_refs,
            persist_loadouts = function() end,
            get_overrides = function() return rt_overrides end,
            clear_override_refs = core.clear_map_keys,
            persist_overrides = function() end,
            save = function() end,
            invalidate = function() end,
        }, { "rt_delete" })
        if removed ~= 1 or delete_err ~= nil
                or rt_records.rt_delete ~= nil
                or rt_inventory.rt_delete ~= nil
                or rt_new.rt_delete ~= nil
                or rt_new_by_career.rt_career.melee.rt_delete ~= nil
                or rt_loadouts.rt_career.slot_melee ~= nil
                or rt_overrides.rt_delete ~= nil then
            return "owned deletion module transaction failed"
        end

        local snapshot = core.snapshot_signature(crafts, records, masters, contract)
        records.owned_weapon.item_key = "accessory"
        local changed = core.snapshot_signature(crafts, records, masters, contract)
        if not snapshot or not changed or snapshot == changed then
            return "same-id canonical identity changes must invalidate cleanup preview"
        end
        records.owned_weapon.item_key = "weapon"
        records.owned_weapon.via_mirror = false
        changed = core.snapshot_signature(crafts, records, masters, contract)
        if snapshot == changed then
            return "same-id deletion-route changes must invalidate cleanup preview"
        end

        local entry = src_read(
            "scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua")
        if entry then
            for _, marker in ipairs({
                "core.classify(_forged_weapons, ItemMasterList, contract)",
                "core.snapshot_signature(deletable, _forged_weapons,",
                "deletion.execute({",
                "type(current) ~= \"table\" or type(saved) ~= \"table\"",
            }) do
                if not entry:find(marker, 1, true) then
                    return "#277 runtime wiring marker missing: " .. marker
                end
            end
        end

        local deletable, blocked, uncertain = core.partition_equipped(
            { "free", "equipped", "unknown" },
            function(id)
                if id == "free" then return false end
                if id == "equipped" then return true end
                return nil
            end
        )
        if #deletable ~= 1 or deletable[1] ~= "free"
                or #blocked ~= 1 or blocked[1] ~= "equipped"
                or #uncertain ~= 1 or uncertain[1] ~= "unknown" then
            return "equipped/uncertain fail-closed partition failed"
        end
        if core.signature({ "b", "a" }) ~= core.signature({ "a", "b" }) then
            return "confirmation signature changed with iteration order"
        end
    end)

    register("issue959_accessory_property_layers_are_independent", function()
        local policy = accessory_property_policy
        if type(policy) ~= "table"
            or type(policy.count_slots) ~= "function"
            or type(policy.last_slot) ~= "function"
            or type(policy.collect_property_slots) ~= "function"
            or type(policy.store_property_slot) ~= "function"
            or type(policy.count_distinct_properties) ~= "function"
            or mod.CIM959_ACCESSORY_PROPERTY_LAYER_MARKER ~= true
        then
            return "#959 accessory property layer policy/runtime wiring missing"
        end

        local properties = { weave_health = { 11, 12, 13, 14, 15 } }
        if policy.count_slots(properties.weave_health, "defence_accessory", 10) ~= 5
            or policy.count_slots(properties.weave_health, "offence_accessory", 10) ~= 0
            or policy.count_slots(properties.weave_health, "utility_accessory", 10) ~= 0
        then
            return "Necklace Health usage leaked into another accessory layer"
        end

        local _, stored, reason = policy.store_property_slot(
            properties, "weave_health", 1, 5, 10)
        if not stored or reason ~= "stored" then
            return "Charm Health write was rejected by Necklace's property cap"
        end
        if policy.count_slots(properties.weave_health, "offence_accessory", 10) ~= 1
            or policy.count_slots(properties.weave_health, "defence_accessory", 10) ~= 5
            or policy.last_slot(properties.weave_health, "offence_accessory", 10) ~= 1
        then
            return "Charm edit did not remain independent from Necklace usage"
        end

        local removals = policy.collect_property_slots(
            properties, "offence_accessory", 10)
        if #removals ~= 1
            or removals[1].property_key ~= "weave_health"
            or removals[1].slot_index ~= 1
        then
            return "active-category clear plan crossed an accessory layer"
        end

        if policy.count_distinct_properties(properties, 2, 10) ~= 1
            or policy.count_distinct_properties(properties, 12, 10) ~= 1
        then
            return "same property did not count independently in each accessory layer"
        end

        -- Write-crash guard: the faked mastery-costs table must resolve the
        -- GLOBAL per-key use count (up to cap*3 across layers) to 0, not nil -
        -- a nil there aborts vanilla's slot repaint mid-loop and freezes the
        -- sibling accessory's grid (Rain's 2026-08-03 log, v0.8.112-dev).
        if type(policy.build_zero_mastery_costs) ~= "function" then
            return "#959 zero-mastery-costs builder missing"
        end
        local costs = policy.build_zero_mastery_costs(5)
        if #costs ~= 5 or costs[5] ~= 0 or costs[6] ~= 0 or costs[15] ~= 0
            or costs[16] ~= nil
        then
            return "faked mastery costs cannot cover the layered global use count"
        end

        -- Reopen bleed: seeding must APPEND sibling layers under one key, not
        -- overwrite, and must clamp to the accessory's authored layer.
        if type(policy.seed_property_indices) ~= "function" then
            return "#959 seed merge helper missing"
        end
        local seeded = {}
        policy.seed_property_indices(seeded, "weave_health", 1, 5, 0, 10)
        local _, dropped = policy.seed_property_indices(seeded, "weave_health", 11, 1, 10, 10)
        if dropped ~= 0
            or policy.count_slots(seeded.weave_health, "offence_accessory", 10) ~= 5
            or policy.count_slots(seeded.weave_health, "defence_accessory", 10) ~= 1
        then
            return "amulet re-seed dropped a sibling accessory's property entries"
        end
        local _, clamped = policy.seed_property_indices(seeded, "weave_stamina", 9, 4, 0, 10)
        if clamped ~= 2
            or policy.count_slots(seeded.weave_stamina, "defence_accessory", 10) ~= 0
        then
            return "amulet re-seed spilled indices into the sibling layer"
        end
    end)

    register("issue246_tab_preview_exact_skin_icon", function()
        local core = mod._cim246_tab_preview_core
        if type(core) ~= "table" or type(core.resolve) ~= "function"
                or type(mod._cim246_apply_player_weapon_icons) ~= "function" then
            return "#246 Tab-preview policy/runtime wiring missing"
        end

        local authoritative, skin, icon = core.resolve({}, {
            slots = { slot_melee = { skin = "issue246_test_skin" } },
        }, "slot_melee", {
            issue246_test_skin = { inventory_icon = "issue246_test_icon" },
        })
        if not authoritative or skin ~= "issue246_test_skin"
                or icon ~= "issue246_test_icon" then
            return "exact live-equipment skin did not win over base loadout identity"
        end

        authoritative, skin, icon = core.resolve({}, {
            slots = { slot_melee = { skin = "n/a" } },
        }, "slot_melee", {})
        if not authoritative or skin ~= nil or icon ~= nil then
            return "default skin did not clear stale preview identity"
        end
    end)

end
