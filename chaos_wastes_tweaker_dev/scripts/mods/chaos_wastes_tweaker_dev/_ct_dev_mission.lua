local mod = get_mod("ct_dev")
local Cat = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_dev_mission_catalog")

-- _ct_dev_mission.lua - Single Mission dev loader (issue 505).
--
-- The verification lever for the ct critical cluster: forces the game to load one
-- specific Chaos Wastes mission with a chosen curse, minor modifiers, starting
-- blessing, base difficulty and depth, so a bug that needs a particular
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
--   * script_data.deus_force_load_blessing is appended to the run's blessing list
--     (deus_run_state.lua:169-170).
--   * Minor modifiers are appended to the debug node's mutator list. table.clone in
--     deus_generate_graph is shallow, so DeusDebugSpecificNodeGraph.start is the
--     very table the loaded node uses - we rebuild .mutators just before the load.
--
-- HOST-ONLY (debug_load_deus_level runs _setup_run as server + pushes the run to
-- clients) and DEUS-MECHANISM-ONLY (the method only exists on DeusMechanism, so
-- you must already be inside a CW expedition). Solo host+bots is the guaranteed
-- path; the co-op caveat is in the CHANGELOG (script_data is per-machine, so a
-- forced curse/modifier applies host-side - clients loading the same seed get the
-- same base level).
--
-- Owned by: chaos_wastes_tweaker_dev.lua entry point. Consumed via: mod:dofile.
-- No mod:hook here (grep-clean) - forcing is done entirely through script_data +
-- the vanilla debug entry point, so there is no (Class, method) to collide with.

