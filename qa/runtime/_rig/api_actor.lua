-- API self-test, actor part (WP-H-06 group "actor input"), in a mission (the keep has no bots): T.first_bot_unit
-- finds a bot, T.as_bot asks it to wield its ranged slot and the bot does, T.pickup drops a healing draught next to
-- the hero, and T.teleport moves the hero 1 m using a { x, y, z } position. Mission start, no enemies spawned.
return {
	issue = 0,
	arena = "mission:military",
	class = "R",
	timeout = 120,
	run = function(T)
		local hero = T.local_hero(60)

		T.require(hero ~= nil, "local hero alive")
		T.invincible(true)

		T.step("T.first_bot_unit and T.as_bot")
		local bot_unit = T.first_bot_unit(60)
		local bot = T.as_bot(bot_unit)
		local inventory = T.ext(bot_unit, "inventory_system")
		-- SimpleInventoryExtension.get_wielded_slot_name (simple_inventory_extension.lua:1336-1341)
		local before = inventory:get_wielded_slot_name()

		T.note("bot_wielded_before", tostring(before))

		local wanted = before == "slot_ranged" and "slot_melee" or "slot_ranged"
		local switched

		for _ = 1, 90 do
			bot.wield(wanted)

			if inventory:get_wielded_slot_name() == wanted then
				switched = true

				break
			end
		end

		T.note("bot_wielded_after", tostring(inventory:get_wielded_slot_name()))
		T.expect(switched, "the bot wielded " .. wanted .. " when asked")
		bot.defend(10)

		T.step("T.pickup a healing draught next to the hero")
		local pickup = T.pickup("healing_draught", { 1, 0, 0 })

		T.expect(pickup ~= nil, "T.pickup returns the unit")

		T.step("T.teleport the hero 1 m with a { x, y, z } position")
		local x, y, z = T.main(function()
			local p = Unit.local_position(hero, 0)

			return p.x, p.y, p.z
		end)

		T.teleport(hero, { x + 1, y, z })
		T.frames(5)

		local nx, ny = T.main(function()
			local p = Unit.local_position(hero, 0)

			return p.x, p.y
		end)

		T.expect_near(nx - x, 1, 0.3, "the hero moved 1 m along x")
		T.expect_near(ny - y, 0, 0.3, "and not along y")
	end,
}
