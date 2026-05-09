local mod = get_mod("character_weapon_variants")

return {
	name = "Character Weapon Variants",
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id    = "mace_sword_tweak",
				type          = "checkbox",
				default_value = true,
			},
			{
				setting_id    = "cwv_3p_swap_enabled",
				type          = "checkbox",
				default_value = true,
			},
		},
	},
}