-- Validation sets (built once from the catalog).
local CURSE_SET, DIFF_SET, MOD_SET, BLESS_SET = {}, {}, {}, {}
do
    for _, c in ipairs(Cat.CURSES) do CURSE_SET[c] = true end
    for _, d in ipairs(Cat.DIFFICULTIES) do DIFF_SET[d] = true end
    for _, m in ipairs(Cat.MODIFIERS) do MOD_SET[m] = true end
    for _, b in ipairs(Cat.BLESSINGS) do BLESS_SET[b] = true end
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
--   curse, modifier1, modifier2, blessing.
local function do_load(opts)
    if not is_host() then
        mod:echo("Single Mission Loader is host-only (the host drives the Chaos Wastes run).")
        return false
    end
    local mech = get_deus_mechanism()
    if not mech then
        mod:echo("No active Chaos Wastes run. Start a Chaos Wastes expedition first, then load from the CW map screen or a CW mission.")
        return false
    end

    local level_key = resolve_alias(opts.level_key)

    -- Forced curse / blessing are read at graph-gen / run-setup time from these
    -- globals; set them fresh every load (nil clears) so no stale state carries.
    script_data.deus_force_load_curse = opts.curse or nil
    script_data.deus_force_load_blessing = opts.blessing or nil

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
    local progress = opts.progress or 0
    local level_seed = opts.level_seed or 0
    local with_belakor = opts.with_belakor and true or false

    mod:echo("Loading CW mission %s | diff=%s depth=%d%% curse=%s mods=[%s, %s] blessing=%s belakor=%s",
        level_key, tostring(difficulty), math.floor(progress * 100 + 0.5),
        tostring(opts.curse or "none"), tostring(opts.modifier1 or "none"),
        tostring(opts.modifier2 or "none"), tostring(opts.blessing or "none"), tostring(with_belakor))
    -- Always-on telemetry (user plays with mod-logging off): [ct:505] greps back to the issue.
    pcall(printf, "[ct:505] single_mission_load level=%s diff=%s progress=%s curse=%s mod1=%s mod2=%s blessing=%s belakor=%s",
        level_key, tostring(difficulty), tostring(progress), tostring(opts.curse),
        tostring(opts.modifier1), tostring(opts.modifier2), tostring(opts.blessing), tostring(with_belakor))

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
    local base = Cat.BASE_LEVELS[mod:get("ctdm_base") or 1]
    local theme = Cat.THEMES[mod:get("ctdm_theme") or 1]
    local path = mod:get("ctdm_path") or 1
    if not (base and theme) then
        mod:echo("Pick a mission and god theme in the Single Mission Loader menu first.")
        return
    end
    local diff_i = mod:get("ctdm_difficulty") or 0
    local curse_i = mod:get("ctdm_curse") or 0
    local mod1_i = mod:get("ctdm_modifier1") or 0
    local mod2_i = mod:get("ctdm_modifier2") or 0
    local bless_i = mod:get("ctdm_blessing") or 0
    do_load({
        level_key    = base .. "_" .. theme .. "_path" .. tostring(path),
        difficulty   = (diff_i > 0) and Cat.DIFFICULTIES[diff_i] or nil,
        progress     = Cat.PROGRESS[mod:get("ctdm_progress") or 1] or 0,
        curse        = (curse_i > 0) and Cat.CURSES[curse_i] or nil,
        modifier1    = (mod1_i > 0) and Cat.MODIFIERS[mod1_i] or nil,
        modifier2    = (mod2_i > 0) and Cat.MODIFIERS[mod2_i] or nil,
        blessing     = (bless_i > 0) and Cat.BLESSINGS[bless_i] or nil,
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
    if n < 0 then n = 0 elseif n > 1 then n = 1 end
    return n
end

mod:command("ct_load_mission",
    "Host: load one CW mission now. Args: <level_key> [progress 0-1] [curse] [difficulty]",
    function(level_key, progress, curse, difficulty)
        if not level_key or level_key == "" then
            mod:echo("Usage: /ct_load_mission <level_key> [progress 0-1] [curse] [difficulty]. Run /ct_list_missions for keys.")
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
        do_load({
            level_key  = level_key,
            progress   = parse_progress(progress) or 0,
            curse      = (curse ~= "" and curse) or nil,
            difficulty = (difficulty ~= "" and difficulty) or nil,
        })
    end)

mod:command("ct_list_missions",
    "List loadable CW mission base keys by pool (optional substring filter)",
    function(filter)
        local rc
        local mech = get_deus_mechanism()
        if mech and mech.get_deus_run_controller then rc = mech:get_deus_run_controller() end
        local journey = (rc and rc.get_journey_name and rc:get_journey_name()) or "journey_ruin"
        local ps = rawget(_G, "DEUS_MAP_POPULATE_SETTINGS")
        local cfg = ps and (ps[journey] or ps.journey_ruin)
        local avail = cfg and cfg.LEVEL_AVAILABILITY
        if type(avail) ~= "table" then
            mod:echo("Mission pool not available (is the Chaos Wastes DLC loaded?).")
            return
        end
        -- Native base set (to flag ct-injected adventure maps).
        local native = {}
        for _, k in ipairs(Cat.BASE_LEVELS) do native[k] = true end
        mod:echo("=== CW missions for %s (compose <base>_<theme>_path<N>; see log for full list) ===", journey)
        pcall(printf, "[ct:505] /ct_list_missions journey=%s filter=%s", journey, tostring(filter or ""))
        for _, pool in ipairs({ "TRAVEL", "SIGNATURE" }) do
            local keys = {}
            for base, data in pairs(avail[pool] or {}) do
                if (not filter or filter == "" or string.find(base, filter, 1, true)) then
                    local themes, paths = {}, {}
                    for _, t in ipairs(data.themes or {}) do themes[#themes + 1] = t end
                    for _, p in ipairs(data.paths or {}) do paths[#paths + 1] = tostring(p) end
                    local tag = native[base] and "" or " (injected)"
                    keys[#keys + 1] = base .. tag
                    pcall(printf, "[ct:505]   %s %s%s themes={%s} paths={%s}",
                        pool, base, tag, table.concat(themes, ","), table.concat(paths, ","))
                end
            end
            table.sort(keys)
            mod:echo("%s: %s", pool, (#keys > 0 and table.concat(keys, ", ")) or "(none)")
        end
    end)

-- Clears the script_data overrides. deus_force_load_curse is debug-node-only
-- (harmless in normal runs), but deus_force_load_blessing is read by the general
-- get_blessings path (deus_run_state.lua:169), so a blessing chosen via this tool
-- would otherwise carry into the NEXT ordinary CW run until re-loaded with None.
mod:command("ct_clear_force", "Clear forced curse/blessing/modifiers set by the Single Mission loader", function()
    script_data.deus_force_load_curse = nil
    script_data.deus_force_load_blessing = nil
    local dbg = rawget(_G, "DeusDebugSpecificNodeGraph")
    if dbg and dbg.start then dbg.start.mutators = { "deus_pacing_tweak", "deus_difficulty_tweak" } end
    mod:echo("Cleared forced curse, blessing and minor modifiers.")
end)

mod:command("ct_list_curses", "List CW curse names by god (for /ct_load_mission)", function()
    for _, grp in ipairs(Cat.CURSES_BY_GOD) do
        mod:echo("%s: %s", grp.god, table.concat(grp.curses, ", "))
    end
end)

mod:command("ct_list_modifiers", "List CW minor modifiers and blessings (for the menu / loader)", function()
    mod:echo("Minor modifiers: %s", table.concat(Cat.MODIFIERS, ", "))
    mod:echo("Blessings: %s", table.concat(Cat.BLESSINGS, ", "))
end)

-- Issue 505 spec completion: Travel/Signature category chips for the mission
-- dropdown, via gut's filtered-dropdown API (gut_dev 0.2.224-dev). Dropdown
-- VALUES are 1-based indices into Cat.BASE_LEVELS, so each match fn resolves
-- the level key first (the key-list form would test raw indices - wrong here).
-- Nil-safe: gut absent or pre-0.2.224 = silent no-op, the dropdown still gets
-- gut's generic type-to-filter when present, and stays a plain VMF dropdown
-- without gut. No other file assigns mod.on_all_mods_loaded (grep-clean).
mod.on_all_mods_loaded = function()
    local gut = get_mod("gut_dev") or get_mod("gut")
    if not (gut and gut.mod_tweaker and gut.mod_tweaker.register_dropdown_categories) then return end
    local BASE = Cat.BASE_LEVELS
    gut.mod_tweaker:register_dropdown_categories("ct_dev", "ctdm_base", {
        { label = "Travel",    match = function(value) local k = BASE[value]; return k ~= nil and k:sub(1, 4) ~= "sig_" end },
        { label = "Signature", match = function(value) local k = BASE[value]; return k ~= nil and k:sub(1, 4) == "sig_" end },
    })
    pcall(printf, "[ct:505] mission dropdown categories registered with gut filtered-dropdown API")
end

mod._ct_dev_mission_loaded = true
pcall(printf, "[ct:505] single-mission dev loader registered (/ct_load_mission, /ct_list_missions, keybind ct_dev_load_selected_mission)")
