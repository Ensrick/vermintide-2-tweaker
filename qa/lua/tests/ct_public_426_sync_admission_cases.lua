-- SharedState sync and pre-GameObject admission cases for the public #426 owner.

return function(H, with_fixture, power_up, make_run_state, attach_run_state)
    H.test("CT public #426 SharedState request sync strips before native send", function()
        with_fixture({ safe = false }, function(f)
            local native = power_up("natural_bond", 1)
            local state = make_run_state(
                { native, power_up("ct_meta_crit", 2) }, {})
            attach_run_state(state)
            local calls = 0
            local shared = {
                _is_server = true,
                _original_context = "deus_run_state_test",
                _context = "deus-context",
            }
            f.hooks["SharedState.rpc_shared_state_request_sync"](
                function()
                    calls = calls + 1
                    local values = state._shared_state._server_state
                        .power_ups.owner[1][2][3][0]
                    H.equal(#values, 1)
                    H.equal(values[1], native)
                end, shared, 9, "deus-context")
            H.equal(calls, 1)
            H.equal(f.calls.require_peer[1], "remote")
        end)
    end)

    H.test("CT public #426 proof exceptions fall back to strip containment", function()
        with_fixture({ safe = false, throw_require = true }, function(f)
            local native = power_up("natural_bond", 1)
            local state = make_run_state(
                { native, power_up("ct_meta_crit", 2) }, {})
            attach_run_state(state)
            local sent = 0
            f.hooks["SharedState.rpc_shared_state_request_sync"](
                function()
                    sent = sent + 1
                    H.deep_equal(state._shared_state._server_state.power_ups
                        .owner[1][2][3][0], { native })
                end,
                { _is_server = true,
                    _original_context = "deus_run_state_test",
                    _context = "deus-context" }, 9, "deus-context")
            H.equal(sent, 1)
            H.deep_equal(f.calls.require_peer, { "remote" })
        end)
    end)

    H.test("CT public #426 SharedState request fence preserves exact and unrelated paths", function()
        with_fixture({ safe = true }, function(f)
            local state = make_run_state({ power_up("ct_meta_crit", 2) }, {})
            attach_run_state(state)
            local calls = 0
            local shared = {
                _is_server = true,
                _original_context = "deus_run_state_test",
                _context = "deus-context",
            }
            local hook = f.hooks["SharedState.rpc_shared_state_request_sync"]
            hook(function() calls = calls + 1 end, shared, 9, "deus-context")
            H.equal(calls, 1)
            H.equal(#state._shared_state._server_state.power_ups
                .owner[1][2][3][0], 1)

            f.peer_state.peer = false
            f.peer_state.all = false
            f.peer_state.applied = "disabled"
            local proofs = #f.calls.require_peer
            hook(function() calls = calls + 1 end, shared, 99, "wrong-context")
            H.equal(calls, 2)
            H.equal(#f.calls.require_peer, proofs,
                "wrong-context request mutated parity proof")
            H.equal(#state._shared_state._server_state.power_ups
                .owner[1][2][3][0], 1,
                "wrong-context request stripped state")

            shared._original_context = "inventory_state"
            hook(function() calls = calls + 1 end, shared, 99, "deus-context")
            H.equal(calls, 3)
            H.equal(#f.calls.require_peer, proofs)
        end)
    end)

    H.test("CT public #426 SharedState request strip failure rejects via class method", function()
        with_fixture({ safe = false }, function(f)
            rawset(_G, "Managers", { player = { is_server = false } })
            local kicks, native = 0, 0
            local server = setmetatable({}, { __index = {
                kick_peer = function(_, peer)
                    if peer == "remote" then kicks = kicks + 1 end
                end,
            } })
            local shared = {
                _is_server = true,
                _original_context = "deus_run_state_test",
                _context = "deus-context",
                _network_server = server,
            }
            f.hooks["SharedState.rpc_shared_state_request_sync"](
                function() native = native + 1 end,
                shared, 9, "deus-context")
            H.equal(native, 0)
            H.equal(kicks, 1)
        end)
    end)

    H.test("CT public #426 peer connection closes producers without destroying pre-ack state", function()
        with_fixture({ safe = true }, function(f)
            local native = power_up("natural_bond", 1)
            local state = make_run_state(
                { native, power_up("ct_meta_crit", 2) }, {})
            attach_run_state(state)
            local admitted = 0
            f.hooks["NetworkServer.peer_connected"](function()
                admitted = admitted + 1
                local values = state._shared_state._server_state
                    .power_ups.owner[1][2][3][0]
                H.equal(#values, 2,
                    "pre-ack connection destroyed valid CT state before proof")
                H.equal(values[1], native)
                local written
                f.hooks["DeusRunState.set_player_power_ups"](
                    function(_, _, _, _, _, next_values) written = next_values end,
                    state, "owner", 1, 2, 3,
                    { native, power_up("ct_meta_health", 4) })
                H.equal(#written, 1,
                    "writer emitted CT during native peer admission")
            end, { my_peer_id = "host" }, "joining")
            H.equal(admitted, 1)
            H.equal(f.calls.require_peer[#f.calls.require_peer], "joining")
        end)
    end)

    H.test("CT public #426 pre-GameObject fence strips unproven state before native", function()
        with_fixture({ safe = true }, function(f)
            local native = power_up("natural_bond", 1)
            local state = make_run_state(
                { native, power_up("ct_meta_crit", 2) }, {})
            attach_run_state(state)
            local connected, synchronizing, predicate = 0, 0, 0
            f.hooks["NetworkServer.peer_connected"](
                function() connected = connected + 1 end,
                { my_peer_id = "host" }, "joining")
            H.equal(connected, 1)
            f.hooks["GameNetworkManager.set_peer_synchronizing"](function()
                synchronizing = synchronizing + 1
                local values = state._shared_state._server_state
                    .power_ups.owner[1][2][3][0]
                H.equal(#values, 1)
                H.equal(values[1], native)
            end, { network_server = { my_peer_id = "host" } }, "joining")
            H.equal(synchronizing, 1)
            local result = f.hooks[
                "NetworkServer.is_network_state_fully_synced_for_peer"](
                function() predicate = predicate + 1; return true end,
                { my_peer_id = "host" }, "joining")
            H.equal(result, true)
            H.equal(predicate, 1)
        end)
    end)

    H.test("CT public #426 exact pre-GameObject peer retains state", function()
        with_fixture({ safe = true }, function(f)
            local state = make_run_state({ power_up("ct_meta_crit", 2) }, {})
            attach_run_state(state)
            f.hooks["NetworkServer.peer_connected"](
                function() end, { my_peer_id = "host" }, "remote")
            local synchronizing = 0
            f.hooks["GameNetworkManager.set_peer_synchronizing"](
                function() synchronizing = synchronizing + 1 end,
                { network_server = { my_peer_id = "host" } }, "remote")
            H.equal(synchronizing, 1)
            H.equal(#state._shared_state._server_state.power_ups
                .owner[1][2][3][0], 1)
            local native = 0
            H.equal(f.hooks[
                "NetworkServer.is_network_state_fully_synced_for_peer"](
                function() native = native + 1; return true end,
                { my_peer_id = "host" }, "remote"), true)
            H.equal(native, 1)
        end)
    end)

    H.test("CT public #426 pre-GameObject cleanup failure holds outside GameSession", function()
        with_fixture({ safe = false }, function(f)
            rawset(_G, "Managers", { player = { is_server = false } })
            local kicks, admitted = 0, 0
            local server = setmetatable({ my_peer_id = "host" }, { __index = {
                kick_peer = function(_, peer)
                    if peer == "joining" then kicks = kicks + 1 end
                end,
            } })
            f.hooks["NetworkServer.peer_connected"](
                function() admitted = admitted + 1 end, server, "joining")
            H.equal(admitted, 1,
                "NetworkState admission is the handshake transport boundary")
            local synchronizing = 0
            f.hooks["GameNetworkManager.set_peer_synchronizing"](
                function() synchronizing = synchronizing + 1 end,
                { network_server = server }, "joining")
            H.equal(synchronizing, 0)
            H.equal(kicks, 1)
            local predicate = 0
            H.equal(f.hooks[
                "NetworkServer.is_network_state_fully_synced_for_peer"](
                function() predicate = predicate + 1; return true end,
                server, "joining"), false)
            H.equal(predicate, 0)

            local proofs = #f.calls.require_peer
            local local_sync, local_predicate = 0, 0
            f.hooks["GameNetworkManager.set_peer_synchronizing"](
                function() local_sync = local_sync + 1 end,
                { network_server = server }, "host")
            H.equal(local_sync, 1)
            H.equal(f.hooks[
                "NetworkServer.is_network_state_fully_synced_for_peer"](
                function() local_predicate = local_predicate + 1; return true end,
                server, "host"), true)
            H.equal(local_predicate, 1)
            H.equal(#f.calls.require_peer, proofs,
                "server's own peer id entered the proof fence")
        end)
    end)
end
