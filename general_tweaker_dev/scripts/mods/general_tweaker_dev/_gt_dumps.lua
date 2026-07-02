local mod = get_mod("gt_dev")

-- _gt_dumps.lua — verbose console-dump commands (level / glossary / cosmetics / items / hero-view)
--
-- Owns gt's read-only introspection commands that walk live engine state and
-- echo a snapshot to the console log: /dump_level (full level/world/pickups/
-- breeds/UI), /dump_glossary, /dump_cosmetics, /dump_items_by_slot,
-- /dump_hero_view. All are command-only (NO hooks) and side-effect-free
-- apart from logging. Extracted from general_tweaker_dev.lua (v0.2.132-dev,
-- "refactor: extract dump commands + item spawner to modules — no behavior
-- change"). Depends only on `mod` + game globals; runs after the main chunk
-- via the mod:dofile chain, so any mod._* fields are already set.
--
-- Owned by: general_tweaker_dev.lua entry point. Consumed via: mod:dofile.

-- ============================================================
-- Level Dump (verbose snapshot of the currently-loaded level)
-- ============================================================
-- One-shot console command walking runtime state worth capturing while
-- modding (identity, worlds + unit counts, pickup spawners + live pickups,
-- CW deus units, interactables, breed roster, terror events, UI/HUD).
-- Doctrine:
--   * Every section is wrapped in pcall — one missing field can't tank the rest.
--   * Runtime introspection only — managers/extensions are existence-checked
--     (rawget / `Managers.*`) before use, so it never crashes in the inn etc.
--   * Heavy data -> mod:info (console-*.log); headers + summary -> mod:info +
--     mod:echo. No disk side-car (VMF has no usable file-write API).

local _LD_PREFIX = "[level_dump]"

mod:command("dump_level", "Verbose level/world/pickups/breeds/UI snapshot (best run AFTER you've entered the area you want to capture)", function()
    local out_lines = {}
    local function out(fmt, ...)
        local line
        if select("#", ...) > 0 then
            line = string.format(fmt, ...)
        else
            line = fmt
        end
        out_lines[#out_lines + 1] = line
        mod:info("%s %s", _LD_PREFIX, line)
    end
    local function section(name)
        out("=========== %s ===========", name)
    end
    local function section_fail(name, err)
        out("%s section %s failed: %s", _LD_PREFIX, name, tostring(err))
    end
    local function safe(name, fn)
        local ok, err = pcall(fn)
        if not ok then section_fail(name, err) end
    end

    local ts = os and os.time and os.time() or 0
    out("=== /dump_level start (unix_ts=%s) ===", tostring(ts))

    -- ---------- 1) Identity ----------
    local level_key_for_filename = "unknown"
    safe("1 identity", function()
        section("1) Identity")

        local lth = rawget(_G, "Managers") and Managers.level_transition_handler
        if lth and lth.get_current_level_key then
            local lk = lth:get_current_level_key()
            out("LevelTransitionHandler.current_level_key = %s", tostring(lk))
            level_key_for_filename = tostring(lk or "unknown")
            if lth.get_current_level_keys then
                local _, sub = pcall(function() return select(2, lth:get_current_level_keys()) end)
                if sub then out("LevelTransitionHandler.current_sub_level_key = %s", tostring(sub)) end
            end
            if lth.get_current_level_seed then
                out("LevelTransitionHandler.current_level_seed = %s", tostring(lth:get_current_level_seed()))
            end
            if lth.get_current_environment_variation_name then
                local _, env = pcall(lth.get_current_environment_variation_name, lth)
                out("LevelTransitionHandler.environment_variation = %s", tostring(env))
            end
        else
            out("LevelTransitionHandler: (not available)")
        end

        local gm = Managers and Managers.state and Managers.state.game_mode
        if gm then
            if gm.game_mode_key then out("GameModeManager.game_mode_key = %s", tostring(gm:game_mode_key())) end
            if gm.level_key      then out("GameModeManager.level_key = %s", tostring(gm:level_key())) end
            local mode = gm.game_mode and gm:game_mode()
            if mode then
                out("GameModeManager._game_mode class.NAME = %s", tostring(mode.NAME or mode.__class_name or "?"))
                if mode.settings then
                    local _, s = pcall(mode.settings, mode)
                    if type(s) == "table" then
                        out("game_mode:settings().key = %s", tostring(s.key))
                        out("game_mode:settings().mutators_allowed = %s", tostring(s.mutators_allowed))
                    end
                end
                if mode.game_mode_state then
                    local _, st = pcall(mode.game_mode_state, mode)
                    out("game_mode:game_mode_state() = %s", tostring(st))
                end
            end
        else
            out("GameModeManager: (none — likely state_loading or main menu)")
        end

        local mech_mgr = Managers and Managers.mechanism
        if mech_mgr and mech_mgr.current_mechanism_name then
            out("Mechanism.current_mechanism_name = %s", tostring(mech_mgr:current_mechanism_name()))
        end

        local conflict = Managers and Managers.state and Managers.state.conflict
        if conflict then
            out("ConflictDirector.current_conflict_settings = %s", tostring(conflict.current_conflict_settings))
            if conflict.level_settings then
                out("ConflictDirector.level_settings.level_id = %s", tostring(conflict.level_settings.level_id or conflict.level_settings.display_name))
            end
        else
            out("ConflictDirector: (not in a mission)")
        end

        local diff_mgr = Managers and Managers.state and Managers.state.difficulty
        if diff_mgr and diff_mgr.get_difficulty then
            local _, d = pcall(diff_mgr.get_difficulty, diff_mgr)
            out("DifficultyManager.get_difficulty = %s", tostring(d))
            if diff_mgr.get_difficulty_rank then
                local _, dr = pcall(diff_mgr.get_difficulty_rank, diff_mgr)
                out("DifficultyManager.get_difficulty_rank = %s", tostring(dr))
            end
        end

        local lk = (gm and gm.level_key and gm:level_key()) or "?"
        local mission_settings = rawget(_G, "MissionSettings")
        if mission_settings and mission_settings[lk] then
            out("MissionSettings[%s] = (present)", tostring(lk))
        else
            out("MissionSettings[%s] = (none — likely not a story mission)", tostring(lk))
        end

        if rawget(_G, "Application") then
            if Application.platform then out("Application.platform() = %s", tostring(Application.platform())) end
            if Application.build    then out("Application.build()    = %s", tostring(Application.build())) end
        end
    end)

    -- ---------- 2) Worlds + units overview ----------
    local level_world = nil
    safe("2 worlds", function()
        section("2) Worlds + units overview")
        local wm = Managers and Managers.world
        if not (wm and wm._worlds) then out("WorldManager: (none)"); return end
        local names = {}
        for name in pairs(wm._worlds) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            local world = wm._worlds[name]
            local n_units = 0
            local ok, units = pcall(World.units, world)
            if ok and type(units) == "table" then n_units = #units end
            out("world '%s' -> %d unit(s)", name, n_units)
            if name == (rawget(_G, "LevelHelper") and LevelHelper.INGAME_WORLD_NAME or "level_world") then
                level_world = world
            end
        end

        if not level_world then out("level_world: (not found — early game state?)"); return end

        local units = World.units(level_world)
        local total = #units
        local with_interactable, with_pickup, with_pickup_spawner = 0, 0, 0
        local with_deus_chest, with_deus_cursed_chest, with_deus_relic = 0, 0, 0
        local with_deus_arena_idol, with_deus_arena_interactable = 0, 0
        local with_deus_belakor = 0
        for _, u in ipairs(units) do
            if Unit.alive(u) then
                if ScriptUnit.has_extension(u, "interactable_system") then with_interactable = with_interactable + 1 end
                if ScriptUnit.has_extension(u, "pickup_system") then
                    with_pickup = with_pickup + 1
                    -- PickupSpawnerExtension is also under pickup_system; identify via the spawner's no-pickup_name init.
                    local ext = ScriptUnit.extension(u, "pickup_system")
                    if ext and ext.get_spawn_location_data and not ext.pickup_name then
                        with_pickup_spawner = with_pickup_spawner + 1
                    end
                end
                if ScriptUnit.has_extension(u, "deus_cursed_chest_system") then with_deus_cursed_chest = with_deus_cursed_chest + 1 end
                if ScriptUnit.has_extension(u, "deus_relic_system") then with_deus_relic = with_deus_relic + 1 end
                if ScriptUnit.has_extension(u, "deus_arena_idol_system") then with_deus_arena_idol = with_deus_arena_idol + 1 end
                if ScriptUnit.has_extension(u, "deus_arena_interactable_system") then with_deus_arena_interactable = with_deus_arena_interactable + 1 end
                if ScriptUnit.has_extension(u, "deus_belakor_locus_system")
                   or ScriptUnit.has_extension(u, "deus_belakor_totem_system")
                   or ScriptUnit.has_extension(u, "deus_belakor_crystal_system") then
                    with_deus_belakor = with_deus_belakor + 1
                end
                -- DeusChestExtension is also under pickup_system; sniff by field.
                local pe = ScriptUnit.has_extension(u, "pickup_system")
                if pe and pe._is_server ~= nil and pe._deus_run_controller then
                    with_deus_chest = with_deus_chest + 1
                end
            end
        end
        out("level_world unit totals: %d total, interactables=%d, pickup_system=%d (of which spawners=%d)",
            total, with_interactable, with_pickup, with_pickup_spawner)
        out("level_world deus units: chests=%d cursed_chests=%d relics=%d arena_idol=%d arena_interactable=%d belakor=%d",
            with_deus_chest, with_deus_cursed_chest, with_deus_relic, with_deus_arena_idol, with_deus_arena_interactable, with_deus_belakor)
    end)

    -- ---------- 3) Pickup spawners + live pickups ----------
    safe("3 pickups", function()
        section("3) Pickup spawners + currently-alive pickups")
        local entity_mgr = Managers and Managers.state and Managers.state.entity
        local pickup_system = entity_mgr and entity_mgr.system and entity_mgr:system("pickup_system")
        if not pickup_system then out("(none — no pickup_system; not in a mission?)"); return end

        local function dump_spawner_bucket(bucket_name, bucket)
            if type(bucket) ~= "table" then return end
            local n = 0
            for _ in pairs(bucket) do n = n + 1 end
            out("--- pickup_system.%s (%d) ---", bucket_name, n)
            -- Buckets are usually keyed; walk values, log spawner_id (key) + pickup_name + position.
            for key, entry in pairs(bucket) do
                local pickup_name, unit
                if type(entry) == "table" then
                    pickup_name = entry.pickup_name
                    unit = entry.unit or entry[1]
                end
                local pos_str = "?"
                if unit and Unit.alive(unit) then
                    local ok, p = pcall(Unit.world_position, unit, 0)
                    if ok and p then pos_str = string.format("(%.1f,%.1f,%.1f)", Vector3.to_elements(p)) end
                end
                out("  spawner key=%s pickup_name=%s pos=%s", tostring(key), tostring(pickup_name), pos_str)
            end
        end
        dump_spawner_bucket("guaranteed_pickup_spawners", pickup_system.guaranteed_pickup_spawners)
        dump_spawner_bucket("triggered_pickup_spawners",  pickup_system.triggered_pickup_spawners)
        dump_spawner_bucket("primary_pickup_spawners",    pickup_system.primary_pickup_spawners)
        dump_spawner_bucket("secondary_pickup_spawners",  pickup_system.secondary_pickup_spawners)
        dump_spawner_bucket("specified_pickup_spawners",  pickup_system.specified_pickup_spawners)

        -- _pickup_units_by_type is the live-spawned units table, keyed by pickup_name (every AllPickups key).
        local by_type = pickup_system._pickup_units_by_type
        if type(by_type) ~= "table" then out("(_pickup_units_by_type missing)"); return end

        local names = {}
        for name in pairs(by_type) do names[#names + 1] = name end
        table.sort(names)
        out("--- _pickup_units_by_type (currently-spawned units, by pickup_name) ---")
        local total_alive = 0
        local summary = {}
        for _, name in ipairs(names) do
            local arr = by_type[name]
            local count = 0
            for i = 1, #arr do
                local u = arr[i]
                if u and Unit.alive(u) then count = count + 1 end
            end
            if count > 0 then
                summary[#summary + 1] = string.format("%s=%d", name, count)
                total_alive = total_alive + count
                local pickup_settings = rawget(_G, "AllPickups") and AllPickups[name]
                local category = pickup_settings and (pickup_settings.spawn_category or pickup_settings.type) or "?"
                out("  %-40s alive=%d  category=%s", name, count, tostring(category))
                for i = 1, #arr do
                    local u = arr[i]
                    if u and Unit.alive(u) then
                        local ext = ScriptUnit.has_extension(u, "pickup_system")
                        local pos_str = "?"
                        local ok, p = pcall(Unit.world_position, u, 0)
                        if ok and p then pos_str = string.format("(%.1f,%.1f,%.1f)", Vector3.to_elements(p)) end
                        local picked_up = ext and (ext.picked_up == true or ext._picked_up == true)
                        out("      pos=%s spawn_type=%s spawn_index=%s picked_up=%s",
                            pos_str,
                            tostring(ext and ext.spawn_type),
                            tostring(ext and ext.spawn_index),
                            tostring(picked_up))
                    end
                end
            end
        end
        out("pickup-by-type summary: total_alive=%d  [%s]", total_alive, table.concat(summary, ", "))
    end)

    -- ---------- 4) Chaos Wastes objective / chest / relic locations ----------
    safe("4 deus", function()
        section("4) Chaos Wastes deus units (chests / cursed chests / relics / arena)")
        local mech_name = Managers and Managers.mechanism and Managers.mechanism.current_mechanism_name
            and Managers.mechanism:current_mechanism_name() or nil
        local lk = Managers and Managers.state and Managers.state.game_mode
            and Managers.state.game_mode.level_key and Managers.state.game_mode:level_key() or nil
        local is_deus = mech_name == "deus" or (lk and string.find(tostring(lk), "^dlc_morris"))
        if not is_deus then
            out("(not a Chaos Wastes run — mechanism=%s level=%s)", tostring(mech_name), tostring(lk))
            return
        end
        if not level_world then out("(no level_world to scan)"); return end

        local function dump_deus_kind(label, system_name, extra_fn)
            local found = 0
            for _, u in ipairs(World.units(level_world)) do
                if Unit.alive(u) then
                    local ext = ScriptUnit.has_extension(u, system_name)
                    if ext then
                        found = found + 1
                        local pos_str = "?"
                        local ok, p = pcall(Unit.world_position, u, 0)
                        if ok and p then pos_str = string.format("(%.1f,%.1f,%.1f)", Vector3.to_elements(p)) end
                        local extras = extra_fn and extra_fn(ext) or ""
                        out("  %s pos=%s%s", label, pos_str, extras)
                    end
                end
            end
            out("%s total = %d", label, found)
        end

        dump_deus_kind("DeusCursedChest",        "deus_cursed_chest_system")
        dump_deus_kind("DeusRelic",              "deus_relic_system")
        dump_deus_kind("DeusArenaIdol",          "deus_arena_idol_system")
        dump_deus_kind("DeusArenaInteractable",  "deus_arena_interactable_system")
        dump_deus_kind("DeusBelakorLocus",       "deus_belakor_locus_system")
        dump_deus_kind("DeusBelakorTotem",       "deus_belakor_totem_system")
        dump_deus_kind("DeusBelakorCrystal",     "deus_belakor_crystal_system")
        dump_deus_kind("DeusBelakorStatueSocket","deus_belakor_statue_socket_system")
        dump_deus_kind("DeusArenaBelakorStatue", "deus_arena_belakor_big_statue_system")

        -- DeusChestExtension lives under pickup_system; identify via fields.
        local found_chests = 0
        for _, u in ipairs(World.units(level_world)) do
            if Unit.alive(u) then
                local ext = ScriptUnit.has_extension(u, "pickup_system")
                if ext and ext._deus_run_controller then
                    found_chests = found_chests + 1
                    local pos_str = "?"
                    local ok, p = pcall(Unit.world_position, u, 0)
                    if ok and p then pos_str = string.format("(%.1f,%.1f,%.1f)", Vector3.to_elements(p)) end
                    local chest_type = ext.get_chest_type and select(2, pcall(ext.get_chest_type, ext)) or "?"
                    local rarity = ext.get_rarity and select(2, pcall(ext.get_rarity, ext)) or "?"
                    local purchased = ext._is_purchased
                    out("  DeusChest pos=%s chest_type=%s rarity=%s purchased=%s",
                        pos_str, tostring(chest_type), tostring(rarity), tostring(purchased))
                end
            end
        end
        out("DeusChest total = %d", found_chests)
    end)

    -- ---------- 5) Interactable inventory ----------
    safe("5 interactables", function()
        section("5) Interactable units on level_world")
        if not level_world then out("(no level_world)"); return end
        local by_type = {}
        local total = 0
        for _, u in ipairs(World.units(level_world)) do
            if Unit.alive(u) then
                local ext = ScriptUnit.has_extension(u, "interactable_system")
                if ext then
                    total = total + 1
                    local itype = (ext.interaction_type and select(2, pcall(ext.interaction_type, ext)))
                        or ext.interactable_type or "?"
                    by_type[itype] = (by_type[itype] or 0) + 1
                    local pos_str = "?"
                    local ok, p = pcall(Unit.world_position, u, 0)
                    if ok and p then pos_str = string.format("(%.1f,%.1f,%.1f)", Vector3.to_elements(p)) end
                    local hud_desc = Unit.get_data(u, "interaction_data", "hud_description")
                    local item_name = Unit.get_data(u, "interaction_data", "item_name")
                    out("  type=%-32s pos=%s hud_desc=%s item_name=%s",
                        tostring(itype), pos_str, tostring(hud_desc), tostring(item_name))
                end
            end
        end
        out("interactable totals = %d", total)
        local sorted = {}
        for k, v in pairs(by_type) do sorted[#sorted + 1] = { k = k, v = v } end
        table.sort(sorted, function(a, b) return a.v > b.v end)
        for _, e in ipairs(sorted) do out("  by_type: %-32s %d", tostring(e.k), e.v) end
    end)

    -- ---------- 6) Breed roster (active conflict settings) ----------
    safe("6 breeds", function()
        section("6) Breed roster (active CurrentConflictSettings)")
        local ccs = rawget(_G, "CurrentConflictSettings")
        if not ccs then out("CurrentConflictSettings: (none — not in a mission)"); return end
        out("CurrentConflictSettings.name = %s", tostring(ccs.name))

        local diff_mgr = Managers and Managers.state and Managers.state.difficulty
        local diff = diff_mgr and diff_mgr.get_difficulty and diff_mgr:get_difficulty() or "?"

        local cb = ccs.contained_breeds and ccs.contained_breeds[diff] or ccs.contained_breeds
        if type(cb) == "table" then
            local names = {}
            for k in pairs(cb) do names[#names + 1] = k end
            table.sort(names)
            out("  contained_breeds[%s] (%d):", tostring(diff), #names)
            for _, n in ipairs(names) do out("    %s", n) end
        else
            out("  contained_breeds: (table missing)")
        end

        -- specials_settings / boss_settings are referenced by name; dump just the names.
        local function ddump(field)
            local v = ccs[field]
            if type(v) == "string" then out("  %s = %s", field, v)
            elseif type(v) == "table" then
                local sub = {}
                for k in pairs(v) do sub[#sub + 1] = tostring(k) end
                out("  %s = { %s }", field, table.concat(sub, ", "))
            end
        end
        ddump("boss")
        ddump("specials")
        ddump("standard_settings")
        ddump("pack_spawning")
        ddump("roaming")
        ddump("intensity")
        ddump("disabled_director_functions")
    end)

    -- ---------- 7) Terror events for this level ----------
    safe("7 terror_events", function()
        section("7) TerrorEventBlueprints[level_key]")
        local lk = Managers and Managers.state and Managers.state.game_mode
            and Managers.state.game_mode.level_key and Managers.state.game_mode:level_key() or nil
        local teb = rawget(_G, "TerrorEventBlueprints")
        if not teb then out("TerrorEventBlueprints: (not loaded)"); return end
        local blueprints = teb[lk]
        if not blueprints then out("TerrorEventBlueprints[%s]: (no entries — many missions only use GenericTerrorEvents)", tostring(lk)); return end
        local names = {}
        for n in pairs(blueprints) do names[#names + 1] = n end
        table.sort(names)
        out("TerrorEventBlueprints[%s] count = %d", tostring(lk), #names)
        for _, name in ipairs(names) do
            local ev = blueprints[name]
            local kinds = {}
            if type(ev) == "table" then
                for i = 1, math.min(#ev, 24) do
                    local step = ev[i]
                    if type(step) == "table" then
                        kinds[#kinds + 1] = tostring(step.kind or step[1] or "?")
                    end
                end
            end
            out("  %s  steps=[%s%s]", name, table.concat(kinds, ","), (#ev > 24 and ",..." or ""))
        end
    end)

    -- ---------- 8) Active UI surfaces ----------
    safe("8 ui_surfaces", function()
        section("8) UI surfaces (Managers.ui._ingame_ui.views, current state)")
        local ui = Managers and Managers.ui
        local ingame_ui = ui and ui._ingame_ui
        if not ingame_ui then out("(no _ingame_ui)"); return end

        local views = ingame_ui.views
        if type(views) == "table" then
            local names = {}
            for k in pairs(views) do names[#names + 1] = tostring(k) end
            table.sort(names)
            out("ingame_ui.views (%d) = { %s }", #names, table.concat(names, ", "))
        else
            out("(no ingame_ui.views table)")
        end

        if ingame_ui.current_state_name then
            local _, csn = pcall(ingame_ui.current_state_name, ingame_ui)
            out("ingame_ui:current_state_name() = %s", tostring(csn))
        end

        -- Mirror cim_dump_active_window: if hero_view is open, peek state name.
        local hero_view = views and views.hero_view
        if hero_view then
            local state = (hero_view._machine and hero_view._machine._state)
                or hero_view._current_state or hero_view._state
            if state then
                out("hero_view active state class = %s", tostring(state.NAME or state.__class_name or "?"))
                local windows = state._active_windows or state.active_windows
                if type(windows) == "table" then
                    for slot_idx, win in pairs(windows) do
                        out("  hero_view window[%s] = %s", tostring(slot_idx), tostring(win and (win.NAME or "?")))
                    end
                end
            else
                out("hero_view present but no active state.")
            end
        end
    end)

    -- ---------- 9) Live HUD elements ----------
    safe("9 hud", function()
        section("9) Live HUD elements (ingame_hud._components / _currently_visible_components)")
        -- ingame_ui.lua:103 assigns `self.ingame_hud = IngameHud:new(...)`. ingame_hud.lua:175 stores
        -- the master table at `self._components`; the keep-vs-mission visibility filter lives in
        -- `self._currently_visible_components`. Walk both so we can report what's on-screen now and
        -- what's defined but currently filtered out.
        local ingame_ui = Managers and Managers.ui and Managers.ui._ingame_ui
        local ingame_hud = ingame_ui and (ingame_ui.ingame_hud or ingame_ui._ingame_hud)
        if not ingame_hud then out("(no ingame_hud found via Managers.ui._ingame_ui)"); return end

        local all_components = ingame_hud._components
        local currently_visible = ingame_hud._currently_visible_components
        if type(all_components) ~= "table" then
            out("(ingame_hud present but no _components table — vt2 build mismatch?)")
            return
        end
        local visible_set = {}
        if type(currently_visible) == "table" then
            for k, v in pairs(currently_visible) do
                -- _currently_visible_components is either { class_name = true } or array-of-instances depending on build; cover both.
                if type(k) == "string" then visible_set[k] = (v and true or false) end
                if type(v) == "table" and v.NAME then visible_set[v.NAME] = true end
            end
        end

        local visible, hidden = {}, {}
        for name in pairs(all_components) do
            if visible_set[name] or next(visible_set) == nil then
                visible[#visible + 1] = tostring(name)
            else
                hidden[#hidden + 1] = tostring(name)
            end
        end
        table.sort(visible); table.sort(hidden)
        out("hud visible (%d) = { %s }", #visible, table.concat(visible, ", "))
        out("hud hidden  (%d) = { %s }", #hidden,  table.concat(hidden,  ", "))
    end)

    -- ---------- 10) Save side-car ----------
    -- VMF mods cannot write arbitrary files; mod:get_temp_data_directory does
    -- not exist in this VMF build, and Application.save_user_settings_to_file
    -- is not callable from sandboxed mod code. Per the doctrine we just emit a
    -- single notice line and rely on the console-*.log capture, which already
    -- holds the full dump as written above.
    safe("10 sidecar", function()
        section("10) Save side-car")
        local intended_filename = string.format("level_dump_%s_%d.txt", level_key_for_filename, ts)
        out("intended filename: %s", intended_filename)
        out("(VMF has no filesystem write API exposed — skipping; full dump is already in console-*.log under the %s prefix)", _LD_PREFIX)
    end)

    out("=== /dump_level end (%d total lines) ===", #out_lines)
    mod:echo(string.format("/dump_level: %d lines written to console log (search '%s')", #out_lines, _LD_PREFIX))
end)

-- ============================================================
-- Shared dump-to-log helper
-- ============================================================
-- VMF mods have no usable filesystem write API; the "filename" arg is a
-- label only — every line lands in console-*.log under a [DUMP:<filename>]
-- prefix. Used by the glossary / cosmetics / items / hero-view commands below.
local function _write_dump(filename, lines)
    for _, line in ipairs(lines) do
        mod:info("[DUMP:%s] %s", tostring(filename), tostring(line))
    end
end

-- ============================================================
-- Game Glossary Dump
-- ============================================================

mod:command("dump_glossary", "Dump localized names for heroes, careers, and weapons to log", function()
    if not SPProfiles then
        mod:echo("SPProfiles not loaded (load a level first).")
        return
    end

    local lines = {}
    local function add(line)
        lines[#lines + 1] = line
    end

    local function safe_localize(key)
        if not key then return "?" end
        local ok, result = pcall(Localize, key)
        return ok and result or key
    end

    add("=== HEROES & CAREERS ===")
    for _, profile in ipairs(SPProfiles) do
        local hero_key = profile.display_name
        if hero_key == "empire_soldier_tutorial" then goto continue_hero end
        local hero_name = safe_localize(profile.ingame_display_name or hero_key)
        add(string.format("HERO  %-25s  %s", hero_key, hero_name))
        if profile.careers then
            for _, career in ipairs(profile.careers) do
                local career_key = career.display_name or career.name
                local career_name = safe_localize(career_key)
                add(string.format("  CAREER  %-23s  %s", career_key, career_name))
            end
        end
        ::continue_hero::
    end

    add("")
    add("=== WEAPONS ===")
    if ItemMasterList then
        local weapons = {}
        for key, item in pairs(ItemMasterList) do
            local st = item.slot_type
            if st == "melee" or st == "ranged" then
                local name = item.display_name and safe_localize(item.display_name) or "?"
                local wield = "none"
                if item.can_wield and #item.can_wield > 0 then
                    wield = table.concat(item.can_wield, ", ")
                end
                weapons[#weapons + 1] = {
                    key = key,
                    slot = st,
                    name = name,
                    careers = wield,
                    template = item.template or "",
                }
            end
        end
        table.sort(weapons, function(a, b)
            if a.slot ~= b.slot then return a.slot < b.slot end
            return a.key < b.key
        end)

        local cur_slot = nil
        for _, w in ipairs(weapons) do
            if w.slot ~= cur_slot then
                cur_slot = w.slot
                add(string.format("--- %s ---", cur_slot:upper()))
            end
            add(string.format("  %-45s  %-30s  can_wield=[%s]", w.key, w.name, w.careers))
        end

        add("")
        add(string.format("Total: %d weapons", #weapons))
    else
        add("ItemMasterList not loaded.")
    end

    _write_dump("glossary.txt", lines)
    mod:echo(string.format("dump_glossary: %d lines written to log", #lines))
end)

-- ============================================================
-- Cosmetic / Item Dump Commands
-- ============================================================

mod:command("dump_cosmetics", "Dump all hats, skins, and frames from ItemMasterList to log", function(filter)
    if not ItemMasterList then
        mod:echo("ItemMasterList not loaded (load a level first).")
        return
    end

    local slot_types = { hat = {}, skin = {}, frame = {} }
    for key, item in pairs(ItemMasterList) do
        local st = item.slot_type
        if slot_types[st] then
            local wield = item.can_wield
            local careers = "none"
            if wield and #wield > 0 then
                careers = table.concat(wield, ", ")
            end
            if not filter or key:find(filter, 1, true) or careers:find(filter, 1, true) then
                -- REVIEW: `icon` is captured but never written to output (the
                -- inner formatter below only uses key + careers). Remove this
                -- field or include it in the dump line.
                slot_types[st][#slot_types[st] + 1] = {
                    key = key,
                    careers = careers,
                    icon = item.inventory_icon or "?",
                }
            end
        end
    end

    local total = 0
    local lines = {}
    for slot_type, items in pairs(slot_types) do
        table.sort(items, function(a, b) return a.key < b.key end)
        local header = string.format("=== %s (%d items) ===", slot_type:upper(), #items)
        mod:echo(header)
        lines[#lines + 1] = header
        for _, item in ipairs(items) do
            local line = string.format("  %-50s  can_wield=[%s]", item.key, item.careers)
            mod:echo(line)
            lines[#lines + 1] = line
            total = total + 1
        end
    end

    local summary = string.format("dump_cosmetics: %d total (%d hats, %d skins, %d frames)",
        total, #slot_types.hat, #slot_types.skin, #slot_types.frame)
    mod:echo(summary)
    lines[#lines + 1] = summary
    _write_dump("cosmetics.txt", lines)
end)

-- ============================================================
-- Item Dump Commands
-- ============================================================

mod:command("dump_items_by_slot", "Dump all ItemMasterList slot_type values and counts", function()
    if not ItemMasterList then
        mod:echo("ItemMasterList not loaded (load a level first).")
        return
    end

    local counts = {}
    for key, item in pairs(ItemMasterList) do
        local st = item.slot_type or "nil"
        counts[st] = (counts[st] or 0) + 1
    end

    local sorted = {}
    for st, count in pairs(counts) do
        sorted[#sorted + 1] = { slot_type = st, count = count }
    end
    table.sort(sorted, function(a, b) return a.count > b.count end)

    local lines = { "=== ItemMasterList slot_type counts ===" }
    mod:echo(lines[1])
    for _, entry in ipairs(sorted) do
        local line = string.format("  %-30s %d items", entry.slot_type, entry.count)
        mod:echo(line)
        lines[#lines + 1] = line
    end
    _write_dump("items_by_slot.txt", lines)
end)

-- gt_dump_hero_view: capture live hero view widget tree for porting analysis
mod:command("dump_hero_view", "Dump the active HeroView state, menu layout, and widget tree to log", function()
    local lines = {}
    local function add(line)
        lines[#lines + 1] = line
    end

    local function safe_localize(key)
        if not key then return "?" end
        local ok, result = pcall(Localize, key)
        return ok and result or key
    end

    local function safe(fn)
        local ok, result = pcall(fn)
        if ok then return result end
        return nil
    end

    add(string.format("=== gt_dump_hero_view @ %s ===", os.date("%Y-%m-%d %H:%M:%S")))
    local build_id = rawget(_G, "BUILD") or safe(function() return Application.build_identifier() end)
    add(string.format("BUILD=%s", tostring(build_id or "?")))

    local ingame_ui = safe(function() return Managers.ui:ingame_ui() end)
    if not ingame_ui then
        mod:echo("Hero view not active - open the character menu first, then run /dump_hero_view.")
        return
    end

    local views = ingame_ui.views
    local hero_view = views and views.hero_view
    if not hero_view then
        mod:echo("Hero view not active - open the character menu first, then run /dump_hero_view.")
        return
    end

    local current_view = ingame_ui.current_view
    local is_active = (current_view == "hero_view")
    add(string.format("ACTIVE_VIEW class=HeroView current_view=%s visible=%s",
        tostring(current_view), tostring(is_active)))

    if not is_active then
        add("Hero view exists but is not the current_view; dumping last-known state anyway.")
    end

    local machine = hero_view._machine
    local state = safe(function() return hero_view:current_state() end) or (machine and safe(function() return machine:state() end))
    if not state then
        add("STATE machine_or_state_unavailable")
        _write_dump("hero_view_dump.txt", lines)
        mod:echo(string.format("gt_dump_hero_view: %d lines written to log", #lines))
        return
    end

    local state_class_name = "?"
    local mt = getmetatable(state)
    if mt and mt.__index then
        for name, ref in pairs(_G) do
            if ref == mt.__index then state_class_name = name; break end
        end
    end
    add(string.format("STATE class=%s", state_class_name))

    local profile_index = state.profile_index or hero_view.initial_profile_index
    local career_index = state.career_index
    local hero_name = state.hero_name
    add(string.format("CAREER hero=%s profile_index=%s career_index=%s",
        tostring(hero_name), tostring(profile_index), tostring(career_index)))
    if SPProfiles and profile_index and SPProfiles[profile_index] then
        local prof = SPProfiles[profile_index]
        local career = prof.careers and prof.careers[career_index]
        if career then
            add(string.format("  career_name=%s display=%s",
                tostring(career.name), safe_localize(career.display_name or career.name)))
        end
    end

    add("")
    add("=== MENU LAYOUT ===")
    local layout_settings = state._layout_settings
    if layout_settings then
        add(string.format("max_active_windows=%s", tostring(layout_settings.max_active_windows)))
        local window_layouts = layout_settings.window_layouts or state._window_layouts
        if window_layouts then
            for i, entry in ipairs(window_layouts) do
                local display = entry.display_name and safe_localize(entry.display_name) or ""
                add(string.format("  layout[%d] name=%s close_on_exit=%s display=%s",
                    i, tostring(entry.name), tostring(entry.close_on_exit), display))
            end
        end
        local windows = layout_settings.windows or state._windows_settings
        if windows then
            add("  --- windows ---")
            for key, w in pairs(windows) do
                add(string.format("    window[%s] class=%s", tostring(key), tostring(w.class_name)))
            end
        end
    else
        add("(_layout_settings not present on state)")
    end

    add(string.format("selected_layout_index=%s", tostring(state._selected_game_mode_index)))

    add("")
    add("=== ACTIVE WINDOWS ===")
    local active_windows = state._active_windows
    if active_windows then
        for idx, window in pairs(active_windows) do
            local cls = "?"
            local wmt = getmetatable(window)
            if wmt and wmt.__index then
                for name, ref in pairs(_G) do
                    if ref == wmt.__index then cls = name; break end
                end
            end
            add(string.format("  active_window[%s] class=%s", tostring(idx), cls))
        end
    else
        add("(no _active_windows)")
    end

    local function dump_widgets(owner_label, widgets_by_name)
        if not widgets_by_name then return end
        add(string.format("--- widgets_by_name (%s) ---", owner_label))
        local keys = {}
        for k in pairs(widgets_by_name) do keys[#keys+1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local w = widgets_by_name[k]
            local wtype = w and (w.element and w.element.name) or (w and w.widget_type) or "?"
            local label = ""
            if w and w.content then
                local txt = w.content.text or w.content.title_text or w.content.display_name
                if type(txt) == "string" then
                    if #txt > 60 then txt = txt:sub(1, 60) .. "..." end
                    label = " text=\"" .. txt .. "\""
                end
                if w.content.visible ~= nil then
                    label = label .. " visible=" .. tostring(w.content.visible)
                end
            end
            add(string.format("  [%s] type=%s%s", k, tostring(wtype), label))
        end
    end

    add("")
    add("=== STATE WIDGETS ===")
    dump_widgets("state", state._widgets_by_name)

    if active_windows then
        for idx, window in pairs(active_windows) do
            add("")
            add(string.format("=== WINDOW[%s] WIDGETS ===", tostring(idx)))
            dump_widgets("window_" .. tostring(idx), window._widgets_by_name)
        end
    end

    _write_dump("hero_view_dump.txt", lines)
    mod:echo(string.format("gt_dump_hero_view: %d lines written to log", #lines))
end)
