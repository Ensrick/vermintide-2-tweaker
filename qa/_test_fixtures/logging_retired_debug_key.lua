-- Historical prose is legal: mod:get("enable_debug_logging") was retired.
local prose = 'mod:set("enable_debug_logging", false) is not executable'

local function retired_read(mod)
    return mod:get("enable_debug_logging")
end

local retired_widget = {
    setting_id = "enable_debug_logging",
    type = "checkbox",
}

local function retired_multiline_read(mod)
    return mod:get(
        "enable_debug_logging"
    )
end

local retired_multiline_widget = {
    setting_id =
        "enable_debug_logging",
    type = "checkbox",
}

return retired_read, retired_widget, retired_multiline_read, retired_multiline_widget, prose
