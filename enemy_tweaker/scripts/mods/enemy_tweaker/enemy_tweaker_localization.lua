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
        en = "Replace horde compositions with a preset. 'Faction' presets force a single race; 'Theme' presets are content overhauls (elites only, skeleton swarms, etc.).",
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
        en = "Scale paced-horde enemy count. 0 = no paced hordes, 1 = vanilla, 2 = double, 15 = fifteen times normal. Applies to HordeCompositionsPacing entries (small/medium/large/huge/mini_patrol per faction) — the rhythm-driven hordes between events. Independent of the Horde Preset dropdown.",
    },

    event_size_multiplier = { en = "Event Horde Size (multiplier)" },
    event_size_multiplier_tooltip = {
        en = "Scale terror-event horde enemy count (the majority of visible adventure-mission hordes — bell events, ambushes, scripted spawns). 0 = no event hordes, 1 = vanilla, 15 = fifteen times normal. Applied at HordeSpawner spawn time over the resolved per-breed amount; respects per-breed max_active_enemies engine caps (excess swaps down to cheaper breeds rather than crashing).",
    },

    roaming_size_multiplier = { en = "Roaming Enemy Density (multiplier)" },
    roaming_size_multiplier_tooltip = {
        en = "Scale roaming-enemy density across both engine layers. 0 = no roaming, 1 = vanilla, 15 = fifteen times normal. TWO LAYERS: (1) per-interest-point pack size (SizeOfInterestPoint) — snapped to the BreedPacksBySize canonical set {1,2,3,4,6,8}, so this layer plateaus at 8 units/IP past ~2.7x; (2) ambient density (SpawnZoneBaker.spawn_amount_rats) — uncapped, scales linearly to the full slider range. v0.7.4-dev adopts SpawnTweaks's global table.clone skip-metatable shim, which is the trick that lets either mod scale to 15x on large Deus levels without OOMing Lua's heap (vanilla's _generate_pack_members deep-clones pack data per placement; stripping metatable reachability from the clones cuts per-clone heap footprint by ~2-3x).",
    },

    patrol_size_multiplier = { en = "Patrol Size (multiplier)" },
    patrol_size_multiplier_tooltip = {
        en = "Scale formed-patrol group size (stormvermin patrols, chaos warrior patrols, beastmen patrols — the marching squads with a leader). 0 = no patrols, 1 = vanilla, 15 = fifteen times normal. Replicates formation rows in AIGroupSystem.create_formation_data. Past ~10x may exceed navmesh/network limits; oversize patrols are logged via Debug Logging.",
    },

    -- ============================================================
    -- SPAWN PACING (v0.7.0-dev — SpawnTweaks parity pass)
    -- ============================================================
    spawn_pacing_group = { en = "Spawn Pacing (frequency + caps)" },

    max_grunts_override = { en = "Max Active Trash Enemies" },
    max_grunts_override_tooltip = {
        en = "Override RecycleSettings.max_grunts — the global cap on how many trash-tier enemies can be alive at once (slaves, clanrats, marauders, fanatics; specials/elites/bosses have their own caps). Vanilla baseline ~90. Raising this lets the engine keep MORE enemies alive concurrently, which is the real lever behind 'Onslaught-feel' density. Range 10–360. Save/restored around ConflictDirector.update so other systems still see vanilla outside the spawn pass.",
    },

    spawn_pace_multiplier = { en = "Spawn Rate Multiplier" },
    spawn_pace_multiplier_tooltip = {
        en = "Scale spawn FREQUENCY by tweaking the threat-pacing system. 1.0 = vanilla, 2.0 = roughly twice as many spawn events per minute, 0.5 = half. Mechanism: multiplies ConflictDirector.threat_value and Pacing.total_intensity / player_intensity at apply time. Higher values trip the engine's delay_horde / delay_mini_patrol / delay_specials thresholds sooner, so paced systems fire more often. Range 0–5. SpawnTweaks calls this 'THREAT_MULTIPLIER' with inverted semantics (lower = harder); ET uses the intuitive direction (higher = more spawns).",
    },

    horde_grunt_push_threshold = { en = "Horde Push Threshold (alive grunts)" },
    horde_grunt_push_threshold_tooltip = {
        en = "Override RecycleSettings.push_horde_if_num_alive_grunts_above — the engine pushes a fresh horde when fewer than this many trash are alive. Vanilla 60. LOWER = hordes pushed more often (e.g. 10 = near-constant hordes once existing ones die down). Range 10–240.",
    },

    horde_frequency_min = { en = "Horde Frequency Min (seconds)" },
    horde_frequency_min_tooltip = {
        en = "Override CurrentPacing.horde_frequency[1] — minimum seconds between paced hordes. Vanilla ~50s. Lower = hordes fire faster. Range 5–200. Engine clamps so max ≥ min automatically.",
    },

    horde_frequency_max = { en = "Horde Frequency Max (seconds)" },
    horde_frequency_max_tooltip = {
        en = "Override CurrentPacing.horde_frequency[2] — maximum seconds between paced hordes. Vanilla ~100s. The engine picks a random value in [min, max] for each cycle. Range 5–200.",
    },

    ambients_ignore_threat = { en = "Ambient Spawns Ignore Threat" },
    ambients_ignore_threat_tooltip = {
        en = "When ON, ambient patrols (mini_patrol) spawn even during high combat intensity. Mechanism: sets CurrentPacing.mini_patrol.only_spawn_below_intensity = infinity and RecycleSettings.max_grunts = infinity for the duration of ConflictDirector.update_mini_patrol, then restores. Vanilla blocks ambient spawns while threat is hot, which makes high Roaming-Density values feel weaker than the slider implies — toggle this ON for the slider to actually deliver during combat.",
    },

    -- ============================================================
    -- BEASTMAN BANNER (v0.7.2-dev)
    -- ============================================================
    banner_group = { en = "Beastman Banner" },

    banner_bearer_staggerable_during_placement = { en = "Bearer Staggerable During Placement" },
    banner_bearer_staggerable_during_placement_tooltip = {
        en = "When ON, the beastmen standard-bearer can be staggered (interrupted) while planting the banner. Vanilla makes the bearer stagger-immune for the duration of the place animation (BreedActions.beastmen_standard_bearer.place_standard_stagger_immune.ignore_staggers all true). Toggle flips them all to false so the place can be interrupted by a well-timed hit. Backed up at boot; reverted cleanly when off.",
    },

    banner_breakable_by_ranged = { en = "Banner Takes Ranged Damage" },
    banner_breakable_by_ranged_tooltip = {
        en = "When ON, the planted beastmen banner takes damage from ranged weapons. Vanilla only accepts melee light/heavy attacks plus a tiny whitelist (grenades, torch, Questing Knight skill, deus relic). This widens the allow-set to also include attack types 'projectile', 'instant_projectile', and 'heavy_instant_projectile' so longbows, handguns, crossbows, blunderbusses, throwing axes, and any other ranged weapon can also destroy it. Hook on BeastmenStandardHealthExtension.add_damage; no vanilla rewrite, just an additional accept condition.",
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
        en = "Difficulty key for horde compositions and HordeSettings overrides. Player/enemy stats unaffected.",
    },
    mimic_specials         = { en = "Specials Difficulty" },
    mimic_specials_tooltip = {
        en = "Difficulty key for SpecialsSettings: max alive, pool, spawn frequency. Player/enemy stats unaffected.",
    },
    mimic_pacing         = { en = "Horde Frequency Difficulty" },
    mimic_pacing_tooltip = {
        en = "Difficulty key for PacingSettings: horde frequency, intensity thresholds, relax timing.",
    },
    mimic_pack_spawning         = { en = "Roaming Density Difficulty" },
    mimic_pack_spawning_tooltip = {
        en = "Difficulty key for PackSpawningSettings: roaming/ambient density on the main path.",
    },
    mimic_intensity         = { en = "Intensity Difficulty" },
    mimic_intensity_tooltip = {
        en = "Difficulty key for IntensitySettings: how fast intensity accumulates and decays.",
    },
    mimic_boss         = { en = "Boss/Event Difficulty" },
    mimic_boss_tooltip = {
        en = "Difficulty key for BossSettings: monster spawn timing and frequency.",
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
        en = "Replace Skaven paced hordes with this faction's. Paced/blob only — scripted/terror-event hordes stay vanilla.",
    },
    faction_swap_chaos            = { en = "Replace Chaos Hordes With" },
    faction_swap_chaos_tooltip    = {
        en = "Replace Chaos paced hordes with this faction's. Useful for missions that switch to Chaos in later zones (Athel Yenlui, Hunger in the Dark).",
    },
    faction_swap_beastmen         = { en = "Replace Beastmen Hordes With" },
    faction_swap_beastmen_tooltip = {
        en = "Replace Beastmen paced hordes with this faction's.",
    },

    -- ============================================================
    -- BREED SUBSTITUTION
    -- ============================================================
    breed_swap_group        = { en = "Breed Substitution" },
    breed_swap_off          = { en = "Off" },
    breed_swap_from         = { en = "Replace This Breed" },
    breed_swap_from_tooltip = { en = "Every enemy of this breed in hordes will be replaced with the target breed below." },
    breed_swap_to           = { en = "With This Breed" },
    breed_swap_to_tooltip   = { en = "The replacement breed. Must be different from the source breed." },

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

    -- Universal Debug Logging toggle (PROJECT_STANDARDS.md § 3.6).
    enable_debug_logging         = { en = "Debug Logging" },
    enable_debug_logging_tooltip = { en = "Emit detailed diagnostic logs to %%APPDATA%%\\Fatshark\\Vermintide 2\\console_logs\\. Increases log volume; enable when investigating a bug, then disable." },
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
            en = string.format("%s — %s", g.label, B.breed_label(breed)),
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
        en = string.format("Max specials alive at once on %s. Vanilla = %d.", diff.label, diff.max_total),
    }
    loc[B.setting_key(k, "max_same")]           = { en = "Max Specials of Same Type" }
    loc[B.setting_key(k, "max_same_tooltip")]   = {
        en = string.format("Max specials of the same breed alive at once on %s. Vanilla = %d.", diff.label, diff.max_same),
    }

    for _, breed in ipairs(SPECIALS) do
        local label = B.breed_label(breed)
        loc[B.setting_key(k, "weight", breed)]            = { en = label }
        loc[B.setting_key(k, "weight", breed) .. "_tooltip"] = {
            en = string.format("Spawn weight for %s on %s. 0 = never. Default 1 (uniform random, vanilla equivalent).", label, diff.label),
        }
        loc[B.setting_key(k, "disabled", breed)]          = { en = label }
        loc[B.setting_key(k, "disabled", breed) .. "_tooltip"] = {
            en = string.format("Prevent %s from spawning as a special on %s.", label, diff.label),
        }
    end
end

return loc
