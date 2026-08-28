-- Independent source-oracle specification for Tweaker: Weapons #1436.
--
-- This file is deliberately not derived from the runtime catalog. It is the
-- reviewed extraction boundary used to query immutable decompiled-source Git
-- objects and to decide which source-exact family/state rows are admissible.

local revisions = {
    current = "c5e4968b1fbb00c49884e56d640ef990a9c04dd0",
    ["5_1_1"] = "8224b4436e20905a6ba463cb28fa2d7771bb2330",
    ["5_2_0"] = "4f496970e2e7514bef7d612ab91331aa065d5e52",
    ["5_2_3"] = "cdc0a86e24e017119e6d6998870bf76f6e76e868",
}

local families = {
    {
        id = "coruscation_staff",
        templates = {
            bw_deus_01_template_1 = "scripts/settings/equipment/weapon_templates/bw_deus_01.lua",
        },
        states = {
            ["5_1_1"] = {
                "staff_magma", "geiser_magma", "geiser_magma_no_damage",
            },
        },
    },
    {
        id = "dual_daggers",
        templates = {
            dual_wield_daggers_template_1 = "scripts/settings/equipment/weapon_templates/dual_wield_daggers.lua",
        },
        states = { ["5_1_1"] = {}, ["5_2_0"] = { "light_slashing_smiter_stab_dual" } },
    },
    {
        id = "one_handed_sword_shared",
        templates = {
            one_handed_swords_template_1 = "scripts/settings/equipment/weapon_templates/1h_swords.lua",
        },
        states = {
            ["5_1_1"] = {
                "light_slashing_linesman_finesse", "medium_slashing_tank_1h_finesse",
            },
            ["5_2_0"] = { "medium_slashing_tank_1h_finesse" },
        },
    },
    {
        id = "two_handed_sword_shared",
        templates = {
            two_handed_swords_template_1 = "scripts/settings/equipment/weapon_templates/2h_swords.lua",
        },
        states = { ["5_1_1"] = { "heavy_slashing_linesman" } },
    },
    {
        id = "one_handed_axe_shared",
        templates = {
            one_hand_axe_template_1 = "scripts/settings/equipment/weapon_templates/1h_axes.lua",
            one_hand_axe_template_2 = "scripts/settings/equipment/weapon_templates/1h_axes.lua",
        },
        states = {
            ["5_1_1"] = { "medium_slashing_smiter_1h_axe" },
            ["5_2_0"] = {},
        },
    },
    {
        id = "one_handed_hammer_shared",
        templates = {
            one_handed_hammer_template_1 = "scripts/settings/equipment/weapon_templates/1h_hammers.lua",
            one_handed_hammer_template_2 = "scripts/settings/equipment/weapon_templates/1h_hammers.lua",
            one_handed_hammer_priest_template = "scripts/settings/equipment/weapon_templates/1h_hammers_priest.lua",
        },
        states = { ["5_1_1"] = {}, ["5_2_0"] = {} },
    },
    {
        id = "javelin",
        templates = {
            javelin_template = "scripts/settings/equipment/weapon_templates/javelin.lua",
        },
        states = {
            ["5_1_1"] = {
                "medium_javelin_smiter_stab", "medium_javelin_smiter_stab_bleed",
                "heavy_javelin_smiter_stab_bleed", "thrown_javelin",
            },
        },
    },
    {
        id = "elf_one_handed_axe",
        templates = {
            we_one_hand_axe_template = "scripts/settings/equipment/weapon_templates/1h_axes_wood_elf.lua",
        },
        states = {
            ["5_1_1"] = { "medium_slashing_smiter_1h_axe" },
            ["5_2_0"] = {},
        },
    },
    {
        id = "kruber_sword_and_shield",
        templates = {
            one_handed_sword_shield_template_1 = "scripts/settings/equipment/weapon_templates/1h_swords_shield.lua",
        },
        states = { ["5_1_1"] = {}, ["5_2_0"] = {} },
    },
    {
        id = "falchion",
        templates = {
            one_hand_falchion_template_1 = "scripts/settings/equipment/weapon_templates/1h_falchions.lua",
        },
        states = { ["5_2_0"] = {}, ["5_2_3"] = {} },
    },
    {
        id = "crowbill",
        templates = {
            one_handed_crowbill = "scripts/settings/equipment/weapon_templates/1h_crowbills.lua",
        },
        states = { ["5_2_0"] = {}, ["5_2_3"] = {} },
    },
    {
        id = "one_handed_flail",
        templates = {
            one_handed_flail_template_1 = "scripts/settings/equipment/weapon_templates/1h_flails.lua",
        },
        states = { ["5_2_0"] = {} },
    },
    {
        id = "sword_and_dagger",
        templates = {
            dual_wield_sword_dagger_template_1 = "scripts/settings/equipment/weapon_templates/dual_wield_sword_dagger.lua",
        },
        states = { ["5_2_0"] = {} },
    },
    {
        id = "masterwork_pistol",
        templates = {
            heavy_steam_pistol_template_1 = "scripts/settings/equipment/weapon_templates/heavy_steam_pistol.lua",
        },
        states = { ["5_2_0"] = { "shot_sniper_pistol" } },
    },
}

