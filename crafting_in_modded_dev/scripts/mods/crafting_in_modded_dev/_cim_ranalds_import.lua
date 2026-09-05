-- Atomic Ranald's Gift build importer (#1360).
--
-- Preflight is complete before the first mirror write. Commit creates five
-- fresh CIM-owned rows, persists them once, writes the selected indexed
-- loadout, writes six talents, then refreshes the live weapon units once. Any
-- failure attempts the prior loadout/talents and removes new rows only after
-- exact restoration and persistence-ownership postconditions succeed. An
-- uncertain compensation retains coherent persisted/live rows and reports it.

local M = {}

M.SLOT_ORDER = {
    "slot_melee", "slot_ranged", "slot_necklace", "slot_ring", "slot_trinket_1",
}

local SLOT_KIND = {
    slot_necklace = "necklace", slot_ring = "ring", slot_trinket_1 = "trinket",
}

local function _copy_array(value)
    local result = {}
    for i = 1, #(value or {}) do result[i] = value[i] end
    return result
end

local function _contains(array, value)
    for i = 1, #(array or {}) do if array[i] == value then return true end end
    return false
end

local function _property_pair_allowed(combinations, table_name, first, second)
    local row = combinations and combinations[table_name]
    local pool = type(row) == "table" and row.exotic
    if type(pool) ~= "table" then return false end
    for i = 1, #pool do
        local combo = pool[i]
        if _contains(combo, first) and _contains(combo, second) then return true end
    end
    return false
end

local function _trait_allowed(combinations, table_name, trait)
    local pool = combinations and combinations[table_name]
    if type(pool) ~= "table" then return false end
    for i = 1, #pool do
        local entry = pool[i]
        if type(entry) == "table" and entry[1] == trait then return true end
    end
    return false
end

