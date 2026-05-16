local mod = get_mod("crt")

-- Shared option list for every talent-swap dropdown (all 20 careers + "none").
-- `text` is a localization key — VMF wraps unresolved keys with `<<...>>` in
-- the UI, so every entry below must have a matching `talent_swap_option_*`
-- entry in career_tweaker_localization.lua.
local talent_swap_options = {
    { text = "talent_swap_option_none",              value = "none"              },
    -- Bardin
    { text = "talent_swap_option_dr_ironbreaker",    value = "dr_ironbreaker"    },
    { text = "talent_swap_option_dr_slayer",         value = "dr_slayer"         },
    { text = "talent_swap_option_dr_ranger",         value = "dr_ranger"         },
    { text = "talent_swap_option_dr_engineer",       value = "dr_engineer"       },
    -- Markus
    { text = "talent_swap_option_es_huntsman",       value = "es_huntsman"       },
    { text = "talent_swap_option_es_knight",         value = "es_knight"         },
    { text = "talent_swap_option_es_mercenary",      value = "es_mercenary"      },
    { text = "talent_swap_option_es_questingknight", value = "es_questingknight" },
    -- Kerillian
    { text = "talent_swap_option_we_shade",          value = "we_shade"          },
    { text = "talent_swap_option_we_maidenguard",    value = "we_maidenguard"    },
    { text = "talent_swap_option_we_waywatcher",     value = "we_waywatcher"     },
    { text = "talent_swap_option_we_thornsister",    value = "we_thornsister"    },
    -- Victor
    { text = "talent_swap_option_wh_zealot",         value = "wh_zealot"         },
    { text = "talent_swap_option_wh_bountyhunter",   value = "wh_bountyhunter"   },
    { text = "talent_swap_option_wh_captain",        value = "wh_captain"        },
    { text = "talent_swap_option_wh_priest",         value = "wh_priest"         },
    -- Sienna
    { text = "talent_swap_option_bw_scholar",        value = "bw_scholar"        },
    { text = "talent_swap_option_bw_adept",          value = "bw_adept"          },
    { text = "talent_swap_option_bw_unchained",      value = "bw_unchained"      },
    { text = "talent_swap_option_bw_necromancer",    value = "bw_necromancer"    },
}

return {
    name              = mod:localize("mod_name"),
    description       = mod:localize("mod_description"),
    is_togglable      = true,
    options = {
        widgets = {
            -- ============================================================
            -- Career Ability & Talent Swapping
            -- ============================================================
            {
                setting_id = "career_swapping_group",
                type       = "group",
                sub_widgets = {
                    -- Bardin
                    { setting_id = "talent_swap_dr_ironbreaker",    type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_dr_slayer",         type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_dr_ranger",         type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_dr_engineer",       type = "dropdown", default_value = "none", options = talent_swap_options },
                    -- Markus
                    { setting_id = "talent_swap_es_huntsman",       type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_es_knight",         type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_es_mercenary",      type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_es_questingknight", type = "dropdown", default_value = "none", options = talent_swap_options },
                    -- Kerillian
                    { setting_id = "talent_swap_we_shade",          type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_we_maidenguard",    type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_we_waywatcher",     type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_we_thornsister",    type = "dropdown", default_value = "none", options = talent_swap_options },
                    -- Victor
                    { setting_id = "talent_swap_wh_zealot",         type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_wh_bountyhunter",   type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_wh_captain",        type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_wh_priest",         type = "dropdown", default_value = "none", options = talent_swap_options },
                    -- Sienna
                    { setting_id = "talent_swap_bw_scholar",        type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_bw_adept",          type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_bw_unchained",      type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_bw_necromancer",    type = "dropdown", default_value = "none", options = talent_swap_options },
                },
            },
            -- ============================================================
            -- Talent Reworks
            --
            -- Hierarchy: Talent Reworks > General | Rework: <Character> > Rework: <Career> > Rework: <Talent>
            -- Every submenu and toggle label is prefixed "Rework: " so the player
            -- always sees which top-level menu they're navigating.
            -- ============================================================
            {
                setting_id = "talent_reworks_group",
                type       = "group",
                sub_widgets = {
                    -- General (cross-career)
                    {
                        setting_id  = "rework_general_group",
                        type        = "group",
                        sub_widgets = {
                            { setting_id = "rework_general_stagger_thp",      type = "checkbox", default_value = false },
                            { setting_id = "rework_general_thp_kill_minimum", type = "checkbox", default_value = false },
                        },
                    },
                    -- Bardin
                    {
                        setting_id  = "rework_dr_group",
                        type        = "group",
                        sub_widgets = {
                            {
                                setting_id  = "rework_dr_ranger_group",
                                type        = "group",
                                sub_widgets = {
                                    { setting_id = "rework_dr_ranger_attack_speed_5_to_10", type = "checkbox", default_value = false },
                                },
                            },
                        },
                    },
                    -- Kruber (Markus)
                    {
                        setting_id  = "rework_es_group",
                        type        = "group",
                        sub_widgets = {
                            {
                                setting_id  = "rework_es_mercenary_group",
                                type        = "group",
                                sub_widgets = {
                                    { setting_id = "rework_es_mercenary_hellborgs_tutelage", type = "checkbox", default_value = false },
                                },
                            },
                        },
                    },
                    -- Kerillian
                    {
                        setting_id  = "rework_we_group",
                        type        = "group",
                        sub_widgets = {
                            {
                                setting_id  = "rework_we_maidenguard_group",
                                type        = "group",
                                sub_widgets = {
                                    { setting_id = "rework_we_maidenguard_crit_chance_5_to_10", type = "checkbox", default_value = false },
                                },
                            },
                        },
                    },
                    -- Saltzpyre (Victor)
                    {
                        setting_id  = "rework_wh_group",
                        type        = "group",
                        sub_widgets = {
                            {
                                setting_id  = "rework_wh_zealot_group",
                                type        = "group",
                                sub_widgets = {
                                    { setting_id = "rework_wh_zealot_smite_random_crits", type = "checkbox", default_value = false },
                                    { setting_id = "rework_wh_zealot_power_5_to_10",      type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id  = "rework_wh_bountyhunter_group",
                                type        = "group",
                                sub_widgets = {
                                    { setting_id = "rework_wh_bountyhunter_double_shotted_80", type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id  = "rework_wh_captain_group",
                                type        = "group",
                                sub_widgets = {
                                    { setting_id = "rework_wh_captain_parry_window", type = "checkbox", default_value = false },
                                },
                            },
                        },
                    },
                },
            },
        },
    },
}
