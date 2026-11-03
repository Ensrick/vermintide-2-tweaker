-- _gt_time_owner.lua -- exact native time and selective-freeze lease ownership.
--
-- Owns the original native time baseline, exact last-applied manager/state, and
-- transient freeze leases for General's time controls (#1801, #1802). Active
-- writes require enabled host/modded authority; a distinct cleanup policy may
-- restore only owned state or retire proved old managers without native writes.
-- Depends on injected native/setting adapters, not hooks, RPCs or synthetic time.
--
-- Owned by: general_tweaker.lua entry point.
-- Consumed via: mod:dofile("scripts/mods/general_tweaker/_gt_time_owner").
-- Native table/setter: scripts/managers/debug/debug_manager.lua:20-45,711-745.
-- VMF notify contract: modules/core/settings.lua:46-60; core/events.lua:73-84.
local M = {}
local PERCENT = {1e-5, 0.0001, 0.001, 0.01, 0.1, 1, 5, 10, 20, 30, 50, 75,
    100, 125, 150, 175, 200, 250, 300, 500, 750, 1000, 5000, 10000}
local PAUSED = 1e-8
local NORMAL = 13

local function index_ok(value)
    return type(value) == "number" and value == value and value >= 1
        and value <= #PERCENT and value % 1 == 0
end
local function multiplier(index)
    if index_ok(index) then return PERCENT[index] * 0.01 end
end
local function copy(state)
    return {index=state.index, paused=state.paused, multiplier=state.multiplier}
end
local function equal(a, b)
    return a.index == b.index and a.paused == b.paused and a.multiplier == b.multiplier
end
local function running(index)
    return {index=index, paused=false, multiplier=multiplier(index)}
end
local function coherent(state)
    return state.multiplier == (state.paused and PAUSED or multiplier(state.index))
end
function M.presets()
    local rows = {}
    for index=1,#PERCENT do
        rows[index] = {index=index, percent=PERCENT[index], multiplier=multiplier(index)}
    end
    return rows -- A caller may format/localize these copies without mutating policy.
end
M.multiplier = multiplier
M.NORMAL_INDEX = NORMAL

