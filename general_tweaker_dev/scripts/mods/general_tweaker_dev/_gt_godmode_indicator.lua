local mod = get_mod("gt_dev")
local policy = mod:dofile("scripts/mods/general_tweaker_dev/_gt_godmode_indicator_policy")

-- Issue #381: persistent, local HUD cue for the dev-only Godmode control. This
-- module owns no hook. `_gt_melee_warning.lua` is gt's singleton owner of
-- (IngameHud, update) and calls this exported draw consumer once per HUD frame.
local UIRenderer = UIRenderer
local UISceneGraph = UISceneGraph
local Vector2 = Vector2
local Vector3 = Vector3
local UILayer = rawget(_G, "UILayer")

local _TEXT = "GODMODE"
local _FONT = "materials/fonts/arial"
local _FONT_SIZE = 24
local _ROOT = {
    root = {
        scale = "hud_scale_fit",
        position = { 0, 0, (UILayer and UILayer.hud) or 100 },
        size = { 1920, 1080 },
    },
}
local _render_settings = { snap_pixel_positions = true }
local _scenegraph

local function _draw(self, dt)
    if not policy.visible(mod:get("godmode_enabled")) then return end

    local context = self and self._ingame_ui_context
    local renderer = context and context.ui_renderer
        or (Managers.ui and Managers.ui._ingame_ui_context
            and Managers.ui._ingame_ui_context.ui_top_renderer)
    if not renderer then return end

    local input = context and context.input_manager
        and context.input_manager:get_service("ingame_menu")
    if not _scenegraph then
        _scenegraph = UISceneGraph.init_scenegraph(_ROOT)
    end

    local width = 0
    local ok, measured = pcall(UIRenderer.text_size, renderer, _TEXT, _FONT, _FONT_SIZE)
    if ok and type(measured) == "number" then width = measured end
    local layout = policy.layout(width)

    UIRenderer.begin_pass(renderer, _scenegraph, input, dt, nil, _render_settings)
    UIRenderer.draw_rect(renderer,
        Vector3(layout.background_x, layout.background_y, 997),
        Vector2(layout.background_width, layout.background_height),
        { 150, 10, 10, 10 })
    UIRenderer.draw_text(renderer, _TEXT, _FONT, _FONT_SIZE, nil,
        Vector3(layout.text_x + 2, layout.text_y - 2, 998), { 220, 0, 0, 0 })
    UIRenderer.draw_text(renderer, _TEXT, _FONT, _FONT_SIZE, nil,
        Vector3(layout.text_x, layout.text_y, 999), { 255, 255, 190, 40 })
    UIRenderer.end_pass(renderer)
end

mod._gt_godmode_indicator_draw = _draw
mod._GT_381_GODMODE_INDICATOR_MARKER = "gt-381-godmode-hud-indicator"

mod._gt_rt_register("issue381_godmode_hud_indicator", function()
    if mod._GT_381_GODMODE_INDICATOR_MARKER ~= "gt-381-godmode-hud-indicator" then
        return "Godmode indicator marker missing"
    end
    if type(mod._gt_godmode_indicator_draw) ~= "function" then
        return "Godmode indicator draw consumer missing"
    end
    if not policy.visible(true) or policy.visible(false) or policy.visible(1) then
        return "Godmode indicator visibility gate drifted"
    end
    local layout = policy.layout(100)
    if layout.background_x < 0 or layout.background_x + layout.background_width > 1920 then
        return "Godmode indicator layout escaped HUD canvas"
    end
end)

return {}
