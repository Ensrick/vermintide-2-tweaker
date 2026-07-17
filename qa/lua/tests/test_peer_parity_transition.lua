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
end

return register
