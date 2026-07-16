-- Engine-boundary helpers for personal difficulty damage classification.
-- Dependencies are injected so the nil/live/deleted-unit contract is testable
-- without loading Stingray.

local M = {}

function M.new(api)
    assert(type(api) == "table", "personal handicap unit API must be a table")
    assert(type(api.unit_alive) == "function", "unit_alive dependency missing")
    assert(type(api.owner) == "function", "owner dependency missing")
    assert(type(api.breed) == "function", "breed dependency missing")
    assert(type(api.is_hostile_breed) == "function", "hostile-breed dependency missing")

    local access = {}

    function access.is_live(unit)
        return unit ~= nil and api.unit_alive(unit) == true
    end

    function access.owner(unit)
        if not access.is_live(unit) then return nil end
        return api.owner(unit)
    end

    function access.is_hostile_ai(unit)
        if not access.is_live(unit) then return false end
        return api.is_hostile_breed(api.breed(unit)) == true
    end

    return access
end

function M.scale_if_hostile(current_damage, factor, access, primary_unit,
        secondary_unit, scale_damage)
    -- Auto/off and at-or-below-host presets resolve to exactly 1. Avoid every
    -- attacker Unit/owner read in that overwhelmingly common neutral path.
    if factor == 1 then return current_damage end

    local hostile = access.is_hostile_ai(primary_unit)
    if not hostile then hostile = access.is_hostile_ai(secondary_unit) end
    if not hostile then return current_damage end
    return scale_damage(current_damage, factor)
end

return M
