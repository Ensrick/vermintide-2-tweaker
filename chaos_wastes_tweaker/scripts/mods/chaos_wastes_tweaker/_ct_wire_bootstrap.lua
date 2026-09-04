-- Pure bootstrap validation for the public issue #426 wire catalog.
-- The entry chunk retains its own CT namespace floor so a missing copy of this
-- module still disables owned content instead of treating it as third-party.

local M = {}

local REQUIRED_METHODS = {
    "reserve_lookups", "power_up_entries", "buff_entries", "count",
    "is_power_up", "is_buff", "is_owned_power_up_name",
    "is_owned_buff_name", "power_registry_ready", "catalog_ready",
    "build_identity", "capture_integrity", "integrity",
    "filter_power_ups", "filter_power_up_names", "filter_persistent_buffs",
    "power_up_allowed", "buff_allowed", "shop_power_up_decision",
    "receiver_decision", "runtime_gate_setting_ids", "runtime_gate_spec",
    "try_register_runtime_gate",
}

local function owned_power(name)
    return type(name) == "string" and name:find("^ct_") ~= nil
end

local function owned_buff(name)
    return type(name) == "string"
        and (name:find("^ct_") ~= nil or name:find("^power_up_ct_") ~= nil)
end

local function policy_true(policy, method, name)
    local fn = type(policy) == "table" and rawget(policy, method)
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn, name)
    return ok and value == true
end

function M.policy_ready(policy)
    if type(policy) ~= "table" or rawget(policy, "POWER_UP_COUNT") ~= 10
            or rawget(policy, "BUFF_COUNT") ~= 19
            or rawget(policy, "WIRE_ROW_COUNT") ~= 29
            or rawget(policy, "MAX_STATE_ROWS") ~= 4096
            or rawget(policy, "IDENTITY_NAMESPACE") ~= "ct-public-wire-v1"
            or type(rawget(policy, "GATED_SETTING_IDS")) ~= "table"
            or type(rawget(policy, "GATE_REASON")) ~= "string" then
        return false
    end
    for i = 1, #REQUIRED_METHODS do
        if type(rawget(policy, REQUIRED_METHODS[i])) ~= "function" then
            return false
        end
    end

    local gates = rawget(policy, "GATED_SETTING_IDS")
    local gate_count, gate_max, seen_gates = 0, 0, {}
    for key, value in next, gates do
        if type(key) ~= "number" or key <= 0 or key ~= math.floor(key)
                or type(value) ~= "string" or value == ""
                or rawget(seen_gates, value) then
            return false
        end
        rawset(seen_gates, value, true)
        gate_count = gate_count + 1
        if key > gate_max then gate_max = key end
    end
    if gate_count ~= 17 or gate_max ~= gate_count then return false end

    local ok_power, powers = pcall(rawget(policy, "power_up_entries"))
    local ok_buff, buffs = pcall(rawget(policy, "buff_entries"))
    if not ok_power or type(powers) ~= "table"
            or not ok_buff or type(buffs) ~= "table" then
        return false
    end
    local power_count, buff_count = 0, 0
    for name, spec in next, powers do
        if not owned_power(name) or type(spec) ~= "table"
                or type(rawget(spec, "rarity")) ~= "string"
                or not policy_true(policy, "is_power_up", name)
                or not policy_true(policy, "is_owned_power_up_name", name) then
            return false
        end
        power_count = power_count + 1
        if power_count > 10 then return false end
    end
    for name in next, buffs do
        if not owned_buff(name) or not policy_true(policy, "is_buff", name)
                or not policy_true(policy, "is_owned_buff_name", name) then
            return false
        end
        buff_count = buff_count + 1
        if buff_count > 19 then return false end
    end
    return power_count == rawget(policy, "POWER_UP_COUNT")
        and buff_count == rawget(policy, "BUFF_COUNT")
        and not policy_true(policy, "is_owned_power_up_name", "natural_bond")
        and not policy_true(policy, "is_owned_buff_name", "other_mod_buff")
end

