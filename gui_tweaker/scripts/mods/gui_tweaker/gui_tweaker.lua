local mod = get_mod("gut")

local MOD_VERSION = "0.2.8-dev"

-- Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6).
-- Both gate on `enable_debug_logging`. Both no-op when toggle is off.
-- `_dbg` is for confirmation / expected behavior — file only.
-- `_dbg_alert` is for unexpected / wrong / mismatch — file AND in-game chat.
local function _dbg(fmt, ...)
    if mod:get("enable_debug_logging") then
        mod:info("[gut:dbg] " .. fmt, ...)
    end
end

local function _dbg_alert(fmt, ...)
    if mod:get("enable_debug_logging") then
        mod:info("[gut:dbg] " .. fmt, ...)
        mod:echo("[gut] " .. fmt, ...)
    end
end

-- Applied marker (PROJECT_STANDARDS.md § 3.6 "Applied marker line (universal)").
-- Walks the data widget tree, FNV-1a-32 hashes setting=value pairs, prints
-- one mod:info line at load. ALWAYS fires (operational telemetry).
local function _settings_fingerprint()
    local ok, data = pcall(require, "scripts/mods/gui_tweaker/gui_tweaker_data")
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

mod:info("[gut:LOAD] v%s enabled fp=%s OK", MOD_VERSION, _settings_fingerprint())

-- Per PROJECT_STANDARDS § 3.6 + § 14a: dev/alpha/beta/0.x versions print
-- version to chat on load so the user can see what's active. Stable
-- (>=1.0.0) versions stay silent. Detect via MOD_VERSION string match.
if MOD_VERSION:find("-dev$") or MOD_VERSION:find("-alpha$") or MOD_VERSION:find("-beta$") or MOD_VERSION:find("-rc%d*$") or MOD_VERSION:find("^0%.") then
    mod:echo(string.format("[gut] v%s loaded", MOD_VERSION))
end

