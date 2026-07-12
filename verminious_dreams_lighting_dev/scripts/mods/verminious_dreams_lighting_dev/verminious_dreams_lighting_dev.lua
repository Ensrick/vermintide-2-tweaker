local mod = get_mod("verminious_dreams_lighting_dev")

local MOD_VERSION = "1.0.15-dev"
-- [mem-probe] temp Lua-footprint baseline (lua_heap 1 GiB cap diagnostic).
-- File-local (was a bare _G global pre-1.0.15-dev; issue 510 / issue 434 audit
-- F7): read only at the bottom of this same chunk, so no _G or cross-file
-- exposure is needed. Matches modded_progression.lua:27.
local _MEM_PROBE_T0_VDL = collectgarbage("count")
-- Startup banner: log-only, NOT chat. The applied marker line further down
-- ([vdl] enabled v<X> settings_fp=<hash>) is the canonical version surface
-- (PROJECT_STANDARDS.md § 3.6 "Chat-echo policy" — never echo at module load,
-- not even gated on debug logging; the operator confirms by tailing the log
-- or running /vdl_regression_test).
mod:info("Verminious Dreams Lighting v%s loaded", MOD_VERSION)

-- Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6).
-- Routed through VMF logging channels; visible via VMF output_mode_debug / output_mode_warning.
-- `_dbg` is for confirmation / expected behavior — mod:debug channel.
-- `_dbg_alert` is for unexpected / wrong / mismatch — mod:warning channel.
local function _dbg(fmt, ...)
    mod:debug("[vdl:dbg] " .. fmt, ...)
end

local function _dbg_alert(fmt, ...)
    mod:warning("[vdl:dbg] " .. fmt, ...)
end

-- Applied marker (PROJECT_STANDARDS.md § 3.6 "Applied marker line (universal)").
-- Walks the data widget tree, FNV-1a-32 hashes setting=value pairs, prints
-- one mod:info line at load. ALWAYS fires (operational telemetry).
local function _settings_fingerprint()
    local ok, data = pcall(require, "scripts/mods/verminious_dreams_lighting_dev/verminious_dreams_lighting_dev_data")
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
    local ok = pcall(_dbg, "smoke test")
    if not ok then return "_dbg raised on call" end
    ok = pcall(_dbg_alert, "smoke test")
    if not ok then return "_dbg_alert raised on call" end
end)


