local mod = get_mod("cosmetics_tweaker")
local U = mod:dofile("scripts/mods/cosmetics_tweaker/_cosmetic_unlocks")

local widgets = {
    {
        setting_id    = "unlock_all_illusions",
        type          = "checkbox",
        default_value = false,
        tooltip       = mod:localize("unlock_all_illusions_tooltip"),
    },
    {
        setting_id    = "unlock_all_frames",
        type          = "checkbox",
        default_value = false,
        tooltip       = mod:localize("unlock_all_frames_tooltip"),
    },
    -- v0.9.3.9: la_bridge_enable toggle REMOVED. The LA bridge is now a
    -- built-in feature, always on. Players who don't want LA cosmetics
    -- just don't subscribe to Loremaster's Armoury. Removed widget from
    -- Settings tree; init code below treats it as unconditionally true.
    -- v0.9.3.1: LA Prefix Patch embedded — quiet-mode toggles for LA's quest
    -- markers and unread-letter notifications. Default off so LA behaves as
    -- shipped until user opts in.
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
    {
        setting_id    = "glow_picker_auto_popup_enabled",
        type          = "checkbox",
        default_value = true,
        tooltip       = mod:localize("glow_picker_auto_popup_enabled_tooltip"),
    },
    {
        setting_id  = "appearance_group",
        type        = "group",
        sub_widgets = {
            {
                setting_id  = "weapon_model_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "es_bastard_sword_thiccc",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("es_bastard_sword_thiccc_tooltip"),
                    },
                },
            },
            {
                setting_id  = "glow_override_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "glow_override_enable",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("glow_override_enable_tooltip"),
                    },
                    {
                        setting_id    = "glow_override_preset",
                        type          = "dropdown",
                        default_value = "default",
                        options       = {
                            { text = "glow_preset_default", value = "default"      },
                            { text = "glow_preset_white",   value = "white_glow"   },
                            { text = "glow_preset_purple",  value = "purple_glow"  },
                            { text = "glow_preset_gold",    value = "golden_glow"  },
                            { text = "glow_preset_red",     value = "deep_crimson" },
                            { text = "glow_preset_green",   value = "life_green"   },
                            { text = "glow_preset_blue",    value = "lileath"      },
                        },
                        tooltip = mod:localize("glow_override_preset_tooltip"),
                    },
                    -- Advanced: per-channel COLORS (magic family) + per-channel
                    -- brightness multipliers.
                    --
                    -- The main `glow_override_preset` above is one color applied
                    -- across the whole weapon. Standard rune-family glowy
                    -- weapons (themed Veteran, Stylish loot-chest) only have
                    -- one channel and that's all they need. Multi-channel
                    -- magic-family weapons (Weavebound, Shyish-Infused) have
                    -- 3 distinct visual elements (per probe v0.8.22):
                    --   * Lower gradient (color_glow_high + color_glow_low)
                    --   * Upper gradient (color_smoke_high + color_smoke_low)
                    --   * Dots particles (color_dots)
                    -- Enable "Per-Channel Colors" to drive each independently.
                    -- When the toggle is OFF, magic weapons use the main color.
                    {
                        setting_id  = "glow_advanced_group",
                        type        = "group",
                        sub_widgets = {
                            {
                                setting_id    = "glow_mult_master",
                                type          = "numeric",
                                default_value = 1.0,
                                range         = { 0.0, 5.0 },
                                decimals_number = 2,
                                tooltip       = mod:localize("glow_mult_master_tooltip"),
                            },
                            -- Per-channel COLORS (magic-family). Defaults match
                            -- the main color so toggling enable on/off doesn't
                            -- visually flip until the user sets specific colors.
                            {
                                setting_id    = "glow_per_channel_color_enable",
                                type          = "checkbox",
                                default_value = false,
                                tooltip       = mod:localize("glow_per_channel_color_enable_tooltip"),
                            },
                            {
                                setting_id    = "glow_color_lower_gradient",
                                type          = "dropdown",
                                default_value = "default",
                                options       = {
                                    { text = "glow_preset_default", value = "default"      },
                                    { text = "glow_preset_white",   value = "white_glow"   },
                                    { text = "glow_preset_purple",  value = "purple_glow"  },
                                    { text = "glow_preset_gold",    value = "golden_glow"  },
                                    { text = "glow_preset_red",     value = "deep_crimson" },
                                    { text = "glow_preset_green",   value = "life_green"   },
                                    { text = "glow_preset_blue",    value = "lileath"      },
                                },
                                tooltip = mod:localize("glow_color_lower_gradient_tooltip"),
                            },
                            {
                                setting_id    = "glow_color_upper_gradient",
                                type          = "dropdown",
                                default_value = "default",
                                options       = {
                                    { text = "glow_preset_default", value = "default"      },
                                    { text = "glow_preset_white",   value = "white_glow"   },
                                    { text = "glow_preset_purple",  value = "purple_glow"  },
                                    { text = "glow_preset_gold",    value = "golden_glow"  },
                                    { text = "glow_preset_red",     value = "deep_crimson" },
                                    { text = "glow_preset_green",   value = "life_green"   },
                                    { text = "glow_preset_blue",    value = "lileath"      },
                                },
                                tooltip = mod:localize("glow_color_upper_gradient_tooltip"),
                            },
                            {
                                setting_id    = "glow_color_dots",
                                type          = "dropdown",
                                default_value = "default",
                                options       = {
                                    { text = "glow_preset_default", value = "default"      },
                                    { text = "glow_preset_white",   value = "white_glow"   },
                                    { text = "glow_preset_purple",  value = "purple_glow"  },
                                    { text = "glow_preset_gold",    value = "golden_glow"  },
                                    { text = "glow_preset_red",     value = "deep_crimson" },
                                    { text = "glow_preset_green",   value = "life_green"   },
                                    { text = "glow_preset_blue",    value = "lileath"      },
                                },
                                tooltip = mod:localize("glow_color_dots_tooltip"),
                            },
                            -- Per-channel BRIGHTNESS multipliers. Mult of 0
                            -- SKIPS that channel (preserves whatever vanilla
                            -- wrote, or no write on non-templated meshes).
                            {
                                setting_id    = "glow_mult_rune",
                                type          = "numeric",
                                default_value = 1.0,
                                range         = { 0.0, 5.0 },
                                decimals_number = 2,
                                tooltip       = mod:localize("glow_mult_rune_tooltip"),
                            },
                            {
                                setting_id    = "glow_mult_glow_high",
                                type          = "numeric",
                                default_value = 1.0,
                                range         = { 0.0, 5.0 },
                                decimals_number = 2,
                                tooltip       = mod:localize("glow_mult_glow_high_tooltip"),
                            },
                            {
                                setting_id    = "glow_mult_glow_low",
                                type          = "numeric",
                                default_value = 1.0,
                                range         = { 0.0, 5.0 },
                                decimals_number = 2,
                                tooltip       = mod:localize("glow_mult_glow_low_tooltip"),
                            },
                            {
                                setting_id    = "glow_mult_smoke_high",
                                type          = "numeric",
                                default_value = 1.0,
                                range         = { 0.0, 5.0 },
                                decimals_number = 2,
                                tooltip       = mod:localize("glow_mult_smoke_high_tooltip"),
                            },
                            {
                                setting_id    = "glow_mult_smoke_low",
                                type          = "numeric",
                                default_value = 1.0,
                                range         = { 0.0, 5.0 },
                                decimals_number = 2,
                                tooltip       = mod:localize("glow_mult_smoke_low_tooltip"),
                            },
                            {
                                setting_id    = "glow_mult_dots",
                                type          = "numeric",
                                default_value = 0.0,
                                range         = { 0.0, 5.0 },
                                decimals_number = 2,
                                tooltip       = mod:localize("glow_mult_dots_tooltip"),
                            },
                        },
                    },
                },
            },
        },
    },
}

