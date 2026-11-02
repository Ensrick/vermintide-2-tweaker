-- #605: execute the actual official category bridge through the installed
-- frontend/catalog/controller owners. Renderer and sound boundaries are sinks.
return function(H, repo_root)
    local base = "gui_tweaker/scripts/mods/gui_tweaker/"
    local function read(name)
        local file = assert(io.open(repo_root .. "/" .. base .. name .. ".lua", "rb"))
        local source = file:read("*a"); file:close(); return source
    end
    local function compatible(version)
        local calls = 0
        local value = { version = version or 6 }
        for _, name in ipairs({ "browser_groups", "browser_page", "browser_window",
                "browser_reconcile_focus", "get_line_state", "set_line_state",
                "toggle_pause", "stop", "preview_state" }) do
            value[name] = function() calls = calls + 1; error("registration must not invoke the provider") end
        end
        return { is_enabled = function() return true end, character_dialogue_api = value },
            function() return calls end
    end
    local function fixture(cd)
        local trace, cache, settings = {}, {}, {}
        local math_copy = {}; for key, value in pairs(math) do math_copy[key] = value end
        math_copy.clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end
        local env = setmetatable({ math = math_copy }, { __index = _G }); env._G = env
        local mod = {}
        function mod:get(key) return settings[key] end
        function mod:set(key, value) settings[key] = value end
        function mod:debug() end
        function mod:warning() end
        function mod:localize(key) return "<" .. key .. ">" end
        env.printf = function() end
        env.class = function(value) value = value or {}; value.__index = value; return value end
        env.get_mod = function(id)
            if id == "gut" then return mod end
            if id == "character_dialogue" then return cd end
        end
        local defs = { create_tab = function(label, index)
            return { content = { text = label, index = index } }
        end }
        local function load(name)
            if cache[name] then return cache[name] end
            local chunk = assert(loadstring(read(name), "@" .. base .. name .. ".lua"))
            setfenv(chunk, env)
            local value = chunk(); cache[name] = value; return value
        end
        function mod:dofile(path)
            local name = assert(path:match("([^/]+)$"))
            if name == "_mod_tweaker_definitions" then return defs end
            if name == "_mod_tweaker_view_interaction" or name == "_mod_tweaker_view_diagnostics" then
                return { install = function() end }
            end
            -- The view has a private second-return binder: do not cache away its tuple.
            if name == "_mod_tweaker_view" then
                local chunk = assert(loadstring(read(name), "@" .. base .. name .. ".lua"))
                setfenv(chunk, env); return chunk()
            end
            return load(name)
        end
        local mt = load("_mod_tweaker")
        mt.install(function() end, function() end); mod.mod_tweaker = mt
        local original_register, original_list = mt.register_category, mt.list_categories
        local registrations = 0
        function mt:register_category(def)
            trace[#trace + 1] = "register"
            registrations = registrations + 1
            return original_register(self, def)
        end
        function mt:list_categories()
            trace[#trace + 1] = "enumerate"
            return original_list(self)
        end
        local catalog, pending = load("_mod_tweaker_view_catalog"), load("_mod_tweaker_view_pending")
        local ok, Class = pending.bind_view_supplier(function()
            return pcall(mod.dofile, mod, "scripts/mods/gui_tweaker/_mod_tweaker_view")
        end, catalog.bind)()
        H.truthy(ok, Class)
        local view = setmetatable({ _rows = {} }, Class)
        function view:_layout_tabs() end
        function view:_build_rows(category) self.built = category; self._rows = {} end
        return { view = view, mt = mt, mod = mod, env = env, load = load,
            trace = trace, count = function() return registrations end,
            replace_cd = function(value) cd = value end }
    end

    H.test("official Dialogue bootstraps before actual registry enumeration and only once", function()
        local cd, calls = compatible()
        local f = fixture(cd)
        H.equal(f.count(), 0, "binding is inert")
        f.view:_rebuild()
        H.deep_equal(f.trace, { "register", "enumerate" })
        H.equal(f.count(), 1); H.equal(calls(), 0)
        local category = f.mt:get_category("character_dialogue")
        H.equal(category, f.view.built)
        H.equal(category.label, "Dialogue")
        H.equal(f.load("_mod_tweaker_dialogue").is_category(category), true)
        H.equal(category.widgets[1].setting_id, "dialogue_browser")
        H.equal(#category.widgets, 1)
        f.view:_rebuild(); f.view:_rebuild()
        H.equal(f.count(), 1); H.equal(calls(), 0)
        H.equal(f.mt:get_category("character_dialogue"), category)
    end)
    H.test("official Dialogue bridge supports a complete older browser API", function()
        local f = fixture(compatible(2)); f.view:_rebuild()
        H.equal(f.count(), 1)
    end)
    H.test("official Dialogue absent old disabled and partial APIs stay absent", function()
        local candidates = { false, {}, { character_dialogue_api = { version = 1 } } }
        local disabled = compatible(); disabled.is_enabled = function() return false end
        local partial = compatible(); partial.character_dialogue_api.browser_window = nil
        local bad_version = compatible(); bad_version.character_dialogue_api.version = "6"
        local fault = compatible(); fault.is_enabled = function() error("disabled probe failure") end
        candidates[#candidates + 1] = disabled; candidates[#candidates + 1] = partial
        candidates[#candidates + 1] = bad_version; candidates[#candidates + 1] = fault
        for _, cd in ipairs(candidates) do
            local f = fixture(cd); f.view:_rebuild()
            H.equal(f.count(), 0); H.equal(f.mt:get_category("character_dialogue"), nil)
        end
    end)
    H.test("official Dialogue observes a late provider without rebinding", function()
        local f = fixture(nil); f.view:_rebuild(); H.equal(f.count(), 0)
        f.replace_cd(compatible()); f.view:_rebuild()
        H.equal(f.count(), 1)
    end)
    H.test("official Dialogue never replaces an already registered provider category", function()
        local f = fixture(compatible())
        H.equal(f.mt:register_category({ mod_id = "character_dialogue", label = "Provider category",
            widgets = { { setting_id = "provider_owned", type = "checkbox" } } }), true)
        local original = f.mt:get_category("character_dialogue")
        f.view:_rebuild()
        H.equal(f.count(), 1); H.equal(f.mt:get_category("character_dialogue"), original)
        H.equal(original.label, "Provider category")
    end)
    H.test("official Dialogue refuses malformed or failing registry collaborators", function()
        local f = fixture(compatible())
        local bridge = f.load("_mod_tweaker_dialogue").register_category
        H.equal(bridge(nil), false); H.equal(bridge({}), false)
        H.equal(bridge({ is_registered = function() error("bad registry") end,
            register_category = function() error("must not reach") end }), false)
        H.equal(bridge({ is_registered = function() return false end,
            register_category = function() error("registration refusal") end }), false)
        H.equal(f.count(), 0)
    end)
    H.test("official Dialogue bootstrap has no hook lifecycle or frame-loop authority", function()
        local source = read("_mod_tweaker_dialogue")
        for _, needle in ipairs({ "mod:hook", "mod:command", "function mod.update", "function mod.on_" }) do
            H.equal(source:find(needle, 1, true), nil)
        end
        H.truthy(read("_mod_tweaker_view_catalog"):find("register_dialogue_category(mod.mod_tweaker)", 1, true))
        H.truthy(read("_mod_tweaker_view"):find("register_dialogue_category = DialogueUI.register_category", 1, true))
    end)
end
