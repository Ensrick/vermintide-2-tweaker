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
			"icon_wpn_blightreaper",
		},
		ui_renderer_injections = {
			{ "ingame_ui", "materials/ui/icon_wpn_blightreaper" },
			{ "hero_view", "materials/ui/icon_wpn_blightreaper" },
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
