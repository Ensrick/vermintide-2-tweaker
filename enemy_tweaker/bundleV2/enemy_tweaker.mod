return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`Tweaker: Enemies` mod must be lower than Vermintide Mod Framework in your launcher's load order.")

		new_mod("enemy_tweaker", {
			mod_script       = "scripts/mods/enemy_tweaker/enemy_tweaker",
			mod_data         = "scripts/mods/enemy_tweaker/enemy_tweaker_data",
			mod_localization = "scripts/mods/enemy_tweaker/enemy_tweaker_localization",
		})
	end,
	packages = {
		"resource_packages/enemy_tweaker/enemy_tweaker",
	},
}
