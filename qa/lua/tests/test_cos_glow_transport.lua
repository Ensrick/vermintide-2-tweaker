return function(H, repo_root)
    local function read(relative_path)
        local file = assert(io.open(repo_root .. "/" .. relative_path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function occurrences(haystack, needle)
        local count, offset = 0, 1
        while true do
            local at = haystack:find(needle, offset, true)
            if not at then return count end
            count = count + 1
            offset = at + #needle
        end
    end

    local base = "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
    local entry = read(base .. "cosmetics_tweaker.lua")
    local module_path = base .. "_cos_glow_transport.lua"
    local source = read(module_path)
    local Transport = assert(loadfile(repo_root .. "/" .. module_path))()

    local function fixture(options)
        options = options or {}
        local handlers, registration_order, sends = {}, {}, {}
        local values = {}
        local mod = {
            _active_per_item_glow = options.active_glow,
            _active_per_item_glow_identity = options.identity,
            _active_per_item_glow_slot = options.slot,
        }
        function mod:get(key) return values[key] end
        function mod:network_register(name, fn)
            handlers[name] = fn
            registration_order[#registration_order + 1] = name
        end
        function mod:network_send(name, target, schema, payload)
            sends[#sends + 1] = {
                name = name, target = target, schema = schema, payload = payload,
            }
        end

        local now = options.now or 1
        local host = options.host
        local alerts, logs, prints = {}, {}, {}
        local managers = {
            state = { network = { game = true } },
            player = {
                local_player = function()
                    return { peer_id = options.local_peer or "local-peer" }
                end,
            },
        }
        local deps = {
            glow_by_peer = options.glow_by_peer or {},
            rpc_schema = 7,
            is_local_server = function() return host end,
            host_peer_id = function() return options.host_peer or "host-peer" end,
            log = function(fmt, ...)
                logs[#logs + 1] = string.format(fmt, ...)
            end,
            dbg = function(fmt, ...)
                logs[#logs + 1] = string.format(fmt, ...)
            end,
            dbg_alert = function(fmt, ...)
                alerts[#alerts + 1] = string.format(fmt, ...)
            end,
            clock = function() return now end,
            get_managers = function() return managers end,
            get_printf = function()
                return function(fmt, ...)
                    prints[#prints + 1] = string.format(fmt, ...)
                end
            end,
        }
        return {
            mod = mod, deps = deps, handlers = handlers,
            registration_order = registration_order, sends = sends,
            alerts = alerts, logs = logs, prints = prints,
            set_now = function(value) now = value end,
            set_host = function(value) host = value end,
            managers = managers,
        }
    end

    H.test("Cosmetics entry installs one ordered glow transport owner", function()
        H.equal(occurrences(entry,
            '"scripts/mods/cosmetics_tweaker/_cos_glow_transport"'), 1)
        H.truthy(entry:find(
            '"scripts/mods/cosmetics_tweaker/_cos_glow_transport").install',
            1, true))
        H.equal(entry:find('mod:network_register("cos_glow_apply_req"', 1, true), nil)
        H.equal(entry:find('mod:network_register("cos_glow_apply"', 1, true), nil)

        -- #1159: the four cos_la_* receivers moved into _cos_la_sync_transport.
        -- The glow owner's position invariant is unchanged - it still installs
        -- AFTER the LA channel is registered and BEFORE the husk wield hook - but
        -- the LA anchor is now that owner's second install phase, which runs at
        -- the exact line the last cos_la_* register used to occupy.
        H.equal(entry:find('mod:network_register("cos_la_apply"', 1, true), nil)
        local last_la_rpc = assert(entry:find("LA_SYNC.install_receivers()", 1, true))
        local install = assert(entry:find("_cos_glow_transport", last_la_rpc, true))
        local husk_hook = assert(entry:find(
            'mod:hook("SimpleHuskInventoryExtension", "_wield_slot"', install, true))
        H.truthy(last_la_rpc < install and install < husk_hook)
    end)

    H.test("Cosmetics glow transport owns only its two RPC channels", function()
        local executable = source:gsub("%-%-[^\n]*", "")
        H.equal(occurrences(executable, "mod:network_register("), 2)
        H.equal(occurrences(executable, 'mod:network_register("cos_glow_apply_req"'), 1)
        H.equal(occurrences(executable, 'mod:network_register("cos_glow_apply"'), 1)
        H.equal(executable:find("mod:hook", 1, true), nil)
        H.equal(executable:find("mod.on_", 1, true), nil)
        H.equal(executable:find("mod.update", 1, true), nil)
        H.equal(executable:find("Unit.set_", 1, true), nil)
        H.equal(executable:find("mod:set", 1, true), nil)
    end)

    H.test("Cosmetics glow publisher preserves host and client routing", function()
        local state = { rune = { r = 10, g = 20, b = 30, intensity = 40 } }
        local host_fx = fixture({
            host = true, now = 1, active_glow = state,
            identity = "backend:1|skin:skin_a", slot = "slot_melee",
        })
        local owner = Transport.install(host_fx.mod, host_fx.deps)
        H.equal(Transport.install(host_fx.mod, {}), owner)
        H.deep_equal(host_fx.registration_order,
            { "cos_glow_apply_req", "cos_glow_apply" })
        H.equal(#host_fx.registration_order, 2)
        host_fx.mod._emit_per_item_glow()
        host_fx.mod._glow_sync_tick(0.1)
        H.equal(#host_fx.sends, 1)
        H.equal(host_fx.sends[1].name, "cos_glow_apply")
        H.equal(host_fx.sends[1].target, "all")
        H.equal(host_fx.sends[1].schema, 7)
        H.equal(host_fx.sends[1].payload.state.active_per_item_glow, state)
        H.equal(host_fx.sends[1].payload.state.active_per_item_glow_slot, "slot_melee")
        H.equal(host_fx.deps.glow_by_peer["local-peer"].active_per_item_glow, state)

        local client_fx = fixture({
            host = false, now = 1, local_peer = "client-peer",
            host_peer = "host-peer", active_glow = state,
            identity = "backend:2|skin:skin_b", slot = "slot_ranged",
        })
        Transport.install(client_fx.mod, client_fx.deps)
        client_fx.mod._on_glow_setting_changed()
        client_fx.mod._glow_sync_tick(0.1)
        H.equal(#client_fx.sends, 1)
        H.equal(client_fx.sends[1].name, "cos_glow_apply_req")
        H.equal(client_fx.sends[1].target, "host-peer")
        H.equal(client_fx.sends[1].payload.state.active_per_item_glow_slot,
            "slot_ranged")
        H.equal(client_fx.deps.glow_by_peer["client-peer"], nil)
    end)

    H.test("Cosmetics glow receivers preserve schema and host authority", function()
        local fx = fixture({ host = true, host_peer = "host-peer" })
        Transport.install(fx.mod, fx.deps)
        local state = {
            active_per_item_glow = { rune = { r = 1 } },
            active_per_item_glow_identity = "backend:9|skin:skin_c",
            active_per_item_glow_slot = "slot_melee",
        }

        fx.handlers.cos_glow_apply_req("client-peer", 6, { state = state })
        H.equal(#fx.sends, 0)
        H.equal(#fx.alerts, 1)
        H.equal(#fx.prints, 1)

        fx.handlers.cos_glow_apply_req("client-peer", 7, { state = state })
        H.equal(fx.deps.glow_by_peer["client-peer"], state)
        H.equal(#fx.sends, 1)
        H.equal(fx.sends[1].name, "cos_glow_apply")
        H.equal(fx.sends[1].payload.wearer_peer_id, "client-peer")

        fx.handlers.cos_glow_apply("spoof-peer", 7, {
            wearer_peer_id = "victim", state = state,
        })
        H.equal(fx.deps.glow_by_peer.victim, nil)
        H.equal(#fx.alerts, 2)

        fx.mod._reapply_glow_for_peer = function() return 0 end
        fx.handlers.cos_glow_apply("host-peer", 7, {
            wearer_peer_id = "victim", state = state,
        })
        H.equal(fx.deps.glow_by_peer.victim, state)
        H.truthy(fx.mod._cos574_glow_rehydrate_pending.victim)
    end)

    H.test("Cosmetics glow rehydrate is bounded and network-silent", function()
        local fx = fixture({ host = true, host_peer = "host-peer", now = 1 })
        Transport.install(fx.mod, fx.deps)
        local attempts = 0
        fx.handlers.cos_glow_apply("host-peer", 7, {
            wearer_peer_id = "peer-a",
            state = { active_per_item_glow = { rune = { r = 1 } } },
        })
        fx.mod._reapply_glow_for_peer = function(peer)
            attempts = attempts + 1
            H.equal(peer, "peer-a")
            return attempts == 2 and 3 or 0
        end
        H.equal(fx.mod._cos574_glow_join_contract.max_attempts, 40)
        H.equal(fx.mod._cos574_glow_join_contract.window, 10)
        H.equal(fx.mod._cos574_glow_join_contract.retry_network, false)
        fx.mod._cos574_glow_rehydrate_tick()
        H.truthy(fx.mod._cos574_glow_rehydrate_pending["peer-a"])
        fx.set_now(1.25)
        fx.mod._cos574_glow_rehydrate_tick()
        H.equal(fx.mod._cos574_glow_rehydrate_pending["peer-a"], nil)
        H.equal(attempts, 2)
        H.equal(#fx.sends, 0)

        fx.handlers.cos_glow_apply("host-peer", 7, {
            wearer_peer_id = "peer-a",
            state = { active_per_item_glow = { rune = { r = 1 } } },
        })
        fx.set_now(11.25)
        fx.mod._cos574_glow_rehydrate_tick()
        H.equal(fx.mod._cos574_glow_rehydrate_pending["peer-a"], nil)
        H.equal(attempts, 3)
        H.equal(#fx.sends, 0)
    end)

    H.test("Cosmetics glow hot-join replay preserves target semantics", function()
        local cache = {
            ["peer-a"] = { marker = "a" },
            ["peer-b"] = { marker = "b" },
        }
        local fx = fixture({ host = true, glow_by_peer = cache })
        Transport.install(fx.mod, fx.deps)
        fx.mod._glow_rebroadcast_all_for_hot_join()
        H.equal(#fx.sends, 2)
        H.equal(fx.sends[1].target, "all")
        H.equal(fx.sends[2].target, "all")
        fx.mod._glow_rebroadcast_targeted("joiner")
        H.equal(#fx.sends, 4)
        H.equal(fx.sends[3].target, "joiner")
        H.equal(fx.sends[4].target, "joiner")
        H.equal(#fx.logs, 1)
        H.truthy(fx.logs[1]:find("sent 2 cos_glow_apply", 1, true))
    end)
end
