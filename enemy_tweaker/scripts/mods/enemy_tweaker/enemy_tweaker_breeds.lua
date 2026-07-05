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

-- ============================================================
-- Role categorization (added 2026-05-14 for Phase 1 expansion)
-- ============================================================
-- These lists are starter sets, intentionally curated rather than auto-collected
-- from the Breeds global so we have deterministic UI ordering and don't pick up
-- internal/dummy breeds. Helper predicates below fall back to runtime Breeds
-- inspection where possible (e.g. is_special checks Breeds[name].special directly).

-- Chapter-end / DLC lords. Names sourced from SpawnTweaks settings + the
-- VT2 source breeds/ directory (breed_chaos_exalted_*.lua, breed_skaven_storm_vermin_warlord.lua,
-- breed_skaven_grey_seer.lua). Subtype suffixes (_norsca, _warcamp) reflect
-- level-specific variants — Bödvarr in Skittergate is _norsca, Burblespue in War Camp is _warcamp.
M.LORDS = {
    "chaos_exalted_champion_norsca",
    "chaos_exalted_champion_warcamp",
    "chaos_exalted_sorcerer",
    "chaos_exalted_sorcerer_drachenfels",
    "skaven_storm_vermin_warlord",
    "skaven_grey_seer",
    "skaven_stormfiend_boss",
}

-- Non-lord big enemies (the "monster" director slot). Includes both the chase
-- bosses (rat ogre, stormfiend) and the per-level event monsters (chaos spawn,
-- troll, troll chief, minotaur). The troll_chief is the Festering Ground finale
-- boss; standard troll is the regular monster.
M.MONSTERS = {
    "skaven_rat_ogre",
    "skaven_stormfiend",
    "chaos_spawn",
    "chaos_troll",
    "chaos_troll_chief",
    "beastmen_minotaur",
}

-- Ambient/passive wildlife. From breed_critters.lua. These spawn from breed_packs
-- in level decorators; they have threat_value = 0 and aren't part of any horde.
M.CRITTERS = {
    "critter_pig",
    "critter_rat",
    "critter_nurgling",
}

M.SPECIALS_FALLBACK = {
    "skaven_gutter_runner", "skaven_pack_master",
    "skaven_poison_wind_globadier", "skaven_ratling_gunner",
    "skaven_warpfire_thrower",
    "chaos_vortex_sorcerer", "chaos_corruptor_sorcerer",
}

-- ============================================================
-- Role predicates
-- ============================================================
-- Each predicate prefers the runtime `Breeds` table when available (so newly-loaded
-- DLC breeds are categorized correctly) and falls back to our curated lists.

local function _set(list)
    local s = {}
    for _, name in ipairs(list) do s[name] = true end
    return s
end

local _LORDS_SET    = _set(M.LORDS)
local _MONSTERS_SET = _set(M.MONSTERS)
local _CRITTERS_SET = _set(M.CRITTERS)
local _SKAVEN_SET   = _set(M.SKAVEN)
local _CHAOS_SET    = _set(M.CHAOS)
local _BEASTMEN_SET = _set(M.BEASTMEN)

function M.is_special(breed_name)
    local B = rawget(_G, "Breeds")
    if B and B[breed_name] then
        local b = B[breed_name]
        if type(b) == "table" then
            return b.special == true and not b.boss
        end
    end
    -- Fallback for pre-Breeds-load callers.
    for _, n in ipairs(M.SPECIALS_FALLBACK) do
        if n == breed_name then return true end
    end
    return false
end

function M.is_lord(breed_name)
    return _LORDS_SET[breed_name] == true
end

function M.is_boss(breed_name)
    -- A "boss" is any unit with breed.boss = true; covers both monsters and lords.
    -- Use this when you mean "big damage-sponge target". Use is_lord() for the
    -- specific chapter-end lord set, is_monster() for the rat-ogre tier.
    local B = rawget(_G, "Breeds")
    if B and B[breed_name] and type(B[breed_name]) == "table" then
        return B[breed_name].boss == true
    end
    return _MONSTERS_SET[breed_name] == true or _LORDS_SET[breed_name] == true
end

function M.is_monster(breed_name)
    return _MONSTERS_SET[breed_name] == true
end

function M.is_critter(breed_name)
    if _CRITTERS_SET[breed_name] then return true end
    -- Defensive prefix match for any critter_* not in our list yet.
    return type(breed_name) == "string" and breed_name:sub(1, 8) == "critter_"
end

