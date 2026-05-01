return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`Character Weapon Variants` mod must be lower than Vermintide Mod Framework in your launcher's load order.")

		new_mod("character_weapon_variants", {
			mod_script       = "scripts/mods/character_weapon_variants/character_weapon_variants",
			mod_data         = "scripts/mods/character_weapon_variants/character_weapon_variants_data",
			mod_localization = "scripts/mods/character_weapon_variants/character_weapon_variants_localization",
		})
	end,
	packages = {
		"resource_packages/character_weapon_variants/character_weapon_variants",
	},
}
