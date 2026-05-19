return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`Modded Progression` mod must be lower than Vermintide Mod Framework in your launcher's load order.")

		new_mod("mp", {
			mod_script       = "scripts/mods/modded_progression/modded_progression",
			mod_data         = "scripts/mods/modded_progression/modded_progression_data",
			mod_localization = "scripts/mods/modded_progression/modded_progression_localization",
		})
	end,
	packages = {
		"resource_packages/modded_progression/modded_progression",
	},
}
