local mod = get_mod("WOC")

-- VMF widget tree. `enable_blightreaper` gates registration of the Blightreaper
-- item (takes effect on game restart — registration is boot/keep-time). The
-- universal `enable_debug_logging` checkbox stays LAST, as a direct child of the
-- top-level widgets list (PROJECT_STANDARDS.md § 3.6).
return {
	name           = "Weapons of Chaos",
	description     = mod:localize("mod_description"),
	is_togglable    = true,
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
