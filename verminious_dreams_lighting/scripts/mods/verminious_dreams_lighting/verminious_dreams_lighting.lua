local mod = get_mod("verminious_dreams_lighting")
_MEM_PROBE_T0_VDLS = collectgarbage("count")  -- [mem-probe] temp Lua-footprint baseline (lua_heap 1 GiB cap diagnostic)

local MOD_VERSION = "1.0.6"
-- Startup banner: log-only, NOT chat. The applied marker line further down
-- ([vdl] enabled v<X> settings_fp=<hash>) is the canonical version surface
-- (PROJECT_STANDARDS.md § 3.6 "Chat-echo policy" — never echo at module load,
-- not even gated on debug logging; the operator confirms by tailing the log
-- or running /vdl_regression_test).
mod:info("Verminious Dreams Lighting v%s loaded", MOD_VERSION)

-- Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6).
-- Both gate on `enable_debug_logging`. Both no-op when toggle is off.
-- `_dbg` is for confirmation / expected behavior — file only.
-- `_dbg_alert` is for unexpected / wrong / mismatch — file AND in-game chat.
local function _dbg(fmt, ...)
    if mod:get("enable_debug_logging") then
        mod:info("[vdl:dbg] " .. fmt, ...)
    end
end

local function _dbg_alert(fmt, ...)
    if mod:get("enable_debug_logging") then
        mod:info("[vdl:dbg] " .. fmt, ...)
        mod:echo("[vdl] " .. fmt, ...)
    end
end

-- Applied marker (PROJECT_STANDARDS.md § 3.6 "Applied marker line (universal)").
-- Walks the data widget tree, FNV-1a-32 hashes setting=value pairs, prints
-- one mod:info line at load. ALWAYS fires (operational telemetry).
local function _settings_fingerprint()
    local ok, data = pcall(require, "scripts/mods/verminious_dreams_lighting/verminious_dreams_lighting_data")
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

mod:info("[vdl:LOAD] v%s enabled fp=%s OK", MOD_VERSION, _settings_fingerprint())

