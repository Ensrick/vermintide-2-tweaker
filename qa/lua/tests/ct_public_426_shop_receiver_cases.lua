-- Source-qualified pre-clone receiver cases for issue #426. Vanilla's
-- DeusRunController receiver dereferences every covered field before its
-- ordinary purchase gate, so these cases drive the actual installed callback.

return function(H, with_fixture)
    local function receiver(is_server, server_peer_id)
        local run_state = {
            _is_server = is_server ~= false,
            _server_peer_id = server_peer_id or "host",
        }
        local controller = { _run_state = run_state }
        return controller, run_state
    end

    H.test("CT public #426 shop receiver authenticates before native clone", function()
        with_fixture({ safe = true }, function(f)
            local hook = f.hooks[
                "DeusRunController.rpc_deus_shop_power_up_bought"]
            local server = receiver()
            local native = {}
            local function call(controller, channel, name, client_id, discount)
                return hook(function(_, got_channel, rarity, got_name, got_id, got_discount)
                    -- Mirror the source receiver's pre-purchase clone boundary.
                    -- Any rejected case reaching this function would therefore
                    -- exercise the same unsafe registry dereference as vanilla.
                    local rows = rawget(_G, "DeusPowerUps")[rarity]
                    local source = rows[got_name]
                    local clone = {}
                    for key, value in pairs(source) do clone[key] = value end
                    clone.client_id = got_id
                    native[#native + 1] = {
                        got_channel, rarity, got_name, clone.client_id, got_discount,
                    }
                    return "native-a", "native-b"
                end, controller, channel, "exotic", name, client_id, discount)
            end

            local a, b = call(server, 9, "ct_meta_health", 17, 0)
            H.equal(a, "native-a")
            H.equal(b, "native-b")
            H.deep_equal(native[1], { 9, "exotic", "ct_meta_health", 17, 0 })

            local client = receiver(false)
            call(client, 9, "ct_meta_health", 17, 0)
            call(client, 9, "natural_bond", 17, 0)
            call(server, 404, "ct_meta_health", 17, 0)
            call(server, 404, "natural_bond", 17, 0)
            rawget(_G, "CHANNEL_TO_PEER_ID")[8] = "host"
            call(server, 8, "ct_meta_health", 17, 0)
            call(server, 8, "natural_bond", 17, 0)
            H.equal(#native, 1, "unauthenticated shop packet reached native")

            -- A known peer without CT retains ordinary vanilla purchases while
            -- its CT request remains inert.
            rawget(_G, "CHANNEL_TO_PEER_ID")[10] = "other"
            call(server, 10, "ct_meta_health", 17, 0)
            call(server, 10, "natural_bond", 18, 0)
            H.equal(#native, 2)
            H.equal(native[2][3], "natural_bond")
        end)
    end)

    H.test("CT public #426 shop receiver rejects pending peers before registry read", function()
        with_fixture({ safe = true }, function(f)
            rawget(_G, "CHANNEL_TO_PEER_ID")[10] = "joining"
            f.hooks["NetworkServer.peer_connected"](
                function() end, { my_peer_id = "host" }, "joining")

            -- If the decision consulted the engine registry before sender
            -- admission, this deliberately absent table would change the
            -- reason or throw. The pending CT packet must simply disappear.
            rawset(_G, "DeusPowerUps", nil)
            local native = 0
            local ok = pcall(
                f.hooks["DeusRunController.rpc_deus_shop_power_up_bought"],
                function(_, _, rarity, name)
                    native = native + 1
                    return rawget(_G, "DeusPowerUps")[rarity][name]
                end, receiver(), 10, "exotic", "ct_meta_health", 17, 0)
            H.equal(ok, true)
            H.equal(native, 0)

            -- A mapped but catalog-foreign peer has the same pre-registry
            -- guarantee even when it was never part of admission bookkeeping.
            rawget(_G, "CHANNEL_TO_PEER_ID")[11] = "foreign"
            ok = pcall(
                f.hooks["DeusRunController.rpc_deus_shop_power_up_bought"],
                function(_, _, rarity, name)
                    native = native + 1
                    return rawget(_G, "DeusPowerUps")[rarity][name]
                end, receiver(), 11, "exotic", "ct_meta_health", 17, 0)
            H.equal(ok, true)
            H.equal(native, 0)
        end)
    end)

    H.test("CT public #426 shop receiver contains malformed packet fields", function()
        with_fixture({ safe = true }, function(f)
            local hook = f.hooks[
                "DeusRunController.rpc_deus_shop_power_up_bought"]
            local server = receiver()
            local native = 0
            local bad = {
                { "exotic", "ct_meta_health", nil, 0 },
                { "exotic", "ct_meta_health", "17", 0 },
                { "exotic", "ct_meta_health", 17.5, 0 },
                { "exotic", "ct_meta_health", 2147483648, 0 },
                { "exotic", "ct_meta_health", 17, nil },
                { "exotic", "ct_meta_health", 17, "0" },
                { "exotic", "ct_meta_health", 17, -1 },
                { "exotic", "ct_meta_health", 17, 0.5 },
                { "exotic", "ct_meta_health", 17, 10001 },
                { "exotic", "ct_meta_health", 17, math.huge },
            }
            for i = 1, #bad do
                local row = bad[i]
                local ok = pcall(hook, function() native = native + 1 end,
                    server, 9, row[1], row[2], row[3], row[4])
                H.equal(ok, true, "malformed shop case escaped: " .. i)
            end
            local hostile = setmetatable({}, {
                __tostring = function() error("hostile tostring") end,
            })
            H.equal(pcall(hook, function() native = native + 1 end,
                server, 9, hostile, hostile, hostile, hostile), true)
            H.equal(native, 0)
        end)
    end)

    H.test("CT public #426 shop receiver bypasses strict engine metatables", function()
        with_fixture({ safe = true }, function(f)
            local powers = rawget(_G, "DeusPowerUps")
            local exotic = rawget(powers, "exotic")
            local row = rawget(exotic, "ct_meta_health")
            local map = rawget(_G, "CHANNEL_TO_PEER_ID")
            local controller, run_state = receiver()
            local strict = { powers, exotic, row, map, controller, run_state }
            for i = 1, #strict do
                setmetatable(strict[i], {
                    __index = function() error("strict shop index") end,
                    __newindex = function() error("strict shop write") end,
                })
            end
            local native = 0
            local ok = pcall(f.hooks[
                "DeusRunController.rpc_deus_shop_power_up_bought"],
                function() native = native + 1 end,
                controller, 9, "exotic", "ct_meta_health", 17, 0)
            H.equal(ok, true)
            H.equal(native, 1)
        end)
    end)

    H.test("CT public #426 retained shop hook stays safe after owner rollback", function()
        with_fixture({ safe = true, fail_install = true,
                expect_install_failure = true }, function(f)
            local hook = f.hooks[
                "DeusRunController.rpc_deus_shop_power_up_bought"]
            local native = {}
            local function call(name)
                return hook(function(_, _, rarity, got_name)
                    native[#native + 1] = got_name
                    return rawget(_G, "DeusPowerUps")[rarity][got_name]
                end, receiver(), 9, "exotic", name, 17, 0)
            end
            H.equal(pcall(call, "ct_meta_health"), true)
            H.equal(#native, 0,
                "rolled-back owner leaked a CT shop request")
            H.equal(pcall(call, "natural_bond"), true)
            H.deep_equal(native, { "natural_bond" })
        end)
    end)

    H.test("CT public #426 named receiver check exercises the shop floor", function()
        with_fixture({ safe = true }, function(f)
            local check = f.calls.checks.ct_426_public_receiver_floors
            H.equal(check(), nil)
            rawget(rawget(_G, "DeusPowerUps"), "exotic").ct_meta_health = nil
            H.equal(check(), "pre-clone shop receiver floor failed")
        end)
    end)
end
