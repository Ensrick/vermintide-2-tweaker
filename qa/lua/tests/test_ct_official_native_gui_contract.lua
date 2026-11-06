-- Native-source-qualified CT UI contract. No proprietary checkout is required.
-- Production loads are actual official files, never a rewritten Dev subject.
return function(H, repo_root)
    repo_root = repo_root:gsub("\\", "/"):gsub("/$", "")
    local evidence = os.getenv("VT2_CT_NATIVE_GUI_EVIDENCE_ROOT")
    if evidence then
        evidence = evidence:gsub("\\", "/"):gsub("/$", "")
        assert(evidence == repo_root .. "/.temp/public-promotion-20261105/native-resource-evidence",
            "unowned native-Gui QA overlay")
    else
        evidence = repo_root
    end
    local production = os.getenv("VT2_CT_OFFICIAL_OVERLAY_ROOT")
    if production then
        production = production:gsub("\\", "/"):gsub("/$", "")
        assert(production == repo_root .. "/.temp/public-promotion-20261105/overlays/ct",
            "unowned official CT overlay")
    else
        production = repo_root
    end
    local Native = assert(loadfile(evidence
        .. "/qa/lua/tests/fixtures/ct_native_gui_contract_6_13.lua"))()
    local PREFIX = "chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/"
    local function copy(value)
        if type(value) ~= "table" then return value end
        local result = {}
        for key, child in pairs(value) do result[key] = copy(child) end
        return result
    end
    local function pack(...) return { n = select("#", ...), ... } end
    local function execute(code, env, label)
        local chunk = assert(loadstring(code, "@ct-native-fixture:" .. label))
        setfenv(chunk, env)
        return chunk()
    end
    local function actual(name, env)
        assert(name:match("^[%w_]+$"), "unsafe production name")
        local path = production .. "/" .. PREFIX .. name .. ".lua"
        local chunk = assert(loadfile(path))
        setfenv(chunk, env)
        return chunk(), path
    end

    local EXPECTED = {
        ct_bomb_cooldown_display_concentration = "deus_icon_supportbomb_concentration_01",
        ct_bomb_cooldown_display_crit = "deus_icon_supportbomb_crit_01",
        ct_bomb_cooldown_display_healing = "deus_icon_supportbomb_healing_01",
        ct_bomb_cooldown_display_speed = "deus_icon_supportbomb_speed_01",
        ct_manann_cooldown_display_boon = "deus_icon_trait_crit_chain_lightning",
        ct_manann_cooldown_display_trait = "deus_icon_trait_crit_chain_lightning",
        ct_manann_ready_display_boon = "deus_icon_trait_crit_chain_lightning",
        ct_manann_ready_display_trait = "deus_icon_trait_crit_chain_lightning",
    }
    local function validate_templates(registry)
        local count = 0
        for name, row in pairs(registry) do
            local expected = EXPECTED[name]
            local template = type(row) == "table" and row.buffs and row.buffs[1]
            if not expected or type(template) ~= "table" or template.name ~= name
                    or template.icon ~= expected or not Native.atlases[template.icon]
                    or template.icon:find("_glow", 1, true) then
                return false, "unexpected local template/icon: " .. tostring(name)
            end
            if name:find("_ready_display_", 1, true) then
                if template.is_cooldown or template.duration ~= nil then
                    return false, "ready is not the native infinite non-cooldown form"
                end
            elseif template.is_cooldown ~= true or type(template.duration) ~= "number"
                    or template.duration <= 0 or template.duration == math.huge then
                return false, "cooldown must retain a finite native presentation"
            end
            count = count + 1
        end
        return count == 8, "local template census=" .. tostring(count)
    end

    local function fixture(context)
        context = context or {}
        local env = setmetatable({}, { __index = _G })
        env._G = env
        env.DLCSettings = { belakor = {} }
        env.IS_WINDOWS, env.AreaSettings, env.CareerSettings = true, {}, {}
        env.RESOLUTION_LOOKUP = { scale = 1 }
        env.script_data = {}
        env.printf = function() end
        env.Vector2 = function(x, y) return { x, y } end
        env.Vector3 = function(x, y, z) return { x, y, z } end
        env.Color = function(a, b, c, d) return { a, b, c, d } end
        execute(Native.code.belakor_settings, env, "Belakor all-context materials")
        local created, bitmap, hooks, channels = {}, {}, {}, {}
        env.World = { create_screen_gui = function(world, ...)
            local args = pack(...)
            local gui = { world = world, args = args,
                kind = args[1] == "immediate" and "immediate" or "retained" }
            created[#created + 1] = gui
            return gui
        end }
        env.UIRenderer = { create_ui_renderer = function(world, gui, gui_retained)
            return { world = world, gui = gui, gui_retained = gui_retained,
                render_settings = { snap_pixel_positions = false } }
        end }
        execute(Native.code.renderer_create, env, "UIRenderer.create")
        local factory = execute("return " .. Native.code.renderer_factory,
            env, "IngameUI native renderer factory")
        local is_in_inn = context.inn == true
        local mechanism = context.mechanism or "deus"
        local renderer = factory("level_world", false, is_in_inn, mechanism)
        local top = factory("top_ingame_view", false, is_in_inn, mechanism)
        local function bitmap_call(gui, material)
            bitmap[#bitmap + 1] = { gui = gui, material = material }
            return #bitmap
        end
        env.Gui_bitmap_uv, env.Gui_bitmap = bitmap_call, bitmap_call
        env.Gui_update_bitmap_uv, env.Gui_update_bitmap = bitmap_call, bitmap_call
        env.UIAtlasHelper = {
            has_atlas_settings_by_texture_name = function(icon)
                return Native.atlases[icon] ~= nil
            end,
            get_atlas_settings_by_texture_name = function(icon)
                return copy(assert(Native.atlases[icon], "non-native icon " .. tostring(icon)))
            end,
        }
        execute(Native.code.bitmap, env, "native atlas bitmap routing")
        execute(Native.code.draw_texture, env, "native immediate/retained selection")
        local mod = {}
        function mod:get() return true end
        function mod:localize(key) return key end
        function mod:hook(class, method, callback)
            local key = tostring(class) .. "." .. method
            assert(not hooks[key], "duplicate production hook " .. key)
            hooks[key] = callback
        end
        mod.hook_safe = mod.hook
        function mod:network_register(name, callback)
            assert(not channels[name], "duplicate display channel")
            channels[name] = callback
        end
        function mod:dofile(path)
            assert(path == "scripts/mods/chaos_wastes_tweaker/_ct_tab_collectibles_layout",
                "unexpected production dependency")
            return actual("_ct_tab_collectibles_layout", env)
        end
        env.get_mod = function(id) assert(id == "ct"); return mod end
        env.BuffTemplates = {}
        env.NetworkLookup = { buff_templates = { [1] = "native", native = 1 } }
        env.UIWidget = { init = function(definition) return definition end }
        env.Colors = { get_table = function() return { 255, 255, 255, 255 } end }
        local controller = {
            get_own_peer_id = function() return "local" end,
            get_cursed_chests_purified = function() return 2 end,
            get_player_soft_currency = function() return 17.8 end,
        }
        env.Managers = { mechanism = { game_mechanism = function()
            if context.adventure then return {} end
            return { get_deus_run_controller = function() return controller end }
        end } }
        actual("_ct_official_collectibles", env)
        local pane = mod._ct_build_deus_collectibles()
        assert(#pane.rows == 2, "unexpected collectible count")
        local rows = {}
        for _, row in ipairs(pane.rows) do rows[row.key] = row end
        assert(rows.chests.widget.content.icon == "deus_icons_boon")
        assert(rows.coins.widget.content.icon == "deus_icons_coin")
        local display = actual("_ct_bomb_cooldown_display", env)
        assert(display.install(2), "actual display installer failed")
        assert(validate_templates(env.BuffTemplates))
        return { env = env, mod = mod, renderer = renderer, top = top,
            created = created, bitmap = bitmap, rows = rows, pane = pane,
            hooks = hooks, channels = channels, display = display }
    end

    local function route(f, renderer, icon, masked, saturated, retained,
            expected_gui, expected_material)
        f.env.UIRenderer.draw_texture(renderer, icon, { 0, 0, 0 }, { 80, 80, 0 },
            nil, masked, saturated, retained)
        local call = f.bitmap[#f.bitmap]
        H.equal(call.gui, expected_gui, "wrong immediate/retained native Gui")
        H.equal(call.material, expected_material, "wrong native atlas variant")
    end

    -- Twenty independent routes. These read actual CT widgets/templates, while
    -- selection and expected native aliases come from the pinned native fixture.
    for _, key in ipairs({ "chests", "coins" }) do
        for _, style_id in ipairs({ "icon", "background_icon" }) do
            local row_key, style_key = key, style_id
            H.test("ct_public_collectibles_native_gui " .. row_key .. "/" .. style_key,
                function()
                    local f = fixture()
                    local widget = f.rows[row_key].widget
                    local style, matching = widget.style[style_key], nil
                    for _, pass in ipairs(widget.element.passes) do
                        if pass.pass_type == "texture" and pass.style_id == style_key then
                            assert(not matching); matching = pass
                        end
                    end
                    assert(matching and not matching.retained_mode)
                    assert(not style.masked and not style.saturated)
                    local icon = widget.content[matching.texture_id]
                    H.equal(Native.atlases[icon].material_name, "gui_icons_atlas")
                    route(f, f.top, icon, style.masked, style.saturated, nil,
                        f.top.gui, "gui_icons_atlas")
                    H.equal(#f.bitmap, 1)
                end)
        end
    end
    local names = {}
    for name in pairs(EXPECTED) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local template_name = name
        H.test("ct_public_cooldown_native_gui background " .. template_name, function()
            local f = fixture()
            local t = f.env.BuffTemplates[template_name].buffs[1]
            local atlas = Native.atlases[t.icon]
            route(f, f.renderer, t.icon, false, false, Native.buff_flags.retained_mode,
                f.renderer.gui_retained, atlas.material_name)
            H.equal(#f.bitmap, 1)
        end)
        if not name:find("_ready_display_", 1, true) then
            H.test("ct_public_cooldown_native_gui foreground " .. template_name, function()
                local f = fixture()
                local t = f.env.BuffTemplates[template_name].buffs[1]
                assert(t.is_cooldown == true)
                local atlas = Native.atlases[t.icon]
                route(f, f.renderer, t.icon, Native.buff_flags.foreground_masked,
                    t.is_cooldown, Native.buff_flags.retained_mode,
                    f.renderer.gui_retained, atlas.masked_saturated_material_name)
                H.equal(#f.bitmap, 1)
            end)
        end
    end
    for _, key in ipairs({ "base", "belakor" }) do
        local control_key = key
        H.test("CT native cooldown control " .. control_key, function()
            local f = fixture()
            local control = Native.controls[control_key]
            local atlas = Native.atlases[control.icon]
            assert(control.is_cooldown == true)
            route(f, f.renderer, control.icon, Native.buff_flags.foreground_masked,
                control.is_cooldown, Native.buff_flags.retained_mode,
                f.renderer.gui_retained, atlas.masked_saturated_material_name)
            H.equal(#f.bitmap, 1)
        end)
    end

    H.test("CT native fixture pins closed source assets and exact source bodies", function()
        H.equal(Native.source_commit, "93dea911a4cc464a0eb51cfdc3a443297bfc4550")
        H.equal(Native.source_game_version, "6.13.0")
        local n = 0
        for icon, row in pairs(Native.atlases) do
            n = n + 1
            assert(not icon:find("_glow", 1, true))
            assert(row.size and row.uv00 and row.uv11)
            assert(row.material_name == "gui_icons_atlas" or row.material_name == "gui_belakor_atlas")
            H.equal(row.masked_saturated_material_name, row.material_name .. "_masked_saturated")
        end
        H.equal(n, 9)
        assert(type(Native.sources) == "table" and next(Native.sources))
        for path, hash in pairs(Native.sources) do
            assert(path:sub(1, 8) == "scripts/" and #hash == 64 and hash:match("^[0-9a-f]+$"))
        end
        assert(#Native.segments >= 5 and #Native.lifecycle > 0)
        H.equal(Native.buff_flags.retained_mode, true)
        H.equal(Native.buff_flags.foreground_masked, true)
        -- These are native source contracts, not simulated live handle validity.
        -- In particular, the native component is destroyed before its renderer,
        -- and infinite ready templates do not take the cooldown foreground pass.
        local life = {}
        for _, row in ipairs(Native.lifecycle) do
            assert(not life[row.name] and Native.sources[row.file])
            assert(type(row.text) == "string" and row.first_line <= row.last_line)
            life[row.name] = row
        end
        local function contains(name, text)
            assert(life[name] and life[name].text:find(text, 1, true), name .. ": " .. text)
        end
        contains("ingame_renderer_creation", "self:create_ui_renderer(top_world")
        contains("ingame_context_renderer_binding", "ingame_ui_context.ui_renderer = self.ui_renderer")
        contains("ingame_context_renderer_binding", "ingame_ui_context.ui_top_renderer = self.ui_top_renderer")
        contains("player_list_renderer_binding", "self._ui_top_renderer = ingame_ui_context.ui_top_renderer")
        contains("buff_renderer_binding", "self._ui_renderer = ingame_ui_context.ui_renderer")
        contains("buff_retained_icon_passes", "return content.is_cooldown")
        contains("buff_icon_and_saturation", "widget_style.texture_icon.saturated = is_cooldown")
        contains("buff_destroy_and_hide_retained_elements", "self:set_visible(false)")
        contains("buff_destroy_and_hide_retained_elements", "UIRenderer.set_element_visible(ui_renderer, widget.element, visible)")
        contains("hud_component_teardown", "component:destroy()")
        contains("hud_before_renderer_teardown", "self.ingame_hud:destroy()")
        contains("renderer_teardown", "UIRenderer.destroy(self.ui_top_renderer, self.top_world)")
        H.equal(life.hud_before_renderer_teardown.file, life.renderer_teardown.file)
        assert(life.hud_before_renderer_teardown.last_line < life.renderer_teardown.first_line)
    end)
    H.test("CT exact native renderer materials persist across supported contexts", function()
        for _, context in ipairs({ { mechanism = "deus" }, { mechanism = "deus", inn = true },
                { mechanism = "adventure", adventure = true }, { mechanism = "weave", adventure = true } }) do
            local f = fixture(context)
            H.equal(#f.created, 4)
            for _, gui in ipairs(f.created) do
                local materials = {}
                for i = 1, gui.args.n - 1 do
                    if gui.args[i] == "material" then materials[gui.args[i + 1]] = true end
                end
                assert(materials["materials/ui/ui_1080p_hud_atlas_textures"])
                assert(materials["materials/ui/ui_1080p_menu_atlas_textures"])
                assert(materials["materials/ui/ui_1080p_belakor_atlas"])
            end
            H.equal(f.top.gui.world, "top_ingame_view")
            H.equal(f.renderer.gui_retained.world, "level_world")
        end
    end)
    H.test("CT production collectible callbacks retain native context and no glow passes", function()
        local f = fixture()
        local drawn, passes = {}, 0
        f.env.UIRenderer.begin_pass = function(renderer) H.equal(renderer, f.top); passes = passes + 1 end
        f.env.UIRenderer.end_pass = function(renderer) H.equal(renderer, f.top); passes = passes - 1 end
        f.env.UIRenderer.draw_widget = function(renderer, widget)
            H.equal(renderer, f.top); drawn[#drawn + 1] = widget
        end
        f.env.UIUtils = { get_text_width = function() return 120 end }
        local ui = { _ui_renderer = f.renderer, _ui_top_renderer = f.top,
            _ui_scenegraph = { loot_objective = { position = { 20, 0, 0 } },
                banner_right = { size = { 660, 1080 } } },
            _input_manager = { get_service = function() return {} end }, _render_settings = {} }
        local native = 0
        f.hooks["IngamePlayerListUI._setup_mission_data"](function() native = native + 1 end, ui, {})
        H.equal(native, 0)
        f.hooks["IngamePlayerListUI._draw"](ui, 0.1)
        H.equal(passes, 0); H.equal(#drawn, 2)
        H.equal(drawn[1].content.icon, "deus_icons_boon")
        H.equal(drawn[2].content.icon, "deus_icons_coin")
        for _, widget in ipairs(drawn) do
            for _, pass in ipairs(widget.element.passes) do
                assert(not tostring(pass.texture_id):find("glow", 1, true))
            end
        end
        ui._is_in_inn = true
        local result = pack(f.hooks["IngamePlayerListUI._setup_mission_data"](
            function() return "native", nil, "tail", nil end, ui, {}))
        H.equal(result.n, 4); H.equal(result[1], "native"); H.equal(result[3], "tail")
    end)
    H.test("CT local display templates do not add wire names or foreign resources", function()
        local f = fixture()
        H.truthy(validate_templates(f.env.BuffTemplates))
        H.deep_equal(f.env.NetworkLookup.buff_templates, { [1] = "native", native = 1 })
        local row = f.env.BuffTemplates.ct_bomb_cooldown_display_crit.buffs[1]
        local old = row.icon
        row.icon = old .. "_glow"
        H.equal(validate_templates(f.env.BuffTemplates), false,
            "the independent closed oracle accepted a synthesized glow")
        row.icon = old
        H.truthy(validate_templates(f.env.BuffTemplates))
    end)
    H.test("CT native route oracle distinguishes wrong Gui and wrong variant", function()
        local f = fixture()
        local icon = "deus_icon_trait_crit_chain_lightning"
        f.env.UIRenderer.draw_texture(f.renderer, icon, { 0, 0, 0 }, { 60, 60, 0 },
            nil, true, true, nil)
        local call = f.bitmap[1]
        H.equal(call.gui, f.renderer.gui)
        assert(call.gui ~= f.renderer.gui_retained, "fixture collapsed native Guis")
        f.env.UIRenderer.draw_texture(f.renderer, icon, { 0, 0, 0 }, { 60, 60, 0 },
            nil, false, false, true)
        H.equal(f.bitmap[2].material, "gui_belakor_atlas")
        assert(f.bitmap[2].material ~= "gui_belakor_atlas_masked_saturated")
    end)
end
