return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`Dynamic Cosmetic Portraits` mod must be lower than Vermintide Mod Framework in your launcher's load order.")

		new_mod("dynamic_cosmetic_portraits", {
			mod_script       = "scripts/mods/dynamic_cosmetic_portraits/dynamic_cosmetic_portraits",
			mod_data         = "scripts/mods/dynamic_cosmetic_portraits/dynamic_cosmetic_portraits_data",
			mod_localization = "scripts/mods/dynamic_cosmetic_portraits/dynamic_cosmetic_portraits_localization",
		})
	end,
	packages = {
		"resource_packages/dynamic_cosmetic_portraits/dynamic_cosmetic_portraits",
	},
}
