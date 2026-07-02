return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`Weapons of Chaos` mod must be lower than Vermintide Mod Framework in your launcher's load order.")

		new_mod("WOC", {
			mod_script       = "scripts/mods/weapons_of_chaos/weapons_of_chaos",
			mod_data         = "scripts/mods/weapons_of_chaos/weapons_of_chaos_data",
			mod_localization = "scripts/mods/weapons_of_chaos/weapons_of_chaos_localization",
		})
	end,
	packages = {
		"resource_packages/weapons_of_chaos/weapons_of_chaos",
	},
}
