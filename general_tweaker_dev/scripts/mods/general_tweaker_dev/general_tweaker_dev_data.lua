local mod = get_mod("gt_dev")

-- Grail Knight quest dropdown options. Values mirror the
-- `markus_questing_knight_passive_*` reward strings that
-- PassiveAbilityQuestingKnight's challenge pool reads.
--
-- PER-DROPDOWN FACTORY (do NOT hoist back to a shared table). VMF's
-- localize_dropdown_data mutates each option's `text` IN PLACE
-- (`option.text = mod:localize(option.text)`). The three quest dropdowns below
-- (gt_gk_quest1/2/3) each localize their options table once; if they shared a
-- single table, the 2nd dropdown would localize the already-localized strings
-- and the 3rd would localize those again, producing the `<<...>>` / `<<<...>>>`
-- bracket cascade users reported on "Choose Grail Knight Quests". Returning a
-- fresh table per call gives each dropdown its own table to mutate. `text` is a
-- real loc key (resolved in general_tweaker_dev_localization) so it renders as a
-- clean display name instead of the missing-key fallback. Same pattern as
-- crt's _talent_swap_options() / enemy_tweaker's dropdown factory.
-- See REGRESSION_CHECKLIST "vmf-dropdown-options-mutated".
local function _gt_gk_quest_options()
    return {
        { text = "gt_gk_opt_random",              value = "random" },
        { text = "gt_gk_opt_power_level",         value = "markus_questing_knight_passive_power_level" },
        { text = "gt_gk_opt_attack_speed",        value = "markus_questing_knight_passive_attack_speed" },
        { text = "gt_gk_opt_cooldown_reduction",  value = "markus_questing_knight_passive_cooldown_reduction" },
        { text = "gt_gk_opt_health_regen",        value = "markus_questing_knight_passive_health_regen" },
        { text = "gt_gk_opt_damage_taken",        value = "markus_questing_knight_passive_damage_taken" },
    }
