local mod = get_mod("gut")

-- Mod Tweaker view (v0.2 — first renderable pass).
-- A native-style settings screen registered into IngameUI.views and opened from
-- the ESC-menu "Mod Tweaker" entry. Built from the verified OptionsView contract
-- (options_view.lua, read 2026-06-17): borrow the IngameUI renderer (never make
-- our own world/renderer), register a modal input service, draw in one
-- begin_pass/end_pass, exit via ingame_ui:transition_with_fade("ingame_menu").
--
-- The registry of categories/values is owned by the controller
-- (get_mod("gut").mod_tweaker); the view goes through it so there's a SINGLE
-- registry instance (a fresh dofile of _mod_tweaker_settings would be empty).

local defs = mod:dofile("scripts/mods/gui_tweaker/_mod_tweaker_definitions")

local UIRenderer = UIRenderer
local UISceneGraph = UISceneGraph
local UIInverseScaleVectorToResolution = UIInverseScaleVectorToResolution
local ShowCursorStack = ShowCursorStack
local math = math

local SERVICE = "gut_mod_tweaker"

local F = defs.widget_factories
local COLORS = defs.colors

local ModTweakerView = class(ModTweakerView)

ModTweakerView.NAME = "mod_tweaker_view"

-- ---------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------

function ModTweakerView:init(ingame_ui_context)
    if not ingame_ui_context then
        -- Caught by the setup_views hook's pcall; the transition guard then keeps
        -- the (unattached) view from ever being switched to. See gui_tweaker.lua.
        error("ModTweakerView:init received nil ingame_ui_context")
    end
    self.ingame_ui_context = ingame_ui_context
    self.ui_renderer = ingame_ui_context.ui_renderer
    self.ui_top_renderer = ingame_ui_context.ui_top_renderer or ingame_ui_context.ui_renderer
    self.ingame_ui = ingame_ui_context.ingame_ui
    self.input_manager = ingame_ui_context.input_manager
    self.render_settings = { alpha_multiplier = 1, snap_pixel_positions = false }

    pcall(function()
        self.input_manager:create_input_service(SERVICE, "IngameMenuKeymaps", "IngameMenuFilters")
        self.input_manager:map_device_to_service(SERVICE, "keyboard")
        self.input_manager:map_device_to_service(SERVICE, "mouse")
        self.input_manager:map_device_to_service(SERVICE, "gamepad")
    end)

    self.ui_scenegraph = UISceneGraph.init_scenegraph(defs.scenegraph_definition)

    self._screen_dim = F.screen_dim()
    self._panel = F.panel()
    self._title = F.title("Mod Tweaker")
    self._hint = F.hint("")
    self._tabs = {}
    self._rows = {}
    self._selected = 1
    self._active = false
end

-- ---------------------------------------------------------------
-- Registry access (through the controller — single source of truth)
-- ---------------------------------------------------------------

local function _mt()
    return mod.mod_tweaker
end

