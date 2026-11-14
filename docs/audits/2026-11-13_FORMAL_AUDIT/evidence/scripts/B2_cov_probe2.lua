-- B2 audit probe v2: line coverage of the repo's unmodified qa/lua/run.lua, sharded.
-- Every suite still REGISTERS (so module loads done at registration are covered in every
-- shard); only test BODIES outside this shard are replaced by no-ops. Writes only to arg[3].
local runner, inventory, out_path, shard, shards = arg[1], arg[2], arg[3], tonumber(arg[4]), tonumber(arg[5])
local script_path = runner:gsub("\\", "/")
local lua_root = script_path:match("^(.*)/run%.lua$")
package.path = table.concat({ lua_root .. "/?.lua", lua_root .. "/tests/?.lua", package.path }, ";")

local H = require("harness")
local orig_test, orig_test_if = H.test, H.test_if
local ordinal, kept = 0, 0
local function noop() end
H.test = function(name, body)
    ordinal = ordinal + 1
    if ordinal % shards == shard then kept = kept + 1; return orig_test(name, body) end
    return orig_test(name, noop)
end
H.test_if = function(condition, name, body, reason)
    ordinal = ordinal + 1
    if ordinal % shards == shard then kept = kept + 1; return orig_test_if(condition, name, body, reason) end
    return orig_test_if(condition, name, noop, reason)
end

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
    f:write("#shard\t", tostring(shard), "/", tostring(shards), "\tkept_cases\t", tostring(kept), "\tregistered\t", tostring(ordinal), "\texit\t", tostring(code), "\n")
    for source, lines in pairs(hits) do
        local list = {}
        for line in pairs(lines) do list[#list + 1] = line end
        table.sort(list)
        local name = source
        if #name > 300 then name = name:sub(1, 120) .. "...<inline-chunk len=" .. #source .. ">" end
        name = name:gsub("[\r\n\t]", " ")
        f:write(name, "\t", #list, "\t", table.concat(list, ","), "\n")
    end
    f:close()
    os.exit = native_exit
    native_exit(code)
end
arg[0], arg[1], arg[2], arg[3], arg[4], arg[5] = runner, "--suite-manifest", inventory, nil, nil, nil
debug.sethook(hook, "l")
dofile(runner)
