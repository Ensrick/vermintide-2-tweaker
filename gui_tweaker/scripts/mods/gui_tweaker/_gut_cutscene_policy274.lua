-- Pure policy for issue #274. Kept engine-free so the rule can be exhausted
-- offline instead of relying on another full mission playthrough.

local M = {}

M.INTRO_SKIP_EVENT = "cs_01_skip"
M.POST_INTRO_GUARD_SECONDS = 15

function M.classify(event_on_skip)
    if event_on_skip == M.INTRO_SKIP_EVENT then
        return "intro"
    end
    if event_on_skip == nil then
        return "locked"
    end
    return "non_intro"
end

function M.is_intro(event_on_skip)
    return M.classify(event_on_skip) == "intro"
end

function M.guard_is_active(owner, system, remaining)
    return owner ~= nil and owner == system and (tonumber(remaining) or 0) > 0
end

function M.tick_guard(remaining, dt)
    remaining = tonumber(remaining) or 0
    dt = tonumber(dt) or 0
    if remaining <= 0 then return 0 end
    if dt < 0 then dt = 0 end
    return math.max(0, remaining - dt)
end

return M
