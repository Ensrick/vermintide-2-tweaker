-- Offline proof for #1670: the /mod_tweaker command route lost the Mod Tweaker's
-- click and hover sounds that the Esc route plays.
--
-- The Esc route opens the standalone ModTweakerView (_mod_tweaker_view.lua); the
-- command opens the keep HeroView sub-state (_mod_tweaker_state.lua), because
-- _ba_heroview_inject.lua registers `mod_tweaker` after the entry file and VMF
-- lets a mod overwrite its own command. Through 0.2.358-dev the sub-state resolved
-- its wwise world with Managers.world:world("music_world"). On PC the music world
-- is the boot global MUSIC_WORLD (vanilla boot_init.lua:23,31-33) and is never
-- registered with WorldManager, so WorldManager.world asserts
-- (world_manager.lua:111-113) and the pcall dropped every sound.
--
-- These cases load BOTH shipped twins whole, capture the click and hover
-- functions each one hands its interaction layer (what tab swaps and group
-- expands call), and fire them against a PC-shaped world manager. printf,
-- WwiseWorld and the worlds resolve through a test-local environment; no
-- global is swapped.
return function(H, repo_root)
    local base = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"

    local function read(name)
        local file = assert(io.open(base .. name, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    -- Self-returning stand-in for the twins' unrelated install-time dofiles.
    local Stub
    Stub = setmetatable({}, {
        __index = function() return Stub end,
        __call = function() return Stub end,
    })

    -- WorldManager as vanilla builds it (foundation/scripts/managers/world/
    -- world_manager.lua): create_world is the only registration (:18-56),
    -- has_world is a table read (:107-109), world() fasserts (:111-113),
    -- wwise_world() is a bare lookup (:60-62).
    local function world_manager(registered)
        local wm = { _worlds = {}, _wwise_worlds = {} }
        for name, wwise in pairs(registered or {}) do
            local world = { name = name }
            wm._worlds[name] = world
            wm._wwise_worlds[world] = wwise
        end
        function wm:has_world(name) return self._worlds[name] ~= nil end
        function wm:world(name)
            assert(self._worlds[name], string.format("World %q doesn't exist", name))
            return self._worlds[name]
        end
        function wm:wwise_world(world) return self._wwise_worlds[world] end
        return wm
    end

    local MUSIC = { tag = "MUSIC_WWISE_WORLD" }
    local LEVEL = { tag = "level_world wwise" }

    -- opts.global_music: set GLOBAL_MUSIC_WORLD/MUSIC_WWISE_WORLD (PC, boot_init.lua:23,33)
    -- opts.registered: worlds registered with the manager, name -> wwise handle
    local function make_env(opts)
        local triggers, deps = {}, {}
        local env = setmetatable({}, { __index = _G })
        env._G = env
        local mod = {}
        for _, name in ipairs({ "debug", "info", "echo", "warning", "error" }) do
            mod[name] = function() end
        end
        local function load_into_env(name)
            local chunk = assert(loadfile(base .. name .. ".lua"))
            setfenv(chunk, env)
            return chunk()
        end
        function mod:dofile(path)
            local name = path:match("([^/]+)$")
            if name == "_mod_tweaker_sound" then return load_into_env(name) end
            if name == "_mod_tweaker_state_interaction" or name == "_mod_tweaker_view_interaction" then
                return { install = function(_, d) deps[name] = d end }
            end
            if name == "_mod_tweaker_view_diagnostics" then return { install = function() end } end
            return Stub
        end
        env.get_mod = function() return mod end
        env.class = function(c)
            c = c or {}
            c.__index = c
            return c
        end
        env.World = {}   -- vanilla never calls a World.wwise_world (no caller in the decompiled source)
        env.WwiseWorld = {
            trigger_event = function(ww, event) triggers[#triggers + 1] = { ww = ww, event = event } end,
        }
        env.Managers = { world = world_manager(opts.registered) }
        if opts.global_music then
            env.GLOBAL_MUSIC_WORLD = true
            env.MUSIC_WWISE_WORLD = MUSIC
        end
        local view = load_into_env("_mod_tweaker_view")
        load_into_env("_mod_tweaker_state")
        return {
            env = env, mod = mod, triggers = triggers, view_class = view,
            state_class = rawget(env, "HeroViewStateModTweaker"),
            esc = deps._mod_tweaker_view_interaction,
            command = deps._mod_tweaker_state_interaction,
        }
    end

    local function fire(route)
        route.play_click()
        route.play_hover()
    end

    local function events_on(triggers, ww)
        local out = {}
        for _, t in ipairs(triggers) do
            if t.ww == ww then out[#out + 1] = t.event end
        end
        return out
    end

    H.test("GUT #1670 both twins load whole and hand their interaction layers a click and a hover", function()
        local s = make_env({ global_music = true, registered = { level_world = LEVEL } })
        for _, route in ipairs({ s.esc, s.command }) do
            H.truthy(route, "interaction deps were not captured")
            H.equal(type(route.play_click), "function")
            H.equal(type(route.play_hover), "function")
        end
        H.equal(type(s.state_class), "table", "HeroViewStateModTweaker class global")
    end)

    H.test("GUT #1670 Esc route (standalone view) fires on MUSIC_WWISE_WORLD like OptionsView", function()
        local s = make_env({ global_music = true, registered = { level_world = LEVEL } })
        fire(s.esc)
        H.deep_equal(events_on(s.triggers, MUSIC), { "Play_hud_select", "Play_hud_hover" })
        H.equal(#s.triggers, 2, "nothing fires on any other world")
    end)

    H.test("GUT #1670 command route (keep sub-state) fires the same events on the same world", function()
        local s = make_env({ global_music = true, registered = { level_world = LEVEL } })
        fire(s.command)
        H.deep_equal(events_on(s.triggers, MUSIC), { "Play_hud_select", "Play_hud_hover" },
            "the 0.2.358-dev sub-state asked Managers.world for an unregistered music_world and dropped both")
        H.equal(#s.triggers, 2)
    end)

    H.test("GUT #1670 without the boot global both twins use the registered music_world", function()
        -- options_view.lua:285-287: the non-global branch reads the manager's handle.
        local MANAGED = { tag = "managed music wwise" }
        local s = make_env({ global_music = false, registered = { music_world = MANAGED } })
        fire(s.esc)
        fire(s.command)
        H.deep_equal(events_on(s.triggers, MANAGED),
            { "Play_hud_select", "Play_hud_hover", "Play_hud_select", "Play_hud_hover" })
    end)

    H.test("GUT #1670 no music world at all is silent on both twins, never a raise", function()
        local s = make_env({ global_music = false, registered = { level_world = LEVEL } })
        fire(s.esc)
        fire(s.command)
        H.equal(#s.triggers, 0, "a Wwise call on an unproven world is the BUG_CLASSES AV")
    end)

    H.test("GUT #1670 both twins publish the resolver their sounds fire on", function()
        local s = make_env({ global_music = true, registered = { level_world = LEVEL } })
        H.equal(type(s.state_class.gut_sound_resolve), "function", "command route resolver")
        H.equal(type(s.view_class.gut_sound_resolve), "function", "Esc route resolver")
        local ww_a, path_a = s.state_class.gut_sound_resolve()
        local ww_b, path_b = s.view_class.gut_sound_resolve()
        H.equal(ww_a, MUSIC)
        H.equal(ww_b, MUSIC)
        H.equal(path_a, "MUSIC_WWISE_WORLD")
        H.equal(path_b, path_a)
    end)

    -- Loads the real contracts module against the scenario's environment and
    -- returns the registered checks.
    local function load_contracts(s)
        local registered = {}
        local dofile = s.mod.dofile
        s.mod.dofile = function(self, path)
            if path:find("_gut_dialogue_contract", 1, true) then return { install = function() end } end
            if path:find("_mod_tweaker_tab_labels", 1, true) then return { rt_checks = {} } end
            return dofile(self, path)
        end
        local chunk = assert(loadfile(base .. "_gut_mod_tweaker_contracts.lua"))
        setfenv(chunk, s.env)
        chunk().install({
            register = function(name, fn) registered[name] = fn end,
            src_read = function() return nil end,
        })
        return registered
    end

    -- Live keep flag as vanilla sets it (state_ingame.lua:137) plus a captured context.
    local function keep_ctx(s, with_view)
        s.env.DamageUtils = { is_in_inn = true }
        local views = {}
        if with_view then views.mod_tweaker_view = setmetatable({}, s.view_class) end
        return { is_in_inn = true, ingame_ui = { views = views } }
    end

    H.test("GUT #1670 live check: PASS in the keep when the routes share the path, verdict only", function()
        local s = make_env({ global_music = true, registered = { level_world = LEVEL } })
        local lines = {}
        s.env.printf = function(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end
        local checks = load_contracts(s)
        local check = checks.issue1670_command_route_sound_path
        H.equal(type(check), "function", "contracts must register issue1670_command_route_sound_path")
        s.mod._gut_ingame_ui_context = keep_ctx(s, true)
        H.equal(check(), nil)
        -- The /gut_regression_test PASS line is the evidence; the check logs nothing itself.
        H.deep_equal(lines, {})
    end)

    H.test("GUT #1670 live check: SKIP with a reason outside the keep or before the view attaches", function()
        local s = make_env({ global_music = true, registered = { level_world = LEVEL } })
        local check = load_contracts(s).issue1670_command_route_sound_path
        -- Main menu: no DamageUtils flag yet.
        local verdict = check()
        H.truthy(verdict and verdict:find("^skip: not in the keep"), tostring(verdict))
        -- Mission after a keep visit: the captured keep context is stale, the live flag is false.
        s.mod._gut_ingame_ui_context = keep_ctx(s, true)
        s.env.DamageUtils.is_in_inn = false
        verdict = check()
        H.truthy(verdict and verdict:find("^skip: not in the keep"), tostring(verdict))
        s.env.DamageUtils.is_in_inn = true
        s.mod._gut_ingame_ui_context = nil
        verdict = check()
        H.truthy(verdict and verdict:find("^skip: no ingame UI context"), tostring(verdict))
        s.mod._gut_ingame_ui_context = keep_ctx(s, false)
        verdict = check()
        H.truthy(verdict and verdict:find("^skip: standalone ModTweakerView"), tostring(verdict))
    end)

    H.test("GUT #1670 live check: FAILs when the command route drifts back to its own lookup", function()
        local s = make_env({ global_music = true, registered = { level_world = LEVEL } })
        local check = load_contracts(s).issue1670_command_route_sound_path
        s.mod._gut_ingame_ui_context = keep_ctx(s, true)
        -- The 0.2.358-dev sub-state lookup, published as its resolver.
        s.state_class.gut_sound_resolve = function()
            local ok, world = pcall(s.env.Managers.world.world, s.env.Managers.world, "music_world")
            return ok and world or nil, "Managers.world:world(music_world)"
        end
        local verdict = check()
        H.truthy(verdict and verdict:find("^command route resolved"), tostring(verdict))
        s.state_class.gut_sound_resolve = nil
        verdict = check()
        H.equal(verdict, "keep sub-state (command route) does not publish gut_sound_resolve")
    end)

    H.test("GUT #1670 the command really is the sub-state route: the inject module re-registers it later", function()
        local main = read("gui_tweaker_dev.lua")
        local inject = read("_ba_heroview_inject.lua")
        H.truthy(inject:find('mod:command("mod_tweaker"', 1, true), "inject module registers /mod_tweaker")
        H.truthy(inject:find('menu_state_name = "gut_mod_tweaker"', 1, true), "and it opens the sub-state")
        local entry_cmd = main:find('mod:command("mod_tweaker"', 1, true)
        local inject_load = main:find('"scripts/mods/gui_tweaker_dev/_ba_heroview_inject"', 1, true)
        H.truthy(entry_cmd and inject_load and inject_load > entry_cmd,
            "the inject module loads after the entry registration, so its handler wins (VMF commands.lua:15-28)")
    end)
end
