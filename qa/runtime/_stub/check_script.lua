-- qa/runtime/_stub/check_script.lua: Lua half of qa/check_runtime_scripts.ps1 (WP-H-13).
--
-- Usage: lua5.1 check_script.lua <qa/runtime/_stub/T.lua> <list file>
-- Each list line is "<script path>\t<issue number from the file name, or ->". For every script it checks that
-- the file parses; that its top level runs with no engine access (only Lua's own string, table and math and the
-- basic functions are visible); that it returns a table with run (function), arena, issue (number, 0 for none),
-- class "R", timeout (seconds) and an optional not_covered; that the issue field equals the number in the file
-- name; and that every T.<name> it uses exists in the stub. Prints "OK <path>" or "ERROR <path>: <problem>"
-- lines and exits 2 when any script has a problem. Shape only: nothing here runs a case.
local stub_path, list_path = arg[1], arg[2]
local new_T = assert(dofile(stub_path), "stub must return a constructor")
local STUB = new_T()

local BASIC = {
    "assert", "error", "ipairs", "next", "pairs", "pcall", "rawequal", "rawget", "rawset", "select",
    "setmetatable", "getmetatable", "tonumber", "tostring", "type", "unpack", "xpcall",
}

local function sandbox()
    local env = { string = string, table = table, math = math }
    for _, name in ipairs(BASIC) do
        env[name] = _G[name]
    end
    return setmetatable(env, {
        __index = function(_, key)
            error("top level reads global '" .. tostring(key) .. "' (engine access belongs inside run)", 2)
        end,
        __newindex = function(_, key)
            error("top level writes global '" .. tostring(key) .. "'", 2)
        end,
    })
end

local ARENAS = { boot = true, keep = true, deus = true, coop = true }

local function valid_arena(arena)
    return type(arena) == "string" and (ARENAS[arena] or arena:match("^mission:[%w_]+$") or arena:match("^level:[%w_]+$")) and true or false
end

local function strip_comments(source)
    source = source:gsub("%-%-%[(=*)%[.-%]%1%]", "")
    return (source:gsub("%-%-[^\n]*", ""))
end

local function check(path, expected_issue)
    local problems = {}
    local function problem(text)
        problems[#problems + 1] = text
    end

    local file = io.open(path, "rb")
    if not file then
        return { "cannot read the file" }
    end
    local source = file:read("*a")
    file:close()

    local chunk, parse_error = loadstring(source, "=" .. path)
    if not chunk then
        return { "does not parse: " .. tostring(parse_error) }
    end

    setfenv(chunk, sandbox())
    local ran, def = pcall(chunk)
    if not ran then
        return { tostring(def) }
    end
    if type(def) ~= "table" then
        return { "must return a table, returned " .. type(def) }
    end

    if type(def.run) ~= "function" then problem("field run must be a function") end
    if not valid_arena(def.arena) then
        problem("field arena must be boot, keep, deus, coop, mission:<level_key> or level:<level_key> (got " .. tostring(def.arena) .. ")")
    end
    if type(def.issue) ~= "number" or def.issue < 0 or def.issue % 1 ~= 0 then
        problem("field issue must be an issue number, or 0 for none (got " .. tostring(def.issue) .. ")")
    end
    if def.class ~= "R" then problem("field class must be \"R\" (got " .. tostring(def.class) .. ")") end
    if type(def.timeout) ~= "number" or def.timeout <= 0 then
        problem("field timeout must be a positive number of seconds (got " .. tostring(def.timeout) .. ")")
    end
    if def.not_covered ~= nil then
        local ok = type(def.not_covered) == "string"
        if type(def.not_covered) == "table" then
            ok = true
            for _, value in pairs(def.not_covered) do
                if type(value) ~= "string" then ok = false end
            end
        end
        if not ok then problem("field not_covered must be a string or a list of strings") end
    end
    if expected_issue and def.issue ~= expected_issue then
        problem("file name says issue " .. expected_issue .. " but the issue field is " .. tostring(def.issue))
    end

    local unknown, seen = {}, {}
    for name in strip_comments(source):gmatch("%f[%w_]T%.([%a_][%w_]*)") do
        if STUB[name] == nil and not seen[name] then
            seen[name] = true
            unknown[#unknown + 1] = "T." .. name
        end
    end
    if #unknown > 0 then
        problem("unknown helper " .. table.concat(unknown, ", ") .. " (not in qa/runtime/_stub/T.lua)")
    end

    return problems
end

local failed, total = 0, 0
for line in io.lines(list_path) do
    if line ~= "" then
        local path, issue = line:match("^(.-)\t(.*)$")
        path = path or line
        total = total + 1
        local problems = check(path, tonumber(issue))
        if #problems == 0 then
            io.write("OK ", path, "\n")
        else
            failed = failed + 1
            for _, text in ipairs(problems) do
                io.write("ERROR ", path, ": ", text, "\n")
            end
        end
    end
end
io.write(string.format("SUMMARY scripts=%d failed=%d\n", total, failed))
os.exit(failed > 0 and 2 or 0)
