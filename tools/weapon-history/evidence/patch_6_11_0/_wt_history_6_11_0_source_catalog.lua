-- Source-exact metadata for the bounded Patch 6.11.0 Longbow, shared
-- one-handed Hammer/Mace, and Kerillian Swiftbow boundary.
--
-- The adjacent evaluator exposes the authored aim_zoom_delay change through
-- both evaluated Longbow templates. They are one gameplay family and must be
-- selected atomically so the tutorial clone cannot drift from the normal bow.
-- The Swiftbow source exports exactly one template whose adjacent delta is the
-- single ammo_data.max_ammo leaf named by the official patch note.
return {
    artifacts = {
        _wt_history_snapshot_6_10_0_hammer_priest_rehydrated_generated =
            "8f5ced37c8bf71f9b50d5e119340ab65e03fce7f398b835e3e45e6692b51e11d",
        _wt_history_snapshot_6_10_0_hammer_priest_to_6_11_0_generated =
            "78c82bed0bc8104360d18aaba020df87d639307ee868b46b39ad558acd003d8f",
        _wt_history_snapshot_6_10_0_hammers_rehydrated_generated =
            "2f496f368a86f76467eb343c504981f009e5e9865ea5d5cfa224027b5073d6fa",
        _wt_history_snapshot_6_10_0_hammers_to_6_11_0_generated =
            "8d1eb9ecc1466a8fa8aed558b74bf4a034cfc57157744ae482caadffd58bffa1",
        _wt_history_snapshot_6_10_0_rehydrated_generated =
            "40a209e92700b23f39dea9ec0597a023ad9a78b97415d82baff8b55eaa5c3251",
        _wt_history_snapshot_6_10_0_swiftbow_rehydrated_generated =
            "baab8cbfa8b5c1b30a388a35273429fcfbb2717d64f7ed2f557535ef8b75f3e1",
        _wt_history_snapshot_6_10_0_swiftbow_to_6_11_0_generated =
            "a68dec5573e30ec9aa23dc42ff9d8da997fa17cd8883249bc42d9c21b19dcaef",
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
        revision = "25fd7b8433e839b678d1c98a7a9af80918cbc252",
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
    hammer_family = {
        display_name =
            "One-handed Hammer/Mace (Kruber, Bardin, and Saltzpyre)",
        id = "one_handed_hammer_shared",
        label_key = "wt_history_family_one_handed_hammer_shared",
        setting_id = "wt_history_one_handed_hammer_shared",
        templates = {
            "one_handed_hammer_template_1",
            "one_handed_hammer_template_2",
            "one_handed_hammer_priest_template",
        },
    },
    hammer_official_change_id = "P6110-1HH-BLOCK-DODGE",
    hammer_official_summary =
        "Patch 6.11.0 increased the effective block angle and dodge count of shared one-handed Hammers and Maces.",
    hammer_sources = {
        {
            current_blob = "a67eb83ad27bcb86f0b88f52dcf8d4a5c8650c6d",
            evidence_stem = "hammers",
            historical_blob = "2a6b000b2d322fa980c4ec2262dc4e36599af9eb",
            path =
                "scripts/settings/equipment/weapon_templates/1h_hammers.lua",
            post_blob = "a67eb83ad27bcb86f0b88f52dcf8d4a5c8650c6d",
            templates = {
                "one_handed_hammer_template_1",
                "one_handed_hammer_template_2",
            },
        },
        {
            current_blob = "dbea759457f3949b685e9e98dfd98cf4063de488",
            evidence_stem = "hammer_priest",
            historical_blob = "abc4699a266616fda0d5f9bbb81a665efac7c7e5",
            path =
                "scripts/settings/equipment/weapon_templates/1h_hammers_priest.lua",
            post_blob = "dbea759457f3949b685e9e98dfd98cf4063de488",
            templates = {
                "one_handed_hammer_priest_template",
            },
        },
    },
    official_change_id = "P6110-KRUBER-LONGBOW-AUTOZOOM",
    official_patch_notes =
        "https://forums.fatsharkgames.com/t/weapon-balance-update-patch-6-11-0-patch-notes/121528",
    official_summary =
        "Patch 6.11.0 reduced the wait time before Kruber's Longbow automatically zooms.",
    schema = 2,
    source_path =
        "scripts/settings/equipment/weapon_templates/longbows_empire.lua",
    state = {
        display_name = "Game Version 6.10.0",
        id = "6_10_0",
        label_key = "wt_history_state_6_10_0",
    },
    swiftbow_family = {
        display_name = "Kerillian's Swiftbow",
        id = "kerillian_swiftbow",
        label_key = "wt_history_family_kerillian_swiftbow",
        setting_id = "wt_history_kerillian_swiftbow",
        templates = {
            "shortbow_template_1",
        },
    },
    swiftbow_official_change_id = "P6110-KERILLIAN-SWIFTBOW-MAX-AMMO",
    swiftbow_official_summary =
        "Patch 6.11.0 increased the maximum ammunition of Kerillian's Swiftbow.",
    swiftbow_source = {
        current_blob = "67e3fa824500fb0129591d0ec698c8a872974623",
        evidence_stem = "swiftbow",
        historical_blob = "8e2a9fc4338e456e8f40d4c1d4578d2b2ecd185e",
        path = "scripts/settings/equipment/weapon_templates/shortbows.lua",
        post_blob = "67e3fa824500fb0129591d0ec698c8a872974623",
        templates = {
            "shortbow_template_1",
        },
    },
    swiftbow_state = {
        display_name = "Game Version 6.10.0 (Ammunition Only)",
        id = "6_10_0_swiftbow_ammunition",
        label_key = "wt_history_state_6_10_0_swiftbow_ammunition",
    },
}
