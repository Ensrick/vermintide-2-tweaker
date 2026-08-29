-- Source-exact metadata for the Patch 6.8 Kerillian Greatsword boundary.
--
-- The operation set is selected only from the adjacent 6.7.2 -> 6.8.1
-- comparison. The selected path is then rehydrated against the current source
-- anchor so later unrelated changes in the same template cannot leak into the
-- historical selector.
return {
    artifacts = {
        _wt_history_snapshot_6_7_2_rehydrated_generated =
            "0c2733d84dde3525a1c5475fc55c9a0b3922f62b90ac2caf802f40b2e651cd19",
        _wt_history_snapshot_6_7_2_to_6_8_1_generated =
            "f088f7130845818d3e5652b8d13d26a25cc74f9d772517dde66e173361c70fcb",
    },
    boundary = {
        historical_blob = "be321d9239d7c0200102f005785587fd5d2dbf3c",
        historical_revision = "b7c15fc61a3b34fae7d1e2de47f52198e26851ce",
        post_blob = "f0a7b263ddc481445608ab269d69d260946aa891",
        post_revision = "447f4eb49921ba08fbbbb945609ce2b9891f4898",
    },
    current = {
        blob = "9d95add8cf0f06d1c52042e13d5f83912b7f3dd9",
        revision = "038498af2b565bcb10bf5ed225638293a7640c83",
    },
    family = {
        display_name = "Kerillian's Greatsword",
        id = "elf_greatsword",
        label_key = "wt_history_family_elf_greatsword",
        setting_id = "wt_history_elf_greatsword",
        template = "two_handed_swords_wood_elf_template",
    },
    official_change_id = "P680-ELF-GS-H1-RANGE",
    official_patch_notes =
        "https://forums.fatsharkgames.com/t/geheimnisnacht-and-the-skull-of-blosphoros-return-patch-6-8-0-hotfix-6-8-1/113884",
    official_summary =
        "Patch 6.8 increased the distance of Kerillian Greatsword's first Heavy Attack.",
    schema = 1,
    source_path =
        "scripts/settings/equipment/weapon_templates/2h_swords_wood_elf.lua",
    state = {
        display_name = "Game Version 6.7.2",
        id = "6_7_2",
        label_key = "wt_history_state_6_7_2",
    },
}
