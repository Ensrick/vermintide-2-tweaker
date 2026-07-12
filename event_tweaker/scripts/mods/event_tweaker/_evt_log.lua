local mod = get_mod("event_tweaker")

-- _evt_log.lua — two-channel debug helpers + settings fingerprint
--
-- Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6). Both helpers
-- route through VMF's built-in logging system (gated by VMF output_mode_debug /
-- output_mode_warning): `dbg` is for confirmation / expected behavior (the
-- mod:debug channel), `dbg_alert` for unexpected / wrong / mismatch, log-only
-- via pcall-guarded engine printf (#427/#240 — mod:warning posts to chat under
-- VMF defaults). `settings_fingerprint` feeds the canonical
-- [event_tweaker:LOAD] applied marker line the entry file prints
-- (PROJECT_STANDARDS.md § 3.6 "Applied marker line (universal)").
--
-- Owned by: event_tweaker.lua entry point (dofile'd FIRST — later modules
-- localize dbg/dbg_alert at their top). Consumed via mod._evt exports:
-- dbg, dbg_alert, settings_fingerprint.

local ET = mod._evt

local function _dbg(fmt, ...)
    mod:debug("[event_tweaker:dbg] " .. fmt, ...)
end

-- Issue #427/#240: mod:warning posts to CHAT under VMF defaults (logging.lua
-- warning mode >= 2), so a "log-only" alert spammed chat. Route through
-- pcall-guarded engine printf (log-only, survives mod-logging-OFF; pcall so a
-- format slip never faults the caller). Reserve chat for a deliberate
-- _chat_alert (none defined here).
local function _dbg_alert(fmt, ...)
    if not pcall(printf, "[event_tweaker:dbg] " .. fmt, ...) then
        pcall(printf, "[event_tweaker:dbg] (alert format error: %s)", tostring(fmt))
    end
end

-- Walks the data widget tree, FNV-1a-32 hashes setting=value pairs. Called
-- once at load by the entry file's [event_tweaker:LOAD] line (ALWAYS fires —
-- operational telemetry).
local function _settings_fingerprint()
    local ok, data = pcall(require, "scripts/mods/event_tweaker/event_tweaker_data")
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
    for i, k in ipairs(keys) do
        local v = mod:get(k)
        if v == true then       parts[i] = k .. "=1"
        elseif v == false then  parts[i] = k .. "=0"
        elseif v == nil then    parts[i] = k .. "=?"
        else                    parts[i] = k .. "=" .. tostring(v) end
    end
    local s = table.concat(parts, ";")
    local h = 2166136261
    for i = 1, #s do
        local byte = string.byte(s, i)
        local xored, place = 0, 1
        local hh, bb = h, byte
        for _ = 1, 32 do
            local hb, bbit = hh % 2, bb % 2
            if hb ~= bbit then xored = xored + place end
            place = place * 2
            hh = (hh - hb) / 2
            bb = (bb - bbit) / 2
        end
        h = (xored * 16777619) % 4294967296
    end
    return string.format("%08x", h)
end

ET.dbg = _dbg
ET.dbg_alert = _dbg_alert
ET.settings_fingerprint = _settings_fingerprint
