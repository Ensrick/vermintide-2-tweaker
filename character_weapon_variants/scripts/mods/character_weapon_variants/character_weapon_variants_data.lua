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
			-- v0.1.347-dev: cwv_es_crossbow variant toggle (Saltzpyre's
			-- crossbow on all 4 Kruber careers, rifle 3P anim mapping).
			-- Default ON. Carries known polish items (grip offsets, smoke FX,
			-- missing 3P bolt) tracked in TODO.md.
			{
				setting_id    = "enable_cwv_es_crossbow",
				type          = "checkbox",
				default_value = true,
				tooltip       = mod:localize("enable_cwv_es_crossbow_tooltip"),
			},
			-- Universal Debug Logging toggle (PROJECT_STANDARDS.md § 3.6).
			-- v0.1.340: renamed from `cwv_debug_mode` and un-nested from the
			-- old `cwv_diagnostics_group` per the universal convention. Key
			-- is `enable_debug_logging` verbatim, position is the BOTTOM of
			-- the widget tree, top-level (NOT inside any group).
			{
				setting_id    = "enable_debug_logging",
				type          = "checkbox",
				default_value = false,
				tooltip       = mod:localize("enable_debug_logging_tooltip"),
			},
		},
	},
}