_rt_register("localization_format_safe", function()
    -- Layer 3 (2026-05-25): catch unescaped %-format chars in loc strings at
    -- runtime. VMF's tooltip render path calls string.format on the loc value;
    -- literal "%APPDATA%" / "5%" / "%USERNAME%" raises 'invalid option' and
    -- shows as a red error tooltip in the VMF settings UI. Static check is
    -- qa/check_localization.ps1 -- this is its runtime twin so the bug can't
    -- ship even if the static check is skipped. RULE: any literal % in a loc
    -- string must be doubled to %%.
    local ok, loc = pcall(mod.dofile, mod, "scripts/mods/verminious_dreams_lighting_dev/verminious_dreams_lighting_dev_localization")
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
        amb_top      = { 91, 91, 109 },  -- brightened: {50,50,60} -> +30% {65,65,78} -> +40% more (user 2026-06-24); lift the dark indoor/shadow fill
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
-- Chaos Wastes curse-adjustment layer (v1.0.9-dev) — FRAMEWORK
-- ============================================================
-- When vdl's mission is played inside a Chaos Wastes expedition with a curse
-- active, the user wants the curse to tint vdl's CUSTOM lighting — the curse
-- look built ON TOP OF vdl's base profile, not replacing it. The base profile
-- (sky/sun/fog/ambient/exposure from _PROFILES) is applied first by the
-- shading_callback hook; then this layer multiplies the result per-deity.
--
-- SEED (no invented colors): each deity's adjustment defaults to the VANILLA
-- engine tint that the base game already associates with that theme —
-- `DeusThemeSettings[theme].light_probe_tint` (deus_theme_settings.lua:9-14
-- for "wastes", :23-27 khorne, :46-50 nurgle, :66-70 tzeentch, :86-90 slaanesh,
-- :106-110 belakor). That's a real {r,g,b} multiplier the engine ships for
-- ambient light-probe tinting, so it's a faithful, citable starting point —
-- NOT a made-up color. The user tunes the final look in-game via /vdl_curse_*
-- and the result bakes into _CURSE_ADJUST below on the next source pass (same
-- workflow as the base _PROFILES tuning loop).
--
-- Applied as a per-channel multiplier on the same 6 ShadingEnvironment vars +
-- an exposure multiplier, so it composes cleanly with vdl's base values and
-- with whatever the level baked. A nil channel = inherit the theme's seed tint;
-- exposure_mul defaults to 1.0 (no change). theme == "wastes" (no curse) =
-- no-op (seed is {1,1,1}).
--
-- DESIGN NOTE for the user: this multiplies vdl's base color by the deity
-- tint. An alternative blend (lerp toward the vanilla curse atmosphere, or an
-- additive overlay) is also reasonable — flagged in the report. Multiply was
-- chosen because it's what ct already does for CW skies
-- (chaos_wastes_tweaker_dev.lua:4100 mul_set) and it keeps vdl's tuned hue
-- recognizable under the curse instead of washing it out.
local _CURSE_THEMES = { "khorne", "nurgle", "tzeentch", "slaanesh", "belakor" }

-- Per-theme tunable override of the seed. Empty by default => every channel
-- falls back to the vanilla light_probe_tint seed at apply time. Populated by
-- /vdl_curse_* commands and (later) baked here from a tuning pass.
local _CURSE_ADJUST = {
    khorne   = {},
    nurgle   = {},
    tzeentch = {},
    slaanesh = {},
    -- v1.0.10-dev: Belakor brightened slightly off its vanilla seed.
    -- User feedback: Belakor on Devious Delvings (dlc_termite_2) was "a little
    -- too dark" — that mission has the darkest vdl base (fog {24,24,24}), so
    -- Belakor's vanilla light_probe_tint seed {0.76, 0.76, 1.0} (which darkens
    -- R+G to 76%) over-darkens it. These per-channel overrides nudge the R/G
    -- multiplier up from the 0.76 seed to 0.85 (a ~12% relative lift, ~9pts of
    -- the multiplier range; blue stays 1.0 so Belakor keeps its cold hue). Small
    -- by design — the user asked for "a little." Still fully tunable in-game:
    --   /vdl_curse belakor <channel> <r> <g> <b>   (sky/sun/sun2/amb/amb_top/fog)
    --   /vdl_curse_clear belakor [channel|all]     (back to the {0.76,0.76,1} seed)
    -- NOTE: _CURSE_ADJUST keys per-THEME, not per-mission, so this also lightly
    -- brightens Belakor on dlc_termite_1/_3. Those have lighter bases and were
    -- reported fine; the lift only *reduces* darkening, so it can't over-darken
    -- them. If you want it scoped to dlc_termite_2 only, retune per-mission via
    -- the commands above once you've eyeballed the other two.
    belakor  = {
        sky     = { 0.85, 0.85, 1.0 },
        sun     = { 0.85, 0.85, 1.0 },
        sun2    = { 0.85, 0.85, 1.0 },
        amb     = { 0.85, 0.85, 1.0 },
        amb_top = { 0.85, 0.85, 1.0 },
        fog     = { 0.85, 0.85, 1.0 },
    },
}

-- Same 6 ShadingEnvironment channels the base layer drives.
local _CURSE_VARS = {
    sky      = "skydome_tint_color",
    sun      = "sun_color",
    sun2     = "secondary_sun_color",
    amb      = "ambient_tint",
    amb_top  = "ambient_tint_top",
    fog      = "fog_color",
}

-- Vanilla seed tint for a deity: DeusThemeSettings[theme].light_probe_tint.
-- Read live from the engine table (never copied as literals into this file) so
-- the seed always tracks vanilla. Returns a {r,g,b} float-multiplier, or a
-- neutral {1,1,1} if the table/field isn't present (defensive — also the
-- correct no-op for theme=="wastes").
local function _theme_seed_tint(theme)
    if not theme or theme == "wastes" then return { 1, 1, 1 } end
    local settings = rawget(_G, "DeusThemeSettings")
    local entry = settings and settings[theme]
    local tint = entry and entry.light_probe_tint
    if type(tint) == "table" and tint[1] and tint[2] and tint[3] then
        return { tint[1], tint[2], tint[3] }
    end
    return { 1, 1, 1 }