function M.install(ctx)
    assert(type(ctx) == "table", "Ranald importer requires context")
    local mod = assert(ctx.mod, "Ranald importer requires mod")
    local catalog = assert(ctx.catalog, "Ranald importer requires catalog")
    local contract = assert(ctx.contract, "Ranald importer requires contract")
    local inject_item = assert(ctx.inject_item, "Ranald importer requires inject_item")
    local guid = assert(ctx.guid, "Ranald importer requires guid")
    local get_globals = assert(ctx.get_globals, "Ranald importer requires globals")
    local get_managers = assert(ctx.get_managers, "Ranald importer requires managers")

    local function _owns_dlc(managers, dlc_id)
        if not dlc_id then return true end
        local unlock = managers and managers.unlock
        if not unlock or type(unlock.dlc_exists) ~= "function"
                or type(unlock.is_dlc_unlocked) ~= "function" then
            return nil
        end
        local exists_ok, exists = pcall(unlock.dlc_exists, unlock, dlc_id)
        if not exists_ok or not exists then return nil end
        local owned_ok, owned = pcall(unlock.is_dlc_unlocked, unlock, dlc_id)
        if not owned_ok then return nil end
        return owned == true
    end

    local function _preflight_impl(build)
        if type(build) ~= "table" or type(build.career_name) ~= "string"
                or type(build.slots) ~= "table" or type(build.talents) ~= "table" then
            return nil, "invalid build"
        end
        for _, dependency in ipairs({
                mod._cim_snapshot_exact_loadout, mod._cim_write_exact_loadout_item,
                mod._cim_finalize_exact_loadout, mod._cim_register_crafts_batch,
                mod._cim_unregister_crafts_batch, mod._cim_get_craft,
            }) do
            if type(dependency) ~= "function" then
                return nil, "transaction APIs unavailable"
            end
        end
        if catalog.CAREERS[build.career_id] ~= build.career_name then
            return nil, "career identity mismatch"
        end
        local globals = get_globals()
        local item_master_list = globals.ItemMasterList
        local career_settings = globals.CareerSettings
        local weapon_properties = globals.WeaponProperties
        local weapon_traits = globals.WeaponTraits
        if type(item_master_list) ~= "table" or type(career_settings) ~= "table"
                or type(weapon_properties) ~= "table" or type(weapon_traits) ~= "table" then
            return nil, "equipment globals unavailable"
        end
        local career = career_settings[build.career_name]
        if type(career) ~= "table" then return nil, "career unavailable" end
        local managers = get_managers()
        if type(managers) ~= "table" then return nil, "managers unavailable" end
        if career.required_dlc then
            local owned = _owns_dlc(managers, career.required_dlc)
            if owned == nil then return nil, "career DLC status unavailable" end
            if not owned then return nil, "career DLC is not owned" end
        end

        local snapshot, snapshot_err = mod._cim_snapshot_exact_loadout(
            build.career_name, M.SLOT_ORDER)
        if not snapshot then return nil, snapshot_err end
        local backend = managers.backend
        local items = backend and backend:get_interface("items")
        local talents = backend and backend:get_interface("talents")
        if not items or not talents then return nil, "backend interfaces unavailable" end
        local talent_tree = talents:get_talent_tree(build.career_name)
        local previous_talents = talents:get_talents(build.career_name)
        if type(talent_tree) ~= "table" or type(previous_talents) ~= "table" then
            return nil, "talent data unavailable"
        end
        for row = 1, 6 do
            local pick = build.talents[row]
            if type(pick) ~= "number" or pick < 1 or pick > 3
                    or type(talent_tree[row]) ~= "table" or not talent_tree[row][pick] then
                return nil, "invalid talent row " .. tostring(row)
            end
        end

        local records = {}
        for i = 1, #M.SLOT_ORDER do
            local slot_name = M.SLOT_ORDER[i]
            local selected = build.slots[slot_name]
            if type(selected) ~= "table" then return nil, "missing " .. slot_name end
            local item_key
            if selected.weapon_id then
                item_key = catalog.WEAPONS[selected.weapon_id]
            else
                local source_bid = snapshot.slots[slot_name]
                local source_item = items:get_item_from_id(source_bid)
                item_key = source_item and contract.canonical_item_key(source_item, source_bid)
            end
            local master = item_key and rawget(item_master_list, item_key)
            if not master then return nil, "item unavailable: " .. tostring(item_key) end
            local provider_ok, provider_problems = contract.validate_provider(item_key, master)
            if provider_ok == false then
                return nil, "item provider rejected: " .. tostring(item_key) .. ":"
                    .. table.concat(provider_problems or {}, ",")
            end
            if selected.weapon_id and not _contains(master.can_wield, build.career_name) then
                return nil, "career cannot wield " .. item_key
            end
            if master.required_dlc then
                local owned = _owns_dlc(managers, master.required_dlc)
                if owned == nil then
                    return nil, "item DLC status unavailable: " .. item_key
                end
                if not owned then return nil, "item DLC is not owned: " .. item_key end
            end
            if mod._cim_item_requires_unowned_dlc
                    and mod._cim_item_requires_unowned_dlc(item_key) then
                return nil, "item DLC is not owned: " .. item_key
            end

            local kind = SLOT_KIND[slot_name]
                or (master.slot_type == "ranged" and "ranged" or "melee")
            local property1 = catalog.property_key(kind, selected.property1_id)
            local property2 = catalog.property_key(kind, selected.property2_id)
            local trait = catalog.trait_key(master.trait_table_name, selected.trait_id)
            if not property1 or not property2 then
                return nil, "unsupported properties: " .. item_key
            end
            if not trait then return nil, "unsupported trait: " .. item_key end
            if not _property_pair_allowed(weapon_properties.combinations,
                    master.property_table_name, property1, property2) then
                return nil, "illegal property pair: " .. item_key
            end
            if not _trait_allowed(weapon_traits.combinations,
                    master.trait_table_name, trait) then
                return nil, "illegal trait: " .. item_key
            end
            local trait_row = weapon_traits.traits and weapon_traits.traits[trait]
            if trait_row and trait_row.crafting_disabled then
                return nil, "trait is not craftable: " .. trait
            end
            records[slot_name] = {
                item_key = item_key,
                properties = { [property1] = 1.0, [property2] = 1.0 },
                traits = { trait },
                power_level = (mod._cim_base_power and mod._cim_base_power()) or 300,
                rarity = "modded",
                via_mirror = true,
                career_name = build.career_name,
            }
        end

        return {
            build = build,
            career_name = build.career_name,
            records = records,
            snapshot = snapshot,
            previous_talents = _copy_array(previous_talents),
            talents = _copy_array(build.talents),
            items = items,
            talents_interface = talents,
        }
    end

    local function _preflight(build)
        local ok, plan, reason = pcall(_preflight_impl, build)
        if not ok then return nil, "preflight exception: " .. tostring(plan) end
        return plan, reason
    end

    local function _backend_ids(created)
        local result = {}
        for i = 1, #(created or {}) do
            result[i] = created[i].backend_id
        end
        return result
    end

    local function _refresh_after_rollback(plan, removed)
        local failures = {}
        local managers = get_managers()
        local backend = managers and managers.backend
        if backend and type(backend.dirtify_interfaces) == "function" then
            local ok, err = pcall(backend.dirtify_interfaces, backend)
            if not ok then failures[#failures + 1] = "dirtify:" .. tostring(err) end
        end

        local items = plan.items
        if type(items) ~= "table" or type(items._refresh) ~= "function" then
            failures[#failures + 1] = "items_refresh_unavailable"
        else
            local ok, err = pcall(items._refresh, items)
            if not ok then failures[#failures + 1] = "refresh:" .. tostring(err) end
        end

        -- A normal-returning no-op refresh is not a postcondition. Every row
        -- whose exact ownership rollback succeeded must also be absent from the
        -- same interface cache the inventory UI reads.
        if type(items) == "table" and type(items.get_item_from_id) == "function" then
            for i = 1, #(removed or {}) do
                local backend_id = removed[i]
                local read_ok, item = pcall(items.get_item_from_id, items, backend_id)
                if not read_ok then
                    failures[#failures + 1] = "readback:" .. tostring(backend_id)
                        .. ":" .. tostring(item)
                elseif item ~= nil then
                    failures[#failures + 1] = "refresh_postcondition:"
                        .. tostring(backend_id)
                end
            end
        end
        return #failures == 0, table.concat(failures, ",")
    end

    local function _rollback_created(plan, created)
        local mirror = plan.items and plan.items._backend_mirror
        local failures, removed = {}, {}
        for i = #(created or {}), 1, -1 do
            local entry = created[i]
            local rolled_back, reason
            if type(entry.rollback) == "function" then
                local called, result, detail = pcall(entry.rollback)
                rolled_back = called and result == true
                reason = called and detail or result
            end
            if not rolled_back and type(contract.rollback_mirror_item) == "function" then
                local called, result, detail = pcall(contract.rollback_mirror_item,
                    mirror, entry.backend_id, entry.token)
                rolled_back = called and result == true
                reason = called and detail or result
            end
            if rolled_back then
                removed[#removed + 1] = entry.backend_id
            else
                failures[#failures + 1] = tostring(entry.backend_id) .. ":"
                    .. tostring(reason or "rollback_rejected")
            end
        end

        if #(created or {}) > 0 then
            local refreshed, refresh_error = _refresh_after_rollback(plan, removed)
            if not refreshed then
                failures[#failures + 1] = "refresh:" .. tostring(refresh_error)
            end
        end
        return #failures == 0, table.concat(failures, ",")
    end

    local function _remove_created(plan, created, unregister_required)
        local backend_ids = _backend_ids(created)
        if unregister_required then
            -- The batch owner returns the exact normalized table objects it
            -- published. Prove that each one is still current before invoking
            -- the id-based unregister API, so a later replacement is retained.
            for i = 1, #(created or {}) do
                local entry = created[i]
                local read_ok, current = pcall(
                    mod._cim_get_craft, entry.backend_id)
                if not read_ok then
                    return false, "persisted_read:" .. tostring(entry.backend_id)
                        .. ":" .. tostring(current)
                end
                if type(entry.persisted) ~= "table"
                        or current ~= entry.persisted then
                    return false, "persisted_identity_mismatch:"
                        .. tostring(entry.backend_id)
                end
            end
            local unregister_ok, unregistered, unregister_err = pcall(
                mod._cim_unregister_crafts_batch, backend_ids)
            if not unregister_ok or unregistered ~= true then
                -- Persistence still owns these exact rows. Retain their mirror
                -- counterparts rather than manufacturing saved/live drift.
                return false, "unregister:" .. tostring(unregister_ok
                    and (unregister_err or unregistered) or unregistered)
            end
            -- A normal return is not evidence that persistence changed. Keep
            -- every mirror row if the batch remover was a no-op or partial.
            for i = 1, #(created or {}) do
                local backend_id = created[i].backend_id
                local read_ok, current = pcall(mod._cim_get_craft, backend_id)
                if not read_ok then
                    return false, "persisted_readback:" .. tostring(backend_id)
                        .. ":" .. tostring(current)
                end
                if current ~= nil then
                    return false, "persisted_remove_postcondition:"
                        .. tostring(backend_id)
                end
            end
        end
        local rolled_back, rollback_error = _rollback_created(plan, created)
        if not rolled_back then return false, "mirror:" .. tostring(rollback_error) end
        return true
    end

    local function _restore(plan, created)
        local failures = {}
        for i = 1, #M.SLOT_ORDER do
            local slot_name = M.SLOT_ORDER[i]
            local ok, restored, err = pcall(mod._cim_write_exact_loadout_item,
                plan.career_name, slot_name,
                plan.snapshot.slots[slot_name], plan.snapshot.index)
            if not ok or restored == false then
                failures[#failures + 1] = slot_name .. ":"
                    .. tostring(ok and err or restored)
            end
        end
        local talent_ok, talent_result = pcall(
            plan.talents_interface.set_talents, plan.talents_interface,
            plan.career_name, _copy_array(plan.previous_talents), plan.snapshot.index)
        if not talent_ok or talent_result == false then
            failures[#failures + 1] = "talents:"
                .. tostring(talent_ok and talent_result or talent_result)
        end
        local final_ok, finalized, final_err = pcall(
            mod._cim_finalize_exact_loadout, plan.career_name, plan.snapshot.slots)
        if not final_ok or finalized == false then
            failures[#failures + 1] = "finalize:"
                .. tostring(final_ok and final_err or finalized)
        end
        -- A failed compensation may leave a loadout or live weapon unit still
        -- pointing at one of the new backend ids. Keep the persisted registry
        -- and mirror rows coherent in that case; deleting them would turn a
        -- reported rollback failure into a dangling loadout reference.
        if #failures > 0 then return false, table.concat(failures, ";") end
        local removed, remove_err = _remove_created(plan, created, true)
        if not removed then failures[#failures + 1] = tostring(remove_err) end
        if #failures > 0 then return false, table.concat(failures, ";") end
        return true
    end

    local function _rollback_result(message, plan, created)
        local restored, restore_err = _restore(plan, created)
        if not restored then
            return false, message .. "; rollback failed: " .. tostring(restore_err)
        end
        return false, message
    end

    local function _cleanup_result(message, plan, created, unregister_required)
        local removed, remove_err = _remove_created(
            plan, created, unregister_required == true)
        if not removed then
            return false, message .. "; cleanup failed: " .. tostring(remove_err)
        end
        return false, message
    end

    local function _failed_registration_result(message, plan, created)
        local occupied = {}
        for i = 1, #(created or {}) do
            local backend_id = created[i].backend_id
            local read_ok, current = pcall(mod._cim_get_craft, backend_id)
            if not read_ok then
                return false, message .. "; cleanup retained: persisted_read:"
                    .. tostring(backend_id) .. ":" .. tostring(current)
            end
            if current ~= nil then occupied[#occupied + 1] = backend_id end
        end
        -- The canonical batch owner is candidate-first, so a rejected write
        -- publishes nothing. Any observed row after rejection is uncertain or
        -- foreign state: never unregister it and never strand it from its live
        -- mirror counterpart.
        if #occupied > 0 then
            return false, message .. "; cleanup retained: persisted_occupied:"
                .. table.concat(occupied, ",")
        end
        return _cleanup_result(message, plan, created, false)
    end

    local function _apply(build)
        local plan, plan_err = _preflight(build)
        if not plan then return false, plan_err end

        local backend_ids, by_slot, batch, allocated, created = {}, {}, {}, {}, {}
        for i = 1, #M.SLOT_ORDER do
            local slot_name = M.SLOT_ORDER[i]
            local guid_ok, backend_id = pcall(guid)
            if not guid_ok or type(backend_id) ~= "string" or backend_id == ""
                    or allocated[backend_id] then
                return _cleanup_result("identity allocation failed", plan, created)
            end
            local persisted_ok, persisted = pcall(
                mod._cim_get_craft, backend_id)
            if not persisted_ok then
                return _cleanup_result("identity allocation ownership check failed: "
                    .. tostring(persisted), plan, created)
            end
            if persisted ~= nil then
                return _cleanup_result("identity allocation occupied: "
                    .. tostring(backend_id), plan, created)
            end
            allocated[backend_id] = true
            local inject_ok, injected, inject_err, token, rollback = pcall(inject_item,
                plan.records[slot_name], backend_id)
            if not inject_ok or not injected then
                return _cleanup_result("create " .. slot_name .. ": "
                    .. tostring(inject_ok and inject_err or injected), plan, created)
            end
            local creation = {
                backend_id = backend_id,
                item_key = plan.records[slot_name].item_key,
                token = token,
                rollback = rollback,
            }
            created[#created + 1] = creation
            local token_call, token_valid = pcall(
                contract.validate_mirror_ownership_token, token, backend_id,
                creation.item_key)
            if injected ~= backend_id or type(rollback) ~= "function"
                    or not token_call or token_valid ~= true then
                return _cleanup_result("create " .. slot_name
                    .. ": ownership proof rejected", plan, created)
            end
            backend_ids[#backend_ids + 1] = backend_id
            by_slot[slot_name] = backend_id
            batch[backend_id] = plan.records[slot_name]
        end
        local register_ok, registered, register_detail = pcall(
            mod._cim_register_crafts_batch, batch)
        if not register_ok or not registered then
            return _failed_registration_result("persist: "
                .. tostring(register_ok and register_detail or registered),
                plan, created)
        end
        if type(register_detail) ~= "table" then
            return _failed_registration_result(
                "persist: ownership proof unavailable", plan, created)
        end
        for i = 1, #created do
            local entry = created[i]
            local persisted_row = register_detail[entry.backend_id]
            local read_ok, current = pcall(
                mod._cim_get_craft, entry.backend_id)
            if type(persisted_row) ~= "table" or not read_ok
                    or current ~= persisted_row then
                return false, "persist: ownership proof rejected:"
                    .. tostring(entry.backend_id)
            end
            entry.persisted = persisted_row
        end

        for i = 1, #M.SLOT_ORDER do
            local slot_name = M.SLOT_ORDER[i]
            local call_ok, written, err = pcall(mod._cim_write_exact_loadout_item,
                plan.career_name, slot_name, by_slot[slot_name], plan.snapshot.index)
            if not call_ok or not written then
                return _rollback_result("equip " .. slot_name .. ": "
                    .. tostring(call_ok and err or written), plan, created)
            end
        end

        local talent_ok, talent_err = pcall(plan.talents_interface.set_talents,
            plan.talents_interface, plan.career_name, _copy_array(plan.talents),
            plan.snapshot.index)
        if not talent_ok or talent_err == false then
            return _rollback_result("talents: " .. tostring(talent_err),
                plan, created)
        end
        local read_ok, readback = pcall(plan.talents_interface.get_talents,
            plan.talents_interface, plan.career_name)
        if not read_ok or type(readback) ~= "table" then
            return _rollback_result("talent readback", plan, created)
        end
        for row = 1, 6 do
            if readback[row] ~= plan.talents[row] then
                return _rollback_result("talent readback row " .. tostring(row),
                    plan, created)
            end
        end

        local final_call_ok, final_ok, final_err = pcall(
            mod._cim_finalize_exact_loadout, plan.career_name, by_slot)
        if not final_call_ok or not final_ok then
            return _rollback_result("live equip: "
                .. tostring(final_call_ok and final_err or final_ok),
                plan, created)
        end
        if mod._cim_note_craft_bid then
            for i = 1, #backend_ids do pcall(mod._cim_note_craft_bid, backend_ids[i]) end
        end
        return true, {
            backend_ids = backend_ids,
            by_slot = by_slot,
            career_name = plan.career_name,
            build_name = build.name,
        }
    end

    local api = { preflight = _preflight, apply = _apply }
    mod._cim_ranalds_import = api
    return api
end

return M
