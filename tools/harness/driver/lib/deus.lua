-- tools/harness/driver/lib/deus.lua: Chaos Wastes helpers (WP-H-05): T.deus_run_controller, T.grant_boon,
-- T.has_boon, T.deus_coins, T.set_deus_coins.
--
-- A helper group (tools/harness/API.md). They need a run: a case in a "deus:<level_key>" arena (the hub alone has none).
-- Engine paths are under Vermintide-2-Source-Code/scripts/managers/game_mode/mechanisms/ unless stated.

local REAL_PLAYER_LOCAL_ID = 1 -- deus_run_controller.lua:29

return function (T, ctx)
	local case = ctx.case

	-- The current run's DeusRunController (DeusMechanism.get_deus_run_controller, deus_mechanism.lua:523-525), or
	-- INCONCLUSIVE when no run is active.
	function T.deus_run_controller()
		local controller = T.main(function ()
			local mechanism = Managers.mechanism and Managers.mechanism:game_mechanism()

			return mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()
		end)

		T.require(controller ~= nil, "a Chaos Wastes run is active (deus run controller)")

		return controller
	end

	-- Grants one boon to the local player the way the game's own test hook does (DeusPowerUpUtils.
	-- generate_specific_power_up and DeusRunController.add_power_ups, scripts/game_state/state_ingame_testify.lua:
	-- 185-197; add_power_ups at deus_run_controller.lua:1126). name: a DeusPowerUpTemplates key; rarity: one of
	-- DeusPowerUpRarities (scripts/settings/dlcs/morris/deus_power_up_settings.lua:7032-7037), default "rare". The boon
	-- stays for the rest of the run (no removal call exists). Returns the power up.
	function T.grant_boon(name, rarity)
		rarity = rarity or "rare"

		T.require(rawget(_G, "DeusPowerUpTemplates") ~= nil and DeusPowerUpTemplates[name] ~= nil, "boon " .. tostring(name) .. " exists")

		local controller = T.deus_run_controller()
		local power_up = T.main(function ()
			local granted = DeusPowerUpUtils.generate_specific_power_up(name, rarity)

			controller:add_power_ups({ granted }, Managers.player:local_player():local_player_id(), false)

			return granted
		end)

		ctx.out("BOON GRANT id=%s name=%s rarity=%s", case.id, tostring(name), rarity)

		return power_up
	end

	-- Whether the local player holds that boon in this run (DeusRunController.has_power_up_by_name,
	-- deus_run_controller.lua:1523-1535).
	function T.has_boon(name, rarity)
		local controller = T.deus_run_controller()

		return T.main(function ()
			return controller:has_power_up_by_name(controller:get_own_peer_id(), name, rarity or "rare")
		end) == true
	end

	-- The local player's coins in this run (DeusRunController.get_player_soft_currency, deus_run_controller.lua:925-927).
	function T.deus_coins()
		local controller = T.deus_run_controller()

		return T.main(function ()
			return controller:get_player_soft_currency(controller:get_own_peer_id())
		end)
	end

	-- Sets the local player's coins in this run through the controller's run state (DeusRunState.
	-- set_player_soft_currency, deus_run_state.lua:575-579). The value before the case's first change is put back at
	-- cleanup. Returns the value before this call.
	function T.set_deus_coins(coins)
		local controller = T.deus_run_controller()
		local before = T.deus_coins()

		if not case.deus_coins_saved then
			case.deus_coins_saved = true
			case.cleanups[#case.cleanups + 1] = function ()
				controller._run_state:set_player_soft_currency(controller:get_own_peer_id(), REAL_PLAYER_LOCAL_ID, before)
				ctx.out("DEUS COINS RESTORE id=%s value=%s", case.id, tostring(before))
			end
		end

		T.main(function ()
			controller._run_state:set_player_soft_currency(controller:get_own_peer_id(), REAL_PLAYER_LOCAL_ID, coins)
		end)

		ctx.out("DEUS COINS id=%s value=%s was=%s", case.id, tostring(coins), tostring(before))

		return before
	end
end
