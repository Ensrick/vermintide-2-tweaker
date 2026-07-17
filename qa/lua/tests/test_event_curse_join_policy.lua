return function(H, repo_root)
    local policy_path = repo_root
        .. "/event_tweaker/scripts/mods/event_tweaker/event_tweaker_curse_join_policy.lua"
    local Policy = assert(loadfile(policy_path))()

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local content = file:read("*a")
        file:close()
        return content
    end

    H.test("Event Tweaker curse session rejects hot joins without changing vanilla open state", function()
        H.equal(Policy.allow_join(true, true), false)
        H.equal(Policy.allow_join(true, false), true)
        H.equal(Policy.allow_join(false, false), false)
        H.equal(Policy.allow_join(false, true), false)
    end)

    H.test("Event Tweaker curse preflight requires parity and a proven closed peer set", function()
        H.equal(Policy.can_arm(true, false), true)
        H.equal(Policy.can_arm(false, false), false)
        H.equal(Policy.can_arm(true, true), false)
        H.equal(Policy.can_arm(true, nil), false)
    end)

    H.test("Event Tweaker detects peers not yet represented in PlayerManager", function()
        local machines = { host = {}, established = {} }
        local players = { established = {} }
        local pending, peer = Policy.has_pending_remote(machines, "host", function(peer_id)
            return players[peer_id]
        end)
        H.equal(pending, false)
        H.equal(peer, nil)

        machines.joining = {}
        pending, peer = Policy.has_pending_remote(machines, "host", function(peer_id)
            return players[peer_id]
        end)
        H.equal(pending, true)
        H.equal(peer, "joining")

        H.equal(Policy.has_pending_remote(nil, "host", function() end), nil)
        H.equal(Policy.has_pending_remote(machines, nil, function() end), nil)
    end)

    H.test("Event Tweaker wires the lock before package curse activation and replication", function()
        local guard = read(repo_root
            .. "/event_tweaker/scripts/mods/event_tweaker/_evt_guard430_curse_parity.lua")
        local selection = read(repo_root
            .. "/event_tweaker/scripts/mods/event_tweaker/_evt_selection.lua")
        local runtime = read(repo_root
            .. "/event_tweaker/scripts/mods/event_tweaker/_evt_cursed_adventure.lua")

        H.truthy(guard:find('mod:hook("GameModeBase", "is_joinable"', 1, true))
        H.truthy(guard:find("JoinPolicy.allow_join(vanilla_joinable, _curse_session_locked)", 1, true))
        H.truthy(guard:find("server.peer_state_machines", 1, true))
        H.truthy(selection:find("set_curse_requested(#out > 0)", 1, true))

        local lock_at = assert(runtime:find("ET.set_curse_session_active(true)", 1, true))
        local preload_at = assert(runtime:find("_maybe_preload_curse_package(name)", lock_at, true))
        local original_at = assert(runtime:find("func(self, name, ...)", preload_at, true))
        H.truthy(lock_at < preload_at and preload_at < original_at,
            "session lock must precede preload and vanilla start_function")
    end)
end
