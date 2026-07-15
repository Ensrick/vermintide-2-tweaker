-- Pure setting policy for WT's per-item, per-career CWV availability surface
-- (#391). Engine-free so the setting schema and compatibility behavior are
-- covered by the host Lua 5.1 suite.
local M = {}

function M.master_setting_id(variant_key)
    return "unlock_cwv_variant_" .. variant_key
end

function M.career_setting_id(variant_key, career_name)
    return "unlock_cwv_variant_" .. career_name .. "_" .. variant_key
end

function M.build_widgets(catalog)
    local rows = {}
    for _, variant in ipairs(catalog or {}) do
        local children = {}
        local defaults = nil
        if type(variant.default_careers) == "table" then
            defaults = {}
            for _, career_name in ipairs(variant.default_careers) do
                defaults[career_name] = true
            end
        end
        for _, career_name in ipairs(variant.careers or {}) do
            children[#children + 1] = {
                setting_id = M.career_setting_id(variant.key, career_name),
                type = "checkbox",
                default_value = defaults == nil or defaults[career_name] == true,
            }
        end
        rows[#rows + 1] = {
            -- Preserve #368's shipped per-item key as a master. An existing
            -- false value therefore still disables the whole item, while an
            -- existing true value reveals independent default-on children.
            setting_id = M.master_setting_id(variant.key),
            type = "checkbox",
            default_value = true,
            sub_widgets = children,
        }
    end
    return rows
end

function M.is_enabled(get_setting, variant_key, career_name)
    if type(get_setting) ~= "function" then return false end
    if get_setting(M.master_setting_id(variant_key)) ~= true then return false end
    return get_setting(M.career_setting_id(variant_key, career_name)) == true
end

return M