-- v0.2.1-dev: proper _RT_CHECKS regression scaffold (previously a one-line stub).
local _RT_CHECKS = {}
local function _rt_register(name, fn)
    _RT_CHECKS[#_RT_CHECKS + 1] = { name = name, fn = fn }
end
mod:command("gut_regression_test", "GUI tweaker self-check", function()
    local pass, fail = 0, 0
    mod:echo("=== gut regression_test (v%s) ===", MOD_VERSION)
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
    local ok, loc = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker/gui_tweaker_localization")
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
-- Loadout Save/Restore (v0.1)
-- ============================================================
-- Clean reimplementation of loadout_manager_vt2's save/restore. The legacy
-- mod OR-merged gear and cosmetics into a single backend_id-per-slot lookup
-- and iterated `slots_by_slot_index`, which routed weapon-skin items
-- (slot_type=melee) into gear slots like slot_ranged and triggered the
-- engine's "cannot equip item in this slot type" rejection. We keep the
-- two namespaces strictly separated: gear iterates `slots_by_ui_slot_index`,
-- cosmetics iterate `slots_by_cosmetic_index`, and each item is validated
-- against its OWN target slot before any write.

local LOADOUT_SLOTS = 30

-- Local player + resolved career name. Returns (career_name, profile, career)
-- or (nil, reason) when no local player/profile is available.
local function _get_current_career()
    local pm = Managers.player
    if not pm then return nil, "Managers.player not available (not in a level?)" end
    local player = pm:local_player(1)
    if not player then return nil, "no local player" end
    local ok_pi, profile_index = pcall(player.profile_index, player)
    local ok_ci, career_index = pcall(player.career_index, player)
    if not (ok_pi and ok_ci and profile_index and career_index) then
        return nil, "could not read profile/career index"
    end
    local profile = SPProfiles and SPProfiles[profile_index]
    if not profile then return nil, "no profile for index " .. tostring(profile_index) end
    local career = profile.careers and profile.careers[career_index]
    if not career then return nil, "no career for index " .. tostring(career_index) end
    return career.name, profile, career
end

-- Localized career display name with safe fallback.
local function _career_display_name(career)
    if not career then return "?" end
    local key = career.display_name or career.name
    if not key then return "?" end
    local ok, name = pcall(Localize, key)
    return (ok and name) or key
end

-- Validate item slot-type compatibility before equipping. Mirrors the
-- sanctioned mod's is_equipment_valid (lines 622-643) including the Slayer /
-- Questing Knight melee-in-ranged exemption. Returns (true) or (false, reason).
local function _validate_item_for_slot(item, slot_name, career_name)
    if not (item and item.data) then return false, "item has no data" end
    local data = item.data
    if data.can_wield and not table.contains(data.can_wield, career_name) then
        return false, string.format("career %s cannot wield %s", career_name, tostring(data.display_name or "?"))
    end
    local slot = InventorySettings and InventorySettings.slots_by_name and InventorySettings.slots_by_name[slot_name]
    if not slot then return false, "unknown slot " .. tostring(slot_name) end
    local actual = data.slot_type
    local expected = slot.type
    if actual == expected then return true end
    if expected == ItemType.RANGED and actual == ItemType.MELEE and
       (career_name == "dr_slayer" or career_name == "es_questingknight") then
        return true
    end
    return false, string.format("slot_type mismatch (item=%s, slot=%s)", tostring(actual), tostring(expected))
end

-- Snapshot the current loadout for `career_name`. Reads gear from
-- slots_by_ui_slot_index, cosmetics from slots_by_cosmetic_index, and
-- talents from the talents interface (cloned).
local function _snapshot_loadout(career_name)
    local items_iface = Managers.backend and Managers.backend:get_interface("items")
    if not items_iface then return nil, "no items interface" end
    local gear, cosmetics = {}, {}
    local frame_id = nil
    if InventorySettings and InventorySettings.slots_by_ui_slot_index then
        for _, slot in pairs(InventorySettings.slots_by_ui_slot_index) do
            local ok, id = pcall(items_iface.get_loadout_item_id, items_iface, career_name, slot.name)
            if ok and id then gear[slot.name] = id end
        end
    end
    if InventorySettings and InventorySettings.slots_by_cosmetic_index then
        for _, slot in pairs(InventorySettings.slots_by_cosmetic_index) do
            local ok, id = pcall(items_iface.get_loadout_item_id, items_iface, career_name, slot.name)
            if ok and id then
                cosmetics[slot.name] = id
                if slot.name == "slot_frame" then frame_id = id end
            end
        end
    end
    local talents = nil
    local talents_iface = Managers.backend and Managers.backend:get_interface("talents")
    if talents_iface then
        local ok, t = pcall(talents_iface.get_talents, talents_iface, career_name)
        if ok and type(t) == "table" then talents = table.clone(t) end
    end
    return {
        saved_at    = os.time(),
        career_name = career_name,
        frame       = frame_id,
        gear        = gear,
        cosmetics   = cosmetics,
        talents     = talents or {},
    }
end

-- Apply a saved loadout. Cross-career restore is out of scope for v0.1 — we
-- reject if the snapshot's career doesn't match the current one. Returns
-- (gear_count, cosmetic_count, talents_applied_bool, error_count).
local function _apply_loadout(loadout, current_career_name)
    if not loadout then return 0, 0, false, 0 end
    if loadout.career_name and loadout.career_name ~= current_career_name then
        mod:echo(string.format("Loadout was saved for %s; switch to that career first (cross-career restore is not supported in v0.1).",
            tostring(loadout.career_name)))
        return 0, 0, false, 1
    end
    local items_iface = Managers.backend and Managers.backend:get_interface("items")
    if not items_iface then
        mod:echo("No items interface; cannot restore loadout.")
        return 0, 0, false, 1
    end
    local gear_count, cos_count, errors = 0, 0, 0

    -- Gear namespace -> slots_by_ui_slot_index only.
    if loadout.gear and InventorySettings and InventorySettings.slots_by_ui_slot_index then
        local gear_slot_names = {}
        for _, slot in pairs(InventorySettings.slots_by_ui_slot_index) do
            gear_slot_names[slot.name] = true
        end
        for slot_name, backend_id in pairs(loadout.gear) do
            if not gear_slot_names[slot_name] then
                mod:echo(string.format("Skipping gear slot %s -- not a known gear slot.", tostring(slot_name)))
                -- _dbg: loadout_apply_skip
                pcall(_dbg_alert, "[gui_tweaker] loadout_apply_skip: slot_name=%s reason=not_a_gear_slot",
                    tostring(slot_name))
                errors = errors + 1
            else
                local ok_item, item = pcall(items_iface.get_item_from_id, items_iface, backend_id)
                if not (ok_item and item) then
                    mod:echo(string.format("Skipping %s -- item %s no longer in backend.", slot_name, tostring(backend_id)))
                    pcall(_dbg_alert, "[gui_tweaker] loadout_apply_skip: slot_name=%s reason=item_not_in_backend",
                        tostring(slot_name))
                    errors = errors + 1
                else
                    local valid, reason = _validate_item_for_slot(item, slot_name, current_career_name)
                    if not valid then
                        mod:echo(string.format("Skipping %s -- %s.", slot_name, tostring(reason)))
                        pcall(_dbg_alert, "[gui_tweaker] loadout_apply_skip: slot_name=%s reason=%s",
                            tostring(slot_name), tostring(reason))
                        errors = errors + 1
                    else
                        local ok_set, err = pcall(BackendUtils.set_loadout_item, backend_id, current_career_name, slot_name)
                        if ok_set then
                            gear_count = gear_count + 1
                            -- _dbg: loadout_apply_item
                            pcall(_dbg, "[gui_tweaker] loadout_apply_item: slot_name=%s item=%s",
                                tostring(slot_name), tostring(backend_id))
                        else
                            mod:echo(string.format("Skipping %s -- set_loadout_item failed: %s", slot_name, tostring(err)))
                            pcall(_dbg_alert, "[gui_tweaker] loadout_apply_skip: slot_name=%s reason=set_loadout_item_failed:%s",
                                tostring(slot_name), tostring(err))
                            errors = errors + 1
                        end
                    end
                end
            end
        end
    end

    -- Cosmetic namespace -> slots_by_cosmetic_index only.
    if loadout.cosmetics and InventorySettings and InventorySettings.slots_by_cosmetic_index then
        local cos_slot_names = {}
        for _, slot in pairs(InventorySettings.slots_by_cosmetic_index) do
            cos_slot_names[slot.name] = true
        end
        for slot_name, backend_id in pairs(loadout.cosmetics) do
            if not cos_slot_names[slot_name] then
                mod:echo(string.format("Skipping cosmetic slot %s -- not a known cosmetic slot.", tostring(slot_name)))
                pcall(_dbg_alert, "[gui_tweaker] loadout_apply_skip: slot_name=%s reason=not_a_cosmetic_slot",
                    tostring(slot_name))
                errors = errors + 1
            else
                local ok_item, item = pcall(items_iface.get_item_from_id, items_iface, backend_id)
                if not (ok_item and item) then
                    mod:echo(string.format("Skipping %s -- item %s no longer in backend.", slot_name, tostring(backend_id)))
                    pcall(_dbg_alert, "[gui_tweaker] loadout_apply_skip: slot_name=%s reason=item_not_in_backend",
                        tostring(slot_name))
                    errors = errors + 1
                else
                    local valid, reason = _validate_item_for_slot(item, slot_name, current_career_name)
                    if not valid then
                        mod:echo(string.format("Skipping %s -- %s.", slot_name, tostring(reason)))
                        pcall(_dbg_alert, "[gui_tweaker] loadout_apply_skip: slot_name=%s reason=%s",
                            tostring(slot_name), tostring(reason))
                        errors = errors + 1
                    else
                        local ok_set, err = pcall(BackendUtils.set_loadout_item, backend_id, current_career_name, slot_name)
                        if ok_set then
                            cos_count = cos_count + 1
                            pcall(_dbg, "[gui_tweaker] loadout_apply_item: slot_name=%s item=%s",
                                tostring(slot_name), tostring(backend_id))
                        else
                            mod:echo(string.format("Skipping %s -- set_loadout_item failed: %s", slot_name, tostring(err)))
                            pcall(_dbg_alert, "[gui_tweaker] loadout_apply_skip: slot_name=%s reason=set_loadout_item_failed:%s",
                                tostring(slot_name), tostring(err))
                            errors = errors + 1
                        end
                    end
                end
            end
        end
    end

    -- Talents.
    local talents_applied = false
    if loadout.talents and #loadout.talents > 0 then
        local talents_iface = Managers.backend and Managers.backend:get_interface("talents")
        if talents_iface then
            local ok_t, err_t = pcall(talents_iface.set_talents, talents_iface, current_career_name, loadout.talents)
            if ok_t then
                talents_applied = true
            else
                mod:echo("Talent restore failed: " .. tostring(err_t))
                errors = errors + 1
            end
        end
    end

    return gear_count, cos_count, talents_applied, errors
end

local function _get_all_loadouts()
    return mod:get("loadouts") or {}
end

local function _save_loadout_to_slot(career_name, n, loadout)
    local all = _get_all_loadouts()
    all[career_name] = all[career_name] or {}
    all[career_name][n] = loadout
    mod:set("loadouts", all)
end

local function _load_loadout_from_slot(career_name, n)
    local all = _get_all_loadouts()
    local by_career = all[career_name]
    return by_career and by_career[n] or nil
end

-- Parse + range-check the slot index argument. Returns (n, nil) or (nil, reason).
local function _parse_slot_arg(arg)
    local n = tonumber(arg)
    if not n then return nil, "slot must be a number 1-" .. LOADOUT_SLOTS end
    n = math.floor(n)
    if n < 1 or n > LOADOUT_SLOTS then return nil, "slot must be 1-" .. LOADOUT_SLOTS end
    return n
end

mod:command("gut_save_loadout", "Save current loadout to slot N (1-30)", function(arg)
    local n, reason = _parse_slot_arg(arg)
    if not n then mod:echo("Save failed: " .. reason) return end
    local career_name, profile_or_err, career = _get_current_career()
    if not career_name then mod:echo("Save failed: " .. tostring(profile_or_err)) return end
    local loadout, snap_err = _snapshot_loadout(career_name)
    if not loadout then mod:echo("Save failed: " .. tostring(snap_err)) return end
    _save_loadout_to_slot(career_name, n, loadout)
    local gear_n, cos_n = 0, 0
    for _ in pairs(loadout.gear) do gear_n = gear_n + 1 end
    for _ in pairs(loadout.cosmetics) do cos_n = cos_n + 1 end
    local talents_n = #(loadout.talents or {})
    mod:echo(string.format("Saved loadout to slot %d for career %s (%d gear, %d cosmetics, %d talents)",
        n, _career_display_name(career), gear_n, cos_n, talents_n))
    -- _dbg: loadout_save
    pcall(function()
        _dbg("[gui_tweaker] loadout_save: slot=%d career=%s gear=%d cosmetics=%d talents=%d",
            n, tostring(career_name), gear_n, cos_n, talents_n)
        for slot_name, backend_id in pairs(loadout.gear) do
            _dbg("[gui_tweaker]   gear.%s = %s", tostring(slot_name), tostring(backend_id))
        end
        for slot_name, backend_id in pairs(loadout.cosmetics) do
            _dbg("[gui_tweaker]   cosmetics.%s = %s", tostring(slot_name), tostring(backend_id))
        end
        local talent_strs = {}
        for i = 1, #(loadout.talents or {}) do talent_strs[i] = tostring(loadout.talents[i]) end
        _dbg("[gui_tweaker]   talents = %s", table.concat(talent_strs, ","))
    end)
end)

mod:command("gut_load_loadout", "Load loadout from slot N (1-30) for current career", function(arg)
    local n, reason = _parse_slot_arg(arg)
    if not n then mod:echo("Load failed: " .. reason) return end
    local career_name, profile_or_err, career = _get_current_career()
    if not career_name then mod:echo("Load failed: " .. tostring(profile_or_err)) return end
    local loadout = _load_loadout_from_slot(career_name, n)
    if not loadout then
        mod:echo(string.format("No loadout in slot %d for career %s", n, _career_display_name(career)))
        return
    end
    local gear_n, cos_n, talents_ok, err_n = _apply_loadout(loadout, career_name)
    mod:echo(string.format("Loaded slot %d for %s -- applied %d gear, %d cosmetics, talents %s, %d errors",
        n, _career_display_name(career), gear_n, cos_n, talents_ok and "yes" or "no", err_n))
    mod:echo("(Open the hero view to refresh the visual model in the keep.)")
    -- _dbg: loadout_apply
    pcall(_dbg, "[gui_tweaker] loadout_apply: slot=%d career=%s gear_applied=%d cosmetics_applied=%d talents_set=%s errors=%d",
        n, tostring(career_name), gear_n, cos_n, talents_ok and "yes" or "no", err_n)
end)

mod:command("gut_list_loadouts", "List saved loadouts for current career", function()
    local career_name, profile_or_err, career = _get_current_career()
    if not career_name then mod:echo("List failed: " .. tostring(profile_or_err)) return end
    local all = _get_all_loadouts()
    local by_career = all[career_name]
    if not by_career then
        mod:echo(string.format("No loadouts saved for %s", _career_display_name(career)))
        return
    end
    local printed = 0
    for n = 1, LOADOUT_SLOTS do
        local lo = by_career[n]
        if lo then
            local gear_n, cos_n = 0, 0
            for _ in pairs(lo.gear or {}) do gear_n = gear_n + 1 end
            for _ in pairs(lo.cosmetics or {}) do cos_n = cos_n + 1 end
            local ts = lo.saved_at and os.date("%Y-%m-%d %H:%M", lo.saved_at) or "?"
            mod:echo(string.format("[%d] saved %s -- %d gear, %d cosmetics", n, ts, gear_n, cos_n))
            printed = printed + 1
        end
    end
    if printed == 0 then
        mod:echo(string.format("No loadouts saved for %s", _career_display_name(career)))
    end
end)

-- ============================================================
-- HUD Customizer (v0.2.0) -- in-game edit-mode + click-and-drag
-- repositioning of native HUD widgets, persisted per-resolution.
-- ============================================================

local Customizer = mod:dofile("scripts/mods/gui_tweaker/_hud_customizer")
-- Wire the two-channel debug helpers into the customizer module before any
-- hooks fire (PROJECT_STANDARDS § 3.6 two-helper policy).
pcall(Customizer.init_dbg, _dbg, _dbg_alert)
local ok_install, install_ret, install_failed, install_failures = pcall(Customizer.install_hooks)
if not ok_install then
    mod:echo("gui_tweaker: hud-customizer hook install failed: " .. tostring(install_ret))
end

-- _dbg: boot (one-shot at mod load)
do
    local rw, rh = 0, 0
    pcall(function()
        local r = rawget(_G, "RESOLUTION_LOOKUP")
        if r then rw, rh = r.res_w or 0, r.res_h or 0 end
    end)
    _dbg("[gui_tweaker] boot: v%s, resolution %dx%d", tostring(MOD_VERSION), rw, rh)
    if ok_install then
        local installed_n = tonumber(install_ret) or 0
        local failed_n = tonumber(install_failed) or 0
        local failures_str = "none"
        if type(install_failures) == "table" and #install_failures > 0 then
            failures_str = table.concat(install_failures, ",")
        end
        if failed_n > 0 then
            _dbg_alert("[gui_tweaker] hook_install: installed=%d failed=%d (failures: %s)",
                installed_n, failed_n, failures_str)
        else
            _dbg("[gui_tweaker] hook_install: installed=%d failed=%d (failures: %s)",
                installed_n, failed_n, failures_str)
        end
    else
        _dbg_alert("[gui_tweaker] hook_install: installed=0 failed=? (failures: pcall_err=%s)",
            tostring(install_ret))
    end
    -- Dump the customizer registry — one line per widget.
    pcall(function()
        for i = 1, #Customizer.REGISTRY do
            local e = Customizer.REGISTRY[i]
            _dbg("[gui_tweaker] registry: id=%s class=%s node=%s vanilla_pos={%d,%d} vanilla_size={%d,%d}",
                tostring(e.id), tostring(e.class_name), tostring(e.scenegraph_node_id),
                math.floor(e.vanilla_position[1] or 0), math.floor(e.vanilla_position[2] or 0),
                math.floor(e.vanilla_size[1] or 0), math.floor(e.vanilla_size[2] or 0))
        end
    end)
end

-- _dbg: hero_view auto-dump. Fires whenever HeroView opens AND debug_logging is on.
mod:hook_safe("HeroView", "on_enter", function(self, ...)
    if not mod:get("enable_debug_logging") then return end
    pcall(Customizer.dump_hero_view, self)
end)

-- VMF emits this callback when the user flips any setting. We use it to log
-- the debug-mode transition unconditionally (only place that does so).
mod.on_setting_changed = function(setting_id)
    if setting_id == "enable_debug_logging" then
        if mod:get("enable_debug_logging") then
            mod:info("[gui_tweaker] debug_logging: ENABLED")
        end
    end
end

-- Per-frame entry point: pulls activation state, runs the drag machine if
-- we're in edit mode, then injects the overlay draw using IngameHud's renderer.
mod:hook_safe("IngameHud", "post_update", function(self, dt, t)
    pcall(Customizer.tick_activation)
    if Customizer.is_edit_mode() then
        pcall(Customizer.tick_drag)
        local ui_renderer = (self._ingame_ui_context and self._ingame_ui_context.ui_renderer)
            or (Managers.ui and Managers.ui._ingame_ui_context and Managers.ui._ingame_ui_context.ui_top_renderer)
        if ui_renderer then
            pcall(Customizer.draw_overlay, ui_renderer)
        end
    end
end)

mod:command("gut_edit_hud", "Toggle HUD edit mode (click-drag widgets to reposition)", function()
    local enabled = not (Customizer.is_edit_mode() and true or false)
    -- We only flip the sticky bit; the alt-gesture path stays independent.
    Customizer.set_sticky(enabled)
    if enabled then
        mod:echo("Edit mode: ON (resolution " .. tostring(Customizer.resolution_key()) .. "). Drag widgets with left mouse.")
    else
        mod:echo("Edit mode: OFF.")
    end
end)

mod:command("gut_reset_hud", "Reset HUD widget(s) to vanilla position. Usage: /gut_reset_hud [widget_id]", function(arg)
    if arg and arg ~= "" then
        local ok = Customizer.reset_widget(arg)
        if ok then
            mod:echo("Reset HUD widget '" .. tostring(arg) .. "' to vanilla position.")
        else
            mod:echo("Reset failed: unknown widget id '" .. tostring(arg) .. "'. Run /gut_list_hud for valid ids.")
        end
    else
        local n = Customizer.reset_all()
        mod:echo(string.format("Reset all HUD widgets (%d entries) for resolution %s.", n, tostring(Customizer.resolution_key())))
    end
end)

mod:command("gut_list_hud", "List current HUD widget offsets for this resolution", function()
    local entries = Customizer.list_offsets()
    mod:echo(string.format("HUD offsets for %s:", tostring(Customizer.resolution_key())))
    if #entries == 0 then
        mod:echo("  (no offsets saved -- all widgets at vanilla position)")
        return
    end
    for i = 1, #entries do
        local e = entries[i]
        mod:echo(string.format("  %s: dx=%.1f, dy=%.1f", e.id, e.dx, e.dy))
    end
end)

-- Registered here (not beside the v0.1 checks at the top of the file) because it
-- closes over `Customizer`, which only becomes available after the dofile above.
_rt_register("hud_offset_preserves_vanilla_baseline", function()
    -- audit 2026-06-07 (v0.2.8-dev, F5): _apply_offset_to_scenegraph used to
    -- write the RAW drag delta into local_position, zeroing each widget's
    -- non-zero vanilla baseline (equipment_ui {0,69}, buff_ui {150,18}, etc.) on
    -- the first drag. The math now lives in Customizer.local_position_for and
    -- must return baseline + delta. This check fails if the baseline term is
    -- dropped again (regression to raw-delta assignment).
    if type(Customizer.local_position_for) ~= "function" then
        return "Customizer.local_position_for missing (refactor regressed)"
    end
    -- equipment_ui has a non-zero baseline {0, 69, 4}; it is the canonical case
    -- the old raw-write broke. A 25,-40 drag must land at vanilla + delta.
    local lx, ly = Customizer.local_position_for("equipment_ui", 25, -40)
    if lx ~= 25 then return string.format("equipment_ui x: expected 0+25=25, got %s", tostring(lx)) end
    if ly ~= 29 then return string.format("equipment_ui y: expected 69+(-40)=29, got %s", tostring(ly)) end
    -- buff_ui baseline {150, 18}: a zero drag must return the exact baseline,
    -- proving the baseline survives (the raw-write bug returned {0,0} here).
    local bx, by = Customizer.local_position_for("buff_ui", 0, 0)
    if bx ~= 150 or by ~= 18 then
        return string.format("buff_ui zero-drag: expected {150,18}, got {%s,%s}", tostring(bx), tostring(by))
    end
    -- Unknown id must degrade to {0,0} + delta, never error.
    local ux, uy = Customizer.local_position_for("nonexistent_widget", 7, 9)
    if ux ~= 7 or uy ~= 9 then
        return string.format("unknown id: expected {7,9}, got {%s,%s}", tostring(ux), tostring(uy))
    end
end)

-- ============================================================
-- Mod Tweaker (v0.1 scaffold) -- replacement settings menu surface
-- exposed at `get_mod("gut").mod_tweaker`. v0.1 just stands up the API
-- and registry; the ESC entry, view rendering, and widget factories
-- arrive in follow-up tasks. Authors detect with:
--   local gut = get_mod("gut")
--   if gut and gut.mod_tweaker then
--       gut.mod_tweaker:register_category({ mod_id = "...", label = "...", widgets = {...} })
--   end
-- ============================================================

local ok_mt, ModTweaker = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker/_mod_tweaker")
if ok_mt and type(ModTweaker) == "table" then
    local ok_install, install_err = pcall(ModTweaker.install, _dbg, _dbg_alert)
    if ok_install then
        mod.mod_tweaker = ModTweaker
        _dbg("[gui_tweaker] mod_tweaker: installed (api version v0.1)")
    else
        _dbg_alert("[gui_tweaker] mod_tweaker install failed: %s", tostring(install_err))
    end
else
    _dbg_alert("[gui_tweaker] mod_tweaker dofile failed: %s", tostring(ModTweaker))
end

-- ESC menu entry injection. Hook the central layout consumer
-- (IngameViewLayoutLogic.setup_button_layout) so we catch every layout variant
-- the engine swaps through: alone / host / client / demo / tutorial / offline /
-- full_access, plus the chat-button injected case. Vanilla source:
-- scripts/ui/views/ingame_view_layout_logic.lua:17-60. hook_safe is correct
-- here because setup_button_layout doesn't return -- it mutates
-- self.active_button_data, which we extend after the iteration runs.
mod:hook_safe("IngameViewLayoutLogic", "setup_button_layout", function(self, layout_data)
    local entries = self.active_button_data
    if type(entries) ~= "table" then return end
    -- Don't double-insert if the hook re-fires on the same active_button_data
    -- (layout swap during gameplay clears + rebuilds — safe to re-add).
    for i = 1, #entries do
        if entries[i].transition == "mod_tweaker_view" then return end
    end
    local insert_at = #entries + 1
    -- Place above Options for visual grouping; if Options isn't in this layout
    -- (e.g. console invert-controls demo), fall through to append.
    for i = 1, #entries do
        if entries[i].transition == "options_menu" then
            insert_at = i
            break
        end
    end
    table.insert(entries, insert_at, {
        display_name      = "mod_tweaker_button_name",
        display_name_func = function() return "Mod Tweaker" end,
        fade              = true,
        transition        = "mod_tweaker_view",
    })
end)

-- Transition + view registration. Two halves:
--   (a) transitions table -- mutated directly via package.loaded so the
--       upvalue `transitions` captured at ingame_ui.lua:50 sees the new entry.
--       The transition closure just sets self.current_view; vanilla pattern
--       is at ingame_ui_settings.lua:537 (options_menu).
--   (b) views table -- hook IngameUI.setup_views post-call (ingame_ui.lua:145)
--       and inject our view instance, mirroring how
--       view_settings.views_function builds the canonical map.
local ok_settings_inject, settings_inject_err = pcall(function()
    local settings = package.loaded["scripts/ui/views/ingame_ui_settings"]
    if not settings or not settings.transitions then
        error("ingame_ui_settings not in package.loaded; mod likely loaded too early")
    end
    if settings.transitions.mod_tweaker_view then
        _dbg("[mt] transition mod_tweaker_view already registered (idempotent)")
        return
    end
    settings.transitions.mod_tweaker_view = function(self) self.current_view = "mod_tweaker_view" end
    _dbg("[mt] transition registered: mod_tweaker_view")
end)
if not ok_settings_inject then
    _dbg_alert("[mt] transitions injection failed: %s", tostring(settings_inject_err))
end

mod:hook_safe("IngameUI", "setup_views", function(self)
    if type(self.views) ~= "table" then return end
    if self.views.mod_tweaker_view then return end -- idempotent
    local ok_view, ModTweakerView = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker/_mod_tweaker_view")
    if not ok_view or type(ModTweakerView) ~= "table" then
        _dbg_alert("[mt] setup_views: ModTweakerView dofile failed: %s", tostring(ModTweakerView))
        return
    end
    local ok_new, view_or_err = pcall(ModTweakerView.new, ModTweakerView, self.ingame_ui_context)
    if not ok_new then
        _dbg_alert("[mt] setup_views: ModTweakerView:new raised: %s", tostring(view_or_err))
        return
    end
    self.views.mod_tweaker_view = view_or_err
    _dbg("[mt] setup_views: ModTweakerView attached")
end)

_rt_register("mod_tweaker_esc_entry_hook", function()
    local logic_class = rawget(_G, "IngameViewLayoutLogic")
    if not logic_class then return "IngameViewLayoutLogic global not present" end
    if type(logic_class.setup_button_layout) ~= "function" then
        return "IngameViewLayoutLogic.setup_button_layout missing"
    end
    -- Build a fake instance and a layout_data with an Options-shaped entry,
    -- run setup_button_layout, then verify our entry was inserted above it.
    local fake = setmetatable({ _params = {} }, { __index = logic_class })
    local layout = {
        { display_name = "return_to_game_button_name", transition = "exit_menu" },
        { display_name = "options_menu_button_name",   transition = "options_menu" },
        { display_name = "quit_menu_button_name",      transition = "quit_game" },
    }
    local ok = pcall(logic_class.setup_button_layout, fake, layout)
    if not ok then return "setup_button_layout raised on probe layout" end
    local got = fake.active_button_data
    if type(got) ~= "table" then return "active_button_data not populated" end
    local mt_idx, opt_idx = nil, nil
    for i = 1, #got do
        if got[i].transition == "mod_tweaker_view" then mt_idx = i end
        if got[i].transition == "options_menu"     then opt_idx = i end
    end
    if not mt_idx then return "mod_tweaker entry not injected" end
    if not opt_idx then return "options entry vanished (engine change?)" end
    if mt_idx >= opt_idx then return string.format("mod_tweaker entry not above options (mt=%d, opt=%d)", mt_idx, opt_idx) end
end)

_rt_register("mod_tweaker_transition_registered", function()
    local settings = package.loaded["scripts/ui/views/ingame_ui_settings"]
    if not settings then return "ingame_ui_settings not in package.loaded" end
    if not settings.transitions then return "settings.transitions missing" end
    if type(settings.transitions.mod_tweaker_view) ~= "function" then
        return "transitions.mod_tweaker_view is not a function"
    end
    -- Smoke: ensure the transition just sets current_view.
    local fake = {}
    settings.transitions.mod_tweaker_view(fake)
    if fake.current_view ~= "mod_tweaker_view" then
        return "transition did not set current_view = mod_tweaker_view"
    end
end)

_rt_register("mod_tweaker_api_present", function()
    local MT = mod.mod_tweaker
    if not MT then return "mod.mod_tweaker not set; install path failed" end
    for _, name in ipairs({ "register_category", "is_registered", "list_categories",
                            "get_category", "get", "set" }) do
        if type(MT[name]) ~= "function" then
            return string.format("mod.mod_tweaker:%s is not a function (got %s)",
                name, type(MT[name]))
        end
    end
    -- Smoke: register a throwaway category, read back, ensure idempotent rejection.
    local probe_id = "__mt_rt_probe__"
    -- Defensively scrub before registering — _rt_check may have been run already.
    local Settings = mod:dofile("scripts/mods/gui_tweaker/_mod_tweaker_settings")
    if Settings and MT:is_registered(probe_id) then
        -- No public unregister yet; if the probe is still registered from a
        -- prior run, just re-use it (the api is supposed to be idempotent on
        -- this call shape and the smoke is still meaningful).
    else
        local ok = MT:register_category({
            mod_id = probe_id,
            label  = "rt probe",
            widgets = { { setting_id = "probe_flag", type = "checkbox", default = false } },
        })
        if not ok then return "register_category returned false on first call" end
    end
    if not MT:is_registered(probe_id) then return "is_registered() false after register" end
    MT:set(probe_id, "probe_flag", true)
    if MT:get(probe_id, "probe_flag") ~= true then return "get() did not reflect set()" end
end)

mod:info(string.format("gui_tweaker v%s ready (loadout save/restore + HUD edit mode + mod_tweaker api)", MOD_VERSION))
