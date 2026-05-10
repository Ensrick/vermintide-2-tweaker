return {
    mod_description = {
        en = "Customize enemy spawns: horde compositions, per-difficulty specials control, and breed substitution.",
    },

    -- ============================================================
    -- HORDES
    -- ============================================================
    horde_group = {
        en = "Horde Composition",
    },
    horde_preset = {
        en = "Horde Preset",
    },
    horde_preset_tooltip = {
        en = "Replace horde compositions with a preset. 'Faction' presets force a single race; 'Theme' presets are content overhauls (elites only, skeleton swarms, etc.).",
    },
    preset_off               = { en = "Off (vanilla hordes)" },
    preset_skaven_only       = { en = "Faction: Skaven Only" },
    preset_chaos_only        = { en = "Faction: Chaos Only" },
    preset_beastmen_invasion = { en = "Faction: Beastmen Invasion" },
    preset_mixed_factions    = { en = "Faction: Mixed (all three)" },
    preset_all_elites        = { en = "Theme: All Elites" },
    preset_necro_skeletons   = { en = "Theme: Necromancer Skeletons" },
    preset_ghost_skeletons   = { en = "Theme: Ghost Skeletons" },
    preset_skeleton_mix      = { en = "Theme: All Skeletons Mixed" },
    horde_size_multiplier = {
        en = "Horde Size",
    },
    horde_size_multiplier_tooltip = {
        en = "Scale horde enemy count. 100 = normal, 200 = double, 25 = quarter. Applies whether or not a preset is selected.",
    },

    -- ============================================================
    -- ENEMY SPAWNS (per-difficulty)
    -- ============================================================
    enemy_spawns_group   = { en = "Enemy Spawns" },
    special_spawns_group = { en = "Special Spawns" },

    -- Difficulty group headers — keys must match `et_diff_<key>_group`
    et_diff_normal_group      = { en = "Recruit" },
    et_diff_hard_group        = { en = "Veteran" },
    et_diff_harder_group      = { en = "Champion" },
    et_diff_hardest_group     = { en = "Legend" },
    et_diff_cataclysm_group   = { en = "Cataclysm 1" },
    et_diff_cataclysm_2_group = { en = "Cataclysm 2" },
    et_diff_cataclysm_3_group = { en = "Cataclysm 3" },

    -- Per-difficulty sub-group headers (one set, reused via the keys built
    -- by _setting_key(diff, "weights_group") / _setting_key(diff, "disabled_group"))
    et_diff_normal_weights_group       = { en = "Spawn Weights" },
    et_diff_hard_weights_group         = { en = "Spawn Weights" },
    et_diff_harder_weights_group       = { en = "Spawn Weights" },
    et_diff_hardest_weights_group      = { en = "Spawn Weights" },
    et_diff_cataclysm_weights_group    = { en = "Spawn Weights" },
    et_diff_cataclysm_2_weights_group  = { en = "Spawn Weights" },
    et_diff_cataclysm_3_weights_group  = { en = "Spawn Weights" },

    et_diff_normal_disabled_group      = { en = "Disabled Specials" },
    et_diff_hard_disabled_group        = { en = "Disabled Specials" },
    et_diff_harder_disabled_group      = { en = "Disabled Specials" },
    et_diff_hardest_disabled_group     = { en = "Disabled Specials" },
    et_diff_cataclysm_disabled_group   = { en = "Disabled Specials" },
    et_diff_cataclysm_2_disabled_group = { en = "Disabled Specials" },
    et_diff_cataclysm_3_disabled_group = { en = "Disabled Specials" },

    -- Reusable labels for the two numeric controls in each difficulty block
    specials_max_total = { en = "Max Specials Active" },
    specials_max_same  = { en = "Max Specials of Same Type" },

    -- ============================================================
    -- BREED SUBSTITUTION
    -- ============================================================
    breed_swap_group = {
        en = "Breed Substitution",
    },
    breed_swap_off = {
        en = "Off",
    },
    breed_swap_from = {
        en = "Replace This Breed",
    },
    breed_swap_from_tooltip = {
        en = "Every enemy of this breed in hordes will be replaced with the target breed below.",
    },
    breed_swap_to = {
        en = "With This Breed",
    },
    breed_swap_to_tooltip = {
        en = "The replacement breed. Must be different from the source breed.",
    },
}
