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

    -- Exact mode is opt-in per FILE, deliberately, because passing
    -- `wire_identity` changes a live network protocol: an exact peer and a
    -- presence-only peer of the same mod fail closed against each other. Exact
    -- mode is therefore granted one converted axis at a time, and a file leaves
    -- the unauthorized list ONLY together with its own positive opt-in
    -- assertion below, so a partial or accidental conversion cannot land
    -- silently. Every other file that builds a parity instance stays on the
    -- presence protocol.
    local function read_source(relative_path)
        local file = assert(io.open(repo_root .. "/" .. relative_path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    Harness.test("shared exact mode is authorized only for CRT, Event and the CWV exact runtime", function()
        local unauthorized = {
            "chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_meta_trait_boons.lua",
            -- CWV's entry file keeps the PRESENCE beacon
            -- (cwv_peer_parity_present): deployed CWV builds already speak that
            -- protocol, and #914's appearance ledgers hang off it. CWV's exact
            -- channels live in _cwv_exact_wire_runtime.lua instead.
            "character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua",
            "event_tweaker/scripts/mods/event_tweaker/_evt_shadow_adventure.lua",
            "weapon_tweaker/scripts/mods/weapon_tweaker/_wt431_damage_profile_parity.lua",
            "weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt431_damage_profile_parity.lua",
        }
        for i = 1, #unauthorized do
            Harness.equal(read_source(unauthorized[i]):find("[^_%w]wire_identity%s*="), nil,
                "shared exact opt-in is not yet authorized for " .. unauthorized[i])
        end

        local career = read_source(
            "career_tweaker/scripts/mods/career_tweaker/career_tweaker.lua")
        Harness.truthy(career:find("[^_%w]wire_identity%s*=%s*wire_identity") ~= nil,
            "CRT exact-mode opt-in disappeared")

        -- #430: Event's managed curse catalog.
        local event = read_source(
            "event_tweaker/scripts/mods/event_tweaker/_evt_guard430_curse_parity.lua")
        Harness.truthy(event:find("[^_%w]wire_identity%s*=%s*wire_proof%.identity") ~= nil,
            "Event must opt its managed curse catalog into exact mode")
        Harness.truthy(event:find('"et_curse_catalog_exact_v1"', 1, true) ~= nil,
            "Event #430 exact channel disappeared")

        -- #423/#424: CWV is the third authorized consumer. Both of its exact
        -- channels are built through ONE factory wrapper, which refuses to
        -- construct an instance without an identity -- so exact mode can never
        -- be half-engaged (a channel name change without a proven catalog).
        local cwv = read_source("character_weapon_variants/scripts/mods/"
            .. "character_weapon_variants/_cwv_exact_wire_runtime.lua")
        Harness.truthy(cwv:find("[^_%w]wire_identity%s*=%s*identity") ~= nil,
            "CWV exact runtime must pass wire_identity into the parity factory")
        local _, factories = cwv:gsub("local function new_exact_parity", "")
        Harness.equal(factories, 1,
            "CWV must build every exact instance through the single guarded factory")
        Harness.truthy(cwv:find('return nil, "identity-missing"', 1, true),
            "CWV exact factory must refuse to build without an identity")
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

    Harness.test("Event legacy and exact curse channels cannot acknowledge each other", function()
        with_network_stubs(function()
            local factory = load_factory()
            local receivers = { legacy = {}, exact = {} }
            local function fake_mod(peer_id)
                return {
                    network_register = function(_, channel, callback)
                        receivers[peer_id][channel] = callback
                    end,
                    network_send = function(_, channel, recipient, ...)
                        local target = receivers[recipient]
                        local callback = target and target[channel]
                        if callback then callback(peer_id, ...) end
                    end,
                    debug = function() end,
                    echo = function() end,
                }
            end
            local legacy = assert(factory(fake_mod("legacy"), {
                channel = "et_peer_parity_present",
                schema = 2,
                poll_interval = 0,
                settle_enable = 0,
            }))
            local exact = assert(factory(fake_mod("exact"), {
                channel = "et_curse_catalog_exact_v1",
                schema = 3,
                wire_identity = "et-wire-v1:11:12345678:abcdef01",
                session_epoch = "exact-e1",
                poll_interval = 0,
                settle_enable = 0,
            }))
            legacy:install()
            exact:install()
            Harness.truthy(not legacy:require_peer("exact"))
            Harness.truthy(not exact:require_peer("legacy"))
            Harness.truthy(not legacy:peer_has("exact"),
                "legacy Event presence must not acknowledge an exact curse peer")
            Harness.truthy(not exact:peer_has("legacy"),
                "exact Event curse parity must reject a legacy presence acknowledgement")
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

    -- Issue 426 presentation half. The module is pure, so drive the shipped
    -- decisions directly instead of pattern-matching the call site.
    local function load_ct_wire_policy()
        local path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_wire_policy.lua"
        local chunk, err = loadfile(path)
        if not chunk then error(err) end
        return chunk()
    end

    Harness.test("ct 426 gate spec covers every modded-content row and fails closed", function()
        local wp = load_ct_wire_policy()
        Harness.truthy(type(wp.GATED_SETTING_IDS) == "table" and #wp.GATED_SETTING_IDS > 0,
            "gated row list must not be empty")

        -- Every row that controls a ct-owned NetworkLookup index must be gated.
        -- A new trait boon or miracle added without a row here would keep an
        -- actionable toggle while the wire gate is closed.
        local declared = {}
        for _, id in ipairs(wp.GATED_SETTING_IDS) do
            Harness.equal(declared[id], nil, "duplicate gated row: " .. id)
            declared[id] = true
        end
        for _, required in ipairs({
            "enable_boon_reworks",
            "enable_boon_anath_raema_swiftness",
            "enable_boon_asuryan_wrath",
            "enable_boon_manann_tempest",
            "enable_boon_taal_twinned_arrow",
            "enable_boon_vauls_anvil",
            "tweak_miracle_of_isha_aegis",
            "tweak_miracle_of_isha_wounds",
            "tweak_miracle_of_ulric_persistent",
        }) do
            Harness.truthy(declared[required], "modded-content row not gated: " .. required)
        end

        -- Every declared row must be a live widget in the shipped data tree,
        -- otherwise the gate greys nothing (runtime_gate_spec cannot know).
        local data_path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev_data.lua"
        local data_file = assert(io.open(data_path, "rb"))
        local data_source = data_file:read("*a")
        data_file:close()
        for _, id in ipairs(wp.GATED_SETTING_IDS) do
            Harness.truthy(data_source:find('setting_id = "' .. id .. '"', 1, true) ~= nil,
                "gated row is not a declared widget: " .. id)
        end

        -- Malformed input is rejected wholesale rather than half-registered.
        Harness.equal(wp.runtime_gate_spec("", wp.GATED_SETTING_IDS, function() end), nil)
        Harness.equal(wp.runtime_gate_spec("ct_dev", {}, function() end), nil)
        Harness.equal(wp.runtime_gate_spec("ct_dev", { "a", "a" }, function() end), nil)
        Harness.equal(wp.runtime_gate_spec("ct_dev", { "a", 7 }, function() end), nil)
        Harness.equal(wp.runtime_gate_spec("ct_dev", wp.GATED_SETTING_IDS, nil), nil)

        -- A valid spec copies the list, so a later caller mutation cannot
        -- retarget a live gate.
        local source_ids = { "enable_boon_vauls_anvil", "tweak_miracle_of_isha_aegis" }
        local spec = wp.runtime_gate_spec("ct_dev", source_ids, function()
            return false, wp.GATE_REASON
        end)
        Harness.truthy(type(spec) == "table")
        Harness.equal(spec.mod_id, "ct_dev")
        Harness.equal(#spec.setting_ids, 2)
        source_ids[1] = "mutated"
        Harness.equal(spec.setting_ids[1], "enable_boon_vauls_anvil",
            "gate spec must own a copy of the row list")

        local available, reason = spec.evaluate()
        Harness.equal(available, false)
        Harness.truthy(type(reason) == "string" and reason ~= "",
            "a closed gate must carry a player-facing reason")
        -- Player-facing text carries no lifecycle metadata and no em dash.
        Harness.equal(reason:find("\226\128\148"), nil, "no em dash in player-facing text")
        Harness.equal(reason:find("[", 1, true), nil, "no lifecycle metadata in player-facing text")

        -- GUT absent must fail closed, never error.
        Harness.equal(wp.try_register_runtime_gate(nil, "gate", spec), false)
        Harness.equal(wp.try_register_runtime_gate(function() return nil end, "", spec), false)
        Harness.equal(wp.try_register_runtime_gate(function() return nil end, "gate", spec), false)
        Harness.equal(wp.try_register_runtime_gate(function() error("boom") end, "gate", spec), false)
        Harness.equal(
            wp.try_register_runtime_gate(function() return { mod_tweaker = {} } end, "gate", spec),
            false, "a GUT without register_runtime_gate must not be treated as registered")

        -- Present GUT registers exactly once, against the dev id first.
        local seen_gate_id, seen_spec, probed = nil, nil, {}
        local ok = wp.try_register_runtime_gate(function(id)
            probed[#probed + 1] = id
            return {
                mod_tweaker = {
                    register_runtime_gate = function(_, gate_id, gate_spec)
                        seen_gate_id, seen_spec = gate_id, gate_spec
                        return true
                    end,
                },
            }
        end, "ct_dev:426:peer-parity", spec)
        Harness.equal(ok, true)
        Harness.equal(seen_gate_id, "ct_dev:426:peer-parity")
        Harness.equal(seen_spec, spec)
        Harness.equal(probed[1], "gut_dev", "dev Mod Tweaker must be probed first")
    end)

    Harness.test("ct 426 presentation bridge never weakens the runtime gate", function()
        local path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_meta_trait_boons.lua"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()

        -- The bridge must sit inside the beacon-installed branch and must not
        -- introduce a second mod.update wrap or any new hook.
        local bridge_at = assert(source:find("_ct_wire_policy", 1, true),
            "presentation bridge not wired")
        Harness.truthy(source:find("inst:applied_state() == \"enabled\"", bridge_at, true) ~= nil,
            "gate rows must track the settled beacon state")
        -- Exactly one wrap per branch of the beacon if/else, never a third: the
        -- installed path reuses the strip ticker and the fail-safe path owns the
        -- only wrap it needs. A third would mean the bridge added its own.
        local _, update_wraps = source:gsub("mod%.update%s*=%s*function", "")
        Harness.equal(update_wraps, 2,
            "bridge must reuse each branch's ticker, not add its own mod.update wrap")
        local beacon_else_at = assert(source:find("peer-parity beacon UNAVAILABLE", 1, true))
        local installed_at = assert(source:find("peer-parity beacon installed", 1, true))
        Harness.truthy(installed_at < beacon_else_at,
            "the two wraps must be the installed and fail-safe branches, in that order")
        local _, hot_join_hooks = source:gsub('mod:hook%("GameNetworkManager", "hot_join_sync"', "")
        Harness.equal(hot_join_hooks, 1, "hot_join_sync must stay a single hook")
        local _, remove_peer_hooks = source:gsub('mod:hook%("GameNetworkManager", "remove_peer"', "")
        Harness.equal(remove_peer_hooks, 1, "remove_peer must stay a single hook")

        -- The runtime gate must not consult GUT: safety is independent.
        local wire_safe_at = assert(source:find("mod._ct_wire_safe = function()", 1, true))
        local wire_safe_body = source:sub(wire_safe_at, wire_safe_at + 400)
        Harness.equal(wire_safe_body:find("mod_tweaker", 1, true), nil,
            "wire safety must never depend on the Mod Tweaker bridge")
        Harness.equal(wire_safe_body:find("gate_registered", 1, true), nil,
            "wire safety must never depend on gate registration")
    end)
end

return register
