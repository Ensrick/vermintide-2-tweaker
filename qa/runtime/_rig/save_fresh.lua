-- WP-H-08 step 3 rig acceptance: plan "save": "fresh" starts the run with no save file. The game then logs a load
-- error and never calls populate_save_data, so SaveData.save_loaded keeps its default false
-- (Vermintide-2-Source-Code/scripts/game_state/title_screen_substates/win32/state_title_screen_init_network.lua:39-44;
-- scripts/managers/save/save_data.win32.lua:14-21, set true only at :72). With the owner's save copied in it is true.
return {
	issue = 0,
	arena = "keep",
	class = "R",
	timeout = 30,
	run = function(T)
		local loaded = T.main(function()
			local save_data = rawget(_G, "SaveData")

			return type(save_data) == "table" and save_data.save_loaded
		end)

		T.expect_eq(loaded, false, "no save file was loaded (SaveData.save_loaded is false)")
	end,
}
