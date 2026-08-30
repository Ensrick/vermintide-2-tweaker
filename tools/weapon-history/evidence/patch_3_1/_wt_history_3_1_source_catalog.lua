-- Source-exact metadata for the bounded Patch 3.1 weapon-history boundary.
--
-- Each adjacent pre-3.1 -> 3.1 comparison selects exactly one scalar leaf.
-- The selectors deliberately project only those patch deltas over the current
-- source anchor; they are not complete Game 3.0 baselines. The current-only
-- Versus Blunderbuss template remains explicitly outside the adjacent family.
return {
    artifacts = {
        _wt_history_snapshot_pre_3_1_rehydrated_generated =
            "7563d45d92bafbcc8be35cc8b5130ed59a8520b8fc4a7aa1e9f372aac9020c14",
        _wt_history_snapshot_pre_3_1_to_3_1_generated =
            "63047d1c57551eca5cb46763d91ada62e9ae2d0a945232e591c7e4500dde5d76",
        _wt_history_snapshot_pre_3_1_tuskgor_rehydrated_generated =
            "6b5030dc1316a6080f1ae579d3beed3cff637d64d621d8d10701c6add6f9f5d3",
        _wt_history_snapshot_pre_3_1_tuskgor_to_3_1_generated =
            "1670075b4ba9072a0f1226152575d1c598d7efb572929680edc3e8b8271c6c95",
    },
    boundary = {
        historical_revision = "c96aa3858011ecd557d55d80b66fe3bb8342eeb2",
        post_revision = "3f0e3ba442d8dcafb8b5f829ff6c2a95ae24ae63",
    },
    changes = {
        {
            current_blob = "87dca4018c18051d653a80b7aff501ed9815a5d0",
            family = {
                display_name = "Kruber's Blunderbuss",
                id = "kruber_blunderbuss",
                label_key = "wt_history_family_kruber_blunderbuss",
                setting_id = "wt_history_kruber_blunderbuss",
                template = "blunderbuss_template_1",
            },
            historical_blob = "f8f6ec97a974bd5767c1ccabf9fc593dba785d34",
            official_change_id = "P310-BLUNDERBUSS-MAX-AMMO",
            official_summary =
                "Patch 3.1 increased Blunderbuss maximum ammunition from 12 to 16.",
            post_blob = "5370ab322355f8066377779aed1fed8e00a864ba",
            source_path =
                "scripts/settings/equipment/weapon_templates/blunderbusses.lua",
        },
        {
            current_blob = "7575b5035a40d9957514667538d253af46e18c9a",
            family = {
                display_name = "Kruber's Tuskgor Spear",
                id = "tuskgor_spear",
                label_key = "wt_history_family_tuskgor_spear",
                setting_id = "wt_history_tuskgor_spear",
                template = "two_handed_heavy_spears_template",
            },
            historical_blob = "bdd5a9bed6cf3e4a826206318a090cc198ccf7de",
            official_change_id = "P310-TUSKGOR-BLOCK-COST",
            official_summary =
                "Patch 3.1 changed the Tuskgor Spear from the shield block-cost modifier to the normal block-cost modifier.",
            post_blob = "5b0175fdfb69412fe8daa76180238ca399768b3a",
            source_path =
                "scripts/settings/equipment/weapon_templates/2h_heavy_spears.lua",
        },
    },
    current = {
        revision = "038498af2b565bcb10bf5ed225638293a7640c83",
    },
    exclusions = {
        {
            id = "current_only_versus_template",
            reason = "blunderbuss_template_1_vs is absent from both adjacent revisions and is not part of the source-proven Patch 3.1 delta",
            template = "blunderbuss_template_1_vs",
        },
    },
    official_patch_notes = "https://www.vermintide.com/news/patch-31",
    schema = 2,
    state = {
        display_name = "Pre-Patch 3.1 (3.0.x source) — bounded patch delta",
        id = "pre_3_1_delta",
        label_key = "wt_history_state_pre_3_1_delta",
    },
}
