local mod = get_mod("gt_dev")
local NETWORK_READINESS = mod:dofile(
    "scripts/mods/general_tweaker_dev/_gt_network_readiness"
)

-- Issue #1143: developer healing through the game's own host/client route.
-- This module never writes health or wound state directly, and it reports
-- success only after the authoritative postcondition is visible locally.
local TIMEOUT_SECONDS = 2
local HEALTH_EPSILON = 0.01

local pending
local receipt_count = 0
local command_registered = false
local update_registered = false

local function _route()
    local player_manager = Managers and Managers.player
    if type(player_manager) ~= "table" then return "unknown" end
    return player_manager.is_server and "host" or "client"
end

local function _call(object, method_name)
    local method = object and object[method_name]
    if type(method) ~= "function" then return nil, false end
    local ok, value = pcall(method, object)
    if not ok then return nil, false end
    return value, true
end

local function _extension(unit, extension_name)
    if type(ScriptUnit) ~= "table"
            or type(ScriptUnit.has_extension) ~= "function" then
        return nil
    end
    local ok, extension = pcall(ScriptUnit.has_extension, unit, extension_name)
    return ok and extension or nil
end

local function _unit_alive(unit)
    if not unit or type(Unit) ~= "table" or type(Unit.alive) ~= "function" then
        return false
    end
    local ok, alive = pcall(Unit.alive, unit)
    return ok and alive == true
end

local function _disabled_state(status)
    local disabled, has_disabled = _call(status, "is_disabled")
    if not has_disabled or type(disabled) ~= "boolean" then
        return nil, false
    end
    return disabled, true
end

local function _snapshot(health, status)
    local current, current_ok = _call(health, "current_permanent_health")
    local maximum, maximum_ok = _call(health, "get_max_health")
    local wounded, wounded_ok = _call(status, "is_wounded")
    local snapshot = {}
    if current_ok and type(current) == "number" then
        snapshot.current = current
    end
    if maximum_ok and type(maximum) == "number" and maximum > 0 then
        snapshot.maximum = maximum
    end
    if wounded_ok and type(wounded) == "boolean" then
        snapshot.wounded = wounded
    end
    if snapshot.current == nil or snapshot.maximum == nil then
        return snapshot, "health_state_unavailable"
    end
    if snapshot.wounded == nil then
        return snapshot, "wound_state_unavailable"
    end
    return snapshot
end

local function _number(value)
    return type(value) == "number" and string.format("%.2f", value) or "unknown"
end

local function _boolean(value)
    return type(value) == "boolean" and tostring(value) or "unknown"
end

local function _emit(result, record, after, elapsed, reason)
    receipt_count = receipt_count + 1
    printf(
        "[gt:1143] heal result=%s route=%s before=%s after=%s max=%s "
            .. "wounded_before=%s wounded_after=%s elapsed=%.3f reason=%s record=%d",
        result,
        record and record.route or _route(),
        _number(record and record.before),
        _number(after and after.current),
        _number(after and after.maximum),
        _boolean(record and record.wounded_before),
        _boolean(after and after.wounded),
        elapsed or 0,
        reason or "none",
        receipt_count
    )
end

local function _reject(reason)
    _emit("error", nil, nil, 0, reason)
    mod:echo("Heal unavailable: %s.", (reason:gsub("_", " ")))
end

