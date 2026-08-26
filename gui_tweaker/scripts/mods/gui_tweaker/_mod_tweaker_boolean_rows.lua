-- Native-style boolean row factories for Mod Tweaker (#446).
-- The definitions owner injects shared geometry/render helpers once; this
-- focused module owns checkbox-steppers and mutually-exclusive radio rows.

local M = {}

function M.new(env)
    local UIWidget = assert(env.UIWidget, "boolean rows require UIWidget")
    local Colors = assert(env.Colors, "boolean rows require Colors")
    local Localize = assert(env.Localize, "boolean rows require Localize")
    local ROW_H, ROW_W = env.row_h, env.row_w
    local INDENT_PER_DEPTH = env.indent_per_depth
    local LABEL_BASE_X, DEC_ARROW_X = env.label_base_x, env.dec_arrow_x
    local INC_ARROW_X_STEPPER = env.inc_arrow_x_stepper
    local VALUE_X_STEPPER = env.value_x_stepper
    local ARROW_HOTSPOT_W, LIST_SG = env.arrow_hotspot_w, env.list_sg
    local text_style = env.text_style
    local append_arrows = env.append_arrows
    local append_highlight = env.append_highlight
    local append_separator = env.append_separator

    local function on_off_text()
        local function localized(key, fallback)
            local ok, value = pcall(Localize, key)
            if ok and type(value) == "string" and value ~= ""
                    and not string.find(value, "^<") then
                return value
            end
            return fallback
        end
        return localized("menu_settings_on", "ON"), localized("menu_settings_off", "OFF")
    end

    local function create_checkbox(text, base_offset, depth)
        local y = base_offset[2] - ROW_H
        base_offset[2] = y
        local cy = y + ROW_H / 2
        local indent = INDENT_PER_DEPTH * (depth or 0)
        local value_width = 90
        local value_x = VALUE_X_STEPPER - value_width / 2
        local on_text, off_text = on_off_text()

        local passes = {
            { pass_type = "hotspot", content_id = "hotspot", style_id = "hotspot" },
            { pass_type = "text", style_id = "label", text_id = "label" },
            { pass_type = "text", style_id = "on_text", text_id = "on_text",
                content_check_function = function(content) return content.flag end },
            { pass_type = "text", style_id = "off_text", text_id = "off_text",
                content_check_function = function(content) return not content.flag end },
        }
        local style = {
            hotspot = { size = { ROW_W, ROW_H }, offset = { 0, y, 0 } },
            label = text_style(LABEL_BASE_X + indent, y,
                DEC_ARROW_X - LABEL_BASE_X - 12 - indent, 16),
            on_text = text_style(value_x, y, value_width, 16,
                Colors.get_color_table_with_alpha("font_default", 255), "center"),
            off_text = text_style(value_x, y, value_width, 16,
                Colors.get_color_table_with_alpha("font_default", 255), "center"),
        }
        local content = {
            flag = false,
            hotspot = {},
            label = text,
            on_text = on_text,
            off_text = off_text,
            dec = {},
            inc = {},
        }
        passes[#passes + 1] = {
            pass_type = "hotspot", content_id = "dec", style_id = "dec",
        }
        passes[#passes + 1] = {
            pass_type = "hotspot", content_id = "inc", style_id = "inc",
        }
        style.dec = {
            size = { ARROW_HOTSPOT_W, ROW_H },
            offset = { DEC_ARROW_X, y, 0 },
        }
        style.inc = {
            size = { ARROW_HOTSPOT_W, ROW_H },
            offset = { VALUE_X_STEPPER, y, 0 },
        }
        append_arrows(passes, style, content, DEC_ARROW_X, INC_ARROW_X_STEPPER, cy)
        append_highlight(passes, style, content, y)
        append_separator(passes, style, y)

        return UIWidget.init({
            scenegraph_id = LIST_SG,
            element = { passes = passes },
            content = content,
            style = style,
            offset = { 0, 0, 0 },
        })
    end

    local function create_radio(text, base_offset, depth)
        local y = base_offset[2] - ROW_H
        base_offset[2] = y
        local indent = INDENT_PER_DEPTH * (depth or 0)
        local bubble_x = LABEL_BASE_X + indent
        local bubble_y = y + math.floor((ROW_H - 18) / 2)
        local label_x = bubble_x + 30
        local ring = Colors.get_color_table_with_alpha("font_default", 220)
        local fill = Colors.get_color_table_with_alpha("font_default", 255)

        local passes = {
            { pass_type = "hotspot", content_id = "hotspot", style_id = "hotspot" },
            { pass_type = "text", style_id = "label", text_id = "label" },
        }
        local style = {
            hotspot = { size = { ROW_W, ROW_H }, offset = { 0, y, 0 } },
            label = text_style(label_x, y, DEC_ARROW_X - label_x - 12, 16),
        }
        local content = { hotspot = {}, label = text, selected = false }
        local segments = {
            { "radio_top", bubble_x + 4, bubble_y + 16, 10, 2 },
            { "radio_bottom", bubble_x + 4, bubble_y, 10, 2 },
            { "radio_left", bubble_x, bubble_y + 4, 2, 10 },
            { "radio_right", bubble_x + 16, bubble_y + 4, 2, 10 },
            { "radio_bl", bubble_x + 2, bubble_y + 2, 2, 2 },
            { "radio_br", bubble_x + 14, bubble_y + 2, 2, 2 },
            { "radio_tl", bubble_x + 2, bubble_y + 14, 2, 2 },
            { "radio_tr", bubble_x + 14, bubble_y + 14, 2, 2 },
        }
        for i = 1, #segments do
            local segment = segments[i]
            passes[#passes + 1] = { pass_type = "rect", style_id = segment[1] }
            style[segment[1]] = {
                offset = { segment[2], segment[3], 3 },
                size = { segment[4], segment[5] },
                color = ring,
            }
        end
        passes[#passes + 1] = {
            pass_type = "rect",
            style_id = "radio_fill",
            content_check_function = function(row) return row.selected end,
        }
        style.radio_fill = {
            offset = { bubble_x + 5, bubble_y + 5, 4 },
            size = { 8, 8 },
            color = fill,
        }
        append_highlight(passes, style, content, y)
        append_separator(passes, style, y)

        return UIWidget.init({
            scenegraph_id = LIST_SG,
            element = { passes = passes },
            content = content,
            style = style,
            offset = { 0, 0, 0 },
        })
    end

    return { create_checkbox = create_checkbox, create_radio = create_radio }
end

return M
