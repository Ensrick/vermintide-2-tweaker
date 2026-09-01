-- _lib_modded_realm_authority.lua -- exact modded-realm authority contract.
--
-- The raw `script_data["eac-untrusted"]` flag is authoritative while it is
-- true. `Development.application_parameter` retains the launch-time parameter
-- presence that originally populated the flag, so it remains authoritative if
-- another synchronous UI shim temporarily clears or falsely restores the raw
-- field. Modded Progression's balanced, positive integral depth is the final
-- nested-bracket authority. Consumers must not infer a realm from truthy
-- values, metatable fallbacks, a missing sibling, or a failing sibling call.
--
-- Canonical source: tools/shared_lib/_lib_modded_realm_authority.lua. Consumer
-- copies are synchronized by tools/shared_lib/sync-shared-libs.ps1; never edit
-- a copy locally.

local M = { VERSION = 1 }

local function valid_depth(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
        and value >= 0
        and value == math.floor(value)
end

local function capture(...)
    return select("#", ...), { ... }
end

function M.launch_parameter_is_modded(development)
    if type(development) ~= "table" then return false end
    local parameters = rawget(development, "application_parameter")
    if type(parameters) ~= "table" then return false end
    return rawget(parameters, "eac-untrusted") ~= nil
        or rawget(parameters, "eac_untrusted") ~= nil
end

function M.is_modded(script_data, modded_depth, development)
    if type(script_data) == "table" and rawget(script_data, "eac-untrusted") == true then
        return true
    end
    if M.launch_parameter_is_modded(development) then return true end
    return valid_depth(modded_depth) and modded_depth > 0
end

-- Resolve CIM's optional stable `mp` sibling surface. A raw true flag remains
-- sufficient when MP is absent; otherwise every malformed/throwing sibling
-- response is denied rather than guessed.
function M.sibling_is_modded(script_data, get_mod, development)
    if M.is_modded(script_data, 0, development) then return true end
    if type(get_mod) ~= "function" then return false end
    local got_provider, provider = pcall(get_mod, "mp")
    if not got_provider or type(provider) ~= "table" then return false end
    local query = rawget(provider, "is_modded_realm")
    if type(query) ~= "function" then return false end
    local called, result = pcall(query)
    return called and result == true
end

-- When MP is available, only MP may own a nested EAC-off bracket because its
-- depth is what survives raw-flag clearing by either VMF hook order. Older or
-- absent MP degrades to CIM's flag-only, throw-safe bracket.
function M.sibling_with_eac_off(script_data, get_mod, func, self, on_error, ...)
    if type(get_mod) == "function" then
        local got_provider, provider = pcall(get_mod, "mp")
        local bracket = got_provider and type(provider) == "table"
            and rawget(provider, "with_eac_off") or nil
        if type(bracket) == "function" then
            return bracket(func, self, ...)
        end
    end
    return M.with_eac_off(script_data, nil, func, self, on_error, ...)
end

-- #434's EAC-off bracket. The original flag and both counters are restored
-- before an optional error observer and before the original error is re-raised.
-- The explicit return count retains nil holes from vanilla methods.
function M.with_eac_off(script_data, state, func, self, on_error, ...)
    if type(script_data) ~= "table" or type(func) ~= "function" then
        return func(self, ...)
    end

    local tracks_depth = state ~= nil
    local eac_depth, modded_depth
    if tracks_depth then
        if type(state) ~= "table" then return func(self, ...) end
        eac_depth = rawget(state, "_mp_eac_depth")
        modded_depth = rawget(state, "_mp_modded_depth")
        if not valid_depth(eac_depth) or not valid_depth(modded_depth) then
            return func(self, ...)
        end
    end

    local original = rawget(script_data, "eac-untrusted")
    rawset(script_data, "eac-untrusted", nil)
    if tracks_depth then
        rawset(state, "_mp_eac_depth", eac_depth + 1)
        if original == true then rawset(state, "_mp_modded_depth", modded_depth + 1) end
    end

    local count, results = capture(pcall(func, self, ...))
    if tracks_depth then
        rawset(state, "_mp_eac_depth", eac_depth)
        rawset(state, "_mp_modded_depth", modded_depth)
    end
    rawset(script_data, "eac-untrusted", original)
    if not results[1] then
        if type(on_error) == "function" then pcall(on_error, results[2]) end
        error(results[2], 0)
    end
    return unpack(results, 2, count)
end

return M