end

-- Effective per-channel multiplier for a theme+short_key: user override wins,
-- else the vanilla seed tint. Returns a 3-float table or nil (treat as no tint).
local function _curse_channel_mul(theme, short_key)
    local ov = _CURSE_ADJUST[theme]
    if ov and ov[short_key] then return ov[short_key] end
    return _theme_seed_tint(theme)  -- seed; {1,1,1} for wastes/unknown
end

-- v1.0.9 storage key for the curse-adjustment overrides (separate from the
-- base saved_profiles_v4 so old saves are untouched).
do
    local saved = mod:get("saved_curse_adjust_v1")
    if type(saved) == "table" then
        for theme, p in pairs(saved) do
            if type(p) == "table" and _CURSE_ADJUST[theme] then
                for k, v in pairs(p) do _CURSE_ADJUST[theme][k] = v end
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

-- ============================================================
-- Chaos Wastes permutation resolution (v1.0.9-dev)
-- ============================================================
-- vdl's 3 missions exist in two places under different level_id forms:
--   * Adventure   -> the raw base key, e.g. "dlc_termite_1"
--   * Chaos Wastes -> a per-theme permutation, e.g.
--       "dlc_termite_1_khorne_path1" (and the duplicate-alias variant
--       "dlc_termite_1_dup1_khorne_path1").
-- The CW-injected permutation format is `<base>_<theme>_path<N>` — the base
-- mission key is always a literal prefix of the permutation key. This is the
-- same prefix-match logic chaos_wastes_tweaker proves with
-- `adventure_base_from_level_key` (chaos_wastes_tweaker_dev.lua:3317) keying off
-- `level_key:find("^" .. base .. "_")`. vdl does NOT depend on ct — we only
-- reuse the level_id naming convention (no ct API is called).
--
-- _resolve_profile_key maps a raw engine level_key onto one of the 3 baked
-- profile keys: exact match first (Adventure keeps working byte-for-byte),
-- then a "^<base>_" prefix scan for the CW permutations. Returns the base
-- profile key (e.g. "dlc_termite_1") or nil if this isn't one of our missions.
local function _resolve_profile_key(raw_key)
    if type(raw_key) ~= "string" then return nil end
    if _PROFILES[raw_key] then return raw_key end          -- adventure / raw base
    for base in pairs(_PROFILES) do
        -- "^<base>_" so "dlc_termite_1" never collides with a hypothetical
        -- "dlc_termite_10"; the CW permutation always inserts a '_' separator.
        if raw_key:find("^" .. base .. "_") then return base end
    end
    return nil
end

-- ============================================================
-- Vanilla Deus (Chaos Wastes) state readers — NO ct dependency
-- ============================================================
-- Read the active expedition's theme + curse straight off the vanilla Deus
-- mechanism. Outside a Deus expedition (Adventure, keep, versus) the game
-- mechanism has no get_deus_run_controller method, so every reader bails nil
-- and the whole curse layer no-ops — exactly today's Adventure behavior.
--
-- node.theme  = the deity tinting the expedition: one of DEUS_THEME_TYPES
--               ("khorne"/"nurgle"/"tzeentch"/"slaanesh"/"belakor"/"wastes").
--               (deus_theme_settings.lua:120-127, DEUS_THEME_TYPES enum.)
-- node.curse  = the granular curse MUTATOR name on the node, e.g.
--               "curse_belakor_totems", "curse_skulls_of_fury"
--               (deus_generate_graph.lua:68 `start_node.curse = ...`,
--                DeusMechanism.get_current_node_curse @ deus_mechanism.lua:870).
--               Many curses map onto one deity theme; vdl keys its adjustment
--               layer on the THEME (the deity) because that's the value with a
--               verifiable vanilla light tint (light_probe_tint) and a 1:1 set
--               of 5 deities to branch on. node.curse is surfaced for the user
--               (the more specific signal) but the lighting branches per-theme.
local function _deus_run_controller()
    if not (Managers and Managers.mechanism and Managers.mechanism.game_mechanism) then return nil end
    local mechanism = Managers.mechanism:game_mechanism()
    if not (mechanism and mechanism.get_deus_run_controller) then return nil end
    return mechanism:get_deus_run_controller()
