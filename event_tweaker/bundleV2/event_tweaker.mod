return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`Tweaker: Events` mod must be lower than Vermintide Mod Framework in your launcher's load order.")

		new_mod("event_tweaker", {
			mod_script       = "scripts/mods/event_tweaker/event_tweaker",
			mod_data         = "scripts/mods/event_tweaker/event_tweaker_data",
			mod_localization = "scripts/mods/event_tweaker/event_tweaker_localization",
		})
	end,
	packages = {
		"resource_packages/event_tweaker/event_tweaker",
	},
}
