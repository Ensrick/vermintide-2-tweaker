-- _cim_owned_deletion.lua -- failure-contained local salvage/deletion.
--
-- Every owned id is validated before mutation. Owned and foreign salvage rows
-- share one transaction. Live inventory rows plus vanilla's two new-item
-- metadata stores are restored directly on failure; rollback never calls
-- PlayFabMirrorBase.add_item and therefore cannot run its normalization,
-- inventory-added, power, skin, new-marker, or autosave side effects.
--
-- Owned by: crafting_in_modded_dev.lua. Consumed via: mod:dofile.

local M = {
    MARKER = "cim_owned_deletion_transaction_v2",
}

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do
        out[copy(key, seen)] = copy(child, seen)
    end
    return out
end

local function restore_table(target, snapshot)
    for key in pairs(target) do target[key] = nil end
    for key, value in pairs(snapshot) do target[key] = copy(value) end
end

local function invoke(label, fn, ...)
    if type(fn) ~= "function" then return false, label .. " is unavailable" end
    local ok, result, detail = pcall(fn, ...)
    if not ok then return false, label .. " failed: " .. tostring(result) end
    return true, result, detail
end

local function snapshot_local_rows(state, deps, backend_ids)
    local inventory = deps.inventory_items
    local new_ids = deps.new_item_ids
    local by_career = deps.new_item_ids_by_career
    for i = 1, #backend_ids do
        local backend_id = backend_ids[i]
        state.local_rows[backend_id] = {
            present = rawget(inventory, backend_id) ~= nil,
            value = rawget(inventory, backend_id),
        }
        local root_value
        if type(new_ids) == "table" then
            root_value = rawget(new_ids, backend_id)
        end
        local markers = {
            root_present = type(new_ids) == "table"
                and rawget(new_ids, backend_id) ~= nil,
            root_value = root_value,
            nested = {},
        }
        if type(by_career) == "table" then
            for _, slots in pairs(by_career) do
                if type(slots) == "table" then
                    for _, ids in pairs(slots) do
                        if type(ids) == "table"
                                and rawget(ids, backend_id) ~= nil then
                            markers.nested[#markers.nested + 1] = {
                                map = ids,
                                value = rawget(ids, backend_id),
                            }
                        end
                    end
                end
            end
        end
        state.local_markers[backend_id] = markers
    end
end

local function clear_new_markers(deps, markers, backend_id)
    if type(deps.new_item_ids) == "table" then
        rawset(deps.new_item_ids, backend_id, nil)
    end
    for i = 1, #markers.nested do
        rawset(markers.nested[i].map, backend_id, nil)
    end
end

local function restore_local_rows(deps, state)
    for i = #state.local_attempts, 1, -1 do
        local backend_id = state.local_attempts[i]
        local row = state.local_rows[backend_id]
        if row.present then
            rawset(deps.inventory_items, backend_id, row.value)
        else
            rawset(deps.inventory_items, backend_id, nil)
        end
        local markers = state.local_markers[backend_id]
        if type(deps.new_item_ids) == "table" then
            if markers.root_present then
                rawset(deps.new_item_ids, backend_id, markers.root_value)
            else
                rawset(deps.new_item_ids, backend_id, nil)
            end
        end
        for j = 1, #markers.nested do
            local marker = markers.nested[j]
            rawset(marker.map, backend_id, marker.value)
        end
    end
end

