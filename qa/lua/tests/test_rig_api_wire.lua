-- test_rig_api_wire.lua: offline tests of the rig's helper group lib/wire.lua (T.transmit_spy), WP-H-06 group "wire".
--
-- Boots the real bootstrap and driver with the real group in plan.libs inside the simulated game of
-- _rig_driver_env.lua. A stub NetworkTransmit class stands in for scripts/network/network_transmit.lua: its senders
-- record what went through. Game-side sends come from the stub world's per-frame hook, the way the engine calls the
-- senders from its own update. This proves the spy's recording, pass-through and restore only.
return function(H, repo_root)
    local E = assert(loadfile(repo_root .. "/qa/lua/tests/_rig_driver_env.lua"))()(H, repo_root)
    local inventory_world = assert(loadfile(repo_root .. "/qa/lua/tests/_rig_inventory_world.lua"))()
    local tag, first = E.tag, E.first

    local SENDERS = { "send_rpc", "send_rpc_server", "send_rpc_clients", "send_rpc_clients_except", "send_rpc_all" }

    local function new_transmit(sent)
        local class = {}
        class.__index = class
        for _, sender in ipairs(SENDERS) do
            class[sender] = function(self, rpc_name, ...)
                sent[#sent + 1] = sender .. " " .. rpc_name .. " " .. table.concat({ ... }, " ", 1, select("#", ...) > 0 and 1 or 0)
            end
        end
        return setmetatable({}, class), class
    end

    local function run(cases, setup, libs)
        local plan = E.make_plan(cases, {
            libs = libs or { E.lib_entry("wire") },
            shared = { { id = "official_mirror", hex = E.hex(E.read(repo_root .. "/qa/runtime/_shared/official_mirror.lua")) } },
        })
        local object, env, lines = E.boot(plan)
        local w = { sent = {}, queue = {} }
        w.transmit, w.class = new_transmit(w.sent)
        env.Managers.state.network = { network_transmit = w.transmit }
        env.newproxy = newproxy
        if setup then
            setup(env, w)
        end
        -- game-side sends queued by a case run in the next frame, as the engine's own update would send them
        local frame = function()
            local queue = w.queue
            w.queue = {}
            for _, send in ipairs(queue) do
                send(w.transmit)
            end
            if w.frame then
                w.frame()
            end
        end
        env.vt2_test_send = function(fn)
            w.queue[#w.queue + 1] = fn
        end
        H.truthy(E.run_to_end(object, env, nil, frame), "run completed")
        return lines, w
    end

    H.test("rig T.transmit_spy: records one RPC across senders, passes every call through, stop restores", function()
        local lines, w = run({ { id = "spy", src = [[
return { run = function(T)
    local spy = T.transmit_spy("rpc_a")
    vt2_test_send(function(t)
        t:send_rpc_clients("rpc_a", 1, 2, 3)
        t:send_rpc_all("rpc_b", 9)
        t:send_rpc("rpc_a", "peer", newproxy())
    end)
    T.frames(2)
    T.expect_eq(spy.count("rpc_a"), 2, "two rpc_a calls")
    T.expect_eq(spy.count(), 2, "only rpc_a recorded")
    T.expect_eq(spy.calls[1].via, "send_rpc_clients", "sender recorded")
    T.expect_eq(spy.calls[1].args[3], 3, "arguments after rpc_name kept")
    T.expect_eq(spy.calls[2].args[1], "peer", "send_rpc keeps the peer id first")
    T.expect_eq(type(spy.calls[2].args[2]), "string", "an engine value is kept as text")
    spy.stop()
    vt2_test_send(function(t) t:send_rpc_clients("rpc_a", 4) end)
    T.frames(2)
    T.expect_eq(spy.count("rpc_a"), 2, "nothing recorded after stop")
end }
]] } })
        H.truthy(first(lines, tag .. "CASE END id=spy verdict=PASS asserts=7 failed=0"), "spy passes: " .. tostring(first(lines, tag .. "CASE END id=spy")))
        H.equal(#w.sent, 4, "every call went through, recorded or not")
        H.equal(w.sent[1], "send_rpc_clients rpc_a 1", "first call reached the class sender")
        for _, sender in ipairs(SENDERS) do
            H.equal(rawget(w.transmit, sender), nil, sender .. " back to the class method")
        end
        H.truthy(first(lines, tag .. "SPY START id=spy rpc=rpc_a senders=5"), "SPY START line")
        H.truthy(first(lines, tag .. "SPY STOP id=spy calls=2 senders=5 replaced_after_start=0"), "SPY STOP line")
    end)

    H.test("rig T.transmit_spy: a list or every RPC; cleanup stops it, also after an ERROR; a later wrapper stays", function()
        local lines, w = run({
            { id = "list", src = [[
return { run = function(T)
    local spy = T.transmit_spy({ "rpc_a", "rpc_b" })
    vt2_test_send(function(t) t:send_rpc_all("rpc_a") t:send_rpc_all("rpc_b") t:send_rpc_all("rpc_c") end)
    T.frames(2)
    T.expect_eq(spy.count(), 2, "rpc_a and rpc_b recorded")
end }
]] },
            { id = "all", src = [[
return { run = function(T)
    local spy = T.transmit_spy()
    vt2_test_send(function(t) t:send_rpc_server("rpc_x") t:send_rpc_clients_except("rpc_y", "peer") end)
    T.frames(2)
    T.expect_eq(spy.count(), 2, "every RPC recorded")
    error("planted error with the spy running")
end }
]] },
            { id = "on-top", src = [[
return { run = function(T)
    T.transmit_spy("rpc_a")
    local t = Managers.state.network.network_transmit
    local spied = t.send_rpc_all
    rawset(t, "send_rpc_all", function(self, ...) return spied(self, ...) end)
end }
]] },
        })
        H.truthy(first(lines, tag .. "CASE END id=list verdict=PASS"), "list passes")
        H.truthy(first(lines, tag .. "SPY STOP id=list calls=2 senders=5 replaced_after_start=0"), "cleanup stopped the list spy")
        H.truthy(first(lines, tag .. "CASE END id=all verdict=ERROR .*planted error with the spy running"), "ERROR reported")
        H.truthy(first(lines, tag .. "SPY STOP id=all calls=2 senders=5"), "cleanup stopped the spy after the ERROR")
        H.truthy(first(lines, tag .. "SPY STOP id=on%-top calls=0 senders=5 replaced_after_start=1"), "a wrapper set after the spy is left in place")
        H.truthy(rawget(w.transmit, "send_rpc_all") ~= nil, "the later wrapper is still there")
        H.equal(rawget(w.transmit, "send_rpc_clients"), nil, "the spy's own wrappers are gone")
    end)

    H.test("rig T.transmit_spy: no network transmit is INCONCLUSIVE", function()
        local lines = run({ { id = "none", src = "return { run = function(T) T.transmit_spy('rpc_a') end }" } }, function(env)
            env.Managers.state.network = nil
        end)
        H.truthy(first(lines, tag .. "CASE END id=none verdict=INCONCLUSIVE .*network transmit exists"), "no transmit")
    end)

    -- The selftest's wire case against the inventory stub world, whose equip sends rpc_add_equipment the way
    -- SimpleInventoryExtension._spawn_resynced_loadout does (simple_inventory_extension.lua:1443-1456).
    H.test("rig api-selftest case api_wire: passes in the simulated game", function()
        local lines = run({ { id = "api-wire", src = E.read(repo_root .. "/qa/runtime/_rig/api_wire.lua") } }, function(env, w)
            local world = inventory_world(env)
            env.Managers.state.network.network_transmit = w.transmit
            local ids = { es_1h_sword = 11, es_2h_sword = 12 }
            env.NetworkLookup = { item_names = { [11] = "es_1h_sword", [12] = "es_2h_sword" } }
            world.on_equip = function(_, slot_name, backend_id)
                local key = world.mirror._inventory_items[backend_id].key
                w.transmit:send_rpc_clients("rpc_add_equipment", 7, slot_name == "slot_melee" and 1 or 2, ids[key], 0)
            end
            w.frame = nil
        end, { E.lib_entry("wire"), E.lib_entry("inventory") })
        H.truthy(first(lines, tag .. "CASE END id=api%-wire verdict=PASS"), "api-wire passes: " .. tostring(first(lines, tag .. "CASE END id=api%-wire")))
    end)
end
