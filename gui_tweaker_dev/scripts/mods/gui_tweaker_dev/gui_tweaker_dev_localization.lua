return {
    mod_description = {
        en = "Quality-of-life tweaks for the Vermintide 2 hero and character menus: save and swap loadouts, hide HUD elements, third-person camera, skip cutscenes, and more.",
    },

    -- ESC-menu button label. Injected by the IngameViewLayoutLogic.setup_button_layout
    -- hook in gui_tweaker.lua; the button widget style has localize=true
    -- (vanilla ingame_view.lua:138-140 + :252), so display_name MUST be a real
    -- loc key. (display_name_func is a dead vanilla field, never invoked in the
    -- decompiled ingame_view render path, so the literal there did not render.)
    mod_tweaker_button_name = {
        en = "Mod Tweaker",
    },

    -- ============================================================
    -- 3rd-Person Camera (migrated from general_tweaker 2026-06-29, #191)
    -- ============================================================
    gut_camera_group = {
        en = "[working] 3rd-Person Camera",
    },
    gut_tp_camera_enabled = {
        en = "[Issue 209] Enable Third-Person Camera",
    },
    gut_tp_camera_enabled_tooltip = {
        en = "Turns on a third-person camera view. Can also be toggled with the /tp chat command.",
    },
    gut_tp_distance = {
        en = "[working] Camera Distance",
    },
    gut_tp_distance_tooltip = {
        en = "How far behind your character the camera sits.",
    },
    gut_tp_height = {
        en = "[working] Camera Height",
    },
    gut_tp_height_tooltip = {
        en = "How far above your character the camera sits.",
    },
    gut_tp_side_offset = {
        en = "[working] Side Offset",
    },
    gut_tp_side_offset_tooltip = {
        en = "Sideways offset of the camera (positive is right, negative is left).",
    },
    gut_tp_disable_zoom_in = {
        en = "[working] Disable Aim Zoom-In",
    },
    gut_tp_disable_zoom_in_tooltip = {
        en = "When on, aiming or throwing no longer pulls the third-person camera in close, so it stays at your chosen distance and height. Useful for watching weapon animations.",
    },
    gut_freecam_enabled = {
        en = "Free Camera",
    },
    gut_freecam_enabled_tooltip = {
        en = "Detaches the camera so you can fly around and view the level. Your character stops responding to input and stays put. Controls: WASD to move, mouse to look, E and Q for up and down, mouse wheel to change speed. Press F8 to exit (while active, the camera has all input, so the menu, chat and other keys will not respond until you press F8). Turning it on from inside a menu starts the camera after the menu closes. Also toggled with the /freecam chat command.",
    },
    gut_freecam_hotkey = {
        en = "Free Camera (Hotkey)",
    },
    gut_freecam_hotkey_tooltip = {
        en = "Hotkey to turn the Free Camera on. Same as the /freecam chat command. To turn it off, press F8 (input is blocked to everything except the camera while it is active).",
    },

    -- ============================================================
    -- Cutscenes & Monologues (migrated from general_tweaker 2026-06-25, #106;
    -- monologue toggle migrated 2026-06-29, #192)
    -- ============================================================
    gut_cutscenes_group = {
        en = "[working] Cutscenes & Monologues",
    },
    gut_skip_cutscenes_enabled = {
        en = "Skip Cutscenes",
    },
    gut_skip_cutscenes_enabled_tooltip = {
        en = "Lets you skip cutscenes with ESC or Space (or the /skipcutscenes command), even ones the game normally will not let you skip. Boss and phase cinematics that the level gives no built-in skip path (for example Nurgloth on The Enchanter's Lair) are left to play out, because skipping them can desync the fight.",
    },
    gut_skip_cutscenes_auto = {
        en = "Auto-skip Cutscenes",
    },
    gut_skip_cutscenes_auto_tooltip = {
        en = "When on, cutscenes are skipped automatically the moment they start, so you never see them. Leave off to skip them manually with ESC or Space.",
    },
    gut_skip_cutscenes_hotkey = {
        en = "[Issue 126] [verify-fix] [diag] Toggle Skip Cutscenes (Hotkey)",
    },
    gut_skip_cutscenes_hotkey_tooltip = {
        en = "Hotkey to turn the Skip Cutscenes option on or off. Same as the /skipcutscenes chat command.",
    },
    gut_disable_intro_monologue = {
        en = "[working] Disable Loading-Screen Monologues",
    },
    gut_disable_intro_monologue_tooltip = {
        en = "Silences the Lohner, Olesya and weave voice lines that play during the level loading screen. Chat: /intromono.",
    },

    -- ============================================================
    -- Hide HUD & UI (umbrella folding the HUD-visibility dropdown + the absorbed
    -- HideBuffs "UI Tweaks" area)
    -- ============================================================
    gut_hide_hud_ui_group = {
        -- Reorg 2026-07-02: former "Hide HUD & UI"; now the single HUD category
        -- (absorbed the deleted "On-Screen Overlays"). setting_id unchanged.
        en = "[working] HUD",
    },

    -- Hide UI (3 modes) — migrated from general_tweaker.
    gut_hud_mode = {
        en = "[working] HUD Visibility Mode",
    },
    gut_hud_mode_tooltip = {
        en = "Controls how much of the HUD is hidden: Off shows everything, Partial hides most UI but keeps prompts and subtitles, Complete hides everything for screenshots, and Camera also hides your first-person arms and weapon.",
    },
    -- Dropdown option labels for gut_hud_mode (VMF localizes each option's text).
    gut_hud_mode_opt_off      = { en = "Off" },
    gut_hud_mode_opt_partial  = { en = "Partial" },
    gut_hud_mode_opt_complete = { en = "Complete" },
    gut_hud_mode_opt_camera   = { en = "Camera" },
    gut_hud_cycle_hotkey = {
        en = "[working] Cycle HUD Mode",
    },
    gut_hud_cycle_hotkey_tooltip = {
        en = "Hotkey to cycle the HUD mode through Off, Partial, Complete and Camera. Same as the /hud chat command.",
    },
    -- HUD edit-mode keybind (#310): bind a key to enter/exit the click-drag HUD
    -- customizer. Same as the /edit_hud chat command.
    gut_edit_hud_hotkey = {
        en = "[untested] Enter HUD Edit Mode",
    },
    gut_edit_hud_hotkey_tooltip = {
        en = "Hotkey to enter or exit HUD edit mode, where you click and drag HUD elements to reposition them. Same as the /edit_hud chat command.",
    },
    -- Retained: gut_hud_visibility_group was the standalone "Hide UI" container.
    -- Its members (dropdown + cycle hotkey) now sit directly under
    -- gut_hide_hud_ui_group, so this label is no longer referenced by a widget.
    -- Kept (not deleted) per the localization orphan policy.
    gut_hud_visibility_group = {
        en = "Hide UI",
    },

    -- Sync + vanilla-mirror subgroup, now nested UNDER the "UI Tweaks" group
    -- (hb_group) per user direction, so all UI Tweaks options share one heading.
    -- Renamed from "UI Tweaks Integration" (the parent is already "UI Tweaks", so
    -- an "integration" sub-label would be redundant): drag-editor write-through to
    -- the standalone UI Tweaks mod + two vanilla HUD-numeric mirrors.
    gut_uitweaks_integration_group = { en = "[untested] Sync & Vanilla Mirrors" },
    gut_uitweaks_sync              = { en = "[untested] UI Tweaks Owns HUD Elements" },
    gut_uitweaks_sync_tooltip      = { en = "With UI Tweaks (HideBuffs) installed, the HUD editor moves the buff, boss health, overcharge, and energy bars through UI Tweaks so the two never conflict. Requires UI Tweaks." },
    gut_vanilla_numeric_ui         = { en = "[untested] Numeric Health, Ammo, Cooldown" },
    gut_vanilla_numeric_ui_tooltip = { en = "Mirrors the vanilla Gameplay > HUD Customization option. Shows numeric health, ammo, and cooldown on the unit frames. Takes effect immediately." },
    gut_vanilla_persistent_ammo         = { en = "[untested] Always Show Ammo Counter" },
    gut_vanilla_persistent_ammo_tooltip = { en = "Mirrors the vanilla Gameplay > HUD Customization option. Keeps your own ammo counter always visible. Requires a game restart." },

    -- Renamed to "UI Tweaks" (was "Hide UI Elements & Buffs"): this group is now
    -- the SINGLE home for all UI Tweaks options (the absorbed HideBuffs tree plus
    -- the #312 "Sync & Vanilla Mirrors" subgroup nested under it). setting_id
    -- (hb_group) unchanged so the fork hooks resolve. #281 tag = the hb/ load bug.
    hb_group               = { en = "[Issue 281] UI Tweaks" },
    HIDE_UI_ELEMENTS_GROUP = { en = "[working] Hide UI Elements" },
    HIDE_BUFFS_GROUP       = { en = "[working] Hide Active Buffs" },

    HIDE_HUD_WHEN_INSPECTING         = { en = "[working] Hide HUD When Inspecting Hero" },
    HIDE_HUD_WHEN_INSPECTING_tooltip = { en = "Hides the HUD, and outlines, while you are inspecting a hero." },
    HIDE_HUD_HOTKEY                  = { en = "[working] Hide HUD Hotkey" },
    HIDE_HUD_HOTKEY_tooltip          = { en = "Toggle HUD visibility." },
    no_tutorial_ui                   = { en = "[working] Hide Floating Objective Marker" },
    no_tutorial_ui_tooltip           = { en = "Hides objective markers such as \"Set Free\" that appear over downed players." },
    no_mission_objective             = { en = "[working] Hide Mission Objective" },
    no_mission_objective_tooltip     = { en = "Hide the mission objective shown at the top of the screen." },
    hide_frames                      = { en = "[working] Hide Portrait Frames" },
    hide_frames_tooltip              = { en = "Hide portrait frames." },
    hide_levels                      = { en = "[working] Hide Player Levels" },
    hide_levels_tooltip              = { en = "Hide player levels." },
    HIDE_BOSS_HP_BAR                 = { en = "[working] Hide Boss HP Bar" },
    HIDE_BOSS_HP_BAR_tooltip         = { en = "Hide the health bar on bosses." },
    HIDE_PICKUP_OUTLINES             = { en = "[working] Hide Pickup Outlines" },
    HIDE_PICKUP_OUTLINES_tooltip     = { en = "Hides the white outline around pickups. Items already spawned in the level are not affected." },
    HIDE_OTHER_OUTLINES              = { en = "[working] Hide Objective Outlines" },
    HIDE_OTHER_OUTLINES_tooltip      = { en = "Hides the white outline around objective items. Items already spawned in the level are not affected." },
    HIDE_NEW_AREA_TEXT               = { en = "[working] Hide New Area Popup" },
    HIDE_NEW_AREA_TEXT_tooltip       = { en = "Hide the location-name popup shown when you enter a new area." },
    HIDE_LOADING_SCREEN_TIPS         = { en = "[working] Hide Level Intro Tips" },
    HIDE_LOADING_SCREEN_TIPS_tooltip = { en = "Hide the tips on the map loading screen." },
    HIDE_LOADING_SCREEN_SUBTITLES    = { en = "[working] Hide Level Intro Subtitles" },
    HIDE_LOADING_SCREEN_SUBTITLES_tooltip = { en = "Hide the subtitles on the map loading screen." },
    DISABLE_LEVEL_INTRO_AUDIO        = { en = "[working] Disable Level Intro Audio" },
    DISABLE_LEVEL_INTRO_AUDIO_tooltip = { en = "Disable Lohner's spoken level intro." },
    DISABLE_OLESYA_UBERSREIK_AUDIO   = { en = "[working] Disable Olesya Ubersreik Audio" },
    DISABLE_OLESYA_UBERSREIK_AUDIO_tooltip = { en = "Disable Olesya's lines in the Ubersreik maps." },
    HIDE_WAITING_FOR_RESCUE          = { en = "[working] Hide Waiting For Rescue Message" },
    HIDE_WAITING_FOR_RESCUE_tooltip  = { en = "Hide the message shown while you wait to be rescued." },
    HIDE_TWITCH_MODE_ON_ICON         = { en = "[working] Hide Twitch Mode Icon" },
    HIDE_TWITCH_MODE_ON_ICON_tooltip = { en = "Hide the Twitch logo and connection icon in the lower right during Twitch mode." },
    STOP_WHITE_HP_FLASHING           = { en = "[working] Stop White HP Flashing" },
    STOP_WHITE_HP_FLASHING_tooltip   = { en = "Stop the white flashing on temporary health." },

    victor_bountyhunter_passive_infinite_ammo_buff         = { en = "[working] Bounty Hunter Passive" },
    victor_bountyhunter_passive_infinite_ammo_buff_tooltip = { en = "Hide the Bounty Hunter passive from your active buffs." },
    grimoire_health_debuff                                 = { en = "[working] Grimoire" },
    grimoire_health_debuff_tooltip                         = { en = "Hide the grimoire health penalty from your active buffs." },
    markus_huntsman_passive_crit_aura_buff                 = { en = "[working] Huntsman Passive Crit Aura" },
    markus_huntsman_passive_crit_aura_buff_tooltip         = { en = "Hide the Huntsman crit-aura passive from your active buffs." },
    markus_knight_passive_defence_aura                     = { en = "[working] Foot Knight Aura" },
    markus_knight_passive_defence_aura_tooltip             = { en = "Hide the Foot Knight defence aura from your active buffs." },
    kerillian_waywatcher_passive                           = { en = "[working] Waywatcher Passive" },
    kerillian_waywatcher_passive_tooltip                   = { en = "Hide the Waywatcher passive from your active buffs." },
    kerillian_maidenguard_passive_stamina_regen_buff       = { en = "[working] Handmaiden Passive" },
    kerillian_maidenguard_passive_stamina_regen_buff_tooltip = { en = "Hide the Handmaiden passive from your active buffs." },
    HIDE_WHC_GRIMOIRE_POWER_BUFF                           = { en = "[working] WHC Grimoire Power Buff" },
    HIDE_WHC_GRIMOIRE_POWER_BUFF_tooltip                   = { en = "Hide the Witch Hunter Captain grimoire-power buff from your active buffs." },
    HIDE_SHADE_GRIMOIRE_POWER_BUFF                         = { en = "[working] Shade Grimoire Power Buff" },
    HIDE_SHADE_GRIMOIRE_POWER_BUFF_tooltip                 = { en = "Hide the Shade grimoire-power buff from your active buffs." },
    HIDE_ZEALOT_HOLY_CRUSADER_BUFF                         = { en = "[working] Zealot Holy Crusader Buff" },
    HIDE_ZEALOT_HOLY_CRUSADER_BUFF_tooltip                 = { en = "Hide the Zealot Holy Crusader buff from your active buffs." },

    -- Formerly-loose hb toggles, now grouped under gut_hb_misc_group.
    gut_hb_misc_group                = { en = "[working] Portrait & Markers" },
    force_default_frame              = { en = "[working] Use Default Portrait Frames" },
    force_default_frame_tooltip      = { en = "Always use the default portrait frame." },
    UNOBTRUSIVE_FLOATING_OBJECTIVE   = { en = "[working] Unobtrusive Objective Marker" },
    UNOBTRUSIVE_FLOATING_OBJECTIVE_tooltip = { en = "Make the floating objective marker smaller and always transparent." },
    UNOBTRUSIVE_MISSION_TOOLTIP      = { en = "[working] Unobtrusive Mission Marker" },
    UNOBTRUSIVE_MISSION_TOOLTIP_tooltip = { en = "Make the floating mission marker (used for the revive warning) smaller and always transparent." },

    -- ============================================================
    -- In-Mission Menus (collapsible wrapper, reorg 2026-07-02)
    -- ============================================================
    gut_inmission_menus_group = {
        en = "[working] In-Mission Menus",
    },

    -- ============================================================
    -- In-Mission Hero Select (sibling of the inventory feature, 2026-06-24)
    -- ============================================================
    gut_mission_hero_select_group = {
        en = "[untested] In-Mission Hero Select",
    },
    gut_mission_hero_select_enabled = {
        en = "[untested] Enable In-Mission Hero Select Access",
    },
    gut_mission_hero_select_enabled_tooltip = {
        en = "Lets you open the hero/career selection screen (the same grid as the keep's C key) during a mission, via the keybind below or /hero_select. Picking a career swaps you and respawns you in place, right where you stand. Blocked in Chaos Wastes (a mid-run career swap would desync your boons and loadout).",
    },
    gut_open_hero_select_hotkey = {
        en = "[untested] Open Hero Select (Mid-Mission)",
    },
    gut_open_hero_select_hotkey_tooltip = {
        en = "Hotkey to open the hero/career selection screen while in a mission. Same as /hero_select. Selecting a character or career respawns you in place with the new pick. In the keep the game's own C key already does this, so the hotkey stays quiet there.",
    },

    -- ============================================================
    -- In-Mission Inventory (migrated from general_tweaker 2026-06-24)
    -- ============================================================
    gut_mission_inventory_group = {
        en = "[working] In-Mission Inventory",
    },
    gut_mission_inventory_enabled = {
        en = "[Issue 193 & 87] [crash] [verify-fix] Enable In-Mission Inventory Access",
    },
    gut_mission_inventory_enabled_tooltip = {
        en = "Lets you open your inventory during a mission and adds an Open Inventory entry to the in-game menu; use the keybind below or /inv, since the keep's normal inventory hotkeys often will not work mid-mission. Works in Adventure only, not Chaos Wastes.",
    },
    gut_mission_menu_tabs = {
        en = "[Issue 172, 155 & 87] [crash] [verify-fix] Show menu tabs in-mission (Inventory/Talents/Cosmetics)",
    },
    gut_mission_menu_tabs_tooltip = {
        en = "Restores the top tabs (Inventory, Talents, Cosmetics) while the menu is open mid-mission, with talent changes applying to your character immediately. The Crafting tab is enabled too when 'Allow crafting bench in mission' is on and Crafting in Modded is installed (it opens the standard bench, not the Athanor); PC only, off by default.",
    },
    gut_open_inv_hotkey = {
        en = "[working] Open Inventory (Mid-Mission)",
    },
    gut_open_inv_hotkey_tooltip = {
        en = "Hotkey to open your inventory while in a mission. Same as the /inv command, and works even though the standard inventory keys are blocked mid-mission.",
    },
    gut_cim_bench_in_mission = {
        en = "[untested] [Issue 80] Allow crafting bench in mission",
    },
    gut_cim_bench_in_mission_tooltip = {
        en = "Requires Crafting in Modded (this option only appears when it is installed). OFF (default): the standard crafting bench does not open during missions. ON: it also opens inside Adventure missions via Crafting in Modded's bench hotkey, /cim_craft_standard, or the Crafting tab in the mid-mission menu (when 'Show menu tabs in-mission' is on); the Athanor stays Keep-only either way. In-mission menus were never meant to run mid-mission, so if you hit a crash with this on, please send the log.",
    },

    -- ============================================================
    -- In-Mission Mission Map (#305)
    -- ============================================================
    gut_mission_map = {
        en = "In-Mission Mission Map",
    },
    gut_mission_map_tooltip = {
        en = "Opens the mission-selection map during a mission, the same screen the keep's M key shows, drawn over a proper menu backdrop like in the keep. Picking a mission starts it right away for the whole party (host side). Use the keybind below (default M) or /map. Adventure only: it stays closed in Chaos Wastes and Versus. Off by default.",
    },
    gut_mission_map_hotkey = {
        en = "Open Mission Map (Mid-Mission)",
    },
    gut_mission_map_hotkey_tooltip = {
        en = "Hotkey to open the mission-selection map while in a mission; default M, same as /map. In the keep the game's own M key already does this, so the hotkey stays quiet there.",
    },
    gut_mission_map_host_only = {
        en = "Mission map is host only",
    },
    gut_mission_map_host_only_tooltip = {
        en = "When on, only the party host can open the mission map mid-mission; everyone else gets a short message instead. Off by default, so any player can open it to look around.",
    },

    -- ============================================================
    -- Inventory (#522): character-preview backdrop dropdown.
    -- ============================================================
    gut_inventory_group = {
        en = "[untested] Inventory",
    },
    gut_inventory_backdrop = {
        en = "[untested] Character Preview Backdrop",
    },
    gut_inventory_backdrop_tooltip = {
        en = "Chooses the scene shown behind your character in the inventory preview. Vanilla is the game's default stage. Dark Camp is the darker campfire scene the chest-opening screen uses. Victory Camp is the celebration scene from the mission-won screen. Applies the next time the inventory opens; if a scene is unavailable, the vanilla backdrop is used.",
    },
    -- Dropdown option labels (VMF localizes each option's text; raw keys here).
    gut_inv_backdrop_opt_vanilla = { en = "Vanilla" },
    gut_inv_backdrop_opt_dark    = { en = "Dark Camp (chest-opening scene)" },
    gut_inv_backdrop_opt_victory = { en = "Victory Camp (mission-won scene)" },

    -- ============================================================
    -- Main Menu & Startup (migrated from general_tweaker 2026-06-29, #190)
    -- ============================================================
    gut_mainmenu_group = {
        en = "[working] Main Menu & Startup",
    },
    gut_skip_start_screen = {
        en = "[working] Skip start screen (straight to the keep)",
    },
    gut_skip_start_screen_tooltip = {
        en = "Skips the 'press any key' title screen on launch so you go straight to the main menu. Takes effect on your next game launch; off by default.",
    },
    gut_return_to_menu_quits = {
        en = "[working] \"Return to Main Menu\" quits to desktop",
    },
    gut_return_to_menu_quits_tooltip = {
        en = "Makes the ESC menu's Return to Main Menu entry quit straight to desktop instead (still with the usual confirmation popup), and adds a /quit command for an instant exit with no confirmation. Off by default.",
    },

    -- ============================================================
    -- Mod Tweaker open hotkey (#125)
    -- ============================================================
    gut_mod_tweaker_group = {
        en = "[working] Mod Tweaker",
    },
    gut_open_mod_tweaker_hotkey = {
        en = "[working] Open Mod Tweaker",
    },
    gut_open_mod_tweaker_hotkey_tooltip = {
        en = "Hotkey to open the Mod Tweaker settings menu directly, the same as the /mod_tweaker command or the Mod Tweaker button in the ESC menu. Works in the keep and mid-mission, and exiting returns you to the game; unbound by default.",
    },
    gut_mt_auto_collapse = {
        en = "[working] Auto-collapse sections",
    },
    gut_mt_auto_collapse_tooltip = {
        en = "In the Mod Tweaker, keeps only one section open at a time, so opening a section closes the others at the same level. Turn off to expand sections independently (on by default).",
    },
    -- (#528) The gut_ckc_options_bridge availability toggle (issue 313) was retired:
    -- the Crosshair Kill Confirmation bridge is implicit, active whenever the CKC
    -- mod is installed and togglable. Its loc keys are gone with the widget.

    -- ============================================================
    -- Loadout Manager -- issue #175 (modded-scoped store itself is implicit/always-on)
    -- ============================================================
    gut_loadout_manager_group = {
        en = "[working] Loadouts",
    },
    gut_use_non_modded_loadouts = {
        -- User-confirmed in-game 2026-07-02 (read-only official loadouts in modded).
        -- #287 cosmetic-exemption fix awaiting in-game confirmation: [verify-fix].
        en = "[verify-fix] [diag] [Issue 287] Use non-modded loadouts",
    },
    gut_use_non_modded_loadouts_tooltip = {
        en = "While in the modded realm, use the loadouts saved in your non-modded (official) game, read-only: the I to VI bar shows your official gameplay loadouts, and gear, talent, loadout-switch and bot-designation changes all snap back so your official saves are never touched. Cosmetics (weapon illusion, hat, portrait frame, victory pose) stay changeable and are kept modded-side only. Turn off (default) to keep fully separate modded loadouts that never touch your official ones.",
    },

    -- ============================================================
    -- Overlays (parry indicator, respawn timer, damage numbers) - now inside the
    -- HUD category (gut_hide_hud_ui_group); the "On-Screen Overlays" category and
    -- its gut_hud_group widget were deleted in the 2026-07-02 reorg.
    -- ============================================================

    -- Parry Indicator (absorbed from the "Parry Indicator" mod).
    gut_parry_indicator = {
        en = "[working] Parry Indicator",
    },
    gut_parry_indicator_tooltip = {
        en = "Recolours your block shields during the brief timed-block window after you raise block, on every weapon (not just those with the Parry trait). Pick the colour with the RGB values below.",
    },
    gut_parry_r = {
        en = "[working] Parry colour - Red (0-255)",
    },
    gut_parry_g = {
        en = "[working] Parry colour - Green (0-255)",
    },
    gut_parry_b = {
        en = "[working] Parry colour - Blue (0-255)",
    },

    -- Respawn countdown over a dead teammate's portrait.
    gut_respawn_timer = {
        en = "[Issue 285] [verify-fix] Respawn Timer over Portrait",
    },
    gut_respawn_timer_tooltip = {
        en = "Shows a large countdown over a dead teammate's portrait while they wait to respawn, starting when their portrait shows the dead skull. Off by default.",
    },
    gut_respawn_font_size = {
        en = "[untested] Respawn number size",
    },
    gut_respawn_font_size_tooltip = {
        en = "Text size of the respawn countdown number shown over the portrait.",
    },
    gut_respawn_r = {
        en = "[untested] Respawn colour - Red (0-255)",
    },
    gut_respawn_g = {
        en = "[untested] Respawn colour - Green (0-255)",
    },
    gut_respawn_b = {
        en = "[untested] Respawn colour - Blue (0-255)",
    },

    -- Floating Damage Numbers (migrated from general_tweaker 2026-06-29).
    gut_damage_numbers_enabled = {
        en = "[working] Show Floating Damage Numbers",
    },
    gut_damage_numbers_enabled_tooltip = {
        en = "Shows floating damage numbers over enemies you hit, using the game's own damage-number display. Takes effect on the next map load, and only ever changes your own screen.",
    },
    gut_damage_numbers_include_dots = {
        en = "[working] Include damage-over-time & explosions",
    },
    gut_damage_numbers_include_dots_tooltip = {
        en = "Also shows numbers for damage over time (burning, bleed) and explosions (bombs), not just direct hits. Turn off to reduce the number spam.",
    },

    -- ============================================================
    -- Mod Tweaker custom-renderer strings (not VMF option widgets)
    -- ============================================================
    -- Reset-to-default button label in the Mod Tweaker view.
    gut_mt_reset = {
        en = "Default",
    },
    gut_mt_profiles = {
        en = "Profiles",
    },
    -- (#208) Mod Tweaker "Equipment" merge: the unified tab + its collapsible section
    -- labels. Shown when 2+ of the inventory mods (cosmetics_tweaker / cim / wt / CWV) are
    -- active; the four individual tabs fold into one "Equipment" tab. gut-owned strings.
    gut_equip_tab = {
        en = "Equipment",
    },
    gut_equip_cosmetics = {
        en = "Cosmetics",
    },
    gut_equip_crafting = {
        en = "Crafting",
    },
    gut_equip_weapons = {
        en = "Weapons",
    },
    gut_equip_cwv = {
        en = "Career Weapon Variants",
    },
    gut_disabled_in_vmf = {
        en = "Disabled in VMF",
    },

}
