-- Pure property refresh policy for the held-Tab item cache (#245).
local Policy = { INTERVAL = 0.25, MAX_LOGS = 16 }

local function clone(values)
    if type(values) ~= "table" then return nil end
    local out = {}
    for key, value in pairs(values) do out[key] = value end
    return out
end

local function instance_id(item)
    return item and (item.backend_id or item.backendId or item.id)
end

function Policy.fingerprint(values)
    if type(values) ~= "table" then return "-" end
    local parts = {}
    for key, value in pairs(values) do
        parts[#parts + 1] = tostring(key) .. "=" .. tostring(value)
    end
    table.sort(parts)
    return table.concat(parts, ";")
end

function Policy.refresh(cached_item, live_item)
    if type(cached_item) ~= "table" or type(live_item) ~= "table" then
        return false, nil, "missing_item"
    end
    local cached_key = cached_item.key or cached_item.ItemId
        or cached_item.data and (cached_item.data.key or cached_item.data.name)
    local live_key = live_item.key or live_item.ItemId
        or live_item.data and (live_item.data.key or live_item.data.name)
    if not cached_key or cached_key ~= live_key then
        return false, nil, "identity_mismatch"
    end
    local cached_id, live_id = instance_id(cached_item), instance_id(live_item)
    if cached_id ~= nil and live_id ~= nil and tostring(cached_id) ~= tostring(live_id) then
        return false, nil, "instance_mismatch"
    end
    if Policy.fingerprint(cached_item.properties) == Policy.fingerprint(live_item.properties) then
        return false, nil, "unchanged"
    end
    return true, clone(live_item.properties), "changed"
end

return Policy
