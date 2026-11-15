-- API self-test, career part (WP-H-06 group "inventory and career"): T.career switches the local hero to another
-- unlocked career of the same hero and back. The game records the selection in the backend mirror
-- (profile_synchronizer.lua:747) and the write shield holds it back, so no updateHeroAttributes request may appear.
return {
	issue = 0,
	arena = "keep",
	class = "R",
	timeout = 120,
	run = function(T)
		T.require(T.local_hero(30) ~= nil, "local hero alive")
		T.require(T.shield().installed, "backend write shield installed")

		local player = T.local_player()
		local profile_name = player:profile_display_name()
		local from = player:career_name()
		local profile = SPProfiles[FindProfileIndex(profile_name)]
		local experience = Managers.backend:get_interface("hero_attributes"):get(profile_name, "experience") or 0
		local level = ExperienceSettings.get_level(experience)
		local target

		-- the unlock rule T.career also checks (career_settings.lua:23-39)
		for _, career in ipairs(profile.careers) do
			if not target and career.name ~= from and career:is_unlocked_function(profile_name, level) then
				target = career.name
			end
		end

		T.require(target ~= nil, "a second unlocked career of " .. tostring(profile_name))
		T.note("careers", tostring(from) .. " -> " .. tostring(target))

		T.step("T.career to the other career")
		local unit = T.career(profile_name, target, 45)

		T.expect(unit ~= nil, "the hero respawned")
		T.expect_eq(T.local_player():career_name(), target, "the player reports the new career")

		T.step("T.career back")
		T.career(profile_name, from, 45)
		T.expect_eq(T.local_player():career_name(), from, "the player is back on the first career")
		T.expect_eq(T.shield().saw_update_hero_attributes, 0, "no updateHeroAttributes request since the shield went up")
	end,
}
