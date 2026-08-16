-- _cd_preview_policy.lua — engine-free preview state machine + isolation ownership.
--
-- Owns two pure decision surfaces: (1) the single-owner preview playback
-- transitions (play/pause/resume/stop), and (2) the #998 audio-isolation
-- ownership tokens. Isolation has exactly two owners — "manual" (/cd_isolate
-- command + keybind) and "preview" (automatic isolation while an enabled
-- preview session plays). The buses mute when the FIRST owner acquires and
-- restore when the LAST owner releases, so the owners compose without ever
-- clobbering the player's saved volumes or double-restoring. No engine calls
-- live here; character_dialogue.lua applies the returned actions to Wwise.
--
-- Owned by: character_dialogue.lua entry point. Consumed via: mod:dofile.
local Preview = {}

Preview.MANUAL_OWNER = "manual"
Preview.PREVIEW_OWNER = "preview"

function Preview.isolation_new() return {} end

-- Pure set arbitration. Returns the next owner set and the engine action the
-- caller must apply: "mute" (first owner in), "restore" (last owner out), or
-- "none". The input set is returned UNCHANGED (same table) when membership
-- does not change, so callers can detect real edges by table identity.
function Preview.isolation_acquire(owners, owner)
    owners = owners or {}
    if not owner or owners[owner] then return owners, "none" end
    local out = {}
    for k, v in pairs(owners) do out[k] = v end
    out[owner] = true
    return out, (next(owners) == nil) and "mute" or "none"
end

function Preview.isolation_release(owners, owner)
    owners = owners or {}
    if not owner or not owners[owner] then return owners, "none" end
    local out = {}
    for k, v in pairs(owners) do out[k] = v end
    out[owner] = nil
    return out, (next(out) == nil) and "restore" or "none"
end

-- #998 Maps one preview lifecycle event to the PREVIEW owner's isolation edge.
--   "play"        trigger succeeded: acquire while the toggle is enabled.
--   "replace"     teardown inside a replacement: hold the token so swapping
--                 lines never flickers restore->mute inside one click.
--   "play_failed" the play attempt died after teardown: never leak the token.
--   "stop"        any real termination: manual stop, natural completion,
--                 collapse, view exit, game-state change.
--   "disable"     the automatic-isolation toggle was switched off mid-session.
--   "pause"/"resume" keep ownership: the session still owns playback, and
--                 releasing here would flicker the player's volumes.
function Preview.isolation_edge(event, auto_enabled)
    if event == "play" then return auto_enabled and "acquire" or "release" end
    if event == "replace" then return auto_enabled and "hold" or "release" end
    if event == "play_failed" or event == "stop" or event == "disable" then return "release" end
    return "none"
end

function Preview.progress(elapsed, duration)
    duration = tonumber(duration) or 0
    if duration <= 0 then return 0 end
    return math.max(0, math.min(1, (tonumber(elapsed) or 0) / duration))
end

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
