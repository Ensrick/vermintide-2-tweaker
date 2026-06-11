local mod = get_mod("gut")

return {
    name = "Tweaker: GUI",
    description = mod:localize("mod_description"),
    is_togglable = true,

    options = {
        widgets = {
            -- Universal Debug Logging toggle (PROJECT_STANDARDS.md § 3.6).
            -- Must be at the BOTTOM of the widget tree, top-level (NOT inside
            -- any group), key `enable_debug_logging` verbatim across every mod.
            {
                setting_id    = "enable_debug_logging",
                type          = "checkbox",
                default_value = false,
                tooltip       = mod:localize("enable_debug_logging_tooltip"),
            },
        },
    },
}
