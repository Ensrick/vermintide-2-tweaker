-- WP-H-08 two-boot acceptance, boot 1: writes a marker into the rig profile's user settings and saves them
-- (Application.set_user_setting / save_user_settings, the calls the driver itself uses for its results). The rig
-- profile is the run's own copy; boot 2 (boot_marker_read.lua) starts from the profile this boot leaves.
return {
	issue = 0,
	arena = "keep",
	class = "R",
	timeout = 30,
	run = function(T)
		local marker = "boot1-" .. T.nonce

		T.main(function()
			Application.set_user_setting("vt2_rig_boot_marker", marker)
			Application.save_user_settings()
		end)

		local stored = T.main(function()
			return Application.user_setting("vt2_rig_boot_marker")
		end)

		T.note("marker", marker)
		T.expect_eq(stored, marker, "the marker is in this boot's user settings")
	end,
}
