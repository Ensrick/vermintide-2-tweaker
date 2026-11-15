-- WP-H-05 deus-smoke, run part: the "deus:pat_mountain_wastes_path1" arena starts a run on one level from the hub,
-- the write shield dropped the run start's deusRunStarted request (it never reaches the account), a vanilla boon
-- granted with T.grant_boon is active, and T.set_deus_coins changes the run's coins (restored at cleanup).
return {
	issue = 0,
	arena = "deus:pat_mountain_wastes_path1",
	class = "R",
	timeout = 90,
	run = function(T)
		local hero = T.local_hero(60)

		T.require(hero ~= nil, "local hero alive in the run level")
		T.expect_eq(T.level_key(), "pat_mountain_wastes_path1", "the run level loaded")
		T.invincible(true)

		local shield = T.shield()

		T.expect((shield.blocked_by_name.deusRunStarted or 0) >= 1, "the shield dropped the run start's deusRunStarted request")
		T.expect_eq(shield.saw_update_hero_attributes, 0, "no updateHeroAttributes request since the shield went up")

		T.step("grant a vanilla boon")
		T.require(T.deus_run_controller() ~= nil, "a run is active")
		T.expect(not T.has_boon("attack_speed", "rare"), "the boon is not held before the grant")
		T.grant_boon("attack_speed", "rare")
		T.expect(T.has_boon("attack_speed", "rare"), "the granted boon is active for the local player")

		T.step("set the run's coins")
		local before = T.deus_coins()

		T.note("coins_before", tostring(before))
		T.set_deus_coins(123)
		T.expect_eq(T.deus_coins(), 123, "the run's coins read back as set")
	end,
}
