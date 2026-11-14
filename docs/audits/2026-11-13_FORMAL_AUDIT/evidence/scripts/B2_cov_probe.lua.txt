-- B2 audit probe: runs the repo's unmodified qa/lua/run.lua under a line hook and
-- dumps which source lines executed. Writes ONLY to the audit workspace (arg[3]).
local runner, inventory, out_path = arg[1], arg[2], arg[3]
local hits = {}
local getinfo = debug.getinfo
local function hook(_, line)
    local s = getinfo(2, "S").source
    local t = hits[s]
    if not t then t = {}; hits[s] = t end
    t[line] = true
end
local native_exit = os.exit
os.exit = function(code)
    debug.sethook()
    local f = assert(io.open(out_path, "wb"))
    for source, lines in pairs(hits) do
        local list = {}
        for line in pairs(lines) do list[#list + 1] = line end
        table.sort(list)
        local name = source
        if #name > 300 then name = name:sub(1, 300):gsub("[\r\n\t]", " ") .. "...<inline-chunk>" end
        name = name:gsub("[\r\n\t]", " ")
        f:write(name, "\t", #list, "\t", table.concat(list, ","), "\n")
    end
    f:close()
    os.exit = native_exit
    native_exit(code)
end
arg[0], arg[1], arg[2], arg[3] = runner, "--suite-manifest", inventory, nil
debug.sethook(hook, "l")
dofile(runner)
