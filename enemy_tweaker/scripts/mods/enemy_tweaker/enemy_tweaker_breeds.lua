-- Shared breed/difficulty data for enemy_tweaker.
-- Required by both enemy_tweaker_data.lua and enemy_tweaker_localization.lua
-- so widget text/tooltips and pre-built loc entries stay in sync.

local M = {}

-- ============================================================
-- Breed lists
-- ============================================================

M.SKAVEN = {
    "skaven_slave", "skaven_clan_rat", "skaven_clan_rat_with_shield",
    "skaven_storm_vermin", "skaven_storm_vermin_with_shield",
    "skaven_storm_vermin_commander", "skaven_plague_monk",
    "skaven_gutter_runner", "skaven_pack_master",
    "skaven_poison_wind_globadier", "skaven_ratling_gunner",
    "skaven_warpfire_thrower", "skaven_rat_ogre", "skaven_stormfiend",
}

M.CHAOS = {
    "chaos_fanatic", "chaos_marauder", "chaos_marauder_with_shield",
    "chaos_berzerker", "chaos_raider", "chaos_warrior", "chaos_bulwark",
    "chaos_spawn", "chaos_troll", "chaos_vortex_sorcerer",
    "chaos_corruptor_sorcerer",
}

M.BEASTMEN = {
    "beastmen_ungor", "beastmen_ungor_archer", "beastmen_gor",
    "beastmen_bestigor", "beastmen_minotaur", "beastmen_standard_bearer",
}

M.SKELETON = {
    "et_necro_skeleton", "et_necro_skeleton_armored",
    "et_necro_skeleton_dual_wield", "et_necro_skeleton_shield",
    "et_ghost_skeleton_hammer", "et_ghost_skeleton_shield",
}

M.SPECIALS_FALLBACK = {
    "skaven_gutter_runner", "skaven_pack_master",
    "skaven_poison_wind_globadier", "skaven_ratling_gunner",
    "skaven_warpfire_thrower",
    "chaos_vortex_sorcerer", "chaos_corruptor_sorcerer",
}

function M.collect_specials()
    if not rawget(_G, "Breeds") then return M.SPECIALS_FALLBACK end
    local out = {}
    for name, b in pairs(Breeds) do
        if type(b) == "table" and b.special and not b.boss
                and not name:find("_tutorial") and not name:find("_dummy") then
            out[#out + 1] = name
        end
    end
    if #out == 0 then return M.SPECIALS_FALLBACK end
    table.sort(out)
    return out
end

-- ============================================================
-- Display name resolution
-- ============================================================

M.BREED_NAME_OVERRIDES = {
    chaos_corruptor_sorcerer     = "Lifeleech Sorcerer",
    chaos_vortex_sorcerer        = "Blightstormer",
    et_necro_skeleton            = "Skeleton Warrior",
    et_necro_skeleton_armored    = "Skeleton Warrior (Armored)",
    et_necro_skeleton_dual_wield = "Skeleton Warrior (Dual)",
    et_necro_skeleton_shield     = "Skeleton Warrior (Shield)",
    et_ghost_skeleton_hammer     = "Ghost Skeleton (Hammer)",
    et_ghost_skeleton_shield     = "Ghost Skeleton (Shield)",
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

function M.breed_label(breed_name)
    local override = M.BREED_NAME_OVERRIDES[breed_name]
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
-- Difficulty list
-- ============================================================

M.DIFFICULTIES = {
    { key = "normal",      label = "Recruit",     max_total = 2, max_same = 1 },
    { key = "hard",        label = "Veteran",     max_total = 3, max_same = 2 },
    { key = "harder",      label = "Champion",    max_total = 3, max_same = 2 },
    { key = "hardest",     label = "Legend",      max_total = 4, max_same = 2 },
    { key = "cataclysm",   label = "Cataclysm 1", max_total = 5, max_same = 3 },
    { key = "cataclysm_2", label = "Cataclysm 2", max_total = 6, max_same = 3 },
    { key = "cataclysm_3", label = "Cataclysm 3", max_total = 6, max_same = 3 },
}

function M.setting_key(diff_key, suffix, breed)
    if breed then
        return string.format("et_diff_%s_%s_%s", diff_key, suffix, breed)
    end
    return string.format("et_diff_%s_%s", diff_key, suffix)
end

function M.breed_swap_option_key(breed_name)
    return "breed_swap_opt_" .. breed_name
end

return M
