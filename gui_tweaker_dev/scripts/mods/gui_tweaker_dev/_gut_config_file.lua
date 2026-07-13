local mod = get_mod("gut_dev")

-- ============================================================================
-- Settings snapshot export: emit TOML for a desktop companion to persist
-- ============================================================================
-- Retail Stingray exposes no file-read primitive (`io` is nil; #511/#517), so
-- the former load-time override and /reload_config paths could never work in the
-- game client. They are intentionally retired. This module only snapshots live
-- VMF settings to the console log; tools/gut-settings*.ps1 can persist that
-- snapshot outside the sandbox for backup or comparison.
--
-- Config path: %APPDATA%\Fatshark\Vermintide 2\gut_mod_settings.toml
-- Snapshot format: one [mod_id] section per mod, `setting_id = value`
-- with bool / int / float / "string" values. Keybinds/tables are skipped.

-- This author's mods (same whitelist as the Mod Tweaker). Only these are exported,
-- with ONE
-- deliberate exception: HideBuffs ("UI Tweaks"). The #312 HUD-customizer
-- write-through makes UI Tweaks the owner of the buff/boss/overcharge/energy bar
-- positions, so the user's HUD layout now lives in HideBuffs' settings; including
-- it here lets a config snapshot capture that layout too.
local _MY_MODS = {
    gut = true, gut_dev = true, wt = true, ct = true, ct_dev = true, gt = true, gt_dev = true,
    cim = true, cim_dev = true, crt = true, cosmetics_tweaker = true,
    dynamic_cosmetic_portraits = true, enemy_tweaker = true,
    character_weapon_variants = true, event_tweaker = true, mp = true, bt = true,
    verminious_dreams_lighting = true, verminious_dreams_lighting_dev = true,
    HideBuffs = true,  -- UI Tweaks (#312): HUD layout lives in its settings now
    ["Crosshair Kill Confirmation"] = true,  -- Crosshair Kill Confirmation (#313)
}

local CONFIG_NAME = "gut_mod_settings.toml"

-- ---------------------------------------------------------------
-- Minimal TOML writer (flat: [section] + key = scalar)
-- ---------------------------------------------------------------
local function _toml_scalar(v)
    local t = type(v)
    if t == "boolean" then return tostring(v) end
    if t == "number" then
        if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
        return tostring(v)
    end
    if t == "string" then return string.format("%q", v) end
    return nil  -- tables / keybinds unsupported
end

local function _to_toml(by_mod)
    local out = {
        "# Tweaker: GUI - mod settings config",
        "# Snapshot of current in-game VMF settings.",
        "# Retail Vermintide cannot read this file; it is a backup/reference only.",
        "",
    }
    local mods = {}
    for m in pairs(by_mod) do mods[#mods + 1] = m end
    table.sort(mods)
    for _, m in ipairs(mods) do
        out[#out + 1] = "[" .. m .. "]"
        local s = by_mod[m]
        local keys = {}
        for k in pairs(s) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local sv = _toml_scalar(s[k])
            if sv then out[#out + 1] = k .. " = " .. sv end
        end
        out[#out + 1] = ""
    end
    return table.concat(out, "\n")
end

-- ---------------------------------------------------------------
-- Collect current settings for the author's mods (via VMF's enumeration)
-- ---------------------------------------------------------------
local function _nf(node, key)
    if type(node) ~= "table" then return nil end
    local val = node[key]
    if val == nil and type(node.content) == "table" then val = node.content[key] end
    return val
end

local function _collect()
    local by_mod = {}
    local vmf = get_mod("VMF")
    local wd = vmf and vmf.options_widgets_data
    if type(wd) ~= "table" then return by_mod end
    for _, list in ipairs(wd) do
        local header = type(list) == "table" and list[1]
        local mn = header and _nf(header, "mod_name")
        if type(mn) == "string" and _MY_MODS[mn] then
            local mob = get_mod(mn)
            if mob and mob.get then
                local settings = {}
                for i = 2, #list do
                    local node = list[i]
                    local sid = _nf(node, "setting_id")
                    local ntype = _nf(node, "type")
                    if sid and ntype ~= "group" and ntype ~= "header" and ntype ~= "keybind" then
                        local ok, v = pcall(mob.get, mob, sid)
                        if ok and (type(v) == "boolean" or type(v) == "number" or type(v) == "string") then
                            settings[sid] = v
                        end
                    end
                end
                if next(settings) then by_mod[mn] = settings end
            end
        end
    end
    return by_mod
end

-- ---------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------
-- Emit the full TOML to the log. The companion watcher (tools/gut-settings-watch.ps1)
-- tails the log and writes the snapshot from each BEGIN..END block.
local function _export_to_log(silent)
    local toml = _to_toml(_collect())
    mod:info("[gut:toml] ===== BEGIN %s =====", CONFIG_NAME)
    for line in (toml .. "\n"):gmatch("(.-)\n") do
        mod:info("[gut:toml] %s", line)
    end
    mod:info("[gut:toml] ===== END %s =====", CONFIG_NAME)
    if not silent then
        mod:echo("Settings dumped to the log (prefix [gut:toml]). The watcher (tools/gut-settings-watch.ps1) or one-shot tools/gut-settings.ps1 writes " .. CONFIG_NAME .. ".")
    end
end
-- Exposed so the Mod Tweaker can auto-export when it closes (a natural save point).
mod._export_settings_to_log = _export_to_log

mod:command("export_settings", "Dump your tweaker mods' settings as TOML to the log (companion writes the file)", function()
    _export_to_log(false)
end)

mod:info("[gut:config] settings snapshot export installed (/export_settings; retail read-back unavailable)")

return { read_supported = false, export_to_log = _export_to_log }
