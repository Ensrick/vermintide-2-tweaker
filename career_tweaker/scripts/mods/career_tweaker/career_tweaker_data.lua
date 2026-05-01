local mod = get_mod("crt")

-- Shared option list for every talent-swap dropdown (all 20 careers + "none").
-- Each option's text key is looked up in career_tweaker_localization.lua.
local talent_swap_options = {
    { text = "None (default)",                  value = "none"              },
    -- Bardin
    { text = "Ironbreaker (Bardin)",            value = "dr_ironbreaker"    },
    { text = "Slayer (Bardin)",                 value = "dr_slayer"         },
    { text = "Ranger (Bardin)",                 value = "dr_ranger"         },
    { text = "Engineer (Bardin)",               value = "dr_engineer"       },
    -- Markus
    { text = "Huntsman (Markus)",               value = "es_huntsman"       },
    { text = "Foot Knight (Markus)",            value = "es_knight"         },
    { text = "Mercenary (Markus)",              value = "es_mercenary"      },
    { text = "Grail Knight (Markus)",           value = "es_questingknight" },
    -- Kerillian
    { text = "Shade (Kerillian)",               value = "we_shade"          },
    { text = "Handmaiden (Kerillian)",          value = "we_maidenguard"    },
    { text = "Waystalker (Kerillian)",          value = "we_waywatcher"     },
    { text = "Sister of the Thorn (Kerillian)", value = "we_thornsister"    },
    -- Victor
    { text = "Zealot (Victor)",                 value = "wh_zealot"         },
    { text = "Bounty Hunter (Victor)",          value = "wh_bountyhunter"   },
    { text = "Witch Hunter Captain (Victor)",   value = "wh_captain"        },
    { text = "Warrior Priest (Victor)",         value = "wh_priest"         },
    -- Sienna
    { text = "Battle Wizard (Sienna)",          value = "bw_scholar"        },
    { text = "Pyromancer (Sienna)",             value = "bw_adept"          },
    { text = "Unchained (Sienna)",              value = "bw_unchained"      },
    { text = "Necromancer (Sienna)",            value = "bw_necromancer"    },
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
            -- Talent Balance Changes
            -- ============================================================
            {
                setting_id = "talent_balance_group",
                type       = "group",
                sub_widgets = {
                    { setting_id = "balance_zealot_merc_allow_random_crits", type = "checkbox", default_value = false },
                    { setting_id = "balance_whc_parry_extended_window", type = "checkbox", default_value = false },
                },
            },
        },
    },
}
