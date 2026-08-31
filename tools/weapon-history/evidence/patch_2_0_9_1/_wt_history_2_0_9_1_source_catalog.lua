-- Source-exact metadata for the Patch 2.0.9.1 Kruber Halberd boundary.
--
-- The adjacent comparison selects only the push-follow-up chain repaired by
-- Patch 2.0.9.1. The selected leaves are then rehydrated against the current
-- source anchor so later Halberd changes cannot leak into this selector.
return {
    artifacts = {
        _wt_history_snapshot_2_0_9_rehydrated_generated =
            "53a9ade7bac742fbb2f81113bf6a4657456068f5c75588d038c03f46c4f9a28d",
        _wt_history_snapshot_2_0_9_to_2_0_9_1_generated =
            "845a4d0af283c61cfa1c63cb923c94b07d36c7c4f48be672ecaaab2701bc909c",
    },
    boundary = {
        historical_blob = "220f6834ce7e54eaa3264792786fcdf4bb0c4198",
        historical_revision = "6d41bab482ac64ebebc5c8bba2c3a47954952af9",
        post_blob = "b890247081ef2a8a61579fe5f6c85e68cc0d6563",
        post_revision = "90c7c21adb7aa2b7de5fcdca5094727895fbeb1a",
    },
    current = {
        blob = "68256d553f364ca97a7dabccb617020afe5a0064",
        revision = "038498af2b565bcb10bf5ed225638293a7640c83",
    },
    family = {
        display_name = "Kruber's Halberd",
        id = "kruber_halberd",
        label_key = "wt_history_family_kruber_halberd",
        setting_id = "wt_history_kruber_halberd",
        template = "two_handed_halberds_template_1",
    },
    official_change_id = "P2091-HALBERD-PUSH-OVERHEAD",
    official_patch_notes =
        "https://forums.fatsharkgames.com/t/vermintide-2-patch-2-0-9-1/36058",
    official_summary =
        "Patch 2.0.9.1 restored the Halberd push-follow-up overhead attack.",
    schema = 1,
    source_path =
        "scripts/settings/equipment/weapon_templates/halberds.lua",
    state = {
        display_name = "Game Version 2.0.9",
        id = "2_0_9",
        label_key = "wt_history_state_2_0_9",
    },
}
