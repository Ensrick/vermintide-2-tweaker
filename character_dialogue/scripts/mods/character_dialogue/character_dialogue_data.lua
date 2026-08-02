local mod = get_mod("character_dialogue")

return {
    name = "Character Dialogue",
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id      = "cd_isolate_hotkey",
                type            = "keybind",
                keybind_trigger = "pressed",
                keybind_type    = "function_call",
                function_name   = "toggle_audio_isolation",
                default_value   = {},
                tooltip         = "cd_isolate_hotkey_tooltip",
            },
        },
    },
}
