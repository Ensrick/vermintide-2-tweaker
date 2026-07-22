local mod = get_mod("ct_dev")
local AdventurePool = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_adventure_pool")

-- _ct_dev_mission_catalog.lua - data + menu/loc builders for Single Mission Loader (issue 505).
--
-- Owns the closed vocabularies the loader forces (curses by god, minor modifiers,
-- difficulties, and every user-selectable mission) plus the VMF menu
-- widget tree and its localization entries. Every list is transcribed from the
-- decompile and carries a `file:line` citation so a Fatshark data reshuffle is
-- auditable. PURE MODULE: no mod:hook, no mod:command, no mod.* writes - it only
-- reads static vanilla tables and returns data, so the double dofile (once from
-- <mod>_data.lua to build widgets, from <mod>_localization.lua to build loc, and
-- from _ct_dev_mission.lua to resolve dropdown index <-> name) is idempotent
-- (PROJECT_STANDARDS 2.2a rule 4). The loadable level key is
-- "<base>_<theme>_path<N>" (deus_populate_graph.lua:945); the loader composes it.
--
-- Owned by: chaos_wastes_tweaker_dev.lua entry point. Consumed via: mod:dofile.

local _M = {}

-- ===========================================================================
-- Vocabularies (all cited to the 2026-07-12 decompile)
-- ===========================================================================

-- Curses grouped by god. Source: deus_map_populate_settings.lua:3-28 (all_curses).
_M.CURSES_BY_GOD = {
    { god = "nurgle",   curses = { "curse_corrupted_flesh", "curse_rotten_miasma", "curse_skulking_sorcerer" } },
    { god = "tzeentch", curses = { "curse_change_of_tzeentch", "curse_bolt_of_change", "curse_egg_of_tzeentch" } },
    { god = "khorne",   curses = { "curse_skulls_of_fury", "curse_khorne_champions", "curse_blood_storm" } },
    { god = "slaanesh", curses = { "curse_greed_pinata", "curse_empathy", "curse_abundance_of_life" } },
    { god = "belakor",  curses = { "curse_shadow_homing_skulls", "curse_belakor_totems" } },
}

