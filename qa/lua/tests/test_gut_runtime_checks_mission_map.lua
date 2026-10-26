-- #2: execute the installed registration child and actual entry invocation.
-- Expected verdicts below are authored contracts, not the retired inline body.
return function(H, repo_root, source_override)
    local root = "gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"
    local child_path = root .. "_gut_runtime_checks_mission_map.lua"
    local entry_path = root .. "gui_tweaker_dev.lua"
    local function read(path)
        if source_override and source_override[path] then return source_override[path] end
        local file = assert(io.open(repo_root .. "/" .. path, "rb"))
        local value = file:read("*a"); file:close(); return value
    end
    local child, entry = read(child_path), read(entry_path)
    local names = { "mission_map_backdrop_swap", "area_video_guard_two_layers", "mission_map_preview_backdrop" }
    local manifest_path = "scripts/mods/gui_tweaker_dev/_gut_runtime_checks_mission_map"
    local map_markers = {
        "_gut_mm_none_backdrop", "_area_video_drawable", '"_assign_video_player"',
        '"_setup_video_player"', "resource_packages/levels/ui_inventory_preview",
        "_kick_preview_pkg_load", "has_loaded(PREVIEW_PKG, MM_PKG_REF)",
        "level_name = PREVIEW_LEVEL",
    }
    local guard_markers = { "_area_video_entries", "if append_areas then", "mod._gut_area_videos_ingame" }
    local errors = {
        none = "#336 regression: the none-tier marker _gut_mm_none_backdrop is gone (map fail-closes again when no backdrop level is resident)",
        drawable = "#336 regression: _area_video_drawable is gone from the map module (area videos draw unguarded -> mid-mission draw fatal)",
        assign = "#336 regression: the StartGameWindowAreaSelectionConsoleV2._assign_video_player skip guard is gone (console-layout area hover crashes mid-mission again)",
        setup = "#336 regression: the StartGameWindowAreaSelection._setup_video_player skip guard is gone (PC-layout area hover crashes mid-mission again)",
        entries = "#336 regression: the AreaSettings video-material enumeration is gone from the GUI guard (no injection -> keep-only materials mid-mission)",
        append = "#336 regression: the append_areas residency gate is gone -- area videos no longer injected into ingame renderers",
        publish = "#336 regression: the per-material publish (mod._gut_area_videos_ingame) is gone -- the map module's skip guard falls back to keep-only heuristics",
        console = "vanilla drift: StartGameWindowAreaSelectionConsoleV2._assign_video_player missing (skip guard orphaned)",
        desktop = "vanilla drift: StartGameWindowAreaSelection._setup_video_player missing (skip guard orphaned)",
        public = "#336 regression: gut_open_mission_map not wired (mission map module failed to load -- preview backdrop gone)",
        package = "#336 regression: the preview-stage package path is gone from the map module (no backdrop package load)",
        kick = "#336 regression: the preview-package async load kick is gone (map never gets the preview backdrop)",
        loaded = "#336 regression: the has_loaded package gate is gone from the def-swap (v0.2.190 lesson: can_get('level') is false until the PACKAGE loads; ungated mount = C-fatal, gated absence = black plate)",
        level = "#336 regression: the tier-2 def no longer mounts the preview level (black backdrop + glow bleeding return)",
    }
    local function count(source, needle)
        local n, at = 0, 1
        while true do
            at = source:find(needle, at, true)
            if not at then return n end
            n, at = n + 1, at + #needle
        end
    end
    local function invocation()
        local start = assert(entry:find('mod:dofile("' .. manifest_path .. '")', 1, true), "map-check manifest disconnected")
        local finish = assert(entry:find("\n})", start, true), "map-check context unterminated")
        local before = assert(entry:find('_rt_register("lifecycle_chain_integrity"', 1, true))
        local after = assert(entry:find('_rt_register("arrow_hover_native_size"', 1, true))
        H.truthy(before < start and finish < after, "map-check registration order moved")
        return entry:sub(start, finish + 2)
    end
    local function fixture(options)
        options = options or {}
        local rows, reads, loads, calls, debug_calls = {}, {}, 0, 0, 0
        local token = options.token or {}
        local mod = {
            _gut_mm_can_get_level = function() calls = calls + 1; error("map action called") end,
            gut_open_mission_map = function() calls = calls + 1; error("map action called") end,
        }
        local noop = function() end
        local env = {
            StartGameWindowBackgroundConsole = {
                _create_viewport_definition = noop, _update_object_sets = noop, _setup_object_sets = noop,
            },
            StartGameWindowAreaSelectionConsoleV2 = { _assign_video_player = noop },
            StartGameWindowAreaSelection = { _setup_video_player = noop },
        }
        rawset(env, "_G", env)
        rawset(env, "debug", { getinfo = function(_, kind)
            H.equal(kind, "S"); debug_calls = debug_calls + 1
            if options.debug_error then error(token, 0) end
            if options.debug_info ~= nil then return options.debug_info end
            return { source = options.path or "@C:/fixture/_gut_mission_map.lua" }
        end })
        setmetatable(env, { __index = _G, __newindex = function(_, key) error("unexpected global write: " .. key) end })
        if options.missing_mod then mod[options.missing_mod] = nil end
        if options.missing_class then rawset(env, options.missing_class, nil) end
        if options.missing_method then env[options.missing_method[1]][options.missing_method[2]] = nil end
        local function source(markers)
            local out = {}
            for _, marker in ipairs(markers) do
                if marker ~= options.omit then out[#out + 1] = marker end
            end
            return table.concat(out, "\n")
        end
        local function reader(path)
            reads[#reads + 1] = path
            if options.reader_error then error(token, 0) end
            if options.unreadable then return nil end
            if path:find("_gut_gui_material_guard.lua", 1, true) then
                if options.unreadable_guard then return nil end
                return source(guard_markers)
            end
            if options.unreadable_map then return nil end
            return source(map_markers)
        end
        local function register(name, callback)
            if options.registrar_error then error(token, 0) end
            H.equal(type(callback), "function")
            rows[#rows + 1] = { name = name, run = callback }
        end
        function mod:dofile(path)
            loads = loads + 1; H.equal(path, manifest_path)
            local chunk = assert(loadstring(child, "@installed-map-check-child")); setfenv(chunk, env)
            local owner = chunk()
            local original = owner.register
            owner.register = function(context)
                H.equal(context.mod, mod); H.equal(context.register, register)
                H.equal(context.read_source, reader, "entry did not forward the IO-safe reader")
                return original(context)
            end
            return owner
        end
        rawset(env, "mod", mod); rawset(env, "_rt_register", register); rawset(env, "_rt_src_read", reader)
        local chunk = assert(loadstring(invocation(), "@installed-map-check-manifest")); setfenv(chunk, env)
        local ok, err = pcall(chunk)
        if options.registrar_error then
            H.equal(ok, false); H.equal(err, token); return
        end
        H.equal(ok, true, tostring(err)); H.equal(loads, 1); H.equal(#rows, 3)
        H.equal(#reads, 0, "registration read source eagerly"); H.equal(debug_calls, 0)
        H.equal(calls, 0, "registration called the map action")
        for i, name in ipairs(names) do H.equal(rows[i].name, name) end
        return rows, reads, function() return calls end, token
    end
    H.test("GUT map-check owner has one ordered manifest and no inline duplicate", function()
        H.equal(count(entry, manifest_path), 1)
        for _, name in ipairs(names) do H.equal(count(entry, '_rt_register("' .. name .. '"'), 0) end
        H.equal(count(child, "mod:dofile("), 0)
        H.equal(count(child, "mod:hook"), 0); H.equal(count(child, "mod:command"), 0)
        local package = read("gui_tweaker_dev/resource_packages/gui_tweaker_dev/gui_tweaker_dev.package")
        H.truthy(package:find('"scripts/mods/gui_tweaker_dev/*"', 1, true))
        fixture()
    end)
    H.test("GUT map-check registration propagates the exact registrar error", function()
        fixture({ registrar_error = true })
    end)
    local cases = {
        { "healthy", {} },
        { "IO sandbox", { unreadable = true } },
        { "map unreadable", { unreadable_map = true } },
        { "guard unreadable", { unreadable_guard = true } },
        { "debug throws", { debug_error = true } },
        { "debug info false", { debug_info = false } },
        { "debug info string", { debug_info = "not metadata" } },
        { "debug source absent", { debug_info = {} } },
        { "can-get missing", { missing_mod = "_gut_mm_can_get_level" }, { [1] = "_gut_mm_can_get_level missing" } },
        { "map public missing", { missing_mod = "gut_open_mission_map" }, { [1] = "gut_open_mission_map missing", [3] = errors.public } },
        { "background class absent", { missing_class = "StartGameWindowBackgroundConsole" }, { [1] = "StartGameWindowBackgroundConsole class missing" } },
        { "create viewport absent", { missing_method = { "StartGameWindowBackgroundConsole", "_create_viewport_definition" } }, { [1] = "_create_viewport_definition missing" } },
        { "update object sets absent", { missing_method = { "StartGameWindowBackgroundConsole", "_update_object_sets" } }, { [1] = "_update_object_sets missing" } },
        { "setup object sets absent", { missing_method = { "StartGameWindowBackgroundConsole", "_setup_object_sets" } }, { [1] = "_setup_object_sets missing" } },
        { "none marker absent", { omit = map_markers[1] }, { [1] = errors.none } },
        { "drawable marker absent", { omit = map_markers[2] }, { [2] = errors.drawable } },
        { "console skip absent", { omit = map_markers[3] }, { [2] = errors.assign } },
        { "desktop skip absent", { omit = map_markers[4] }, { [2] = errors.setup } },
        { "video entries absent", { omit = guard_markers[1] }, { [2] = errors.entries } },
        { "video append absent", { omit = guard_markers[2] }, { [2] = errors.append } },
        { "video publish absent", { omit = guard_markers[3] }, { [2] = errors.publish } },
        { "console native drift", { missing_method = { "StartGameWindowAreaSelectionConsoleV2", "_assign_video_player" } }, { [2] = errors.console } },
        { "desktop native drift", { missing_method = { "StartGameWindowAreaSelection", "_setup_video_player" } }, { [2] = errors.desktop } },
        { "console class not loaded", { missing_class = "StartGameWindowAreaSelectionConsoleV2" } },
        { "desktop class not loaded", { missing_class = "StartGameWindowAreaSelection" } },
        { "preview package absent", { omit = map_markers[5] }, { [3] = errors.package } },
        { "preview async kick absent", { omit = map_markers[6] }, { [3] = errors.kick } },
        { "preview residency gate absent", { omit = map_markers[7] }, { [3] = errors.loaded } },
        { "preview level absent", { omit = map_markers[8] }, { [3] = errors.level } },
    }
    for _, case in ipairs(cases) do
        H.test("GUT installed map checks: " .. case[1], function()
            local rows, _, calls = fixture(case[2])
            for i, row in ipairs(rows) do
                local ok, result = pcall(row.run)
                H.equal(ok, true, case[1] .. ": " .. tostring(result))
                H.equal(result, (case[3] or {})[i], row.name .. " verdict changed")
            end
            H.equal(calls(), 0, "check executed gameplay map action")
        end)
    end
    H.test("GUT map checks preserve exact injected reader exceptions", function()
        local rows, _, calls, token = fixture({ reader_error = true })
        for _, row in ipairs(rows) do
            local ok, err = pcall(row.run)
            H.equal(ok, false); H.equal(err, token)
        end
        H.equal(calls(), 0)
    end)
    for _, source in ipairs({ "@C:/fixture/map.lua", "C:/fixture/map.lua", "@C:\\fixture\\map.lua", "map.lua" }) do
        H.test("GUT map source paths preserve sibling lookup: " .. source, function()
            local rows, reads = fixture({ path = source })
            for _, row in ipairs(rows) do H.equal(row.run(), nil) end
            local path = source:sub(1, 1) == "@" and source:sub(2) or source
            local dir = path:match("^(.*[/\\])[^/\\]*$")
            local expected = { path, path }
            if dir then expected[#expected + 1] = dir .. "_gut_gui_material_guard.lua" end
            expected[#expected + 1] = path
            H.deep_equal(reads, expected)
        end)
    end
end
