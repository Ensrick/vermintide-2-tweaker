-- _lib_resource_residency.lua -- strict resource preflight helpers.
--
-- Issue #749: borrowed preview/renderer worlds can crash below Lua when asked
-- to bind a texture/material/shading environment that is not resident in that
-- render scope. These helpers are deliberately fail-closed: absence of the
-- engine proof API, malformed data, or a throwing probe all mean "do not make
-- the native C call".

local M = {
    VERSION = 1,
}

local function log_once(logger, reason, resource_type, path, slot, context)
    if type(logger) == "function" then
        pcall(logger, reason, resource_type, path, slot, context)
    end
end

function M.live_unit(unit, unit_api, logger, context)
    if unit == nil then
        log_once(logger, "missing_unit", "unit", nil, nil, context)
        return false, "missing_unit"
    end
    if type(unit) ~= "userdata" then
        log_once(logger, "malformed_unit", "unit", tostring(unit), nil, context)
        return false, "malformed_unit"
    end
    if type(unit_api) ~= "table" or type(unit_api.alive) ~= "function" then
        log_once(logger, "missing_unit_api", "unit", tostring(unit), nil, context)
        return false, "missing_unit_api"
    end

    local ok, alive = pcall(unit_api.alive, unit)
    if not ok then
        log_once(logger, "unit_alive_error", "unit", tostring(unit), nil, context)
        return false, "unit_alive_error"
    end
    if alive ~= true then
        log_once(logger, "dead_unit", "unit", tostring(unit), nil, context)
        return false, "dead_unit"
    end

    return true, "resident"
end

function M.texture_bind_resident(slot, texture, application, logger, context)
    if type(slot) ~= "string" or slot == "" then
        log_once(logger, "malformed_slot", "texture", texture, slot, context)
        return false, "malformed_slot"
    end
    if type(texture) ~= "string" or texture == "" then
        log_once(logger, "malformed_path", "texture", texture, slot, context)
        return false, "malformed_path"
    end

    local can_get = application and application.can_get
    if type(can_get) ~= "function" then
        log_once(logger, "missing_can_get", "texture", texture, slot, context)
        return false, "missing_can_get"
    end

    local ok, resident = pcall(can_get, "texture", texture)
    if not ok then
        log_once(logger, "can_get_error", "texture", texture, slot, context)
        return false, "can_get_error"
    end
    if resident ~= true then
        log_once(logger, "not_resident", "texture", texture, slot, context)
        return false, "not_resident"
    end

    return true, "resident"
end

return M
