local M = {}

local function _channel(value)
    value = tonumber(value) or 0
    if value < 0 then value = 0 end
    if value > 255 then value = 255 end
    return math.floor(value + 0.5)
end

-- A badge represents only a committed, visibly active override. Rune glows
-- have one authored colour. Magic glows have three independently coloured
-- components, so collapse them into one deterministic intensity-weighted
-- swatch without allowing native shader brightness to blow out the UI tint.
function M.color(state)
    if type(state) ~= "table" or state.disabled then return nil end
    local rune = state.rune
    if type(rune) == "table" and (tonumber(rune.intensity) or 0) > 0 then
        return { 255, _channel(rune.r), _channel(rune.g), _channel(rune.b) }
    end

    local red, green, blue, total = 0, 0, 0, 0
    for _, key in ipairs({ "lower", "upper", "dots" }) do
        local component = state[key]
        local weight = type(component) == "table"
            and math.max(tonumber(component.intensity) or 0, 0) or 0
        if weight > 0 then
            red = red + _channel(component.r) * weight
            green = green + _channel(component.g) * weight
            blue = blue + _channel(component.b) * weight
            total = total + weight
        end
    end
    if total <= 0 then return nil end
    return {
        255,
        _channel(red / total),
        _channel(green / total),
        _channel(blue / total),
    }
end

function M.button(family, open_for_identity)
    local available = family == "rune" or family == "magic"
    return {
        available = available,
        selected = available and open_for_identity == true,
    }
end

-- Only the weapon-illusion selector owns this exact definition shape. This
-- classifier lets the global UIWidget.init pre-hook enrich that definition
-- without catching unrelated widgets that also happen to draw an icon.
function M.is_illusion_definition(widget_definition)
    if type(widget_definition) ~= "table"
            or widget_definition.scenegraph_id ~= "illusions_root" then
        return false
    end

    local element = widget_definition.element
    local content = widget_definition.content
    local style = widget_definition.style
    if type(element) ~= "table" or element.pass_data ~= nil
            or type(element.passes) ~= "table"
            or type(content) ~= "table"
            or type(content.button_hotspot) ~= "table"
            or type(style) ~= "table"
            or type(style.icon_texture) ~= "table" then
        return false
    end

    for _, pass in ipairs(element.passes) do
        if type(pass) == "table" and pass.pass_type == "texture"
                and pass.style_id == "icon_texture"
                and pass.texture_id == "icon_texture" then
            return true
        end
    end

    return false
end

return M
