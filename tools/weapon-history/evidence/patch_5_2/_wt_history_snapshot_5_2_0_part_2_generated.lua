-- Rehydrated from immutable source revisions; do not hand-edit.
return {
    new_revision = "25fd7b84",
    old_revision = "4f496970",
    records = {
        [1] = {
            ops = {
                [1] = {
                    expected_current = {
                        [1] = {
                            action = "action_one",
                            end_time = 1.2,
                            input = "action_one",
                            release_required = "action_two_hold",
                            start_time = 0.5,
                            sub_action = "default_left",
                        },
                        [2] = {
                            action = "action_two",
                            input = "action_two_hold",
                            start_time = 0.45000000000000001,
                            sub_action = "default",
                        },
                        [3] = {
                            action = "action_one",
                            input = "action_one",
                            start_time = 0.84999999999999998,
                            sub_action = "default",
                        },
                        [4] = {
                            action = "action_two",
                            input = "action_two_hold",
                            start_time = 0.55000000000000004,
                            sub_action = "default",
                        },
                        [5] = {
                            action = "action_wield",
                            input = "action_wield",
                            start_time = 0.5,
                            sub_action = "default",
                        },
                    },
                    expected_current_unset = false,
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_bopp",
                        [4] = "allowed_chain_actions",
                    },
                    unset = false,
                    value = {
                        [1] = {
                            action = "action_one",
                            end_time = 1.2,
                            input = "action_one",
                            release_required = "action_two_hold",
                            start_time = 0.55000000000000004,
                            sub_action = "default",
                        },
                        [2] = {
                            action = "action_one",
                            end_time = 1.2,
                            input = "action_one_hold",
                            release_required = "action_two_hold",
                            start_time = 0.55000000000000004,
                            sub_action = "default",
                        },
                        [3] = {
                            action = "action_one",
                            input = "action_one",
                            start_time = 0.84999999999999998,
                            sub_action = "default",
                        },
                        [4] = {
                            action = "action_two",
                            input = "action_two_hold",
                            start_time = 0.55000000000000004,
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
                    expected_current = {
                        [1] = {
                            buff_name = "planted_fast_decrease_movement",
                            end_time = 0.20000000000000001,
                            external_multiplier = 0.84999999999999998,
                            start_time = 0,
                        },
                        [2] = {
                            buff_name = "planted_fast_decrease_movement",
                            end_time = 0.40000000000000002,
                            external_multiplier = 1.7,
                            start_time = 0.20000000000000001,
                        },
                        [3] = {
                            buff_name = "planted_fast_decrease_movement",
                            end_time = 0.5,
                            external_multiplier = 0.69999999999999996,
                            start_time = 0.40000000000000002,
                        },
                    },
                    expected_current_unset = false,
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_last",
                        [4] = "buff_data",
                    },
                    unset = false,
                    value = {
                        [1] = {
                            buff_name = "planted_fast_decrease_movement",
                            end_time = 0.20000000000000001,
                            external_multiplier = 0.69999999999999996,
                            start_time = 0,
                        },
                        [2] = {
                            buff_name = "planted_fast_decrease_movement",
                            end_time = 0.40000000000000002,
                            external_multiplier = 1.7,
                            start_time = 0.20000000000000001,
                        },
                        [3] = {
                            buff_name = "planted_fast_decrease_movement",
                            end_time = 0.5,
                            external_multiplier = 0.69999999999999996,
                            start_time = 0.40000000000000002,
                        },
                    },
                },
                [3] = {
                    expected_current = "sword_1h_light_smiter_vertical",
                    expected_current_unset = false,
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
                    expected_current = {
                        [1] = {
                            buff_name = "planted_decrease_movement",
                            end_time = 0.5,
                            external_multiplier = 0.94999999999999996,
                            start_time = 0,
                        },
                    },
                    expected_current_unset = false,
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_left",
                        [4] = "buff_data",
                    },
                    unset = false,
                    value = {
                        [1] = {
                            buff_name = "planted_decrease_movement",
                            end_time = 0.5,
                            external_multiplier = 0.90000000000000002,
                            start_time = 0,
                        },
                    },
                },
                [5] = {
                    expected_current = {
                        [1] = {
                            buff_name = "planted_decrease_movement",
                            end_time = 0.5,
                            external_multiplier = 0.94999999999999996,
                            start_time = 0,
                        },
                    },
                    expected_current_unset = false,
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_right",
                        [4] = "buff_data",
                    },
                    unset = false,
                    value = {
                        [1] = {
                            buff_name = "planted_decrease_movement",
                            end_time = 0.5,
                            external_multiplier = 0.90000000000000002,
                            start_time = 0,
                        },
                    },
                },
                [6] = {
                    expected_current = 1.3,
                    expected_current_unset = false,
                    path = {
                        [1] = "buffs",
                        [2] = "change_dodge_distance",
                        [3] = "external_optional_multiplier",
                    },
                    unset = false,
                    value = 1.2,
                },
                [7] = {
                    expected_current = 1.3,
                    expected_current_unset = false,
                    path = {
                        [1] = "buffs",
                        [2] = "change_dodge_speed",
                        [3] = "external_optional_multiplier",
                    },
                    unset = false,
                    value = 1.2,
                },
                [8] = {
                    expected_current = 6,
                    expected_current_unset = false,
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
        [2] = {
            ops = {
                [1] = {
                    expected_current = "elven_axe_heavy_smiter_vertical",
                    expected_current_unset = false,
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
                    expected_current = "elven_axe_heavy_smiter_vertical",
                    expected_current_unset = false,
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
                    expected_current_unset = true,
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_bopp",
                        [4] = "additional_critical_strike_chance",
                    },
                    unset = false,
                    value = 0.20000000000000001,
                },
                [4] = {
                    expected_current = {
                        [1] = {
                            buff_name = "planted_decrease_movement",
                            end_time = 0.14999999999999999,
                            external_multiplier = 2,
                            start_time = 0,
                        },
                        [2] = {
                            buff_name = "planted_decrease_movement",
                            end_time = 0.25,
                            external_multiplier = 1.2,
                            start_time = 0.14999999999999999,
                        },
                        [3] = {
                            buff_name = "planted_decrease_movement",
                            end_time = 0.40000000000000002,
                            external_multiplier = 0.69999999999999996,
                            start_time = 0.25,
                        },
                    },
                    expected_current_unset = false,
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_bopp",
                        [4] = "buff_data",
                    },
                    unset = false,
                    value = {
                        [1] = {
                            buff_name = "planted_decrease_movement",
                            end_time = 0.5,
                            external_multiplier = 0.59999999999999998,
                            start_time = 0,
                        },
                    },
                },
                [5] = {
                    expected_current = "elven_axe_light_tank_diag",
                    expected_current_unset = false,
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
                    expected_current = {
                        [1] = {
                            buff_name = "planted_decrease_movement",
                            end_time = 0.29999999999999999,
                            external_multiplier = 1.3999999999999999,
                            start_time = 0,
                        },
                        [2] = {
                            buff_name = "planted_decrease_movement",
                            end_time = 0.5,
                            external_multiplier = 0.69999999999999996,
                            start_time = 0.29999999999999999,
                        },
                    },
                    expected_current_unset = false,
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_last",
                        [4] = "buff_data",
                    },
                    unset = false,
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
                    expected_current = "elven_axe_light_smiter_vertical",
                    expected_current_unset = false,
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
                    expected_current = {
                        [1] = {
                            buff_name = "planted_decrease_movement",
                            end_time = 0.5,
                            external_multiplier = 0.90000000000000002,
                            start_time = 0,
                        },
                    },
                    expected_current_unset = false,
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_left",
                        [4] = "buff_data",
                    },
                    unset = false,
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
                    expected_current = "elven_axe_light_smiter_horizontal",
                    expected_current_unset = false,
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
                    expected_current = {
                        [1] = {
                            buff_name = "planted_decrease_movement",
                            end_time = 0.5,
                            external_multiplier = 0.90000000000000002,
                            start_time = 0,
                        },
                    },
                    expected_current_unset = false,
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_right",
                        [4] = "buff_data",
                    },
                    unset = false,
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
                    expected_current = "elven_axe_light_smiter_horizontal",
                    expected_current_unset = false,
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
                    expected_current = {
                        [1] = {
                            buff_name = "planted_decrease_movement",
                            end_time = 0.29999999999999999,
                            external_multiplier = 1.3999999999999999,
                            start_time = 0,
                        },
                        [2] = {
                            buff_name = "planted_decrease_movement",
                            end_time = 0.5,
                            external_multiplier = 0.69999999999999996,
                            start_time = 0.29999999999999999,
                        },
                    },
                    expected_current_unset = false,
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_right_last",
                        [4] = "buff_data",
                    },
                    unset = false,
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
                    expected_current = "elven_axe_light_smiter_vertical",
                    expected_current_unset = false,
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
                    expected_current = 1.3,
                    expected_current_unset = false,
                    path = {
                        [1] = "buffs",
                        [2] = "change_dodge_distance",
                        [3] = "external_optional_multiplier",
                    },
                    unset = false,
                    value = 1.2,
                },
                [15] = {
                    expected_current = 1.3,
                    expected_current_unset = false,
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
