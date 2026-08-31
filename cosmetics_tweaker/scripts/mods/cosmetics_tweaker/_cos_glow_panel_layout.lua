-- Pure host/layout policy for #377. The glow editor is hosted by the vanilla
-- HeroWindowItemCustomization Information panel; it must follow that live
-- scenegraph node instead of assuming a 1920x1080 screen position.
local PanelLayout = {}

local function _finite_number(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function _pair(value, positive)
    if type(value) ~= "table" or not _finite_number(value[1])
            or not _finite_number(value[2]) then
        return nil
    end
    if positive and (value[1] <= 0 or value[2] <= 0) then return nil end
    return value
end

function PanelLayout.resolve(host)
    local graph = type(host) == "table" and host._ui_scenegraph or nil
    local info = type(graph) == "table" and graph.info_window or nil
    local size = info and _pair(info.size, true)
    local position = info and _pair(info.world_position, false)
    if not size then return nil, "missing_info_size" end
    if not position then return nil, "missing_info_world_position" end
    return {
        x = position[1],
        y = position[2],
        width = size[1],
        height = size[2],
    }
end

function PanelLayout.toggle_offset(panel_width, button_width, inset, z)
    panel_width = tonumber(panel_width)
    button_width = tonumber(button_width)
    inset = tonumber(inset) or 0
    if not panel_width or not button_width or panel_width <= 0
            or button_width < 0 then
        return nil
    end
    return { math.max(inset, panel_width - button_width - inset), inset, z or 20 }
end

-- Bind the picker-owned frame constants once while continuing to read their
-- current values at call time. This keeps the public GlowPicker frame contract
-- intact while the pure layout owner constructs all shared frame styles.
function PanelLayout.make_frame_style(style_owner)
    return function(width, height, z, color)
        return {
            texture_size = style_owner.FRAME_TEX_SIZE,
            texture_sizes = style_owner.FRAME_TEX_SIZES,
            color = color or { 255, 255, 255, 255 },
            offset = { 0, 0, z or 3 },
            area_size = { width, height },
        }
    end
end

-- Bind the authored inset once so every persistent toggle uses the same live
-- Information-panel geometry and fail-closed mutation policy.
function PanelLayout.make_toggle_positioner(inset)
    return function(host, widget, button_width, z)
        local layout = PanelLayout.resolve(host)
        if not layout or type(widget) ~= "table" then return false end
        local target = PanelLayout.toggle_offset(
            layout.width, button_width, inset, z or 20)
        if not target then return false end
        widget.offset = widget.offset or { 0, 0, 0 }
        widget.offset[1], widget.offset[2], widget.offset[3] =
            target[1], target[2], target[3]
        return true
    end
end

function PanelLayout.contains(layout, x, y)
    return type(layout) == "table" and _finite_number(x) and _finite_number(y)
        and x >= layout.x and x <= layout.x + layout.width
        and y >= layout.y and y <= layout.y + layout.height
end

-- Vanilla draws the Information contents from _info_widgets independently of
-- the frame in _widgets. Replace only that field for one wrapped draw and
-- restore the exact table before returning or propagating an error.
function PanelLayout.without_native_information(func, host, ...)
    if type(func) ~= "function" or type(host) ~= "table" then
        return false, "invalid_host_draw"
    end
    local native_info_widgets = host._info_widgets
    host._info_widgets = nil
    local results = { pcall(func, host, ...) }
    host._info_widgets = native_info_widgets
    if not results[1] then error(results[2], 0) end
    return true
end

return PanelLayout
