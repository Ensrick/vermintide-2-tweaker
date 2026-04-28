return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`Cosmetics Tweaker` mod must be lower than Vermintide Mod Framework in your launcher's load order.")

		new_mod("cosmetics_tweaker", {
			mod_script       = "scripts/mods/cosmetics_tweaker/cosmetics_tweaker",
			mod_data         = "scripts/mods/cosmetics_tweaker/cosmetics_tweaker_data",
			mod_localization = "scripts/mods/cosmetics_tweaker/cosmetics_tweaker_localization",
		})
	end,
	packages = {
		"resource_packages/cosmetics_tweaker/cosmetics_tweaker",
	},
}
