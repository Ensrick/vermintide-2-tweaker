-- WP-H-08 rig acceptance: values a plan sets before boot are what the game reads. The plan
-- qa/runtime/plans/plan-options.json writes a VMF option into the profile's mods_settings table (read by VMF once at
-- load, Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/settings.lua:10) and the top-level user setting
-- use_pc_menu_layout; the smoke case before this one asserts the modset's mods are loaded.
return {
	issue = 0,
	arena = "keep",
	class = "R",
	timeout = 30,
	run = function(T)
		local vmf = T.find_mod("VMF")

		T.require(vmf ~= nil, "VMF loaded")
		T.expect_eq(vmf:get("vt2_rig_plan_option"), "rig-plan", "VMF reads the option the plan set")
		T.expect_eq(vmf:get("vt2_rig_plan_number"), 7, "a number option arrives as a number")

		local layout = T.main(function()
			return Application.user_setting("use_pc_menu_layout")
		end)

		T.expect_eq(layout, true, "the plan's top-level setting use_pc_menu_layout is true")
	end,
}
