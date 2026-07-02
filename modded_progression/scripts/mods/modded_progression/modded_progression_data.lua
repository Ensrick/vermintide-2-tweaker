local mod = get_mod("mp")

return {
    name = "Modded Progression",
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id    = "starting_state",
                type          = "dropdown",
                default_value = "fresh",
                tooltip       = "starting_state_tooltip",
                options = {
                    { text = "start_fresh",             value = "fresh" },
                    { text = "start_level_35",          value = "level_35" },
                    { text = "start_level_35_unlocked", value = "level_35_unlocked" },
                },
            },
        },
    },
}
