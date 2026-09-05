-- Source-exact metadata for the Patch 6.6 Deepwood Staff boundary.
--
-- The adjacent 6.5.4 -> 6.6.0 source comparison selects only the three
-- Chaos Warrior with Shield leaves added by the official fix. Those paths
-- are then rehydrated against the 6.11.3 anchor so later Deepwood additions
-- remain outside this historical projection.
return {
    artifacts = {
        _wt_history_snapshot_6_5_4_rehydrated_generated =
            "b06c8114fad35b8d318f42338cd639aaa5d131185200f1bd1145bf89f80145af",
        _wt_history_snapshot_6_5_4_to_6_6_0_generated =
            "c3e97e994ac6cc9da1862fdcd1d494fbdc924daddb039c15d03a9379d5e59121",
    },
    boundary = {
        historical_revision = "5a74a378502353b075cbe0c3abe37da07f1d9bc9",
        post_revision = "877aa9b2720d297e0594f7039773eca610324f5b",
    },
    current = {
        revision = "c5e4968b1fbb00c49884e56d640ef990a9c04dd0",
    },
    family = {
        authority = "server",
        display_name = "Kerillian's Deepwood Staff",
        id = "deepwood_staff",
        label_key = "wt_history_family_deepwood_staff",
        setting_id = "wt_history_deepwood_staff",
        templates = {
            "staff_life",
            "staff_life_vs",
        },
    },
    official_change_id = "P660-DEEPWOOD-BULWARK-LIFT",
    official_patch_notes =
        "https://forums.fatsharkgames.com/t/new-map-the-well-of-dreams-live-now-skulls-in-game-event-patch-6-6-0-hotfix-6-6-1/108063",
    official_summary =
        "Patch 6.6 changed Deepwood Staff lifts on Chaos Warriors with Shields from eight seconds to four seconds.",
    schema = 1,
    source_files = {
        {
            current_blob = "8625739b65e4750ff8735149415b8158ccca68ce",
            historical_blob = "33b16c2f162cf43af0cc7e2451098fd50dc6b1e2",
            path = "scripts/settings/equipment/weapon_templates/staff_life.lua",
            post_blob = "f94e8f3de5334fe8446c43869e946fc1c2f4812e",
        },
        {
            current_blob = "092d2aee259b141e3ddc0cb3779a60dc39b536c0",
            historical_blob = "bd140b12581c0621a82edd735ae9cf7903f54ddc",
            path = "scripts/settings/dlcs/woods/woods_equipment_settings.lua",
            post_blob = "092d2aee259b141e3ddc0cb3779a60dc39b536c0",
        },
    },
    state = {
        display_name = "Game Version 6.5.4",
        id = "6_5_4",
        label_key = "wt_history_state_6_5_4",
    },
}
