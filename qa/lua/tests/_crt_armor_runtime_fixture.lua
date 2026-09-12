-- Exact installed CRT callback/writer and GUT staging/Apply/profile slices.
-- VMF persistence/events may use the explicitly supplied external VMF source;
-- otherwise that boundary and unrelated engine/UI observers are doubles.
-- No planner or callback is reimplemented here.
return function(root, initial, vmf_settings_path, options)
    options = options or {}
    local function read(path)
        local file = assert(io.open(root .. "/" .. path, "rb"))
        local text = file:read("*a")
        file:close()
        return text
    end
    local function slice(text, first, after)
        local start = assert(text:find(first, 1, true), first)
        assert(not text:find(first, start + #first, true), "ambiguous slice: " .. first)
        local finish = assert(text:find(after, start, true), after)
        return text:sub(start, finish - 1)
    end
    local function clone(value)
        if type(value) ~= "table" then return value end
        local out = {}
        for key, item in pairs(value) do out[key] = clone(item) end
        return out
    end
    local function install(text, env, name)
        local chunk = assert(loadstring(text, "@" .. name))
        setfenv(chunk, setmetatable(env, { __index = _G }))
        return chunk()
    end
    local noop = function() end
    local settings, calls = clone(initial), { events = 0, writes = 0, engines = 0, foot_knight = 0 }
    local mod = { _crt = {}, debug = noop, warning = noop }
    function mod:dofile(path) return assert(loadfile(root .. "/career_tweaker/" .. path .. ".lua"))() end
    function mod:get(id) return settings[id] end
    function mod:set(id, value, notify)
        settings[id] = clone(value)
        calls.writes = calls.writes + 1
        if notify then
            calls.events = calls.events + 1
            self.on_setting_changed(id)
        end
    end
    if vmf_settings_path then
        local storage = { crt = settings }
        local proto = {}
        local vmf = { mods = {}, mods_unloading_order = {}, safe_call_nr = function(_, _, callback, id)
            local ok, err = pcall(callback, id)
            assert(ok, err)
        end }
        local env = setmetatable({
            VMFMod = proto, get_mod = function() return vmf end,
            Application = { user_setting = function() return storage end },
            table = setmetatable({ clone = clone }, { __index = table }),
        }, { __index = _G })
        local events_path = vmf_settings_path:gsub("settings.lua$", "events.lua")
        for _, path in ipairs({ vmf_settings_path, events_path }) do
            local chunk = assert(loadfile(path))
            setfenv(chunk, env)
            chunk()
        end
        mod.get_name = function() return "crt" end
        mod.get = proto.get
        mod.set = function(self, id, value, notify)
            calls.writes = calls.writes + 1
            if notify then calls.events = calls.events + 1 end
            return proto.set(self, id, value, notify)
        end
    end
    local base = "career_tweaker/scripts/mods/career_tweaker/"
    local module = assert(loadfile(root .. "/" .. base .. "_crt_rework_master_policy.lua"))()
    local main = read(base .. "career_tweaker.lua")
    install("local _rework_master_batch = false\n"
        .. slice(main, "local function _rework_master_snapshot()", "-- One exact presentation catalog for issue #776.")
        .. slice(main, "mod.on_setting_changed = function(setting_id)", "mod.on_disabled = function()"), {
            mod = mod, ok_rmp = true, rework_master_module = module,
            rework_master_policy = module.new(options.ensrick or { rework_a = {} }, options.tourney or { "trn_a" }),
            tourney = options.tourney_engine or {}, balance = {}, mutex = { enforce = noop }, _dbg = noop,
            printf = options.printf or noop,
            foot_knight = { apply_settings = function() calls.foot_knight = calls.foot_knight + 1 end },
            _reconcile_rework_engines = function() calls.engines = calls.engines + 1 end,
        }, "actual-crt-armor-callback")
    local profile_check
    install(slice(read(base .. "_crt_regression.lua"), '_rt_register("issue221_armor_profile_owner", function()',
        '-- #221 profile-owner check end'), {
        mod = mod, _rt_register = function(_, callback) profile_check = callback end,
    }, "actual-crt-armor-runtime-check")

    local gui = "gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"
    local embedded = options.surface == "embedded"
    local class = embedded and "HeroViewStateModTweaker" or "ModTweakerView"
    local view_source = read(gui .. (embedded and "_mod_tweaker_state.lua" or "_mod_tweaker_view.lua"))
    local profiles = assert(loadfile(root .. "/" .. gui .. "_mod_tweaker_profiles.lua"))()
    local methods = {}
    local profile_values = clone(options.profile_values or {})
    local store = { debug = noop }
    function store:get(key) return profile_values[key] end
    function store:set(key, value)
        calls.profile_writes = (calls.profile_writes or 0) + 1
        profile_values[key] = clone(value)
    end
    install(slice(view_source, "local function _owner(category, setting_id)", "-- Native menu sound feedback.")
        .. slice(view_source, "local function _cat_key(category)", "-- Read a setting's EFFECTIVE value:")
        .. slice(view_source, "function " .. class .. ":_active_category_dirty()", "-- Recompute the APPLY button")
        .. slice(view_source, "function " .. class .. ":_profile_snapshot(category, defaults)",
            embedded and "-- APPLY: commit" or "-- (#446) Mutually-exclusive group enforcement.")
        .. slice(view_source, "function " .. class .. ":apply_pending(category)", "-- (v0.2.148-dev) RESTORE DEFAULTS:"), {
            ModTweakerView = methods, HeroViewStateModTweaker = methods, mod = store, profiles = profiles,
            transactions = assert(loadfile(root .. "/" .. gui .. "_mod_tweaker_transaction.lua"))(),
            profile_runtime = assert(loadfile(root .. "/" .. gui .. "_mod_tweaker_profile_runtime.lua"))(),
            default_reset = assert(loadfile(root .. "/" .. gui .. "_mod_tweaker_default_reset.lua"))(),
            -- Retain the actual #998 custom-category guards after integration.
            DialogueUI = assert(loadfile(root .. "/" .. gui .. "_mod_tweaker_dialogue.lua"))(),
            _mt = function() return { emit_profile_diagnostic = function()
                calls.profile_events = (calls.profile_events or 0) + 1
                if options.throw_observer or calls.throw_observer then error("planted observer failure") end
            end } end,
            _printf = noop, printf = noop, _play_click = noop,
            _nf = function(node, key) return node[key] end,
        }, "actual-gut-armor-staging-apply")

    local data = assert(loadfile(root .. "/" .. base .. "career_tweaker_data.lua"))
    setfenv(data, setmetatable({ get_mod = function()
        return { localize = function(_, key) return key end }
    end }, { __index = _G }))
    local nodes = {}
    local function visit(node)
        nodes[#nodes + 1] = node
        for _, child in ipairs(node.sub_widgets or {}) do visit(child) end
    end
    for _, node in ipairs(data().options.widgets) do visit(node) end
    local view = setmetatable({
        _pending = {}, _build_nodes = nodes, _search_note_setting = noop,
        _profile_ready = {}, _update_apply_button = noop, _build_rows = noop,
    }, { __index = methods })
    local category = { mod_id = "crt", mod_obj = mod }
    view._categories, view._selected = { category }, 1
    view._profile_capture = function(self, selected)
        local result = methods._profile_capture(self, selected)
        self.captured = profiles.load(store, "crt", profiles.get_active(store, "crt"))
        return result
    end
    return { mod = mod, state = settings, calls = calls, view = view, category = category,
        profiles = profiles, store = store, profile_values = profile_values, profile_check = profile_check }
end
