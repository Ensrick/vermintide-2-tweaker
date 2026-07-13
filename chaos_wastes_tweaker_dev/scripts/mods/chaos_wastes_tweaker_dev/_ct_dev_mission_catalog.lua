local mod = get_mod("ct_dev")

-- _ct_dev_mission_catalog.lua - static data + menu/loc builders for the Single Mission dev loader (issue 505).
--
-- Owns the closed vocabularies the loader forces (curses by god, minor modifiers,
-- shrine blessings, difficulties, themes, native CW base levels) plus the VMF menu
-- widget tree and its localization entries. Every list is transcribed from the
-- decompile and carries a `file:line` citation so a Fatshark data reshuffle is
-- auditable. PURE MODULE: no mod:hook, no mod:command, no mod.* writes - it only
-- reads static vanilla tables and returns data, so the double dofile (once from
-- <mod>_data.lua to build widgets, once from <mod>_localization.lua to build loc,
-- once from _ct_dev_mission.lua to resolve dropdown index <-> name) is idempotent
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

-- Shrine blessings (permanent run modifiers). Source: deus_blessing_settings.lua:18-99.
-- Forced via script_data.deus_force_load_blessing (deus_run_state.lua:169-170).
_M.BLESSINGS = {
    "blessing_of_power", "blessing_of_shallya", "blessing_of_grimnir", "blessing_of_isha",
    "blessing_of_ranald", "blessing_of_abundance", "blessing_holy_hand_grenade", "blessing_rally_flag",
}

-- Base difficulties. Source: difficulty_settings.lua:4-269 (ranks 2..8). ct's
-- progressive-difficulty hook then ramps this up by run_progress at play time.
_M.DIFFICULTIES = { "normal", "hard", "harder", "hardest", "cataclysm", "cataclysm_2", "cataclysm_3" }

-- Node themes. Source: deus_theme_settings.lua DEUS_THEME_TYPES (:120-127).
_M.THEMES = { "wastes", "khorne", "nurgle", "tzeentch", "slaanesh", "belakor" }

