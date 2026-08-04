-- _gt_diag_disconnect_failure.lua -- issue #753 service-loss diagnostics.
--
-- Observes three source-backed seams without changing their behavior:
-- StateTitleScreenInitNetwork's Steam availability check,
-- BackendManagerPlayFab's disconnected transition, and NetworkClient's P2P
-- failure transition.  Emission is transition-only and always uses engine
-- printf so a normal frame loop cannot spam the log and VMF logging may be off.
--
-- Owned by: general_tweaker_dev.lua. Consumed via: manifest mod:dofile.

local mod = get_mod("gt_dev")
local Policy = mod:dofile("scripts/mods/general_tweaker_dev/_gt_disconnect_failure_core")
local engine_printf = rawget(_G, "printf")
local unpack_fn = unpack

local function _pack(...)
    return { n = select("#", ...), ... }
end

local function _emit(fmt, ...)
    if type(engine_printf) == "function" then
        pcall(engine_printf, "[gt:753] " .. fmt, ...)
    end
end

local function _steam_connected()
    local steam = rawget(_G, "Steam")
    local connected = steam and steam.connected
    if type(connected) ~= "function" then
        return nil
    end

    local ok, value = pcall(connected)
    if not ok or type(value) ~= "boolean" then
        return nil
    end

    return value
end

local function _backend_disconnected(fallback)
    local manager = fallback
    local managers = rawget(_G, "Managers")
    if manager == nil and type(managers) == "table" then
        manager = managers.backend
    end
    if type(manager) ~= "table" then
        return nil
    end

    local value = rawget(manager, "_is_disconnected")
    if type(value) == "boolean" then
        return value
    end

    local getter = manager.is_disconnected
    if type(getter) ~= "function" then
        return nil
    end
    local ok, result = pcall(getter, manager)
    return ok and type(result) == "boolean" and result or nil
end

local function _snapshot_class(network_failed, backend)
    local steam_connected = _steam_connected()
    local backend_disconnected = _backend_disconnected(backend)
    return steam_connected,
        backend_disconnected,
        Policy.classify(steam_connected, backend_disconnected, network_failed)
end

local steam_state = setmetatable({}, { __mode = "k" })
local backend_reason = setmetatable({}, { __mode = "k" })

-- Hook preflight: whole-mod grep found no existing gt_dev registration on
-- StateTitleScreenInitNetwork._connected_to_steam (2026-07-19).
mod:hook("StateTitleScreenInitNetwork", "_connected_to_steam", function(func, self)
    local connected = func(self)
    local previous = steam_state[self]
    steam_state[self] = connected

    if Policy.steam_transition(previous, connected) then
        local backend_disconnected = _backend_disconnected()
        _emit(
            "edge=steam_check steam_connected=%s backend_disconnected=%s observed=%s",
            Policy.bool_label(connected),
            Policy.bool_label(backend_disconnected),
            Policy.classify(connected, backend_disconnected, false)
        )
    end

    return connected
end)

-- Hook preflight: whole-mod grep found no existing gt_dev registration on
-- BackendManagerPlayFab._update_error_handling (2026-07-19).
mod:hook("BackendManagerPlayFab", "_update_error_handling", function(func, self, dt)
    local previous = _backend_disconnected(self)
    local queued = rawget(self, "_errors")
    local queued_head = type(queued) == "table" and rawget(queued, 1) or nil
    -- Match vanilla's exact promotion condition. While a popup is active,
    -- `_errors[1]` belongs to a later queued failure; retaining it here would
    -- misattribute the popup whose dismissal actually flips _is_disconnected.
    if rawget(self, "_error_dialog") == nil
        and previous ~= true
        and type(queued_head) == "table"
        and queued_head.reason ~= nil then
        backend_reason[self] = tostring(queued_head.reason)
    end

    local results = _pack(func(self, dt))
    local current = _backend_disconnected(self)

    if Policy.backend_disconnected_transition(previous, current) then
        local steam_connected, backend_disconnected, observed = _snapshot_class(false, self)
        _emit(
            "edge=playfab_disconnect steam_connected=%s backend_disconnected=%s last_reason=%s observed=%s",
            Policy.bool_label(steam_connected),
            Policy.bool_label(backend_disconnected),
            tostring(backend_reason[self] or "unknown"),
            observed
        )
    end

    return unpack_fn(results, 1, results.n)
end)

-- Hook preflight: whole-mod grep found no existing gt_dev registration on
-- NetworkClient.update (2026-07-19).  This enclosing seam observes both the
-- channel-disconnected branch in _update_connections (network_client.lua:332-
-- 345) and the connecting timeout branch (network_client.lua:372-382).
mod:hook("NetworkClient", "update", function(func, self, dt, t)
    local before_reason = rawget(self, "fail_reason")
    local before_channel = rawget(self, "_server_channel_state")
    local results = _pack(func(self, dt, t))
    local after_reason = rawget(self, "fail_reason")
    local after_channel = rawget(self, "_server_channel_state")

    if Policy.network_failure_transition(
        before_reason,
        after_reason,
        before_channel,
        after_channel
    ) then
        local steam_connected, backend_disconnected, observed = _snapshot_class(true)
        _emit(
            "edge=network_client reason=%s channel_before=%s channel_after=%s steam_connected=%s backend_disconnected=%s observed=%s",
            tostring(after_reason or "unknown"),
            tostring(before_channel or "unknown"),
            tostring(after_channel or "unknown"),
            Policy.bool_label(steam_connected),
            Policy.bool_label(backend_disconnected),
            observed
        )
    end

    return unpack_fn(results, 1, results.n)
end)

mod._gt753_disconnect_diagnostics = {
    policy = Policy,
    steam_hook = true,
    backend_hook = true,
    network_hook = true,
}

if type(mod._gt_rt_register) == "function" then
    mod._gt_rt_register("issue753_disconnect_failure_diagnostics_armed", function()
        -- Runner contract: nil == PASS, a reason string == FAIL (issue #1153).
        local state = mod._gt753_disconnect_diagnostics
        local ok = type(state) == "table"
            and state.steam_hook == true
            and state.backend_hook == true
            and state.network_hook == true
            and type(state.policy) == "table"
            and type(state.policy.classify) == "function"
        if not ok then
            return "disconnect service probe wiring incomplete"
        end
    end)
end

_emit("armed: steam_check=1 playfab_disconnect=1 network_client=1 transition_only=yes")
