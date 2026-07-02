local mod = get_mod("gut_dev")

-- ============================================================================
-- Compendium (Armory + Bestiary) — Phase 0: stub HeroView sub-state
-- ============================================================================
-- Opens a blank framed panel from the hero menu, proving the HeroView sub-state
-- injection works before the real Armory/Bestiary UI (Phases 1-3). Reached via
-- /armory or /bestiary (the top-tab button lands in Phase 1). Lifecycle
-- modeled on the old Armory mod's HeroViewStateArmory; content is stubbed.
--
-- Defensive throughout: the hero menu is high-traffic, so a fault here must not
-- take it down — draw/update/input are pcall-guarded by the caller pattern and
-- nil-checked.

local UIRenderer   = UIRenderer
local UISceneGraph = UISceneGraph
local UIWidget     = UIWidget

local scenegraph_definition = {
    root  = { is_root = true, scale = "fit", size = { 1920, 1080 }, position = { 0, 0, 0 } },
    panel = { parent = "root",  vertical_alignment = "center", horizontal_alignment = "center",
              size = { 900, 600 }, position = { 0, 0, 10 } },
    title = { parent = "panel", vertical_alignment = "top",    horizontal_alignment = "center",
              size = { 860, 50 },  position = { 0, -30, 2 } },
    body  = { parent = "panel", vertical_alignment = "center", horizontal_alignment = "center",
              size = { 820, 400 }, position = { 0, 0, 2 } },
    exit  = { parent = "panel", vertical_alignment = "bottom", horizontal_alignment = "center",
              size = { 280, 48 },  position = { 0, 40, 2 } },
}

local function _panel_widget()
    return UIWidget.init({
        scenegraph_id = "panel",
        element = { passes = {
            { pass_type = "rect",   style_id = "bg" },
            { pass_type = "border", style_id = "border" },
        } },
        content = {},
        style = {
            bg     = { color = { 235, 14, 14, 16 } },
            border = { color = { 255, 120, 120, 120 }, thickness = 2 },
        },
        offset = { 0, 0, 0 },
    })
end

local function _text_widget(sg, text, font_size, color, halign)
    return UIWidget.init({
        scenegraph_id = sg,
        element = { passes = { { pass_type = "text", style_id = "text", text_id = "text" } } },
        content = { text = tostring(text or "") },
        style = { text = {
            font_type = "hell_shark", font_size = font_size, localize = false, upper_case = false,
            horizontal_alignment = halign or "center", vertical_alignment = "center",
            text_color = color, offset = { 0, 0, 2 },
        } },
        offset = { 0, 0, 0 },
    })
end

local function _exit_widget()
    return UIWidget.init({
        scenegraph_id = "exit",
        element = { passes = {
            { pass_type = "rect",    style_id = "bg" },
            { pass_type = "border",  style_id = "border" },
            -- style_id REQUIRED so the hotspot uses style.hotspot's size, not the
            -- node size (see reference_vt2_options_widgets_raw_materials).
            { pass_type = "hotspot", content_id = "hotspot", style_id = "hotspot" },
            { pass_type = "text",    style_id = "text", text_id = "text" },
        } },
        content = { hotspot = {}, text = "Back" },
        style = {
            bg      = { color = { 235, 30, 30, 34 } },
            border  = { color = { 255, 150, 150, 150 }, thickness = 2 },
            hotspot = { size = { 280, 48 }, offset = { 0, 0, 0 } },
            text    = { font_type = "hell_shark", font_size = 22, localize = false,
                        horizontal_alignment = "center", vertical_alignment = "center",
                        text_color = { 255, 230, 230, 230 }, offset = { 0, 0, 3 } },
        },
        offset = { 0, 0, 0 },
    })
end

HeroViewStateCompendium = class(HeroViewStateCompendium)
HeroViewStateCompendium.NAME = "HeroViewStateCompendium"

