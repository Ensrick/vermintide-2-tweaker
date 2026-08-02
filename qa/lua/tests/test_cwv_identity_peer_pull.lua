-- Offline lock for the #914 peer-pull trigger: the request must fire at
-- `game_object_initialized` time, when vanilla has NOT yet assigned
-- `player.player_unit` (spawn at bulldozer_player.lua:365 ->
-- unit_spawner.lua:349 sync_unit_extensions fires GO-init -> ownership only
-- at bulldozer_player.lua:393). Locality therefore derives from the unit's
-- own inventory extension (simple_inventory_extension.lua:31-32), never from
-- `Managers.player:local_player(1).player_unit`.

local function read(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

return function(H, repo_root)
    local module_path = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_identity_peer_pull.lua"
    local gate_path = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_javelin_gate.lua"
    local Pull = assert(loadfile(module_path))()

    local POLICY = { MAX_REQUEST_GENERATION = 8, MAX_RETRY_ATTEMPTS = 5 }

    local function with_globals(env, body)
        local previous = {}
        for key, value in pairs(env) do
            previous[key] = rawget(_G, key)
            rawset(_G, key, value)
        end
        local ok, err = pcall(body)
        for key in pairs(env) do
            rawset(_G, key, previous[key])
        end
        if not ok then error(err, 0) end
    end

    local function make_unit(player, is_bot)
        local unit = { live = true }
        unit.inventory = player and {
            player = player,
            is_bot = is_bot or false,
            _equipment = { slots = { slot_melee = { base = "vanilla_base" } } },
        } or nil
        return unit
    end

    local function engine_stubs(local_player_unit)
        return {
            Unit = { alive = function(u) return type(u) == "table" and u.live == true end },
            ScriptUnit = {
                has_extension = function(u, name)
                    if name == "inventory_system" then return u and u.inventory end
                end,
                extension = function(u, name)
                    if name == "inventory_system" then return u and u.inventory end
                    error("no extension")
                end,
            },
            Managers = {
                player = {
                    local_player = function(_, _)
                        -- The #914 timing: at GO-init the local player object
                        -- exists but its player_unit is NOT yet assigned.
                        return { player_unit = local_player_unit }
                    end,
                },
            },
        }
    end

    H.test("CWV #914 request fires for the local human unit BEFORE ownership assignment", function()
        local begun = {}
        local lifecycle = {
            begin_request = function(_, generation, context)
                begun[#begun + 1] = { generation = generation, context = context }
                return true
            end,
        }
        local owner = Pull.bind(lifecycle, function() return 0 end, POLICY, function() end)
        local local_human = make_unit({ local_player = true }, false)
        with_globals(engine_stubs(nil), function()
            H.equal(owner.request(local_human, "game_object_initialized_ready"), true,
                "peer pull must trigger for the local player's own new unit "
                .. "even while local_player(1).player_unit is still nil")
        end)
        H.equal(#begun, 1)
        H.equal(begun[1].generation, 1)
        H.equal(begun[1].context, "game_object_initialized_ready")
    end)

    H.test("CWV #914 request refuses bots, husks, and dead or foreign units", function()
        local begun = 0
        local lifecycle = { begin_request = function() begun = begun + 1; return true end }
        local owner = Pull.bind(lifecycle, function() return 0 end, POLICY, function() end)
        with_globals(engine_stubs(nil), function()
            H.equal(owner.request(make_unit({ local_player = true, bot_player = true }, true), "t"),
                false, "bot unit must not trigger the pull")
            H.equal(owner.request(make_unit({ remote = true }, false), "t"),
                false, "remote-owned unit must not trigger the pull")
            H.equal(owner.request(make_unit(nil), "t"),
                false, "unit without an inventory extension must not trigger the pull")
            H.equal(owner.request(nil, "t"), false, "nil unit must not trigger the pull")
            local dead = make_unit({ local_player = true }, false)
            dead.live = false
            H.equal(owner.request(dead, "t"), false, "dead unit must not trigger the pull")
        end)
        H.equal(begun, 0)
    end)

    H.test("CWV #914 request keeps the bounded wire generation cycle intact", function()
        local generations = {}
        local lifecycle = {
            begin_request = function(_, generation)
                generations[#generations + 1] = generation
                return true
            end,
        }
        local owner = Pull.bind(lifecycle, function() return 0 end, POLICY, function() end)
        local local_human = make_unit({ local_player = true }, false)
        with_globals(engine_stubs(nil), function()
            for _ = 1, POLICY.MAX_REQUEST_GENERATION + 2 do
                H.equal(owner.request(local_human, "cycle"), true)
            end
        end)
        H.equal(#generations, POLICY.MAX_REQUEST_GENERATION + 2)
        for index, generation in ipairs(generations) do
            H.equal(generation, (index - 1) % POLICY.MAX_REQUEST_GENERATION + 1,
                "request generations must stay wire-bounded")
        end
    end)

    H.test("CWV #914 reply path still reads the NOW-assigned local player slots", function()
        local tracked, sent
        local lifecycle = {
            accept_request = function() return true end,
            track_delivery = function(_, peer_id, slots, context)
                tracked = { peer_id = peer_id, slots = slots, context = context }
                return 1
            end,
        }
        local owner = Pull.bind(lifecycle, function(slots, context, force, recipient)
            sent = { slots = slots, context = context, force = force, recipient = recipient }
            return 1
        end, POLICY, function() end)
        local local_human = make_unit({ local_player = true }, false)
        with_globals(engine_stubs(local_human), function()
            H.equal(owner.accept("peer-req", 1, { generation = 1 }), true)
        end)
        H.truthy(tracked and tracked.slots and tracked.slots.slot_melee,
            "reply must track the local equipment slots")
        H.equal(tracked.context, "peer_ready_reply")
        H.equal(sent.recipient, "peer-req")
        H.equal(sent.force, true)
    end)

    H.test("CWV #914 source locks: unit-derived locality and peer teardown wiring", function()
        local pull_source = read(module_path)
        H.truthy(pull_source:find("unit_is_local_human(unit)", 1, true),
            "request must derive locality from the unit itself")
        H.equal(pull_source:find("local_unit ~= unit", 1, true), nil,
            "the dead player_unit comparison guard must not return (#914)")

        -- clear_peer must be wired to the real peer-teardown seam: the existing
        -- consolidated (GameNetworkManager, remove_peer) hook in the javelin
        -- gate (game_network_manager.lua:814, from peer_states.lua:574).
        local gate_source = read(gate_path)
        local hook_at = gate_source:find('"GameNetworkManager", "remove_peer"', 1, true)
        H.truthy(hook_at, "peer-teardown hook missing from the javelin gate")
        H.truthy(gate_source:find("lifecycle.clear_peer", 1, true)
                and gate_source:find("_appearance_lifecycle", 1, true),
            "appearance lifecycle clear_peer is not wired to peer teardown (#914)")
    end)
end
