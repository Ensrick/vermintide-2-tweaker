local mod = get_mod("character_weapon_variants")

return {
	name = "Character Weapon Variants",
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		-- Loose variant toggles sorted A->Z by display label: Bomb Slot
		-- (Tuskgor Javelin), Kruber Crossbow, Mace and Sword.
		widgets = {
			-- Bomb-slot Tuskgor Javelin — single-use thrown spear injected into
			-- the grenade pickup pool (does not replace frag/fire bombs).
			-- Default ON; takes effect on next keep/level load (pool is built
			-- on map entry, gated in the StateInGameRunning.on_enter register).
			{
				setting_id    = "enable_cwv_tuskgor_javelin_bomb",
				type          = "checkbox",
				default_value = true,
				tooltip       = "enable_cwv_tuskgor_javelin_bomb_tooltip",
			},
			-- v0.1.347-dev: cwv_es_crossbow variant toggle (Saltzpyre's
			-- crossbow on all 4 Kruber careers, rifle 3P anim mapping).
			-- Default ON. Carries known polish items (grip offsets, smoke FX,
			-- missing 3P bolt) tracked in TODO.md.
			{
				setting_id    = "enable_cwv_es_crossbow",
				type          = "checkbox",
				default_value = true,
				tooltip       = "enable_cwv_es_crossbow_tooltip",
			},
			{
				setting_id    = "mace_sword_tweak",
				type          = "checkbox",
				default_value = true,
			},
		},
	},
}
