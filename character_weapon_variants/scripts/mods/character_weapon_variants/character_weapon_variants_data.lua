local mod = get_mod("character_weapon_variants")
local _anim_picker = mod:dofile("scripts/mods/character_weapon_variants/cwv_dev_anim_picker")

return {
	name = "Character Weapon Variants",
	description = mod:localize("mod_description"),
	is_togglable = true,
	custom_gui_textures = {
		atlases = {
			{
				"materials/character_weapon_variants/cwv_weapon_icons",
				"cwv_weapon_icons",
				"cwv_weapon_icons_masked",
				nil,
				nil,
				"cwv_weapon_icons",
			},
		},
		ui_renderer_injections = {
			{ "ingame_ui", "materials/character_weapon_variants/cwv_weapon_icons" },
			{ "hero_view", "materials/character_weapon_variants/cwv_weapon_icons" },
			{ "loading_view", "materials/character_weapon_variants/cwv_weapon_icons" },
			{ "popup_manager", "materials/character_weapon_variants/cwv_weapon_icons" },
		},
	},
	options = {
		-- Loose variant toggles sorted A->Z by display label: Bomb Slot
		-- (Tuskgor Javelin), Kruber Crossbow, Mace and Hammer Identity,
		-- Mace and Sword.
		widgets = {
			{
				setting_id = "cwv_dev_options",
				type = "group",
				sub_widgets = {
					{
						setting_id = "enable_cwv_dev_anim_picker",
						type = "checkbox",
						default_value = false,
						tooltip = "enable_cwv_dev_anim_picker_tooltip",
						sub_widgets = _anim_picker.build_widget_tree(),
					},
				},
			},
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
				setting_id    = "enable_cwv_mace_hammer_identity",
				type          = "checkbox",
				default_value = true,
				tooltip       = "enable_cwv_mace_hammer_identity_tooltip",
			},
			{
				setting_id    = "mace_sword_tweak",
				type          = "checkbox",
				default_value = true,
			},
		},
	},
}
