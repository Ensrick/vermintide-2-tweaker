-- B2 audit experiment: can real vanilla VT2 data tables load in plain PUC Lua 5.1.5
-- with stubbed engine globals? Read-only against the decompiled source. No repo writes.
--
-- usage: lua5.1 probe.lua <decompile_root> <stubs.lua> <target module> [...]
--   each target is a require-style path, e.g. scripts/settings/equipment/item_master_list
local root, stubs_path = arg[1], arg[2]
local targets = {}
for i = 3, #arg do targets[#targets + 1] = arg[i] end

local P = { loaded = {}, order = {}, missing_modules = {}, nil_globals = {}, stub_hits = {}, stub_names = {} }
_G.B2_PROBE = P
P.root = root

local function read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    if s:sub(1, 3) == "\239\187\191" then s = s:sub(4) end -- UTF-8 BOM (PUC 5.1 loadfile rejects it)
    return s
end

-- Engine semantics: require() keys package.loaded by slash path and keeps
-- package.load_order (used by foundation/scripts/util/local_require.lua).
package.load_order = {}
local function load_module(name, force)
    if not force and package.loaded[name] ~= nil then return package.loaded[name] end
    local src = read(root .. "/" .. name .. ".lua")
    if not src then
        P.missing_modules[name] = true
        error("B2: module not found in decompile: " .. name, 0)
    end
    local chunk, err = loadstring(src, "@" .. name .. ".lua")
    if not chunk then error("B2: PARSE ERROR " .. tostring(err), 0) end
    if not force then package.loaded[name] = true end -- cycle guard (native require uses a sentinel too)
    package.load_order[#package.load_order + 1] = name
    P.order[#P.order + 1] = name
    local ok, result = xpcall(chunk, function(e) P.first_trace = P.first_trace or debug.traceback(tostring(e), 2); return e end)
    if not ok then
        if not force then package.loaded[name] = nil end
        P.failed = P.failed or {}
        if not P.failed[name] then P.failed[name] = tostring(result); P.first_failure = P.first_failure or (name .. ": " .. tostring(result)) end
        error(result, 0)
    end
    if not force and result ~= nil then package.loaded[name] = result end
    if force then return result end
    return package.loaded[name]
end

local native_require = require
local native_loadfile = loadfile
function require(name)
    if type(name) == "string" and (name:find("/", 1, true)) then return load_module(name, false) end
    if type(name) == "string" then
        local as_path = name:gsub("%.", "/")
        local f = io.open(root .. "/" .. as_path .. ".lua", "rb")
        if f then f:close(); return load_module(as_path, false) end
    end
    return native_require(name)
end
function dofile(name) return load_module(name, true) end

-- Generic inert engine object: indexable, callable, never errors on use.
local stub_mt = {}
local function make_stub(name)
    P.stub_names[name] = true
    return setmetatable({ __b2_name = name }, stub_mt)
end
stub_mt.__index = function(t, k)
    local name = rawget(t, "__b2_name") .. "." .. tostring(k)
    P.stub_hits[name] = (P.stub_hits[name] or 0) + 1
    local child = make_stub(name)
    rawset(t, k, child)
    return child
end
stub_mt.__call = function(t, ...)
    local name = rawget(t, "__b2_name") .. "()"
    P.stub_hits[name] = (P.stub_hits[name] or 0) + 1
    return make_stub(name)
end
stub_mt.__add = function() return 0 end
stub_mt.__sub = function() return 0 end
stub_mt.__mul = function() return 0 end
stub_mt.__div = function() return 0 end
stub_mt.__unm = function() return 0 end
stub_mt.__concat = function(a, b)
    local function s(v) return type(v) == "table" and ("<" .. tostring(rawget(v, "__b2_name")) .. ">") or tostring(v) end
    return s(a) .. s(b)
end
stub_mt.__tostring = function(t) return "<stub " .. tostring(rawget(t, "__b2_name")) .. ">" end
P.make_stub = make_stub

-- Record every global read that returned nil (candidate missing engine surface).
setmetatable(_G, {
    __index = function(_, k)
        P.nil_globals[k] = (P.nil_globals[k] or 0) + 1
        return nil
    end,
})

-- Explicit stubs / real foundation files for this run.
local stubs_chunk = assert(loadfile(stubs_path))
stubs_chunk(P, load_module, make_stub)

local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
local function sorted_keys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    return keys
end

local results = {}
for _, target in ipairs(targets) do
    local before = #P.order
    local t0 = os.clock()
    local ok, err = xpcall(function()
        if target:sub(1, 1) == "@" then return assert(native_loadfile(target:sub(2)))(P) end
        return load_module(target, false)
    end, function(e)
        return tostring(e) .. "\n" .. debug.traceback("", 2):sub(1, 900)
    end)
    results[#results + 1] = { target = target, ok = ok, err = err, files = #P.order - before, secs = os.clock() - t0 }
end

io.write("==== B2 engine-free load probe ====\n")
for _, r in ipairs(results) do
    io.write(string.format("%s  %s  (+%d files, %.2fs)\n", r.ok and "LOADED" or "FAILED", r.target, r.files, r.secs))
    if not r.ok then io.write("    " .. tostring(r.err):gsub("\n", "\n    ") .. "\n") end
end
io.write(string.format("vanilla files executed: %d\n", #P.order))
io.write(string.format("explicit engine stubs touched: %d distinct paths, top-level stub roots: %s\n",
    count(P.stub_hits), table.concat((function()
        local roots = {}
        for name in pairs(P.stub_names) do if not name:find("[%.%(]") then roots[name] = true end end
        return sorted_keys(roots)
    end)(), ",")))
local nilg = sorted_keys(P.nil_globals)
io.write(string.format("globals read while nil: %d\n  %s\n", #nilg, table.concat(nilg, " "):sub(1, 3000)))
if P.report then P.report() end
