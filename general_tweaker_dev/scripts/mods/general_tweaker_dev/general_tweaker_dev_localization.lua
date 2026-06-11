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
    noclip_hotkey = {
        en = "Noclip Toggle",
    },
    noclip_hotkey_tooltip = {
        en = "Hotkey: toggle noclip on/off. Same as '/noclip'. The toggle remembers state so re-pressing returns you to normal locomotion.",
    },
    clear_enemies_hotkey = {
        en = "Clear Enemy Spawns",
    },
    clear_enemies_hotkey_tooltip = {
        en = "Hotkey: despawn every currently-alive enemy AI unit. Same as '/clear_enemies'. Host-only. Skips breeds tagged as objective-immune (e.g. the cursed-chest beastman) so mission objectives don't break.",
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
        en = "Hand your character over to bot AI for stepping away or for testing. Works as host OR client (host self-toggle is now supported — the swap is deferred one tick so the current frame finishes reading input before the local Player object is torn down). Refused in versus (no hero bot AI) and in the keep (no spawning). Toggling off recreates your character with a fresh loadout (consumables/ammo do NOT persist across the swap). Auto-resets on state change. The host must also have General Tweaker installed. Chat: '/ai'.",
    },
    gt_bots_in_keep = {
        en = "Allow Bots in Keep",
    },
    gt_bots_in_keep_tooltip = {
        en = "Host-side: while in the keep / Chaos Wastes hub / Versus inn, fill the heroes party up to four with bots so you can preview their loadouts and have a populated lobby. Vanilla VT2 skips bot spawning in inn-type game modes (GameModeInn.server_update doesn't call _handle_bots); this toggle reproduces the adventure-mode bot fill logic against the inn party. Bots are cleared when the toggle flips off or when you leave the keep. Bots picked via the vanilla bot-priority list, same as adventure. Host only — clients see whatever bots the host spawned. Chat: '/gt_bots_in_keep'.",
    },
    gt_no_bots = {
        en = "Disable Bots (Solo)",
    },
    gt_no_bots_tooltip = {
        en = "Host-side: prevents bots from filling empty party slots, and instantly despawns any bots already present. Sets the engine flag `script_data.ai_bots_disabled`, which the game's bot manager checks every server tick — so turning this ON mid-mission clears existing bots, and leaving it ON keeps the party bot-free from the very start of the next mission. For true solo runs and speedruns. Re-applied on every mission start so it survives level transitions. Host only (bots are server-managed). Toggle off to let bots return on the next tick. Chat: '/gt_no_bots'.",
    },

    mission_inventory_group = {
        en = "Keep Menus in Missions",
    },
    mission_inventory_enabled = {
        en = "Enable Keep Menu Hotkeys in Missions",
    },
    mission_inventory_enabled_tooltip = {
        en = "Patches InventorySettings so the inventory view can render in adventure/survival/deus game modes and adds an 'Open Inventory' entry to the in-game ESC menu. The keep's bound hotkeys (Inventory/Hero/Map etc.) USUALLY do not fire mid-mission even with this on (vanilla gates them deep inside the view's can_interact checks). Use the keybind/command below for a reliable open.",
    },
    gt_open_inv_hotkey = {
        en = "Open Inventory (Mid-Mission)",
    },
    gt_open_inv_hotkey_tooltip = {
        en = "Hotkey: open the inventory while you're in a mission. Same as '/gt_inv'. Calls `Managers.ui:handle_transition('hero_view_force', ...)` directly — the same path vanilla fires from the ESC-menu 'Open Inventory' entry — so it bypasses the hotkey gating that blocks the standard I/H/M/etc. keys mid-mission.",
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
        en = "Base Crit Chance (%%)",
    },
    base_crit_chance_tooltip = {
        en = "Rewrites the current career's base_critical_strike_chance. Default for most careers is 5%% (Shade and Witch Hunter Captain differ). Auto-resets to that career's vanilla value when you switch careers. Per-session — game restart restores defaults.",
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

    gt_cutscenes_group = {
        en = "Cutscenes & Monologues",
    },
    gt_skip_cutscenes_enabled = {
        en = "Skip Cutscenes",
    },
    gt_skip_cutscenes_enabled_tooltip = {
        en = "Allow cutscenes to be skipped with ESC or Space — vanilla normally gates this behind the level author's `skippable_cutscenes` flag. Chat: '/gt_skipcutscenes'. Uses a unique command name so this can coexist with the standalone 'Skip Cutscenes' / 'Skip Cutscenes Please' workshop mods.",
    },
    gt_skip_cutscenes_auto = {
        en = "Auto-skip Cutscenes",
    },
    gt_skip_cutscenes_auto_tooltip = {
        en = "When on, cutscenes fire their own skip event the moment activation begins — you never see them. Leave off to require a manual ESC/Space press (still much easier than vanilla because the skip is now always enabled).",
    },
    gt_disable_intro_monologue = {
        en = "Disable Loading-Screen Monologues",
    },
    gt_disable_intro_monologue_tooltip = {
        en = "Suppress Lohner/Olesya/weave-loading voice lines that play during the level loading screen. Flips `script_data.disable_level_intro_dialogue` — the same flag the vanilla debug screen exposes. Chat: '/gt_intromono'.",
    },

    gt_corpses_group = {
        en = "More Corpses",
    },
    gt_more_corpses_enabled = {
        en = "More Corpses",
    },
    gt_more_corpses_enabled_tooltip = {
        en = "Raise the engine's ragdoll cap so dead enemies persist longer instead of vanishing. Vanilla caps at 24 ragdolls and prunes down to 10 once exceeded; this rewrites both bounds to the value below.",
    },
    gt_more_corpses_count = {
        en = "Max Corpses",
    },
    gt_more_corpses_count_tooltip = {
        en = "Maximum simultaneous ragdolls/corpses. Vanilla = 24. Higher values can stress lower-end machines (more physics simulation, more draw calls); 100-200 is a reasonable cinematic range.",
    },

    gt_gk_group = {
        en = "Choose Grail Knight Quests",
    },
    gt_gk_quests_enabled = {
        en = "Choose Grail Knight Quests",
    },
    gt_gk_quests_enabled_tooltip = {
        en = "Override the Grail Knight's random quest selection. When on, the three quests you pick below become Quest 1 / 2 / 3 for every mission; any slots left on 'Random' fall back to the vanilla shuffled pool. The Chaos Wastes 'additional quest' talent still pulls from the remaining shuffled quests.",
    },
    gt_gk_quest1 = {
        en = "Quest 1",
    },
    gt_gk_quest1_tooltip = {
        en = "First quest the Grail Knight should be assigned. 'Random' = leave to vanilla shuffle.",
    },
    gt_gk_quest2 = {
        en = "Quest 2",
    },
    gt_gk_quest2_tooltip = {
        en = "Second quest. Duplicates are skipped — if Quest 1 already took 'Power vs. Elites', selecting it here is ignored and the slot falls through to vanilla shuffle.",
    },
    gt_gk_quest3 = {
        en = "Quest 3",
    },
    gt_gk_quest3_tooltip = {
        en = "Third quest. Same dedupe behaviour as Quest 2.",
    },

    gt_readyup_group = {
        en = "Ready Up",
    },
    gt_ready_up_hotkey = {
        en = "Ready Up (Skip Countdown)",
    },
    gt_ready_up_hotkey_tooltip = {
        en = "Hotkey: skip the Bridge of Shadows countdown and start the mission immediately. Host-only. Same as '/gt_readyup'.",
    },
    gt_auto_ready_on_vote_pass = {
        en = "Auto-start On Vote Pass",
    },
    gt_auto_ready_on_vote_pass_tooltip = {
        en = "When a mission vote (deed, lookup, etc.) passes, immediately call `countdown_completed` to skip the bridge animation. Host-only. Leave off if you enjoy the bridge ceremony.",
    },

    gt_bot_toggle_hotkey = {
        en = "Toggle Bots On/Off",
    },
    gt_bot_toggle_hotkey_tooltip = {
        en = "Hotkey: flip `no_bots_allowed` on the current level. Lets bots spawn in the keep, or removes them mid-mission. Same as '/gt_bottoggle'. NOTE: Inn bots can trigger a rare nav crash.",
    },

    gt_hud_visibility_group = {
        en = "Hide UI",
    },
    gt_hud_mode = {
        en = "HUD Visibility Mode",
    },
    gt_hud_mode_tooltip = {
        en = "Off = normal HUD. Partial = most UI hidden, prompts/subtitles/twitch votes stay (Act on Instinct mutator behavior). Complete = everything hidden, best for screenshots. Camera = Complete + hides first-person arms and weapon, best for scenery screenshots.",
    },
    gt_hud_cycle_hotkey = {
        en = "Cycle HUD Mode",
    },
    gt_hud_cycle_hotkey_tooltip = {
        en = "Hotkey: cycle through off → partial → complete → camera. Same as '/gt_hud'.",
    },

    -- Creature Spawner (ported from Aussiemon's CreatureSpawner mod,
    -- Workshop ID 1395132559, MIT-licensed). gt_cs_* namespace.
    gt_cs_group = {
        en = "Creature Spawner",
    },
    gt_cs_unit_list = {
        en = "Available Unit List",
    },
    gt_cs_unit_list_tooltip = {
        en = "Pick which subset of breeds the cycle hotkeys walk through.\n\n" ..
            "REGULAR = normal in-mission unit types.\n" ..
            "DUMMY   = AI-less practice dummies.\n" ..
            "MISC    = debug/unused/unstable units.\n" ..
            "SPECIAL = pingable special enemies only.\n" ..
            "BOSS    = bosses and monstrosities.\n" ..
            "ALL     = every known breed.\n\n" ..
            "Categories are sourced from Aussiemon's `unit_categories` map in CreatureSpawner_data.lua. Changing this snaps the active selection to the first breed in the new list.",
    },
    gt_cs_unit_list_regular = { en = "Regular" },
    gt_cs_unit_list_dummy   = { en = "Dummy" },
    gt_cs_unit_list_misc    = { en = "Misc" },
    gt_cs_unit_list_special = { en = "Special" },
    gt_cs_unit_list_boss    = { en = "Boss" },
    gt_cs_unit_list_all     = { en = "All" },

    gt_cs_spawn = {
        en = "Keybind: Spawn Creature",
    },
    gt_cs_spawn_tooltip = {
        en = "Hotkey: spawn the currently-selected breed at your crosshair raycast position. Same as '/gt_spawncreature'. Host-only — uses ConflictDirector:spawn_queued_unit with the breed's debug_spawn_optional_data.ignore_breed_limits flag set so soft caps are bypassed.",
    },
    gt_cs_next = {
        en = "Keybind: Next Creature",
    },
    gt_cs_next_tooltip = {
        en = "Hotkey: cycle forward through the active unit list. Same as '/gt_nextcreature'. Skips breeds that aren't in the `Breeds` global (DLC not owned, etc.).",
    },
    gt_cs_prev = {
        en = "Keybind: Previous Creature",
    },
    gt_cs_prev_tooltip = {
        en = "Hotkey: cycle backward through the active unit list. Same as '/gt_prevcreature'.",
    },
    gt_cs_destroy = {
        en = "Keybind: Destroy Spawned Creatures",
    },
    gt_cs_destroy_tooltip = {
        en = "Hotkey: call ConflictDirector:destroy_all_units() and clear the buff-cap flag. Same as '/gt_destroycreatures'. Host-only. Note: this is the same primitive `gt_clear_enemies` calls, so it also clears non-modded spawns alongside ours.",
    },

    gt_cs_spawn_slot_1 = {
        en = "Keybind: Spawn Saved Slot 1",
    },
    gt_cs_spawn_slot_1_tooltip = {
        en = "Hotkey: spawn whatever breed is saved in slot 1. Save with '/gt_savecreature 1'.",
    },
    gt_cs_spawn_slot_2 = {
        en = "Keybind: Spawn Saved Slot 2",
    },
    gt_cs_spawn_slot_2_tooltip = {
        en = "Hotkey: spawn whatever breed is saved in slot 2. Save with '/gt_savecreature 2'.",
    },
    gt_cs_spawn_slot_3 = {
        en = "Keybind: Spawn Saved Slot 3",
    },
    gt_cs_spawn_slot_3_tooltip = {
        en = "Hotkey: spawn whatever breed is saved in slot 3. Save with '/gt_savecreature 3'.",
    },

    gt_cs_mission_ai = {
        en = "Enable AI in Missions",
    },
    gt_cs_mission_ai_tooltip = {
        en = "Toggle AI perception and pathfinding in missions. Off means spawned enemies stand still — turn this ON to actually fight what you spawn. Hooked into AISystem.update_brains and AIGroupSystem.update so the AI tick short-circuits when off. Default ON (matches upstream).",
    },
    gt_cs_keep_ai = {
        en = "Enable AI in Keep",
    },
    gt_cs_keep_ai_tooltip = {
        en = "Allow AI in the keep level. WARNING: enabling this often crashes because most breeds rely on level-specific navigation/analysis data the keep doesn't have. Default OFF (matches upstream).",
    },

    gt_cs_grudge = {
        en = "Enable Grudge-Marked Modifiers",
    },
    gt_cs_grudge_tooltip = {
        en = "Apply grudge-marked enemy enhancements to newly-spawned breeds.\n\n" ..
            "DISABLED = no modifiers.\n" ..
            "RANDOM   = roll N random modifiers (see slider below).\n" ..
            "MANUAL   = apply exactly the modifiers checked below.\n\n" ..
            "Uses vanilla TerrorEventUtils.add_enhancements_to_spawn_data / generate_enhanced_breed_from_set. The server-controlled buff id table has a hard cap; the BuffSystem.add_buff hook auto-backs off when approaching it (prints `Too many active grudge-mark modifiers!`).",
    },
    gt_cs_grudge_disabled = { en = "Disabled" },
    gt_cs_grudge_random   = { en = "Random" },
    gt_cs_grudge_manual   = { en = "Manual" },

    gt_cs_grudge_random_modifier_count = {
        en = "Random Modifier Count",
    },
    gt_cs_grudge_random_modifier_count_tooltip = {
        en = "When grudge-mark mode is RANDOM, this is how many modifiers each spawn rolls (0-13).",
    },

    gt_cs_grudge_warping         = { en = "Warping" },
    gt_cs_grudge_warping_tooltip = { en = "Manual mode: enable Warping modifier (chip damage / warp pulse)." },
    gt_cs_grudge_intangible      = { en = "Intangible" },
    gt_cs_grudge_intangible_tooltip = { en = "Manual mode: enable Intangible modifier (periodic damage immunity)." },
    gt_cs_grudge_unstaggerable   = { en = "Unstaggerable" },
    gt_cs_grudge_unstaggerable_tooltip = { en = "Manual mode: enable Unstaggerable modifier (immune to stagger)." },
    gt_cs_grudge_raging          = { en = "Raging" },
    gt_cs_grudge_raging_tooltip  = { en = "Manual mode: enable Raging modifier (frenzy attack speed)." },
    gt_cs_grudge_vampiric        = { en = "Vampiric" },
    gt_cs_grudge_vampiric_tooltip = { en = "Manual mode: enable Vampiric modifier (heals on hit)." },
    gt_cs_grudge_ranged_immune   = { en = "Ranged Immune" },
    gt_cs_grudge_ranged_immune_tooltip = { en = "Manual mode: enable Ranged Immune modifier (takes no damage from ranged sources)." },
    gt_cs_grudge_periodic_shield = { en = "Periodic Shield" },
    gt_cs_grudge_periodic_shield_tooltip = { en = "Manual mode: enable Periodic Shield modifier (intermittent invulnerability)." },
    gt_cs_grudge_crippling       = { en = "Crippling" },
    gt_cs_grudge_crippling_tooltip = { en = "Manual mode: enable Crippling modifier (slows the player on hit)." },
    gt_cs_grudge_crushing        = { en = "Crushing" },
    gt_cs_grudge_crushing_tooltip = { en = "Manual mode: enable Crushing modifier (heavy push back / extra knockback)." },
    gt_cs_grudge_regenerating    = { en = "Regenerating" },
    gt_cs_grudge_regenerating_tooltip = { en = "Manual mode: enable Regenerating modifier (passive heal-back)." },
    gt_cs_grudge_periodic_curse  = { en = "Periodic Curse" },
    gt_cs_grudge_periodic_curse_tooltip = { en = "Manual mode: enable Periodic Curse modifier (debuffs nearby players)." },
    gt_cs_grudge_commander       = { en = "Commander" },
    gt_cs_grudge_commander_tooltip = { en = "Manual mode: enable Commander modifier (buffs nearby allies)." },
    gt_cs_grudge_frenzy          = { en = "Frenzy" },
    gt_cs_grudge_frenzy_tooltip  = { en = "Manual mode: enable Frenzy modifier (attack speed scales with missing HP)." },

    gt_is_group = { en = "Item Spawner" },
    gt_is_next_hotkey = { en = "Next Pickup" },
    gt_is_next_hotkey_tooltip = { en = "Hotkey: cycle to the next pickup in the live AllPickups list (excludes loot_die / lorebook_pages / beer_barrel / *_limited / endurance_badge). Same as '/gt_nextitem'. Spawn the selected pickup with the 'Spawn Pickup' hotkey or '/gt_spawnitem'." },
    gt_is_prev_hotkey = { en = "Previous Pickup" },
    gt_is_prev_hotkey_tooltip = { en = "Hotkey: cycle to the previous pickup. Same as '/gt_previtem'." },
    gt_is_spawn_hotkey = { en = "Spawn Selected Pickup" },
    gt_is_spawn_hotkey_tooltip = { en = "Hotkey: spawn the currently selected pickup at your feet via vanilla's rpc_spawn_pickup_with_physics. Training dummies are host-only. Same as '/gt_spawnitem' (no arg). '/gt_spawnitem <substring>' fuzzy-matches by pickup name or localized item name." },

    -- ============================================================
    -- Host-Side Lobby Controls (absorbed from lobby_tweaker
    -- 2026-05-25; lt v0.1.7-dev). Keys + tooltips renamed lt_* /
    -- bare-form -> gt_lobby_* per merge.
    -- ============================================================
    gt_lobby_controls_group = { en = "Host-Side Lobby Controls" },

    -- Slot Reservations
    gt_lobby_slot_reservations_enabled = { en = "Enable slot reservations" },
    gt_lobby_slot_reservations_enabled_tooltip = { en = "Host-only. Reserve lobby slots for specific Steam IDs via /gt_lobby_reserve <steam_id> <1-4>. Non-reserved joiners are auto-kicked while a reservation is pending (the reserved peer isn't already in the lobby). /gt_lobby_reservations lists current entries." },

    -- Session Ignore List
    gt_lobby_session_ignore_enabled = { en = "Enable ignore list" },
    gt_lobby_session_ignore_enabled_tooltip = { en = "Host-only. Two-tier ignore: session-only (/gt_lobby_ignore) and persistent (/gt_lobby_ignore_persist). Either tier auto-kicks the peer on join. /gt_lobby_unignore clears, /gt_lobby_ignored lists, /gt_lobby_ignore_last re-adds the most recent host-kicked peer." },

    -- Kick on Idle
    gt_lobby_kick_idle_enabled = { en = "Auto-kick idle players in keep" },
    gt_lobby_kick_idle_enabled_tooltip = { en = "Host-only. While in the keep, polls every 30s for non-host, non-bot player_unit position; if a player hasn't moved more than 0.05m for the threshold below, they get a warning then a kick. /gt_lobby_idle_whitelist exempts specific Steam IDs." },
    gt_lobby_kick_idle_threshold_minutes = { en = "Idle threshold (minutes)" },
    gt_lobby_kick_idle_threshold_minutes_tooltip = { en = "Range 1-60. How long a player can stand still in the keep before being kicked." },
    gt_lobby_ki_warn_seconds = { en = "Warning lead time (seconds)" },
    gt_lobby_ki_warn_seconds_tooltip = { en = "Range 10-180. How far ahead of the kick the warning chat message fires." },

    -- Message of the Day
    gt_lobby_motd_enabled = { en = "Send MOTD to joiners" },
    gt_lobby_motd_enabled_tooltip = { en = "Host-only. When a peer joins the party, send the MOTD text below. Chat / popup channels configurable. Joiners without general_tweaker installed will NOT see the MOTD (no vanilla path to push system messages to a remote chat HUD)." },
    gt_lobby_motd_text = { en = "MOTD text (use \\n for line breaks)" },
    gt_lobby_motd_text_tooltip = { en = "The message body. Use \\n in the text to insert line breaks; literal newlines also accepted. Chunked into <=400-char RPC pieces internally so the Stingray 500-char string cap doesn't truncate." },
    gt_lobby_motd_send_chat = { en = "Send via chat" },
    gt_lobby_motd_send_chat_tooltip = { en = "Render the MOTD in the receiver's local chat panel (one line per \\n)." },
    gt_lobby_motd_send_popup = { en = "Send via popup" },
    gt_lobby_motd_send_popup_tooltip = { en = "Render the MOTD as a modal popup with an OK button on the receiver's screen." },
    gt_lobby_motd_once_per_peer_per_session = { en = "Only greet each peer once per session" },
    gt_lobby_motd_once_per_peer_per_session_tooltip = { en = "Default ON: each peer is greeted at most once per host process lifetime. Turn OFF to re-greet on every party-join event (useful when a peer reconnects)." },
    gt_lobby_motd_popup_topic = { en = "Message of the Day" },

    -- Modded Lobby Manifest
    gt_lobby_manifest_broadcast_enabled = { en = "Broadcast my mod list (as host)" },
    gt_lobby_manifest_broadcast_enabled_tooltip = { en = "Host-only. Publishes a per-mod manifest (id, version, mode, workshop_id, name) to Steam lobby_data so joining clients can read it on hash mismatch. Hash-neutral; ~1KB per chunk; rate-limited to 1 republish per 500ms." },
    gt_lobby_manifest_failnotify_enabled = { en = "Show missing mods when a join fails" },
    gt_lobby_manifest_failnotify_enabled_tooltip = { en = "Client-side. On the vanilla 'incorrect hash' failed-join popup, fetch the host's manifest from Steam lobby_data and replace the popup with one listing missing required mods + an Open-Workshop button. Falls back to the vanilla popup if the host isn't broadcasting." },

    -- Failed-join manifest reveal (rendered text)
    gt_lobby_failnotify_title              = { en = "Cannot join -- modded host" },
    gt_lobby_failnotify_required_header    = { en = "You are missing %%d mods required by the host:" },
    gt_lobby_failnotify_version_header     = { en = "%%d mods have a version mismatch:" },
    gt_lobby_failnotify_cosmetic_footer    = { en = "Host also has %%d cosmetic mods you don't (gameplay unaffected)." },
    gt_lobby_failnotify_button_workshop    = { en = "Open Workshop" },
    gt_lobby_failnotify_button_cancel      = { en = "Close" },

    -- Self-refreshing vanilla-name dump (feeds tools/gen-name-map).
    gt_auto_name_dump = { en = "Auto-dump vanilla item names" },
    gt_auto_name_dump_tooltip = { en = "Default ON. On keep entry, once per game build, silently writes every vanilla item/career/breed loc_key and its English name to the console log (prefix [gt:name_dump]). Feeds the repo name-map generator so vanilla names stay current with zero manual action. Re-fires automatically after a game patch. Force a re-dump with /gt_dump_names." },

    -- Universal Debug Logging toggle (PROJECT_STANDARDS.md § 3.6).
    -- v0.2.54-dev: renamed from `gt_debug_mode` (was nested in `gt_debug_group`)
    -- to the universal `enable_debug_logging` key.
    enable_debug_logging = { en = "Debug Logging" },
    enable_debug_logging_tooltip = { en = "Emit detailed diagnostic logs to %%APPDATA%%\\Fatshark\\Vermintide 2\\console_logs\\. Increases log volume; enable when investigating a bug, then disable." },
    memwatch_interval = { en = "Memory Watchdog Interval (sec)" },
    memwatch_interval_tooltip = { en = "How often the Lua memory watchdog logs a [memwatch] heap-size line WHILE Debug Logging is on. Lower = finer growth curve, more log lines. Default 10s. (The watchdog runs automatically whenever Debug Logging is enabled — read the [memwatch] lines in the console log for the heap growth curve when hunting a leak.)" },
    gc_mitigation_enabled = { en = "Aggressive GC (long-session leak mitigation)" },
    gc_mitigation_enabled_tooltip = { en = "Tightens Lua's garbage collector so the heap stays close to the live set instead of growing to 2x before collecting. Helps survive a long (~1hr) Chaos Wastes run despite the memory leak under investigation. Buys time when the growth is collectable garbage / GC lag; does NOT help if it's a true reference leak. Slight extra CPU for GC. Turn on for long runs." },
    gc_full_collect_sec = { en = "Force Full GC Every (sec, 0=off)" },
    gc_full_collect_sec_tooltip = { en = "When Aggressive GC is on, force a complete garbage collection this often. Reclaims everything the incremental collector hasn't. Each collect causes a brief frame hitch (bigger heap = longer) but a short stutter beats a crash. 0 = off. Try 30-60 if the heap still climbs." },
}
