-- Issue #257: bounded, engine-free policy for the automatic Well of Dreams
-- cutscene trace. The authored level-flow graph is not present in the Lua source
-- checkout, so the runtime callback order and event names must be observed before
-- changing cutscene behavior.

local M = {
    target_level = "dlc_termite_3",
    max_events = 32,
}

function M.new()
    return { system = nil, count = 0, capped = false }
end

-- Mirrors the production swallow precedence in _gut_cutscenes.lua's
-- flow_cb_cutscene_effect (ROUND 3): one-shot, then deferred-skip pending,
-- then the skipped episode's window, then the pre-identity intro watch.
-- The two trailing args are optional so pre-ROUND-3 3-arg callers (and the
-- offline probe test) keep their exact legacy behavior.
function M.fade_disposition(name, skip_next_fade, post_skip_guard, pending_skip, intro_watch)
    if name ~= "fx_fade" then return "pass_nonfade" end
    if skip_next_fade then return "swallow_one_shot" end
    if pending_skip then return "swallow_pending" end
    if post_skip_guard then return "swallow_post_skip" end
    if intro_watch then return "swallow_intro_watch" end
    return "pass_fade"
end

function M.record(state, level, system, phase, fields)
    if type(state) ~= "table" or level ~= M.target_level then return nil end
    if state.system ~= system then
        state.system, state.count, state.capped = system, 0, false
    end
    if state.count >= M.max_events then
        if state.capped then return nil end
        state.capped = true
        return { seq = M.max_events + 1, phase = "cap", capped = true }
    end
    state.count = state.count + 1
    local out = { seq = state.count, phase = phase, capped = false }
    for k, v in pairs(fields or {}) do out[k] = v end
    return out
end

M.rt_checks = {
    {
        name = "issue257_well_of_dreams_cutscene_probe",
        fn = function()
            if M.target_level ~= "dlc_termite_3" or M.max_events ~= 32 then
                return "#257 target or event bound drifted"
            end
            if M.fade_disposition("fx_fade", true, false) ~= "swallow_one_shot"
                or M.fade_disposition("fx_fade", false, true) ~= "swallow_post_skip"
                or M.fade_disposition("fx_fade", false, false) ~= "pass_fade"
                or M.fade_disposition("fx_fade", false, false, true) ~= "swallow_pending"
                or M.fade_disposition("fx_fade", false, false, false, true) ~= "swallow_intro_watch"
                or M.fade_disposition("fx_fade", false, true, true) ~= "swallow_pending" then
                return "#257 fade classifier no longer mirrors production precedence"
            end
        end,
    },
}

return M
