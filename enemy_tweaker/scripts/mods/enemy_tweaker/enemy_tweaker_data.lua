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
                    {
                        setting_id    = "horde_size_multiplier",
                        type          = "numeric",
                        default_value = 100,
                        range         = { 25, 300 },
                        tooltip       = "horde_size_multiplier_tooltip",
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
        },
    },
}
