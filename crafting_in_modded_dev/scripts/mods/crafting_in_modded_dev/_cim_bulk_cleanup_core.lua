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
-- Weapon scope is independently proven from the live ItemMasterList row. An
-- unavailable definition is retained because its slot type cannot be proven.
function M.classify(forged, item_master)
    local weapon_set, non_weapon_set, unresolved_set = {}, {}, {}
    if type(forged) ~= "table" then forged = {} end
    if type(item_master) ~= "table" then item_master = {} end

    for backend_id, record in pairs(forged) do
        if type(backend_id) ~= "string" or type(record) ~= "table"
                or type(record.item_key) ~= "string" then
            unresolved_set[tostring(backend_id)] = true
        else
            local master = item_master[record.item_key]
            local slot_type = type(master) == "table" and master.slot_type or nil
            if slot_type == "melee" or slot_type == "ranged" then
                weapon_set[backend_id] = true
            elseif slot_type ~= nil then
                non_weapon_set[backend_id] = true
            else
                unresolved_set[backend_id] = true
            end
        end
    end

    return sorted_keys(weapon_set), sorted_keys(non_weapon_set), sorted_keys(unresolved_set)
end

function M.signature(ids)
    local copy = {}
    for i = 1, #(ids or {}) do copy[i] = tostring(ids[i]) end
    table.sort(copy)
    return tostring(#copy) .. ":" .. table.concat(copy, "\31")
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
