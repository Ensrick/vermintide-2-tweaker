-- Pure policy helpers for issue #277's destructive CIM craft cleanup.
-- No engine globals or mod state: this module is shared by runtime and the
-- offline Lua 5.1 regression suite.

local M = {}

local function sorted_keys(set)
    local out = {}
    for key in pairs(set) do out[#out + 1] = key end
    table.sort(out)
    return out
end

-- Exact ownership comes from forged[backend_id], never rarity or an id prefix.
-- Craft scope is independently proven from the live ItemMasterList row. An
-- unavailable definition is retained because its slot type cannot be proven.
--
-- #277: scope and identity both come from the issue 628 synthetic-item
-- contract. That contract owns the same melee/ranged/necklace/ring/trinket set
-- consumed by crafting and salvage, so accessories cannot drift out of this
-- cleanup surface again. A missing contract makes every row unresolved: the
-- failure mode for destructive cleanup is always retention.
function M.classify(forged, item_master, contract)
    local owned_set, retained_set, unresolved_set = {}, {}, {}
    if type(forged) ~= "table" then forged = {} end
    if type(item_master) ~= "table" then item_master = {} end
    local canonical_key = type(contract) == "table"
        and type(contract.canonical_item_key) == "function"
        and contract.canonical_item_key or nil
    local classify_record = canonical_key
        and type(contract.classify_owned_record) == "function"
        and contract.classify_owned_record or nil

    for backend_id, record in pairs(forged) do
        if not classify_record then
            unresolved_set[tostring(backend_id)] = true
        else
            local key_ok, item_key = pcall(canonical_key, record, backend_id)
            if not key_ok then item_key = nil end
            local master = type(item_key) == "string" and item_master[item_key] or nil
            local verdict = "unresolved"
            if type(item_key) == "string" and type(master) == "table" then
                local verdict_ok, result = pcall(classify_record,
                    backend_id, record, master)
                if verdict_ok then verdict = result end
            end
            if verdict == "owned" then
                owned_set[backend_id] = true
            elseif verdict == "retained" then
                retained_set[backend_id] = true
            else
                unresolved_set[tostring(backend_id)] = true
            end
        end
    end

    return sorted_keys(owned_set), sorted_keys(retained_set), sorted_keys(unresolved_set)
end

function M.signature(ids)
    local copy = {}
    for i = 1, #(ids or {}) do copy[i] = tostring(ids[i]) end
    table.sort(copy)
    return tostring(#copy) .. ":" .. table.concat(copy, "\31")
end

-- Confirmation must prove more than set membership. A record can retain the
-- same backend id while its canonical item, owner/schema, live slot/provider,
-- or mirror-vs-MIL deletion route changes. Those fields determine whether and
-- how it is safe to delete, so they are part of the preview fingerprint.
-- Cosmetic/property edits do not change cleanup identity and are deliberately
-- excluded. Returning nil makes callers refuse confirmation.
function M.snapshot_signature(ids, records, item_master, contract)
    if type(records) ~= "table" or type(item_master) ~= "table"
            or type(contract) ~= "table"
            or type(contract.canonical_item_key) ~= "function"
            or type(contract.provider_for) ~= "function" then
        return nil
    end

    local rows = {}
    for i = 1, #(ids or {}) do
        local backend_id = ids[i]
        local record = records[backend_id]
        local key_ok, item_key = pcall(contract.canonical_item_key, record, backend_id)
        if not key_ok then item_key = nil end
        local master = type(item_key) == "string" and item_master[item_key] or nil
        if type(backend_id) ~= "string" or type(record) ~= "table"
                or type(item_key) ~= "string" or type(master) ~= "table" then
            return nil
        end
        local provider_ok, provider = pcall(contract.provider_for, item_key, master)
        if not provider_ok then return nil end
        rows[#rows + 1] = table.concat({
            backend_id,
            tostring(record.owner),
            tostring(record.schema_version),
            item_key,
            tostring(master.slot_type),
            tostring(provider),
            tostring(record.via_mirror ~= false),
        }, "\30")
    end
    table.sort(rows)
    return tostring(#rows) .. ":" .. table.concat(rows, "\31")
end

function M.partition_equipped(ids, is_equipped)
    local deletable, blocked, uncertain = {}, {}, {}
    for i = 1, #(ids or {}) do
        local backend_id = ids[i]
        local ok, result = pcall(is_equipped, backend_id)
        if not ok or result == nil then
            uncertain[#uncertain + 1] = backend_id
        elseif result then
            blocked[#blocked + 1] = backend_id
        else
            deletable[#deletable + 1] = backend_id
        end
    end
    return deletable, blocked, uncertain
end

function M.clear_map_keys(map, ids)
    if type(map) ~= "table" then return false end
    local dirty = false
    for i = 1, #(ids or {}) do
        local backend_id = ids[i]
        if map[backend_id] ~= nil then
            map[backend_id] = nil
            dirty = true
        end
    end
    return dirty
end

-- Handles legacy flat, current indexed, and mixed/corrupt saved loadout shapes.
function M.clear_loadout_refs(loadout, ids)
    if type(loadout) ~= "table" then return false end
    local owned = {}
    for i = 1, #(ids or {}) do owned[ids[i]] = true end

    local dirty = false
    local function walk(node)
        for key, value in pairs(node) do
            if type(value) == "table" then
                walk(value)
            elseif owned[value] then
                node[key] = nil
                dirty = true
            end
        end
    end
    walk(loadout)
    return dirty
end

return M
