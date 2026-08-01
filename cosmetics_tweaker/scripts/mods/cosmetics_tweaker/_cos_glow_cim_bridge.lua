-- _cos_glow_cim_bridge.lua
--
-- Issue 48: bounded persistence bridge between Tweaker: Cosmetics and CIM.
-- Cosmetics remains the only glow renderer and the authoritative provider.
-- CIM stores one opaque backup blob on an exact synthetic item; it never
-- interprets or applies the payload.
--
-- This module is pure policy. It owns schema validation, exact-identity
-- matching, sibling selection, and guarded calls to CIM's public API.

local M = {}

M.SCHEMA = 1
M.PROVIDER = "cosmetics_tweaker.glow"

local function _finite(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function _clamp(value, lo, hi)
    if value < lo then return lo end
    if value > hi then return hi end
    return value
end

local function _component(value)
    if type(value) ~= "table"
        or not _finite(value.r)
        or not _finite(value.g)
        or not _finite(value.b)
        or not _finite(value.intensity) then
        return nil
    end
    return {
        r = _clamp(value.r, 0, 255),
        g = _clamp(value.g, 0, 255),
        b = _clamp(value.b, 0, 255),
        intensity = _clamp(value.intensity, 0, 5),
    }
end

-- Copy only the renderer-owned, bounded glow vocabulary. Unknown fields never
-- cross the mod boundary or enter CIM's durable save.
function M.sanitize_state(state)
    if type(state) ~= "table" then return nil end
    local result = {}
    if state.disabled == true then result.disabled = true end
    for _, key in ipairs({ "rune", "lower", "upper", "dots" }) do
        local value = _component(state[key])
        if value then result[key] = value end
    end
    if result.disabled ~= true
        and not result.rune and not result.lower
        and not result.upper and not result.dots then
        return nil
    end
    return result
end

function M.make_blob(identity, state)
    if type(identity) ~= "string" or identity == "" then return nil end
    local clean = M.sanitize_state(state)
    if not clean then return nil end
    return {
        schema = M.SCHEMA,
        provider = M.PROVIDER,
        identity = identity,
        state = clean,
    }
end

function M.state_from_record(record, identity)
    if type(record) ~= "table" or type(identity) ~= "string" then
        return nil, "missing"
    end
    local blob = record.custom_glow
    if type(blob) ~= "table" then return nil, "missing" end
    if blob.schema ~= M.SCHEMA or blob.provider ~= M.PROVIDER then
        return nil, "schema"
    end
    if blob.identity ~= identity then return nil, "identity" end
    local state = M.sanitize_state(blob.state)
    if not state then return nil, "state" end
    return state, "matched"
end

-- Development CIM takes precedence when both streams are installed. This
-- mirrors the monorepo's established optional-mod convention.
function M.resolve_cim(get_mod_fn)
    if type(get_mod_fn) ~= "function" then return nil end
    return get_mod_fn("cim_dev") or get_mod_fn("cim")
end

function M.read(cim, backend_id, identity)
    if type(cim) ~= "table" or type(cim._cim_get_craft) ~= "function" then
        return nil, "unavailable"
    end
    local ok, record = pcall(cim._cim_get_craft, backend_id)
    if not ok then return nil, "read-error" end
    return M.state_from_record(record, identity)
end

function M.write(cim, backend_id, identity, state)
    if type(cim) ~= "table" or type(cim._cim_set_custom_glow) ~= "function" then
        return false, "unavailable"
    end
    local blob = M.make_blob(identity, state)
    if not blob then return false, "invalid-state" end
    local ok, accepted = pcall(cim._cim_set_custom_glow, backend_id, blob)
    if not ok then return false, "write-error" end
    if accepted ~= true then return false, "not-cim-item" end
    return true, "written"
end

-- CIM has one backup slot per crafted instance. Restore must therefore clear
-- only the exact item+illusion blob being restored, never a newer blob authored
-- for another illusion on the same backend instance.
function M.clear(cim, backend_id, identity)
    local state, reason = M.read(cim, backend_id, identity)
    if not state then return false, reason end
    local ok, accepted = pcall(cim._cim_set_custom_glow, backend_id, nil)
    if not ok then return false, "write-error" end
    if accepted ~= true then return false, "not-cim-item" end
    return true, "cleared"
end

-- Registration is deliberately modeled as data so its retry/terminal behavior
-- can be verified without loading VMF. The caller owns `state` for one session.
function M.ensure_registration(state, cim, now, callback)
    if type(state) ~= "table" or type(callback) ~= "function" then
        return false, "invalid"
    end
    if state.complete then
        return state.registered_mod ~= nil, state.reason
    end
    now = _finite(now) and now or 0
    if state.next_at and now < state.next_at then return false, "pending" end

    state.attempts = (state.attempts or 0) + 1
    if not cim then
        if state.attempts < 3 then
            state.next_at = now + 1
            return false, "pending"
        end
        state.complete, state.reason = true, "absent"
        return false, state.reason
    end
    if type(cim._cim_register_restore_callback) ~= "function"
        or type(cim._cim_get_craft) ~= "function"
        or type(cim._cim_set_custom_glow) ~= "function" then
        state.complete, state.reason = true, "api-incomplete"
        return false, state.reason
    end

    local ok, accepted = pcall(cim._cim_register_restore_callback, callback)
    if not ok or accepted ~= true then
        if state.attempts < 3 then
            state.next_at = now + 1
            return false, "pending"
        end
        state.complete, state.reason = true, "register-failed"
        return false, state.reason
    end
    state.registered_mod, state.complete, state.reason = cim, true, "registered"
    return true, state.reason
end

function M.registration_status(state)
    if type(state) ~= "table" or not state.complete then return "pending" end
    return state.reason or (state.registered_mod and "registered" or "absent")
end

-- CIM's callback fires after each bounded restore pass. Rehydrate each realized
-- exact item once, then invoke the existing renderer reapply seam once.
function M.rebind_units(unit_to_backend_id, unit_context, restore_fn, reapply_fn)
    if type(restore_fn) ~= "function" then return 0 end
    local imported = 0
    for unit, backend_id in pairs(unit_to_backend_id or {}) do
        local context = unit_context and unit_context[unit]
        local state = restore_fn(backend_id, { skin = context and context.skin })
        if state then imported = imported + 1 end
    end
    if type(reapply_fn) == "function" then pcall(reapply_fn) end
    return imported
end

return M
