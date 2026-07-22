-- Pure policy for the Numeric UI authoritative-ammo adapter (issue #249).
--
-- The runtime boundary reads current/max through InventoryExtension:ammo_status;
-- this module only validates and formats those engine-owned values. Keeping the
-- policy engine-free makes malformed/stale network-value behavior testable.

local M = {}

local function finite_nonnegative(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
        and value >= 0
end

function M.normalize(current_ammo, max_ammo)
    if not finite_nonnegative(current_ammo) then
        return nil, nil, "invalid_current"
    end
    if not finite_nonnegative(max_ammo) or max_ammo <= 0 then
        return nil, nil, "invalid_max"
    end

    return math.floor(current_ammo + 0.5), math.floor(max_ammo + 0.5), nil
end

function M.mode_key(mode)
    if mode == true or mode == 1 then
        return 1
    end
    if mode == 2 or mode == 3 then
        return mode
    end
    return nil
end

function M.format(mode, current_ammo, max_ammo)
    local key = M.mode_key(mode)
    if not key then
        return nil, nil
    end
    if key == 1 then
        return tostring(current_ammo), 1
    end
    if key == 2 then
        return tostring(current_ammo) .. "/" .. tostring(max_ammo), 2
    end
    return "", 3
end

return M