local function rollback(deps, state)
    local errors = {}
    local function attempt(label, fn, ...)
        local ok, err = invoke(label, fn, ...)
        if not ok then errors[#errors + 1] = err end
    end

    if state.records_mutated then
        for backend_id, record in pairs(state.record_rows) do
            deps.records[backend_id] = record
        end
    end

    for i = #state.legacy_attempts, 1, -1 do
        local backend_id = state.legacy_attempts[i]
        attempt("legacy restore", deps.restore_legacy_item,
            backend_id, state.legacy_rows[backend_id])
    end
    restore_local_rows(deps, state)

    if state.overrides_mutated then
        local ok, err = pcall(restore_table, state.overrides, state.overrides_before)
        if not ok then
            errors[#errors + 1] = "override rollback failed: " .. tostring(err)
        else
            attempt("override rollback persistence",
                deps.persist_overrides, state.overrides)
        end
    end
    if state.loadouts_mutated then
        local ok, err = pcall(restore_table, deps.loadouts, state.loadouts_before)
        if not ok then
            errors[#errors + 1] = "loadout rollback failed: " .. tostring(err)
        else
            attempt("loadout rollback persistence", deps.persist_loadouts)
        end
    end
    if state.records_mutated then
        attempt("craft rollback persistence", deps.save)
    end
    return errors
end

local function fail(deps, state, message)
    local errors = rollback(deps, state)
    if #errors > 0 then
        message = message .. "; rollback incomplete: " .. table.concat(errors, " | ")
    end
    return 0, message
end

function M.execute(deps, owned_ids, foreign_ids)
    deps = type(deps) == "table" and deps or {}
    local records = deps.records
    local item_master = deps.item_master
    local contract = deps.contract
    if type(records) ~= "table" or type(item_master) ~= "table"
            or type(contract) ~= "table"
            or type(contract.canonical_item_key) ~= "function"
            or type(contract.classify_owned_record) ~= "function"
            or type(deps.inventory_items) ~= "table"
            or type(deps.loadouts) ~= "table"
            or type(deps.clear_loadout_refs) ~= "function"
            or type(deps.persist_loadouts) ~= "function"
            or type(deps.get_overrides) ~= "function"
            or type(deps.clear_override_refs) ~= "function"
            or type(deps.persist_overrides) ~= "function"
            or type(deps.save) ~= "function"
            or type(deps.invalidate) ~= "function" then
        return 0, "CIM local deletion transaction is unavailable"
    end

    local exact, foreign, local_ids, seen = {}, {}, {}, {}
    local state = {
        record_rows = {},
        legacy_rows = {},
        local_rows = {},
        local_markers = {},
        local_attempts = {},
        legacy_attempts = {},
        records_mutated = false,
        loadouts_mutated = false,
        overrides_mutated = false,
    }
    for i = 1, #(owned_ids or {}) do
        local backend_id = owned_ids[i]
        if type(backend_id) ~= "string" or backend_id == "" then
            return 0, "requested craft identity is unreadable"
        end
        if not seen[backend_id] then
            seen[backend_id] = true
            local record = records[backend_id]
            local key_ok, item_key = pcall(
                contract.canonical_item_key, record, backend_id)
            if not key_ok then item_key = nil end
            local master = type(item_key) == "string"
                and rawget(item_master, item_key) or nil
            local verdict_ok, verdict = pcall(
                contract.classify_owned_record, backend_id, record, master)
            if not verdict_ok or verdict ~= "owned" then
                return 0, "CIM ownership or craft scope changed before deletion"
            end
            exact[#exact + 1] = backend_id
            state.record_rows[backend_id] = record
            if record.via_mirror == false then
                if type(deps.build_legacy_entry) ~= "function"
                        or type(deps.remove_legacy_item) ~= "function"
                        or type(deps.restore_legacy_item) ~= "function" then
                    return 0, "legacy local deletion transaction is unavailable"
                end
                local entry_ok, entry = pcall(
                    deps.build_legacy_entry, record, backend_id)
                if not entry_ok or entry == nil then
                    return 0, "legacy deletion snapshot failed: " .. tostring(entry)
                end
                state.legacy_rows[backend_id] = entry
            else
                local_ids[#local_ids + 1] = backend_id
            end
        end
    end
    for i = 1, #(foreign_ids or {}) do
        local backend_id = foreign_ids[i]
        if type(backend_id) ~= "string" or backend_id == "" then
            return 0, "requested foreign identity is unreadable"
        end
        if not seen[backend_id] then
            seen[backend_id] = true
            foreign[#foreign + 1] = backend_id
            local_ids[#local_ids + 1] = backend_id
        end
    end
    if #exact == 0 and #foreign == 0 then return 0, nil end

    local snapshot_ok, snapshot_err = pcall(
        snapshot_local_rows, state, deps, local_ids)
    if not snapshot_ok then
        return 0, "local inventory snapshot failed: " .. tostring(snapshot_err)
    end

    if #exact > 0 then
        local overrides_ok, overrides = pcall(deps.get_overrides)
        if not overrides_ok then
            return 0, "override snapshot failed: " .. tostring(overrides)
        end
        if type(overrides) ~= "table" then overrides = {} end
        state.overrides = overrides
        local refs_ok, loadouts_before, overrides_before = pcall(
            function() return copy(deps.loadouts), copy(overrides) end)
        if not refs_ok then
            return 0, "reference snapshot failed: " .. tostring(loadouts_before)
        end
        state.loadouts_before = loadouts_before
        state.overrides_before = overrides_before

        state.loadouts_mutated = true
        local ok, err = invoke(
            "loadout cleanup", deps.clear_loadout_refs, deps.loadouts, exact)
        if not ok then return fail(deps, state, err) end

        state.overrides_mutated = true
        ok, err = invoke(
            "override cleanup", deps.clear_override_refs, overrides, exact)
        if not ok then return fail(deps, state, err) end
    end

    local remove_local_row = deps.remove_local_row
        or function(inventory, backend_id)
            rawset(inventory, backend_id, nil)
        end
    for i = 1, #local_ids do
        local backend_id = local_ids[i]
        state.local_attempts[#state.local_attempts + 1] = backend_id
        local ok, err = invoke(
            "local inventory remove " .. backend_id,
            remove_local_row, deps.inventory_items, backend_id)
        if not ok then return fail(deps, state, err) end
        clear_new_markers(
            deps, state.local_markers[backend_id], backend_id)
    end

    for i = 1, #exact do
        local backend_id = exact[i]
        local record = state.record_rows[backend_id]
        if record.via_mirror == false then
            state.legacy_attempts[#state.legacy_attempts + 1] = backend_id
            local ok, err = invoke(
                "legacy remove " .. backend_id,
                deps.remove_legacy_item, backend_id)
            if not ok then return fail(deps, state, err) end
        end
    end

    if #exact > 0 then
        state.records_mutated = true
        for i = 1, #exact do records[exact[i]] = nil end

        local ok, err = invoke("loadout persistence", deps.persist_loadouts)
        if not ok then return fail(deps, state, err) end
        ok, err = invoke(
            "override persistence", deps.persist_overrides, state.overrides)
        if not ok then return fail(deps, state, err) end
        ok, err = invoke("craft persistence", deps.save)
        if not ok then return fail(deps, state, err) end
    end
    -- Success-only presentation invalidation. Runtime supplies
    -- BackendManagerPlayFab.dirtify_interfaces, whose implementations only
    -- set interface dirty flags. Never call BackendInterfaceItemPlayfab._refresh
    -- here or from rollback: it normalizes skins, unmarks new/favorite ids, and
    -- autosaves before the transaction can restore exact state.
    local ok, err = invoke("inventory invalidation", deps.invalidate)
    if not ok then return fail(deps, state, err) end
    return #exact, nil
end

return M
