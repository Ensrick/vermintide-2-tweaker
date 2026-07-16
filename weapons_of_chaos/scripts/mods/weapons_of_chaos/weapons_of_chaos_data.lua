local mod = get_mod("WOC")

-- VMF widget tree. `enable_blightreaper` gates registration of the Blightreaper
-- item (takes effect on game restart; registration is boot/keep-time). WOC has no
-- debug-logging checkbox: it uses the VMF-native debug channels (mod:debug /
-- mod:warning) gated by VMF output_mode_debug / output_mode_warning, migrated in
-- v0.1.2-dev (PROJECT_STANDARDS.md § 3.6).
return {
	name           = "Weapons of Chaos",
	description     = mod:localize("mod_description"),
	is_togglable    = true,
	custom_gui_textures = {
		textures = {
			"icon_bg_cursed",
			"icon_wpn_blightreaper",
		},
		ui_renderer_injections = {
			-- `icon_bg_cursed` is an item-card rarity background. Inject it into
			-- the same ten renderer creators proven by CIM's `icon_bg_modded`.
			-- The authored weapon icon keeps its narrower four-renderer contract.
			{ "ingame_ui", "materials/ui/icon_bg_cursed", "materials/ui/icon_wpn_blightreaper" },
			{ "ingame_ui_settings", "materials/ui/icon_bg_cursed" },
			{ "hero_view", "materials/ui/icon_bg_cursed", "materials/ui/icon_wpn_blightreaper" },
			{ "hero_view_state_loot", "materials/ui/icon_bg_cursed" },
			{ "hero_view_state_store", "materials/ui/icon_bg_cursed" },
			{ "hero_view_state_weave_forge", "materials/ui/icon_bg_cursed" },
			{ "start_game_state_settings_overview", "materials/ui/icon_bg_cursed" },
			{ "level_end_view_base", "materials/ui/icon_bg_cursed" },
			{ "level_end_view_versus", "materials/ui/icon_bg_cursed" },
			{ "ui_manager", "materials/ui/icon_bg_cursed" },
			{ "loading_view", "materials/ui/icon_wpn_blightreaper" },
			{ "popup_manager", "materials/ui/icon_wpn_blightreaper" },
		},
	},
	options = {
		widgets = {
			{
				setting_id    = "enable_blightreaper",
				type          = "checkbox",
				default_value = true,
				tooltip       = "enable_blightreaper_tooltip",
			},
		},
	},
}
