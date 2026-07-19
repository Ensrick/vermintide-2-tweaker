-- Pure geometry for the in-context glow sliders.
--
-- `held_function` receives the style selected by its pass `style_id`, not the
-- widget's aggregate style table.  Keeping the coordinate math here prevents
-- the rendered track, hit target, value mapping, and thumb travel from deriving
-- four subtly different rectangles.

local Geometry = {}

local function _number(value, fallback)
    local converted = tonumber(value)
    if converted == nil then return fallback end
    return converted
end

local function _component(vector, index, fallback)
    if type(vector) ~= "table" then return fallback end
    return _number(vector[index], fallback)
end

local function _clamp01(value)
    value = _number(value, 0)
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

function Geometry.value_from_cursor(cursor_x, scenegraph_world_x, track_style)
    if type(track_style) ~= "table" then return nil end

    local width = _component(track_style.size, 1, 0)
    if width <= 0 then return nil end

    local left = _number(scenegraph_world_x, 0)
        + _component(track_style.offset, 1, 0)

    return _clamp01((_number(cursor_x, left) - left) / width)
end


function Geometry.thumb_left(track_style, normalized_value, thumb_width)
    if type(track_style) ~= "table" then return nil end

    local width = _component(track_style.size, 1, 0)
    if width <= 0 then return nil end

    local left = _component(track_style.offset, 1, 0)
    local half_thumb = math.max(_number(thumb_width, 0), 0) * 0.5

    -- The thumb's centre, not its left edge, represents the selected value.
    return left + width * _clamp01(normalized_value) - half_thumb
end


function Geometry.hotspot_style(track_style, padding)
    if type(track_style) ~= "table" then return nil end

    padding = math.max(_number(padding, 0), 0)
    local width = math.max(_component(track_style.size, 1, 0), 0)
    local height = math.max(_component(track_style.size, 2, 0), 0)
    local left = _component(track_style.offset, 1, 0)
    local bottom = _component(track_style.offset, 2, 0)

    return {
        size = { width + padding * 2, height + padding * 2 },
        offset = { left - padding, bottom - padding, 0 },
    }
end


return Geometry
