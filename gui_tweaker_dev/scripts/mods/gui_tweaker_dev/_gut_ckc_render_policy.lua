-- #528: make the borrowed Options checkbox safe on the renderer that draws the
-- gameplay list. The native local-offset pass writes raw checkbox_* materials,
-- which are not resident there; retain its flag toggle but normalize the visual
-- to an atlas-backed checked mark and a material-free border.
local M = {}

M.SAFE_CHECKMARK = "matchmaking_checkbox"

function M.harden(widget)
    if type(widget) ~= "table" then return false end
    if widget.__gut_ckc_renderer_safe then return true end
    local content = widget.content
    local style = widget.style
    local passes = widget.element and widget.element.passes
    if type(content) ~= "table" or type(style) ~= "table" or type(passes) ~= "table" then
        return false
    end

    local checkbox_pass
    for _, pass in ipairs(passes) do
        if pass.pass_type == "local_offset" and type(pass.offset_function) == "function" then
            local original = pass.offset_function
            pass.offset_function = function(ui_scenegraph, ui_style, ui_content, ui_renderer)
                original(ui_scenegraph, ui_style, ui_content, ui_renderer)
                ui_content.checkbox = M.SAFE_CHECKMARK
            end
        elseif pass.pass_type == "texture" and pass.texture_id == "checkbox" then
            checkbox_pass = pass
        end
    end
    if not checkbox_pass or type(style.checkbox) ~= "table" then return false end

    content.checkbox = M.SAFE_CHECKMARK
    checkbox_pass.content_check_function = function(c) return c.flag == true end
    style.checkbox.color = style.checkbox.color or { 255, 255, 255, 255 }
    style.checkbox.thickness = 1
    passes[#passes + 1] = { pass_type = "border", style_id = "checkbox" }
    widget.__gut_ckc_renderer_safe = true
    return true
end

return M