HeroViewStateCompendium.on_enter = function (self, params)
    self.parent = params.parent
    local ctx = params.ingame_ui_context
    self.ingame_ui_context = ctx
    self.ui_renderer       = ctx.ui_renderer
    self.ui_top_renderer   = ctx.ui_top_renderer
    self.input_manager     = ctx.input_manager
    self.voting_manager    = ctx.voting_manager
    self.ingame_ui         = ctx.ingame_ui
    self.render_settings   = { snap_pixel_positions = true }
    -- Mode is best-effort (custom transition params may not propagate); the stub
    -- panel is the same either way. Real Armory/Bestiary split comes with the data.
    -- The internal HeroView state-switch path (from an already-open hero_view, #223)
    -- carries no per-transition params, so the mode is stashed on the mod there and
    -- read here as a fallback; the from-outside transition path sets it in params.
    self._mode = (params and params.gut_compendium_mode) or mod._gut_pending_compendium_mode or "armory"
    mod._gut_pending_compendium_mode = nil
    self:create_ui_elements(params)
    pcall(function() self:play_sound("play_gui_lobby_button_00_heroic_deed") end)
    mod:info("[gut:compendium] Phase-0 stub entered (mode=%s)", tostring(self._mode))
end

HeroViewStateCompendium.create_ui_elements = function (self, params)
    self.ui_scenegraph   = UISceneGraph.init_scenegraph(scenegraph_definition)
    self._widgets        = {}
    self._widgets_by_name = {}
    local function add(name, w) self._widgets[#self._widgets + 1] = w; self._widgets_by_name[name] = w end
    add("panel", _panel_widget())
    add("title", _text_widget("title", "COMPENDIUM - WORK IN PROGRESS", 28, { 255, 255, 215, 90 }, "center"))
    add("body",  _text_widget("body",
        "Armory & Bestiary are being built here.\nWeapon and enemy lists arrive in the next update.",
        20, { 255, 200, 200, 200 }, "center"))
    add("exit",  _exit_widget())
end

HeroViewStateCompendium.update = function (self, dt, t)
    local input_service = self:input_service()
    self:draw(dt, input_service)
    if self:_has_active_level_vote() then
        self:close_menu(true)
    else
        self:_handle_input(dt, t)
    end
end

HeroViewStateCompendium.post_update = function (self, dt, t) end

HeroViewStateCompendium._handle_input = function (self, dt, t)
    local exit = self._widgets_by_name and self._widgets_by_name.exit
    local hs = exit and exit.content.hotspot
    if hs and (hs.on_release or hs.on_left_release) then
        self:close_menu()
    end
end

HeroViewStateCompendium.draw = function (self, dt, input_service)
    local ui_renderer   = self.ui_renderer
    local ui_scenegraph = self.ui_scenegraph
    if not (ui_renderer and ui_scenegraph and self._widgets) then return end
    UIRenderer.begin_pass(ui_renderer, ui_scenegraph, input_service, dt, nil, self.render_settings)
    for i = 1, #self._widgets do
        UIRenderer.draw_widget(ui_renderer, self._widgets[i])
    end
    UIRenderer.end_pass(ui_renderer)
end

HeroViewStateCompendium.input_service = function (self)
    return self.parent:input_service()
end

HeroViewStateCompendium.play_sound = function (self, event)
    if self.parent and self.parent.play_sound then self.parent:play_sound(event) end
end

HeroViewStateCompendium._has_active_level_vote = function (self)
    local vm = self.voting_manager
    if not vm then return false end
    local active = vm:vote_in_progress()
    local is_mission = active == "game_settings_vote" or active == "game_settings_deed_vote"
    return is_mission and not vm:has_voted(Network.peer_id())
end

HeroViewStateCompendium.close_menu = function (self, ignore_sound)
    if not ignore_sound then pcall(function() self:play_sound("Play_gui_achivements_menu_close") end) end
    if self.parent and self.parent.close_menu then
        self.parent:close_menu(nil, true)
    end
end

HeroViewStateCompendium.on_exit = function (self)
    self._widgets = nil
    self._widgets_by_name = nil
    self.ui_scenegraph = nil
end

return { class_name = "HeroViewStateCompendium" }
