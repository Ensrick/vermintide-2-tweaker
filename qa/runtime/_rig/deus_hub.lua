-- WP-H-05 deus-smoke, hub part: the "deus" arena reaches the Chaos Wastes hub with no input, and the game runs the
-- deus mechanism there (LevelSettings.morris_hub.mechanism, Vermintide-2-Source-Code/levels/honduras_dlcs/morris/
-- level_settings_morris.lua:15-29; GameMechanismManager.current_mechanism_name, game_mechanism_manager.lua:666).
return {
	issue = 0,
	arena = "deus",
	class = "R",
	timeout = 60,
	run = function(T)
		T.require(T.local_hero(60) ~= nil, "local hero alive in the hub")
		T.expect_eq(T.level_key(), "morris_hub", "the level is the Chaos Wastes hub")

		local mechanism = T.main(function()
			return Managers.mechanism:current_mechanism_name()
		end)

		T.expect_eq(mechanism, "deus", "the deus mechanism runs the hub")
		T.expect_eq(T.shield().saw_update_hero_attributes, 0, "no updateHeroAttributes request since the shield went up")
	end,
}
