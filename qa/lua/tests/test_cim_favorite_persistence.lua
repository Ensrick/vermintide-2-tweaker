-- Behavioral coverage for #1001: exact-instance favorite persistence for CIM
-- crafts. Loads the real policy module, the real synthetic-item contract, the
-- real owned-deletion transaction, and the real forge state owner.
return function(H, repo_root)
    local root = repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local policy = assert(loadfile(root .. "_cim_favorite_persistence.lua"))()
    local contract = assert(loadfile(root .. "_cim_synthetic_item_contract.lua"))()
    local deletion = assert(loadfile(root .. "_cim_owned_deletion.lua"))()

    H.test("CIM #1001 captures only exact owned instances", function()
        local saves = 0
        local records = { cim_1 = { item_key = "cwv_dr_dawi_mace" } }
        local changed, value = policy.capture(records, "cim_1", true, function()
            saves = saves + 1
        end)
        H.truthy(changed)
        H.equal(value, true)
        H.equal(records.cim_1.favorite, true)
        H.equal(saves, 1)

        local foreign, reason = policy.capture(records, "native_1", true,
            function() saves = saves + 1 end)
        H.equal(foreign, false)
        H.equal(reason, "foreign_item")
        H.equal(saves, 1)
    end)

    H.test("CIM #1001 dedupes unchanged toggles including the nil default", function()
        local saves = 0
        local records = { cim_1 = {} }
        -- nil -> false is not a change: no spurious persistence pass.
        local unchanged, reason = policy.capture(records, "cim_1", false,
            function() saves = saves + 1 end)
        H.equal(unchanged, false)
        H.equal(reason, "unchanged")
        H.equal(saves, 0)

        records.cim_1.favorite = true
        local changed, value = policy.capture(records, "cim_1", false,
            function() saves = saves + 1 end)
        H.truthy(changed)
        H.equal(value, false)
        H.equal(records.cim_1.favorite, false)
        H.equal(saves, 1)

        local repeated = policy.capture(records, "cim_1", false,
            function() saves = saves + 1 end)
        H.equal(repeated, false)
        H.equal(saves, 1)
    end)

    H.test("CIM #1001 favorite survives a simulated refresh prune and reinject", function()
        -- Vanilla model (backend_interface_item_playfab.lua:95-107): favorites
        -- whose rows are absent during a refresh pass are pruned.
        local function vanilla_prune(items, favorite_ids)
            for backend_id in pairs(favorite_ids) do
                if not items[backend_id] then favorite_ids[backend_id] = nil end
            end
        end
        local records = {
            cim_1 = { favorite = true },
            cim_2 = { favorite = true },
        }
        local items = { native_1 = { backend_id = "native_1" } }
        local favorite_ids = { cim_1 = true, cim_2 = true, native_1 = true }

        vanilla_prune(items, favorite_ids)
        H.equal(favorite_ids.cim_1, nil)
        H.equal(favorite_ids.cim_2, nil)
        H.equal(favorite_ids.native_1, true)

        local marked = {}
        local function resolve(backend_id) return items[backend_id] end
        local function mark(backend_id, item)
            H.equal(item.backend_id, backend_id)
            marked[#marked + 1] = backend_id
            favorite_ids[backend_id] = true
        end

        -- Only cim_1 reinjects on this pass; cim_2 stays deferred, durable.
        items.cim_1 = { backend_id = "cim_1" }
        local restored, deferred = policy.restore_all(records, resolve, mark)
        H.equal(restored, 1)
        H.equal(deferred, 1)
        H.equal(favorite_ids.cim_1, true)
        H.equal(favorite_ids.cim_2, nil)
        H.deep_equal(marked, { "cim_1" })

        items.cim_2 = { backend_id = "cim_2" }
        restored, deferred = policy.restore_all(records, resolve, mark)
        H.equal(restored, 2)
        H.equal(deferred, 0)
        H.equal(favorite_ids.cim_2, true)
        -- Foreign ids are never touched by the restore sweep.
        H.equal(favorite_ids.native_1, true)
        for i = 1, #marked do
            H.truthy(marked[i] ~= "native_1")
        end
    end)

    H.test("CIM #1001 restore failures stay bounded and fail closed", function()
        local records = { cim_1 = { favorite = true } }
        local ok, reason = policy.restore_one(records, "cim_1",
            function() return {} end,
            function() error("synthetic failure") end)
        H.equal(ok, false)
        H.truthy(reason:find("mark_failed:", 1, true))

        local no_item, unavailable = policy.restore_one(records, "cim_1",
            function() return nil end, function() end)
        H.equal(no_item, false)
        H.equal(unavailable, "item_unavailable")

        local not_fav = policy.restore_one({ cim_1 = { favorite = false } },
            "cim_1", function() return {} end, function() end)
        H.equal(not_fav, false)

        local foreign = policy.restore_one(records, "native_1",
            function() return {} end, function() end)
        H.equal(foreign, false)
    end)

    H.test("CIM #1001 contract carries the favorite bit through normalization", function()
        local record = assert(contract.normalize_record("cim_1", {
            item_key = "dr_1h_hammer",
            favorite = true,
        }))
        H.equal(record.favorite, true)
        local round_trip = assert(contract.normalize_record("cim_1", record))
        H.equal(round_trip.favorite, true)

        -- false and absent both normalize to nil, so foreign inputs cannot
        -- invent a mark and unfavorited records persist nothing.
        local unfavorited = assert(contract.normalize_record("cim_2", {
            item_key = "dr_1h_hammer",
            favorite = false,
        }))
        H.equal(unfavorited.favorite, nil)
        local untouched = assert(contract.normalize_record("cim_3", {
            item_key = "dr_1h_hammer",
        }))
        H.equal(untouched.favorite, nil)
    end)

    H.test("CIM #1001 deletion transaction clears the record for good", function()
        local records = {
            delete_me = {
                owner = "cim", schema_version = 1,
                item_key = "weapon", via_mirror = true, favorite = true,
            },
            keep_me = {
                owner = "cim", schema_version = 1,
                item_key = "weapon", via_mirror = true, favorite = true,
            },
        }
        local rows = {
            delete_me = { backend_id = "delete_me" },
            keep_me = { backend_id = "keep_me" },
        }
        local saves = 0
        local deps = {
            records = records,
            item_master = { weapon = { slot_type = "melee" } },
            contract = contract,
            inventory_items = rows,
            loadouts = {},
            clear_loadout_refs = function() return true end,
            persist_loadouts = function() end,
            get_overrides = function() return {} end,
            clear_override_refs = function() return true end,
            persist_overrides = function() end,
            save = function() saves = saves + 1 end,
            invalidate = function() end,
        }
        local removed, err = deletion.execute(deps, { "delete_me" })
        H.equal(err, nil)
        H.equal(removed, 1)
        H.equal(records.delete_me, nil)
        H.truthy(records.keep_me)
        H.truthy(saves >= 1)

        -- The stored bit died with the record: a later restore sweep cannot
        -- resurrect the deleted craft's favorite, and the survivor still works.
        local marked = {}
        local restored = policy.restore_all(records,
            function(backend_id) return rows[backend_id] end,
            function(backend_id) marked[#marked + 1] = backend_id end)
        H.equal(restored, 1)
        H.deep_equal(marked, { "keep_me" })
    end)

    H.test("CIM #1001 forge owner persists and restores the bit end to end", function()
        local saved = {
            fav_bid = {
                item_key = "dr_1h_hammer", slot_type = "melee",
                power_level = 300, rarity = "modded", via_mirror = true,
                favorite = true, properties = {}, traits = {},
            },
            plain_bid = {
                item_key = "dr_1h_hammer", slot_type = "melee",
                power_level = 300, rarity = "modded", via_mirror = true,
                properties = {}, traits = {},
            },
        }
        local mod = {
            settings = { forged_weapons = saved },
            hooks = {}, safe_hooks = {},
            _cim_external_trait_policy = {
                merge_traits = function(active) return active or {} end,
                partition = function(combined) return combined, {} end,
                REQUIRED_CAPABILITY_BY_PROVIDER = {},
                RESERVED_PROVIDER_BY_TRAIT = {},
            },
            _cim_synthetic_item_contract = contract,
            _cim_favorite_persistence = policy,
        }
        function mod:get(key) return self.settings[key] end
        function mod:set(key, value) self.settings[key] = value end
        function mod:info() end
        function mod:echo() end
        function mod:hook(class, method, fn)
            self.hooks[tostring(class) .. ":" .. method] = fn
        end
        function mod:hook_safe(class, method, fn)
            self.safe_hooks[tostring(class) .. ":" .. method] = fn
        end
        function mod:dofile(path)
            if path:find("_cim_custom_glow_notice", 1, true) then
                return { new = function()
                    return { observe = function() return 0, false end }
                end }
            end
            if path:find("_cim_mil_entry_builder", 1, true) then
                return function(weapon, backend_id)
                    return { backend_id = backend_id, key = weapon.item_key }
                end
            end
            error("unexpected dofile: " .. tostring(path))
        end

        local rows = {}
        local favorite_ids = {}
        local helper = {
            is_favorite_backend_id = function(backend_id)
                return favorite_ids[backend_id] == true
            end,
            mark_backend_id_as_favorite = function(backend_id, item, save_flag)
                H.equal(save_flag, false)
                H.equal(item.backend_id, backend_id)
                favorite_ids[backend_id] = true
            end,
        }
        local managers = {
            input = { is_device_active = function() return false end },
            backend = {
                get_interface = function()
                    return {
                        get_item_from_id = function(_, backend_id)
                            return rows[backend_id]
                        end,
                    }
                end,
            },
        }
        local checks = {}
        local install = assert(loadfile(root .. "_cim_forge_state_owner.lua"))()
        local owner = install({
            mod = mod,
            rt_register = function(name, fn) checks[name] = fn end,
            print_line = function() end,
            get_mod = function() return nil end,
            get_managers = function() return managers end,
            get_item_master_list = function() return {} end,
            get_weapon_traits = function() return nil end,
            get_cjson = function() return nil end,
            get_item_helper = function() return helper end,
            get_athanor_inject_all = function() return nil end,
            get_restore_modded_loadout = function() return nil end,
        })

        -- load() carried the persisted bit onto the live normalized record and
        -- save() wrote it back to settings.
        H.equal(owner.get_forged_weapons().fav_bid.favorite, true)
        H.equal(owner.get_forged_weapons().plain_bid.favorite, nil)
        H.equal(mod.settings.forged_weapons.fav_bid.favorite, true)
        H.equal(mod.settings.forged_weapons.plain_bid.favorite, nil)

        -- Both engine seams are wired exactly once.
        local toggle = mod.hooks["ItemGridUI:handle_favorite_marking"]
        local refresh = mod.safe_hooks["BackendInterfaceItemPlayfab:_refresh"]
        H.equal(type(toggle), "function")
        H.equal(type(refresh), "function")
        H.equal(type(checks.issue1001_favorite_persistence), "function")

        -- Post-refresh restore defers until the exact row resolves, then marks.
        refresh()
        H.equal(favorite_ids.fav_bid, nil)
        rows.fav_bid = { backend_id = "fav_bid" }
        refresh()
        H.equal(favorite_ids.fav_bid, true)
        H.equal(favorite_ids.plain_bid, nil)
        H.equal(checks.issue1001_favorite_persistence(), nil)

        -- A completed unfavorite toggle updates the durable record and the
        -- persisted settings blob; a foreign row is left alone.
        favorite_ids.fav_bid = nil
        local handled = toggle(function() return true end, {
            get_item_hovered = function() return rows.fav_bid end,
        }, {})
        H.equal(handled, true)
        H.equal(owner.get_forged_weapons().fav_bid.favorite, false)
        H.equal(mod.settings.forged_weapons.fav_bid.favorite, nil)
        refresh()
        H.equal(favorite_ids.fav_bid, nil)

        local foreign_handled = toggle(function() return true end, {
            get_item_hovered = function()
                return { backend_id = "native_1" }
            end,
        }, {})
        H.equal(foreign_handled, true)
        H.equal(owner.get_forged_weapons().native_1, nil)

        -- Re-favorite through the same seam and confirm the persisted state.
        favorite_ids.fav_bid = true
        toggle(function() return true end, {
            get_item_hovered = function() return rows.fav_bid end,
        }, {})
        H.equal(owner.get_forged_weapons().fav_bid.favorite, true)
        H.equal(mod.settings.forged_weapons.fav_bid.favorite, true)
    end)
end