function M.reservation_valid(policy, network_lookup, reservation)
    if type(policy) ~= "table" or type(reservation) ~= "table"
            or type(rawget(reservation, "power_up")) ~= "table"
            or type(rawget(reservation, "buff")) ~= "table" then
        return false
    end
    for key in next, reservation do
        if key ~= "power_up" and key ~= "buff" then return false end
    end
    local allowed = { added = true, first_id = true, last_id = true }
    local function axis_valid(axis, count)
        for key in next, axis do
            if not rawget(allowed, key) then return false end
        end
        local added = rawget(axis, "added")
        local first_id = rawget(axis, "first_id")
        local last_id = rawget(axis, "last_id")
        if added ~= 0 and added ~= count then return false end
        if type(first_id) ~= "number" or first_id <= 0
                or first_id ~= math.floor(first_id)
                or first_id == math.huge or first_id == -math.huge
                or first_id > 9007199254740991
                or type(last_id) ~= "number"
                or last_id == math.huge or last_id == -math.huge
                or last_id > 9007199254740991
                or last_id ~= first_id + count - 1 then
            return false
        end
        return true
    end
    if not axis_valid(rawget(reservation, "power_up"),
                rawget(policy, "POWER_UP_COUNT"))
            or not axis_valid(rawget(reservation, "buff"),
                rawget(policy, "BUFF_COUNT")) then
        return false
    end
    local capture = rawget(policy, "capture_integrity")
    local integrity = rawget(policy, "integrity")
    if type(capture) ~= "function" or type(integrity) ~= "function" then
        return false
    end
    local ok_capture, snapshot = pcall(capture, network_lookup)
    if not ok_capture or type(snapshot) ~= "table" then return false end
    local ok_integrity, intact = pcall(integrity, snapshot)
    return ok_integrity and intact == true
end

local function safe_log(log, fmt, ...)
    if type(log) == "function" then pcall(log, fmt, ...) end
end

-- Treat the reservation provider as fallible. A partially deployed or
-- malformed helper can mutate one lookup and then throw/return an unverifiable
-- result. Snapshot the root plus both raw axes so every failure can restore the
-- exact bindings, entries, and metatables that existed before the attempt.
local function capture_raw_table(value)
    local entries = {}
    local count = 0
    for key, item in next, value do
        count = count + 1
        entries[count] = { key, item }
    end
    return {
        value = value,
        entries = entries,
        metatable = getmetatable(value),
    }
end

