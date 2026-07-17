-- _cim_property_value_policy.lua — Athanor bubbles to Adventure property values.
--
-- The Weave picker presents an absolute fraction of its property maximum, while
-- ordinary inventory items store a normalized interpolation parameter. This
-- pure policy translates in both directions without VMF or engine globals.
-- Discrete and special properties remain owned by the caller.
--
-- Owned by: crafting_in_modded.lua. Consumed via: mod:dofile and offline QA.

local M = {}

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function two_number_range(value)
    return type(value) == "table"
        and type(value[1]) == "number"
        and type(value[2]) == "number"
        and value[3] == nil
end

function M.storage_for_bubbles(adventure_range, weave_max, count, cap)
    if not two_number_range(adventure_range)
        or type(weave_max) ~= "number"
        or weave_max == 0
        or type(count) ~= "number"
        or type(cap) ~= "number"
        or cap <= 0
    then
        return nil
    end

    local range_start, range_end = adventure_range[1], adventure_range[2]
    local span = range_end - range_start
    if span == 0 then return 0 end

    local bounded_count = clamp(count, 0, cap)
    local absolute_value = weave_max * bounded_count / cap
    return clamp((absolute_value - range_start) / span, 0, 1)
end

-- A stored zero is a valid low-end property, not absence: property presence is
-- represented by the containing table key.
function M.bubbles_for_storage(adventure_range, weave_max, stored_value, cap)
    if not two_number_range(adventure_range)
        or type(weave_max) ~= "number"
        or weave_max == 0
        or type(stored_value) ~= "number"
        or type(cap) ~= "number"
        or cap <= 0
    then
        return nil
    end

    local range_start, range_end = adventure_range[1], adventure_range[2]
    local normalized = clamp(stored_value, 0, 1)
    local absolute_value = range_start + (range_end - range_start) * normalized
    local raw_count = absolute_value / weave_max * cap
    return clamp(math.floor(raw_count + 0.5), 1, cap)
end

return M
