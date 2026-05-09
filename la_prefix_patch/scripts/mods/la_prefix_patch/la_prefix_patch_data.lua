local mod = get_mod("la_prefix_patch")

return {
    name         = mod:localize("mod_name"),
    description  = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = {},
    },
}
