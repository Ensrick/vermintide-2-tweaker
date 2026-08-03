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
M.LAYER_COUNT = 3

local CATEGORY_LAYER = {
    offence_accessory = 1,
    defence_accessory = 2,
    utility_accessory = 3,
}

local function layer_index(slot_index, layer_size)
    if type(slot_index) ~= "number"
        or type(layer_size) ~= "number"
        or layer_size <= 0
    then
        return nil
    end
    return math.ceil(slot_index / layer_size)
end

local function same_scope(a, b, layer_size)
    if layer_size == nil then return true end
    local a_layer = layer_index(a, layer_size)
    return a_layer ~= nil and a_layer == layer_index(b, layer_size)
end

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

    return layer_index(slot_index, layer_size) == layer
end

-- Store one property bubble while retaining the accessory layer dimension.
-- A nil layer_size preserves the native single-item/global-cap behavior.
-- An accessory layer_size applies the use cap independently inside the target
-- ten-slot range while still rejecting a slot occupied by any property.
function M.store_property_slot(properties, property_key, slot_index, cap, layer_size)
    if type(properties) ~= "table"
        or property_key == nil
        or type(slot_index) ~= "number"
        or type(cap) ~= "number"
        or cap <= 0
    then
        return nil, false, "invalid", 0
    end

    local target_layer
    if layer_size ~= nil then
        target_layer = layer_index(slot_index, layer_size)
        if not target_layer then return nil, false, "invalid", 0 end
    end

    local slots = properties[property_key]
    if type(slots) ~= "table" then
        slots = {}
        properties[property_key] = slots
    end

    local used_in_scope = 0
    for _, used_slot in ipairs(slots) do
        if not target_layer or same_scope(used_slot, slot_index, layer_size) then
            used_in_scope = used_in_scope + 1
        end
    end

    -- Slot occupancy remains global: two properties may never own the same
    -- authored grid slot, even when their property-use caps are layer-local.
    for _, property_slots in pairs(properties) do
        if type(property_slots) == "table" then
            for _, used_slot in ipairs(property_slots) do
                if used_slot == slot_index then
                    return slots, false, "occupied", used_in_scope
                end
            end
        end
    end

    if used_in_scope >= cap then
        return slots, false, "cap", used_in_scope
    end

    slots[#slots + 1] = slot_index
    return slots, true, "stored", used_in_scope + 1
end


function M.property_present_in_scope(slot_indices, target_slot, layer_size)
    if type(slot_indices) ~= "table" or type(target_slot) ~= "number" then
        return false
    end
    for _, slot_index in ipairs(slot_indices) do
        if same_scope(slot_index, target_slot, layer_size) then return true end
    end
    return false
end

function M.count_distinct_properties(properties, target_slot, layer_size)
    if type(properties) ~= "table" or type(target_slot) ~= "number" then
        return 0
    end
    local count = 0
    for _, slot_indices in pairs(properties) do
        if M.property_present_in_scope(slot_indices, target_slot, layer_size) then
            count = count + 1
        end
    end
    return count
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

-- #959 write-crash guard: zero-cost mastery table for the faked Athanor
-- economy. The array part holds exactly `cap` entries so every `#costs`
-- consumer still renders `cap` bubbles per row, while integer reads past the
-- array resolve to 0 instead of nil. Vanilla paints each occupied grid slot
-- with the GLOBAL per-key use count (`num_uses = #slot_indices` then
-- `mastery_costs[num_uses]`, hero_window_weave_properties.lua:1594-1637); in
-- the layered amulet that count legitimately reaches cap*LAYER_COUNT, and the
-- nil concat aborted the whole slot repaint mid-loop - the "second accessory
-- never fills, one list node consumed" symptom. Bounded: indices outside
-- 1..cap*layers still return nil so any ipairs walk terminates.
function M.build_zero_mastery_costs(cap, layers)
    if type(cap) ~= "number" or cap < 1 then cap = 1 end
    if type(layers) ~= "number" or layers < 1 then layers = M.LAYER_COUNT end
    local out = {}
    for i = 1, cap do out[i] = 0 end
    local limit = cap * layers
    return setmetatable(out, {
        __index = function(_, k)
            if type(k) == "number" and k >= 1 and k <= limit then return 0 end
            return nil
        end,
    })
end

-- #959 reopen bleed: seed one accessory layer's slot indices for
-- `property_key` into the shared amulet aggregate WITHOUT overwriting sibling
-- layers (the old `props_out[key] = indices` assignment dropped an earlier
-- accessory's entries whenever two accessories carried the same property, and
-- the next apply then wiped that property off the earlier accessory's item).
-- Appends `filled` sequential indices starting at `next_slot`, clamped to the
-- layer's authored range so an over-valued accessory can never spill indices
-- into its sibling's layer. Returns the advanced next_slot and the number of
-- indices dropped by the clamp; an optional log_fn receives one bounded
-- `[cim:959] seed clamp` line when the clamp actually dropped indices.
function M.seed_property_indices(props_out, property_key, next_slot, filled, layer_offset, layer_size, log_fn)
    if type(props_out) ~= "table" or property_key == nil
        or type(next_slot) ~= "number" or type(filled) ~= "number"
        or type(layer_offset) ~= "number" or type(layer_size) ~= "number"
        or layer_size <= 0
    then
        return next_slot, filled
    end

    local limit = layer_offset + layer_size
    local dropped = 0
    for _ = 1, filled do
        if next_slot > limit then
            dropped = dropped + 1
        else
            local slots = props_out[property_key]
            if type(slots) ~= "table" then
                slots = {}
                props_out[property_key] = slots
            end
            slots[#slots + 1] = next_slot
            next_slot = next_slot + 1
        end
    end
    if dropped > 0 and type(log_fn) == "function" then
        pcall(log_fn, "[cim:959] seed clamp key=%s layer=%d filled=%d dropped=%d",
            tostring(property_key), math.floor(layer_offset / layer_size) + 1,
            filled, dropped)
    end
    return next_slot, dropped
end

-- #959 evidence: one bounded `[cim:959] seed key=... layers=a,b,c` line per
-- property key per Athanor open, proving sibling accessories' entries all
-- survived the re-seed. Engine-free: the caller supplies printf.
function M.log_seed_census(props, layer_size, log_fn)
    if type(props) ~= "table" or type(log_fn) ~= "function" then return end
    for property_key, slot_indices in pairs(props) do
        pcall(log_fn, "[cim:959] seed key=%s layers=%d,%d,%d", tostring(property_key),
            M.count_slots(slot_indices, "offence_accessory", layer_size),
            M.count_slots(slot_indices, "defence_accessory", layer_size),
            M.count_slots(slot_indices, "utility_accessory", layer_size))
    end
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
