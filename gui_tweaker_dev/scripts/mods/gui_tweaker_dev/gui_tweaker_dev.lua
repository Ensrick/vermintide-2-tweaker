local mod = get_mod("gut_dev")
_MEM_PROBE_T0_GUT = collectgarbage("count")  -- [mem-probe] temp Lua-footprint baseline (lua_heap 1 GiB cap diagnostic)

local MOD_VERSION = "0.2.169-dev"

-- Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6).
-- Both route through VMF's built-in logging, gated by VMF output_mode_debug /
-- output_mode_warning. No per-mod toggle.
-- `_dbg` is for confirmation / expected behavior — debug channel only.
-- `_dbg_alert` is for unexpected / wrong / mismatch — warning channel only.
local function _dbg(fmt, ...)
    mod:debug("[gut:dbg] " .. fmt, ...)
end

local function _dbg_alert(fmt, ...)
    -- (warnings noise) demoted mod:warning -> mod:debug. These [gut:dbg] traces (e.g. HUD
    -- widget_init_skip when a scenegraph node isn't present in the keep) are diagnostics, not
    -- real problems, and at warning level they spammed the in-game chat. Debug is off by default.
    mod:debug("[gut:dbg] " .. fmt, ...)
end

-- Applied marker (PROJECT_STANDARDS.md § 3.6 "Applied marker line (universal)").
-- Walks the data widget tree, FNV-1a-32 hashes setting=value pairs, prints
-- one mod:info line at load. ALWAYS fires (operational telemetry).
local function _settings_fingerprint()
    local ok, data = pcall(require, "scripts/mods/gui_tweaker_dev/gui_tweaker_data")
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
mod:command("regression_test", "GUI tweaker self-check", function()
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

mod:command("lua_mem", "Print live Lua heap usage (per-mod memory measurement). Optional label: /lua_mem <label>", function(label)
    -- Diagnostic for the VT2 1 GiB lua_heap cap crash ("Not enough memory
    -- reserved for heap lua_heap", reserved 1073741824). Forces a full GC so the
    -- reading is the LIVE footprint (not transient garbage), then reports
    -- collectgarbage("count").
    -- Find a heavy mod: disable all suspects -> launch -> load a level ->
    --   /lua_mem baseline ; then enable ONE mod -> relaunch -> load a level ->
    --   /lua_mem <modname>. The jump between readings is that mod's footprint.
    -- The engine lua_heap holds bytecode + C-side Lua structures ON TOP of this,
    -- so treat the number as a lower-bound proxy and compare DELTAS, not absolutes.
    collectgarbage("collect")
    collectgarbage("collect")
    local kb = collectgarbage("count")
    local lbl = (label and label ~= "") and (" | " .. tostring(label)) or ""
    mod:echo("[lua_mem] %.1f MB live Lua (%.0f KB) -- lua_heap cap is ~1024 MB%s", kb / 1024, kb, lbl)
    mod:info("[lua_mem] live_lua_mb=%.1f live_lua_kb=%.0f label=%s", kb / 1024, kb, tostring(label or ""))
end)

_rt_register("dbg_helpers_two_channel", function()
    if type(_dbg) ~= "function" then return "_dbg helper missing" end
    if type(_dbg_alert) ~= "function" then return "_dbg_alert helper missing" end
    local ok = pcall(_dbg, "smoke test")
    if not ok then return "_dbg raised" end
    ok = pcall(_dbg_alert, "smoke test")
    if not ok then return "_dbg_alert raised" end
end)


_rt_register("arrow_hover_native_size", function()
    -- (#92/#99) The arrow hover/glow overlay must be the BIGGER native sprite (30x35), NOT the
    -- 19x27 base — drawing it at base size made the glow too small + misplaced. Build a stepper
    -- row and assert the overlay styles match the vanilla size, so the fix can't silently revert
    -- (ground truth: options_view_definitions.lua left_arrow_hover :2206-2216 size 30x35).
    local ok, defs = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_definitions")
    if not ok or type(defs) ~= "table" or type(defs.create_checkbox) ~= "function" then
        return "definitions/create_checkbox unavailable"
    end
    local ok2, w = pcall(defs.create_checkbox, "RT", { 0, 0, 0 }, 0)
    if not ok2 or type(w) ~= "table" or type(w.style) ~= "table" then
        return "create_checkbox build failed: " .. tostring(w)
    end
    for _, k in ipairs({ "left_arrow_hover", "right_arrow_hover" }) do
        local ts = w.style[k] and w.style[k].texture_size
        if type(ts) ~= "table" or ts[1] ~= 30 or ts[2] ~= 35 then
            return string.format("%s texture_size=%s (want {30,35})", k,
                ts and ("{" .. tostring(ts[1]) .. "," .. tostring(ts[2]) .. "}") or tostring(ts))
        end
    end
end)

_rt_register("localization_format_safe", function()
    -- Layer 3 (2026-05-25): catch unescaped %-format chars in loc strings at
    -- runtime. VMF's tooltip render path calls string.format on the loc value;
    -- literal "%APPDATA%" / "5%" / "%USERNAME%" raises 'invalid option' and
    -- shows as a red error tooltip in the VMF settings UI. Static check is
    -- qa/check_localization.ps1 -- this is its runtime twin so the bug can't
    -- ship even if the static check is skipped. RULE: any literal % in a loc
    -- string must be doubled to %%.
    local ok, loc = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/gui_tweaker_localization")
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

mod:command("save_loadout", "Save current loadout to slot N (1-30)", function(arg)
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

mod:command("load_loadout", "Load loadout from slot N (1-30) for current career", function(arg)
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

mod:command("list_loadouts", "List saved loadouts for current career", function()
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
-- Versus host-crash fix: UnitFrameUI.add_damage_feedback overflow (v0.2.9, Phase 0)
-- ============================================================
-- VANILLA bug (scripts/ui/hud_ui/unit_frame_ui.lua, add_damage_feedback). A NEW
-- damage-feedback event computes `order_index = #hash_order + 1` and immediately
-- indexes `self._damage_widgets[order_index]`, then `widget.content.visible = true`
-- (vanilla L1687-1690 / L1699-1702) -- BEFORE the over-MAX eviction at the bottom
-- of the function, which is itself dead-coded behind `fassert(false)` (vanilla
-- L1724-1725). The pool only holds `#self._damage_widgets` widgets (4 when
-- features_list.damage is on, 0 when off). When more than that many distinct
-- damage events are active at once, `order_index` exceeds the pool, the lookup
-- returns nil, and `widget.content.visible = true` is a fatal index-of-nil. On
-- the HOST this crashes the whole session.
-- Reproduced in Versus: a Pactsworn Ratling Gunner's sustained machinegun fire
-- stacks 5+ simultaneous damage-feedback messages on one hero frame
-- (crash GUID 59ae9a93-..., 2026-06-15; NumericUI re-news the vanilla UnitFrameUI
-- which keeps this vanilla path live).
--
-- Fix: a real wrapper that DROPS the overflow event before it reaches the nil
-- index -- only when (a) the pool is already full AND (b) a new order_index would
-- be assigned (a brand-new event, or a re-activated `disabled` one). Existing
-- active events (the common case -- repeated hits accumulate into one hash) pass
-- straight through untouched. The cap is self-healing: vanilla
-- `_update_damage_feedback` removes expired events from `_hash_order`
-- (table.remove at the remove_time check, vanilla L1819), freeing slots. No
-- vanilla state is mutated here -- it is a pure pre-call guard that degrades
-- safely (just stops dropping) if the vanilla shape ever drifts. Perf: the
-- full_hash/events work only runs in the rare at-capacity case; the common path
-- is two `#` reads. Always-on (a safety guard, not a toggled feature).
mod._gut_damage_feedback_should_drop = function(num_active, pool_size, is_new_event)
    -- Drop iff a NEW order_index would be assigned and it would exceed the
    -- widget pool (== the vanilla nil-index crash condition).
    return is_new_event and num_active >= pool_size
end

mod:hook("UnitFrameUI", "add_damage_feedback", function(func, self, hash, is_local_player, event_type, attacker_player, target_player, damage_amount)
    local hash_order = self._hash_order
    local damage_widgets = self._damage_widgets
    -- Only the at/over-capacity case can crash; skip all work otherwise.
    if hash_order and damage_widgets and #hash_order >= #damage_widgets then
        local events = self._damage_events
        if events then
            local existing = events[tostring(hash) .. tostring(event_type)]
            local will_add_new = (not existing) or existing.disabled or false
            if mod._gut_damage_feedback_should_drop(#hash_order, #damage_widgets, will_add_new and true or false) then
                return  -- pool full + new event: vanilla would index a nil widget. Drop it.
            end
        end
    end
    return func(self, hash, is_local_player, event_type, attacker_player, target_player, damage_amount)
end)

_rt_register("damage_feedback_overflow_guard", function()
    -- Pins the Versus host-crash fix decision rule across boundary cases.
    local f = mod._gut_damage_feedback_should_drop
    if type(f) ~= "function" then return "damage-feedback overflow guard fn missing (Versus host-crash fix reverted?)" end
    if not f(4, 4, true) then return "must DROP a new event when the 4-widget pool is full (the Versus crash case)" end
    if not f(5, 4, true) then return "must DROP a new event when active count exceeds the pool" end
    if not f(0, 0, true) then return "must DROP a new event when the pool is empty (features_list.damage off)" end
    if f(3, 4, true)     then return "must NOT drop a new event when the pool has a free slot" end
    if f(9, 4, false)    then return "must NOT drop an existing event -- only new events get a new order_index" end
end)

-- ============================================================
-- HUD Customizer (v0.2.0) -- in-game edit-mode + click-and-drag
-- repositioning of native HUD widgets, persisted per-resolution.
-- ============================================================

local Customizer = mod:dofile("scripts/mods/gui_tweaker_dev/_hud_customizer")
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

-- _dbg: hero_view auto-dump. Fires whenever HeroView opens.
mod:hook_safe("HeroView", "on_enter", function(self, ...)
    pcall(Customizer.dump_hero_view, self)
end)

-- VMF emits this callback when the user flips any setting. We use it to log
-- the debug-mode transition unconditionally (only place that does so).
mod.on_setting_changed = function(setting_id)
    if setting_id == "gut_mission_inventory_enabled"
        or setting_id == "gut_mission_hero_select_enabled" then
        -- In-mission inventory + hero-select share the same InventorySettings
        -- loadout-access data patch (body in _gut_mission_inventory.lua); both
        -- panels need it to render mid-mission. mod._gut_apply_keep_menus is a table
        -- field resolved at call time (the module dofile's later in this file).
        if mod._gut_apply_keep_menus then mod._gut_apply_keep_menus() end
    elseif setting_id == "gut_skip_cutscenes_enabled" then
        -- Skip Cutscenes (migrated from gt, issue #106): persistently mirror the
        -- VMF checkbox into the engine's skip gate, exactly as gt's on_setting_changed
        -- did. The _gut_cutscenes.lua hooks also flip this transiently per-skip, so the
        -- feature works either way; this keeps the persistent flag in sync for any
        -- engine path that reads it directly.
        script_data = script_data or {}
        script_data.skippable_cutscenes = mod:get("gut_skip_cutscenes_enabled") or nil
    end
end

-- Re-apply the in-mission inventory InventorySettings patch + ESC-menu entry on
-- every game-state transition, since the engine can reload InventorySettings and
-- the per-mission deus/adventure gate must be re-evaluated. mod._gut_apply_keep_menus
-- is a table field resolved at call time (body in _gut_mission_inventory.lua).
mod.on_game_state_changed = function(status, state_name)
    if mod._gut_apply_keep_menus then mod._gut_apply_keep_menus() end
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

mod:command("edit_hud", "Toggle HUD edit mode (click-drag widgets to reposition)", function()
    local enabled = not (Customizer.is_edit_mode() and true or false)
    -- We only flip the sticky bit; the alt-gesture path stays independent.
    Customizer.set_sticky(enabled)
    if enabled then
        mod:echo("Edit mode: ON (resolution " .. tostring(Customizer.resolution_key()) .. "). Drag widgets with left mouse.")
    else
        mod:echo("Edit mode: OFF.")
    end
end)

mod:command("reset_hud", "Reset HUD widget(s) to vanilla position. Usage: /reset_hud [widget_id]", function(arg)
    if arg and arg ~= "" then
        local ok = Customizer.reset_widget(arg)
        if ok then
            mod:echo("Reset HUD widget '" .. tostring(arg) .. "' to vanilla position.")
        else
            mod:echo("Reset failed: unknown widget id '" .. tostring(arg) .. "'. Run /list_hud for valid ids.")
        end
    else
        local n = Customizer.reset_all()
        mod:echo(string.format("Reset all HUD widgets (%d entries) for resolution %s.", n, tostring(Customizer.resolution_key())))
    end
end)

mod:command("list_hud", "List current HUD widget offsets for this resolution", function()
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
-- exposed at `get_mod("gut_dev").mod_tweaker`. v0.1 just stands up the API
-- and registry; the ESC entry, view rendering, and widget factories
-- arrive in follow-up tasks. Authors detect with:
--   local gut = get_mod("gut_dev")
--   if gut and gut.mod_tweaker then
--       gut.mod_tweaker:register_category({ mod_id = "...", label = "...", widgets = {...} })
--   end
-- ============================================================

local ok_mt, ModTweaker = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker")
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

-- Dogfood category so the view renders real content (and proves the end-to-end:
-- open -> change -> persist -> on_change). gut's own demo settings live in the
-- Mod Tweaker keyspace (mt::gut::*). Replace/extend once per-mod registration (or
-- VMF auto-mirror) lands.
if mod.mod_tweaker and not mod.mod_tweaker:is_registered("gut_dev") then
    mod.mod_tweaker:register_category({
        mod_id = "gut_dev",
        label  = "Tweaker: GUI dev",
        widgets = {
            {
                setting_id = "mt_demo_slider",
                type       = "slider",
                label      = "Demo slider (proof of render)",
                default    = 5,
                range      = { 0, 20 },
                decimals   = 0,
            },
        },
    })
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
        -- display_name is a LOC KEY (resolved to "Mod Tweaker" via our
        -- append_backend_localizations). Do NOT add a display_name_func returning the
        -- resolved string: the MODERN menu (hero_window_ingame_view.lua:473) does
        -- `text_field = display_name_func() or display_name` and then LOCALIZES
        -- text_field — so a func returning "Mod Tweaker" gets re-localized into
        -- "<Mod Tweaker>". The key path localizes correctly in BOTH menus.
        display_name = "mod_tweaker_button_name",
        fade         = true,
        transition   = "mod_tweaker_view",
    })
    -- Diagnostic for the "ESC menu looks deprecated after leaving the Mod Tweaker"
    -- report: log the full button list each time the layout is built, so we can see
    -- if the count grows (accumulation) or the set changes after the Mod Tweaker.
    local ts = {}
    for i = 1, #entries do ts[#ts + 1] = tostring(entries[i].transition) end
    mod:debug("[mt:esc] setup_button_layout -> %d buttons: [%s]", #entries, table.concat(ts, ", "))
end)

-- Build + attach the Mod Tweaker view into an IngameUI instance's `views` table.
-- Idempotent. Used by BOTH the setup_views hook (early attempt) and the
-- transition closure (lazy, on demand). At transition time the IngameUI is fully
-- initialised (self.views populated, self.ingame_ui_context set at
-- ingame_ui.lua:138), so the lazy path is the reliable one — the setup_views
-- post-call hook's timing vs self.views shifted after the game's Versus update,
-- so it now sees self.views as not-yet-a-table and silently bails.
local function _attach_view(self, ctx_arg)
    if not self or type(self.views) ~= "table" then return false end
    if self.views.mod_tweaker_view then return true end
    local ctx = ctx_arg or self.ingame_ui_context
    if not ctx then
        ctx = {
            ui_renderer     = self.ui_renderer,
            ui_top_renderer = self.ui_top_renderer,
            ingame_ui       = self,
            input_manager   = self.input_manager,
            world_manager   = self.world_manager,
        }
    end
    if not (ctx.ui_renderer or ctx.ui_top_renderer) then
        _dbg_alert("[mt] attach: no usable ui_renderer in context; cannot build view")
        return false
    end
    local ok_view, ModTweakerView = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_view")
    if not ok_view or type(ModTweakerView) ~= "table" then
        _dbg_alert("[mt] attach: view dofile failed: %s", tostring(ModTweakerView))
        return false
    end
    local ok_new, view_or_err = pcall(ModTweakerView.new, ModTweakerView, ctx)
    if not ok_new then
        _dbg_alert("[mt] attach: ModTweakerView:new raised: %s", tostring(view_or_err))
        return false
    end
    self.views.mod_tweaker_view = view_or_err
    _dbg("[mt] attach: ModTweakerView attached")
    return true
end

-- Forward-declared so the transition closure below (and the on_enter re-pin in
-- _mod_tweaker_view.lua) can defensively re-pin LA's atlas + log on every Mod
-- Tweaker open (v0.2.56). The keepalive module is dofile'd much later in this file;
-- this local is ASSIGNED at that dofile site (`_gut_la_keepalive = mod:dofile(...)`),
-- but DECLARED here so the closure captures it as an upvalue. `_mt_open_count` is a
-- module-level open counter for the instrumentation (shows 1st/2nd/3rd/4th open).
local _gut_la_keepalive
local _mt_open_count = 0

-- Re-pin LA's atlas package (pcall-guarded) + log the residency/renderer state on
-- every Mod Tweaker open. The Mod Tweaker BORROWS the long-lived IngameUI renderer
-- (does NOT recreate it), and the keepalive's premise that "LA unloads its own
-- package" means the atlas can go missing between opens — so a one-time pin on
-- StateInGameRunning.on_enter isn't enough; we re-pin on each open. The keepalive's
-- own `has_loaded` force-load guard stays intact (it NEVER force-loads a non-resident
-- LA package — that re-introduces the 0.2.54 crash). `self` is the IngameUI (site i)
-- or the ModTweakerView (site ii) — both expose ui_renderer/ui_top_renderer for the
-- renderer-identity probe. Exposed as mod._gut_mt_repin_la so the view module can
-- call the SAME path.
local function _gut_mt_repin_la(self, site)
    _mt_open_count = _mt_open_count + 1
    local pm = Managers and Managers.package
    local resident = "?"
    if pm and pm.has_loaded then
        local ok_r, r = pcall(pm.has_loaded, pm, "resource_packages/Loremasters-Armoury/Loremasters-Armoury")
        resident = ok_r and tostring(r) or ("err:" .. tostring(r))
    end
    local pinned = "?"
    if _gut_la_keepalive and _gut_la_keepalive.is_pinned then
        local ok_p, p = pcall(_gut_la_keepalive.is_pinned)
        pinned = ok_p and tostring(p) or ("err:" .. tostring(p))
    end
    mod:debug("[gut:la] mod-tweaker open #%d (site=%s): LA_resident=%s gut_pinned=%s ui_renderer=%s ui_top_renderer=%s",
        _mt_open_count, tostring(site), resident, pinned,
        tostring(self and self.ui_renderer), tostring(self and self.ui_top_renderer))
    if _gut_la_keepalive and _gut_la_keepalive.pin then
        local ok_pin, err_pin = pcall(_gut_la_keepalive.pin)
        if not ok_pin then
            mod:warning("[gut:la] re-pin pcall raised on open #%d: %s", _mt_open_count, tostring(err_pin))
        end
    end
end
mod._gut_mt_repin_la = _gut_mt_repin_la

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
    settings.transitions.mod_tweaker_view = function(self)
        -- BUILD 2 ROUTING (v0.2.57-dev). The ESC "Mod Tweaker" button has TWO targets:
        --
        --   * IN THE KEEP/INN -> open the HeroView SUB-STATE (gut_mod_tweaker,
        --     _mod_tweaker_state.lua). A sub-state stays INSIDE the already-open
        --     hero_view and never recreates its renderer, so it eliminates BOTH the
        --     deprecated bare-IngameView look on exit AND the LA armoury_atlas
        --     renderer-recreation crash (42c81d84) that the leave/re-enter
        --     standalone-view path triggered. This is the proper fix the old TODO
        --     described.
        --
        --   * IN A MISSION -> there is NO hero_view, so we KEEP the existing standalone
        --     ModTweakerView path (the pre-build-2 behaviour). In a mission the
        --     standalone view's exit routes to "ingame_menu" (never crashed there; no
        --     hero_view to recreate), preserving in-mission access exactly as before.
        --
        -- Keep/inn detection matches _ba_heroview_inject: ingame_ui_context.is_in_inn.
        local ctx = self.ingame_ui_context
        local in_keep = not (ctx and ctx.is_in_inn == false)
        -- v0.2.62-dev REVERT: the keep HeroView sub-state (build 2) reliably OPENED (rows
        -- built) but the HeroView state machine immediately BOUNCED it back to
        -- HeroViewStateOverview (log: overview -> gut_mod_tweaker on_enter rows=13 ->
        -- overview), so it never stayed visible from the ESC button — the "doesn't open
        -- from the main menu" regression. The STANDALONE ModTweakerView opens reliably (it
        -- always did in-mission), and build-3's origin-capture exit (below) returns to the
        -- modern hero_view menu rather than the deprecated bare one, so the sub-state is no
        -- longer needed to avoid the deprecated look. Route the KEEP through the standalone
        -- view too. (HeroViewStateModTweaker + _ba_heroview_inject stay registered for the
        -- /mod_tweaker command.) Flip _USE_KEEP_SUBSTATE back only after the sub-state
        -- bounce is root-caused.
        local _USE_KEEP_SUBSTATE = false
        if _USE_KEEP_SUBSTATE and in_keep and self.transition_with_fade and rawget(_G, "HeroViewStateModTweaker") then
            _dbg("[mt] ESC entry in keep -> hero_view sub-state gut_mod_tweaker")
            -- force_open = true is LOAD-BEARING. The ESC "Mod Tweaker" button fires from
            -- INSIDE the already-open keep ESC menu, which IS hero_view (the ingame_menu
            -- window inside HeroViewStateOverview), so self.current_view == "hero_view"
            -- ALREADY. Without force_open, IngameUI.handle_transition's guard
            -- `if old_view ~= new_view or force_open` (ingame_ui.lua:953) is false→false,
            -- so it SKIPS HeroView:on_enter / post_update_on_enter — and post_update_on_enter
            -- is the ONLY path that reads menu_state_name (hero_view.lua:504-508). Result
            -- (the reported bug): the fade plays but the gut_mod_tweaker sub-state never
            -- opens. force_open forces the re-enter so menu_state_name is honored. This is
            -- the EXACT vanilla keep-button flow: every keep ESC menu button (Inventory,
            -- Loot, ...) uses transition="hero_view" + transition_state=<screen> +
            -- force_open=true (ingame_view_menu_layout_console.lua:742-745).
            self:transition_with_fade("hero_view", {
                menu_state_name = "gut_mod_tweaker",
                force_open = true,
            })
            return
        end

        -- In-mission path (or sub-state unavailable): standalone ModTweakerView.
        -- DEFENSIVE re-pin LA's atlas + instrument BEFORE attaching/showing the view
        -- (site i). The borrowed renderer is long-lived, so the atlas can be unloaded
        -- between opens; re-pin every open (pcall-guarded, has_loaded-gated inside).
        pcall(_gut_mt_repin_la, self, "transition")
        -- Lazy-attach on demand: at click time the IngameUI is fully initialised, so
        -- this is the reliable build point. Idempotent. Only switch if the view
        -- actually attached, so a build failure stays a harmless no-op.
        _attach_view(self)
        if self.views and self.views.mod_tweaker_view then
            -- Capture the ORIGIN menu so exit returns to it. In a mission ESC opens
            -- EITHER the modern HeroView menu (current_view == "hero_view", the default
            -- when use_pc_menu_layout=false) OR the legacy IngameView (current_view ==
            -- "ingame_menu"). self.current_view is still the origin here — the engine
            -- snapshots old_view BEFORE invoking this closure (ingame_ui.lua:946) — so
            -- reading it now gives the menu the player actually opened. Hard-coding
            -- "ingame_menu" dumped modern-menu players into the deprecated bare
            -- IngameView on exit. ModTweakerView:exit already safely handles the
            -- "hero_view" target (supplies { menu_state_name = "overview" }).
            local origin = self.current_view
            self.views.mod_tweaker_view._exit_transition =
                (origin == "hero_view") and "hero_view" or "ingame_menu"
            self.current_view = "mod_tweaker_view"
        else
            _dbg_alert("[mt] transition: view not attached; ESC entry is a no-op")
        end
    end
    _dbg("[mt] transition registered: mod_tweaker_view")
end)
if not ok_settings_inject then
    _dbg_alert("[mt] transitions injection failed: %s", tostring(settings_inject_err))
end

-- ============================================================
-- Open the Mod Tweaker from gameplay (#125) — hotkey + chat command
-- ============================================================
-- The Mod Tweaker settings menu is reachable from the ESC menu's "Mod Tweaker"
-- button (the IngameViewLayoutLogic.setup_button_layout injection above). This
-- exposes a DIRECT opener so a function-call keybind + a chat command can open it
-- without going through the ESC menu first.
--
-- It drives the SAME `mod_tweaker_view` transition the ESC button uses (registered
-- just above), via Managers.ui:handle_transition — so there is NO new hook and NO
-- duplicated open logic. The transition closure handles attach + origin-capture +
-- current_view, and works from raw gameplay (current_view is nil there, so the
-- closure sets _exit_transition = "ingame_menu" as the FALLBACK only). With the
-- #124 change the view's exit always routes to "exit_menu" (game), so a hotkey-
-- opened menu — which has no originating menu — correctly returns to gameplay on
-- exit. Mirrors the sibling in-mission inventory/hero-select openers
-- (Managers.ui:handle_transition(..., { use_fade = true })).
--
-- SCOPE: keep AND mid-mission. The Mod Tweaker is a borrowed-renderer settings
-- LIST (not a preview world), so it is NOT subject to the keep-only preview-world
-- crash class that gates the hero-select/inventory features — the standalone
-- ModTweakerView already opens reliably in-mission via the ESC button, and this
-- reuses that exact path. No Chaos Wastes/deus gate is needed (no loadout surface).
-- (In-mission behavior still wants the user's in-game confirmation.)
mod.gut_open_mod_tweaker = function()
    if not (Managers.ui and Managers.ui.handle_transition) then
        mod:echo("UI manager not available (not in-game?).")
        return
    end
    local ok, err = pcall(function()
        Managers.ui:handle_transition("mod_tweaker_view", { use_fade = true })
    end)
    if not ok then
        mod:echo("Could not open the Mod Tweaker: " .. tostring(err))
    end
end

mod:command("mod_tweaker", "Open the Mod Tweaker settings menu (works in the keep and mid-mission). Same as the gut_open_mod_tweaker_hotkey keybind and the ESC-menu 'Mod Tweaker' button.", function()
    mod.gut_open_mod_tweaker()
end)

-- NOTE the second param: IngameUI.init passes the context to setup_views as an
-- ARGUMENT (ingame_ui.lua:107) and does NOT store self.ingame_ui_context until
-- later, so reading self.ingame_ui_context here is nil — that nil context made
-- ModTweakerView:new throw, the view never attached, and transitioning to the
-- (missing) view crashed IngameUI at ingame_ui.lua:625. Capture the arg instead.
-- Early attach attempt. May no-op if self.views isn't populated yet at this
-- hook's timing (the transition lazy-attach is the guaranteed path).
mod:hook_safe("IngameUI", "setup_views", function(self, ingame_ui_context)
    _attach_view(self, ingame_ui_context)
end)

-- The ESC-menu "Mod Tweaker" button is the raw key "mod_tweaker_button_name"
-- (ingame_view.lua:252 content.title_text = data.display_name, :138
-- title_text.localize = true), localized at draw by the engine localizer. VMF mod
-- loc is NOT in the engine tables, so it rendered as "<mod_tweaker_button_name>".
--
-- TWO prior HOOK fixes FAILED: (a) hooking _G.Localize — the global is set via
-- rawset in LocalizationManager.init, so a re-init blows the VMF wrapper away; and
-- (b) hooking LocalizationManager.lookup — the button's text pass ALSO localizes
-- via LocalizationManager.simple_lookup (ui_passes.lua:1599), a SIBLING method that
-- `lookup` never routes through. Both are interception; both miss a path.
--
-- ROOT-CAUSE FIX (workflow wf_8504e8ba): SUPPLY the string instead of intercepting.
-- LocalizationManager._base_lookup checks self._backend_localizations FIRST
-- (localization_manager.lua:50-51) and is the shared bottom of BOTH lookup and
-- simple_lookup, so registering the string there resolves on every path natively —
-- no wrapped closure to bypass. (LA already hooks _base_lookup in the field,
-- confirming that table is the universal chokepoint.)
local function _register_button_loc()
    local loc = Managers and Managers.localizer
    if loc and loc.append_backend_localizations then
        pcall(loc.append_backend_localizations, loc, { mod_tweaker_button_name = "Mod Tweaker" })
        -- PROBE: after registering, what does the engine localizer actually return
        -- for the key? If this prints "Mod Tweaker", the append works and any <> the
        -- user still sees is a DIFFERENT element (not this ESC button). If it prints
        -- "<mod_tweaker_button_name>", the backend-loc path is NOT what this button
        -- localizes through and we need a different fix.
        local resolved = "?"
        if rawget(_G, "Localize") then pcall(function() resolved = Localize("mod_tweaker_button_name") end) end
        mod:info("[mt] registered backend loc; Localize('mod_tweaker_button_name') -> '%s'", tostring(resolved))
        return true
    end
    mod:info("[mt] backend-loc register SKIPPED (Managers.localizer not ready at this point)")
    return false
end
-- Register at boot if the localizer is already up; otherwise on_all_mods_loaded (below)
-- and the IngameView.on_enter retry guarantee it's set before the ESC menu draws.
_register_button_loc()
-- _backend_localizations is reset to {} in LocalizationManager.init (a mid-session
-- language switch re-inits), so re-register after any re-init. This is DATA, not a
-- wrapped closure — immune to the rawset/VMF-chain fragility that killed both hooks.
mod:hook_safe("LocalizationManager", "init", function()
    _register_button_loc()
end)
-- Belt-and-suspenders: register when the ESC menu opens (Managers.localizer is
-- definitely up by then), so even if boot/on_all_mods_loaded missed, the key is set
-- before the button's title_text is drawn. (gut hooks HeroView.on_enter, not
-- IngameView.on_enter — distinct pair, no duplicate.)
mod:hook_safe("IngameView", "on_enter", function()
    _register_button_loc()
end)

-- ESC/keep-menu button-overflow compaction (v0.2.56; REWRITTEN v0.2.64-dev — was
-- hooking the WRONG class for 8 versions).
--
-- DIAGNOSIS of why the prior fix never worked:
--   * The keep pause/ESC menu the user sees is NOT the legacy IngameView. The
--     reported button list (character_selection / spoils_of_war /
--     return_to_pc_menu_hero_view / quit_game_hero_view, 10 entries) is the MODERN
--     HeroView sub-window `HeroWindowIngameView` (hero_window_ingame_view.lua) — the
--     "Main Menu" screen inside hero_view. That class has NO set_background_height
--     method; the gut hook on `IngameView.set_background_height` therefore NEVER
--     FIRED for the keep menu. (Legacy IngameView is only the bare in-MISSION menu.)
--   * Even on the legacy IngameView path the logo branch was dead: IngameView.
--     create_ui_elements (ingame_view.lua:122-152) NEVER assigns self.logo — the logo
--     widget isn't even instantiated there (it has no `logo` widget def), so
--     `if self.logo ...` was always nil. The visible logo comes from the modern menu.
--
-- The modern menu lays out its button column + sizes its panel in
-- HeroWindowIngameView._update_presentation (hero_window_ingame_view.lua:490-515):
-- each title button gets `offset[2] = -(60 * index - 1)` (spacing = 60, line 504),
-- and the background panel grows to `total_height + 90` (line 513). With 10 buttons
-- the column runs `0 .. -540` and overflows off the bottom. The logo widget is
-- `_widgets_by_name.logo` (definitions :287, scenegraph node "logo").
--
-- FIX: hook_safe `HeroWindowIngameView._update_presentation` (runs AFTER vanilla
-- positions the column, so our shift/hide stick) and, once over the overflow
-- threshold: (a) lift the whole button column up by re-walking the same index→offset
-- math with a reduced spacing AND a positive top bias, and (b) hide the logo by
-- zeroing its style.color alpha. hook_safe is correct (the vanilla method returns
-- nothing; it mutates widget offsets + the scenegraph in place). This (Class,method)
-- pair is hooked NOWHERE ELSE in gut — grep-verified before adding (the only other
-- HeroView-family hook is HeroView.on_enter, a different class+method).
--
-- (#93) ALWAYS-ON implicit feature (2026-06-24): the `gut_compact_esc_menu` toggle +
-- setting were removed — this was never meant to be optional (gut itself adds the Mod
-- Tweaker ESC button that causes the overflow this fixes, so the fix should always run,
-- like wt's auto-vent). The hook is only a no-op below the overflow threshold anyway, so
-- there's nothing to gate. No setting read remains.
--
-- NOTE the COLUMN_SHIFT / SPACING numbers below are TUNE-IN-GAME values — they move
-- the column the right DIRECTION (up) but the exact lift needs an in-game eyeball.
local _MT_ESC_OVERFLOW_THRESHOLD = 8   -- vanilla keep menu is ~8 buttons; gut + VMF push it to 10
mod:hook_safe("HeroWindowIngameView", "_update_presentation", function(self)
    local buttons = self._title_button_widgets
    local layout_logic = self.layout_logic
    if not (buttons and layout_logic) then return end
    local ok_ld, layout_data = pcall(layout_logic.layout_data, layout_logic)
    if not ok_ld or type(layout_data) ~= "table" then return end
    local num = #layout_data
    if num < _MT_ESC_OVERFLOW_THRESHOLD then return end

    -- Re-pack the column tighter so all `num` buttons fit, and bias the whole stack
    -- UP. Vanilla uses spacing = 60 starting near offset 0 (descending). We compress
    -- spacing and add a positive top bias = half the saved height, re-centring the
    -- shorter column. (Vanilla math: hero_window_ingame_view.lua:497-505.)
    local VANILLA_SPACING = 60
    local SPACING = 48                                  -- tighter rows (TUNE IN-GAME)
    local saved = (VANILLA_SPACING - SPACING) * num     -- total height reclaimed
    local TOP_BIAS = math.floor(saved / 2)              -- lift so the column re-centres
    for index = 1, num do
        local w = buttons[index]
        if w and w.offset then
            -- mirrors vanilla `-(spacing * index - 1)` with our spacing + the up-bias.
            w.offset[2] = -(SPACING * index - 1) + TOP_BIAS
        end
    end

    -- Hide the keep logo so the (now lifted) column has clear headroom. The logo
    -- widget is _widgets_by_name.logo (definitions :287, built via
    -- UIWidgets.create_simple_texture). create_simple_texture nests color under
    -- style.texture_id.color, NOT style.color (ui_widgets.lua:5302-5318) — the prior
    -- IngameView code read the wrong path, which was part of why "logo still shows".
    -- VT2 color tables are {A,R,G,B}, so alpha is index [1]. Idempotent — re-zeroing
    -- each presentation rebuild is harmless.
    local wbn = self._widgets_by_name
    local logo = wbn and wbn.logo
    local lstyle = logo and logo.style and logo.style.texture_id
    if lstyle and lstyle.color then
        lstyle.color[1] = 0
    end

    -- Lift the keep separator/divider by the same amount as the button column so it
    -- sits ABOVE the menu text instead of bleeding through it. _widgets_by_name.divider
    -- is the upper rule (hero_window_ingame_view_definitions.lua:279,
    -- UIWidgets.create_simple_texture("divider_01_top", "divider"); sg node "divider").
    -- NOT divider_bottom (:280, the lower rule). It's registered into _widgets_by_name
    -- in create_ui_elements (:161-169), so it's drawable/mutable here. The button
    -- column was lifted +TOP_BIAS via each button widget's render offset[2] (:1096);
    -- mutating the divider's render offset[2] the SAME {0,0,0} field keeps the shift
    -- isolated to the divider texture (does NOT cascade to the logo/panel/buttons that
    -- are scenegraph-parented to the "divider" node — a render-offset change doesn't
    -- touch the scenegraph). Idempotent: TOP_BIAS is recomputed each presentation
    -- rebuild and vanilla never resets this offset, so SET (not +=) to avoid drift.
    local divider = wbn and wbn.divider
    if divider and divider.offset then
        divider.offset[2] = TOP_BIAS
    end
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
    -- Smoke (IN-MISSION fallback, build 2): force is_in_inn=false and supply NO
    -- transition_with_fade so the closure takes the standalone-ModTweakerView branch.
    -- Pre-seed views.mod_tweaker_view so _attach_view short-circuits (idempotent
    -- early-return) without needing a real renderer; the closure must then set
    -- current_view. (The keep branch routes via transition_with_fade -> hero_view
    -- sub-state and is covered by mod_tweaker_substate_registered below.)
    local fake = {
        ingame_ui_context = { is_in_inn = false },
        views = { mod_tweaker_view = { _exit_transition = nil } },
    }
    settings.transitions.mod_tweaker_view(fake)
    if fake.current_view ~= "mod_tweaker_view" then
        return "in-mission transition did not set current_view = mod_tweaker_view"
    end

    -- ORIGIN-CAPTURE (v0.2.58-dev): the in-mission exit must return to whichever
    -- menu the player opened. The closure reads self.current_view (the engine's
    -- pre-closure origin snapshot) and routes "hero_view" origin -> "hero_view",
    -- everything else -> "ingame_menu". Assert both branches so a regression that
    -- re-hardcodes "ingame_menu" (the deprecated-bare-menu bug) is caught.
    local function _exit_for(origin)
        local f = {
            current_view = origin,
            ingame_ui_context = { is_in_inn = false },
            views = { mod_tweaker_view = { _exit_transition = nil } },
        }
        settings.transitions.mod_tweaker_view(f)
        return f.views.mod_tweaker_view._exit_transition
    end
    local et_hero = _exit_for("hero_view")
    if et_hero ~= "hero_view" then
        return string.format("hero_view origin did not set _exit_transition = hero_view (got %s)", tostring(et_hero))
    end
    local et_legacy = _exit_for("ingame_menu")
    if et_legacy ~= "ingame_menu" then
        return string.format("ingame_menu origin did not set _exit_transition = ingame_menu (got %s)", tostring(et_legacy))
    end

    -- KEEP branch (v0.2.60-dev): in the keep (is_in_inn ~= false) the closure must route
    -- to the hero_view sub-state via transition_with_fade WITH force_open = true and
    -- menu_state_name = "gut_mod_tweaker". Dropping force_open is the regression that made
    -- the ESC button darken-then-open-nothing (the keep ESC menu IS hero_view, so without
    -- force_open IngameUI.handle_transition skips the re-enter and menu_state_name is
    -- ignored). Capture the call to assert both params survive.
    if rawget(_G, "HeroViewStateModTweaker") then
        local captured
        local fake_keep = {
            ingame_ui_context = { is_in_inn = true },
            transition_with_fade = function(_self, transition, params)
                captured = { transition = transition, params = params or {} }
            end,
        }
        settings.transitions.mod_tweaker_view(fake_keep)
        if not captured then
            return "keep branch did not call transition_with_fade"
        end
        if captured.transition ~= "hero_view" then
            return string.format("keep branch transition not 'hero_view' (got %s)", tostring(captured.transition))
        end
        if captured.params.menu_state_name ~= "gut_mod_tweaker" then
            return string.format("keep branch menu_state_name not 'gut_mod_tweaker' (got %s)", tostring(captured.params.menu_state_name))
        end
        if captured.params.force_open ~= true then
            return "keep branch missing force_open = true (the darken-then-nothing regression)"
        end
    end
end)

-- Build 2: the Mod Tweaker KEEP sub-state must register exactly like the compendium —
-- the class global exists and the gut_mod_tweaker screen descriptor is appended in the
-- SINGLE HeroView.init hook (no duplicate hook). This marker mirrors the compendium's
-- registration invariant.
_rt_register("mod_tweaker_substate_registered", function()
    if not rawget(_G, "HeroViewStateModTweaker") then
        return "HeroViewStateModTweaker class global not defined (state dofile failed)"
    end
    local C = rawget(_G, "HeroViewStateModTweaker")
    for _, name in ipairs({ "on_enter", "update", "post_update", "on_exit",
                            "input_service", "close_menu" }) do
        if type(C[name]) ~= "function" then
            return string.format("HeroViewStateModTweaker:%s is not a function (got %s)",
                name, type(C[name]))
        end
    end
    if type(mod._gut_open_mod_tweaker) ~= "function" then
        return "mod._gut_open_mod_tweaker opener not defined (inject module didn't load)"
    end
    return nil
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
    local Settings = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_settings")
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

-- v0.2.59-dev — the gear "Advanced Settings" drill-down + the slider thumb-move fix.
-- (1) The defs module must export the gear + back-row factories, and a built gear must
--     carry a hotspot pass WITH an explicit style.hotspot (rows share the mt_list_start
--     node, so a missing style collapses the hit target to 1x1).
-- (2) The slider must drive its thumb/fill via a `local_offset` pass — the ONLY pass
--     type the engine invokes `offset_function` for (ui_passes.lua:4587). A regression
--     that re-attaches offset_function to a texture/rect pass (where it's ignored, the
--     build-3 "thumb doesn't move" bug) would have NO local_offset pass and is caught here.
_rt_register("mod_tweaker_gear_and_slider", function()
    local defs = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_definitions")
    if type(defs.create_gear_button) ~= "function" then return "create_gear_button factory missing" end
    if type(defs.create_back_row) ~= "function" then return "create_back_row factory missing" end

    local gear = defs.create_gear_button(-46)
    if type(gear) ~= "table" then return "create_gear_button did not return a widget" end
    local g_has_hotspot, g_styled = false, false
    for _, p in ipairs(gear.element.passes) do
        if p.pass_type == "hotspot" then g_has_hotspot = true; if p.style_id then g_styled = true end end
    end
    if not g_has_hotspot then return "gear widget has no hotspot pass" end
    if not g_styled then return "gear hotspot lacks style_id (hit target would collapse to 1x1)" end
    if not (gear.style and gear.style.hotspot and gear.style.hotspot.size) then
        return "gear hotspot has no explicit style.hotspot.size"
    end

    -- A slider must contain a local_offset pass carrying an offset_function.
    local base = { 0, -10, 0 }
    local slider = defs.create_slider("rt probe", "", base)
    local has_local_offset = false
    for _, p in ipairs(slider.element.passes) do
        if p.pass_type == "local_offset" and type(p.offset_function) == "function" then
            has_local_offset = true
        end
    end
    if not has_local_offset then
        return "slider has no local_offset pass with offset_function (thumb/fill would not move)"
    end
end)

-- (#95) Keybind / table read-only values must route through _format_keybind_value
-- in _mod_tweaker_view.lua, NOT tostring(), or a VMF keybind (a Lua TABLE like
-- {"left alt"}) renders its raw address ("CYCLE HUD MODE: table: 0x..."). Source
-- guard: read the VIEW file (anchored via debug.getinfo on a ModTweakerView method)
-- and assert BOTH (a) the formatter helper is present and (b) the read-only branch
-- routes keybind/table values through it. Needles are split across two literals so
-- this test's own source can't self-match. Degrades to a no-op when source
-- introspection is unavailable (deploy/bundle paths ship no readable .lua).
_rt_register("mod_tweaker_keybind_render", function()
    local ok_view, View = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_view")
    if not ok_view or type(View) ~= "table" or type(View._handle_input) ~= "function" then
        return  -- can't reach the view module; skip
    end
    local ok, info = pcall(debug.getinfo, View._handle_input, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local f = io.open(src_path, "r")
    if not f then return end
    local txt = f:read("*a")
    f:close()
    if not txt then return end
    -- (a) the formatter helper must exist.
    local helper_needle = "_format_keybind" .. "_value"
    if not txt:find(helper_needle, 1, true) then
        return "#95 regression: _format_keybind_value is absent from _mod_tweaker_view.lua (keybinds would render a raw table address)"
    end
    -- (b) the read-only branch must route wtype=="keybind" OR a table value through it.
    local branch_needle = 'wtype == "keybind" or type(val)' .. ' == "table"'
    if not txt:find(branch_needle, 1, true) then
        return "#95 regression: read-only row no longer routes keybind/table values through _format_keybind_value (raw 'table: 0x...' would reach the label)"
    end
    local routed_needle = ': " .. _format_keybind' .. "_value(val)"
    if not txt:find(routed_needle, 1, true) then
        return "#95 regression: the keybind/table branch does not call _format_keybind_value(val)"
    end
end)

-- (#91) Scrollbar thumb drag must use a GRAB-OFFSET anchor (the cursor-Y at grab +
-- the scroll_value at grab), then track the cursor DELTA over the thumb's travel —
-- NOT the old absolute-position snap that jumped the thumb top to the cursor.
-- Source guard on _mod_tweaker_view.lua's _handle_input: assert both grab-anchor
-- fields survive. Split needles to avoid self-match; no-op when source unreadable.
_rt_register("mod_tweaker_scrollbar_grab_offset", function()
    local ok_view, View = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_view")
    if not ok_view or type(View) ~= "table" or type(View._handle_input) ~= "function" then
        return
    end
    local ok, info = pcall(debug.getinfo, View._handle_input, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local f = io.open(src_path, "r")
    if not f then return end
    local txt = f:read("*a")
    f:close()
    if not txt then return end
    local cursor_anchor = "_sb_grab_cursor" .. "_y"
    local scroll_anchor = "_sb_grab_scroll" .. "_value"
    if not txt:find(cursor_anchor, 1, true) or not txt:find(scroll_anchor, 1, true) then
        return "#91 regression: scrollbar thumb drag no longer records a grab-offset anchor (reverted to absolute-position snapping — grabbing the thumb jumps it)"
    end
end)

-- (#92 corrected) The stepper/slider arrow glow must match the VANILLA GAME SETTINGS
-- menu (create_stepper_widget, options_view_definitions.lua:3054), NOT VMF. Native draws
-- TWO sprites per arrow: a base `settings_arrow_normal` at FULL alpha (font_default,255 —
-- :3415/:3457) that is NEVER dimmed at idle, plus a separate `settings_arrow_clicked`
-- OVERLAY seeded color {0,255,255,255} = alpha 0 (:3428-3433/:3470-3475) that fades up to
-- 255 on hover (OptionsView.on_stepper_arrow_hover, options_view.lua:4335-4369). The glow
-- is the _clicked overlay APPEARING, not an alpha ramp on the base. Table-introspection of
-- a built slider (which calls _append_arrows) asserts: (a) the base arrows draw
-- settings_arrow_normal at FULL alpha 255 (NOT dim); (b) the _clicked hover OVERLAYS exist
-- drawing settings_arrow_clicked seeded at alpha 0; (c) a local_offset pass with an
-- offset_function drives the overlay alpha 0->255.
_rt_register("mod_tweaker_arrow_hover_glow", function()
    local defs = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_definitions")
    if type(defs.create_slider) ~= "function" then return "create_slider factory missing" end
    local base = { 0, -10, 0 }
    local slider = defs.create_slider("rt probe", "", base)
    if type(slider) ~= "table" or not (slider.element and slider.element.passes) then
        return "create_slider did not return a renderable widget"
    end
    -- (a) base arrows draw settings_arrow_normal at FULL alpha (idle must NOT be dimmed —
    -- native :3415/:3457 are font_default,255).
    local la = slider.content and slider.content.left_arrow
    if not (la and la.texture_id == "settings_arrow_normal") then
        return "#92 regression: base left arrow no longer draws settings_arrow_normal"
    end
    local las = slider.style and slider.style.left_arrow
    if not (las and las.color and las.color[1] == 255) then
        return "#92 regression: base arrow not at FULL idle alpha 255 (vanilla draws the idle sprite full; a dimmed idle is the wrong-menu VMF ramp)"
    end
    -- (b) the _clicked hover OVERLAYS must exist, drawing settings_arrow_clicked seeded at
    -- alpha 0 (native left_arrow_hover/right_arrow_hover color {0,...}).
    local lah = slider.content and slider.content.left_arrow_hover
    if not (lah and lah.texture_id == "settings_arrow_clicked") then
        return "#92 regression: missing _clicked hover overlay (vanilla glow = settings_arrow_clicked overlay fading in over the base)"
    end
    local lahs = slider.style and slider.style.left_arrow_hover
    if not (lahs and lahs.color and lahs.color[1] == 0) then
        return "#92 regression: _clicked hover overlay not seeded at alpha 0 (native seed {0,255,255,255}; it ramps to 255 on hover)"
    end
    -- (c) a local_offset pass with an offset_function must drive the overlay alpha ramp
    -- (only a local_offset pass's offset_function runs each frame).
    local has_local_offset = false
    for _, p in ipairs(slider.element.passes) do
        if p.pass_type == "local_offset" and type(p.offset_function) == "function" then
            has_local_offset = true
        end
    end
    if not has_local_offset then
        return "#92 regression: no local_offset pass with an offset_function — the _clicked overlay alpha ramp cannot run"
    end
end)

-- (#92 corrected) The COLLAPSED dropdown arrow must match the VANILLA GAME SETTINGS
-- dropdown (create_drop_down_widget, options_view_definitions.lua:2299): a visible arrow
-- in BOTH states (down sprite when closed, up-flip when open — it never disappears), with
-- the brighter drop_down_menu_arrow_clicked glow sprite layering on hover/open. Asserts:
-- (a) base arrow_down + arrow_up passes both exist and are gated on content.active so one
-- is ALWAYS drawn; (b) an arrow_glow pass draws drop_down_menu_arrow_clicked; (c) the base
-- arrows are at FULL alpha (never gated to a blank/dimmed open state).
_rt_register("mod_tweaker_dropdown_arrow_glow", function()
    local defs = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_definitions")
    if type(defs.create_dropdown) ~= "function" then return "create_dropdown factory missing" end
    local dd = defs.create_dropdown("rt probe dd", { 0, -10, 0 }, 0)
    if type(dd) ~= "table" or not (dd.element and dd.element.passes) then
        return "create_dropdown did not return a renderable widget"
    end
    -- (a) both base arrows present; one drawn when closed, one when open -> never blank.
    local has_down, has_up, has_glow = false, false, false
    local down_check, up_check = nil, nil
    for _, p in ipairs(dd.element.passes) do
        if p.style_id == "arrow_down" then has_down = true; down_check = p.content_check_function end
        if p.style_id == "arrow_up"   then has_up   = true; up_check   = p.content_check_function end
        if p.style_id == "arrow_glow" then has_glow = true end
    end
    if not (has_down and has_up) then
        return "#92 regression: dropdown missing a base down/up arrow pass (the arrow must stay visible when open — never gate the only arrow off active)"
    end
    -- The closed pass shows when NOT active, the open pass shows when active -> exactly one
    -- base arrow is always drawn, so opening can never blank the arrow.
    if not (down_check and up_check and down_check({ active = false }) and up_check({ active = true })
            and not down_check({ active = true }) and not up_check({ active = false })) then
        return "#92 regression: dropdown arrow gating wrong (closed must draw the down arrow, open the up arrow — the open state must not be blank)"
    end
    -- (b) the _clicked glow sprite overlay exists (drop_down_menu_arrow_clicked).
    local glowc = dd.content and dd.content.arrow_glow
    if not (has_glow and glowc and glowc.texture_id == "drop_down_menu_arrow_clicked") then
        return "#92 regression: dropdown missing the drop_down_menu_arrow_clicked glow overlay (native hover/open glow sprite)"
    end
    -- (c) base arrows at FULL alpha in both states (native style.arrow color = font_default,255).
    local ad, au = dd.style and dd.style.arrow_down, dd.style and dd.style.arrow_up
    if not (ad and ad.color and ad.color[1] == 255 and au and au.color and au.color[1] == 255) then
        return "#92 regression: dropdown base arrows not at FULL alpha (native arrow is font_default,255 closed AND open; a dim/0 open arrow is the disappearing-arrow defect)"
    end
end)

-- (#93) Compact-ESC menu compaction is now an UNCONDITIONAL implicit feature — the
-- gut_compact_esc_menu TOGGLE + setting were removed (2026-06-24) and the
-- HeroWindowIngameView._update_presentation hook always runs (no-op below the
-- overflow threshold). This guard FAILS if a real setting-READ for that toggle is
-- reintroduced (gating the feature again). It checks the setting-read shape, not the
-- bare string, so the explanatory comment naming the removed toggle does not trip it.
-- Anchored on mod.on_setting_changed (a `mod.` field in the MAIN file). Split needle;
-- no-op when source unreadable.
_rt_register("mod_tweaker_compact_esc_implicit", function()
    local ok, info = pcall(debug.getinfo, mod.on_setting_changed or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local f = io.open(src_path, "r")
    if not f then return end
    local txt = f:read("*a")
    f:close()
    if not txt then return end
    -- A reintroduced gate would read the setting via mod:get(...) on that toggle id.
    -- (The read-shape needle is assembled below from two literals so this very line
    -- and the comment naming the removed toggle can't make the test self-match.)
    local read_needle = 'mod:get("gut_compact_esc' .. '_menu")'
    if txt:find(read_needle, 1, true) then
        return "#93 regression: the gut_compact_esc_menu setting/toggle was reintroduced (the ESC-menu compaction must run unconditionally now)"
    end
end)

-- hb/ SETTING_NAMES-nil crash (2026-06-24): the BOOT loading screen fires the
-- hb/level_loading_screen.lua LoadingView.create_ui_elements hook before
-- hb_data.lua has populated mod.SETTING_NAMES, so reading
-- mod.SETTING_NAMES.HIDE_LOADING_SCREEN_SUBTITLES indexed a nil value and crashed
-- ("attempt to index field 'SETTING_NAMES' (a nil value)"). The fix guards the
-- hook body with `if not mod.SETTING_NAMES then return func(...) end`. This check
-- FAILS if that guard is removed (the crash would return). Source path is derived
-- from a sibling hb/ function (mod.reapply_pickup_ranges, defined in
-- hide_elements.lua) by swapping the filename, since the level_loading_screen
-- hooks are anonymous closures with no addressable reference. Needles are split
-- so this comment/line can't self-match. No-op when source unreadable.
_rt_register("hb_setting_names_guarded", function()
    local ok, info = pcall(debug.getinfo, mod.reapply_pickup_ranges or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local sibling = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    -- hide_elements.lua and level_loading_screen.lua are siblings in hb/.
    local src_path = sibling:gsub("hide_elements%.lua$", "level_loading_screen.lua")
    if src_path == sibling then return end  -- couldn't derive the sibling path; skip
    local f = io.open(src_path, "r")
    if not f then return end
    local txt = f:read("*a")
    f:close()
    if not txt then return end
    local guard_needle = "if not mod.SETTING" .. "_NAMES then"
    local read_needle = "mod.SETTING_NAMES.HIDE_LOADING_SCREEN" .. "_SUBTITLES"
    local guard_at = txt:find(guard_needle, 1, true)
    local read_at = txt:find(read_needle, 1, true)
    if not read_at then return end  -- hook restructured; the specific read is gone
    if not guard_at or guard_at >= read_at then
        return "hb regression: the LoadingView.create_ui_elements hook in hb/level_loading_screen.lua no longer guards mod.SETTING_NAMES before reading HIDE_LOADING_SCREEN_SUBTITLES (boot loading screen would crash 'index field SETTING_NAMES (a nil value)')"
    end
end)

-- UI Tweaks "Temporal Fix" (absorbed): re-aligns stock UI Tweaks (HideBuffs)
-- player HP-bar placement broken by the Versus update. Applied at
-- on_all_mods_loaded (HideBuffs must be loaded first); also tried now in case
-- HideBuffs loaded before us. No-op if UI Tweaks isn't installed. See
-- _gut_uitweaks_temporal_fix.lua for the verified diff + mechanism.
local _gut_temporal_fix = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_uitweaks_temporal_fix")
-- UI Tweaks buff-bar end-time crash fix (absorbed): nil-guards
-- PriorityBuffUI._add_buff so stacking buffs (e.g. Bardin OE pump stacks) stop
-- spamming "attempt to compare nil with number" every frame. No-op if UI Tweaks
-- isn't installed. See _gut_buffbar_endtime_fix.lua for the diagnosed mechanic.
local _gut_buffbar_fix = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_buffbar_endtime_fix")
-- External config file (.toml): on load, override the author's mods' VMF settings
-- with the values in gut_mod_settings.toml. Read-only (the sandbox blocks writes);
-- /export_settings dumps TOML to the log + tools/gut-settings.ps1 writes it.
local _gut_config = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_config_file")
-- Hide UI (3 modes: off/partial/complete/camera) — migrated from general_tweaker.
-- Owns mod.update (chains any prior) for per-frame complete/camera enforcement;
-- registers the gut_hud_cycle keybind function + /hud command.
local _gut_hide_ui = mod:dofile("scripts/mods/gui_tweaker_dev/_hide_ui")
-- GUI material guard: drops any unloadable material from UIRenderer.create before it
-- reaches World.create_screen_gui, which C-fatals (bypasses pcall/xpcall) on a missing
-- material. Prevents the "Gui material not found" client CTD class on mod-compat edges
-- (e.g. More Loading Screens + ui_1080p_chat on mission load, 2026-07-01). Mod-agnostic;
-- the general form of the LA-atlas keepalive below. See _gut_gui_material_guard.lua.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_gui_material_guard")
-- Loremaster's Armoury atlas keep-alive: pins LA's package so its custom atlas can't
-- be unloaded out from under the hero-view HDR renderer (VMF injects it there and the
-- engine C-fatals on a missing material). No-op if LA isn't installed. See
-- _la_atlas_keepalive.lua (crash efadf778).
-- Assigns the forward-declared `_gut_la_keepalive` upvalue (declared above the Mod
-- Tweaker transition closure so that closure + the view module can call its pin()).
_gut_la_keepalive = mod:dofile("scripts/mods/gui_tweaker_dev/_la_atlas_keepalive")
-- NumericUI ability-cooldown realtime fix: VT2 cooldown reduction speeds up the
-- countdown (decreases the value faster), so NumericUI's raw cooldown number visibly
-- speeds up. We divide the cooldown read (only while NumericUI is computing its
-- display) by the cooldown_regen multiplier so it shows accurate, real-time-paced
-- reduced seconds. No-op if NumericUI isn't installed. See _numericui_cooldown_realtime.lua.
local _gut_numericui_cd = mod:dofile("scripts/mods/gui_tweaker_dev/_numericui_cooldown_realtime")
local _gut_prev_on_all_mods_loaded = mod.on_all_mods_loaded
mod.on_all_mods_loaded = function(...)
    if _gut_prev_on_all_mods_loaded then _gut_prev_on_all_mods_loaded(...) end
    if _gut_temporal_fix and _gut_temporal_fix.apply then pcall(_gut_temporal_fix.apply) end
    if _gut_buffbar_fix and _gut_buffbar_fix.apply then pcall(_gut_buffbar_fix.apply) end
    -- Apply the config override LAST so it wins over whatever the mods restored.
    if _gut_config and _gut_config.apply then pcall(_gut_config.apply) end
end
if _gut_temporal_fix and _gut_temporal_fix.apply then pcall(_gut_temporal_fix.apply) end
if _gut_buffbar_fix and _gut_buffbar_fix.apply then pcall(_gut_buffbar_fix.apply) end

-- Parry Indicator (absorbed): recolours the HUD block shields during the
-- timed-block window for EVERY weapon (the original gated on the Parry trait).
-- Optional via `gut_parry_indicator`. Hooks register at dofile time. See
-- _gut_parry_indicator.lua for the verified mechanic + the dropped gate.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_parry_indicator")

-- Optional: large respawn countdown over a dead teammate's portrait (client-safe
-- estimate anchored to the dead-skull state). See _gut_respawn_timer.lua.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_respawn_timer")

-- Floating Damage Numbers (MIGRATED from general_tweaker 2026-06-29): client-side,
-- networking-free numbers over enemies you damage, via the engine's own
-- DamageNumbersUI + DamageUtils.add_unit_floating_damage_numbers. Registers its OWN
-- hooks on DamageUtils.add_damage_network / add_damage_network_player (PRE-FLIGHT:
-- gut has no other hook on either method — it only reads DamageUtils.is_in_inn), and
-- chains mod.on_setting_changed / mod.on_game_state_changed (dofile'd after both are
-- defined). See _gut_damage_numbers.lua.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_damage_numbers")

-- Main Menu & Startup (MIGRATED from general_tweaker 2026-06-29, #190): two
-- independent toggles (both default OFF) — "Skip start screen" (sets
-- GameSettingsDevelopment.skip_start_screen, next-launch) + "Return to Main Menu
-- quits to desktop" (remaps the return_to_title_screen transitions to quit_game),
-- plus the /quit instant-exit command. Plain engine-data reassignments, NO
-- hooks (no duplicate-hook concern); chains mod.on_setting_changed + mod.on_disabled.
-- See _gut_mainmenu.lua.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_mainmenu")

-- 3rd-Person Camera (MIGRATED from general_tweaker 2026-06-29, #191): follow camera
-- with distance/height/side-offset sliders (Camera Distance min stays -3.0 per #147),
-- the gut_tp_camera_enabled toggle + /tp command. Hooks
-- PlayerUnitFirstPerson.set_first_person_mode + .extensions_ready (PRE-FLIGHT: gut has
-- no other hook on PlayerUnitFirstPerson). Chains mod.update (tp re-apply timer) +
-- mod.on_setting_changed / mod.on_game_state_changed / mod.on_disabled. Dropped gt's
-- godmode/noclip post-spawn-reapply trigger (gut has neither). See _gut_camera.lua.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_camera")

-- Skip Cutscenes (MIGRATED from general_tweaker 2026-06-25, issue #106): hooks
-- CutsceneSystem.flow_cb_cutscene_effect / flow_cb_activate_cutscene_logic /
-- skip_pressed + ShowCursorStack.pop, exposes mod.gut_skip_cutscenes_toggle, and
-- chains mod.update for the deferred auto-skip processor. Behavior is unchanged from
-- gt (CW/deus gating + deferred-skip teardown preserved verbatim); ADDS a printf-based
-- [gut:cutscene] diagnostic (survives mod-logging-off) for the stuck dlc_castle CW
-- cutscene (#106). PRE-FLIGHT: gut has no other CutsceneSystem / ShowCursorStack.pop
-- hook (it only CALLS ShowCursorStack.show/.hide). Dofile'd AFTER _hide_ui.lua so its
-- mod.update chain captures the hide-ui update as prev. See _gut_cutscenes.lua.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_cutscenes")

-- Disable Loading-Screen Monologues (MIGRATED from general_tweaker 2026-06-29, #192):
-- the REMAINDER of gt's old "Cutscenes & Monologues" group after the cutscene-skip
-- half migrated (#106). Flips script_data.disable_level_intro_dialogue; no hooks.
-- Chains mod.on_setting_changed; exposes mod.gut_intro_monologue_toggle + /intromono.
-- See _gut_monologue.lua.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_monologue")

-- In-mission inventory access (migrated from general_tweaker 2026-06-24): Open
-- Inventory In Mission (mod.gut_open_mission_inventory + /inv) + Customize
-- gear-icon cim crash-gate (HeroWindowLoadoutConsole._customize_item) + Show menu
-- tabs in-mission (HeroWindowPanelConsole.on_enter) + the InventorySettings/ESC
-- "Open Inventory" data patch (mod._gut_apply_keep_menus, driven by the
-- on_setting_changed branch + on_game_state_changed dispatcher above). All hooks
-- are singletons (preflight-verified: gut has no other HeroWindowLoadoutConsole /
-- HeroWindowPanelConsole hook). See _gut_mission_inventory.lua.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_mission_inventory")

-- In-mission HERO SELECT (sibling of the inventory feature, 2026-06-24): Open the
-- HeroView TALENTS layout mid-mission (mod.gut_open_mission_hero_select +
-- /hero_select + the gut_open_hero_select_hotkey keybind). Reuses the inventory
-- feature's exact keep-gate bypass (the shared mod._gut_apply_keep_menus
-- InventorySettings patch), the vanilla `hero_view_force` transition (exit_to_game =
-- true -> free exit-to-mission, no custom exit closure), and the deus/CW hard-block.
-- Registers NO hooks (direct transition + pure-data game-mode flip), so there are no
-- new (Class, method) pairs to collide with. SAFETY: scoped to VIEW + live-safe
-- talents/cosmetics only -- a mid-mission career CHANGE is unsafe (force_respawn
-- teleports to level start) and CharacterSelectionView mounts a keep-only preview
-- world, so true career-PICK is left to the keep. See _gut_mission_hero_select.lua.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_mission_hero_select")

-- EXPERIMENTAL/diagnostic (#173 feasibility): /gut_swap_career <n> asks the game to
-- swap the LOCAL player's CURRENT hero to career index n (1-4) mid-mission via the
-- vanilla ProfileRequester:request_profile(..., force_respawn=true). No UI, no
-- CharacterSelectionView (that's the mid-mission crash) -- just the host-mediated
-- profile-request call, mirroring ImguiCareerDebug's mid-mission requester accessor.
-- Heavy [gut:career] printf logging to farm ground truth on whether the swap+respawn
-- works live. Registers NO hooks (command only). See _gut_career_swap.lua.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_career_swap")

-- Dev probe: capture the live vanilla OptionsView so /dump_options can dump
-- its real scroll/mask/scrollbar layout — ground-truth for the Mod Tweaker
-- scrollbar. See _gut_options_probe.lua.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_options_probe")

-- Dev probe (#92 corrected): hook the LIVE VANILLA GAME SETTINGS menu (OptionsView,
-- NOT VMFOptionsView — the prior probe captured the wrong menu) and emit
-- [gut-glow-probe] raw-printf lines (survive logging-off) capturing the exact
-- texture/material/pass/style the real Settings menu uses on hover for a stepper/slider
-- arrow, a collapsed dropdown arrow (incl. the open-state FLIP + glow-while-open), and an
-- EXTENDED (open) dropdown option — ground-truth to confirm/correct the Mod Tweaker glow
-- replication. Fires only on hover/open-state CHANGE (bounded). See _gut_glow_probe.lua.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_glow_probe")

-- Dev probe (#123): capture how VMF actually does keybind REBINDING so we can later
-- make the Mod Tweaker's read-only keybind rows settable. Hooks the three
-- VMFOptionsView rebind methods (callback_setting_keybind / set_new_keybind /
-- callback_change_setting_keybind_state) on the live Esc -> Mod Options menu, and logs
-- the Mod Tweaker's own keybind-row classification (wtype/readonly/value/draw-pass) via
-- the mod.update chain (NOT a 2nd IngameUI.update hook — the glow probe owns that).
-- Raw-printf '[gut-keybind-probe]'; diagnostic only, no settability. See
-- _gut_keybind_probe.lua. Must dofile AFTER _gut_cutscenes/_hide_ui so it chains their
-- mod.update tick.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_keybind_probe")

-- Dev probe (#124): MEASURE the Mod Tweaker exit routing instead of trusting the
-- code-read. Hooks IngameUI.transition_with_fade + IngameUI.handle_transition
-- (hook_safe; DIFFERENT methods from the setup_views/update hooks gut already owns,
-- so no (Class,method) collision) and wraps the LIVE attached ModTweakerView instance's
-- exit/on_enter (the class is neither a _G global nor a dofile singleton, so a VMF hook
-- can't reliably reach it). Raw-printf '[gut-menu-probe]' (survives mod-logging-off),
-- bounded + pcall-guarded. On exit it logs the real fired transition + the view the
-- player lands on, so '#124 exit -> game' is confirmed empirically. See
-- _gut_menu_transition_probe.lua.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_menu_transition_probe")

-- (#173 Probe B7): hook_safe GameModeAdventure.force_respawn + log the resulting spawn
-- position vs the pre-respawn position, to settle whether a career swap teleports the
-- player to level start. Read-only diagnostic. Must dofile AFTER the mod.update definers
-- (_gut_camera / _gut_cutscenes / _hide_ui / _gut_keybind_probe) since it chains mod.update.
-- (Probe B3 -- char-select bundle residency -- lives inside _gut_menu_transition_probe.lua,
-- extending the existing handle_transition hook per the VMF no-duplicate-hook rule.)
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_173_probes")

-- Bestiary & Armory (absorbed): merged weapon (Armory) + enemy (Bestiary)
-- compendium with a PURE-DYNAMIC data layer — weapons enumerated live from
-- ItemMasterList, enemies from Breeds, so new content appears with no hardcoded
-- list. Currently ships the data providers + dump/open commands; the HeroView
-- compendium UI is built in subsequent phases. See _ba_compendium.lua.
-- Phase 0 of the HeroView compendium UI: the state class must dofile FIRST (so the
-- global HeroViewStateCompendium exists before HeroView resolves it), then the
-- injection (HeroView.init screen registration + /armory open), then the data
-- layer + commands.
-- The Mod Tweaker KEEP sub-state class (build 2) must ALSO dofile before the inject
-- module, for the same reason: _ba_heroview_inject registers BOTH the gut_compendium
-- and gut_mod_tweaker screens in its single HeroView.init hook, and HeroView resolves
-- state_name -> global class at transition time. The standalone in-mission
-- ModTweakerView (_mod_tweaker_view) is unchanged and stays the mission path.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_ba_compendium_state")
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_state")
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_ba_heroview_inject")
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_ba_compendium")

-- UI Tweaks (HideBuffs) absorbed features — Phase 1: hide UI elements, hide
-- active buffs, loading-screen hides, Hide-HUD hotkey. `hb_data` defines the data
-- backbone (SETTING_NAMES, alignments, etc.) and MUST load first. Disable the
-- standalone "UI Tweaks" mod once gut covers it, to avoid double-hooking.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/hb/hb_data")
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/hb/hide_elements")
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/hb/level_loading_screen")

mod:info(string.format("gui_tweaker v%s ready (loadout save/restore + HUD edit mode + mod_tweaker api + bestiary/armory)", MOD_VERSION))

mod:info("[mem-probe] gut boot_lua=+%.1f MB (of ~1024 MB lua_heap cap)", (collectgarbage("count") - _MEM_PROBE_T0_GUT) / 1024)