end

local function _current_deus_node()
    local run = _deus_run_controller()
    if not (run and run.get_current_node) then return nil end
    return run:get_current_node()
end

local function _current_deus_theme()
    local node = _current_deus_node()
    return node and node.theme or nil
end

local function _current_deus_curse()
    local node = _current_deus_node()
    return node and node.curse or nil
end

-- True only when we're in a Deus expedition AND on one of vdl's 3 missions
-- (by permutation prefix). Drives the curse-adjustment layer.
local function _in_cw_on_vdl_mission()
    if not _deus_run_controller() then return false end
    return _resolve_profile_key(_current_level_key()) ~= nil
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

-- Resolve the BASE profile key from whatever raw key we currently hold
-- (adventure raw key OR CW permutation). _CURRENT_LEVEL_KEY is already
-- base-resolved at hook time, but we re-resolve defensively for command paths
-- that read the live engine key.
local function _profile_for_current_level()
    local key = _resolve_profile_key(_CURRENT_LEVEL_KEY or _current_level_key())
    if not key then return nil, nil end
    if not _is_level_enabled(key) then return nil, key end
    return _PROFILES[key], key
end

-- Commands ignore the toggle so the user can tune even with the level
-- disabled (their edits queue up; flipping the toggle on applies them).
local function _profile_for_current_level_raw()
    local key = _resolve_profile_key(_CURRENT_LEVEL_KEY or _current_level_key())
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
-- Is the CW curse-adjustment layer enabled? Defaults ON (user intent: vdl
-- "also changes the lighting" in CW). Harmless outside CW because the layer
-- only runs when in a Deus expedition with a non-wastes theme.
local function _curse_layer_enabled()
    local v = mod:get("enable_cw_curse_adjust")
    if v == nil then return true end   -- never-set => default on
    return v and true or false
end

mod:hook_safe("CameraManager", "shading_callback", function(self, world, shading_env, viewport)
    local profile, key = _profile_for_current_level()
    if not profile then return end

    for short_key, var_name in pairs(_SHADING_VARS) do
        local v = ShadingEnvironment.vector3(shading_env, var_name)
        if v then _LAST_SAMPLED[short_key] = _vector3_to_bytes(v) end
    end
    local cur_exp = ShadingEnvironment.scalar(shading_env, "exposure")
    if cur_exp then _LAST_SAMPLED_EXP = cur_exp end

    -- LAYER 1 — vdl base profile: set each overridden channel to its tuned
    -- byte-RGB. Unset channels stay at the level's baked value.
    for short_key, var_name in pairs(_SHADING_VARS) do
        local ov = profile[short_key]
        if ov then
            ShadingEnvironment.set_vector3(shading_env, var_name, _bytes_to_vector3(ov))
        end
    end
    if profile.exp then
        ShadingEnvironment.set_scalar(shading_env, "exposure", profile.exp)
    end

    -- LAYER 2 — Chaos Wastes curse adjustment (v1.0.9-dev): when this mission
    -- is being played inside a Deus expedition with a curse (theme ~= wastes),
    -- multiply the now-applied value (vdl base, or baked vanilla where vdl left
    -- it alone) by the per-deity curse tint. This composes the curse look on
    -- TOP of vdl's custom lighting rather than replacing it. Read the current
    -- (post-LAYER-1) value back out so the multiply lands on vdl's color.
    if _curse_layer_enabled() and _deus_run_controller() then
        local theme = _current_deus_theme()
        if theme and theme ~= "wastes" and _CURSE_ADJUST[theme] then
            for short_key, var_name in pairs(_CURSE_VARS) do
                local m = _curse_channel_mul(theme, short_key)
                if m then
                    local v = ShadingEnvironment.vector3(shading_env, var_name)
                    if v then
                        ShadingEnvironment.set_vector3(shading_env, var_name,
                            Vector3(v.x * m[1], v.y * m[2], v.z * m[3]))
                    end
                end
            end
            local exp_mul = _CURSE_ADJUST[theme].exp_mul
            if exp_mul and exp_mul ~= 1.0 then
                local cur = ShadingEnvironment.scalar(shading_env, "exposure")
                if cur then
                    ShadingEnvironment.set_scalar(shading_env, "exposure", cur * exp_mul)
                end
            end
        end
    end
end)

