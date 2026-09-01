-- Source-exact metadata for the Hotfix 6.11.2 Sienna Dagger boundary.
--
-- The operation set is selected only from the adjacent 6.11.1 -> 6.11.2
-- comparison. The selected path is then rehydrated against the current source
-- anchor so later unrelated changes in the same template cannot leak into the
-- historical selector.
return {
    artifacts = {
        _wt_history_snapshot_6_11_1_rehydrated_generated =
            "5479c3a8d57e60d6716182923731087088d9146394a39674f943a7b21d4405b2",
        _wt_history_snapshot_6_11_1_to_6_11_2_generated =
            "c73b84364a83038ccdd60522b19d654e08519fe706289174253acab74e6716c6",
    },
    boundary = {
        historical_blob = "656ef0ffac628d707d13adbf3c4a8950aec7fca7",
        historical_revision = "1a0a4e0caf5c119bfe8d42a4d1bc23b34a7b005e",
        post_blob = "fcfeecee65342ae8b3bb4a75a57e248c3a677b1e",
        post_revision = "9fbf92c11acfaca5c49f5e40d565b0743a2bdf43",
    },
    current = {
        blob = "fcfeecee65342ae8b3bb4a75a57e248c3a677b1e",
        revision = "038498af2b565bcb10bf5ed225638293a7640c83",
    },
    family = {
        display_name = "Sienna's Dagger",
        id = "sienna_dagger",
        label_key = "wt_history_family_sienna_dagger",
        setting_id = "wt_history_sienna_dagger",
        template = "one_handed_daggers_template_1",
    },
    official_change_id = "P6112-SIENNA-DAGGER-H2",
    official_patch_notes =
        "https://forums.fatsharkgames.com/t/hotfix-6-11-2-2nd-of-june-hotfix-6-11-3/122090",
    official_summary =
        "Hotfix 6.11.2 reverted Sienna's Dagger Heavy Attack 2 to its previous damage profile.",
    schema = 1,
    source_path =
        "scripts/settings/equipment/weapon_templates/1h_dagger_wizard.lua",
    state = {
        display_name = "Game Version 6.11.1",
        id = "6_11_1",
        label_key = "wt_history_state_6_11_1",
    },
}
