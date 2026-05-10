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
    {
        setting_id    = "la_bridge_enable",
        type          = "checkbox",
        default_value = false,
        tooltip       = mod:localize("la_bridge_enable_tooltip"),
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
                setting_id  = "experimental_tints_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "tint_pureheart_white",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("tint_pureheart_white_tooltip"),
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

-- Append the auto-generated cosmetic-unlock widget tree (Character → Career →
-- Hats/Skins → individual checkboxes). See _cosmetic_unlocks.lua and the python
-- generator that produces it.
for _, w in ipairs(U.widgets) do
    widgets[#widgets + 1] = w
end

return {
    name = "Tweaker: Cosmetics",
    description = mod:localize("mod_description"),
    is_togglable = true,

    options = { widgets = widgets },
}
