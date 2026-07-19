-- _gt_diag_player_stats.lua -- issue #797 player-stat HUD census.
--
-- The game does not expose one authoritative "all final stats" object. Combat
-- paths combine career/item/action/profile data with BuffExtension stat rows,
-- including conditional/function-valued contributions. This probe records the
-- real local extension state without calling proc-bearing value application,
-- guessing a final, mutating gameplay, or sending network traffic.
-- luacheck: globals Managers ScriptUnit Unit StatBuffApplicationMethods printf
--
-- Owned by: general_tweaker_dev.lua. Consumed via: manifest mod:dofile.

local mod = get_mod("gt_dev")
local core = mod:dofile("scripts/mods/general_tweaker_dev/_gt_player_stat_probe_core")
local clock, trace = 0, nil

local function _safe(fn)
    local ok, value = pcall(fn)
    return ok and value or nil
end

local function _local_unit()
    local pm = Managers and Managers.player
    local player = pm and _safe(function() return pm:local_player(1) end)
    local unit = player and player.player_unit
    if not unit or not Unit or not Unit.alive or not _safe(function() return Unit.alive(unit) end) then
        return nil
    end
    return unit
end

local function _extension(unit, system)
    if not unit or not ScriptUnit then return nil end
    if type(ScriptUnit.has_extension) == "function" then
        return _safe(function() return ScriptUnit.has_extension(unit, system) end)
    end
    return _safe(function() return ScriptUnit.extension(unit, system) end)
end

local function _call(object, method)
    return object and type(object[method]) == "function"
        and _safe(function() return object[method](object) end) or nil
end

local function _identity(unit)
    local inventory = _extension(unit, "inventory_system")
    local equipment = inventory and inventory.equipment
    equipment = type(equipment) == "function" and _safe(function() return inventory:equipment() end)
        or equipment
    local slot_name = equipment and equipment.wielded_slot
    local slot = slot_name and equipment.slots and equipment.slots[slot_name]
    local item = slot and slot.item_data
    return {
        slot = tostring(slot_name or "nil"),
        item = tostring(item and (item.key or item.name or item.item_type) or "nil"),
        template = tostring(item and item.template or "nil"),
    }
end

local function _snapshot()
    local unit = _local_unit()
    if not unit then return nil, "local-player-unavailable" end
    local buff = _extension(unit, "buff_system")
    if not buff or type(buff._stat_buffs) ~= "table" then return nil, "buff-extension-unavailable" end
    local normalized = core.normalize(buff._stat_buffs, rawget(_G, "StatBuffApplicationMethods"))
    local health = _extension(unit, "health_system")
    local status = _extension(unit, "status_system")
    local career = _extension(unit, "career_system")
    local identity = _identity(unit)
    normalized.context = {
        slot = identity.slot,
        item = identity.item,
        template = identity.template,
        health = _call(health, "current_health"),
        max_health = _call(health, "get_max_health"),
        disabled = _call(status, "is_disabled"),
        career = tostring(_call(career, "career_name") or career and career._career_name or "nil"),
        active_buffs = tonumber(buff._num_buffs) or 0,
    }
    normalized.fingerprint = core.fingerprint(normalized)
    return normalized
end

local function _emit(snapshot, phase)
    local c = snapshot.context
    pcall(printf,
        "[gt:797] phase=%s fp_len=%d career=%s slot=%s item=%s template=%s health=%s/%s disabled=%s active_buffs=%d stat_types=%d stat_rows=%d contributions=%d truncated=%s",
        tostring(phase), #snapshot.fingerprint, tostring(c.career), tostring(c.slot),
        tostring(c.item), tostring(c.template), tostring(c.health), tostring(c.max_health),
        tostring(c.disabled), c.active_buffs, snapshot.stat_types, #snapshot.rows,
        snapshot.contributions,
        tostring(snapshot.truncated))
    for i, row in ipairs(snapshot.rows) do
        pcall(printf,
            "[gt:797] row=%d stat=%s method=%s entries=%d bonus=%.6f multiplier=%.6f values=%d dynamic=%d conditional=%d",
            i, row.stat, row.method, row.entries, row.bonus, row.multiplier,
            row.values, row.dynamic, row.conditional)
    end
end

local function _capture(phase)
    local snapshot, reason = _snapshot()
    if not snapshot then
        pcall(printf, "[gt:797] phase=%s skip=%s", tostring(phase), tostring(reason))
        return nil
    end
    _emit(snapshot, phase)
    return snapshot
end

local function _update(dt)
    clock = clock + (tonumber(dt) or 0)
    if not trace then return end
    local offset = core.take_due(trace, clock)
    if offset == nil then return end
    local snapshot = _capture(string.format("trace_%.2f", offset))
    core.record(trace, offset, snapshot and snapshot.fingerprint or "unavailable")
    if core.complete(trace) then
        pcall(printf, "[gt:797] trace complete records=%d window=10.00", #trace.records)
        trace = nil
    end
end

if type(mod._gt_register_update) == "function" then
    mod._gt_register_update("gt797_player_stat_probe", _update)
    mod._gt_player_stat_probe_update_registered = true
end

mod:command("gt_stat_probe", "Log one read-only local player stat census", function()
    _capture("single")
end)

mod:command("gt_stat_trace", "Log five bounded player stat censuses over ten seconds", function()
    trace = core.new_trace(clock)
    pcall(printf,
        "[gt:797] trace armed samples=%d window=10.00 action=change_one_item_talent_buff_or_action_state",
        #core.TRACE_OFFSETS)
end)

mod._gt_player_stat_snapshot = _snapshot
if type(mod._gt_rt_register) == "function" then
    mod._gt_rt_register("issue797_player_stat_diagnostics_armed", function()
        local ok = mod._gt_player_stat_probe_update_registered == true
            and type(mod._gt_player_stat_snapshot) == "function"
            and core.MAX_STAT_TYPES == 256 and core.MAX_CONTRIBUTIONS == 1024
            and #core.TRACE_OFFSETS == 5
        return ok, ok and "read-only bounded stat census wired"
            or "player stat census wiring incomplete"
    end)
end

return core
