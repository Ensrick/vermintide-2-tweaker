-- Official GUI definitions promotion: execute the complete installed parent and
-- real row/tooltip owners under private graphics-free native collaborators.
return function(H, repo_root)
    local root = repo_root .. "/gui_tweaker/"
    local prefix = "scripts/mods/gui_tweaker/"

    local function installed(options)
        options = options or {}
        local loads, bindings, factories, constructions = {}, {}, {}, {}
        local native = {
            scenegraph_definition = {
                background = { size = { 1400, 900 } },
                list_mask = { size = { 1400, 760 }, position = { 0, 0, 0 } },
            },
            background_widget_definitions = {},
        }
        local private_math = {}
        for key, value in pairs(math) do private_math[key] = value end
        private_math.clamp = function(value, low, high)
            return math.max(low, math.min(high, value))
        end
        local env = setmetatable({
            math = private_math,
            UIWidget = { init = function(widget) return widget end },
            UIWidgets = {},
            Colors = { get_color_table_with_alpha = function(name, alpha)
                if name == "font_button_normal" then return { alpha, 160, 146, 101 } end
                return { alpha, 255, 255, 255 }
            end },
            Localize = function(key)
                return ({ menu_settings_on = "ON", menu_settings_off = "OFF" })[key]
                    or "<" .. key .. ">"
            end,
            local_require = function(path)
                assert(path == "scripts/ui/views/options_view_definitions")
                return native
            end,
            RESOLUTION_LOOKUP = { res_h = 1080, inv_scale = 1 },
            UIFontByResolution = function(style) return { "native_font" }, style.font_size end,
            UIGetFontHeight = function() return 0, 0, 20 end,
            UIRenderer = {
                word_wrap = function() return { "one line" } end,
                text_size = function(_, text) return #text * 10, 20, { x = 2 } end,
            },
        }, { __index = _G })
        local mod = {}
        env.get_mod = function(id) assert(id == "gut"); return mod end
        local function load_module(path)
            local chunk = assert(loadfile(root .. path .. ".lua"))
            setfenv(chunk, env)
            return chunk()
        end
        function mod:dofile(path)
            loads[path] = (loads[path] or 0) + 1
            local owner = load_module(path)
            local name = path:match("([^/]+)$")
            if type(owner.new) == "function" then
                local create = owner.new
                owner.new = function(collaborators)
                    constructions[name] = (constructions[name] or 0) + 1
                    bindings[name] = collaborators
                    if options.break_owner == name then
                        collaborators[options.break_binding] = nil
                    end
                    local factory = create(collaborators)
                    factories[name] = factory
                    if options.drop_owner == name then factory[options.drop_export] = nil end
                    return factory
                end
            end
            return owner
        end
        return load_module(prefix .. "_mod_tweaker_definitions"), {
            env = env, native = native, loads = loads, bindings = bindings,
            factories = factories, constructions = constructions,
        }
    end

    local function pass(widget, style_id)
        for _, candidate in ipairs(widget.element.passes) do
            if candidate.style_id == style_id then return candidate end
        end
        error("missing pass " .. style_id)
    end

    local function assert_exports(defs, fixture)
        local dialogue = fixture.factories._mod_tweaker_dialogue_rows
        local tooltip = fixture.factories._mod_tweaker_tooltip
        local boolean = fixture.factories._mod_tweaker_boolean_rows
        for _, item in ipairs({
            { defs.create_dialogue_row, dialogue.create_dialogue_row },
            { defs.create_tooltip_popup, tooltip.create_tooltip_popup },
            { defs.layout_tooltip, tooltip.layout_tooltip },
            { defs.create_checkbox, boolean.create_checkbox },
            { defs.create_radio, boolean.create_radio },
        }) do
            assert(type(item[1]) == "function", "installed factory export is disconnected")
            assert(item[1] == item[2], "parent does not export its actual factory")
        end
    end

    H.test("public definitions installs real row and tooltip factories once", function()
        local defs, fixture = installed()
        assert_exports(defs, fixture)
        for _, name in ipairs({
            "_mod_tweaker_numeric_editor", "_mod_tweaker_boolean_rows",
            "_mod_tweaker_dialogue_rows", "_mod_tweaker_tooltip",
        }) do
            H.equal(fixture.loads[prefix .. name], 1, name .. " must load exactly once")
            if name ~= "_mod_tweaker_numeric_editor" then
                H.equal(fixture.constructions[name], 1, name .. " must bind exactly once")
            end
        end
        local dialogue = fixture.bindings._mod_tweaker_dialogue_rows
        H.equal(dialogue.row_w, 1300)
        H.equal(dialogue.indent_per_depth, 24)
        H.equal(dialogue.label_base_x, 12)
        H.equal(dialogue.list_sg, defs.list_sg)
        H.equal(type(dialogue.text_style), "function")
        H.equal(type(dialogue.append_separator), "function")
        local tooltip = fixture.bindings._mod_tweaker_tooltip
        H.equal(tooltip.row_h, 32)
        for _, name in ipairs({ "font_by_resolution", "word_wrap", "font_height", "get_resolution_lookup" }) do
            H.equal(type(tooltip[name]), "function", "missing native tooltip collaborator " .. name)
        end
    end)

    H.test("public definitions retains BooleanRows caret and native search geometry", function()
        local defs, fixture = installed()
        local offset = { 0, 100, 0 }
        local checkbox = defs.create_checkbox("Boolean", offset, 2)
        H.equal(offset[2], 68)
        H.deep_equal(checkbox.style.hotspot.size, { 1300, 32 })
        H.equal(checkbox.style.label.offset[1], 60)
        H.equal(checkbox.content.on_text, "ON")
        H.equal(checkbox.content.off_text, "OFF")
        H.equal(checkbox.style.label.font_type, "hell_shark")
        local radio = defs.create_radio("Radio", offset, 1)
        H.equal(offset[2], 36)
        H.equal(radio.style.hotspot.size[2], 32)
        H.equal(pass(radio, "radio_fill").content_check_function(radio.content), false)
        radio.content.selected = true
        H.equal(pass(radio, "radio_fill").content_check_function(radio.content), true)
        local style = { offset = { 100, 0, 0 }, font_type = "hell_shark", font_size = 16 }
        H.equal(defs.numeric_caret_x({}, style, "1234", 50, 2), 123)
        H.equal(defs.numeric_caret_index({}, style, "1234", 50, 123), 2)
        H.equal(defs.scenegraph_definition.list_mask.size[2], 716)
        H.equal(defs.scenegraph_definition.list_mask.position[2], -22)
        H.equal(fixture.native.scenegraph_definition.list_mask.size[2], 760,
            "the borrowed native scenegraph must remain independent")
        local search = defs.create_search_box()
        H.deep_equal(search.style.hotspot.size, { 1300, 30 })
        H.deep_equal(search.style.search_icon.texture_size, { 95, 95 })
        H.deep_equal(search.style.search_icon.offset, { -28, -3, 3 })
        H.equal(search.style.text.offset[1], 47)
    end)

    H.test("public Dialogue factory uses caller height and separate state media hotspots", function()
        local defs = installed()
        local offset = { 0, 100, 0 }
        local row = defs.create_dialogue_row("event", "DEFAULT", offset, 2, "many\n words", 64)
        H.equal(offset[2], 36)
        H.equal(row.scenegraph_id, defs.list_sg)
        H.deep_equal(row.style.row_hs.size, { 1300, 64 })
        H.deep_equal(row.style.row_hs.offset, { 0, 36, 0 })
        H.equal(row.style.label.offset[1], 60)
        H.equal(row.style.state_hotspot.offset[1], 1146)
        H.equal(row.style.media_hotspot.offset[1], 1258)
        H.equal(row.style.state_hotspot.offset[2], 55)
        H.deep_equal(row.style.state_hotspot.size, { 104, 26 })
        H.deep_equal(row.style.media_hotspot.size, { 32, 26 })
        H.equal(row.style.separator.offset[2], 36)
        H.equal(row.content.transcript, "many words")
        H.equal(row.content.has_transcript, true)
        H.truthy(row.content.state_hotspot ~= row.content.media_hotspot)
        H.truthy(row.content.row_hs ~= row.content.state_hotspot)
        H.equal(pass(row, "play_glyph").content_check_function(row.content), true)
        H.equal(pass(row, "pause_bar_left").content_check_function(row.content), false)
        row.content.media_is_playing = true
        H.equal(pass(row, "play_glyph").content_check_function(row.content), false)
        H.equal(pass(row, "pause_bar_left").content_check_function(row.content), true)
        H.equal(pass(row, "pause_bar_right").content_check_function(row.content), true)
    end)

    H.test("public Dialogue transcript and progress passes stay bounded and gated", function()
        local defs = installed()
        local row = defs.create_dialogue_row("event", nil, { 0, 0, 0 }, 0,
            string.rep("spoken words ", 200))
        H.equal(row.style.row_hs.size[2], 48, "standalone fallback height must remain 48")
        H.equal(row.content.state_text, "DEFAULT")
        H.truthy(#row.content.transcript <= math.floor(row.style.label.size[1] / 6.5))
        H.equal(row.content.transcript:sub(-3), "...")
        H.equal(pass(row, "progress_track").content_check_function(row.content), false)
        H.equal(pass(row, "progress_fill").content_check_function(row.content), false)
        row.content.progress_visible = true
        H.equal(pass(row, "progress_track").content_check_function(row.content), true)
        H.equal(pass(row, "progress_fill").content_check_function(row.content), true)
        H.equal(row.style._dialogue_progress_width, row.style.label.size[1])
        H.equal(row.style.progress_fill.size[1], 0)
        local empty = defs.create_dialogue_row("event", "MUTE", { 0, 0, 0 }, 0, "", 48)
        H.equal(empty.content.has_transcript, false)
        H.equal(pass(empty, "transcript").content_check_function(empty.content), false)
        H.equal(empty.content.transcript, "")
    end)

    H.test("public tooltip preserves native default and prefer-below edge flips", function()
        local defs, fixture = installed()
        local widget = defs.create_tooltip_popup()
        local function layout(world_y, prefer_below, alpha)
            defs.layout_tooltip(widget, { gui = {} }, "Title", "Description", -100,
                world_y, alpha or 0.5, prefer_below)
            return widget.style.panel.offset[2]
        end
        H.equal(layout(500), -68, "ordinary native tooltip sits above its row")
        H.equal(widget.style.panel.size[2], 70)
        H.equal(layout(500, true), -170, "Dialogue tooltip prefers directly below")
        H.equal(layout(1000), -170, "ordinary tooltip flips at top edge")
        H.equal(layout(60, true), -68, "preferred-below flips at bottom edge")
        H.equal(layout(78, true), -170, "exact screen margin stays below")
        H.equal(widget.content.frame, "menu_frame_12")
        H.equal(widget.style.title.font_type, "hell_shark")
        H.equal(widget.style.desc.font_type, "hell_shark")
        H.equal(widget.style.title.upper_case, nil, "tooltip prose must not inherit row caps")
        for _, color in ipairs({ widget.style.panel.color, widget.style.frame.color,
            widget.style.title.text_color, widget.style.desc.text_color }) do H.equal(color[1], 128) end
        layout(500, true, -1)
        H.equal(widget.style.frame.color[1], 0)
        layout(500, true, 2)
        H.equal(widget.style.frame.color[1], 255)
        fixture.env.RESOLUTION_LOOKUP = { res_h = 600, inv_scale = 1 }
        H.equal(layout(550), -170, "screen resolution must be read after construction")
        H.deep_equal(widget.style.frame.area_size, widget.style.panel.size)
        H.equal(widget.style.frame.offset[2], widget.style.panel.offset[2])
    end)

    H.test("public tooltip retains one-line measurement fallback", function()
        local defs, fixture = installed()
        fixture.env.UIRenderer.word_wrap = function() error("measurement unavailable") end
        local widget = defs.create_tooltip_popup()
        defs.layout_tooltip(widget, { gui = {} }, "Title", "Description", -100, 500, 1, true)
        H.equal(widget.style.panel.size[2], 84)
        H.equal(widget.style.panel.offset[2], -184)
        H.equal(widget.content.title, "Title")
        H.equal(widget.content.desc, "Description")
    end)

    H.test("public installed gear accent preserves disabled and ordinary rows", function()
        local defs = installed()
        local parent = { style = { label = { text_color = { 255, 255, 255, 255 } } } }
        H.equal(defs.apply_gear_parent_accent(parent, true), true)
        H.deep_equal(parent.style.label.text_color, { 255, 160, 146, 101 })
        H.equal(parent._advanced_parent_accent, true)
        local disabled = { _disabled_in_vmf = true,
            style = { label = { text_color = { 255, 128, 128, 128 } } } }
        H.equal(defs.apply_gear_parent_accent(disabled, true), false)
        H.deep_equal(disabled.style.label.text_color, { 255, 128, 128, 128 })
        H.equal(disabled._advanced_parent_accent, true)
        local child = { style = { label = { text_color = { 255, 255, 255, 255 } } } }
        H.equal(defs.apply_gear_parent_accent(child, false), false)
        H.equal(child._advanced_parent_accent, nil)
        H.deep_equal(child.style.label.text_color, { 255, 255, 255, 255 })
        H.equal(defs.apply_gear_parent_accent(nil, true), false)
    end)

    H.test("public whole-parent factory contract rejects planted missing bindings", function()
        for _, damaged in ipairs({
            { owner = "_mod_tweaker_dialogue_rows", binding = "append_separator" },
            { owner = "_mod_tweaker_tooltip", binding = "get_resolution_lookup" },
        }) do
            local ok = pcall(installed, { break_owner = damaged.owner, break_binding = damaged.binding })
            H.equal(ok, false, "missing " .. damaged.binding .. " must fail real factory construction")
        end
        for _, damaged in ipairs({
            { owner = "_mod_tweaker_dialogue_rows", export = "create_dialogue_row" },
            { owner = "_mod_tweaker_tooltip", export = "layout_tooltip" },
            { owner = "_mod_tweaker_boolean_rows", export = "create_checkbox" },
        }) do
            local defs, fixture = installed({ drop_owner = damaged.owner, drop_export = damaged.export })
            H.equal(pcall(assert_exports, defs, fixture), false,
                "actual-parent export check must detect a disconnected " .. damaged.export)
        end
        local defs, fixture = installed()
        H.equal(pcall(assert_exports, defs, fixture), true, "healthy complete installation control")
    end)
end
