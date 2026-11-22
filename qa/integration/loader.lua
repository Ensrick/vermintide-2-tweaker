-- qa/integration/loader.lua (WP-T-03): runs real vanilla VT2 Lua files from the decompile under plain Lua 5.1.
--
-- From the 2026-11-13 B2 prototype (probe.lua). Returns a function(decompile_root) that installs, in this Lua state:
--   * require(name) / dofile(name) the way the engine resolves them: slash paths relative to the decompile root,
--     dotted names mapped to slashes, results kept in package.loaded, and package.load_order kept in load order
--     (foundation/scripts/util/local_require.lua:5-16 reads it). A UTF-8 BOM is stripped before compiling.
--   * make_stub(name): an inert engine object. Indexing or calling it gives another stub and records the path; it
--     never errors and it carries the marker field __vt2_stub, so a suite can tell a real value from a stub's
--     (is_stub). Arithmetic on it gives 0.
-- and returns a table L with load_module, make_stub, is_stub, order (every vanilla file run, in order),
-- failures and stub_hits. Nothing is read outside the decompile root; nothing is written anywhere.
return function(root)
    local L = { root = root, order = {}, failures = {}, stub_hits = {}, stub_names = {} }

    local function read(path)
        local f = io.open(path, "rb")
        if not f then return nil end
        local s = f:read("*a")
        f:close()
        if s:sub(1, 3) == "\239\187\191" then s = s:sub(4) end -- PUC Lua 5.1 rejects the UTF-8 BOM
        return s
    end

    package.load_order = {}

    local function load_module(name, force)
        if not force and package.loaded[name] ~= nil then return package.loaded[name] end
        local src = read(root .. "/" .. name .. ".lua")
        if not src then
            error("module not found in the decompile: " .. name, 0)
        end
        local chunk, err = loadstring(src, "@" .. name .. ".lua")
        if not chunk then error("parse error in " .. name .. ": " .. tostring(err), 0) end
        if not force then package.loaded[name] = true end -- cycle guard, as the native require's sentinel
        package.load_order[#package.load_order + 1] = name
        L.order[#L.order + 1] = name
        local ok, result = xpcall(chunk, function(e) return tostring(e) .. "\n" .. debug.traceback("", 2):sub(1, 800) end)
        if not ok then
            if not force then package.loaded[name] = nil end
            L.failures[#L.failures + 1] = name .. ": " .. tostring(result)
            error(result, 0)
        end
        if not force and result ~= nil then package.loaded[name] = result end
        if force then return result end
        return package.loaded[name]
    end

    local native_require = require
    function require(name) -- luacheck: ignore (the engine's global require is replaced the same way)
        if type(name) == "string" and name:find("/", 1, true) then return load_module(name, false) end
        if type(name) == "string" then
            local as_path = name:gsub("%.", "/")
            local f = io.open(root .. "/" .. as_path .. ".lua", "rb")
            if f then f:close(); return load_module(as_path, false) end
        end
        return native_require(name)
    end
    function dofile(name) return load_module(name, true) end -- luacheck: ignore

    local stub_mt = {}
    local function make_stub(name)
        L.stub_names[name] = true
        return setmetatable({ __vt2_stub = name }, stub_mt)
    end
    stub_mt.__index = function(t, k)
        local name = rawget(t, "__vt2_stub") .. "." .. tostring(k)
        L.stub_hits[name] = (L.stub_hits[name] or 0) + 1
        local child = make_stub(name)
        rawset(t, k, child)
        return child
    end
    stub_mt.__call = function(t)
        local name = rawget(t, "__vt2_stub") .. "()"
        L.stub_hits[name] = (L.stub_hits[name] or 0) + 1
        return make_stub(name)
    end
    stub_mt.__add = function() return 0 end
    stub_mt.__sub = function() return 0 end
    stub_mt.__mul = function() return 0 end
    stub_mt.__div = function() return 0 end
    stub_mt.__unm = function() return 0 end
    stub_mt.__concat = function(a, b)
        local function s(v) return type(v) == "table" and ("<" .. tostring(rawget(v, "__vt2_stub")) .. ">") or tostring(v) end
        return s(a) .. s(b)
    end
    stub_mt.__tostring = function(t) return "<stub " .. tostring(rawget(t, "__vt2_stub")) .. ">" end

    L.load_module = load_module
    L.make_stub = make_stub
    L.is_stub = function(v) return type(v) == "table" and rawget(v, "__vt2_stub") ~= nil end
    return L
end
