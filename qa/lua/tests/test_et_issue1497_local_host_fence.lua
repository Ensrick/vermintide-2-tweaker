return function(H, repo_root)
    local Fixture = assert(loadfile(repo_root
        .. "/qa/lua/tests/fixtures/et_custom_breed_parity_runtime.lua"))()(H, repo_root)
    local with_runtime = Fixture.with_runtime

    H.test("ET #1497 local host bypasses invalid live and queued census", function()
        local cases = {
            {
                name = "invalid-census",
                mutate = function(runtime)
                    runtime.live_counts.et_chosen_greataxe = "invalid"
                end,
            },
            {
                name = "live-custom",
                options = { live_counts = { et_chosen_greataxe = 1 } },
            },
            {
                name = "queued-custom",
                options = { queued_counts = { et_skaven_warlord = 1 } },
            },
        }

        for i = 1, #cases do
            local case = cases[i]
            with_runtime(case.options or {}, function(runtime)
                if case.mutate then case.mutate(runtime) end

                local occupied = runtime.mod._et.custom_breed_state_live()
                H.equal(occupied, true, case.name .. " did not engage census")

                local sync = assert(runtime.hooks[
                    "GameNetworkManager.set_peer_synchronizing"])
                local synced = assert(runtime.hooks[
                    "NetworkServer.is_network_state_fully_synced_for_peer"])
                local native_set_calls, native_sync_calls, kicks = 0, 0, 0
                local server = {
                    my_peer_id = "host",
                    kick_peer = function() kicks = kicks + 1 end,
                }
                local manager = { network_server = server }
                local sends_before = #runtime.sends

                local a, b, c, d = sync(function(_, peer_id)
                    native_set_calls = native_set_calls + 1
                    H.equal(peer_id, "host")
                    return nil, false, "prior-chain", 0
                end, manager, "host")
                H.equal(a, nil)
                H.equal(b, false)
                H.equal(c, "prior-chain")
                H.equal(d, 0)
                H.equal(native_set_calls, 1)
                H.equal(runtime.mod._et.custom_breed_hot_join_phase("host"), nil)
                H.equal(#runtime.sends, sends_before,
                    case.name .. " challenged the local host")

                local network_ready, marker = synced(function(_, peer_id)
                    native_sync_calls = native_sync_calls + 1
                    H.equal(peer_id, "host")
                    return true, "sync-chain"
                end, server, "host")
                H.equal(network_ready, true)
                H.equal(marker, "sync-chain")
                H.equal(native_sync_calls, 1)

                runtime.mod.update(
                    runtime.mod._et.CUSTOM_BREED_HOT_JOIN_TIMEOUT + 0.01)
                H.equal(synced(function()
                    native_sync_calls = native_sync_calls + 1
                    return true
                end, server, "host"), true)
                H.equal(native_sync_calls, 2)
                H.equal(kicks, 0, case.name .. " kicked the local host")
                H.equal(runtime.mod._et.custom_breed_hot_join_phase("host"), nil)

                for row = 1, #runtime.logs do
                    H.equal(runtime.logs[row]:find(
                        "hot-join sync ", 1, true) == nil, true,
                        case.name .. " emitted a remote hot-join row")
                end
            end)
        end
    end)

    H.test("ET #1497 runtime check is wired to both installed bypass branches", function()
        with_runtime({}, function(runtime)
            local check_name = "issue1497_local_host_hot_join_bypass"
            local check = assert(runtime.checks[check_name])
            local options = assert(runtime.check_options[check_name])
            local precondition = assert(options.precondition)
            local peer_state_machines = { host = {} }
            runtime.roster[1] = { peer_id = "host" }
            runtime.managers.state.network = {
                is_server = true,
                network_server = {
                    my_peer_id = "host",
                    peer_state_machines = peer_state_machines,
                },
            }

            H.equal(precondition(), true,
                "stable solo must execute the issue check")
            local direct_player_manager = runtime.managers.player
            runtime.managers.player = setmetatable({}, {
                __index = {
                    human_players = direct_player_manager.human_players,
                },
            })
            H.equal(precondition(), true,
                "source-style metatable PlayerManager method must resolve")
            runtime.managers.player = direct_player_manager
            runtime.roster[2] = { peer_id = "remote" }
            local present, reason = precondition()
            H.equal(present, false)
            H.equal(reason, "remote human player visible")
            runtime.roster[2] = nil
            peer_state_machines.remote = {}
            present, reason = precondition()
            H.equal(present, false)
            H.equal(reason, "remote peer still joining")
            peer_state_machines.remote = nil

            peer_state_machines.host = nil
            present, reason = precondition()
            H.equal(present, false)
            H.equal(reason, "local peer state machine not established")
            peer_state_machines.host = {}

            local network_server = runtime.managers.state.network.network_server
            network_server.peer_state_machines = nil
            present, reason = precondition()
            H.equal(present, false)
            H.equal(reason, "peer-state-machine roster unavailable")
            network_server.peer_state_machines = peer_state_machines

            local human_players = runtime.managers.player.human_players
            runtime.managers.player.human_players = function() return nil end
            present, reason = precondition()
            H.equal(present, false)
            H.equal(reason, "human-player roster unreadable")
            runtime.managers.player.human_players = function()
                error("human-roster-threw")
            end
            present, reason = precondition()
            H.equal(present, false)
            H.equal(reason, "human-player roster unreadable")
            runtime.managers.player.human_players = human_players
            runtime.roster[1] = "malformed-player"
            present, reason = precondition()
            H.equal(present, false)
            H.equal(reason, "human-player roster malformed")
            runtime.roster[1] = { peer_id = "host" }
            peer_state_machines[1] = {}
            present, reason = precondition()
            H.equal(present, false)
            H.equal(reason, "peer-state-machine roster malformed")
            peer_state_machines[1] = nil

            H.equal(check(),
                "set_peer_synchronizing local bypass not observed")

            local set_hook = assert(runtime.hooks[
                "GameNetworkManager.set_peer_synchronizing"])
            local synced_hook = assert(runtime.hooks[
                "NetworkServer.is_network_state_fully_synced_for_peer"])
            local server = { my_peer_id = "host" }
            local manager = { network_server = server }
            local sends_before = #runtime.sends
            H.equal(set_hook(function() return "set-native" end,
                manager, "host"), "set-native")
            H.equal(check(), "fully-synced local bypass not observed")
            H.equal(synced_hook(function() return "sync-native" end,
                server, "host"), "sync-native")
            H.equal(check(), nil)
            H.equal(#runtime.sends, sends_before,
                "runtime-evidence exercise sent a parity packet")

            local provenance = assert(runtime.mod.
                _et_custom_breed_local_host_provenance)
            local set_evidence = assert(provenance.set_peer_synchronizing)
            local synced_evidence = assert(provenance.fully_synced_for_peer)
            local set_callback = set_evidence.callback
            set_evidence.callback = nil
            H.equal(check(), "set_peer_synchronizing bypass hook disconnected")
            set_evidence.callback = set_callback
            local synced_callback = synced_evidence.callback
            synced_evidence.callback = nil
            H.equal(check(), "fully-synced bypass hook disconnected")
            synced_evidence.callback = synced_callback
            set_evidence.observed = false
            H.equal(check(),
                "set_peer_synchronizing local bypass not observed")
            set_evidence.observed = true
            set_evidence.retirement_observed = false
            H.equal(check(), nil,
                "one successful seam retirement must satisfy the contract")
            synced_evidence.observed = false
            H.equal(check(), "fully-synced local bypass not observed")
            synced_evidence.observed = true
            synced_evidence.retirement_observed = false
            H.equal(check(), "canonical parity retirement not observed")
            set_evidence.retirement_observed = true
            synced_evidence.retirement_observed = true
            synced_evidence.last_local_peer_id = "different-local"
            H.equal(check(),
                "local peer evidence disagrees across bypass hooks")
            synced_evidence.last_local_peer_id = "host"

            local parity = assert(runtime.mod._et.CustomBreedParity)
            local original_peer_has = parity.peer_has
            local original_all_peers_have = parity.all_peers_have
            runtime.network.own_peer_id = "new-host"
            network_server.my_peer_id = "new-host"
            runtime.roster[1].peer_id = "new-host"
            peer_state_machines.host = nil
            peer_state_machines["new-host"] = {}
            parity.peer_has = function(_, peer_id)
                return peer_id == "new-host"
            end
            parity.all_peers_have = function() return true end
            H.equal(precondition(), true)
            H.equal(check(),
                "local peer evidence stale for current listen server")
            parity.peer_has = original_peer_has
            parity.all_peers_have = original_all_peers_have
            runtime.network.own_peer_id = "host"
            network_server.my_peer_id = "host"
            runtime.roster[1].peer_id = "host"
            peer_state_machines["new-host"] = nil
            peer_state_machines.host = {}

            server.my_peer_id = "other"
            H.equal(synced_hook(function() return true end,
                server, "host"), true)
            H.equal(parity:require_peer("host"), false)
            server.my_peer_id = "host"
            H.equal(precondition(), true,
                "stale local parity pending must not turn solo into a skip")
            H.equal(check(),
                "local-host canonical pending state retained or check is not solo")
            H.equal(set_hook(function() return true end,
                manager, "host"), true)
            H.equal(check(), nil)

            server.my_peer_id = "other"
            set_hook(function() return true end, manager, "host")
            server.my_peer_id = "host"
            H.equal(check(),
                "local-host local fence state retained")
            H.equal(synced_hook(function() return true end,
                server, "host"), true)
            H.equal(check(), nil)

            parity.peer_has = nil
            H.equal(check(), "local-host parity postcondition reader missing")
            parity.peer_has = function() error("peer-has-threw") end
            H.equal(check(), "local-host peer acknowledgement unreadable")
            parity.peer_has = function() return true end
            H.equal(check(), "local-host local acknowledgement retained")
            parity.peer_has = original_peer_has
            parity.all_peers_have = nil
            H.equal(check(), "local-host parity postcondition reader missing")
            parity.all_peers_have = function()
                error("all-peers-have-threw")
            end
            H.equal(check(), "local-host parity consensus unreadable")
            parity.all_peers_have = function() return false end
            H.equal(check(),
                "local-host canonical pending state retained or check is not solo")
            parity.all_peers_have = original_all_peers_have
            H.equal(check(), nil)

            runtime.mod._et.CustomBreedParity = nil
            H.equal(check(), "canonical parity instance changed after boot")
            runtime.mod._et.CustomBreedParity = setmetatable({
                peer_has = parity.peer_has,
                all_peers_have = parity.all_peers_have,
                forget_peer = parity.forget_peer,
            }, {
                __eq = function() return true end,
            })
            H.equal(check(), "canonical parity instance changed after boot")
            runtime.mod._et.CustomBreedParity = parity
            H.equal(check(), nil)

            runtime.mod._et_custom_breed_local_host_provenance = nil
            H.equal(check(), "local-host bypass provenance missing")
            runtime.mod._et_custom_breed_local_host_provenance = provenance
            H.equal(check(), nil)
            H.equal(runtime.mod._et.custom_breed_hot_join_phase("host"), nil,
                "runtime check mutated live peer-fence state")
        end)
    end)

    H.test("ET #1497 runtime check accepts source-proven absent parity", function()
        local cases = {
            { name = "factory-unavailable", parity_unavailable = true },
            { name = "identity-capture-failed", identity_capture_failure = true },
        }
        for i = 1, #cases do
            local case = cases[i]
            with_runtime(case, function(runtime)
                local check_name = "issue1497_local_host_hot_join_bypass"
                local check = assert(runtime.checks[check_name])
                local precondition = assert(runtime.check_options[
                    check_name].precondition)
                local peer_state_machines = { host = {} }
                runtime.roster[1] = { peer_id = "host" }
                runtime.managers.state.network = {
                    is_server = true,
                    network_server = {
                        my_peer_id = "host",
                        peer_state_machines = peer_state_machines,
                    },
                }
                H.equal(runtime.mod._et.CustomBreedParity, nil)
                if case.identity_capture_failure then
                    H.equal(runtime.mod._et.CustomBreedIdentitySnapshot, nil)
                else
                    H.equal(type(runtime.mod._et.CustomBreedIdentitySnapshot),
                        "table")
                end
                H.equal(precondition(), true)

                local set_hook = assert(runtime.hooks[
                    "GameNetworkManager.set_peer_synchronizing"])
                local synced_hook = assert(runtime.hooks[
                    "NetworkServer.is_network_state_fully_synced_for_peer"])
                local server = { my_peer_id = "host" }
                local manager = { network_server = server }
                local set_calls, synced_calls = 0, 0
                H.equal(set_hook(function()
                    set_calls = set_calls + 1
                    return "set-native"
                end, manager, "host"), "set-native")
                H.equal(synced_hook(function()
                    synced_calls = synced_calls + 1
                    return true, "sync-native"
                end, server, "host"), true)
                H.equal(set_calls, 1)
                H.equal(synced_calls, 1)
                H.equal(runtime.mod._et.custom_breed_hot_join_phase("host"),
                    nil)
                H.equal(#runtime.sends, 0)
                H.equal(check(), nil, case.name
                    .. " invented canonical state that must be retired")

                local evidence = assert(runtime.mod.
                    _et_custom_breed_local_host_provenance)
                evidence.set_peer_synchronizing.parity_absence_observed = false
                evidence.fully_synced_for_peer.parity_absence_observed = false
                H.equal(check(), "canonical parity absence not observed")

                evidence.set_peer_synchronizing.parity_absence_observed = true
                runtime.mod._et.CustomBreedParity = "malformed"
                H.equal(check(),
                    "canonical parity instance changed after boot")
            end)
        end
    end)

    H.test("ET #1497 unavailable parity preserves remote fence policy", function()
        with_runtime({
            identity_capture_failure = true,
            live_counts = { et_chosen_greataxe = 1 },
        }, function(runtime)
            local set_hook = assert(runtime.hooks[
                "GameNetworkManager.set_peer_synchronizing"])
            local synced_hook = assert(runtime.hooks[
                "NetworkServer.is_network_state_fully_synced_for_peer"])
            local kicks, set_calls, synced_calls = 0, 0, 0
            local server = {
                my_peer_id = "host",
                kick_peer = function(_, peer_id)
                    H.equal(peer_id, "remote")
                    kicks = kicks + 1
                end,
            }
            local manager = { network_server = server }
            H.equal(set_hook(function()
                set_calls = set_calls + 1
                return "unsafe-native"
            end, manager, "remote"), nil)
            H.equal(set_calls, 0)
            H.equal(runtime.mod._et.custom_breed_hot_join_phase("remote"),
                "pending")

            runtime.mod.update(
                runtime.mod._et.CUSTOM_BREED_HOT_JOIN_TIMEOUT + 0.01)
            H.equal(synced_hook(function()
                synced_calls = synced_calls + 1
                return true
            end, server, "remote"), false)
            H.equal(synced_calls, 0)
            H.equal(kicks, 1)
            H.equal(runtime.mod._et.custom_breed_hot_join_phase("remote"),
                "kicked")
            H.equal(synced_hook(function()
                synced_calls = synced_calls + 1
                return true
            end, server, "remote"), false)
            H.equal(synced_calls, 0)
            H.equal(kicks, 1, "unavailable remote peer was kicked twice")
        end)

        with_runtime({ identity_capture_failure = true }, function(runtime)
            local set_hook = assert(runtime.hooks[
                "GameNetworkManager.set_peer_synchronizing"])
            local native_calls, kicks = 0, 0
            local manager = { network_server = {
                my_peer_id = "host",
                kick_peer = function() kicks = kicks + 1 end,
            } }
            H.equal(set_hook(function(_, peer_id)
                native_calls = native_calls + 1
                return "native:" .. peer_id
            end, manager, "remote"), "native:remote")
            H.equal(native_calls, 1)
            H.equal(kicks, 0)
            H.equal(runtime.mod._et.custom_breed_hot_join_phase("remote"),
                "admitted")
        end)
    end)

    H.test("ET #1497 mutable parity export is never behavioral authority", function()
        with_runtime({ live_counts = { et_chosen_greataxe = 1 } },
            function(runtime)
                local canonical = assert(runtime.mod._et.CustomBreedParity)
                local original_forget = canonical.forget_peer
                local canonical_forget_calls = 0
                canonical.forget_peer = function(self, peer_id)
                    canonical_forget_calls = canonical_forget_calls + 1
                    return original_forget(self, peer_id)
                end

                local foreign_calls = {
                    require_peer = 0,
                    peer_has = 0,
                    forget_peer = 0,
                }
                local foreign = {
                    require_peer = function()
                        foreign_calls.require_peer =
                            foreign_calls.require_peer + 1
                        return true
                    end,
                    peer_has = function()
                        foreign_calls.peer_has = foreign_calls.peer_has + 1
                        return true
                    end,
                    forget_peer = function()
                        foreign_calls.forget_peer =
                            foreign_calls.forget_peer + 1
                    end,
                }
                runtime.mod._et.CustomBreedParity = foreign

                local set_hook = assert(runtime.hooks[
                    "GameNetworkManager.set_peer_synchronizing"])
                local synced_hook = assert(runtime.hooks[
                    "NetworkServer.is_network_state_fully_synced_for_peer"])
                local remove_hook = assert(runtime.safe_hooks[
                    "GameNetworkManager.remove_peer"])
                local server = {
                    my_peer_id = "host",
                    kick_peer = function() end,
                }
                local manager = { network_server = server }

                H.equal(canonical:require_peer("host"), false)
                local native_local = 0
                H.equal(set_hook(function()
                    native_local = native_local + 1
                    return "local-set"
                end, manager, "host"), "local-set")
                H.equal(canonical:peer_has("host"), false)

                H.equal(canonical:require_peer("host"), false)
                H.equal(synced_hook(function()
                    native_local = native_local + 1
                    return true, "local-synced"
                end, server, "host"), true)
                H.equal(native_local, 2)
                H.equal(canonical:peer_has("host"), false)
                H.equal(canonical_forget_calls, 2)

                local remote_native = 0
                H.equal(set_hook(function()
                    remote_native = remote_native + 1
                    return "unsafe-native"
                end, manager, "remote"), nil)
                H.equal(remote_native, 0,
                    "foreign pre-ack bypassed the live-state fence")
                H.equal(runtime.mod._et.custom_breed_hot_join_phase("remote"),
                    "pending")
                H.equal(synced_hook(function()
                    remote_native = remote_native + 1
                    return true
                end, server, "remote"), false)
                H.equal(remote_native, 0)

                H.equal(canonical:require_peer("disconnect"), false)
                remove_hook(manager, "disconnect")
                H.equal(canonical:peer_has("disconnect"), false)
                H.equal(canonical_forget_calls, 3)
                H.equal(foreign_calls.require_peer, 0)
                H.equal(foreign_calls.peer_has, 0)
                H.equal(foreign_calls.forget_peer, 0)

                runtime.mod._et.CustomBreedParity = canonical
                canonical.forget_peer = original_forget
            end)
    end)

    H.test("ET #1497 local identity authority fallback and stale recovery", function()
        with_runtime({ live_counts = { et_chosen_greataxe = 1 } },
            function(runtime)
                local sync = assert(runtime.hooks[
                    "GameNetworkManager.set_peer_synchronizing"])
                local synced = assert(runtime.hooks[
                    "NetworkServer.is_network_state_fully_synced_for_peer"])
                local native_calls, sync_calls, kicks = 0, 0, 0
                local server = {
                    my_peer_id = "host",
                    kick_peer = function() kicks = kicks + 1 end,
                }
                local manager = { network_server = server }
                local function native_set()
                    native_calls = native_calls + 1
                    return "native"
                end
                local parity = assert(runtime.mod._et.CustomBreedParity)
                for _ = 1, 5 do runtime.mod.update(0.5) end
                H.equal(parity:all_peers_have(), true)
                H.equal(parity:applied_state(), "enabled")

                -- The source-owned server field remains authoritative even if
                -- the engine fallback is temporarily unreadable.
                runtime.network.peer_id_throws = true
                H.equal(sync(native_set, manager, "host"), "native")
                H.equal(native_calls, 1)

                -- The earlier GameNetworkManager seam can safely use the
                -- guarded engine fallback before NetworkServer is attached.
                server.my_peer_id = nil
                runtime.network.peer_id_throws = false
                runtime.network.own_peer_id = "host"
                H.equal(sync(native_set, manager, "host"), "native")
                H.equal(native_calls, 2)

                -- A readable source owner wins over a conflicting fallback,
                -- so a real remote peer retains the live-custom hold.
                server.my_peer_id = "other"
                H.equal(sync(native_set, manager, "host"), nil)
                H.equal(native_calls, 2)
                H.equal(runtime.mod._et.custom_breed_hot_join_phase("host"),
                    "pending")
                H.equal(parity:all_peers_have(), false,
                    "mistaken local pending proof did not poison parity")
                H.equal(parity:applied_state(), "disabled")

                -- Once the source owner becomes readable/correct, the sync
                -- seam clears BOTH stale owners before they can age into a kick.
                server.my_peer_id = "host"
                local ready, marker = synced(function()
                    sync_calls = sync_calls + 1
                    return true, "recovered"
                end, server, "host")
                H.equal(ready, true)
                H.equal(marker, "recovered")
                H.equal(sync_calls, 1)
                H.equal(runtime.mod._et.custom_breed_hot_join_phase("host"), nil)
                H.equal(parity:peer_has("host"), false)
                H.equal(parity:all_peers_have(), true,
                    "canonical pending local proof survived recovery")
                runtime.mod.update(
                    runtime.mod._et.CUSTOM_BREED_HOT_JOIN_TIMEOUT + 0.01)
                for _ = 1, 5 do runtime.mod.update(0.5) end
                H.equal(parity:applied_state(), "enabled")
                local custom, decision = runtime.mod._et.custom_breed_spawn_floor(
                    runtime.ctx.breeds.et_chosen_greataxe,
                    "issue1497-stale-owner-recovery")
                H.equal(custom, runtime.ctx.breeds.et_chosen_greataxe)
                H.equal(decision, "exact-custom")
                H.equal(synced(function()
                    sync_calls = sync_calls + 1
                    return true
                end, server, "host"), true)
                H.equal(sync_calls, 2)
                H.equal(kicks, 0)

                -- If neither authority can be read, containment preserves the
                -- conservative remote hold instead of throwing or guessing.
                server.my_peer_id = nil
                runtime.network.peer_id_throws = true
                H.equal(sync(native_set, manager, "unreadable-owner"), nil)
                H.equal(runtime.mod._et.custom_breed_hot_join_phase(
                    "unreadable-owner"), "pending")
            end)
    end)

    H.test("ET #1497 either ingress retires pending parity without a fence row", function()
        for _, seam in ipairs({ "set", "synced" }) do
            with_runtime({}, function(runtime)
                local set_hook = assert(runtime.hooks[
                    "GameNetworkManager.set_peer_synchronizing"])
                local synced_hook = assert(runtime.hooks[
                    "NetworkServer.is_network_state_fully_synced_for_peer"])
                local parity = assert(runtime.mod._et.CustomBreedParity)
                local kicks = 0
                local server = {
                    my_peer_id = "host",
                    kick_peer = function() kicks = kicks + 1 end,
                }
                local manager = { network_server = server }

                -- This is the partial state the original fix missed: the
                -- canonical pre-roster proof exists with no ET fence record.
                H.equal(parity:require_peer("host"), false)
                H.equal(runtime.mod._et.custom_breed_hot_join_phase("host"), nil)
                H.equal(parity:all_peers_have(), false)

                local forget_calls, native_calls = 0, 0
                local original_forget = parity.forget_peer
                parity.forget_peer = function(self, peer_id)
                    forget_calls = forget_calls + 1
                    return original_forget(self, peer_id)
                end
                local sends_before = #runtime.sends
                local logs_before = #runtime.logs
                local retired_before = parity:retired_peer_count()
                local function native(_, peer_id)
                    native_calls = native_calls + 1
                    H.equal(peer_id, "host")
                    return nil, false, seam, 0
                end
                local a, b, c, d
                if seam == "set" then
                    a, b, c, d = set_hook(native, manager, "host")
                else
                    a, b, c, d = synced_hook(native, server, "host")
                end
                H.equal(a, nil)
                H.equal(b, false)
                H.equal(c, seam)
                H.equal(d, 0)
                H.equal(native_calls, 1)
                H.equal(forget_calls, 1)
                H.equal(parity:all_peers_have(), true)
                H.equal(parity:peer_has("host"), false)
                H.equal(#runtime.sends, sends_before)
                H.equal(#runtime.logs, logs_before)
                H.equal(kicks, 0)
                H.equal(parity:retired_peer_count(), retired_before)

                -- Repeated local polling re-runs the canonical idempotent
                -- cleanup so delayed proof cannot recreate pending state.
                if seam == "set" then
                    set_hook(native, manager, "host")
                else
                    synced_hook(native, server, "host")
                end
                H.equal(native_calls, 2)
                H.equal(forget_calls, 2)
                H.equal(#runtime.sends, sends_before)
                H.equal(#runtime.logs, logs_before)
                H.equal(kicks, 0)
                H.equal(parity:retired_peer_count(), retired_before)
                H.equal(parity:all_peers_have(), true)
            end)
        end
    end)

    H.test("ET #1497 local retirement errors admit native and retry fail closed", function()
        for _, failure in ipairs({
            "forget-missing", "forget-throwing", "forget-no-op",
        }) do
            with_runtime({}, function(runtime)
                local set_hook = assert(runtime.hooks[
                    "GameNetworkManager.set_peer_synchronizing"])
                local synced_hook = assert(runtime.hooks[
                    "NetworkServer.is_network_state_fully_synced_for_peer"])
                local parity = assert(runtime.mod._et.CustomBreedParity)
                local original_forget = parity.forget_peer
                local server = { my_peer_id = "host" }
                local manager = { network_server = server }
                H.equal(parity:require_peer("host"), false)
                local sends_before = #runtime.sends
                local forget_calls = 0
                if failure == "forget-missing" then
                    parity.forget_peer = nil
                elseif failure == "forget-throwing" then
                    parity.forget_peer = function()
                        forget_calls = forget_calls + 1
                        error("forget-peer-threw")
                    end
                elseif failure == "forget-no-op" then
                    parity.forget_peer = function()
                        forget_calls = forget_calls + 1
                    end
                end

                local native_calls = 0
                local a, b, c = set_hook(function()
                    native_calls = native_calls + 1
                    return "native", false, failure
                end, manager, "host")
                H.equal(a, "native")
                H.equal(b, false)
                H.equal(c, failure)
                H.equal(native_calls, 1)
                H.equal(forget_calls,
                    failure == "forget-missing" and 0 or 1)
                H.equal(runtime.mod._et.custom_breed_hot_join_phase("host"), nil)
                H.equal(parity:all_peers_have(), false,
                    "failed canonical cleanup did not remain fail closed")
                H.equal(#runtime.sends, sends_before)
                H.equal(runtime.checks[
                    "issue1497_local_host_hot_join_bypass"](),
                    "fully-synced local bypass not observed")

                -- Cleanup failure is not latched. A later ingress retries the
                -- canonical operation and restores eligibility.
                parity.forget_peer = original_forget
                local sync_calls = 0
                local ready, marker = synced_hook(function()
                    sync_calls = sync_calls + 1
                    return true, "retried"
                end, server, "host")
                H.equal(ready, true)
                H.equal(marker, "retried")
                H.equal(sync_calls, 1)
                H.equal(parity:all_peers_have(), true)
                H.equal(#runtime.sends, sends_before)
                H.equal(runtime.checks[
                    "issue1497_local_host_hot_join_bypass"](), nil)
            end)
        end
    end)

    H.test("ET #1497 local proof retirement is bounded and permits later remote proof", function()
        with_runtime({ live_counts = { et_chosen_greataxe = 1 } },
            function(runtime)
                local set_hook = assert(runtime.hooks[
                    "GameNetworkManager.set_peer_synchronizing"])
                local synced_hook = assert(runtime.hooks[
                    "NetworkServer.is_network_state_fully_synced_for_peer"])
                local parity = assert(runtime.mod._et.CustomBreedParity)
                local server = { my_peer_id = "other" }
                local manager = { network_server = server }

                H.equal(set_hook(function() return "unexpected" end,
                    manager, "remote-stable"), nil)
                runtime.reply_exact("remote-stable", "epoch-remote-stable")
                H.equal(parity:peer_has("remote-stable"), true)

                -- Wrong owner creates a full exact proof for what is really the
                -- local host. Correct classification must retire it once.
                H.equal(set_hook(function() return "unexpected" end,
                    manager, "host"), nil)
                runtime.reply_exact("host", "epoch-local")
                H.equal(parity:peer_has("host"), true)
                local retired_before = parity:retired_peer_count()
                server.my_peer_id = "host"
                local sends_before = #runtime.sends
                H.equal(set_hook(function() return "local" end,
                    manager, "host"), "local")
                H.equal(parity:peer_has("host"), false)
                H.equal(parity:peer_has("remote-stable"), true,
                    "targeted local retirement cleared a remote proof")
                H.equal(parity:retired_peer_count(), retired_before + 1)
                local retired_once = parity:retired_peer_count()
                H.equal(synced_hook(function() return true end,
                    server, "host"), true)
                H.equal(parity:retired_peer_count(), retired_once,
                    "repeated local cleanup churned retired proof history")
                H.equal(#runtime.sends, sends_before)

                -- If the same id is subsequently authoritative as a remote
                -- peer, local retirement must no longer suppress new proof.
                server.my_peer_id = "new-host"
                runtime.network.own_peer_id = "new-host"
                runtime.roster[1] = { peer_id = "host" }
                H.equal(set_hook(function() return "remote-native" end,
                    manager, "host"), nil)
                runtime.reply_exact("host", "epoch-remote")
                H.equal(parity:peer_has("host"), true)
                H.equal(synced_hook(function()
                    return true, "remote-ready"
                end, server, "host"), true)
                H.equal(parity:peer_has("host"), true,
                    "later valid remote proof was suppressed")
            end)
    end)

    H.test("ET #1497 delayed pre-cleanup reply cannot re-poison local parity", function()
        with_runtime({ live_counts = { et_chosen_greataxe = 1 } },
            function(runtime)
                local set_hook = assert(runtime.hooks[
                    "GameNetworkManager.set_peer_synchronizing"])
                local synced_hook = assert(runtime.hooks[
                    "NetworkServer.is_network_state_fully_synced_for_peer"])
                local parity = assert(runtime.mod._et.CustomBreedParity)
                local server = {
                    my_peer_id = "wrong-owner",
                    kick_peer = function() error("local host was kicked") end,
                }
                local manager = { network_server = server }

                H.equal(set_hook(function() return "remote-native" end,
                    manager, "host"), nil)
                local old_challenge = assert(runtime.latest.host)
                H.equal(parity:all_peers_have(), false)

                server.my_peer_id = "host"
                local native_set_calls = 0
                H.equal(set_hook(function()
                    native_set_calls = native_set_calls + 1
                    return "local-native"
                end, manager, "host"), "local-native")
                H.equal(native_set_calls, 1)
                H.equal(parity:all_peers_have(), true)
                local sends_after_cleanup = #runtime.sends
                local retired_after_cleanup = parity:retired_peer_count()

                -- The old directed response arrives after forget_peer cleared
                -- its outstanding challenge. Canonical rejection deliberately
                -- re-adds `_pending`; the next local ingress must heal it even
                -- though no ET fence row was recreated.
                runtime.receiver("host", 1, 1,
                    assert(runtime.mod._et.CustomBreedIdentitySnapshot).identity,
                    "epoch-delayed", "", old_challenge.query)
                H.equal(parity:peer_has("host"), false)
                H.equal(parity:all_peers_have(), false,
                    "delayed reply did not reproduce canonical pending poison")
                H.equal(runtime.mod._et.custom_breed_hot_join_phase("host"), nil)

                local native_sync_calls = 0
                local ready, marker = synced_hook(function()
                    native_sync_calls = native_sync_calls + 1
                    return true, "healed"
                end, server, "host")
                H.equal(ready, true)
                H.equal(marker, "healed")
                H.equal(native_sync_calls, 1)
                H.equal(parity:all_peers_have(), true)
                H.equal(parity:peer_has("host"), false)
                H.equal(#runtime.sends, sends_after_cleanup)
                H.equal(parity:retired_peer_count(), retired_after_cleanup)
                H.equal(runtime.checks[
                    "issue1497_local_host_hot_join_bypass"](), nil)
            end)
    end)

    H.test("ET #1497 malformed peer ids preserve the prior chain", function()
        with_runtime({ live_counts = { et_chosen_greataxe = 1 } },
            function(runtime)
                local sync = assert(runtime.hooks[
                    "GameNetworkManager.set_peer_synchronizing"])
                local calls = 0
                local function native(_, peer_id)
                    calls = calls + 1
                    return peer_id, false, "tail"
                end
                local malformed = {
                    n = 5,
                    [1] = nil,
                    [2] = "",
                    [3] = 7,
                    [4] = false,
                    [5] = {},
                }
                for i = 1, malformed.n do
                    local peer_id = malformed[i]
                    local a, b, c = sync(native, {}, peer_id)
                    H.equal(a, peer_id)
                    H.equal(b, false)
                    H.equal(c, "tail")
                end
                H.equal(calls, malformed.n)
            end)
    end)

    H.test("ET #1497 local host crosses the vanilla enter-game conjunction", function()
        with_runtime({}, function(runtime)
            -- Match the observed keep failure: the ConflictDirector exists but
            -- its custom-breed census is not readable yet.
            runtime.live_counts.et_chosen_greataxe = "invalid"
            local sync = assert(runtime.hooks[
                "GameNetworkManager.set_peer_synchronizing"])
            local synced = assert(runtime.hooks[
                "NetworkServer.is_network_state_fully_synced_for_peer"])
            local native_set_calls, native_sync_calls, kicks = 0, 0, 0
            local server = {
                my_peer_id = "host",
                peers_added_to_gamesession = {},
                game_session = {},
                kick_peer = function() kicks = kicks + 1 end,
            }
            local manager = { network_server = server }
            manager.game_session_host = function() return "host" end
            manager.in_game_session = function() return true end
            manager.set_peer_synchronizing = function(self, peer_id)
                return sync(function(_, native_peer_id)
                    native_set_calls = native_set_calls + 1
                    H.equal(native_peer_id, peer_id)
                end, self, peer_id)
            end
            server.game_network_manager = manager
            server.is_network_state_fully_synced_for_peer = function(self, peer_id)
                return synced(function(_, native_peer_id)
                    native_sync_calls = native_sync_calls + 1
                    H.equal(native_peer_id, peer_id)
                    return true
                end, self, peer_id)
            end

            local entered_state = nil
            local state = {
                is_ingame = true,
                is_remote = false,
                peer_id = "host",
                server = server,
                change_state = function(_, next_state)
                    entered_state = next_state
                end,
            }
            local waiting_for_game_objects = {}

            -- Exact source-shaped conjunction from PeerStates.WaitingForEnterGame:
            -- every non-network leaf is true and resync is complete.
            local function update_waiting_for_enter_game(self)
                local active_server = self.server
                if self.is_ingame and active_server.game_network_manager then
                    local host = active_server.game_network_manager:game_session_host()
                    if host then
                        local peer_id = self.peer_id
                        if not active_server.peers_added_to_gamesession[peer_id] then
                            active_server.game_network_manager:set_peer_synchronizing(
                                peer_id)
                            local all_synced = active_server:
                                is_network_state_fully_synced_for_peer(peer_id)
                                and true -- no ongoing package resync
                            local in_session = active_server.game_network_manager:
                                in_game_session()
                            if not (active_server.game_session
                                    and in_session and all_synced) then
                                return
                            end
                        end
                        self:change_state(waiting_for_game_objects)
                    end
                end
            end

            update_waiting_for_enter_game(state)
            H.equal(entered_state, waiting_for_game_objects,
                "local host remained trapped in WaitingForEnterGame")
            H.equal(native_set_calls, 1)
            H.equal(native_sync_calls, 1)
            H.equal(kicks, 0)
            H.equal(runtime.mod._et.custom_breed_hot_join_phase("host"), nil)
        end)
    end)
end
