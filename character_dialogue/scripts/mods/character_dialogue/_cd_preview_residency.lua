-- Pure source-to-package and pending-request policy for dialogue preview.
--
-- Fatshark's generated dialogue Lua files identify events, but Wwise can only
-- play them while the bank that owns the event is resident.  Keep this table
-- deliberately small: every entry must be backed by both LevelSettings and a
-- bundle-content audit.  Never derive or load arbitrary level packages from a
-- catalogue filename.
local Residency = {}

Residency.MORRIS_PACKAGE = "resource_packages/dlcs/morris_ingame"
Residency.REFERENCE = "character_dialogue_preview"
Residency.TIMEOUT_SECONDS = 30

function Residency.package_for_source(source)
    if type(source) == "string" and source:find("hero_conversations_dlc_morris_", 1, true) == 1 then
        return Residency.MORRIS_PACKAGE
    end
    return nil
end

function Residency.new_state()
    return {
        package = nil,
        acquired = false,
        pending_event = nil,
        pending_source = nil,
        pending_elapsed = 0,
    }
end

function Residency.request(state, event, source, owned_loaded, owned_loading)
    local package_name = Residency.package_for_source(source)
    if not package_name then return "direct", event, nil end

    state.package = package_name
    state.pending_event = event
    state.pending_source = source
    state.pending_elapsed = 0

    if owned_loaded then
        state.pending_event = nil
        state.pending_source = nil
        return "direct", event, package_name
    end
    if owned_loading then return "pending", nil, package_name end
    return "load", nil, package_name
end

function Residency.poll(state, dt, owned_loaded, owned_loading)
    if not state.pending_event then return "idle" end
    if owned_loaded then
        local event = state.pending_event
        state.pending_event = nil
        state.pending_source = nil
        state.pending_elapsed = 0
        return "ready", event
    end

    state.pending_elapsed = state.pending_elapsed + math.max(0, tonumber(dt) or 0)
    if not owned_loading then
        local event = state.pending_event
        state.pending_event = nil
        state.pending_source = nil
        return "failed", event, "package load stopped before residency"
    end
    if state.pending_elapsed >= Residency.TIMEOUT_SECONDS then
        local event = state.pending_event
        state.pending_event = nil
        state.pending_source = nil
        return "failed", event, "package load timed out"
    end
    return "pending"
end

function Residency.cancel(state, keep_package)
    state.pending_event = nil
    state.pending_source = nil
    state.pending_elapsed = 0
    if state.package ~= keep_package then
        state.package = nil
        state.acquired = false
    end
end

return Residency
