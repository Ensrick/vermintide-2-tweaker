-- Fixture for check_logging.ps1 -SelfTest -- Issue #1637 printf-mutation shapes.
-- Every runtime write to the global/environment printf below is a hard error;
-- prose, comments, reads, calls and table fields stay legal.

-- Historical prose is legal: rawset(_G, "printf", capture) in a comment is not a call.
local prose = 'rawset(_G, "printf", capture) is historical prose'
local long_prose = [=[
_G.printf = capture is historical prose
]=]
--[==[
setfenv(1, env) in a block comment is not executable.
]==]
local escaped_prose = "Quoted \"_G.printf = x\" is not a write."

-- Sanctioned reads and calls: zero findings.
local real_printf = rawget(_G, "printf")
pcall(printf, "[fx:1637] miss career=%s", "probe")
local has_env = type(getfenv) == "function"
local fn_env = getfenv(some_function)
local field_table = { printf = printf }
local nested_field = { logger = { printf = real_printf } }
if _G.printf == nil or _G.printf ~= real_printf then
    pcall(printf, "[fx] %s", tostring(real_printf))
end

local function bad_direct()
    _G.printf = function() end
    _ENV.printf = real_printf
    _G["printf"] = real_printf
    _G[ [[printf]] ] = real_printf
end

local function bad_rawset()
    rawset(_G, "printf", function(fmt, ...) end)
    rawset(_G, 'printf', real_printf)
    rawset(
        _G,
        "printf",
        real_printf)
    rawset(getfenv(1), "printf", real_printf)
end

local function bad_hook(mod)
    mod:hook(_G, "printf", function(func, ...) end)
    mod:hook_safe(_G, "printf", function() end)
end

local function bad_env(chunk, env)
    setfenv(chunk, env)
    debug.setfenv(chunk, env)
    pcall(setfenv, chunk, env)
    local ambient = getfenv()
    local main_thread = getfenv(0)
    getfenv(1).printf = real_printf
    getfenv(2)["printf"] = real_printf
end

return { bad_direct = bad_direct, bad_rawset = bad_rawset, bad_hook = bad_hook, bad_env = bad_env }
