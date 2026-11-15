-- qa/lua/fixtures/gen_wt_anim_vocab.lua (WP-WT-05): generate
-- qa/lua/tests/fixtures/wt_anim_vocab.lua from the decompiled game source.
--
-- Usage (by hand, vendored interpreter):
--   qa/lua/vendor/lua-5.1.5-win64/lua5.1.exe qa/lua/fixtures/gen_wt_anim_vocab.lua <decompile root> <output path>
--
-- Every file in <root>/scripts/settings/equipment/weapon_templates/ is run
-- under a permissive stub environment: any unknown global is a proxy that can
-- be indexed, called and combined, so engine tables are only referenced, never
-- needed. For every template the file returns (`return { <name> = template }`)
-- it records wield = wield_anim and events = the set of
-- `anim_event_3p or anim_event` of every top-level sub-action
-- (actions.<action>.<sub_action>) plus wield_anim, wield_anim_3p,
-- wield_anim_no_ammo, wield_anim_not_loaded and every value of
-- wield_anim_career / wield_anim_career_3p. The engine fires exactly that
-- value on the 3P body (scripts/unit_extensions/weapons/weapon_unit_extension.lua:510-512, 652).
-- ItemMasterList `template = "<name>"` rows are read as text from the same
-- files the game loads: the six base lists of
-- scripts/settings/equipment/item_master_list.lua:41-46 and every path named
-- by a DLC's `settings.item_master_list_file_names` (DLCUtils.require_list at
-- item_master_list.lua:47; many base weapons, e.g. the Billhook, live in
-- scripts/settings/equipment/item_master_list_<dlc>.lua).

local root, out_path = arg[1], arg[2]
assert(root and out_path, "usage: gen_wt_anim_vocab.lua <decompile root> <output path>")
root = root:gsub("\\", "/"):gsub("/$", "")

