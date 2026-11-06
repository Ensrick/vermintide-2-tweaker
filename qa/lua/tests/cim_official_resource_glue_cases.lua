-- Actual official/Dev CIM resource-glue proof, with exact native routes.
-- No Dev namespace rewrite, copied CIM logic, game launch or engine acceptance.
return function(H, repo, stream)
    repo = repo:gsub("\\", "/")
    stream = stream or "crafting_in_modded"
    assert(stream == "crafting_in_modded" or stream == "crafting_in_modded_dev")
    local mod_id = stream == "crafting_in_modded" and "cim" or "cim_dev"
    local prefix = "/" .. stream .. "/scripts/mods/" .. stream .. "/"
    local proof = os.getenv("CIM_RESOURCE_PROOF_OVERLAY")
    if proof then
        proof = proof:gsub("\\", "/"):gsub("/$", "")
        assert(proof == repo .. "/.temp/public-promotion-20261105/cim-proof-integration/files")
    end
    local Native = assert(loadfile(repo .. "/qa/lua/tests/fixtures/ct_native_gui_contract_6_13.lua"))()
    local texture_source_commit = "93dea911a4cc464a0eb51cfdc3a443297bfc4550"
    local texture_source_sha256 = "b83cbb8b6d9840464d720453eb763dd4adf6bd0a0c1c8cf35f40950b042d39eb"
    local texture_code = [==[
UIPasses.texture = {
	init = function (pass_definition, content, style, ui_renderer)
		if pass_definition.clone and ui_renderer then
			local gui = ui_renderer.gui

			if pass_definition.retained_mode then
				gui = ui_renderer.gui_retained
			end

			local material_name = content[pass_definition.texture_id or "texture_id"]
			local new_material_name = Application.guid()

			Gui.clone_material_from_template(gui, new_material_name, material_name)

			pass_definition.cloned_material = new_material_name
			content[pass_definition.texture_id or "texture_id"] = new_material_name
		end

		if pass_definition.material_func and ui_renderer then
			local gui = ui_renderer.gui

			if pass_definition.retained_mode then
				gui = ui_renderer.gui_retained
			end

			local context = pass_definition.context
			local texture_name = content[pass_definition.texture_id or "texture_id"]

			pass_definition.material_func(gui, texture_name, context)
		end

		if pass_definition.retained_mode then
			return {
				dirty = true,
			}
		end
	end,
	destroy = function (ui_renderer, pass_data, pass_definition)
		assert(pass_definition.retained_mode, "Attempted to destroy an immediate mode pass")

		if pass_data.retained_id then
			UIRenderer.destroy_bitmap(ui_renderer, pass_data.retained_id)

			pass_data.retained_id = nil
		end
	end,
	draw = function (ui_renderer, pass_data, ui_scenegraph, pass_definition, ui_style, ui_content, position, size, input_service, dt)
		local texture_name = ui_content[pass_definition.texture_id or "texture_id"]
		local color, masked, saturated, point_sample, viewport_mask

		if ui_style then
			local texture_size = ui_style.texture_size

			if texture_size then
				UIUtils.align_box_inplace(ui_style, position, size, texture_size)

				size = texture_size
			end

			color = ui_style.color
			masked = ui_style.masked
			saturated = ui_style.saturated
			point_sample = ui_style.point_sample
			viewport_mask = ui_style.viewport_mask
		end

		if pass_definition.retained_mode then
			local retained_id = pass_definition.retained_mode and (pass_data.retained_id or true)

			retained_id = UIRenderer_draw_texture(ui_renderer, texture_name, position, size, color, masked, saturated, retained_id, point_sample, viewport_mask)
			pass_data.retained_id = retained_id or pass_data.retained_id
			pass_data.dirty = false
		else
			UIRenderer_draw_texture(ui_renderer, texture_name, position, size, color, masked, saturated, nil, point_sample, viewport_mask)
		end
	end,
}
]==]
    H.equal(texture_source_commit, Native.source_commit)
    H.equal(#texture_source_sha256, 64)

    local function pack(...) return { n = select("#", ...), ... } end
    local function execute(source, env, label)
        local chunk = assert(loadstring(source, "@" .. label))
        setfenv(chunk, env); return chunk()
    end
    local function fixture()
        local f = { hooks = {}, queries = {}, bitmaps = {}, resource_queries = {}, atlases = {} }
        local env = setmetatable({}, { __index = _G })
        env._G = env
        env.printf = function() end
        env.DamageUtils = { is_in_inn = false }
        env.RESOLUTION_LOOKUP = { scale = 1 }
        env.Vector2 = function(x, y) return { x, y } end
        env.Vector3 = function(x, y, z) return { x, y, z } end
        env.Color = function(a, b, c, d) return { a, b, c, d } end
        env.UIRenderer, env.UIPasses = {}, {}
        env.UIAtlasHelper = {
            has_atlas_settings_by_texture_name = function(name) return f.atlases[name] ~= nil end,
            get_atlas_settings_by_texture_name = function(name) return f.atlases[name] end,
        }
        env.Application = { can_get = function(kind, name)
            f.resource_queries[#f.resource_queries + 1] = { kind, name }
            if f.resource_probe then return f.resource_probe(kind, name) end
            return true
        end }
        env.Gui = { material = function(gui, name)
            f.queries[#f.queries + 1] = { gui = gui, name = name }
            if f.gui_probe then return f.gui_probe(gui, name) end
            return gui and gui.materials and gui.materials[name]
        end }
        local function bitmap(gui, material)
            f.bitmaps[#f.bitmaps + 1] = { gui = gui, material = material }
            assert(gui and gui.materials and gui.materials[material],
                "actual native bitmap reached unproved Gui/material")
            return #f.bitmaps
        end
        env.Gui_bitmap, env.Gui_bitmap_uv = bitmap, bitmap
        env.Gui_update_bitmap, env.Gui_update_bitmap_uv = bitmap, bitmap
        execute(Native.code.bitmap, env, "native6.13/UIRenderer.script_draw_bitmap")
        execute(Native.code.draw_texture, env, "native6.13/UIRenderer.draw_texture")
        env.UIRenderer_draw_texture = env.UIRenderer.draw_texture
        execute(texture_code, env, "native6.13/UIPasses.texture")
        local mod = {}
        function mod:debug() end
        function mod:info() end
        function mod:warning() end
        function mod:hook(class, method, callback)
            local key = class .. "." .. method
            assert(f.hooks[key] == nil, "duplicate actual mission hook " .. key)
            f.hooks[key] = callback
        end
        mod.hook_safe = mod.hook
        env.get_mod = function(id) H.equal(id, mod_id); return mod end
        local function actual(name)
            local path = repo .. prefix .. name .. ".lua"
            if proof then
                local candidate = proof .. prefix .. name .. ".lua"
                local file = io.open(candidate, "rb")
                if file then file:close(); path = candidate end
            end
            local chunk = assert(loadfile(path))
            setfenv(chunk, env); return chunk()
        end
        f.residency = actual("_lib_resource_residency")
        f.icon = actual("_cim_athanor_icon_policy")
        f.icon.set_resource_residency(f.residency)
        mod._cim_resource_residency = f.residency
        mod._cim_athanor_icon_policy = f.icon
        mod._cim83_forge_widget_policy = actual("_cim_forge_widget_material_policy")
        mod._cim_forge_preview_policy = actual("_cim_forge_preview_policy")
        actual("_cim_mission_forge_safety") -- COMPLETE actual entry installs every hook.
        f.env, f.mod = env, mod
        return f
    end
    local function gui(label)
        return { label = label, materials = {} }
    end
    local function renderer(label)
        return { gui = gui(label .. "-immediate"), gui_retained = gui(label .. "-retained"),
            render_settings = { snap_pixel_positions = false } }
    end
    local function widget(texture, retained)
        return { element = { passes = {
            { pass_type = "texture", style_id = "texture", texture_id = "icon",
                retained_mode = retained },
            { pass_type = "text", style_id = "text", text_id = "title" },
        } }, content = { icon = texture, title = "Unchanged text" }, style = { texture = {}, text = {} } }
    end
    local function draw(f, w, target)
        local pass = w.element.passes[1]
        if pass.content_check_function and pass.content_check_function(w.content, w.style) == false then
            return false
        end
        -- Actual native pass selects retained_mode, then actual native renderer
        -- selects gui/gui_retained and the atlas variant before the sink spy.
        local data = f.env.UIPasses.texture.init(pass) or {}
        f.env.UIPasses.texture.draw(target, data, {}, pass, w.style.texture,
            w.content, { 0, 0, 0 }, { 8, 8, 0 }, {}, 0)
        return true
    end
    local function static_setup(f, window)
        f.hooks["HeroWindowWeaveProperties.create_ui_elements"](window)
    end
    local function dynamic_setup(f, window, w)
        local calls = 0
        local result = pack(f.hooks["HeroWindowWeaveForgeWeapons._setup_weapon_stats"](
            function(self, argument)
                H.equal(argument, "producer"); calls = calls + 1
                self._scrollbars = { late = { list_widgets = { w } } }
                return nil, "tail", nil
            end, window, "producer"))
        H.equal(calls, 1); H.equal(result.n, 3)
        H.equal(result[1], nil); H.equal(result[2], "tail"); H.equal(result[3], nil)
    end

    H.test(stream .. " resource glue: real icon/shared helper proves exact atlas Gui", function()
        local f, target = fixture(), renderer("icon")
        f.atlases.icon = { material_name = "base", masked_material_name = "masked",
            saturated_material_name = "saturated", masked_saturated_material_name = "exact",
            uv00 = { 0, 0 }, uv11 = { 1, 1 } }
        target.gui.materials.exact = {}
        local ready, material, reason = f.icon.renderer_has_texture(target, "icon",
            f.env.UIAtlasHelper, f.env.Gui, { masked = true, saturated = true })
        H.equal(ready, true); H.equal(material, "exact"); H.equal(reason, "resident")
        H.equal(f.queries[1].gui, target.gui); H.equal(f.queries[1].name, "exact")
        H.equal(#f.resource_queries, 0, "global can_get is not renderer ownership")
        for _, mode in ipairs({ "nil", "null", "throw", "wrong-gui" }) do
            f.gui_probe = function(g, name)
                if mode == "throw" then error("unavailable Gui API", 0) end
                if mode == "null" then return "#ID[00000000]" end
                if mode == "wrong-gui" and g == target.gui_retained then return {} end
                return nil
            end
            local result = f.icon.renderer_has_texture(target, "icon",
                f.env.UIAtlasHelper, f.env.Gui, { masked = true, saturated = true })
            H.equal(result, false, mode .. " proof must refuse")
        end
        f.gui_probe = nil
        H.equal(f.icon.renderer_has_texture({}, "icon", f.env.UIAtlasHelper, f.env.Gui), false)
        H.equal(f.icon.renderer_has_texture(target, "icon", f.env.UIAtlasHelper, {}), false)
    end)

    H.test(stream .. " resource glue: actual viewport hook uses strict boolean resource proof", function()
        for _, mode in ipairs({ "true", "false", "nil", "throw", "hdr-only", "wrong-kind" }) do
            local f = fixture()
            f.resource_probe = function(kind, name)
                if mode == "throw" then error("probe unavailable", 0) end
                if mode == "true" then return true end
                if mode == "false" then return false end
                if mode == "hdr-only" then return name == "environment/ui_hdr" end
                if mode == "wrong-kind" then return kind == "material" end
                return nil
            end
            local result = f.hooks["HeroWindowWeaveForgeWeapons._create_viewport_definition"](
                function() return { style = { viewport = {
                    shading_environment = "environment/ui_weave_forge_preview" } } } end, {})
            local expected = mode == "true" and "environment/ui_store_preview"
                or mode == "hdr-only" and "environment/ui_hdr" or "environment/blank"
            H.equal(result.style.viewport.shading_environment, expected, mode)
            for _, query in ipairs(f.resource_queries) do H.equal(query[1], "shading_environment") end
        end
        local f = fixture()
        f.env.DamageUtils.is_in_inn = true
        local definition = { style = { viewport = { shading_environment = "keep-native" } } }
        H.equal(f.hooks["HeroWindowWeaveForgeWeapons._create_viewport_definition"](
            function() return definition end, {}), definition)
        H.equal(#f.resource_queries, 0)
    end)

    H.test(stream .. " resource glue: actual dynamic producer allows only proved immediate draws", function()
        for _, mode in ipairs({ "true", "nil", "null", "throw", "wrong-gui" }) do
            local f, target, w = fixture(), renderer("dynamic"), widget("raw", false)
            w.style.texture.retained_id = "irrelevant-style-field"
            target.gui.materials.raw = {}
            f.gui_probe = function(g, name)
                if mode == "true" then return g == target.gui and g.materials[name] end
                if mode == "throw" then error("unavailable", 0) end
                if mode == "null" then return "#ID[00000000]" end
                if mode == "wrong-gui" and g == target.gui_retained then return {} end
                return nil
            end
            dynamic_setup(f, { _ui_top_renderer = target }, w)
            H.equal(draw(f, w, target), mode == "true", mode)
            H.equal(#f.bitmaps, mode == "true" and 1 or 0)
            H.equal(w.element.passes[2].pass_type, "text")
        end
        local f, token = fixture(), {}
        local ok, err = pcall(f.hooks["HeroWindowWeaveForgeWeapons._setup_weapon_stats"],
            function() error(token, 0) end, {})
        H.equal(ok, false); H.equal(err, token); H.equal(#f.queries, 0)
    end)

    H.test(stream .. " resource glue: actual static callback separates bottom and top immediate Guis", function()
        local f, bottom, top = fixture(), renderer("bottom"), renderer("top")
        local bw, tw = widget("bottom-only", false), widget("top-only", false)
        bottom.gui.materials["bottom-only"], top.gui.materials["top-only"] = {}, {}
        local window = { _ui_renderer = bottom, _ui_top_renderer = top,
            _bottom_widgets = { bw }, _top_widgets = { tw },
            _bottom_hdr_widgets = { {} }, _top_hdr_widgets = { {} } }
        static_setup(f, window)
        H.equal(#window._bottom_hdr_widgets, 0); H.equal(#window._top_hdr_widgets, 0)
        H.equal(draw(f, bw, bottom), true); H.equal(draw(f, tw, top), true)
        H.equal(f.bitmaps[1].gui, bottom.gui); H.equal(f.bitmaps[2].gui, top.gui)
        local wrong = widget("top-only", false)
        window._bottom_widgets = { wrong }; static_setup(f, window)
        H.equal(draw(f, wrong, bottom), false, "top proof cannot authorize bottom")
    end)

    H.test(stream .. " resource glue: actual dynamic retained pass proves native retained Gui", function()
        for _, safe in ipairs({ true, false }) do
            local f, target, w = fixture(), renderer("retained-dynamic"), widget("retained-only", true)
            if safe then target.gui_retained.materials["retained-only"] = {}
            else target.gui.materials["retained-only"] = {} end
            dynamic_setup(f, { _ui_top_renderer = target }, w)
            H.equal(draw(f, w, target), safe)
            H.equal(#f.bitmaps, safe and 1 or 0)
            if safe then H.equal(f.bitmaps[1].gui, target.gui_retained) end
        end
    end)

    H.test(stream .. " resource glue: actual static retained pass proves native retained Gui", function()
        for _, safe in ipairs({ true, false }) do
            local f, target, w = fixture(), renderer("retained-static"), widget("retained-only", true)
            if safe then target.gui_retained.materials["retained-only"] = {}
            else target.gui.materials["retained-only"] = {} end
            static_setup(f, { _ui_top_renderer = target, _top_widgets = { w } })
            H.equal(draw(f, w, target), safe)
            H.equal(#f.bitmaps, safe and 1 or 0)
            if safe then H.equal(f.bitmaps[1].gui, target.gui_retained) end
        end
    end)

    H.test(stream .. " resource glue: missing retained Gui never borrows immediate proof", function()
        local f, target, w = fixture(), renderer("missing-retained"), widget("raw", true)
        target.gui.materials.raw = {}
        target.gui_retained = nil
        dynamic_setup(f, { _ui_top_renderer = target }, w)
        H.equal(draw(f, w, target), false)
        H.equal(#f.bitmaps, 0)
    end)

    H.test(stream .. " resource glue: actual setup and unsafe draw callbacks refuse mission native body", function()
        local f, calls = fixture(), 0
        local function native() calls = calls + 1; return "native" end
        f.hooks["HeroView._setup_hdr_gui"](native, { is_in_inn = false })
        f.hooks["HeroWindowWeaveProperties._set_background_bloom_intensity"](native, {})
        f.hooks["HeroWindowWeaveForgeWeapons._start_transition_animation"](native, {}, "upgrade")
        H.equal(calls, 0)
        H.equal(f.hooks["HeroWindowWeaveForgeWeapons._start_transition_animation"](
            native, {}, "on_enter"), "native"); H.equal(calls, 1)
        f.env.DamageUtils.is_in_inn = true
        H.equal(f.hooks["HeroView._setup_hdr_gui"](native, { is_in_inn = true }), "native")
        H.equal(f.hooks["HeroWindowWeaveProperties._set_background_bloom_intensity"](native, {}), "native")
        H.equal(calls, 3)
    end)
end
