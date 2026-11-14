-- A4 helper: load a VMF *_data.lua offline with stubs and print every widget setting_id + type.
-- Usage: lua5.1 A4_settings.lua <repo_root> <mod_dir> <mod_id> <data_file_rel>
local root, mod_dir, mod_id, data_rel = arg[1], arg[2], arg[3], arg[4]
local base = root .. "/" .. mod_dir .. "/"
local function load_rel(path)
    local f, err = loadfile(base .. path .. ".lua")
    if not f then error("load failed: " .. tostring(err)) end
    return f
end
local mod = {}
local store = {}
function mod:get(k) return store[k] end
function mod:set(k, v) store[k] = v end
function mod:localize(k) return k end
function mod:dofile(p) return load_rel(p)() end
function mod:echo() end function mod:info() end function mod:warning() end function mod:error() end function mod:debug() end
function mod:command() end function mod:hook() end function mod:hook_safe() end
function mod:get_name() return mod_id end
setmetatable(mod, { __index = function(t, k) return nil end })
_G.get_mod = function(id) if id == mod_id then return mod end return nil end
_G.printf = function() end
table.clone = table.clone or function(t) local o = {} for k, v in pairs(t) do o[k] = type(v) == "table" and table.clone(v) or v end return o end
table.contains = table.contains or function(t, x) for _, v in pairs(t) do if v == x then return true end end return false end
local loaded = {}
local real_require = require
_G.require = function(p)
    if p:find("^scripts/mods/") then
        if loaded[p] == nil then loaded[p] = load_rel(p)() or true end
        return loaded[p]
    end
    return real_require(p)
end
local ok, data = pcall(function() return load_rel(data_rel)() end)
if not ok then io.stderr:write("DATA LOAD ERROR: " .. tostring(data) .. "\n") os.exit(1) end
local n = 0
local seen = {}
local function visit(node, depth)
    if type(node) ~= "table" then return end
    if type(node.setting_id) == "string" then
        n = n + 1
        local dv = node.default_value
        print(string.format("%s\t%s\t%s\t%s", node.setting_id, tostring(node.type), tostring(dv), seen[node.setting_id] and "DUP" or ""))
        seen[node.setting_id] = true
    end
    for _, key in ipairs({ "sub_widgets", "widgets" }) do
        if type(node[key]) == "table" then for _, w in ipairs(node[key]) do visit(w, depth + 1) end end
    end
end
visit(data.options, 0)
io.stderr:write("total widgets with setting_id: " .. n .. "\n")
