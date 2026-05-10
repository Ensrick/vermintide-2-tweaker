local mod = get_mod("enemy_tweaker")

-- ============================================================
-- Breed display-name resolution
-- ============================================================
-- Use VT2's Localize() to map breed keys → in-game readable names
-- (skaven_storm_vermin → "Stormvermin"). Localize returns "<key>"
-- when the string isn't found, so we fall back to a humanized key.
-- A few names lack VT2 localizations and need explicit overrides.

local _BREED_NAME_OVERRIDES = {
    chaos_corruptor_sorcerer = "Lifeleech Sorcerer",
    chaos_vortex_sorcerer    = "Blightstormer",
    et_necro_skeleton        = "Skeleton Warrior",
    et_necro_skeleton_armored = "Skeleton Warrior (Armored)",
    et_necro_skeleton_dual_wield = "Skeleton Warrior (Dual)",
    et_necro_skeleton_shield = "Skeleton Warrior (Shield)",
    et_ghost_skeleton_hammer = "Ghost Skeleton (Hammer)",
    et_ghost_skeleton_shield = "Ghost Skeleton (Shield)",
}

local function _humanize(breed_name)
    local s = breed_name
        :gsub("^skaven_", "")
        :gsub("^chaos_", "")
        :gsub("^beastmen_", "")
        :gsub("^et_", "")
        :gsub("_with_shield", " (Shield)")
        :gsub("_", " ")
    return (s:gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end))
end

local function _breed_label(breed_name)
    local override = _BREED_NAME_OVERRIDES[breed_name]
    if override then return override end
    local L = rawget(_G, "Localize")
    if L then
        local ok, str = pcall(L, breed_name)
        if ok and type(str) == "string" and str ~= "" and not str:match("^<.+>$") then
            return str
        end
    end
    return _humanize(breed_name)
end

-- ============================================================
-- Breed lists (built at data-file-load time)
-- ============================================================
-- Breeds is normally available by the time _data.lua runs, but guard
-- against early load (returns hard-coded fallback list in that case).

local _SKAVEN_BREEDS = {
    "skaven_slave", "skaven_clan_rat", "skaven_clan_rat_with_shield",
    "skaven_storm_vermin", "skaven_storm_vermin_with_shield",
    "skaven_storm_vermin_commander", "skaven_plague_monk",
    "skaven_gutter_runner", "skaven_pack_master",
    "skaven_poison_wind_globadier", "skaven_ratling_gunner",
    "skaven_warpfire_thrower", "skaven_rat_ogre", "skaven_stormfiend",
}

local _CHAOS_BREEDS = {
    "chaos_fanatic", "chaos_marauder", "chaos_marauder_with_shield",
    "chaos_berzerker", "chaos_raider", "chaos_warrior", "chaos_bulwark",
    "chaos_spawn", "chaos_troll", "chaos_vortex_sorcerer",
    "chaos_corruptor_sorcerer",
}

local _BEASTMEN_BREEDS = {
    "beastmen_ungor", "beastmen_ungor_archer", "beastmen_gor",
    "beastmen_bestigor", "beastmen_minotaur", "beastmen_standard_bearer",
}

local _SKELETON_BREEDS = {
    "et_necro_skeleton", "et_necro_skeleton_armored",
    "et_necro_skeleton_dual_wield", "et_necro_skeleton_shield",
    "et_ghost_skeleton_hammer", "et_ghost_skeleton_shield",
}

-- Specials = breed.special == true. Built from Breeds at runtime when
-- available; otherwise a curated fallback covering vanilla specials.
local _SPECIALS_FALLBACK = {
    "skaven_gutter_runner", "skaven_pack_master",
    "skaven_poison_wind_globadier", "skaven_ratling_gunner",
    "skaven_warpfire_thrower",
    "chaos_vortex_sorcerer", "chaos_corruptor_sorcerer",
}

