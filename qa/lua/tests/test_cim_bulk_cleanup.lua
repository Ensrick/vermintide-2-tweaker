return function(H, repo_root)
    local cim_root = repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local core = dofile(cim_root .. "_cim_bulk_cleanup_core.lua")
    local contract = dofile(cim_root .. "_cim_synthetic_item_contract.lua")
    local deletion = dofile(cim_root .. "_cim_owned_deletion.lua")
    local salvage_boundary = dofile(cim_root .. "_cim_salvage_local_boundary.lua")
    local craft_dispatch = dofile(cim_root .. "_cim_craft_dispatch.lua")

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

    H.test("CIM #628 deletion removes exact rows and vanilla new metadata", function()
        local records = {
            delete_me = owned("weapon", true),
            keep_me = owned("weapon", true),
            woc_blightreaper_001 = owned("woc_blightreaper", true),
        }
        local item_master = {
            weapon = { slot_type = "melee" },
            woc_blightreaper = {
                slot_type = "melee",
                woc_variant = true,
                woc_unique_relic = true,
            },
        }
        local rows = {
            delete_me = { backend_id = "delete_me" },
            keep_me = { backend_id = "keep_me" },
            woc_blightreaper_001 = { backend_id = "woc_blightreaper_001" },
        }
        local new_ids = { delete_me = "global-exact", keep_me = "keep-global" }
        local career_markers = {
            delete_me = "career-exact", keep_me = "keep-career",
        }
        local new_by_career = {
            dr_ranger = { melee = career_markers },
        }
        local removed_rows = {}
        local loadouts = {
            dr_ranger = { slot_melee = "delete_me", slot_ranged = "keep_me" },
            es_mercenary = {
                [2] = {
                    slot_melee = "woc_blightreaper_001",
                    slot_ranged = "delete_me",
                },
            },
        }
        local overrides = {
            delete_me = "delete_skin",
            keep_me = "keep_skin",
            woc_blightreaper_001 = "relic_skin",
        }
        local loadout_saves, override_saves, saves, invalidations = 0, 0, 0, 0
        local deps = {
            records = records,
            item_master = item_master,
            contract = contract,
            inventory_items = rows,
            new_item_ids = new_ids,
            new_item_ids_by_career = new_by_career,
            remove_local_row = function(inventory, backend_id)
                removed_rows[#removed_rows + 1] = backend_id
                rawset(inventory, backend_id, nil)
            end,
            loadouts = loadouts,
            clear_loadout_refs = core.clear_loadout_refs,
            persist_loadouts = function() loadout_saves = loadout_saves + 1 end,
            get_overrides = function() return overrides end,
            clear_override_refs = core.clear_map_keys,
            persist_overrides = function(value)
                overrides = value
                override_saves = override_saves + 1
            end,
            save = function() saves = saves + 1 end,
            invalidate = function() invalidations = invalidations + 1 end,
        }
        local removed, err =
            deletion.execute(deps, { "delete_me", "delete_me" })

        H.equal(err, nil)
        H.equal(removed, 1)
        H.deep_equal(removed_rows, { "delete_me" })
        H.equal(records.delete_me, nil)
        H.truthy(records.keep_me)
        H.truthy(records.woc_blightreaper_001)
        H.equal(loadouts.dr_ranger.slot_melee, nil)
        H.equal(loadouts.dr_ranger.slot_ranged, "keep_me")
        H.equal(loadouts.es_mercenary[2].slot_ranged, nil)
        H.equal(loadouts.es_mercenary[2].slot_melee, "woc_blightreaper_001")
        H.equal(overrides.delete_me, nil)
        H.equal(overrides.keep_me, "keep_skin")
        H.equal(rows.delete_me, nil)
        H.truthy(rows.keep_me)
        H.equal(new_ids.delete_me, nil)
        H.equal(new_ids.keep_me, "keep-global")
        H.equal(career_markers.delete_me, nil)
        H.equal(career_markers.keep_me, "keep-career")
        H.equal(loadout_saves, 1)
        H.equal(override_saves, 1)
        H.equal(saves, 1)
        H.equal(invalidations, 1)

        local relic_removed, relic_err =
            deletion.execute(deps, { "woc_blightreaper_001" })
        H.equal(relic_removed, 0)
        H.truthy(type(relic_err) == "string")
        H.deep_equal(removed_rows, { "delete_me" })
        H.truthy(records.woc_blightreaper_001)
    end)

    H.test("CIM #628 deletion compensates every fallible local seam", function()
        local function fixture(fail_at, legacy)
            local tripped = false
            local function trip(label)
                if fail_at == label and not tripped then
                    tripped = true
                    error("planted " .. label)
                end
            end
            local records = {
                first = owned("weapon", not legacy),
                second = owned("weapon", true),
            }
            local inventory_rows = {
                second = { backend_id = "second" },
            }
            if not legacy then
                inventory_rows.first = { backend_id = "first" }
            end
            local local_remove_count = 0
            local loadouts = {
                career = { slot_melee = "first", slot_ranged = "second" },
            }
            local overrides = { first = "skin_a", second = "skin_b" }
            local legacy_rows = legacy and { first = { backend_id = "first" } } or {}
            local deps = {
                records = records,
                item_master = { weapon = { slot_type = "melee" } },
                contract = contract,
                inventory_items = inventory_rows,
                new_item_ids = { first = "new-first", second = "new-second" },
                new_item_ids_by_career = {
                    career = {
                        melee = { first = "career-first", second = "career-second" },
                    },
                },
                remove_local_row = function(inventory, backend_id)
                    local_remove_count = local_remove_count + 1
                    rawset(inventory, backend_id, nil)
                    trip("local_remove_" .. local_remove_count)
                end,
                loadouts = loadouts,
                clear_loadout_refs = function(map, ids)
                    core.clear_loadout_refs(map, ids)
                    trip("clear_loadout_refs")
                end,
                persist_loadouts = function() trip("persist_loadouts") end,
                get_overrides = function()
                    trip("get_overrides")
                    return overrides
                end,
                clear_override_refs = function(map, ids)
                    core.clear_map_keys(map, ids)
                    trip("clear_override_refs")
                end,
                persist_overrides = function() trip("persist_overrides") end,
                build_legacy_entry = function(record, backend_id)
                    trip("build_legacy_entry")
                    return { backend_id = backend_id, record = record }
                end,
                remove_legacy_item = function(backend_id)
                    legacy_rows[backend_id] = nil
                    trip("legacy_remove")
                end,
                restore_legacy_item = function(backend_id, entry)
                    legacy_rows[backend_id] = entry
                    trip("legacy_restore")
                end,
                save = function() trip("save") end,
                invalidate = function() trip("invalidate") end,
            }
            return deps, records, inventory_rows, loadouts, overrides, legacy_rows
        end

        local scenarios = {
            { "get_overrides", false, "override snapshot failed" },
            { "clear_loadout_refs", false, "loadout cleanup failed" },
            { "clear_override_refs", false, "override cleanup failed" },
            { "local_remove_1", false, "local inventory remove first failed" },
            { "local_remove_2", false, "local inventory remove second failed" },
            { "persist_loadouts", false, "loadout persistence failed" },
            { "persist_overrides", false, "override persistence failed" },
            { "save", false, "craft persistence failed" },
            { "invalidate", false, "inventory invalidation failed" },
            { "build_legacy_entry", true, "legacy deletion snapshot failed" },
            { "legacy_remove", true, "legacy remove first failed" },
        }
        for i = 1, #scenarios do
            local name, legacy, needle =
                scenarios[i][1], scenarios[i][2], scenarios[i][3]
            local deps, records, inventory_rows, loadouts, overrides, legacy_rows =
                fixture(name, legacy)
            local removed, err = deletion.execute(deps, { "first", "second" })
            H.equal(removed, 0, name)
            H.truthy(type(err) == "string" and err:find(needle, 1, true), name)
            H.truthy(records.first, name)
            H.truthy(records.second, name)
            H.equal(loadouts.career.slot_melee, "first", name)
            H.equal(loadouts.career.slot_ranged, "second", name)
            H.equal(overrides.first, "skin_a", name)
            H.equal(overrides.second, "skin_b", name)
            if legacy then
                H.truthy(legacy_rows.first, name)
            else
                H.truthy(inventory_rows.first, name)
            end
            H.truthy(inventory_rows.second, name)
            H.equal(deps.new_item_ids.first, "new-first", name)
            H.equal(deps.new_item_ids.second, "new-second", name)
        end
    end)

    H.test("CIM #628 mixed salvage rolls back owned plus two foreign rows exactly", function()
        local records = { owned = owned("weapon", true) }
        local owned_row = {
            backend_id = "owned", skin = "owned-skin-row",
            payload = { exact = 1 },
        }
        local foreign_a_row = {
            backend_id = "foreign_a", skin = "foreign-a-skin-row",
            payload = { exact = 2 },
        }
        local foreign_b_row = {
            backend_id = "foreign_b", skin = "foreign-b-skin-row",
            payload = { exact = 3 },
        }
        local rows = {
            owned = owned_row,
            foreign_a = foreign_a_row,
            foreign_b = foreign_b_row,
        }
        local new_ids = {
            owned = "owned-global",
            foreign_a = "foreign-a-global",
            foreign_b = "foreign-b-global",
        }
        local career_map = {
            owned = "owned-career",
            foreign_a = "foreign-a-career",
            foreign_b = "foreign-b-career",
        }
        local new_by_career = { dr_ranger = { melee = career_map } }
        local favorites = {
            owned = "owned-favorite",
            foreign_a = "foreign-a-favorite",
            foreign_b = "foreign-b-favorite",
        }
        local loadouts = { dr_ranger = { slot_melee = "owned" } }
        local overrides = { owned = "owned-skin" }
        local attempts = {}
        local eager_refreshes, new_unmarks, favorite_unmarks, autosaves = 0, 0, 0, 0
        local invalidations = 0
        local tx_deps = {
            records = records,
            item_master = { weapon = { slot_type = "melee" } },
            contract = contract,
            inventory_items = rows,
            new_item_ids = new_ids,
            new_item_ids_by_career = new_by_career,
            remove_local_row = function(inventory, backend_id)
                attempts[#attempts + 1] = backend_id
                rawset(inventory, backend_id, nil)
                if backend_id == "foreign_b" then
                    error("planted second foreign failure")
                end
            end,
            loadouts = loadouts,
            clear_loadout_refs = core.clear_loadout_refs,
            persist_loadouts = function() end,
            get_overrides = function() return overrides end,
            clear_override_refs = core.clear_map_keys,
            persist_overrides = function() end,
            save = function() end,
            -- Production-shaped forbidden seam: BackendInterfaceItemPlayfab
            -- _refresh normalizes skin rows, unmarks missing new/favorite ids,
            -- and autosaves. Rollback must never call this eager path.
            refresh = function()
                eager_refreshes = eager_refreshes + 1
                rows.owned.skin = nil
                new_ids.owned = nil
                favorites.owned = nil
                new_unmarks = new_unmarks + 1
                favorite_unmarks = favorite_unmarks + 1
                autosaves = autosaves + 1
            end,
            invalidate = function()
                invalidations = invalidations + 1
            end,
        }
        local crafting = { _last_id = 40, _craft_requests = {} }
        local recipe = { name = "salvage" }
        local outer_dirtify, presentation_calls = 0, 0
        local refusal_err
        local id, completed_recipe, committed = craft_dispatch.execute({
            invalidate = function()
                outer_dirtify = outer_dirtify + 1
                presentation_calls = presentation_calls + 1
            end,
        }, crafting, function()
            local summary
            summary, refusal_err = salvage_boundary.execute({
                contract = contract,
                get_record = function(backend_id) return records[backend_id] end,
                delete_owned_ids = function(owned_ids, foreign_ids)
                    return deletion.execute(tx_deps, owned_ids, foreign_ids)
                end,
            }, { "owned", "foreign_a", "foreign_b" })
            if not summary then return {}, false end
            return {}, true
        end, { "owned", "foreign_a", "foreign_b" }, recipe, "salvage")

        H.equal(id, 41)
        H.equal(completed_recipe, recipe)
        H.equal(committed, false)
        H.deep_equal(crafting._craft_requests[41], {})
        H.truthy(refusal_err:find(
            "local inventory remove foreign_b failed", 1, true))
        H.deep_equal(attempts, { "owned", "foreign_a", "foreign_b" })
        H.equal(rows.owned, owned_row)
        H.equal(rows.foreign_a, foreign_a_row)
        H.equal(rows.foreign_b, foreign_b_row)
        H.equal(rows.owned.skin, "owned-skin-row")
        H.equal(rows.foreign_a.skin, "foreign-a-skin-row")
        H.equal(rows.foreign_b.skin, "foreign-b-skin-row")
        H.equal(new_ids.owned, "owned-global")
        H.equal(new_ids.foreign_a, "foreign-a-global")
        H.equal(new_ids.foreign_b, "foreign-b-global")
        H.equal(new_by_career.dr_ranger.melee, career_map,
            "rollback must preserve the exact metadata table owner")
        H.equal(career_map.owned, "owned-career")
        H.equal(career_map.foreign_a, "foreign-a-career")
        H.equal(career_map.foreign_b, "foreign-b-career")
        H.equal(favorites.owned, "owned-favorite")
        H.equal(favorites.foreign_a, "foreign-a-favorite")
        H.equal(favorites.foreign_b, "foreign-b-favorite")
        H.truthy(records.owned)
        H.equal(loadouts.dr_ranger.slot_melee, "owned")
        H.equal(overrides.owned, "owned-skin")
        H.equal(eager_refreshes, 0)
        H.equal(new_unmarks, 0)
        H.equal(favorite_unmarks, 0)
        H.equal(autosaves, 0)
        H.equal(invalidations, 0,
            "presentation invalidation is success-only")
        H.equal(outer_dirtify, 0,
            "enclosing craft dispatcher must not dirtify a refused salvage")
        H.equal(presentation_calls, 0)
    end)

    H.test("CIM #628 production salvage boundary is executable and local-only", function()
        H.equal(salvage_boundary.MARKER, "cim_salvage_local_only_v1")
        local records = { owned = owned("weapon", true) }
        local owned_deleted, foreign_deleted = {}, {}
        local summary, err = salvage_boundary.execute({
            contract = contract,
            get_record = function(backend_id) return records[backend_id] end,
            delete_owned_ids = function(owned_ids, foreign_ids)
                owned_deleted = owned_ids
                foreign_deleted = foreign_ids
                return #owned_ids
            end,
        }, { "owned", "foreign", "owned" })
        H.equal(err, nil)
        H.deep_equal(summary, {
            selected = 3, owned = 1, deleted = 1, foreign = 1,
        })
        H.deep_equal(owned_deleted, { "owned" })
        H.deep_equal(foreign_deleted, { "foreign" })

        local function read(name)
            local file = assert(io.open(cim_root .. name, "rb"))
            local source = file:read("*a")
            file:close()
            return source
        end
        local standard = read("standard_forge.lua")
        local entry = read("crafting_in_modded_dev.lua")
        local boundary_source = read("_cim_salvage_local_boundary.lua")
        local dispatch_source = read("_cim_craft_dispatch.lua")
        local first = assert(standard:find("synth.salvage = function", 1, true))
        local last = assert(standard:find(
            "-- ---- apply_weapon_skin", first, true))
        local production_salvage = standard:sub(first, last - 1)
        local deletion_first = assert(entry:find(
            "mod._cim277_delete_owned_ids = function", 1, true))
        local deletion_last = assert(entry:find(
            'mod:command("forge_delete"', deletion_first, true))
        local production_deletion = entry:sub(deletion_first, deletion_last - 1)
        H.truthy(production_salvage:find("_salvage_local.execute", 1, true))
        H.truthy(production_salvage:find(
            "delete_owned_ids = mod._cim277_delete_owned_ids", 1, true))
        H.truthy(production_salvage:find("return {}, false", 1, true))
        H.truthy(production_salvage:find("return {}, true", 1, true))
        H.truthy(standard:find("_craft_dispatch.execute({", 1, true))
        H.truthy(dispatch_source:find(
            "if committed and type(deps.invalidate)", 1, true))
        H.truthy(production_deletion:find("deletion.execute({", 1, true))
        H.truthy(production_deletion:find(
            "inventory_items = mirror._inventory_items", 1, true))
        H.truthy(production_deletion:find("save = _forge_save", 1, true))
        H.truthy(production_deletion:find(
            "persist_loadouts = _modded_loadout_save", 1, true))
        H.truthy(production_deletion:find(
            "Managers.backend:dirtify_interfaces()", 1, true))
        H.equal(production_deletion:find("items:_refresh()", 1, true), nil)
        for _, forbidden in ipairs({
            "Managers.backend", "BackendInterface", "PlayFab",
            "enqueue", ":commit", ".commit",
        }) do
            H.equal(production_salvage:find(forbidden, 1, true), nil, forbidden)
            H.equal(boundary_source:find(forbidden, 1, true), nil, forbidden)
        end
        for _, forbidden in ipairs({
            "PlayFabRequestQueue", "BackendManagerPlayFab",
            "BackendInterfaceCraftingPlayfab", "enqueue", ":commit", ".commit",
        }) do
            H.equal(production_deletion:find(forbidden, 1, true), nil, forbidden)
        end
        local deletion_source = read("_cim_owned_deletion.lua")
        H.equal(deletion_source:find("mirror.add_item", 1, true), nil)
        H.equal(deletion_source:find("mirror:remove_item", 1, true), nil)
        H.equal(deletion_source:find("ItemHelper.", 1, true), nil)
        H.equal(deletion_source:find("deps.refresh", 1, true), nil)
        H.truthy(deletion_source:find(
            "rawset(deps.inventory_items, backend_id", 1, true))
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
        local deletion_source = read("_cim_owned_deletion.lua")
        local regression_source = read("_cim_regression_checks.lua")
        H.truthy(entry:find(
            "scripts/mods/crafting_in_modded_dev/_cim_bulk_cleanup_command", 1, true))
        H.truthy(source:find(
            "core.classify(forged, item_master, contract)", 1, true))
        H.truthy(source:find(
            "core.snapshot_signature(", 1, true))
        H.truthy(deletion_source:find(
            "contract.classify_owned_record, backend_id, record, master", 1, true))
        H.truthy(deletion_source:find(
            'MARKER = "cim_owned_deletion_transaction_v2"', 1, true))
        H.truthy(regression_source:find(
            'deletion.MARKER ~= "cim_owned_deletion_transaction_v2"', 1, true))
        H.truthy(regression_source:find("deletion.execute({", 1, true))
        H.truthy(entry:find(
            "mod._cim277_owned_deletion", 1, true))
        H.truthy(source:find(
            'type(current) ~= "table" or type(saved) ~= "table"', 1, true))
        H.truthy(source:find(
            'Delete every unequipped CIM-crafted weapon and accessory', 1, true))
    end)
end
