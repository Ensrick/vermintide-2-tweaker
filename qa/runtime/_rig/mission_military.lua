-- Mission arena smoke (WP-H-04): Righteous Stand loads as host with bots, the hero is alive, an enemy can be
-- spawned next to the hero and killed. The hero is made invincible for the case and the flag is restored after
-- it, like every helper change (driver cleanup). Plan: qa/runtime/plans/mission-smoke.json.
-- Engine calls behind the helpers: T.spawn = ConflictDirector.spawn_queued_unit as the game's own test hook
-- calls it (Vermintide-2-Source-Code/scripts/managers/conflict_director/conflict_director_testify.lua:18-22),
-- read back through spawned_units_by_breed (conflict_director.lua:2144); T.kill = AiUtils.kill_unit
-- (scripts/unit_extensions/human/ai_player_unit/ai_utils.lua:1326), which needs HEALTH_ALIVE[unit] (same file).
return {
	issue = 0,
	arena = "mission:military",
	class = "R",
	timeout = 90,
	run = function(T)
		T.step("mission loaded")
		T.expect_eq(T.level_key(), "military", "level is Righteous Stand")
		local hero = T.local_hero(30)
		T.expect(hero ~= nil, "local hero unit is alive")
		local bots = T.bots()
		T.note("bot_count", #bots)
		T.expect(#bots > 0, "at least one bot is alive")
		T.invincible(true)

		T.step("spawn one enemy next to the hero")
		local enemy = T.spawn("skaven_slave", { 2, 0, 0 })
		T.expect(enemy ~= nil, "a skaven slave was spawned and is alive")

		T.step("kill it")
		T.expect(T.kill(enemy), "kill_unit accepted the living enemy")
		local dead = T.wait_until(function()
			return not HEALTH_ALIVE[enemy]
		end, 10, "the enemy is dead")
		T.expect(dead ~= nil, "the enemy died")

		T.step("buff extension readable on the hero")
		local buff_ext = T.ext(hero, "buff_system")
		local had = buff_ext:has_buff_type("twitch_speed_boost")
		T.note("had_speed_boost_before", had)
	end,
}
