local mod = get_mod("chaos_wastes_coin_tweaker")

return {
    name              = mod:localize("mod_name"),
    description       = mod:localize("mod_description"),
    is_togglable      = true,
    options = {
        widgets = {
            -- ============================================================
            -- Coin Multiplier
            -- ============================================================
            {
                setting_id      = "coin_multiplier",
                type            = "numeric",
                default_value   = 1,
                range           = { 0.1, 5 },
                decimals_number = 2,
            },
            -- ============================================================
            -- Starting Coins
            -- ============================================================
            {
                setting_id    = "starting_coins",
                type          = "numeric",
                default_value = 0,
                range         = { 0, 3000 },
                decimals_number = 0,
            },
            -- ============================================================
            -- Boon Options Count
            -- ============================================================
            {
                setting_id      = "shrine_boon_count",
                type            = "numeric",
                default_value   = 4,
                range           = { 1, 5 },
                decimals_number = 0,
            },
            {
                setting_id      = "chest_boon_count",
                type            = "numeric",
                default_value   = 3,
                range           = { 1, 5 },
                decimals_number = 0,
            },
            -- ============================================================
            -- Curse Disabling
            -- ============================================================
            {
                setting_id    = "disable_curse_bolt_of_change",
                type          = "checkbox",
                default_value = false,
            },
            {
                setting_id    = "disable_curse_change_of_tzeentch",
                type          = "checkbox",
                default_value = false,
            },
            {
                setting_id    = "disable_curse_egg_of_tzeentch",
                type          = "checkbox",
                default_value = false,
            },
            {
                setting_id    = "disable_curse_empathy",
                type          = "checkbox",
                default_value = false,
            },
            {
                setting_id    = "disable_curse_khorne_champions",
                type          = "checkbox",
                default_value = false,
            },
            {
                setting_id    = "disable_curse_rotten_miasma",
                type          = "checkbox",
                default_value = false,
            },
            {
                setting_id    = "disable_curse_shadow_homing_skulls",
                type          = "checkbox",
                default_value = false,
            },
            {
                setting_id    = "disable_curse_skulking_sorcerer",
                type          = "checkbox",
                default_value = false,
            },
            {
                setting_id    = "disable_curse_skulls_of_fury",
                type          = "checkbox",
                default_value = false,
            },
        },
    },
}
