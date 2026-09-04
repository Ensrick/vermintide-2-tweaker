-- Source-exact metadata for the bounded Patch 2.0.10 Sword-and-Dagger slice.
--
-- The adjacent weapon-balance boundary changes exactly two scalar leaves in
-- shared damage profiles used by the two heavy attacks. The source generator
-- projects those values into private current-schema profiles and swaps only
-- the four exact current Sword-and-Dagger routes. Other Patch 2.0.10 files are
-- outside this one-family declared scope.
return {
    artifacts = {
        _wt_history_2_0_10_routes_oracle =
            "b7b29d80d5f3688f08b0e528e00b2d3a56cb72598026954e9fac689241207bde",
        _wt_history_profiles_2_0_9_1_to_2_0_10_generated =
            "b8e7a4e42c68dbfddd9b20564fbae5851bd7201a93689b8a669f799889d8afba",
        _wt_history_profiles_current_6_12_1_generated =
            "7eb51fc267d42212bef2ab5bd07211288d9256e4dd7783094e714550dc88aeb2",
        _wt_history_profiles_post_2_0_10_generated =
            "f40fc0505834a1e15bbe43d298cef97486ab35d1adb4d8bd144ac6c453b22678",
    },
    boundary = {
        historical_revision = "90c7c21adb7aa2b7de5fcdca5094727895fbeb1a",
        post_revision = "67d593c4f98653e1d511105b6adeebb5d6619c58",
    },
    current = {
        revision = "25fd7b8433e839b678d1c98a7a9af80918cbc252",
    },
    exclusions = {
        {
            id = "outside_sword_and_dagger_family",
            reason = "all other adjacent Patch 2.0.10 files and leaves are outside the official Sword-and-Dagger heavy-attack fix",
        },
        {
            id = "shared_profile_consumers",
            reason = "the historical values are exposed only through private profiles on the exact Sword-and-Dagger routes; shared native profiles remain current and immutable",
        },
    },
    family = {
        display_name = "Kerillian's Sword and Dagger",
        id = "sword_and_dagger",
        label_key = "wt_history_family_sword_and_dagger",
        official_change_id = "P2010-SD-HEAVY-PROFILES",
        official_summary =
            "Patch 2.0.10 corrected the Sword-and-Dagger second-heavy damage behavior by exchanging the two heavy-profile melee boost values.",
        setting_id = "wt_history_sword_and_dagger",
        template = "dual_wield_sword_dagger_template_1",
    },
    official_patch_notes =
        "https://forums.fatsharkgames.com/t/vermintide-2-patch-2-0-10/36215",
    schema = 1,
    source_files = {
        {
            current_blob = "6eba753d985ea80057947ed1ae1a25214204783e",
            historical_blob = "f9643cb2701d0a8bc5df8f9ea103a0ce8a528d67",
            path = "scripts/settings/equipment/power_level_templates.lua",
            post_blob = "f9643cb2701d0a8bc5df8f9ea103a0ce8a528d67",
        },
        {
            current_blob = "e8330328d0085f6aee09e0495ba88fdc0211d5aa",
            historical_blob = "44ddcd9af0bb0df90bee614d102cdb6d99a6881f",
            path = "scripts/settings/equipment/damage_profile_templates.lua",
            post_blob = "a6d3544ef2368a218661fd457468c7f9502bed31",
        },
        {
            current_blob = "62d57cc3537ef6c7f78a40a8988027f0b527c8d9",
            historical_blob = "c23af26d0557f5b29e52cafa72c52562da0a6f56",
            path = "scripts/settings/equipment/weapon_templates/dual_wield_sword_dagger.lua",
            post_blob = "c23af26d0557f5b29e52cafa72c52562da0a6f56",
        },
    },
    current_only_profile_files = {
        {
            current_blob = "a7f6e9e9fd9eb3e862c4c7a1ea5babfc5c43a733",
            path = "scripts/settings/dlcs/morris/damage_profile_templates_dlc_morris.lua",
        },
        {
            current_blob = "01d295acab5e5850c83f31939124ca3124edc403",
            path = "scripts/settings/equipment/damage_profile_templates_dlc_cog.lua",
        },
        {
            current_blob = "c379649a9dd9366004ac6e2221780f10dcfec581",
            path = "scripts/settings/equipment/damage_profile_templates_dlc_woods.lua",
        },
    },
    state = {
        display_name = "Game Version 2.0.9.1",
        id = "2_0_9_1",
        label_key = "wt_history_state_2_0_9_1",
    },
}
