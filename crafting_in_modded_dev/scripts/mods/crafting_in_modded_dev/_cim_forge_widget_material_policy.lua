-- _cim_forge_widget_material_policy.lua -- dynamic Athanor widget closure.
--
-- The weave weapon window creates its stat widgets after create_ui_elements
-- and stores them under `_scrollbars.<name>.list_widgets`.  Mission Guis do not
-- necessarily own the Keep-only raw materials referenced by those widgets.
-- This pure policy disables only texture passes whose exact target renderer
-- cannot prove the material; text, hotspots, and safe textures remain intact.
--
-- Owned by: crafting_in_modded_dev.lua. Engine-free; returns a policy table.

local M = {}

local function _pack(...)
    local values = { ... }
    values.n = select("#", ...)
    return values
end

-- Runs a post-producer guard without collapsing nil or multiple vanilla
-- returns. Errors still propagate from the producer exactly as before.
function M.call_then(call, after, ...)
    local values = _pack(call(...))
    after()
    return unpack(values, 1, values.n)
end

local function _never()
    return false
end

local function _shallow_copy(source)
    local result = {}
    for key, value in pairs(source or {}) do result[key] = value end
    return result
end

local function _texture_name(value)
    if type(value) == "table" then
        value = value.texture_id or value.texture or value.material
    end
    if type(value) == "string" and value ~= "" then return value end
    return nil
end

local function _pass_content(widget, pass)
    local content = type(widget) == "table" and widget.content
    if type(content) ~= "table" then return nil end
    if type(pass.content_id) == "string" then
        content = content[pass.content_id]
    end
    return type(content) == "table" and content or nil
end

local function _pass_texture(widget, pass)
    if type(pass) ~= "table" or type(pass.pass_type) ~= "string"
            or not pass.pass_type:find("texture", 1, true) then
        return nil
    end
    local content = _pass_content(widget, pass)
    local texture_key = pass.texture_id or "texture_id"
    return _texture_name(content and content[texture_key])
end

local function _pass_flags(widget, pass)
    local style = type(widget) == "table" and widget.style
    style = type(style) == "table" and style[pass.style_id]
    style = type(style) == "table" and style or {}
    return {
        masked = style.masked == true,
        saturated = style.saturated == true,
        point_sample = style.point_sample == true,
        viewport_mask = style.viewport_mask == true,
        retained = style.retained_id ~= nil and style.retained_id ~= false,
    }
end

-- Mutates only unsafe pass definitions on the supplied, already-instantiated
-- widgets. `has_texture(texture_name, flags)` must prove the exact Gui material
-- that the pass would draw. Errors and unavailable renderers fail closed.
function M.sanitize_widgets(widgets, has_texture)
    local report = {
        widgets_scanned = 0,
        texture_passes = 0,
        verified = 0,
        suppressed = 0,
        materials = {},
    }
    if type(widgets) ~= "table" or type(has_texture) ~= "function" then
        return report
    end

    local material_seen = {}
    for i = 1, #widgets do
        local widget = widgets[i]
        local passes = type(widget) == "table" and widget.element
            and widget.element.passes
        report.widgets_scanned = report.widgets_scanned + 1
        if type(passes) == "table" then
            local copied_pass_array = false
            for j = 1, #passes do
                local pass = passes[j]
                local texture = _pass_texture(widget, pass)
                if texture then
                    report.texture_passes = report.texture_passes + 1
                    local flags = _pass_flags(widget, pass)
                    local ok, safe = pcall(has_texture, texture, flags)
                    if ok and safe == true then
                        report.verified = report.verified + 1
                    else
                        if pass._cim83_material_suppressed ~= true then
                            -- UIWidget.init clones content/style but retains the
                            -- definition's pass array. Some factories reuse one
                            -- definition across multiple widget instances. Clone
                            -- both the array and the pass before mutation so one
                            -- unsafe instance cannot hide a safe sibling or alter
                            -- a later Keep widget built from the same definition.
                            if not copied_pass_array then
                                passes = _shallow_copy(passes)
                                widget.element.passes = passes
                                copied_pass_array = true
                            end
                            pass = _shallow_copy(pass)
                            passes[j] = pass
                            pass._cim83_previous_content_check = pass.content_check_function
                            pass.content_check_function = _never
                            pass._cim83_material_suppressed = true
                            pass._cim83_material = texture
                            report.suppressed = report.suppressed + 1
                        end
                        if not material_seen[texture] then
                            material_seen[texture] = true
                            report.materials[#report.materials + 1] = texture
                        end
                    end
                end
            end
        end
    end
    return report
end

return M
