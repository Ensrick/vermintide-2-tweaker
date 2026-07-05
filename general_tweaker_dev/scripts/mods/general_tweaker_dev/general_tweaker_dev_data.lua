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

local _data = {
    name = "Tweaker: General",
    description = mod:localize("mod_description"),
    is_togglable = true,

    options = {
        -- Top-level groups are ordered A->Z by display label: Bots, Cheats and
        -- Debug, Gameplay, Host-Side Lobby Controls, Info, Visuals and Audio.
        widgets = {
            -- ============================================================
            -- Bots -- AI teammate behavior fixes (see _gt_bot_fixes.lua).
            -- Loose options A->Z by display label (status tags ignored). All
            -- default OFF; host-side only (bots exist on the host), no network
            -- registration so they can't affect non-modded peers. (The former
            -- Bot Teleport Lab nested group was removed in v0.2.175-dev -- its
            -- diagnostics are now implicit + always-on in the dev build, and its
            -- two visual tools moved to the dev-only "Dev Tools" group below.)
            -- ============================================================
            {
                setting_id  = "gt_bot_options_group",
                type        = "group",
                sub_widgets = {
                    -- Loose options, A->Z by display label (status tags ignored):
                    {
                        setting_id    = "gt_ai_afk_takeover",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gt_ai_afk_takeover_tooltip",
                    },
                    {
                        setting_id    = "gt_bots_in_keep",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gt_bots_in_keep_tooltip",
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
                    -- Bot Behavior Improvements MASTER toggle (#297, v0.2.182-dev).
                    -- v0.2.128-dev bundled the eight former individual bot fixes
                    -- under this one checkbox; #297 re-exposes each fix as a nested
                    -- sub-widget (VMF native master-toggle pattern: children auto-
                    -- hide while the box is unchecked, vmf_options_view.lua:4461-4463).
                    -- The master still gates EVERYTHING (default OFF); every child
                    -- defaults ON so the master alone reproduces the former bundle.
                    -- Checkbox ids reuse the pre-bundle setting ids retired in
                    -- v0.2.128-dev (no widget used them since), restoring persisted
                    -- pre-bundle user choices. The two delay sliders replace the
                    -- delays hard-coded (3s / 4s) since v0.2.128-dev; sub-toggles are
                    -- read live inside the tick/hook bodies (_gt_bot_fixes.lua), so
                    -- no on_setting_changed wiring. gt_bot_greedy_pickup is NEW
                    -- (#297 item 8). Children kept in FEATURE order, NOT A->Z: each
                    -- delay slider must sit directly under the toggle it tunes.
                    {
                        setting_id    = "gt_bot_behavior_improvements",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gt_bot_behavior_improvements_tooltip",
                        sub_widgets   = {
                            {
                                setting_id    = "gt_bot_necro_potion_handoff",
                                type          = "checkbox",
                                default_value = true,
                                tooltip       = "gt_bot_necro_potion_handoff_tooltip",
                            },
                            {
                                setting_id    = "gt_bot_mission_fail_prevention",
                                type          = "checkbox",
                                default_value = true,
                                tooltip       = "gt_bot_mission_fail_prevention_tooltip",
                            },
                            {
                                setting_id    = "gt_bot_ledge_pullup",
                                type          = "checkbox",
                                default_value = true,
                                tooltip       = "gt_bot_ledge_pullup_tooltip",
                            },
                            {
                                setting_id      = "gt_bot_ledge_pullup_delay",
                                type            = "numeric",
                                default_value   = 3,
                                range           = { 0, 10 },
                                decimals_number = 0,
                                tooltip         = "gt_bot_ledge_pullup_delay_tooltip",
                            },
                            {
                                setting_id    = "gt_bot_ladder_unstick",
                                type          = "checkbox",
                                default_value = true,
                                tooltip       = "gt_bot_ladder_unstick_tooltip",
                            },
                            {
                                setting_id      = "gt_bot_ladder_unstick_delay",
                                type            = "numeric",
                                default_value   = 4,
                                range           = { 3, 10 },
                                decimals_number = 0,
                                tooltip         = "gt_bot_ladder_unstick_delay_tooltip",
                            },
                            {
                                setting_id    = "gt_bot_instant_pickup",
                                type          = "checkbox",
                                default_value = true,
                                tooltip       = "gt_bot_instant_pickup_tooltip",
                            },
                            {
                                setting_id    = "gt_bot_greedy_pickup",
                                type          = "checkbox",
                                default_value = true,
                                tooltip       = "gt_bot_greedy_pickup_tooltip",
                            },
                            {
                                setting_id    = "gt_bot_aid_priority",
                                type          = "checkbox",
                                default_value = true,
                                tooltip       = "gt_bot_aid_priority_tooltip",
                            },
                            {
                                setting_id    = "gt_bot_ironbreaker_revive_in_ult",
                                type          = "checkbox",
                                default_value = true,
                                tooltip       = "gt_bot_ironbreaker_revive_in_ult_tooltip",
                            },
                        },
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
                    -- Bot Takeover (handing YOUR hero to bot AI). setting_id
                    -- preserved; /ai command unchanged. NOT gated on the AFK
                    -- toggle -- both are independent takeover controls.
                    {
                        setting_id    = "ai_takeover_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "ai_takeover_enabled_tooltip",
                    },
                    -- Replicant Bots ports (v0.2.131-dev). Host-side, default OFF.
                    -- #320: the drink-potions toggle is now a MASTER with nested
                    -- sub-widgets deciding WHAT counts as danger (VMF native
                    -- master-toggle pattern: children auto-hide while the box is
                    -- unchecked). setting_id preserved so persisted user state
                    -- carries over. Children in feature order (each count slider
                    -- directly under the trigger it tunes), read live in
                    -- _gt_danger_near (no on_setting_changed wiring).
                    {
                        setting_id    = "gt_bot_drink_potions_in_danger",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gt_bot_drink_potions_in_danger_tooltip",
                        sub_widgets   = {
                            {
                                setting_id      = "gt_bot_drink_range_m",
                                type            = "numeric",
                                default_value   = 18,
                                range           = { 5, 40 },
                                decimals_number = 0,
                                tooltip         = "gt_bot_drink_range_m_tooltip",
                            },
                            {
                                setting_id    = "gt_bot_drink_on_boss",
                                type          = "checkbox",
                                default_value = true,
                                tooltip       = "gt_bot_drink_on_boss_tooltip",
                            },
                            {
                                setting_id    = "gt_bot_drink_on_special",
                                type          = "checkbox",
                                default_value = false,
                                tooltip       = "gt_bot_drink_on_special_tooltip",
                            },
                            {
                                setting_id    = "gt_bot_drink_on_patrol",
                                type          = "checkbox",
                                default_value = true,
                                tooltip       = "gt_bot_drink_on_patrol_tooltip",
                            },
                            {
                                setting_id      = "gt_bot_drink_patrol_count",
                                type            = "numeric",
                                default_value   = 3,
                                range           = { 1, 10 },
                                decimals_number = 0,
                                tooltip         = "gt_bot_drink_patrol_count_tooltip",
                            },
                            {
                                setting_id    = "gt_bot_drink_on_horde",
                                type          = "checkbox",
                                default_value = false,
                                tooltip       = "gt_bot_drink_on_horde_tooltip",
                            },
                            {
                                setting_id      = "gt_bot_drink_horde_count",
                                type            = "numeric",
                                default_value   = 8,
                                range           = { 3, 30 },
                                decimals_number = 0,
                                tooltip         = "gt_bot_drink_horde_count_tooltip",
                            },
                        },
                    },
                    {
                        setting_id    = "gt_bot_rescue_awaiting",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gt_bot_rescue_awaiting_tooltip",
                    },
                    -- Bot-roster presence (whether bots exist / where). Still
                    -- runtime kill-switched (#65).
                    {
                        setting_id    = "gt_no_bots",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gt_no_bots_tooltip",
                    },
                    {
                        setting_id    = "gt_bot_fast_reactions",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gt_bot_fast_reactions_tooltip",
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
                    {
                        setting_id    = "gt_improved_bot_combat",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gt_improved_bot_combat_tooltip",
                    },
                },
            },
            -- ============================================================
            -- Cheats and Debug (v0.2.128-dev). Houses godmode + noclip plus
            -- the Buffs & Stats / Ult / Time & Pause / Level Control / Spawners
            -- sub-groups.
            --
            -- ORDER (deliberate, exemption from pure A->Z): the loose headline
            -- cheats (Clear/Disable Enemy Spawns, Godmode, Noclip) stay surfaced
            -- ABOVE the detail sub-groups so the most-used toggles are visible
            -- without expanding a group. Loose primitives A->Z, then nested
            -- sub-groups A->Z (Buffs & Stats, Level Control, Spawners, Time &
            -- Pause, Ult).
            -- ============================================================
            {
                setting_id  = "cheats_debug_group",
                type        = "group",
                sub_widgets = {
                    -- Loose primitives, A->Z:
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
                        setting_id    = "disable_enemy_spawns",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "disable_enemy_spawns_tooltip",
                    },
                    {
                        setting_id    = "godmode_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "godmode_enabled_tooltip",
                    },
                    -- Noclip master toggle -- speed + boost fine-tunes nest under
                    -- it (code reads them only inside the active movement hook,
                    -- _gt_noclip.lua:123-125, so hiding them while off is purely
                    -- visual). The toggle HOTKEY stays a loose sibling below: it
                    -- turns noclip on, so hiding it while noclip is off would hide
                    -- the control needed to enable/bind it.
                    {
                        setting_id    = "noclip_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "noclip_enabled_tooltip",
                        sub_widgets   = {
                            {
                                setting_id      = "noclip_speed",
                                type            = "numeric",
                                default_value   = 15.0,
                                range           = { 1.0, 60.0 },
                                decimals_number = 1,
                                tooltip         = "noclip_speed_tooltip",
                            },
                            {
                                setting_id      = "noclip_boost_multiplier",
                                type            = "numeric",
                                default_value   = 3.0,
                                range           = { 1.0, 10.0 },
                                decimals_number = 1,
                                tooltip         = "noclip_boost_multiplier_tooltip",
                            },
                        },
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
                    -- Nested sub-groups, A->Z:
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
                            {
                                setting_id      = "movement_speed",
                                type            = "numeric",
                                default_value   = 4,
                                range           = { 0, 30 },
                                decimals_number = 1,
                                tooltip         = "movement_speed_tooltip",
                            },
                        },
                    },
                    {
                        setting_id  = "level_control_group",
                        type        = "group",
                        sub_widgets = {
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
                                setting_id      = "fix_sound_hotkey",
                                type            = "keybind",
                                keybind_trigger = "pressed",
                                keybind_type    = "function_call",
                                function_name   = "gt_fix_sound",
                                default_value   = {},
                                tooltip         = "fix_sound_hotkey_tooltip",
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
                                setting_id      = "restart_level_hotkey",
                                type            = "keybind",
                                keybind_trigger = "pressed",
                                keybind_type    = "function_call",
                                function_name   = "gt_restart_level",
                                default_value   = {},
                                tooltip         = "restart_level_hotkey_tooltip",
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
                                setting_id      = "gt_bot_toggle_hotkey",
                                type            = "keybind",
                                keybind_trigger = "pressed",
                                keybind_type    = "function_call",
                                function_name   = "gt_bot_toggle",
                                default_value   = {},
                                tooltip         = "gt_bot_toggle_hotkey_tooltip",
                            },
                            {
                                setting_id      = "win_level_hotkey",
                                type            = "keybind",
                                keybind_trigger = "pressed",
                                keybind_type    = "function_call",
                                function_name   = "gt_win_level",
                                default_value   = {},
                                tooltip         = "win_level_hotkey_tooltip",
                            },
                        },
                    },
                    -- Spawners: collapsible parent grouping Creature Spawner +
                    -- Item Spawner (both A->Z: Creature, Item).
                    {
                        setting_id  = "gt_spawners_group",
                        type        = "group",
                        sub_widgets = {
                            -- Creature Spawner keeps a deliberate WORKFLOW order
                            -- (select list -> spawn -> cycle -> destroy -> saved
                            -- slots 1/2/3 -> AI toggles -> grudge), NOT A->Z. The
                            -- grudge sub_widgets are additionally INDEX-LOCKED: the
                            -- dropdown's `show_widgets = {1}` / `{2..14}` reveal
                            -- arrays reference sub_widget POSITIONS, so reordering
                            -- them would break the reveal mapping. Do not sort.
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
                            -- Item Spawner keeps a deliberate WORKFLOW order
                            -- (next -> prev -> spawn), NOT A->Z.
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
                        },
                    },
                    -- Time & Pause keeps a deliberate FUNCTIONAL order (the time
                    -- controls -- scale, then faster/slower that adjust it --
                    -- then the pause controls), NOT A->Z.
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
                        setting_id  = "ult_group",
                        type        = "group",
                        sub_widgets = {
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
                                setting_id      = "ult_reset_hotkey",
                                type            = "keybind",
                                keybind_trigger = "pressed",
                                keybind_type    = "function_call",
                                function_name   = "gt_ult_reset",
                                default_value   = {},
                                tooltip         = "ult_reset_hotkey_tooltip",
                            },
                        },
                    },
                },
            },
            -- ============================================================
            -- Gameplay. No nested groups (Prioritize Specials + Choose Grail
            -- Knight Quests are master toggles); every member is a loose option,
            -- ordered A->Z by label.
            -- ============================================================
            {
                setting_id  = "gameplay_group",
                type        = "group",
                sub_widgets = {
                    -- "Choose Grail Knight Quests" -- master toggle + 3 quest
                    -- dropdowns (quest1/2/3 kept in numbered order, not A->Z).
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
                    -- "Prioritize Specials (Tagging, Deepwood and Soulstealer)" --
                    -- master toggle. The 3 context sub-toggles default ON; the
                    -- master gates all of them (_gt_prioritize_specials.lua).
                    -- Sub-toggles A->Z (Deepwood Staff, Soulstealer Staff, Tagging).
                    {
                        setting_id    = "gt_prio_specials_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gt_prio_specials_enabled_tooltip",
                        sub_widgets   = {
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
                            {
                                setting_id    = "gt_prio_special_tag",
                                type          = "checkbox",
                                default_value = true,
                                tooltip       = "gt_prio_special_tag_tooltip",
                            },
                        },
                    },
                },
            },
            -- ============================================================
            -- Host-Side Lobby Controls (absorbed from lobby_tweaker
            -- 2026-05-25; lt v0.1.7-dev). All settings namespaced
            -- `gt_lobby_*`; chat commands likewise renamed `/lobby_*`.
            -- Nested sub-group (Modded Lobby Manifest) first, then loose
            -- options A->Z by display label.
            -- ============================================================
            {
                setting_id  = "gt_lobby_controls_group",
                type        = "group",
                sub_widgets = {
                    -- Modded Lobby Manifest -- nested group, so it sits at the TOP.
                    -- Also holds Message of the Day (both are host->joiner
                    -- broadcasts). Loose members A->Z: Broadcast, Send MOTD, Show
                    -- missing mods.
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
                            -- Message of the Day master toggle. The send-mode /
                            -- once-per-peer fine-tunes nest under it: the join
                            -- handler reads them only after the gt_lobby_motd_enabled
                            -- gate (_gt_lobby_motd.lua:183), so hiding them while
                            -- off is purely visual. MOTD text is set via chat:
                            -- /lobby_motd_set <text> (VMF has no string-input widget).
                            -- Sub-toggles A->Z (Only greet once, Send via chat,
                            -- Send via popup).
                            {
                                setting_id    = "gt_lobby_motd_enabled",
                                type          = "checkbox",
                                default_value = false,
                                tooltip       = "gt_lobby_motd_enabled_tooltip",
                                sub_widgets   = {
                                    {
                                        setting_id    = "gt_lobby_motd_once_per_peer_per_session",
                                        type          = "checkbox",
                                        default_value = true,
                                        tooltip       = "gt_lobby_motd_once_per_peer_per_session_tooltip",
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
                                },
                            },
                            {
                                setting_id    = "gt_lobby_manifest_failnotify_enabled",
                                type          = "checkbox",
                                default_value = true,
                                tooltip       = "gt_lobby_manifest_failnotify_enabled_tooltip",
                            },
                        },
                    },
                    -- Loose options, A->Z by display label:
                    -- "Allow Duplicate Careers"
                    {
                        setting_id    = "allow_duplicate_careers",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "allow_duplicate_careers_tooltip",
                    },
                    -- "Auto-kick idle players in keep" -- the idle threshold + warn
                    -- lead-time fine-tunes nest under it: the idle tick reads them
                    -- only after the gt_lobby_kick_idle_enabled gate
                    -- (_gt_lobby_kick_idle.lua:130), so hiding them while off is
                    -- purely visual.
                    {
                        setting_id    = "gt_lobby_kick_idle_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gt_lobby_kick_idle_enabled_tooltip",
                        sub_widgets   = {
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
                        },
                    },
                    -- "Auto-restart mission on team wipe" (setting_id preserved so
                    -- _gt_solo_qol.lua reads + user state carry over)
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
                    -- "Unlock All Ranked Weaves"
                    {
                        setting_id    = "gt_unlock_all_weaves",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gt_unlock_all_weaves_tooltip",
                    },
                },
            },
            -- ============================================================
            -- Info -- on-screen text readouts / warnings (2026-06-29). Widget
            -- IDs preserved (gt_solo_*) so existing user settings carry over.
            -- Loose options A->Z.
            -- ============================================================
            {
                setting_id  = "gt_info_group",
                type        = "group",
                sub_widgets = {
                    { setting_id = "gt_solo_assassin_text_warning",   type = "checkbox", default_value = false, tooltip = "gt_solo_assassin_text_warning_tooltip" },
                    { setting_id = "gt_solo_boss_path_progress",      type = "checkbox", default_value = false, tooltip = "gt_solo_boss_path_progress_tooltip" },
                    { setting_id = "gt_solo_packmaster_text_warning", type = "checkbox", default_value = false, tooltip = "gt_solo_packmaster_text_warning_tooltip" },
                },
            },
            -- ============================================================
            -- Visuals and Audio (was "Solo & QoL"; ported from True Solo QoL
            -- Tweaks; see _gt_solo_qol.lua). setting_ids preserved (gt_solo_* /
            -- gt_more_corpses_count) for user state continuity. All default OFF.
            -- Loose options A->Z.
            -- ============================================================
            {
                setting_id  = "gt_solo_group",  -- display label "Visuals and Audio" (loc); setting_id preserved
                type        = "group",
                sub_widgets = {
                    { setting_id = "gt_solo_assassin_hero_vo",           type = "checkbox", default_value = false, tooltip = "gt_solo_assassin_hero_vo_tooltip" },
                    { setting_id = "gt_solo_disable_downed_fx",          type = "checkbox", default_value = false, tooltip = "gt_solo_disable_downed_fx_tooltip" },
                    { setting_id = "gt_solo_disable_fog",                type = "checkbox", default_value = false, tooltip = "gt_solo_disable_fog_tooltip" },
                    { setting_id = "gt_solo_disable_mutator_explosions", type = "checkbox", default_value = false, tooltip = "gt_solo_disable_mutator_explosions_tooltip" },
                    { setting_id = "gt_solo_disable_sun_shadows",        type = "checkbox", default_value = false, tooltip = "gt_solo_disable_sun_shadows_tooltip" },
                    { setting_id = "gt_solo_disable_ult_fx",             type = "checkbox", default_value = false, tooltip = "gt_solo_disable_ult_fx_tooltip" },
                    { setting_id = "gt_solo_disable_ult_vo",             type = "checkbox", default_value = false, tooltip = "gt_solo_disable_ult_vo_tooltip" },
                    { setting_id = "gt_solo_draw_boss_spheres",          type = "checkbox", default_value = false, tooltip = "gt_solo_draw_boss_spheres_tooltip" },
                    -- Max Ragdolls -- single always-on slider (24 = vanilla default;
                    -- up to 300 for a cinematic pile).
                    {
                        setting_id      = "gt_more_corpses_count",
                        type            = "numeric",
                        default_value   = 24,
                        range           = { 1, 300 },
                        decimals_number = 0,
                        tooltip         = "gt_more_corpses_count_tooltip",
                    },
                    -- Melee Attack Warning (Issue #308) -- client-side windup cue.
                    -- Master checkbox; sub_widgets auto-hide while off. All local
                    -- + cosmetic; changes no gameplay outcome. See _gt_melee_warning.lua.
                    {
                        setting_id    = "gt_melee_warning",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gt_melee_warning_tooltip",
                        sub_widgets   = {
                            {
                                setting_id    = "gt_melee_warning_audio",
                                type          = "checkbox",
                                default_value = true,
                                tooltip       = "gt_melee_warning_audio_tooltip",
                            },
                            {
                                setting_id    = "gt_melee_warning_visual",
                                type          = "checkbox",
                                default_value = true,
                                tooltip       = "gt_melee_warning_visual_tooltip",
                            },
                            {
                                setting_id    = "gt_melee_warning_lead",
                                type          = "dropdown",
                                default_value = 100,
                                options       = {
                                    { text = "gt_melee_warning_lead_0",   value = 0 },
                                    { text = "gt_melee_warning_lead_50",  value = 50 },
                                    { text = "gt_melee_warning_lead_100", value = 100 },
                                    { text = "gt_melee_warning_lead_150", value = 150 },
                                    { text = "gt_melee_warning_lead_200", value = 200 },
                                    { text = "gt_melee_warning_lead_250", value = 250 },
                                },
                                tooltip       = "gt_melee_warning_lead_tooltip",
                            },
                            {
                                setting_id    = "gt_melee_warning_scope",
                                type          = "dropdown",
                                default_value = "elites_only",
                                options       = {
                                    { text = "gt_melee_warning_scope_elites", value = "elites_only" },
                                    { text = "gt_melee_warning_scope_all",    value = "all_melee" },
                                },
                                tooltip       = "gt_melee_warning_scope_tooltip",
                            },
                        },
                    },
                    -- Smooth Health-Bar Damage (Issue #308) -- presentation-only.
                    -- Eases the local player's own health-bar drop. See _gt_hp_smoothing.lua.
                    {
                        setting_id    = "gt_hp_smoothing",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gt_hp_smoothing_tooltip",
                        sub_widgets   = {
                            {
                                setting_id    = "gt_hp_smoothing_ms",
                                type          = "dropdown",
                                default_value = 150,
                                options       = {
                                    { text = "gt_hp_smoothing_ms_100", value = 100 },
                                    { text = "gt_hp_smoothing_ms_150", value = 150 },
                                    { text = "gt_hp_smoothing_ms_200", value = 200 },
                                    { text = "gt_hp_smoothing_ms_250", value = 250 },
                                },
                                tooltip       = "gt_hp_smoothing_ms_tooltip",
                            },
                        },
                    },
                },
            },
        },
    },
}

-- Dev Tools (dev-stream only). The whole group is appended ONLY in the dev clone.
-- `"gt" .. "_dev"` has NO contiguous "gt_dev" substring, so it SURVIVES the
-- dev->stable sed that rewrites the literal `gt_dev` on line 1 to `gt`; in the
-- promoted stable clone `mod` == get_mod("gt") while get_mod("gt".."_dev") resolves
-- to the (absent) dev mod -> nil, so the group is never built and "Dev Tools"
-- simply doesn't exist. VMF loads loc -> data -> script, so `mod` (line 1) is
-- resolved by data-load time. Inserted right after "Cheats and Debug" so the
-- top-level A->Z order (Bots, Cheats and Debug, Dev Tools, Gameplay, Host-Side
-- Lobby Controls, Info, Visuals and Audio) holds. Both toggles default OFF; the
-- feature code (_gt_bot_teleport_lab.lua) also gates on IS_DEV_STREAM + host.
if mod == get_mod("gt" .. "_dev") then
    local widgets = _data.options.widgets
    local insert_at = #widgets + 1
    for i = 1, #widgets do
        if widgets[i].setting_id == "cheats_debug_group" then
            insert_at = i + 1
            break
        end
    end
    table.insert(widgets, insert_at, {
        setting_id  = "gt_devtools_group",
        type        = "group",
        sub_widgets = {
            -- Bot behavior HUD (supersedes the former Bot Teleport Lab D6 head-text).
            -- Host-only; draws one on-screen column per bot.
            {
                setting_id    = "gt_devtools_bot_hud",
                type          = "checkbox",
                default_value = false,
                tooltip       = "gt_devtools_bot_hud_tooltip",
            },
            -- 3D leash lines (former Bot Teleport Lab D7). Host-only, visual.
            {
                setting_id    = "gt_devtools_leash_lines",
                type          = "checkbox",
                default_value = false,
                tooltip       = "gt_devtools_leash_lines_tooltip",
            },
        },
    })
end

return _data