-- Native CW base levels. Source: deus_map_populate_settings.lua LEVEL_AVAILABILITY
-- (TRAVEL :422-448 / SIGNATURE :449-483, sig_citadel added in journey_citadel
-- :1135). arena_*/shop_* node types are out of scope per issue 505 ("if it's not
-- an arena mission").
_M.TRAVEL_LEVELS    = { "pat_forest", "pat_town", "pat_mountain", "pat_mines", "pat_tower", "pat_bay" }
_M.SIGNATURE_LEVELS = { "sig_mordrek", "sig_gorge", "sig_volcano", "sig_snare", "sig_crag", "sig_citadel" }

-- Flat base list (travel first, then signature) - the menu base dropdown index space.
_M.BASE_LEVELS = {}
do
    for _, k in ipairs(_M.TRAVEL_LEVELS) do _M.BASE_LEVELS[#_M.BASE_LEVELS + 1] = k end
    for _, k in ipairs(_M.SIGNATURE_LEVELS) do _M.BASE_LEVELS[#_M.BASE_LEVELS + 1] = k end
end

-- Depth presets -> run_progress fraction. Higher = deeper into the run (more
-- spawns, harder trials, higher weapon-chest tier via ct's progressive hooks).
_M.PROGRESS = { 0.0, 0.25, 0.5, 0.75, 1.0 }

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

local BLESSING_LABEL = {
    blessing_of_power        = "Blessing of Power (+50 weapon power)",
    blessing_of_shallya      = "Blessing of Shallya",
    blessing_of_grimnir      = "Blessing of Grimnir",
    blessing_of_isha         = "Blessing of Isha",
    blessing_of_ranald       = "Blessing of Ranald",
    blessing_of_abundance    = "Blessing of Abundance",
    blessing_holy_hand_grenade = "Holy Hand Grenade",
    blessing_rally_flag      = "Rally Flag",
}

local DIFFICULTY_LABEL = {
    normal = "Recruit (normal)", hard = "Veteran (hard)", harder = "Champion (harder)",
    hardest = "Legend (hardest)", cataclysm = "Cataclysm", cataclysm_2 = "Cataclysm 2",
    cataclysm_3 = "Cataclysm 3",
}

local THEME_LABEL = {
    wastes = "Wastes (neutral)", khorne = "Khorne", nurgle = "Nurgle",
    tzeentch = "Tzeentch", slaanesh = "Slaanesh", belakor = "Be'lakor",
}

-- CW mission display names. Source: _adventure_pool.lua CW_SCENARIOS names +
-- sig_citadel (citadel journey approach map).
local LEVEL_LABEL = {
    pat_forest = "The Forbidden Trail", pat_town = "Grimblood's Stronghold",
    pat_mountain = "Pinnacle of Nightmares", pat_mines = "Bel'sha'ziir's Mine",
    pat_tower = "Holseher's Tower", pat_bay = "Slaughter Bay",
    sig_mordrek = "Count Mordrek's Fortress", sig_gorge = "The Foetid Gorge",
    sig_volcano = "Cinder Peak", sig_snare = "The Pit of Reflections",
    sig_crag = "The Lost City of Marakza", sig_citadel = "Citadel of Eternity (approach)",
}

-- VMF localizes dropdown options through string.format, so literal percent signs
-- must remain escaped in the localization table. They render as a single "%".
local PROGRESS_LABEL = { "Start (0%%)", "Early (25%%)", "Mid (50%%)", "Late (75%%)", "Deepest (100%%)" }

-- ===========================================================================
-- Loc-key helpers (systematic prefixes keep menu and loc in lockstep)
-- ===========================================================================

function _M.curse_key(name)    return "ctdm_c_" .. name end
function _M.modifier_key(name) return "ctdm_m_" .. name end
function _M.blessing_key(name) return "ctdm_b_" .. name end
function _M.difficulty_key(n)  return "ctdm_d_" .. n end
function _M.theme_key(name)    return "ctdm_t_" .. name end
function _M.base_key(name)     return "ctdm_l_" .. name end
function _M.progress_key(i)    return "ctdm_p_" .. tostring(i) end

-- ===========================================================================
-- Localization entries (consumed by <mod>_localization.lua)
-- ===========================================================================

function _M.build_loc_entries()
    local e = {}

    -- Group + widget titles / tooltips. [untested] dev status tag per
    -- LOCALIZATION_STANDARD s13 - drops to [working] once the user confirms in-game.
    e.ctdm_group = { en = "[untested] Dev: Single Mission Loader" }

    e.ctdm_load = { en = "Load Selected Mission Now (hotkey)" }
    e.ctdm_load_tooltip = { en = "Host-only. Immediately loads the mission chosen below as a one-mission Chaos Wastes run.\n\nYou must already be inside a Chaos Wastes expedition (on the CW map screen or in a CW mission) - start any expedition first, then press this to jump to the exact mission you want to test." }

    e.ctdm_base = { en = "Mission" }
    e.ctdm_base_tooltip = { en = "The Chaos Wastes level to load. Travel maps (pat_) and Signature maps (sig_) only; arenas, shops and finales are out of scope.\n\nTo load a Campaign or DLC mission injected by Inject Adventure Missions, use the /ct_load_mission chat command with its level key (run /ct_list_missions to list them)." }

    e.ctdm_theme = { en = "God Theme" }
    e.ctdm_theme_tooltip = { en = "Which god's visual theme colours the mission. Wastes is the neutral (un-themed) look. When you also force a curse, the theme is pulled toward that curse's god automatically." }

    e.ctdm_path = { en = "Path Variant" }
    e.ctdm_path_tooltip = { en = "Which layout variant of the map to load (1-5). Not every base map has all five; if a variant does not exist the load is refused with a message." }

    e.ctdm_difficulty = { en = "Base Difficulty" }
    e.ctdm_difficulty_tooltip = { en = "Starting difficulty of the run. Keep Current keeps whatever the active run is on. Progressive Difficulty (if enabled) still ramps upward from here based on the depth below." }

    e.ctdm_progress = { en = "Mission Depth" }
    e.ctdm_progress_tooltip = { en = "How deep into a run this mission counts as. Deeper = more spawns, harder trials, and higher-tier weapon-chest rolls (via ct's progressive hooks). This does not pre-equip you with upgraded gear." }

    e.ctdm_curse = { en = "Curse" }
    e.ctdm_curse_tooltip = { en = "Force a specific god curse on the mission, or None for an un-cursed mission." }

    e.ctdm_modifier1 = { en = "Minor Modifier 1" }
    e.ctdm_modifier1_tooltip = { en = "First minor modifier applied to the mission (e.g. More Coins, Fewer Specials). Best-effort: appended to the loaded node's mutator list." }

    e.ctdm_modifier2 = { en = "Minor Modifier 2" }
    e.ctdm_modifier2_tooltip = { en = "Second minor modifier applied to the mission. Best-effort: appended to the loaded node's mutator list." }

    e.ctdm_blessing = { en = "Starting Blessing" }
    e.ctdm_blessing_tooltip = { en = "Grant a shrine blessing for the run at the start (e.g. Blessing of Power for +50 weapon power), as if you had bought it at a shrine." }

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
    for _, b in ipairs(_M.BLESSINGS) do
        e[_M.blessing_key(b)] = { en = BLESSING_LABEL[b] or b }
    end
    for _, d in ipairs(_M.DIFFICULTIES) do
        e[_M.difficulty_key(d)] = { en = DIFFICULTY_LABEL[d] or d }
    end
    for _, t in ipairs(_M.THEMES) do
        e[_M.theme_key(t)] = { en = THEME_LABEL[t] or t }
    end
    for _, l in ipairs(_M.BASE_LEVELS) do
        local pool = string.sub(l, 1, 4) == "sig_" and "Signature" or "Travel"
        e[_M.base_key(l)] = { en = (LEVEL_LABEL[l] or l) .. " [" .. pool .. "]" }
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
    for i, l in ipairs(_M.BASE_LEVELS) do opts[i] = { text = _M.base_key(l), value = i } end
    return opts
end

function _M.theme_options()
    local opts = {}
    for i, t in ipairs(_M.THEMES) do opts[i] = { text = _M.theme_key(t), value = i } end
    return opts
end

function _M.path_options()
    -- reuses the numeric "1".."5" loc entries already defined for other dropdowns.
    return {
        { text = "1", value = 1 }, { text = "2", value = 2 }, { text = "3", value = 3 },
        { text = "4", value = 4 }, { text = "5", value = 5 },
    }
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

function _M.blessing_options()
    local opts = { { text = "ctdm_none", value = 0 } }
    for i, b in ipairs(_M.BLESSINGS) do opts[#opts + 1] = { text = _M.blessing_key(b), value = i } end
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
            { setting_id = "ctdm_theme",      type = "dropdown", default_value = 1, options = _M.theme_options(),      tooltip = "ctdm_theme_tooltip" },
            { setting_id = "ctdm_path",       type = "dropdown", default_value = 1, options = _M.path_options(),       tooltip = "ctdm_path_tooltip" },
            { setting_id = "ctdm_difficulty", type = "dropdown", default_value = 0, options = _M.difficulty_options(), tooltip = "ctdm_difficulty_tooltip" },
            { setting_id = "ctdm_progress",   type = "dropdown", default_value = 1, options = _M.progress_options(),   tooltip = "ctdm_progress_tooltip" },
            { setting_id = "ctdm_curse",      type = "dropdown", default_value = 0, options = _M.curse_options(),      tooltip = "ctdm_curse_tooltip" },
            { setting_id = "ctdm_modifier1",  type = "dropdown", default_value = 0, options = _M.modifier_options(),   tooltip = "ctdm_modifier1_tooltip" },
            { setting_id = "ctdm_modifier2",  type = "dropdown", default_value = 0, options = _M.modifier_options(),   tooltip = "ctdm_modifier2_tooltip" },
            { setting_id = "ctdm_blessing",   type = "dropdown", default_value = 0, options = _M.blessing_options(),   tooltip = "ctdm_blessing_tooltip" },
            { setting_id = "ctdm_with_belakor", type = "checkbox", default_value = false, tooltip = "ctdm_with_belakor_tooltip" },
        },
    }
end

return _M
