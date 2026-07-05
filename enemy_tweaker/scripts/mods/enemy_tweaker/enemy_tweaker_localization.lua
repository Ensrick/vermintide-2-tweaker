-- Localization for enemy_tweaker. All entries (static + dynamic per-difficulty)
-- are baked here at file-load time. The data file passes raw key strings only,
-- so VMF resolves them at render time — never call mod:localize() in the data
-- file (it returns "<key>" if loc isn't ready, and that bracket text becomes
-- the literal widget label).
--
-- Section order mirrors the top-level widget tree in enemy_tweaker_data.lua,
-- which is A→Z by display label. Group headings are Title Case; setting labels
-- are sentence case (LOCALIZATION_STANDARD §11).

local B = require("scripts/mods/enemy_tweaker/enemy_tweaker_breeds")

local loc = {
    mod_description = {
        en = "Customize enemy spawns: horde compositions, per-difficulty specials control, and breed substitution.",
    },

    -- ============================================================
    -- Beastman Banner
    -- ============================================================
    banner_group = { en = "[working] Beastman Banner" },

    banner_breakable_by_ranged = { en = "[working] Banner takes ranged damage" },
    banner_breakable_by_ranged_tooltip = {
        en = "Lets ranged weapons (bows, handguns, crossbows) destroy the planted Beastmen banner. Normally only melee and a few special sources can damage it.",
    },

    banner_bearer_staggerable_during_placement = { en = "[working] Bearer staggerable during placement" },
    banner_bearer_staggerable_during_placement_tooltip = {
        en = "Lets the Beastmen standard-bearer be staggered and interrupted while planting the banner. Normally the planting cannot be stopped once it starts.",
    },

    banner_no_camera_jerk_on_placement = { en = "[working] No camera jerk on placement" },
    banner_no_camera_jerk_on_placement_tooltip = {
        en = "Stops the planted Beastmen standard from shoving the player or jerking the camera. The shockwave still affects nearby Beastmen.",
    },

    -- ============================================================
    -- Boss Mechanic Tweaks
    -- ============================================================
    boss_tweaks_group = { en = "[working] Boss Mechanic Tweaks" },
    et_fly_disable_mult = { en = "[working] Fly-disable duration (Halescourge/Nurgloth)" },
    et_fly_disable_mult_tooltip = {
        en = "Multiplies how long the cloud of flies from Burblespue Halescourge and Nurgloth keeps you disabled: 1.00 normal, 0.50 half, 2.00 double, 0 near-instant. Each boss scales from its own base length, so one value cannot make them identical. Host only; the cloud can still be destroyed.",
    },

    -- ============================================================
    -- Breed Substitution
    -- ============================================================
    breed_swap_group        = { en = "[working] Breed Substitution" },
    breed_swap_off          = { en = "Off" },
    breed_swap_from         = { en = "[working] Replace this breed" },
    breed_swap_from_tooltip = { en = "Every enemy of this type in hordes becomes the one chosen below." },
    breed_swap_to           = { en = "[working] With this breed" },
    breed_swap_to_tooltip   = { en = "The enemy type used as the replacement. It must be different from the one chosen above." },

    -- ============================================================
    -- Enemy Spawns
    -- ============================================================
    enemy_spawns_group   = { en = "[working] Enemy Spawns" },

    -- Difficulty Mimic — override the difficulty key used by
    -- patch_settings_with_difficulty for individual spawn-side subsystems.
    -- Player/enemy stats stay on the real difficulty; only spawn frequency,
    -- composition, density etc. mimic the chosen difficulty.
    difficulty_mimic_group = { en = "[working] Difficulty Mimic" },

    mimic_opt_off         = { en = "Match (vanilla)" },
    mimic_opt_normal      = { en = "Recruit" },
    mimic_opt_hard        = { en = "Veteran" },
    mimic_opt_harder      = { en = "Champion" },
    mimic_opt_hardest     = { en = "Legend" },
    mimic_opt_cataclysm   = { en = "Cataclysm 1" },
    mimic_opt_cataclysm_2 = { en = "Cataclysm 2" },
    mimic_opt_cataclysm_3 = { en = "Cataclysm 3" },

    mimic_boss         = { en = "[working] Boss/event difficulty" },
    mimic_boss_tooltip = {
        en = "Uses another difficulty's monster and boss spawn timing without changing your real difficulty. Player and enemy stats stay as they are.",
    },
    mimic_horde         = { en = "[working] Horde composition difficulty" },
    mimic_horde_tooltip = {
        en = "Uses another difficulty's horde makeup without changing your real difficulty. Player and enemy stats stay as they are.",
    },
    mimic_pacing         = { en = "[working] Horde frequency difficulty" },
    mimic_pacing_tooltip = {
        en = "Uses another difficulty's horde timing and pacing without changing your real difficulty. Player and enemy stats stay as they are.",
    },
    mimic_intensity         = { en = "[working] Intensity difficulty" },
    mimic_intensity_tooltip = {
        en = "Uses another difficulty's combat intensity buildup and decay without changing your real difficulty. Player and enemy stats stay as they are.",
    },
    mimic_pack_spawning         = { en = "[working] Roaming density difficulty" },
    mimic_pack_spawning_tooltip = {
        en = "Uses another difficulty's roaming and ambient enemy density without changing your real difficulty. Player and enemy stats stay as they are.",
    },
    mimic_specials         = { en = "[working] Specials difficulty" },
    mimic_specials_tooltip = {
        en = "Uses another difficulty's special-enemy rules, such as how many can be active and how often they appear, without changing your real difficulty. Player and enemy stats stay as they are.",
    },

    -- Special Spawns — the group header. Per-difficulty blocks + per-special
    -- weight/disable widgets are generated dynamically at the bottom of this file.
    special_spawns_group = { en = "[working] Special Spawns" },

    -- ============================================================
    -- Faction Substitution
    -- ============================================================
    faction_swap_group   = { en = "[working] Faction Substitution" },
    faction_opt_off      = { en = "Off (don't swap)" },
    faction_opt_skaven   = { en = "Skaven" },
    faction_opt_chaos    = { en = "Chaos" },
    faction_opt_beastmen = { en = "Beastmen" },

    faction_swap_skaven           = { en = "[working] Replace Skaven hordes with" },
    faction_swap_skaven_tooltip   = {
        en = "Replaces Skaven paced hordes with the chosen faction's hordes instead. Only the regular paced hordes change; scripted event hordes stay as they are.",
    },
    faction_swap_chaos            = { en = "[working] Replace Chaos hordes with" },
    faction_swap_chaos_tooltip    = {
        en = "Replaces Chaos paced hordes with the chosen faction's hordes instead. Handy on missions that turn to Chaos in later areas, like Athel Yenlui or Hunger in the Dark.",
    },
    faction_swap_beastmen         = { en = "[working] Replace Beastmen hordes with" },
    faction_swap_beastmen_tooltip = {
        en = "Replaces Beastmen paced hordes with the chosen faction's hordes instead. Only the regular paced hordes change; scripted event hordes stay as they are.",
    },

    -- ============================================================
    -- Horde Composition
    -- ============================================================
    horde_group = { en = "[working] Horde Composition" },
    horde_preset = { en = "[working] Horde preset" },
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
    -- Skaven Warlord Monster Pool
    -- ============================================================
    -- #324 (v0.7.27-dev): retargeted from literal Skarrik to the new
    -- mod-added "Skaven Warlord" breed (et_skaven_warlord, the unused
    -- champion-recolour of Skarrik's model). Significant overhaul, so the
    -- tags drop [working] for [untested] per LOCALIZATION_STANDARD § 13.4.
    monster_swap_group              = { en = "[untested] Skaven Warlord Monster Pool" },
    warlord_in_monster_pool         = { en = "[untested] Add Skaven Warlord to monster pool" },
    warlord_in_monster_pool_tooltip = { en = "Lets a level's monster (Rat Ogre, Stormfiend, Chaos Spawn, Troll, or Minotaur) be replaced by the Skaven Warlord, a new boss that uses the unused recolour of Skarrik's model with the Stormvermin Champion's full boss stats. Host rolls the chance, and every player in the lobby needs this mod installed for the Warlord to appear safely. The Festering Ground finale troll is never replaced." },
    warlord_monster_chance          = { en = "[untested] Skaven Warlord spawn chance (%%)" },
    warlord_monster_chance_tooltip  = { en = "The percent chance that an eligible monster is replaced by the Skaven Warlord. 0 never happens and 100 replaces every eligible monster; kept low so several Warlords do not appear at once." },

    -- ============================================================
    -- Spawn Pacing
    -- ============================================================
    spawn_pacing_group = { en = "[working] Spawn Pacing" },

    ambients_ignore_threat = { en = "[working] Ambient spawns ignore threat" },
    ambients_ignore_threat_tooltip = {
        en = "Keeps small ambient patrols spawning even during heavy combat. Normally the game pauses them while fighting is intense; turn this on if Roaming enemy density feels weaker than expected.",
    },

    horde_frequency_min = { en = "[working] Horde frequency min (seconds)" },
    horde_frequency_min_tooltip = {
        en = "The shortest time, in seconds, the game waits between paced hordes (normally about 50). Lower values make hordes arrive more often; the range is 5 to 200.",
    },

    horde_frequency_max = { en = "[working] Horde frequency max (seconds)" },
    horde_frequency_max_tooltip = {
        en = "The longest time, in seconds, the game waits between paced hordes (normally about 100). The actual gap is picked at random between the minimum and this value; the range is 5 to 200.",
    },

    horde_grunt_push_threshold = { en = "[working] Horde push threshold (alive grunts)" },
    horde_grunt_push_threshold_tooltip = {
        en = "The game starts a new horde once fewer than this many basic enemies are still alive (normally 60). Lower values mean hordes come almost back to back; the range is 10 to 240.",
    },

    max_grunts_override = { en = "[Issue 213] [verify-fix] [diag] Max active trash enemies" },
    max_grunts_override_tooltip = {
        en = "Sets how many basic trash enemies can be alive at the same time (the normal cap is about 90). Raising it packs the map with more enemies at once for an Onslaught-style feel; the range is 10 to 360.",
    },

    spawn_pace_multiplier = { en = "[working] Spawn rate multiplier" },
    spawn_pace_multiplier_tooltip = {
        en = "Multiplies how often new enemies spawn. 1 is normal, 2 is roughly twice as many spawn waves per minute, 0.5 is half, and the range is 0 to 5.",
    },

    -- ============================================================
    -- Spawn Scaling
    -- ============================================================
    spawn_scaling_group = { en = "[working] Spawn Scaling" },

    event_size_multiplier = { en = "[working] Event horde size (multiplier)" },
    event_size_multiplier_tooltip = {
        en = "Multiplies how many enemies come in event hordes, the scripted ambushes and bell-summoned waves that make up most mission hordes. 0 means none, 1 is normal, and 5 is the capped maximum.",
    },

    horde_size_multiplier = { en = "[working] Paced horde size (multiplier)" },
    horde_size_multiplier_tooltip = {
        en = "Multiplies how many enemies come in each paced horde, the regular waves between big events. 0 means none, 1 is normal, and 5 is the capped maximum since paced hordes get unstable past that.",
    },

    patrol_size_multiplier = { en = "[working] Patrol size (multiplier)" },
    patrol_size_multiplier_tooltip = {
        en = "Multiplies the size of marching patrols, the organized squads such as Stormvermin, Chaos Warrior, or Beastmen patrols. 0 means no patrols, 1 is normal, and 15 is the maximum; very large patrols may run into the game's movement limits.",
    },

    roaming_size_multiplier = { en = "[working] Roaming enemy density (multiplier)" },
    roaming_size_multiplier_tooltip = {
        en = "Multiplies how many wandering enemies roam the level. 0 means none, 1 is normal, and 15 is the maximum; very high values mostly add loose ambient enemies rather than larger packs.",
    },

    -- ============================================================
    -- Stormvermin Champion Pool
    -- ============================================================
    elite_swap_group                = { en = "[working] Stormvermin Champion Pool" },
    champion_in_elite_pool          = { en = "[working] Add Stormvermin Champion to roaming elites" },
    champion_in_elite_pool_tooltip  = { en = "Lets roaming Skaven Stormvermin elites be replaced by the Stormvermin Champion at the chance below; only loose wandering elites are affected, not horde or event spawns. Host only. Retunes the Champion into a tough mini-boss with a health bar and boss music, affecting every Champion (including its rare normal appearances) while on; restored when off." },
    champion_elite_chance           = { en = "[working] Champion spawn chance (%%)" },
    champion_elite_chance_tooltip   = { en = "The percent chance that a roaming Skaven elite is replaced by the Stormvermin Champion. 0 never happens and 100 replaces every roaming elite; kept low so the Champion stays a rare mini-boss." },

    -- ============================================================
    -- Big Rebalance (ON ICE) — the br_* widget block in enemy_tweaker_data.lua
    -- is commented out (bt retired 2026-06-08), so none of these keys render.
    -- They are retained (not stripped) so the block can be restored intact; the
    -- technical engine terms are the content, so they are left as-is.
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

}

-- ============================================================
-- Dynamic entries: breed-swap option labels + per-difficulty
-- group headers and per-special widgets. Appended by key, so table order
-- here does not affect VMF resolution.
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

-- Per-difficulty entries (Special Spawns). Group headers stay Title Case;
-- the count-cap labels are sentence case.
for _, diff in ipairs(B.DIFFICULTIES) do
    local k = diff.key

    loc["et_diff_" .. k .. "_group"]            = { en = "[working] " .. diff.label }
    loc[B.setting_key(k, "weights_group")]      = { en = "[working] Spawn Weights" }
    loc[B.setting_key(k, "disabled_group")]     = { en = "[working] Disabled Specials" }
    loc[B.setting_key(k, "max_total")]          = { en = "[working] Max specials active" }
    loc[B.setting_key(k, "max_total_tooltip")]  = {
        en = string.format("The most specials that can be alive at once on %s (normally %d).", diff.label, diff.max_total),
    }
    loc[B.setting_key(k, "max_same")]           = { en = "[working] Max specials of same type" }
    loc[B.setting_key(k, "max_same_tooltip")]   = {
        en = string.format("The most specials of the same type that can be alive at once on %s (normally %d).", diff.label, diff.max_same),
    }

    for _, breed in ipairs(SPECIALS) do
        local label = B.breed_label(breed)
        loc[B.setting_key(k, "weight", breed)]            = { en = "[working] " .. label }
        loc[B.setting_key(k, "weight", breed) .. "_tooltip"] = {
            en = string.format("How likely %s is to be chosen as a special on %s. 0 means never; the default of 1 is the normal even chance.", label, diff.label),
        }
        loc[B.setting_key(k, "disabled", breed)]          = { en = "[working] " .. label }
        loc[B.setting_key(k, "disabled", breed) .. "_tooltip"] = {
            en = string.format("Prevents %s from spawning as a special on %s.", label, diff.label),
        }
    end
end

return loc
