local mod = get_mod("gut_dev")

-- Dropdown option `text` is a LOC KEY, not literal display text: VMF's options
-- module localizes each option's text at menu-build time (option.text =
-- mod:localize(option.text)), so a literal "Off" would render as "<Off>".
-- A single dropdown references this table, so no per-dropdown factory is needed.
local GUT_HUD_MODE_OPTIONS = {
    { text = "gut_hud_mode_opt_off",      value = "off" },
    { text = "gut_hud_mode_opt_partial",  value = "partial" },
    { text = "gut_hud_mode_opt_complete", value = "complete" },
    { text = "gut_hud_mode_opt_camera",   value = "camera" },
}

return {
    name = "Tweaker: GUI",
    description = mod:localize("mod_description"),
    is_togglable = true,

    options = {
        widgets = {
            -- UI-mod compatibility patches (UI Tweaks Temporal Fix + buff-bar end-time
            -- crash fix) are now IMPLICIT/always-on with no widgets, so the former
            -- "UI Mod Compatibility" group (gut_compat_group) is gone.
            -- HUD group: collapsible wrapper for the parry indicator + respawn timer.
            { setting_id = "gut_hud_group", type = "group", sub_widgets = {
            -- Parry Indicator (absorbed). Recolours the block shields during the
            -- timed-block window for every weapon. RGB sub-sliders pick the colour.
            {
                setting_id  = "gut_parry_indicator",
                type        = "checkbox",
                default_value = false,
                tooltip     = "gut_parry_indicator_tooltip",
                sub_widgets = {
                    {
                        setting_id     = "gut_parry_r",
                        type           = "numeric",
                        range          = { 0, 255 },
                        default_value  = 0,
                        decimals_number = 0,
                        tooltip        = "gut_parry_r",
                    },
                    {
                        setting_id     = "gut_parry_g",
                        type           = "numeric",
                        range          = { 0, 255 },
                        default_value  = 255,
                        decimals_number = 0,
                        tooltip        = "gut_parry_g",
                    },
                    {
                        setting_id     = "gut_parry_b",
                        type           = "numeric",
                        range          = { 0, 255 },
                        default_value  = 120,
                        decimals_number = 0,
                        tooltip        = "gut_parry_b",
                    },
                },
            },
            -- Respawn countdown over a dead teammate's portrait (optional).
            {
                setting_id  = "gut_respawn_timer",
                type        = "checkbox",
                default_value = false,
                tooltip     = "gut_respawn_timer_tooltip",
                sub_widgets = {
                    { setting_id = "gut_respawn_font_size", type = "numeric", range = { 12, 80 },  default_value = 32, decimals_number = 0, tooltip = "gut_respawn_font_size_tooltip" },
                    { setting_id = "gut_respawn_r",         type = "numeric", range = { 0, 255 },  default_value = 255, decimals_number = 0, tooltip = "gut_respawn_r" },
                    { setting_id = "gut_respawn_g",         type = "numeric", range = { 0, 255 },  default_value = 60,  decimals_number = 0, tooltip = "gut_respawn_g" },
                    { setting_id = "gut_respawn_b",         type = "numeric", range = { 0, 255 },  default_value = 60,  decimals_number = 0, tooltip = "gut_respawn_b" },
                },
            },
            -- Floating Damage Numbers (MIGRATED from general_tweaker 2026-06-29).
            -- Client-side, networking-free; takes effect on the next map load.
            -- See _gut_damage_numbers.lua.
            {
                setting_id    = "gut_damage_numbers_enabled",
                type          = "checkbox",
                default_value = false,
                tooltip       = "gut_damage_numbers_enabled_tooltip",
                sub_widgets   = {
                    {
                        setting_id    = "gut_damage_numbers_include_dots",
                        type          = "checkbox",
                        default_value = true,
                        tooltip       = "gut_damage_numbers_include_dots_tooltip",
                    },
                },
            },
            }, },  -- close gut_hud_group sub_widgets + group
            -- Skip Cutscenes (MIGRATED from general_tweaker 2026-06-25, issue #106).
            -- Own self-contained group. Behavior unchanged from gt; adds a printf
            -- [gut:cutscene] diagnostic. See _gut_cutscenes.lua.
            {
                setting_id  = "gut_cutscenes_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "gut_skip_cutscenes_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gut_skip_cutscenes_enabled_tooltip",
                        sub_widgets   = {
                            {
                                setting_id    = "gut_skip_cutscenes_auto",
                                type          = "checkbox",
                                default_value = false,
                                tooltip       = "gut_skip_cutscenes_auto_tooltip",
                            },
                        },
                    },
                    {
                        setting_id      = "gut_skip_cutscenes_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gut_skip_cutscenes_toggle",
                        default_value   = {},
                        tooltip         = "gut_skip_cutscenes_hotkey_tooltip",
                    },
                    -- Disable Loading-Screen Monologues (MIGRATED from
                    -- general_tweaker 2026-06-29, #192). See _gut_monologue.lua.
                    {
                        setting_id    = "gut_disable_intro_monologue",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gut_disable_intro_monologue_tooltip",
                    },
                },
            },
            -- (Config-file override is now IMPLICIT/always-on — see _gut_config_file.lua; no toggle.)
            -- ===== UI Tweaks (HideBuffs) absorbed — Phase 1 =====
            -- Hide UI elements, hide active buffs, loading-screen hides, Hide-HUD
            -- hotkey. Setting ids kept verbatim from HideBuffs so the forked hb/
            -- hooks (which read mod:get(SETTING_NAMES.<id>)) resolve.
            {
                setting_id  = "hb_group",
                type        = "group",
                sub_widgets = {
                    { setting_id = "force_default_frame",            type = "checkbox", default_value = false, tooltip = "force_default_frame_tooltip" },
                    { setting_id = "UNOBTRUSIVE_FLOATING_OBJECTIVE", type = "checkbox", default_value = false, tooltip = "UNOBTRUSIVE_FLOATING_OBJECTIVE_tooltip" },
                    { setting_id = "UNOBTRUSIVE_MISSION_TOOLTIP",    type = "checkbox", default_value = false, tooltip = "UNOBTRUSIVE_MISSION_TOOLTIP_tooltip" },
                    {
                        setting_id  = "HIDE_UI_ELEMENTS_GROUP",
                        type        = "group",
                        sub_widgets = {
                            { setting_id = "HIDE_HUD_WHEN_INSPECTING",     type = "checkbox", default_value = false, tooltip = "HIDE_HUD_WHEN_INSPECTING_tooltip" },
                            { setting_id = "HIDE_HUD_HOTKEY", type = "keybind", default_value = {}, keybind_trigger = "pressed", keybind_type = "function_call", function_name = "hide_hud", tooltip = "HIDE_HUD_HOTKEY_tooltip" },
                            { setting_id = "no_tutorial_ui",               type = "checkbox", default_value = false, tooltip = "no_tutorial_ui_tooltip" },
                            { setting_id = "no_mission_objective",         type = "checkbox", default_value = false, tooltip = "no_mission_objective_tooltip" },
                            { setting_id = "hide_frames",                  type = "checkbox", default_value = false, tooltip = "hide_frames_tooltip" },
                            { setting_id = "hide_levels",                  type = "checkbox", default_value = false, tooltip = "hide_levels_tooltip" },
                            { setting_id = "HIDE_BOSS_HP_BAR",             type = "checkbox", default_value = false, tooltip = "HIDE_BOSS_HP_BAR_tooltip" },
                            { setting_id = "HIDE_PICKUP_OUTLINES",         type = "checkbox", default_value = false, tooltip = "HIDE_PICKUP_OUTLINES_tooltip" },
                            { setting_id = "HIDE_OTHER_OUTLINES",          type = "checkbox", default_value = false, tooltip = "HIDE_OTHER_OUTLINES_tooltip" },
                            { setting_id = "HIDE_NEW_AREA_TEXT",           type = "checkbox", default_value = false, tooltip = "HIDE_NEW_AREA_TEXT_tooltip" },
                            { setting_id = "HIDE_LOADING_SCREEN_TIPS",     type = "checkbox", default_value = false, tooltip = "HIDE_LOADING_SCREEN_TIPS_tooltip" },
                            { setting_id = "HIDE_LOADING_SCREEN_SUBTITLES",type = "checkbox", default_value = false, tooltip = "HIDE_LOADING_SCREEN_SUBTITLES_tooltip" },
                            { setting_id = "DISABLE_LEVEL_INTRO_AUDIO",    type = "checkbox", default_value = false, tooltip = "DISABLE_LEVEL_INTRO_AUDIO_tooltip" },
                            { setting_id = "DISABLE_OLESYA_UBERSREIK_AUDIO",type = "checkbox", default_value = false, tooltip = "DISABLE_OLESYA_UBERSREIK_AUDIO_tooltip" },
                            { setting_id = "HIDE_WAITING_FOR_RESCUE",      type = "checkbox", default_value = false, tooltip = "HIDE_WAITING_FOR_RESCUE_tooltip" },
                            { setting_id = "HIDE_TWITCH_MODE_ON_ICON",     type = "checkbox", default_value = false, tooltip = "HIDE_TWITCH_MODE_ON_ICON_tooltip" },
                            { setting_id = "STOP_WHITE_HP_FLASHING",       type = "checkbox", default_value = false, tooltip = "STOP_WHITE_HP_FLASHING_tooltip" },
                        },
                    },
                    {
                        setting_id  = "HIDE_BUFFS_GROUP",
                        type        = "group",
                        sub_widgets = {
                            { setting_id = "victor_bountyhunter_passive_infinite_ammo_buff",   type = "checkbox", default_value = false, tooltip = "victor_bountyhunter_passive_infinite_ammo_buff_tooltip" },
                            { setting_id = "grimoire_health_debuff",                           type = "checkbox", default_value = false, tooltip = "grimoire_health_debuff_tooltip" },
                            { setting_id = "markus_huntsman_passive_crit_aura_buff",           type = "checkbox", default_value = false, tooltip = "markus_huntsman_passive_crit_aura_buff_tooltip" },
                            { setting_id = "markus_knight_passive_defence_aura",               type = "checkbox", default_value = false, tooltip = "markus_knight_passive_defence_aura_tooltip" },
                            { setting_id = "kerillian_waywatcher_passive",                     type = "checkbox", default_value = false, tooltip = "kerillian_waywatcher_passive_tooltip" },
                            { setting_id = "kerillian_maidenguard_passive_stamina_regen_buff", type = "checkbox", default_value = false, tooltip = "kerillian_maidenguard_passive_stamina_regen_buff_tooltip" },
                            { setting_id = "HIDE_WHC_GRIMOIRE_POWER_BUFF",                     type = "checkbox", default_value = false, tooltip = "HIDE_WHC_GRIMOIRE_POWER_BUFF_tooltip" },
                            { setting_id = "HIDE_SHADE_GRIMOIRE_POWER_BUFF",                   type = "checkbox", default_value = false, tooltip = "HIDE_SHADE_GRIMOIRE_POWER_BUFF_tooltip" },
                            { setting_id = "HIDE_ZEALOT_HOLY_CRUSADER_BUFF",                   type = "checkbox", default_value = false, tooltip = "HIDE_ZEALOT_HOLY_CRUSADER_BUFF_tooltip" },
                        },
                    },
                },
            },
            -- Hide UI (3 modes) — migrated from general_tweaker. Cycle
            -- off → partial → complete → camera via dropdown, /hud, or hotkey.
            {
                setting_id  = "gut_hud_visibility_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "gut_hud_mode",
                        type          = "dropdown",
                        default_value = "off",
                        options       = GUT_HUD_MODE_OPTIONS,
                        tooltip       = "gut_hud_mode_tooltip",
                    },
                    {
                        setting_id      = "gut_hud_cycle_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gut_hud_cycle",
                        default_value   = {},
                        tooltip         = "gut_hud_cycle_hotkey_tooltip",
                    },
                },
            },
            -- (#93) The Compact ESC/keep menu fix is now an ALWAYS-ON implicit feature
            -- (the toggle was removed 2026-06-24) — gut adds the ESC button that causes
            -- the overflow, so the fix always runs. See the
            -- HeroWindowIngameView._update_presentation hook in gui_tweaker_dev.lua.
            -- In-mission inventory access (migrated from general_tweaker 2026-06-24).
            -- Own self-contained group. See _gut_mission_inventory.lua.
            {
                setting_id  = "gut_mission_inventory_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "gut_mission_inventory_enabled",
                        type          = "checkbox",
                        default_value = true,   -- #87: on by default
                        tooltip       = "gut_mission_inventory_enabled_tooltip",
                    },
                    {
                        setting_id    = "gut_mission_menu_tabs",
                        type          = "checkbox",
                        default_value = true,   -- #87: on by default
                        tooltip       = "gut_mission_menu_tabs_tooltip",
                    },
                    {
                        setting_id      = "gut_open_inv_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gut_open_mission_inventory",
                        default_value   = {},
                        tooltip         = "gut_open_inv_hotkey_tooltip",
                    },
                },
            },
            -- In-mission HERO SELECT (sibling of the inventory group, 2026-06-24).
            -- Own self-contained group. Opens the HeroView TALENTS layout mid-mission
            -- (live-safe: talents apply immediately, no respawn). Career PICK is
            -- keep-only by design (mid-mission career change is unsafe). See
            -- _gut_mission_hero_select.lua.
            {
                setting_id  = "gut_mission_hero_select_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "gut_mission_hero_select_enabled",
                        type          = "checkbox",
                        default_value = true,   -- ON by default
                        tooltip       = "gut_mission_hero_select_enabled_tooltip",
                    },
                    {
                        setting_id      = "gut_open_hero_select_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gut_open_mission_hero_select",
                        default_value   = {},
                        tooltip         = "gut_open_hero_select_hotkey_tooltip",
                    },
                },
            },
            -- Mod Tweaker open hotkey (#125). The Mod Tweaker settings menu can
            -- already be opened from the ESC menu's "Mod Tweaker" button; this adds a
            -- direct function-call keybind (default UNBOUND) + the /mod_tweaker
            -- command, both routing through mod.gut_open_mod_tweaker. Works in the keep
            -- and mid-mission; exiting returns to the game (#124).
            {
                setting_id  = "gut_mod_tweaker_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id      = "gut_open_mod_tweaker_hotkey",
                        type            = "keybind",
                        keybind_trigger = "pressed",
                        keybind_type    = "function_call",
                        function_name   = "gut_open_mod_tweaker",
                        default_value   = {},
                        tooltip         = "gut_open_mod_tweaker_hotkey_tooltip",
                    },
                    {
                        setting_id    = "gut_mt_auto_collapse",
                        type          = "checkbox",
                        default_value = true,
                        tooltip       = "gut_mt_auto_collapse_tooltip",
                    },
                },
            },
            -- Main Menu & Startup (MIGRATED from general_tweaker 2026-06-29, #190).
            -- Both default OFF; plain engine-data reassignments (no hooks). See
            -- _gut_mainmenu.lua.
            {
                setting_id  = "gut_mainmenu_group",
                type        = "group",
                sub_widgets = {
                    { setting_id = "gut_skip_start_screen",    type = "checkbox", default_value = false, tooltip = "gut_skip_start_screen_tooltip" },
                    { setting_id = "gut_return_to_menu_quits", type = "checkbox", default_value = false, tooltip = "gut_return_to_menu_quits_tooltip" },
                },
            },
            -- 3rd-Person Camera (MIGRATED from general_tweaker 2026-06-29, #191).
            -- Camera Distance min stays at -3.0 (issue #147: allow closer /
            -- over-shoulder views below 1.0). See _gut_camera.lua.
            {
                setting_id  = "gut_camera_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "gut_tp_camera_enabled",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gut_tp_camera_enabled_tooltip",
                    },
                    {
                        setting_id    = "gut_tp_distance",
                        type          = "numeric",
                        default_value = 3.0,
                        range         = { -3.0, 10.0 },   -- #147: min lowered 1.0 -> -3.0 (allow closer / over-shoulder views)
                        decimals_number = 1,
                        tooltip       = "gut_tp_distance_tooltip",
                    },
                    {
                        setting_id    = "gut_tp_height",
                        type          = "numeric",
                        default_value = 1.0,
                        range         = { -1.0, 5.0 },
                        decimals_number = 1,
                        tooltip       = "gut_tp_height_tooltip",
                    },
                    {
                        setting_id    = "gut_tp_side_offset",
                        type          = "numeric",
                        default_value = 0.8,
                        range         = { -3.0, 3.0 },
                        decimals_number = 1,
                        tooltip       = "gut_tp_side_offset_tooltip",
                    },
                    {
                        setting_id    = "gut_tp_disable_zoom_in",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gut_tp_disable_zoom_in_tooltip",
                    },
                },
            },
        },
    },
}