local function _walk_leaves(node, out)
    if type(node) ~= "table" then return end
    if type(node.setting_id) == "string" then out[#out + 1] = node end
    if type(node.sub_widgets) == "table" then
        for i = 1, #node.sub_widgets do _walk_leaves(node.sub_widgets[i], out) end
    end
    if type(node.widgets) == "table" then
        for i = 1, #node.widgets do _walk_leaves(node.widgets[i], out) end
    end
end

-- ---------------------------------------------------------------
-- Value <-> widget glue
-- ---------------------------------------------------------------

function ModTweakerView:_apply_checkbox(row)
    local on = row.content.flag and true or false
    row.style.box.color = on and COLORS.BOX_ON or COLORS.BOX_OFF
    row.content.value_text = on and "ON" or "OFF"
end

function ModTweakerView:_apply_slider(row)
    local c = row.content
    local iv = math.clamp(c.internal_value or 0, 0, 1)
    c.internal_value = iv
    local val = (c.min or 0) + ((c.max or 1) - (c.min or 0)) * iv
    val = math.round_with_precision(val, c.num_decimals or 0)
    c.value = val
    c.value_text = tostring(val)
    row.style.fill.size[1] = (row.style._track_w or 0) * iv
end

function ModTweakerView:_build_rows(category)
    self._rows = {}
    if not category or type(category.widgets) ~= "table" then return end
    local leaves = {}
    for i = 1, #category.widgets do _walk_leaves(category.widgets[i], leaves) end

    local MT = _mt()
    for i = 1, #leaves do
        local w = leaves[i]
        local label = w.label or w.text or w.setting_id
        local wtype = w.type
        local row

        if wtype == "checkbox" or wtype == "boolean" then
            row = F.checkbox(label, i)
            local val = MT and MT:get(category.mod_id, w.setting_id)
            row.content.flag = val and true or false
            self:_apply_checkbox(row)
        elseif wtype == "slider" or wtype == "numeric" then
            row = F.slider(label, i)
            local min = (w.range and w.range[1]) or w.min or 0
            local max = (w.range and w.range[2]) or w.max or 1
            row.content.min = min
            row.content.max = max
            row.content.num_decimals = w.decimals or w.num_decimals or w.decimals_number or 0
            local val = MT and MT:get(category.mod_id, w.setting_id)
            if type(val) ~= "number" then val = min end
            row.content.internal_value = (max > min) and math.clamp((val - min) / (max - min), 0, 1) or 0
            self:_apply_slider(row)
        else
            -- v1: types we don't render yet (dropdown/keybind) show as a
            -- read-only label so the list is still complete.
            row = F.checkbox(label .. "  [" .. tostring(wtype) .. "]", i)
            row._readonly = true
            row.style.box.color = COLORS.BOX_OFF
            row.content.value_text = ""
        end

        row._mod_id = category.mod_id
        row._setting_id = w.setting_id
        row._wtype = wtype
        self._rows[#self._rows + 1] = row
    end
end

function ModTweakerView:_rebuild()
    local MT = _mt()
    self._categories = (MT and MT:list_categories()) or {}
    local n = #self._categories
    self._selected = math.clamp(self._selected or 1, 1, math.max(1, n))

    self._tabs = {}
    for i = 1, n do
        local cat = self._categories[i]
        self._tabs[i] = F.tab(cat.label or cat.mod_id, i)
    end

    self:_build_rows(self._categories[self._selected])

    if n == 0 then
        self._hint.content.text = "No mods have registered yet. (A mod calls get_mod('gut').mod_tweaker:register_category{...})"
    else
        self._hint.content.text = "Left: pick a mod.  Click a checkbox / drag a slider to change it.  ESC closes."
    end
end

-- ---------------------------------------------------------------
-- Lifecycle (driven by IngameUI)
-- ---------------------------------------------------------------

function ModTweakerView:on_enter(params)
    self._exit_transition = params and params.exit_transition
    self._active = true
    self:_rebuild()

    pcall(function()
        ShowCursorStack.show("ModTweakerView")
        self._cursor_pushed = true
        self.input_manager:block_device_except_service(SERVICE, "keyboard", 1)
        self.input_manager:block_device_except_service(SERVICE, "mouse", 1)
        self.input_manager:block_device_except_service(SERVICE, "gamepad", 1)
    end)
end

function ModTweakerView:on_exit()
    self._active = false
    self.exiting = nil
    pcall(function()
        if self._cursor_pushed then
            ShowCursorStack.hide("ModTweakerView")
            self._cursor_pushed = nil
        end
        self.input_manager:device_unblock_all_services("keyboard", 1)
        self.input_manager:device_unblock_all_services("mouse", 1)
        self.input_manager:device_unblock_all_services("gamepad", 1)
    end)
end

function ModTweakerView:exit(return_to_game)
    self.exiting = true
    local transition = (return_to_game and "exit_menu") or self._exit_transition or "ingame_menu"
    if self.ingame_ui and self.ingame_ui.transition_with_fade then
        self.ingame_ui:transition_with_fade(transition)
    end
end

function ModTweakerView:transitioning()
    if self.exiting then
        return true
    end
    return not self._active
end

-- IngameUI calls these UNCONDITIONALLY on the active/new/old view (ingame_ui.lua
-- :416/770 input_service, :913 post_update_on_enter, :906 post_update_on_exit),
-- so a view MUST implement them or IngameUI crashes. input_service hands back the
-- service IngameUI routes input through; the post_update_on_* hooks are no-ops
-- for us (all our enter/exit work is in on_enter/on_exit). The remaining contract
-- methods (current_state/disable_toggle_menu/hotkey_allowed/set_map_interaction_
-- state/is_survey_*) are guarded with `if view.method` and are safe to omit.
function ModTweakerView:input_service()
    return self.input_manager:get_service(SERVICE)
end

function ModTweakerView:post_update_on_enter(params) end

function ModTweakerView:post_update_on_exit(params, was_replaced) end

function ModTweakerView:update(dt, t)
    if not self._active then
        return
    end
    local input_service = self.input_manager:get_service(SERVICE)
    if not input_service then
        return
    end

    self:_draw(dt, input_service)

    -- ESC / back -> close.
    if input_service:get("toggle_menu", true) or input_service:get("back", true) then
        self:exit(false)
        return
    end

    self:_handle_input(input_service)
end

function ModTweakerView:post_update(dt, t) end

function ModTweakerView:destroy()
    pcall(function()
        if self._cursor_pushed then
            ShowCursorStack.hide("ModTweakerView")
            self._cursor_pushed = nil
        end
    end)
end

-- ---------------------------------------------------------------
-- Input (read hotspot flags populated during the draw pass)
-- ---------------------------------------------------------------

function ModTweakerView:_handle_input(input_service)
    -- Tab clicks -> switch category.
    for i = 1, #self._tabs do
        local hs = self._tabs[i].content.hotspot
        if hs and hs.on_release and i ~= self._selected then
            self._selected = i
            self:_build_rows(self._categories[i])
            return
        end
    end

    -- Row interactions.
    local MT = _mt()
    for i = 1, #self._rows do
        local row = self._rows[i]
        if not row._readonly then
            if row._wtype == "checkbox" or row._wtype == "boolean" then
                if row.content.hotspot and row.content.hotspot.on_release then
                    row.content.flag = not row.content.flag
                    self:_apply_checkbox(row)
                    if MT then MT:set(row._mod_id, row._setting_id, row.content.flag) end
                end
            elseif row._wtype == "slider" or row._wtype == "numeric" then
                if row.content._dirty then
                    row.content._dirty = false
                    self:_apply_slider(row)
                    if MT then MT:set(row._mod_id, row._setting_id, row.content.value) end
                end
            end
        end
    end
end

-- ---------------------------------------------------------------
-- Draw (single begin_pass/end_pass on the borrowed top renderer)
-- ---------------------------------------------------------------

function ModTweakerView:_draw(dt, input_service)
    local renderer = self.ui_top_renderer
    local scenegraph = self.ui_scenegraph

    -- Refresh tab colors (selected vs hover vs idle) before drawing.
    for i = 1, #self._tabs do
        local tab = self._tabs[i]
        if i == self._selected then
            tab.style.bg.color = COLORS.TAB_SEL
        elseif tab.content.hotspot and tab.content.hotspot.is_hover then
            tab.style.bg.color = COLORS.TAB_HOVER
        else
            tab.style.bg.color = COLORS.TAB
        end
    end

    UIRenderer.begin_pass(renderer, scenegraph, input_service, dt, nil, self.render_settings)

    UIRenderer.draw_widget(renderer, self._screen_dim)
    UIRenderer.draw_widget(renderer, self._panel)
    UIRenderer.draw_widget(renderer, self._title)
    UIRenderer.draw_widget(renderer, self._hint)

    for i = 1, #self._tabs do
        UIRenderer.draw_widget(renderer, self._tabs[i])
    end
    for i = 1, #self._rows do
        UIRenderer.draw_widget(renderer, self._rows[i])
    end

    UIRenderer.end_pass(renderer)
end

return ModTweakerView
