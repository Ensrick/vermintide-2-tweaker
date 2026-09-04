-- Source-exact metadata for the Patch 3.2 Kerillian One-Handed Axe boundary.
--
-- The operation set is selected only from the adjacent 3.1.0 -> 3.2 source
-- comparison. The selected path is then rehydrated against the current source
-- anchor so later unrelated changes in the same template cannot leak into the
-- historical selector.
return {
    artifacts = {
        _wt_history_snapshot_3_1_0_rehydrated_generated =
            "9b551c384631be623f19b35a728eeb4cc6aa5c052a78aa996d05c65d4c677362",
        _wt_history_snapshot_3_1_0_to_3_2_0_generated =
            "88fb8a04e3b2b2d95fd3afe59416b087a1d3a6652a1469274447eca5ae9ab629",
    },
    boundary = {
        historical_blob = "d8a526f548596c8915826352cd7f1cb9a03486f8",
        historical_revision = "3f0e3ba442d8dcafb8b5f829ff6c2a95ae24ae63",
        post_blob = "4f4192fc3ba292fd071b2b09d9f2a32dc53d3547",
        post_revision = "98965ca6e57e46d5a161f7262471b2124e0d0823",
    },
    current = {
        blob = "25c9ac9c38d51cb7b588c20d46e2773ca67149eb",
        revision = "25fd7b8433e839b678d1c98a7a9af80918cbc252",
    },
    family = {
        display_name = "Kerillian's One-handed Axe",
        id = "elf_one_handed_axe",
        label_key = "wt_history_family_elf_one_handed_axe",
        setting_id = "wt_history_elf_one_handed_axe",
        template = "we_one_hand_axe_template",
    },
    official_change_id = "P320-ELF1HA-BOPP-CRIT",
    official_patch_notes =
        "https://www.vermintide.com/news/patch-32-quality-of-life-update",
    official_summary =
        "Patch 3.2 increased Kerillian One-Handed Axe's push-follow-up critical chance.",
    schema = 1,
    source_path =
        "scripts/settings/equipment/weapon_templates/1h_axes_wood_elf.lua",
    state = {
        display_name = "Game Version 3.1.0",
        id = "3_1_0",
        label_key = "wt_history_state_3_1_0",
    },
}
