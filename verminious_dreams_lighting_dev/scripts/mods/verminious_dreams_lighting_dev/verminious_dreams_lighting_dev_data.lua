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
            -- Chaos Wastes curse-adjustment layer (v1.0.9-dev). When one of the
            -- three missions is injected into a cursed CW expedition, layer the
            -- per-deity curse tint on TOP of vdl's base lighting. Default ON;
            -- harmless outside Chaos Wastes (no-op in Adventure).
            {
                setting_id    = "enable_cw_curse_adjust",
                type          = "checkbox",
                default_value = true,
                tooltip       = "enable_cw_curse_adjust_tooltip",
            },
        },
    },
}
