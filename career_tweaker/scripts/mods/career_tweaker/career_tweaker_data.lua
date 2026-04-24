local mod = get_mod("career_tweaker")

local talent_swap_options = {
    { text = "talent_source_none", value = "none" },
    { text = "cname_dr_ironbreaker", value = "dr_ironbreaker" },
    { text = "cname_dr_slayer", value = "dr_slayer" },
    { text = "cname_dr_ranger", value = "dr_ranger" },
    { text = "cname_dr_engineer", value = "dr_engineer" },
    { text = "cname_es_huntsman", value = "es_huntsman" },
    { text = "cname_es_knight", value = "es_knight" },
    { text = "cname_es_mercenary", value = "es_mercenary" },
    { text = "cname_es_questingknight", value = "es_questingknight" },
    { text = "cname_we_shade", value = "we_shade" },
    { text = "cname_we_maidenguard", value = "we_maidenguard" },
    { text = "cname_we_waywatcher", value = "we_waywatcher" },
    { text = "cname_we_thornsister", value = "we_thornsister" },
    { text = "cname_wh_zealot", value = "wh_zealot" },
    { text = "cname_wh_bountyhunter", value = "wh_bountyhunter" },
    { text = "cname_wh_captain", value = "wh_captain" },
    { text = "cname_wh_priest", value = "wh_priest" },
    { text = "cname_bw_scholar", value = "bw_scholar" },
    { text = "cname_bw_adept", value = "bw_adept" },
    { text = "cname_bw_unchained", value = "bw_unchained" },
    { text = "cname_bw_necromancer", value = "bw_necromancer" },
}

return {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = "career_group",
                type = "group",
                sub_widgets = {
                    { setting_id = "allow_melee_in_ranged_slot", type = "checkbox", default_value = false },
                    { setting_id = "allow_duplicate_careers", type = "checkbox", default_value = false },
                },
            },
            {
                setting_id = "talents_group",
                type = "group",
                sub_widgets = {
                    { setting_id = "talent_swap_dr_ironbreaker", type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_dr_slayer", type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_dr_ranger", type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_dr_engineer", type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_es_huntsman", type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_es_knight", type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_es_mercenary", type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_es_questingknight", type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_we_shade", type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_we_maidenguard", type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_we_waywatcher", type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_we_thornsister", type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_wh_zealot", type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_wh_bountyhunter", type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_wh_captain", type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_wh_priest", type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_bw_scholar", type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_bw_adept", type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_bw_unchained", type = "dropdown", default_value = "none", options = talent_swap_options },
                    { setting_id = "talent_swap_bw_necromancer", type = "dropdown", default_value = "none", options = talent_swap_options },
                },
            },
        },
    },
}
