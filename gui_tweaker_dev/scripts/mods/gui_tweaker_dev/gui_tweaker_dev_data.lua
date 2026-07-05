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

-- UI-mod compatibility patches (UI Tweaks Temporal Fix + buff-bar end-time crash
-- fix) and the .toml config-file override are now IMPLICIT/always-on with no
-- widgets, so the former "UI Mod Compatibility" group (gut_compat_group), the
-- gut_buffbar_endtime_fix toggle, and gut_config_override are gone. Debug logging
-- is routed through VMF's own output_mode gates (PROJECT_STANDARDS § 3.6), so
-- there is no enable_debug_logging widget either.
--
-- Top-level groups are ordered A->Z by their English display label (repo standing
-- rule). "3rd-Person Camera" leads because the label begins with a digit.

-- Load-order-safe cim-presence detector (pattern ported from cim's former #96
-- `_gut_present()`, which gated cim's old bench widget on gut - now inverted: the
-- bench option lives HERE and is gated on cim). `get_mod` alone is load-order
-- fragile (VMF unfolds this data table at gut's registration; cim may not have
-- registered yet), so fall back to the engine ModManager manifest, which is built
-- from the full enabled-mod list BEFORE any mod's Lua runs (mod_manager.lua:278-343;
-- entries carry Workshop title `name` + `enabled`). "Crafting in Modded" covers cim
-- and cim_dev (both Workshop titles start with it).
local function _cim_present()
    if get_mod("cim") or get_mod("cim_dev") then
        return true
    end
    local mod_mgr = rawget(_G, "Managers") and Managers.mod
    local mods = mod_mgr and mod_mgr._mods
    if type(mods) == "table" then
        for i = 1, (mod_mgr._num_mods or #mods) do
            local entry = mods[i]
            if entry and entry.enabled and type(entry.name) == "string"
               and entry.name:find("Crafting in Modded", 1, true) then
                return true
            end
        end
    end
    return false
end

local options_data = {
    name = "Tweaker: GUI",
    description = mod:localize("mod_description"),
    is_togglable = true,

    options = {
        widgets = {
            -- ================================================================
            -- 3rd-Person Camera (MIGRATED from general_tweaker 2026-06-29, #191)
            -- ================================================================
            -- Deliberate order: enable -> distance -> height -> side offset ->
            -- zoom (camera-rig ordering, NOT A->Z). Camera Distance min stays at
            -- -3.0 (issue #147: allow closer / over-shoulder views below 1.0).
            -- See _gut_camera.lua.
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
            -- ================================================================
            -- HUD (reorg 2026-07-02 per user direction: the former "On-Screen
            -- Overlays" category is deleted and its widgets live here - overlays
            -- like the parry indicator and respawn-over-portrait timer modify HUD
            -- elements, so one HUD category. setting_id kept: gut_hide_hud_ui_group.)
            -- ================================================================
            -- Deliberate order (NOT A->Z): the HUD-mode dropdown + its cycle
            -- hotkey sit at the top, then the "Hide UI Elements & Buffs" sub-tree
            -- (absorbed HideBuffs/"UI Tweaks"), then the overlay master toggles.
            -- Setting ids kept verbatim (HideBuffs fork hooks read
            -- mod:get(SETTING_NAMES.<id>)); only labels changed.
            {
                setting_id  = "gut_hide_hud_ui_group",
                type        = "group",
                sub_widgets = {
                    -- (a) Hide UI (3 modes) — migrated from general_tweaker.
                    -- Cycle off -> partial -> complete -> camera via dropdown,
                    -- /hud, or hotkey. (Container gut_hud_visibility_group was
                    -- dissolved into this group; its members live here directly.)
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
                    -- (b/c/d) UI Tweaks (HideBuffs) absorbed. Setting ids kept
                    -- verbatim from HideBuffs so the forked hb/ hooks resolve.
                    {
                        setting_id  = "hb_group",
                        type        = "group",
                        sub_widgets = {
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
                            -- (d) Formerly-loose hb toggles, now grouped.
                            {
                                setting_id  = "gut_hb_misc_group",
                                type        = "group",
                                sub_widgets = {
                                    { setting_id = "force_default_frame",            type = "checkbox", default_value = false, tooltip = "force_default_frame_tooltip" },
                                    { setting_id = "UNOBTRUSIVE_FLOATING_OBJECTIVE", type = "checkbox", default_value = false, tooltip = "UNOBTRUSIVE_FLOATING_OBJECTIVE_tooltip" },
                                    { setting_id = "UNOBTRUSIVE_MISSION_TOOLTIP",    type = "checkbox", default_value = false, tooltip = "UNOBTRUSIVE_MISSION_TOOLTIP_tooltip" },
                                },
                            },
                        },
                    },
                    -- UI Tweaks Integration (#312). gut_uitweaks_sync: when UI Tweaks
                    -- (HideBuffs) is installed + enabled, the HUD drag editor writes UI
                    -- Tweaks' offsets for the buff/boss/overcharge/energy bars instead of
                    -- gut's own, so the two never stack (see _gut_uitweaks_sync.lua).
                    -- The two vanilla mirrors reflect the base game's Gameplay > HUD
                    -- Customization numeric options into gut's menu (write-through in
                    -- on_setting_changed; seeded from the engine at on_all_mods_loaded).
                    {
                        setting_id  = "gut_uitweaks_integration_group",
                        type        = "group",
                        sub_widgets = {
                            {
                                setting_id    = "gut_uitweaks_sync",
                                type          = "checkbox",
                                default_value = true,
                                tooltip       = "gut_uitweaks_sync_tooltip",
                            },
                            {
                                setting_id    = "gut_vanilla_numeric_ui",
                                type          = "checkbox",
                                default_value = false,
                                tooltip       = "gut_vanilla_numeric_ui_tooltip",
                            },
                            {
                                setting_id    = "gut_vanilla_persistent_ammo",
                                type          = "checkbox",
                                default_value = false,
                                tooltip       = "gut_vanilla_persistent_ammo_tooltip",
                            },
                        },
                    },
                    -- Overlays (former "On-Screen Overlays" category, deleted in the
                    -- 2026-07-02 reorg). Parry-block colour, respawn countdown over a
                    -- portrait, floating damage numbers - each an independent master
                    -- toggle with fine-tune sub-widgets.
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
                },
            },
            -- ================================================================
            -- In-Mission Menus (collapsible; reorg 2026-07-02 per user direction)
            -- ================================================================
            -- Wraps the two mid-mission menu features. Setting_ids unchanged, so
            -- existing user settings carry over.
            -- Hero Select (#173): opens the REAL CharacterSelectionView mid-mission;
            --   keep-only backdrop swapped to the inventory-preview world; career
            --   swap respawns IN PLACE. Blocked in Chaos Wastes.
            --   See _gut_mission_hero_select.lua.
            -- Inventory (migrated from general_tweaker 2026-06-24): see
            --   _gut_mission_inventory.lua.
            {
                setting_id  = "gut_inmission_menus_group",
                type        = "group",
                sub_widgets = {
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
                    -- In-Mission Mission Map (#305): opens the start-game /
                    -- mission-selection view (the keep "M" map) mid-mission. Master
                    -- checkbox with auto-hiding sub_widgets (keybind default "M" +
                    -- host-only toggle). Adventure only; blocked in Chaos
                    -- Wastes/Versus. See _gut_mission_map.lua.
                    {
                        setting_id    = "gut_mission_map",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gut_mission_map_tooltip",
                        sub_widgets   = {
                            {
                                setting_id      = "gut_mission_map_hotkey",
                                type            = "keybind",
                                keybind_trigger = "pressed",
                                keybind_type    = "function_call",
                                function_name   = "gut_open_mission_map",
                                default_value   = {"m"},
                                tooltip         = "gut_mission_map_hotkey_tooltip",
                            },
                            {
                                setting_id    = "gut_mission_map_host_only",
                                type          = "checkbox",
                                default_value = false,
                                tooltip       = "gut_mission_map_host_only_tooltip",
                            },
                        },
                    },
                    -- Allow crafting bench in mission (moved FROM cim 2026-07-02,
                    -- user direction). Shown ONLY when Crafting in Modded is
                    -- installed (pruned below via _cim_present(), same treatment
                    -- as cosmetics-gated options). gut writes through to cim's
                    -- `allow_in_mission` setting on change + at load (main lua),
                    -- so cim's open_forge/open_standard_crafting gates are
                    -- untouched.
                    {
                        setting_id    = "gut_cim_bench_in_mission",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gut_cim_bench_in_mission_tooltip",
                    },
                },
            },
            -- ================================================================
            -- Loadout Manager -- issue #175
            -- ================================================================
            -- The modded-scoped native loadout store itself is INTRINSIC/implicit
            -- (always on in the modded realm, no toggle - user direction 2026-07-02;
            -- the former gut_native_loadouts_group/_enabled widgets are gone). This
            -- group holds loadout MANAGEMENT options; more coming later.
            -- gut_use_non_modded_loadouts ON = modded reads your non-modded (official)
            -- loadouts read-only: gameplay writes (gear/talents/loadout switch/bot) are
            -- blocked and snap back; cosmetics (illusion/hat/frame/pose) stay editable
            -- modded-side (issue #287). OFF (default) = modded loadouts stored separately.
            {
                setting_id  = "gut_loadout_manager_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "gut_use_non_modded_loadouts",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "gut_use_non_modded_loadouts_tooltip",
                    },
                },
            },
            -- ================================================================
            -- Main Menu & Startup (MIGRATED from general_tweaker 2026-06-29, #190;
            -- Cutscenes & Monologues nested here in the 2026-07-02 reorg)
            -- ================================================================
            -- Startup toggles default OFF; plain engine-data reassignments (no
            -- hooks). See _gut_mainmenu.lua. Cutscenes sub-group: skip-cutscenes
            -- master + hotkey + loading-screen monologue toggle (issues #106/#192,
            -- setting_ids unchanged). See _gut_cutscenes.lua / _gut_monologue.lua.
            {
                setting_id  = "gut_mainmenu_group",
                type        = "group",
                sub_widgets = {
                    { setting_id = "gut_skip_start_screen",    type = "checkbox", default_value = false, tooltip = "gut_skip_start_screen_tooltip" },
                    { setting_id = "gut_return_to_menu_quits", type = "checkbox", default_value = false, tooltip = "gut_return_to_menu_quits_tooltip" },
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
                            -- Disable Loading-Screen Monologues (#192). See _gut_monologue.lua.
                            {
                                setting_id    = "gut_disable_intro_monologue",
                                type          = "checkbox",
                                default_value = false,
                                tooltip       = "gut_disable_intro_monologue_tooltip",
                            },
                        },
                    },
                },
            },
            -- ================================================================
            -- Mod Tweaker open hotkey (#125)
            -- ================================================================
            -- The Mod Tweaker settings menu can already be opened from the ESC
            -- menu's "Mod Tweaker" button; this adds a direct function-call
            -- keybind (default UNBOUND) + the /mod_tweaker command, both routing
            -- through mod.gut_open_mod_tweaker. Works in the keep and mid-mission;
            -- exiting returns to the game (#124).
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
        },
    },
}

-- Prune the cim-gated bench option when Crafting in Modded is absent (without cim
-- there is no bench to open, so the toggle would only confuse - mirror of cim's
-- former #96 prune, target inverted).
if not _cim_present() then
    local widgets = options_data.options and options_data.options.widgets
    for _, group in ipairs(widgets or {}) do
        if group.setting_id == "gut_inmission_menus_group" and type(group.sub_widgets) == "table" then
            for i = #group.sub_widgets, 1, -1 do
                if group.sub_widgets[i].setting_id == "gut_cim_bench_in_mission" then
                    table.remove(group.sub_widgets, i)
                end
            end
            break
        end
    end
end

return options_data
