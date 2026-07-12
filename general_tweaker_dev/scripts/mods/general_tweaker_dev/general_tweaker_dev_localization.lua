-- Localization for gt_dev. Ordered to MIRROR the widget tree in
-- general_tweaker_dev_data.lua: one banner per top-level group, groups A->Z,
-- entries within each group in widget order (loose options A->Z; deliberate /
-- index-locked / workflow orders noted in the data file).
--
-- NOTE: literal '%' MUST be escaped as '%%' -- VMF's mod:localize runs every
-- string through string.format (safe_string_format, vmf .../core/localization.lua),
-- so a bare '%' is read as a format spec ('% C' -> "invalid option to format" crash).
-- Guards: qa/check_localization.ps1 (static, pre-ship) + the
-- `localization_format_safe` regression test (runtime, /gt_regression_test).
-- No em dashes ("--") in menu-facing strings.

return {
    mod_description = {
        en = "A grab bag of gameplay tweaks and host tools: bot behavior, lobby controls, spawners, noclip, godmode, and other cheats.",
    },

    -- ============================================================
    -- Bots
    -- ============================================================
    gt_bot_options_group = { en = "[working] Bots" },

    -- Loose bot options (A->Z by display label; status tags ignored).
    gt_ai_afk_takeover = { en = "[Issue 247] AFK Bot Takeover" },
    gt_ai_afk_takeover_tooltip = { en = "If you give no input for 20 seconds, a bot takes over your character, and you resume control the moment you press anything. Affects only your own character and works during missions only, not in Versus or the keep." },

    gt_bots_in_keep = { en = "[crash] [Issue 65] Allow Bots in Keep" },
    gt_bots_in_keep_tooltip = { en = "While in the keep, allows bots so you can preview loadouts and have a full lobby. Works only when you are the host, and the bots are removed when you turn it off." },

    gt_bot_guard_break_msg = { en = "[untested] Announce when a bot's guard breaks (Replicant)" },
    gt_bot_guard_break_msg_tooltip = { en = "Posts a chat message whenever a bot teammate's block is broken. Choose who sees it below; works only when you are the host." },
    gt_bot_guard_break_msg_none   = { en = "Off" },
    gt_bot_guard_break_msg_host   = { en = "Host only (just me)" },
    gt_bot_guard_break_msg_global = { en = "Host + clients (everyone)" },
    -- The chat line itself when a bot's guard breaks (code-referenced).
    gt_bot_guard_break_chat = { en = "A bot's guard was broken!" },

    -- Bot Behavior Improvements master toggle + nested sub-toggles (#297,
    -- v0.2.182-dev). The master gates everything; each fix below is now
    -- individually toggleable while the master is on. Checkbox ids reuse the
    -- pre-bundle setting ids (retired v0.2.128-dev); the delay sliders replace
    -- the formerly hard-coded 3s / 4s. Children in FEATURE order (matches the
    -- data file), not A->Z. Tags: [working] where the CHANGELOG records an
    -- in-game confirmation of the wrapped fix, [untested] otherwise; the
    -- greedy-pickup item is brand-new (#297 item 8).
    gt_bot_behavior_improvements = { en = "[Issue 297, 139, 142 & 468] Bot Behavior Improvements" },
    gt_bot_behavior_improvements_tooltip = { en = "Master switch for the bot fixes listed underneath; while it is on, each fix can be toggled individually below. Covers Necromancer potion handoff, keeping the mission alive while a bot still stands, ledge recovery, ladder unstick, instant and greedy item pickup, smarter self-healing, revive and rescue priority, and reviving during the Ironbreaker ult. Works only when you are the host." },

    gt_bot_necro_potion_handoff = { en = "[working] Necromancer bots hand off potions" },
    gt_bot_necro_potion_handoff_tooltip = { en = "A Necromancer bot brings a real potion forward over its skull item, so it can drink it or pass it to a teammate, which the skull otherwise blocks." },

    gt_bot_mission_fail_prevention = { en = "[untested] Keep the mission going while a bot lives" },
    gt_bot_mission_fail_prevention_tooltip = { en = "Normally the run ends when every human is down even if a bot still stands; with this on, the mission only fails when no teammate, human or bot, remains." },

    gt_bot_ledge_pullup = { en = "[untested] Bots pull themselves up from ledges" },
    gt_bot_ledge_pullup_tooltip = { en = "A bot left hanging from a ledge climbs back up on its own after the delay below instead of waiting for a rescue." },

    gt_bot_ledge_pullup_delay = { en = "[untested] Ledge pull-up delay (seconds)" },
    gt_bot_ledge_pullup_delay_tooltip = { en = "How many seconds a bot hangs from a ledge before climbing back up; 0 makes the recovery instant." },

    gt_bot_ladder_unstick = { en = "[working] Bots free themselves from ladders" },
    gt_bot_ladder_unstick_tooltip = { en = "A bot wedged on a ladder teleports to a teammate after the delay below instead of staying stuck there." },

    gt_bot_ladder_unstick_delay = { en = "[working] Ladder unstick delay (seconds)" },
    gt_bot_ladder_unstick_delay_tooltip = { en = "How many seconds a bot may sit on a ladder before it teleports to a teammate. Values below 3 would trigger during normal climbs, so 3 is the minimum." },

    gt_bot_instant_pickup = { en = "[working] Bots instantly grab targeted items" },
    gt_bot_instant_pickup_tooltip = { en = "The pickup a bot is going for, including pinged items, is grabbed from where the bot stands instead of it walking all the way over." },

    gt_bot_greedy_pickup = { en = "[untested] Bots collect items players leave behind" },
    gt_bot_greedy_pickup_tooltip = { en = "Normally bots refuse to take potions, bombs, and healing while a nearby player has a free slot for them; with this on they collect such items anyway, then carry them and hand them over when asked or needed." },

    -- #468: control WHEN a bot spends a heal on itself (bots cannot heal another
    -- player -- that is not a game feature -- so this is self-use timing only).
    gt_bot_smart_self_heal = { en = "[untested] [diag] [Issue 468] Smarter bot self-healing" },
    gt_bot_smart_self_heal_tooltip = { en = "Decide for yourself when a bot spends healing on itself instead of the game's fixed rules, which drink a full Draught of Healing at 40 percent health and burn Medical Supplies at 20 percent even when a player could use them better. With this on, the three settings below take over. Bots cannot heal other players (the game has no such action), so this only changes self-use timing; carrying and handing items to players is the greedy-pickup option above. Works only when you are the host." },

    gt_bot_self_heal_pct = { en = "[untested] [Issue 468] Bot self-heal health threshold (%%)" },
    gt_bot_self_heal_pct_tooltip = { en = "A bot only heals itself once its health drops to this percentage or lower. Lower values make bots hold their healing longer (less waste); higher values make them heal sooner. Applies to both draughts and medical supplies, replacing the game's fixed 40 and 20 percent triggers." },

    gt_bot_reserve_kits_for_players = { en = "[untested] [Issue 468] Bots reserve medical supplies for players" },
    gt_bot_reserve_kits_for_players_tooltip = { en = "Medical Supplies can heal a hurt teammate, so a bot holds onto them instead of using them on itself, unless it is wounded (grey health) or spare healing is lying around anyway. Draughts of Healing, which only heal the drinker, are not affected." },

    gt_bot_ignore_surplus_selfuse = { en = "[untested] [Issue 468] Bots don't top themselves off on spare healing" },
    gt_bot_ignore_surplus_selfuse_tooltip = { en = "The game tells a bot to drink its healing when more healing items are lying around than players to use them, even at high health. With this on a bot ignores that prompt and keeps its healing until it actually needs it." },

    gt_bot_aid_priority = { en = "[verify-fix] [Issue 492] Bots prioritize reviving and rescuing" },
    gt_bot_aid_priority_tooltip = { en = "Downed, hooked, and ledge-hanging allies always outrank following and other chores, so a bot commits to the revive or rescue and walks the whole way there." },

    gt_bot_ignore_backward_gate = { en = "[verify-fix] [Issue 515] Bots go back for stragglers and past no-return points" },
    gt_bot_ignore_backward_gate_tooltip = { en = "The game normally refuses to teleport or path a bot backward along the level, so a player who drops behind it is left alone until they catch up, and a bot shoved past a point of no return (over a ledge into the next area) stays stuck for the rest of the run. With this on that block is lifted: a lagging follow target still pulls the bot back, a teammate who goes down behind the bot is retried right away, and a bot that cannot walk back to the team teleports to regroup once it is genuinely stuck, and can do so again later in the run. Reviving and rescuing keep priority over merely catching up." },

    gt_bot_ironbreaker_revive_in_ult = { en = "[working] Ironbreaker bots revive during their ult" },
    gt_bot_ironbreaker_revive_in_ult_tooltip = { en = "The career skill no longer parks the bot in a blocking stance for its whole duration; the bot breaks off to revive or rescue an ally while the damage-reduction buff keeps running." },

    -- issue 448 (FIX 11): downed bot must not project the Morr's Protection aura.
    gt_bot_no_downed_morrs_grant = { en = "[untested] [Issue 448] Downed bots don't grant Morr's Protection" },
    gt_bot_no_downed_morrs_grant_tooltip = { en = "The Chaos Wastes boon Morr's Protection makes downed allies near the carrier invulnerable, and the game keeps that aura running even while the carrier is downed itself. Two bots carrying it that go down near each other protect each other forever: they can't be finished, can't get up, and the run soft-locks. With this on, a bot stops granting the aura while it is knocked down and resumes the moment it is back up. Human carriers and standing bots are untouched. Host-side only." },

    -- Bot follow mode dropdown (v0.2.152-dev) -- consolidates the previous
    -- gt_bot_split_among_players + gt_bot_follow_host checkboxes into one
    -- tri-state setting.
    gt_bot_follow_mode = { en = "[diag] [Issue 261] Bot follow mode" },
    gt_bot_follow_mode_tooltip = { en = "Three modes: Default (normal behavior), Follow Host (all bots stick to the host), or Split (one bot per human, host first). Bots still break off to revive or rescue an ally, and this only works when you are the host." },
    gt_bot_follow_mode_default     = { en = "Default" },
    gt_bot_follow_mode_follow_host = { en = "Follow Host" },
    gt_bot_follow_mode_split       = { en = "Split" },

    ai_takeover_enabled = { en = "[Issue 247] Bot Takeover" },
    ai_takeover_enabled_tooltip = { en = "Step away or test while bot AI drives your character, and take control back by turning it off. Not available in Versus or the keep, and your consumables and ammo are not kept when control changes." },

    -- Replicant Bots ports (v0.2.131-dev). All host-side, default OFF, ported
    -- from the "Replicant Bots - Different Bots Experimental Branch" mod.
    gt_bot_drink_potions_in_danger = { en = "[untested] Bots drink potions when in danger (Replicant)" },
    gt_bot_drink_potions_in_danger_tooltip = { en = "A bot drinks a potion it is carrying instead of hoarding it when danger is near. Expand this option to choose exactly which situations count as danger and how close enemies must be. Works only when you are the host." },

    -- #320 advanced conditions: what counts as "danger" for a bot to drink.
    gt_bot_drink_range_m = { en = "Danger scan range (m)" },
    gt_bot_drink_range_m_tooltip = { en = "How close an enemy must be to count toward the danger checks below. Larger values make bots drink earlier." },

    gt_bot_drink_on_boss = { en = "Drink near a boss or lord" },
    gt_bot_drink_on_boss_tooltip = { en = "Drink when a monster, boss, or lord is in range (Rat Ogre, Chaos Spawn, Troll, Minotaur, Stormfiend, map bosses, etc.). On by default." },

    gt_bot_drink_on_special = { en = "Drink near a special" },
    gt_bot_drink_on_special_tooltip = { en = "Drink when a special enemy is in range (Gutter Runner, Packmaster, Blightstormer, Ratling Gunner, Warpfire Thrower, Leech, etc.). Off by default." },

    gt_bot_drink_on_patrol = { en = "Drink near an elite patrol" },
    gt_bot_drink_on_patrol_tooltip = { en = "Drink when at least the set number of elites are in range at once (Stormvermin, Maulers, Savages). Tune the count below. On by default." },

    gt_bot_drink_patrol_count = { en = "Elites needed for a patrol" },
    gt_bot_drink_patrol_count_tooltip = { en = "How many elites must be in range at once before it counts as a patrol worth a potion." },

    gt_bot_drink_on_horde = { en = "Drink during a horde" },
    gt_bot_drink_on_horde_tooltip = { en = "Drink when at least the set number of ordinary trash enemies are in range at once. Off by default." },

    gt_bot_drink_horde_count = { en = "Enemies needed for a horde" },
    gt_bot_drink_horde_count_tooltip = { en = "How many ordinary trash enemies must be in range at once before it counts as a horde worth a potion." },

    gt_bot_rescue_awaiting = { en = "[Issue 300] Bots rescue allies awaiting respawn" },
    gt_bot_rescue_awaiting_tooltip = { en = "Vanilla bots ignore a teammate waiting to be rescued at a respawn point; this sends them to go free that ally. Works only when you are the host; experimental, so verify it in game." },

    gt_no_bots = { en = "[untested] Disable Bots" },
    gt_no_bots_tooltip = { en = "Keeps bots from filling empty party slots and instantly removes any already present, for true solo runs. Works only when you are the host and stays in effect across missions until you turn it off." },

    gt_bot_fast_reactions = { en = "[untested] Faster bot reactions (Replicant)" },
    gt_bot_fast_reactions_tooltip = { en = "Cuts bot reaction time to threats down to a fraction of a second. Works only when you are the host." },

    -- (gt_bot_follow_distance_enabled removed 2026-06-30 -- the slider below is now the sole control; 40 = off.)
    gt_bot_follow_distance_m = { en = "[diag] [Issue 261 & 139] Follow snap-back distance (meters)" },
    gt_bot_follow_distance_m_tooltip = { en = "How far a bot may fall behind before it snaps back to you; 40 (the maximum) does nothing, and lower values keep bots closer, with about 15 to 20 the practical limit. Works only when you are the host." },

    gt_improved_bot_combat = { en = "[Issue 298] Improved Bot Combat" },
    gt_improved_bot_combat_tooltip = { en = "Bot teammates make smarter attack choices, ping the elite hitting them, stop chasing distant specials, ignore far-off gunners, do not over-focus bosses, and time abilities better for several careers. Works only when you are the host." },

    -- ============================================================
    -- Cheats and Debug
    -- ============================================================
    cheats_debug_group = { en = "[working] Cheats and Debug" },

    -- Loose cheat primitives (A->Z).
    clear_enemies_hotkey = { en = "[untested] Clear Enemy Spawns" },
    clear_enemies_hotkey_tooltip = { en = "Every enemy currently alive vanishes at once, except any tied to mission objectives so nothing breaks. Works only when you are the host." },

    disable_enemy_spawns = { en = "[Issue 242] Disable Enemy Spawns" },
    disable_enemy_spawns_tooltip = { en = "No new enemies appear at all: hordes, specials, bosses, patrols, and ambient critters. Enemies already present are left alone, and turning it off resumes normal spawning." },

    godmode_enabled = { en = "[working] Godmode" },
    godmode_enabled_tooltip = { en = "Makes you invincible: you take no damage and cannot be grabbed or pinned by disablers, and enemies stop noticing you. Your third-person body fades out while it is on; your own view stays normal." },

    noclip_enabled = { en = "[Issue 241] Noclip" },
    noclip_enabled_tooltip = { en = "Fly freely through walls and terrain: WASD moves you where you look, Space and Ctrl go up and down, and holding Shift speeds you up. Turning it off while airborne drops you to the ground." },
    noclip_speed = { en = "[working] Noclip Base Speed" },
    noclip_speed_tooltip = { en = "How fast you fly, in metres per second. The default of about 15 is roughly four times normal walking speed." },
    noclip_boost_multiplier = { en = "[working] Noclip Shift-Boost Multiplier" },
    noclip_boost_multiplier_tooltip = { en = "How much holding Left Shift multiplies your flight speed. At 3.0 you fly about three times faster than the base speed." },
    noclip_hotkey = { en = "[working] Noclip Toggle" },
    noclip_hotkey_tooltip = { en = "Remembers your state, so one press drops you into noclip flight and the next returns you to normal movement." },

    -- ---- Buffs & Stats ----
    buffs_group = { en = "[working] Buffs & Stats" },
    base_crit_chance = { en = "[untested] Base Crit Chance (%%)" },
    base_crit_chance_tooltip = { en = "Most careers start at 5%%; this raises or lowers that rate for your current career. It resets to the career's normal value when you switch careers and after a game restart." },
    gt_fall_damage_enabled = { en = "[untested] Fall damage multiplier" },
    gt_fall_damage_enabled_tooltip = { en = "When off, fall damage is normal; when on, the multiplier below takes effect. The host's setting applies to everyone in the lobby." },
    gt_fall_damage_mult = { en = "[untested] Fall damage multiplier (1 = normal, 0 = none, 5 = 5x)" },
    gt_fall_damage_mult_tooltip = { en = "1.0 is normal, 0 removes fall damage entirely, and up to 5.0 makes tall falls five times as deadly. Only used while the fall damage toggle above is on." },
    movement_speed = { en = "[untested] Movement Speed (m/s)" },
    movement_speed_tooltip = { en = "The default is 4 metres per second; higher values make everyone move faster. Resets after a game restart, and in a lobby the host's value affects everyone." },

    -- ---- Level Control ----
    level_control_group = { en = "[working] Level Control" },
    fail_level_hotkey = { en = "[untested] Fail Level" },
    fail_level_hotkey_tooltip = { en = "Sends the whole team straight to the defeat screen, ending the run on the spot. Available during a mission only, not in the keep." },
    fix_sound_hotkey = { en = "[untested] Fix Vortex Sound" },
    fix_sound_hotkey_tooltip = { en = "Silences the looping wind or storm effect that can get stuck after a mid-storm mission restart. Works during a mission only." },
    kill_bots_hotkey = { en = "[untested] Kill Bots" },
    kill_bots_hotkey_tooltip = { en = "On the official realm this is only allowed before the round starts; the modded realm has no restriction. Every bot in your party goes down at once." },
    down_bots_hotkey = { en = "[verify-fix] Down Bots (Morr's test)" },
    down_bots_hotkey_tooltip = { en = "Host only. Forces every standing bot into the downed bleedout state at once, the same way lethal damage would, but without killing them. Use it to test the Morr's Protection soft-lock fix: give two bots the Morr's Protection boon, down them close together, and they should still bleed out instead of becoming permanently invulnerable. Does nothing in the keep." },
    restart_level_hotkey = { en = "[untested] Restart Level" },
    restart_level_hotkey_tooltip = { en = "Reloads the current mission from the beginning with the same team and difficulty. Does nothing in the keep." },
    die_hotkey = { en = "[untested] Suicide" },
    die_hotkey_tooltip = { en = "Your own character drops dead on the spot. Does nothing in the keep." },
    gt_bot_toggle_hotkey = { en = "[untested] Toggle Bots On/Off" },
    gt_bot_toggle_hotkey_tooltip = { en = "On the current level, bots either start spawning (including in the keep) or are removed mid-mission. Keep bots can occasionally cause a rare crash." },
    win_level_hotkey = { en = "[untested] Win Level" },
    win_level_hotkey_tooltip = { en = "Jumps straight to the end-of-mission victory screen and its rewards. Does nothing in the keep." },

    -- ---- Spawners ----
    -- Creature Spawner + Item Spawner (ported from Aussiemon's CreatureSpawner
    -- mod, Workshop ID 1395132559, MIT-licensed). gt_cs_* / gt_is_* namespaces.
    gt_spawners_group = { en = "[working] Spawners" },

    gt_cs_group = { en = "[verify-fix] [Issue 254] Creature Spawner" },
    gt_cs_unit_list = { en = "[untested] Available Unit List" },
    gt_cs_unit_list_tooltip = { en = "Choose which set of enemies the cycle hotkeys move through: Regular, Dummy (practice targets), Misc (debug units), Special, Boss, or All. Changing this jumps the selection to the first enemy in the new set." },
    gt_cs_unit_list_regular = { en = "Regular" },
    gt_cs_unit_list_dummy   = { en = "Dummy" },
    gt_cs_unit_list_misc    = { en = "Misc" },
    gt_cs_unit_list_special = { en = "Special" },
    gt_cs_unit_list_boss    = { en = "Boss" },
    gt_cs_unit_list_all     = { en = "All" },

    gt_cs_spawn = { en = "[untested] Keybind: Spawn Creature" },
    gt_cs_spawn_tooltip = { en = "Drops the currently selected enemy at wherever your crosshair points, ignoring the usual spawn limits. Works only when you are the host." },
    gt_cs_next = { en = "[untested] Keybind: Next Creature" },
    gt_cs_next_tooltip = { en = "Moves the selection forward by one in the active list, skipping any you cannot spawn such as DLC you do not own." },
    gt_cs_prev = { en = "[untested] Keybind: Previous Creature" },
    gt_cs_prev_tooltip = { en = "Moves the selection back by one in the active list." },
    gt_cs_destroy = { en = "[untested] Keybind: Destroy Spawned Creatures" },
    gt_cs_destroy_tooltip = { en = "Clears the whole level of enemies, not just the ones you placed. Works only when you are the host." },

    gt_cs_spawn_slot_1 = { en = "[untested] Keybind: Spawn Saved Slot 1" },
    gt_cs_spawn_slot_1_tooltip = { en = "Whatever enemy you saved to slot 1 appears at your crosshair." },
    gt_cs_spawn_slot_2 = { en = "[untested] Keybind: Spawn Saved Slot 2" },
    gt_cs_spawn_slot_2_tooltip = { en = "Whatever enemy you saved to slot 2 appears at your crosshair." },
    gt_cs_spawn_slot_3 = { en = "[untested] Keybind: Spawn Saved Slot 3" },
    gt_cs_spawn_slot_3_tooltip = { en = "Whatever enemy you saved to slot 3 appears at your crosshair." },

    gt_cs_mission_ai = { en = "[untested] Enable AI in Missions" },
    gt_cs_mission_ai_tooltip = { en = "On by default, so spawned enemies actually move and fight; with it off, they just stand still." },
    gt_cs_keep_ai = { en = "[untested] Enable AI in Keep" },
    gt_cs_keep_ai_tooltip = { en = "Off by default because it often crashes: most enemies need navigation data the keep lacks. Enabling it lets enemy AI run in the keep anyway." },

    gt_cs_grudge = { en = "[untested] Enable Grudge-Marked Modifiers" },
    gt_cs_grudge_tooltip = { en = "Newly spawned enemies can carry grudge-mark modifiers: Disabled for none, Random to roll a number of them (set by the slider below), or Manual to apply exactly the ones you check. There is a cap on active modifiers, so extras are skipped once it is reached." },
    gt_cs_grudge_disabled = { en = "Disabled" },
    gt_cs_grudge_random   = { en = "Random" },
    gt_cs_grudge_manual   = { en = "Manual" },
    gt_cs_grudge_random_modifier_count = { en = "[untested] Random Modifier Count" },
    gt_cs_grudge_random_modifier_count_tooltip = { en = "In Random mode, how many modifiers each spawn rolls (0 to 13)." },

    -- v0.2.131-dev: labels converted from internal grudge-mark names to the
    -- official in-game display names. Mapping verified against the Fatshark
    -- "All About Grudge Marks" article + the buff mechanics in
    -- scripts/settings/dlcs/grudge_marks/buff_settings_grudge_marks.lua
    -- (internal name kept in parentheses for cross-reference):
    --   warping->Shadow-Step  intangible->Illusionist  unstaggerable->Relentless
    --   raging->Mighty  vampiric->Vampiric  ranged_immune->Rampart
    --   periodic_shield->Invincible  crippling->Crippling  crushing->Shield-Shatter
    --   regenerating->Regenerating  periodic_curse->Cursed Aura
    gt_cs_grudge_warping         = { en = "[untested] Shadow-Step (Warping)" },
    gt_cs_grudge_warping_tooltip = { en = "Manual mode: the enemy teleports to a random spot near a player when hit." },
    gt_cs_grudge_intangible      = { en = "[untested] Illusionist (Intangible)" },
    gt_cs_grudge_intangible_tooltip = { en = "Manual mode: the enemy periodically summons three mirror images of itself." },
    gt_cs_grudge_unstaggerable   = { en = "[untested] Relentless (Unstaggerable)" },
    gt_cs_grudge_unstaggerable_tooltip = { en = "Manual mode: the enemy cannot be staggered." },
    gt_cs_grudge_raging          = { en = "[untested] Mighty (Raging)" },
    gt_cs_grudge_raging_tooltip  = { en = "Manual mode: the enemy periodically deals extra damage." },
    gt_cs_grudge_vampiric        = { en = "[untested] Vampiric" },
    gt_cs_grudge_vampiric_tooltip = { en = "Manual mode: the enemy heals from the damage it deals to players and bots." },
    gt_cs_grudge_ranged_immune   = { en = "[untested] Rampart (Ranged Immune)" },
    gt_cs_grudge_ranged_immune_tooltip = { en = "Manual mode: the enemy is immune to ranged damage and can only be killed in melee." },
    gt_cs_grudge_periodic_shield = { en = "[untested] Invincible (Periodic Shield)" },
    gt_cs_grudge_periodic_shield_tooltip = { en = "Manual mode: the enemy periodically becomes immune to all damage for a moment." },
    gt_cs_grudge_crippling       = { en = "[untested] Crippling" },
    gt_cs_grudge_crippling_tooltip = { en = "Manual mode: the enemy badly slows the movement and dodge of players it hits." },
    gt_cs_grudge_crushing        = { en = "[untested] Shield-Shatter (Crushing)" },
    gt_cs_grudge_crushing_tooltip = { en = "Manual mode: the enemy breaks blocks and briefly stops your stamina from recovering." },
    gt_cs_grudge_regenerating    = { en = "[untested] Regenerating" },
    gt_cs_grudge_regenerating_tooltip = { en = "Manual mode: the enemy regenerates health over time." },
    gt_cs_grudge_periodic_curse  = { en = "[untested] Cursed Aura (Periodic Curse)" },
    gt_cs_grudge_periodic_curse_tooltip = { en = "Manual mode: the enemy gives off a curse that drains the health of nearby players, and it stacks." },
    gt_cs_grudge_commander       = { en = "[untested] Commander" },
    gt_cs_grudge_commander_tooltip = { en = "Manual mode: the enemy buffs nearby allies." },
    gt_cs_grudge_frenzy          = { en = "[untested] Frenzy" },
    gt_cs_grudge_frenzy_tooltip  = { en = "Manual mode: the enemy attacks faster as it loses health." },

    gt_is_group = { en = "[working] Item Spawner" },
    gt_is_next_hotkey = { en = "[untested] Next Pickup" },
    gt_is_next_hotkey_tooltip = { en = "Moves the selection forward by one through the pickups you can place. Drop it with the Spawn Selected Pickup key." },
    gt_is_prev_hotkey = { en = "[untested] Previous Pickup" },
    gt_is_prev_hotkey_tooltip = { en = "Moves the selection back by one through the pickups you can place." },
    gt_is_spawn_hotkey = { en = "[untested] Spawn Selected Pickup" },
    gt_is_spawn_hotkey_tooltip = { en = "The currently selected pickup appears at your feet. Training dummies can only be placed by the host." },

    -- ---- Time & Pause ----
    time_group = { en = "[working] Time & Pause" },
    time_scale_value = { en = "[untested] Time Scale" },
    time_scale_value_tooltip = { en = "Ranges from 1 (slowest) to 24 (fastest), with 13 being normal game speed. Reapplied each mission but reset when the game restarts." },
    time_faster_hotkey = { en = "[untested] Time Faster" },
    time_faster_hotkey_tooltip = { en = "Bumps the Time Scale up by one step." },
    time_slower_hotkey = { en = "[untested] Time Slower" },
    time_slower_hotkey_tooltip = { en = "Bumps the Time Scale down by one step." },
    pause_value = { en = "[untested] Pause Speed" },
    pause_value_tooltip = { en = "The game speed used while paused, from 1 to 24. 1 is the slowest (closest to a real pause, though the interface keeps updating) and 13 is normal; the game has no true freeze." },
    pause_hotkey = { en = "[untested] Pause Toggle" },
    pause_hotkey_tooltip = { en = "Flips a host-only slow-motion pause on or off. Clients see it too, since game speed is controlled by the host." },

    -- ---- Ult ----
    ult_group = { en = "[working] Ult" },
    ult_bot_cap_enabled = { en = "[untested] Cap Bot Ult Cooldown" },
    ult_bot_cap_enabled_tooltip = { en = "Same as the player cap, but for bots. Useful in solo play to see bots use their ults more often." },
    ult_bot_cap_value = { en = "[untested] Max Bot Ult Cooldown (seconds)" },
    ult_bot_cap_value_tooltip = { en = "The longest career ability cooldown allowed for bots, in seconds. Set to 0 so bots ult constantly." },
    ult_player_cap_enabled = { en = "[untested] Cap Player Ult Cooldown" },
    ult_player_cap_enabled_tooltip = { en = "Keeps every human player's career ability cooldown at or below the limit set below. Effectively a short, adjustable ult cooldown for players." },
    ult_player_cap_value = { en = "[untested] Max Player Ult Cooldown (seconds)" },
    ult_player_cap_value_tooltip = { en = "The longest career ability cooldown allowed for human players, in seconds. Set to 0 for an always-ready ult." },
    ult_reset_hotkey = { en = "[untested] Ult Reset" },
    ult_reset_hotkey_tooltip = { en = "Your career ability becomes ready to use again at once. A one-time effect; it does not keep the ability charged." },

    -- ============================================================
    -- Dev Tools (dev-stream only; the group is appended in the data file ONLY
    -- when mod == get_mod("gt".."_dev")). Bot behavior HUD + leash lines.
    -- ============================================================
    gt_devtools_group = { en = "[untested] Dev Tools" },

    gt_devtools_bot_hud = { en = "[crash] [Issue 293 & 295] Bot behavior HUD" },
    gt_devtools_bot_hud_tooltip = { en = "Draws a column per bot showing its current behavior-tree action, the teammate it follows, distance to that teammate and to you, whether it just teleported, its teleport tally, and the last twenty actions it entered. On-screen, host-only, dev build only." },

    gt_devtools_leash_lines = { en = "[untested] Bot leash lines (3D)" },
    gt_devtools_leash_lines_tooltip = { en = "Runs a line in the world from each bot to the teammate it follows and another to you, so the follow leash is visible at a glance. Purely visual, host-only, dev build only." },

    -- Debug Highlights (#302). Master + per-category wireframe overlays. Dev build
    -- only; all children default OFF. Titles carry [untested] per LOCALIZATION_STANDARD
    -- section 13; tooltips name the color and note the two known approximations.
    gt_debug_highlights = { en = "[verify-fix] Debug Highlights" },
    gt_debug_highlights_tooltip = { en = "Master toggle for in-world debug wireframes. Turn on a category below. Wireframe only this build; dev build only, works on host and client." },

    gt_dh_interactables = { en = "[untested] Interactables" },
    gt_dh_interactables_tooltip = { en = "Yellow box around interactable objects: doors, chests, levers, anything used with the interact key." },

    gt_dh_pickups = { en = "[untested] Item Pickups" },
    gt_dh_pickups_tooltip = { en = "Green box on ground pickups: health, ammo, potions, bombs, tomes, grimoires." },

    gt_dh_pickup_spawners = { en = "[untested] Pickup Spawn Points" },
    gt_dh_pickup_spawners_tooltip = { en = "Grey box on pickup spawn points, shown even when the spawn is empty." },

    gt_dh_hitboxes_enemies = { en = "[untested] Enemy Hitboxes" },
    gt_dh_hitboxes_enemies_tooltip = { en = "Red box around each nearby enemy's bounding volume. Whole-unit box: per-limb capsules are not exposed to mods." },

    gt_dh_hitboxes_players = { en = "[untested] Player Hitboxes" },
    gt_dh_hitboxes_players_tooltip = { en = "Dark green box around each hero's bounding volume." },

    gt_dh_headshot_zones = { en = "[untested] Headshot Zones" },
    gt_dh_headshot_zones_tooltip = { en = "Orange sphere at each enemy's head node. Approximate radius: the true headshot capsule size is not exposed to mods." },

    gt_dh_aggro_ranges = { en = "[untested] Aggro Ranges" },
    gt_dh_aggro_ranges_tooltip = { en = "Amber ring at each enemy's detection radius. Enemy perception is a radius, not a cone." },

    gt_dh_range = { en = "[untested] Draw Distance" },
    gt_dh_range_tooltip = { en = "Only draw highlights within this distance of you. Higher values cost more per frame." },
    gt_dh_range_20 = { en = "20 m" },
    gt_dh_range_30 = { en = "30 m" },
    gt_dh_range_50 = { en = "50 m" },

    -- ============================================================
    -- Gameplay
    -- ============================================================
    gameplay_group = { en = "[working] Gameplay" },

    -- (gt_gk_group removed 2026-06-30 -- was a redundant single-item group; gt_gk_quests_enabled is now a direct master toggle.)
    gt_gk_quests_enabled = { en = "[untested] Choose Grail Knight Quests" },
    gt_gk_quests_enabled_tooltip = { en = "Overrides the Grail Knight's random quest picks with the three quests you choose below; any left on Random use the normal shuffle. The Chaos Wastes extra-quest talent still draws from the remaining quests." },
    gt_gk_quest1 = { en = "[untested] Quest 1" },
    gt_gk_quest1_tooltip = { en = "The first quest to assign the Grail Knight. Random leaves it to the normal shuffle." },
    gt_gk_quest2 = { en = "[untested] Quest 2" },
    gt_gk_quest2_tooltip = { en = "The second quest to assign. Duplicates are skipped: if the first quest already took this one, this slot falls back to the normal shuffle." },
    gt_gk_quest3 = { en = "[untested] Quest 3" },
    gt_gk_quest3_tooltip = { en = "The third quest to assign. Duplicates are skipped, the same as the second quest." },

    -- Grail Knight quest dropdown OPTION labels. These are real localization
    -- keys (not plain text) because VMF's localize_dropdown_data runs each
    -- option's `text` through mod:localize -- a real key resolves to the display
    -- string below; plain text would fall through to the `<...>` missing-key
    -- fallback. Paired with the per-dropdown factory in the data file so the
    -- three quest dropdowns never share (and re-localize) one options table.
    gt_gk_opt_random = { en = "Random (vanilla)" },
    gt_gk_opt_power_level = { en = "Power vs. Elites" },
    gt_gk_opt_attack_speed = { en = "Attack Speed" },
    gt_gk_opt_cooldown_reduction = { en = "Cooldown Reduction" },
    gt_gk_opt_health_regen = { en = "Health Regen" },
    gt_gk_opt_damage_taken = { en = "Damage Reduction" },

    disable_friendly_fire = { en = "[working] Disable Friendly Fire" },
    disable_friendly_fire_tooltip = { en = "No damage passes between teammates, ranged or melee. Higher difficulties normally let friendly ranged fire through; this stops that." },

    gt_adventure_save_trait_chance = { en = "[untested] Healer's Touch, Home Brewer, Grenadier %% Chance" },
    gt_adventure_save_trait_chance_tooltip = { en = "Vanilla gives these three Adventure charm traits a 25%% save chance each; raise it up to 75 to make them more worthwhile. Each player sets their own." },

    -- (gt_prio_specials_group became a master toggle gt_prio_specials_enabled 2026-06-30.)
    gt_prio_specials_enabled = { en = "[untested] Prioritize Specials (Tagging, Deepwood and Soulstealer)" },
    gt_prio_specials_enabled_tooltip = { en = "Biases your aim toward Special enemies, with three sub-toggles to choose where it applies: crosshair tagging, the Deepwood Staff bolt, and the Soulstealer Staff soul. Only affects your own targeting." },
    gt_prio_special_deepwood = { en = "[untested] Deepwood Staff" },
    gt_prio_special_deepwood_tooltip = { en = "Its seeking bolt prefers a Special in your aim over the nearest enemy to your crosshair, falling back to normal aim when no Special is in view. Affects only you." },
    gt_prio_special_soulstealer = { en = "[untested] Soulstealer Staff" },
    gt_prio_special_soulstealer_tooltip = { en = "Its homing soul locks onto a Special in your aim before a closer non-Special. Affects only you." },
    gt_prio_special_tag = { en = "[working] Tagging" },
    gt_prio_special_tag_tooltip = { en = "When you tag an enemy, prefer a Special along your aim even if an elite or a pickup is in the way. Affects only you." },

    -- ============================================================
    -- Host-Side Lobby Controls (absorbed from lobby_tweaker 2026-05-25;
    -- lt v0.1.7-dev). Keys + tooltips renamed lt_* / bare-form -> gt_lobby_*.
    -- ============================================================
    gt_lobby_controls_group = { en = "[working] Host-Side Lobby Controls" },

    -- Modded Lobby Manifest -- nested collapsible; also holds Message of the Day.
    gt_lobby_manifest_group = { en = "[working] Modded Lobby Manifest" },
    gt_lobby_manifest_broadcast_enabled = { en = "[untested] Broadcast my mod list (as host)" },
    gt_lobby_manifest_broadcast_enabled_tooltip = { en = "Lets players whose join fails see which mods they are missing, by sharing your mod list with the lobby as host. Does not affect players who join successfully." },

    -- Message of the Day (master toggle + nested send/greet options).
    gt_lobby_motd_enabled = { en = "[untested] Send MOTD to joiners" },
    gt_lobby_motd_enabled_tooltip = { en = "When someone joins your party, send them your message of the day. Works only when you are the host, and joiners without this mod will not see it." },
    gt_lobby_motd_once_per_peer_per_session = { en = "[untested] Only greet each peer once per session" },
    gt_lobby_motd_once_per_peer_per_session_tooltip = { en = "On by default: greet each player at most once while you are hosting. Turn it off to greet them again every time they join, which is handy when someone reconnects." },
    gt_lobby_motd_send_chat = { en = "[untested] Send via chat" },
    gt_lobby_motd_send_chat_tooltip = { en = "The message arrives in the receiver's chat window, one line per break." },
    gt_lobby_motd_send_popup = { en = "[untested] Send via popup" },
    gt_lobby_motd_send_popup_tooltip = { en = "The message pops up on the receiver's screen with an OK button to dismiss it." },

    gt_lobby_manifest_failnotify_enabled = { en = "[untested] Show missing mods when a join fails" },
    gt_lobby_manifest_failnotify_enabled_tooltip = { en = "When you fail to join a modded host over a mod mismatch, replace the generic error with a list of the mods you are missing plus a button to open the Workshop. Falls back to the normal error if the host is not sharing its mod list." },

    -- Loose lobby options (A->Z by display label).
    allow_duplicate_careers = { en = "[working] Allow Duplicate Careers" },
    allow_duplicate_careers_tooltip = { en = "More than one player can pick the same hero and career in the same lobby." },

    gt_lobby_kick_idle_enabled = { en = "[untested] Auto-kick idle players in keep" },
    gt_lobby_kick_idle_enabled_tooltip = { en = "While in the keep, warn and then kick players who stand still too long (the host and bots are never affected). Works only when you are the host, and you can exempt specific players." },
    gt_lobby_kick_idle_threshold_minutes = { en = "[untested] Idle threshold (minutes)" },
    gt_lobby_kick_idle_threshold_minutes_tooltip = { en = "How long a player can stand still in the keep before being kicked, from 1 to 60 minutes." },
    gt_lobby_ki_warn_seconds = { en = "[untested] Warning lead time (seconds)" },
    gt_lobby_ki_warn_seconds_tooltip = { en = "How many seconds before the kick the warning message appears, from 10 to 180." },

    gt_solo_auto_restart_on_wipe = { en = "[untested] Auto-restart mission on team wipe" },
    gt_solo_auto_restart_on_wipe_tooltip = { en = "When the whole team goes down, restart the mission in place instead of returning to the keep, which is handy for solo practice and speedrun resets. Works only when you are the host." },

    gt_auto_ready_on_vote_pass = { en = "[working] Auto-start On Vote Pass" },
    gt_auto_ready_on_vote_pass_tooltip = { en = "When a mission vote passes, skip the bridge countdown and start immediately. Host only; leave it off if you enjoy the bridge sequence." },

    gt_lobby_session_ignore_enabled = { en = "[untested] Enable ignore list" },
    gt_lobby_session_ignore_enabled_tooltip = { en = "Players on your ignore list are turned away the moment they try to join, either for this session only or permanently. Works only when you are the host." },

    gt_lobby_slot_reservations_enabled = { en = "[untested] Enable slot reservations" },
    gt_lobby_slot_reservations_enabled_tooltip = { en = "Named players get lobby slots held for them by their Steam ID; other joiners are turned away while a held slot still waits for its player. Works only when you are the host." },

    gt_ready_up_hotkey = { en = "[working] Ready Up (Skip Countdown)" },
    gt_ready_up_hotkey_tooltip = { en = "Starts the mission right away, cutting straight past the Bridge of Shadows countdown. Host only." },

    gt_unlock_all_weaves = { en = "[working] Unlock All Ranked Weaves" },
    gt_unlock_all_weaves_tooltip = { en = "Every ranked weave in the Winds of Magic ladder becomes playable without grinding up the ladder first. You still need the Winds of Magic DLC, and this only affects your own game." },

    -- ============================================================
    -- Info -- on-screen text readouts / warnings.
    -- ============================================================
    gt_info_group = { en = "[working] Info" },
    gt_solo_assassin_text_warning = { en = "[untested] Assassin spawn warning (on-screen text)" },
    gt_solo_assassin_text_warning_tooltip = { en = "Flashes an 'ASS!' warning with a live count on screen whenever a Gutter Runner is about to spawn. Normal area names are hidden while this or the packmaster warning is on." },
    gt_solo_boss_path_progress = { en = "[untested] Boss path progress readout (needs StreamingInfo)" },
    gt_solo_boss_path_progress_tooltip = { en = "Feeds the boss main-path distance to the StreamingInfo overlay mod. Does nothing unless StreamingInfo is installed." },
    gt_solo_packmaster_text_warning = { en = "[untested] Packmaster spawn warning (on-screen text)" },
    gt_solo_packmaster_text_warning_tooltip = { en = "Flashes a 'PACK!' warning with a live count on screen whenever a Packmaster is about to spawn. Normal area names are hidden while this or the assassin warning is on." },

    -- ============================================================
    -- Visuals and Audio (was "Solo & QoL"; ported from True Solo QoL Tweaks;
    -- _gt_solo_qol.lua). setting_ids preserved for user state continuity.
    -- ============================================================
    gt_solo_group = { en = "[working] Visuals and Audio" },
    gt_solo_assassin_hero_vo = { en = "[untested] Assassin/Packmaster hero voice callout" },
    gt_solo_assassin_hero_vo_tooltip = { en = "Even in solo play, your hero calls out the instant a Gutter Runner or Packmaster spawns." },
    gt_solo_disable_downed_fx = { en = "[untested] Disable downed screen effects" },
    gt_solo_disable_downed_fx_tooltip = { en = "Removes the fullscreen desaturation and vignette overlay shown while you are knocked down and while wounded (bleeding out). Visual only, affects only your own game." },
    gt_solo_disable_fog = { en = "[untested] Disable fog" },
    gt_solo_disable_fog_tooltip = { en = "The level's fog stops rendering, giving a cleaner line of sight. Purely visual and affects only your own game." },
    gt_solo_disable_mutator_explosions = { en = "[untested] Disable mutator death explosions" },
    gt_solo_disable_mutator_explosions_tooltip = { en = "Removes the purple burst that enemies leave behind when they die under the Explosive mutator or boon. Works whether you host or join, and only changes what you see." },
    gt_solo_disable_sun_shadows = { en = "[untested] Disable sun shadows" },
    gt_solo_disable_sun_shadows_tooltip = { en = "Sun shadows stop rendering, for clearer visibility and a small performance gain. Purely visual and affects only your own game." },
    gt_solo_disable_ult_fx = { en = "[untested] [Issue 255] Disable ult screen effects" },
    gt_solo_disable_ult_fx_tooltip = { en = "Removes the fullscreen color and distortion overlay and the swirly screen effects shown when a career ability is used: Slayer, Zealot, Ranger, Shade, Huntsman, and Sister of the Thorn radiance. Visual only, affects only your own game." },
    gt_solo_disable_ult_vo = { en = "[untested] Disable your ult voice line" },
    gt_solo_disable_ult_vo_tooltip = { en = "Silences your own character's voice line when you use your career ultimate." },
    gt_solo_draw_boss_spheres = { en = "[untested] Draw boss-event spheres" },
    gt_solo_draw_boss_spheres_tooltip = { en = "Red wireframe markers appear at the boss and main-path event spots on the level, as a debug or streamer aid." },
    gt_more_corpses_count = { en = "[untested] Max Ragdolls" },
    gt_more_corpses_count_tooltip = { en = "How many ragdolls and corpses stay on the ground before the game starts removing them. Vanilla is 24; raise it up to 300 for a more cinematic battlefield, though high values can strain slower machines." },
    -- Melee Attack Warning (Issue #308). Client-side, cosmetic only.
    gt_melee_warning = { en = "[untested] Melee Attack Warning" },
    gt_melee_warning_tooltip = { en = "Fires a local cue when a nearby enemy starts a melee swing at you, so you can dodge a moment earlier under lag. Cosmetic only; hits are unchanged." },
    gt_melee_warning_audio = { en = "[untested] Warning sound" },
    gt_melee_warning_audio_tooltip = { en = "Plays a short ping the moment a swing is detected." },
    gt_melee_warning_visual = { en = "[untested] Warning screen flash" },
    gt_melee_warning_visual_tooltip = { en = "Pulses a red screen-edge glow the moment a swing is detected." },
    gt_melee_warning_lead = { en = "[untested] Warning lead time" },
    gt_melee_warning_lead_tooltip = { en = "How far ahead of the predicted hit the cue fires. Higher values warn earlier; match it to your ping." },
    gt_melee_warning_lead_0 = { en = "0 ms" },
    gt_melee_warning_lead_50 = { en = "50 ms" },
    gt_melee_warning_lead_100 = { en = "100 ms" },
    gt_melee_warning_lead_150 = { en = "150 ms" },
    gt_melee_warning_lead_200 = { en = "200 ms" },
    gt_melee_warning_lead_250 = { en = "250 ms" },
    gt_melee_warning_scope = { en = "[untested] Warn for" },
    gt_melee_warning_scope_tooltip = { en = "Elites only covers stormvermin, maulers, chaos warriors, bestigors, plague monks, and berserkers. All melee flags every melee enemy." },
    gt_melee_warning_scope_elites = { en = "Elites only" },
    gt_melee_warning_scope_all = { en = "All melee enemies" },
    -- Smooth Health-Bar Damage (Issue #308). Presentation only.
    gt_hp_smoothing = { en = "[untested] Smooth Health-Bar Damage" },
    gt_hp_smoothing_tooltip = { en = "Eases your own health bar down over a short window instead of snapping, so a lag spike of damage reads more smoothly. Heals and knockdowns still snap." },
    gt_hp_smoothing_ms = { en = "[untested] Smoothing window" },
    gt_hp_smoothing_ms_tooltip = { en = "How long the bar takes to slide down to a new lower value." },
    gt_hp_smoothing_ms_100 = { en = "100 ms" },
    gt_hp_smoothing_ms_150 = { en = "150 ms" },
    gt_hp_smoothing_ms_200 = { en = "200 ms" },
    gt_hp_smoothing_ms_250 = { en = "250 ms" },

    -- ============================================================
    -- Code-referenced strings with no widget (rendered by the mod at runtime).
    -- Kept even though they don't map 1:1 to a menu entry.
    -- ============================================================
    -- MOTD popup title + the MOTD text buffer. MOTD text is set via chat
    -- (/lobby_motd_set <text>) and read with mod:get, not localized -- so the
    -- gt_lobby_motd_text label + tooltip below are SUSPECTED ORPHANS left over
    -- from the removed text-input widget (kept per audit policy; not deleted).
    gt_lobby_motd_popup_topic = { en = "Message of the Day" },
    gt_lobby_motd_text = { en = "MOTD text (use \\n for line breaks)" },
    gt_lobby_motd_text_tooltip = { en = "The message players receive when they join. Type a backslash and n where you want a line break." },

    -- Failed-join manifest reveal (rendered text; _gt_lobby_failed_join_reveal.lua).
    gt_lobby_failnotify_title              = { en = "Cannot join: modded host" },
    gt_lobby_failnotify_required_header    = { en = "You are missing %%d mods required by the host:" },
    gt_lobby_failnotify_version_header     = { en = "%%d mods have a version mismatch:" },
    gt_lobby_failnotify_cosmetic_footer    = { en = "Host also has %%d cosmetic mods you don't (gameplay unaffected)." },
    gt_lobby_failnotify_button_workshop    = { en = "Open Workshop" },
    gt_lobby_failnotify_button_cancel      = { en = "Close" },
}
