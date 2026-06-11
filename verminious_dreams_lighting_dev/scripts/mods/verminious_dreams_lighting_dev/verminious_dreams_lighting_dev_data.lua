local mod = get_mod("verminious_dreams_lighting_dev")

return {
    name        = "Verminious Dreams Lighting",
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id    = "enable_dlc_termite_1",
                type          = "checkbox",
                default_value = true,
                tooltip       = "enable_dlc_termite_1_tooltip",
            },
            {
                setting_id    = "enable_dlc_termite_2",
                type          = "checkbox",
                default_value = true,
                tooltip       = "enable_dlc_termite_2_tooltip",
            },
            {
                setting_id    = "enable_dlc_termite_3",
                type          = "checkbox",
                default_value = true,
                tooltip       = "enable_dlc_termite_3_tooltip",
            },
            -- Universal Debug Logging toggle (PROJECT_STANDARDS.md § 3.6).
            -- Must be at the BOTTOM of the widget tree, top-level (NOT inside
            -- any group), key `enable_debug_logging` verbatim across every mod.
            {
                setting_id    = "enable_debug_logging",
                type          = "checkbox",
                default_value = false,
                tooltip       = "enable_debug_logging_tooltip",
            },
        },
    },
}
