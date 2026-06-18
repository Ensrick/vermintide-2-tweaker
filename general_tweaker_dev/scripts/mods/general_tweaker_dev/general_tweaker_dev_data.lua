local mod = get_mod("gt_dev")

-- Grail Knight quest dropdown options. Values mirror the
-- `markus_questing_knight_passive_*` reward strings that
-- PassiveAbilityQuestingKnight's challenge pool reads. Text is plain
-- English here (the localized labels live in general_tweaker_localization).
local GT_GK_QUEST_OPTIONS = {
    { text = "Random (vanilla)",    value = "random" },
    { text = "Power vs. Elites",    value = "markus_questing_knight_passive_power_level" },
    { text = "Attack Speed",        value = "markus_questing_knight_passive_attack_speed" },
    { text = "Cooldown Reduction",  value = "markus_questing_knight_passive_cooldown_reduction" },
    { text = "Health Regen",        value = "markus_questing_knight_passive_health_regen" },
    { text = "Damage Reduction",    value = "markus_questing_knight_passive_damage_taken" },
}

local GT_HUD_MODE_OPTIONS = {
    { text = "Off",      value = "off" },
    { text = "Partial",  value = "partial" },
    { text = "Complete", value = "complete" },
    { text = "Camera",   value = "camera" },
}

-- Creature Spawner unit-list dropdown options. Values match the runtime
-- table keys in _gt_cs_unit_lists (regular_units / dummy_units / etc.) so
-- mod:get("gt_cs_unit_list") returns the exact key we index into.
local GT_CS_UNIT_LIST_OPTIONS = {
    { text = "gt_cs_unit_list_regular", value = "regular_units" },
    { text = "gt_cs_unit_list_dummy",   value = "dummy_units" },
    { text = "gt_cs_unit_list_misc",    value = "misc_units" },
    { text = "gt_cs_unit_list_special", value = "special_units" },
    { text = "gt_cs_unit_list_boss",    value = "boss_units" },
    { text = "gt_cs_unit_list_all",     value = "all_units" },
}

-- Grudge-marked dropdown. Disabled/Random/Manual, matching upstream.
-- Sub-widget reveal lists mirror the upstream `show_widgets` arrays:
-- index 1 is the random-count slider, indices 2-14 are the 13 manual toggles.
local GT_CS_GRUDGE_OPTIONS = {
    { text = "gt_cs_grudge_disabled", value = false },
    { text = "gt_cs_grudge_random",   value = "RANDOM", show_widgets = { 1 } },
    { text = "gt_cs_grudge_manual",   value = "MANUAL", show_widgets = { 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14 } },
}

