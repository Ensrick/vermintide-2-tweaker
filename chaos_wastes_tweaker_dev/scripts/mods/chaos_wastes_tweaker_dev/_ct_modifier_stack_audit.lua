-- Observation-only multiple-modifier feasibility audit (#289).
local mod = get_mod("ct_dev")
local Policy = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_modifier_stack_policy")
local M = { rt_checks = {} }
local CAP, captures = 3, 0

local function _manager_state()
    return Managers and Managers.state and Managers.state.game_mode
end

local function _controller()
    local manager = Managers and Managers.mechanism
    local mechanism = manager and manager.game_mechanism and manager:game_mechanism()
    return mechanism and mechanism.get_deus_run_controller
        and mechanism:get_deus_run_controller() or nil
end

local function _snapshot()
    local controller = _controller()
    local node = controller and controller.get_current_node and controller:get_current_node() or nil
    local game_mode_manager = _manager_state()
    local game_mode = game_mode_manager and game_mode_manager._game_mode
    local handler = game_mode_manager and game_mode_manager._mutator_handler
    local effective = {}
    if game_mode and type(game_mode.mutators) == "function" then
        local ok, value = pcall(game_mode.mutators, game_mode)
        if ok and type(value) == "table" then effective = value end
    end
    local events = controller and controller.get_event_mutators
        and controller:get_event_mutators() or {}
    return {
        completed = controller and controller.get_completed_level_count
            and controller:get_completed_level_count() or 0,
        node_curse = node and node.curse,
        minor = node and node.minor_modifier_group or {},
        events = events,
        effective = effective,
        active = handler and handler._active_mutators or {},
        base_count = 1,
        levels_per_step = 2,
        maximum = 3,
        is_server = game_mode_manager and game_mode_manager.is_server,
    }
end

local function _report(reason)
    if captures >= CAP then return end
    local snapshot = _snapshot()
    if #snapshot.effective == 0 and not _controller() then return end
    captures = captures + 1
    local lookup = rawget(_G, "NetworkLookup")
    local result = Policy.inspect(snapshot, rawget(_G, "MutatorTemplates"),
        lookup and lookup.mutator_templates)
    printf("[ct:289] audit=%d/%d reason=%s role=%s completed=%d ramp_target=%d node_curse=%s minor=%d events=%d effective=%s active=%s packages=%d missing_template=%d missing_wire=%d duplicates=%d transport_ready=%s",
        captures, CAP, tostring(reason), snapshot.is_server and "host" or "client",
        result.completed, result.target, result.node_curse, #result.minor,
        #result.events, result.effective_signature, result.active_signature,
        #result.package_names, #result.missing_template, #result.missing_wire,
        result.duplicate_count, tostring(result.transport_ready))
    printf("[ct:289] schema=node.curse:singular ramp_blocked=%s activation=disabled compare_host_client=effective+active signatures",
        tostring(result.singular_node_schema_blocks_ramp))
end

mod:command("ct_modifier_stack_audit", "Capture multiple-modifier feasibility (#289)", function()
    _report("command")
end)

local previous_state_changed = mod.on_game_state_changed
mod.on_game_state_changed = function(status, state_name)
    if previous_state_changed then previous_state_changed(status, state_name) end
    if status == "enter" and state_name == "StateIngame" then
        _report("StateIngame")
    end
end

M.rt_checks[#M.rt_checks + 1] = {
    name = "issue289_modifier_stack_feasibility",
    fn = function()
        local lookup = rawget(_G, "NetworkLookup")
        local result = Policy.inspect(_snapshot(), rawget(_G, "MutatorTemplates"),
            lookup and lookup.mutator_templates)
        if result.target < 1 or result.target > 3 then
            return "modifier ramp target escaped the audited 1..3 bound: " .. tostring(result.target)
        end
        if #result.effective > 0 and not result.transport_ready then
            return string.format("live stack not transport-ready template/wire/dupes=%d/%d/%d",
                #result.missing_template, #result.missing_wire, result.duplicate_count)
        end
    end,
}

if type(mod._ct_rt_register) == "function" then
    for _, check in ipairs(M.rt_checks) do
        mod._ct_rt_register(check.name, check.fn)
    end
end

return M
