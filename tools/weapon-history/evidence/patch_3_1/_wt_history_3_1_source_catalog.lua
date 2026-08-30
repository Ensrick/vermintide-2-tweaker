-- Source-exact metadata for the bounded Patch 3.1 Blunderbuss boundary.
--
-- The adjacent pre-3.1 -> 3.1 comparison selects exactly one scalar leaf. The
-- selector deliberately projects only that patch delta over the current source
-- anchor; it is not a complete Game 3.0 baseline. The current-only Versus
-- template is explicitly outside the adjacent family and remains untouched.
return {
    artifacts = {
        _wt_history_snapshot_pre_3_1_rehydrated_generated =
            "7563d45d92bafbcc8be35cc8b5130ed59a8520b8fc4a7aa1e9f372aac9020c14",
        _wt_history_snapshot_pre_3_1_to_3_1_generated =
            "63047d1c57551eca5cb46763d91ada62e9ae2d0a945232e591c7e4500dde5d76",
    },
    boundary = {
        historical_blob = "f8f6ec97a974bd5767c1ccabf9fc593dba785d34",
        historical_revision = "c96aa3858011ecd557d55d80b66fe3bb8342eeb2",
        post_blob = "5370ab322355f8066377779aed1fed8e00a864ba",
        post_revision = "3f0e3ba442d8dcafb8b5f829ff6c2a95ae24ae63",
    },
    current = {
        blob = "87dca4018c18051d653a80b7aff501ed9815a5d0",
        revision = "038498af2b565bcb10bf5ed225638293a7640c83",
    },
    exclusions = {
        {
            id = "current_only_versus_template",
            reason = "blunderbuss_template_1_vs is absent from both adjacent revisions and is not part of the source-proven Patch 3.1 delta",
            template = "blunderbuss_template_1_vs",
        },
    },
    family = {
        display_name = "Kruber's Blunderbuss",
        id = "kruber_blunderbuss",
        label_key = "wt_history_family_kruber_blunderbuss",
        setting_id = "wt_history_kruber_blunderbuss",
        template = "blunderbuss_template_1",
    },
    official_change_id = "P310-BLUNDERBUSS-MAX-AMMO",
    official_patch_notes = "https://www.vermintide.com/news/patch-31",
    official_summary = "Patch 3.1 increased Blunderbuss maximum ammunition from 12 to 16.",
    schema = 1,
    source_path = "scripts/settings/equipment/weapon_templates/blunderbusses.lua",
    state = {
        display_name = "Pre-Patch 3.1 (3.0.x source) — bounded patch delta",
        id = "pre_3_1_delta",
        label_key = "wt_history_state_pre_3_1_delta",
    },
}
