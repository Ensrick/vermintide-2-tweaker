return function(H, repo_root)
    local base = repo_root
        .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/"
    local Policy = assert(loadfile(base .. "_gt_disconnect_failure_core.lua"))()

    H.test("GT disconnect diagnostic classifies measured service states", function()
        H.equal(
            Policy.classify(true, false, true),
            "p2p_failed_steam_backend_report_live"
        )
        H.equal(
            Policy.classify(false, false, true),
            "steam_client_unavailable+p2p_failed"
        )
        H.equal(
            Policy.classify(true, true, false),
            "playfab_backend_disconnected"
        )
        H.equal(
            Policy.classify(false, true, true),
            "steam_client_unavailable+playfab_backend_disconnected+p2p_failed"
        )
        H.equal(Policy.classify(nil, nil, false), "insufficient_state")
    end)

    H.test("GT disconnect diagnostic emits transitions rather than frames", function()
        H.equal(Policy.steam_transition(nil, true), false)
        H.equal(Policy.steam_transition(nil, false), true)
        H.equal(Policy.steam_transition(false, false), false)
        H.equal(Policy.steam_transition(false, true), true)

        H.equal(Policy.backend_disconnected_transition(false, true), true)
        H.equal(Policy.backend_disconnected_transition(true, true), false)
        H.equal(Policy.backend_disconnected_transition(nil, false), false)

        H.equal(Policy.network_failure_transition(nil, "broken_connection", nil, nil), true)
        H.equal(Policy.network_failure_transition("broken_connection", "broken_connection", "disconnected", "disconnected"), false)
        H.equal(Policy.network_failure_transition(nil, nil, "connected", "disconnected"), true)
        H.equal(Policy.network_failure_transition(nil, nil, "connected", "connected"), false)
        H.equal(Policy.network_failure_transition(nil, "eac_authorize_failed", "connected", "connected"), false)
    end)

    H.test("GT disconnect diagnostic wires exactly three read-only seams", function()
        local diag_file = assert(io.open(base .. "_gt_diag_disconnect_failure.lua", "rb"))
        local diag = diag_file:read("*a")
        diag_file:close()
        local entry_file = assert(io.open(base .. "general_tweaker_dev.lua", "rb"))
        local entry = entry_file:read("*a")
        entry_file:close()

        H.truthy(diag:find('mod:hook("StateTitleScreenInitNetwork", "_connected_to_steam"', 1, true))
        H.truthy(diag:find('mod:hook("BackendManagerPlayFab", "_update_error_handling"', 1, true))
        H.truthy(diag:find('mod:hook("NetworkClient", "update"', 1, true))
        H.truthy(diag:find('"[gt:753] "', 1, true))
        H.equal(diag:find("network_send", 1, true), nil)
        H.equal(diag:find("mod:echo", 1, true), nil)
        H.truthy(diag:find('rawget(self, "_error_dialog") == nil', 1, true))
        H.truthy(diag:find("and previous ~= true", 1, true))
        H.truthy(entry:find(
            'mod:dofile("scripts/mods/general_tweaker_dev/_gt_diag_disconnect_failure")',
            1,
            true
        ))
    end)
end
