-- Issue #350: engine-free Chest of Trials early-reward policy.
-- Network state RUNNING remains authoritative until vanilla completes the terror
-- event; this policy only decides local presentation and reward availability.

local M = {
    WAITING = 1,
    RUNNING = 2,
    OPEN = 3,
}

function M.reward_available(enabled, network_state, reward_collected)
    return enabled == true and network_state == M.RUNNING and reward_collected ~= true
end

function M.after_update(state, enabled, network_state, reward_collected)
    if type(state) ~= "table" then return nil end
    if network_state == M.RUNNING and enabled == true and not state.early_opened then
        state.early_opened = true
        return "open_presentation"
    end
    if network_state == M.OPEN and state.early_opened and reward_collected == true
        and not state.looted_restored then
        state.looted_restored = true
        return "restore_looted"
    end
    return nil
end

M.rt_checks = {
    {
        name = "issue350_cot_early_reward_policy",
        fn = function()
            if M.reward_available(true, M.RUNNING, false) ~= true
                or M.reward_available(true, M.OPEN, false) ~= false
                or M.reward_available(false, M.RUNNING, false) ~= false then
                return "#350 reward availability escaped the opt-in RUNNING state"
            end
            local state = {}
            if M.after_update(state, true, M.RUNNING, false) ~= "open_presentation"
                or M.after_update(state, true, M.RUNNING, false) ~= nil
                or M.after_update(state, false, M.OPEN, true) ~= "restore_looted"
                or M.after_update(state, true, M.OPEN, true) ~= nil then
                return "#350 per-chest presentation actions are not one-shot"
            end
        end,
    },
}

return M