-- Flat, ordered curse list + the reverse (curse -> god) map, built from the grouping.
_M.CURSES = {}
_M.CURSE_GOD = {}
do
    for _, grp in ipairs(_M.CURSES_BY_GOD) do
        for _, curse in ipairs(grp.curses) do
            _M.CURSES[#_M.CURSES + 1] = curse
            _M.CURSE_GOD[curse] = grp.god
        end
    end
end

-- The per-node "minor modifiers" the user asked to pick (e.g. +coins, -specials).
-- These are the individual mutator names the vanilla map generator draws in PAIRS
-- from AVAILABLE_MINOR_MODIFIERS (deus_map_populate_settings.lua:86-170 default,
-- plus the per-journey variants that add increased_deus_soft_currency /
-- increased_healing, e.g. :390-420). Flattened here to the distinct names so the
-- user can pick any two independently.
_M.MODIFIERS = {
    "increased_deus_soft_currency",   -- more coins
    "increased_healing",
    "increased_deus_potions",
    "deus_more_specials", "deus_less_specials",
    "deus_more_elites",   "deus_less_elites",
    "deus_more_hordes",   "deus_less_hordes",
    "deus_more_roamers",  "deus_less_roamers",
    "deus_more_monsters", "deus_less_monsters",
}

-- Base difficulties. Source: difficulty_settings.lua:4-269 (ranks 2..8). ct's
-- progressive-difficulty hook then ramps this up by run_progress at play time.
_M.DIFFICULTIES = { "normal", "hard", "harder", "hardest", "cataclysm", "cataclysm_2", "cataclysm_3" }

-- The mission picker uses user-facing content families, not the graph solver's
-- internal TRAVEL/SIGNATURE node types. AdventurePool is already the canonical
-- mission/name catalog for Helmgart, DLC, events and normal CW scenarios. An
-- Adventure mission is shown only when its vanilla LevelSettings entry exists;
-- register_mission_resolvables uses the same test as the DLC-ownership gate.
_M.CATEGORY_HELMGART = "Helmgart Campaign"
_M.CATEGORY_DLC      = "DLC Missions"
_M.CATEGORY_EVENT    = "Event Missions"
_M.CATEGORY_CW       = "Chaos Wastes"
_M.CATEGORIES = {
    _M.CATEGORY_HELMGART,
    _M.CATEGORY_DLC,
    _M.CATEGORY_EVENT,
    _M.CATEGORY_CW,
}

_M.MISSIONS = {}
_M.MISSION_INDEX_BY_KEY = {}
local function add_mission(mission, category, is_native_cw)
    if not mission or not mission.key or _M.MISSION_INDEX_BY_KEY[mission.key] then return end
    if not is_native_cw and rawget(_G, "LevelSettings") and not rawget(LevelSettings, mission.key) then return end
    local entry = {
        key = mission.key,
        name = mission.name or mission.key,
        category = category,
        native_cw = is_native_cw and true or false,
    }
    _M.MISSIONS[#_M.MISSIONS + 1] = entry
    _M.MISSION_INDEX_BY_KEY[entry.key] = #_M.MISSIONS
end

for _, group in ipairs(AdventurePool.MISSION_GROUPS or {}) do
    local category = group.id == "helmgart" and _M.CATEGORY_HELMGART or _M.CATEGORY_DLC
    for _, mission in ipairs(group.missions or {}) do add_mission(mission, category, false) end
end
for _, mission in ipairs(AdventurePool.EVENT_MISSIONS or {}) do
    add_mission(mission, _M.CATEGORY_EVENT, false)
end
for _, mission in ipairs(AdventurePool.CW_SCENARIOS or {}) do
    add_mission(mission, _M.CATEGORY_CW, true)
end
-- Citadel's approach map is a normal SIGNATURE node only in journey_citadel
-- (deus_map_populate_settings.lua:1135); it is absent from the shared CW pool
-- catalog because availability toggles intentionally do not alter that journey.
add_mission({ key = "sig_citadel", name = "Citadel of Eternity (Approach)" }, _M.CATEGORY_CW, true)

-- Back-compat alias for diagnostic command callers; values are now the complete
-- user-facing mission set rather than only native CW bases.
_M.BASE_LEVELS = {}
for _, mission in ipairs(_M.MISSIONS) do _M.BASE_LEVELS[#_M.BASE_LEVELS + 1] = mission.key end

-- Depth presets -> run_progress fraction. Fatshark's own Deus loader limits its
-- slider to 0.999, and DeusWeaponGeneration.get_random_rarity asserts on every
-- value >= 1.0. Keep the engine boundary and every caller on one canonical cap.
_M.MAX_RUN_PROGRESS = 0.999
_M.PROGRESS = { 0.0, 0.25, 0.5, 0.75, _M.MAX_RUN_PROGRESS }

function _M.sanitize_progress(value)
    local progress = tonumber(value)
    if not progress or progress ~= progress then return 0 end -- nil / NaN
    if progress < 0 then return 0 end
    if progress > _M.MAX_RUN_PROGRESS then return _M.MAX_RUN_PROGRESS end
    return progress
end

-- Vanilla graph population picks a valid layout path from level_info.paths
-- (deus_populate_graph.lua:342-346,462-465). The single-node debug graph bypasses
-- that population pass, so choose the first declared path deterministically.
-- A forced curse also supplies its god theme (deus_generate_graph.lua:67-69);
-- un-cursed nodes use the neutral Wastes theme.
function _M.compose_level_key(base, curse, level_settings)
    local theme = (curse and _M.CURSE_GOD[curse]) or "wastes"
    local info = level_settings and level_settings[base]
    local paths = info and info.paths
    local path = (type(paths) == "table" and paths[1]) or 1
    return base .. "_" .. theme .. "_path" .. tostring(path), theme, path
end

-- ===========================================================================
-- Human-readable labels (menu display + loc generation, single source)
-- ===========================================================================

local GOD_LABEL = {
    nurgle = "Nurgle", tzeentch = "Tzeentch", khorne = "Khorne",
    slaanesh = "Slaanesh", belakor = "Be'lakor",
}

local CURSE_LABEL = {
    curse_corrupted_flesh   = "Corrupted Flesh",
    curse_rotten_miasma     = "Rotten Miasma",
    curse_skulking_sorcerer = "Skulking Sorcerer",
    curse_change_of_tzeentch = "Change of Tzeentch",
    curse_bolt_of_change    = "Bolt of Change",
    curse_egg_of_tzeentch   = "Egg of Tzeentch",
    curse_skulls_of_fury    = "Skulls of Fury",
    curse_khorne_champions  = "Khorne Champions",
    curse_blood_storm       = "Blood Storm",
    curse_greed_pinata      = "Greed Pinata",
    curse_empathy           = "Empathy",
    curse_abundance_of_life = "Abundance of Life",
    curse_shadow_homing_skulls = "Shadow Homing Skulls",
    curse_belakor_totems    = "Be'lakor Totems",
}

local MODIFIER_LABEL = {
    increased_deus_soft_currency = "More Coins",
    increased_healing            = "More Healing",
    increased_deus_potions       = "More Potions",
    deus_more_specials = "More Specials", deus_less_specials = "Fewer Specials",
    deus_more_elites   = "More Elites",   deus_less_elites   = "Fewer Elites",
    deus_more_hordes   = "More Hordes",   deus_less_hordes   = "Fewer Hordes",
    deus_more_roamers  = "More Roamers",  deus_less_roamers  = "Fewer Roamers",
    deus_more_monsters = "More Monsters", deus_less_monsters = "Fewer Monsters",
}

local DIFFICULTY_LABEL = {
    normal = "Recruit (normal)", hard = "Veteran (hard)", harder = "Champion (harder)",
    hardest = "Legend (hardest)", cataclysm = "Cataclysm", cataclysm_2 = "Cataclysm 2",
    cataclysm_3 = "Cataclysm 3",
}

-- VMF localizes dropdown options through string.format, so literal percent signs
-- must remain escaped in the localization table. They render as a single "%".
local PROGRESS_LABEL = { "Start (0%%)", "Early (25%%)", "Mid (50%%)", "Late (75%%)", "Deepest (99.9%%)" }

-- ===========================================================================
-- Loc-key helpers (systematic prefixes keep menu and loc in lockstep)
-- ===========================================================================

function _M.curse_key(name)    return "ctdm_c_" .. name end
function _M.curse_label(name)  return CURSE_LABEL[name] or tostring(name) end
function _M.modifier_key(name) return "ctdm_m_" .. name end
function _M.difficulty_key(n)  return "ctdm_d_" .. n end
function _M.base_key(name)     return "ctdm_l_" .. name end
function _M.progress_key(i)    return "ctdm_p_" .. tostring(i) end

-- ===========================================================================
-- Localization entries (consumed by <mod>_localization.lua)
-- ===========================================================================

function _M.build_loc_entries()
    local e = {}

    -- Group + widget titles / tooltips omit issue/lifecycle state. Verification
    -- belongs in GitHub and the changelog, never in player-facing labels.
    e.ctdm_group = { en = "Single Mission Loader" }

    e.ctdm_load = { en = "Load Selected Mission Now (hotkey)" }
    e.ctdm_load_tooltip = { en = "Host-only. Immediately starts the selected one-mission Chaos Wastes run. This hotkey works only while your character is physically inside the Pilgrimage Chamber reached through the Chaos Wastes door in the keep." }

    e.ctdm_base = { en = "Mission" }
    e.ctdm_base_tooltip = { en = "Choose a Helmgart Campaign, DLC, Event, or normal Chaos Wastes mission. Use the dropdown filters to narrow the list. DLC missions appear only when their vanilla level data is available." }

    e.ctdm_difficulty = { en = "Base Difficulty" }
    e.ctdm_difficulty_tooltip = { en = "Starting difficulty of the run. Keep Current keeps whatever the active run is on. Progressive Difficulty (if enabled) still ramps upward from here based on the depth below." }

    e.ctdm_progress = { en = "Run Progress" }
    e.ctdm_progress_tooltip = { en = "The normalized position of this node within its one-mission run. CT features may use it for pacing, difficulty, or economy scaling. It is independent from the mission's hidden layout path, which the loader chooses from vanilla's valid paths." }

    e.ctdm_curse = { en = "Curses" }
    e.ctdm_curse_tooltip = { en = "Force one god curse, or None for an un-cursed mission. Vanilla ties a forced curse to that curse's god theme; None uses the neutral Wastes theme." }

    e.ctdm_modifier1 = { en = "Minor Modifier 1" }
    e.ctdm_modifier1_tooltip = { en = "First minor modifier applied to the mission (e.g. More Coins, Fewer Specials). Best-effort: appended to the loaded node's mutator list." }

    e.ctdm_modifier2 = { en = "Minor Modifier 2" }
    e.ctdm_modifier2_tooltip = { en = "Second minor modifier applied to the mission. Best-effort: appended to the loaded node's mutator list." }

    e.ctdm_with_belakor = { en = "Be'lakor Journey" }
    e.ctdm_with_belakor_tooltip = { en = "Load the mission as part of a Be'lakor journey (enables Be'lakor's curses/loci where applicable)." }

    e.ctdm_none = { en = "None" }
    e.ctdm_d_current = { en = "Keep Current" }

    for _, c in ipairs(_M.CURSES) do
        e[_M.curse_key(c)] = { en = (CURSE_LABEL[c] or c) .. " (" .. (GOD_LABEL[_M.CURSE_GOD[c]] or "?") .. ")" }
    end
    for _, m in ipairs(_M.MODIFIERS) do
        e[_M.modifier_key(m)] = { en = MODIFIER_LABEL[m] or m }
    end
    for _, d in ipairs(_M.DIFFICULTIES) do
        e[_M.difficulty_key(d)] = { en = DIFFICULTY_LABEL[d] or d }
    end
    for _, mission in ipairs(_M.MISSIONS) do
        e[_M.base_key(mission.key)] = { en = mission.name }
    end
    for i = 1, #_M.PROGRESS do
        e[_M.progress_key(i)] = { en = PROGRESS_LABEL[i] or (tostring(math.floor(_M.PROGRESS[i] * 100)) .. "%%") }
    end

    return e
end

-- ===========================================================================
-- Dropdown option builders (value 0 = None/Current where applicable)
-- ===========================================================================

function _M.base_options()
    local opts = {}
    for i, mission in ipairs(_M.MISSIONS) do opts[i] = { text = _M.base_key(mission.key), value = i } end
    return opts
end

function _M.difficulty_options()
    local opts = { { text = "ctdm_d_current", value = 0 } }
    for i, d in ipairs(_M.DIFFICULTIES) do opts[#opts + 1] = { text = _M.difficulty_key(d), value = i } end
    return opts
end

function _M.progress_options()
    local opts = {}
    for i = 1, #_M.PROGRESS do opts[i] = { text = _M.progress_key(i), value = i } end
    return opts
end

function _M.curse_options()
    local opts = { { text = "ctdm_none", value = 0 } }
    for i, c in ipairs(_M.CURSES) do opts[#opts + 1] = { text = _M.curse_key(c), value = i } end
    return opts
end

function _M.modifier_options()
    local opts = { { text = "ctdm_none", value = 0 } }
    for i, m in ipairs(_M.MODIFIERS) do opts[#opts + 1] = { text = _M.modifier_key(m), value = i } end
    return opts
end

-- ===========================================================================
-- Menu group widget (consumed by <mod>_data.lua)
-- ===========================================================================

function _M.build_menu_group()
    return {
        setting_id = "ctdm_group",
        type = "group",
        sub_widgets = {
            {
                setting_id = "ctdm_load", type = "keybind",
                keybind_trigger = "pressed", keybind_type = "function_call",
                function_name = "ct_dev_load_selected_mission",
                default_value = {}, tooltip = "ctdm_load_tooltip",
            },
            { setting_id = "ctdm_base",       type = "dropdown", default_value = 1, options = _M.base_options(),       tooltip = "ctdm_base_tooltip" },
            { setting_id = "ctdm_curse",      type = "dropdown", default_value = 0, options = _M.curse_options(),      tooltip = "ctdm_curse_tooltip" },
            { setting_id = "ctdm_progress",   type = "dropdown", default_value = 1, options = _M.progress_options(),   tooltip = "ctdm_progress_tooltip" },
            { setting_id = "ctdm_difficulty", type = "dropdown", default_value = 0, options = _M.difficulty_options(), tooltip = "ctdm_difficulty_tooltip" },
            { setting_id = "ctdm_modifier1",  type = "dropdown", default_value = 0, options = _M.modifier_options(),   tooltip = "ctdm_modifier1_tooltip" },
            { setting_id = "ctdm_modifier2",  type = "dropdown", default_value = 0, options = _M.modifier_options(),   tooltip = "ctdm_modifier2_tooltip" },
            { setting_id = "ctdm_with_belakor", type = "checkbox", default_value = false, tooltip = "ctdm_with_belakor_tooltip" },
        },
    }
end

return _M
