-- Engine-free target policy for Issue #400.

local M = {}

M.TEMPLATE = "staff_flamethrower_template"
M.NATIVE_CAREER_PREFIX = "bw_"

function M.is_target(career_name, template_name)
    return type(career_name) == "string"
        and type(template_name) == "string"
        and template_name == M.TEMPLATE
        and career_name:sub(1, #M.NATIVE_CAREER_PREFIX) ~= M.NATIVE_CAREER_PREFIX
end

return M
