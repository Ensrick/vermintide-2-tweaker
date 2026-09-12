-- Historical prose is legal: mod:get("enable_debug_logging") was retired.
local prose = 'mod:set("enable_debug_logging", false) is not executable'
local long_prose = [=[
mod:get("enable_debug_logging") is historical prose, not a call.
]=]
--[==[
mod:set("enable_debug_logging", false) is a historical block comment.
]==]
local escaped_prose = "Quoted \"mod:get('enable_debug_logging')\" is not a call."
local dot_prose = 'mod.get(mod, "enable_debug_logging") is not executable'
-- mod.set(mod, "enable_debug_logging", false) is historical prose.
local marker_prose = 'mod:get(@VT_RETIRED_DEBUG_KEY@) is not executable'

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

local function retired_write(mod)
    mod:set("enable_debug_logging", false)
    mod:set(
        'enable_debug_logging', false)
    mod:get([=[enable_debug_logging]=])
    local prose_prefix = "-- history"; mod:get("enable_debug_logging")
    return prose_prefix
end

local function retired_dot_calls(mod, owners)
    mod.get(mod, "enable_debug_logging")
    mod.set(mod, 'enable_debug_logging', false)
    mod.get(
        mod,
        "enable_debug_logging")
    mod.set(owners.gt, [=[enable_debug_logging]=], false)
end

local function retired_literal_calls(mod)
    mod:get "enable_debug_logging"
    mod:get [=[enable_debug_logging]=]
end

local function safe_identifier_call(mod)
    -- enable_debug_logging is historical prose; this identifier is legal Lua.
    local __VT_RETIRED_DEBUG_KEY__ = "safe_key"
    return mod:get(__VT_RETIRED_DEBUG_KEY__)
end

return retired_read, retired_widget, retired_multiline_read, retired_multiline_widget,
    retired_write, retired_dot_calls, retired_literal_calls, safe_identifier_call,
    prose, long_prose, escaped_prose, dot_prose, marker_prose
