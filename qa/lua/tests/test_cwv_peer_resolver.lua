return function(H, repo_root)
	local resolver = dofile(repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_peer_resolver.lua")

	H.test("CWV peer resolver preserves protected-call return values", function()
		local human = {
			peer_id = "peer-a",
			_local_player_id = 1,
			is_player_controlled = function() return true end,
		}
		local bot = {
			peer_id = "peer-a",
			_local_player_id = 2,
			is_player_controlled = function() return false end,
		}
		local manager = {
			owner = function(_, unit)
				if unit == "human-owner-unit" then return human end
				if unit == "bot-owner-unit" then return bot end
			end,
			local_player = function(_, id)
				if id == 1 then return human end
				if id == 2 then return bot end
			end,
			player_from_peer_id = function(_, peer, id)
				if peer ~= "peer-a" then return nil end
				if id == 1 then return human end
				if id == 2 then return bot end
			end,
			human_players = function() return { human } end,
		}
		H.equal(resolver.owner(manager, "human-owner-unit"), human)
		H.equal(resolver.local_player(manager, 1), human)
		local player, source = resolver.peer_player(manager, "peer-a", 1)
		H.equal(player, human)
		H.equal(source, "player_from_peer_id")
		H.equal(resolver.human_players(manager)[1], human)

		manager.player_from_peer_id = function() return nil end
		manager.players_at_peer = function() return { [2] = bot, [1] = human } end
		player, source = resolver.peer_player(manager, "peer-a", 1)
		H.equal(player, human)
		H.equal(source, "players_at_peer")

		manager.players_at_peer = function()
			return {
				{ peer_id = "peer-a", _local_player_id = 2 },
				{ peer_id = "peer-a", local_player_id = function() return 1 end },
			}
		end
		player, source = resolver.peer_player(manager, "peer-a", 1)
		H.equal(player.local_player_id(), 1)
		H.equal(source, "players_at_peer")
	end)

	H.test("CWV style and mode transport rows never alias a same-peer bot", function()
		local received = {}
		local human = {
			name = "human",
			peer_id = "shared-peer",
			_local_player_id = 1,
			is_player_controlled = function() return true end,
		}
		local bot = {
			name = "bot",
			peer_id = "shared-peer",
			_local_player_id = 2,
			is_player_controlled = function() return false end,
		}
		local manager = {
			owner = function(_, unit)
				return unit == "human-unit" and human or bot
			end,
			local_player = function(_, id)
				return id == 1 and human or bot
			end,
			player_from_peer_id = function(_, peer, id)
				if peer ~= "shared-peer" then return nil end
				return id == 1 and human or bot
			end,
		}
		local function deliver(row, player)
			if player then received[player.name] = row end
		end

		-- Owner lookups feed peer+slot style/mode stores. A bot owner sharing the
		-- human peer must not inherit that row.
		deliver("style-row", resolver.owner(manager, "human-unit"))
		local player, reason = resolver.owner(manager, "bot-unit")
		H.equal(player, nil)
		H.equal(reason, "owner not human")
		deliver("style-row", player)

		-- Direct local/from-peer fast paths are gated too, not merely the
		-- players_at_peer fallback.
		deliver("mode-row", resolver.local_player(manager, 1))
		player, reason = resolver.local_player(manager, 2)
		H.equal(player, nil)
		H.equal(reason, "local player not human")
		deliver("mode-row", player)
		deliver("mode-row", resolver.peer_player(manager, "shared-peer", 1))
		player, reason = resolver.peer_player(manager, "shared-peer", 2)
		H.equal(player, nil)
		H.equal(reason, "player unavailable")
		deliver("mode-row", player)

		H.equal(received.human, "mode-row")
		H.equal(received.bot, nil)

		-- Explicit bot classification wins even if a stale id claims slot 1.
		bot._local_player_id = 1
		H.equal(resolver.owner(manager, "bot-unit"), nil)
	end)

	H.test("CWV peer resolver preserves profile tuple and fails closed", function()
		local profile, career, source = resolver.profile_by_peer({
			profile_by_peer = function(_, peer, local_id)
				if peer == "peer-a" and local_id == 1 then return 5, 3 end
			end,
		}, "peer-a", 1)
		H.equal(profile, 5)
		H.equal(career, 3)
		H.equal(source, "profile_by_peer")
		local player, reason = resolver.peer_player({}, "missing", 1)
		H.equal(player, nil)
		H.equal(reason, "player unavailable")
	end)

	H.test("CWV #914 husk owner prefers validated extension player then falls back", function()
		local owner_unit = {}
		local other_unit = {}
		local hinted = {
			peer_id = "peer-hinted",
			player_unit = nil,
			is_player_controlled = function() return true end,
		}
		local fallback = {
			peer_id = "peer-fallback",
			player_unit = owner_unit,
			is_player_controlled = function() return true end,
		}
		local manager = { owner = function() return fallback end }
		local player, source = resolver.husk_owner(manager, owner_unit, hinted)
		H.equal(player, hinted)
		H.equal(source, "husk_extension_player")
		H.equal(resolver.player_peer_id(player), "peer-hinted")

		hinted.player_unit = other_unit
		player, source = resolver.husk_owner(manager, owner_unit, hinted)
		H.equal(player, fallback, "conflicting extension player must be rejected")
		H.equal(source, "owner")

		hinted.player_unit = nil
		hinted.is_player_controlled = function() return false end
		player, source = resolver.husk_owner(manager, owner_unit, hinted)
		H.equal(player, fallback, "bot hint must be rejected")
		H.equal(source, "owner")
	end)

	H.test("CWV peer identity paths contain no logical pcall multi-return collapse", function()
		for _, relative in ipairs({
			"character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua",
			"character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_crowbill_runtime.lua",
			"character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_old_musket_wire.lua",
		}) do
			local file = assert(io.open(repo_root .. "/" .. relative, "rb"))
			local source = file:read("*a")
			file:close()
			H.equal(source:find("pm and pcall", 1, true), nil, relative)
			H.equal(source:find("and pcall(psync.profile_by_peer", 1, true), nil, relative)
			H.truthy(source:find("peer_resolver", 1, true), relative)
		end
	end)
end