local function read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function list_dir(dir, pattern)
    local names = {}
    local cmd = package.config:sub(1, 1) == "\\"
        and ('dir /b "' .. dir:gsub("/", "\\") .. '" 2>nul')
        or ('ls -1 "' .. dir .. '" 2>/dev/null')
    local p = assert(io.popen(cmd))
    for line in p:lines() do
        line = line:gsub("\r$", "")
        if line:match(pattern) then names[#names + 1] = line end
    end
    p:close()
    table.sort(names)
    return names
end

local function decompile_commit()
    local head = read(root .. "/.git/HEAD")
    if not head then return "unknown" end
    head = head:gsub("%s+$", "")
    local ref = head:match("^ref: (.+)$")
    if not ref then return head:sub(1, 8) end
    local sha = read(root .. "/.git/" .. ref)
    if sha then return sha:gsub("%s+$", ""):sub(1, 8) end
    local packed = read(root .. "/.git/packed-refs") or ""
    for line in packed:gmatch("[^\n]+") do
        local s, r = line:match("^(%x+) (.+)$")
        if r == ref then return s:sub(1, 8) end
    end
    return "unknown"
end

-- Permissive proxies ------------------------------------------------------
local PROXY = setmetatable({}, { __mode = "k" })
local proxy_mt = {}
local function proxy()
    local p = setmetatable({}, proxy_mt)
    PROXY[p] = true
    return p
end
proxy_mt.__index = function() return proxy() end
proxy_mt.__newindex = function() end
proxy_mt.__call = function() return proxy() end
for _, op in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm", "__concat" }) do
    proxy_mt[op] = function() return proxy() end
end
proxy_mt.__lt = function() return false end
proxy_mt.__le = function() return false end
proxy_mt.__len = function() return 0 end

local function deep_clone(v, seen)
    if type(v) ~= "table" or PROXY[v] then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local c = {}
    seen[v] = c
    for k, x in pairs(v) do c[deep_clone(k, seen)] = deep_clone(x, seen) end
    return c
end

local stub_table = setmetatable({
    clone = deep_clone,
    create_copy = function(_, src) return deep_clone(src) end,
    merge = function(dst, src) for k, v in pairs(src or {}) do dst[k] = v end return dst end,
    merge_recursive = function(dst, src)
        local function m(d, s)
            for k, v in pairs(s or {}) do
                if type(v) == "table" and type(d[k]) == "table" and not PROXY[v] then m(d[k], v) else d[k] = v end
            end
        end
        m(dst, src)
        return dst
    end,
    contains = function(t, v) for _, x in pairs(t or {}) do if x == v then return true end end return false end,
    size = function(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end,
}, { __index = function(_, k) return table[k] or function() return proxy() end end })

local SAFE = {
    "assert", "error", "ipairs", "next", "pairs", "pcall", "rawequal", "rawget", "rawset",
    "select", "setmetatable", "getmetatable", "tonumber", "tostring", "type", "unpack", "xpcall",
}

local function new_env()
    local env = { string = string, math = math, table = stub_table }
    for _, name in ipairs(SAFE) do env[name] = _G[name] end
    env.require = function() return proxy() end
    env._G = env
    return setmetatable(env, { __index = function() return proxy() end })
end

-- Templates ---------------------------------------------------------------
local templates, failed = {}, {}
local tdir = root .. "/scripts/settings/equipment/weapon_templates"

local function add_event(set, v)
    if type(v) == "string" and v ~= "" then set[v] = true end
end

local function harvest(name, tpl)
    if type(tpl) ~= "table" or PROXY[tpl] then return end
    local events = {}
    if type(tpl.actions) == "table" and not PROXY[tpl.actions] then
        for _, action in pairs(tpl.actions) do
            if type(action) == "table" and not PROXY[action] then
                for _, sub in pairs(action) do
                    if type(sub) == "table" and not PROXY[sub] then
                        add_event(events, sub.anim_event_3p or sub.anim_event)
                    end
                end
            end
        end
    end
    for _, field in ipairs({ "wield_anim", "wield_anim_3p", "wield_anim_no_ammo", "wield_anim_not_loaded" }) do
        add_event(events, tpl[field])
    end
    for _, field in ipairs({ "wield_anim_career", "wield_anim_career_3p" }) do
        local map = tpl[field]
        if type(map) == "table" and not PROXY[map] then
            for _, v in pairs(map) do add_event(events, v) end
        end
    end
    templates[name] = { wield = type(tpl.wield_anim) == "string" and tpl.wield_anim or nil, events = events }
end

for _, file in ipairs(list_dir(tdir, "%.lua$")) do
    local source = read(tdir .. "/" .. file)
    source = source:gsub("^\239\187\191", "")
    local chunk, err = loadstring(source, "=" .. file)
    local ok, result = false, err
    if chunk then
        setfenv(chunk, new_env())
        ok, result = pcall(chunk)
    end
    if ok and type(result) == "table" and not PROXY[result] then
        for name, tpl in pairs(result) do
            if type(name) == "string" then harvest(name, tpl) end
        end
    else
        failed[#failed + 1] = file .. ": " .. tostring(result)
    end
end

-- ItemMasterList template rows (text) ------------------------------------
local item_template = {}
local function scan_iml(path)
    local text = read(path)
    if not text then return end
    local key
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        line = line:gsub("\r$", "")
        local k = line:match("^ItemMasterList%.([%w_]+) = {")
        if k then
            key = k
        elseif line == "}" then
            key = nil
        elseif key then
            local t = line:match('^\ttemplate = "([^"]+)"')
            if t then item_template[key] = t end
        end
    end
    -- Second shape (e.g. item_master_list_morris.lua): a local table of rows
    -- `<tab><key> = {` ... `<tab><tab>template = "<name>"` ... `<tab>},`.
    local block = text:match("\nlocal item_master_list = (%b{})")
    if block then
        local row
        for line in (block .. "\n"):gmatch("([^\n]*)\n") do
            line = line:gsub("\r$", "")
            local k = line:match("^\t([%w_]+) = {$")
            if k then
                row = k
            elseif line == "\t}," or line == "\t}" then
                row = nil
            elseif row then
                local t = line:match('^\t\ttemplate = "([^"]+)"')
                if t then item_template[row] = t end
            end
        end
    end
end
local iml_files = {
    "scripts/settings/equipment/item_master_list_local",
    "scripts/settings/equipment/item_master_list_exported",
    "scripts/settings/equipment/item_master_list_weapon_skins",
    "scripts/settings/equipment/item_master_list_test_items",
    "scripts/settings/equipment/item_master_list_steam_items",
    "scripts/settings/equipment/item_master_list_weapon_poses",
}
local ddir = root .. "/scripts/settings/dlcs"
for _, dlc in ipairs(list_dir(ddir, "^[%w_]+$")) do
    for _, file in ipairs(list_dir(ddir .. "/" .. dlc, "%.lua$")) do
        local text = read(ddir .. "/" .. dlc .. "/" .. file) or ""
        local block = text:match("item_master_list_file_names = (%b{})")
        if block then
            for path in block:gmatch('"([^"]+)"') do iml_files[#iml_files + 1] = path end
        end
    end
end
for _, path in ipairs(iml_files) do scan_iml(root .. "/" .. path .. ".lua") end

-- Output ------------------------------------------------------------------
local function sorted_keys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

local out = {}
local function w(s) out[#out + 1] = s end
local commit = decompile_commit()
w("-- AUTO-GENERATED by qa/lua/fixtures/gen_wt_anim_vocab.lua (WP-WT-05). DO NOT HAND-EDIT.")
w("-- Source: Vermintide-2-Source-Code " .. commit .. "; " .. #sorted_keys(templates) .. " templates, "
    .. #sorted_keys(item_template) .. " ItemMasterList template rows, " .. #failed .. " template files not executable.")
for _, f in ipairs(failed) do w("-- not executed: " .. f) end
w("return {")
w(string.format("    source = %q,", commit))
w("    templates = {")
for _, name in ipairs(sorted_keys(templates)) do
    local t = templates[name]
    w(string.format("        [%q] = {", name))
    if t.wield then w(string.format("            wield = %q,", t.wield)) end
    w("            events = {")
    for _, e in ipairs(sorted_keys(t.events)) do w(string.format("                [%q] = true,", e)) end
    w("            },")
    w("        },")
end
w("    },")
w("    item_template = {")
for _, key in ipairs(sorted_keys(item_template)) do
    w(string.format("        [%q] = %q,", key, item_template[key]))
end
w("    },")
w("}")
local f = assert(io.open(out_path, "wb"))
f:write(table.concat(out, "\n") .. "\n")
f:close()
io.write(string.format("templates=%d item_rows=%d failed=%d\n", #sorted_keys(templates), #sorted_keys(item_template), #failed))
for _, x in ipairs(failed) do io.write("  not executed: " .. x .. "\n") end
