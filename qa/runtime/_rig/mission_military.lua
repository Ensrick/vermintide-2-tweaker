-- Mission arena smoke: Righteous Stand loads as host with bots, the hero is alive, an enemy can be spawned and killed.
return {
	issue = 0,
	timeout = 90,
	run = function(T)
		T.step("mission loaded")
		T.expect_eq(T.level_key(), "military", "level is Righteous Stand")
		local hero = T.local_hero(30)
		T.expect(hero ~= nil, "local hero unit is alive")
		local bots = T.bots()
		T.note("bot_count", #bots)
		T.expect(#bots > 0, "at least one bot is alive")

		T.step("spawn one enemy next to the hero")
		local conflict = Managers.state.conflict
		T.require(conflict ~= nil, "conflict director exists")
		local breed = Breeds.skaven_slave
		T.require(breed ~= nil, "breed skaven_slave exists")
		local pos = POSITION_LOOKUP[hero] + Vector3(2, 0, 0)
		local count_before = conflict:count_units_by_breed("skaven_slave")
		conflict:spawn_queued_unit(breed, Vector3Box(pos), QuaternionBox(Quaternion.identity()), "spawn_one", nil, "horde_hidden", nil)
		local spawned = T.wait_until(function()
			return conflict:count_units_by_breed("skaven_slave") > count_before
		end, 15, "enemy count rises after spawn")
		T.expect(spawned ~= nil, "a skaven slave was spawned")

		T.step("buff round trip on the hero")
		local buff_ext = T.ext(hero, "buff_system")
		local had = buff_ext:has_buff_type("twitch_speed_boost")
		T.note("had_speed_boost_before", had)
	end,
}
