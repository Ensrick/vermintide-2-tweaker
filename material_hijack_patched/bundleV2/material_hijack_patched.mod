return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`Material-Hijack (patched)` mod must be lower than Vermintide Mod Framework in your launcher's load order.")

		new_mod("material_hijack_patched", {
			mod_script       = "scripts/mods/material_hijack_patched/material_hijack_patched",
			mod_data         = "scripts/mods/material_hijack_patched/material_hijack_patched_data",
			mod_localization = "scripts/mods/material_hijack_patched/material_hijack_patched_localization",
		})
	end,
	packages = {
		"resource_packages/material_hijack_patched/material_hijack_patched",
	},
}
