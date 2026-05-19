return {
    mod_description = {
        en = "General gameplay tweaks: third-person camera and more.",
    },

    tp_camera_group = {
        en = "Third-Person Camera",
    },
    tp_camera_enabled = {
        en = "Enable Third-Person Camera",
    },
    tp_camera_enabled_tooltip = {
        en = "Toggle third-person camera view. Can also be toggled in-game with the 'gt tp' chat command.",
    },
    tp_distance = {
        en = "Camera Distance",
    },
    tp_distance_tooltip = {
        en = "How far behind the character the camera sits.",
    },
    tp_height = {
        en = "Camera Height",
    },
    tp_height_tooltip = {
        en = "How far above the character the camera sits.",
    },
    tp_side_offset = {
        en = "Side Offset",
    },
    tp_side_offset_tooltip = {
        en = "Horizontal offset (positive = right, negative = left).",
    },
    tp_disable_zoom_in = {
        en = "Disable Aim Zoom-In",
    },
    tp_disable_zoom_in_tooltip = {
        en = "When on, aiming or throwing in third-person no longer pulls the camera in close — it stays at the configured distance/height. Useful for watching 3P weapon animations.",
    },
    freecam_enabled = {
        en = "Free Camera (Detached)",
    },
    freecam_enabled_tooltip = {
        en = "Detaches the camera from the player so you can fly around with WASD/mouse and inspect the character/weapon model from any angle. While active, player input is blocked — press F8 to exit. Mainly a dev/inspection tool. Can also be toggled with the 'gt freecam' chat command.",
    },

    gameplay_group = {
        en = "Gameplay",
    },
    godmode_enabled = {
        en = "Godmode",
    },
    godmode_enabled_tooltip = {
        en = "Toggle invincibility — no damage taken, immune to disablers (pounce, packmaster hook, chaos-spawn / corruptor / tentacle grabs, hanging cage), AND invisible to enemy AI (your 3P body fades; first-person view stays normal). Can also be toggled with the 'gt god' chat command.",
    },
    allow_duplicate_careers = {
        en = "Allow Duplicate Careers",
    },
    allow_duplicate_careers_tooltip = {
        en = "Allow multiple players to pick the same hero/career in a lobby.",
    },
    disable_friendly_fire = {
        en = "Disable Friendly Fire",
    },
    disable_friendly_fire_tooltip = {
        en = "Suppress friendly fire damage from both ranged and melee sources. Champion+ difficulties normally enable ranged FF; this turns it off.",
    },
    noclip_enabled = {
        en = "Noclip",
    },
    noclip_enabled_tooltip = {
        en = "Fly through walls. WASD to move in the direction you're looking, Space/Ctrl for up/down, hold Shift for a speed boost. Can also be toggled with the 'gt noclip' chat command. Note: when toggled off mid-air you'll fall to the ground.",
    },
    noclip_speed = {
        en = "Noclip Base Speed",
    },
    noclip_speed_tooltip = {
        en = "Flight speed in metres per second. The default ~15 m/s is roughly 4x normal walk speed.",
    },
    noclip_boost_multiplier = {
        en = "Noclip Shift-Boost Multiplier",
    },
    noclip_boost_multiplier_tooltip = {
        en = "When holding Left Shift, base speed is multiplied by this value. 3.0 = ~45 m/s with the default base speed.",
    },
    disable_enemy_spawns = {
        en = "Disable Enemy Spawns",
    },
    disable_enemy_spawns_tooltip = {
        en = "Block every enemy from spawning — hordes, specials, bosses, patrols, critters, mini-patrols, and pre-placed level enemies all go through the same ConflictDirector chokepoint and are refused while this is on. Belt-and-suspenders: the toggle also flips `script_data.ai_*_disabled` flags so the pacing/intervention pipelines abort earlier. Existing enemies are NOT despawned; pair with 'gt god' if you want to ignore them. Toggle off any time to resume normal spawning. Chat: 'gt no_enemies'.",
    },
    ai_takeover_enabled = {
        en = "AI Takeover (bot controls your character)",
    },
    ai_takeover_enabled_tooltip = {
        en = "Hand your character over to bot AI for stepping away or for testing multiplayer code paths from the host's side. CLIENT ONLY in v1 — host self-toggle is refused because tearing down the local Player object mid-mission would break camera/HUD/input. Refused in versus (no hero bot AI) and in the keep (no spawning). Toggling off recreates your character with a fresh loadout (consumables/ammo do NOT persist across the swap). Auto-resets on state change. The host must also have General Tweaker installed. Chat: 'gt ai'.",
    },

    mission_inventory_group = {
        en = "Keep Menus in Missions",
    },
    mission_inventory_enabled = {
        en = "Enable Keep Menu Hotkeys in Missions",
    },
    mission_inventory_enabled_tooltip = {
        en = "Lets the keep's menu hotkeys (Inventory, Hero, Map, Achievements, Spoils of War, Weave Forge, Weave Play — whatever keys you've rebound them to) open their menus during missions. Also adds an Inventory entry to the in-game ESC menu as a fallback.",
    },

    startup_group = {
        en = "Startup",
    },
    skip_intro_enabled = {
        en = "Skip Intro Splash Screens",
    },
    skip_intro_enabled_tooltip = {
        en = "Skip the Fatshark/engine logo splash sequence at game launch. Takes effect on the next boot (the splash for the current session has already run by the time this setting is reachable). Same mechanism as the '-skip-splash' command-line flag — sets Development.parameter(\"skip_splash\") which StateSplashScreen.on_enter honours.",
    },

    player_state_group = {
        en = "Player State Toggles",
    },
    cloak_hotkey = {
        en = "Cloak (Invisibility)",
    },
    cloak_hotkey_tooltip = {
        en = "Hotkey: toggle visual invisibility (model hidden + invisible to AI). Same as '/cloak'. Distinct from godmode — uses a separate reason namespace so toggling cloak doesn't affect godmode's invisibility state and vice versa.",
    },

    buffs_group = {
        en = "Buffs & Stats",
    },
    base_crit_chance = {
        en = "Base Crit Chance (%)",
    },
    base_crit_chance_tooltip = {
        en = "Rewrites the current career's base_critical_strike_chance. Default for most careers is 5% (Shade and Witch Hunter Captain differ). Auto-resets to that career's vanilla value when you switch careers. Per-session — game restart restores defaults.",
    },
    movement_speed = {
        en = "Movement Speed (m/s)",
    },
    movement_speed_tooltip = {
        en = "Rewrites PlayerUnitMovementSettings.move_speed AND every per-unit override already snapshotted by the engine. Default is 4. Per-session — game restart restores defaults. Affects everyone whose movement settings the host updates; for single-player effects only, use this with caution in lobbies.",
    },

    ult_group = {
        en = "Ult",
    },
    ult_reset_hotkey = {
        en = "Ult Reset",
    },
    ult_reset_hotkey_tooltip = {
        en = "Hotkey: set every charge of your career ability to 0 cooldown immediately. Same as '/gt_ultreset'. One-shot — won't keep your ult ready, just makes it ready now.",
    },
    ult_player_cap_enabled = {
        en = "Cap Player Ult Cooldown",
    },
    ult_player_cap_enabled_tooltip = {
        en = "While on, clamp every player-controlled career ability's remaining cooldown to at most the value below, every update tick. Effectively a configurable 'short ult cooldown' for human players.",
    },
    ult_player_cap_value = {
        en = "Max Player Ult Cooldown (seconds)",
    },
    ult_player_cap_value_tooltip = {
        en = "Maximum remaining cooldown (in seconds) for the local player and other human-controlled units. 0 = ult always ready.",
    },
    ult_bot_cap_enabled = {
        en = "Cap Bot Ult Cooldown",
    },
    ult_bot_cap_enabled_tooltip = {
        en = "Same as the player cap, but applies to bot-controlled units. Useful in solo-with-bots to see bots ult more aggressively for testing.",
    },
    ult_bot_cap_value = {
        en = "Max Bot Ult Cooldown (seconds)",
    },
    ult_bot_cap_value_tooltip = {
        en = "Maximum remaining cooldown (in seconds) for bot-controlled units. 0 = bots ult constantly.",
    },

    time_group = {
        en = "Time & Pause",
    },
    time_scale_value = {
        en = "Time Scale",
    },
    time_scale_value_tooltip = {
        en = "Game time scale (index 1-24). 13 = normal speed, lower = slower (slow-motion), higher = faster. Re-applied on every mission entry but reset by the game on restart. Index into debug_manager.lua's time_scale_list.",
    },
    time_faster_hotkey = {
        en = "Time Faster",
    },
    time_faster_hotkey_tooltip = {
        en = "Hotkey: bump time scale up one step. Same as 'gt time_faster'.",
    },
    time_slower_hotkey = {
        en = "Time Slower",
    },
    time_slower_hotkey_tooltip = {
        en = "Hotkey: bump time scale down one step. Same as 'gt time_slower'.",
    },
    pause_value = {
        en = "Pause Speed",
    },
    pause_value_tooltip = {
        en = "Time scale to use while paused (index 1-24). 1 = slowest possible (closest to a true pause; UI still updates). 6 = slow enough to read tooltips. 13 = normal (no effect). >13 = faster than normal. VT2 has no true freeze primitive — set_time_scale(1) is the closest thing.",
    },
    pause_hotkey = {
        en = "Pause Toggle",
    },
    pause_hotkey_tooltip = {
        en = "Hotkey: toggle the host-only time-slowdown pause. Same as '/gt_pause'. Clients see the change because time scale is server-driven.",
    },

    level_control_group = {
        en = "Level Control",
    },
    win_level_hotkey = {
        en = "Win Level",
    },
    win_level_hotkey_tooltip = {
        en = "Hotkey: complete the current mission. Same as '/gt_win'. No-op in the keep.",
    },
    fail_level_hotkey = {
        en = "Fail Level",
    },
    fail_level_hotkey_tooltip = {
        en = "Hotkey: fail the current mission. Same as '/gt_fail'. No-op in the keep.",
    },
    restart_level_hotkey = {
        en = "Restart Level",
    },
    restart_level_hotkey_tooltip = {
        en = "Hotkey: restart the current mission. Same as '/gt_restart'. No-op in the keep.",
    },
    kill_bots_hotkey = {
        en = "Kill Bots",
    },
    kill_bots_hotkey_tooltip = {
        en = "Hotkey: kill every bot in the party. Same as '/gt_killbots'. On official realm only allowed before the round starts (EAC block); unrestricted on modded realm.",
    },
    die_hotkey = {
        en = "Suicide",
    },
    die_hotkey_tooltip = {
        en = "Hotkey: kill your character. Same as '/gt_die'. No-op in the keep.",
    },
    fix_sound_hotkey = {
        en = "Fix Vortex Sound",
    },
    fix_sound_hotkey_tooltip = {
        en = "Hotkey: stop the looping vortex SFX that gets stuck after restarting a mission during a wind/storm. Same as 'gt fix_sound'. Mission-only.",
    },
}
