local mod = get_mod("gt")

return {
    name = "Tweaker: General",
    description = mod:localize("mod_description"),
    is_togglable = true,

    options = {
        widgets = {
            {
                setting_id  = "tp_camera_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "tp_camera_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("tp_camera_enabled_tooltip"),
                    },
                    {
                        setting_id    = "tp_distance",
                        type          = "numeric",
                        default_value = 3.0,
                        range         = { 1.0, 10.0 },
                        decimals_number = 1,
                        tooltip       = mod:localize("tp_distance_tooltip"),
                    },
                    {
                        setting_id    = "tp_height",
                        type          = "numeric",
                        default_value = 1.0,
                        range         = { -1.0, 5.0 },
                        decimals_number = 1,
                        tooltip       = mod:localize("tp_height_tooltip"),
                    },
                    {
                        setting_id    = "tp_side_offset",
                        type          = "numeric",
                        default_value = 0.8,
                        range         = { -3.0, 3.0 },
                        decimals_number = 1,
                        tooltip       = mod:localize("tp_side_offset_tooltip"),
                    },
                },
            },
            {
                setting_id  = "gameplay_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "godmode_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("godmode_enabled_tooltip"),
                    },
                    {
                        setting_id    = "allow_duplicate_careers",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("allow_duplicate_careers_tooltip"),
                    },
                },
            },
            {
                setting_id  = "mission_inventory_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "mission_inventory_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("mission_inventory_enabled_tooltip"),
                    },
                },
            },
        },
    },
}
