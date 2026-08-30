-- Independent source-oracle specification for the bounded Patch 4.6
-- Hagbane history slice (#1436). Moonfire Bow is deliberately excluded until
-- global BuffTemplates routes and live ExplosionTemplates references can be
-- committed as one peer-safe family transaction.
return {
    schema = 1,
    oracle_id = "wt_patch_4_6_hagbane_source_oracle_v1",
    revisions = {
        current = "038498af2b565bcb10bf5ed225638293a7640c83",
        ["4_5_1"] = "0cec9547152a395c4f35f75288f29d8b18b8294f",
    },
    families = {
        {
            id = "hagbane_shortbow",
            templates = {
                shortbow_hagbane_template_1 =
                    "scripts/settings/equipment/weapon_templates/shortbows_hagbane.lua",
            },
            states = {
                ["4_5_1"] = {
                    "shortbow_hagbane",
                    "shortbow_hagbane_charged",
                },
            },
        },
    },
    profile_source_paths = {
        shortbow_hagbane =
            "scripts/settings/equipment/damage_profile_templates.lua",
        shortbow_hagbane_charged =
            "scripts/settings/equipment/damage_profile_templates.lua",
    },
    extra_source_paths = {
        "scripts/settings/equipment/power_level_templates.lua",
    },
}
