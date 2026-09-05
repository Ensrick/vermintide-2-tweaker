-- Source-exact metadata for the Patch 6.0 launch boundary (#1436).
--
-- Fatshark originally numbered this release 5.7.0. The adjacent source
-- boundary selects only the two shield post-push changes and the charged
-- Fireball berserker armor modifier; Versus, presentation, sound, trait-pool,
-- function-body, and later penetrating changes remain excluded.
return {
    artifacts = {
        _wt_history_profiles_current_6_12_1_generated =
            "3c593a19fb8fd7ff8c8c0c35e2105a1ebdf46d2600dee98d971a89dc3cfddd95",
        _wt_history_profiles_5_6_1_rehydrated_generated =
            "e7d7c5c14526b2e09c0c74827a4e1760d1aaab65751273fe1386d8b337968943",
        _wt_history_profiles_5_6_1_to_6_0_generated =
            "990537de0d7405883f1cc2b9b70a0fba07a7a2cc1b99c66d4507c73c36ee2685",
        _wt_history_snapshot_5_6_1_breton_rehydrated_generated =
            "61837ef47d543637fa7554a8f0c0416cde2ef32bc789fb1a1344612535394763",
        _wt_history_snapshot_5_6_1_breton_to_6_0_generated =
            "ba310d502f9395db0a87d0670254034187efcea2f7e91db52db3a541d875f905",
        _wt_history_snapshot_5_6_1_sword_shield_rehydrated_generated =
            "e6fafa985f7fd4d8e1e36733e9672be62ebfdc446b62bd8d1125fc6c7e7bb9ce",
        _wt_history_snapshot_5_6_1_sword_shield_to_6_0_generated =
            "c875fb82bc37f2841dd99ad598f3b16bf755c44f2f82dae2356b26decd047791",
    },
    boundary = {
        historical_revision = "f64ecd2495bd26b1b0a4d296970bef0a0d7a06a9",
        post_revision = "da0bbdaf6af1ca7e8c96e7892a3416a4aa8a7f87",
    },
    current = {
        revision = "25fd7b8433e839b678d1c98a7a9af80918cbc252",
    },
    families = {
        bretonnian_sword_and_shield = {
            display_name = "Kruber's Bretonnian Sword and Shield",
            id = "kruber_bretonnian_sword_and_shield",
            label_key = "wt_history_family_kruber_bretonnian_sword_and_shield",
            official_change_id = "P600-BRETON-SS-POSTPUSH",
            official_summary =
                "Patch 6.0 adjusted the Bretonnian Sword and Shield post-push attack.",
            setting_id = "wt_history_kruber_bretonnian_sword_and_shield",
            template = "one_handed_sword_shield_template_2",
        },
        fireball_staff = {
            display_name = "Sienna's Fireball Staff",
            id = "sienna_fireball_staff",
            label_key = "wt_history_family_sienna_fireball_staff",
            official_change_id = "P600-FIREBALL-BERSERKER",
            official_summary =
                "Patch 6.0 fixed charged Fireball damage against berserkers.",
            setting_id = "wt_history_sienna_fireball_staff",
            template = "staff_fireball_fireball_template_1",
        },
        kruber_sword_and_shield = {
            display_name = "Kruber's Sword and Shield",
            id = "kruber_sword_and_shield",
            label_key = "wt_history_family_kruber_sword_and_shield",
            official_change_id = "P600-KRUBER-SS-POSTPUSH",
            official_summary =
                "Patch 6.0 adjusted Kruber's Sword and Shield post-push attack.",
            setting_id = "wt_history_kruber_sword_and_shield",
            template = "one_handed_sword_shield_template_1",
        },
    },
    official_patch_notes = "https://www.vermintide.com/news/versus-launch-patch-5-7-0",
    schema = 1,
    source_files = {
        {
            current_blob = "aed608e09cb504a3ac403e01e3a207630233044c",
            historical_blob = "70e77acd479b141c577eadf37097f6f909f4de6d",
            path = "scripts/settings/equipment/weapon_templates/1h_swords_shield.lua",
            post_blob = "86dd1780c0d47b7498eb1e82e9c1555b1c3a3453",
        },
        {
            current_blob = "e8463479350cb9a3195f553f46dabd2d658d279e",
            historical_blob = "67f836c0f9f024889ad8aec2b1dbe92a503a7434",
            path = "scripts/settings/equipment/weapon_templates/1h_swords_shield_breton.lua",
            post_blob = "3131d0570530893d4edde6edd8ac126de8c1cff3",
        },
        {
            current_blob = "6eba753d985ea80057947ed1ae1a25214204783e",
            historical_blob = "4a0d78a4d6125bb3f14575b505fb3d4c2d014094",
            path = "scripts/settings/equipment/power_level_templates.lua",
            post_blob = "4a0d78a4d6125bb3f14575b505fb3d4c2d014094",
        },
        {
            current_blob = "e8330328d0085f6aee09e0495ba88fdc0211d5aa",
            historical_blob = "e5d56cfb8de366baf1a946f70566ea052688c969",
            path = "scripts/settings/equipment/damage_profile_templates.lua",
            post_blob = "2daa213ce02ae4199a2f8147c8fb1d6753be59f2",
        },
        {
            current_blob = "a7f6e9e9fd9eb3e862c4c7a1ea5babfc5c43a733",
            historical_blob = "a5276cb9dbea4bbdf642905ef6b7b9cd3ad4e7fa",
            path = "scripts/settings/dlcs/morris/damage_profile_templates_dlc_morris.lua",
            post_blob = "8bc80fad3e34e165a942c4969e27ae418dc6ae08",
        },
        {
            current_blob = "01d295acab5e5850c83f31939124ca3124edc403",
            historical_blob = "01d295acab5e5850c83f31939124ca3124edc403",
            path = "scripts/settings/equipment/damage_profile_templates_dlc_cog.lua",
            post_blob = "01d295acab5e5850c83f31939124ca3124edc403",
        },
        {
            current_blob = "c379649a9dd9366004ac6e2221780f10dcfec581",
            historical_blob = "c379649a9dd9366004ac6e2221780f10dcfec581",
            path = "scripts/settings/equipment/damage_profile_templates_dlc_woods.lua",
            post_blob = "c379649a9dd9366004ac6e2221780f10dcfec581",
        },
        {
            current_blob = "18fc3da707e6bf155a12118361b43c176401e916",
            historical_blob = "1cc99c0b50d2a215807cc5aa11cefad0e2044174",
            path = "scripts/settings/equipment/weapon_templates/staff_fireball_fireball.lua",
            post_blob = "18fc3da707e6bf155a12118361b43c176401e916",
        },
    },
    state = {
        display_name = "Game Version 5.6.1",
        id = "5_6_1",
        label_key = "wt_history_state_5_6_1",
    },
}
