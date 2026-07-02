-- Localization for enemy_tweaker. All entries (static + dynamic per-difficulty)
-- are baked here at file-load time. The data file passes raw key strings only,
-- so VMF resolves them at render time — never call mod:localize() in the data
-- file (it returns "<key>" if loc isn't ready, and that bracket text becomes
-- the literal widget label).

local B = require("scripts/mods/enemy_tweaker/enemy_tweaker_breeds")

local loc = {
    mod_description = {
        en = "Customize enemy spawns: horde compositions, per-difficulty specials control, and breed substitution.",
    },

    -- ============================================================
    -- HORDES
    -- ============================================================
    horde_group = { en = "Horde Composition" },
    horde_preset = { en = "Horde Preset" },
    horde_preset_tooltip = {
        en = "Replaces the enemies in hordes with a chosen preset. Faction presets force a single race, while Theme presets are broader overhauls such as elites only.",
    },
    preset_off               = { en = "Off (vanilla hordes)" },
    preset_skaven_only       = { en = "Faction: Skaven Only" },
    preset_chaos_only        = { en = "Faction: Chaos Only" },
    preset_beastmen_invasion = { en = "Faction: Beastmen Invasion" },
    preset_mixed_factions    = { en = "Faction: Mixed (all three)" },
    preset_all_elites        = { en = "Theme: All Elites" },
    -- ============================================================
    -- SPAWN SCALING (4 multipliers, v0.6.0-dev)
    -- ============================================================
    spawn_scaling_group = { en = "Spawn Scaling" },

    horde_size_multiplier = { en = "Paced Horde Size (multiplier)" },
    horde_size_multiplier_tooltip = {
        en = "Multiplies how many enemies come in each paced horde, the regular waves between big events. 0 means none, 1 is normal, and 5 is the capped maximum since paced hordes get unstable past that.",
    },

    event_size_multiplier = { en = "Event Horde Size (multiplier)" },
    event_size_multiplier_tooltip = {
        en = "Multiplies how many enemies come in event hordes, the scripted ambushes and bell-summoned waves that make up most mission hordes. 0 means none, 1 is normal, and 5 is the capped maximum.",
    },

    roaming_size_multiplier = { en = "Roaming Enemy Density (multiplier)" },
    roaming_size_multiplier_tooltip = {
        en = "Multiplies how many wandering enemies roam the level. 0 means none, 1 is normal, and 15 is the maximum; very high values mostly add loose ambient enemies rather than larger packs.",
    },

    patrol_size_multiplier = { en = "Patrol Size (multiplier)" },
    patrol_size_multiplier_tooltip = {
        en = "Multiplies the size of marching patrols, the organized squads such as Stormvermin, Chaos Warrior, or Beastmen patrols. 0 means no patrols, 1 is normal, and 15 is the maximum; very large patrols may run into the game's movement limits.",
    },

    -- ============================================================
    -- SPAWN PACING (v0.7.0-dev — SpawnTweaks parity pass)
    -- ============================================================
    spawn_pacing_group = { en = "Spawn Pacing (frequency + caps)" },

    max_grunts_override = { en = "Max Active Trash Enemies" },
    max_grunts_override_tooltip = {
        en = "Sets how many basic trash enemies can be alive at the same time (the normal cap is about 90). Raising it packs the map with more enemies at once for an Onslaught-style feel; the range is 10 to 360.",
    },

    spawn_pace_multiplier = { en = "Spawn Rate Multiplier" },
    spawn_pace_multiplier_tooltip = {
        en = "Multiplies how often new enemies spawn. 1 is normal, 2 is roughly twice as many spawn waves per minute, 0.5 is half, and the range is 0 to 5.",
    },

    horde_grunt_push_threshold = { en = "Horde Push Threshold (alive grunts)" },
    horde_grunt_push_threshold_tooltip = {
        en = "The game starts a new horde once fewer than this many basic enemies are still alive (normally 60). Lower values mean hordes come almost back to back; the range is 10 to 240.",
    },

    horde_frequency_min = { en = "Horde Frequency Min (seconds)" },
    horde_frequency_min_tooltip = {
        en = "The shortest time, in seconds, the game waits between paced hordes (normally about 50). Lower values make hordes arrive more often; the range is 5 to 200.",
    },

    horde_frequency_max = { en = "Horde Frequency Max (seconds)" },
    horde_frequency_max_tooltip = {
        en = "The longest time, in seconds, the game waits between paced hordes (normally about 100). The actual gap is picked at random between the minimum and this value; the range is 5 to 200.",
    },

    ambients_ignore_threat = { en = "Ambient Spawns Ignore Threat" },
    ambients_ignore_threat_tooltip = {
        en = "When on, small ambient patrols keep spawning even during heavy combat. Normally the game pauses them while fighting is intense, so turn this on if the Roaming Enemy Density setting feels weaker than it should.",
    },

    -- ============================================================
    -- BEASTMAN BANNER (v0.7.2-dev)
    -- ============================================================
    banner_group = { en = "Beastman Banner" },

    banner_bearer_staggerable_during_placement = { en = "Bearer Staggerable During Placement" },
    banner_bearer_staggerable_during_placement_tooltip = {
        en = "When on, the Beastmen standard-bearer can be staggered and interrupted while planting the banner. Normally he cannot be stopped once the planting starts, so this lets a well-timed hit cancel it.",
    },

    banner_breakable_by_ranged = { en = "Banner Takes Ranged Damage" },
    banner_breakable_by_ranged_tooltip = {
        en = "When on, the planted Beastmen banner can be destroyed by ranged weapons like bows, handguns, and crossbows. Normally only melee attacks and a few special sources can damage it.",
    },

    banner_no_camera_jerk_on_placement = { en = "No Camera Jerk On Placement" },
    banner_no_camera_jerk_on_placement_tooltip = {
        en = "When on, planting the Beastmen standard no longer shoves the player or jerks the camera. The shockwave still affects nearby Beastmen as usual.",
    },

    -- ============================================================
    -- ENEMY SPAWNS (per-difficulty)
    -- ============================================================
    enemy_spawns_group   = { en = "Enemy Spawns" },
    special_spawns_group = { en = "Special Spawns" },

    -- Difficulty mimic — override the difficulty key used by
    -- patch_settings_with_difficulty for individual spawn-side subsystems.
    -- Player/enemy stats stay on the real difficulty; only spawn frequency,
    -- composition, density etc. mimic the chosen difficulty.
    difficulty_mimic_group = { en = "Difficulty Mimic" },

    mimic_opt_off         = { en = "Match (vanilla)" },
    mimic_opt_normal      = { en = "Recruit" },
    mimic_opt_hard        = { en = "Veteran" },
    mimic_opt_harder      = { en = "Champion" },
    mimic_opt_hardest     = { en = "Legend" },
    mimic_opt_cataclysm   = { en = "Cataclysm 1" },
    mimic_opt_cataclysm_2 = { en = "Cataclysm 2" },
    mimic_opt_cataclysm_3 = { en = "Cataclysm 3" },

    mimic_horde         = { en = "Horde Composition Difficulty" },
    mimic_horde_tooltip = {
        en = "Uses another difficulty's horde makeup without changing your real difficulty. Player and enemy stats stay as they are.",
    },
    mimic_specials         = { en = "Specials Difficulty" },
    mimic_specials_tooltip = {
        en = "Uses another difficulty's special-enemy rules, such as how many can be active and how often they appear, without changing your real difficulty. Player and enemy stats stay as they are.",
    },
    mimic_pacing         = { en = "Horde Frequency Difficulty" },
    mimic_pacing_tooltip = {
        en = "Uses another difficulty's horde timing and pacing without changing your real difficulty. Player and enemy stats stay as they are.",
    },
    mimic_pack_spawning         = { en = "Roaming Density Difficulty" },
    mimic_pack_spawning_tooltip = {
        en = "Uses another difficulty's roaming and ambient enemy density without changing your real difficulty. Player and enemy stats stay as they are.",
    },
    mimic_intensity         = { en = "Intensity Difficulty" },
    mimic_intensity_tooltip = {
        en = "Uses another difficulty's combat intensity buildup and decay without changing your real difficulty. Player and enemy stats stay as they are.",
    },
    mimic_boss         = { en = "Boss/Event Difficulty" },
    mimic_boss_tooltip = {
        en = "Uses another difficulty's monster and boss spawn timing without changing your real difficulty. Player and enemy stats stay as they are.",
    },

    -- ============================================================
    -- FACTION SUBSTITUTION
    -- ============================================================
    faction_swap_group   = { en = "Faction Substitution" },
    faction_opt_off      = { en = "Off (don't swap)" },
    faction_opt_skaven   = { en = "Skaven" },
    faction_opt_chaos    = { en = "Chaos" },
    faction_opt_beastmen = { en = "Beastmen" },

    faction_swap_skaven           = { en = "Replace Skaven Hordes With" },
    faction_swap_skaven_tooltip   = {
        en = "Replaces Skaven paced hordes with the chosen faction's hordes instead. Only the regular paced hordes change; scripted event hordes stay as they are.",
    },
    faction_swap_chaos            = { en = "Replace Chaos Hordes With" },
    faction_swap_chaos_tooltip    = {
        en = "Replaces Chaos paced hordes with the chosen faction's hordes instead. Handy on missions that turn to Chaos in later areas, like Athel Yenlui or Hunger in the Dark.",
    },
    faction_swap_beastmen         = { en = "Replace Beastmen Hordes With" },
    faction_swap_beastmen_tooltip = {
        en = "Replaces Beastmen paced hordes with the chosen faction's hordes instead. Only the regular paced hordes change; scripted event hordes stay as they are.",
    },

    -- ============================================================
    -- BREED SUBSTITUTION
    -- ============================================================
    breed_swap_group        = { en = "Breed Substitution" },
    breed_swap_off          = { en = "Off" },
    breed_swap_from         = { en = "Replace This Breed" },
    breed_swap_from_tooltip = { en = "Choose an enemy type to replace. Every enemy of this type in hordes becomes the one selected below." },
    breed_swap_to           = { en = "With This Breed" },
    breed_swap_to_tooltip   = { en = "The enemy type used as the replacement. It must be different from the one chosen above." },

    -- ============================================================
    -- MONSTER POOL: SKARRIK SPINEMANGLER
    -- ============================================================
    monster_swap_group              = { en = "Monster Pool: Skarrik Spinemangler" },
    warlord_in_monster_pool         = { en = "Add Skarrik Spinemangler to Monster Pool" },
    warlord_in_monster_pool_tooltip = { en = "When on, a level's monster (Rat Ogre, Stormfiend, Chaos Spawn, Troll, or Minotaur) can be replaced by Skarrik Spinemangler, the Skaven Warlord. This is host only and experimental: away from his home level he may appear without music or act passively, and on some levels he will not show up at all. The Festering Ground finale troll is never replaced." },
    warlord_monster_chance          = { en = "Skarrik Spawn Chance (%%)" },
    warlord_monster_chance_tooltip  = { en = "The percent chance that an eligible monster is replaced by Skarrik Spinemangler. 0 never happens and 100 replaces every eligible monster; kept low so several Warlords do not appear at once." },

    -- ============================================================
    -- ROAMING ELITE POOL: STORMVERMIN CHAMPION (v0.7.18-dev)
    -- ============================================================
    elite_swap_group                = { en = "Roaming Elite Pool: Stormvermin Champion" },
    champion_in_elite_pool          = { en = "Add Stormvermin Champion to Roaming Elites" },
    champion_in_elite_pool_tooltip  = { en = "When on, roaming Skaven Stormvermin elites can be replaced by the Stormvermin Champion at the chance below; only loose wandering elites are affected, not horde or event spawns. This host-only option retunes the Champion into a tough mini-boss with a health bar and boss music, so treat it as a rare heavy encounter. It affects every Stormvermin Champion while on, including its rare normal appearances, and is restored when turned off." },
    champion_elite_chance           = { en = "Champion Spawn Chance (%%)" },
    champion_elite_chance_tooltip   = { en = "The percent chance that a roaming Skaven elite is replaced by the Stormvermin Champion. 0 never happens and 100 replaces every roaming elite; kept low so the Champion stays a rare mini-boss." },

    -- ============================================================
    -- BIG REBALANCE (Core's BR integration)
    -- ============================================================
    br_group                          = { en = "Big Rebalance" },
    br_group_tooltip                  = { en = "Opt-in Big Rebalance enemy/stagger/THP changes. All toggles default OFF. REQUIRES 'Tweaker: Buffs' (bt) installed with its master toggle ON; without bt master, every toggle here is inert." },

    br_breed_tuning_group               = { en = "Breed Tuning" },
    br_bloodlust_class_table            = { en = "BR: bloodlust_health class table" },
    br_bloodlust_class_table_tooltip    = {
        en = "Exposes the BR per-class HP table (NewBreedTweaks.bloodlust_health). Inert until 'per-breed bloodlust_health assignments' is on.",
    },
    br_bloodlust_per_breed_assign       = { en = "BR: per-breed bloodlust_health assignments" },
    br_bloodlust_per_breed_assign_tooltip = {
        en = "Writes the BR class-table value to each breed's bloodlust_health field (45 breeds). Requires the class-table toggle above.",
    },
    br_breed_trash_flags                = { en = "BR: trash flags (horde-rank breeds)" },
    br_breed_trash_flags_tooltip        = {
        en = "Sets breed.trash = true on the 11 horde-rank breeds. Consumed by the Maidenguard res-time DR path in Tweaker: Careers.",
    },
    br_per_breed_overrides_group        = { en = "Per-breed overrides" },

    br_stagger_damage_group             = { en = "Stagger / Damage math" },
    br_stagger_ai_rewrite               = { en = "BR: stagger_ai rewrite" },
    br_stagger_ai_rewrite_tooltip       = {
        en = "Replaces DamageUtils.stagger_ai with the BR body: blackboard stagger-immunity, push/stab/pull angle logic, on_stagger proc. Affects every AI stagger globally.",
    },
    br_calculate_damage_rewrite         = { en = "BR: calculate_damage rewrite" },
    br_calculate_damage_rewrite_tooltip = {
        en = "Replaces DamageUtils.calculate_damage with the BR body: smiter/finesse/mainstay stagger rules, unbalanced_damage_taken stat_buff, weave scaling, max_friendly_damage cap. Affects ALL damage.",
    },
    br_shield_slam_rewrite              = { en = "BR: ActionShieldSlam._hit rewrite" },
    br_shield_slam_rewrite_tooltip      = {
        en = "Replaces ActionShieldSlam._hit with the BR body: inner/outer push radii, AOE damage dispatch, level-unit handling. Required for BR shield-weapon behavior.",
    },
    br_unbalance_debuff_infra           = { en = "BR: power-modifier debuff (Unbalance infra)" },
    br_unbalance_debuff_infra_tooltip   = {
        en = "Registers two BR enemy debuff templates: rebaltourn_tank_unbalance (proc on stagger) and rebaltourn_tank_unbalance_buff (+15%% damage taken for 5s). Talent-slot side lives in Tweaker: Careers.",
    },

    br_thp_group                        = { en = "THP from kills (template registration)" },
    br_thp_regrowth_template            = { en = "BR: regrowth THP source" },
    br_thp_regrowth_template_tooltip    = {
        en = "Registers rebaltourn_regrowth: 1.5 THP on melee crit, 3 THP on headshot, 4.5 on crit-headshot. Perk ninja_healing. Talent slots in Tweaker: Careers.",
    },
    br_thp_vanguard_template            = { en = "BR: vanguard THP source" },
    br_thp_vanguard_template_tooltip    = {
        en = "Registers rebaltourn_vanguard: THP on stagger, flat 0.6 on push, ≤5 targets, no corpses. Perk tank_healing. Talent slots in Tweaker: Careers.",
    },
    br_thp_reaper_template              = { en = "BR: reaper THP source" },
    br_thp_reaper_template_tooltip      = {
        en = "Registers rebaltourn_reaper: THP per damage dealt, multiplier -0.05, bonus 0.25, max_targets 5. Perk linesman_healing. Uses vanilla proc.",
    },
    br_thp_bloodlust_template           = { en = "BR: bloodlust THP source" },
    br_thp_bloodlust_template_tooltip   = {
        en = "Registers rebaltourn_bloodlust: THP on kill scaled by breed.bloodlust_health, multiplier 0.2. Perk smiter_healing. Inert without 'per-breed bloodlust_health assignments'.",
    },

    -- ============================================================
    -- BOSS MECHANIC TWEAKS (received from general_tweaker_dev 2026-06-20)
    -- ============================================================
    boss_tweaks_group = { en = "Boss Mechanic Tweaks" },
    et_fly_disable_mult = { en = "Fly disable: x vanilla duration (Halescourge/Nurgloth)" },
    et_fly_disable_mult_tooltip = { en = "Multiplies how long the cloud of flies from Burblespue Halescourge and Nurgloth keeps you disabled. 1.00 is normal, 0.50 is half as long, 2.00 is twice, and 0 is nearly instant; it scales each boss's fly attack from its own base length, so one setting cannot make them all the exact same duration. Host only, since the boss runs on the host, and the cloud can still be destroyed either way." },

}

-- ============================================================
-- Dynamic entries: per-difficulty group headers + per-special widgets
-- ============================================================

local SPECIALS = B.collect_specials()

local FACTION_GROUPS = {
    { label = "Skaven",   list = B.SKAVEN },
    { label = "Chaos",    list = B.CHAOS },
    { label = "Beastmen", list = B.BEASTMEN },
}

-- Breed-swap dropdown option labels (one entry per breed, faction-prefixed).
for _, g in ipairs(FACTION_GROUPS) do
    for _, breed in ipairs(g.list) do
        loc[B.breed_swap_option_key(breed)] = {
            en = string.format("%s - %s", g.label, B.breed_label(breed)),
        }
    end
end

-- Per-difficulty entries.
for _, diff in ipairs(B.DIFFICULTIES) do
    local k = diff.key

    loc["et_diff_" .. k .. "_group"]            = { en = diff.label }
    loc[B.setting_key(k, "weights_group")]      = { en = "Spawn Weights" }
    loc[B.setting_key(k, "disabled_group")]     = { en = "Disabled Specials" }
    loc[B.setting_key(k, "max_total")]          = { en = "Max Specials Active" }
    loc[B.setting_key(k, "max_total_tooltip")]  = {
        en = string.format("The most specials that can be alive at once on %s (normally %d).", diff.label, diff.max_total),
    }
    loc[B.setting_key(k, "max_same")]           = { en = "Max Specials of Same Type" }
    loc[B.setting_key(k, "max_same_tooltip")]   = {
        en = string.format("The most specials of the same type that can be alive at once on %s (normally %d).", diff.label, diff.max_same),
    }

    for _, breed in ipairs(SPECIALS) do
        local label = B.breed_label(breed)
        loc[B.setting_key(k, "weight", breed)]            = { en = label }
        loc[B.setting_key(k, "weight", breed) .. "_tooltip"] = {
            en = string.format("How likely %s is to be chosen as a special on %s. 0 means never; the default of 1 is the normal even chance.", label, diff.label),
        }
        loc[B.setting_key(k, "disabled", breed)]          = { en = label }
        loc[B.setting_key(k, "disabled", breed) .. "_tooltip"] = {
            en = string.format("Prevents %s from spawning as a special on %s.", label, diff.label),
        }
    end
end

return loc
