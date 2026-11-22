-- tools/harness/driver/lib/actor.lua: actor helpers (WP-H-06 group "actor input"): T.first_bot_unit, T.as_bot, T.pickup.
--
-- A helper group (tools/harness/API.md). Bots are the actor; no OS input. Every call that hands a unit to the engine
-- runs in the main update (T.main). A pickup the case spawned and left lying is removed at cleanup.

local BOT_ACTIONS = {
	"tap_attack", "hold_attack", "defend", "fire", "fire_hold", "charge_shot", "activate_ability", "melee_push", "dodge",
	"interact", "weapon_reload",
}

return function (T, ctx)
	local case = ctx.case

	-- Waits up to `seconds` for fn() to be truthy without counting a FAIL (the caller decides with T.require).
	local function poll(fn, seconds)
		local deadline = ctx.now() + seconds

		while true do
			local ok, value = pcall(fn)

			if ok and value then
				return value
			end

			if ctx.now() >= deadline then
				return nil
			end

			T.frames(1)
		end
	end

	-- The first alive bot unit (T.bots order), waiting up to `timeout` seconds (30) for one; INCONCLUSIVE without one
	-- (the keep has no bots: use a mission arena).
	function T.first_bot_unit(timeout)
		local unit = poll(function ()
			return T.bots()[1]
		end, timeout or 30)

		T.require(unit ~= nil, "a bot is alive")

		return unit
	end

	-- Drives a bot's input through its PlayerBotInput extension
	-- (Vermintide-2-Source-Code/scripts/unit_extensions/human/player_bot_unit/player_bot_input.lua:262-319). Each
	-- method sets the flag the extension turns into input in its next update (_update_actions, :85), so one call is
	-- one update of input; bot.<action>(frames) repeats it for `frames` updates (hold_attack, fire_hold and defend need
	-- that to be held). bot.wield(slot_name) asks for a slot ("slot_melee", "slot_ranged"). The bot's own behaviour
	-- keeps running and may give other input in the same updates; a case asserts the effect it needs.
	-- Actions: tap_attack, hold_attack, defend, fire, fire_hold, charge_shot, activate_ability, melee_push, dodge,
	-- interact, weapon_reload. bot.input is the extension.
	function T.as_bot(unit)
		local input = T.ext(unit, "input_system")

		T.require(type(input.tap_attack) == "function" and type(input.wield) == "function", "unit has bot input (PlayerBotInput)")

		local bot = { input = input, unit = unit }

		for _, name in ipairs(BOT_ACTIONS) do
			bot[name] = function (frames)
				local method = input[name]

				T.require(type(method) == "function", "bot input has " .. name)

				for _ = 1, frames or 1 do
					T.main(method, input)
				end

				ctx.out("BOT INPUT id=%s action=%s frames=%d", case.id, name, frames or 1)
			end
		end

		function bot.wield(slot_name)
			T.main(input.wield, input, slot_name)
			ctx.out("BOT INPUT id=%s action=wield slot=%s", case.id, tostring(slot_name))
		end

		return bot
	end

	-- Spawns pickup `name` (an AllPickups key, scripts/settings/equipment/pickups.lua:939-952, e.g. "healing_draught")
	-- next to the local hero with PickupSystem.buff_spawn_pickup (scripts/entity_system/systems/pickups/pickup_system.lua:1181-1206),
	-- the call the game uses to drop a pickup at a player (buff_templates.lua:1695): it rays down to the floor from
	-- 1 m above the hero plus `offset` ({ x, y, z }, default 1 m along x). Host only. Returns the unit; INCONCLUSIVE when
	-- nothing spawned (e.g. the pickup's package is not loaded in this level). A pickup still lying at cleanup is
	-- removed with PickupSystem._delete_pickup (:1451-1457).
	function T.pickup(name, offset)
		T.require(AllPickups[name] ~= nil, "pickup " .. tostring(name) .. " exists")

		offset = offset or { 1, 0, 0 }

		local unit, why = T.main(function ()
			local hero = ctx.local_hero()
			local entity = Managers.state.entity

			if not hero then
				return nil, "local hero alive"
			elseif not entity then
				return nil, "entity manager exists"
			end

			local system = entity:system("pickup_system")
			local position = Unit.local_position(hero, 0) + Vector3(offset[1] or offset.x or 0, offset[2] or offset.y or 0, (offset[3] or offset.z or 0) + 1)

			return system:buff_spawn_pickup(name, position, true), "pickup " .. tostring(name) .. " spawned"
		end)

		T.require(unit ~= nil, why)

		case.cleanups[#case.cleanups + 1] = function ()
			Managers.state.entity:system("pickup_system"):_delete_pickup(unit)
		end

		ctx.out("PICKUP id=%s name=%s", case.id, tostring(name))

		return unit
	end
end
