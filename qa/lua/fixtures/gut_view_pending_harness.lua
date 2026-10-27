-- Complete actual view/VMF loader/private owner and exact entry supplier.
-- Engine rendering/class construction/WWise are explicit boundary ledgers.
-- VMF safe_calls is complete source; only the engine vararg-xpcall convention
-- is supplied by the Lua5.1 host. No host globals/metatables are changed.
local M = {}
local REL = "gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"
local SCRIPT = "scripts/mods/gui_tweaker_dev/"
local function pack(...) return { n = select("#", ...), ... } end
local function read(root, path)
    local file = assert(io.open(root .. "/" .. path, "rb"), "required GUI pending source missing: " .. path)
    local source = file:read("*a"); file:close(); return source
end
local function slice(source, first, after)
    local from = assert(source:find(first, 1, true), first)
    assert(not source:find(first, from + #first, true), "ambiguous source start")
    local to = assert(source:find(after, from + #first, true), after)
    return source:sub(from, to - 1)
end
-- Only this fixed structural extraction is reversed, in memory. The outside
-- source proof binds its complete old result to the published view's raw SHA.
function M.prior_view(current, fixture)
    local function replace_once(before, after)
        local at = assert(current:find(before, 1, true), "prior view inverse anchor absent")
        assert(not current:find(before, at + #before, true), "prior view inverse anchor ambiguous")
        current = current:sub(1, at - 1) .. after .. current:sub(at + #before)
    end
    replace_once("return ModTweakerView, function(install)\n" ..
        "    return install(ModTweakerView, {\n" ..
        "        mod = mod, transactions = transactions, default_reset = default_reset,\n" ..
        "        profiles = profiles, profile_runtime = profile_runtime, DialogueUI = DialogueUI,\n" ..
        "        owner = _owner, nf = _nf, cat_get = _cat_get, cat_set = _cat_set,\n" ..
        "        mt = _mt, printf = _printf, play_click = _play_click, commit_keybind = _commit_keybind,\n" ..
        "    })\nend\n", "return ModTweakerView\n")
    replace_once("-- The entry installs this closed cluster from _mod_tweaker_view_pending before the\n" ..
        "-- class can be constructed. Its private second-return binder below captures these\n" ..
        "-- already-defined _cat_set / _play_click locals, never a forward global reference.\n" ..
        "-- The TWIN (state) retains its own original installation point and behavior.\n" ..
        "-- No staged method is called while the retained presentation children install.", fixture.published_comment)
    local boundary = "\n-- ---------------------------------------------------------------\n-- Build the row widgets for a category."
    replace_once(boundary, fixture.published_span .. boundary)
    return current
end
function M.new(H, root, options)
    options = options or {}
    local quiet = setmetatable({ test = function() end }, { __index = H })
    local Rows = assert(loadfile(root .. "/qa/lua/tests/test_gut_view_rows.lua"))()(quiet, root, options.sources)
    local f = Rows.fixture(options.rows)
    local env, mod, dispatch = f.env, f.mod, f.mod.dofile
    local source = assert(loadfile(root .. "/qa/lua/fixtures/gut_view_pending_source.lua"))()
    assert(type(source.vmf_safe_calls) == "string" and type(source.published_span) == "string")
    assert(#source.vmf_safe_calls == 3484, "complete actual VMF source required")
    f.vmf_logs, f.module_trace, f.staged_during_install, f.settings, f.modules = {}, {}, {}, {}, {}
    local function trace(...)
        f.trace[#f.trace + 1] = pack(...)
    end
    env.printf = function(...) trace("captured_print", ...) end
    env.UIRenderer, env.UISceneGraph = {}, {}
    env.UIInverseScaleVectorToResolution = function(value) return value end
    env.Script = { callstack = function() return "<host callstack boundary>" end }
    env.print = function(...) f.vmf_logs[#f.vmf_logs + 1] = pack("print", ...) end
    env.Localize = function(value) trace("localize", value); return "localized:" .. value end
    env.Managers = {}
    mod.error = function(_, ...) f.vmf_logs[#f.vmf_logs + 1] = pack("error", ...) end
    mod.get = function(_, key) return f.settings[key] end
    mod.set = function(_, key, value) trace("store", key, value); f.settings[key] = value end
    f.provider.set = function(_, key, value, notify)
        trace("set", key, value, notify); f.values[key] = value
    end
    -- Existing supported host convention: Lua5.1 xpcall does not forward args,
    -- whereas VMF's engine host does. Keep this one collaborator explicit.
    env.xpcall = function(callback, handler, ...)
        local arguments = pack(...)
        return xpcall(function() return callback(unpack(arguments, 1, arguments.n)) end, handler)
    end
    local vmf, proto, original_get_mod = {}, {}, env.get_mod
    env.VMFMod = proto
    env.get_mod = function(id)
        if id == "VMF" then return vmf end
        return original_get_mod(id)
    end
    local function current(path)
        if options.sources and options.sources[path] then return options.sources[path] end
        return read(root, path)
    end
    local function run(text, name)
        local chunk = assert(loadstring(text, "@" .. name)); setfenv(chunk, env); return chunk()
    end
    local real = {
        _mod_tweaker_view_pending = true, _mod_tweaker_transaction = true,
        _mod_tweaker_default_reset = true, _mod_tweaker_profiles = true,
        _mod_tweaker_profile_runtime = true, _mod_tweaker_dialogue = true,
        _mod_tweaker_view_diagnostics = true, _mod_tweaker_view_interaction = true,
        _mod_tweaker_slider_drag_edge = true,
    }
    env.dofile = function(path)
        local name = assert(path:match("([^/]+)$"))
        f.module_trace[#f.module_trace + 1] = name
        if name == "_mod_tweaker_view" then
            if f.chunk_error then error(f.chunk_error, 0) end
            if f.raw_return then return f.raw_return() end
            local text = current(REL .. name .. ".lua")
            if options.prior then return run(M.prior_view(text, source), "published-complete-view") end
            local class, binder = run(text, REL .. name .. ".lua")
            if options.disconnect_binder then return class end
            return class, function(install)
                return binder(function(target, deps)
                    f.deps = deps
                    if options.installer then return options.installer(install, target, deps) end
                    return install(target, deps)
                end)
            end
        end
        if name == "_mod_tweaker_sound" then
            f.sound = { new_probe = function() return {} end,
                play = function(event) trace("sound", event) end, resolve = function() return {} end }
            return f.sound
        end
        local value
        if real[name] then value = run(current(REL .. name .. ".lua"), REL .. name .. ".lua")
        else value = dispatch(mod, path) end
        f.modules[name] = value
        if name == "_mod_tweaker_view_rows" or name == "_mod_tweaker_view_diagnostics"
                or name == "_mod_tweaker_view_interaction" then
            local install = assert(value.install)
            value.install = function(class, deps)
                f.staged_during_install[#f.staged_during_install + 1] = { name, rawget(class, "stage_set") }
                if options.child_install then options.child_install(name, class, deps, f) end
                return install(class, deps)
            end
        end
        return value
    end
    run(source.vmf_safe_calls, "vmf/modules/core/safe_calls.lua")
    f.proto, f.vmf = proto, vmf
    rawset(mod, "dofile", nil)
    setmetatable(mod, { __index = function(_, key)
        if key == "dofile" then
            f.getter_calls = (f.getter_calls or 0) + 1
            if f.getter_error then error(f.getter_error, 0) end
        end
        return rawget(proto, key)
    end })
    local class_factory = env.class
    env.class = function(base)
        local class = class_factory(base)
        class.new = function(_, context)
            for _, name in ipairs({ "stage_set", "get_staged", "apply_pending", "reset_to_defaults",
                    "_profile_snapshot", "_profile_ensure", "_profile_capture", "_switch_profile",
                    "_queue_reset_popup", "_check_reset_popup" }) do
                assert(type(rawget(class, name)) == "function", "constructor reached before pending install: " .. name)
            end
            f.constructed = (f.constructed or 0) + 1
            trace("constructor", context)
            return setmetatable({ _pending = {}, _rows = {}, _profile_ready = {},
                _categories = { f.category }, _selected = 1, _build_category = f.category,
                _build_nodes = {}, _apply = { content = {} } }, class)
        end
        return class
    end
    local entry = current(REL .. "gui_tweaker_dev.lua")
    local supplier = slice(entry,
        '    load_view = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_view_pending").bind_view_supplier(function()',
        '    load_localization = function()')
    local body = assert(supplier:match('(        return pcall%(mod%.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_view"%))'))
    f.legacy_load = run("return function(mod) return function()\n" .. body .. "\nend end", "original-supplier-expression")(mod)
    if options.prior then f.load_view = f.legacy_load
    else f.load_view = run("return function(mod) return {\n" .. supplier .. "} end\n", "actual-entry-supplier")(mod).load_view end
    -- The real shell's full attach function, not an invented constructor flow.
    local shell = current(REL .. "_gut_mod_tweaker_shell.lua"):gsub("\r\n", "\n")
    local attach = slice(shell, "        local function _attach_view(self, ctx_arg)",
        "\n        -- The entry owns LA's forward-declared keepalive")
    f.attach = run("return function(load_view, _dbg, _dbg_alert)\n" .. attach .. "\nreturn _attach_view end",
        "actual-shell-attach")(f.load_view, function(...) trace("attach_debug", ...) end,
        function(...) trace("attach_alert", ...) end)
    f.pack, f.read, f.run = pack, current, run
    function f.instance()
        local result = pack(f.load_view()); H.equal(result.n, 2); H.equal(result[1], true)
        local class = result[2]; H.equal(type(class), "table")
        local view = class:new({ ui_renderer = {} })
        view._search_note_setting = function(_, category, setting) trace("search", category.mod_id, setting) end
        view._build_rows = function(_, category) trace("rebuild", category.mod_id) end
        return view, class
    end
    return f
end
return M
