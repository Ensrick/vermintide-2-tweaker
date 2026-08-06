local function register(Harness, repo_root)
    local function load_factory()
        local path = repo_root .. "/tools/shared_lib/_lib_peer_parity.lua"
        local chunk, err = loadfile(path)
        if not chunk then error(err) end
        return chunk()
    end

    local function with_network_stubs(body)
        local previous_managers, previous_network = Managers, Network
        local roster = {}
        Managers = {
            player = {
                human_players = function() return roster end,
            },
        }
        Network = { peer_id = function() return "host" end }
        local ok, err = xpcall(function() body(roster) end, debug.traceback)
        Managers, Network = previous_managers, previous_network
        if not ok then error(err, 0) end
    end

    local function build_inst(factory)
        local receiver
        local fake_mod = {
            network_register = function(_, _, callback) receiver = callback end,
            network_send = function() end,
            debug = function() end,
            echo = function() end,
        }
        local inst = factory(fake_mod, {
            schema = 7,
            poll_interval = 0,
            settle_enable = 0,
        })
        return inst, function(peer_id)
            assert(receiver, "network receiver was not installed")
            receiver(peer_id, 7, 1)
        end
    end

    Harness.test("peer parity retains positive ack only across bounded transition gap", function()
        local factory = load_factory()
        local parity = factory({}, { absence_grace = 15, notify_grace = 10 })
        Harness.truthy(parity.__retain_ack(true, 0))
        Harness.truthy(parity.__retain_ack(true, 14.999))
        Harness.truthy(not parity.__retain_ack(true, 15))
        Harness.truthy(not parity.__retain_ack(false, 1))
        Harness.truthy(not parity.__retain_ack(true, -1))
    end)

    Harness.test("peer parity transition defaults cover observed handshake without changing classifier", function()
        local factory = load_factory()
        local parity = factory({})
        Harness.equal(15, parity.ABSENCE_GRACE)
        Harness.equal(10, parity.NOTIFY_GRACE)
        Harness.truthy(parity.__classify({ host = true }, { host = true }))
        Harness.truthy(not parity.__classify({ host = true }, {}), "new or expired peer must remain fail-closed")
    end)

    Harness.test("peer parity unknown roster fails closed", function()
        local previous_managers, previous_network = Managers, Network
        Managers, Network = nil, nil
        local ok, err = xpcall(function()
            local factory = load_factory()
            local inst = factory({}, { poll_interval = 0 })
            Harness.truthy(not inst:all_peers_have(), "unavailable PlayerManager is not positive solo evidence")
            inst:tick(0)
            Harness.equal(inst:applied_state(), "disabled")
        end, debug.traceback)
        Managers, Network = previous_managers, previous_network
        if not ok then error(err, 0) end
    end)

    Harness.test("peer parity pre-roster unknown join disables immediately", function()
        with_network_stubs(function()
            local factory = load_factory()
            local inst = build_inst(factory)
            local disabled = 0
            inst:register_gated_feature("wire", {
                on_enable = function() end,
                on_disable = function() disabled = disabled + 1 end,
            })
            inst:install()
            inst:tick(0)
            Harness.equal(inst:applied_state(), "enabled", "solo baseline must enable")
            Harness.truthy(not inst:require_peer("peer_missing"), "unknown peer must not pass")
            Harness.equal(inst:applied_state(), "disabled", "join fence must disable before roster polling")
            Harness.equal(disabled, 1, "disable callback must run synchronously")
            Harness.truthy(not inst:all_peers_have(), "pending peer must count while PlayerManager is still empty")
        end)
    end)

    Harness.test("peer parity pending join survives polls until roster exposure", function()
        with_network_stubs(function(roster)
            local factory = load_factory()
            local inst = build_inst(factory)
            inst:install()
            inst:tick(0)
            Harness.truthy(not inst:require_peer("peer_delayed"))
            inst:tick(1)
            inst:tick(1)
            Harness.truthy(not inst:all_peers_have(),
                "pending join must remain fail-closed across multiple pre-roster polls")
            roster[1] = { peer_id = "peer_delayed" }
            inst:tick(1)
            Harness.truthy(not inst:all_peers_have(),
                "visible but unacknowledged join must remain fail-closed")
        end)
    end)

    Harness.test("peer parity pre-acked join preserves all-peer parity", function()
        with_network_stubs(function()
            local factory = load_factory()
            local inst, acknowledge = build_inst(factory)
            inst:install()
            acknowledge("peer_ct")
            Harness.truthy(inst:peer_has("peer_ct"), "VMF acknowledgement must be positive evidence")
            Harness.truthy(inst:require_peer("peer_ct"), "pre-acked peer must pass synchronous join fence")
            Harness.truthy(inst:all_peers_have(), "all-acked pending roster must classify safe")
        end)
    end)

    Harness.test("peer parity leave and rejoin cannot reuse stale acknowledgement", function()
        with_network_stubs(function()
            local factory = load_factory()
            local inst, acknowledge = build_inst(factory)
            inst:install()
            acknowledge("peer_reused")
            Harness.truthy(inst:require_peer("peer_reused"))
            inst:forget_peer("peer_reused")
            Harness.truthy(not inst:peer_has("peer_reused"), "real leave must invalidate acknowledgement")
            Harness.truthy(not inst:require_peer("peer_reused"), "same peer id must be unknown on rejoin")
            Harness.truthy(not inst:all_peers_have(), "rejoined peer stays fail-closed until a fresh ack")
        end)
    end)

    Harness.test("peer parity legacy mode preserves the two-field wire payload", function()
        with_network_stubs(function()
            local factory = load_factory()
            local receiver, explicit_args
            local fake_mod = {
                network_register = function(_, _, callback) receiver = callback end,
                network_send = function(_, ...)
                    explicit_args = select("#", ...)
                end,
                debug = function() end,
                echo = function() end,
            }
            local inst = assert(factory(fake_mod, { schema = 7, poll_interval = 0 }))
            inst:install()
            Harness.equal(explicit_args, 4,
                "legacy transport must remain channel/recipient/schema/reply only")
            Harness.equal(inst.EXACT_MODE, false)
            receiver("peer-legacy", 7, 1)
            Harness.truthy(inst:peer_has("peer-legacy"))
        end)
    end)

    Harness.test("shared exact mode is opt-in only for CRT in this release", function()
        local paths = {
            "chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_meta_trait_boons.lua",
            "character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua",
            "event_tweaker/scripts/mods/event_tweaker/_evt_guard430_curse_parity.lua",
            "event_tweaker/scripts/mods/event_tweaker/_evt_shadow_adventure.lua",
            "weapon_tweaker/scripts/mods/weapon_tweaker/_wt431_damage_profile_parity.lua",
            "weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt431_damage_profile_parity.lua",
        }
        for i = 1, #paths do
            local file = assert(io.open(repo_root .. "/" .. paths[i], "rb"))
            local source = file:read("*a")
            file:close()
            Harness.equal(source:find("[^_%w]wire_identity%s*="), nil,
                "shared exact opt-in is not yet authorized for " .. paths[i])
        end

        local file = assert(io.open(repo_root
            .. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker.lua", "rb"))
        local career = file:read("*a")
        file:close()
        Harness.truthy(career:find("[^_%w]wire_identity%s*=%s*wire_identity") ~= nil,
            "CRT must be the sole shared exact-mode opt-in")
    end)

    local function build_exact(factory, identity)
        local receiver, latest = nil, {}
        local fake_mod = {
            network_register = function(_, _, callback) receiver = callback end,
            network_send = function(_, channel, recipient, schema, reply,
                    sent_identity, epoch, query, echo)
                latest[recipient] = {
                    channel = channel, schema = schema, reply = reply,
                    identity = sent_identity, epoch = epoch,
                    query = query, echo = echo,
                }
            end,
            debug = function() end,
            echo = function() end,
        }
        local inst = assert(factory(fake_mod, {
            channel = "exact_presence",
            schema = 9,
            wire_identity = identity,
            session_epoch = "local-e1",
            poll_interval = 0,
            settle_enable = 0,
        }))
        inst:install()
        return inst, function() return receiver end, latest
    end

    Harness.test("peer parity exact mode requires identity epoch and current challenge", function()
        with_network_stubs(function()
            local factory = load_factory()
            local identity = "wire-v1:2:12345678:abcdef01"
            local inst, receiver_fn, latest = build_exact(factory, identity)
            local receiver = assert(receiver_fn())
            Harness.truthy(inst.EXACT_MODE)
            Harness.equal(inst.WIRE_IDENTITY, identity)
            Harness.truthy(inst:max_json_envelope_length() <= inst.MAX_VMF_JSON_LENGTH)

            inst:require_peer("peer-a")
            local query = latest["peer-a"].query
            receiver("peer-a", 9, 1, "wrong", "remote-e1", "", query)
            Harness.truthy(not inst:peer_has("peer-a"))

            inst:require_peer("peer-a")
            local fresh = latest["peer-a"].query
            receiver("peer-a", 9, 1, identity, "remote-e1", "", query)
            Harness.truthy(not inst:peer_has("peer-a"), "stale echo must not acknowledge")
            receiver("peer-a", 9, 1, identity, "remote-e1", "", fresh)
            Harness.truthy(inst:peer_has("peer-a"), "current challenge must acknowledge")

            receiver("peer-a", 9, 0, identity, "remote-e2", "remote-query", "")
            Harness.truthy(not inst:peer_has("peer-a"),
                "unchallenged process-epoch change must revoke proof")
            inst:require_peer("peer-a")
            local restart = latest["peer-a"].query
            receiver("peer-a", 9, 1, identity, "remote-e2", "", restart)
            Harness.truthy(inst:peer_has("peer-a"),
                "fresh challenged process restart must recover")
        end)
    end)

    Harness.test("peer parity exact reply acceptance matrix fails closed", function()
        with_network_stubs(function()
            local factory = load_factory()
            local identity = "wire-v1:2:12345678:abcdef01"
            local cases = {
                { label = "schema mismatch", schema = 8, identity = identity,
                    epoch = "remote-e1", echo = "current", accepted = false },
                { label = "missing identity", schema = 9, identity = nil,
                    epoch = "remote-e1", echo = "current", accepted = false },
                { label = "wrong identity", schema = 9, identity = "wire-v1:other",
                    epoch = "remote-e1", echo = "current", accepted = false },
                { label = "missing epoch", schema = 9, identity = identity,
                    epoch = nil, echo = "current", accepted = false },
                { label = "unsafe epoch", schema = 9, identity = identity,
                    epoch = "remote epoch", echo = "current", accepted = false },
                { label = "missing echo", schema = 9, identity = identity,
                    epoch = "remote-e1", echo = nil, accepted = false },
                { label = "stale echo", schema = 9, identity = identity,
                    epoch = "remote-e1", echo = "stale", accepted = false },
                { label = "current echo", schema = 9, identity = identity,
                    epoch = "remote-e1", echo = "current", accepted = true },
            }

            for i = 1, #cases do
                local case = cases[i]
                local inst, receiver_fn, latest = build_exact(factory, identity)
                local receiver = assert(receiver_fn())
                inst:require_peer("peer-matrix")
                local current = latest["peer-matrix"].query
                local echo = case.echo == "current" and current or case.echo
                receiver("peer-matrix", case.schema, 1, case.identity,
                    case.epoch, "", echo)
                Harness.equal(inst:peer_has("peer-matrix"), case.accepted,
                    "unexpected exact reply verdict: " .. case.label)
            end
        end)
    end)

    Harness.test("peer parity exact query acceptance matrix echoes only valid proof", function()
        with_network_stubs(function()
            local factory = load_factory()
            local identity = "wire-v1:2:12345678:abcdef01"
            local inst, receiver_fn, latest = build_exact(factory, identity)
            local receiver = assert(receiver_fn())

            receiver("peer-query", 9, 0, identity, "remote-e1", "remote-q1", "")
            Harness.truthy(inst:peer_has("peer-query"))
            Harness.equal(latest["peer-query"].reply, 1)
            Harness.equal(latest["peer-query"].echo, "remote-q1")

            receiver("peer-query", 9, 0, identity, "remote-e2", "remote-q2", "")
            Harness.truthy(not inst:peer_has("peer-query"),
                "unchallenged query epoch change must revoke exact proof")

            receiver("peer-bad-query", 9, 0, identity, "remote e1", "remote-q", "")
            Harness.truthy(not inst:peer_has("peer-bad-query"))
            Harness.equal(latest["peer-bad-query"], nil,
                "malformed query proof must not receive a reply")
        end)
    end)

    Harness.test("peer parity exact mismatch immediately disables an enabled feature", function()
        with_network_stubs(function()
            local factory = load_factory()
            local identity = "wire-v1:2:12345678:abcdef01"
            local inst, receiver_fn = build_exact(factory, identity)
            local enabled, disabled = 0, 0
            inst:register_gated_feature("exact-live", {
                on_enable = function() enabled = enabled + 1 end,
                on_disable = function() disabled = disabled + 1 end,
            })
            inst:tick(0)
            Harness.equal(inst:applied_state(), "enabled")
            Harness.equal(enabled, 1)
            Harness.equal(disabled, 0)

            local receiver = assert(receiver_fn())
            receiver("peer-mismatch", 9, 0, "wire-v1:wrong",
                "remote-e1", "remote-query", "")
            Harness.equal(inst:applied_state(), "disabled",
                "identity mismatch must synchronously revoke the enabled state")
            Harness.equal(disabled, 1,
                "identity mismatch must synchronously invoke on_disable once")
            Harness.truthy(not inst:peer_has("peer-mismatch"))
        end)
    end)

    Harness.test("peer parity exact mode retires disconnect epochs with hard bounds", function()
        with_network_stubs(function()
            local factory = load_factory()
            local identity = "wire-v1:1:12345678:abcdef01"
            local inst, receiver_fn, latest = build_exact(factory, identity)
            local receiver = assert(receiver_fn())

            for epoch = 1, 9 do
                inst:require_peer("peer-one")
                receiver("peer-one", 9, 1, identity, "remote-e" .. epoch, "",
                    latest["peer-one"].query)
                Harness.truthy(inst:peer_has("peer-one"))
                inst:forget_peer("peer-one")
            end
            Harness.truthy(not inst:is_epoch_retired("peer-one", "remote-e1"),
                "oldest retired epoch must be evicted at the per-peer cap")
            Harness.truthy(inst:is_epoch_retired("peer-one", "remote-e9"))

            for peer = 2, 40 do
                local id = "peer-" .. peer
                inst:require_peer(id)
                receiver(id, 9, 1, identity, "epoch-" .. peer, "", latest[id].query)
                inst:forget_peer(id)
            end
            Harness.equal(inst:retired_peer_count(), inst.MAX_RETIRED_PEERS)

            inst:require_peer("peer-40")
            local replay_query = latest["peer-40"].query
            receiver("peer-40", 9, 1, identity, "epoch-40", "", replay_query)
            Harness.truthy(not inst:peer_has("peer-40"),
                "retired process epoch must not authorize a reused peer id")
        end)
    end)

    Harness.test("ct hot-join preflight precedes native sync and has bounded fallback", function()
        local path = repo_root .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_meta_trait_boons.lua"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        local hook_at = assert(source:find('mod:hook("GameNetworkManager", "hot_join_sync"', 1, true))
        local require_at = assert(source:find("inst:require_peer(peer_id)", hook_at, true))
        local strip_at = assert(source:find('_ct_strip_modded_content("hot_join_unconfirmed:"', require_at, true))
        local native_at = assert(source:find("return func(self, peer_id, ...)", strip_at, true))
        Harness.truthy(hook_at < require_at and require_at < strip_at and strip_at < native_at,
            "pending fence and strip must run before native hot-join sync")
        Harness.truthy(source:find("network_server.kick_peer", strip_at, true) ~= nil,
            "strip failure must reject instead of calling unsafe native sync")
        Harness.truthy(source:find('mod:hook("GameNetworkManager", "remove_peer"', native_at, true) ~= nil,
            "real leave must forget peer proof")
    end)

    Harness.test("ct issue 426 diagnostic separates gate catalog state and live coverage", function()
        local path = repo_root .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_meta_trait_boons.lua"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        local census_at = assert(source:find("local function _ct_census_modded_content()", 1, true))
        local player_at = assert(source:find('_ct_each_server_state_row(run_state, "power_ups"', census_at, true))
        local persist_at = assert(source:find('_ct_each_server_state_row(run_state, "persistent_buffs"', player_at, true))
        local command_at = assert(source:find('mod:command("ct_426_diag"', persist_at, true))
        local summary_at = assert(source:find("[ct:426:diag] summary", command_at, true))
        Harness.truthy(census_at < player_at and player_at < persist_at
            and persist_at < command_at and command_at < summary_at)
        for _, marker in ipairs({
            "installed=%s", "gate=%s", "catalog=%s", "state=%s",
            "live_custom=%s", "roster_known=%s", "missing=%d",
        }) do
            Harness.truthy(source:find(marker, summary_at, true), "missing #426 discriminator: " .. marker)
        end
        Harness.truthy(source:find('audit_lookup("power_up"', command_at, true))
        Harness.truthy(source:find('audit_lookup("buff"', command_at, true))
        Harness.truthy(source:find("census.total == 0", command_at, true),
            "mixed parity must require zero surviving CT state")
    end)
end

return register
