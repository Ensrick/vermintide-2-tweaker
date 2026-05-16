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
        en = "Block every enemy from spawning — hordes, specials, bosses, patrols, and pre-placed level enemies all go through the same ConflictDirector chokepoint and are refused while this is on. Existing enemies are NOT despawned; pair with 'gt god' if you want to ignore them. Toggle off any time to resume normal spawning. Chat: 'gt no_enemies'.",
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
}
