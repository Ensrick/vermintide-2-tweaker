return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`VT2 Rig Driver` must be lower than Vermintide Mod Framework in the load order.")

		new_mod("vt2_rig_driver", {
			mod_script       = "scripts/mods/vt2_rig_driver/vt2_rig_driver",
			mod_data         = "scripts/mods/vt2_rig_driver/vt2_rig_driver_data",
			mod_localization = "scripts/mods/vt2_rig_driver/vt2_rig_driver_localization",
		})
	end,
	packages = {
		"resource_packages/vt2_rig_driver/vt2_rig_driver",
	},
}