local rejected = {
    ["javelin_template|actions.action_one.heavy_stab.allowed_chain_actions"] = true,
    ["javelin_template|actions.action_one.throw_charged.anim_event_infinite_ammo_3p"] = true,
    ["javelin_template|actions.action_one.throw_charged.anim_event_last_ammo_3p"] = true,
    ["javelin_template|destroy_indexed_projectiles"] = true,
    ["heavy_steam_pistol_template_1|actions.action_one.default.allowed_chain_actions"] = true,
    ["one_hand_falchion_template_1|actions.action_one.light_attack_bopp.allowed_chain_actions"] = true,
    ["one_handed_swords_template_1|actions.action_one.light_attack_bopp.allowed_chain_actions"] = true,
    ["one_handed_sword_shield_template_1|actions.action_two.default.anim_event_3p"] = true,
}

return {
    schema = 1,
    oracle_id = "wt_patch_5_2_source_oracle_v1",
    revisions = revisions,
    families = families,
    rejected = rejected,
    snapshot_files = {
        ["5_1_1"] = {
            "_wt_history_snapshot_5_1_1_part_1_generated.lua",
            "_wt_history_snapshot_5_1_1_part_2_generated.lua",
        },
        ["5_2_0"] = {
            "_wt_history_snapshot_5_2_0_part_1_generated.lua",
            "_wt_history_snapshot_5_2_0_part_2_generated.lua",
        },
        ["5_2_3"] = { "_wt_history_snapshot_5_2_3_generated.lua" },
    },
    profile_files = {
        ["5_1_1"] = {
            "_wt_history_profiles_5_1_1_generated.lua",
            "_wt_history_profiles_5_1_1_dlc_generated.lua",
        },
        ["5_2_0"] = {
            "_wt_history_profiles_5_2_0_generated.lua",
            "_wt_history_profiles_5_2_0_dlc_generated.lua",
        },
        ["5_2_3"] = {},
    },
    profile_source_paths = {
        light_slashing_smiter_stab_dual = "scripts/settings/equipment/damage_profile_templates.lua",
        light_slashing_linesman_finesse = "scripts/settings/equipment/damage_profile_templates.lua",
        medium_slashing_tank_1h_finesse = "scripts/settings/equipment/damage_profile_templates.lua",
        heavy_slashing_linesman = "scripts/settings/equipment/damage_profile_templates.lua",
        medium_slashing_smiter_1h_axe = "scripts/settings/equipment/damage_profile_templates.lua",
        staff_magma = "scripts/settings/dlcs/morris/damage_profile_templates_dlc_morris.lua",
        geiser_magma = "scripts/settings/dlcs/morris/damage_profile_templates_dlc_morris.lua",
        geiser_magma_no_damage = "scripts/settings/dlcs/morris/damage_profile_templates_dlc_morris.lua",
        medium_javelin_smiter_stab = "scripts/settings/equipment/damage_profile_templates_dlc_woods.lua",
        medium_javelin_smiter_stab_bleed = "scripts/settings/equipment/damage_profile_templates_dlc_woods.lua",
        heavy_javelin_smiter_stab_bleed = "scripts/settings/equipment/damage_profile_templates_dlc_woods.lua",
        thrown_javelin = "scripts/settings/equipment/damage_profile_templates_dlc_woods.lua",
        shot_sniper_pistol = "scripts/settings/equipment/damage_profile_templates_dlc_cog.lua",
    },
    -- Historical source profiles needed only as derivation donors are not
    -- required to appear in a current weapon-template damage_profile field.
    source_only_profiles = {
        ["coruscation_staff|5_1_1|geiser_magma"] = true,
    },
    extra_source_paths = {
        "scripts/settings/equipment/damage_profile_templates.lua",
        "scripts/settings/equipment/damage_profile_templates_dlc_cog.lua",
        "scripts/settings/equipment/damage_profile_templates_dlc_woods.lua",
        "scripts/settings/dlcs/morris/damage_profile_templates_dlc_morris.lua",
        "scripts/settings/dlcs/morris/morris_buff_settings.lua",
        "scripts/settings/dlcs/morris/player_unit_status_settings_morris.lua",
    },
    expected = {
        families = 14,
        family_states = 22,
        raw_snapshot_operations = { ["5_1_1"] = 97, ["5_2_0"] = 82, ["5_2_3"] = 11 },
        rejected_occurrences = { ["5_1_1"] = 6, ["5_2_0"] = 8, ["5_2_3"] = 2 },
        emitted_snapshot_operations = 174,
        global_operations = 8,
        emitted_operations = 182,
        unique_source_profiles = 13,
        derived_profiles = 1,
        source_profile_routes = 14,
        family_profile_references = 15,
    },
}
