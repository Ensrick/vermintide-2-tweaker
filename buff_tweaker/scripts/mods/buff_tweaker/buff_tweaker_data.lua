local mod = get_mod("bt")

return {
    name         = mod:localize("mod_name"),
    description  = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id  = "bt_big_rebalance_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "bt_master_enable_br_registrations",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("bt_master_enable_br_registrations_tooltip"),
                    },
                },
            },
        },
    },
}
