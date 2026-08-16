local mod = get_mod("enemy_tweaker")
local B = require("scripts/mods/enemy_tweaker/enemy_tweaker_breeds")

-- All widget text/tooltip values are raw localization keys (strings) — VMF
-- resolves them at render time. NEVER call mod:localize() in this file: it
-- runs during data-file load when the loc table may not be ready, returning
-- "<key>" which then gets used as the literal widget label.

mod._SPECIALS    = B.collect_specials()
mod._DIFFICULTIES = B.DIFFICULTIES
mod._setting_key = B.setting_key

-- ============================================================
-- Breed substitution dropdown options
-- ============================================================

-- IMPORTANT: VMF's options.lua localize_dropdown_data mutates each option's
-- `text` field in place (`option.text = mod:localize(option.text)`). If two
-- dropdowns share the same options table reference, the first pass converts
-- "mimic_opt_off" → "Match (vanilla)"; the second pass then tries to localize
-- "Match (vanilla)" (which isn't a loc key) and gets the missing-key fallback
-- "<Match (vanilla)>". Each additional sharing dropdown wraps another pair of
-- angle brackets, giving "<<<...>>>". Every dropdown MUST get its own freshly-
-- built options table. The factory functions below ensure that.

local function _build_breed_options()
    local out = { { text = "breed_swap_off", value = "off" } }
    local groups = {
        { list = B.SKAVEN }, { list = B.CHAOS }, { list = B.BEASTMEN },
    }
    for _, g in ipairs(groups) do
        for _, breed_name in ipairs(g.list) do
            out[#out + 1] = {
                text  = B.breed_swap_option_key(breed_name),
                value = breed_name,
            }
        end
    end
    return out
end

local function _faction_swap_options()
    return {
        { text = "faction_opt_off",      value = "off" },
        { text = "faction_opt_skaven",   value = "skaven" },
        { text = "faction_opt_chaos",    value = "chaos" },
        { text = "faction_opt_beastmen", value = "beastmen" },
    }
end

local function _mimic_options()
    return {
        { text = "mimic_opt_off",         value = "off" },
        { text = "mimic_opt_normal",      value = "normal" },
        { text = "mimic_opt_hard",        value = "hard" },
        { text = "mimic_opt_harder",      value = "harder" },
        { text = "mimic_opt_hardest",     value = "hardest" },
        { text = "mimic_opt_cataclysm",   value = "cataclysm" },
        { text = "mimic_opt_cataclysm_2", value = "cataclysm_2" },
        { text = "mimic_opt_cataclysm_3", value = "cataclysm_3" },
    }
end

local function _mimic_dropdown(setting_id, tooltip_id)
    return {
        setting_id    = setting_id,
        type          = "dropdown",
        default_value = "off",
        tooltip       = tooltip_id,
        options       = _mimic_options(),
    }
end

local function _personal_difficulty_options()
    return {
        { text = "personal_difficulty_auto",        value = "off" },
        { text = "mimic_opt_normal",                value = "normal" },
        { text = "mimic_opt_hard",                  value = "hard" },
        { text = "mimic_opt_harder",                value = "harder" },
        { text = "mimic_opt_hardest",               value = "hardest" },
        { text = "mimic_opt_cataclysm",             value = "cataclysm" },
        { text = "mimic_opt_cataclysm_2",           value = "cataclysm_2" },
        { text = "mimic_opt_cataclysm_3",           value = "cataclysm_3" },
    }
end

-- ============================================================
-- Per-difficulty Specials widget builders
-- ============================================================

local function _build_diff_weights(diff_key)
    local out = {}
    for _, breed_name in ipairs(mod._SPECIALS) do
        out[#out + 1] = {
            setting_id    = B.setting_key(diff_key, "weight", breed_name),
            type          = "numeric",
            tooltip       = B.setting_key(diff_key, "weight", breed_name) .. "_tooltip",
            range         = { 0, 20 },
            default_value = 1,
        }
    end
    return out
end

local function _build_diff_disabled(diff_key)
    local out = {}
    for _, breed_name in ipairs(mod._SPECIALS) do
        out[#out + 1] = {
            setting_id    = B.setting_key(diff_key, "disabled", breed_name),
            type          = "checkbox",
            tooltip       = B.setting_key(diff_key, "disabled", breed_name) .. "_tooltip",
            default_value = false,
        }
    end
    return out
end

local function _build_difficulty_block(diff)
    return {
        setting_id = "et_diff_" .. diff.key .. "_group",
        type       = "group",
        -- Deliberate order (NOT A→Z): the two active-count caps come first,
        -- then the per-special Spawn Weights and Disabled Specials sub-lists.
        sub_widgets = {
            {
                setting_id    = B.setting_key(diff.key, "max_total"),
                type          = "numeric",
                tooltip       = B.setting_key(diff.key, "max_total_tooltip"),
                range         = { 0, 20 },
                default_value = diff.max_total,
            },
            {
                setting_id    = B.setting_key(diff.key, "max_same"),
                type          = "numeric",
                tooltip       = B.setting_key(diff.key, "max_same_tooltip"),
                range         = { 0, 20 },
                default_value = diff.max_same,
            },
            {
                setting_id  = B.setting_key(diff.key, "weights_group"),
                type        = "group",
                sub_widgets = _build_diff_weights(diff.key),
            },
            {
                setting_id  = B.setting_key(diff.key, "disabled_group"),
                type        = "group",
                sub_widgets = _build_diff_disabled(diff.key),
            },
        },
    }
end

local function _build_special_spawns_block()
    local subs = {}
    -- Deliberate order (NOT A→Z): per-difficulty blocks follow the difficulty
    -- ladder (Recruit → Cataclysm 3), matching B.DIFFICULTIES.
    for _, diff in ipairs(B.DIFFICULTIES) do
        subs[#subs + 1] = _build_difficulty_block(diff)
    end
    return {
        setting_id  = "special_spawns_group",
        type        = "group",
        sub_widgets = subs,
    }
end

-- ============================================================
-- Enemy Stats widget builders
-- ============================================================

-- #369 restructure (user direction): the per-difficulty enemy health
-- multipliers moved OUT of the Special Spawns per-difficulty blocks into
-- this dedicated top-level Enemy Stats category — the planned home for
-- future per-stat adjustments (mass/stagger resistance, damage, speed).
-- setting_ids are UNCHANGED (et_diff_<key>_health_multiplier) so persisted
-- values survive the move; _et_health_multiplier.lua reads the same keys.
local function _build_enemy_stats_health_widgets()
    local out = {}
    -- Deliberate order (NOT A→Z): one slider per difficulty, following the
    -- difficulty ladder (Recruit → Cataclysm 3), matching B.DIFFICULTIES.
    for _, diff in ipairs(B.DIFFICULTIES) do
        out[#out + 1] = {
            setting_id      = B.setting_key(diff.key, "health_multiplier"),
            type            = "numeric",
            tooltip         = B.setting_key(diff.key, "health_multiplier") .. "_tooltip",
            range           = { 0.1, 5.0 },
            default_value   = 1.0,
            decimals_number = 1,
        }
    end
    return out
end

local function _build_enemy_stats_block()
    return {
        setting_id  = "enemy_stats_group",
        type        = "group",
        sub_widgets = {
            {
                setting_id  = "enemy_stats_health_group",
                type        = "group",
                sub_widgets = _build_enemy_stats_health_widgets(),
            },
        },
    }
end

return {
    name         = "Tweaker: Enemies",
    -- Root-level description is the ONE field VMF uses verbatim (get_description, no
    -- re-localize), so it must be localized eagerly here - unlike every widget field below.
    description  = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        -- Top-level entries are ordered A→Z by their English display label
        -- (see enemy_tweaker_localization.lua). Order within each group is also
        -- A→Z, except the deliberate-order exemptions commented at each site:
        --   • Special Spawns per-difficulty blocks follow the difficulty ladder.
        --   • Faction / breed substitution follows the mod's Skaven → Chaos →
        --     Beastmen faction order.
        --   • min/max pairs read min-before-max.
        --   • per-difficulty specials blocks lead with the count caps.
        widgets = {

            -- ============================================================
            -- BEASTMAN BANNER (v0.7.2-dev)
            -- Toggles for the beastmen standard-bearer's planted banner:
            --   banner_bearer_staggerable_during_placement
            --     Patches BreedActions.beastmen_standard_bearer
            --     .place_standard_stagger_immune.ignore_staggers from
            --     {true, true, true, true, true, true} to all-false so the
            --     bearer can be staggered out of the place animation.
            --   banner_breakable_by_ranged
            --     Hooks BeastmenStandardHealthExtension.add_damage and
            --     extends the can_damage_banner whitelist to include
            --     attack_type "projectile" / "instant_projectile" /
            --     "heavy_instant_projectile" (vanilla only accepts melee
            --     light/heavy plus a small explosive/torch whitelist).
            -- All default false (vanilla behavior preserved).
            {
                setting_id  = "banner_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "banner_breakable_by_ranged",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "banner_breakable_by_ranged_tooltip",
                    },
                    {
                        setting_id    = "banner_bearer_staggerable_during_placement",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "banner_bearer_staggerable_during_placement_tooltip",
                    },
                    {
                        setting_id    = "banner_no_camera_jerk_on_placement",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "banner_no_camera_jerk_on_placement_tooltip",
                    },
                },
            },

            -- ============================================================
            -- BOSS BALANCE (v0.7.34-dev — GitHub issue #450)
            -- Per-boss curated balance toggles, all default false (vanilla).
            -- Stat toggles are revert-safe data mutations in
            -- _et_boss_balance.lua. Runtime behaviors share the consolidated
            -- post-spawn/lifecycle owners in _et_boss_grudge.lua and
            -- _et_boss_behavior.lua. Grouped by boss (deliberate issue order).
            -- ============================================================
            {
                setting_id  = "boss_balance_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "boss_bal_halescourge_health",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "boss_bal_halescourge_health_tooltip",
                    },
                    {
                        setting_id    = "boss_behavior_halescourge_monster",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "boss_behavior_halescourge_monster_tooltip",
                    },
                    {
                        setting_id    = "boss_bal_skarrik_health",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "boss_bal_skarrik_health_tooltip",
                    },
                    {
                        setting_id    = "boss_behavior_skarrik_ranged_dr",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "boss_behavior_skarrik_ranged_dr_tooltip",
                    },
                    {
                        setting_id    = "boss_grudge_skarrik_berserk",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "boss_grudge_skarrik_berserk_tooltip",
                    },
                    {
                        setting_id    = "boss_bal_bodvarr_health",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "boss_bal_bodvarr_health_tooltip",
                    },
                    {
                        setting_id    = "boss_grudge_bodvarr_crippling",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "boss_grudge_bodvarr_crippling_tooltip",
                    },
                    {
                        setting_id    = "boss_behavior_deathrattler_tracking",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "boss_behavior_deathrattler_tracking_tooltip",
                    },
                    {
                        setting_id    = "boss_bal_rasknitt_health",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "boss_bal_rasknitt_health_tooltip",
                    },
                    {
                        setting_id    = "boss_bal_rasknitt_lightning",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "boss_bal_rasknitt_lightning_tooltip",
                    },
                    {
                        setting_id    = "boss_bal_nurgloth_health",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "boss_bal_nurgloth_health_tooltip",
                    },
                    {
                        setting_id    = "boss_bal_nurgloth_armor",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "boss_bal_nurgloth_armor_tooltip",
                    },
                },
            },

            -- ============================================================
            -- BOSS MECHANIC TWEAKS (received from general_tweaker_dev
            -- 2026-06-20 — was gt_fly_disable_mult; renamed et_fly_disable_mult)
            -- ============================================================
            {
                setting_id  = "boss_tweaks_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id      = "et_fly_disable_mult",
                        type            = "numeric",
                        default_value   = 1.0,
                        range           = { 0.0, 3.0 },
                        decimals_number = 2,
                        tooltip         = "et_fly_disable_mult_tooltip",
                    },
                },
            },

            -- ============================================================
            -- BREED SUBSTITUTION
            -- Deliberate order (from → to): pick the breed to replace, then
            -- its replacement.
            -- ============================================================
            {
                setting_id = "breed_swap_group",
                type       = "group",
                sub_widgets = {
                    {
                        setting_id    = "breed_swap_from",
                        type          = "dropdown",
                        default_value = "off",
                        tooltip       = "breed_swap_from_tooltip",
                        options       = _build_breed_options(),
                    },
                    {
                        setting_id    = "breed_swap_to",
                        type          = "dropdown",
                        default_value = "off",
                        tooltip       = "breed_swap_to_tooltip",
                        options       = _build_breed_options(),
                    },
                },
            },

            -- ============================================================
            -- ENEMY SPAWNS (per-difficulty controls)
            -- ============================================================
            {
                setting_id  = "enemy_spawns_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "personal_difficulty",
                        type          = "dropdown",
                        default_value = "off",
                        tooltip       = "personal_difficulty_tooltip",
                        options       = _personal_difficulty_options(),
                    },
                    -- Difficulty Mimic: override the difficulty key used to
                    -- patch each Current* settings table independently of the
                    -- player's actual difficulty. Lets you play on Champion
                    -- stats with Cata-1's horde sizes, special frequency, etc.
                    {
                        setting_id  = "difficulty_mimic_group",
                        type        = "group",
                        sub_widgets = {
                            _mimic_dropdown("mimic_boss",          "mimic_boss_tooltip"),
                            _mimic_dropdown("mimic_horde",         "mimic_horde_tooltip"),
                            _mimic_dropdown("mimic_pacing",        "mimic_pacing_tooltip"),
                            _mimic_dropdown("mimic_intensity",     "mimic_intensity_tooltip"),
                            _mimic_dropdown("mimic_pack_spawning", "mimic_pack_spawning_tooltip"),
                            _mimic_dropdown("mimic_specials",      "mimic_specials_tooltip"),
                        },
                    },
                    _build_special_spawns_block(),
                },
            },

            -- ============================================================
            -- ENEMY STATS (#369 restructure)
            -- Top-level home for per-difficulty enemy stat adjustments.
            -- Currently: Health Multipliers (moved from the Special Spawns
            -- per-difficulty blocks; setting_ids unchanged so saved values
            -- carry over). Planned: mass (stagger resistance), damage, speed.
            -- ============================================================
            _build_enemy_stats_block(),

            -- ============================================================
            -- FACTION SUBSTITUTION (per-faction horde slot swap)
            -- VT2 missions activate one ConflictDirector at start and may
            -- switch to another at zone boundaries (Athel Yenlui = skaven →
            -- chaos, etc.). Each director keys to a faction's comp family.
            -- These dropdowns rewrite the active CurrentHordeSettings
            -- *_composition fields so every paced horde from a given faction
            -- becomes another faction's instead. Set Skaven → Beastmen to
            -- get Beastmen hordes in missions that would normally spawn
            -- Skaven, etc.
            -- Deliberate order (NOT A→Z): Skaven, Chaos, Beastmen — the mod's
            -- established faction order.
            -- ============================================================
            {
                setting_id = "faction_swap_group",
                type       = "group",
                sub_widgets = {
                    {
                        setting_id    = "faction_swap_skaven",
                        type          = "dropdown",
                        default_value = "off",
                        tooltip       = "faction_swap_skaven_tooltip",
                        options       = _faction_swap_options(),
                    },
                    {
                        setting_id    = "faction_swap_chaos",
                        type          = "dropdown",
                        default_value = "off",
                        tooltip       = "faction_swap_chaos_tooltip",
                        options       = _faction_swap_options(),
                    },
                    {
                        setting_id    = "faction_swap_beastmen",
                        type          = "dropdown",
                        default_value = "off",
                        tooltip       = "faction_swap_beastmen_tooltip",
                        options       = _faction_swap_options(),
                    },
                },
            },

            -- ============================================================
            -- HORDE COMPOSITION
            -- ============================================================
            {
                setting_id = "horde_group",
                type       = "group",
                sub_widgets = {
                    {
                        setting_id    = "horde_preset",
                        type          = "dropdown",
                        default_value = "off",
                        tooltip       = "horde_preset_tooltip",
                        options = {
                            { text = "preset_off",               value = "off" },
                            { text = "preset_skaven_only",       value = "skaven_only" },
                            { text = "preset_chaos_only",        value = "chaos_only" },
                            { text = "preset_beastmen_invasion", value = "beastmen_invasion" },
                            { text = "preset_mixed_factions",    value = "mixed_factions" },
                            { text = "preset_all_elites",        value = "all_elites" },
                        },
                    },
                },
            },

            -- ============================================================
            -- SKAVEN WARLORD MONSTER POOL (v0.7.12-dev; #324 retarget v0.7.27-dev)
            -- Swap target is the mod-added et_skaven_warlord breed (see
            -- _et_skaven_warlord_breed.lua); setting_ids kept unchanged so
            -- saved settings carry over. warlord_monster_chance is nested as
            -- a sub_widget of the warlord_in_monster_pool master checkbox:
            -- enemy_tweaker.lua reads the chance ONLY when the checkbox is
            -- on, so VMF auto-hides the slider while the feature is off.
            -- ============================================================
            {
                setting_id  = "monster_swap_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "warlord_in_monster_pool",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "warlord_in_monster_pool_tooltip",
                        sub_widgets   = {
                            {
                                setting_id      = "warlord_monster_chance",
                                type            = "numeric",
                                default_value   = 25,
                                range           = { 0, 100 },
                                decimals_number = 0,
                                tooltip         = "warlord_monster_chance_tooltip",
                            },
                        },
                    },
                },
            },

            -- ============================================================
            -- SPAWN PACING (added v0.7.0-dev — SpawnTweaks parity pass)
            -- These hit different engine layers than the four spawn-scaling
            -- sliders:
            --   max_grunts_override          -> RecycleSettings.max_grunts
            --                                   (concurrent-alive trash cap;
            --                                   vanilla baseline ~90)
            --   spawn_pace_multiplier        -> ConflictDirector.threat_value
            --                                   + Pacing.total_intensity (>1 =
            --                                   spawn-delay thresholds trip
            --                                   sooner = MORE FREQUENT spawns)
            --   horde_grunt_push_threshold   -> RecycleSettings
            --                                   .push_horde_if_num_alive_grunts_above
            --                                   (lower = hordes trigger sooner)
            --   horde_frequency_min/max      -> CurrentPacing.horde_frequency
            --                                   (paced-horde interval seconds)
            --   ambients_ignore_threat       -> mini_patrol.only_spawn_below_intensity
            --                                   = math.huge during update
            --                                   (ambient packs spawn even
            --                                   while combat is hot)
            --
            -- SPAWN SCALING controls "how many enemies per spawn event."
            -- SPAWN PACING (here) controls "how often / how many concurrently."
            -- They compound multiplicatively at runtime — use both.
            -- Deliberate sub-order: the horde_frequency min/max pair reads
            -- min-before-max; everything else is A→Z.
            {
                setting_id  = "spawn_pacing_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "ambients_ignore_threat",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "ambients_ignore_threat_tooltip",
                    },
                    {
                        setting_id    = "horde_frequency_min",
                        type          = "numeric",
                        default_value = 50,
                        range         = { 5, 200 },
                        tooltip       = "horde_frequency_min_tooltip",
                    },
                    {
                        setting_id    = "horde_frequency_max",
                        type          = "numeric",
                        default_value = 100,
                        range         = { 5, 200 },
                        tooltip       = "horde_frequency_max_tooltip",
                    },
                    {
                        setting_id    = "horde_grunt_push_threshold",
                        type          = "numeric",
                        default_value = 60,
                        range         = { 10, 240 },
                        tooltip       = "horde_grunt_push_threshold_tooltip",
                    },
                    {
                        setting_id    = "max_grunts_override",
                        type          = "numeric",
                        default_value = 90,
                        range         = { 10, 360 },
                        tooltip       = "max_grunts_override_tooltip",
                    },
                    {
                        setting_id    = "spawn_pace_multiplier",
                        type          = "numeric",
                        default_value = 1,
                        range         = { 0, 5 },
                        decimals_number = 1,
                        tooltip       = "spawn_pace_multiplier_tooltip",
                    },
                },
            },

            -- ============================================================
            -- SPAWN SCALING (added v0.6.0-dev — four multipliers, default
            -- 1.0 = vanilla, 0 = suppress entirely)
            --
            -- The widget type is `numeric` with `decimals_number = 1`, which
            -- gives a slider that snaps to 0.1 increments. mod:get returns a
            -- Lua number.
            --
            -- The four surfaces:
            --   horde_size   — paced hordes (HordeCompositionsPacing, ~25 keys)
            --   event_size   — terror-event hordes (HordeCompositions, ~194 keys
            --                  — majority of visible adventure-mission hordes)
            --   roaming_size — ambient roaming patrols (SizeOfInterestPoint
            --                  pack sizes, drives ConflictDirector.roaming)
            --   patrol_size  — formed marching squads (AIGroupSystem
            --                  create_formation_data formation rows)
            --
            -- All four apply *independently and multiplicatively* on their own
            -- spawn surface so setting one to 0 suppresses only that channel.
            -- See enemy_tweaker.lua for the apply implementations and
            -- /verify_horde_size /verify_event_size /verify_roaming_size
            -- /verify_patrol_size commands for live-state verification.
            {
                setting_id  = "spawn_scaling_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "event_size_multiplier",
                        type          = "numeric",
                        default_value = 1,
                        range         = { 0, 5 },   -- v0.7.11-dev: capped at 5x (event hordes are wave spawns like paced hordes; patrols + roaming still go to 15x)
                        decimals_number = 1,
                        tooltip       = "event_size_multiplier_tooltip",
                    },
                    {
                        setting_id    = "horde_size_multiplier",
                        type          = "numeric",
                        default_value = 1,
                        range         = { 0, 5 },   -- v0.7.11-dev: capped at 5x (paced hordes get overwhelming/unstable past ~5x; patrols + roaming still go to 15x)
                        decimals_number = 1,
                        tooltip       = "horde_size_multiplier_tooltip",
                    },
                    {
                        setting_id    = "patrol_size_multiplier",
                        type          = "numeric",
                        default_value = 1,
                        range         = { 0, 15 },
                        decimals_number = 1,
                        tooltip       = "patrol_size_multiplier_tooltip",
                    },
                    {
                        setting_id    = "roaming_size_multiplier",
                        type          = "numeric",
                        default_value = 1,
                        range         = { 0, 15 },
                        decimals_number = 1,
                        tooltip       = "roaming_size_multiplier_tooltip",
                    },
                },
            },

            -- ============================================================
            -- STORMVERMIN CHAMPION POOL (v0.7.18-dev)
            -- champion_elite_chance is nested as a sub_widget of the
            -- champion_in_elite_pool master checkbox: enemy_tweaker.lua reads
            -- the chance (line ~1280) ONLY when the checkbox is on (gated at
            -- line ~1273), so VMF auto-hides the slider while the feature is off.
            -- ============================================================
            {
                setting_id  = "elite_swap_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "champion_in_elite_pool",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "champion_in_elite_pool_tooltip",
                        sub_widgets   = {
                            {
                                setting_id      = "champion_elite_chance",
                                type            = "numeric",
                                default_value   = 5,
                                range           = { 0, 100 },
                                decimals_number = 0,
                                tooltip         = "champion_elite_chance_tooltip",
                            },
                        },
                    },
                },
            },