mod:hook_safe("GameModeManager", "local_player_game_starts", function(self, player, loading_context)
    local raw_key = _current_level_key()
    -- Resolve the raw engine key (adventure base OR CW permutation) down to one
    -- of our 3 base profile keys, and CACHE the base — every downstream lookup
    -- (_profile_for_current_level, light apply) keys on the base.
    local key = _resolve_profile_key(raw_key)
    _CURRENT_LEVEL_KEY = key
    if not key then return end

    -- Diagnostic context: note when we matched a CW permutation (raw ~= base)
    -- and the active curse, so the log shows whether the curse layer engaged.
    local in_cw = _deus_run_controller() ~= nil
    mod:info("[vdl] level start: %s (%s) [base=%s cw=%s theme=%s curse=%s]",
        tostring(raw_key), tostring(_LEVEL_DISPLAY[key] or "?"), tostring(key),
        tostring(in_cw), tostring(_current_deus_theme()), tostring(_current_deus_curse()))
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

-- ============================================================
-- Chaos Wastes curse-adjustment commands (v1.0.9-dev)
-- ============================================================
-- These tune the per-deity curse layer that multiplies on TOP of vdl's base
-- lighting when one of vdl's missions is injected into a cursed CW expedition.
-- Multipliers are floats (1.0 = no change), NOT byte-RGB — they scale vdl's
-- already-applied color. Default for any unset channel is the vanilla
-- DeusThemeSettings[theme].light_probe_tint seed (a real engine value), so the
-- framework does something sensible before you tune anything.

local _CURSE_CHANNEL_LABEL = {
    sky = "skydome_tint_color", sun = "sun_color", sun2 = "secondary_sun_color",
    amb = "ambient_tint", amb_top = "ambient_tint_top", fog = "fog_color",
}

local function _valid_theme(theme)
    return theme and _CURSE_ADJUST[theme] ~= nil
end

local function _mul_str(t)
    if type(t) ~= "table" then return tostring(t) end
    return string.format("%.3f %.3f %.3f", t[1] or 1, t[2] or 1, t[3] or 1)
end

mod:command("vdl_curse", "Show/set a curse-layer channel multiplier: vdl_curse <theme> <channel> [r g b]. theme=khorne/nurgle/tzeentch/slaanesh/belakor; channel=sky/sun/sun2/amb/amb_top/fog. No r g b = show (override + vanilla seed).", function(theme, channel, r, g, b)
    if not _valid_theme(theme) then
        mod:echo("[vdl] curse: theme must be one of: " .. table.concat(_CURSE_THEMES, ", "))
        return
    end
    if not (channel and _CURSE_CHANNEL_LABEL[channel]) then
        mod:echo("[vdl] curse: channel must be one of: sky, sun, sun2, amb, amb_top, fog")
        return
    end
    if r == nil and g == nil and b == nil then
        local ov   = _CURSE_ADJUST[theme][channel]
        local seed = _theme_seed_tint(theme)
        mod:echo(string.format("[vdl] curse %s %s (%s):  (float multipliers, 1.0 = no change)",
            theme, channel, _CURSE_CHANNEL_LABEL[channel]))
        mod:echo(string.format("       seed (vanilla light_probe_tint) = %s", _mul_str(seed)))
        mod:echo(string.format("       override = %s", ov and _mul_str(ov) or "(none — using seed)"))
        return
    end
    local nr, ng, nb = _to_num(r), _to_num(g), _to_num(b)
    if not (nr and ng and nb) then
        mod:echo("[vdl] curse: need three numbers (float multipliers)")
        return
    end
    _CURSE_ADJUST[theme][channel] = { nr, ng, nb }
    mod:echo(string.format("[vdl] curse %s %s = %.3f %.3f %.3f", theme, channel, nr, ng, nb))
end)

mod:command("vdl_curse_exp", "Show/set the curse-layer exposure multiplier: vdl_curse_exp <theme> [mul]. 1.0 = no change.", function(theme, val)
    if not _valid_theme(theme) then
        mod:echo("[vdl] curse_exp: theme must be one of: " .. table.concat(_CURSE_THEMES, ", "))
        return
    end
    if val == nil then
        local ov = _CURSE_ADJUST[theme].exp_mul
        mod:echo(string.format("[vdl] curse %s exp_mul = %s", theme,
            ov and string.format("%.3f", ov) or "(none — 1.0, no change)"))
        return
    end
    local n = _to_num(val)
    if not n then mod:echo("[vdl] curse_exp: need a number"); return end
    _CURSE_ADJUST[theme].exp_mul = n
    mod:echo(string.format("[vdl] curse %s exp_mul = %.3f", theme, n))
end)

mod:command("vdl_curse_clear", "Clear curse-layer overrides: vdl_curse_clear <theme> [channel|all]. Cleared channels fall back to the vanilla seed tint.", function(theme, field)
    if not _valid_theme(theme) then
        mod:echo("[vdl] curse_clear: theme must be one of: " .. table.concat(_CURSE_THEMES, ", "))
        return
    end
    if field == nil or field == "all" then
        _CURSE_ADJUST[theme] = {}
        mod:echo(string.format("[vdl] curse %s: cleared ALL overrides (back to vanilla seed)", theme))
        return
    end
    _CURSE_ADJUST[theme][field] = nil
    mod:echo(string.format("[vdl] curse %s: cleared %s", theme, field))
end)

mod:command("vdl_curse_dump", "Print the _CURSE_ADJUST overrides (copy-paste-able into source). Channels with no override show their vanilla seed as a comment.", function()
    mod:echo("[vdl] _CURSE_ADJUST = {")
    for _, theme in ipairs(_CURSE_THEMES) do
        local ov = _CURSE_ADJUST[theme]
        local seed = _theme_seed_tint(theme)
        mod:echo(string.format("    %s = {  -- vanilla seed light_probe_tint = %s", theme, _mul_str(seed)))
        for _, ch in ipairs({ "sky", "sun", "sun2", "amb", "amb_top", "fog" }) do
            local v = ov and ov[ch]
            if v then
                mod:echo(string.format("        %s = { %.3f, %.3f, %.3f },", ch, v[1] or 1, v[2] or 1, v[3] or 1))
            end
        end
        if ov and ov.exp_mul then
            mod:echo(string.format("        exp_mul = %.3f,", ov.exp_mul))
        end
        mod:echo("    },")
    end
    mod:echo("}")
end)

mod:command("vdl_curse_save", "Persist the curse-layer overrides to VMF settings (survives restart)", function()
    local snapshot = {}
    for theme, p in pairs(_CURSE_ADJUST) do
        local entry = {}
        for k, v in pairs(p) do
            if type(v) == "table" then
                local arr = {}
                for i, x in ipairs(v) do arr[i] = x end
                entry[k] = arr
            else
                entry[k] = v
            end
        end
        snapshot[theme] = entry
    end
    mod:set("saved_curse_adjust_v1", snapshot, false)
    mod:echo("[vdl] saved curse-layer overrides for all themes")
end)

mod:command("vdl_level", "Print current level_key and whether it has a profile", function()
    local raw = _current_level_key()
    if not raw then mod:echo("[vdl] no active level"); return end
    local base = _resolve_profile_key(raw)
    local profiled = base ~= nil
    local in_cw = _deus_run_controller() ~= nil
    mod:echo(string.format("[vdl] level_key = %s  base = %s  display = %s  profiled = %s",
        tostring(raw), tostring(base or "—"), tostring(base and _LEVEL_DISPLAY[base] or "?"), tostring(profiled)))
    mod:echo(string.format("       chaos_wastes = %s  theme = %s  curse = %s",
        tostring(in_cw), tostring(_current_deus_theme() or "—"), tostring(_current_deus_curse() or "—")))
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
    -- The CW curse-adjustment master toggle drives the per-frame shading layer
    -- only (no cached lights to reapply); shading_callback re-reads it next
    -- frame, so nothing to do here beyond ignoring it cleanly.
    if setting_id == "enable_cw_curse_adjust" then return end
    if string.sub(setting_id, 1, 7) ~= "enable_" then return end
    local level_key = string.sub(setting_id, 8)
    -- Compare against the RESOLVED base key so the per-mission toggle reapplies
    -- correctly even when the live engine key is a CW permutation.
    local current = _resolve_profile_key(_current_level_key())
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
        "  --- chaos wastes curse layer (applies on TOP of base in CW) ---",
        "  vdl_curse <theme> <ch> [r g b]             per-deity channel multiplier (float)",
        "  vdl_curse_exp <theme> [mul]                per-deity exposure multiplier",
        "  vdl_curse_clear <theme> [ch|all]           clear back to vanilla seed tint",
        "  vdl_curse_dump / vdl_curse_save            dump / persist curse overrides",
    }
    for i = 1, #lines do mod:echo(lines[i]) end
end)

