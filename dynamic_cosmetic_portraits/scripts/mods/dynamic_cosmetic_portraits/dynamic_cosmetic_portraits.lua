local mod = get_mod("dynamic_cosmetic_portraits")
_MEM_PROBE_T0_DCP = collectgarbage("count")  -- [mem-probe] temp Lua-footprint baseline (lua_heap 1 GiB cap diagnostic)

local MOD_VERSION = "0.1.14-dev"
-- Startup banner: log-only, NOT chat. The applied marker line further down
-- ([dcp] enabled v<X> settings_fp=<hash>) is the canonical version surface
-- (PROJECT_STANDARDS.md § 3.6 "Chat-echo policy").
mod:info("Dynamic Cosmetic Portraits v%s loaded", MOD_VERSION)

-- Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6).
-- Both gate on `enable_debug_logging`. Both no-op when toggle is off.
-- `_dbg` is for confirmation / expected behavior — file only.
-- `_dbg_alert` is for unexpected / wrong / mismatch — file AND in-game chat.
local function _dbg(fmt, ...)
    if mod:get("enable_debug_logging") then
        mod:info("[dcp:dbg] " .. fmt, ...)
    end
end

local function _dbg_alert(fmt, ...)
    if mod:get("enable_debug_logging") then
        mod:info("[dcp:dbg] " .. fmt, ...)
        mod:echo("[dcp] " .. fmt, ...)
    end
end

-- Applied marker (PROJECT_STANDARDS.md § 3.6 "Applied marker line (universal)").
-- Walks the data widget tree, FNV-1a-32 hashes setting=value pairs, prints
-- one mod:info line at load. ALWAYS fires (operational telemetry).
local function _settings_fingerprint()
    local ok, data = pcall(require, "scripts/mods/dynamic_cosmetic_portraits/dynamic_cosmetic_portraits_data")
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

mod:info("[dcp:LOAD] v%s enabled fp=%s OK", MOD_VERSION, _settings_fingerprint())

-- Per PROJECT_STANDARDS § 3.6 + § 14a: dev/alpha/beta/0.x versions print
-- version to chat on load so the user can see what's active. Stable
-- (>=1.0.0) versions stay silent. Detect via MOD_VERSION string match.
if MOD_VERSION:find("-dev$") or MOD_VERSION:find("-alpha$") or MOD_VERSION:find("-beta$") or MOD_VERSION:find("-rc%d*$") or MOD_VERSION:find("^0%.") then
    mod:echo(string.format("[dcp] v%s loaded", MOD_VERSION))
end

