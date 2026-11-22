-- API self-test, T.set part (WP-H-06 step 3): T.set changes a VMF option through VMFMod:set with its
-- on_setting_changed event, and the case end puts the old value back (checked by api_set_restored.lua, the next case).
-- The option is a marker id that no VMF branch reads (vmf.on_setting_changed only acts on its own ids,
-- Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/vmf_options.lua:169-212), so the change has no effect
-- beyond the rig profile's settings.
local SETTING = "vt2_rig_api_selftest"

return {
	issue = 0,
	arena = "keep",
	class = "R",
	timeout = 60,
	run = function(T)
		local vmf = T.find_mod("VMF")
		T.require(vmf ~= nil and type(vmf.on_setting_changed) == "function", "VMF loaded with its on_setting_changed")
		T.note("before", tostring(vmf:get(SETTING)))

		T.step("T.set the marker option")
		local events = {}
		local original = vmf.on_setting_changed
		vmf.on_setting_changed = function(setting_id, ...)
			if setting_id == SETTING then
				events[#events + 1] = vmf:get(SETTING)
			end
			return original(setting_id, ...)
		end
		local value = "rig-" .. T.nonce
		-- No pcall around T.set: it yields (T.main). If it raised, the pass-through wrapper would stay for the boot.
		T.set("VMF", SETTING, value)
		vmf.on_setting_changed = original

		T.expect_eq(vmf:get(SETTING), value, "the option holds the new value")
		T.expect_eq(#events, 1, "on_setting_changed ran once for the option")
		T.expect_eq(events[1], value, "the event saw the new value")
	end,
}
