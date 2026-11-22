-- WP-H-08 step 4 rig acceptance: what every rig profile forces is what the game reads. New-RigProfile.ps1 sets the
-- mod manager's developer_mode (top-level mod_settings, read once at start: Vermintide-2-Source-Code/scripts/managers/
-- mod/mod_manager.lua:11-15, ModManager.developer_mode_enabled :50-52) and VMF's own developer_mode and logging options
-- (mods_settings.VMF; Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/vmf_options.lua:27-123); the driver makes
-- the lobby private at KEEP READY (matchmaking_manager.lua:2246-2255, read back with is_game_private :2299-2305).
return {
	issue = 0,
	arena = "keep",
	class = "R",
	timeout = 30,
	run = function(T)
		T.step("mod developer mode")
		local manager_dev = T.main(function()
			return Managers.mod:developer_mode_enabled()
		end)

		T.expect_eq(manager_dev, true, "the mod manager runs in developer mode")

		local vmf = T.find_mod("VMF")

		T.require(vmf ~= nil, "VMF loaded")
		T.expect_eq(vmf:get("developer_mode"), true, "VMF developer_mode is on")

		T.step("VMF logging reaches the log file")
		T.expect_eq(vmf:get("logging_mode"), "custom", "VMF logging_mode is custom")

		for _, level in ipairs({ "echo", "error", "warning", "info", "debug" }) do
			local mode = vmf:get("output_mode_" .. level)

			-- 1 log, 3 log and chat (vmf_options.lua:57-123; logging.lua:136-152 sends odd values to the log)
			T.expect(type(mode) == "number" and mode % 2 == 1, "VMF output_mode_" .. level .. " includes the log file (got " .. tostring(mode) .. ")")
		end

		T.step("private lobby")
		local private = T.main(function()
			return Managers.matchmaking:is_game_private()
		end)

		T.expect_eq(private, true, "the host's lobby is private")
	end,
}
