-- _gut_loadout_lifecycle_owner.lua -- executable loadout persistence boundaries
--
-- This module owns the two production transactions that must stay executable in tests:
-- the outer BackendUtils equip capture (#353) and the three bounded exit snapshots (#354).
-- It is deliberately dependency-injected so the live hook/callbacks and offline harness run
-- the same control flow without mocking engine globals.

local M = {}

local function _call_report(report_error, edge, err)
    if type(report_error) == "function" then
        pcall(report_error, edge, err)
    end
end

function M.capture_equip(ctx)
    if type(ctx) ~= "table" then return "ignored", "invalid-context" end
    if ctx.mode == ctx.mode_off or not ctx.career_name or ctx.backend_id == nil
        or not ctx.is_loadout_slot then
        return "ignored", "out-of-scope"
    end
    if type(ctx.capture_slot_durable) ~= "function"
        or type(ctx.slot_owned_by_items) ~= "function"
        or type(ctx.get_mirror) ~= "function"
        or type(ctx.canonical_value) ~= "function"
        or type(ctx.write) ~= "function" then
        return "ignored", "missing-dependency"
    end

    local ok_owner, owned = pcall(ctx.slot_owned_by_items, ctx.slot_name)
    if not ok_owner then owned = false end
    local ok_durable, durable = pcall(ctx.capture_slot_durable, ctx.slot_name, owned)
    if not ok_durable or not durable then
        return "foreign-owner", ok_durable and "foreign-loadout-interface" or tostring(durable)
    end

    local ok_mirror, mirror = pcall(ctx.get_mirror)
    if not ok_mirror or mirror == nil then
        return "unresolved", ok_mirror and "mirror-unavailable" or tostring(mirror)
    end
    local ok_value, value, source = pcall(ctx.canonical_value, ctx.backend_id, ctx.slot_name)
    if not ok_value or value == nil then
        return "unresolved", ok_value and source or tostring(value)
    end
    local ok_write, write_err = pcall(ctx.write, ctx.mode, mirror, ctx.career_name,
        ctx.slot_name, value, source)
    if not ok_write then
        return "write-error", tostring(write_err)
    end
    return "captured", source
end

function M.bind_snapshot_edges(ctx)
    assert(type(ctx) == "table" and type(ctx.snapshot) == "function",
        "loadout lifecycle snapshot callback required")

    local function _snapshot(edge)
        local ok, err = pcall(ctx.snapshot, edge)
        if not ok then _call_report(ctx.report_error, edge, err) end
        return ok, err
    end

    local function _previous(name, callback, ...)
        if type(callback) ~= "function" then return end
        local ok, err = pcall(callback, ...)
        if not ok then _call_report(ctx.report_error, name, err) end
    end

    local on_game_state_changed = function(status, state_name)
        _previous("previous_state", ctx.previous_state, status, state_name)
        if status == "exit" and state_name == "StateIngame" then
            _snapshot("ingame_exit")
        elseif status == "enter" and state_name == "StateTitleScreen" then
            _snapshot("title_enter")
        end
    end

    local on_unload = function(...)
        _previous("previous_unload", ctx.previous_unload, ...)
        _snapshot("unload")
    end

    return on_game_state_changed, on_unload
end

return M
