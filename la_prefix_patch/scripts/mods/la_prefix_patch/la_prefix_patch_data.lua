local mod = get_mod("la_prefix_patch")

return {
    name         = mod:localize("mod_name"),
    description  = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id  = "la_quiet_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "suppress_la_quest_markers",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("suppress_la_quest_markers_tooltip"),
                    },
                    {
                        setting_id    = "suppress_la_notifications",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("suppress_la_notifications_tooltip"),
                    },
                },
            },
        },
    },
}
