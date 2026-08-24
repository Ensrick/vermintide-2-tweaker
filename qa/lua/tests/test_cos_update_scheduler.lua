-- Boundary and behaviour guard for the Phase-5 Cosmetics frame owner.
return function(H, repo_root)
    local function read(relative)
        local file = assert(io.open(repo_root .. "/" .. relative, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function occurrences(source, needle)
        local count, cursor = 0, 1
        while true do
            local at = source:find(needle, cursor, true)
            if not at then return count end
            count = count + 1
            cursor = at + #needle
        end
    end

    local entry = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua")
    local module_relative =
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_update_scheduler.lua"
    local source = read(module_relative)
    local module_path = repo_root .. "/" .. module_relative
    local install = 'mod:dofile(\n    "scripts/mods/cosmetics_tweaker/_cos_update_scheduler").install(mod, {'

    H.test("cos update scheduler exclusively owns the former frame boundary", function()
        H.equal(occurrences(entry, install), 1)
        H.equal(occurrences(entry, "mod.update = function"), 0)
        H.equal(occurrences(source, "mod.update = state.update"), 1)
        local at_complete = entry:find("_cos_complete_set_rebroadcast", 1, true)
        local at_owner = entry:find(install, 1, true)
        local at_probe = entry:find("local _cos_diag_glow", 1, true)
        H.truthy(at_complete and at_owner and at_probe)
        H.truthy(at_complete < at_owner)
        H.truthy(at_owner < at_probe)
    end)

    H.test("cos update scheduler adds no registration or unbounded transport", function()
        local executable = source:gsub("%-%-[^\n]*", "")
        for _, forbidden in ipairs({
            "mod:hook(", "mod:hook_safe(", "mod:hook_origin(",
            "mod:command(", "mod:network_register(", "mod:dofile(",
        }) do
            H.equal(occurrences(executable, forbidden), 0, forbidden)
        end
        H.equal(occurrences(executable, 'mod:network_send("cos_la_state_req"'), 1)
        H.truthy(source:find("st.attempts >= 8", 1, true))
        H.truthy(source:find("st.next_at = now_p + 5", 1, true))
        H.truthy(source:find("now < deadline", 1, true))
        H.truthy(source:find("RESPONSIBILITY", 1, true))
        H.truthy(source:find("Consumed via:", 1, true))
    end)

    H.test("cos update scheduler uses accessors for both rebound entry locals", function()
        H.equal(occurrences(entry,
            "get_la_pending_apply = function() return _la_pending_apply end,"), 4)
        H.equal(occurrences(entry,
            "set_la_pending_apply = function(t) _la_pending_apply = t end,"), 2)
        H.equal(occurrences(entry,
            "get_la_bridge_init_done = function() return _la_bridge_init_done end,"), 1)
        H.equal(occurrences(entry,
            "set_la_bridge_init_done = function(v) _la_bridge_init_done = v end,"), 1)
        H.truthy(source:find("local _la_pending_apply = ctx.get_la_pending_apply()", 1, true))
        H.truthy(source:find("ctx.set_la_pending_apply(_la_pending_apply)", 1, true))
        H.truthy(source:find("local _la_bridge_init_done = ctx.get_la_bridge_init_done()", 1, true))
        H.truthy(source:find("ctx.set_la_bridge_init_done(_la_bridge_init_done)", 1, true))
    end)

    local function build(options)
        options = options or {}
        local events = {}
        local now = options.now or 10
        local bridge_done = options.bridge_done
        if bridge_done == nil then bridge_done = true end
        local pending = options.pending or {}
        local sends = {}

        local function event(name)
            events[#events + 1] = name
        end

        local custom_hats = { registered = options.hats_registered ~= false }
        function custom_hats.tick() event("hats") end
        function custom_hats.register_all()
            custom_hats.registered = true
            event("register-hats")
        end

        local gk_set = { registered = options.gk_registered ~= false }
        function gk_set.register_all()
            gk_set.registered = true
            event("register-gk")
        end

        local la_bridge = { registered = true }
        function la_bridge.register_all() event("register-la") end
        function la_bridge.install_apply_gate() event("install-la-gate") end

        local mod = {
            _cos_rewield = { drain = function() event("rewield") end },
            _la_offhand_restore_done = true,
        }
        function mod:info() event("info") end
        function mod:network_send(...)
            sends[#sends + 1] = { ... }
            event("state-pull-send")
        end
        mod._cos_complete_set_rebroadcast_tick = function() event("complete-set") end
        mod._glow_scan_tick = function() event("glow-scan") end
        mod._la_shield_probe_tick = function() event("shield-probe") end
        mod._drain_deferred_la_emits = function() event("deferred-emits") end
        mod._la_tick_peer_purges = function() event("peer-purges") end
        mod._glow_sync_tick = function() event("glow-sync") end
        mod._cos574_glow_rehydrate_tick = function() event("glow-rehydrate") end
        mod._la_restore_offhand_selections = function() event("restore-offhands") end
        mod._la_reconcile = options.reconcile or function() return true end

        local deps = {
            custom_hats = custom_hats,
            la_persist = {
                tick_pending_restore = function() event("persist") end,
            },
            la_bridge = la_bridge,
            gk_set = gk_set,
            get_mod = options.get_mod or function() return {} end,
            get_item_master_list = function() return {} end,
            merge_la_offhand_options = function() event("merge-offhands") end,
            force_load_all_offhand_packages = function() event("force-load") end,
            install_skin_loadout_safety = function() event("skin-safety") end,
            local_player_safe = options.local_player_safe or function() return nil end,
            la_equips_by_peer = options.la_equips_by_peer or {},
            wearer_unit_for_peer = options.wearer_unit_for_peer or function() return nil end,
            get_la_bridge_init_done = function() return bridge_done end,
            set_la_bridge_init_done = function(value) bridge_done = value end,
            is_local_server = options.is_local_server or function() return false end,
            host_peer_id = options.host_peer_id or function() return "host" end,
            local_peer_id_quick = options.local_peer_id_quick or function() return "self" end,
            rpc_schema = 2,
            get_managers = function() return options.managers or {} end,
            now = function() return now end,
            printf = false,
            la_okri = { tick = function() event("okri") end },
            tpe = { update = function() event("tpe") end },
            glow_picker = { ensure_cim_bridge = function() event("cim-bridge") end },
            get_la_pending_apply = function() return pending end,
            set_la_pending_apply = function(value) pending = value end,
        }

        local Runtime = assert(loadfile(module_path))()
        local owner = Runtime.install(mod, deps)
        return {
            mod = mod, deps = deps, owner = owner, events = events, sends = sends,
            set_now = function(value) now = value end,
            get_pending = function() return pending end,
            set_pending = function(value) pending = value end,
            bridge_done = function() return bridge_done end,
        }
    end

    H.test("cos update scheduler preserves the historical tick order", function()
        local fixture = build()
        fixture.mod.update(0.016)
        H.equal(table.concat(fixture.events, ","), table.concat({
            "rewield", "hats", "persist", "complete-set", "force-load",
            "skin-safety", "glow-scan", "cim-bridge", "shield-probe", "okri",
            "deferred-emits", "peer-purges", "tpe", "glow-sync",
            "glow-rehydrate",
        }, ","))
    end)

    H.test("cos update scheduler bridge initialization is one-way and observable", function()
        local fixture = build({
            bridge_done = false, hats_registered = false, gk_registered = false,
        })
        fixture.mod.update(0.016)
        H.equal(fixture.bridge_done(), true)
        H.equal(occurrences(table.concat(fixture.events, ","), "register-hats"), 1)
        H.equal(occurrences(table.concat(fixture.events, ","), "register-gk"), 1)
        H.equal(occurrences(table.concat(fixture.events, ","), "register-la"), 1)
        H.equal(occurrences(table.concat(fixture.events, ","), "merge-offhands"), 1)
        fixture.mod.update(0.016)
        H.equal(occurrences(table.concat(fixture.events, ","), "register-la"), 1)
    end)

    H.test("cos update scheduler refreshes dependencies without replacing its owner", function()
        local fixture = build()
        local second_ticks = 0
        local second = {}
        for key, value in pairs(fixture.deps) do second[key] = value end
        second.custom_hats = {
            registered = true,
            tick = function() second_ticks = second_ticks + 1 end,
        }
        local Runtime = assert(loadfile(module_path))()
        local owner = Runtime.install(fixture.mod, second)
        H.equal(owner, fixture.owner)
        H.equal(owner.update, fixture.mod.update)
        fixture.mod.update(0.016)
        H.equal(second_ticks, 1)
        H.equal(occurrences(table.concat(fixture.events, ","), "hats"), 0)
    end)

    H.test("cos update scheduler bounds and reuses the state-pull request", function()
        local fixture = build()
        fixture.mod._la_state_pull_pending = { attempts = 0, next_at = 0 }
        fixture.mod.update(0.016)
        H.equal(#fixture.sends, 1)
        H.equal(fixture.sends[1][1], "cos_la_state_req")
        H.equal(fixture.sends[1][2], "host")
        H.equal(fixture.sends[1][3], 2)
        fixture.mod.update(0.016)
        H.equal(#fixture.sends, 1, "five-second cadence must suppress an early retry")
        fixture.set_now(15)
        fixture.mod.update(0.016)
        H.equal(#fixture.sends, 2)
        fixture.mod._la_state_pull_pending = { attempts = 8, next_at = 20 }
        fixture.set_now(20)
        fixture.mod.update(0.016)
        H.equal(fixture.mod._la_state_pull_pending, nil)
        H.equal(fixture.mod._la_state_pull_exhausted, true)
        H.equal(#fixture.sends, 2, "exhaustion must not send a ninth request")
    end)

    H.test("cos update scheduler drains the current shared LA queue by accessor", function()
        local fixture = build({
            pending = {
                { "peer", "terminal", nil, nil, nil, 20 },
                { "peer", "retry", nil, nil, nil, 20 },
            },
            reconcile = function(_, slot)
                if slot == "terminal" then return false, "deus-yield" end
                if slot == "applied" then return true end
                return false, "not-ready"
            end,
        })
        fixture.mod.update(0.016)
        H.equal(#fixture.get_pending(), 1)
        H.equal(fixture.get_pending()[1][2], "retry")
        local rebound = { { "peer", "applied", nil, nil, nil, 20 } }
        fixture.set_pending(rebound)
        fixture.mod.update(0.016)
        H.equal(#fixture.get_pending(), 0)
        H.equal(#rebound, 1, "drain must rebind rather than mutate the shared input")
    end)
end
