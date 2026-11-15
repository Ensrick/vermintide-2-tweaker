--[[
#1654 / #277 (WP-CIM-06): pure checks for the crafted-item store.

VMF keeps every mod's settings in one table and serializes it as a whole; a
table with mixed array and map keys makes that save fail for every mod
(Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/settings.lua:5-6,
19-33). The forge state owner validates the store with this module before it
calls mod:set, so a bad record is refused instead of written.

  M.is_serializable(value)        number, string, boolean; a table only when all
                                  keys are strings or all keys are the integers
                                  1..n, checked recursively
  M.validate_store(store)         true, or false, backend_id, path
  M.merge_missing(target, source) new table + count of ids added from source;
                                  never overwrites an id, never mutates inputs
  M.count(store)                  number of ids
]]

local M = {}

local function sorted_keys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        if ta == "number" or ta == "string" then return a < b end
        return tostring(a) < tostring(b)
    end)
    return keys
end

-- Returns true, or false and the path of the first offending value.
local function check(value, path, seen)
    local kind = type(value)
    if kind == "string" or kind == "boolean" or kind == "number" then return true end
    if kind ~= "table" then return false, path end
    if seen[value] then return false, path end
    seen[value] = true
    local strings, integers, total = 0, 0, 0
    for k in pairs(value) do
        total = total + 1
        if type(k) == "string" then
            strings = strings + 1
        elseif type(k) == "number" and k >= 1 and k % 1 == 0 then
            integers = integers + 1
        else
            seen[value] = nil
            return false, path .. "[" .. tostring(k) .. "]"
        end
    end
    if strings > 0 and integers > 0 then
        seen[value] = nil
        return false, path
    end
    if integers > 0 then
        for i = 1, total do
            if value[i] == nil then
                seen[value] = nil
                return false, path
            end
        end
    end
    for _, k in ipairs(sorted_keys(value)) do
        local ok, bad = check(value[k], path .. "." .. tostring(k), seen)
        if not ok then
            seen[value] = nil
            return false, bad
        end
    end
    seen[value] = nil
    return true
end

function M.is_serializable(value)
    return (check(value, "", {}))
end

function M.validate_store(store)
    if type(store) ~= "table" then return false, nil, "store" end
    for _, backend_id in ipairs(sorted_keys(store)) do
        if type(backend_id) ~= "string" then
            return false, backend_id, "backend_id"
        end
        local ok, path = check(store[backend_id], "", {})
        if not ok then
            return false, backend_id, path ~= "" and path:sub(2) or "record"
        end
    end
    return true
end

function M.merge_missing(target, source)
    local merged, added = {}, 0
    if type(target) == "table" then
        for backend_id, record in pairs(target) do merged[backend_id] = record end
    end
    if type(source) == "table" then
        for backend_id, record in pairs(source) do
            if merged[backend_id] == nil then
                merged[backend_id] = record
                added = added + 1
            end
        end
    end
    return merged, added
end

function M.count(store)
    local n = 0
    if type(store) == "table" then
        for _ in pairs(store) do n = n + 1 end
    end
    return n
end

return M
