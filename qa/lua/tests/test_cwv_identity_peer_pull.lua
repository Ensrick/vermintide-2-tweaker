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
    local Cleanup = assert(loadfile(repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_identity_peer_cleanup.lua"))()
    local Resolver = assert(loadfile(repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_peer_resolver.lua"))()

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

	H.test("CWV #914 pre-ready reply does not consume the request generation", function()
		local accepted, sent = 0, 0
		local lifecycle = {
			accept_request = function()
				accepted = accepted + 1
				return true
			end,
			track_delivery = function() return 1 end,
		}
		local owner = Pull.bind(lifecycle, function()
			sent = sent + 1
			return 1
		end, POLICY, function() end)
		local local_human = make_unit({ local_player = true }, false)
		with_globals(engine_stubs(nil), function()
			H.equal(owner.accept("peer-req", 1, { generation = 7 }), false)
		end)
		H.equal(accepted, 0, "pre-ready request generation must remain unconsumed")
		H.equal(sent, 0)
		with_globals(engine_stubs(local_human), function()
			H.equal(owner.accept("peer-req", 1, { generation = 7 }), true)
		end)
		H.equal(accepted, 1, "same generation must be accepted after readiness")
		H.equal(sent, 1)
	end)

	H.test("CWV #914 client human removal clears only the visible remote peer", function()
		local hook, cleared, vanilla_calls = nil, {}, 0
		local mod = {
			hook = function(_, _, method, callback)
				H.equal(method, "remove_player")
				hook = callback
			end,
		}
		local lifecycle = {
			clear_peer = function(_, peer_id) cleared[#cleared + 1] = peer_id end,
		}
		local player_class = {}
		H.equal(Cleanup.install(mod, lifecycle, player_class, Resolver,
			function() end, function() return "local-peer" end), true)
		H.truthy(hook)
		local human = {
			peer_id = "remote-peer",
			is_player_controlled = function() return true end,
		}
		local bot = {
			peer_id = "remote-peer",
			is_player_controlled = function() return false end,
		}
		-- Model the REAL PlayerManager surface: players_at_peer exists and
		-- returns the still-present human alongside the bot. Without the
		-- local_player_id gate, a bot removal (lpid 2) would resolve to the
		-- human through this fallback and wrongly clear the host's identity.
		local manager = {
			is_server = false,
			player_from_peer_id = function(_, peer_id, local_id)
				if peer_id == "remote-peer" and local_id == 1 then return human end
				if local_id == 2 then return bot end
			end,
			players_at_peer = function(_, peer_id)
				if peer_id == "remote-peer" then return { human, bot } end
			end,
		}
		local function vanilla()
			vanilla_calls = vanilla_calls + 1
			return "r1", "r2", "r3", "r4"
		end
		local r1, r2, r3, r4 = hook(vanilla, manager, "remote-peer", 1)
		H.equal(table.concat({ r1, r2, r3, r4 }, "|"), "r1|r2|r3|r4")
		H.equal(cleared[1], "remote-peer")
		hook(vanilla, manager, "remote-peer", 2)
		hook(vanilla, manager, "local-peer", 1)
		manager.is_server = true
		hook(vanilla, manager, "remote-peer", 1)
		H.equal(#cleared, 1, "bot/local/server removals must not clear client identity")
		H.equal(vanilla_calls, 4, "cleanup must never suppress vanilla removal")
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
		local husk_source = read(repo_root
			.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_husk_path.lua")
		H.truthy(husk_source:find("player = self and self._player", 1, true),
			"husk wield context must carry SimpleHuskInventoryExtension._player")
    end)
end
