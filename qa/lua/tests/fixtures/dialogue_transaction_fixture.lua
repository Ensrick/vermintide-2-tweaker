-- Narrow UI boundary fixture: execute the installed view/interaction methods,
-- renderer adapter and CD's real setting callbacks, without constructing a game UI.
return function(root, persisted)
    local f = { stored = persisted or {}, writes = 0, reconciles = 0, gut_writes = 0 }
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.math = setmetatable({ clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end }, { __index = math })
    env.printf = function() end
    env.class = function() return {} end
    env.UIRenderer, env.UISceneGraph = {}, {}
    env.UIInverseScaleVectorToResolution = function(v) return v end
    local function row(label)
        return { content = { label = label, hotspot = {}, dec = {}, inc = {} },
            style = { label = { text_color = { 255, 255, 255, 255 } } } }
    end
    local defs = { create_checkbox = row, create_section_title = row,
        create_group_header = row, create_dialogue_row = row }
    local cache = {}
    local function load(path)
        if not cache[path] then
            local chunk = assert(loadfile(root .. "/" .. path .. ".lua"))
            setfenv(chunk, env)
            cache[path] = chunk()
        end
        return cache[path]
    end
    local cd = {}
    function cd:get(id) return f.stored[id] end
    function cd:set(id, value, notify)
        if f.fail_write then error("planted write failure") end
        f.writes = f.writes + 1
        f.stored[id] = value
        if notify then self.on_setting_changed(id) end
    end
    local setting = load("character_dialogue/scripts/mods/character_dialogue/_cd_isolation_setting")
    f.setting = setting.install(cd, function(value)
        if f.fail_callback then error("planted completion failure") end
        f.reconciles = f.reconciles + 1
        f.enabled = value
    end)
    local browser = load("character_dialogue/scripts/mods/character_dialogue/_cd_browser")
    cd.character_dialogue_api = {
        version = 6, isolation_setting = { version = setting.VERSION, setting_id = setting.ID },
        get_auto_isolation = f.setting.get, set_auto_isolation = f.setting.set,
        browser_groups = function() return {} end,
        browser_window = browser.window, browser_row_height = browser.ROW_HEIGHT,
        browser_reconcile_focus = browser.reconcile_focus,
        stop = function() f.stops = (f.stops or 0) + 1 end,
    }
    local gut = { debug = function() end, get = function() return nil end,
        set = function() f.gut_writes = f.gut_writes + 1 end }
    function gut:dofile(path)
        if path:match("_mod_tweaker_definitions$") then return defs end
        return load("gui_tweaker_dev/" .. path)
    end
    env.get_mod = function(id)
        if id == "gut_dev" then return gut end
        if id == "character_dialogue" and not f.absent then return cd end
    end
    f.cd, f.env, f.defs = cd, env, defs
    f.View = gut:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_view")
    f.UI = gut:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_dialogue")
    f.category = { mod_id = "character_dialogue", widgets = { { type = "dialogue_browser" } } }
    function f:new_view()
        local view = setmetatable({ _pending = {}, _rows = {}, _search_str = "", _scroll_y = 0,
            _visible_h = 640, _max_scroll = 0, _categories = { f.category }, _selected = 1,
            _apply = { content = {} }, _profile_ready = {}, _profile_slot = 8,
            _recompute_scroll_bounds = function() end, _search_note_setting = function() end,
            _search_finish = function() end }, { __index = f.View })
        view:_build_rows(f.category)
        return view
    end
    f.view = f:new_view()
    function f:click()
        local control = self.view._rows[1]
        control.content.hotspot.on_release = false
        self.UI.handle_row(self.view, control)
        control.content.hotspot.on_release = true
        return self.UI.handle_row(self.view, control)
    end
    function f:load_live_cd()
        -- Execute the real entry's setter, VMF lifecycle and Wwise-owner code.
        -- Only external audio/package/registration boundaries are supplied.
        cd.info, cd.echo, cd.debug, cd.warning = function() end, function() end, function() end, function() end
        cd.localize = function(_, key) return key end
        cd.hook = function() end
        cd.command = function() end
        function cd:dofile(path)
            if path:match("character_dialogue_catalogue$") then
                return { { "pes_fixture_01", "", "", "empire_soldier", 2 } }
            end
            return load("character_dialogue/" .. path)
        end
        env.require = function(name)
            assert(name == "scripts/entity_system/systems/dialogues/dialogue_queries")
            return {}
        end
        f.buses = { music_bus_volume = 0.37, sfx_bus_volume = 0.81 }
        env.Application = { user_setting = function(name)
            return ({ music_bus_volume = 0.37, sfx_bus_volume = 0.81 })[name]
        end }
        env.Managers = { world = { world = function() return {} end,
            wwise_world = function() return {} end } }
        env.WwiseWorld = {
            trigger_event = function() f.playing = true; return 7 end,
            stop_event = function() f.playing = false end,
            pause_event = function() end, resume_event = function() end,
            is_playing = function() return f.playing end,
            get_playing_elapsed = function() return 100 end,
            set_global_parameter = function(_, name, value) f.buses[name] = value end,
        }
        load("character_dialogue/scripts/mods/character_dialogue/character_dialogue")
        f.api = cd.character_dialogue_api
        f.view = f:new_view()
    end
    return f
end