local function _collect_specials_from_breeds()
    if not rawget(_G, "Breeds") then return _SPECIALS_FALLBACK end
    local out = {}
    for name, b in pairs(Breeds) do
        if type(b) == "table" and b.special and not b.boss
                and not name:find("_tutorial") and not name:find("_dummy") then
            out[#out + 1] = name
        end
    end
    if #out == 0 then return _SPECIALS_FALLBACK end
    table.sort(out)
    return out
end

local _SPECIALS = _collect_specials_from_breeds()
mod._SPECIALS = _SPECIALS  -- expose to enemy_tweaker.lua

local function _build_breed_options()
    local out = { { text = mod:localize("breed_swap_off"), value = "off" } }
    local groups = {
        { label = "Skaven",   list = _SKAVEN_BREEDS },
        { label = "Chaos",    list = _CHAOS_BREEDS },
        { label = "Beastmen", list = _BEASTMEN_BREEDS },
        { label = "Undead",   list = _SKELETON_BREEDS },
    }
    for _, g in ipairs(groups) do
        for _, breed_name in ipairs(g.list) do
            out[#out + 1] = {
                text  = string.format("%s — %s", g.label, _breed_label(breed_name)),
                value = breed_name,
            }
        end
    end
    return out
end

local _BREED_OPTIONS = _build_breed_options()

-- ============================================================
-- Per-difficulty Specials configuration
-- ============================================================
-- Each difficulty gets its own slate of: max_specials_active,
-- max_same_type, per-special spawn weight, per-special disabled toggle.
-- Defaults pulled from VT2's SpecialDifficultyOverrides (conflict_settings.lua)
-- so the UI shows the same values vanilla uses out of the box.

local _DIFFICULTIES = {
    { key = "normal",      label = "Recruit",     max_total = 2, max_same = 1 },
    { key = "hard",        label = "Veteran",     max_total = 3, max_same = 2 },
    { key = "harder",      label = "Champion",    max_total = 3, max_same = 2 },
    { key = "hardest",     label = "Legend",      max_total = 4, max_same = 2 },
    { key = "cataclysm",   label = "Cataclysm 1", max_total = 5, max_same = 3 },
    { key = "cataclysm_2", label = "Cataclysm 2", max_total = 6, max_same = 3 },
    { key = "cataclysm_3", label = "Cataclysm 3", max_total = 6, max_same = 3 },
}
mod._DIFFICULTIES = _DIFFICULTIES  -- expose to enemy_tweaker.lua

local function _setting_key(diff_key, suffix, breed)
    if breed then
        return string.format("et_diff_%s_%s_%s", diff_key, suffix, breed)
    end
    return string.format("et_diff_%s_%s", diff_key, suffix)
end
mod._setting_key = _setting_key

local function _build_diff_weights(diff_key)
    local out = {}
    for _, breed_name in ipairs(_SPECIALS) do
        out[#out + 1] = {
            setting_id    = _setting_key(diff_key, "weight", breed_name),
            type          = "numeric",
            text          = _breed_label(breed_name),
            tooltip       = string.format("Relative spawn weight for %s. 0 = never spawns. Higher = more frequent. Default 1 (uniform random, vanilla behavior).", _breed_label(breed_name)),
            range         = { 0, 20 },
            default_value = 1,
        }
    end
    return out
end

local function _build_diff_disabled(diff_key)
    local out = {}
    for _, breed_name in ipairs(_SPECIALS) do
        out[#out + 1] = {
            setting_id    = _setting_key(diff_key, "disabled", breed_name),
            type          = "checkbox",
            text          = _breed_label(breed_name),
            tooltip       = string.format("Prevent %s from being eligible to spawn as a special on this difficulty.", _breed_label(breed_name)),
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
                setting_id    = _setting_key(diff.key, "max_total"),
                type          = "numeric",
                text          = mod:localize("specials_max_total"),
                tooltip       = string.format("Max specials alive at once on %s. Vanilla = %d.", diff.label, diff.max_total),
                range         = { 0, 20 },
                default_value = diff.max_total,
            },
            {
                setting_id    = _setting_key(diff.key, "max_same"),
                type          = "numeric",
                text          = mod:localize("specials_max_same"),
                tooltip       = string.format("Max specials of the same breed alive at once on %s. Vanilla = %d.", diff.label, diff.max_same),
                range         = { 0, 20 },
                default_value = diff.max_same,
            },
            {
                setting_id  = _setting_key(diff.key, "weights_group"),
                type        = "group",
                sub_widgets = _build_diff_weights(diff.key),
            },
            {
                setting_id  = _setting_key(diff.key, "disabled_group"),
                type        = "group",
                sub_widgets = _build_diff_disabled(diff.key),
            },
        },
    }
end

local function _build_special_spawns_block()
    local subs = {}
    for _, diff in ipairs(_DIFFICULTIES) do
        subs[#subs + 1] = _build_difficulty_block(diff)
    end
    return {
        setting_id  = "special_spawns_group",
        type        = "group",
        sub_widgets = subs,
    }
end

return {
    name        = "Tweaker: Enemies",
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = {
            -- ============================================================
            -- HORDES
            -- ============================================================
            {
                setting_id = "horde_group",
                type       = "group",
                sub_widgets = {
                    {
                        setting_id    = "horde_preset",
                        type          = "dropdown",
                        default_value = "off",
                        tooltip       = mod:localize("horde_preset_tooltip"),
                        options = {
                            { text = mod:localize("preset_off"),               value = "off" },
                            { text = mod:localize("preset_skaven_only"),       value = "skaven_only" },
                            { text = mod:localize("preset_chaos_only"),        value = "chaos_only" },
                            { text = mod:localize("preset_beastmen_invasion"), value = "beastmen_invasion" },
                            { text = mod:localize("preset_mixed_factions"),    value = "mixed_factions" },
                            { text = mod:localize("preset_all_elites"),        value = "all_elites" },
                            { text = mod:localize("preset_necro_skeletons"),   value = "necro_skeletons" },
                            { text = mod:localize("preset_ghost_skeletons"),   value = "ghost_skeletons" },
                            { text = mod:localize("preset_skeleton_mix"),      value = "skeleton_mix" },
                        },
                    },
                    {
                        setting_id    = "horde_size_multiplier",
                        type          = "numeric",
                        default_value = 100,
                        range         = { 25, 300 },
                        unit_text     = "%",
                        tooltip       = mod:localize("horde_size_multiplier_tooltip"),
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
                    _build_special_spawns_block(),
                },
            },

            -- ============================================================
            -- BREED SUBSTITUTION
            -- ============================================================
            {
                setting_id = "breed_swap_group",
                type       = "group",
                sub_widgets = {
                    {
                        setting_id    = "breed_swap_from",
                        type          = "dropdown",
                        default_value = "off",
                        tooltip       = mod:localize("breed_swap_from_tooltip"),
                        options       = _BREED_OPTIONS,
                    },
                    {
                        setting_id    = "breed_swap_to",
                        type          = "dropdown",
                        default_value = "off",
                        tooltip       = mod:localize("breed_swap_to_tooltip"),
                        options       = _BREED_OPTIONS,
                    },
                },
            },
        },
    },
}
