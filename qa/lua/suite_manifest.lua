-- #1700: compare the host-discovered suite inventory with modules actually
-- completed while registering the explicit runner. Importing a registration
-- function is not coverage until it returns successfully. Pure Lua
-- policy; PowerShell owns directory discovery and the temporary manifest.
local M = {}
local MAX_BYTES, MAX_SUITES = 1048576, 4096

function M.parse(source)
    if type(source) ~= "string" or #source == 0 or #source > MAX_BYTES then
        return nil, "suite inventory is empty or exceeds 1 MiB"
    end
    source = source:gsub("\r\n", "\n")
    if source:sub(-1) ~= "\n" then return nil, "suite inventory must end with LF" end
    local names, seen = {}, {}
    for name in source:gmatch("(.-)\n") do
        if #name > 256 or not name:match("^test_[a-z0-9_]+$") then
            return nil, "invalid suite inventory name: " .. name
        end
        if seen[name] then return nil, "duplicate suite inventory name: " .. name end
        seen[name] = true
        names[#names + 1] = name
        if #names > MAX_SUITES then return nil, "suite inventory exceeds 4096 entries" end
    end
    return names
end

function M.read(path)
    if type(path) ~= "string" or path == "" then return nil, "suite inventory path required" end
    local file, reason = io.open(path, "rb")
    if not file then return nil, "cannot read suite inventory: " .. tostring(reason) end
    local source = file:read(MAX_BYTES + 1)
    file:close()
    return M.parse(source)
end

function M.track(require_function)
    assert(type(require_function) == "function", "require function required")
    local completed, wrappers = {}, {}
    local function tracked_require(name)
        local registration = require_function(name)
        if type(name) ~= "string" or not name:match("^test_[a-z0-9_]+$")
                or type(registration) ~= "function" then return registration end
        local cached = wrappers[name]
        if cached and cached.registration == registration then return cached.wrapper end
        local function complete(...)
            completed[name] = true
            return ...
        end
        local function invoke(...)
            return complete(registration(...))
        end
        wrappers[name] = { registration = registration, wrapper = invoke }
        return invoke
    end
    return tracked_require, completed
end

function M.audit(names, completed)
    if type(names) ~= "table" or #names == 0 then return "suite inventory required" end
    if type(completed) ~= "table" then return "completed-registration inventory required" end
    local missing = {}
    for _, name in ipairs(names) do
        if rawget(completed, name) ~= true then missing[#missing + 1] = name end
    end
    if #missing > 0 then return "unreached test suites: " .. table.concat(missing, ", ") end
    return nil
end

function M.validate_explicit(suites)
    if type(suites) ~= "table" or #suites == 0 then return "explicit suite list required" end
    local seen = {}
    for _, name in ipairs(suites) do
        if type(name) ~= "string" or not name:match("^test_[a-z0-9_]+$") then
            return "invalid explicit suite name"
        end
        if seen[name] then return "duplicate explicit suite: " .. name end
        seen[name] = true
    end
    return nil
end

return M
