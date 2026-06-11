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
    for _, diff in ipairs(B.DIFFICULTIES) do
        subs[#subs + 1] = _build_difficulty_block(diff)
    end
    return {
        setting_id  = "special_spawns_group",
        type        = "group",
        sub_widgets = subs,
    }
end

return {
    name         = "Tweaker: Enemies",
    description  = "mod_description",
    is_togglable = true,
    options = {
        widgets = {
            -- SPAWN SCALING (added v0.6.0-dev — four multipliers, all 0–15x in
            -- 0.1 steps, default 1.0 = vanilla, 0 = suppress entirely)
            --
            -- The widget type is `numeric` with `decimals_number = 1`, which
            -- gives a slider that snaps to 0.1 increments (verified across 40
            -- in-repo usages — chaos_wastes_tweaker_data.lua:402,
            -- general_tweaker_data.lua:66 etc). mod:get returns a Lua number.
            --
            -- Why these four:
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
                        setting_id    = "horde_size_multiplier",
                        type          = "numeric",
                        default_value = 1,
                        range         = { 0, 15 },
                        decimals_number = 1,
                        tooltip       = "horde_size_multiplier_tooltip",
                    },
                    {
                        setting_id    = "event_size_multiplier",
                        type          = "numeric",
                        default_value = 1,
                        range         = { 0, 15 },
                        decimals_number = 1,
                        tooltip       = "event_size_multiplier_tooltip",
                    },
                    {
                        setting_id    = "roaming_size_multiplier",
                        type          = "numeric",
                        default_value = 1,
                        range         = { 0, 15 },
                        decimals_number = 1,
                        tooltip       = "roaming_size_multiplier_tooltip",
                    },
                    {
                        setting_id    = "patrol_size_multiplier",
                        type          = "numeric",
                        default_value = 1,
                        range         = { 0, 15 },
                        decimals_number = 1,
                        tooltip       = "patrol_size_multiplier_tooltip",
                    },
                },
            },

            -- SPAWN PACING (added v0.7.0-dev — SpawnTweaks parity pass)
            -- These hit different engine layers than the four 0–15x sliders
            -- above:
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
            -- SPAWN SCALING (above) controls "how many enemies per spawn event."
            -- SPAWN PACING (here)  controls "how often / how many concurrently."
            -- They compound multiplicatively at runtime — use both.
            {
                setting_id  = "spawn_pacing_group",
                type        = "group",
                sub_widgets = {
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
                    {
                        setting_id    = "horde_grunt_push_threshold",
                        type          = "numeric",
                        default_value = 60,
                        range         = { 10, 240 },
                        tooltip       = "horde_grunt_push_threshold_tooltip",
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
                        setting_id    = "ambients_ignore_threat",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "ambients_ignore_threat_tooltip",
                    },
                },
            },

            -- HORDES
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

            -- BEASTMAN BANNER (v0.7.2-dev)
            -- Two toggles for the beastmen standard-bearer's planted banner:
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
            -- Both default false (vanilla behavior preserved).
            {
                setting_id  = "banner_group",
                type        = "group",
                sub_widgets = {
                    {
                        setting_id    = "banner_bearer_staggerable_during_placement",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "banner_bearer_staggerable_during_placement_tooltip",
                    },
                    {
                        setting_id    = "banner_breakable_by_ranged",
                        type          = "checkbox",
                        default_value = false,
                        tooltip       = "banner_breakable_by_ranged_tooltip",
                    },
                },
            },

            -- ENEMY SPAWNS (per-difficulty controls)
            {
                setting_id  = "enemy_spawns_group",
                type        = "group",
                sub_widgets = {
                    -- Difficulty Mimic: override the difficulty key used to
                    -- patch each Current* settings table independently of the
                    -- player's actual difficulty. Lets you play on Champion
                    -- stats with Cata-1's horde sizes, special frequency, etc.
                    {
                        setting_id  = "difficulty_mimic_group",
                        type        = "group",
                        sub_widgets = {
                            _mimic_dropdown("mimic_horde",         "mimic_horde_tooltip"),
                            _mimic_dropdown("mimic_specials",      "mimic_specials_tooltip"),
                            _mimic_dropdown("mimic_pacing",        "mimic_pacing_tooltip"),
                            _mimic_dropdown("mimic_pack_spawning", "mimic_pack_spawning_tooltip"),
                            _mimic_dropdown("mimic_intensity",     "mimic_intensity_tooltip"),
                            _mimic_dropdown("mimic_boss",          "mimic_boss_tooltip"),
                        },
                    },
                    _build_special_spawns_block(),
                },
            },

            -- FACTION SUBSTITUTION (per-faction horde slot swap)
            -- VT2 missions activate one ConflictDirector at start and may
            -- switch to another at zone boundaries (Athel Yenlui = skaven →
            -- chaos, etc.). Each director keys to a faction's comp family.
            -- These dropdowns rewrite the active CurrentHordeSettings
            -- *_composition fields so every paced horde from a given faction
            -- becomes another faction's instead. Set Skaven → Beastmen to
            -- get Beastmen hordes in missions that would normally spawn
            -- Skaven, etc.
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

            -- BREED SUBSTITUTION
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

            -- BIG REBALANCE (Core's BR / "Weapon Balance" decompile)
            -- All defaults false; master gates registrations across mods
            -- (same setting_id pattern in wt + ct, OR-merged at runtime).
            -- See enemy_tweaker_big_rebalance.lua + ..._registrations.lua.
            {
                setting_id  = "br_group",
                type        = "group",
                sub_widgets = {
                    -- Master toggle moved to the new `bt` (Tweaker: Buffs) mod.
                    -- Subscribe to it and enable its master to make these et BR
                    -- sub-toggles functional.

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
            -- Universal Debug Logging toggle (PROJECT_STANDARDS.md § 3.6).
            -- Must be at the BOTTOM of the widget tree, top-level (NOT inside
            -- any group), key `enable_debug_logging` verbatim across every mod.
            {
                setting_id    = "enable_debug_logging",
                type          = "checkbox",
                default_value = false,
                tooltip       = "enable_debug_logging_tooltip",
            },
        },
    },
}
