-- Engine-free single-owner preview state machine.
local Preview = {}

function Preview.transition(state, action, event)
    state = state or {}
    if action == "stop" then return { event = nil, paused = false }, state.event ~= nil end
    if action == "play" then
        if type(event) ~= "string" or event == "" then return state, false, "no dialogue selected" end
        return { event = event, paused = false }, state.event ~= nil
    end
    if action == "pause" then
        if not state.event or state.paused then return state, false, "nothing is playing" end
        return { event = state.event, paused = true }, false
    end
    if action == "resume" then
        if not state.event or not state.paused then return state, false, "nothing is paused" end
        return { event = state.event, paused = false }, false
    end
    return state, false, "unknown preview action"
end

return Preview
