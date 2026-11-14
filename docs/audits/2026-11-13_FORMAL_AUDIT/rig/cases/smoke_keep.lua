-- Boot-to-keep smoke: the game reached the keep with no input and the expected mods are loaded.
return {
	issue = 0,
	timeout = 60,
	run = function(T)
		T.step("reach the keep")
		local hero = T.local_hero(30)
		T.expect(hero ~= nil, "local hero unit is alive")
		T.expect_eq(T.level_key(), "inn_level", "level is the keep")

		T.step("framework and commands")
		local vmf = T.find_mod("VMF")
		T.expect(vmf ~= nil, "VMF is loaded")
		local commands = T.commands("")
		T.note("command_count", #commands)

		T.step("player state readable")
		local player = T.local_player()
		T.expect(player ~= nil, "local player exists")
		if player then
			T.note("profile_index", player:profile_index())
			T.note("career_index", player:career_index())
		end
		local health = hero and ScriptUnit.has_extension(hero, "health_system")
		T.expect(health ~= nil, "hero has a health extension")
		if health then
			T.note("health", health:current_health())
		end
	end,
}
