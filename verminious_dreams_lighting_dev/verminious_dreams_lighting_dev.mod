return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`Verminious Dreams Lighting` mod must be lower than Vermintide Mod Framework in your launcher's load order.")

		new_mod("verminious_dreams_lighting_dev", {
			mod_script       = "scripts/mods/verminious_dreams_lighting_dev/verminious_dreams_lighting_dev",
			mod_data         = "scripts/mods/verminious_dreams_lighting_dev/verminious_dreams_lighting_dev_data",
			mod_localization = "scripts/mods/verminious_dreams_lighting_dev/verminious_dreams_lighting_dev_localization",
		})
	end,
	packages = {
		"resource_packages/verminious_dreams_lighting_dev/verminious_dreams_lighting_dev",
	},
}
