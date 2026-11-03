-- General time-control composition and public dispatch (#1801/#1802).
-- Loaded once by the main manifest; owns no native hook registration.
-- Factories retain exact native identities; engine-phase hooks call the small
-- dispatch surface below. No movement is run from the VMF update callback.
-- Public: gt_time_*/gt_pause_toggle plus _gt_time_* lifecycle/phase dispatch.
-- Dependencies: main-owned _gt_time_modules and canonical realm authority.
local mod = get_mod("gt_dev")
local modules = assert(mod._gt_time_modules, "time factory manifest missing")
local realm = assert(mod._gt_modded_realm_authority, "time realm authority missing")
local state_object, pending_apply, busy = nil, false, false
local freeze, owner
-- A persisted target is not an applied native speed. Until the first owned
-- success, refused slow presets roll the UI back to the safe normal baseline.
local last_selected = modules.Owner.NORMAL_INDEX
local context = modules.Context.new(mod, realm, function() return state_object end)
local report_count = {}

local function report(event, detail)
    -- This diagnostic is bounded per event, including repeated refused keys.
    report_count[event] = (report_count[event] or 0) + 1
    if report_count[event] > 8 then return end
    if type(detail) == "table" then
        detail = detail.reason or detail.cause or detail.error or "state_mismatch"
    end
    if type(printf) == "function" then
        printf("[gt:time] %s reason=%s", tostring(event):sub(1, 64), tostring(detail):sub(1, 240))
    end
end
local function set_freeze_ui()
    -- VMF core/settings.lua:46-60: false suppresses on_setting_changed.
    mod._gt_pause_active = freeze and freeze:is_active() or false
    mod:set("gt_world_freeze_enabled", mod._gt_pause_active, false)
end
local function bound(id)
    local keys = mod:get(id)
    return type(keys) == "table" and #keys > 0
end
local function recovery_bound()
    return bound("pause_hotkey") or bound("gt_time_normal_hotkey")
end
local function stop_freeze(reason)
    local ok, why = true, nil
    if freeze then ok, why = freeze:cleanup(reason) end
    set_freeze_ui()
    return ok, why
end
local function guarded(action)
    if busy then return false, "reentrant_control" end
    busy = true
    local ok, accepted, reason = pcall(action)
    busy = false
    if not ok then report("control_error", accepted); return false, "control_error" end
    if accepted ~= true then report("refused", reason) end
    return accepted == true, reason
end
local api = {
    authorize = context.authorize,
    authorize_cleanup = context.authorize_cleanup,
    read_native = context.read_native,
    write_native = function(manager, index) manager:set_time_scale(index) end,
    write_native_local = function(manager, index) manager:set_time_scale(index, true) end,
    write_paused = function(manager) manager:set_time_paused() end,
    write_paused_local = function(manager)
        -- Exact no-RPC prefix of DebugManager.set_time_paused:732-745.
        -- Used only by proven ownership cleanup after synchronized authority ends.
        Application.set_time_step_policy("external_multiplier", 1e-08)
        rawset(_G, "GLOBAL_TIME_SCALE", 1e-08)
        manager.time_paused = true
    end,
    request_freeze_stop = function(_, reason) return stop_freeze(reason) end,
    diagnostic = report,
}
owner = modules.Owner.new(mod, api)
local freeze_api = {
    resolve_context = context.resolve_context,
    world_live = context.world_live,
    game_identity = context.game_identity,
    world_paused = function(world) return World.get_data(world, "paused") == true end,
    set_world_paused = function(world, paused)
        if not context.world_live(world) then error("world_not_current", 0) end
        if paused then ScriptWorld.pause(world) else ScriptWorld.unpause(world) end
    end,
    local_scale = function(tm) return tm:local_scale("game") end,
    set_local_scale = function(tm, value) tm:set_local_scale("game", value) end,
    game_time = function(tm) return tm:time("game") end,
    wall_time = function() return Application.time_since_launch() end,
    frame_id = function() return rawget(_G, "GLOBAL_FRAME_INDEX") end,
    report = report,
    driver_factory = function()
        local templates = rawget(_G, "LocomotionTemplates")
        if type(templates) ~= "table" then error("locomotion_templates_unavailable", 0) end
        return modules.Driver.new({ engine = {
            CharacterStateHelper = CharacterStateHelper,
            PlayerLocomotionTemplate = templates.PlayerUnitLocomotionExtension,
            Unit = Unit, POSITION_LOOKUP = POSITION_LOOKUP,
            PlayerUnitMovementSettings = PlayerUnitMovementSettings,
        } })
    end,
}
freeze = modules.Freeze.new(mod, freeze_api, {
    begin_freeze = function() return owner:begin_freeze() end,
    end_freeze = function(lease) return owner:end_freeze(lease) end,
})
-- Freeze is deliberately transient, never restored from yesterday's setting.
set_freeze_ui()

local function apply(index)
    return guarded(function()
        if modules.Owner.multiplier(index) == nil then return false, "invalid_index" end
        if index < modules.Owner.NORMAL_INDEX and not recovery_bound() then
            mod:set("time_scale_value", last_selected, false)
            return false, "assign_recovery_hotkey"
        end
        local ok, reason = owner:apply(index)
        if ok then last_selected = index end
        return ok, reason
    end)
end
mod.gt_time_apply = function() return apply(mod:get("time_scale_value")) end
mod.gt_time_faster = function()
    local index = mod:get("time_scale_value")
    if modules.Owner.multiplier(index) == nil then return false, "invalid_index" end
    return apply(math.min(index + 1, 24))
end
mod.gt_time_slower = function()
    local index = mod:get("time_scale_value")
    if modules.Owner.multiplier(index) == nil then return false, "invalid_index" end
    return apply(math.max(index - 1, 1))
end
mod.gt_time_normal = function()
    return guarded(function()
        local ok, reason = owner:normal()
        if ok then last_selected = modules.Owner.NORMAL_INDEX end
        set_freeze_ui()
        return ok, reason
    end)
end
mod.gt_pause_toggle = function()
    return guarded(function()
        if freeze:is_active() then return stop_freeze("toggle") end
        if not bound("pause_hotkey") then return false, "assign_freeze_hotkey" end
        local ok, reason = freeze:enable()
        if not ok and not freeze:has_pending_cleanup() then
            -- A lone global Freeze key is also a recovery key for slow time.
            -- Unsupported movement/death must not strand the UI at tiny speed.
            local _, current = context.read_native()
            if current and type(current.index) == "number" and current.index < 13 then
                local recovered = owner:normal()
                if recovered then
                    last_selected = modules.Owner.NORMAL_INDEX
                    set_freeze_ui()
                    report("normal_recovery", reason)
                    return true, "normal_recovery"
                end
            end
        end
        set_freeze_ui()
        return ok, reason
    end)
end

mod._gt_time_outer_dt = function(state, phase, dt)
    state_object = state
    if freeze:has_pending_cleanup() then freeze:cleanup("cleanup_retry") end
    if pending_apply and phase == "pre_update" then
        pending_apply = false
        if mod:get("time_scale_value") ~= modules.Owner.NORMAL_INDEX then mod.gt_time_apply() end
    end
    local result = freeze:outer_dt(state, phase, dt)
    if mod._gt_pause_active ~= freeze:is_active() then set_freeze_ui() end
    return result
end
mod._gt_time_entity_phase = function(entity, phase, dt)
    local handled = freeze:on_entity_phase(entity, phase, dt)
    if mod._gt_pause_active ~= freeze:is_active() then set_freeze_ui() end
    return handled
end
mod._gt_time_world_frozen = function() return freeze:is_active() end
mod._gt_time_on_setting = function(id)
    if id == "time_scale_value" then mod.gt_time_apply(); return true end
    if id == "gt_world_freeze_enabled" then
        if (mod:get(id) == true) ~= freeze:is_active() then mod.gt_pause_toggle() end
        set_freeze_ui()
        return true
    end
    if id == "pause_hotkey" or id == "gt_time_normal_hotkey" then
        if freeze:is_active() and not bound("pause_hotkey") then stop_freeze("recovery_key_removed") end
        local selected = mod:get("time_scale_value")
        if not recovery_bound() and modules.Owner.multiplier(selected) ~= nil
                and selected < modules.Owner.NORMAL_INDEX then
            mod.gt_time_normal()
        end
        return true
    end
    return false
end
mod._gt_time_disable = function(reason)
    stop_freeze(reason or "disabled")
    local ok, why = owner:release(reason or "disabled")
    if not ok then report("cleanup_pending", why) end
    pending_apply = false
    return ok, why
end
mod._gt_time_on_state = function(status, name)
    if status == "exit" then
        mod._gt_time_disable("state_exit")
        state_object = nil
    elseif status == "enter" then
        state_object = nil
        pending_apply = name == "StateIngame"
        set_freeze_ui()
    end
end
mod._gt_time_before_hotjoin = function()
    local ok, why = stop_freeze("peer_arrival")
    if not ok then report("hotjoin_cleanup_pending", why) end
    return ok, why
end
mod._gt_time_after_hotjoin = function()
    -- Native hot_join_sync broadcasts before removing the joining peer ignore.
    -- Reapply only after the original returns; selector/ownership checks still run.
    if freeze:is_active() or freeze:has_pending_cleanup() then return false, "cleanup_pending" end
    local ok, reason = owner:resync()
    if not ok and reason ~= "ownership_missing" then report("resync_refused", reason) end
    return ok, reason
end

mod:command("pause", "Toggle solo world freeze (assign Freeze / Resume hotkey first)", mod.gt_pause_toggle)
mod:command("freeze", "Toggle solo world freeze (assign Freeze / Resume hotkey first)", mod.gt_pause_toggle)
mod:command("time_faster", "Increase host game speed by one preset", mod.gt_time_faster)
mod:command("time_slower", "Decrease host game speed by one preset", mod.gt_time_slower)
mod:command("time_normal", "Release freeze and restore normal host game speed", mod.gt_time_normal)

-- Diagnostic surface is observational; exact source/phase wiring is checked by QA.
mod._gt_time_control_owner = owner
mod._gt_time_freeze_owner = freeze

mod._gt_rt_register("issue1801_world_freeze_owner", function()
    if not mod._gt_time_hooks_armed then return "world-freeze phase hooks are not armed" end
    if type(mod._gt_time_outer_dt) ~= "function"
            or type(mod._gt_time_entity_phase) ~= "function"
            or type(mod._gt_time_before_hotjoin) ~= "function"
            or type(mod._gt_time_disable) ~= "function" then
        return "world-freeze dispatch is incomplete"
    end
    if freeze:has_pending_cleanup() then return "owned freeze cleanup is still pending" end
    if freeze:is_active() then
        local ctx = context.resolve_context()
        if not (ctx.world and context.world_live(ctx.world)
                and World.get_data(ctx.world, "paused") == true
                and ctx.time_manager and ctx.time_manager:local_scale("game") == 0
                and ctx.humans == 1 and ctx.pending_peers == 0) then
            return "active freeze no longer owns its current solo world/timer"
        end
    end
    -- Observation only: this does not prove native mover/physics acceptance.
end)
mod._gt_rt_register("issue1802_native_time_controls", function()
    if not mod._gt_time_hooks_armed then return "time-control phase hooks are not armed" end
    if type(owner.resync) ~= "function" or type(mod.gt_time_normal) ~= "function"
            or type(mod.gt_time_apply) ~= "function" then return "native time dispatch is incomplete" end
    local manager = select(1, context.read_native())
    if not manager then return "native time manager is unavailable" end
    if type(manager.time_scale_list) ~= "table" or #manager.time_scale_list ~= 24 then
        return "native time preset list changed"
    end
    local rows = modules.Owner.presets()
    for index = 1, #rows do
        if manager.time_scale_list[index] ~= rows[index].percent then
            return "native time preset mapping changed at index " .. tostring(index)
        end
    end
end)