end

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
            -- Bot Options -- AI teammate behavior fixes (see _gt_bot_fixes.lua).
            -- All default OFF; host-side only (bots exist on the host), no
            -- network registration so they can't affect non-modded peers.
            {
                setting_id  = "gt_bot_options_group",
                type        = "group",
                sub_widgets = {
                    -- Nested sub-group first (menu convention: nested sub-groups
                    -- before loose options). Bot Teleport Lab = diagnostics-only
                    -- tools to observe/probe the "bots teleport away" bug. A master
                    -- checkbox (gt_btlab_enabled) gates 10 independent D-toggles.
                    -- The 10 are listed in D1..D10 NUMERIC order (NOT alphabetical)
                    -- -- the numbering is deliberate and maps to _gt_bot_teleport_lab.lua.
                    -- All default OFF; host-side (bot AI is server-side).
                    {
                        setting_id  = "gt_btlab_group",
                        type        = "group",
                        sub_widgets = {
                            {
                                setting_id    = "gt_btlab_enabled",
                                type          = "checkbox",
                                default_value = false,
                                tooltip       = "gt_btlab_enabled_tooltip",
                                -- Master gate: every D-toggle also requires this ON
                                -- (code reads `mod:get("gt_btlab_enabled") and
                                -- mod:get("gt_btlab_dNN_...")`). VMF auto-hides these
                                -- sub_widgets while the master is unchecked.
                                sub_widgets   = {
                                    {
                                        setting_id    = "gt_btlab_d1_teleport_events",
                                        type          = "checkbox",
                                        default_value = false,
                                        tooltip       = "gt_btlab_d1_teleport_events_tooltip",
                                    },
                                    {
                                        setting_id    = "gt_btlab_d2_follow_tracker",
                                        type          = "checkbox",
                                        default_value = false,
                                        tooltip       = "gt_btlab_d2_follow_tracker_tooltip",
                                    },
                                    {
                                        setting_id    = "gt_btlab_d3_distance_readout",
                                        type          = "checkbox",
                                        default_value = false,
                                        tooltip       = "gt_btlab_d3_distance_readout_tooltip",
                                    },
                                    {
                                        setting_id    = "gt_btlab_d4_segment_probe",
                                        type          = "checkbox",
                                        default_value = false,
                                        tooltip       = "gt_btlab_d4_segment_probe_tooltip",
                                    },
                                    {
                                        setting_id    = "gt_btlab_d5_aid_probe",
                                        type          = "checkbox",
                                        default_value = false,
                                        tooltip       = "gt_btlab_d5_aid_probe_tooltip",
                                    },
                                    {
                                        setting_id    = "gt_btlab_d6_bot_hud",
                                        type          = "checkbox",
                                        default_value = false,
                                        tooltip       = "gt_btlab_d6_bot_hud_tooltip",
                                    },
                                    {
                                        setting_id    = "gt_btlab_d7_leash_lines",
                                        type          = "checkbox",
                                        default_value = false,
                                        tooltip       = "gt_btlab_d7_leash_lines_tooltip",
                                    },
                                    {
                                        setting_id    = "gt_btlab_d8_tp_counter",
                                        type          = "checkbox",
                                        default_value = false,
                                        tooltip       = "gt_btlab_d8_tp_counter_tooltip",
                                    },
                                    {
                                        setting_id    = "gt_btlab_d9_hasteleported_probe",
                                        type          = "checkbox",
                                        default_value = false,
                                        tooltip       = "gt_btlab_d9_hasteleported_probe_tooltip",
                                    },
                                    {
                                        setting_id    = "gt_btlab_d10_tp_snapshot",
                                        type          = "checkbox",
                                        default_value = false,
                                        tooltip       = "gt_btlab_d10_tp_snapshot_tooltip",
                                    },
                                    -- FIXES (F1..F10): the toggles that actually
                                    -- STOP "bots teleport away". Listed in F1..F10
                                    -- NUMERIC order (NOT alphabetical) -- the
                                    -- numbering is deliberate and maps to the fix
                                    -- dispatch fns in _gt_bot_teleport_lab.lua.
                                    -- Each ALSO requires the master gate above.
                                    -- F4/F7/F8/F9 carry a nested numeric param.
                                    -- All default OFF; host-side.
                                    {
                                        setting_id    = "gt_btlab_f1_follow_you",
                                        type          = "checkbox",
                                        default_value = false,
                                        tooltip       = "gt_btlab_f1_follow_you_tooltip",
                                    },
                                    {
                                        setting_id    = "gt_btlab_f2_block_away",
                                        type          = "checkbox",
                                        default_value = false,
                                        tooltip       = "gt_btlab_f2_block_away_tooltip",
                                    },
                                    {
                                        setting_id    = "gt_btlab_f3_teleport_to_you",
                                        type          = "checkbox",
                                        default_value = false,
                                        tooltip       = "gt_btlab_f3_teleport_to_you_tooltip",
                                    },
                                    {
                                        setting_id    = "gt_btlab_f4_proximity_veto",
                                        type          = "checkbox",
                                        default_value = false,
                                        tooltip       = "gt_btlab_f4_proximity_veto_tooltip",
                                        sub_widgets   = {
                                            {
                                                setting_id      = "gt_btlab_f4_radius",
                                                type            = "numeric",
                                                default_value   = 25.0,
                                                range           = { 5.0, 60.0 },
                                                decimals_number = 0,
                                                tooltip         = "gt_btlab_f4_radius_tooltip",
                                            },
                                        },
                                    },
                                    {
                                        setting_id    = "gt_btlab_f5_nearest_human",
                                        type          = "checkbox",
                                        default_value = false,
                                        tooltip       = "gt_btlab_f5_nearest_human_tooltip",
                                    },
                                    {
                                        setting_id    = "gt_btlab_f6_stuck_only",
                                        type          = "checkbox",
                                        default_value = false,
                                        tooltip       = "gt_btlab_f6_stuck_only_tooltip",
                                    },
                                    {
                                        setting_id    = "gt_btlab_f7_threshold_raise",
                                        type          = "checkbox",
                                        default_value = false,
                                        tooltip       = "gt_btlab_f7_threshold_raise_tooltip",
                                        sub_widgets   = {
                                            {
                                                setting_id      = "gt_btlab_f7_distance",
                                                type            = "numeric",
                                                default_value   = 80.0,
                                                range           = { 40.0, 200.0 },
                                                decimals_number = 0,
                                                tooltip         = "gt_btlab_f7_distance_tooltip",
                                            },
                                        },
                                    },
                                    {
                                        setting_id    = "gt_btlab_f8_combat_hold",
                                        type          = "checkbox",
                                        default_value = false,
                                        tooltip       = "gt_btlab_f8_combat_hold_tooltip",
                                        sub_widgets   = {
                                            {
                                                setting_id      = "gt_btlab_f8_radius",
                                                type            = "numeric",
                                                default_value   = 15.0,
                                                range           = { 5.0, 40.0 },
                                                decimals_number = 0,
                                                tooltip         = "gt_btlab_f8_radius_tooltip",
                                            },
                                        },
                                    },
                                    {
                                        setting_id    = "gt_btlab_f9_cooldown",
                                        type          = "checkbox",
                                        default_value = false,
                                        tooltip       = "gt_btlab_f9_cooldown_tooltip",
                                        sub_widgets   = {
                                            {
                                                setting_id      = "gt_btlab_f9_seconds",
                                                type            = "numeric",
                                                default_value   = 3.0,
                                                range           = { 0.5, 15.0 },
                                                decimals_number = 1,
                                                tooltip         = "gt_btlab_f9_seconds_tooltip",
                                            },
                                        },
                                    },
                                    {
                                        setting_id    = "gt_btlab_f10_direction_aware",
                                        type          = "checkbox",
                                        default_value = false,
                                        tooltip       = "gt_btlab_f10_direction_aware_tooltip",
                                    },
                                },
                            },
                        },
                    },
                    -- Bot-roster presence (whether bots exist / where) comes first,
                    -- before the behavior tweaks. Moved here from Gameplay
                    -- (v0.2.145-dev) — both are bot controls and belong under Bot
                    -- Options. gt_bots_in_keep is still runtime kill-switched (#65).
                    {
                        setting_id    = "gt_no_bots",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gt_no_bots_tooltip",
                    },
                    {
                        setting_id    = "gt_bots_in_keep",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gt_bots_in_keep_tooltip",
                    },
                    {
                        setting_id    = "gt_improved_bot_combat",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gt_improved_bot_combat_tooltip",
                    },
                    -- Bundled bot-behavior fixes (v0.2.128-dev). Replaces the eight
                    -- former individual toggles: necro potion handoff, don't-fail-
                    -- while-a-bot-is-alive, auto ledge pull-up (3s), ladder unstick
                    -- (4s), instant grab targeted items, prioritize revive, allow
                    -- revive during ult, rescue ledge/hooked/disabled allies. The
                    -- per-feature delays are now hard-coded (3s / 4s) in
                    -- _gt_bot_fixes.lua.
                    {
                        setting_id    = "gt_bot_behavior_improvements",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gt_bot_behavior_improvements_tooltip",
                    },
                    {
                        setting_id    = "gt_bot_rescue_awaiting",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gt_bot_rescue_awaiting_tooltip",
                    },
                    -- Bot follow mode (v0.2.152-dev) -- single dropdown
                    -- consolidating the previous gt_bot_split_among_players +
                    -- gt_bot_follow_host checkboxes. Migration: the FIX 9 hook
                    -- in _gt_bot_fixes.lua falls back to the old settings on
                    -- the first tick before the new dropdown is read, so
                    -- existing user state carries over without a forced reset.
                    {
                        setting_id    = "gt_bot_follow_mode",
                        type          = "dropdown",
                        default_value = "default",
                        options       = {
                            { text = "gt_bot_follow_mode_default",     value = "default" },
                            { text = "gt_bot_follow_mode_follow_host", value = "follow_host" },
                            { text = "gt_bot_follow_mode_split",       value = "split" },
                        },
                        tooltip       = "gt_bot_follow_mode_tooltip",
                    },
                    -- Bot follow snap-back distance. The separate "Tighter bot follow
                    -- distance" enable toggle was removed 2026-06-30 -- this slider is now
                    -- the sole control: 40 = vanilla (no-op / off), lower = tighter leash.
                    {
                        setting_id      = "gt_bot_follow_distance_m",
                        type            = "numeric",
                        default_value   = 40.0,             -- 40 = vanilla gate; default = off. Lower to tighten.
                        range           = { 10.0, 40.0 },   -- >= 40 does nothing (FIX 7 short-circuits); 40 = off, 10 = tightest
                        decimals_number = 1,
                        tooltip         = "gt_bot_follow_distance_m_tooltip",
                    },
                    -- Replicant Bots ports (v0.2.131-dev). Host-side, default OFF.
                    {
                        setting_id    = "gt_bot_fast_reactions",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gt_bot_fast_reactions_tooltip",
                    },
                    {
                        setting_id    = "gt_bot_drink_potions_in_danger",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gt_bot_drink_potions_in_danger_tooltip",
                    },
                    {
                        setting_id    = "gt_bot_guard_break_msg",
                        type          = "dropdown",
                        default_value = "none",
                        options       = {
                            { text = "gt_bot_guard_break_msg_none",   value = "none" },
                            { text = "gt_bot_guard_break_msg_host",   value = "host" },
                            { text = "gt_bot_guard_break_msg_global", value = "global" },
                        },
                        tooltip       = "gt_bot_guard_break_msg_tooltip",
                    },
                    -- Bot Takeover (moved from Gameplay 2026-06-30) -- handing YOUR
                    -- hero to bot AI is a bot-control feature, so it lives in Bot
                    -- Options. setting_ids preserved; /ai command unchanged.
                    {
                        setting_id    = "ai_takeover_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "ai_takeover_enabled_tooltip",
                    },
                    {
                        setting_id    = "gt_ai_afk_takeover",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gt_ai_afk_takeover_tooltip",
                    },
                },
            },
            -- ============================================================
            -- Cheats and Debug (v0.2.128-dev). Houses godmode + noclip
            -- (moved out of Gameplay) plus the formerly top-level Buffs &
            -- Stats / Ult / Time & Pause / Level Control / Spawners groups,
            -- now nested as sub-groups.
            -- ============================================================
            {
                setting_id  = "cheats_debug_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "godmode_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "godmode_enabled_tooltip",
                    },
                    {
                        setting_id    = "noclip_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "noclip_enabled_tooltip",
                    },
                    {
                        setting_id    = "noclip_speed",
                        type          = "numeric",
                        default_value = 15.0,
                        range         = { 1.0, 60.0 },
                        decimals_number = 1,
                        tooltip       = "noclip_speed_tooltip",
                    },
                    {
                        setting_id    = "noclip_boost_multiplier",
                        type          = "numeric",
                        default_value = 3.0,
                        range         = { 1.0, 10.0 },
                        decimals_number = 1,
                        tooltip       = "noclip_boost_multiplier_tooltip",
                    },
                    {
                        setting_id      = "noclip_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_noclip_toggle",
                        default_value   = {},
                        tooltip         = "noclip_hotkey_tooltip",
                    },
                    -- Enemy spawn controls (moved from Gameplay 2026-06-30) -- both are
                    -- cheat-style combat toggles, so they sit with godmode / noclip.
                    {
                        setting_id    = "disable_enemy_spawns",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "disable_enemy_spawns_tooltip",
                    },
                    {
                        setting_id      = "clear_enemies_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_clear_enemies",
                        default_value   = {},
                        tooltip         = "clear_enemies_hotkey_tooltip",
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
                        tooltip         = "base_crit_chance_tooltip",
                    },
                    {
                        setting_id      = "movement_speed",
                        type            = "numeric",
                        default_value   = 4,
                        range           = { 0, 30 },
                        decimals_number = 1,
                        tooltip         = "movement_speed_tooltip",
                    },
                    {
                        setting_id    = "gt_fall_damage_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gt_fall_damage_enabled_tooltip",
                        sub_widgets   = {
                            {
                                setting_id      = "gt_fall_damage_mult",
                                type            = "numeric",
                                default_value   = 1,
                                range           = { 0, 5 },
                                decimals_number = 2,
                                tooltip         = "gt_fall_damage_mult_tooltip",
                            },
                        },
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
                        tooltip         = "ult_reset_hotkey_tooltip",
                    },
                    {
                        setting_id    = "ult_player_cap_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "ult_player_cap_enabled_tooltip",
                        sub_widgets   = {
                            {
                                setting_id      = "ult_player_cap_value",
                                type            = "numeric",
                                default_value   = 0,
                                range           = { 0, 120 },
                                decimals_number = 1,
                                tooltip         = "ult_player_cap_value_tooltip",
                            },
                        },
                    },
                    {
                        setting_id    = "ult_bot_cap_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "ult_bot_cap_enabled_tooltip",
                        sub_widgets   = {
                            {
                                setting_id      = "ult_bot_cap_value",
                                type            = "numeric",
                                default_value   = 20,   -- was 0, which made enabling the toggle clamp bots to 0s cooldown = ult CONSTANTLY (footgun). 20s = "more aggressive" per the loc intent, not unlimited; user can still set 0 for constant.
                                range           = { 0, 120 },
                                decimals_number = 1,
                                tooltip         = "ult_bot_cap_value_tooltip",
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
                        tooltip       = "time_scale_value_tooltip",
                    },
                    {
                        setting_id      = "time_faster_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_time_faster",
                        default_value   = {},
                        tooltip         = "time_faster_hotkey_tooltip",
                    },
                    {
                        setting_id      = "time_slower_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_time_slower",
                        default_value   = {},
                        tooltip         = "time_slower_hotkey_tooltip",
                    },
                    {
                        setting_id    = "pause_value",
                        type          = "numeric",
                        default_value = 1,
                        range         = { 1, 24 },
                        tooltip       = "pause_value_tooltip",
                    },
                    {
                        setting_id      = "pause_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_pause_toggle",
                        default_value   = {},
                        tooltip         = "pause_hotkey_tooltip",
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
                        tooltip         = "win_level_hotkey_tooltip",
                    },
                    {
                        setting_id      = "fail_level_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_fail_level",
                        default_value   = {},
                        tooltip         = "fail_level_hotkey_tooltip",
                    },
                    {
                        setting_id      = "restart_level_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_restart_level",
                        default_value   = {},
                        tooltip         = "restart_level_hotkey_tooltip",
                    },
                    {
                        setting_id      = "kill_bots_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_kill_bots",
                        default_value   = {},
                        tooltip         = "kill_bots_hotkey_tooltip",
                    },
                    {
                        setting_id      = "die_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_die",
                        default_value   = {},
                        tooltip         = "die_hotkey_tooltip",
                    },
                    {
                        setting_id      = "fix_sound_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_fix_sound",
                        default_value   = {},
                        tooltip         = "fix_sound_hotkey_tooltip",
                    },
                    {
                        setting_id      = "gt_bot_toggle_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_bot_toggle",
                        default_value   = {},
                        tooltip         = "gt_bot_toggle_hotkey_tooltip",
                    },
                },
            },
            -- Spawners: collapsible parent grouping Creature Spawner + Item Spawner.
            -- Nested under Cheats and Debug (v0.2.128-dev).
            {
                setting_id  = "gt_spawners_group",
                type        = "group",
                sub_widgets = {
            {
                setting_id  = "gt_cs_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "gt_cs_unit_list",
                        type          = "dropdown",
                        default_value = "regular_units",
                        options       = GT_CS_UNIT_LIST_OPTIONS,
                        tooltip       = "gt_cs_unit_list_tooltip",
                    },
                    {
                        setting_id      = "gt_cs_spawn",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_cs_spawn",
                        default_value   = {},
                        tooltip         = "gt_cs_spawn_tooltip",
                    },
                    {
                        setting_id      = "gt_cs_next",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_cs_next",
                        default_value   = {},
                        tooltip         = "gt_cs_next_tooltip",
                    },
                    {
                        setting_id      = "gt_cs_prev",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_cs_prev",
                        default_value   = {},
                        tooltip         = "gt_cs_prev_tooltip",
                    },
                    {
                        setting_id      = "gt_cs_destroy",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_cs_destroy",
                        default_value   = {},
                        tooltip         = "gt_cs_destroy_tooltip",
                    },
                    {
                        setting_id      = "gt_cs_spawn_slot_1",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_cs_spawn_slot_1",
                        default_value   = {},
                        tooltip         = "gt_cs_spawn_slot_1_tooltip",
                    },
                    {
                        setting_id      = "gt_cs_spawn_slot_2",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_cs_spawn_slot_2",
                        default_value   = {},
                        tooltip         = "gt_cs_spawn_slot_2_tooltip",
                    },
                    {
                        setting_id      = "gt_cs_spawn_slot_3",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_cs_spawn_slot_3",
                        default_value   = {},
                        tooltip         = "gt_cs_spawn_slot_3_tooltip",
                    },
                    {
                        setting_id    = "gt_cs_mission_ai",
                        type          = "checkbox",
                        default_value = true,
                        tooltip       = "gt_cs_mission_ai_tooltip",
                    },
                    {
                        setting_id    = "gt_cs_keep_ai",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gt_cs_keep_ai_tooltip",
                    },
                    {
                        setting_id    = "gt_cs_grudge",
                        type          = "dropdown",
                        default_value = false,
                        options       = GT_CS_GRUDGE_OPTIONS,
                        tooltip       = "gt_cs_grudge_tooltip",
                        sub_widgets   = {
                            {
                                setting_id      = "gt_cs_grudge_random_modifier_count",
                                type            = "numeric",
                                default_value   = 1,
                                range           = { 0, 13 },
                                decimals_number = 0,
                                tooltip         = "gt_cs_grudge_random_modifier_count_tooltip",
                            },
                            { setting_id = "gt_cs_grudge_warping",         type = "checkbox", default_value = false, tooltip = "gt_cs_grudge_warping_tooltip" },
                            { setting_id = "gt_cs_grudge_intangible",      type = "checkbox", default_value = false, tooltip = "gt_cs_grudge_intangible_tooltip" },
                            { setting_id = "gt_cs_grudge_unstaggerable",   type = "checkbox", default_value = false, tooltip = "gt_cs_grudge_unstaggerable_tooltip" },
                            { setting_id = "gt_cs_grudge_raging",          type = "checkbox", default_value = false, tooltip = "gt_cs_grudge_raging_tooltip" },
                            { setting_id = "gt_cs_grudge_vampiric",        type = "checkbox", default_value = false, tooltip = "gt_cs_grudge_vampiric_tooltip" },
                            { setting_id = "gt_cs_grudge_ranged_immune",   type = "checkbox", default_value = false, tooltip = "gt_cs_grudge_ranged_immune_tooltip" },
                            { setting_id = "gt_cs_grudge_periodic_shield", type = "checkbox", default_value = false, tooltip = "gt_cs_grudge_periodic_shield_tooltip" },
                            { setting_id = "gt_cs_grudge_crippling",       type = "checkbox", default_value = false, tooltip = "gt_cs_grudge_crippling_tooltip" },
                            { setting_id = "gt_cs_grudge_crushing",        type = "checkbox", default_value = false, tooltip = "gt_cs_grudge_crushing_tooltip" },
                            { setting_id = "gt_cs_grudge_regenerating",    type = "checkbox", default_value = false, tooltip = "gt_cs_grudge_regenerating_tooltip" },
                            { setting_id = "gt_cs_grudge_periodic_curse",  type = "checkbox", default_value = false, tooltip = "gt_cs_grudge_periodic_curse_tooltip" },
                            { setting_id = "gt_cs_grudge_commander",       type = "checkbox", default_value = false, tooltip = "gt_cs_grudge_commander_tooltip" },
                            { setting_id = "gt_cs_grudge_frenzy",          type = "checkbox", default_value = false, tooltip = "gt_cs_grudge_frenzy_tooltip" },
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
                        tooltip         = "gt_is_next_hotkey_tooltip",
                    },
                    {
                        setting_id      = "gt_is_prev_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_is_prev",
                        default_value   = {},
                        tooltip         = "gt_is_prev_hotkey_tooltip",
                    },
                    {
                        setting_id      = "gt_is_spawn_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_is_spawn",
                        default_value   = {},
                        tooltip         = "gt_is_spawn_hotkey_tooltip",
                    },
                },
            },
                },  -- end gt_spawners_group sub_widgets
            },      -- end gt_spawners_group
                },  -- end cheats_debug_group sub_widgets
            },      -- end cheats_debug_group
            -- Skip Cutscenes / Auto-skip MIGRATED to gui_tweaker (gut) 2026-06-25,
            -- issue #106; the loading-screen monologue toggle (the group's last
            -- remaining member) MIGRATED to gut 2026-06-29, #192 — group removed.
            -- Floating Damage Numbers MIGRATED to gui_tweaker (gut) 2026-06-29.
            {
                setting_id  = "gameplay_group",
                type        = "group",
                -- SORTING (2026-06-30 rule): Prioritize Specials + Choose Grail Knight
                -- Quests are now master toggles (not groups), so this level has NO nested
                -- groups -- every member is a loose option, ordered alphabetically by
                -- label. (Allow Duplicate Careers + Unlock Weaves -> Lobby; Enemy Spawns
                -- -> Cheats and Debug; Bot / AFK Takeover -> Bots.)
                sub_widgets = {
                    -- "Choose Grail Knight Quests" -- master toggle + 3 quest dropdowns.
                    -- Unwrapped 2026-06-30 from a redundant single-item group (gt_gk_group).
                    {
                        setting_id    = "gt_gk_quests_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gt_gk_quests_enabled_tooltip",
                        sub_widgets   = {
                            {
                                setting_id    = "gt_gk_quest1",
                                type          = "dropdown",
                                default_value = "random",
                                options       = _gt_gk_quest_options(),
                                tooltip       = "gt_gk_quest1_tooltip",
                            },
                            {
                                setting_id    = "gt_gk_quest2",
                                type          = "dropdown",
                                default_value = "random",
                                options       = _gt_gk_quest_options(),
                                tooltip       = "gt_gk_quest2_tooltip",
                            },
                            {
                                setting_id    = "gt_gk_quest3",
                                type          = "dropdown",
                                default_value = "random",
                                options       = _gt_gk_quest_options(),
                                tooltip       = "gt_gk_quest3_tooltip",
                            },
                        },
                    },
                    -- "Disable Friendly Fire"
                    {
                        setting_id    = "disable_friendly_fire",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "disable_friendly_fire_tooltip",
                    },
                    -- "Healer's Touch, Home Brewer, Grenadier % Chance"
                    {
                        setting_id      = "gt_adventure_save_trait_chance",
                        type            = "numeric",
                        default_value   = 25,
                        range           = { 1, 75 },
                        decimals_number = 0,
                        tooltip         = "gt_adventure_save_trait_chance_tooltip",
                    },
                    -- "Prioritize Specials (Tagging, Deepwood and Soulstealer)" -- master
                    -- toggle (was a plain group 2026-06-30). The 3 context sub-toggles
                    -- default ON; the master gates all of them (_gt_prioritize_specials.lua).
                    {
                        setting_id    = "gt_prio_specials_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gt_prio_specials_enabled_tooltip",
                        sub_widgets   = {
                            {
                                setting_id    = "gt_prio_special_tag",
                                type          = "checkbox",
                                default_value = true,
                                tooltip       = "gt_prio_special_tag_tooltip",
                            },
                            {
                                setting_id    = "gt_prio_special_deepwood",
                                type          = "checkbox",
                                default_value = true,
                                tooltip       = "gt_prio_special_deepwood_tooltip",
                            },
                            {
                                setting_id    = "gt_prio_special_soulstealer",
                                type          = "checkbox",
                                default_value = true,
                                tooltip       = "gt_prio_special_soulstealer_tooltip",
                            },
                        },
                    },
                },
            },
            -- ============================================================
            -- Host-Side Lobby Controls (absorbed from lobby_tweaker
            -- 2026-05-25; lt v0.1.7-dev). All settings namespaced
            -- `gt_lobby_*`; chat commands likewise renamed `/lobby_*`.
            -- ============================================================
            {
                setting_id  = "gt_lobby_controls_group",
                type        = "group",
                -- SORTING (2026-06-30 rule): nested sub-groups first (top), then loose
                -- options alphabetical by display label (status tags ignored). Dependent
                -- sub-options (idle threshold / warn) stay directly under their parent.
                sub_widgets = {
                    -- Modded Lobby Manifest -- nested group, so it sits at the TOP.
                    -- Also holds Message of the Day (both are host->joiner broadcasts).
                    {
                        setting_id  = "gt_lobby_manifest_group",
                        type        = "group",
                        sub_widgets = {
                            {
                                setting_id    = "gt_lobby_manifest_broadcast_enabled",
                                type          = "checkbox",
                                default_value = true,
                                tooltip       = "gt_lobby_manifest_broadcast_enabled_tooltip",
                            },
                            {
                                setting_id    = "gt_lobby_manifest_failnotify_enabled",
                                type          = "checkbox",
                                default_value = true,
                                tooltip       = "gt_lobby_manifest_failnotify_enabled_tooltip",
                            },
                            -- Message of the Day (moved from the parent 2026-06-30).
                            -- MOTD text is set via chat: /lobby_motd_set <text>
                            -- (VMF has no string-input widget type).
                            {
                                setting_id    = "gt_lobby_motd_enabled",
                                type          = "checkbox",
                                default_value = false,
                                tooltip       = "gt_lobby_motd_enabled_tooltip",
                            },
                            {
                                setting_id    = "gt_lobby_motd_send_chat",
                                type          = "checkbox",
                                default_value = true,
                                tooltip       = "gt_lobby_motd_send_chat_tooltip",
                            },
                            {
                                setting_id    = "gt_lobby_motd_send_popup",
                                type          = "checkbox",
                                default_value = false,
                                tooltip       = "gt_lobby_motd_send_popup_tooltip",
                            },
                            {
                                setting_id    = "gt_lobby_motd_once_per_peer_per_session",
                                type          = "checkbox",
                                default_value = true,
                                tooltip       = "gt_lobby_motd_once_per_peer_per_session_tooltip",
                            },
                        },
                    },
                    -- Loose options, alphabetical by display label:
                    -- "Allow Duplicate Careers" (moved from Gameplay 2026-06-30; confirmed working)
                    {
                        setting_id    = "allow_duplicate_careers",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "allow_duplicate_careers_tooltip",
                    },
                    -- "Auto-kick idle players in keep" (+ dependent threshold / warn sliders)
                    {
                        setting_id    = "gt_lobby_kick_idle_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gt_lobby_kick_idle_enabled_tooltip",
                    },
                    {
                        setting_id    = "gt_lobby_kick_idle_threshold_minutes",
                        type          = "numeric",
                        default_value = 10,
                        range         = { 1, 60 },
                        tooltip       = "gt_lobby_kick_idle_threshold_minutes_tooltip",
                    },
                    {
                        setting_id    = "gt_lobby_ki_warn_seconds",
                        type          = "numeric",
                        default_value = 60,
                        range         = { 10, 180 },
                        tooltip       = "gt_lobby_ki_warn_seconds_tooltip",
                    },
                    -- "Auto-restart mission on team wipe" (moved from Visuals 2026-06-30).
                    -- setting_id preserved so _gt_solo_qol.lua reads + user state carry over.
                    {
                        setting_id    = "gt_solo_auto_restart_on_wipe",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gt_solo_auto_restart_on_wipe_tooltip",
                    },
                    -- "Auto-start On Vote Pass"
                    {
                        setting_id    = "gt_auto_ready_on_vote_pass",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gt_auto_ready_on_vote_pass_tooltip",
                    },
                    -- "Enable ignore list"
                    {
                        setting_id    = "gt_lobby_session_ignore_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gt_lobby_session_ignore_enabled_tooltip",
                    },
                    -- "Enable slot reservations"
                    {
                        setting_id    = "gt_lobby_slot_reservations_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gt_lobby_slot_reservations_enabled_tooltip",
                    },
                    -- "Ready Up (Skip Countdown)"
                    {
                        setting_id      = "gt_ready_up_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gt_ready_up_now",
                        default_value   = {},
                        tooltip         = "gt_ready_up_hotkey_tooltip",
                    },
                    -- "Unlock All Ranked Weaves" (moved from Gameplay 2026-06-30)
                    {
                        setting_id    = "gt_unlock_all_weaves",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gt_unlock_all_weaves_tooltip",
                    },
                },
            },
            -- (In-mission inventory group MIGRATED to gui_tweaker 2026-06-24.)
            -- (Main Menu & Startup group MIGRATED to gui_tweaker 2026-06-29, #190.)
            -- (Ready Up group MIGRATED into Host-Side Lobby Controls above 2026-06-29.)
            -- Info (2026-06-29) -- on-screen text readouts / warnings split out
            -- from Solo & QoL into their own group so they're easier to find.
            -- Widget IDs preserved (gt_solo_*) so existing user settings carry
            -- over and the _gt_solo_qol.lua reads against `mod:get(...)` keep
            -- working unchanged.
            {
                setting_id  = "gt_info_group",
                type        = "group",
                sub_widgets = {
                    { setting_id = "gt_solo_assassin_text_warning",   type = "checkbox", default_value = false, tooltip = "gt_solo_assassin_text_warning_tooltip" },
                    { setting_id = "gt_solo_packmaster_text_warning", type = "checkbox", default_value = false, tooltip = "gt_solo_packmaster_text_warning_tooltip" },
                    { setting_id = "gt_solo_boss_path_progress",      type = "checkbox", default_value = false, tooltip = "gt_solo_boss_path_progress_tooltip" },
                },
            },
            -- (More Corpses group MERGED into Visuals (gt_solo_group, renamed
            -- from "Solo & QoL") 2026-06-29.)
            -- Visuals (was "Solo & QoL"; ported from True Solo QoL Tweaks; see
            -- _gt_solo_qol.lua). All default OFF. AUTO_KILL_BOTS not ported --
            -- use "Disable Bots".
            {
                setting_id  = "gt_solo_group",  -- display label "Visuals" (loc); setting_id preserved
                type        = "group",
                sub_widgets = {
                    -- (Auto-restart on team wipe MOVED to Host-Side Lobby Controls
                    -- 2026-06-30 -- it's a host-side match-flow control, not a visual.)
                    { setting_id = "gt_solo_assassin_hero_vo",           type = "checkbox", default_value = false, tooltip = "gt_solo_assassin_hero_vo_tooltip" },
                    { setting_id = "gt_solo_disable_ult_vo",             type = "checkbox", default_value = false, tooltip = "gt_solo_disable_ult_vo_tooltip" },
                    { setting_id = "gt_solo_disable_mutator_explosions", type = "checkbox", default_value = false, tooltip = "gt_solo_disable_mutator_explosions_tooltip" },
                    -- (Disable level intro audio REMOVED 2026-06-30 -- duplicated GUI Tweaker's "Disable Level Intro Audio".)
                    { setting_id = "gt_solo_disable_fog",                type = "checkbox", default_value = false, tooltip = "gt_solo_disable_fog_tooltip" },
                    { setting_id = "gt_solo_disable_sun_shadows",        type = "checkbox", default_value = false, tooltip = "gt_solo_disable_sun_shadows_tooltip" },
                    { setting_id = "gt_solo_draw_boss_spheres",          type = "checkbox", default_value = false, tooltip = "gt_solo_draw_boss_spheres_tooltip" },
                    -- Max Ragdolls -- single always-on slider (the enable toggle +
                    -- nested sub-widget were dropped 2026-06-30). 24 = vanilla default;
                    -- up to 300 for a cinematic pile.
                    {
                        setting_id      = "gt_more_corpses_count",
                        type            = "numeric",
                        default_value   = 24,
                        range           = { 1, 300 },
                        decimals_number = 0,
                        tooltip         = "gt_more_corpses_count_tooltip",
                    },
                },
            },
            -- 3rd-Person Camera (tp_camera_group) MIGRATED to gui_tweaker (gut)
            -- 2026-06-29, #191.
        },
    },
}
