-- _mod_tweaker_runtime_gates.lua - live, fail-closed Mod Tweaker row gates.
--
-- Sibling mods register bounded predicates for settings which are unsafe in the
-- current lobby.  The registry evaluates those predicates at interaction time,
-- greys blocked rows, makes them read-only, and replaces the normal tooltip with
-- a player-facing reason.  It is presentation/interaction containment only: the
-- owning mod must still fail closed at its gameplay and network emission boundary.
--
-- Owned by: _mod_tweaker.lua. Consumed via: the public mod.mod_tweaker API.

local RuntimeGates = {}

local _dbg_alert = function() end
local _gates = {}
local _gate_order = {}
local _members = {}
local _reported_failures = {}

local DEFAULT_REASON = "Unavailable because multiplayer safety could not be confirmed."

local function _member_key(mod_id, setting_id)
    return tostring(mod_id) .. "\0" .. tostring(setting_id)
end

local function _copy_color(color)
    if type(color) ~= "table" then return nil end
    return { color[1], color[2], color[3], color[4] }
end

local function _restore_color(color, original)
    if type(color) ~= "table" or type(original) ~= "table" then return end
    color[1], color[2], color[3], color[4] = original[1], original[2], original[3], original[4]
end

local function _remove_gate_from_members(gate)
    if not gate then return end
    for i = 1, #gate.setting_ids do
        local key = _member_key(gate.mod_id, gate.setting_ids[i])
        local ids = _members[key]
        if ids then
            for j = #ids, 1, -1 do
                if ids[j] == gate.gate_id then table.remove(ids, j) end
            end
            if #ids == 0 then _members[key] = nil end
        end
    end
end

function RuntimeGates.init_dbg(_, dbg_alert)
    if type(dbg_alert) == "function" then _dbg_alert = dbg_alert end
end

-- spec = {
--   mod_id = "character_weapon_variants",
--   setting_ids = { "enable_throwing_spear" },
--   evaluate = function() return false,
--       "Disabled while Rain lacks Career Weapon Variants." end,
-- }
--
-- `evaluate` returns available:boolean, reason:string. A throwing predicate,
-- non-boolean result, or blocked result without a reason fails closed.
function RuntimeGates.register(gate_id, spec)
    if type(gate_id) ~= "string" or gate_id == "" then
        return false, "gate_id must be a non-empty string"
    end
    if type(spec) ~= "table" then return false, "gate spec must be a table" end
    if type(spec.mod_id) ~= "string" or spec.mod_id == "" then
        return false, "gate spec is missing string mod_id"
    end
    if type(spec.setting_ids) ~= "table" or #spec.setting_ids == 0 then
        return false, "gate spec requires at least one setting_id"
    end
    if type(spec.evaluate) ~= "function" then
        return false, "gate spec is missing evaluate function"
    end

    local setting_ids = {}
    local seen = {}
    for i = 1, #spec.setting_ids do
        local setting_id = spec.setting_ids[i]
        if type(setting_id) ~= "string" or setting_id == "" then
            return false, "setting_ids must contain non-empty strings"
        end
        if not seen[setting_id] then
            seen[setting_id] = true
            setting_ids[#setting_ids + 1] = setting_id
        end
    end

    local old = _gates[gate_id]
    if old then
        _remove_gate_from_members(old)
    else
        _gate_order[#_gate_order + 1] = gate_id
    end

    local gate = {
        gate_id = gate_id,
        mod_id = spec.mod_id,
        setting_ids = setting_ids,
        evaluate = spec.evaluate,
    }
    _gates[gate_id] = gate
    _reported_failures[gate_id] = nil
    for i = 1, #setting_ids do
        local key = _member_key(gate.mod_id, setting_ids[i])
        local ids = _members[key] or {}
        ids[#ids + 1] = gate_id
        _members[key] = ids
    end
    return true
end

function RuntimeGates.unregister(gate_id)
    local gate = _gates[gate_id]
    if not gate then return false end
    _remove_gate_from_members(gate)
    _gates[gate_id] = nil
    _reported_failures[gate_id] = nil
    for i = #_gate_order, 1, -1 do
        if _gate_order[i] == gate_id then table.remove(_gate_order, i) end
    end
    return true
end

function RuntimeGates.status(mod_id, setting_id)
    local ids = _members[_member_key(mod_id, setting_id)]
    if not ids then return false end

    for i = 1, #ids do
        local gate = _gates[ids[i]]
        if gate then
            local ok, available, reason = pcall(gate.evaluate)
            if not ok then
                local signature = "error:" .. tostring(available)
                if _reported_failures[gate.gate_id] ~= signature then
                    _reported_failures[gate.gate_id] = signature
                    _dbg_alert("[mt:runtime-gate] %s predicate failed: %s",
                        tostring(gate.gate_id), tostring(available))
                end
                return true, DEFAULT_REASON, gate.gate_id
            end
            if type(available) ~= "boolean" then
                local signature = "non-boolean:" .. type(available)
                if _reported_failures[gate.gate_id] ~= signature then
                    _reported_failures[gate.gate_id] = signature
                    _dbg_alert("[mt:runtime-gate] %s returned non-boolean availability",
                        tostring(gate.gate_id))
                end
                return true, DEFAULT_REASON, gate.gate_id
            end
            _reported_failures[gate.gate_id] = nil
            if not available then
                if type(reason) ~= "string" or reason == "" then reason = DEFAULT_REASON end
                return true, reason, gate.gate_id
            end
        end
    end
    return false
end

-- Apply the current live state to an already-built row. The first call captures
-- the row's native/VMF state so a peer leaving can restore it exactly.
function RuntimeGates.apply_row(row, mod_id, setting_id)
    if type(row) ~= "table" or type(mod_id) ~= "string"
            or type(setting_id) ~= "string" then
        return false
    end

    local label_color = row.style and row.style.label and row.style.label.text_color
    if not row._runtime_gate_base then
        row._runtime_gate_base = {
            readonly = row._readonly == true,
            tip_desc = row._tip_desc,
            label_color = _copy_color(label_color),
        }
    end

    local blocked, reason, gate_id = RuntimeGates.status(mod_id, setting_id)
    local base = row._runtime_gate_base
    row._readonly = base.readonly or blocked
    row._runtime_gate_disabled = blocked or nil
    row._runtime_gate_id = blocked and gate_id or nil
    row._tip_desc = blocked and reason or base.tip_desc

    if blocked and label_color then
        label_color[1], label_color[2], label_color[3], label_color[4] = 128, 128, 128, 128
    else
        _restore_color(label_color, base.label_color)
    end
    return blocked, reason, gate_id
end

-- Remove newly blocked edits from the Mod Tweaker's pending maps immediately
-- before Apply. The outer key is already the owning mod id, including for the
-- synthesized Equipment tab, so no second owner-resolution system is needed.
function RuntimeGates.prune_pending(pending_by_mod, mod_ids)
    local blocked_count = 0
    if type(pending_by_mod) ~= "table" or type(mod_ids) ~= "table" then return blocked_count end
    for i = 1, #mod_ids do
        local mod_id = mod_ids[i]
        local pending = pending_by_mod[mod_id]
        if type(pending) == "table" then
            for setting_id in pairs(pending) do
                if RuntimeGates.status(mod_id, setting_id) then
                    pending[setting_id] = nil
                    blocked_count = blocked_count + 1
                end
            end
        end
    end
    return blocked_count
end

-- Test-only reset for this engine-free registry. Production never calls it.
function RuntimeGates._reset()
    _gates, _gate_order, _members, _reported_failures = {}, {}, {}, {}
end

return RuntimeGates
