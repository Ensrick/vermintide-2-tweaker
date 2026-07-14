local mod = get_mod("enemy_tweaker")

-- _et_fingerprint.lua - deterministic whole-mod settings fingerprint.
-- Big Rebalance's retired sub-toggle RPC/stub was removed under #433. This
-- remaining hash feeds only the universal [et:LOAD] applied marker.

local ET = mod._et

-- Minimal FNV-1a 32-bit. Standard Lua 5.1, no bit32 dependency.
local function _fnv1a32(s)
    local hash = 2166136261
    for i = 1, #s do
        local byte = string.byte(s, i)
        local xored, place = 0, 1
        local h, b = hash, byte
        for _ = 1, 32 do
            local hb = h % 2
            local bb = b % 2
            if hb ~= bb then xored = xored + place end
            place = place * 2
            h = (h - hb) / 2
            b = (b - bb) / 2
        end
        hash = (xored * 16777619) % 4294967296
    end
    return string.format("%08x", hash)
end

local function _settings_fingerprint()
    local ok, data = pcall(require, "scripts/mods/enemy_tweaker/enemy_tweaker_data")
    if not ok or type(data) ~= "table" then return "nodata" end
    local keys = {}
    local function walk(node)
        if type(node) ~= "table" then return end
        if type(node.setting_id) == "string" then keys[#keys + 1] = node.setting_id end
        for _, child in pairs(node) do
            if type(child) == "table" then walk(child) end
        end
    end
    walk(data)
    if #keys == 0 then return "nosettings" end
    table.sort(keys)
    local parts = {}
    for i, key in ipairs(keys) do
        local value = mod:get(key)
        if value == true then parts[i] = key .. "=1"
        elseif value == false then parts[i] = key .. "=0"
        elseif value == nil then parts[i] = key .. "=?"
        else parts[i] = key .. "=" .. tostring(value) end
    end
    return _fnv1a32(table.concat(parts, ";"))
end

ET.settings_fingerprint = _settings_fingerprint
