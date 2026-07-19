local mod = get_mod("ct_dev")
local Cat = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_dev_mission_catalog")

-- _ct_dev_mission.lua - Single Mission Loader (issue 505).
--
-- The verification lever for the ct critical cluster: forces the game to load one
-- specific mission with a chosen curse, minor modifiers, base difficulty and
-- run progress, so a bug that needs a particular
-- mission/curse/depth can be reproduced on demand (the CW analogue of gt_dev's
-- /downbots for issue 448).
--
-- MECHANISM (no new hooks - reuses vanilla's own debug single-node loader):
--   * DeusMechanism:debug_load_deus_level(level_name, difficulty, progress,
--     level_seed, with_belakor)  builds the run seed
--     "DEBUG_SPECIFIC_NODE<progress*1000>_<level>SEED<seed>SEED_END" and calls
--     _debug_load_seed -> _setup_run + rpc_deus_setup_run to clients + level
--     transition (deus_mechanism.lua:1018 / :1054-1058).
--   * deus_generate_graph.lua:10-72 takes that seed and returns a ONE-node graph
--     (DeusDebugSpecificNodeGraph, deus_default_graph_settings.lua:1534), parsing
--     level/base/theme/run_progress from the seed string and reading
--     script_data.deus_force_load_curse for the curse (deus_generate_graph.lua:67).
--   * CT's existing DeusRunController._add_initial_power_ups hook grants all
--     selected Starting Boons when the debug run initializes.
--   * Minor modifiers are appended to the debug node's mutator list. table.clone in
--     deus_generate_graph is shallow, so DeusDebugSpecificNodeGraph.start is the
--     very table the loaded node uses - we rebuild .mutators just before the load.
--
-- HOST-ONLY (debug_load_deus_level runs _setup_run as server + pushes the run to
-- clients) and PILGRIMAGE-CHAMBER-ONLY (`morris_hub`, the level loaded by the
-- keep's deus_door_transition in interactions.lua:2738-2744). Solo host+bots is the guaranteed
-- path; the co-op caveat is in the CHANGELOG (script_data is per-machine, so a
-- forced curse/modifier applies host-side - clients loading the same seed get the
-- same base level).
--
-- Owned by: chaos_wastes_tweaker_dev.lua entry point. Consumed via: mod:dofile.
-- No mod:hook here (grep-clean) - forcing is done entirely through script_data +
-- the vanilla debug entry point, so there is no (Class, method) to collide with.

-- Validation sets (built once from the catalog).
local CURSE_SET, DIFF_SET, MOD_SET = {}, {}, {}
do
    for _, c in ipairs(Cat.CURSES) do CURSE_SET[c] = true end
    for _, d in ipairs(Cat.DIFFICULTIES) do DIFF_SET[d] = true end
    for _, m in ipairs(Cat.MODIFIERS) do MOD_SET[m] = true end
end

-- LEVEL_ALIAS remap. The alias table (deus_map_populate_settings.lua:188-220) is
-- applied by the graph populator (deus_populate_graph.lua:1097-1100), but the
-- DEBUG_SPECIFIC_NODE path returns BEFORE populate runs, so composite keys that
-- alias to a real level (notably every sig_snare_<theme>_path<N> -> sig_snare_<a-e>
-- variant) must be remapped here or the level key is invalid.
local function resolve_alias(level_key)
    local ps = rawget(_G, "DEUS_MAP_POPULATE_SETTINGS")
    local cfg = ps and (ps.journey_ruin or ps.default)
    local alias = cfg and cfg.LEVEL_ALIAS
    return (alias and alias[level_key]) or level_key
end

local function is_host()
    return (Managers and Managers.player and Managers.player.is_server) and true or false
end

-- Exact physical-location gate. A queued expedition or an active CW mission is
-- intentionally insufficient: only the keep chamber level is `morris_hub`.
local function in_pilgrimage_chamber(level_override)
    if level_override ~= nil then return level_override == "morris_hub" end
    local lth = Managers and Managers.level_transition_handler
    local ok, key = pcall(function()
        return lth and lth:get_current_level_key()
    end)
    return ok and key == "morris_hub"
end
mod._ct505_in_pilgrimage_chamber = in_pilgrimage_chamber

-- Returns the active DeusMechanism (only that class carries debug_load_deus_level),
-- or nil when the current mechanism is Adventure/Versus. Same accessor idiom as
-- ct's on_injected_adventure_level (chaos_wastes_tweaker_dev.lua:5032).
local function get_deus_mechanism()
    local mm = Managers and Managers.mechanism
    local mech = mm and mm.game_mechanism and mm:game_mechanism()
    if mech and type(mech.debug_load_deus_level) == "function" then return mech end
    return nil
end

local function current_difficulty()
    local ok, d = pcall(function()
        return Managers.state and Managers.state.difficulty and Managers.state.difficulty:get_difficulty()
    end)
    if ok and type(d) == "string" and DIFF_SET[d] then return d end
    return "cataclysm"
end

-- The single load primitive. opts fields (all optional except level_key):
--   level_key, difficulty, progress (0..1), level_seed, with_belakor,
--   curse, modifier1, modifier2.
local function do_load(opts)
    if not is_host() then
        mod:echo("Single Mission Loader is host-only (the host drives the Chaos Wastes run).")
        return false
    end
    if not in_pilgrimage_chamber() then
        mod:echo("Single Mission Loader can only launch from the Pilgrimage Chamber. Enter the Chaos Wastes chamber through the keep door, then try again.")
        return false
    end
    local mech = get_deus_mechanism()
    if not mech then
        mod:echo("The Pilgrimage Chamber's Chaos Wastes mechanism is not ready yet. Wait for the chamber to finish loading, then try again.")
        return false
    end

    local level_key = resolve_alias(opts.level_key)

    -- A curse is read during graph generation. Always clear the loader's removed
    -- legacy blessing override so an old setting cannot leak into this run.
    script_data.deus_force_load_curse = opts.curse or nil
    script_data.deus_force_load_blessing = nil

    -- Rebuild the debug node's mutator list: the two base tweaks it always carries
    -- (deus_default_graph_settings.lua:1550-1553) + any chosen minor modifiers.
    local dbg = rawget(_G, "DeusDebugSpecificNodeGraph")
    if dbg and dbg.start then
        local muts = { "deus_pacing_tweak", "deus_difficulty_tweak" }
        if opts.modifier1 then muts[#muts + 1] = opts.modifier1 end
        if opts.modifier2 then muts[#muts + 1] = opts.modifier2 end
        dbg.start.mutators = muts
    end

    local difficulty = opts.difficulty or current_difficulty()
    -- Canonical final boundary for menu, command, and any future caller. Vanilla
    -- asserts when a weapon chest sees run_progress >= 1.0 (#505 crash log).
    local progress = Cat.sanitize_progress(opts.progress)
    local level_seed = opts.level_seed or 0
    local with_belakor = opts.with_belakor and true or false

    local starting_boons = type(mod._ct_collect_start_boons) == "function" and mod._ct_collect_start_boons() or {}
    mod:echo("Loading mission %s | diff=%s progress=%d%% curse=%s mods=[%s, %s] starting_boons=%d belakor=%s",
        level_key, tostring(difficulty), math.floor(progress * 100 + 0.5),
        tostring(opts.curse or "none"), tostring(opts.modifier1 or "none"),
        tostring(opts.modifier2 or "none"), #starting_boons, tostring(with_belakor))
    -- Always-on telemetry (user plays with mod-logging off): [ct:505] greps back to the issue.
    pcall(printf, "[ct:505] single_mission_load level=%s diff=%s progress=%s curse=%s mod1=%s mod2=%s starting_boons=%d belakor=%s",
        level_key, tostring(difficulty), tostring(progress), tostring(opts.curse),
        tostring(opts.modifier1), tostring(opts.modifier2), #starting_boons, tostring(with_belakor))

    local ok, err = pcall(function()
        mech:debug_load_deus_level(level_key, difficulty, progress, level_seed, with_belakor)
    end)
    if not ok then
        mod:echo("Load failed: %s -- is the level key valid? (run /ct_list_missions)", tostring(err))
        pcall(printf, "[ct:505] single_mission_load FAILED level=%s err=%s", level_key, tostring(err))
        return false
    end
    return true
end
mod._ct_dev_mission_do_load = do_load

-- ===========================================================================
-- Menu "Load now" keybind target (reads the dropdown settings)
-- ===========================================================================
mod.ct_dev_load_selected_mission = function()
    local mission = Cat.MISSIONS[mod:get("ctdm_base") or 1]
    if not mission then
        mod:echo("Pick a mission in the Single Mission Loader menu first.")
        return
    end
    local diff_i = mod:get("ctdm_difficulty") or 0
    local curse_i = mod:get("ctdm_curse") or 0
    local mod1_i = mod:get("ctdm_modifier1") or 0
    local mod2_i = mod:get("ctdm_modifier2") or 0
    local curse = (curse_i > 0) and Cat.CURSES[curse_i] or nil
    local level_key, theme, path = Cat.compose_level_key(mission.key, curse, rawget(_G, "DEUS_LEVEL_SETTINGS"))
    local resolved = resolve_alias(level_key)
    local available = rawget(_G, "LevelSettings")
    if available and not rawget(available, resolved) then
        mod:echo("Mission '%s' is unavailable with theme=%s path=%s. Check DLC ownership and installed level data.", mission.name, theme, tostring(path))
        return
    end
    do_load({
        level_key    = level_key,
        difficulty   = (diff_i > 0) and Cat.DIFFICULTIES[diff_i] or nil,
        progress     = Cat.PROGRESS[mod:get("ctdm_progress") or 1] or 0,
        curse        = curse,
        modifier1    = (mod1_i > 0) and Cat.MODIFIERS[mod1_i] or nil,
        modifier2    = (mod2_i > 0) and Cat.MODIFIERS[mod2_i] or nil,
        with_belakor = mod:get("ctdm_with_belakor") and true or false,
    })
end

-- ===========================================================================
-- Chat commands (the primary lever; menu-independent)
-- ===========================================================================

-- Accept either a fraction (0..1) or the vanilla debug convention where 900 == 0.9.
local function parse_progress(s)
    local n = tonumber(s)
    if not n then return nil end
    if n > 1 then n = n / 1000 end
    return Cat.sanitize_progress(n)
end

-- Commands advertise catalog base keys. Also recognize an older composite key
-- by its catalog prefix, then rebuild it so curse/theme/path cannot contradict.
local function catalog_base_for(level_key)
    if Cat.MISSION_INDEX_BY_KEY[level_key] then return level_key end
    for _, mission in ipairs(Cat.MISSIONS) do
        if string.sub(level_key, 1, #mission.key + 1) == mission.key .. "_" then return mission.key end
    end
    return nil
end

mod:command("ct_load_mission",
    "Host: load one mission from the Pilgrimage Chamber. Args: <mission_key> [progress 0-1] [curse] [difficulty]",
    function(level_key, progress, curse, difficulty)
        if not level_key or level_key == "" then
            mod:echo("Usage: /ct_load_mission <mission_key> [progress 0-1] [curse] [difficulty]. Run /ct_list_missions for keys.")
            return
        end
        if curse and curse ~= "" and not CURSE_SET[curse] then
            mod:echo("Unknown curse '%s'. Run /ct_list_curses.", tostring(curse))
            return
        end
        if difficulty and difficulty ~= "" and not DIFF_SET[difficulty] then
            mod:echo("Unknown difficulty '%s'. Valid: normal hard harder hardest cataclysm cataclysm_2 cataclysm_3.", tostring(difficulty))
            return
        end
        local base = catalog_base_for(level_key)
        if not base then
            mod:echo("Unknown mission key '%s'. Run /ct_list_missions.", tostring(level_key))
            return
        end
        local selected_curse = (curse ~= "" and curse) or nil
        local composed = Cat.compose_level_key(base, selected_curse, rawget(_G, "DEUS_LEVEL_SETTINGS"))
        do_load({
            level_key  = composed,
            progress   = parse_progress(progress) or 0,
            curse      = selected_curse,
            difficulty = (difficulty ~= "" and difficulty) or nil,
        })
    end)

mod:command("ct_list_missions",
    "List Single Mission Loader missions by user-facing category (optional substring filter)",
    function(filter)
        pcall(printf, "[ct:505] /ct_list_missions filter=%s", tostring(filter or ""))
        for _, category in ipairs(Cat.CATEGORIES) do
            local rows = {}
            for _, mission in ipairs(Cat.MISSIONS) do
                local haystack = mission.name .. " " .. mission.key
                if mission.category == category and (not filter or filter == "" or string.find(string.lower(haystack), string.lower(filter), 1, true)) then
                    rows[#rows + 1] = mission.name .. " (" .. mission.key .. ")"
                end
            end
            mod:echo("%s: %s", category, (#rows > 0 and table.concat(rows, ", ")) or "(none)")
        end
    end)

-- Clears the script_data overrides. deus_force_load_curse is debug-node-only
-- (harmless in normal runs), but deus_force_load_blessing is read by the general
-- get_blessings path (deus_run_state.lua:169), so a blessing chosen via this tool
-- would otherwise carry into the NEXT ordinary CW run until re-loaded with None.
mod:command("ct_clear_force", "Clear forced curse and modifiers set by Single Mission Loader", function()
    script_data.deus_force_load_curse = nil
    script_data.deus_force_load_blessing = nil
    local dbg = rawget(_G, "DeusDebugSpecificNodeGraph")
    if dbg and dbg.start then dbg.start.mutators = { "deus_pacing_tweak", "deus_difficulty_tweak" } end
    mod:echo("Cleared forced curse, legacy blessing override, and minor modifiers.")
end)

mod:command("ct_list_curses", "List CW curse names by god (for /ct_load_mission)", function()
    for _, grp in ipairs(Cat.CURSES_BY_GOD) do
        mod:echo("%s: %s", grp.god, table.concat(grp.curses, ", "))
    end
end)

mod:command("ct_list_modifiers", "List CW minor modifiers for Single Mission Loader", function()
    mod:echo("Minor modifiers: %s", table.concat(Cat.MODIFIERS, ", "))
end)

-- Issue 505 redesign: user-facing content-family chips for the mission
-- dropdown, via gut's filtered-dropdown API (gut_dev 0.2.224-dev). Dropdown
-- VALUES are 1-based indices into Cat.MISSIONS, so each match fn resolves
-- the level key first (the key-list form would test raw indices - wrong here).
-- Nil-safe: gut absent or pre-0.2.224 = silent no-op, the dropdown still gets
-- gut's generic type-to-filter when present, and stays a plain VMF dropdown
-- without gut. No other file assigns mod.on_all_mods_loaded (grep-clean).
mod.on_all_mods_loaded = function()
    local gut = get_mod("gut_dev") or get_mod("gut")
    if not (gut and gut.mod_tweaker and gut.mod_tweaker.register_dropdown_categories) then return end
    local MISSIONS = Cat.MISSIONS
    local categories = {}
    for _, category in ipairs(Cat.CATEGORIES) do
        local owned_category = category
        categories[#categories + 1] = {
            label = owned_category,
            match = function(value)
                local mission = MISSIONS[value]
                return mission ~= nil and mission.category == owned_category
            end,
        }
    end
    gut.mod_tweaker:register_dropdown_categories("ct_dev", "ctdm_base", categories)
    pcall(printf, "[ct:505] mission dropdown categories registered with gut filtered-dropdown API")
end

mod._ct_dev_mission_loaded = true
mod._ct_dev_mission_catalog = Cat
mod._ct505_uses_starting_boons = true
pcall(printf, "[ct:505] Single Mission Loader registered (/ct_load_mission, /ct_list_missions, keybind ct_dev_load_selected_mission)")
