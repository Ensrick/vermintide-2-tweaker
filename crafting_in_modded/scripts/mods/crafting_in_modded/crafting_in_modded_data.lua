local mod = get_mod("cim")

return {
    name        = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = "forge_group",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "forge_hotkey",
                        type = "keybind",
                        default_value = {"b"},
                        keybind_trigger = "pressed",
                        keybind_type = "function_call",
                        function_name = "open_forge",
                    },
                },
            },
            {
                setting_id = "inventory_group",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "show_only_modded_weapons",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "restore_modded_loadout",
                        type = "checkbox",
                        default_value = true,
                    },
                },
            },
        },
    },
}
