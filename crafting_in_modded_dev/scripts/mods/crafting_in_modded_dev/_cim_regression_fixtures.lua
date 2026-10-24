-- _cim_regression_fixtures.lua - pure fixtures and verdicts for /cim_regression_test (#1656).
--
-- Engine-free: no VMF, no hooks, no engine globals, no formatter calls on loc
-- strings. Each helper encodes the contract one regression check asserts, so the
-- check states the production policy instead of a stale copy of it, and the
-- offline proof can drive the same verdict with plain tables.
--
-- Owned by: crafting_in_modded_dev. Consumed via mod:dofile from
-- _cim_regression_checks.lua and _cim_regression_forge_surfaces.lua, and by
-- qa/lua/tests/test_cim_regression_harness_1656.lua.

local M = {}

-- #86 raised the per-item property ceiling from 2 to 10: the load-time trimmer
-- keeps at most 10 properties (`keep_limit`, _cim_forge_state_owner.lua) and the
-- Athanor refuses an eleventh distinct property (`MAX_DISTINCT_PROPERTIES`,
-- _cim_weave_loadout_owner.lua). The offline proof pins both literals to this.
M.ITEM_PROPERTY_CEILING = 10

-- A stored Adventure value that differs from 1.0 by less than this is the full
-- row: (0.3 - 0.1) / 0.2 is 0.9999999999999999 in doubles.
M.FULL_ROW_EPSILON = 1e-6

-- Stand-in `self` for a direct BackendInterfaceItemPlayfab.set_loadout_item
-- call. Vanilla reads self:get_all_backend_items()[item_id], asserts the row,
-- refuses rarity "magic" and writes through
-- self._backend_mirror:set_character_data (backend_interface_item_playfab.lua:
-- 635-670). The old fixture answered every field with a no-op function, so
-- get_all_backend_items() returned nil, vanilla raised at :640, and the
-- hook_safe capture that runs after vanilla returns never fired. These are
-- plain instance fields, so class hooks on get_all_backend_items are bypassed,
-- and every mirror write lands in `writes` instead of the real backend.
function M.loadout_interface_stub(backend_ids)
    local rows, writes = {}, {}
    for _, backend_id in ipairs(backend_ids) do
        rows[backend_id] = { backend_id = backend_id }
    end
    local stub = {
        _backend_mirror = {
            set_character_data = function(_, career_name, slot_name, item_id, _, loadout_index)
                writes[#writes + 1] = {
                    career_name = career_name, slot_name = slot_name,
                    item_id = item_id, loadout_index = loadout_index,
                }
            end,
        },
    }
    stub.get_all_backend_items = function() return rows end
    return stub, writes
end

-- Inventory rows that carry more than `ceiling` properties, as sorted
-- "backend_id(count)" strings, at most `max_listed` of them, plus the total.
function M.property_count_offenders(inventory, ceiling, max_listed)
    local offenders = {}
    for backend_id, item in pairs(inventory) do
        local properties = type(item) == "table" and item.properties
        if type(properties) == "table" then
            local count = 0
            for _ in pairs(properties) do count = count + 1 end
            if count > ceiling then
                offenders[#offenders + 1] = tostring(backend_id) .. "(" .. count .. ")"
            end
        end
    end
    table.sort(offenders)
    local total = #offenders
    while max_listed and #offenders > max_listed do
        offenders[#offenders] = nil
    end
    return offenders, total
end

-- #86 / #244 / #1141 scaling contract for one generic 5-bubble property.
-- An Adventure item stores a normalized value that buff_extension lerps across
-- the Adventure range (buff_extension.lua:224-230), so a count whose absolute
-- value sits below the range start has no storable value: the #244 write
-- clamps it to 0 and Apply/Craft refuse it (#1141). One fatigue_regen bubble
-- is 6% against the 10-30% Adventure range (weapon_properties.lua:114-119,
-- weave max 0.3 at weave_properties.lua:57-59), so it stores 0, not the
-- pre-#244 linear 0.2. The contract is therefore: the storable range ends at the cap,
-- the full row stores 1.0, every storable count reads back as itself, and the
-- value rises with every storable bubble. `api` carries the live owner's
-- value_for_bubbles, bubbles_for_value and representable_bubble_range.
-- Returns nil, or a reason naming the property.
function M.bubble_scaling_failure(key, cap, api)
    local low, high = api.representable_bubble_range(key)
    if type(low) ~= "number" or type(high) ~= "number" then
        return "'" .. key .. "': no storable bubble count (#1141 range is empty)"
    end
    if high ~= cap then
        return "'" .. key .. "': storable range ends at " .. tostring(high)
            .. " bubbles, expected the full " .. tostring(cap)
    end
    local full = api.value_for_bubbles(key, cap)
    if type(full) ~= "number" or math.abs(full - 1) > M.FULL_ROW_EPSILON then
        return "'" .. key .. "': " .. tostring(cap) .. " bubble value = "
            .. tostring(full) .. ", expected 1.0 (max)"
    end
    local previous
    for count = low, high do
        local value = api.value_for_bubbles(key, count)
        local back = api.bubbles_for_value(key, value)
        if back ~= count then
            return "'" .. key .. "': " .. count .. " bubbles stored " .. tostring(value)
                .. " and read back as " .. tostring(back)
        end
        if previous ~= nil and value <= previous then
            return "'" .. key .. "': " .. count .. " bubbles stored " .. tostring(value)
                .. ", not above " .. tostring(previous) .. " (scaling broken)"
        end
        previous = value
    end
    return nil
end

return M
