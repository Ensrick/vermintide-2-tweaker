local mod = get_mod("gut")

-- Mod Tweaker scenegraph + widget factories (v0.2 — first renderable pass).
-- Built from the verified VT2 OptionsView patterns (options_view.lua /
-- options_view_definitions.lua, read 2026-06-17): borrow the IngameUI renderer,
-- one begin_pass/end_pass, widgets via UIWidget.init, scenegraph via
-- UISceneGraph.init_scenegraph. Deliberately atlas-free: widgets are built from
-- `rect` + `text` + `hotspot` passes (always available on any UI renderer) so the
-- first on-screen pass can't fail on a missing texture. Visual polish (proper
-- checkbox/slider textures) is a later pass once layout is confirmed in-game.

local UIWidget = UIWidget
local Colors = Colors

-- Layout constants (1920x1080 virtual space, like options_view).
local PANEL_W, PANEL_H = 1200, 800
local CONTENT_TOP   = -96        -- y of the first tab/row under the title bar
local TAB_AREA_W    = 300
local TAB_H         = 40
local ROW_H         = 44
local ROW_W         = PANEL_W - TAB_AREA_W - 90   -- list width
local LIST_X        = TAB_AREA_W + 60             -- left x of the settings list (within panel)

local FONT = "hell_shark"

local function _color(a, r, g, b) return { a, r, g, b } end

-- Solid panel + chrome colors.
local C_DIM       = _color(210, 8, 8, 10)     -- full-screen dim behind panel
local C_PANEL     = _color(245, 22, 22, 26)   -- panel fill
local C_TAB       = _color(180, 38, 38, 44)
local C_TAB_SEL   = _color(235, 120, 90, 40)
local C_TAB_HOVER = _color(210, 70, 60, 50)
local C_BOX_ON    = _color(255, 90, 200, 90)
local C_BOX_OFF   = _color(255, 70, 70, 78)
local C_TRACK     = _color(255, 50, 50, 58)
local C_FILL      = _color(255, 200, 150, 60)
local C_TEXT      = _color(255, 235, 230, 215)
local C_TEXT_DIM  = _color(255, 170, 165, 155)

local scenegraph_definition = {
    root = {
        scale = "fit",
        position = { 0, 0, (UILayer.options_menu or 100) + 10 },
        size = { 1920, 1080 },
    },
    screen = {
        parent = "root",
        horizontal_alignment = "center",
        vertical_alignment = "center",
        position = { 0, 0, 1 },
        size = { 1920, 1080 },
    },
    panel = {
        parent = "root",
        horizontal_alignment = "center",
        vertical_alignment = "center",
        position = { 0, 0, 2 },
        size = { PANEL_W, PANEL_H },
    },
    title = {
        parent = "panel",
        horizontal_alignment = "left",
        vertical_alignment = "top",
        position = { 40, -28, 3 },
        size = { PANEL_W - 80, 48 },
    },
    tab_area = {
        parent = "panel",
        horizontal_alignment = "left",
        vertical_alignment = "top",
        position = { 30, CONTENT_TOP, 3 },
        size = { TAB_AREA_W, PANEL_H + CONTENT_TOP - 60 },
    },
    list_area = {
        parent = "panel",
        horizontal_alignment = "left",
        vertical_alignment = "top",
        position = { LIST_X, CONTENT_TOP, 3 },
        size = { ROW_W + 40, PANEL_H + CONTENT_TOP - 60 },
    },
    hint = {
        parent = "panel",
        horizontal_alignment = "left",
        vertical_alignment = "bottom",
        position = { 40, 18, 3 },
        size = { PANEL_W - 80, 28 },
    },
}

-- ---------------------------------------------------------------
-- Widget factories. Each returns a live widget (UIWidget.init).
-- The VIEW owns all interaction logic; it reads the hotspot tables
-- (`content.hotspot.on_release`, `.is_hover`) and the held-drag cursor each
-- frame, then mutates `content` (color/value/text) + persists via Settings.
-- ---------------------------------------------------------------

local function _text_pass(style_id, text_id)
    return { pass_type = "text", style_id = style_id, text_id = text_id }
end

local function _text_style(offset, size, color, h_align)
    return {
        dynamic_font = true,
        font_size = size or 24,
        font_type = FONT,
        horizontal_alignment = h_align or "left",
        vertical_alignment = "center",
        text_color = color or C_TEXT,
        offset = offset,
        size = { ROW_W, ROW_H },
    }
end

-- Full-screen dim behind the panel.
local function create_screen_dim()
    return UIWidget.init({
        element = { passes = { { pass_type = "rect", style_id = "rect" } } },
        content = {},
        style = { rect = { color = C_DIM, offset = { 0, 0, 0 }, size = { 1920, 1080 } } },
        scenegraph_id = "screen",
    })
end

-- The panel background + title bar accent.
local function create_panel()
    return UIWidget.init({
        element = {
            passes = {
                { pass_type = "rect", style_id = "fill" },
                { pass_type = "rect", style_id = "title_bar" },
            },
        },
        content = {},
        style = {
            fill = { color = C_PANEL, offset = { 0, 0, 0 }, size = { PANEL_W, PANEL_H } },
            title_bar = { color = C_TAB_SEL, offset = { 0, -76, 1 }, size = { PANEL_W, 4 } },
        },
        scenegraph_id = "panel",
    })
end

local function create_title(text)
    return UIWidget.init({
        element = { passes = { _text_pass("text", "text") } },
        content = { text = text or "Mod Tweaker" },
        style = { text = _text_style({ 0, 0, 0 }, 34, C_TEXT) },
        scenegraph_id = "title",
    })
end

