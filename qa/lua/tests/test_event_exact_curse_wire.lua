return function(H, repo_root)
    local Policy = assert(loadfile(repo_root
        .. "/event_tweaker/scripts/mods/event_tweaker/event_tweaker_curse_wire_policy.lua"))()
    local Curses = assert(loadfile(repo_root
        .. "/event_tweaker/scripts/mods/event_tweaker/event_tweaker_curses.lua"))()
    local WireCatalog = assert(loadfile(repo_root
        .. "/event_tweaker/scripts/mods/event_tweaker/_lib_wire_catalog.lua"))()

    local function fixture()
        local templates, lookup = {}, {}
        for i = 1, #Curses.MANAGED_CURSES do
            local name = Curses.MANAGED_CURSES[i].id
            local id = 700 + i
            templates[name] = {
                packages = { "resource_packages/mutators/mutator_" .. name },
            }
            lookup[name] = id
            lookup[id] = name
        end
        return templates, lookup
    end

    H.test("Event #430 exact identity covers all managed curse ids and packages", function()
        local templates, lookup = fixture()
        local proof, err = Policy.capture(Curses, templates, lookup, WireCatalog)
        H.equal(err, nil)
        H.equal(proof.count, 11)
        H.truthy(proof.identity:find("^wire%-v1:11:") ~= nil)
        H.equal(Policy.integrity(Curses, templates, lookup, proof), true)

        local unrelated_id = 999
        lookup.unrelated_mutator = unrelated_id
        lookup[unrelated_id] = "unrelated_mutator"
        H.equal(Policy.integrity(Curses, templates, lookup, proof), true,
            "unrelated later appends must not invalidate tracked ids")
    end)

    H.test("Event #430 identity changes on tracked numeric drift", function()
        local templates_a, lookup_a = fixture()
        local proof_a = assert(Policy.capture(Curses, templates_a, lookup_a, WireCatalog))
        local templates_b, lookup_b = fixture()
        local name = Curses.MANAGED_CURSES[4].id
        local old = lookup_b[name]
        lookup_b[old] = nil
        lookup_b[name] = 900
        lookup_b[900] = name
        local proof_b = assert(Policy.capture(Curses, templates_b, lookup_b, WireCatalog))
        H.truthy(proof_a.identity ~= proof_b.identity)
        H.equal(Policy.integrity(Curses, templates_b, lookup_b, proof_a), false)
    end)

    H.test("Event #430 package and reverse lookup mismatches fail closed", function()
        local templates, lookup = fixture()
        local name = Curses.MANAGED_CURSES[1].id
        templates[name].packages[1] = "wrong/package"
        local proof, err = Policy.capture(Curses, templates, lookup, WireCatalog)
        H.equal(proof, nil)
        H.truthy(err:find("packages%-mismatch") ~= nil)

        templates, lookup = fixture()
        local id = lookup[name]
        lookup[id] = "other"
        proof, err = Policy.capture(Curses, templates, lookup, WireCatalog)
        H.equal(proof, nil)
        H.truthy(err:find("lookup%-mismatch") ~= nil)
    end)

    H.test("Event #430 optional UI gate owns settings and supports load order", function()
        local ids = {}
        for i = 1, #Curses.MANAGED_CURSES do ids[i] = Curses.MANAGED_CURSES[i].id end
        local spec = assert(Policy.runtime_gate_spec("event_tweaker", ids,
            function() return false, "catalog unavailable" end))
        ids[1] = "mutated"
        H.equal(spec.setting_ids[1], "curse_blood_storm")
        H.equal(#spec.setting_ids, 11)
        for i = 1, #spec.setting_ids do
            H.truthy(spec.setting_ids[i] ~= "cursed_lighting",
                "presentation-only lighting must not be parity gated")
        end

        local calls, captured = {}, nil
        local ok = Policy.try_register_runtime_gate(function(name)
            calls[#calls + 1] = name
            if name == "gut_dev" then
                return { mod_tweaker = {
                    register_runtime_gate = function() error("planted dev GUI failure") end,
                } }
            end
            if name == "gut" then
                return { mod_tweaker = {
                    register_runtime_gate = function(_, gate_id, gate_spec)
                        captured = { gate_id, gate_spec }
                        return true
                    end,
                } }
            end
        end, "event_tweaker:430:exact-curse-catalog", spec)
        H.equal(ok, true)
        H.deep_equal(calls, { "gut_dev", "gut" })
        H.equal(captured[1], "event_tweaker:430:exact-curse-catalog")
        H.equal(captured[2], spec)
    end)

    H.test("Event #430 production uses exact committed state and real disconnect retirement", function()
        local function read(relative)
            local file = assert(io.open(repo_root .. "/" .. relative, "rb"))
            local text = file:read("*a")
            file:close()
            return text
        end
        local guard = read("event_tweaker/scripts/mods/event_tweaker/_evt_guard430_curse_parity.lua")
        H.truthy(guard:find('local ET_PEER_PARITY_CHANNEL = "et_curse_catalog_exact_v1"', 1, true),
            "exact Event peers must use a dedicated channel")
        H.equal(guard:find('local ET_PEER_PARITY_CHANNEL = "et_peer_parity_present"', 1, true), nil,
            "exact Event must not reuse the legacy presence-only channel")
        H.truthy(guard:find("local ET_PEER_PARITY_SCHEMA  = 3", 1, true),
            "exact Event schema must remain pinned")
        H.truthy(guard:find("wire_identity = wire_proof.identity", 1, true))
        H.truthy(guard:find("pcall(inst.install, inst)", 1, true),
            "beacon installation must be contained")
        H.truthy(guard:find("pcall(inst.is_installed, inst)", 1, true),
            "downstream hooks require positive installed-state proof")
        H.truthy(guard:find("pcall(pp.is_installed, pp)", 1, true),
            "authoritative Event floor independently requires an installed receiver")
        H.truthy(guard:find("mod._et_peer_parity = nil", 1, true),
            "partial installation must fail closed")
        H.truthy(guard:find('mod:hook_safe("GameNetworkManager", "remove_peer"', 1, true))
        H.truthy(guard:find("pcall(pp.applied_state, pp)", 1, true))
        H.truthy(guard:find("WirePolicy.integrity", 1, true))
        H.truthy(guard:find("runtime_gate_spec", 1, true))
        local gate_at = assert(guard:find("local spec = WirePolicy.runtime_gate_spec", 1, true))
        local gate_end = assert(guard:find("local ok_register", gate_at, true))
        H.truthy(guard:sub(gate_at, gate_end):find(
            "local available = _curse_wire_safe() == true", 1, true),
            "UI availability must consume the complete authoritative predicate")
        local predicate_at = assert(guard:find("local function _curse_wire_safe()", 1, true))
        H.truthy(predicate_at < gate_at,
            "the complete predicate must exist before synchronous GUI evaluation")
        local predicate_end = assert(guard:find("end\n\nif inst then", predicate_at))
        local predicate = guard:sub(predicate_at, predicate_end)
        H.truthy(predicate:find("pcall", 1, true)
            and predicate:find("WirePolicy.integrity", 1, true),
            "UI and gameplay must both close on post-capture catalog drift")
        H.truthy(predicate:find("_peer_feature_wire_safe", 1, true),
            "UI and gameplay must both require installed exact peer state")
        H.truthy(guard:find("runtime_gate_attempts >= 30", 1, true),
            "optional GUI registration retries must be bounded")
        H.truthy(guard:find("pcall(WirePolicy.try_register_runtime_gate", 1, true),
            "optional GUI registration must not escape into mod.update")
        H.truthy(guard:find("parity_feature_registered = ok_feature and ok_count and feature_count >= 1", 1, true),
            "feature registration needs positive proof")
        H.truthy(guard:find("if not parity_feature_registered then return false end", 1, true),
            "missing peer notification owner must keep managed curses inert")
        H.truthy(guard:find("Unavailable until every player has the same Tweaker: Events curse catalog.", 1, true))
        H.equal(guard:find("mod:set(", 1, true), nil,
            "presentation gate must not rewrite saved settings")
    end)

    -- End-to-end sender-side proof of the crash this floor exists to prevent.
    -- Each lobby runs the SHIPPED beacon copy over a real transport with the
    -- real captured identity, so the outcome follows from the actual handshake
    -- rather than from a restated assertion. The test above pins which terms the
    -- production predicate composes; this one proves what that composition does.
    --
    -- The all-modded lobby is the control. Without it a zero-transmission result
    -- proves only that the rig is dead: delete the floor and the vanilla lobby
    -- starts transmitting all 11 ids, which is exactly the difference measured
    -- here.
    local function drive_lobby(client_mode)
        local Parity = assert(loadfile(repo_root
            .. "/event_tweaker/scripts/mods/event_tweaker/_lib_peer_parity.lua"))()
        local JoinPolicy = assert(loadfile(repo_root
            .. "/event_tweaker/scripts/mods/event_tweaker/event_tweaker_curse_join_policy.lua"))()

        local templates, lookup = fixture()
        local proof = assert(Policy.capture(Curses, templates, lookup, WireCatalog))

        -- A peer whose process-local ids differ captures a different identity
        -- from the same 11 vanilla names -- the case presence alone cannot see.
        local other_templates, other_lookup = {}, {}
        for i = 1, #Curses.MANAGED_CURSES do
            local name = Curses.MANAGED_CURSES[i].id
            other_templates[name] = {
                packages = { "resource_packages/mutators/mutator_" .. name },
            }
            other_lookup[name] = 500 + i
            other_lookup[500 + i] = name
        end
        local other_proof = assert(
            Policy.capture(Curses, other_templates, other_lookup, WireCatalog))

        local previous_managers, previous_network = Managers, Network
        local roster = { { peer_id = "host" }, { peer_id = "client" } }
        local active = "host"
        Managers = { player = { human_players = function() return roster end } }
        Network = { peer_id = function() return active end }

        local receivers = {}
        local function as(peer, body)
            local previous = active
            active = peer
            local ok, err = pcall(body)
            active = previous
            if not ok then error(err, 0) end
        end

        local function peer_mod(peer)
            return {
                network_register = function(_, channel, callback)
                    receivers[peer] = receivers[peer] or {}
                    receivers[peer][channel] = callback
                end,
                -- A peer not running the mod registers nothing, so a broadcast
                -- reaches no callback at all: absence of ack is absence of mod.
                network_send = function(_, channel, recipient, schema, is_reply,
                        identity, epoch, query, echo)
                    local targets = {}
                    if recipient == nil or recipient == "others" then
                        for candidate in pairs(receivers) do
                            if candidate ~= peer then targets[#targets + 1] = candidate end
                        end
                    else
                        targets[1] = recipient
                    end
                    for i = 1, #targets do
                        local target = targets[i]
                        local callback = receivers[target] and receivers[target][channel]
                        if callback then
                            as(target, function()
                                callback(peer, schema, is_reply, identity, epoch, query, echo)
                            end)
                        end
                    end
                end,
                debug = function() end,
                echo = function() end,
            }
        end

        local function build(peer, identity, epoch)
            return assert(Parity(peer_mod(peer), {
                channel = "et_curse_catalog_exact_v1",
                schema = 3,
                mod_label = "Tweaker: Events",
                echo_prefix = "[Events]",
                wire_identity = identity,
                session_epoch = epoch,
                poll_interval = 0,
                settle_enable = 0,
            }))
        end

        local result = {}
        local ok, err = xpcall(function()
            -- The client installs first so the host's commit broadcast can be
            -- answered inside the same synchronous seam a live lobby uses.
            if client_mode == "modded" then
                local client = build("client", proof.identity, "client-e1")
                as("client", function() client:install() end)
            elseif client_mode == "divergent" then
                local client = build("client", other_proof.identity, "client-e1")
                as("client", function() client:install() end)
            end

            local host = build("host", proof.identity, "host-e1")
            host:register_gated_feature("et_cursed_adventure_curses", {
                label = "peer_parity_curse_feature_label",
            })
            as("host", function()
                host:install()
                host:tick(1)
                host:tick(1)
            end)

            result.applied = host:applied_state()
            result.acked_client = host:peer_has("client")

            -- The production floor: committed receiver, exact peer state, live
            -- catalog integrity, and a closed pre-session roster.
            local floor_open = host:is_installed()
                and host:applied_state() == "enabled"
                and Policy.integrity(Curses, templates, lookup, proof) == true
                and JoinPolicy.can_arm(true, false) == true

            -- selected_curse_mutators() drops every managed curse when the floor
            -- is shut, so nothing reaches append_live_event_mutators and no
            -- rpc_activate_mutator_client carries a managed id to any peer.
            result.transmitted_ids = {}
            result.client_decoded = {}
            if floor_open then
                for i = 1, #Curses.MANAGED_CURSES do
                    local name = Curses.MANAGED_CURSES[i].id
                    result.transmitted_ids[#result.transmitted_ids + 1] = lookup[name]
                end
            end
            for i = 1, #result.transmitted_ids do
                local client_lookup = client_mode == "divergent" and other_lookup or lookup
                result.client_decoded[#result.client_decoded + 1] =
                    client_lookup[result.transmitted_ids[i]] or "<unresolved>"
            end
        end, debug.traceback)

        Managers, Network = previous_managers, previous_network
        if not ok then error(err, 0) end
        return result
    end

    H.test("Event #430 a peer without event_tweaker never receives a managed curse id", function()
        local vanilla = drive_lobby("vanilla")
        H.equal(vanilla.acked_client, false,
            "a peer with no event_tweaker receiver can never acknowledge")
        H.equal(vanilla.applied, "disabled")
        H.equal(#vanilla.transmitted_ids, 0,
            "no managed curse id may reach a lobby containing a non-event_tweaker peer")
        H.equal(#vanilla.client_decoded, 0,
            "a vanilla peer must never resolve a managed curse id or its package")

        local divergent = drive_lobby("divergent")
        H.equal(divergent.acked_client, false,
            "a peer whose curse catalog resolves to different ids must be rejected")
        H.equal(divergent.applied, "disabled")
        H.equal(#divergent.transmitted_ids, 0,
            "presence without an identical catalog must not authorize injection")

        -- Control: the same rig with a peer proving the same catalog transmits
        -- every managed id, so the two zero results above are the floor acting.
        local modded = drive_lobby("modded")
        H.equal(modded.acked_client, true)
        H.equal(modded.applied, "enabled")
        H.equal(#modded.transmitted_ids, 11)
        H.equal(#modded.client_decoded, 11)
        for i = 1, #modded.client_decoded do
            H.truthy(modded.client_decoded[i] ~= "<unresolved>",
                "an exact-parity peer resolves every transmitted curse id")
        end
    end)
end