return {
    name = "Tweaker: General",
    description = mod:localize("mod_description"),
    is_togglable = true,

    options = {
        widgets = {
            {
                setting_id  = "tp_camera_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "tp_camera_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("tp_camera_enabled_tooltip"),
                    },
                    {
                        setting_id    = "tp_distance",
                        type          = "numeric",
                        default_value = 3.0,
                        range         = { 1.0, 10.0 },
                        decimals_number = 1,
                        tooltip       = mod:localize("tp_distance_tooltip"),
                    },
                    {
                        setting_id    = "tp_height",
                        type          = "numeric",
                        default_value = 1.0,
                        range         = { -1.0, 5.0 },
                        decimals_number = 1,
                        tooltip       = mod:localize("tp_height_tooltip"),
                    },
                    {
                        setting_id    = "tp_side_offset",
                        type          = "numeric",
                        default_value = 0.8,
                        range         = { -3.0, 3.0 },
                        decimals_number = 1,
                        tooltip       = mod:localize("tp_side_offset_tooltip"),
                    },
                    {
                        setting_id    = "tp_disable_zoom_in",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("tp_disable_zoom_in_tooltip"),
                    },
                    {
                        setting_id    = "freecam_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("freecam_enabled_tooltip"),
                    },
                },
            },
            {
                setting_id  = "gameplay_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "godmode_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("godmode_enabled_tooltip"),
                    },
                    {
                        setting_id    = "allow_duplicate_careers",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("allow_duplicate_careers_tooltip"),
                    },
                    {
                        setting_id    = "disable_friendly_fire",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("disable_friendly_fire_tooltip"),
                    },
                    {
                        setting_id    = "noclip_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("noclip_enabled_tooltip"),
                    },
                    {
                        setting_id    = "noclip_speed",
                        type          = "numeric",
                        default_value = 15.0,
                        range         = { 1.0, 60.0 },
                        decimals_number = 1,
                        tooltip       = mod:localize("noclip_speed_tooltip"),
                    },
                    {
                        setting_id    = "noclip_boost_multiplier",
                        type          = "numeric",
                        default_value = 3.0,
                        range         = { 1.0, 10.0 },
                        decimals_number = 1,
                        tooltip       = mod:localize("noclip_boost_multiplier_tooltip"),
                    },
                    {
                        setting_id      = "noclip_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_noclip_toggle",
                        default_value   = {},
                        tooltip         = mod:localize("noclip_hotkey_tooltip"),
                    },
                    {
                        setting_id    = "disable_enemy_spawns",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("disable_enemy_spawns_tooltip"),
                    },
                    {
                        setting_id      = "clear_enemies_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_clear_enemies",
                        default_value   = {},
                        tooltip         = mod:localize("clear_enemies_hotkey_tooltip"),
                    },
                    {
                        setting_id    = "ai_takeover_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("ai_takeover_enabled_tooltip"),
                    },
                    {
                        setting_id    = "gt_bots_in_keep",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("gt_bots_in_keep_tooltip"),
                    },
                    {
                        setting_id    = "gt_no_bots",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("gt_no_bots_tooltip"),
                    },
                },
            },
            {
                setting_id  = "gt_cutscenes_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "gt_skip_cutscenes_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("gt_skip_cutscenes_enabled_tooltip"),
                        sub_widgets   = {
                            {
                                setting_id    = "gt_skip_cutscenes_auto",
                                type          = "checkbox",
                                default_value = false,
                                tooltip       = mod:localize("gt_skip_cutscenes_auto_tooltip"),
                            },
                        },
                    },
                    {
                        setting_id    = "gt_disable_intro_monologue",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("gt_disable_intro_monologue_tooltip"),
                    },
                },
            },
            {
                setting_id  = "gt_corpses_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "gt_more_corpses_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("gt_more_corpses_enabled_tooltip"),
                        sub_widgets   = {
                            {
                                setting_id      = "gt_more_corpses_count",
                                type            = "numeric",
                                default_value   = 24,
                                range           = { 1, 500 },
                                decimals_number = 0,
                                tooltip         = mod:localize("gt_more_corpses_count_tooltip"),
                            },
                        },
                    },
                },
            },
            {
                setting_id  = "gt_gk_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "gt_gk_quests_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("gt_gk_quests_enabled_tooltip"),
                        sub_widgets   = {
                            {
                                setting_id    = "gt_gk_quest1",
                                type          = "dropdown",
                                default_value = "random",
                                options       = GT_GK_QUEST_OPTIONS,
                                tooltip       = mod:localize("gt_gk_quest1_tooltip"),
                            },
                            {
                                setting_id    = "gt_gk_quest2",
                                type          = "dropdown",
                                default_value = "random",
                                options       = GT_GK_QUEST_OPTIONS,
                                tooltip       = mod:localize("gt_gk_quest2_tooltip"),
                            },
                            {
                                setting_id    = "gt_gk_quest3",
                                type          = "dropdown",
                                default_value = "random",
                                options       = GT_GK_QUEST_OPTIONS,
                                tooltip       = mod:localize("gt_gk_quest3_tooltip"),
                            },
                        },
                    },
                },
            },
            {
                setting_id  = "gt_readyup_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id      = "gt_ready_up_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_ready_up_now",
                        default_value   = {},
                        tooltip         = mod:localize("gt_ready_up_hotkey_tooltip"),
                    },
                    {
                        setting_id    = "gt_auto_ready_on_vote_pass",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("gt_auto_ready_on_vote_pass_tooltip"),
                    },
                },
            },
            {
                setting_id  = "mission_inventory_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "mission_inventory_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("mission_inventory_enabled_tooltip"),
                    },
                    {
                        setting_id      = "gt_open_inv_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_open_mission_inventory",
                        default_value   = {},
                        tooltip         = mod:localize("gt_open_inv_hotkey_tooltip"),
                    },
                },
            },
            {
                setting_id  = "player_state_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id      = "cloak_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_cloak_toggle",
                        default_value   = {},
                        tooltip         = mod:localize("cloak_hotkey_tooltip"),
                    },
                },
            },
            {
                setting_id  = "buffs_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id      = "base_crit_chance",
                        type            = "numeric",
                        default_value   = 5,
                        range           = { 0, 100 },
                        decimals_number = 1,
                        tooltip         = mod:localize("base_crit_chance_tooltip"),
                    },
                    {
                        setting_id      = "movement_speed",
                        type            = "numeric",
                        default_value   = 4,
                        range           = { 0, 30 },
                        decimals_number = 1,
                        tooltip         = mod:localize("movement_speed_tooltip"),
                    },
                },
            },
            {
                setting_id  = "ult_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id      = "ult_reset_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_ult_reset",
                        default_value   = {},
                        tooltip         = mod:localize("ult_reset_hotkey_tooltip"),
                    },
                    {
                        setting_id    = "ult_player_cap_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("ult_player_cap_enabled_tooltip"),
                        sub_widgets   = {
                            {
                                setting_id      = "ult_player_cap_value",
                                type            = "numeric",
                                default_value   = 0,
                                range           = { 0, 120 },
                                decimals_number = 1,
                                tooltip         = mod:localize("ult_player_cap_value_tooltip"),
                            },
                        },
                    },
                    {
                        setting_id    = "ult_bot_cap_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("ult_bot_cap_enabled_tooltip"),
                        sub_widgets   = {
                            {
                                setting_id      = "ult_bot_cap_value",
                                type            = "numeric",
                                default_value   = 0,
                                range           = { 0, 120 },
                                decimals_number = 1,
                                tooltip         = mod:localize("ult_bot_cap_value_tooltip"),
                            },
                        },
                    },
                },
            },
            {
                setting_id  = "time_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "time_scale_value",
                        type          = "numeric",
                        default_value = 13,
                        range         = { 1, 24 },
                        tooltip       = mod:localize("time_scale_value_tooltip"),
                    },
                    {
                        setting_id      = "time_faster_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_time_faster",
                        default_value   = {},
                        tooltip         = mod:localize("time_faster_hotkey_tooltip"),
                    },
                    {
                        setting_id      = "time_slower_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_time_slower",
                        default_value   = {},
                        tooltip         = mod:localize("time_slower_hotkey_tooltip"),
                    },
                    {
                        setting_id    = "pause_value",
                        type          = "numeric",
                        default_value = 1,
                        range         = { 1, 24 },
                        tooltip       = mod:localize("pause_value_tooltip"),
                    },
                    {
                        setting_id      = "pause_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_pause_toggle",
                        default_value   = {},
                        tooltip         = mod:localize("pause_hotkey_tooltip"),
                    },
                },
            },
            {
                setting_id  = "level_control_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id      = "win_level_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_win_level",
                        default_value   = {},
                        tooltip         = mod:localize("win_level_hotkey_tooltip"),
                    },
                    {
                        setting_id      = "fail_level_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_fail_level",
                        default_value   = {},
                        tooltip         = mod:localize("fail_level_hotkey_tooltip"),
                    },
                    {
                        setting_id      = "restart_level_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_restart_level",
                        default_value   = {},
                        tooltip         = mod:localize("restart_level_hotkey_tooltip"),
                    },
                    {
                        setting_id      = "kill_bots_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_kill_bots",
                        default_value   = {},
                        tooltip         = mod:localize("kill_bots_hotkey_tooltip"),
                    },
                    {
                        setting_id      = "die_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_die",
                        default_value   = {},
                        tooltip         = mod:localize("die_hotkey_tooltip"),
                    },
                    {
                        setting_id      = "fix_sound_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_fix_sound",
                        default_value   = {},
                        tooltip         = mod:localize("fix_sound_hotkey_tooltip"),
                    },
                    {
                        setting_id      = "gt_bot_toggle_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_bot_toggle",
                        default_value   = {},
                        tooltip         = mod:localize("gt_bot_toggle_hotkey_tooltip"),
                    },
                },
            },
            {
                setting_id  = "gt_hud_visibility_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "gt_hud_mode",
                        type          = "dropdown",
                        default_value = "off",
                        options       = GT_HUD_MODE_OPTIONS,
                        tooltip       = mod:localize("gt_hud_mode_tooltip"),
                    },
                    {
                        setting_id      = "gt_hud_cycle_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_hud_cycle",
                        default_value   = {},
                        tooltip         = mod:localize("gt_hud_cycle_hotkey_tooltip"),
                    },
                },
            },
            {
                setting_id  = "gt_damage_numbers_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "gt_damage_numbers_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("gt_damage_numbers_enabled_tooltip"),
                        sub_widgets   = {
                            {
                                setting_id    = "gt_damage_numbers_include_dots",
                                type          = "checkbox",
                                default_value = true,
                                tooltip       = mod:localize("gt_damage_numbers_include_dots_tooltip"),
                            },
                        },
                    },
                },
            },
            {
                setting_id  = "gt_cs_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "gt_cs_unit_list",
                        type          = "dropdown",
                        default_value = "regular_units",
                        options       = GT_CS_UNIT_LIST_OPTIONS,
                        tooltip       = mod:localize("gt_cs_unit_list_tooltip"),
                    },
                    {
                        setting_id      = "gt_cs_spawn",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_cs_spawn",
                        default_value   = {},
                        tooltip         = mod:localize("gt_cs_spawn_tooltip"),
                    },
                    {
                        setting_id      = "gt_cs_next",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_cs_next",
                        default_value   = {},
                        tooltip         = mod:localize("gt_cs_next_tooltip"),
                    },
                    {
                        setting_id      = "gt_cs_prev",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_cs_prev",
                        default_value   = {},
                        tooltip         = mod:localize("gt_cs_prev_tooltip"),
                    },
                    {
                        setting_id      = "gt_cs_destroy",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_cs_destroy",
                        default_value   = {},
                        tooltip         = mod:localize("gt_cs_destroy_tooltip"),
                    },
                    {
                        setting_id      = "gt_cs_spawn_slot_1",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_cs_spawn_slot_1",
                        default_value   = {},
                        tooltip         = mod:localize("gt_cs_spawn_slot_1_tooltip"),
                    },
                    {
                        setting_id      = "gt_cs_spawn_slot_2",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_cs_spawn_slot_2",
                        default_value   = {},
                        tooltip         = mod:localize("gt_cs_spawn_slot_2_tooltip"),
                    },
                    {
                        setting_id      = "gt_cs_spawn_slot_3",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_cs_spawn_slot_3",
                        default_value   = {},
                        tooltip         = mod:localize("gt_cs_spawn_slot_3_tooltip"),
                    },
                    {
                        setting_id    = "gt_cs_mission_ai",
                        type          = "checkbox",
                        default_value = true,
                        tooltip       = mod:localize("gt_cs_mission_ai_tooltip"),
                    },
                    {
                        setting_id    = "gt_cs_keep_ai",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("gt_cs_keep_ai_tooltip"),
                    },
                    {
                        setting_id    = "gt_cs_grudge",
                        type          = "dropdown",
                        default_value = false,
                        options       = GT_CS_GRUDGE_OPTIONS,
                        tooltip       = mod:localize("gt_cs_grudge_tooltip"),
                        sub_widgets   = {
                            {
                                setting_id      = "gt_cs_grudge_random_modifier_count",
                                type            = "numeric",
                                default_value   = 1,
                                range           = { 0, 13 },
                                decimals_number = 0,
                                tooltip         = mod:localize("gt_cs_grudge_random_modifier_count_tooltip"),
                            },
                            { setting_id = "gt_cs_grudge_warping",         type = "checkbox", default_value = false, tooltip = mod:localize("gt_cs_grudge_warping_tooltip") },
                            { setting_id = "gt_cs_grudge_intangible",      type = "checkbox", default_value = false, tooltip = mod:localize("gt_cs_grudge_intangible_tooltip") },
                            { setting_id = "gt_cs_grudge_unstaggerable",   type = "checkbox", default_value = false, tooltip = mod:localize("gt_cs_grudge_unstaggerable_tooltip") },
                            { setting_id = "gt_cs_grudge_raging",          type = "checkbox", default_value = false, tooltip = mod:localize("gt_cs_grudge_raging_tooltip") },
                            { setting_id = "gt_cs_grudge_vampiric",        type = "checkbox", default_value = false, tooltip = mod:localize("gt_cs_grudge_vampiric_tooltip") },
                            { setting_id = "gt_cs_grudge_ranged_immune",   type = "checkbox", default_value = false, tooltip = mod:localize("gt_cs_grudge_ranged_immune_tooltip") },
                            { setting_id = "gt_cs_grudge_periodic_shield", type = "checkbox", default_value = false, tooltip = mod:localize("gt_cs_grudge_periodic_shield_tooltip") },
                            { setting_id = "gt_cs_grudge_crippling",       type = "checkbox", default_value = false, tooltip = mod:localize("gt_cs_grudge_crippling_tooltip") },
                            { setting_id = "gt_cs_grudge_crushing",        type = "checkbox", default_value = false, tooltip = mod:localize("gt_cs_grudge_crushing_tooltip") },
                            { setting_id = "gt_cs_grudge_regenerating",    type = "checkbox", default_value = false, tooltip = mod:localize("gt_cs_grudge_regenerating_tooltip") },
                            { setting_id = "gt_cs_grudge_periodic_curse",  type = "checkbox", default_value = false, tooltip = mod:localize("gt_cs_grudge_periodic_curse_tooltip") },
                            { setting_id = "gt_cs_grudge_commander",       type = "checkbox", default_value = false, tooltip = mod:localize("gt_cs_grudge_commander_tooltip") },
                            { setting_id = "gt_cs_grudge_frenzy",          type = "checkbox", default_value = false, tooltip = mod:localize("gt_cs_grudge_frenzy_tooltip") },
                        },
                    },
                },
            },
            {
                setting_id  = "gt_is_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id      = "gt_is_next_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_is_next",
                        default_value   = {},
                        tooltip         = mod:localize("gt_is_next_hotkey_tooltip"),
                    },
                    {
                        setting_id      = "gt_is_prev_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_is_prev",
                        default_value   = {},
                        tooltip         = mod:localize("gt_is_prev_hotkey_tooltip"),
                    },
                    {
                        setting_id      = "gt_is_spawn_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_is_spawn",
                        default_value   = {},
                        tooltip         = mod:localize("gt_is_spawn_hotkey_tooltip"),
                    },
                },
            },
            -- ============================================================
            -- Host-Side Lobby Controls (absorbed from lobby_tweaker
            -- 2026-05-25; lt v0.1.7-dev). All settings namespaced
            -- `gt_lobby_*`; chat commands likewise renamed `/gt_lobby_*`.
            -- ============================================================
            {
                setting_id  = "gt_lobby_controls_group",
                type        = "group",
                sub_widgets = {
                    -- Slot Reservations
                    {
                        setting_id    = "gt_lobby_slot_reservations_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("gt_lobby_slot_reservations_enabled_tooltip"),
                    },
                    -- Session Ignore List
                    {
                        setting_id    = "gt_lobby_session_ignore_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("gt_lobby_session_ignore_enabled_tooltip"),
                    },
                    -- Kick on Idle
                    {
                        setting_id    = "gt_lobby_kick_idle_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("gt_lobby_kick_idle_enabled_tooltip"),
                    },
                    {
                        setting_id    = "gt_lobby_kick_idle_threshold_minutes",
                        type          = "numeric",
                        default_value = 10,
                        range         = { 1, 60 },
                        tooltip       = mod:localize("gt_lobby_kick_idle_threshold_minutes_tooltip"),
                    },
                    {
                        setting_id    = "gt_lobby_ki_warn_seconds",
                        type          = "numeric",
                        default_value = 60,
                        range         = { 10, 180 },
                        tooltip       = mod:localize("gt_lobby_ki_warn_seconds_tooltip"),
                    },
                    -- Message of the Day
                    {
                        setting_id    = "gt_lobby_motd_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("gt_lobby_motd_enabled_tooltip"),
                    },
                    -- MOTD text setting is NOT a widget — VMF has no native
                    -- string-input widget type. Set via chat command:
                    --   /gt_lobby_motd_set <text>
                    -- which writes to `mod:set("gt_lobby_motd_text", text)`.
                    -- A widget here with type="text_input" caused widget#103
                    -- to fail VMF validation (no such VMF type) and broke gt
                    -- options init entirely on 2026-05-25.
                    {
                        setting_id    = "gt_lobby_motd_send_chat",
                        type          = "checkbox",
                        default_value = true,
                        tooltip       = mod:localize("gt_lobby_motd_send_chat_tooltip"),
                    },
                    {
                        setting_id    = "gt_lobby_motd_send_popup",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("gt_lobby_motd_send_popup_tooltip"),
                    },
                    {
                        setting_id    = "gt_lobby_motd_once_per_peer_per_session",
                        type          = "checkbox",
                        default_value = true,
                        tooltip       = mod:localize("gt_lobby_motd_once_per_peer_per_session_tooltip"),
                    },
                    -- Modded Lobby Manifest
                    {
                        setting_id    = "gt_lobby_manifest_broadcast_enabled",
                        type          = "checkbox",
                        default_value = true,
                        tooltip       = mod:localize("gt_lobby_manifest_broadcast_enabled_tooltip"),
                    },
                    {
                        setting_id    = "gt_lobby_manifest_failnotify_enabled",
                        type          = "checkbox",
                        default_value = true,
                        tooltip       = mod:localize("gt_lobby_manifest_failnotify_enabled_tooltip"),
                    },
                },
            },
            -- Self-refreshing vanilla-name dump (feeds tools/gen-name-map).
            -- Default ON: emits loc_key->English to the console log once per
            -- game build on keep entry. See _gt_name_dump.lua. Manual re-dump:
            -- /gt_dump_names.
            {
                setting_id    = "gt_auto_name_dump",
                type          = "checkbox",
                default_value = true,
                tooltip       = mod:localize("gt_auto_name_dump_tooltip"),
            },
            -- Universal Debug Logging toggle (PROJECT_STANDARDS.md § 3.6).
            -- v0.2.54-dev: renamed from `gt_debug_mode` (was nested in
            -- `gt_debug_group`) to the universal `enable_debug_logging` key,
            -- un-nested to top-level at the BOTTOM of the widget tree.
            {
                setting_id    = "enable_debug_logging",
                type          = "checkbox",
                default_value = false,
                tooltip       = mod:localize("enable_debug_logging_tooltip"),
            },
            -- Lua memory watchdog interval. The watchdog itself rides the
            -- universal `enable_debug_logging` toggle above (v0.2.79-dev) — it's
            -- a debug diagnostic like every other, so it runs whenever debug
            -- logging is on. Logs collectgarbage("count") every N seconds — the
            -- ground-truth Lua heap size — so a session that OOMs the lua_heap
            -- shows the exact growth curve + which level/timeframe it accelerates.
            {
                setting_id    = "memwatch_interval",
                type          = "numeric",
                default_value = 10,
                range         = { 2, 60 },
                decimals_number = 0,
                tooltip       = mod:localize("memwatch_interval_tooltip"),
            },
            -- v0.2.78-dev: GC mitigation to survive long sessions despite the
            -- in-investigation Lua heap leak. Tightens the incremental GC so the
            -- heap stays closer to the live set, with an optional periodic full
            -- collect. Toggle on for long CW runs until the leak is fixed.
            {
                setting_id    = "gc_mitigation_enabled",
                type          = "checkbox",
                default_value = false,
                tooltip       = mod:localize("gc_mitigation_enabled_tooltip"),
            },
            {
                setting_id    = "gc_full_collect_sec",
                type          = "numeric",
                default_value = 0,
                range         = { 0, 120 },
                decimals_number = 0,
                tooltip       = mod:localize("gc_full_collect_sec_tooltip"),
            },
            -- Bot Options -- AI teammate behavior fixes (see _gt_bot_fixes.lua).
            -- All default OFF; host-side only (bots exist on the host), no
            -- network registration so they can't affect non-modded peers.
            {
                setting_id  = "gt_bot_options_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "gt_bot_necro_potion_handoff",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("gt_bot_necro_potion_handoff_tooltip"),
                    },
                    {
                        setting_id    = "gt_bot_ironbreaker_revive_in_ult",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("gt_bot_ironbreaker_revive_in_ult_tooltip"),
                    },
                    {
                        setting_id    = "gt_bot_rescue_awaiting",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("gt_bot_rescue_awaiting_tooltip"),
                    },
                    {
                        setting_id    = "gt_bot_mission_fail_prevention",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("gt_bot_mission_fail_prevention_tooltip"),
                    },
                    {
                        setting_id    = "gt_bot_ledge_pullup",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("gt_bot_ledge_pullup_tooltip"),
                    },
                    {
                        setting_id      = "gt_bot_ledge_pullup_delay",
                        type            = "numeric",
                        default_value   = 3.0,
                        range           = { 1.0, 10.0 },
                        decimals_number = 1,
                        tooltip         = mod:localize("gt_bot_ledge_pullup_delay_tooltip"),
                    },
                    {
                        setting_id    = "gt_bot_ladder_unstick",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("gt_bot_ladder_unstick_tooltip"),
                    },
                    {
                        setting_id      = "gt_bot_ladder_unstick_delay",
                        type            = "numeric",
                        default_value   = 5.0,
                        range           = { 2.0, 20.0 },
                        decimals_number = 1,
                        tooltip         = mod:localize("gt_bot_ladder_unstick_delay_tooltip"),
                    },
                    {
                        setting_id    = "gt_bot_follow_distance_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("gt_bot_follow_distance_enabled_tooltip"),
                    },
                    {
                        setting_id      = "gt_bot_follow_distance_m",
                        type            = "numeric",
                        default_value   = 40.0,
                        range           = { 10.0, 50.0 },
                        decimals_number = 1,
                        tooltip         = mod:localize("gt_bot_follow_distance_m_tooltip"),
                    },
                    {
                        setting_id    = "gt_bot_instant_pickup",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = mod:localize("gt_bot_instant_pickup_tooltip"),
                    },
                },
            },
            -- Boss Mechanic Tweaks (see _gt_boss_tweaks.lua). Load-time data
            -- mutation; host-side, no network registration.
            {
                setting_id  = "gt_boss_tweaks_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id      = "gt_fly_disable_mult",
                        type            = "numeric",
                        default_value   = 1.0,
                        range           = { 0.0, 3.0 },
                        decimals_number = 2,
                        tooltip         = mod:localize("gt_fly_disable_mult_tooltip"),
                    },
                },
            },
            -- Solo & QoL (ported from True Solo QoL Tweaks; see _gt_solo_qol.lua).
            -- All default OFF. AUTO_KILL_BOTS not ported -- use "Disable Bots (Solo)".
            {
                setting_id  = "gt_solo_group",
                type        = "group",
                sub_widgets = {
                    { setting_id = "gt_solo_auto_restart_on_wipe",       type = "checkbox", default_value = false, tooltip = mod:localize("gt_solo_auto_restart_on_wipe_tooltip") },
                    { setting_id = "gt_solo_assassin_text_warning",      type = "checkbox", default_value = false, tooltip = mod:localize("gt_solo_assassin_text_warning_tooltip") },
                    { setting_id = "gt_solo_packmaster_text_warning",    type = "checkbox", default_value = false, tooltip = mod:localize("gt_solo_packmaster_text_warning_tooltip") },
                    { setting_id = "gt_solo_assassin_hero_vo",           type = "checkbox", default_value = false, tooltip = mod:localize("gt_solo_assassin_hero_vo_tooltip") },
                    { setting_id = "gt_solo_disable_ult_vo",             type = "checkbox", default_value = false, tooltip = mod:localize("gt_solo_disable_ult_vo_tooltip") },
                    { setting_id = "gt_solo_disable_mutator_explosions", type = "checkbox", default_value = false, tooltip = mod:localize("gt_solo_disable_mutator_explosions_tooltip") },
                    { setting_id = "gt_solo_disable_intro_audio",        type = "checkbox", default_value = false, tooltip = mod:localize("gt_solo_disable_intro_audio_tooltip") },
                    { setting_id = "gt_solo_disable_fog",                type = "checkbox", default_value = false, tooltip = mod:localize("gt_solo_disable_fog_tooltip") },
                    { setting_id = "gt_solo_disable_sun_shadows",        type = "checkbox", default_value = false, tooltip = mod:localize("gt_solo_disable_sun_shadows_tooltip") },
                    { setting_id = "gt_solo_draw_boss_spheres",          type = "checkbox", default_value = false, tooltip = mod:localize("gt_solo_draw_boss_spheres_tooltip") },
                    { setting_id = "gt_solo_boss_path_progress",         type = "checkbox", default_value = false, tooltip = mod:localize("gt_solo_boss_path_progress_tooltip") },
                },
            },
        },
    },
}
