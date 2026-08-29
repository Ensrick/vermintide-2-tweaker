-- Rehydrated from immutable source revisions; do not hand-edit.
return {
    new_revision = "038498af",
    old_revision = "cdc0a86e",
    records = {
        [1] = {
            ops = {
                [1] = {
                    expected_current = {
                        [1] = {
                            action = "action_wield",
                            input = "action_wield",
                            start_time = 0.40000000000000002,
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
                            input = "action_one_softbutton_gamepad",
                            softbutton_required = {
                                [1] = {
                                    input = "action_one_softbutton_gamepad",
                                    softbutton_threshold = 0.10000000000000001,
                                },
                            },
                            softbutton_threshold = 0.10000000000000001,
                            start_time = 0.69999999999999996,
                            sub_action = "shoot",
                        },
                        [4] = {
                            action = "action_one",
                            hold_required = {
                                [1] = "action_one_hold",
                            },
                            input = "action_one_hold",
                            start_time = 0.69999999999999996,
                            sub_action = "shoot",
                        },
                        [5] = {
                            action = "action_two",
                            input = "action_two_hold",
                            start_time = 0.40000000000000002,
                            sub_action = "default",
                        },
                        [6] = {
                            action = "weapon_reload",
                            input = "weapon_reload",
                            start_time = 0.75,
                            sub_action = "default",
                        },
                    },
                    expected_current_unset = false,
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "default",
                        [4] = "allowed_chain_actions",
                    },
                    unset = false,
                    value = {
                        [1] = {
                            action = "action_wield",
                            input = "action_wield",
                            start_time = 0.40000000000000002,
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
                            start_time = 0.69999999999999996,
                            sub_action = "shoot",
                        },
                        [4] = {
                            action = "action_two",
                            input = "action_two_hold",
                            start_time = 0.40000000000000002,
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
        [2] = {
            ops = {
                [1] = {
                    expected_current = {
                        [1] = {
                            action = "action_one",
                            input = "action_one",
                            release_required = "action_two_hold",
                            start_time = 0.55000000000000004,
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
                            start_time = 0.55000000000000004,
                            sub_action = "default",
                        },
                        [4] = {
                            action = "action_wield",
                            input = "action_wield",
                            start_time = 0.55000000000000004,
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
                            start_time = 0.55000000000000004,
                            sub_action = "default",
                        },
                        [4] = {
                            action = "action_wield",
                            input = "action_wield",
                            start_time = 0.55000000000000004,
                            sub_action = "default",
                        },
                    },
                },
                [2] = {
                    expected_current = 1.3,
                    expected_current_unset = false,
                    path = {
                        [1] = "buffs",
                        [2] = "change_dodge_distance",
                        [3] = "external_optional_multiplier",
                    },
                    unset = false,
                    value = 1.25,
                },
                [3] = {
                    expected_current = 1.3,
                    expected_current_unset = false,
                    path = {
                        [1] = "buffs",
                        [2] = "change_dodge_speed",
                        [3] = "external_optional_multiplier",
                    },
                    unset = false,
                    value = 1.25,
                },
                [4] = {
                    expected_current = 6,
                    expected_current_unset = false,
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
        [3] = {
            ops = {
                [1] = {
                    expected_current = "crowbill_1h_heavy_smiter",
                    expected_current_unset = false,
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
                    expected_current = "crowbill_1h_heavy_smiter",
                    expected_current_unset = false,
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
                    expected_current = "crowbill_1h_heavy_smiter_diag",
                    expected_current_unset = false,
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
                    expected_current = "crowbill_1h_light_smiter_upper",
                    expected_current_unset = false,
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
                    expected_current = "crowbill_1h_light_smiter_diag",
                    expected_current_unset = false,
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
                    expected_current = "crowbill_1h_light_smiter_flat",
                    expected_current_unset = false,
                    path = {
                        [1] = "actions",
                        [2] = "action_one",
                        [3] = "light_attack_upper",
                        [4] = "damage_profile",
                    },
                    unset = false,
                    value = "light_pointy_smiter_flat",
                },
            },
            source_path = "scripts/settings/equipment/weapon_templates/1h_crowbills.lua",
            template = "one_handed_crowbill",
            unsupported = {},
        },
    },
}
