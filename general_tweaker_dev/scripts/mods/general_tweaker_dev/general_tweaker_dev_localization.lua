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
    gt_bot_options_group = { en = "Bots" },

    -- Loose bot options (A->Z by display label).
    gt_ai_afk_takeover = { en = "AFK Bot Takeover" },
    gt_ai_afk_takeover_tooltip = { en = "After 20 seconds without input, a temporary bot drives your hero while you observe; any input requests your native respawn. A normal bot yields its slot if needed. Supports Adventure, Chaos Wastes, and Weaves, but not a four-human party, Versus, or the keep." },

    gt_bots_in_keep = { en = "Allow Bots in Keep" },
    gt_bots_in_keep_tooltip = { en = "While in the keep, allows bots so you can preview loadouts and have a full lobby. Works only when you are the host, and the bots are removed when you turn it off." },

    gt_bot_guard_break_msg = { en = "Announce when a bot's guard breaks (Replicant)" },
    gt_bot_guard_break_msg_tooltip = { en = "Posts a chat message whenever a bot teammate's block is broken. Choose who sees it below; works only when you are the host." },
    gt_bot_guard_break_msg_none   = { en = "Off" },
    gt_bot_guard_break_msg_host   = { en = "Host only (just me)" },
    gt_bot_guard_break_msg_global = { en = "Host + clients (everyone)" },
    -- The chat line itself when a bot's guard breaks (code-referenced).
    gt_bot_guard_break_chat = { en = "A bot's guard was broken!" },

    gt_bot_command_wheel = { en = "Bot command wheel" },
    gt_bot_command_wheel_tooltip = { en = "Adds Attack Now, Group Up, Cover Me, and Wait as a second page of the mission social wheel for the host. Attack Now prioritizes the last enemy you pinged for 10 seconds; Group Up and Cover Me temporarily gather bots around you; Wait parks the nearest bot around the aimed point for 30 seconds. Normal safety, combat, and rescue behavior still takes priority where required." },

    -- Bot Behavior Improvements master toggle + nested sub-toggles (#297,
    -- v0.2.182-dev). The master gates everything; each fix below is now
    -- individually toggleable while the master is on. Checkbox ids reuse the
    -- pre-bundle setting ids (retired v0.2.128-dev); the delay sliders replace
    -- the formerly hard-coded 3s / 4s. Children in FEATURE order (matches the
    -- data file), not A->Z. Tags: where the CHANGELOG records an
    -- in-game confirmation of the wrapped fix, otherwise; the
    -- greedy-pickup item is brand-new (#297 item 8).
    gt_bot_behavior_improvements = { en = "Bot Behavior Improvements" },
    gt_bot_behavior_improvements_tooltip = { en = "Master switch for the bot fixes listed underneath; while it is on, each fix can be toggled individually below. Covers Necromancer potion handoff, keeping the mission alive while a bot still stands, ledge recovery, ladder unstick, instant and greedy item pickup, smarter self-healing, revive and rescue priority, reviving during the Ironbreaker ult, curated AOE immunity, and short-lived gas/warpfire resistance. Works only when you are the host." },

    gt_bot_necro_potion_handoff = { en = "Necromancer bots hand off potions" },
    gt_bot_necro_potion_handoff_tooltip = { en = "A Necromancer bot brings a real potion forward over its skull item, so it can drink it or pass it to a teammate, which the skull otherwise blocks." },

    gt_bot_mission_fail_prevention = { en = "Keep the mission going while a bot lives" },
    gt_bot_mission_fail_prevention_tooltip = { en = "Normally the run ends when every human is down even if a bot still stands; with this on, the mission only fails when no teammate, human or bot, remains." },

    gt_bot_ledge_pullup = { en = "Bots pull themselves up from ledges" },
    gt_bot_ledge_pullup_tooltip = { en = "A bot left hanging from a ledge climbs back up on its own after the delay below instead of waiting for a rescue." },

    gt_bot_ledge_pullup_delay = { en = "Ledge pull-up delay (seconds)" },
    gt_bot_ledge_pullup_delay_tooltip = { en = "How many seconds a bot hangs from a ledge before climbing back up; 0 makes the recovery instant." },

    gt_bot_ladder_unstick = { en = "Bots free themselves from ladders" },
    gt_bot_ladder_unstick_tooltip = { en = "A bot wedged on a ladder teleports to a teammate after the delay below instead of staying stuck there." },

    gt_bot_ladder_unstick_delay = { en = "Ladder unstick delay (seconds)" },
    gt_bot_ladder_unstick_delay_tooltip = { en = "How many seconds a bot may sit on a ladder before it teleports to a teammate. Values below 3 would trigger during normal climbs, so 3 is the minimum." },

    gt_bot_instant_pickup = { en = "Bots instantly grab targeted items" },
    gt_bot_instant_pickup_tooltip = { en = "The pickup a bot is going for, including pinged items, is grabbed from where the bot stands instead of it walking all the way over." },

    gt_bot_greedy_pickup = { en = "Bots collect items players leave behind" },
    gt_bot_greedy_pickup_tooltip = { en = "Normally bots refuse to take potions, bombs, and healing while a nearby player has a free slot for them; with this on they collect such items anyway, then carry them and hand them over when asked or needed." },

    gt_bot_smart_ale = { en = "Bots drink surplus Ranger ale" },
    gt_bot_smart_ale_tooltip = { en = "Lets bots pick up and drink Bardin's Survival Ale only when every active teammate already has all three ale stacks and strictly more than half of the refreshed duration remains. Otherwise ale stays reserved for human players. Works only when you are the host." },

    -- #468: control WHEN a bot spends a heal on ITSELF (self-use timing only).
    -- Making a bot walk up and heal a teammate is the separate #523 heal-allies
    -- option below (which drives the game's own, dormant, heal-other bot action).
    gt_bot_smart_self_heal = { en = "Smarter bot self-healing" },
    gt_bot_smart_self_heal_tooltip = { en = "Decide for yourself when a bot spends healing on itself instead of the game's fixed rules, which drink a full Draught of Healing at 40 percent health and burn Medical Supplies at 20 percent even when a player could use them better. With this on, the three settings below take over. This only changes self-use timing; to make bots actually walk up and heal a teammate use the heal-allies option below, and carrying or handing items to players is the greedy-pickup option above. Works only when you are the host." },

    gt_bot_self_heal_pct = { en = "Bot self-heal health threshold (%%)" },
    gt_bot_self_heal_pct_tooltip = { en = "A bot only heals itself once its health drops to this percentage or lower. Lower values make bots hold their healing longer (less waste); higher values make them heal sooner. Applies to both draughts and medical supplies, replacing the game's fixed 40 and 20 percent triggers." },

    gt_bot_reserve_kits_for_players = { en = "Bots reserve medical supplies for players" },
    gt_bot_reserve_kits_for_players_tooltip = { en = "Medical Supplies can heal a hurt teammate, so a bot holds onto them instead of using them on itself, unless it is wounded (grey health) or spare healing is lying around anyway. Draughts of Healing, which only heal the drinker, are not affected." },

    gt_bot_ignore_surplus_selfuse = { en = "Bots don't top themselves off on spare healing" },
    gt_bot_ignore_surplus_selfuse_tooltip = { en = "The game tells a bot to drink its healing when more healing items are lying around than players to use them, even at high health. With this on a bot ignores that prompt and keeps its healing until it actually needs it." },

    gt_bot_heal_allies = { en = "Bots heal hurt allies with medical supplies" },
    gt_bot_heal_allies_tooltip = { en = "When a bot is carrying Medical Supplies and no one needs reviving, it walks up to the most hurt eligible teammate and heals them, wounded (grey health) players first. It only heals when the coast is clear (no enemies right next to the target), and only humans, never other bots. Pairs with the reserve option above, which stops bots from spending the kit on themselves. Works only when you are the host." },

    gt_bot_heal_allies_pct = { en = "Heal allies at or below health (%%)" },
    gt_bot_heal_allies_pct_tooltip = { en = "A non-wounded teammate is eligible once their permanent (white) health reaches this percentage or lower. Set 0 to prevent bots from using kits on non-wounded allies. The wounded threshold below is separate." },

    gt_bot_heal_wounded_allies_pct = { en = "Heal wounded allies at or below health (%%)" },
    gt_bot_heal_wounded_allies_pct_tooltip = { en = "A wounded (grey-health) teammate is eligible once their permanent health reaches this percentage or lower. The default 100 makes every wounded teammate eligible; lower it if bots should wait." },

    gt_bot_heal_allies_exclude_zealot = { en = "Do not heal non-wounded Zealots" },
    gt_bot_heal_allies_exclude_zealot_tooltip = { en = "Keep a non-wounded Zealot's permanent health low so the player can build temporary health. Wounded Zealots are controlled separately below." },

    gt_bot_heal_wounded_zealot = { en = "Heal Zealot when wounded" },
    gt_bot_heal_wounded_zealot_tooltip = { en = "Allow bots to spend Medical Supplies on a wounded Zealot when the wounded-health threshold is met. On by default because another knockdown would otherwise kill them." },

    gt_bot_aid_priority = { en = "Bots prioritize reviving and rescuing" },
    gt_bot_aid_priority_tooltip = { en = "Downed, hooked, and ledge-hanging allies always outrank following and other chores, so a bot commits to the revive or rescue and walks the whole way there." },

    gt_bot_ignore_backward_gate = { en = "Bots go back for stragglers and past no-return points" },
    gt_bot_ignore_backward_gate_tooltip = { en = "The game normally refuses to teleport or path a bot backward along the level, so a player who drops behind it is left alone until they catch up, and a bot shoved past a point of no return (over a ledge into the next area) stays stuck for the rest of the run. With this on that block is lifted: a lagging follow target still pulls the bot back, a teammate who goes down behind the bot is retried right away, and a bot that cannot walk back to the team teleports to regroup once it is genuinely stuck, and can do so again later in the run. Reviving and rescuing keep priority over merely catching up." },

    gt_bot_ironbreaker_revive_in_ult = { en = "Ironbreaker bots revive during their ult" },
    gt_bot_ironbreaker_revive_in_ult_tooltip = { en = "The career skill no longer parks the bot in a blocking stance for its whole duration; the bot breaks off to revive or rescue an ally while the damage-reduction buff keeps running." },

    -- #469: bots ignore a curated set of hazard / mutator AOE they cannot path
    -- around. Host-side, bots only, humans never affected.
    gt_bot_aoe_immunity = { en = "Bots ignore mutator and hazard AOE damage" },
    gt_bot_aoe_immunity_tooltip = { en = "Bots take no damage from a hand-picked set of area hazards they cannot reliably path around: Weaves and Twitch lightning strikes, the Chaos Wastes Khorne skull curse and Tzeentch bolt-of-change curse, and oil-barrel ground fire. Only bots are affected, never human players, and only while you are the host. Boss slams, warpfire, gas, and thrown bombs are left alone on purpose so bots still react to them." },

    gt_bot_hazard_resistance = { en = "Bots build gas and warpfire resistance" },
    gt_bot_hazard_resistance_tooltip = { en = "When a host-owned bot takes gas or warpfire damage, it gains one matching resistance stack for 2 seconds. Each active stack reduces subsequent damage of that type by 20%%, up to 5 stacks. Gas and warpfire stacks are independent; human players and other damage types are unchanged." },

    -- issue 448 (FIX 11): downed bot must not project the Morr's Protection aura.
    gt_bot_no_downed_morrs_grant = { en = "Downed bots don't grant Morr's Protection" },
    gt_bot_no_downed_morrs_grant_tooltip = { en = "The Chaos Wastes boon Morr's Protection makes downed allies near the carrier invulnerable, and the game keeps that aura running even while the carrier is downed itself. Two bots carrying it that go down near each other protect each other forever: they can't be finished, can't get up, and the run soft-locks. With this on, a bot stops granting the aura while it is knocked down and resumes the moment it is back up. Human carriers and standing bots are untouched. Host-side only." },

    -- Bot follow mode dropdown (v0.2.152-dev) -- consolidates the previous
    -- gt_bot_split_among_players + gt_bot_follow_host checkboxes into one
    -- tri-state setting.
    gt_bot_follow_mode = { en = "Bot follow mode" },
    gt_bot_follow_mode_tooltip = { en = "Three modes: Default (normal behavior), Follow Host (all bots stick to the host), or Split (one bot per human, host first). Bots still break off to revive or rescue an ally, and this only works when you are the host." },
    gt_bot_follow_mode_default     = { en = "Default" },
    gt_bot_follow_mode_follow_host = { en = "Follow Host" },
    gt_bot_follow_mode_split       = { en = "Split" },

    ai_takeover_enabled = { en = "Bot Takeover" },
    ai_takeover_enabled_tooltip = { en = "Let a temporary bot drive your hero while your player identity and party slot remain reserved; turn this off to return through the native respawn flow. A normal bot yields its slot if needed. Supports Adventure, Chaos Wastes, and Weaves, but not a four-human party." },

    -- Replicant Bots ports (v0.2.131-dev). All host-side, default OFF, ported
    -- from the "Replicant Bots - Different Bots Experimental Branch" mod.
    gt_bot_drink_potions_in_danger = { en = "Bots drink potions when in danger (Replicant)" },
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

    gt_bot_rescue_awaiting = { en = "Bots rescue allies awaiting respawn" },
    gt_bot_rescue_awaiting_tooltip = { en = "Vanilla bots ignore a teammate waiting to be rescued at a respawn point; this sends them to go free that ally. The nested options control how far bots may leave the team for a rescue. Works only when you are the host." },

    gt_bot_rescue_awaiting_ignore_leash = { en = "Ignore follow leash for awaiting rescues" },
    gt_bot_rescue_awaiting_ignore_leash_tooltip = { en = "On by default. Bots may cross the mission to rescue an awaiting teammate, matching this feature's existing behavior. Turn this off to apply either the normal follow leash or the custom rescue range below." },

    gt_bot_rescue_awaiting_custom_range = { en = "Use a custom awaiting-rescue range" },
    gt_bot_rescue_awaiting_custom_range_tooltip = { en = "When Ignore follow leash is off, use the dedicated range below instead of the current Follow snap-back distance. Off by default." },

    gt_bot_rescue_awaiting_range_m = { en = "Custom awaiting-rescue range (meters)" },
    gt_bot_rescue_awaiting_range_m_tooltip = { en = "Maximum straight-line distance at which a bot may select an awaiting-rescue teammate when the custom range is enabled. Defaults to 40 meters and can be set from 10 to 100." },

    gt_no_bots = { en = "Disable Bots" },
    gt_no_bots_tooltip = { en = "Keeps bots from filling empty party slots and instantly removes any already present, for true solo runs. Works only when you are the host and stays in effect across missions until you turn it off." },

    gt_keep_dummy_no_collision = { en = "No Player Collision with Keep Dummies" },
    gt_keep_dummy_no_collision_tooltip = { en = "Lets your character walk through training dummies while you are in the keep. Dummies remain visible, targetable, and damageable. Local to your player and off by default." },

    gt_bot_fast_reactions = { en = "Faster bot reactions (Replicant)" },
    gt_bot_fast_reactions_tooltip = { en = "Cuts bot reaction time to threats down to a fraction of a second. Works only when you are the host." },

    -- (gt_bot_follow_distance_enabled removed 2026-06-30 -- the slider below is now the sole control; 40 = off.)
    gt_bot_follow_distance_m = { en = "Follow snap-back distance (meters)" },
    gt_bot_follow_distance_m_tooltip = { en = "How far a bot may fall behind before it snaps back to you; 40 (the maximum) does nothing, and lower values keep bots closer, with about 15 to 20 the practical limit. Works only when you are the host." },

    gt_improved_bot_combat = { en = "Improved Bot Combat" },
    gt_improved_bot_combat_tooltip = { en = "Bot teammates make smarter attack choices, ping the elite hitting them, stop chasing distant specials, ignore far-off gunners, do not over-focus bosses, and time abilities better for several careers. Works only when you are the host." },
    gt_ibc_smarter_attacks = { en = "Smarter attack choices" },
    gt_ibc_smarter_attacks_tooltip = { en = "Prefer faster single-target attacks when safe and wider or penetrating attacks against crowds and armour." },
    gt_ibc_ping_attackers = { en = "Ping attacking elites" },
    gt_ibc_ping_attackers_tooltip = { en = "Bots ping a visible elite that is actively targeting them, with a bounded cooldown." },
    gt_ibc_limit_special_chase = { en = "Limit special chasing" },
    gt_ibc_limit_special_chase_tooltip = { en = "Stops bots committing to paths toward enemies beyond the configured chase distance." },
    gt_ibc_special_chase_distance = { en = "Special chase distance (meters)" },
    gt_ibc_special_chase_distance_tooltip = { en = "Maximum distance at which improved combat permits a bot to commit to chasing an enemy. The previous bundled value was approximately 7.1 meters." },
    gt_ibc_ignore_distant_gunners = { en = "Ignore distant gunners" },
    gt_ibc_ignore_distant_gunners_tooltip = { en = "Only makes bots take cover when a ranged attacker and its target are within the configured distance." },
    gt_ibc_gunner_cover_distance = { en = "Gunner cover distance (meters)" },
    gt_ibc_gunner_cover_distance_tooltip = { en = "Maximum attacker-to-target distance for the improved line-of-fire cover response. The previous bundled value was approximately 11.8 meters." },
    gt_ibc_limit_boss_focus = { en = "Limit boss over-focus" },
    gt_ibc_limit_boss_focus_tooltip = { en = "Keeps non-boss urgent targets ahead of monsters and only adds a nearby boss when the bot is not occupied by a crowd." },
    gt_ibc_boss_engage_distance = { en = "Boss engage distance (meters)" },
    gt_ibc_boss_engage_distance_tooltip = { en = "Maximum distance at which improved combat adds a boss as an urgent target. The previous bundled value was 15 meters." },
    gt_ibc_ability_timing = { en = "Smarter career ability timing" },
    gt_ibc_ability_timing_tooltip = { en = "Uses the existing improved timing heuristics for Mercenary, Huntsman, Handmaiden, Shade, Witch Hunter Captain, and Unchained bots." },

    -- ============================================================
    -- Cheats and Debug
    -- ============================================================
    cheats_debug_group = { en = "Cheats and Debug" },

    -- Loose cheat primitives (A->Z).
    clear_enemies_hotkey = { en = "Clear Enemy Spawns" },
    clear_enemies_hotkey_tooltip = { en = "Every enemy currently alive vanishes at once, except any tied to mission objectives so nothing breaks. Works only when you are the host." },

    disable_enemy_spawns = { en = "Disable Enemy Spawns" },
    disable_enemy_spawns_tooltip = { en = "No new enemies appear at all: hordes, specials, bosses, patrols, and ambient critters. Enemies already present are left alone, and turning it off resumes normal spawning." },

    godmode_enabled = { en = "Godmode" },
    godmode_enabled_tooltip = { en = "Makes you invincible: you take no damage, cannot be grabbed or pinned by disablers, and enemies stop noticing you. Enemy hits no longer drain your stamina or break your block; your own pushes and dodges still cost stamina. Optional child toggles can make your strikes deal 9999 damage or give you unlimited ammo while Godmode is active. Your third-person body fades out while it is on; your own view stays normal." },
    gt_godmode_strike_damage = { en = "9999 Damage Per Strike" },
    gt_godmode_strike_damage_tooltip = { en = "While Godmode is active, every damaging hit you deal to an enemy is raised to 9999 damage. This follows your Godmode state when you are a client, so the host applies it authoritatively." },
    gt_godmode_unlimited_ammo = { en = "Unlimited Ammo" },
    gt_godmode_unlimited_ammo_tooltip = { en = "While Godmode is active, your ranged ammo and overcharge are not consumed. This affects only you and does not change the separate /infinite_ammo cheat." },

    noclip_enabled = { en = "Noclip" },
    noclip_enabled_tooltip = { en = "Fly freely through walls and terrain: WASD moves you where you look, Space and Ctrl go up and down, and holding Shift speeds you up. Turning it off while airborne drops you to the ground." },
    noclip_speed = { en = "Noclip Base Speed" },
    noclip_speed_tooltip = { en = "How fast you fly, in metres per second. The default of about 15 is roughly four times normal walking speed." },
    noclip_boost_multiplier = { en = "Noclip Shift-Boost Multiplier" },
    noclip_boost_multiplier_tooltip = { en = "How much holding Left Shift multiplies your flight speed. At 3.0 you fly about three times faster than the base speed." },
    noclip_hotkey = { en = "Noclip Toggle" },
    noclip_hotkey_tooltip = { en = "Remembers your state, so one press drops you into noclip flight and the next returns you to normal movement." },

    -- ---- Buffs & Stats ----
    buffs_group = { en = "Buffs & Stats" },
    base_crit_chance = { en = "Base Crit Chance (%%)" },
    base_crit_chance_tooltip = { en = "Most careers start at 5%%; this raises or lowers that rate for your current career. It resets to the career's normal value when you switch careers and after a game restart." },
    gt_fall_damage_enabled = { en = "Fall damage multiplier" },
    gt_fall_damage_enabled_tooltip = { en = "When off, fall damage is normal; when on, the multiplier below takes effect. The host's setting applies to everyone in the lobby." },
    gt_fall_damage_mult = { en = "Fall damage multiplier (1 = normal, 0 = none, 5 = 5x)" },
    gt_fall_damage_mult_tooltip = { en = "1.0 is normal, 0 removes fall damage entirely, and up to 5.0 makes tall falls five times as deadly. Only used while the fall damage toggle above is on." },
    movement_speed = { en = "Movement Speed (m/s)" },
    movement_speed_tooltip = { en = "The default is 4 metres per second; higher values make everyone move faster. Resets after a game restart, and in a lobby the host's value affects everyone." },

    -- ---- Level Control ----
    level_control_group = { en = "Level Control" },
    fail_level_hotkey = { en = "Fail Level" },
    fail_level_hotkey_tooltip = { en = "Sends the whole team straight to the defeat screen, ending the run on the spot. Available during a mission only, not in the keep." },
    fix_sound_hotkey = { en = "Fix Vortex Sound" },
    fix_sound_hotkey_tooltip = { en = "Silences the looping wind or storm effect that can get stuck after a mid-storm mission restart. Works during a mission only." },
    kill_bots_hotkey = { en = "Kill Bots" },
    kill_bots_hotkey_tooltip = { en = "On the official realm this is only allowed before the round starts; the modded realm has no restriction. Every bot in your party goes down at once." },
    down_bots_hotkey = { en = "Down Bots (Morr's test)" },
    down_bots_hotkey_tooltip = { en = "Host only. Forces every standing bot into the downed bleedout state at once, the same way lethal damage would, but without killing them. Use it to test the Morr's Protection soft-lock fix: give two bots the Morr's Protection boon, down them close together, and they should still bleed out instead of becoming permanently invulnerable. Does nothing in the keep." },
    restart_level_hotkey = { en = "Restart Level" },
    restart_level_hotkey_tooltip = { en = "Reloads the current mission from the beginning with the same team and difficulty. Does nothing in the keep." },
    die_hotkey = { en = "Suicide" },
    die_hotkey_tooltip = { en = "Your own character drops dead on the spot. Does nothing in the keep." },
    gt_bot_toggle_hotkey = { en = "Toggle Bots On/Off" },
    gt_bot_toggle_hotkey_tooltip = { en = "On the current level, bots either start spawning (including in the keep) or are removed mid-mission. Keep bots can occasionally cause a rare crash." },
    win_level_hotkey = { en = "Win Level" },
    win_level_hotkey_tooltip = { en = "Jumps straight to the end-of-mission victory screen and its rewards. Does nothing in the keep." },

    -- ---- Spawners ----
    -- Creature Spawner + Item Spawner (ported from Aussiemon's CreatureSpawner
    -- mod, Workshop ID 1395132559, MIT-licensed). gt_cs_* / gt_is_* namespaces.
    gt_spawners_group = { en = "Spawners" },

    gt_cs_group = { en = "Creature Spawner" },
    gt_cs_unit_list = { en = "Available Unit List" },
    gt_cs_unit_list_tooltip = { en = "Choose which set of enemies the cycle hotkeys move through: Regular, Dummy (practice targets), Misc (debug units), Special, Boss, or All. Changing this jumps the selection to the first enemy in the new set." },
    gt_cs_unit_list_regular = { en = "Regular" },
    gt_cs_unit_list_dummy   = { en = "Dummy" },
    gt_cs_unit_list_misc    = { en = "Misc" },
    gt_cs_unit_list_special = { en = "Special" },
    gt_cs_unit_list_boss    = { en = "Boss" },
    gt_cs_unit_list_all     = { en = "All" },

    gt_cs_spawn = { en = "Keybind: Spawn Creature" },
    gt_cs_spawn_tooltip = { en = "Drops the currently selected enemy at wherever your crosshair points, ignoring the usual spawn limits. As the host it spawns directly; as a client it asks the host to place it for you, so the host must also run this mod." },
    gt_cs_next = { en = "Keybind: Next Creature" },
    gt_cs_next_tooltip = { en = "Moves the selection forward by one in the active list, skipping any you cannot spawn such as DLC you do not own." },
    gt_cs_prev = { en = "Keybind: Previous Creature" },
    gt_cs_prev_tooltip = { en = "Moves the selection back by one in the active list." },
    gt_cs_destroy = { en = "Keybind: Destroy Spawned Creatures" },
    gt_cs_destroy_tooltip = { en = "Clears the whole level of enemies, not just the ones you placed. As the host it happens directly; as a client it asks the host to do it, so the host must also run this mod." },

    gt_cs_spawn_slot_1 = { en = "Keybind: Spawn Saved Slot 1" },
    gt_cs_spawn_slot_1_tooltip = { en = "Whatever enemy you saved to slot 1 appears at your crosshair." },
    gt_cs_spawn_slot_2 = { en = "Keybind: Spawn Saved Slot 2" },
    gt_cs_spawn_slot_2_tooltip = { en = "Whatever enemy you saved to slot 2 appears at your crosshair." },
    gt_cs_spawn_slot_3 = { en = "Keybind: Spawn Saved Slot 3" },
    gt_cs_spawn_slot_3_tooltip = { en = "Whatever enemy you saved to slot 3 appears at your crosshair." },

    gt_cs_mission_ai = { en = "Enable AI in Missions" },
    gt_cs_mission_ai_tooltip = { en = "On by default, so spawned enemies actually move and fight; with it off, they just stand still." },
    gt_cs_keep_ai = { en = "Enable AI in Keep" },
    gt_cs_keep_ai_tooltip = { en = "Off by default because it often crashes: most enemies need navigation data the keep lacks. Enabling it lets enemy AI run in the keep anyway." },

    gt_cs_grudge = { en = "Enable Grudge-Marked Modifiers" },
    gt_cs_grudge_tooltip = { en = "Newly spawned enemies can carry grudge-mark modifiers: Disabled for none, Random to roll a number of them (set by the slider below), or Manual to apply exactly the ones you check. There is a cap on active modifiers, so extras are skipped once it is reached." },
    gt_cs_grudge_disabled = { en = "Disabled" },
    gt_cs_grudge_random   = { en = "Random" },
    gt_cs_grudge_manual   = { en = "Manual" },
    gt_cs_grudge_random_modifier_count = { en = "Random Modifier Count" },
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
    gt_cs_grudge_warping         = { en = "Shadow-Step (Warping)" },
    gt_cs_grudge_warping_tooltip = { en = "Manual mode: the enemy teleports to a random spot near a player when hit." },
    gt_cs_grudge_intangible      = { en = "Illusionist (Intangible)" },
    gt_cs_grudge_intangible_tooltip = { en = "Manual mode: the enemy periodically summons three mirror images of itself." },
    gt_cs_grudge_unstaggerable   = { en = "Relentless (Unstaggerable)" },
    gt_cs_grudge_unstaggerable_tooltip = { en = "Manual mode: the enemy cannot be staggered." },
    gt_cs_grudge_raging          = { en = "Mighty (Raging)" },
    gt_cs_grudge_raging_tooltip  = { en = "Manual mode: the enemy periodically deals extra damage." },
    gt_cs_grudge_vampiric        = { en = "Vampiric" },
    gt_cs_grudge_vampiric_tooltip = { en = "Manual mode: the enemy heals from the damage it deals to players and bots." },
    gt_cs_grudge_ranged_immune   = { en = "Rampart (Ranged Immune)" },
    gt_cs_grudge_ranged_immune_tooltip = { en = "Manual mode: the enemy is immune to ranged damage and can only be killed in melee." },
    gt_cs_grudge_periodic_shield = { en = "Invincible (Periodic Shield)" },
    gt_cs_grudge_periodic_shield_tooltip = { en = "Manual mode: the enemy periodically becomes immune to all damage for a moment." },
    gt_cs_grudge_crippling       = { en = "Crippling" },
    gt_cs_grudge_crippling_tooltip = { en = "Manual mode: the enemy badly slows the movement and dodge of players it hits." },
    gt_cs_grudge_crushing        = { en = "Shield-Shatter (Crushing)" },
    gt_cs_grudge_crushing_tooltip = { en = "Manual mode: the enemy breaks blocks and briefly stops your stamina from recovering." },
    gt_cs_grudge_regenerating    = { en = "Regenerating" },
    gt_cs_grudge_regenerating_tooltip = { en = "Manual mode: the enemy regenerates health over time." },
    gt_cs_grudge_periodic_curse  = { en = "Cursed Aura (Periodic Curse)" },
    gt_cs_grudge_periodic_curse_tooltip = { en = "Manual mode: the enemy gives off a curse that drains the health of nearby players, and it stacks." },
    gt_cs_grudge_commander       = { en = "Commander" },
    gt_cs_grudge_commander_tooltip = { en = "Manual mode: the enemy buffs nearby allies." },
    gt_cs_grudge_frenzy          = { en = "Frenzy" },
    gt_cs_grudge_frenzy_tooltip  = { en = "Manual mode: the enemy attacks faster as it loses health." },

    gt_is_group = { en = "Item Spawner" },
    gt_is_next_hotkey = { en = "Next Pickup" },
    gt_is_next_hotkey_tooltip = { en = "Moves the selection forward by one through the pickups you can place. Drop it with the Spawn Selected Pickup key." },
    gt_is_prev_hotkey = { en = "Previous Pickup" },
    gt_is_prev_hotkey_tooltip = { en = "Moves the selection back by one through the pickups you can place." },
    gt_is_spawn_hotkey = { en = "Spawn Selected Pickup" },
    gt_is_spawn_hotkey_tooltip = { en = "The currently selected pickup appears at your feet. Training dummies can only be placed by the host." },

    -- ---- Time & Pause ----
    time_group = { en = "Time & Pause" },
    time_scale_value = { en = "Time Scale" },
    time_scale_value_tooltip = { en = "Ranges from 1 (slowest) to 24 (fastest), with 13 being normal game speed. Reapplied each mission but reset when the game restarts." },
    time_faster_hotkey = { en = "Time Faster" },
    time_faster_hotkey_tooltip = { en = "Bumps the Time Scale up by one step." },
    time_slower_hotkey = { en = "Time Slower" },
    time_slower_hotkey_tooltip = { en = "Bumps the Time Scale down by one step." },
    pause_value = { en = "Pause Speed" },
    pause_value_tooltip = { en = "The game speed used while paused, from 1 to 24. 1 is the slowest (closest to a real pause, though the interface keeps updating) and 13 is normal; the game has no true freeze." },
    pause_hotkey = { en = "Pause Toggle" },
    pause_hotkey_tooltip = { en = "Flips a host-only slow-motion pause on or off. Clients see it too, since game speed is controlled by the host." },

    -- ---- Ult ----
    ult_group = { en = "Ult" },
    ult_bot_cap_enabled = { en = "Cap Bot Ult Cooldown" },
    ult_bot_cap_enabled_tooltip = { en = "Same as the player cap, but for bots. Useful in solo play to see bots use their ults more often." },
    ult_bot_cap_value = { en = "Max Bot Ult Cooldown (seconds)" },
    ult_bot_cap_value_tooltip = { en = "The longest career ability cooldown allowed for bots, in seconds. Set to 0 so bots ult constantly." },
    ult_player_cap_enabled = { en = "Cap Player Ult Cooldown" },
    ult_player_cap_enabled_tooltip = { en = "Keeps every human player's career ability cooldown at or below the limit set below. Effectively a short, adjustable ult cooldown for players." },
    ult_player_cap_value = { en = "Max Player Ult Cooldown (seconds)" },
    ult_player_cap_value_tooltip = { en = "The longest career ability cooldown allowed for human players, in seconds. Set to 0 for an always-ready ult." },
    ult_reset_hotkey = { en = "Ult Reset" },
    ult_reset_hotkey_tooltip = { en = "Your career ability becomes ready to use again at once. A one-time effect; it does not keep the ability charged." },

    -- ============================================================
    -- Dev Tools (dev-stream only; the group is appended in the data file ONLY
    -- when mod == get_mod("gt".."_dev")). Bot behavior HUD + leash lines.
    -- ============================================================
    gt_devtools_group = { en = "Dev Tools" },

    gt_devtools_freeze_ai_hotkey = { en = "Freeze AI" },
    gt_devtools_freeze_ai_hotkey_tooltip = { en = "Halts every enemy in place so you can inspect positioning or set up a scenario: no enemy starts a new attack, move, target, or pathing decision, and new spawns stop while it is held. An enemy already moving settles at its last step; one already mid-attack may finish that swing before going still. Press again to resume. Works only when you are the host. Also available as the /freezeai chat command. Dev build only." },

    gt_devtools_bot_hud = { en = "Bot behavior HUD" },
    gt_devtools_bot_hud_tooltip = { en = "Draws a column per bot showing its current behavior-tree action, the teammate it follows, distance to that teammate and to you, whether it just teleported, its teleport tally, and the last twenty actions it entered. On-screen, host-only, dev build only." },

    gt_devtools_player_stat_hud = { en = "Player stat HUD" },
    gt_devtools_player_stat_hud_tooltip = { en = "Shows source-backed consumer-effective values where the engine path is deterministic, exact retained factors where downstream context is required, and explicit UNSUPPORTED reasons otherwise. Expanded mode exposes every row and contribution across navigable pages. Read-only, local-only, dev build only." },
    gt_player_stat_hud_mode = { en = "Player stat HUD detail" },
    gt_player_stat_hud_mode_tooltip = { en = "Compact shows eight high-value stat families. Expanded exposes all stat families, authoritative consumer names, and contribution stages across navigable pages." },
    gt_player_stat_hud_mode_compact = { en = "Compact" },
    gt_player_stat_hud_mode_expanded = { en = "Expanded" },
    gt_player_stat_hud_position = { en = "Player stat HUD position" },
    gt_player_stat_hud_position_tooltip = { en = "Places the player stat text in a bottom corner, away from the bot HUD and Godmode indicator." },
    gt_player_stat_hud_position_left = { en = "Bottom left" },
    gt_player_stat_hud_position_right = { en = "Bottom right" },
    gt_player_stat_hud_scale = { en = "Player stat HUD scale" },
    gt_player_stat_hud_scale_tooltip = { en = "Scales the player stat panel and text." },
    gt_player_stat_hud_scale_75 = { en = "75%%" },
    gt_player_stat_hud_scale_100 = { en = "100%%" },
    gt_player_stat_hud_scale_125 = { en = "125%%" },
    gt_player_stat_hud_title = { en = "PLAYER STATS - READ ONLY" },
    gt_player_stat_hud_compact_more = { en = "Expanded mode exposes all rows and contribution stages." },
    gt_player_stat_hud_page = { en = "page" },
    gt_player_stat_hud_page_help = { en = "/gt_stat_hud_page next|prev|#" },
    gt_player_stat_hud_stat_max_health = { en = "Health" },
    gt_player_stat_hud_stat_max_fatigue = { en = "Stamina" },
    gt_player_stat_hud_stat_movement_speed = { en = "Move speed" },
    gt_player_stat_hud_stat_activated_cooldown = { en = "Ability activation cooldown factor" },
    gt_player_stat_hud_stat_ability_remaining = { en = "Ability remaining" },
    gt_player_stat_hud_stat_ability_charges = { en = "Ability charges ready" },
    gt_player_stat_hud_stat_attack_speed_chain = { en = "Current chain/action time scale" },
    gt_player_stat_hud_stat_attack_speed_animation = { en = "Current animation time scale" },
    gt_player_stat_hud_stat_critical_strike_chance = { en = "Effective critical chance" },
    gt_player_stat_hud_stat_critical_settings_chance = { en = "Action-settings critical chance" },
    gt_player_stat_hud_stat_critical_strike_effectiveness = { en = "Critical-power factor" },
    gt_player_stat_hud_stat_effective_power = { en = "Effective hit power" },
    gt_player_stat_hud_stat_power_level = { en = "Generic power factor" },
    gt_player_stat_hud_stat_power_level_melee = { en = "Melee-power factor" },
    gt_player_stat_hud_stat_power_level_ranged = { en = "Ranged-power factor" },
    gt_player_stat_hud_stat_power_level_skaven = { en = "Skaven-power factor" },
    gt_player_stat_hud_stat_power_level_chaos = { en = "Chaos-power factor" },
    gt_player_stat_hud_stat_power_level_unarmoured = { en = "Infantry-power factor" },
    gt_player_stat_hud_stat_power_level_armoured = { en = "Armoured-power factor" },
    gt_player_stat_hud_stat_power_level_large = { en = "Monster-power factor" },
    gt_player_stat_hud_stat_power_level_frenzy = { en = "Berserker-power factor" },
    gt_player_stat_hud_stat_melee_damage = { en = "Melee-damage factor" },
    gt_player_stat_hud_stat_ranged_damage = { en = "Ranged-damage factor" },
    gt_player_stat_hud_stat_power_level_impact = { en = "Impact-power factor" },
    gt_player_stat_hud_stat_power_level_cleave = { en = "Melee-cleave factor" },
    gt_player_stat_hud_stat_max_targets = { en = "Max-targets factor" },
    gt_player_stat_hud_stat_damage_taken = { en = "Generic damage-taken factor" },
    gt_player_stat_hud_stat_healing_received = { en = "Healing-received factor" },
    gt_player_stat_hud_stat_fatigue_regen = { en = "Stamina regen rate" },
    gt_player_stat_hud_stat_block_angle = { en = "Block-angle factor" },
    gt_player_stat_hud_stat_block_cost = { en = "Block-cost factor" },
    gt_player_stat_hud_stat_push_power = { en = "Push-power factor" },
    gt_player_stat_hud_stat_push_cost = { en = "Effective push cost" },
    gt_player_stat_hud_stat_dodge_bonus = { en = "Effective dodge bonus" },
    gt_player_stat_hud_stat_cooldown_regen = { en = "Cooldown-regen factor" },
    gt_player_stat_hud_stat_reload_speed = { en = "Reload-speed factor" },
    gt_player_stat_hud_stat_total_ammo = { en = "Total-ammo factor" },

    gt_devtools_leash_lines = { en = "Bot leash lines (3D)" },
    gt_devtools_leash_lines_tooltip = { en = "Runs a line in the world from each bot to the teammate it follows and another to you, so the follow leash is visible at a glance. Purely visual, host-only, dev build only." },

    gt_devtools_share_draws = { en = "Share debug draws with other players" },
    gt_devtools_share_draws_tooltip = { en = "Sends the bot leash lines to other players running this mod so they see the same overlay. On the host it broadcasts the lines it is drawing; on a client it shows the host's lines. Only the sparse bot leash lines are shared: everyone draws their own wireframe highlights locally. Turn on Bot leash lines too on the host for there to be anything to share. Dev build only." },

    -- Debug Highlights (#302). Master + per-category wireframe overlays. Dev build
    -- only; all children default OFF. Titles carry per LOCALIZATION_STANDARD
    -- section 13; tooltips name the color and note the two known approximations.
    gt_debug_highlights = { en = "Debug Highlights" },
    gt_debug_highlights_tooltip = { en = "Master toggle for in-world debug wireframes, drawn as screen-projected outlines over the 3D view. Turn on a category below. Dev build only; works in the keep and in a mission, on host and client." },

    gt_dh_interactables = { en = "Interactables" },
    gt_dh_interactables_tooltip = { en = "Yellow box around interactable objects: doors, chests, levers, anything used with the interact key." },

    gt_dh_pickups = { en = "Item Pickups" },
    gt_dh_pickups_tooltip = { en = "Green box on ground pickups: health, ammo, potions, bombs, tomes, grimoires." },

    gt_dh_pickup_spawners = { en = "Pickup Spawn Points" },
    gt_dh_pickup_spawners_tooltip = { en = "Grey box on pickup spawn points, shown even when the spawn is empty." },

    gt_dh_hitboxes_enemies = { en = "Enemy Hitboxes" },
    gt_dh_hitboxes_enemies_tooltip = { en = "Red box around each nearby enemy's bounding volume. Whole-unit box: per-limb capsules are not exposed to mods." },

    gt_dh_hitboxes_players = { en = "Player Hitboxes" },
    gt_dh_hitboxes_players_tooltip = { en = "Dark green box around each hero's bounding volume." },

    gt_dh_headshot_zones = { en = "Headshot Zones" },
    gt_dh_headshot_zones_tooltip = { en = "Orange sphere at each enemy's head node. Approximate radius: the true headshot capsule size is not exposed to mods." },

    gt_dh_aggro_ranges = { en = "Aggro Ranges" },
    gt_dh_aggro_ranges_tooltip = { en = "Amber ring at each enemy's detection radius. Enemy perception is a radius, not a cone." },

    gt_dh_range = { en = "Draw Distance" },
    gt_dh_range_tooltip = { en = "Only draw highlights within this distance of you. Higher values cost more per frame." },
    gt_dh_range_20 = { en = "20 m" },
    gt_dh_range_30 = { en = "30 m" },
    gt_dh_range_50 = { en = "50 m" },

    -- ============================================================
    -- Gameplay
    -- ============================================================
    gameplay_group = { en = "Gameplay" },

    -- (gt_gk_group removed 2026-06-30 -- was a redundant single-item group; gt_gk_quests_enabled is now a direct master toggle.)
    gt_gk_quests_enabled = { en = "Choose Grail Knight Quests" },
    gt_gk_quests_enabled_tooltip = { en = "Overrides the Grail Knight's random quest picks with the three quests you choose below; any left on Random use the normal shuffle. The Chaos Wastes extra-quest talent still draws from the remaining quests." },
    gt_gk_quest1 = { en = "Quest 1" },
    gt_gk_quest1_tooltip = { en = "The first quest to assign the Grail Knight. Random leaves it to the normal shuffle." },
    gt_gk_quest2 = { en = "Quest 2" },
    gt_gk_quest2_tooltip = { en = "The second quest to assign. Duplicates are skipped: if the first quest already took this one, this slot falls back to the normal shuffle." },
    gt_gk_quest3 = { en = "Quest 3" },
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

    disable_friendly_fire = { en = "Disable Friendly Fire" },
    disable_friendly_fire_tooltip = { en = "No damage passes between teammates, ranged or melee. Higher difficulties normally let friendly ranged fire through; this stops that." },

    gt_adventure_save_trait_chance = { en = "Healer's Touch, Home Brewer, Grenadier %% Chance" },
    gt_adventure_save_trait_chance_tooltip = { en = "Vanilla gives these three Adventure charm traits a 25%% save chance each; raise it up to 75 to make them more worthwhile. Each player sets their own." },

    gt_offline_twitch_enabled = { en = "Offline Twitch Mode" },
    gt_offline_twitch_enabled_tooltip = { en = "Runs Twitch votes locally for the host without an account or stream, using the normal vote UI and a locally chosen winner. The filters below also apply when Twitch is linked. Takes effect on the next mission; vanilla clients receive normal Twitch vote messages." },
    gt_offline_twitch_allow_buffs = { en = "Allow buffs and effects" },
    gt_offline_twitch_allow_buffs_tooltip = { en = "Allows ordinary positive and negative Twitch effects. Unknown future vote types are grouped here." },
    gt_offline_twitch_allow_items = { en = "Allow item giveaways" },
    gt_offline_twitch_allow_items_tooltip = { en = "Allows Twitch votes that give potions, bombs, ammunition, or other items." },
    gt_offline_twitch_allow_mutators = { en = "Allow mutators" },
    gt_offline_twitch_allow_mutators_tooltip = { en = "Allows temporary Twitch mutators and curses." },
    gt_offline_twitch_allow_spawns = { en = "Allow enemy spawns" },
    gt_offline_twitch_allow_spawns_tooltip = { en = "Allows Twitch votes that spawn hordes, specials, monsters, or other enemies." },

    -- (gt_prio_specials_group became a master toggle gt_prio_specials_enabled 2026-06-30.)
    gt_prio_specials_enabled = { en = "Prioritize Specials (Tagging, Deepwood and Soulstealer)" },
    gt_prio_specials_enabled_tooltip = { en = "Biases your aim toward Special enemies, with three sub-toggles to choose where it applies: crosshair tagging, the Deepwood Staff bolt, and the Soulstealer Staff soul. Only affects your own targeting." },
    gt_prio_special_deepwood = { en = "Deepwood Staff" },
    gt_prio_special_deepwood_tooltip = { en = "Its seeking bolt prefers a Special in your aim over the nearest enemy to your crosshair, falling back to normal aim when no Special is in view. Affects only you." },
    gt_prio_special_soulstealer = { en = "Soulstealer Staff" },
    gt_prio_special_soulstealer_tooltip = { en = "Its homing soul locks onto a Special in your aim before a closer non-Special. Affects only you." },
    gt_prio_special_tag = { en = "Tagging" },
    gt_prio_special_tag_tooltip = { en = "When you tag an enemy, prefer a Special along your aim even if an elite or a pickup is in the way. Affects only you." },

    -- ============================================================
    -- Host-Side Lobby Controls (absorbed from lobby_tweaker 2026-05-25;
    -- lt v0.1.7-dev). Keys + tooltips renamed lt_* / bare-form -> gt_lobby_*.
    -- ============================================================
    gt_lobby_controls_group = { en = "Host-Side Lobby Controls" },

    -- Modded Lobby Manifest -- nested collapsible; also holds Message of the Day.
    gt_lobby_manifest_group = { en = "Modded Lobby Manifest" },
    gt_lobby_manifest_broadcast_enabled = { en = "Broadcast my mod list (as host)" },
    gt_lobby_manifest_broadcast_enabled_tooltip = { en = "Lets players whose join fails see which mods they are missing, by sharing your mod list with the lobby as host. Does not affect players who join successfully." },

    -- Message of the Day (master toggle + nested send/greet options).
    gt_lobby_motd_enabled = { en = "Send MOTD to joiners" },
    gt_lobby_motd_enabled_tooltip = { en = "When someone joins your party, send them your message of the day. Works only when you are the host, and joiners without this mod will not see it." },
    gt_lobby_motd_once_per_peer_per_session = { en = "Only greet each peer once per session" },
    gt_lobby_motd_once_per_peer_per_session_tooltip = { en = "On by default: greet each player at most once while you are hosting. Turn it off to greet them again every time they join, which is handy when someone reconnects." },
    gt_lobby_motd_send_chat = { en = "Send via chat" },
    gt_lobby_motd_send_chat_tooltip = { en = "The message arrives in the receiver's chat window, one line per break." },
    gt_lobby_motd_send_popup = { en = "Send via popup" },
    gt_lobby_motd_send_popup_tooltip = { en = "The message pops up on the receiver's screen with an OK button to dismiss it." },

    gt_lobby_manifest_failnotify_enabled = { en = "Show missing mods when a join fails" },
    gt_lobby_manifest_failnotify_enabled_tooltip = { en = "When you fail to join a modded host over a mod mismatch, replace the generic error with a list of the mods you are missing plus a button to open the Workshop. Falls back to the normal error if the host is not sharing its mod list." },

    -- Issue #737: successful-join appearance-mod parity banner.
    gt_lobby_appearance_parity_enabled = { en = "Warn when appearance mods differ from the host" },
    gt_lobby_appearance_parity_enabled_tooltip = { en = "After you join a modded host, post one chat line if an appearance mod (Weapon Tweaker, Character Weapon Variants, Cosmetics Tweaker, Weapons of Chaos, Crafting in Modded) is enabled for you but not the host, or runs a different stream or version. Mismatched appearance mods can desync modded weapon skins and crash the score screen even when the join itself succeeds. Reads the host's shared mod list, and stays silent if the host is not sharing one." },

    -- Issue #378: stalled-join watchdog.
    gt_lobby_join_watchdog_enabled = { en = "Recover from a stalled join" },
    gt_lobby_join_watchdog_enabled_tooltip = { en = "If a join to a modded host hangs on the loading screen instead of erroring out, show the missing-mods list (or a plain stall notice when the host shares no mod list) and a Leave button, so you never have to alt-F4. Off leaves a hung join hanging." },
    gt_lobby_join_watchdog_timeout_seconds = { en = "Stalled-join timeout (seconds)" },
    gt_lobby_join_watchdog_timeout_seconds_tooltip = { en = "How long a join may sit before game start before it counts as stalled, from 20 to 180 seconds. Level loading happens after this window, so a slow disk will not trip it. Default 60." },

    -- Loose lobby options (A->Z by display label).
    allow_duplicate_careers = { en = "Allow Duplicate Careers" },
    allow_duplicate_careers_tooltip = { en = "More than one player can pick the same hero and career in the same lobby." },

    gt_lobby_kick_idle_enabled = { en = "Auto-kick idle players in keep" },
    gt_lobby_kick_idle_enabled_tooltip = { en = "While in the keep, warn and then kick players who stand still too long (the host and bots are never affected). Works only when you are the host, and you can exempt specific players." },
    gt_lobby_kick_idle_threshold_minutes = { en = "Idle threshold (minutes)" },
    gt_lobby_kick_idle_threshold_minutes_tooltip = { en = "How long a player can stand still in the keep before being kicked, from 1 to 60 minutes." },
    gt_lobby_ki_warn_seconds = { en = "Warning lead time (seconds)" },
    gt_lobby_ki_warn_seconds_tooltip = { en = "How many seconds before the kick the warning message appears, from 10 to 180." },

    gt_solo_auto_restart_on_wipe = { en = "Auto-restart mission on team wipe" },
    gt_solo_auto_restart_on_wipe_tooltip = { en = "When the whole team goes down, restart the mission in place instead of returning to the keep, which is handy for solo practice and speedrun resets. Works only when you are the host." },

    gt_auto_ready_on_vote_pass = { en = "Auto-start On Vote Pass" },
    gt_auto_ready_on_vote_pass_tooltip = { en = "When a mission vote passes, skip the bridge countdown and start immediately. Host only; leave it off if you enjoy the bridge sequence." },

    gt_lobby_session_ignore_enabled = { en = "Enable ignore list" },
    gt_lobby_session_ignore_enabled_tooltip = { en = "Players on your ignore list are turned away the moment they try to join, either for this session only or permanently. Works only when you are the host." },

    gt_lobby_slot_reservations_enabled = { en = "Enable slot reservations" },
    gt_lobby_slot_reservations_enabled_tooltip = { en = "Named players get lobby slots held for them by their Steam ID; other joiners are turned away while a held slot still waits for its player. Works only when you are the host." },

    gt_ready_up_hotkey = { en = "Ready Up (Skip Countdown)" },
    gt_ready_up_hotkey_tooltip = { en = "Starts the mission right away, cutting straight past the Bridge of Shadows countdown. Host only." },

    gt_unlock_all_weaves = { en = "Unlock All Ranked Weaves" },
    gt_unlock_all_weaves_tooltip = { en = "Every ranked weave in the Winds of Magic ladder becomes playable without grinding up the ladder first. You still need the Winds of Magic DLC, and this only affects your own game." },

    -- ============================================================
    -- Info -- on-screen text readouts / warnings.
    -- ============================================================
    gt_info_group = { en = "Info" },
    gt_solo_assassin_text_warning = { en = "Assassin spawn warning (on-screen text)" },
    gt_solo_assassin_text_warning_tooltip = { en = "Flashes an 'ASS!' warning with a live count on screen whenever a Gutter Runner is about to spawn. Normal area names are hidden while this or the packmaster warning is on." },
    gt_solo_boss_path_progress = { en = "Boss path progress readout (needs StreamingInfo)" },
    gt_solo_boss_path_progress_tooltip = { en = "Feeds the boss main-path distance to the StreamingInfo overlay mod. Does nothing unless StreamingInfo is installed." },
    gt_solo_packmaster_text_warning = { en = "Packmaster spawn warning (on-screen text)" },
    gt_solo_packmaster_text_warning_tooltip = { en = "Flashes a 'PACK!' warning with a live count on screen whenever a Packmaster is about to spawn. Normal area names are hidden while this or the assassin warning is on." },

    -- ============================================================
    -- Visuals and Audio (was "Solo & QoL"; ported from True Solo QoL Tweaks;
    -- _gt_solo_qol.lua). setting_ids preserved for user state continuity.
    -- ============================================================
    gt_solo_group = { en = "Visuals and Audio" },
    gt_solo_assassin_hero_vo = { en = "Assassin/Packmaster hero voice callout" },
    gt_solo_assassin_hero_vo_tooltip = { en = "Even in solo play, your hero calls out the instant a Gutter Runner or Packmaster spawns." },
    gt_solo_disable_downed_fx = { en = "Disable downed screen effects" },
    gt_solo_disable_downed_fx_tooltip = { en = "Removes the fullscreen desaturation and vignette overlay shown while you are knocked down and while wounded (bleeding out). Visual only, affects only your own game." },
    gt_solo_disable_fog = { en = "Disable fog" },
    gt_solo_disable_fog_tooltip = { en = "The level's fog stops rendering, giving a cleaner line of sight. Purely visual and affects only your own game." },
    gt_solo_disable_mutator_explosions = { en = "Disable mutator death explosions" },
    gt_solo_disable_mutator_explosions_tooltip = { en = "Removes the purple burst that enemies leave behind when they die under the Explosive mutator or boon. Works whether you host or join, and only changes what you see." },
    gt_solo_disable_sun_shadows = { en = "Disable sun shadows" },
    gt_solo_disable_sun_shadows_tooltip = { en = "Sun shadows stop rendering, for clearer visibility and a small performance gain. Purely visual and affects only your own game." },
    gt_solo_disable_ult_fx = { en = "Disable ult screen effects" },
    gt_solo_disable_ult_fx_tooltip = { en = "Removes the fullscreen color and distortion overlay and the swirly screen effects shown when a career ability is used: Slayer, Zealot, Ranger, Shade, Huntsman, and Sister of the Thorn radiance. Visual only, affects only your own game." },
    gt_solo_disable_ult_vo = { en = "Disable your ult voice line" },
    gt_solo_disable_ult_vo_tooltip = { en = "Silences your own character's voice line when you use your career ultimate." },
    gt_solo_draw_boss_spheres = { en = "Draw boss-event spheres" },
    gt_solo_draw_boss_spheres_tooltip = { en = "Red wireframe markers appear at the boss and main-path event spots on the level, as a debug or streamer aid." },
    gt_more_corpses_count = { en = "Max Ragdolls" },
    gt_more_corpses_count_tooltip = { en = "How many ragdolls and corpses stay on the ground before the game starts removing them. Vanilla is 24; raise it up to 300 for a more cinematic battlefield, though high values can strain slower machines." },
    -- Melee Attack Warning (Issue #308). Client-side, cosmetic only.
    gt_melee_warning = { en = "Melee Attack Warning" },
    gt_melee_warning_tooltip = { en = "Fires a local cue when a nearby enemy starts a melee swing at you, so you can dodge a moment earlier under lag. Cosmetic only; hits are unchanged." },
    gt_melee_warning_audio = { en = "Warning sound" },
    gt_melee_warning_audio_tooltip = { en = "Plays a short ping the moment a swing is detected." },
    gt_melee_warning_visual = { en = "Warning screen flash" },
    gt_melee_warning_visual_tooltip = { en = "Pulses a red screen-edge glow the moment a swing is detected." },
    gt_melee_warning_lead = { en = "Warning lead time" },
    gt_melee_warning_lead_tooltip = { en = "How far ahead of the predicted hit the cue fires. Higher values warn earlier; match it to your ping." },
    gt_melee_warning_lead_0 = { en = "0 ms" },
    gt_melee_warning_lead_50 = { en = "50 ms" },
    gt_melee_warning_lead_100 = { en = "100 ms" },
    gt_melee_warning_lead_150 = { en = "150 ms" },
    gt_melee_warning_lead_200 = { en = "200 ms" },
    gt_melee_warning_lead_250 = { en = "250 ms" },
    gt_melee_warning_scope = { en = "Warn for" },
    gt_melee_warning_scope_tooltip = { en = "Elites only covers stormvermin, maulers, chaos warriors, bestigors, plague monks, and berserkers. All melee flags every melee enemy." },
    gt_melee_warning_scope_elites = { en = "Elites only" },
    gt_melee_warning_scope_all = { en = "All melee enemies" },
    -- Smooth Health-Bar Damage (Issue #308). Presentation only.
    gt_hp_smoothing = { en = "Smooth Health-Bar Damage" },
    gt_hp_smoothing_tooltip = { en = "Eases your own health bar down over a short window instead of snapping, so a lag spike of damage reads more smoothly. Heals and knockdowns still snap." },
    gt_hp_smoothing_ms = { en = "Smoothing window" },
    gt_hp_smoothing_ms_tooltip = { en = "How long the bar takes to slide down to a new lower value." },
    gt_hp_smoothing_ms_100 = { en = "100 ms" },
    gt_hp_smoothing_ms_150 = { en = "150 ms" },
    gt_hp_smoothing_ms_200 = { en = "200 ms" },
    gt_hp_smoothing_ms_250 = { en = "250 ms" },

    -- Host-authoritative melee latency compensation (#1034).
    gt_host_lag_comp = { en = "Host-side Melee Latency Compensation" },
    gt_host_lag_comp_tooltip = { en = "When you host, ordinary blockable enemy melee hits against remote human players wait for a short grace window based on the host-measured connection delay. A block, dodge, or attack-interrupting stagger that reaches the host during that window prevents the hit. Bots, the host, grabs, projectiles, hazards, and unblockable attacks are unchanged. On by default." },
    gt_host_lag_comp_max_ms = { en = "Maximum Compensation Window" },
    gt_host_lag_comp_max_ms_tooltip = { en = "Caps the host-measured grace window from 0 to 350 milliseconds. The actual window follows a smoothed connection delay for each remote player and never exceeds this value." },

    -- ============================================================
    -- Code-referenced strings with no widget (rendered by the mod at runtime).
    -- Kept even though they don't map 1:1 to a menu entry.
    -- ============================================================
    -- MOTD popup title. The command-authored text buffer is a persisted setting,
    -- not a localized/menu-facing value.
    gt_lobby_motd_popup_topic = { en = "Message of the Day" },

    -- Failed-join manifest reveal (rendered text; _gt_lobby_failed_join_reveal.lua).
    gt_lobby_failnotify_title              = { en = "Cannot join: modded host" },
    gt_lobby_failnotify_required_header    = { en = "You are missing %%d mods required by the host:" },
    gt_lobby_failnotify_version_header     = { en = "%%d mods have a version mismatch:" },
    gt_lobby_failnotify_cosmetic_footer    = { en = "Host also has %%d cosmetic mods you don't (gameplay unaffected)." },
    gt_lobby_failnotify_button_workshop    = { en = "Open Workshop" },
    gt_lobby_failnotify_button_cancel      = { en = "Close" },

    -- Issue #378 join-watchdog rendered text.
    gt_lobby_watchdog_intro       = { en = "The join to this host timed out. You appear to be missing mods it requires:" },
    gt_lobby_watchdog_stall_title = { en = "Join timed out" },
    gt_lobby_watchdog_stall_body  = { en = "The join to this lobby did not finish. The host may require mods you do not have, or may not be sharing its mod list. Leave to return to the main menu." },
}
