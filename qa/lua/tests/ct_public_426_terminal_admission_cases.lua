-- Terminal admission and disconnect cases split from the main #426 owner suite
-- to keep each test owner below the repository size ceiling.

return function(H, with_fixture)
    local function shop_receiver()
        return { _run_state = {
            _is_server = true,
            _server_peer_id = "host",
        } }
    end

    H.test("CT public #426 rejected admission cannot revive from a late beacon", function()
        with_fixture({ safe = false }, function(f)
            rawset(_G, "Managers", { player = { is_server = false } })
            local kicks, synchronizing = 0, 0
            local server = {
                my_peer_id = "host",
                kick_peer = function(_, peer)
                    if peer == "remote" then kicks = kicks + 1 end
                end,
            }
            local manager = { network_server = server }
            f.hooks["NetworkServer.peer_connected"](
                function() end, server, "remote")
            f.hooks["GameNetworkManager.set_peer_synchronizing"](
                function() synchronizing = synchronizing + 1 end,
                manager, "remote")
            H.equal(kicks, 1)
            H.equal(synchronizing, 0)

            f.peer_state.peer = true
            f.peer_state.all = true
            f.peer_state.applied = "enabled"
            H.equal(f.mod._ct_wire_safe(), false,
                "late exact proof revived a rejected native connection")
            local buff_id = rawget(f.nl.buff_templates, "ct_miracle_of_ulric")
            local receiver_native = 0
            f.hooks["BuffSystem.rpc_add_buff"](
                function() receiver_native = receiver_native + 1 end,
                { is_server = false }, 9, 1, buff_id, 2, 3, false)
            H.equal(receiver_native, 0,
                "late exact proof revived a rejected receiver route")
            local relay_methods = {
                "rpc_add_buff", "rpc_add_buff_synced",
                "rpc_add_buff_synced_relay", "rpc_add_buff_synced_params",
                "rpc_add_buff_synced_relay_params",
                "rpc_add_volume_buff_multiplier", "rpc_remove_volume_buff",
            }
            for i = 1, #relay_methods do
                local method = relay_methods[i]
                local relay_native = 0
                f.hooks["BuffSystem." .. method](
                    function() relay_native = relay_native + 1 end,
                    { is_server = true }, 9, 1, buff_id, 2, 3, 4)
                H.equal(relay_native, 0,
                    "late exact proof revived rejected host relay " .. method)
            end
            local shop_native = 0
            rawset(_G, "DeusPowerUps", nil)
            local shop_ok = pcall(
                f.hooks["DeusRunController.rpc_deus_shop_power_up_bought"],
                function(_, _, rarity, name)
                    shop_native = shop_native + 1
                    return rawget(_G, "DeusPowerUps")[rarity][name]
                end, shop_receiver(), 9, "exotic", "ct_meta_health", 17, 0)
            H.equal(shop_ok, true,
                "rejected shop route reached the native registry clone")
            H.equal(shop_native, 0,
                "late exact proof reached the pre-clone shop receiver")
            f.hooks["GameNetworkManager.set_peer_synchronizing"](
                function() synchronizing = synchronizing + 1 end,
                manager, "remote")
            H.equal(synchronizing, 0)
            local predicate_native = 0
            H.equal(f.hooks[
                "NetworkServer.is_network_state_fully_synced_for_peer"](
                function() predicate_native = predicate_native + 1; return true end,
                server, "remote"), false)
            H.equal(predicate_native, 0)

            local shared_native = 0
            f.hooks["SharedState.rpc_shared_state_request_sync"](
                function() shared_native = shared_native + 1 end,
                { _is_server = true,
                    _original_context = "deus_run_state_test",
                    _context = "deus-context" }, 9, "deus-context")
            H.equal(shared_native, 0)
            local hot_join_native = 0
            f.hooks["GameNetworkManager.hot_join_sync"](
                function() hot_join_native = hot_join_native + 1 end,
                manager, "remote")
            H.equal(hot_join_native, 0)
        end)
    end)

    H.test("CT public #426 pending unproven admission closes every host relay", function()
        with_fixture({ safe = true }, function(f)
            f.hooks["NetworkServer.peer_connected"](
                function() end, { my_peer_id = "host" }, "joining")

            -- Simulate the underlying roster overlooking the pre-PlayerManager
            -- peer: the explicit admission ledger must still close every relay.
            f.peer_state.all = true
            f.peer_state.applied = "enabled"
            local buff_id = rawget(f.nl.buff_templates, "ct_miracle_of_ulric")
            local relay_methods = {
                "rpc_add_buff", "rpc_add_buff_synced",
                "rpc_add_buff_synced_relay", "rpc_add_buff_synced_params",
                "rpc_add_buff_synced_relay_params",
                "rpc_add_volume_buff_multiplier", "rpc_remove_volume_buff",
            }
            for i = 1, #relay_methods do
                local method = relay_methods[i]
                local native = 0
                f.hooks["BuffSystem." .. method](
                    function() native = native + 1 end,
                    { is_server = true }, 9, 1, buff_id, 2, 3, 4)
                H.equal(native, 0,
                    "pending pre-roster peer escaped host relay " .. method)
            end
        end)
    end)

    H.test("CT public #426 remove-peer cleanup contains both failure directions", function()
        with_fixture({ safe = true, throw_forget = true }, function(f)
            local hook = f.hooks["GameNetworkManager.remove_peer"]
            local value = hook(function() return "native-value" end, {}, "remote")
            H.equal(value, "native-value")
            H.deep_equal(f.calls.forgotten, { "remote" })
            H.equal(f.mod._ct_wire_safe(), false,
                "failed proof retirement reopened the producer floor")

            -- The planted failure preserves the old positive acknowledgement.
            -- A same-id native reconnect must still be tombstoned.
            local server = { my_peer_id = "host" }
            f.hooks["NetworkServer.peer_connected"](
                function() end, server, "remote")
            local sync_native = 0
            f.hooks["GameNetworkManager.set_peer_synchronizing"](
                function() sync_native = sync_native + 1 end,
                { network_server = server }, "remote")
            H.equal(sync_native, 0)
            local predicate_native = 0
            H.equal(f.hooks[
                "NetworkServer.is_network_state_fully_synced_for_peer"](
                function() predicate_native = predicate_native + 1; return true end,
                server, "remote"), false)
            H.equal(predicate_native, 0)
        end)
        with_fixture({ safe = true, throw_forget = true }, function(f)
            local ok, err = pcall(f.hooks["GameNetworkManager.remove_peer"],
                function() error("native-remove-failure") end, {}, "remote")
            H.equal(ok, false)
            H.truthy(tostring(err):find("native-remove-failure", 1, true) ~= nil)
            H.deep_equal(f.calls.forgotten, { "remote" })
            H.equal(f.mod._ct_wire_safe(), false,
                "double cleanup failure reopened the producer floor")
            local server = { my_peer_id = "host" }
            f.hooks["NetworkServer.peer_connected"](
                function() end, server, "remote")
            local sync_native = 0
            f.hooks["GameNetworkManager.set_peer_synchronizing"](
                function() sync_native = sync_native + 1 end,
                { network_server = server }, "remote")
            H.equal(sync_native, 0)
            H.equal(f.hooks[
                "NetworkServer.is_network_state_fully_synced_for_peer"](
                function() return true end, server, "remote"), false)
        end)
        with_fixture({ safe = true }, function(f)
            f.hooks["GameNetworkManager.remove_peer"](
                function() return true end, {}, "remote")
            f.peer_state.peer = true
            f.peer_state.all = true
            f.peer_state.applied = "enabled"
            local server = { my_peer_id = "host" }
            f.hooks["NetworkServer.peer_connected"](
                function() end, server, "remote")
            local sync_native = 0
            f.hooks["GameNetworkManager.set_peer_synchronizing"](
                function() sync_native = sync_native + 1 end,
                { network_server = server }, "remote")
            H.equal(sync_native, 1,
                "successful native/proof cleanup left a stale tombstone")
        end)
    end)

    H.test("CT public #426 unsafe hot join never syncs after strip failure", function()
        with_fixture({ safe = false }, function(f)
            rawset(_G, "Managers", { player = { is_server = false } })
            local kicks = 0
            local manager = { network_server = {
                kick_peer = function(_, peer) if peer == "remote" then kicks = kicks + 1 end end,
            } }
            local native = 0
            f.hooks["GameNetworkManager.hot_join_sync"](
                function() native = native + 1 end, manager, "remote")
            H.equal(native, 0)
            H.equal(kicks, 1)
            H.equal(f.calls.require_peer[1], "remote")
        end)
    end)

    H.test("CT public #426 hostile strip errors remain fail-closed", function()
        with_fixture({ safe = false }, function(f)
            local hostile = setmetatable({}, {
                __tostring = function() error("hostile strip tostring") end,
            })
            rawset(_G, "Managers", {
                player = { is_server = true },
                mechanism = {
                    game_mechanism = function() error(hostile) end,
                },
            })
            local kicks, native = 0, 0
            local manager = { network_server = {
                kick_peer = function(_, peer)
                    if peer == "remote" then kicks = kicks + 1 end
                end,
            } }
            local ok = pcall(f.hooks["GameNetworkManager.hot_join_sync"],
                function() native = native + 1 end, manager, "remote")
            H.equal(ok, true)
            H.equal(native, 0)
            H.equal(kicks, 1)
            H.equal(f.mod._ct_wire_safe(), false)
        end)
    end)
end