-- v0.1.9: regression test scaffold (dcp had none).
local _RT_CHECKS = {}
local function _rt_register(name, fn)
    _RT_CHECKS[#_RT_CHECKS + 1] = { name = name, fn = fn }
end
mod:command("dcp_regression_test", "Run regression smoke checks for past bugs", function()
    local pass, fail = 0, 0
    mod:echo("=== dcp regression_test (v%s) ===", MOD_VERSION)
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
    local ok, loc = pcall(mod.dofile, mod, "scripts/mods/dynamic_cosmetic_portraits/dynamic_cosmetic_portraits_localization")
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
-- Returns true if the given Gui has the named material loaded.
--
-- IMPORTANT: `Gui.material(gui, name)` does NOT throw on missing materials in
-- this VT2 build — it returns nil silently. So pcall alone is NOT a reliable
-- probe; we MUST inspect the return value too.
local function _gui_has_material(gui, material_name)
    if not gui or not Gui or not Gui.material then return false end
    local ok, mat = pcall(Gui.material, gui, material_name)
    return ok and mat ~= nil
end

-- Force-flush the engine console log so command output is on disk before the
-- user navigates anywhere.
local function _flush_log()
    pcall(function() if io and io.flush then io.flush() end end)
    pcall(function() if Log and Log.flush then Log.flush() end end)
    pcall(function()
        if Application and Application.console_command then
            Application.console_command("flush_log")
            Application.console_command("log_flush")
            Application.console_command("flush")
        end
    end)
    mod:info("[flush] %s", tostring(os.time()))
end

-- ============================================================
-- Dynamic Character Portraits (hat / outfit dependent)
-- ============================================================

-- =============================================================================
-- ADDING A PORTRAIT — READ DEVELOPMENT.md FIRST
-- -----------------------------------------------------------------------------
-- The asset pipeline for new portraits is non-obvious and has been gotten
-- wrong in multiple shipped versions (see CHANGELOG.md v0.1.0 / v0.1.1 /
-- v0.1.2 — each fixed a different free-hand mistake). Always use:
--
--   .\tools\add_portrait.ps1 -SourcePng "<110x130 PNG>" -HatKey "kruber_<key>"
--
-- DO NOT add entries to _PORTRAIT_MATERIALS / _hat_portrait_map /
-- _skin_portrait_map without first running the script to produce the
-- corresponding .png/.texture/.material files. The maps below are LOOKUP
-- tables that assume the assets already exist on disk — adding a key here
-- without the assets crashes "Material not found in Gui" in-game.
--
-- See DEVELOPMENT.md "Adding a new portrait" for the full step-by-step.
-- =============================================================================

-- Custom portrait textures: each portrait size has its own .material file so
-- that Stingray creates a Gui material whose name matches the texture name
-- (file-based naming). No UIAtlasHelper hooks needed — standalone textures
-- bypass atlas lookup and the UI uses Gui.bitmap with the material name.

local _PORTRAIT_MATERIALS = {
    "materials/ui/portrait_kruber_mercenary_hat_0004",
    "materials/ui/medium_portrait_kruber_mercenary_hat_0004",
    "materials/ui/small_portrait_kruber_mercenary_hat_0004",
    "materials/ui/portrait_kruber_mercenary_hat_0009",
    "materials/ui/medium_portrait_kruber_mercenary_hat_0009",
    "materials/ui/small_portrait_kruber_mercenary_hat_0009",
    "materials/ui/portrait_kruber_mercenary_hat_1001",
    "materials/ui/medium_portrait_kruber_mercenary_hat_1001",
    "materials/ui/small_portrait_kruber_mercenary_hat_1001",
    "materials/ui/portrait_kruber_mercenary_hat_1002",
    "materials/ui/medium_portrait_kruber_mercenary_hat_1002",
    "materials/ui/small_portrait_kruber_mercenary_hat_1002",
    "materials/ui/portrait_kruber_mercenary_hat_1003",
    "materials/ui/medium_portrait_kruber_mercenary_hat_1003",
    "materials/ui/small_portrait_kruber_mercenary_hat_1003",
    "materials/ui/portrait_kruber_mercenary_hat_0006",
    "materials/ui/medium_portrait_kruber_mercenary_hat_0006",
    "materials/ui/small_portrait_kruber_mercenary_hat_0006",
    "materials/ui/portrait_kruber_mercenary_hat_0007",
    "materials/ui/medium_portrait_kruber_mercenary_hat_0007",
    "materials/ui/small_portrait_kruber_mercenary_hat_0007",
    "materials/ui/portrait_kruber_skin_es_mercenary_1003",
    "materials/ui/medium_portrait_kruber_skin_es_mercenary_1003",
    "materials/ui/small_portrait_kruber_skin_es_mercenary_1003",
    "materials/ui/portrait_kruber_skin_es_default",
    "materials/ui/medium_portrait_kruber_skin_es_default",
    "materials/ui/small_portrait_kruber_skin_es_default",
    "materials/ui/portrait_kruber_mercenary_hat_0001",
    "materials/ui/medium_portrait_kruber_mercenary_hat_0001",
    "materials/ui/small_portrait_kruber_mercenary_hat_0001",
    "materials/ui/portrait_kruber_mercenary_hat_0003",
    "materials/ui/medium_portrait_kruber_mercenary_hat_0003",
    "materials/ui/small_portrait_kruber_mercenary_hat_0003",
    "materials/ui/portrait_kruber_mercenary_hat_0005",
    "materials/ui/medium_portrait_kruber_mercenary_hat_0005",
    "materials/ui/small_portrait_kruber_mercenary_hat_0005",
}

-- _hat_portrait_map: cosmetic-key (slot_hat) -> texture name set.
-- Adding an entry here REQUIRES the matching asset files to exist
-- (run tools/add_portrait.ps1 first — see banner at top of file).
-- _hat_portrait_map[KEY] is checked SECOND (skin map runs first). If you
-- need a portrait that overrides hats, put it in _skin_portrait_map below.
local _hat_portrait_map = {
    mercenary_hat_0001 = {  -- Estalian Conquistador
        hud    = "portrait_kruber_mercenary_hat_0001",
        medium = "medium_portrait_kruber_mercenary_hat_0001",
        small  = "small_portrait_kruber_mercenary_hat_0001",
    },
    mercenary_hat_0003 = {  -- Plumed Horseshoe
        hud    = "portrait_kruber_mercenary_hat_0003",
        medium = "medium_portrait_kruber_mercenary_hat_0003",
        small  = "small_portrait_kruber_mercenary_hat_0003",
    },
    mercenary_hat_0004 = {  -- Morr's Mask
        hud    = "portrait_kruber_mercenary_hat_0004",
        medium = "medium_portrait_kruber_mercenary_hat_0004",
        small  = "small_portrait_kruber_mercenary_hat_0004",
    },
    mercenary_hat_0005 = {  -- Sellsword's Twinplume
        hud    = "portrait_kruber_mercenary_hat_0005",
        medium = "medium_portrait_kruber_mercenary_hat_0005",
        small  = "small_portrait_kruber_mercenary_hat_0005",
    },
    mercenary_hat_0006 = {
        hud    = "portrait_kruber_mercenary_hat_0006",
        medium = "medium_portrait_kruber_mercenary_hat_0006",
        small  = "small_portrait_kruber_mercenary_hat_0006",
    },
    mercenary_hat_0007 = {
        hud    = "portrait_kruber_mercenary_hat_0007",
        medium = "medium_portrait_kruber_mercenary_hat_0007",
        small  = "small_portrait_kruber_mercenary_hat_0007",
    },
    mercenary_hat_0009 = {
        hud    = "portrait_kruber_mercenary_hat_0009",
        medium = "medium_portrait_kruber_mercenary_hat_0009",
        small  = "small_portrait_kruber_mercenary_hat_0009",
    },
    mercenary_hat_1001 = {
        hud    = "portrait_kruber_mercenary_hat_1001",
        medium = "medium_portrait_kruber_mercenary_hat_1001",
        small  = "small_portrait_kruber_mercenary_hat_1001",
    },
    mercenary_hat_1002 = {
        hud    = "portrait_kruber_mercenary_hat_1002",
        medium = "medium_portrait_kruber_mercenary_hat_1002",
        small  = "small_portrait_kruber_mercenary_hat_1002",
    },
    mercenary_hat_1003 = {
        hud    = "portrait_kruber_mercenary_hat_1003",
        medium = "medium_portrait_kruber_mercenary_hat_1003",
        small  = "small_portrait_kruber_mercenary_hat_1003",
    },
}

-- _skin_portrait_map: cosmetic-key (slot_skin) -> texture name set.
-- Skin/outfit portraits override hat portraits because the outfit replaces
-- Kruber's head model regardless of equipped hat. _sync_portrait_settings
-- checks this map FIRST and falls back to _hat_portrait_map if no skin
-- entry matches. Adding an entry here REQUIRES the matching asset files
-- to exist (run tools/add_portrait.ps1 first).
local _skin_portrait_map = {
    skin_es_mercenary_1003 = {  -- Felix Jaeger
        hud    = "portrait_kruber_skin_es_mercenary_1003",
        medium = "medium_portrait_kruber_skin_es_mercenary_1003",
        small  = "small_portrait_kruber_skin_es_mercenary_1003",
    },
    skin_es_default = {  -- Champion of Ubersreik (VT1 default outfit)
        hud    = "portrait_kruber_skin_es_default",
        medium = "medium_portrait_kruber_skin_es_default",
        small  = "small_portrait_kruber_skin_es_default",
    },
}

local _portrait_materials_ready = false
local _portrait_settings_active = false
local _original_portrait_image = nil
local _original_picking_image = nil
local _last_known_hat_key = nil
local _last_known_skin_key = nil

-- Collect ALL gui handles from every UIRenderer we can find.
local function _collect_all_guis()
    local guis = {}
    local function add(label, renderer)
        if not renderer then return end
        for _, gf in ipairs({"gui", "gui_retained"}) do
            if renderer[gf] then
                guis[#guis + 1] = { label = label .. "." .. gf, gui = renderer[gf] }
            end
        end
    end
    for _, mgr_name in ipairs({"ui", "matchmaking", "transition"}) do
        local mgr = Managers[mgr_name]
        if mgr then
            for _, field in ipairs({"ui_renderer", "_ui_renderer", "renderer"}) do
                if mgr[field] then add("Managers." .. mgr_name .. "." .. field, mgr[field]) end
            end
        end
    end
    local ingame_ui = Managers.ui and Managers.ui._ingame_ui
    if ingame_ui then
        for _, field in ipairs({"ui_renderer", "_ui_renderer"}) do
            if ingame_ui[field] then add("ingame_ui." .. field, ingame_ui[field]) end
        end
    end
    local hud = ingame_ui and ingame_ui._hud
    if hud then
        for _, field in ipairs({"ui_renderer", "_ui_renderer"}) do
            if hud[field] then add("hud." .. field, hud[field]) end
        end
    end
    local unit_frames = hud and (hud._unit_frames_handler or hud.unit_frames_handler)
    if unit_frames then
        for _, field in ipairs({"ui_renderer", "_ui_renderer"}) do
            if unit_frames[field] then add("unit_frames." .. field, unit_frames[field]) end
        end
    end
    return guis
end

local function _check_portrait_materials_ready()
    if _portrait_materials_ready then return true end
    local guis = _collect_all_guis()
    for _, entry in ipairs(guis) do
        if _gui_has_material(entry.gui, "portrait_kruber_mercenary_hat_1002") then
            _portrait_materials_ready = true
            mod:info("[portrait] materials confirmed on %s", entry.label)
            return true
        end
    end
    return false
end

local function _get_kruber_merc_hat_key()
    local pm = Managers.player
    if not pm then return _last_known_hat_key end

    if CosmeticUtils and CosmeticUtils.get_cosmetic_slot then
        for _, player in pairs(pm:players()) do
            local career_name = nil
            pcall(function() career_name = player:career_name() end)
            if not career_name then pcall(function() career_name = player.career_name end) end
            if career_name == "es_mercenary" then
                local ok, hat_data = pcall(CosmeticUtils.get_cosmetic_slot, player, "slot_hat")
                if ok and hat_data and hat_data.item_name then
                    _last_known_hat_key = hat_data.item_name
                    return hat_data.item_name
                end
            end
        end
    end

    if BackendUtils and BackendUtils.get_loadout_item then
        local ok, item = pcall(BackendUtils.get_loadout_item, "es_mercenary", "slot_hat")
        if ok and item then
            local key = item.key or (item.data and item.data.key)
            if key then
                _last_known_hat_key = key
                return key
            end
        end
    end

    return _last_known_hat_key
end

local function _get_kruber_merc_skin_key()
    local pm = Managers.player
    if not pm then return _last_known_skin_key end

    if CosmeticUtils and CosmeticUtils.get_cosmetic_slot then
        for _, player in pairs(pm:players()) do
            local career_name = nil
            pcall(function() career_name = player:career_name() end)
            if not career_name then pcall(function() career_name = player.career_name end) end
            if career_name == "es_mercenary" then
                local ok, skin_data = pcall(CosmeticUtils.get_cosmetic_slot, player, "slot_skin")
                if ok and skin_data and skin_data.item_name then
                    _last_known_skin_key = skin_data.item_name
                    return skin_data.item_name
                end
            end
        end
    end

    if BackendUtils and BackendUtils.get_loadout_item then
        local ok, item = pcall(BackendUtils.get_loadout_item, "es_mercenary", "slot_skin")
        if ok and item then
            local key = item.key or (item.data and item.data.key)
            if key then
                _last_known_skin_key = key
                return key
            end
        end
    end

    return _last_known_skin_key
end

local function _restore_portrait_settings()
    if not _portrait_settings_active then return end
    if not SPProfiles then return end
    local career = SPProfiles[5] and SPProfiles[5].careers and SPProfiles[5].careers[1]
    if career and _original_portrait_image then
        career.portrait_image = _original_portrait_image
        career.picking_image = _original_picking_image
        _portrait_settings_active = false
        mod:info("[portrait] restored career_settings to '%s'", _original_portrait_image)
    end
end

local function _sync_portrait_settings()
    if not SPProfiles then return end
    local career = SPProfiles[5] and SPProfiles[5].careers and SPProfiles[5].careers[1]
    if not career then return end

    if not _original_portrait_image then
        _original_portrait_image = career.portrait_image
        _original_picking_image = career.picking_image
    end

    if not mod:get("dynamic_portraits") then
        _restore_portrait_settings()
        return
    end

    if not _check_portrait_materials_ready() then return end

    -- Skin/outfit takes priority: outfits replace the head model regardless
    -- of which hat is equipped, so a Felix-style skin should override any
    -- hat-specific portrait.
    local skin_key = _get_kruber_merc_skin_key()
    local portraits = skin_key and _skin_portrait_map[skin_key]
    if not portraits then
        local hat_key = _get_kruber_merc_hat_key()
        portraits = hat_key and _hat_portrait_map[hat_key]
    end
    if portraits then
        career.portrait_image = portraits.hud
        career.picking_image = portraits.medium
        if not _portrait_settings_active then
            mod:info("[portrait] swapped career_settings to '%s'", portraits.hud)
        end
        _portrait_settings_active = true
    else
        _restore_portrait_settings()
    end
end

-- Diagnostic: check if VMF registered our custom portrait textures
mod:command("portrait_diag", "Diagnose portrait texture registration + hat state", function()
    local function emit(fmt, ...)
        mod:echo(fmt, ...)
        mod:info("[portrait_diag] " .. fmt, ...)
    end

    local ready = _check_portrait_materials_ready()
    emit("settings_active=%s dynamic_portraits=%s materials_ready=%s",
        tostring(_portrait_settings_active), tostring(mod:get("dynamic_portraits")),
        tostring(ready))
    local career = SPProfiles and SPProfiles[5] and SPProfiles[5].careers and SPProfiles[5].careers[1]
    if career then
        emit("career_settings.portrait_image='%s' picking_image='%s'",
            tostring(career.portrait_image), tostring(career.picking_image))
    end

    local tex_names = {
        "portrait_kruber_mercenary_hat_1002",
        "medium_portrait_kruber_mercenary_hat_1002",
        "small_portrait_kruber_mercenary_hat_1002",
    }
    if UIAtlasHelper then
        emit("UIAtlasHelper functions: has_atlas=%s get_atlas=%s has_tex=%s",
            tostring(UIAtlasHelper.has_atlas_settings_by_texture_name ~= nil),
            tostring(UIAtlasHelper.get_atlas_settings_by_texture_name ~= nil),
            tostring(UIAtlasHelper.has_texture_by_name ~= nil))
        for _, tex_name in ipairs(tex_names) do
            local has_atlas = false
            if UIAtlasHelper.has_atlas_settings_by_texture_name then
                local ok, val = pcall(UIAtlasHelper.has_atlas_settings_by_texture_name, tex_name)
                has_atlas = ok and val
            end
            local get_result = "nil"
            if UIAtlasHelper.get_atlas_settings_by_texture_name then
                local ok, val = pcall(UIAtlasHelper.get_atlas_settings_by_texture_name, tex_name)
                if ok then get_result = tostring(val) end
            end
            emit("  '%s': has_atlas=%s get_atlas=%s", tex_name, tostring(has_atlas), get_result)
        end
    else
        emit("UIAtlasHelper not available")
    end

    local hat_key = _get_kruber_merc_hat_key()
    local skin_key = _get_kruber_merc_skin_key()
    emit("local hat key: %s", tostring(hat_key))
    emit("local skin key: %s", tostring(skin_key))

    local material_probes = {
        "portrait_kruber_mercenary_hat_1002",
        "medium_portrait_kruber_mercenary_hat_1002",
        "small_portrait_kruber_mercenary_hat_1002",
    }
    local guis = _collect_all_guis()
    emit("found %d gui handles", #guis)
    for _, entry in ipairs(guis) do
        for _, mat_name in ipairs(material_probes) do
            local ok, mat = pcall(Gui.material, entry.gui, mat_name)
            if ok and mat then
                emit("FOUND: %s has '%s' -> %s", entry.label, mat_name, tostring(mat))
            end
        end
    end

    if UIRenderer and UIRenderer._injected_material_sets then
        emit("_injected_material_sets count: %d", #UIRenderer._injected_material_sets)
        for i, v in ipairs(UIRenderer._injected_material_sets) do
            emit("  [%d] = %s", i, tostring(v))
        end
    else
        emit("UIRenderer._injected_material_sets: %s", tostring(UIRenderer and UIRenderer._injected_material_sets))
    end

    _flush_log()
end)

-- Deep dump of ALL portrait widgets across every UI surface.
-- Run this in the keep, during hero selection, and at end-of-round to map
-- all portrait locations, their content keys, pass types, and mask fields.
mod:command("portrait_dump", "Dump ALL portrait widgets from every UI surface", function()
    local function emit(fmt, ...)
        mod:echo(fmt, ...)
        mod:info("[portrait_dump] " .. fmt, ...)
    end

    local MASK_FIELDS = {
        "masked", "texture_mask", "mask_texture", "alpha_mask",
        "circular_mask", "use_mask", "mask", "mask_alpha",
    }

    local function dump_widget(source_label, wname, widget)
        emit("=== %s / %s ===", source_label, tostring(wname))
        if widget.content then
            local port = widget.content.character_portrait or widget.content.portrait
            emit("  portrait: %s", tostring(port))
            local ckeys = {}
            for k, v in pairs(widget.content) do
                ckeys[#ckeys + 1] = tostring(k) .. "=" .. tostring(v)
            end
            table.sort(ckeys)
            for _, s in ipairs(ckeys) do emit("  c: %s", s) end
        end
        if widget.style then
            for sk, sv in pairs(widget.style) do
                if type(sv) == "table" then
                    local extras = {}
                    for _, tf in ipairs({"texture_id", "texture", "texture_name", "material_name"}) do
                        if sv[tf] then extras[#extras + 1] = tf .. "=" .. tostring(sv[tf]) end
                    end
                    for _, mf in ipairs(MASK_FIELDS) do
                        if sv[mf] ~= nil then extras[#extras + 1] = mf .. "=" .. tostring(sv[mf]) end
                    end
                    if sv.texture_size then
                        extras[#extras + 1] = "size=" .. tostring(sv.texture_size[1]) .. "x" .. tostring(sv.texture_size[2])
                    end
                    if #extras > 0 then emit("  s.%s: %s", tostring(sk), table.concat(extras, ", ")) end
                end
            end
        end
        local element = widget.element
        if element then
            local passes = element.passes or element.pass_data
            if passes and type(passes) == "table" then
                emit("  passes (%d):", #passes)
                for pi, pass in ipairs(passes) do
                    local pkeys = {}
                    for k, v in pairs(pass) do
                        pkeys[#pkeys + 1] = tostring(k) .. "=" .. tostring(v)
                    end
                    table.sort(pkeys)
                    emit("    [%d] %s", pi, table.concat(pkeys, ", "))
                end
            end
        end
    end

    local function scan_widgets(source_label, widgets)
        if not widgets or type(widgets) ~= "table" then return 0 end
        local found = 0
        for wname, widget in pairs(widgets) do
            if type(widget) == "table" and widget.content then
                if widget.content.character_portrait or widget.content.portrait then
                    dump_widget(source_label, wname, widget)
                    found = found + 1
                end
            end
        end
        return found
    end

    local found = 0
    local ingame_ui = Managers.ui and Managers.ui._ingame_ui
    local hud = ingame_ui and ingame_ui._hud

    local uf_handler = hud and (hud._unit_frames_handler or hud.unit_frames_handler)
    if uf_handler then
        local frames = uf_handler._unit_frames or uf_handler.unit_frames
        if frames then
            for i, frame in ipairs(frames) do
                if frame then
                    for _, wf in ipairs({"_widgets", "widgets", "_default_widgets", "_portrait_widgets"}) do
                        found = found + scan_widgets("hud.frame[" .. i .. "]." .. wf, frame[wf])
                    end
                end
            end
        end
    else
        emit("unit_frames_handler: NOT FOUND")
    end

    local hero_view = ingame_ui and (ingame_ui._hero_view or ingame_ui.hero_view)
    if hero_view then
        emit("-- hero_view found --")
        for _, wf in ipairs({"_widgets", "widgets", "_static_widgets"}) do
            local ok_w, widgets = pcall(function() return hero_view[wf] end)
            if ok_w and widgets then
                found = found + scan_widgets("hero_view." .. wf, widgets)
            end
        end
        local ok_wins, windows = pcall(function() return hero_view._windows or hero_view.windows end)
        if ok_wins and windows then
            for wkey, window in pairs(windows) do
                if type(window) == "table" then
                    for _, wf in ipairs({"_widgets", "widgets", "_static_widgets"}) do
                        local ok_w, widgets = pcall(function() return window[wf] end)
                        if ok_w and widgets then
                            found = found + scan_widgets("hero_view.win[" .. tostring(wkey) .. "]." .. wf, widgets)
                        end
                    end
                end
            end
        end
    else
        emit("hero_view: not active")
    end

    for _, vname in ipairs({"_end_screen_view", "end_screen_view", "_game_over_view"}) do
        local ok_v, view = pcall(function() return ingame_ui and ingame_ui[vname] end)
        if ok_v and view then
            emit("-- %s found --", vname)
            for _, wf in ipairs({"_widgets", "widgets", "_static_widgets", "_player_widgets"}) do
                local ok_w, widgets = pcall(function() return view[wf] end)
                if ok_w and widgets then
                    found = found + scan_widgets(vname .. "." .. wf, widgets)
                end
            end
        end
    end

    if ingame_ui then
        emit("-- brute-force ingame_ui scan --")
        for field_name, field_val in pairs(ingame_ui) do
            if type(field_val) == "table" and field_name ~= "_hud" then
                for _, wf in ipairs({"_widgets", "widgets", "_static_widgets", "_player_widgets"}) do
                    local ok, widgets = pcall(function() return field_val[wf] end)
                    if ok and widgets then
                        local n = scan_widgets("ingame_ui." .. tostring(field_name) .. "." .. wf, widgets)
                        found = found + n
                    end
                end
            end
        end
    end

    if hud then
        local elements = hud._hud_elements or hud.hud_elements or hud._elements
        if elements and type(elements) == "table" then
            for ek, el in pairs(elements) do
                if type(el) == "table" then
                    for _, wf in ipairs({"_widgets", "widgets", "_static_widgets"}) do
                        local ok_w, widgets = pcall(function() return el[wf] end)
                        if ok_w and widgets then
                            found = found + scan_widgets("hud.el[" .. tostring(ek) .. "]." .. wf, widgets)
                        end
                    end
                end
            end
        end
    end

    emit("=== portrait_dump complete: %d portrait widgets found ===", found)
    _flush_log()
end)

-- Manual test: force career_settings swap and report state
mod:command("test_portrait", "Force portrait career_settings swap", function()
    _sync_portrait_settings()
    local career = SPProfiles and SPProfiles[5] and SPProfiles[5].careers and SPProfiles[5].careers[1]
    mod:echo("[test_portrait] active=%s portrait_image='%s'",
        tostring(_portrait_settings_active),
        career and tostring(career.portrait_image) or "nil")
    _flush_log()
end)

-- Sync portrait career_settings on each UnitFrameUI draw so the swap
-- activates as soon as materials are ready and hat is detected. Once
-- _portrait_settings_active is true, this is a cheap no-op.
mod:hook_safe("UnitFrameUI", "draw", function(self, dt)
    _sync_portrait_settings()
end)

mod.on_game_state_changed = function()
    _sync_portrait_settings()
end

mod.on_setting_changed = function(setting_id)
    if setting_id == "dynamic_portraits" then
        _sync_portrait_settings()
    end
end

-- CLARIFY: Ctrl+Shift+R (hot-reload) is UNSAFE for this mod — engine holds
-- C++ resource locks on loaded materials/textures that Lua can't release.
-- on_unload only restores the Lua-mutable career_settings; nothing else.
mod.on_unload = function()
    _restore_portrait_settings()
    mod:info("[unload] dynamic_cosmetic_portraits unloading")
end

mod:info("[mem-probe] dcp boot_lua=+%.1f MB (of ~1024 MB lua_heap cap)", (collectgarbage("count") - _MEM_PROBE_T0_DCP) / 1024)
