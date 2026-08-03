-- Observation-only save/resume feasibility audit (#141).
local mod = get_mod("ct_dev")
local Policy = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_resume_policy")
local M = { rt_checks = {} }
-- #141 audit repair (2026-08-03): CAP was 2 and the automatic StateIngame
-- report consumed both, so manual /ct_resume_audit calls no-op'd for the rest
-- of the session. CAP is now 6 with the last MANUAL_RESERVE captures reserved
-- for the manual command, so at least two manual captures survive any session
-- length. Still observation-only: no writes, no setters.
local CAP, MANUAL_RESERVE, captures = 6, 2, 0

local function controller()
    local manager = Managers and Managers.mechanism
    local mechanism = manager and manager:game_mechanism()
    if mechanism and type(mechanism.get_deus_run_controller) == "function" then
        return mechanism:get_deus_run_controller()
    end
end

local function report(reason, manual)
    local budget = manual and CAP or (CAP - MANUAL_RESERVE)
    if captures >= budget then return end
    captures = captures + 1
    local ctrl = controller()
    local result = Policy.inspect(ctrl)
    printf("[ct:141] audit=%d/%d reason=%s controller=%s run_state=%s server=%s config=%d/%d values=%d progress=%d/%d values=%d shared=%s full_sync=%s player_read=%s/%s/%s player_write=%s/%s/%s config_missing=%s progress_missing=%s mutation=false",
        captures, CAP, tostring(reason), tostring(result.controller), tostring(result.run_state),
        tostring(result.server), result.config_methods, #Policy.CONFIG_GETTERS,
        result.config_values, result.progress_methods, #Policy.PROGRESS_GETTERS,
        result.progress_values, tostring(result.shared_state), tostring(result.full_sync),
        tostring(result.player_power_ups), tostring(result.player_currency), tostring(result.player_loadout),
        tostring(result.set_power_ups), tostring(result.set_currency), tostring(result.set_loadout),
        Policy.joined_missing(ctrl, Policy.CONFIG_GETTERS),
        Policy.joined_missing(ctrl and ctrl._run_state, Policy.PROGRESS_GETTERS))
end

mod:command("ct_resume_audit", "Capture Chaos Wastes save/resume readiness (#141)", function()
    report("command", true)
end)

local previous = mod.on_game_state_changed
mod.on_game_state_changed = function(status, state_name)
    if previous then previous(status, state_name) end
    if status == "enter" and state_name == "StateIngame" then report("StateIngame") end
end

M.rt_checks[#M.rt_checks + 1] = {
    name = "issue141_resume_surface_inventory",
    fn = function()
        local result = Policy.inspect(controller())
        if result.controller and result.config_methods < #Policy.CONFIG_GETTERS then
            return "live Deus controller is missing run-config getters"
        end
        if result.run_state and result.progress_methods < #Policy.PROGRESS_GETTERS then
            return "live Deus state is missing progress getters"
        end
    end,
}

if type(mod._ct_rt_register) == "function" then
    for _, check in ipairs(M.rt_checks) do mod._ct_rt_register(check.name, check.fn) end
end

return M
