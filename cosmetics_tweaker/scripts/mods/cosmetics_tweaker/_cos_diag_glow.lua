-- cosmetics_tweaker glow diagnostic commands and bounded scan owner.
-- Installed once at the historical registration point; no hooks or wire state.
local M = {}

function M.install(mod, deps)
    local _local_player_safe = deps.local_player_safe
    local _is_unit = deps.is_unit
    local _flush_log = deps.flush_log

-- ============================================================
-- GLOW PROBE — find what shader uniform controls baked emissive on Stylish
-- (`_runed_01`), Weavebound (`_magic_01`), or other non-template-driven
-- glow categories.
--
-- Mechanism: brute-force a battery of plausible shader-uniform names by
-- calling Unit.set_vector3_for_materials with each candidate set to a
-- bright HDR red value. Variables that don't exist on the unit's materials
-- silently no-op. The variable that controls the emissive will visibly
-- turn the weapon red.
--
-- Cannot enumerate parameters via Material.num_parameters / parameter_name
-- — those crash Stingray (resource_manager.cpp:245, NOT pcall-recoverable).
-- Brute force is the only viable approach.
--
-- Three commands provide different probe modes:
--   cos glow_dump       - dump unit metadata (mesh + material counts)
--   cos glow_probe NAME - paint single named variable bright red
--   cos glow_scan       - cycle through all candidates with red/clear
--                         flashing per candidate. Watch and note when
--                         the weapon flashes red — the chat message at
--                         that moment names the variable.
--   cos glow_scan_stop  - cancel an in-flight scan
--   cos glow_restore    - re-apply the wielded item's original template
--                         to clear lingering probe values
-- ============================================================

-- Vector3 in Stingray is a frame-allocated temporary; do NOT cache it as a
-- module-level constant — across frames the storage is reclaimed and every
-- pcall(Unit.set_vector3_for_materials, ..., cached_vec) returns false. Found
-- empirically in v0.8.20: the scan reported `painted=0` on EVERY candidate ×
-- every unit because of this. Construct fresh per call site (same pattern as
-- _apply_glow_to_unit).
local function _probe_red()   return Vector3(15, 0, 0) end
local function _probe_clear() return Vector3(0,  0, 0) end
local _GLOW_PROBE_CANDIDATES = {
    -- emissive family
    "emissive_color", "_emissive_color", "emissive", "self_illum_color",
    "self_illumination", "illumination_color", "mtr_emissive",
    -- existing rune (control: should turn _runed_02 red)
    "rune_emissive_color", "_rune_emissive_color", "rune_color", "rune_glow",
    -- glow family
    "glow_color", "_glow_color", "glow", "main_glow", "primary_glow",
    "secondary_glow", "edge_glow", "rim_glow", "blade_glow",
    -- color/tint family
    "tint_color", "_tint_color", "tint", "color", "_color",
    "main_color", "primary_color", "secondary_color", "accent_color",
    "albedo_color", "albedo", "diffuse_color", "base_color", "base_color_tint",
    "highlight_color", "lamp_color", "light_color",
    -- gradient/swirl (Weavebound suspects — animated effects)
    "gradient_color_a", "gradient_color_b", "gradient_a", "gradient_b",
    "color_a", "color_b", "color_main", "color_alt",
    "swirl_color", "wind_color", "wind_color_a", "wind_color_b",
    -- versus 5-channel (covers Shyish-Infused if scanned on those)
    "color_glow_high", "color_glow_low", "color_smoke_high", "color_smoke_low", "color_dots",
    -- effect / fx family
    "effect_color", "fx_color", "vfx_color", "magic_color",
    -- material color generics
    "material_color", "mat_color", "baked_color",
    -- per-Loremaster's-Armoury map (these names work for shield textures)
    "texture_map_c0ba2942", "texture_map_64cc5eb8",
}

