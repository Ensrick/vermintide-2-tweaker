-- _mod_tweaker_profile_events.lua - bounded owner diagnostics at profile commits.
--
-- Profiles are stored by Mod Tweaker, but only an owning mod can explain what
-- its settings mean at runtime (including host-authoritative effective values).
-- This engine-free registry gives each tab exactly one observer and emits only
-- after a profile transaction has committed. It intentionally carries no
-- setting payload; owners read and bound their own diagnostic snapshots.

local ProfileEvents = {}

function ProfileEvents.new(profiles, store, log)
    assert(type(profiles) == "table" and type(profiles.get_active) == "function",
        "profiles.get_active is required")
    assert(type(store) == "table", "profile store is required")

    local observers = {}
    local api = {}

    function api.get_active(tab_id)
        if type(tab_id) ~= "string" or tab_id == "" then return nil, "tab_id is required" end
        local ok, slot = pcall(profiles.get_active, store, tab_id)
        if not ok then return nil, tostring(slot) end
        return slot
    end

    function api.register(tab_id, callback)
        if type(tab_id) ~= "string" or tab_id == "" then return false, "tab_id is required" end
        if type(callback) ~= "function" then return false, "callback must be a function" end
        observers[tab_id] = callback
        return true
    end

    function api.emit(tab_id, phase)
        local callback = observers[tab_id]
        if not callback then return true, false end
        local slot, err = api.get_active(tab_id)
        if not slot then return false, err end
        local ok, callback_err = pcall(callback, {
            tab_id = tab_id,
            slot = slot,
            phase = tostring(phase or "profile_commit"),
        })
        if not ok then
            if type(log) == "function" then
                pcall(log, "[mt:profile-event] tab=%s callback failed: %s",
                    tostring(tab_id), tostring(callback_err))
            end
            return false, tostring(callback_err)
        end
        return true, true
    end

    return api
end

return ProfileEvents