local function capture_lookup_transaction(network_lookup)
    if type(network_lookup) ~= "table" then
        return nil, "network-lookup-missing"
    end
    local power = rawget(network_lookup, "deus_power_up_templates")
    local buff = rawget(network_lookup, "buff_templates")
    if type(power) ~= "table" or type(buff) ~= "table" then
        return nil, "lookup-axis-missing"
    end
    local snapshots = {}
    local function add(value)
        for i = 1, #snapshots do
            if rawequal(snapshots[i].value, value) then return end
        end
        snapshots[#snapshots + 1] = capture_raw_table(value)
    end
    add(network_lookup)
    add(power)
    add(buff)
    return { tables = snapshots }
end

local function restore_raw_table(snapshot)
    local value = snapshot.value
    local keys = {}
    for key in next, value do keys[#keys + 1] = key end
    for i = 1, #keys do rawset(value, keys[i], nil) end
    for i = 1, #snapshot.entries do
        local entry = snapshot.entries[i]
        rawset(value, entry[1], entry[2])
    end
    local current = getmetatable(value)
    if not rawequal(current, snapshot.metatable) then
        if snapshot.metatable ~= nil and type(snapshot.metatable) ~= "table" then
            return false, "protected-metatable-changed"
        end
        local ok, reason = pcall(setmetatable, value, snapshot.metatable)
        if not ok then return false, "metatable-restore-failed:" .. tostring(reason) end
    end
    return true
end

local function restore_lookup_transaction(snapshot)
    if type(snapshot) ~= "table" or type(snapshot.tables) ~= "table" then
        return false, "lookup-snapshot-missing"
    end
    for i = 1, #snapshot.tables do
        local ok, reason = restore_raw_table(snapshot.tables[i])
        if not ok then return false, reason end
    end
    return true
end

function M.install(mod, globals, print_fn, log)
    if type(mod) ~= "table" or type(globals) ~= "table" then
        return false
    end
    local dofile_fn = mod.dofile
    if type(dofile_fn) ~= "function" then return false end
    local ok_policy, policy = pcall(dofile_fn, mod,
        "scripts/mods/chaos_wastes_tweaker/_ct_wire_policy")
    local ok_lookup, lookup_lib = pcall(dofile_fn, mod,
        "scripts/mods/chaos_wastes_tweaker/_lib_network_lookup")
    local ok_policy_ready, policy_ready = pcall(M.policy_ready, policy)
    policy_ready = ok_policy and ok_policy_ready and policy_ready == true
    local lookup_ready = ok_lookup and type(lookup_lib) == "table"
        and type(rawget(lookup_lib, "register_named")) == "function"
    if not policy_ready then policy = nil end
    if not lookup_ready then lookup_lib = nil end

    local ok_capacity, buff_capacity = pcall(function()
        local network = rawget(globals, "Network")
        local info = network and network.type_info("buff_lookup")
        return type(info) == "table" and rawget(info, "max") or nil
    end)
    local reservation, reservation_error
    if policy_ready and lookup_ready and ok_capacity
            and type(buff_capacity) == "number" then
        local network_lookup = rawget(globals, "NetworkLookup")
        local ok_snapshot, snapshot, snapshot_error = pcall(
            capture_lookup_transaction, network_lookup)
        if ok_snapshot and snapshot ~= nil then
            local ok_reserve, result, reason = pcall(
                rawget(policy, "reserve_lookups"), network_lookup,
                { buff = buff_capacity })
            local ok_verify, verified = false, false
            if ok_reserve and result ~= nil then
                ok_verify, verified = pcall(
                    M.reservation_valid, policy, network_lookup, result)
            end
            if ok_reserve and result ~= nil and ok_verify and verified == true then
                reservation, reservation_error = result, reason
            else
                if ok_reserve and result ~= nil then
                    reservation_error = "reservation-verification-failed"
                elseif ok_reserve then
                    reservation_error = reason
                else
                    reservation_error = "reservation-error:" .. tostring(result)
                end
                local ok_restore, restored, restore_error = pcall(
                    restore_lookup_transaction, snapshot)
                if not ok_restore or restored ~= true then
                    reservation_error = tostring(reservation_error)
                        .. ":rollback-failed:"
                        .. tostring(ok_restore and restore_error or restored)
                end
            end
        else
            reservation_error = "lookup-snapshot-unavailable:"
                .. tostring(ok_snapshot and snapshot_error or snapshot)
        end
    else
        reservation_error = "wire-bootstrap-unavailable:policy=" .. tostring(policy)
            .. ":lookup=" .. tostring(lookup_lib)
            .. ":buff_capacity=" .. tostring(buff_capacity)
    end

    rawset(mod, "_ct_wire_policy", policy)
    rawset(mod, "_ct_network_lookup_lib", lookup_lib)
    rawset(mod, "_ct_wire_reservation", reservation)
    rawset(mod, "_ct_wire_reservation_error", reservation_error)
    rawset(mod, "_ct_wire_reservation_ready", reservation ~= nil)
    rawset(mod, "_ct_wire_safe", function() return false end)
    rawset(mod, "_ct_sender_wire_safe", function() return false end)
    rawset(mod, "_ct_is_modded_power_up", owned_power)
    rawset(mod, "_ct_is_ct_buff_template", owned_buff)
    rawset(mod, "_ct_power_up_wire_allowed", function(name)
        return not owned_power(name)
    end)
    rawset(mod, "_ct_buff_wire_allowed", function(name)
        return not owned_buff(name)
    end)
    rawset(mod, "_ct_register_network_name", function(axis, name)
        if type(name) ~= "string" then return end
        local power_axis = axis == "deus_power_up_templates"
        local buff_axis = axis == "buff_templates"
        local ct_name = power_axis and owned_power(name)
            or buff_axis and owned_buff(name)
        if ct_name then
            if reservation == nil then return end
            local classifier = power_axis and "is_power_up" or "is_buff"
            if not policy_true(policy, classifier, name) then
                safe_log(log,
                    "[ct:426] refused stale/unfrozen NetworkLookup identity axis=%s name=%s",
                    tostring(axis), tostring(name))
                return
            end
        end
        if not lookup_lib then return end
        local ok_register, _, _, reason = pcall(
            lookup_lib.register_named, rawget(globals, "NetworkLookup"),
            axis, name)
        if not ok_register then reason = "registrar-error" end
        if reason ~= "registered" and reason ~= "already_registered" then
            safe_log(log,
                "[ct:426] NetworkLookup registration refused axis=%s name=%s reason=%s",
                tostring(axis), tostring(name), tostring(reason))
        end
    end)
    if not reservation and type(print_fn) == "function" then
        pcall(print_fn,
            "[ct:426] exact public wire reservation refused (%s); custom boons and miracles remain inert",
            tostring(reservation_error))
    end
    return true
end

return M