local function _wielded_units_for_probe()
    local pm = Managers and Managers.player
    local pl = _local_player_safe(pm)
    local pu = pl and pl.player_unit
    if not (pu and ScriptUnit and ScriptUnit.has_extension and ScriptUnit.has_extension(pu, "inventory_system")) then
        return nil, nil
    end
    local ext = ScriptUnit.extension(pu, "inventory_system")
    local slot_data = ext.get_wielded_slot_data and ext:get_wielded_slot_data()
    if not slot_data then return nil, nil end
    local out = {}
    for _, field in ipairs({ "right_unit_1p", "right_unit_3p", "left_unit_1p", "left_unit_3p" }) do
        local u = slot_data[field]
        if u and _is_unit(u) then out[#out + 1] = { field = field, unit = u } end
    end
    return out, slot_data
end

mod:command("glow_dump", "Dump wielded weapon unit metadata: mesh + material counts per hand unit", function()
    local units, slot_data = _wielded_units_for_probe()
    if not units or #units == 0 then mod:echo("[glow_dump] no wielded weapon"); return end
    mod:echo(string.format("[glow_dump] skin=%s, %d hand-units to probe", tostring(slot_data and slot_data.skin), #units))
    mod:info("[glow_dump] === wielded slot metadata ===")
    mod:info("[glow_dump] skin=%s item=%s", tostring(slot_data and slot_data.skin), tostring(slot_data and slot_data.item_data and slot_data.item_data.name))
    for _, u in ipairs(units) do
        local ok_n, n_meshes = pcall(Unit.num_meshes, u.unit)
        mod:info("[glow_dump] %s: alive=%s num_meshes=%s", u.field, tostring(_is_unit(u.unit)), tostring(ok_n and n_meshes or "err"))
        if ok_n and type(n_meshes) == "number" and Mesh and Mesh.num_materials then
            for i = 0, n_meshes - 1 do
                local ok_m, mesh = pcall(Unit.mesh, u.unit, i)
                if ok_m and mesh then
                    local ok_nm, n_mats = pcall(Mesh.num_materials, mesh)
                    mod:info("[glow_dump]   mesh[%d] num_materials=%s", i, tostring(ok_nm and n_mats or "err"))
                end
            end
        end
    end
    mod:echo("[glow_dump] done — full data in console log under [glow_dump]")
    if _flush_log then _flush_log() end
end)

mod:command("glow_probe", "Paint wielded weapon's chosen variable to bright HDR red. Usage: /glow_probe <varname>", function(varname)
    if not varname or varname == "" then
        mod:echo("[glow_probe] usage: /glow_probe <varname> — e.g. /glow_probe emissive_color")
        return
    end
    local units = _wielded_units_for_probe()
    if not units or #units == 0 then mod:echo("[glow_probe] no wielded weapon"); return end
    local n_set = 0
    for _, u in ipairs(units) do
        local ok, err = pcall(Unit.set_vector3_for_materials, u.unit, varname, _probe_red())
        if ok then n_set = n_set + 1 end
        mod:info("[glow_probe] var=%s unit=%s set_ok=%s err=%s", varname, u.field, tostring(ok), tostring(err))
    end
    mod:echo(string.format("[glow_probe] var=%s painted on %d/%d hand units. Look at the weapon — RED?", varname, n_set, #units))
end)

local _GLOW_SCAN = nil

mod:command("glow_scan", "Cycle ALL candidate variables on wielded weapon with red/clear flash. Watch — note when the weapon flashes red.", function()
    local units, slot_data = _wielded_units_for_probe()
    if not units or #units == 0 then mod:echo("[glow_scan] no wielded weapon"); return end
    _GLOW_SCAN = {
        units      = units,
        candidates = _GLOW_PROBE_CANDIDATES,
        idx        = 0,
        phase      = "advance",  -- "advance" -> set red, "clear" -> set (0,0,0)
        timer      = 0,
        red_dur    = 1.5,        -- seconds at red per candidate
        clear_dur  = 0.4,        -- seconds at (0,0,0) before next candidate
        slot_data  = slot_data,
    }
    local total_s = (_GLOW_SCAN.red_dur + _GLOW_SCAN.clear_dur) * #_GLOW_PROBE_CANDIDATES
    mod:echo(string.format("[glow_scan] starting — %d candidates × %.1fs ≈ %.0fs total. Wield the weapon you want probed; weapon flashes red on a hit.",
        #_GLOW_PROBE_CANDIDATES, _GLOW_SCAN.red_dur + _GLOW_SCAN.clear_dur, total_s))
end)

mod:command("glow_scan_stop", "Stop the in-flight glow_scan", function()
    if _GLOW_SCAN then
        local last = _GLOW_SCAN.candidates[_GLOW_SCAN.idx]
        mod:echo(string.format("[glow_scan] stopped at idx=%d var=%s. Run cos glow_restore to re-apply original template.",
            _GLOW_SCAN.idx, tostring(last)))
        _GLOW_SCAN = nil
    else
        mod:echo("[glow_scan] not running")
    end
end)

mod:command("glow_restore", "Re-apply the wielded item's original material template to undo probe edits", function()
    local units, slot_data = _wielded_units_for_probe()
    if not units or #units == 0 then mod:echo("[glow_restore] no wielded weapon"); return end
    local skin_key = slot_data and slot_data.skin
    local skin_data = skin_key and WeaponSkins and WeaponSkins.skins and rawget(WeaponSkins.skins, skin_key)
    local tpl = skin_data and skin_data.material_settings_name
    if not tpl then
        mod:echo("[glow_restore] skin has no material_settings_name (Stylish/_runed_01?). Re-equip via inventory loadout to fully restore.")
        return
    end
    local n = 0
    for _, u in ipairs(units) do
        if GearUtils and GearUtils.apply_material_settings then
            local ok = pcall(GearUtils.apply_material_settings, u.unit, tpl)
            if ok then n = n + 1 end
        end
    end
    mod:echo(string.format("[glow_restore] re-applied template '%s' on %d/%d units", tpl, n, #units))
end)

-- v0.9.1-dev: focused LA shield glow probe. Paints the 6 known glow shader
-- variables (rune_emissive_color + 5 versus channels) on the LEFT-hand units
-- (the shield) at bright HDR red for ~3s, then auto-clears. Watch the shield:
-- if any flash red, that glow channel IS paintable on the LA-repainted mesh
-- and we can wire up a glow toggle for that shield family.
local _LA_SHIELD_PROBE = nil
local _LA_SHIELD_GLOW_VARS = {
    "rune_emissive_color",
    "color_glow_high", "color_glow_low",
    "color_smoke_high", "color_smoke_low",
    "color_dots",
}

mod:command("la_shield_glow_probe", "Paint all 6 glow shader variables on the wielded shield (left hand only) at HDR red for 3s. Watch — does the shield flash red?", function()
    local units, slot_data = _wielded_units_for_probe()
    if not units or #units == 0 then mod:echo("[la_shield_probe] no wielded weapon"); return end
    -- Filter to left-hand only (the shield in a sword+shield combo). LA shield
    -- repaints sit on the left unit; the weapon (right) is untouched here.
    local left_units = {}
    for _, u in ipairs(units) do
        if u.field == "left_unit_1p" or u.field == "left_unit_3p" then
            left_units[#left_units + 1] = u
        end
    end
    if #left_units == 0 then mod:echo("[la_shield_probe] no left-hand (shield) unit — wield a sword+shield"); return end

    local skin_key = slot_data and slot_data.skin
    mod:echo(string.format("[la_shield_probe] painting %d glow vars × %d shield units; skin=%s",
        #_LA_SHIELD_GLOW_VARS, #left_units, tostring(skin_key)))
    mod:info("[la_shield_probe] === starting on skin=%s ===", tostring(skin_key))
    for _, var in ipairs(_LA_SHIELD_GLOW_VARS) do
        local painted = 0
        for _, u in ipairs(left_units) do
            local ok = pcall(Unit.set_vector3_for_materials, u.unit, var, _probe_red())
            if ok then painted = painted + 1 end
        end
        mod:info("[la_shield_probe]   var=%s painted=%d/%d", var, painted, #left_units)
    end
    _LA_SHIELD_PROBE = { units = left_units, timer = 0, duration = 3.0, slot_data = slot_data }
    mod:echo("[la_shield_probe] HDR red applied. Looking at the shield — does it glow red? Auto-clears in 3s.")
end)

mod._la_shield_probe_tick = function(dt)
    if not _LA_SHIELD_PROBE then return end
    _LA_SHIELD_PROBE.timer = _LA_SHIELD_PROBE.timer + (dt or 0)
    if _LA_SHIELD_PROBE.timer < _LA_SHIELD_PROBE.duration then return end
    -- Time's up — clear the variables back to (0,0,0). NOT a full restore
    -- because LA shield meshes may not have native templates; this is a
    -- best-effort. User can also re-equip the shield to fully restore.
    for _, var in ipairs(_LA_SHIELD_GLOW_VARS) do
        for _, u in ipairs(_LA_SHIELD_PROBE.units) do
            pcall(Unit.set_vector3_for_materials, u.unit, var, _probe_clear())
        end
    end
    mod:echo("[la_shield_probe] cleared. If the shield flashed red, glow vars ARE paintable — report which (or all). If not, LA shield material doesn't expose any glow channel.")
    _LA_SHIELD_PROBE = nil
end

mod._glow_scan_tick = function(dt)
    if not _GLOW_SCAN then return end
    _GLOW_SCAN.timer = _GLOW_SCAN.timer + (dt or 0)
    if _GLOW_SCAN.phase == "advance" then
        if _GLOW_SCAN.timer < _GLOW_SCAN.red_dur then return end
        _GLOW_SCAN.timer = 0
        _GLOW_SCAN.phase = "clear"
        local var = _GLOW_SCAN.candidates[_GLOW_SCAN.idx]
        if var then
            for _, u in ipairs(_GLOW_SCAN.units) do
                pcall(Unit.set_vector3_for_materials, u.unit, var, _probe_clear())
            end
        end
        return
    elseif _GLOW_SCAN.phase == "clear" then
        if _GLOW_SCAN.timer < _GLOW_SCAN.clear_dur then return end
        _GLOW_SCAN.timer = 0
        _GLOW_SCAN.idx = _GLOW_SCAN.idx + 1
        local var = _GLOW_SCAN.candidates[_GLOW_SCAN.idx]
        if not var then
            mod:echo("[glow_scan] DONE — all candidates tried. Run cos glow_restore to clean up.")
            _GLOW_SCAN = nil
            return
        end
        local n, last_err = 0, nil
        for _, u in ipairs(_GLOW_SCAN.units) do
            local ok, err = pcall(Unit.set_vector3_for_materials, u.unit, var, _probe_red())
            if ok then n = n + 1 else last_err = err end
        end
        mod:echo(string.format("[glow_scan] %d/%d → var=%s (set on %d units)", _GLOW_SCAN.idx, #_GLOW_SCAN.candidates, var, n))
        mod:info("[glow_scan] %d/%d var=%s painted=%d err=%s", _GLOW_SCAN.idx, #_GLOW_SCAN.candidates, var, n, tostring(last_err))
        _GLOW_SCAN.phase = "advance"
        return
    end
end


    M.wielded_units_for_probe = _wielded_units_for_probe
end

return M
