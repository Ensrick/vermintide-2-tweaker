local mod = get_mod("gut_dev")

-- ============================================================================
-- External config file: edit a .toml, override VMF settings on load
-- ============================================================================
-- Goal (user, 2026-06-20): keep all my tweaker mods' settings in a .toml file I
-- can edit directly; on game load those values OVERRIDE the in-game VMF options.
--
-- SANDBOX REALITY (verified: general_tweaker_dev _gt_name_dump note, cim io.open):
-- VMF mods can READ files (`io.open(path, "r")`) but CANNOT WRITE arbitrary files
-- (`io.open(path, "w")` is sandboxed out; no get_temp_data_directory /
-- save_user_settings_to_file). So:
--   * LOAD/OVERRIDE  -> the mod reads the .toml and mod:set()s each value. (here)
--   * EDIT           -> you edit the .toml by hand. (here)
--   * SAVE/EXPORT    -> the mod dumps TOML to the console log; the companion
--                       tools/gut-settings.ps1 writes the .toml from that log.
--
-- Config path: %APPDATA%\Fatshark\Vermintide 2\gut_mod_settings.toml
-- File format (minimal TOML): one [mod_id] section per mod, `setting_id = value`
-- with bool / int / float / "string" values. Keybinds/tables are skipped.

-- This author's mods (same whitelist as the Mod Tweaker). Only these are exported
-- and only these are overridden — we never touch other authors' mods, with ONE
-- deliberate exception: HideBuffs ("UI Tweaks"). The #312 HUD-customizer
-- write-through makes UI Tweaks the owner of the buff/boss/overcharge/energy bar
-- positions, so the user's HUD layout now lives in HideBuffs' settings; including
-- it here lets a config snapshot capture and restore that layout too.
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

-- Resolve %APPDATA%\Fatshark\Vermintide 2\<file>. os.getenv may be sandboxed; guard.
local function _config_path()
    local appdata
    local ok = pcall(function() appdata = os and os.getenv and os.getenv("APPDATA") end)
    if ok and type(appdata) == "string" and appdata ~= "" then
        return appdata .. "\\Fatshark\\Vermintide 2\\" .. CONFIG_NAME
    end
    return nil
end

-- ---------------------------------------------------------------
-- Minimal TOML (flat: [section] + key = scalar)
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
        "# Edit the values below. On game load (or /reload_config) these OVERRIDE",
        "# the in-game VMF settings for these mods. Lines starting with # are ignored.",
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

local function _parse_scalar(v)
    if v == "true" then return true end
    if v == "false" then return false end
    local q = v:match('^"(.*)"$')
    if q then return q end
    local n = tonumber(v)
    if n then return n end
    return v  -- bare string fallback
end

local function _parse_toml(text)
    local by_mod, cur = {}, nil
    for line in text:gmatch("[^\r\n]+") do
        local s = line:gsub("^%s+", ""):gsub("%s+$", "")
        if s ~= "" and s:sub(1, 1) ~= "#" then
            local section = s:match("^%[(.-)%]$")
            if section then
                cur = section
                by_mod[cur] = by_mod[cur] or {}
            elseif cur then
                local k, v = s:match("^([%w_]+)%s*=%s*(.+)$")
                if k and v then
                    v = v:gsub('%s+#[^"]*$', "")  -- strip trailing inline comment (not inside a string)
                    by_mod[cur][k] = _parse_scalar(v)
                end
            end
        end
    end
    return by_mod
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
-- Apply the config file: override VMF settings with the file's values
-- ---------------------------------------------------------------
local function apply()
    -- Config-file override is IMPLICIT (always on) — no toggle. It's a no-op when the file
    -- doesn't exist, so there's nothing worth gating on (removed gut_config_override checkbox).
    local path = _config_path()
    if not path then
        mod:info("[gut:config] could not resolve APPDATA path (os.getenv sandboxed?)")
        return 0
    end
    local f = io.open(path, "r")
    if not f then return 0 end  -- no file yet = nothing to override
    local text = f:read("*a")
    f:close()
    if not text or text == "" then return 0 end

    local by_mod = _parse_toml(text)
    local applied, mods_touched = 0, 0
    for mn, settings in pairs(by_mod) do
        if _MY_MODS[mn] then
            local mob = get_mod(mn)
            if mob and mob.set then
                mods_touched = mods_touched + 1
                for sid, val in pairs(settings) do
                    -- 3rd arg true => fire the mod's on_setting_changed so it reacts
                    local ok = pcall(mob.set, mob, sid, val, true)
                    if ok then applied = applied + 1 end
                end
            end
        end
    end
    mod:info("[gut:config] applied %d setting(s) across %d mod(s) from %s", applied, mods_touched, path)
    return applied
end

-- ---------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------
-- Emit the full TOML to the log. The companion watcher (tools/gut-settings-watch.ps1)
-- tails the log and writes the .toml from each BEGIN..END block — that's how a
-- write-sandboxed mod "writes" a file: log out, let a desktop process commit it.
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

mod:command("reload_config", "Re-read the .toml and override settings now (no restart needed)", function()
    local path = _config_path()
    if not path then mod:echo("Config path unavailable on this build."); return end
    local f = io.open(path, "r")
    if not f then mod:echo("No config file found at " .. path .. " - run /export_settings + the companion script first."); return end
    f:close()
    local n = apply()
    mod:echo(string.format("Applied %d setting(s) from %s.", n, CONFIG_NAME))
end)

mod:info("[gut] Config-file feature installed (/export_settings, /reload_config; overrides on load)")

return { apply = apply }