--[==[ RETIRED BIG REBALANCE IDENTIFIERS. The br_group menu remains commented out
-- so old settings retain stable br_* keys without exposing inert controls. There
-- is no implementation or registration owner; revival requires a new design.
            {
                setting_id  = "br_group",
                type        = "group",
                sub_widgets = {
                    -- Historical master identifier; intentionally inactive.

                    -- Breed tuning
                    {
                        setting_id  = "br_breed_tuning_group",
                        type        = "group",
                        sub_widgets = {
                            {
                                setting_id    = "br_bloodlust_class_table",
                                type          = "checkbox",
                                default_value = false,
                                tooltip       = "br_bloodlust_class_table_tooltip",
                            },
                            {
                                setting_id    = "br_bloodlust_per_breed_assign",
                                type          = "checkbox",
                                default_value = false,
                                tooltip       = "br_bloodlust_per_breed_assign_tooltip",
                            },
                            {
                                setting_id    = "br_breed_trash_flags",
                                type          = "checkbox",
                                default_value = false,
                                tooltip       = "br_breed_trash_flags_tooltip",
                            },
                            -- Per-breed overrides: empty scaffold per design Q4.
                            -- VMF rejects groups with zero sub_widgets ("must have
                            -- at least 1 sub_widget"), so the placeholder group
                            -- was removed entirely. Re-add this group with real
                            -- sub-widgets when actual per-breed overrides are
                            -- defined; localization keys for it remain so the
                            -- label can be reused.
                        },
                    },

                    -- Stagger / damage math
                    {
                        setting_id  = "br_stagger_damage_group",
                        type        = "group",
                        sub_widgets = {
                            {
                                setting_id    = "br_stagger_ai_rewrite",
                                type          = "checkbox",
                                default_value = false,
                                tooltip       = "br_stagger_ai_rewrite_tooltip",
                            },
                            {
                                setting_id    = "br_calculate_damage_rewrite",
                                type          = "checkbox",
                                default_value = false,
                                tooltip       = "br_calculate_damage_rewrite_tooltip",
                            },
                            {
                                setting_id    = "br_shield_slam_rewrite",
                                type          = "checkbox",
                                default_value = false,
                                tooltip       = "br_shield_slam_rewrite_tooltip",
                            },
                            {
                                setting_id    = "br_unbalance_debuff_infra",
                                type          = "checkbox",
                                default_value = false,
                                tooltip       = "br_unbalance_debuff_infra_tooltip",
                            },
                        },
                    },

                    -- THP from kills
                    {
                        setting_id  = "br_thp_group",
                        type        = "group",
                        sub_widgets = {
                            {
                                setting_id    = "br_thp_regrowth_template",
                                type          = "checkbox",
                                default_value = false,
                                tooltip       = "br_thp_regrowth_template_tooltip",
                            },
                            {
                                setting_id    = "br_thp_vanguard_template",
                                type          = "checkbox",
                                default_value = false,
                                tooltip       = "br_thp_vanguard_template_tooltip",
                            },
                            {
                                setting_id    = "br_thp_reaper_template",
                                type          = "checkbox",
                                default_value = false,
                                tooltip       = "br_thp_reaper_template_tooltip",
                            },
                            {
                                setting_id    = "br_thp_bloodlust_template",
                                type          = "checkbox",
                                default_value = false,
                                tooltip       = "br_thp_bloodlust_template_tooltip",
                            },
                        },
                    },
                },
            },
]==]
        },
    },
}
