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
    horde_size_multiplier = { en = "Horde Size (%%)" },  -- VMF runs string.format on loc text; literal % must be escaped as %%
    horde_size_multiplier_tooltip = {
        en = "Scale horde enemy count. 100 = normal, 200 = double, 25 = quarter. Applies whether or not a preset is selected.",
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
        en = "Override the difficulty key used to pick horde compositions. Affects which Cataclysm-tier comp lists are selected and the per-difficulty overrides in HordeSettings. Player/enemy stats are unaffected.",
    },
    mimic_specials         = { en = "Specials Difficulty" },
    mimic_specials_tooltip = {
        en = "Override the difficulty key for SpecialsSettings: max specials alive, special spawn pool, spawn frequency. Player/enemy stats are unaffected.",
    },
    mimic_pacing         = { en = "Horde Frequency Difficulty" },
    mimic_pacing_tooltip = {
        en = "Override the difficulty key for PacingSettings: horde frequency, multi-horde frequency, intensity peak thresholds, relax timing. Bigger / more frequent hordes if you mimic a higher difficulty.",
    },
    mimic_pack_spawning         = { en = "Roaming Density Difficulty" },
    mimic_pack_spawning_tooltip = {
        en = "Override the difficulty key for PackSpawningSettings: roaming/ambient enemy density along the main path.",
    },
    mimic_intensity         = { en = "Intensity Difficulty" },
    mimic_intensity_tooltip = {
        en = "Override the difficulty key for IntensitySettings: how fast intensity accumulates and decays from player actions.",
    },
    mimic_boss         = { en = "Boss/Event Difficulty" },
    mimic_boss_tooltip = {
        en = "Override the difficulty key for BossSettings: monster (Rat Ogre, Stormfiend, Troll, Spawn, Chaos Spawn) timing and frequency.",
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
        en = "When a mission's active conflict director would spawn Skaven paced hordes, spawn this faction's hordes instead. Affects paced/blob hordes only — terror-event hordes (scripted ambushes, finale spawns) still use vanilla compositions.",
    },
    faction_swap_chaos            = { en = "Replace Chaos Hordes With" },
    faction_swap_chaos_tooltip    = {
        en = "When a mission's active conflict director would spawn Chaos paced hordes, spawn this faction's hordes instead. Useful for missions that switch to Chaos in later zones (Athel Yenlui, Hunger in the Dark, etc.).",
    },
    faction_swap_beastmen         = { en = "Replace Beastmen Hordes With" },
    faction_swap_beastmen_tooltip = {
        en = "When a mission's active conflict director would spawn Beastmen paced hordes, spawn this faction's hordes instead.",
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
    br_group_tooltip                  = { en = "Opt-in Core's Big Rebalance enemy/stagger/THP changes. All toggles default OFF. REQUIRES the companion mod 'Tweaker: Buffs' (internal id `bt`) installed and its master toggle ON — subscribe to it separately, then restart the game. Without bt's master on, every toggle here is inert." },

    br_breed_tuning_group               = { en = "Breed Tuning" },
    br_bloodlust_class_table            = { en = "BR: bloodlust_health class table" },
    br_bloodlust_class_table_tooltip    = {
        en = "Exposes the Big Rebalance per-class HP table (NewBreedTweaks.bloodlust_health). On its own this does nothing — turn on 'per-breed bloodlust_health assignments' to wire it to actual breeds.",
    },
    br_bloodlust_per_breed_assign       = { en = "BR: per-breed bloodlust_health assignments" },
    br_bloodlust_per_breed_assign_tooltip = {
        en = "Writes the BR class-table value onto each breed's `bloodlust_health` field (45 breeds). Used by the vanilla bloodlust THP buff. Requires the 'class table' toggle above to be on, otherwise the assignment reads nil.",
    },
    br_breed_trash_flags                = { en = "BR: trash flags (horde-rank breeds)" },
    br_breed_trash_flags_tooltip        = {
        en = "Sets `breed.trash = true` on the 11 horde-rank breeds (gor/ungor/ungor_archer, fanatic/marauder/marauder_with_shield, slave/clan_rat/clan_rat_with_shield + dummies). Consumed by the Kerillian maidenguard res-time DR path that Tweaker: Careers ships.",
    },
    br_per_breed_overrides_group        = { en = "Per-breed overrides" },

    br_stagger_damage_group             = { en = "Stagger / Damage math" },
    br_stagger_ai_rewrite               = { en = "BR: stagger_ai rewrite" },
    br_stagger_ai_rewrite_tooltip       = {
        en = "Replaces DamageUtils.stagger_ai with the Big Rebalance body. Adds blackboard stagger-immunity (num_attacks / damage_threshold / time), push/stab/pull angle logic, and an on_stagger proc trigger with weapon-template buff_type. Affects every AI stagger globally.",
    },
    br_calculate_damage_rewrite         = { en = "BR: calculate_damage rewrite" },
    br_calculate_damage_rewrite_tooltip = {
        en = "Replaces DamageUtils.calculate_damage with the Big Rebalance body. Integrates smiter / finesse / mainstay stagger-number rules, the `unbalanced_damage_taken` stat buff, weave scaling, and the max_friendly_damage cap. Affects ALL damage calculations.",
    },
    br_shield_slam_rewrite              = { en = "BR: ActionShieldSlam._hit rewrite" },
    br_shield_slam_rewrite_tooltip      = {
        en = "Replaces ActionShieldSlam._hit with the Big Rebalance body. Reorganizes inner/outer push radii, AOE damage profile dispatch, and level-unit handling. Required for Big Rebalance shield-weapon behavior on ES Sword & Shield, Mace & Shield, and Warrior Priest.",
    },
    br_unbalance_debuff_infra           = { en = "BR: power-modifier debuff (Unbalance infra)" },
    br_unbalance_debuff_infra_tooltip   = {
        en = "Fills in the two BuffTemplate bodies whose effects apply to enemies: `rebaltourn_tank_unbalance` (proc on stagger) and `rebaltourn_tank_unbalance_buff` (the +15%% damage-taken debuff applied to the staggered enemy for 5 s). Tweaker: Careers owns the talent-slot side; this is just the proc infrastructure.",
    },

    br_thp_group                        = { en = "THP from kills (template registration)" },
    br_thp_regrowth_template            = { en = "BR: regrowth THP source" },
    br_thp_regrowth_template_tooltip    = {
        en = "Fills in the rebaltourn_regrowth buff body (1.5 THP on melee crit, 3 THP on melee headshot, 4.5 on crit-headshot, perk: ninja_healing) plus its proc function. Talent slots are set by Tweaker: Careers separately.",
    },
    br_thp_vanguard_template            = { en = "BR: vanguard THP source" },
    br_thp_vanguard_template_tooltip    = {
        en = "Fills in the rebaltourn_vanguard buff body (THP on stagger; flat 0.6 on push; per-weapon caps for wh_2h_billhook and bw_flame_sword; <=5 targets, no corpses; perk: tank_healing) plus its proc function. Talent slots are set by Tweaker: Careers separately.",
    },
    br_thp_reaper_template              = { en = "BR: reaper THP source" },
    br_thp_reaper_template_tooltip      = {
        en = "Fills in the rebaltourn_reaper buff body (THP per damage dealt; multiplier -0.05; bonus 0.25; max_targets 5; perk: linesman_healing). Uses the vanilla heal_damage_targets_on_melee proc — no new function needed.",
    },
    br_thp_bloodlust_template           = { en = "BR: bloodlust THP source" },
    br_thp_bloodlust_template_tooltip   = {
        en = "Fills in the rebaltourn_bloodlust buff body (THP on kill scaled by `breed.bloodlust_health`; multiplier 0.2; perk: smiter_healing). Uses the vanilla heal_percentage_of_enemy_hp_on_melee_kill proc. Inert without 'per-breed bloodlust_health assignments' under Breed Tuning.",
    },
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
