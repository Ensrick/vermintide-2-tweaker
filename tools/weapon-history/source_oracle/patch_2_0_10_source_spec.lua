-- Independent source-oracle specification for the bounded Patch 2.0.10
-- Kerillian Sword-and-Dagger history slice (#1436).
return {
    schema = 1,
    oracle_id = "wt_patch_2_0_10_sword_and_dagger_source_oracle_v1",
    revisions = {
        current = "038498af2b565bcb10bf5ed225638293a7640c83",
        ["2_0_9_1"] = "90c7c21adb7aa2b7de5fcdca5094727895fbeb1a",
    },
    families = {
        {
            id = "sword_and_dagger",
            templates = {
                dual_wield_sword_dagger_template_1 =
                    "scripts/settings/equipment/weapon_templates/dual_wield_sword_dagger.lua",
            },
            states = {
                ["2_0_9_1"] = {
                    "light_slashing_linesman_dual_medium",
                    "light_slashing_smiter_stab_dual",
                },
            },
        },
    },
    profile_source_paths = {
        light_slashing_linesman_dual_medium =
            "scripts/settings/equipment/damage_profile_templates.lua",
        light_slashing_smiter_stab_dual =
            "scripts/settings/equipment/damage_profile_templates.lua",
    },
    extra_source_paths = {
        "scripts/settings/equipment/power_level_templates.lua",
    },
}
