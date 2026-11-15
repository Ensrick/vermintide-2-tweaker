-- Boot-to-keep smoke: the game reached the keep with no input and the expected mods are loaded.
-- WP-H-02: every VMF mod id in the plan's expect_mods must be loaded; its version is noted when the mod object
-- exposes MOD_VERSION (run.ps1 also lists the [<tag>:LOAD] banners from the log in summary.json).
return {
	issue = 0,
	arena = "keep",
	class = "R",
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

		T.step("expected mods loaded")
		-- the plan block run.ps1 wrote into this profile's user settings (the bootstrap read the same table)
		local plan = Application.user_setting("vt2_rig_plan")
		local expect = type(plan) == "table" and plan.nonce == T.nonce and plan.expect_mods or {}
		T.note("expect_mods", #expect)
		for i = 1, #expect do
			local id = tostring(expect[i])
			local mod = T.find_mod(id)
			T.expect(mod ~= nil, "mod " .. id .. " is loaded")
			if mod then
				T.note("version:" .. id, tostring(rawget(mod, "MOD_VERSION") or "see load banner"))
			end
		end

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
