-- #2: execute the whole standalone owner, its installed row child and consumers.
-- Factories are table-only boundary doubles, not an engine/renderer simulation.
return function(H, repo_root, source_override)
    local root = "gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"
    local view_path, rows_path = root .. "_mod_tweaker_view.lua", root .. "_mod_tweaker_view_rows.lua"
    local function read(path)
        if source_override and source_override[path] then return source_override[path] end
        local file = assert(io.open(repo_root .. "/" .. path, "rb"))
        local source = file:read("*a"); file:close(); return source
    end
    local function pack(...) return { n = select("#", ...), ... } end
    local function count(source, needle)
        local n, at = 0, 1
        while true do
            at = source:find(needle, at, true)
            if not at then return n end
            n, at = n + 1, at + #needle
        end
    end
    local function fixture(options)
        options = options or {}
        local trace, loads, printed, warnings = {}, {}, {}, {}
        local token = {}
        local math_copy = {}; for k, v in pairs(math) do math_copy[k] = v end
        math_copy.clamp = function(v, a, b) return math.max(a, math.min(b, v)) end
        local env = setmetatable({ math = math_copy }, { __index = _G })
        env._G = env
        local mod = { mod_tweaker = {} }
        function mod:debug(...) trace[#trace + 1] = { "debug", ... } end
        function mod:warning(...) warnings[#warnings + 1] = pack(...) end
        function mod.mod_tweaker:apply_runtime_gate(row, owner, setting)
            trace[#trace + 1] = { "gate", row, owner, setting }
            if options.gate_error then error(token, 0) end
        end
        function mod.mod_tweaker:get_exclusive_members()
            return options.members or { { setting_id = "one" }, { setting_id = "two" } }
        end
        local values = options.values or { setting = true, one = false, two = false }
        local provider = {}
        function provider:get(id)
            trace[#trace + 1] = { "get", id }
            if options.get_error then error(token, 0) end
            return values[id]
        end
        function provider:localize(key) return "localized:" .. key end
        local defs = { row_w = 800, gear_col_w = 50 }
        local function factory(kind)
            return function(label, offset, depth, extra, fifth)
                if kind == "group" then
                    label, offset, depth, extra = label, depth, extra, offset
                elseif kind == "slider" then
                    label, offset, depth, extra = label, depth, extra, offset
                end
                trace[#trace + 1] = { "factory", kind, label, offset, depth, extra, fifth }
                offset[2] = offset[2] - 40
                if options.factory_error == kind then error(token, 0) end
                if options.factory_nil == kind then return nil end
                if options.factory_false == kind then return false end
                return { content = {}, style = {
                    label = { text_color = { 255, 1, 2, 3 } }, hotspot = { size = { 800, 40 } },
                }, authored_kind = kind }
            end
        end
        for _, kind in ipairs({ "checkbox", "radio", "slider", "dropdown", "section_title", "group_header" }) do
            local tag = kind == "group_header" and "group" or kind
            defs["create_" .. kind] = factory(tag)
        end
        function defs.create_gear_button(y)
            trace[#trace + 1] = { "gear", y }
            if options.gear_error then error(token, 0) end
            if options.gear_nil then return nil end
            return { content = {}, style = {}, authored_kind = "gear" }
        end
        -- Execute the existing ONE #717 policy, not a copied color decision.
        local source = read(root .. "_mod_tweaker_definitions.lua")
        local accent = assert(source:match("(local function apply_gear_parent_accent%(row, has_gear%).-\nend\n)"))
        defs.apply_gear_parent_accent = assert(loadstring(accent .. "\nreturn apply_gear_parent_accent"))()
        local original_accent = defs.apply_gear_parent_accent
        defs.apply_gear_parent_accent = function(row, gear)
            trace[#trace + 1] = { "accent", row, gear }
            if options.accent_error then error(token, 0) end
            return original_accent(row, gear)
        end
        defs.plan_drill_children = function(nodes, depths, index)
            local plan = {}
            for i = index + 1, #nodes do
                if depths[i] <= depths[index] then break end
                plan[#plan + 1] = { index = i, depth = depths[i], has_gear = false }
            end
            return plan
        end
        defs.create_back_row = function(label, offset)
            return factory("back")(label, offset, 0)
        end
        local installed, install_count
        local pure = {
            _mod_tweaker_search = true, _mod_tweaker_ordering = true,
            _mod_tweaker_label_policy = true, _mod_tweaker_exclusive_layout = true,
            _mod_tweaker_view_catalog = true,
            _mod_tweaker_view_pending = true,
        }
        local function load_source(path)
            local chunk = assert(loadstring(read(path), "@" .. path)); setfenv(chunk, env); return chunk()
        end
        function mod:dofile(path)
            local name = assert(path:match("([^/]+)$"))
            loads[name] = (loads[name] or 0) + 1
            if name == "_mod_tweaker_definitions" then return defs end
            if name == "_mod_tweaker_view_rows" then
                local rows = load_source(root .. name .. ".lua")
                local install = rows.install
                rows.install = function(class, deps)
                    install_count = (install_count or 0) + 1; installed = deps
                    H.equal(deps.mod, mod); H.equal(deps.defs, defs); H.equal(deps.math, math_copy)
                    for _, key in ipairs({ "mt", "nf", "owner", "vmf_label", "vmf_tooltip", "cat_get", "resolve_step", "format_keybind_value" }) do
                        H.equal(type(deps[key]), "function", "missing real view dependency " .. key)
                    end
                    return install(class, deps)
                end
                return rows
            end
            if pure[name] then return load_source(root .. name .. ".lua") end
            if name == "_mod_tweaker_dialogue" then return { is_category = function() return false end } end
            if name == "_mod_tweaker_sound" then return {
                new_probe = function() return {} end, play = function() end,
                click = function() end, hover = function() end,
            } end
            if name == "_gut_dx12_fence630" then return {} end
            return { install = function() end }
        end
        env.get_mod = function(id) H.equal(id, "gut_dev"); return mod end
        env.class = function(class) class = class or {}; class.__index = class; return class end
        env.printf = function(...) printed[#printed + 1] = pack(...) end
        local pending = load_source(root .. "_mod_tweaker_view_pending.lua")
        local ok, Class = pending.bind_view_supplier(function() return pcall(load_source, view_path) end)()
        H.truthy(ok, Class)
        H.equal(loads._mod_tweaker_view_rows, 1, "view must load the real child once")
        H.equal(install_count, 1, "view must install the real child once")
        H.equal(type(Class._build_node_row), "function"); H.equal(type(Class._append_row), "function")
        local category = { mod_id = "gut_equipment", mod_obj = provider, _flat = true }
        local view = setmetatable({ _pending = {}, _expanded = {}, _rows = {} }, Class)
        function view:_profile_ensure() end -- retained profile owner is outside this proof
        function view:_recompute_scroll_bounds() self._max_scroll = 0 end
        return {
            view = view, Class = Class, category = category, provider = provider, values = values,
            defs = defs, trace = trace, printed = printed, warnings = warnings,
            token = token, deps = installed, env = env, mod = mod,
        }
    end
    local function node(kind, fields)
        local value = { type = kind, setting_id = "setting", title = "title", tooltip = "description" }
        for key, v in pairs(fields or {}) do value[key] = v end
        return value
    end
    local function build(f, kind, fields, depth, expanded)
        local offset = { 0, -10, 0 }
        return pack(f.view:_build_node_row(node(kind, fields), f.category, offset, depth, expanded)), offset
    end
    local function events(f)
        local out = {}; for _, row in ipairs(f.trace) do out[#out + 1] = row[1] end; return out
    end
    H.test("GUT row child has one hook-free installed owner and retains method identities", function()
        local source, child = read(view_path), read(rows_path)
        H.equal(count(source, 'mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_view_rows")'), 1)
        H.equal(count(source, "function ModTweakerView:_build_node_row"), 0)
        H.equal(count(source, "function ModTweakerView:_append_row"), 0)
        for _, forbidden in ipairs({ "mod:dofile(", "mod:hook", "mod:command", "function mod.update", "function mod.on_" }) do
            H.equal(count(child, forbidden), 0, forbidden)
        end
        local f = fixture()
        H.equal(f.deps.mt(), f.mod.mod_tweaker)
        H.equal(f.deps.owner(f.category, "setting"), f.provider)
        local package = read("gui_tweaker_dev/resource_packages/gui_tweaker_dev/gui_tweaker_dev.package")
        H.truthy(package:find('"scripts/mods/gui_tweaker_dev/*"', 1, true))
    end)
    H.test("GUT row header preserves five returns without a factory or warning", function()
        local f = fixture(); local result, offset = build(f, "header")
        H.equal(result.n, 5); H.equal(result[1], nil); H.equal(result[2], nil)
        H.equal(result[3], "header"); H.equal(result[4], "setting"); H.equal(result[5], "localized:title")
        H.equal(offset[2], -10); H.equal(#f.trace, 0)
        f.view:_append_row(result[1], result[2], result[3], f.category, result[4], offset, false)
        H.equal(#f.warnings, 0)
    end)
    for _, kind in ipairs({ "checkbox", "boolean", "radio", "slider", "numeric", "dropdown", "action", "keybind", "text", "unknown" }) do
        H.test("GUT installed row fixed metadata: " .. kind, function()
            local f = fixture({ values = { setting = kind == "keybind" and { "left alt" } or 0.25 } })
            local result, offset = build(f, kind, { range = { 0, 1 }, decimals_number = 2,
                options = { { value = 0.25, text = "Quarter" } }, on_activate = print })
            local row = result[1]
            H.equal(result.n, 5); H.equal(result[2], nil); H.equal(row._mod_id, "gut_equipment")
            H.equal(row._setting_id, "setting"); H.equal(row._wtype, kind)
            H.equal(row._category, f.category); H.equal(row._list_y, -50); H.equal(offset[2], -50)
            H.equal(row._tip_title, "localized:title"); H.equal(row._tip_desc, "localized:description")
            H.equal(f.trace[#f.trace][1], "gate")
            if kind == "slider" or kind == "numeric" then
                H.equal(row.content.value, 0.25); H.equal(row.content.internal_value, 0.25)
                H.equal(row.content.step, 0.01); H.equal(row.content.value_text, "0.25")
            elseif kind == "dropdown" then
                H.equal(row.content.value_text, "Quarter"); H.equal(row.content.active, false)
            elseif kind == "keybind" then
                H.equal(row.content.value_text, "LEFT ALT"); H.equal(row._is_keybind, true)
            elseif kind == "action" then
                H.equal(row._action, print); H.equal(row._is_action, true); H.equal(row.content.value_text, "RUN")
            elseif kind == "text" or kind == "unknown" then H.equal(row._readonly, true) end
        end)
    end
    H.test("GUT installed row preserves owner localization, step25 and staged false", function()
        local f = fixture({ values = { setting = 324 } })
        f.category._owners = { setting = { mod_id = "cim_dev", mod_obj = f.provider } }
        f.view._pending.cim_dev = { setting = false }
        local result = build(f, "checkbox"); H.equal(result[1].content.flag, false)
        f.category._owners.base_power_level = f.category._owners.setting
        f.values.base_power_level = 324; f.view._pending.cim_dev.base_power_level = 325
        local slider = build(f, "numeric", { setting_id = "base_power_level", range = { 0, 950 } })
        H.equal(slider[1].content.step, 25); H.equal(slider[1].content.value, 325)
        H.equal(slider[1]._mod_id, "cim_dev"); H.equal(slider[1].content.value_text, "325")
    end)
    H.test("GUT installed keybind retains the exact deferred definition fields", function()
        local f = fixture({ values = { setting = { "ctrl", "f" } } }); local transition = {}
        local result = build(f, "keybind", { keybind_type = "function_call", keybind_trigger = "pressed",
            keybind_global = false, function_name = "invoke", view_name = "screen", transition_data = transition })
        H.deep_equal(result[1]._keybind_def, { keybind_type = "function_call", keybind_trigger = "pressed",
            keybind_global = false, function_name = "invoke", view_name = "screen", transition_data = transition })
        H.equal(result[1]._keybind_def.transition_data, transition)
        H.equal(result[1].content.value_text, "CTRL + F")
    end)
    H.test("GUT numeric invalid value falls back without snapping valid off-grid values", function()
        local f = fixture({ values = { setting = "invalid" } })
        local result = build(f, "slider", { range = { 3, 3 }, step = 2, decimals_number = 1 })
        H.equal(result[1].content.value, 3); H.equal(result[1].content.internal_value, 0)
        H.equal(result[1].content.step, 2); H.equal(result[1].content.value_text, "3.0")
        f.values.setting = 3.25
        result = build(f, "slider", { range = { 0, 10 }, step = 2, decimals_number = 2 })
        H.equal(result[1].content.value, 3.25); H.equal(result[1].content.internal_value, 0.325)
    end)
    H.test("GUT no-gear append leaves authored style and metadata alone", function()
        local f = fixture(); local result, offset = build(f, "checkbox")
        f.view:_append_row(result[1], nil, "checkbox", f.category, "setting", offset, false)
        H.equal(#f.view._rows, 1); H.deep_equal(result[1].style.label.text_color, { 255, 1, 2, 3 })
        H.equal(result[1].style.hotspot.size[1], 800); H.equal(result[1]._advanced_parent_accent, nil)
        H.equal(f.trace[#f.trace][1], "gate")
    end)
    for _, expanded in ipairs({ false, true }) do
        H.test("GUT installed group preserves explicit display state " .. tostring(expanded), function()
            local f = fixture(); local w = node("group"); local key = f.view:_group_key(w, f.category)
            f.view._expanded[key] = not expanded
            local result = build(f, "group", nil, 3, expanded)
            H.equal(result[1]._group_key, key); H.equal(result[1]._is_group, true)
            H.equal(result[1]._display_expanded, expanded); H.equal(f.trace[1][6], expanded)
            H.equal(f.trace[1][5], 3)
        end)
    end
    H.test("GUT installed group defaults to stored expansion without writing it", function()
        local f = fixture(); local key = f.view:_group_key(node("group"), f.category); f.view._expanded[key] = true
        local result = build(f, "group"); H.equal(result[1]._display_expanded, nil)
        H.equal(f.trace[1][6], true); H.equal(f.view._expanded[key], true)
    end)
    for _, value in ipairs({ false, true }) do
        H.test("GUT installed None radio reads current staged members " .. tostring(value), function()
            local f = fixture(); f.view._pending.gut_equipment = { two = value }
            local result = build(f, "radio", { _mt_exclusive_group = "group", _mt_exclusive_none = true })
            H.equal(result[1].content.selected, not value); H.equal(result[1]._mt_radio_none, true)
            H.equal(result[1]._mt_radio_group, "group")
        end)
    end
    H.test("GUT lazy options provider precedes factory and preserves selected last duplicate", function()
        local f = fixture({ values = { setting = "b" } }); local calls = 0
        local provider = function()
            calls = calls + 1; f.trace[#f.trace + 1] = { "provider" }
            return { { value = "a", text = "A" }, { value = "b", text = "B" }, { value = "b", text = "B2" } }
        end
        local result = build(f, "dropdown", { options_provider = provider })
        H.deep_equal(events(f), { "provider", "factory", "get", "gate" }); H.equal(calls, 1)
        H.equal(result[1]._option_idx, 3); H.equal(result[1].content.value_text, "B2")
        H.deep_equal(result[1]._options_values, { "a", "b", "b" })
        build(f, "dropdown", { options = {}, options_provider = provider }); H.equal(calls, 1)
    end)
    for _, mode in ipairs({ "throw", "scalar", "empty" }) do
        H.test("GUT lazy options failure remains readonly: " .. mode, function()
            local f = fixture()
            local result = build(f, "dropdown", { options_provider = function()
                if mode == "throw" then error(f.token, 0) elseif mode == "scalar" then return false else return {} end
            end })
            H.equal(result[1]._readonly, true); H.equal(result[1].content.value_text, "?")
            H.equal(#f.warnings, mode == "empty" and 0 or 1)
            if mode == "throw" then H.equal(f.warnings[1][4], tostring(f.token)) end
        end)
    end
    for _, mode in ipairs({ "error", "nil", "false" }) do
        H.test("GUT factory " .. mode .. " preserves offset and error return identity", function()
            local opts = {}; opts["factory_" .. mode] = "checkbox"
            local f = fixture(opts); local result, offset = build(f, "checkbox")
            H.equal(result.n, 5); H.equal(result[1], nil); H.equal(offset[2], -50)
            local expected
            if mode == "error" then expected = f.token elseif mode == "false" then expected = false end
            H.equal(result[2], expected)
            H.deep_equal(events(f), { "factory" })
            f.view:_append_row(result[1], result[2], result[3], f.category, result[4], offset, false)
            H.equal(#f.warnings, 1); H.equal(#f.view._rows, 0)
        end)
    end
    H.test("GUT runtime gate error propagates unchanged after row decoration", function()
        local f = fixture({ gate_error = true })
        local ok, err = pcall(build, f, "checkbox"); H.equal(ok, false); H.equal(err, f.token)
        local gate = f.trace[#f.trace]; H.equal(gate[1], "gate")
        H.equal(gate[2]._setting_id, "setting"); H.equal(gate[2]._tip_desc, "localized:description")
    end)
    H.test("GUT raw marker printf remains late-bound after whole-view installation", function()
        local f = fixture(); local late = {}
        f.env.printf = function(...) late[#late + 1] = pack(...) end
        build(f, "checkbox", { title = "<title>" })
        H.equal(#late, 1); H.equal(#f.printed, 0)
        H.equal(late[1][1], "[gut:desc] MARKER mod=%s sid=%s type=%s raw_title=%q raw_tt=%q -> label=%q desc=%q")
    end)
    for _, disabled in ipairs({ false, true }) do
        H.test("GUT append actual shared gear accent preserves disabled state " .. tostring(disabled), function()
            local f = fixture(); local result, offset = build(f, "checkbox", { disabled = disabled })
            f.view:_append_row(result[1], result[2], result[3], f.category, result[4], offset, true, "Parent")
            H.equal(#f.view._rows, 2); H.equal(f.view._rows[1], result[1])
            local gear = f.view._rows[2]; H.equal(gear._is_gear, true); H.equal(gear._list_y, -50)
            H.equal(gear._drill_setting, "setting"); H.equal(gear._drill_label, "Parent")
            H.equal(gear._category, f.category); H.equal(result[1].style.hotspot.size[1], 750)
            H.deep_equal(result[1].style.label.text_color, disabled and { 128, 128, 128, 128 } or { 255, 160, 146, 101 })
            H.equal(f.trace[#f.trace - 1][1], "accent"); H.equal(f.trace[#f.trace][1], "gear")
        end)
    end
    for _, mode in ipairs({ "error", "nil" }) do
        H.test("GUT failed gear factory retains parent silently: " .. mode, function()
            local opts = {}; opts["gear_" .. mode] = true
            local f = fixture(opts); local result, offset = build(f, "checkbox")
            f.view:_append_row(result[1], nil, "checkbox", f.category, "setting", offset, true)
            H.equal(#f.view._rows, 1); H.equal(f.view._rows[1], result[1]); H.equal(#f.warnings, 0)
        end)
    end
    H.test("GUT append accent error propagates with already-appended parent", function()
        local f = fixture({ accent_error = true }); local result, offset = build(f, "checkbox")
        local ok, err = pcall(f.view._append_row, f.view, result[1], nil, "checkbox", f.category, "setting", offset, true)
        H.equal(ok, false); H.equal(err, f.token); H.equal(#f.view._rows, 1)
        H.equal(f.view._rows[1], result[1]); H.equal(f.trace[#f.trace][1], "accent")
    end)
    for _, route in ipairs({ "normal", "search", "drill" }) do
        H.test("GUT actual build_rows consumes installed row owner: " .. route, function()
            local f = fixture(); f.category.widgets = {
                node("checkbox", { setting_id = "parent", title = "Parent", depth = 0 }),
                node("checkbox", { setting_id = "child", title = "Child", depth = 1 }),
                node("checkbox", { setting_id = "last", title = "Last", depth = 0 }),
            }
            f.values.parent, f.values.child, f.values.last = true, false, true
            if route == "search" then f.view._search_str = "child"
            elseif route == "drill" then f.view._drill = { setting_id = "parent", label = "Parent" } end
            f.view:_build_rows(f.category)
            local ids = {}; for _, row in ipairs(f.view._rows) do
                ids[#ids + 1] = row._is_gear and "gear" or row._is_back and "back" or row._setting_id
            end
            H.deep_equal(ids, route == "normal" and { "parent", "gear", "last" }
                or route == "search" and { "parent", "child" } or { "back", "child" })
            H.equal(f.view._rows[#f.view._rows]._list_y, route == "normal" and -90 or -90)
            H.equal(f.view._max_scroll, 0)
        end)
    end
    return { fixture = fixture, read = read }
end
