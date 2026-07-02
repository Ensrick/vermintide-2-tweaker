local mod = get_mod("verminious_dreams_lighting")

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
        },
    },
}
