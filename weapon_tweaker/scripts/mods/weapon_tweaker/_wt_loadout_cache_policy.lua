-- Pure row-scoped loadout-cache policy.
--
-- The backend owns engine discovery and hooks. This module owns only the
-- session-cache shape and deterministic row lifecycle used by those hooks:
--
--   cache[career_name][loadout_index][slot_name] = backend_id
--
-- It has no game globals and is therefore directly exercisable under Lua 5.1.

local M = {}

M.SCHEMA_VERSION = 2

local function valid_index(value)
    return type(value) == "number" and value >= 1 and value % 1 == 0
end

local function valid_cache_shape(cache)
    if type(cache) ~= "table" then return false end

    for career_name, rows in pairs(cache) do
        if type(career_name) ~= "string" or type(rows) ~= "table" then
            return false
        end

        for loadout_index, slots in pairs(rows) do
            -- Reject the legacy career -> slot -> id shape even if a caller
            -- accidentally supplies the current schema marker with it.
            if not valid_index(loadout_index) or type(slots) ~= "table" then
                return false
            end

            for slot_name, backend_id in pairs(slots) do
                if type(slot_name) ~= "string" or backend_id == nil
                        or type(backend_id) == "table" then
                    return false
                end
            end
        end
    end

    return true
end

local function deep_copy(value, seen)
    if type(value) ~= "table" then return value end

    seen = seen or {}
    if seen[value] then return seen[value] end

    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[deep_copy(key, seen)] = deep_copy(child, seen)
    end
    return copy
end

local function prune(cache, career_name, loadout_index)
    local rows = type(cache) == "table" and cache[career_name]
    if type(rows) ~= "table" then return end

    local slots = rows[loadout_index]
    if type(slots) == "table" and next(slots) == nil then
        rows[loadout_index] = nil
    end
    if next(rows) == nil then
        cache[career_name] = nil
    end
end

-- Return a cache safe for SCHEMA_VERSION consumers. Legacy rowless state is
-- deliberately discarded: it cannot be assigned to a saved row without
-- guessing, and guessing recreates the cross-row override fixed by #1190.
function M.ensure_schema(cache, schema_version)
    if schema_version ~= M.SCHEMA_VERSION or not valid_cache_shape(cache) then
        return {}, M.SCHEMA_VERSION, true
    end
    return cache, M.SCHEMA_VERSION, false
end

function M.set(cache, career_name, loadout_index, slot_name, backend_id)
    if type(cache) ~= "table" or type(career_name) ~= "string"
            or not valid_index(loadout_index) or type(slot_name) ~= "string" then
        return false
    end
    if backend_id == nil then
        return M.clear(cache, career_name, loadout_index, slot_name)
    end

    local rows = cache[career_name]
    if type(rows) ~= "table" then
        rows = {}
        cache[career_name] = rows
    end
    local slots = rows[loadout_index]
    if type(slots) ~= "table" then
        slots = {}
        rows[loadout_index] = slots
    end
    slots[slot_name] = backend_id
    return true
end

function M.get(cache, career_name, loadout_index, slot_name)
    if type(cache) ~= "table" or not valid_index(loadout_index) then return nil end
    local rows = cache[career_name]
    local slots = type(rows) == "table" and rows[loadout_index]
    return type(slots) == "table" and slots[slot_name] or nil
end

function M.clear(cache, career_name, loadout_index, slot_name)
    if type(cache) ~= "table" or not valid_index(loadout_index) then return false end
    local rows = cache[career_name]
    local slots = type(rows) == "table" and rows[loadout_index]
    if type(slots) ~= "table" or slots[slot_name] == nil then return false end

    slots[slot_name] = nil
    prune(cache, career_name, loadout_index)
    return true
end

function M.clear_all(cache)
    if type(cache) ~= "table" then return false end
    local changed = next(cache) ~= nil
    for career_name in pairs(cache) do
        cache[career_name] = nil
    end
    return changed
end

-- Vanilla and GUT append a clone of the selected row. Cache only the overlay
-- part here; the underlying loadout owner clones the ordinary slot values.
function M.clone_added_row(cache, career_name, source_index, new_index)
    if type(cache) ~= "table" or type(career_name) ~= "string"
            or not valid_index(source_index) or not valid_index(new_index) then
        return false
    end

    local rows = cache[career_name]
    local source = type(rows) == "table" and rows[source_index]
    if type(source) ~= "table" or next(source) == nil then
        if type(rows) == "table" then
            rows[new_index] = nil
            prune(cache, career_name, new_index)
        end
        return false
    end

    rows[new_index] = deep_copy(source)
    return true
end

-- Call only after the underlying owner confirms a successful deletion. The
-- explicit old row count makes shifting deterministic even when cached rows
-- are sparse (for example, only rows 1 and 3 contain cross-career weapons).
function M.delete_row(cache, career_name, deleted_index, old_count)
    if type(cache) ~= "table" or type(career_name) ~= "string"
            or not valid_index(deleted_index) or not valid_index(old_count)
            or deleted_index > old_count then
        return false
    end

    local rows = cache[career_name]
    if type(rows) ~= "table" then return false end

    local changed = rows[deleted_index] ~= nil
    for index = deleted_index, old_count - 1 do
        if rows[index] ~= rows[index + 1] then changed = true end
        rows[index] = rows[index + 1]
    end
    if rows[old_count] ~= nil then changed = true end
    rows[old_count] = nil

    if next(rows) == nil then cache[career_name] = nil end
    return changed
end

-- Overlay cached rows onto a deep copy of the engine/GUT row array. The
-- source rows and cache are never mutated, and cache rows outside the live
-- loadout array are ignored. `accept` may reject a stale backend id.
function M.overlay_rows(loadouts, cache, career_name, accept)
    local output = deep_copy(loadouts)
    if type(output) ~= "table" or type(cache) ~= "table" then return output end

    local rows = cache[career_name]
    if type(rows) ~= "table" then return output end

    for loadout_index, slots in pairs(rows) do
        local output_row = output[loadout_index]
        if type(output_row) == "table" and type(slots) == "table" then
            for slot_name, backend_id in pairs(slots) do
                if not accept or accept(backend_id, career_name, loadout_index, slot_name) then
                    output_row[slot_name] = backend_id
                end
            end
        end
    end

    return output
end

return M
