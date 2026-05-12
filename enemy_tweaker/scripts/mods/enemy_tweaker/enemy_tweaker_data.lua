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

local function _build_breed_options()
    local out = { { text = "breed_swap_off", value = "off" } }
    local groups = {
        { list = B.SKAVEN }, { list = B.CHAOS },
        { list = B.BEASTMEN }, { list = B.SKELETON },
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

local _BREED_OPTIONS = _build_breed_options()

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
                            { text = "preset_necro_skeletons",   value = "necro_skeletons" },
                            { text = "preset_ghost_skeletons",   value = "ghost_skeletons" },
                            { text = "preset_skeleton_mix",      value = "skeleton_mix" },
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
                    _build_special_spawns_block(),
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
                        options       = _BREED_OPTIONS,
                    },
                    {
                        setting_id    = "breed_swap_to",
                        type          = "dropdown",
                        default_value = "off",
                        tooltip       = "breed_swap_to_tooltip",
                        options       = _BREED_OPTIONS,
                    },
                },
            },
        },
    },
}
