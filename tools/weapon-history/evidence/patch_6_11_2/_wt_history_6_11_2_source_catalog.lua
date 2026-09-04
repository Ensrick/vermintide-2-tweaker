-- Source-exact metadata for the Hotfix 6.11.2 weapon-balance reversions.
--
-- Each operation set is selected only from the adjacent 6.11.1 -> 6.11.2
-- comparison. The selected paths are then rehydrated against the current source
-- anchor so later unrelated changes in either template cannot leak into the
-- historical selector.
return {
    artifacts = {
        _wt_history_snapshot_6_11_1_axe_falchion_rehydrated_generated =
            "e12c444ba28ec368ce44823150ee6496f24d0ed6cbbd3dfc08c4f114bf1c0ff8",
        _wt_history_snapshot_6_11_1_axe_falchion_to_6_11_2_generated =
            "8e3fbd667f3503a5d27bdd3b7588f0b5405ceddc6f3545db85cf8b1d5ad0c3c3",
        _wt_history_snapshot_6_11_1_rehydrated_generated =
            "5479c3a8d57e60d6716182923731087088d9146394a39674f943a7b21d4405b2",
        _wt_history_snapshot_6_11_1_to_6_11_2_generated =
            "c73b84364a83038ccdd60522b19d654e08519fe706289174253acab74e6716c6",
    },
    boundary = {
        historical_revision = "1a0a4e0caf5c119bfe8d42a4d1bc23b34a7b005e",
        post_revision = "9fbf92c11acfaca5c49f5e40d565b0743a2bdf43",
    },
    current = {
        revision = "25fd7b8433e839b678d1c98a7a9af80918cbc252",
    },
    families = {
        {
            adjacent_artifact =
                "_wt_history_snapshot_6_11_1_to_6_11_2_generated",
            current_blob = "fcfeecee65342ae8b3bb4a75a57e248c3a677b1e",
            display_name = "Sienna's Dagger",
            historical_blob = "656ef0ffac628d707d13adbf3c4a8950aec7fca7",
            id = "sienna_dagger",
            label_key = "wt_history_family_sienna_dagger",
            official_change_id = "P6112-SIENNA-DAGGER-H2",
            official_summary =
                "Hotfix 6.11.2 reverted Sienna's Dagger Heavy Attack 2 to its previous damage profile.",
            operations = {
                {
                    current_value = "medium_burning_smiter_stab_H",
                    historical_value = "dagger_h1_medium_smiter_diag",
                    path = {
                        "actions", "action_one", "heavy_attack_right",
                        "damage_profile",
                    },
                },
            },
            post_blob = "fcfeecee65342ae8b3bb4a75a57e248c3a677b1e",
            rehydrated_artifact =
                "_wt_history_snapshot_6_11_1_rehydrated_generated",
            setting_id = "wt_history_sienna_dagger",
            source_path =
                "scripts/settings/equipment/weapon_templates/1h_dagger_wizard.lua",
            template = "one_handed_daggers_template_1",
        },
        {
            adjacent_artifact =
                "_wt_history_snapshot_6_11_1_axe_falchion_to_6_11_2_generated",
            current_blob = "fae29e68dd3779c66a0e8c09285ded12b33667c5",
            display_name = "Saltzpyre's Axe and Falchion",
            historical_blob = "5d51821f8186ceb111e4ff97dd2b975d159bde4a",
            id = "axe_and_falchion",
            label_key = "wt_history_family_axe_and_falchion",
            official_change_id = "P6112-AXE-FALCHION-H1-H2",
            official_summary =
                "Hotfix 6.11.2 reverted the unintended Axe and Falchion Heavy Attack 1 and 2 profile changes.",
            operations = {
                {
                    current_value = "light_slashing_smiter_dual",
                    historical_value =
                        "axe_falcion_heavy_smiter_vertical_right",
                    path = {
                        "actions", "action_one", "heavy_attack",
                        "damage_profile_right",
                    },
                },
                {
                    current_value = "light_slashing_smiter_dual",
                    historical_value =
                        "axe_falcion_heavy_smiter_vertical_right",
                    path = {
                        "actions", "action_one", "heavy_attack_2",
                        "damage_profile_right",
                    },
                },
            },
            post_blob = "fae29e68dd3779c66a0e8c09285ded12b33667c5",
            rehydrated_artifact =
                "_wt_history_snapshot_6_11_1_axe_falchion_rehydrated_generated",
            setting_id = "wt_history_axe_and_falchion",
            source_path =
                "scripts/settings/equipment/weapon_templates/dual_wield_axe_falchion.lua",
            template = "dual_wield_axe_falchion_template",
        },
    },
    official_patch_notes =
        "https://forums.fatsharkgames.com/t/hotfix-6-11-2-2nd-of-june-hotfix-6-11-3/122090",
    schema = 2,
    state = {
        display_name = "Game Version 6.11.1",
        id = "6_11_1",
        label_key = "wt_history_state_6_11_1",
    },
}
