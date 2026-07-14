-- Engine-free definition/content policy for the #528 CKC OptionsView checkbox.
local P = {}

function P.prepare_definition(definition, setting_name, active)
    if not active or type(definition) ~= "table" then return nil end
    for i = 1, #definition do
        local element = definition[i]
        if type(element) == "table" and element.setting_name == setting_name then
            local token = { element = element, widget_type = element.widget_type }
            element.widget_type = "checkbox"
            return token
        end
    end
end

function P.restore_definition(token)
    if type(token) == "table" and type(token.element) == "table" then
        token.element.widget_type = token.widget_type
    end
end

function P.checkbox_setup(enabled, label)
    return enabled == true, label, true
end

function P.checkbox_value(content)
    return type(content) == "table" and content.flag == true
end

function P.restore_checkbox(content, enabled)
    if type(content) == "table" then content.flag = enabled == true end
end

return P
