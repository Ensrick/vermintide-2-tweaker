-- Source-exact metadata for the Patch 6.11.0 Kruber Longbow boundary.
--
-- The adjacent evaluator exposes the authored aim_zoom_delay change through
-- both evaluated Longbow templates. They are one gameplay family and must be
-- selected atomically so the tutorial clone cannot drift from the normal bow.
return {
    artifacts = {
        _wt_history_snapshot_6_10_0_rehydrated_generated =
            "40a209e92700b23f39dea9ec0597a023ad9a78b97415d82baff8b55eaa5c3251",
        _wt_history_snapshot_6_10_0_to_6_11_0_generated =
            "87b6f190c7beade349cbcb96a869c8bb43c2eba645849b4811bf670230739841",
    },
    boundary = {
        historical_blob = "6408a36495e3c78e9a9ed2dbc91a913c512d9aed",
        historical_revision = "5ff26df11311ba011f3313b9b232ed0d8b64b921",
        post_blob = "b4e374e2d9a2dbc0c25537617163901eeca1fc03",
        post_revision = "abe82ab4ba3e00c22d912093b37234c59f8a00d9",
    },
    current = {
        blob = "a4685fbd52464f3a65ade77776a85a131dea8476",
        revision = "038498af2b565bcb10bf5ed225638293a7640c83",
    },
    family = {
        display_name = "Kruber's Longbow",
        id = "kruber_longbow",
        label_key = "wt_history_family_kruber_longbow",
        setting_id = "wt_history_kruber_longbow",
        templates = {
            "longbow_empire_template",
            "longbow_empire_tutorial_template",
        },
    },
    official_change_id = "P6110-KRUBER-LONGBOW-AUTOZOOM",
    official_patch_notes =
        "https://forums.fatsharkgames.com/t/weapon-balance-update-patch-6-11-0-patch-notes/121528",
    official_summary =
        "Patch 6.11.0 reduced the wait time before Kruber's Longbow automatically zooms.",
    schema = 1,
    source_path =
        "scripts/settings/equipment/weapon_templates/longbows_empire.lua",
    state = {
        display_name = "Game Version 6.10.0",
        id = "6_10_0",
        label_key = "wt_history_state_6_10_0",
    },
}
