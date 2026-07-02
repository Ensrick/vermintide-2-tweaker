return {
    mod_description = {
        en = "Quality-of-life tweaks for the Vermintide 2 hero/character GUI (save loadouts, etc.).",
    },

    -- ESC-menu button label. Injected by the IngameViewLayoutLogic.setup_button_layout
    -- hook in gui_tweaker.lua; the button widget style has localize=true
    -- (vanilla ingame_view.lua:138-140 + :252), so display_name MUST be a real
    -- loc key. (display_name_func is a dead vanilla field — never invoked in the
    -- decompiled ingame_view render path — so the literal there did not render.)
    mod_tweaker_button_name = {
        en = "Mod Tweaker",
    },

    -- UI-mod compatibility patches absorbed into gut.
    gut_compat_group = {
        en = "UI Mod Compatibility",
    },
    gut_buffbar_endtime_fix = {
        en = "UI Tweaks: buff-bar end-time crash fix",
    },
    gut_buffbar_endtime_fix_tooltip = {
        en = "Stops the per-frame 'attempt to compare nil with number' error UI Tweaks (HideBuffs) PriorityBuffUI._add_buff throws when a stacking buff (e.g. Bardin Outcast Engineer's pump stacks) refreshes after first appearing without an end time. Backfills the stored buff's missing end_time before the compare, so the buff bar updates cleanly instead of spamming the log every frame. Only does anything when UI Tweaks is installed. On by default.",
    },

    -- Parry Indicator (absorbed from the "Parry Indicator" mod).
    gut_parry_indicator = {
        en = "Parry Indicator",
    },
    gut_parry_indicator_tooltip = {
        en = "Recolour the block/stamina shields during the timed-block window (the first 0.5s after raising block, while blocking). Unlike the original Parry Indicator mod, this works on EVERY weapon, not only weapons with the Parry trait. Pick the colour with the R/G/B values below.",
    },
    gut_parry_r = {
        en = "Parry colour - Red (0-255)",
    },
    gut_parry_g = {
        en = "Parry colour - Green (0-255)",
    },
    gut_parry_b = {
        en = "Parry colour - Blue (0-255)",
    },

    -- Respawn countdown over a dead teammate's portrait.
    gut_respawn_timer = {
        en = "Respawn Timer over Portrait",
    },
    gut_respawn_timer_tooltip = {
        en = "Show a large countdown (seconds, one decimal) over a DEAD teammate's portrait while they wait to respawn. Client-safe estimate anchored to when the dead-skull portrait appears, counting down 30s (or the mode's respawn time). Off by default.",
    },
    gut_respawn_font_size = {
        en = "Respawn number size",
    },
    gut_respawn_font_size_tooltip = {
        en = "Font size of the respawn countdown number drawn over the portrait.",
    },
    gut_respawn_r = {
        en = "Respawn colour - Red (0-255)",
    },
    gut_respawn_g = {
        en = "Respawn colour - Green (0-255)",
    },
    gut_respawn_b = {
        en = "Respawn colour - Blue (0-255)",
    },

    gut_config_override = {
        en = "Override settings from config file",
    },
    gut_config_override_tooltip = {
        en = "On game load, read gut_mod_settings.toml from your Fatshark/Vermintide 2 folder and override the in-game VMF settings for your tweaker mods with the file's values. Edit that file directly to control settings outside the game. Use /gut_export_settings to dump current settings (to the log) and the companion tools/gut-settings.ps1 to write the file; /gut_reload_config re-applies it without a restart. On by default (no-op if the file doesn't exist).",
    },

    -- Hide UI (3 modes) — migrated from general_tweaker.
    gut_hud_visibility_group = {
        en = "Hide UI",
    },
    gut_hud_mode = {
        en = "HUD Visibility Mode",
    },
    gut_hud_mode_tooltip = {
        en = "Off = normal HUD. Partial = most UI hidden, prompts/subtitles/twitch votes stay (Act on Instinct mutator behavior). Complete = everything hidden, best for screenshots. Camera = Complete + hides first-person arms and weapon, best for scenery screenshots.",
    },
    gut_hud_cycle_hotkey = {
        en = "Cycle HUD Mode",
    },
    gut_hud_cycle_hotkey_tooltip = {
        en = "Hotkey: cycle through off → partial → complete → camera. Same as '/gut_hud'.",
    },

    -- (#93) Compact ESC/keep menu loc keys removed 2026-06-24 — the feature is now an
    -- always-on implicit fix with no toggle.

    -- Skip Cutscenes (migrated from general_tweaker 2026-06-25, issue #106).
    gut_cutscenes_group = {
        en = "Skip Cutscenes",
    },
    gut_skip_cutscenes_enabled = {
        en = "Skip Cutscenes",
    },
    gut_skip_cutscenes_enabled_tooltip = {
        en = "Allow cutscenes to be skipped with ESC or Space — vanilla normally gates this behind the level author's `skippable_cutscenes` flag. Chat: '/gut_skipcutscenes'. Uses a unique command name so this can coexist with the standalone 'Skip Cutscenes' / 'Skip Cutscenes Please' workshop mods. In Chaos Wastes, author-locked boss/phase cinematics are left alone (skipping them desyncs the fight).",
    },
    gut_skip_cutscenes_auto = {
        en = "Auto-skip Cutscenes",
    },
    gut_skip_cutscenes_auto_tooltip = {
        en = "When on, cutscenes fire their own skip event the moment activation begins — you never see them. Leave off to require a manual ESC/Space press (still much easier than vanilla because the skip is now always enabled).",
    },
    gut_skip_cutscenes_hotkey = {
        en = "Toggle Skip Cutscenes (Hotkey)",
    },
    gut_skip_cutscenes_hotkey_tooltip = {
        en = "Hotkey: toggle the Skip Cutscenes setting on/off. Same as '/gut_skipcutscenes'.",
    },

    -- In-mission inventory access (migrated from general_tweaker 2026-06-24).
    gut_mission_inventory_group = {
        en = "In-Mission Inventory",
    },
    gut_mission_inventory_enabled = {
        en = "Enable In-Mission Inventory Access",
    },
    gut_mission_inventory_enabled_tooltip = {
        en = "Patches InventorySettings so the inventory view can render in adventure/survival game modes and adds an 'Open Inventory' entry to the in-game ESC menu. The keep's bound hotkeys (Inventory/Hero/Map etc.) USUALLY do not fire mid-mission even with this on (vanilla gates them deep inside the view's can_interact checks). Use the keybind below or /gut_inv for a reliable open. Adventure only -- in-mission inventory is blocked in Chaos Wastes (CW is loadout-locked and crashes).",
    },
    gut_mission_menu_tabs = {
        en = "Show menu tabs in-mission (Inventory/Talents/Cosmetics)",
    },
    gut_mission_menu_tabs_tooltip = {
        en = "Restores the top tab strip when the inventory/menu is open mid-mission, so you can switch between Inventory, Talents and Cosmetics (the 'new GUI' tabs). Vanilla hides AND disables that tab strip in a mission (it only draws/accepts input in the keep). The Crafting/Forge tab stays disabled unless you also run Crafting in Modded (cim) -- opening the forge's item-customization mid-mission loads a keep-only preview level and hard-crashes. Talent changes apply to your live character immediately. PC only. Default off.",
    },
    gut_open_inv_hotkey = {
        en = "Open Inventory (Mid-Mission)",
    },
    gut_open_inv_hotkey_tooltip = {
        en = "Hotkey: open the inventory while you're in a mission. Same as '/gut_inv'. Calls Managers.ui:handle_transition('hero_view_force', ...) directly -- the same path vanilla fires from the ESC-menu 'Open Inventory' entry -- so it bypasses the hotkey gating that blocks the standard I/H/M/etc. keys mid-mission.",
    },

    -- In-mission HERO SELECT (sibling of the inventory feature, 2026-06-24).
    gut_mission_hero_select_group = {
        en = "In-Mission Hero Select",
    },
    gut_mission_hero_select_enabled = {
        en = "Enable In-Mission Hero Select Access",
    },
    gut_mission_hero_select_enabled_tooltip = {
        en = "Lets you open your hero's Talents screen during a mission (via the keybind below or /gut_hero_select). Opens the same Hero View the inventory feature uses, on the Talents tab -- talent and active-ability changes apply to your LIVE character immediately, no respawn. From there you can tab to Cosmetics too (enable 'Show menu tabs in-mission' above). LIMIT: this is VIEW + talents/cosmetics only -- it does NOT let you change CAREER mid-mission. A career change is unsafe in a live level (the game's only career-swap path force-respawns you at the LEVEL START with fresh health/ammo and can desync your career across players), and the standalone character-pick screen loads a keep-only preview world that crashes mid-mission. So actual career/hero PICKING stays in the keep, by design. Adventure only -- blocked in Chaos Wastes (CW is loadout-locked and crashes).",
    },
    gut_open_hero_select_hotkey = {
        en = "Open Hero Select (Mid-Mission)",
    },
    gut_open_hero_select_hotkey_tooltip = {
        en = "Hotkey: open your hero's Talents screen while you're in a mission. Same as '/gut_hero_select'. Calls Managers.ui:handle_transition('hero_view_force', { menu_sub_state_name = 'talents' }) directly -- the same vanilla transition the in-mission inventory uses, just landing on the Talents tab. Live-safe: talent/ability changes apply to your current character immediately, with no respawn. Career PICK is NOT available mid-mission (keep-only by design -- see the toggle tooltip).",
    },

    -- Mod Tweaker open hotkey (#125).
    gut_mod_tweaker_group = {
        en = "Mod Tweaker",
    },
    gut_open_mod_tweaker_hotkey = {
        en = "Open Mod Tweaker",
    },
    gut_open_mod_tweaker_hotkey_tooltip = {
        en = "Hotkey: open the Mod Tweaker settings menu directly -- same as the /gut_mod_tweaker command, or the 'Mod Tweaker' button in the ESC menu. Calls mod.gut_open_mod_tweaker, which drives the same Managers.ui:handle_transition('mod_tweaker_view', ...) the ESC button uses. Works in the keep AND mid-mission (it's a settings list, not a preview world, so no keep-only crash). Exiting the menu (ESC or the X) returns you to the game. Default unbound.",
    },

}
