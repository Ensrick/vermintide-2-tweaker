return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`Verminious Dreams Lighting` mod must be lower than Vermintide Mod Framework in your launcher's load order.")

		new_mod("verminious_dreams_lighting", {
			mod_script       = "scripts/mods/verminious_dreams_lighting/verminious_dreams_lighting",
			mod_data         = "scripts/mods/verminious_dreams_lighting/verminious_dreams_lighting_data",
			mod_localization = "scripts/mods/verminious_dreams_lighting/verminious_dreams_lighting_localization",
		})
	end,
	packages = {
		"resource_packages/verminious_dreams_lighting/verminious_dreams_lighting",
	},
}
