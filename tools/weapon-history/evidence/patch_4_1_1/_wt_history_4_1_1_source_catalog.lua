-- Source-exact metadata for the Patch 4.1.1 Masterwork Pistol boundary.
--
-- The operation set is selected only from the adjacent 4.0.1 -> post-4.1.1
-- comparison. The selected path is then rehydrated against the current source
-- anchor so later unrelated changes in the same template cannot leak into the
-- historical selector.
return {
    artifacts = {
        _wt_history_snapshot_4_0_1_rehydrated_generated =
            "5cd59760c5af801075c785fd285167768c6d8ecd45b4404b3a2c3cba6ebd156a",
        _wt_history_snapshot_4_0_1_to_4_1_1_generated =
            "9d261910ff282e25ef3e04a706f45600123842e2fd28f2247377a11ec8ab9417",
    },
    boundary = {
        historical_blob = "25a4db5545750c0a5eb590e8d1bfc9882c80d30a",
        historical_revision = "872027662e076477451c8c4bf077473d8ab9e27d",
        post_blob = "b705e7b247242d60a6177682a2c2a89ae5164b2a",
        post_revision = "d5f1fa23c97e0e324db047cabb21faeffa9819bf",
    },
    current = {
        blob = "d68819bb59bdece50b69c9401a9feb5ae238b3cb",
        revision = "25fd7b8433e839b678d1c98a7a9af80918cbc252",
    },
    family = {
        display_name = "Bardin's Masterwork Pistol",
        id = "masterwork_pistol",
        label_key = "wt_history_family_masterwork_pistol",
        setting_id = "wt_history_masterwork_pistol",
        template = "heavy_steam_pistol_template_1",
    },
    official_change_id = "P411-MASTERWORK-PISTOL-AMMO-RELOAD",
    official_patch_notes =
        "https://forums.fatsharkgames.com/t/patch-notes-version-4-1-1/43407",
    official_summary =
        "Patch 4.1.1 stopped Masterwork Pistol reload animations from triggering on ammo pickup.",
    schema = 1,
    source_path =
        "scripts/settings/equipment/weapon_templates/heavy_steam_pistol.lua",
    state = {
        display_name = "Game Version 4.0.1",
        id = "4_0_1",
        label_key = "wt_history_state_4_0_1",
    },
}
