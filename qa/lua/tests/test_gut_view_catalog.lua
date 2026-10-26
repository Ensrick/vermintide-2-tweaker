-- #2: complete catalog owner through the actual standalone parent binding.
-- VMF inputs are ordinary private tables; renderer/row sinks are not simulated.
return function(H, repo_root, source_override)
    local root = "gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"
    local view_path, child_path = root .. "_mod_tweaker_view.lua", root .. "_mod_tweaker_view_catalog.lua"
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
    local function list(id, label, ...)
        return { { mod_name = id, readable_mod_name = label or id }, ... }
    end
    local function node(id, kind, depth)
        return { setting_id = id, type = kind or "checkbox", depth = depth or 1 }
    end
    local function category(cats, id)
        for _, value in ipairs(cats) do if value.mod_id == id then return value end end
    end
    local function ids(nodes)
        local out = {}; for _, value in ipairs(nodes) do out[#out + 1] = value.setting_id or value.mod_name end
        return out
    end
    local function fixture(options)
        options = options or {}
        local loads, calls, logs, debug_rows, trace = {}, {}, {}, {}, {}
        local math_copy = {}; for key, value in pairs(math) do math_copy[key] = value end
        math_copy.clamp = function(value, low, high) return math.max(low, math.min(high, value)) end
        local env = setmetatable({ math = math_copy }, { __index = _G }); env._G = env
        local mod = { mod_tweaker = {} }
        function mod:debug(...) debug_rows[#debug_rows + 1] = pack(...) end
        function mod:localize(key)
            if options.localize_error then error(options.localize_error, 0) end
            return "<" .. key .. ">"
        end
        function mod.mod_tweaker:list_categories() return options.controller or {} end
        local mods = options.mods or {}
        local vmf = options.vmf
        env.get_mod = function(id)
            calls[#calls + 1] = id
            if id == "gut_dev" then return mod end
            if id == "VMF" then return vmf end
            if id == "Crosshair Kill Confirmation" then trace[#trace + 1] = "ckc" end
            if id == "HideBuffs" then trace[#trace + 1] = "hb" end
            return mods[id]
        end
        env.printf = function(...) logs[#logs + 1] = pack(...) end
        env.class = function(value) value = value or {}; value.__index = value; return value end
        local pure = { _mod_tweaker_view_rows = true, _mod_tweaker_disabled_sections = true,
            _mod_tweaker_external_group = true }
        local bound, bind_count, selected_input
        local function load_source(path)
            local chunk = assert(loadstring(read(path), "@" .. path)); setfenv(chunk, env); return chunk()
        end
        function mod:dofile(path)
            local name = assert(path:match("([^/]+)$")); loads[name] = (loads[name] or 0) + 1
            if name == "_mod_tweaker_view_catalog" then
                local owner = load_source(child_path)
                local bind = owner.bind
                owner.bind = function(deps)
                    bind_count = (bind_count or 0) + 1
                    H.equal(deps.mod, mod); H.equal(deps.math, math_copy)
                    H.equal(deps.printf, env.printf); H.equal(type(deps.get_mod), "function")
                    bound = bind(deps)
                    return bound
                end
                return owner
            end
            if pure[name] then
                local value = load_source(root .. name .. ".lua")
                if name == "_mod_tweaker_disabled_sections" then
                    local select_members = value.select_equipment_members
                    value.select_equipment_members = function(cats)
                        trace[#trace + 1] = "equipment"; selected_input = cats
                        return select_members(cats)
                    end
                end
                return value
            end
            if name == "_mod_tweaker_definitions" then return {
                create_tab = function(label, index) return { content = { text = label, index = index } } end,
            } end
            if name == "_mod_tweaker_tab_labels" then return { exact = function() end } end
            if name == "_mod_tweaker_sound" then return { new_probe = function() return {} end, play = function() end } end
            return { install = function() end }
        end
        local Class = load_source(view_path)
        H.equal(loads._mod_tweaker_view_catalog, 1, "actual parent must load the complete child once")
        H.equal(bind_count, 1, "actual parent must bind once")
        H.equal(type(bound), "function")
        H.deep_equal(calls, { "gut_dev" }, "binding must not read live VMF or integrated mods")
        local view = setmetatable({ _rows = {} }, Class)
        function view:_layout_tabs() end -- presentation sink; not catalog logic
        function view:_build_rows(value) self.built = value; self._rows = {} end
        return { build = bound, view = view, env = env, mod = mod, calls = calls,
            logs = logs, debug_rows = debug_rows, trace = trace, mods = mods,
            set_vmf = function(value) vmf = value end,
            selected_input = function() return selected_input end }
    end
    H.test("GUT catalog has one deferred hook-neutral owner and actual parent pcall", function()
        local parent, child = read(view_path), read(child_path)
        H.equal(count(parent, 'mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_view_catalog")'), 1)
        H.equal(count(parent, "local function _vmf_categories"), 0)
        H.equal(count(parent, "local function _synthesize_equipment"), 0)
        H.truthy(parent:find("pcall(_vmf_categories)", 1, true))
        for _, forbidden in ipairs({ "mod:dofile(", "mod:hook", "mod:command", "function mod.update", "function mod.on_" }) do
            H.equal(count(child, forbidden), 0, forbidden)
        end
        local f = fixture(); local result = pack(f.build())
        H.equal(result.n, 1); H.deep_equal(result[1], {})
    end)
    H.test("GUT catalog absent or malformed VMF data returns one empty array", function()
        for _, vmf in ipairs({ {}, { options_widgets_data = false }, { options_widgets_data = {} } }) do
            local f = fixture({ vmf = vmf }); local result = pack(f.build())
            H.equal(result.n, 1); H.deep_equal(result[1], {})
        end
    end)
    H.test("GUT catalog preserves authored discovery enabled sort and original lists", function()
        local gt, gut, mp = list("gt", "Zeta", node("g")), list("gut_dev", "Original", node("u")), list("mp", "Alpha", node("m"))
        local f = fixture({ vmf = { options_widgets_data = { gt, gut, mp, list("unrelated", "A") } }, mods = {
            gt = { is_enabled = function() return false end }, mp = { is_enabled = function() error("unknown") end },
        } })
        local cats = f.build()
        H.equal(#cats, 3); H.equal(cats[1].mod_id, "mp"); H.equal(cats[2].mod_id, "gut_dev"); H.equal(cats[3].mod_id, "gt")
        H.equal(cats[2].label, "Interface"); H.equal(cats[3].enabled, false)
        H.equal(cats[1].widgets, mp); H.equal(cats[2].widgets, gut); H.equal(cats[3].widgets, gt)
    end)
    H.test("GUT catalog zero and one Equipment branches retain category array identity", function()
        for _, input in ipairs({ list("gut_dev", "GUI", node("u")), list("character_weapon_variants", "CWV", node("c")) }) do
            local f = fixture({ vmf = { options_widgets_data = { input } } })
            local result = f.build(); H.equal(result, f.selected_input()); H.equal(result[1].widgets, input)
            if input[1].mod_name == "character_weapon_variants" then H.equal(result[1].label, "Weapons") end
        end
    end)
    H.test("GUT catalog Equipment retains authored depths ownership and disabled headers", function()
        local cosmetic = node("paint", "checkbox", 4)
        local weapon = node("unlock", "checkbox", 2)
        local hidden = node("cwv", "checkbox", 1)
        local cos_obj, wt_obj = {}, {}
        local f = fixture({ vmf = { options_widgets_data = {
            list("cosmetics_tweaker", "Cos", cosmetic), list("wt_dev", "WT", weapon),
            list("character_weapon_variants", "CWV", hidden),
        } }, mods = { cosmetics_tweaker = cos_obj, wt_dev = wt_obj,
            character_weapon_variants = { is_enabled = function() return false end } } })
        local cat = assert(category(f.build(), "gut_equipment"))
        H.deep_equal(ids(cat.widgets), { "__equip_cosmetics", "paint", "__equip_weapons", "unlock", "__equip_cwv" })
        H.deep_equal(cat._depths, { 0, 1, 0, 1, 1 })
        H.equal(cat.widgets[2], cosmetic); H.equal(cat.widgets[4], weapon)
        H.equal(cat.widgets[5].disabled, true); H.equal(cat.widgets[5].tooltip, "Disabled in VMF")
        H.deep_equal(cat._owner_mod_ids, { "cosmetics_tweaker", "wt_dev" })
        H.equal(cat._owners.paint.mod_obj, cos_obj); H.equal(cat._owners.unlock.mod_obj, wt_obj)
        H.equal(cat._owners.cwv, nil)
    end)
    H.test("GUT catalog enabled stream aliases win without copying the shared allowlist", function()
        local active = node("dev", "checkbox", 6)
        local f = fixture({ vmf = { options_widgets_data = {
            list("cim", "CIM", node("old")), list("cim_dev", "CIM Dev", active),
            list("wt_dev", "WT Dev", node("weapons")), list("verminious_dreams_lighting", "Not a tab"),
        } }, mods = { cim = { is_enabled = function() return false end }, cim_dev = {} } })
        local cats = f.build(); H.equal(#cats, 2)
        H.equal(cats[1].mod_id, "gut_equipment")
        H.equal(cats[2].mod_id, "cim"); H.equal(cats[2].enabled, false,
            "unselected disabled alias retains its existing standalone category")
        H.deep_equal(ids(cats[1].widgets), { "__equip_crafting", "dev", "__equip_weapons", "weapons" })
        H.equal(cats[1].widgets[2], active); H.deep_equal(cats[1]._owner_mod_ids, { "cim_dev", "wt_dev" })
    end)
    local function integrated(options)
        options = options or {}
        local gut = list("gut_dev", "GUI", node("gut_hide_hud_ui_group", "group", 1),
            node("hb_group", "group", 2), node("legacy", "checkbox", 3),
            node("gut_uitweaks_integration_group", "group", 3), node("sync", "checkbox", 4),
            node("outside", "checkbox", 1))
        local ckc_node, hb_node = node("kill", "checkbox", 5), node("live", "checkbox", 6)
        local wd = { gut, list("Crosshair Kill Confirmation", "CKC", ckc_node) }
        if not options.missing_live then wd[#wd + 1] = list("HideBuffs", "HB", hb_node) end
        local hb = { SETTING_NAMES = { legacy = "legacy" } }
        if options.disabled then hb.is_enabled = function() return false end end
        local f = fixture({ vmf = { options_widgets_data = wd }, mods = {
            ["Crosshair Kill Confirmation"] = {}, HideBuffs = hb,
        } })
        return f, gut, ckc_node, hb_node
    end
    H.test("GUT catalog CKC then live HB fold retains all mixed owner buffers", function()
        local f, gut, ckc_node, hb_node = integrated()
        local cats = f.build(); H.equal(#cats, 1)
        local cat = cats[1]
        H.deep_equal(f.trace, { "ckc", "hb", "equipment" })
        H.deep_equal(ids(cat.widgets), { "gut_dev", "gut_hide_hud_ui_group", "gut_ckc_group", "kill", "hb_group", "live", "gut_uitweaks_integration_group", "sync", "outside" })
        H.deep_equal(cat._owner_mod_ids, { "gut_dev", "Crosshair Kill Confirmation", "HideBuffs" })
        H.equal(cat._profile_excluded_owners.HideBuffs, true)
        H.equal(cat._owners.kill.mod_obj, f.mods["Crosshair Kill Confirmation"])
        H.equal(cat._owners.live.mod_obj, f.mods.HideBuffs)
        H.equal(cat._owners.sync, nil); H.equal(cat.mod_obj, f.mod)
        H.equal(cat.widgets[4].depth, 3); H.equal(cat.widgets[6].depth, 3)
        H.truthy(cat.widgets[4] ~= ckc_node); H.truthy(cat.widgets[6] ~= hb_node)
        H.equal(ckc_node.depth, 5); H.equal(hb_node.depth, 6)
        H.deep_equal(ids(gut), { "gut_dev", "gut_hide_hud_ui_group", "hb_group", "legacy", "gut_uitweaks_integration_group", "sync", "outside" })
    end)
    H.test("GUT catalog disabled HB retains explained header and never owns its children", function()
        local f = integrated({ disabled = true }); local cat = f.build()[1]
        H.deep_equal(ids(cat.widgets), { "gut_dev", "gut_hide_hud_ui_group", "gut_ckc_group", "kill", "hb_group", "outside" })
        H.equal(cat.widgets[5].disabled, true); H.equal(cat.widgets[5].tooltip, "Disabled in VMF")
        H.equal(cat._owners.live, nil); H.deep_equal(cat._owner_mod_ids, { "gut_dev", "Crosshair Kill Confirmation" })
    end)
    H.test("GUT catalog missing live HB uses the existing fallback and one diagnostic", function()
        local f = integrated({ missing_live = true })
        for _ = 1, 2 do
            local cat = f.build()[1]
            H.equal(cat._owners.legacy.mod_obj, f.mods.HideBuffs)
            H.equal(cat._profile_excluded_owners.HideBuffs, true)
            H.deep_equal(cat._owner_mod_ids, { "gut_dev", "Crosshair Kill Confirmation", "HideBuffs" })
        end
        H.equal(#f.logs, 1); H.equal(#f.debug_rows, 3, "VMF registry probe remains once per live registry")
        H.equal(f.logs[1][1], "[gut:312] live UI Tweaks tree unavailable reason=%s; keeping authored fallback")
        H.equal(f.logs[1][2], "live_list_missing")
    end)
    H.test("GUT catalog absent HB retains authored fallback identity without private ownership", function()
        local gut = list("gut_dev", "GUI", node("hb_group", "group", 1), node("legacy", "checkbox", 2))
        local f = fixture({ vmf = { options_widgets_data = { gut } } }); local cat = f.build()[1]
        H.equal(cat.widgets, gut); H.equal(cat._owners, nil); H.equal(cat._profile_excluded_owners, nil)
    end)
    H.test("GUT catalog reobserves live registry and get_mod without rebinding", function()
        local f = fixture({ vmf = { options_widgets_data = { list("gt", "First", node("one")) } } })
        H.equal(f.build()[1].label, "First")
        f.set_vmf({ options_widgets_data = { list("mp", "Second", node("two")) } })
        H.equal(f.build()[1].label, "Second")
        f.env.get_mod = function(id) if id == "VMF" then return nil end end
        H.deep_equal(f.build(), {}, "actual parent must inject call-time global lookup")
    end)
    H.test("GUT catalog localization failure keeps existing literal Equipment fallback", function()
        local token = {}
        local f = fixture({ localize_error = token, vmf = { options_widgets_data = {
            list("wt", "WT", node("w")), list("character_weapon_variants", "CWV", node("c")),
        } } })
        local cat = f.build()[1]; H.equal(cat.label, "Equipment")
        H.deep_equal(ids(cat.widgets), { "__equip_weapons", "w", "__equip_cwv", "c" })
    end)
    H.test("GUT catalog discovery errors retain identity and actual rebuild controller fallback", function()
        local token, controller = {}, { mod_id = "controller", label = "Fallback", widgets = {} }
        local f = fixture({ controller = { controller } })
        f.env.get_mod = function(id) if id == "VMF" then error(token, 0) end end
        local result = pack(pcall(f.build)); H.equal(result[1], false); H.equal(result[2], token)
        f.view:_rebuild()
        H.equal(f.view._all_categories[1], controller); H.equal(f.view.built, controller)
    end)
end
