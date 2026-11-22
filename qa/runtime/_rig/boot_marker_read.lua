-- WP-H-08 two-boot acceptance, boot 2: the marker boot 1 saved (boot_marker_write.lua) is still in the user settings,
-- so this boot started from the profile boot 1 left, not from a fresh copy of the owner's profile.
return {
	issue = 0,
	arena = "keep",
	class = "R",
	timeout = 30,
	run = function(T)
		local stored = T.main(function()
			return Application.user_setting("vt2_rig_boot_marker")
		end)

		T.note("marker", tostring(stored))
		T.expect(type(stored) == "string" and stored:find("^boot1%-") ~= nil, "boot 1's marker survived the restart")
		T.expect(stored ~= "boot1-" .. T.nonce, "the marker comes from the earlier boot (its nonce differs)")
	end,
}
