-- Pure acquisition-selector policy for the standard Craft Item grid.
-- Engine-free so the CIM/CWV ownership boundary can be exercised under Lua 5.1.

local M = {}

local function _rarity(item)
    if type(item) ~= "table" then return nil end
    return item.rarity
        or (type(item.CustomData) == "table" and item.CustomData.rarity)
        or (type(item.mod_data) == "table" and item.mod_data.rarity)
end

function M.canonical_key(item)
    if type(item) ~= "table" then return nil end

    -- New selectors carry an exact acquisition key. CWV definitions also
    -- carry cwv_key because their inherited .key/.name must remain the base
    -- weapon for vanilla preview/equip fallbacks.
    if type(item.cim_acquisition_key) == "string" then
        return item.cim_acquisition_key
    end
    local data = type(item.data) == "table" and item.data or nil
    if data and type(data.cwv_key) == "string" then
        return data.cwv_key
    end

    -- Compatibility with historical CWV blacksmith rows, whose inherited key
    -- named the base weapon but whose backend id retained the exact variant.
    local backend_id = item.backend_id or item.ItemInstanceId
    if type(backend_id) == "string" then
        local cwv_key = backend_id:match("^(cwv_.-)_%d%d%d$")
        if cwv_key then return cwv_key end
    end

    local key = item.key or (data and data.key) or item.ItemId
    return type(key) == "string" and key or nil
end

function M.inject(items, templates)
    if type(items) ~= "table" or type(templates) ~= "table" then return items end

    -- A real default-rarity row wins over CIM's synthetic selector. Modded
    -- crafted instances never count: vanilla can_craft_with excludes them,
    -- and this guard preserves the contract even if an upstream filter leaks.
    local real_keys = {}
    for _, item in ipairs(items) do
        local rarity = _rarity(item)
        if not item.cim_acquisition_template and (rarity == nil or rarity == "default") then
            local key = M.canonical_key(item)
            if key then real_keys[key] = true end
        end
    end

    -- Compact any stale/repeated synthetic rows in place. This makes injection
    -- idempotent even if a caller reuses the same filtered array.
    local synthetic_keys = {}
    local write = 0
    for i = 1, #items do
        local item = items[i]
        local keep = true
        if item and item.cim_acquisition_template then
            local key = M.canonical_key(item)
            if not key or real_keys[key] or synthetic_keys[key] then
                keep = false
            else
                synthetic_keys[key] = true
            end
        end
        if keep then
            write = write + 1
            items[write] = item
        end
    end
    for i = write + 1, #items do items[i] = nil end

    local pending = {}
    for _, template in pairs(templates) do
        local key = M.canonical_key(template)
        if key and not real_keys[key] and not synthetic_keys[key] then
            pending[#pending + 1] = { key = key, template = template }
            synthetic_keys[key] = true
        end
    end
    table.sort(pending, function(a, b) return a.key < b.key end)
    for i = 1, #pending do
        items[#items + 1] = pending[i].template
    end
    return items
end

return M
