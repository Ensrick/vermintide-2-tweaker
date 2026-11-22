-- qa/runtime/_stub/index_script.lua: header fields of rig scripts for qa/runtime/index.json (WP-H-11 step 3).
--
-- Usage: lua5.1 index_script.lua <list file>
-- Each list line is a script path. Each script's top level runs in the same engine-free sandbox as check_script.lua
-- (only Lua's own string, table and math and the basic functions). Prints one line per script:
--   OK<TAB><path><TAB><issue><TAB><class><TAB><not_covered, list items joined with " | ", or empty>
-- or "ERROR<TAB><path><TAB><problem>". Tabs and newlines inside not_covered become spaces. Reads only.
local list_path = arg[1]

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
            error("top level reads global '" .. tostring(key) .. "'", 2)
        end,
        __newindex = function(_, key)
            error("top level writes global '" .. tostring(key) .. "'", 2)
        end,
    })
end

local function flat(text)
    return (tostring(text):gsub("[\t\r\n]+", " "))
end

for path in io.lines(list_path) do
    if path ~= "" then
        local file = io.open(path, "rb")
        local source = file and file:read("*a")
        if file then file:close() end
        local chunk, err = source and loadstring(source, "=" .. path)
        local def
        if chunk then
            setfenv(chunk, sandbox())
            local ran, value = pcall(chunk)
            if ran then def = value else err = value end
        end
        if type(def) ~= "table" then
            io.write("ERROR\t", path, "\t", flat(err or "does not return a table"), "\n")
        else
            local nc = def.not_covered
            if type(nc) == "table" then
                local parts = {}
                for _, v in ipairs(nc) do parts[#parts + 1] = flat(v) end
                nc = table.concat(parts, " | ")
            elseif nc ~= nil then
                nc = flat(nc)
            end
            io.write("OK\t", path, "\t", tostring(def.issue), "\t", tostring(def.class), "\t", nc or "", "\n")
        end
    end
end