local function _request()
    if pending then
        _reject("request_already_pending")
        return
    end

    local player = NETWORK_READINESS.local_player(Managers)
    local unit = player and player.player_unit
    if not _unit_alive(unit) then
        _reject("no_living_local_hero")
        return
    end

    local health = _extension(unit, "health_system")
    local status = _extension(unit, "status_system")
    if not health or not status then
        _reject("local_hero_extensions_unavailable")
        return
    end
    local health_alive, has_health_alive = _call(health, "is_alive")
    if not has_health_alive or type(health_alive) ~= "boolean" then
        _reject("health_alive_state_unavailable")
        return
    end
    local disabled, has_disabled = _disabled_state(status)
    if not has_disabled then
        _reject("status_state_unavailable")
        return
    end
    if not health_alive or disabled then
        _reject("local_hero_disabled_or_dead")
        return
    end

    local before, snapshot_error = _snapshot(health, status)
    if snapshot_error then
        _reject(snapshot_error)
        return
    end

    local native = DamageUtils and DamageUtils.debug_heal
    if type(native) ~= "function" then
        _reject("native_debug_heal_unavailable")
        return
    end

    local record = {
        unit = unit,
        health = health,
        status = status,
        route = _route(),
        before = before.current,
        maximum = before.maximum,
        wounded_before = before.wounded,
        elapsed = 0,
    }
    local ok = pcall(native, unit, before.maximum)
    if not ok then
        local after = _snapshot(health, status)
        _emit("error", record, after, 0, "native_debug_heal_error")
        mod:echo("Heal failed before the game accepted the request.")
        return
    end

    pending = record
    mod:echo("Heal requested; waiting for the game to confirm full health.")
end

local function _update(dt)
    local record = pending
    if not record then return end

    record.elapsed = record.elapsed + (type(dt) == "number" and dt or 0)
    if not _unit_alive(record.unit) then
        pending = nil
        _emit("error", record, nil, record.elapsed, "local_hero_no_longer_alive")
        mod:echo("Heal failed because the local hero is no longer alive.")
        return
    end

    local after, snapshot_error = _snapshot(record.health, record.status)
    if not snapshot_error
            and after.current >= after.maximum - HEALTH_EPSILON
            and after.wounded == false then
        pending = nil
        _emit("ok", record, after, record.elapsed)
        mod:echo("Healed to full permanent health.")
        return
    end

    if record.elapsed >= TIMEOUT_SECONDS then
        pending = nil
        _emit("timeout", record, after, record.elapsed,
            snapshot_error or "postcondition_not_observed")
        mod:echo("Heal was requested, but full health was not confirmed.")
    end
end

local function _reset(reason)
    local record = pending
    if not record then return end
    pending = nil
    local after = _snapshot(record.health, record.status)
    _emit("error", record, after, record.elapsed,
        "request_cancelled_" .. tostring(reason or "lifecycle_reset"))
    mod:echo("Pending heal confirmation was cancelled by a lifecycle change.")
end

mod._gt_dev_heal_request = _request
mod._gt_dev_heal_update = _update
mod._gt_dev_heal_reset = _reset
mod._gt_dev_heal_contract = {
    marker = "gt-1143-native-debug-heal",
    native_debug_heal = function()
        return DamageUtils and DamageUtils.debug_heal
    end,
    debug_heal_lookup = function()
        return NetworkLookup and NetworkLookup.heal_types
            and NetworkLookup.heal_types.debug
    end,
    network_readiness = NETWORK_READINESS,
    command_registered = function() return command_registered end,
    update_registered = function() return update_registered end,
}

mod:command("heal", "Restore your living hero to full permanent health and clear wounds", _request)
command_registered = true
mod._gt_register_update("gt1143_dev_heal_postcondition", _update)
update_registered = true

mod._gt_rt_register("issue1143_dev_heal_command", function()
    local contract = mod._gt_dev_heal_contract
    if not contract or contract.marker ~= "gt-1143-native-debug-heal" then
        return "developer heal contract marker missing"
    end
    if type(mod._gt_dev_heal_request) ~= "function"
            or type(mod._gt_dev_heal_update) ~= "function"
            or type(mod._gt_dev_heal_reset) ~= "function"
            or not contract.command_registered()
            or not contract.update_registered() then
        return "developer heal command/update wiring missing"
    end
    if type(contract.network_readiness) ~= "table"
            or type(contract.network_readiness.local_player) ~= "function" then
        return "network-readiness owner missing"
    end
    if type(contract.native_debug_heal()) ~= "function" then
        return "DamageUtils.debug_heal unavailable"
    end
    if contract.debug_heal_lookup() == nil then
        return "debug heal network lookup unavailable"
    end
end)

return {}
