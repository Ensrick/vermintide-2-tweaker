-- Generated from decompiled source revisions; do not hand-edit.
return {
    new_revision = "c5e4968b",
    old_revision = "4f496970",
    records = {
        [1] = {
            ops = {
                [1] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "heavy_attack",
                        [4] = "additional_critical_strike_chance",
                    },
                    unset = false,
                    value = 0,
                },
                [2] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "heavy_attack",
                        [4] = "damage_profile_left",
                    },
                    unset = false,
                    value = "light_slashing_smiter_stab_dual",
                },
                [3] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "heavy_attack",
                        [4] = "damage_profile_right",
                    },
                    unset = false,
                    value = "light_slashing_smiter_stab_dual",
                },
                [4] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "heavy_attack_stab",
                        [4] = "additional_critical_strike_chance",
                    },
                    unset = false,
                    value = 0,
                },
                [5] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "heavy_attack_stab",
                        [4] = "damage_profile_left",
                    },
                    unset = false,
                    value = "light_slashing_smiter_stab_dual",
                },
                [6] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "heavy_attack_stab",
                        [4] = "damage_profile_right",
                    },
                    unset = false,
                    value = "light_slashing_smiter_stab_dual",
                },
            },
            source_path = "scripts/settings/equipment/weapon_templates/dual_wield_daggers.lua",
            template = "dual_wield_daggers_template_1",
            unsupported = {},
        },
        [2] = {
            ops = {
                [1] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "heavy_attack_2",
                        [4] = "additional_critical_strike_chance",
                    },
                    unset = false,
                    value = 0.1,
                },
            },
            source_path = "scripts/settings/equipment/weapon_templates/dual_wield_sword_dagger.lua",
            template = "dual_wield_sword_dagger_template_1",
            unsupported = {},
        },
        [3] = {
            ops = {
                [1] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "default",
                        [4] = "allowed_chain_actions",
                    },
                    value = {
                        [1] = {
                            action = "action_wield",
                            input = "action_wield",
                            start_time = 0.4,
                            sub_action = "default",
                        },
                        [2] = {
                            action = "action_one",
                            input = "action_one",
                            start_time = 0,
                            sub_action = "default",
                        },
                        [3] = {
                            action = "action_one",
                            hold_required = {
                                [1] = "action_one_hold",
                            },
                            input = "action_one_hold",
                            start_time = 0.7,
                            sub_action = "shoot",
                        },
                        [4] = {
                            action = "action_two",
                            input = "action_two_hold",
                            start_time = 0.4,
                            sub_action = "default",
                        },
                        [5] = {
                            action = "weapon_reload",
                            input = "weapon_reload",
                            start_time = 0.75,
                            sub_action = "default",
                        },
                    },
                },
            },
            source_path = "scripts/settings/equipment/weapon_templates/heavy_steam_pistol.lua",
            template = "heavy_steam_pistol_template_1",
            unsupported = {},
        },
        [4] = {
            ops = {
                [1] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "heavy_stab",
                        [4] = "allowed_chain_actions",
                    },
                    value = {
                        [1] = {
                            action = "weapon_reload",
                            input = "weapon_reload",
                            start_time = 0.5,
                            sub_action = "default",
                        },
                        [2] = {
                            action = "action_wield",
                            input = "action_wield",
                            start_time = 0.8,
                            sub_action = "default",
                        },
                        [3] = {
                            action = "action_one",
                            end_time = math.huge,
                            input = "action_one_hold",
                            start_time = 0.55,
                            sub_action = "default",
                        },
                        [4] = {
                            action = "action_one",
                            end_time = math.huge,
                            input = "action_one_release",
                            release_required = "action_one_hold",
                            start_time = 0.5,
                            sub_action = "chain_stab_01",
                        },
                        [5] = {
                            action = "action_two",
                            end_time = math.huge,
                            input = "action_two_hold",
                            start_time = 0.8,
                            sub_action = "default",
                        },
                    },
                },
                [2] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "throw_charged",
                        [4] = "anim_event_infinite_ammo_3p",
                    },
                    unset = false,
                    value = "attack_throw",
                },
                [3] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "throw_charged",
                        [4] = "anim_event_last_ammo_3p",
                    },
                    unset = false,
                    value = "attack_throw_last",
                },
                [4] = {
                    path = {
                        [1] = "destroy_indexed_projectiles",
                    },
                    unset = true,
                },
            },
            source_path = "scripts/settings/equipment/weapon_templates/javelin.lua",
            template = "javelin_template",
            unsupported = {},
        },
        [5] = {
            ops = {
                [1] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "heavy_attack_left",
                        [4] = "damage_profile",
                    },
                    unset = false,
                    value = "medium_slashing_smiter_1h_axe",
                },
                [2] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "heavy_attack_right",
                        [4] = "damage_profile",
                    },
                    unset = false,
                    value = "medium_slashing_smiter_1h_axe",
                },
                [3] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_bopp",
                        [4] = "damage_profile",
                    },
                    unset = false,
                    value = "light_slashing_smiter",
                },
                [4] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_last",
                        [4] = "buff_data",
                    },
                    value = {
                        [1] = {
                            buff_name = "planted_decrease_movement",
                            end_time = 0.5,
                            external_multiplier = 0.8,
                            start_time = 0,
                        },
                    },
                },
                [5] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_last",
                        [4] = "damage_profile",
                    },
                    unset = false,
                    value = "light_slashing_smiter_diag",
                },
                [6] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_left",
                        [4] = "buff_data",
                    },
                    value = {
                        [1] = {
                            buff_name = "planted_decrease_movement",
                            end_time = 0.5,
                            external_multiplier = 0.8,
                            start_time = 0,
                        },
                    },
                },
                [7] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_left",
                        [4] = "damage_profile",
                    },
                    unset = false,
                    value = "light_slashing_smiter_diag",
                },
                [8] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_right",
                        [4] = "buff_data",
                    },
                    value = {
                        [1] = {
                            buff_name = "planted_decrease_movement",
                            end_time = 0.5,
                            external_multiplier = 0.8,
                            start_time = 0,
                        },
                    },
                },
                [9] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_right",
                        [4] = "damage_profile",
                    },
                    unset = false,
                    value = "light_slashing_smiter_diag",
                },
                [10] = {
                    path = {
                        [1] = "buffs",
                        [2] = "change_dodge_distance",
                        [3] = "external_optional_multiplier",
                    },
                    unset = false,
                    value = 1.2,
                },
                [11] = {
                    path = {
                        [1] = "buffs",
                        [2] = "change_dodge_speed",
                        [3] = "external_optional_multiplier",
                    },
                    unset = false,
                    value = 1.2,
                },
            },
            source_path = "scripts/settings/equipment/weapon_templates/1h_axes.lua",
            template = "one_hand_axe_template_1",
            unsupported = {},
        },
        [6] = {
            ops = {
                [1] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "heavy_attack_left",
                        [4] = "damage_profile",
                    },
                    unset = false,
                    value = "medium_slashing_smiter_1h_axe",
                },
                [2] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "heavy_attack_right",
                        [4] = "damage_profile",
                    },
                    unset = false,
                    value = "medium_slashing_smiter_1h_axe",
                },
                [3] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_bopp",
                        [4] = "damage_profile",
                    },
                    unset = false,
                    value = "light_slashing_smiter",
                },
                [4] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_last",
                        [4] = "buff_data",
                    },
                    value = {
                        [1] = {
                            buff_name = "planted_decrease_movement",
                            end_time = 0.5,
                            external_multiplier = 0.8,
                            start_time = 0,
                        },
                    },
                },
                [5] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_last",
                        [4] = "damage_profile",
                    },
                    unset = false,
                    value = "light_slashing_smiter_diag",
                },
                [6] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_left",
                        [4] = "buff_data",
                    },
                    value = {
                        [1] = {
                            buff_name = "planted_decrease_movement",
                            end_time = 0.5,
                            external_multiplier = 0.8,
                            start_time = 0,
                        },
                    },
                },
                [7] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_left",
                        [4] = "damage_profile",
                    },
                    unset = false,
                    value = "light_slashing_smiter_diag",
                },
                [8] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_right",
                        [4] = "buff_data",
                    },
                    value = {
                        [1] = {
                            buff_name = "planted_decrease_movement",
                            end_time = 0.5,
                            external_multiplier = 0.8,
                            start_time = 0,
                        },
                    },
                },
                [9] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_right",
                        [4] = "damage_profile",
                    },
                    unset = false,
                    value = "light_slashing_smiter_diag",
                },
                [10] = {
                    path = {
                        [1] = "buffs",
                        [2] = "change_dodge_distance",
                        [3] = "external_optional_multiplier",
                    },
                    unset = false,
                    value = 1.2,
                },
                [11] = {
                    path = {
                        [1] = "buffs",
                        [2] = "change_dodge_speed",
                        [3] = "external_optional_multiplier",
                    },
                    unset = false,
                    value = 1.2,
                },
            },
            source_path = "scripts/settings/equipment/weapon_templates/1h_axes.lua",
            template = "one_hand_axe_template_2",
            unsupported = {},
        },
        [7] = {
            ops = {
                [1] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_bopp",
                        [4] = "allowed_chain_actions",
                    },
                    value = {
                        [1] = {
                            action = "action_one",
                            input = "action_one",
                            release_required = "action_two_hold",
                            start_time = 0.75,
                            sub_action = "default",
                        },
                        [2] = {
                            action = "action_one",
                            input = "action_one_hold",
                            release_required = "action_two_hold",
                            start_time = 0.75,
                            sub_action = "default",
                        },
                        [3] = {
                            action = "action_two",
                            input = "action_two_hold",
                            start_time = 0.55,
                            sub_action = "default",
                        },
                        [4] = {
                            action = "action_wield",
                            input = "action_wield",
                            start_time = 0.55,
                            sub_action = "default",
                        },
                    },
                },
                [2] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "push",
                        [4] = "fatigue_cost",
                    },
                    unset = true,
                },
                [3] = {
                    path = {
                        [1] = "buffs",
                        [2] = "change_dodge_distance",
                        [3] = "external_optional_multiplier",
                    },
                    unset = false,
                    value = 1.25,
                },
                [4] = {
                    path = {
                        [1] = "buffs",
                        [2] = "change_dodge_speed",
                        [3] = "external_optional_multiplier",
                    },
                    unset = false,
                    value = 1.25,
                },
                [5] = {
                    path = {
                        [1] = "dodge_count",
                    },
                    unset = false,
                    value = 4,
                },
            },
            source_path = "scripts/settings/equipment/weapon_templates/1h_falchions.lua",
            template = "one_hand_falchion_template_1",
            unsupported = {},
        },
        [8] = {
            ops = {
                [1] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "heavy_attack",
                        [4] = "damage_profile",
                    },
                    unset = false,
                    value = "medium_pointy_smiter_upper_1h",
                },
                [2] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "heavy_attack_left",
                        [4] = "damage_profile",
                    },
                    unset = false,
                    value = "medium_pointy_smiter_flat_1h",
                },
                [3] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "heavy_attack_right_up",
                        [4] = "damage_profile",
                    },
                    unset = false,
                    value = "medium_pointy_smiter_diag_1h",
                },
                [4] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_bopp",
                        [4] = "damage_profile",
                    },
                    unset = false,
                    value = "light_pointy_smiter_upper",
                },
                [5] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_right",
                        [4] = "damage_profile",
                    },
                    unset = false,
                    value = "light_pointy_smiter_diag",
                },
                [6] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_upper",
                        [4] = "damage_profile",
                    },
                    unset = false,
                    value = "light_pointy_smiter_flat",
                },
                [7] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "push",
                        [4] = "fatigue_cost",
                    },
                    unset = true,
                },
            },
            source_path = "scripts/settings/equipment/weapon_templates/1h_crowbills.lua",
            template = "one_handed_crowbill",
            unsupported = {},
        },
        [9] = {
            ops = {
                [1] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "push",
                        [4] = "fatigue_cost",
                    },
                    unset = true,
                },
            },
            source_path = "scripts/settings/equipment/weapon_templates/1h_flails.lua",
            template = "one_handed_flail_template_1",
            unsupported = {},
        },
        [10] = {
            ops = {
                [1] = {
                    path = {
                        [1] = "block_angle",
                    },
                    unset = false,
                    value = 90,
                },
                [2] = {
                    path = {
                        [1] = "dodge_count",
                    },
                    unset = false,
                    value = 3,
                },
            },
            source_path = "scripts/settings/equipment/weapon_templates/1h_hammers_priest.lua",
            template = "one_handed_hammer_priest_template",
            unsupported = {},
        },
        [11] = {
            ops = {
                [1] = {
                    path = {
                        [1] = "block_angle",
                    },
                    unset = false,
                    value = 90,
                },
                [2] = {
                    path = {
                        [1] = "dodge_count",
                    },
                    unset = false,
                    value = 3,
                },
            },
            source_path = "scripts/settings/equipment/weapon_templates/1h_hammers.lua",
            template = "one_handed_hammer_template_1",
            unsupported = {},
        },
        [12] = {
            ops = {
                [1] = {
                    path = {
                        [1] = "block_angle",
                    },
                    unset = false,
                    value = 90,
                },
                [2] = {
                    path = {
                        [1] = "dodge_count",
                    },
                    unset = false,
                    value = 3,
                },
            },
            source_path = "scripts/settings/equipment/weapon_templates/1h_hammers.lua",
            template = "one_handed_hammer_template_2",
            unsupported = {},
        },
        [13] = {
            ops = {
                [1] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_stab_postpush",
                        [4] = "damage_window_end",
                    },
                    unset = false,
                    value = 0.28,
                },
                [2] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_stab_postpush",
                        [4] = "damage_window_start",
                    },
                    unset = false,
                    value = 0.18,
                },
                [3] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_stab_postpush",
                        [4] = "dedicated_target_range",
                    },
                    unset = false,
                    value = 2.5,
                },
                [4] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_stab_postpush",
                        [4] = "range_mod",
                    },
                    unset = false,
                    value = 1.2,
                },
                [5] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_stab_postpush",
                        [4] = "range_mod_add",
                    },
                    unset = true,
                },
                [6] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_two",
                        [3] = "default",
                        [4] = "anim_event_3p",
                    },
                    unset = false,
                    value = "parry_pose",
                },
            },
            source_path = "scripts/settings/equipment/weapon_templates/1h_swords_shield.lua",
            template = "one_handed_sword_shield_template_1",
            unsupported = {},
        },
        [14] = {
            ops = {
                [1] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_bopp",
                        [4] = "allowed_chain_actions",
                    },
                    value = {
                        [1] = {
                            action = "action_one",
                            end_time = 1.2,
                            input = "action_one",
                            release_required = "action_two_hold",
                            start_time = 0.55,
                            sub_action = "default",
                        },
                        [2] = {
                            action = "action_one",
                            end_time = 1.2,
                            input = "action_one_hold",
                            release_required = "action_two_hold",
                            start_time = 0.55,
                            sub_action = "default",
                        },
                        [3] = {
                            action = "action_one",
                            input = "action_one",
                            start_time = 0.85,
                            sub_action = "default",
                        },
                        [4] = {
                            action = "action_two",
                            input = "action_two_hold",
                            start_time = 0.55,
                            sub_action = "default",
                        },
                        [5] = {
                            action = "action_wield",
                            input = "action_wield",
                            start_time = 0.5,
                            sub_action = "default",
                        },
                    },
                },
                [2] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_last",
                        [4] = "buff_data",
                    },
                    value = {
                        [1] = {
                            buff_name = "planted_fast_decrease_movement",
                            end_time = 0.2,
                            external_multiplier = 0.7,
                            start_time = 0,
                        },
                        [2] = {
                            buff_name = "planted_fast_decrease_movement",
                            end_time = 0.4,
                            external_multiplier = 1.7,
                            start_time = 0.2,
                        },
                        [3] = {
                            buff_name = "planted_fast_decrease_movement",
                            end_time = 0.5,
                            external_multiplier = 0.7,
                            start_time = 0.4,
                        },
                    },
                },
                [3] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_last",
                        [4] = "damage_profile",
                    },
                    unset = false,
                    value = "light_slashing_smiter_finesse",
                },
                [4] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_left",
                        [4] = "buff_data",
                    },
                    value = {
                        [1] = {
                            buff_name = "planted_decrease_movement",
                            end_time = 0.5,
                            external_multiplier = 0.9,
                            start_time = 0,
                        },
                    },
                },
                [5] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_right",
                        [4] = "buff_data",
                    },
                    value = {
                        [1] = {
                            buff_name = "planted_decrease_movement",
                            end_time = 0.5,
                            external_multiplier = 0.9,
                            start_time = 0,
                        },
                    },
                },
                [6] = {
                    path = {
                        [1] = "buffs",
                        [2] = "change_dodge_distance",
                        [3] = "external_optional_multiplier",
                    },
                    unset = false,
                    value = 1.2,
                },
                [7] = {
                    path = {
                        [1] = "buffs",
                        [2] = "change_dodge_speed",
                        [3] = "external_optional_multiplier",
                    },
                    unset = false,
                    value = 1.2,
                },
                [8] = {
                    path = {
                        [1] = "dodge_count",
                    },
                    unset = false,
                    value = 3,
                },
            },
            source_path = "scripts/settings/equipment/weapon_templates/1h_swords.lua",
            template = "one_handed_swords_template_1",
            unsupported = {},
        },
        [15] = {
            ops = {
                [1] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "heavy_attack_left",
                        [4] = "damage_profile",
                    },
                    unset = false,
                    value = "medium_slashing_smiter_1h_axe",
                },
                [2] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "heavy_attack_right",
                        [4] = "damage_profile",
                    },
                    unset = false,
                    value = "medium_slashing_smiter_1h_axe",
                },
                [3] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_bopp",
                        [4] = "additional_critical_strike_chance",
                    },
                    unset = false,
                    value = 0.2,
                },
                [4] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_bopp",
                        [4] = "buff_data",
                    },
                    value = {
                        [1] = {
                            buff_name = "planted_decrease_movement",
                            end_time = 0.5,
                            external_multiplier = 0.6,
                            start_time = 0,
                        },
                    },
                },
                [5] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_bopp",
                        [4] = "damage_profile",
                    },
                    unset = false,
                    value = "light_slashing_smiter",
                },
                [6] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_last",
                        [4] = "buff_data",
                    },
                    value = {
                        [1] = {
                            buff_name = "planted_decrease_movement",
                            end_time = 0.5,
                            external_multiplier = 0.75,
                            start_time = 0,
                        },
                    },
                },
                [7] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_last",
                        [4] = "damage_profile",
                    },
                    unset = false,
                    value = "light_slashing_smiter_finesse",
                },
                [8] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_left",
                        [4] = "buff_data",
                    },
                    value = {
                        [1] = {
                            buff_name = "planted_decrease_movement",
                            end_time = 0.5,
                            external_multiplier = 0.75,
                            start_time = 0,
                        },
                    },
                },
                [9] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_left",
                        [4] = "damage_profile",
                    },
                    unset = false,
                    value = "light_slashing_smiter_diag_1h",
                },
                [10] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_right",
                        [4] = "buff_data",
                    },
                    value = {
                        [1] = {
                            buff_name = "planted_decrease_movement",
                            end_time = 0.5,
                            external_multiplier = 0.75,
                            start_time = 0,
                        },
                    },
                },
                [11] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_right",
                        [4] = "damage_profile",
                    },
                    unset = false,
                    value = "light_slashing_smiter_diag",
                },
                [12] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_right_last",
                        [4] = "buff_data",
                    },
                    value = {
                        [1] = {
                            buff_name = "planted_decrease_movement",
                            end_time = 0.5,
                            external_multiplier = 0.75,
                            start_time = 0,
                        },
                    },
                },
                [13] = {
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_right_last",
                        [4] = "damage_profile",
                    },
                    unset = false,
                    value = "light_slashing_smiter_finesse",
                },
                [14] = {
                    path = {
                        [1] = "buffs",
                        [2] = "change_dodge_distance",
                        [3] = "external_optional_multiplier",
                    },
                    unset = false,
                    value = 1.2,
                },
                [15] = {
                    path = {
                        [1] = "buffs",
                        [2] = "change_dodge_speed",
                        [3] = "external_optional_multiplier",
                    },
                    unset = false,
                    value = 1.2,
                },
            },
            source_path = "scripts/settings/equipment/weapon_templates/1h_axes_wood_elf.lua",
            template = "we_one_hand_axe_template",
            unsupported = {},
        },
    },
}