-- Experimental Third-Person Equipment: spawns extra 3P weapon meshes
-- attached to the player's body for whichever loadout slot isn't currently
-- wielded. Inspired by the standalone TPE mod (Workshop 1387440934).
-- Positions are coarse — per-item_type, not per-career.
widgets[#widgets + 1] = {
    setting_id  = "tpe_group",
    type        = "group",
    sub_widgets = {
        {
            setting_id    = "tpe_enable",
            type          = "checkbox",
            default_value = false,
            tooltip       = mod:localize("tpe_enable_tooltip"),
        },
        {
            setting_id    = "tpe_show_self_in_3p",
            type          = "checkbox",
            default_value = true,
            tooltip       = mod:localize("tpe_show_self_in_3p_tooltip"),
        },
        {
            setting_id      = "tpe_downscale_big_weapons",
            type            = "numeric",
            default_value   = 100,
            range           = { 25, 100 },
            decimals_number = 0,
            tooltip         = mod:localize("tpe_downscale_big_weapons_tooltip"),
        },
    },
}

-- Nest the auto-generated per-character cosmetic-unlock widget tree under a
-- single top-level "Cosmetic Availability" group so it doesn't clutter the
-- main settings list. The generated tree is Character → Career → Hats/Skins →
-- individual checkboxes; see _cosmetic_unlocks.lua and the python generator.
widgets[#widgets + 1] = {
    setting_id  = "cosmetic_availability_group",
    type        = "group",
    sub_widgets = U.widgets,
}

return {
    name = "Tweaker: Cosmetics",
    description = mod:localize("mod_description"),
    is_togglable = true,

    options = { widgets = widgets },
}