local function create_hint(text)
    return UIWidget.init({
        element = { passes = { _text_pass("text", "text") } },
        content = { text = text or "" },
        style = { text = _text_style({ 0, 0, 0 }, 18, C_TEXT_DIM) },
        scenegraph_id = "hint",
    })
end

-- Left-column tab button (one per registered category). `index` is 1-based;
-- rows stack downward from the top of tab_area.
local function create_tab(text, index)
    local y = -(index - 1) * (TAB_H + 6)
    return UIWidget.init({
        element = {
            passes = {
                { pass_type = "hotspot", content_id = "hotspot", style_id = "hotspot" },
                { pass_type = "rect", style_id = "bg" },
                _text_pass("text", "text"),
            },
        },
        content = {
            hotspot = {},
            text = text,
            selected = false,
        },
        style = {
            hotspot = { offset = { 0, y, 0 }, size = { TAB_AREA_W - 10, TAB_H } },
            bg = { color = C_TAB, offset = { 0, y, 0 }, size = { TAB_AREA_W - 10, TAB_H } },
            text = {
                dynamic_font = true, font_size = 22, font_type = FONT,
                horizontal_alignment = "left", vertical_alignment = "center",
                text_color = C_TEXT, offset = { 16, y, 1 }, size = { TAB_AREA_W - 26, TAB_H },
            },
        },
        scenegraph_id = "tab_area",
    })
end

-- Checkbox row. `row_index` is 1-based position within the list. Value box turns
-- green (on) / grey (off); the view flips it from content.hotspot.on_release.
local function create_checkbox(text, row_index)
    local y = -(row_index - 1) * ROW_H
    return UIWidget.init({
        element = {
            passes = {
                { pass_type = "hotspot", content_id = "hotspot", style_id = "hotspot" },
                { pass_type = "rect", style_id = "box" },
                _text_pass("label", "text"),
                _text_pass("value", "value_text"),
            },
        },
        content = {
            hotspot = {},
            flag = false,
            text = text,
            value_text = "OFF",
        },
        style = {
            hotspot = { offset = { 0, y, 0 }, size = { ROW_W, ROW_H } },
            box = { color = C_BOX_OFF, offset = { ROW_W - 60, y + 10, 0 }, size = { 24, 24 } },
            label = _text_style({ 4, y, 0 }, 22, C_TEXT),
            value = {
                dynamic_font = true, font_size = 20, font_type = FONT,
                horizontal_alignment = "right", vertical_alignment = "center",
                text_color = C_TEXT_DIM, offset = { 4, y, 1 }, size = { ROW_W - 90, ROW_H },
            },
        },
        scenegraph_id = "list_area",
    })
end

-- Numeric slider row. Track + proportional fill; value text on the right. The
-- view updates internal_value/value from a held-drag and recomputes the fill.
local function create_slider(text, row_index)
    local y = -(row_index - 1) * ROW_H
    local track_x, track_w = ROW_W - 360, 300
    return UIWidget.init({
        element = {
            passes = {
                { pass_type = "hotspot", content_id = "hotspot", style_id = "hotspot" },
                {
                    pass_type = "held",
                    content_check_hover = "hotspot",
                    style_id = "track",
                    held_function = function(ui_scenegraph, ui_style, ui_content, input_service)
                        local cursor = UIInverseScaleVectorToResolution(input_service:get("cursor"))
                        local world_pos = UISceneGraph.get_world_position(ui_scenegraph, ui_content.scenegraph_id)
                        local pos_start = world_pos[1] + ui_style.offset[1]
                        local size_x = ui_style.size[1]
                        local v = math.clamp((cursor[1] - pos_start) / size_x, 0, 1)
                        ui_content.internal_value = v
                        ui_content._dirty = true
                    end,
                },
                { pass_type = "rect", style_id = "track" },
                { pass_type = "rect", style_id = "fill" },
                _text_pass("label", "text"),
                _text_pass("value", "value_text"),
            },
        },
        content = {
            hotspot = {},
            scenegraph_id = "list_area",
            internal_value = 0,
            value = 0,
            min = 0,
            max = 1,
            num_decimals = 2,
            text = text,
            value_text = "0",
            _dirty = false,
        },
        style = {
            hotspot = { offset = { track_x - 8, y + 6, 0 }, size = { track_w + 16, 26 } },
            track = { color = C_TRACK, offset = { track_x, y + 14, 0 }, size = { track_w, 12 } },
            fill = { color = C_FILL, offset = { track_x, y + 14, 1 }, size = { 0, 12 } },
            label = _text_style({ 4, y, 0 }, 22, C_TEXT),
            value = {
                dynamic_font = true, font_size = 20, font_type = FONT,
                horizontal_alignment = "right", vertical_alignment = "center",
                text_color = C_TEXT_DIM, offset = { 4, y, 2 }, size = { ROW_W - 30, ROW_H },
            },
            _track_x = track_x,
            _track_w = track_w,
        },
        scenegraph_id = "list_area",
    })
end

return {
    scenegraph_definition = scenegraph_definition,
    -- layout constants the view needs for hit-testing / fill math
    layout = {
        PANEL_W = PANEL_W, PANEL_H = PANEL_H, TAB_H = TAB_H, ROW_H = ROW_H, ROW_W = ROW_W,
        TAB_AREA_W = TAB_AREA_W,
    },
    colors = {
        TAB = C_TAB, TAB_SEL = C_TAB_SEL, TAB_HOVER = C_TAB_HOVER,
        BOX_ON = C_BOX_ON, BOX_OFF = C_BOX_OFF,
    },
    widget_factories = {
        screen_dim = create_screen_dim,
        panel = create_panel,
        title = create_title,
        hint = create_hint,
        tab = create_tab,
        checkbox = create_checkbox,
        slider = create_slider,
    },
}
