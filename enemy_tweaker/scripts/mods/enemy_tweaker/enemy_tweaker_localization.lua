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