-- v1.0.3: regression test scaffold (vdl had none).
local _RT_CHECKS = {}
local function _rt_register(name, fn)
    _RT_CHECKS[#_RT_CHECKS + 1] = { name = name, fn = fn }
end
mod:command("vdl_regression_test", "Run regression smoke checks for past bugs", function()
    local pass, fail = 0, 0
    mod:echo("=== vdl regression_test (v%s) ===", MOD_VERSION)
    for _, c in ipairs(_RT_CHECKS) do
        local ok, err = pcall(c.fn)
        if ok and err == nil then
            mod:echo("  PASS: %s", c.name); pass = pass + 1
            mod:info("[regression] PASS %s", c.name)
        else
            local msg = (not ok and tostring(err)) or tostring(err)
            mod:echo("  FAIL: %s -- %s", c.name, msg); fail = fail + 1
            mod:warning("[regression] FAIL %s: %s", c.name, msg)
        end
    end
    mod:echo("=== %d passed, %d failed ===", pass, fail)
end)

_rt_register("dbg_helpers_two_channel", function()
    if type(_dbg) ~= "function" then return "_dbg helper missing" end
    if type(_dbg_alert) ~= "function" then return "_dbg_alert helper missing" end
    local saved = mod:get("enable_debug_logging")
    if saved ~= false then mod:set("enable_debug_logging", false) end
    local ok = pcall(_dbg, "smoke test off")
    if not ok then return "_dbg raised with toggle off" end
    ok = pcall(_dbg_alert, "smoke test off")
    if not ok then return "_dbg_alert raised with toggle off" end
    if saved == true then mod:set("enable_debug_logging", true) end
end)


_rt_register("localization_format_safe", function()
    -- Layer 3 (2026-05-25): catch unescaped %-format chars in loc strings at
    -- runtime. VMF's tooltip render path calls string.format on the loc value;
    -- literal "%APPDATA%" / "5%" / "%USERNAME%" raises 'invalid option' and
    -- shows as a red error tooltip in the VMF settings UI. Static check is
    -- qa/check_localization.ps1 -- this is its runtime twin so the bug can't
    -- ship even if the static check is skipped. RULE: any literal % in a loc
    -- string must be doubled to %%.
    local ok, loc = pcall(mod.dofile, mod, "scripts/mods/verminious_dreams_lighting/verminious_dreams_lighting_localization")
    if not ok or type(loc) ~= "table" then return end  -- can't reach loc; skip
    for k, v in pairs(loc) do
        if type(v) == "table" and type(v.en) == "string" then
            local fmt_ok, fmt_err = pcall(string.format, v.en)
            if not fmt_ok then
                return string.format(
                    "loc key %q has invalid format string (escape literal %% as %%%%): %s",
                    k, tostring(fmt_err))
            end
        end
    end
end)
-- ============================================================
-- Targeted levels
-- ============================================================
local _LEVEL_DISPLAY = {
    dlc_termite_1 = "The Forsaken Temple",
    dlc_termite_2 = "Devious Delvings",
    dlc_termite_3 = "The Well of Dreams",
}

-- ============================================================
-- Light grouping
-- ============================================================
-- Lights in a level fall into two categories the player thinks about:
--   - torches:  attached to torch / brazier / candle / lantern units.
--     Auto-classified by unit-name substring at capture time.
--   - general:  everything else.
--
-- Each profile can override color + intensity per group. Apply order is
-- torches-override → global override → vanilla. Setting both group and
-- global lets you say "all lights = X except torches = Y".
local _DEFAULT_TORCH_PATTERNS = { "torch", "brazier", "candle", "lantern", "sconce" }

local _SHADING_VARS = {
    sky      = "skydome_tint_color",
    sun      = "sun_color",
    sun2     = "secondary_sun_color",
    amb      = "ambient_tint",
    amb_top  = "ambient_tint_top",
    fog      = "fog_color",
}

local function _default_profile()
    return {
        sky = nil, sun = nil, sun2 = nil, amb = nil, amb_top = nil, fog = nil,
        exp = nil,
        -- global Light component overrides (apply to every light not matched
        -- by a more-specific group)
        light_color = nil,
        light_intensity = nil,
        -- torch group
        light_torches_color = nil,
        light_torches_intensity = nil,
        torch_patterns = nil,      -- optional override of _DEFAULT_TORCH_PATTERNS
    }
end

-- ============================================================
-- Baked defaults — replace _default_profile() result for each level
-- after the in-game tuning pass. Subscribers get these without
-- running any commands.
-- ============================================================
local _PROFILES = {
    -- The Forsaken Temple — first tuning pass 2026-05-16
    dlc_termite_1 = {
        sky          = { 50, 100, 170 },
        sun          = { 210, 210, 230 },
        sun2         = { 255, 255, 255 },
        amb          = { 210, 210, 180 },
        amb_top      = { 150, 150, 200 },
        fog          = { 86, 90, 70 },
        exp          = 0.045,
        light_color = nil, light_intensity = nil,
        light_torches_color = nil, light_torches_intensity = nil,
        torch_patterns = nil,
    },
    -- Devious Delvings — first tuning pass 2026-05-16
    dlc_termite_2 = {
        sky          = nil,                  -- vanilla
        sun          = { 160, 120, 80 },
        sun2         = nil,                  -- vanilla
        amb          = { 250, 250, 250 },
        amb_top      = { 50, 100, 160 },
        fog          = { 24, 24, 24 },
        exp          = nil,                  -- vanilla
        light_color = nil, light_intensity = nil,
        light_torches_color = nil, light_torches_intensity = nil,
        torch_patterns = nil,
    },
    -- The Well of Dreams — first tuning pass 2026-05-16
    dlc_termite_3 = {
        sky          = nil,                  -- vanilla
        sun          = { 100, 100, 100 },
        sun2         = nil,                  -- vanilla
        amb          = { 200, 200, 280 },
        amb_top      = { 50, 50, 60 },
        fog          = { 70, 85, 85 },
        exp          = nil,                  -- vanilla
        light_color = nil, light_intensity = nil,
        light_torches_color = nil, light_torches_intensity = nil,
        torch_patterns = nil,
    },
}

-- v0.4 storage key (additive on v0.3 fields). Old keys ignored.
do
    local saved = mod:get("saved_profiles_v4")
    if type(saved) == "table" then
        for level_key, p in pairs(saved) do
            if type(p) == "table" then
                local dest = _PROFILES[level_key] or _default_profile()
                for k, v in pairs(p) do dest[k] = v end
                _PROFILES[level_key] = dest
            end
        end
    end
end

-- ============================================================
-- Byte ↔ float conversion
-- ============================================================
local function _byte_to_float(b)
    return (b or 0) / 255
end
local function _float_to_byte(f)
    local n = math.floor((f or 0) * 255 + 0.5)
    if n < 0 then n = 0 end
    return n
end
local function _bytes_to_vector3(t)
    return Vector3(_byte_to_float(t[1]), _byte_to_float(t[2]), _byte_to_float(t[3]))
end
local function _vector3_to_bytes(v)
    return { _float_to_byte(v.x), _float_to_byte(v.y), _float_to_byte(v.z) }
end
local function _bytes_str(t)
    if type(t) ~= "table" then return tostring(t) end
    return string.format("%d %d %d", t[1] or 0, t[2] or 0, t[3] or 0)
end

-- ============================================================
-- Caches
-- ============================================================
local _LAST_SAMPLED = {}
local _LAST_SAMPLED_EXP = nil
local _CURRENT_LEVEL_KEY = nil

-- Each entry in _CACHED_LIGHTS:
--   { light = <handle>, unit = <unit>, name = "<debug_name>", y = <number>, group = "torches"|"chasm"|"general" }
local _CACHED_LIGHTS = {}

-- ============================================================
-- Helpers
-- ============================================================

local function _current_level_key()
    if Managers and Managers.state and Managers.state.game_mode then
        return Managers.state.game_mode:level_key()
    end
    return nil
end

-- Per-level VMF toggle. The widget id is "enable_<level_key>"; default
-- is true. Disabling the toggle returns a nil profile, which makes the
-- shading_callback hook short-circuit (engine re-seeds the env each
-- frame so atmosphere reverts immediately) and makes light overrides
-- skip on the next reapply. The currently-applied Light component
-- values stay in place until next level load — that's the same caveat
-- as `vdl_light_off`, documented in the toggle tooltip.
local function _is_level_enabled(key)
    if not key then return false end
    local v = mod:get("enable_" .. key)
    -- VMF returns nil for never-set settings → treat as default (on).
    if v == nil then return true end
    return v and true or false
end

local function _profile_for_current_level()
    local key = _CURRENT_LEVEL_KEY or _current_level_key()
    if not key then return nil, nil end
    if not _is_level_enabled(key) then return nil, key end
    return _PROFILES[key], key
end

-- Commands ignore the toggle so the user can tune even with the level
-- disabled (their edits queue up; flipping the toggle on applies them).
local function _profile_for_current_level_raw()
    local key = _CURRENT_LEVEL_KEY or _current_level_key()
    if not key then return nil, nil end
    return _PROFILES[key], key
end

local function _to_int(s)
    if s == nil then return nil end
    local n = tonumber(s)
    if not n then return nil end
    return math.floor(n + 0.5)
end
local function _to_num(s)
    if s == nil then return nil end
    return tonumber(s)
end

-- Case-insensitive substring match. patterns is an array of plain
-- lowercase substrings; name is a string. Returns true if any pattern
-- is a substring of name.
local function _name_matches_any(name, patterns)
    if not name then return false end
    local lower = string.lower(name)
    for i = 1, #patterns do
        if string.find(lower, patterns[i], 1, true) then return true end
    end
    return false
end

local function _classify_light(parent_name, parent_y, profile)
    local patterns = profile.torch_patterns or _DEFAULT_TORCH_PATTERNS
    if _name_matches_any(parent_name, patterns) then return "torches" end
    return "general"
end

-- ============================================================
-- Light apply
-- ============================================================
-- For each cached light, pick a color + intensity based on its group:
--   1. Per-group profile override (torches / chasm)
--   2. Global profile override (light_color / light_intensity)
--   3. Vanilla baseline (do nothing)
local function _apply_lights_to_cached()
    local profile = _profile_for_current_level()
    if not profile then return 0 end

    -- Does this profile touch ANY light field? Short-circuit if not, so
    -- default-state mods don't reach the engine boundary at all.
    local any_set = profile.light_color or profile.light_intensity
        or profile.light_torches_color or profile.light_torches_intensity
    if not any_set then return 0 end

    local applied = 0
    for i = 1, #_CACHED_LIGHTS do
        local entry = _CACHED_LIGHTS[i]
        local light = entry.light
        if light then
            -- Re-classify each apply in case torch_patterns / chasm_y_max changed.
            local group = _classify_light(entry.name, entry.y, profile)
            entry.group = group

            local color, intensity
            if group == "torches" then
                color     = profile.light_torches_color     or profile.light_color
                intensity = profile.light_torches_intensity or profile.light_intensity
            else
                color     = profile.light_color
                intensity = profile.light_intensity
            end

            if color or intensity then
                local ok = pcall(function()
                    if color then
                        Light.set_color(light, _bytes_to_vector3(color))
                    end
                    if intensity then
                        Light.set_intensity(light, intensity)
                    end
                end)
                if ok then applied = applied + 1 end
            end
        end
    end
    return applied
end

local function _capture_and_apply_lights(world)
    _CACHED_LIGHTS = {}

    if not world then return 0 end
    local level = LevelHelper:current_level(world)
    if not level then return 0 end

    local profile = _profile_for_current_level()
    local units = Level.units(level)
    local count = 0
    for j = 1, #units do
        local level_unit = units[j]
        if Unit.alive(level_unit) then
            local num_lights = Unit.num_lights(level_unit)
            if num_lights and num_lights > 0 then
                -- Parent unit metadata, captured once per unit.
                local debug_name
                pcall(function() debug_name = Unit.debug_name(level_unit) end)
                local pos_y
                pcall(function()
                    local p = Unit.world_position(level_unit, 1)
                    if p then pos_y = p.z end  -- Stingray Z is up; "below the map" = low Z
                end)

                for i = 1, num_lights do
                    local light = Unit.light(level_unit, i - 1)
                    if light then
                        local entry = {
                            light = light,
                            unit  = level_unit,
                            name  = debug_name or "?",
                            y     = pos_y,
                            group = profile and _classify_light(debug_name, pos_y, profile) or "general",
                        }
                        _CACHED_LIGHTS[#_CACHED_LIGHTS + 1] = entry
                        count = count + 1
                    end
                end
            end
        end
    end

    local applied = _apply_lights_to_cached()
    mod:info("[vdl] captured %d lights, applied override to %d", count, applied)
    return count
end

-- ============================================================
-- Per-frame shading sample + apply
-- ============================================================
mod:hook_safe("CameraManager", "shading_callback", function(self, world, shading_env, viewport)
    local profile, key = _profile_for_current_level()
    if not profile then return end

    for short_key, var_name in pairs(_SHADING_VARS) do
        local v = ShadingEnvironment.vector3(shading_env, var_name)
        if v then _LAST_SAMPLED[short_key] = _vector3_to_bytes(v) end
    end
    local cur_exp = ShadingEnvironment.scalar(shading_env, "exposure")
    if cur_exp then _LAST_SAMPLED_EXP = cur_exp end

    for short_key, var_name in pairs(_SHADING_VARS) do
        local ov = profile[short_key]
        if ov then
            ShadingEnvironment.set_vector3(shading_env, var_name, _bytes_to_vector3(ov))
        end
    end
    if profile.exp then
        ShadingEnvironment.set_scalar(shading_env, "exposure", profile.exp)
    end
end)

mod:hook_safe("GameModeManager", "local_player_game_starts", function(self, player, loading_context)
    local key = _current_level_key()
    _CURRENT_LEVEL_KEY = key
    if not key or not _PROFILES[key] then return end

    mod:info("[vdl] level start: %s (%s)", tostring(key), tostring(_LEVEL_DISPLAY[key] or "?"))
    _capture_and_apply_lights(self._world)
end)

-- ============================================================
-- Commands
-- ============================================================

local function _require_profiled_level()
    local profile, key = _profile_for_current_level_raw()
    if not profile then
        mod:echo(string.format("[vdl] current level (%s) isn't profiled. This mod only tunes dlc_termite_1/2/3.",
            tostring(key or "nil")))
        return nil, nil
    end
    if not _is_level_enabled(key) then
        mod:echo(string.format("[vdl] note: %s toggle is OFF in VMF settings. Edits will queue; flip the toggle on to apply.",
            tostring(key)))
    end
    return profile, key
end

local function _show_or_set_bytes(short_key, label, r, g, b)
    local profile = _require_profiled_level(); if not profile then return end
    if r == nil and g == nil and b == nil then
        local sample = _LAST_SAMPLED[short_key]
        local override = profile[short_key]
        local sample_str   = sample and _bytes_str(sample) or "(not sampled yet — be in the mission, then try again)"
        local override_str = override and _bytes_str(override) or "(none — using vanilla)"
        mod:echo(string.format("[vdl] %s:  (RGB bytes 0-255)", label))
        mod:echo(string.format("       vanilla  = %s", sample_str))
        mod:echo(string.format("       override = %s", override_str))
        return
    end
    local nr, ng, nb = _to_int(r), _to_int(g), _to_int(b)
    if not (nr and ng and nb) then
        mod:echo(string.format("[vdl] %s: need three integers (0-255) or no args; got %s %s %s",
            label, tostring(r), tostring(g), tostring(b)))
        return
    end
    profile[short_key] = { nr, ng, nb }
    local sample = _LAST_SAMPLED[short_key]
    mod:echo(string.format("[vdl] %s = %d %d %d  (vanilla was %s)", label, nr, ng, nb,
        sample and _bytes_str(sample) or "?"))
end

mod:command("vdl_sky", "Show or set skydome_tint_color (RGB 0-255): vdl_sky [r g b]", function(r, g, b)
    _show_or_set_bytes("sky", "sky", r, g, b)
end)
mod:command("vdl_sun", "Show or set sun_color (RGB 0-255): vdl_sun [r g b]", function(r, g, b)
    _show_or_set_bytes("sun", "sun", r, g, b)
end)
mod:command("vdl_sun2", "Show or set secondary_sun_color (RGB 0-255): vdl_sun2 [r g b]", function(r, g, b)
    _show_or_set_bytes("sun2", "sun2", r, g, b)
end)
mod:command("vdl_amb", "Show or set ambient_tint (RGB 0-255): vdl_amb [r g b]", function(r, g, b)
    _show_or_set_bytes("amb", "amb", r, g, b)
end)
mod:command("vdl_amb_top", "Show or set ambient_tint_top (RGB 0-255): vdl_amb_top [r g b]", function(r, g, b)
    _show_or_set_bytes("amb_top", "amb_top", r, g, b)
end)
mod:command("vdl_fog", "Show or set fog_color (RGB 0-255): vdl_fog [r g b]", function(r, g, b)
    _show_or_set_bytes("fog", "fog", r, g, b)
end)

mod:command("vdl_exp", "Show or set exposure (scalar): vdl_exp [value]", function(val)
    local profile = _require_profiled_level(); if not profile then return end
    if val == nil then
        local sample_str = _LAST_SAMPLED_EXP and string.format("%.3f", _LAST_SAMPLED_EXP) or "(not sampled yet)"
        local override_str = profile.exp and string.format("%.3f", profile.exp) or "(none — using vanilla)"
        mod:echo("[vdl] exp:  (scalar; vanilla here ~0.05)")
        mod:echo(string.format("       vanilla  = %s", sample_str))
        mod:echo(string.format("       override = %s", override_str))
        return
    end
    local n = _to_num(val)
    if not n then mod:echo("[vdl] exp: need a number"); return end
    profile.exp = n
    mod:echo(string.format("[vdl] exp = %.3f", n))
end)

-- ============================================================
-- Light commands (global)
-- ============================================================

local function _light_show_or_set(field_color, field_intensity, label, r_or_int, g, b)
    local profile = _require_profiled_level(); if not profile then return end
    if r_or_int == nil and g == nil and b == nil then
        local ov_c = profile[field_color]
        local ov_i = profile[field_intensity]
        mod:echo(string.format("[vdl] %s:", label))
        mod:echo(string.format("       color     = %s", ov_c and _bytes_str(ov_c) or "(none — using vanilla)"))
        mod:echo(string.format("       intensity = %s", ov_i and string.format("%.3f", ov_i) or "(none — using vanilla)"))
        return
    end
    local nr, ng, nb = _to_int(r_or_int), _to_int(g), _to_int(b)
    if not (nr and ng and nb) then
        mod:echo(string.format("[vdl] %s: need three integers (0-255)", label)); return
    end
    profile[field_color] = { nr, ng, nb }
    local n = _apply_lights_to_cached()
    mod:echo(string.format("[vdl] %s color = %d %d %d; reapplied to %d lights", label, nr, ng, nb, n))
end

local function _light_intensity_set(field, label, val)
    local profile = _require_profiled_level(); if not profile then return end
    if val == nil then
        local ov = profile[field]
        mod:echo(string.format("[vdl] %s intensity = %s", label,
            ov and string.format("%.3f", ov) or "(none — using vanilla)"))
        return
    end
    local n = _to_num(val); if not n then mod:echo("[vdl] need a number"); return end
    profile[field] = n
    local applied = _apply_lights_to_cached()
    mod:echo(string.format("[vdl] %s intensity = %.3f; reapplied to %d lights", label, n, applied))
end

mod:command("vdl_light", "Global per-light color (RGB 0-255), applies to lights NOT in a more-specific group: vdl_light [r g b]", function(r, g, b)
    _light_show_or_set("light_color", "light_intensity", "global light", r, g, b)
end)
mod:command("vdl_light_int", "Global per-light intensity (scalar): vdl_light_int [value]", function(val)
    _light_intensity_set("light_intensity", "global light", val)
end)

-- Torches group
mod:command("vdl_torch", "Torches color (RGB 0-255). Matches unit names containing torch/brazier/candle/lantern/sconce: vdl_torch [r g b]", function(r, g, b)
    _light_show_or_set("light_torches_color", "light_torches_intensity", "torches", r, g, b)
end)
mod:command("vdl_torch_int", "Torches intensity (scalar): vdl_torch_int [value]", function(val)
    _light_intensity_set("light_torches_intensity", "torches", val)
end)
mod:command("vdl_torch_patterns", "Set/clear torch name patterns (comma-separated). No args = show. 'reset' = use defaults.", function(...)
    local profile = _require_profiled_level(); if not profile then return end
    local args = {...}
    if #args == 0 then
        local p = profile.torch_patterns or _DEFAULT_TORCH_PATTERNS
        mod:echo(string.format("[vdl] torch_patterns = %s%s",
            table.concat(p, ", "),
            profile.torch_patterns == nil and "  (default)" or ""))
        return
    end
    if args[1] == "reset" then
        profile.torch_patterns = nil
        mod:echo("[vdl] torch_patterns = default")
        return
    end
    -- Accept comma- or space-separated list
    local joined = table.concat(args, " ")
    local list = {}
    for word in string.gmatch(joined, "[^,%s]+") do
        list[#list + 1] = string.lower(word)
    end
    profile.torch_patterns = list
    mod:echo("[vdl] torch_patterns = " .. table.concat(list, ", "))
end)

-- ============================================================
-- Light discovery
-- ============================================================

mod:command("vdl_lights", "Print counts of lights per group", function()
    local _ = _require_profiled_level(); if _ == nil then return end
    local counts = { torches = 0, general = 0 }
    for i = 1, #_CACHED_LIGHTS do
        local e = _CACHED_LIGHTS[i]
        counts[e.group] = (counts[e.group] or 0) + 1
    end
    mod:echo(string.format("[vdl] lights: total=%d  torches=%d  general=%d",
        #_CACHED_LIGHTS, counts.torches, counts.general))
end)

mod:command("vdl_lights_list", "List lights (optional name-substring filter): vdl_lights_list [pattern]", function(pattern)
    local _ = _require_profiled_level(); if _ == nil then return end
    local needle = pattern and string.lower(pattern) or nil
    local shown = 0
    for i = 1, #_CACHED_LIGHTS do
        local e = _CACHED_LIGHTS[i]
        if not needle or (e.name and string.find(string.lower(e.name), needle, 1, true)) then
            mod:echo(string.format("  #%-3d  group=%-7s  y=%6.2f  %s",
                i, e.group, e.y or 0, tostring(e.name)))
            shown = shown + 1
            if shown >= 30 then
                mod:echo(string.format("  ... (truncated; %d more match)", #_CACHED_LIGHTS - i))
                break
            end
        end
    end
    if shown == 0 then mod:echo("[vdl] no lights matched") end
end)

-- ============================================================
-- Profile management
-- ============================================================

mod:command("vdl_clear", "Clear an override: vdl_clear <field>  fields: sky/sun/sun2/amb/amb_top/fog/exp/light/light_int/torch/torch_int/torch_patterns/all", function(field)
    local profile = _require_profiled_level(); if not profile then return end
    if field == nil then
        mod:echo("[vdl] need a field. See `vdl_clear <field>` help.")
        return
    end
    field = string.lower(field)
    if field == "all" then
        for k in pairs(profile) do profile[k] = nil end
        _apply_lights_to_cached()
        mod:echo("[vdl] cleared ALL overrides for current level")
        return
    end
    local alias = {
        light = "light_color", light_int = "light_intensity",
        torch = "light_torches_color", torch_int = "light_torches_intensity",
    }
    local key = alias[field] or field
    profile[key] = nil
    _apply_lights_to_cached()
    mod:echo(string.format("[vdl] cleared %s", field))
end)

mod:command("vdl_reset", "Reset current level's profile to all-vanilla + reapply", function()
    local _, key = _require_profiled_level(); if not key then return end
    _PROFILES[key] = _default_profile()
    _apply_lights_to_cached()
    mod:echo(string.format("[vdl] reset profile for %s", key))
end)

mod:command("vdl_reapply", "Re-walk level units, re-cache lights, reapply current profile", function()
    local _, key = _require_profiled_level(); if not key then return end
    local world = Managers.state.game_mode and Managers.state.game_mode._world
    if not world then mod:echo("[vdl] no world available"); return end
    local count = _capture_and_apply_lights(world)
    mod:echo(string.format("[vdl] reapply: %d lights cached + tinted", count))
end)

mod:command("vdl_dump", "Print the current level's profile (copy-paste-able into _PROFILES)", function()
    local profile, key = _require_profiled_level(); if not profile then return end
    mod:echo(string.format("[vdl] %s = {  -- %s", key, _LEVEL_DISPLAY[key] or "?"))
    local function vec3_line(short, label)
        local v = profile[short]
        if v then
            mod:echo(string.format("    %s = { %d, %d, %d },", short, v[1] or 0, v[2] or 0, v[3] or 0))
        else
            mod:echo(string.format("    -- %-12s (vanilla)", short .. ":"))
        end
    end
    local function num_line(short)
        local v = profile[short]
        if v then mod:echo(string.format("    %s = %.3f,", short, v))
        else mod:echo(string.format("    -- %-12s (vanilla)", short .. ":")) end
    end
    vec3_line("sky")
    vec3_line("sun")
    vec3_line("sun2")
    vec3_line("amb")
    vec3_line("amb_top")
    vec3_line("fog")
    num_line("exp")
    vec3_line("light_color")
    num_line("light_intensity")
    vec3_line("light_torches_color")
    num_line("light_torches_intensity")
    if profile.torch_patterns then
        mod:echo(string.format("    torch_patterns = { %q },", table.concat(profile.torch_patterns, '", "')))
    else
        mod:echo("    -- torch_patterns: (default: torch/brazier/candle/lantern/sconce)")
    end
    mod:echo("},")
end)

mod:command("vdl_save", "Persist all per-level profiles to VMF settings (survives restart)", function()
    local snapshot = {}
    for key, p in pairs(_PROFILES) do
        local entry = {}
        for k, v in pairs(p) do
            if type(v) == "table" then
                -- shallow copy of array
                local arr = {}
                for i, x in ipairs(v) do arr[i] = x end
                entry[k] = arr
            else
                entry[k] = v
            end
        end
        snapshot[key] = entry
    end
    mod:set("saved_profiles_v4", snapshot, false)
    local keys = {}
    for k in pairs(snapshot) do keys[#keys+1] = k end
    mod:echo("[vdl] saved profiles for: " .. table.concat(keys, ", "))
end)

mod:command("vdl_level", "Print current level_key and whether it has a profile", function()
    local key = _current_level_key()
    if not key then mod:echo("[vdl] no active level"); return end
    local profiled = _PROFILES[key] ~= nil
    mod:echo(string.format("[vdl] level_key = %s  display = %s  profiled = %s",
        tostring(key), tostring(_LEVEL_DISPLAY[key] or "?"), tostring(profiled)))
end)

-- ============================================================
-- VMF setting-changed: respond to toggle flips mid-mission
-- ============================================================
-- Atmosphere (shading_callback) picks up the toggle change next frame
-- for free. Lights are stickier — they were set absolutely on the
-- engine's Light handles at level start; flipping the toggle here
-- triggers a reapply with the new effective profile. Turning the
-- toggle OFF mid-mission: atmosphere reverts but currently-tinted
-- lights stay tinted (the engine has no read API for Light.color, so
-- we can't restore vanilla — full revert requires a level reload).
mod.on_setting_changed = function(setting_id)
    if not setting_id then return end
    if string.sub(setting_id, 1, 7) ~= "enable_" then return end
    local level_key = string.sub(setting_id, 8)
    local current = _current_level_key()
    if current ~= level_key then return end  -- toggle for some other level
    _apply_lights_to_cached()
end

mod:command("vdl_help", "List Verminious Dreams Lighting commands", function()
    local lines = {
        "[vdl] commands. RGB = bytes 0-255. No args = print current.",
        "  --- atmosphere ---",
        "  vdl_sky/sun/sun2/amb/amb_top/fog [r g b]   ShadingEnvironment channels",
        "  vdl_exp [value]                            exposure scalar",
        "  --- per-light groups ---",
        "  vdl_torch [r g b]   /  vdl_torch_int [v]   torch/brazier/candle/lantern lights",
        "  vdl_torch_patterns [list|reset]            override which name substrings count as torches",
        "  vdl_light [r g b]   /  vdl_light_int [v]   everything else (the global fallback)",
        "  --- discovery ---",
        "  vdl_lights                                 counts per group",
        "  vdl_lights_list [pattern]                  list lights (filter by unit name substring)",
        "  --- profile ---",
        "  vdl_clear <field> | vdl_reset | vdl_reapply",
        "  vdl_dump                                   copy-paste-able _PROFILES block",
        "  vdl_save                                   persist all profiles",
        "  vdl_level                                  show current level_key + profile status",
    }
    for i = 1, #lines do mod:echo(lines[i]) end
end)

mod:info("[mem-probe] vdl boot_lua=+%.1f MB (of ~1024 MB lua_heap cap)", (collectgarbage("count") - _MEM_PROBE_T0_VDLS) / 1024)
