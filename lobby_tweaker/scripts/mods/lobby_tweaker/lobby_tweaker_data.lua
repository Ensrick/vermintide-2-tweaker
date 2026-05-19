local mod = get_mod("lobby_tweaker")

return {
    name = "Tweaker: Lobby",
    description = "mod_description",
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = "group_slot_reservations",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "slot_reservations_enabled",
                        type = "checkbox",
                        default_value = false,
                    },
                },
            },
            {
                setting_id = "group_session_ignore",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "session_ignore_enabled",
                        type = "checkbox",
                        default_value = false,
                    },
                },
            },
            {
                setting_id = "group_kick_idle",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "kick_idle_enabled",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "kick_idle_threshold_minutes",
                        type = "numeric",
                        default_value = 10,
                        range = { 1, 60 },
                    },
                    {
                        setting_id = "ki_warn_seconds",
                        type = "numeric",
                        default_value = 60,
                        range = { 10, 180 },
                    },
                },
            },
            {
                setting_id = "group_motd",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "motd_enabled",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "motd_text",
                        type = "text_input",
                        default_value = "",
                    },
                    {
                        setting_id = "motd_send_chat",
                        type = "checkbox",
                        default_value = true,
                    },
                    {
                        setting_id = "motd_send_popup",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "motd_once_per_peer_per_session",
                        type = "checkbox",
                        default_value = true,
                    },
                },
            },
            {
                setting_id = "group_modded_manifest",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "manifest_broadcast_enabled",
                        type = "checkbox",
                        default_value = true,
                    },
                    {
                        setting_id = "manifest_failnotify_enabled",
                        type = "checkbox",
                        default_value = true,
                    },
                },
            },
        },
    },
}