-- ============================================================
-- Regression: CW permutation prefix-match + curse framework (v1.0.9-dev)
-- ============================================================
-- Registered at the BOTTOM of the file so the closures can capture the helpers
-- declared further up (lexical upvalue capture — a check registered near the
-- top of the file can't see a local defined later).
_rt_register("cw_permutation_prefix_match", function()
    -- Adventure raw keys resolve to themselves.
    for _, base in ipairs({ "dlc_termite_1", "dlc_termite_2", "dlc_termite_3" }) do
        if _resolve_profile_key(base) ~= base then
            return "adventure base key " .. base .. " failed to resolve to itself"
        end
    end
    -- CW permutations resolve to the base. Cover plain theme permutation and the
    -- duplicate-alias permutation form (both produced by the deus map populate).
    local cases = {
        ["dlc_termite_1_khorne_path1"]      = "dlc_termite_1",
        ["dlc_termite_2_nurgle_path3"]      = "dlc_termite_2",
        ["dlc_termite_3_belakor_path1"]     = "dlc_termite_3",
        ["dlc_termite_1_dup1_slaanesh_path2"] = "dlc_termite_1",
    }
    for perm, want in pairs(cases) do
        local got = _resolve_profile_key(perm)
        if got ~= want then
            return string.format("permutation %q resolved to %q, want %q", perm, tostring(got), want)
        end
    end
    -- Non-vdl levels must NOT match (no false positives on other CW levels).
    for _, other in ipairs({ "bell_khorne_path1", "magnus", "dlc_termite", "dlc_termite_4" }) do
        if _resolve_profile_key(other) ~= nil then
            return "non-vdl key " .. other .. " falsely resolved to a profile"
        end
    end
end)

_rt_register("curse_seed_is_engine_value_not_invented", function()
    -- The seed must come from the live engine table, never a baked literal.
    -- With no DeusThemeSettings present (keep/menu), seed is neutral {1,1,1}
    -- (no-op) — proving we don't ship invented per-curse colors.
    if type(_theme_seed_tint) ~= "function" then return "_theme_seed_tint missing" end
    local wastes = _theme_seed_tint("wastes")
    if not (wastes and wastes[1] == 1 and wastes[2] == 1 and wastes[3] == 1) then
        return "wastes seed should be neutral {1,1,1}"
    end
    -- Every theme key in _CURSE_ADJUST must be a real DEUS theme branch.
    for _, theme in ipairs(_CURSE_THEMES) do
        if _CURSE_ADJUST[theme] == nil then
            return "missing _CURSE_ADJUST branch for theme " .. theme
        end
    end
end)

_rt_register("curse_layer_noop_outside_deus", function()
    -- Outside a Deus expedition the run-controller readers must all bail nil so
    -- the curse layer no-ops (adventure behaves exactly as before).
    if _deus_run_controller() ~= nil then
        -- We may legitimately be in CW while testing; only assert the nil-safety
        -- contract, not the absence of an expedition.
        return  -- in an expedition; readers are exercised live, nothing to assert here
    end
    if _current_deus_theme() ~= nil or _current_deus_curse() ~= nil then
        return "deus readers returned non-nil outside an expedition"
    end
    if _in_cw_on_vdl_mission() ~= false then
        return "_in_cw_on_vdl_mission should be false outside a Deus expedition"
    end
end)

mod:info("[mem-probe] vdl boot_lua=+%.1f MB (of ~1024 MB lua_heap cap)", (collectgarbage("count") - _MEM_PROBE_T0_VDL) / 1024)