function M.new(mod, api)
    assert(type(mod) == "table" and type(mod.get) == "function" and type(mod.set) == "function", "mod_api")
    for _, name in ipairs({"authorize", "read_native", "write_native", "write_paused"}) do
        assert(type(api[name]) == "function", "missing_api_" .. name)
    end
    local owner = {}
    local record, freeze, releasing, selecting
    local retired_generation = 0
    local function report(key, detail)
        if api.diagnostic then pcall(api.diagnostic, key, detail) end
    end
    local function authorize()
        local ok, allowed, reason = pcall(api.authorize)
        if not ok then return false, "authorize_error" end
        if allowed ~= true then
            local key = type(reason) == "string" and reason:match("^[a-z][a-z0-9_]*$") and reason or "not_authorized"
            return false, key
        end
        return true
    end
    local function permission(lane, manager, reason)
        if lane ~= "cleanup" then
            local allowed, key = authorize()
            return allowed and "synchronized" or nil, key
        end
        if type(api.authorize_cleanup) ~= "function" then return nil, "cleanup_authorization_missing" end
        local ok, mode, denied = pcall(api.authorize_cleanup, manager, reason)
        if not ok then return nil, "cleanup_authorize_error" end
        if mode == "synchronized" or mode == "local_only" then return mode end
        local key = type(denied) == "string" and denied:match("^[a-z][a-z0-9_]*$") and denied or "cleanup_not_authorized"
        return nil, key
    end
    local function read()
        local ok, manager, state = pcall(api.read_native)
        if not ok then return nil, nil, "read_error" end
        if manager == nil or manager == false or type(state) ~= "table" then
            return nil, nil, "missing_native", manager
        end
        if not index_ok(state.index) or type(state.paused) ~= "boolean"
            or type(state.multiplier) ~= "number" or state.multiplier ~= state.multiplier
            or state.multiplier <= 0 or state.multiplier == math.huge then
            return nil, nil, "invalid_native", manager
        end
        return manager, copy(state), nil, manager
    end
    local function guard(lane)
        if lane ~= "cleanup" then
            local allowed, reason = authorize()
            if not allowed then return nil, nil, reason end
        elseif not record then return nil, nil, "ownership_missing" end
        local manager, state, err, identity = read()
        if lane == "cleanup" and record then
            if identity ~= nil and identity ~= false and identity ~= record.manager then
                return nil, nil, "manager_retired"
            end
            if type(api.manager_retired) == "function" then
                local ok, retired = pcall(api.manager_retired, record.manager)
                if ok and retired == true then return nil, nil, "manager_retired" end
            end
        end
        if not manager then return nil, nil, err end
        if record then
            if manager ~= record.manager then return nil, nil, "manager_replaced" end
            if not equal(state, record.last) then return nil, nil, "foreign_state" end
        elseif not coherent(state) then
            return nil, nil, "foreign_native_mapping"
        end
        return manager, state
    end
    -- Synchronous native setter prefixes only. This is not permission to restore
    -- arbitrary observations, or to claim protection against a reentrant writer.
    local function owned_prefix(state, before, expected)
        return equal(state, before) or (state.multiplier == expected.multiplier
            and (state.index == before.index or state.index == expected.index)
            and (state.paused == before.paused or state.paused == expected.paused))
    end
    local function attempt(manager, before, target, lane, reason, force)
        if equal(before, target) and not force then return true, copy(before) end
        local steps = {}
        local normal = running(target.index)
        if not equal(before, normal) or force then steps[#steps+1] = normal end
        if target.paused then steps[#steps+1] = copy(target) end
        local current = copy(before)
        for _, expected in ipairs(steps) do
            local check_manager, check, err = read()
            if not check_manager then return false, nil, err, false end
            if check_manager ~= manager then return false, nil, "manager_replaced", false end
            if not equal(check, current) then return false, check, "foreign_state", false end
            local mode, permission_err = permission(lane, manager, reason)
            if not mode then return false, current, permission_err, true end
            -- Authorization is an adapter callback, not authority to use a stale
            -- object/snapshot if that callback observed or caused a transition.
            check_manager, check, err = read()
            if not check_manager then return false, nil, err, false end
            if check_manager ~= manager then return false, nil, "manager_replaced", false end
            if not equal(check, current) then return false, check, "foreign_state", false end
            local write_native, write_paused = api.write_native, api.write_paused
            if mode == "local_only" then write_native, write_paused = api.write_native_local, api.write_paused_local end
            if type(write_native) ~= "function" or (expected.paused and type(write_paused) ~= "function") then
                return false, current, "cleanup_local_unavailable", true
            end
            local ok, detail
            if expected.paused then ok, detail = pcall(write_paused, manager)
            else ok, detail = pcall(write_native, manager, expected.index) end
            local observed_manager, observed, read_err = read()
            if not ok then
                report("write_error", {error=tostring(detail):sub(1,240), expected=copy(expected),
                    observed=observed and copy(observed) or nil, read_reason=read_err})
            end
            if not observed_manager then return false, nil, ok and read_err or "write_error", false end
            if observed_manager ~= manager then return false, nil, "manager_replaced", false end
            if not ok or not equal(observed, expected) then
                local key = ok and "write_mismatch" or "write_error"
                if ok then report(key, {expected=copy(expected), observed=copy(observed)}) end
                return false, observed, key, owned_prefix(observed, current, expected)
            end
            current = observed
            if record and record.manager == manager then record.last = copy(current) end
        end
        return true, current
    end
    local function retire()
        record, freeze = nil, nil
        retired_generation = retired_generation + 1
        report("manager_retired")
        return true, "manager_retired"
    end
    local function transition(target, lane, reason, force)
        local manager, before, guard_err = guard(lane)
        if not manager then
            if lane == "cleanup" and guard_err == "manager_retired" then return retire() end
            return false, guard_err
        end
        local newly_owned = record == nil
        if newly_owned then record = {manager=manager, prior=copy(before), last=copy(before)} end
        local ok, observed, err, owned = attempt(manager, before, target, lane, reason, force)
        if ok then record.last = copy(observed); return true end
        if owned and observed then
            record.last = copy(observed)
            local restored, after, rollback_err, rollback_owned = attempt(manager, observed, before, "cleanup", "rollback")
            if restored then
                record.last = copy(after)
                if newly_owned then record = nil end
            else
                if rollback_owned and after then record.last = copy(after) end
                report("rollback_failed", {cause=err, reason=rollback_err})
            end
        else
            report("rollback_refused", {cause=err})
        end
        return false, err -- Original failure remains primary, even after rollback.
    end
    local function selected()
        local ok, value = pcall(mod.get, mod, "time_scale_value")
        if not ok then return nil, "setting_read_error" end
        if not index_ok(value) then return nil, "invalid_index" end
        return value
    end
    local function set_selected(index)
        local old = selected()
        if old == index then return true end
        -- VMF core/settings.lua:46-60 notifies only when argument 3 is true.
        -- Explicit false plus a narrow guard also protects against a bad adapter
        -- synchronously feeding on_setting_changed back into apply_selected.
        selecting = true
        local ok = pcall(mod.set, mod, "time_scale_value", index, false)
        selecting = false
        if not ok then return false, "setting_write_error" end
        local actual, reason = selected()
        if actual ~= index then return false, reason or "setting_write_mismatch" end
        return true
    end
    local function request_stop(reason)
        if not freeze then return true end
        if type(api.request_freeze_stop) ~= "function" then return false, "freeze_stop_missing" end
        local ok, accepted = pcall(api.request_freeze_stop, freeze.lease, reason)
        if not ok then return false, "freeze_stop_error" end
        if accepted == false or freeze then return false, "freeze_stop_incomplete" end
        return true
    end
    function owner:apply(index)
        if selecting then return false, "selection_reentrant" end
        if not index_ok(index) then return false, "invalid_index" end
        local manager, current, reason = guard()
        if not manager then return false, reason end
        if freeze and not equal(current, running(NORMAL)) then return false, "freeze_hold_lost" end
        local ok, err = set_selected(index)
        if not ok then return false, err end
        if freeze then freeze.edited = true; return true, "resume_selected" end
        return transition(running(index))
    end
    function owner:apply_selected()
        local index, reason = selected()
        if not index then return false, reason end
        return self:apply(index)
    end
    function owner:resync()
        if freeze then return false, "freeze_active" end
        if not record then return false, "ownership_missing" end
        local manager, current, reason = guard()
        if not manager then return false, reason end
        local index, err = selected()
        if not index then return false, err end
        if current.paused or not coherent(current) then return false, "resync_state_mismatch" end
        if current.index ~= index then return false, "resync_selection_mismatch" end
        -- Explicit post-admission replay only: one existing native broadcast,
        -- even when local state already matches. Ordinary apply stays deduped.
        return transition(running(index), nil, "resync", true)
    end
    function owner:faster()
        local index, reason = selected()
        if not index then return false, reason end
        return self:apply(math.min(index + 1, #PERCENT))
    end
    function owner:slower()
        local index, reason = selected()
        if not index then return false, reason end
        return self:apply(math.max(index - 1, 1))
    end
    function owner:normal()
        local manager, _, reason = guard()
        if not manager then return false, reason end
        local ok, err = request_stop("normal")
        if not ok then return false, err end
        return self:apply(NORMAL)
    end
    function owner:begin_freeze()
        local manager, before, reason = guard()
        if not manager then return nil, reason end
        if freeze then
            if not equal(before, running(NORMAL)) then return nil, "freeze_hold_lost" end
            return freeze.lease
        end
        local index, err = selected()
        if not index then return nil, err end
        local ok, apply_err = transition(running(NORMAL))
        if not ok then return nil, apply_err end
        freeze = {lease={}, before_index=before.index, selected=index, edited=false}
        return freeze.lease
    end
    function owner:end_freeze(lease)
        if not freeze or lease ~= freeze.lease then return false, "stale_freeze_lease" end
        local manager, _, guard_err = guard("cleanup")
        if not manager then
            if guard_err == "manager_retired" then return retire() end
            return false, guard_err
        end
        local active = authorize()
        if releasing or not active then
            local ok, err = transition(copy(record.prior), "cleanup", releasing or "freeze_authority_lost")
            if not ok then return false, err end
            record, freeze = nil, nil
            return true, err or "restored"
        end
        local index, reason = selected()
        if not index then return false, reason end
        local target = (freeze.edited or index ~= freeze.selected) and index or freeze.before_index
        local ok, err = transition(running(target))
        if not ok then return false, err end
        freeze = nil
        return true
    end
    function owner:release(reason)
        if not record then return true, "idle" end
        if releasing then return false, "cleanup_reentrant" end
        local manager, _, err = guard("cleanup")
        if not manager and err ~= "manager_retired" then return false, err end
        local generation = retired_generation
        releasing = reason or "release"
        local stopped, stop_err = request_stop(reason or "release")
        releasing = nil
        if not stopped then return false, stop_err end
        if not record then return true, retired_generation ~= generation and "manager_retired" or "restored" end
        if err == "manager_retired" then return retire() end
        local ok, restore_err = transition(copy(record.prior), "cleanup", reason or "release")
        if not ok then return false, restore_err end
        record = nil
        return true
    end
    return owner
end
return M