function M.faction_of(breed_name)
    if _SKAVEN_SET[breed_name]    then return "skaven" end
    if _CHAOS_SET[breed_name]     then return "chaos" end
    if _BEASTMEN_SET[breed_name]  then return "beastmen" end
    if _CRITTERS_SET[breed_name]  then return "critter" end
    -- Best-effort prefix fallback for breeds we haven't catalogued.
    if type(breed_name) == "string" then
        if breed_name:sub(1, 7)  == "skaven_"   then return "skaven" end
        if breed_name:sub(1, 6)  == "chaos_"    then return "chaos" end
        if breed_name:sub(1, 9)  == "beastmen_" then return "beastmen" end
        if breed_name:sub(1, 8)  == "critter_"  then return "critter" end
    end
    return "other"
end

-- Convenience: a flat list of every hostile breed we tune (excludes critters,
-- which are passive). Stable ordering for UI.
M.ALL_HOSTILE = {}
for _, list in ipairs({ M.SKAVEN, M.CHAOS, M.BEASTMEN, M.LORDS, M.MONSTERS }) do
    for _, name in ipairs(list) do
        M.ALL_HOSTILE[#M.ALL_HOSTILE + 1] = name
    end
end

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
-- Mod-added breeds (#324)
-- ============================================================
-- Naming convention for enemy_tweaker-added breeds: `et_<faction>_<role>`
-- (precedent: the v0.2.x-v0.3.8 skeleton clones et_necro_skeleton*,
-- et_ghost_skeleton_* -- see enemy_tweaker/DEVELOPMENT.md "Skeleton breed
-- clones"). The Skaven Warlord is a boss breed deep-copied from PRISTINE
-- vanilla skaven_storm_vermin_champion; registration + the full
-- DEVELOPMENT.md breed-adding checklist live in _et_skaven_warlord_breed.lua.
M.ET_SKAVEN_WARLORD = "et_skaven_warlord"

-- Display-name loc key. Served to VANILLA `Localize` by the consolidated
-- _G.Localize hook in _et_skaven_warlord_breed.lua -- VMF's mod_localization
-- table is private to mod:localize and invisible to vanilla Localize
-- (character_weapon_variants/REGRESSION_CHECKLIST.md:557 burn). BossHealthUI
-- renders an UNmarked boss as Localize(breed.display_name or breed_name)
-- (boss_health_ui.lua:303 + :174), so this key must resolve through the
-- vanilla path, not mod:localize.
M.ET_SKAVEN_WARLORD_NAME_KEY = "et_skaven_warlord_name"

-- Grudge-marked display names (#324 Part 3). Ordered list of
-- { key = <loc key>, en = <string> }; the KEYS are registered into vanilla
-- GrudgeMarkedNames[et_skaven_warlord] (grudge_mark_settings.lua:196 table,
-- consumed by TerrorEventUtils.get_grudge_marked_name at
-- terror_event_utils.lua:59-78: name_list = GrudgeMarkedNames[breed_name],
-- index = magic_number %% #name_list + 1, then Localize(name_list[index])).
-- The STRINGS are served by the same _G.Localize hook as the display name.
-- Style mirrors the vanilla name_grudge_* sets (title + epithet).
M.WARLORD_GRUDGE_NAMES = {
    { key = "et_grudge_warlord_001", en = "Skrittch the Thrice-Crowned" },
    { key = "et_grudge_warlord_002", en = "Vraskitt the Gore-Warden" },
    { key = "et_grudge_warlord_003", en = "Kritchak Blackfang" },
    { key = "et_grudge_warlord_004", en = "Sneekit the Throat-Taker" },
    { key = "et_grudge_warlord_005", en = "Queekrit the Man-Flayer" },
    { key = "et_grudge_warlord_006", en = "Iskrit the Warp-Sworn" },
    { key = "et_grudge_warlord_007", en = "Gnashrak the Tail-Ripper" },
    { key = "et_grudge_warlord_008", en = "Skabrit Doom-Whisker" },
    { key = "et_grudge_warlord_009", en = "Vermitch the Hollow-Eyed" },
    { key = "et_grudge_warlord_010", en = "Rikkfang the Pit-Master" },
    { key = "et_grudge_warlord_011", en = "Tretchik the Oath-Gnawer" },
    { key = "et_grudge_warlord_012", en = "Karskit the Red-Clawed" },
}

-- ============================================================
-- Display name resolution
-- ============================================================

M.BREED_NAME_OVERRIDES = {
    chaos_corruptor_sorcerer = "Lifeleech Sorcerer",
    chaos_vortex_sorcerer    = "Blightstormer",
    et_skaven_warlord        = "Skaven Warlord",  -- #324 mod-added breed
}

local function _humanize(breed_name)
    local s = breed_name
        :gsub("^skaven_", "")
        :gsub("^chaos_", "")
        :gsub("^beastmen_", "")
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
