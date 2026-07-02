local mod = get_mod("gut")

local GUT_HUD_MODE_OPTIONS = {
    { text = "Off",      value = "off" },
    { text = "Partial",  value = "partial" },
    { text = "Complete", value = "complete" },
    { text = "Camera",   value = "camera" },
}

return {
    name = "Tweaker: GUI",
    description = mod:localize("mod_description"),
    is_togglable = true,

    options = {
        widgets = {
            -- Compatibility patches for other UI mods absorbed into gut.
            {
                setting_id  = "gut_compat_group",
                type        = "group",
                sub_widgets = {
                    -- UI Tweaks "Temporal Fix" is now ALWAYS ON with a baked-in
                    -- nudge of -48 (the value the user dialed in) — no toggle / slider.
                    -- See _gut_uitweaks_temporal_fix.lua.
                    {
                        setting_id    = "gut_buffbar_endtime_fix",
                        type          = "checkbox",
                        default_value = true,
                        tooltip       = mod:localize("gut_buffbar_endtime_fix_tooltip"),
                    },
                },
            },
            -- Parry Indicator (absorbed). Recolours the block shields during the
            -- timed-block window for every weapon. RGB sub-sliders pick the colour.
            {
                setting_id  = "gut_parry_indicator",
                type        = "checkbox",
                default_value = false,
                tooltip     = mod:localize("gut_parry_indicator_tooltip"),
                sub_widgets = {
                    {
                        setting_id     = "gut_parry_r",
                        type           = "numeric",
                        range          = { 0, 255 },
                        default_value  = 0,
                        decimals_number = 0,
                        tooltip        = mod:localize("gut_parry_r"),
                    },
                    {
                        setting_id     = "gut_parry_g",
                        type           = "numeric",
                        range          = { 0, 255 },
                        default_value  = 255,
                        decimals_number = 0,
                        tooltip        = mod:localize("gut_parry_g"),
                    },
                    {
                        setting_id     = "gut_parry_b",
                        type           = "numeric",
                        range          = { 0, 255 },
                        default_value  = 120,
                        decimals_number = 0,
                        tooltip        = mod:localize("gut_parry_b"),
                    },
                },
            },
            -- Respawn countdown over a dead teammate's portrait (optional).
            {
                setting_id  = "gut_respawn_timer",
                type        = "checkbox",
                default_value = false,
                tooltip     = mod:localize("gut_respawn_timer_tooltip"),
                sub_widgets = {
                    { setting_id = "gut_respawn_font_size", type = "numeric", range = { 12, 80 },  default_value = 32, decimals_number = 0, tooltip = mod:localize("gut_respawn_font_size_tooltip") },
                    { setting_id = "gut_respawn_r",         type = "numeric", range = { 0, 255 },  default_value = 255, decimals_number = 0, tooltip = mod:localize("gut_respawn_r") },
                    { setting_id = "gut_respawn_g",         type = "numeric", range = { 0, 255 },  default_value = 60,  decimals_number = 0, tooltip = mod:localize("gut_respawn_g") },
                    { setting_id = "gut_respawn_b",         type = "numeric", range = { 0, 255 },  default_value = 60,  decimals_number = 0, tooltip = mod:localize("gut_respawn_b") },
                },
            },
            -- Skip Cutscenes (MIGRATED from general_tweaker 2026-06-25, issue #106).
            -- Own self-contained group. Behavior unchanged from gt; adds a printf
            -- [gut:cutscene] diagnostic. See _gut_cutscenes.lua.
            {
                setting_id  = "gut_cutscenes_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "gut_skip_cutscenes_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("gut_skip_cutscenes_enabled_tooltip"),
                        sub_widgets   = {
                            {
                                setting_id    = "gut_skip_cutscenes_auto",
                                type          = "checkbox",
                                default_value = false,
                                tooltip       = mod:localize("gut_skip_cutscenes_auto_tooltip"),
                            },
                        },
                    },
                    {
                        setting_id      = "gut_skip_cutscenes_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gut_skip_cutscenes_toggle",
                        default_value   = {},
                        tooltip         = mod:localize("gut_skip_cutscenes_hotkey_tooltip"),
                    },
                },
            },
            -- External config file (.toml): override VMF settings from a file you edit.
            {
                setting_id    = "gut_config_override",
                type          = "checkbox",
                default_value = true,
                tooltip       = mod:localize("gut_config_override_tooltip"),
            },
            -- Hide UI (3 modes) — migrated from general_tweaker. Cycle
            -- off → partial → complete → camera via dropdown, /gut_hud, or hotkey.
            {
                setting_id  = "gut_hud_visibility_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "gut_hud_mode",
                        type          = "dropdown",
                        default_value = "off",
                        options       = GUT_HUD_MODE_OPTIONS,
                        tooltip       = mod:localize("gut_hud_mode_tooltip"),
                    },
                    {
                        setting_id      = "gut_hud_cycle_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gut_hud_cycle",
                        default_value   = {},
                        tooltip         = mod:localize("gut_hud_cycle_hotkey_tooltip"),
                    },
                },
            },
            -- (#93) The Compact ESC/keep menu fix is now an ALWAYS-ON implicit feature
            -- (the toggle was removed 2026-06-24) — gut adds the ESC button that causes
            -- the overflow, so the fix always runs. See the
            -- HeroWindowIngameView._update_presentation hook in gui_tweaker_dev.lua.
            -- In-mission inventory access (migrated from general_tweaker 2026-06-24).
            -- Own self-contained group. See _gut_mission_inventory.lua.
            {
                setting_id  = "gut_mission_inventory_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "gut_mission_inventory_enabled",
                        type          = "checkbox",
                        default_value = true,   -- #87: on by default
                        tooltip       = mod:localize("gut_mission_inventory_enabled_tooltip"),
                    },
                    {
                        setting_id    = "gut_mission_menu_tabs",
                        type          = "checkbox",
                        default_value = true,   -- #87: on by default
                        tooltip       = mod:localize("gut_mission_menu_tabs_tooltip"),
                    },
                    {
                        setting_id      = "gut_open_inv_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gut_open_mission_inventory",
                        default_value   = {},
                        tooltip         = mod:localize("gut_open_inv_hotkey_tooltip"),
                    },
                },
            },
            -- In-mission HERO SELECT (sibling of the inventory group, 2026-06-24).
            -- Own self-contained group. Opens the HeroView TALENTS layout mid-mission
            -- (live-safe: talents apply immediately, no respawn). Career PICK is
            -- keep-only by design (mid-mission career change is unsafe). See
            -- _gut_mission_hero_select.lua.
            {
                setting_id  = "gut_mission_hero_select_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "gut_mission_hero_select_enabled",
                        type          = "checkbox",
                        default_value = true,   -- ON by default
                        tooltip       = mod:localize("gut_mission_hero_select_enabled_tooltip"),
                    },
                    {
                        setting_id      = "gut_open_hero_select_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gut_open_mission_hero_select",
                        default_value   = {},
                        tooltip         = mod:localize("gut_open_hero_select_hotkey_tooltip"),
                    },
                },
            },
            -- Mod Tweaker open hotkey (#125). The Mod Tweaker settings menu can
            -- already be opened from the ESC menu's "Mod Tweaker" button; this adds a
            -- direct function-call keybind (default UNBOUND) + the /gut_mod_tweaker
            -- command, both routing through mod.gut_open_mod_tweaker. Works in the keep
            -- and mid-mission; exiting returns to the game (#124).
            {
                setting_id  = "gut_mod_tweaker_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id      = "gut_open_mod_tweaker_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gut_open_mod_tweaker",
                        default_value   = {},
                        tooltip         = mod:localize("gut_open_mod_tweaker_hotkey_tooltip"),
                    },
                },
            },
        },
    },
}
