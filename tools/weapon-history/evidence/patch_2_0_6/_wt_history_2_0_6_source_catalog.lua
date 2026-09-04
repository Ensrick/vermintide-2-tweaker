-- Source-exact metadata for the bounded Patch 2.0.6 Handgun boundary.
--
-- The historical source exposes one shared Handgun template. Current source
-- clones that same gameplay table for Kruber and Bardin, then changes only
-- Bardin's presentation fields. The generator proves that immutable clone
-- relationship before projecting the three adjacent leaves onto both current
-- gameplay templates.
return {
    artifacts = {
        _wt_history_snapshot_2_0_5_rehydrated_generated =
            "9823425cec31b95fa8af557782b702cd54efe92bc968d76885c3c497cb12d079",
        _wt_history_snapshot_2_0_5_to_2_0_6_generated =
            "f62c8c615225d5460072b1bee65c434bdc633f795b8b06f6c89b8d8aba25df2f",
    },
    boundary = {
        historical_blob = "9068877534daa29eb050d51cf548c7677a2000b3",
        historical_revision = "b5a93414e883825f69c61eb3e90e73f52d6c2e80",
        post_blob = "a04a5e7579702c75f7ccbfc4dde33363b1e13c84",
        post_revision = "750fa8f8a393d807f2f7205dfed4b60b6abe3c46",
    },
    current = {
        blob = "547f75e51dbf656184ed351ecd261714db4f25fe",
        revision = "25fd7b8433e839b678d1c98a7a9af80918cbc252",
    },
    exclusions = {
        {
            id = "adjacent_key_order_churn",
            reason = "all other movement in handguns.lua is table-key ordering with no semantic value change",
        },
        {
            id = "unrelated_dot_network_sync",
            reason = "the adjacent weapons.lua change fixes damage-over-time network synchronization and is outside the Handgun balance boundary",
        },
        {
            id = "current_versus_clones",
            reason = "handgun_template_1_vs and handgun_template_2_vs do not exist at the adjacent boundary and are not projected",
        },
    },
    family = {
        display_name = "Kruber's and Bardin's Handguns",
        id = "handgun_shared",
        label_key = "wt_history_family_handgun_shared",
        setting_id = "wt_history_handgun_shared",
        source_template = "handgun_template_1",
        templates = {
            "handgun_template_1",
            "handgun_template_2",
        },
    },
    official_change_id = "P206-HANDGUN-SHIELD-PIERCE",
    official_patch_notes =
        "https://forums.fatsharkgames.com/t/vermintide-2-patch-2-0-6-1/35277",
    official_summary =
        "Patch 2.0.6 made Handgun hipfire shots pierce shields while preserving the adjacent aimed-fire penetration behavior.",
    schema = 1,
    source_path =
        "scripts/settings/equipment/weapon_templates/handguns.lua",
    state = {
        display_name = "Game Version 2.0.5",
        id = "2_0_5",
        label_key = "wt_history_state_2_0_5",
    },
}
