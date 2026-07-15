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

function M.canonical_family(item)
    if type(item) ~= "table" then return nil end
    if type(item.cim_acquisition_family) == "string" then
        return item.cim_acquisition_family
    end
    local data = type(item.data) == "table" and item.data or nil
    local key = M.canonical_key(item)
    if data and (data.cwv_definition == true or type(data.cwv_key) == "string") then
        return "cwv:" .. tostring(data.cwv_key or key)
    end
    if type(key) == "string" and key:sub(1, 4) == "cwv_" then
        return "cwv:" .. key
    end
    if data and type(data.cim_craft_family) == "string" then
        return "provider:" .. data.cim_craft_family
    end
    if data and type(data.item_type) == "string" then
        return "item_type:" .. tostring(data.slot_type or "?") .. ":" .. data.item_type
    end
    return key and ("key:" .. key) or nil
end

function M.inject(items, templates)
    if type(items) ~= "table" or type(templates) ~= "table" then return items end

    -- A real default-rarity row wins over CIM's synthetic selector. Modded
    -- crafted instances never count: vanilla can_craft_with excludes them,
    -- and this guard preserves the contract even if an upstream filter leaks.
    local real_families = {}
    for _, item in ipairs(items) do
        local rarity = _rarity(item)
        if not item.cim_acquisition_template and (rarity == nil or rarity == "default") then
            local family = M.canonical_family(item)
            if family then real_families[family] = true end
        end
    end

    -- Compact any stale/repeated synthetic rows in place. This makes injection
    -- idempotent even if a caller reuses the same filtered array.
    local synthetic_families = {}
    local write = 0
    for i = 1, #items do
        local item = items[i]
        local keep = true
        if item and item.cim_acquisition_template then
            local family = M.canonical_family(item)
            if not family or real_families[family] or synthetic_families[family] then
                keep = false
            else
                synthetic_families[family] = true
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
        local family = M.canonical_family(template)
        if key and family and not real_families[family] and not synthetic_families[family] then
            pending[#pending + 1] = { key = key, family = family, template = template }
            synthetic_families[family] = true
        end
    end
    table.sort(pending, function(a, b)
        if a.family ~= b.family then return a.family < b.family end
        return a.key < b.key
    end)
    for i = 1, #pending do
        items[#items + 1] = pending[i].template
    end
    return items
end

return M
