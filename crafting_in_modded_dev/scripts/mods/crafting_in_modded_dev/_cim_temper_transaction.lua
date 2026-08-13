-- Engine-free policy for the Athanor "Temper Item" transaction.
-- The weave bubble grid is a draft. Owned items change only at Apply; a
-- default-rarity blacksmith template is immutable and therefore uses Craft.

local M = {}

local function copy_map(value)
    local result = {}
    if type(value) == "table" then
        for key, child in pairs(value) do result[key] = child end
    end
    return result
end

local function copy_array(value)
    local result = {}
    if type(value) == "table" then
        for index = 1, #value do result[index] = value[index] end
    end
    return result
end

local function same_map(left, right)
    left = type(left) == "table" and left or {}
    right = type(right) == "table" and right or {}
    for key, value in pairs(left) do
        if right[key] ~= value then return false end
    end
    for key, value in pairs(right) do
        if left[key] ~= value then return false end
    end
    return true
end

local function same_array(left, right)
    left = type(left) == "table" and left or {}
    right = type(right) == "table" and right or {}
    if #left ~= #right then return false end
    for index = 1, #left do
        if left[index] ~= right[index] then return false end
    end
    return true
end

local function item_rarity(item)
    if type(item) ~= "table" then return nil end
    if item.rarity ~= nil then return item.rarity end
    if type(item.CustomData) == "table" and item.CustomData.rarity ~= nil then
        return item.CustomData.rarity
    end
    if type(item.data) == "table" and item.data.rarity ~= nil then
        return item.data.rarity
    end
    return nil
end

function M.is_blacksmith_template(item, backend_id)
    if item_rarity(item) == "default" then return true end
    backend_id = backend_id or (type(item) == "table" and item.backend_id)
    return type(backend_id) == "string"
        and backend_id:sub(1, 13) == "cim_template_"
end

function M.action_for(item, backend_id)
    return M.is_blacksmith_template(item, backend_id) and "craft" or "apply"
end

function M.payload_from_grid(grid, strip_property, property_value)
    grid = type(grid) == "table" and grid or {}
    assert(type(strip_property) == "function", "strip_property callback required")
    assert(type(property_value) == "function", "property_value callback required")

    local properties = {}
    for weave_key, slots in pairs(grid.properties or {}) do
        if type(slots) == "table" then
            local key = strip_property(weave_key)
            if type(key) == "string" and key ~= "" then
                properties[key] = property_value(weave_key, #slots)
            end
        end
    end

    -- `pairs` is unordered. Sorting makes a future multi-trait draft stable.
    local trait_entries = {}
    for weave_key, slot_index in pairs(grid.traits or {}) do
        trait_entries[#trait_entries + 1] = {
            key = tostring(weave_key):gsub("^weave_", ""),
            slot = tonumber(slot_index) or math.huge,
        }
    end
    table.sort(trait_entries, function(left, right)
        if left.slot == right.slot then return left.key < right.key end
        return left.slot < right.slot
    end)
    local traits = {}
    for index = 1, #trait_entries do traits[index] = trait_entries[index].key end

    return { properties = properties, traits = traits }
end

function M.copy_payload(payload)
    payload = type(payload) == "table" and payload or {}
    return {
        properties = copy_map(payload.properties),
        traits = copy_array(payload.traits),
    }
end

function M.is_dirty(item, payload)
    if type(item) ~= "table" then return false end
    payload = type(payload) == "table" and payload or {}
    return not same_map(item.properties, payload.properties)
        or not same_array(item.traits, payload.traits)
end

function M.apply_to_item(item, payload, json_encode)
    if type(item) ~= "table" then return false, "item" end
    if M.is_blacksmith_template(item) then return false, "template" end
    local normalized = M.copy_payload(payload)
    if not M.is_dirty(item, normalized) then return true, false end

    item.properties = normalized.properties
    item.traits = normalized.traits
    if type(item.CustomData) == "table" and type(json_encode) == "function" then
        item.CustomData.properties = json_encode(normalized.properties)
        item.CustomData.traits = json_encode(normalized.traits)
    end
    return true, true
end

return M
