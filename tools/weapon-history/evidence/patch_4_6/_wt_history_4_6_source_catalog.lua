-- Source-exact metadata for the bounded Patch 4.6 Hagbane slice (#1436).
--
-- The adjacent boundary contains the official finesse-DoT profile change plus
-- one Ricochet-talent template change, one weapon-diagram presentation root,
-- and one decompiler/refactor symbol. Only the weapon-balance profile change
-- is emitted. Moonfire Bow remains excluded until its global buff/profile/AoE
-- routes can be applied atomically.
return {
    artifacts = {
        _wt_history_4_6_routes_oracle =
            "52902d86ef11f1da7fcf1d10e25f36b1bcbdfe7881221ab863a28f0b75f2e179",
        _wt_history_profiles_4_5_1_rehydrated_generated =
            "c3a0167e80e4980c660b203f0b9aebb62a4672f55ec122f4426f6d7339c2b377",
        _wt_history_profiles_4_5_1_to_4_6_generated =
            "c4fb71879225b85e4021b541206536134b1a943c2112a43c590025bea33973b0",
        _wt_history_profiles_current_6_12_0_generated =
            "b37a67604422766c07a71c675c47d2f6ffeccd1710ca97d7320c50aaf723e3fb",
        _wt_history_profiles_post_4_6_generated =
            "877cb30430d9bb9ffc28903586b9b4d483502790e2c557624da32585864a2351",
        _wt_history_snapshot_4_5_1_rehydrated_generated =
            "048cfd627e4e894277d030615cb3a31f84c5c6d43615270d02dd2fba52846e98",
        _wt_history_snapshot_4_5_1_to_4_6_generated =
            "d26d7fdc14928639d9ea224783a4f5157a8af505ed8b12871996d68c34765945",
    },
    boundary = {
        historical_revision = "0cec9547152a395c4f35f75288f29d8b18b8294f",
        post_revision = "b38754a3bd61983118215359845d5b4fe5005014",
    },
    current = {
        revision = "038498af2b565bcb10bf5ed225638293a7640c83",
    },
    family = {
        display_name = "Kerillian's Hagbane Shortbow",
        id = "hagbane_shortbow",
        label_key = "wt_history_family_hagbane_shortbow",
        official_change_id = "P460-HAGBANE-FINESSE-DOT",
        official_summary =
            "Patch 4.6 increased Hagbane poison damage on finesse hits.",
        setting_id = "wt_history_hagbane_shortbow",
        template = "shortbow_hagbane_template_1",
    },
    official_patch_notes =
        "https://www.vermintide.com/news/patch-46-patch-notes",
    schema = 1,
    source_root_exclusions = {
        {
            path =
                "scripts/settings/equipment/weapon_templates/shortbows_hagbane.lua",
            reason = "presentation_only",
            root = "weapon_diagram",
        },
    },
    source_files = {
        {
            current_blob = "6eba753d985ea80057947ed1ae1a25214204783e",
            historical_blob = "13eeccec333d072261afd1705d4e18c8a411095e",
            path = "scripts/settings/equipment/power_level_templates.lua",
            post_blob = "13eeccec333d072261afd1705d4e18c8a411095e",
        },
        {
            current_blob = "e8330328d0085f6aee09e0495ba88fdc0211d5aa",
            historical_blob = "6653fb47c9ee40611bc0525fd62bc7f927c17fdf",
            path = "scripts/settings/equipment/damage_profile_templates.lua",
            post_blob = "c0b1c1f09996eb009b4a269ddc60db005e862061",
        },
        {
            current_blob = "a7f6e9e9fd9eb3e862c4c7a1ea5babfc5c43a733",
            historical_blob = "a3f8460405a808442bd4f53bc8de424ac934a3cb",
            path =
                "scripts/settings/dlcs/morris/damage_profile_templates_dlc_morris.lua",
            post_blob = "314db1d53cdbd2bd6654df4d87f3244819d22653",
        },
        {
            current_blob = "01d295acab5e5850c83f31939124ca3124edc403",
            historical_blob = "5c5c41c056c16ba0624eca1b4e918eb80c41dd28",
            path =
                "scripts/settings/equipment/damage_profile_templates_dlc_cog.lua",
            post_blob = "5c5c41c056c16ba0624eca1b4e918eb80c41dd28",
        },
        {
            current_blob = "c379649a9dd9366004ac6e2221780f10dcfec581",
            historical_blob = "8722245ebf343116dfd8164b7ff15356e1d37ba8",
            path =
                "scripts/settings/equipment/damage_profile_templates_dlc_woods.lua",
            post_blob = "5ceb7298a2e3f2394b1bef37e2c3d659738eeae3",
        },
        {
            current_blob = "9803627f8e1a4573b6dbea8b11f8836e7460214f",
            historical_blob = "2450220312570da7d14a3741edcf6c4d3ae0ec70",
            path =
                "scripts/settings/equipment/weapon_templates/shortbows_hagbane.lua",
            post_blob = "ca19bd7d9c02702bd82b0f2dddc40fa75bb79fdc",
        },
    },
    state = {
        display_name = "Game Version 4.5.1",
        id = "4_5_1",
        label_key = "wt_history_state_4_5_1",
    },
}
