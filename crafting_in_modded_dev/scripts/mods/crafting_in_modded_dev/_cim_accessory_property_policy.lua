-- _cim_accessory_property_policy.lua — category-aware Athanor accessory slots.
--
-- Vanilla groups a property by key because each property normally belongs to
-- one category. CIM can expose the same key in all three accessory categories,
-- so every read/remove decision must also retain the category's ten-slot layer.
-- This pure module keeps that policy engine-free for offline regression tests.
--
-- Owned by: crafting_in_modded_dev.lua. Consumed via: mod:dofile and offline QA.

local M = {}
M.LAYER_SIZE = 10

local CATEGORY_LAYER = {
    offence_accessory = 1,
    defence_accessory = 2,
    utility_accessory = 3,
}

function M.layer_for_category(category)
    return CATEGORY_LAYER[category]
end

function M.slot_in_category(slot_index, category, layer_size)
    local layer = M.layer_for_category(category)
    if not layer
        or type(slot_index) ~= "number"
        or type(layer_size) ~= "number"
        or layer_size <= 0
    then
        return false
    end

    return math.ceil(slot_index / layer_size) == layer
end

function M.count_slots(slot_indices, category, layer_size)
    if type(slot_indices) ~= "table" then return 0 end

    local count = 0
    for _, slot_index in ipairs(slot_indices) do
        if M.slot_in_category(slot_index, category, layer_size) then
            count = count + 1
        end
    end
    return count
end

function M.last_slot(slot_indices, category, layer_size)
    if type(slot_indices) ~= "table" then return nil end

    local result
    for _, slot_index in ipairs(slot_indices) do
        if M.slot_in_category(slot_index, category, layer_size) then
            result = slot_index
        end
    end
    return result
end

function M.collect_property_slots(properties, category, layer_size)
    local result = {}
    if type(properties) ~= "table" or not M.layer_for_category(category) then
        return result
    end

    for property_key, slot_indices in pairs(properties) do
        if type(property_key) == "string" and type(slot_indices) == "table" then
            for _, slot_index in ipairs(slot_indices) do
                if M.slot_in_category(slot_index, category, layer_size) then
                    result[#result + 1] = {
                        property_key = property_key,
                        slot_index = slot_index,
                    }
                end
            end
        end
    end

    table.sort(result, function(a, b)
        if a.slot_index == b.slot_index then
            return a.property_key < b.property_key
        end
        return a.slot_index < b.slot_index
    end)
    return result
end

return M
