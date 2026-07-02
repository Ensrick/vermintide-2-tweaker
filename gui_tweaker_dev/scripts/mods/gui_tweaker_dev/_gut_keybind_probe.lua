local mod = get_mod("gut_dev")

-- ============================================================================
-- KEYBIND REBIND-FLOW probe (#123) — DIAGNOSTIC ONLY, no settability yet
-- ============================================================================
-- The Mod Tweaker renders a VMF `keybind` widget as a READ-ONLY title-like text row
-- ("[UNTESTED] CLEAR ENEMY SPAWNS: UNBOUND" looks like a heading, can't be rebound).
-- Before we can make it settable we need to SEE how VMF itself does keybind rebinding.
-- This probe captures that flow live; it does NOT implement settability and does NOT
-- touch the existing keybind VALUE rendering (`_format_keybind_value`, #95).
--
-- Two capture surfaces, both raw-printf, both bounded + pcall-guarded:
--
--   [gut-keybind-probe] VMF  — the LIVE vanilla mod-options menu (Esc -> Mod Options,
--     the VMFOptionsView, NOT the Mod Tweaker). Hooks the three VMF methods that drive
--     a keybind rebind so when the user clicks a keybind row and presses a key we log
--     the whole idle -> waiting-for-key -> captured -> stored sequence.
--
--   [gut-keybind-probe] GUT  — the Mod Tweaker's OWN keybind row. Logs its `_wtype`
--     classification, `_readonly` flag, the rendered label text (which already embeds
--     `_format_keybind_value`), the resolved raw setting value + its type/format, and
--     the style/pass it is drawn with — confirming exactly why it renders like a title
--     and is read-only.
--
-- ---- VMF method names + value format (sourced, NOT invented) ----------------
-- Found by disassembling the installed VMF's `vmf_options_view.lua` +
-- `core/keybindings.lua` (LuaJIT bytecode string tables; the source path is embedded
-- as `@scripts/mods/vmf/modules/ui/options/vmf_options_view.lua`). The class is
-- `VMFOptionsView`; the rebind-relevant methods/fields are:
--   * callback_setting_keybind            -- click handler: ENTERS capture mode
--                                            (sets is_setting_keybind, changing_setting,
--                                             blocks input via block_device_except_service)
--   * callback_change_setting_keybind_state -- toggles the capture state (also the
--                                            esc-to-cancel path)
--   * set_new_keybind                     -- RECEIVES the pressed combo (reads
--                                            first_pressed_button_id/type/index +
--                                            pressed_buttons) and WRITES it back
--   * fields on self: is_setting_keybind (bool), changing_setting (the widget/setting
--     being rebound), first_pressed_button_id/type/index, pressed_buttons,
--     keybind_widget_content
-- Keybind VALUE format (from core/keybindings.lua): a keybind's `raw_keybind_data`
-- carries `keys` (an ARRAY of key-name strings, e.g. {"left alt"} / {"ctrl","f"}),
-- `primary_key` (the main key) and `modifier_keys` (held modifiers). gut's
-- `_format_keybind_value` (#95) assumes the value is that flat `keys` array; this probe
-- dumps the REAL live structure so the next build can confirm the exact shape.
--
-- ---- WHY printf (not mod:info) ----------------------------------------------
-- The user runs with mod logging OFF most of the time; mod:info is then invisible (it
-- already cost us the cutscene diagnostic #106). `printf` is the Stingray engine global,
-- written to console + game log regardless of mod log level.
--
-- ---- WHY no second IngameUI.update hook -------------------------------------
-- `_gut_glow_probe.lua` already owns `mod:hook_safe("IngameUI","update",...)`, and VMF
-- silently drops a second hook on the same (Class,method) from the same mod. So the GUT
-- side does NOT re-hook IngameUI.update; it CHAINS `mod.update` (the established gut
-- idiom — capture-prev/call-prev-first, same as _hide_ui.lua / _gut_cutscenes.lua) and
-- reaches the live Mod Tweaker view through `Managers.ui._ingame_ui` (the canonical live
-- IngameUI accessor gut uses everywhere else, see _hide_ui.lua). The VMF-side hooks
-- target VMFOptionsView, which nothing else in gut hooks — collision-free.

local _printf = rawget(_G, "printf") or function(fmt, ...) print(string.format(fmt, ...)) end

-- ---------------------------------------------------------------------------
-- formatting helpers (all defensive; never throw)
-- ---------------------------------------------------------------------------
local function _fmt_array(t)
    local parts = {}
    for i = 1, #t do parts[i] = tostring(t[i]) end
    return "[" .. table.concat(parts, ", ") .. "]"
end

-- One-level value dump: scalars as type:value; tables show their array part AND named
-- keys (so a keybind's {keys=..., primary_key=..., modifier_keys=...} structure is
-- visible, as is a flat {"left alt"} array).
local function _dump_value(v)
    local tt = type(v)
    if tt ~= "table" then return tt .. ":" .. tostring(v) end
    local out = {}
    if #v > 0 then out[#out + 1] = "array=" .. _fmt_array(v) end
    for k, vv in pairs(v) do
        if type(k) ~= "number" then
            local sv
            if type(vv) == "table" then
                sv = (#vv > 0) and _fmt_array(vv) or "{table}"
            else
                sv = tostring(vv)
            end
            out[#out + 1] = tostring(k) .. "=" .. sv
        end
    end
    return "table{" .. table.concat(out, ", ") .. "}"
end

-- Best-effort setting id of the widget/setting currently being rebound.
local function _changing_setting_id(self)
    local cs = self and self.changing_setting
    if type(cs) ~= "table" then return tostring(cs) end
    return tostring(cs.setting_id
        or (cs.content and cs.content.setting_id)
        or (self.keybind_widget_content and self.keybind_widget_content.setting_id)
        or "?")
end

-- One-line snapshot of the view's keybind-capture state.
local function _vmf_state(self)
    return string.format(
        "is_setting_keybind=%s changing_setting_id=%s first_pressed{id=%s type=%s index=%s} pressed_buttons=%s",
        tostring(self.is_setting_keybind),
        _changing_setting_id(self),
        tostring(self.first_pressed_button_id),
        tostring(self.first_pressed_button_type),
        tostring(self.first_pressed_button_index),
        (type(self.pressed_buttons) == "table") and _fmt_array(self.pressed_buttons) or tostring(self.pressed_buttons))
end

-- ============================================================================
-- VMF side — hook the three VMFOptionsView rebind methods (each pcall-guarded so a
-- VMF-version method-name drift can't break probe load).
-- ============================================================================
local function _safe_hook(method, fn)
    local ok, err = pcall(function()
        mod:hook_safe("VMFOptionsView", method, fn)
    end)
    if ok then
        _printf("[gut-keybind-probe] VMF installed hook on VMFOptionsView.%s", method)
    else
        _printf("[gut-keybind-probe] VMF hook on VMFOptionsView.%s FAILED to register: %s", method, tostring(err))
    end
end

-- (1) STARTS the rebind: click on a keybind row -> enter capture (waiting-for-key).
_safe_hook("callback_setting_keybind", function(self, ...)
    local ok, err = pcall(function()
        _printf("[gut-keybind-probe] VMF START callback_setting_keybind -> %s", _vmf_state(self))
        if type(self.changing_setting) == "table" then
            _printf("[gut-keybind-probe] VMF START changing_setting(value-shape) = %s", _dump_value(self.changing_setting))
        end
    end)
    if not ok then _printf("[gut-keybind-probe] VMF START err: %s", tostring(err)) end
end)

-- (2) PER-WIDGET capture state change (enter waiting / esc-cancel).
_safe_hook("callback_change_setting_keybind_state", function(self, ...)
    local ok, err = pcall(function()
        _printf("[gut-keybind-probe] VMF STATE callback_change_setting_keybind_state -> %s", _vmf_state(self))
    end)
    if not ok then _printf("[gut-keybind-probe] VMF STATE err: %s", tostring(err)) end
end)

-- (3) STORE hook REMOVED (gut v0.2.97-dev). `VMFOptionsView.set_new_keybind` does NOT
-- exist on the installed VMF — the v0.2.94 bytecode read mis-named it, and VMF logged
-- "[gut_dev][ERROR] (hook_safe): trying to hook function or method that doesn't exist:
-- [VMFOptionsView.set_new_keybind]" on every load (the `_safe_hook` pcall can't suppress
-- it: VMF LOGS the missing-method error without THROWING, so nothing is caught). The
-- START + STATE hooks above already capture the pressed combo (first_pressed_button_*
-- + pressed_buttons via `_vmf_state`), so the rebind flow stays observable. When #123
-- settability is implemented, find VMF's real keybind-store method from VMF source first.

-- ============================================================================
-- GUT side — the Mod Tweaker's own keybind row classification + draw style.
-- ============================================================================
-- Logs one block per keybind-type row, once per distinct `_rows` table (so it fires on
-- Mod Tweaker open AND each tab / category switch, which rebuild `_rows`).
local function _log_gut_keybind_row(row, idx)
    local content = row.content or {}
    _printf("[gut-keybind-probe] GUT keybind-row[%d] setting_id=%s mod_id=%s wtype=%s readonly=%s",
        idx, tostring(row._setting_id), tostring(row._mod_id), tostring(row._wtype), tostring(row._readonly))
    _printf("[gut-keybind-probe] GUT keybind-row[%d] rendered_text=%q (label+value, value via _format_keybind_value #95)",
        idx, tostring(content.text))

    -- Resolve the raw setting value to reveal its true type/format.
    local cat = row._category
    local raw, got = nil, false
    if cat and row._setting_id then
        if cat.mod_obj and cat.mod_obj.get then
            local ok, v = pcall(cat.mod_obj.get, cat.mod_obj, row._setting_id)
            if ok then raw, got = v, true end
        end
    end
    if got then
        _printf("[gut-keybind-probe] GUT keybind-row[%d] resolved_value=%s", idx, _dump_value(raw))
    else
        _printf("[gut-keybind-probe] GUT keybind-row[%d] resolved_value=<could not resolve via category.mod_obj:get>", idx)
    end

    -- Style/pass the label is drawn with (it uses defs.create_section_title -> a plain
    -- read-only text pass, which is exactly why it looks like a heading not a widget).
    local passes = row.element and row.element.passes
    if type(passes) == "table" then
        local descr = {}
        for p = 1, #passes do
            descr[#descr + 1] = string.format("%s(style_id=%s)", tostring(passes[p].pass_type), tostring(passes[p].style_id))
        end
        _printf("[gut-keybind-probe] GUT keybind-row[%d] passes=[%s] -> drawn as read-only section_title text (no editable control = why it reads like a title)",
            idx, table.concat(descr, ", "))
    end
end

local function _scan_gut_keybind_rows(rows)
    local kb = 0
    for i = 1, #rows do
        local row = rows[i]
        if type(row) == "table" and row._wtype == "keybind" then
            kb = kb + 1
            _log_gut_keybind_row(row, i)
        end
    end
    _printf("[gut-keybind-probe] GUT scanned mod_tweaker rows=%d keybind_rows=%d on current tab/category. If 0, switch to a mod tab that has a keybind setting.",
        #rows, kb)
end

-- Chain mod.update (capture-prev / call-prev-first) — never clobber another feature's
-- tick. This module dofile's AFTER _hide_ui / _gut_cutscenes, so `mod.update` here is
-- already their chain.
local _gut_keybind_prev_update = mod.update
mod.update = function(dt)
    if _gut_keybind_prev_update then _gut_keybind_prev_update(dt) end
    local ok, err = pcall(function()
        local ingame_ui = Managers and Managers.ui and Managers.ui._ingame_ui
        if not ingame_ui or ingame_ui.current_view ~= "mod_tweaker_view" then return end
        local view = ingame_ui.views and ingame_ui.views.mod_tweaker_view
        local rows = view and view._rows
        if type(rows) ~= "table" or #rows == 0 then return end
        if rows == mod._gut_kb_last_rows then return end  -- already scanned this row set
        mod._gut_kb_last_rows = rows
        _scan_gut_keybind_rows(rows)
    end)
    if not ok then _printf("[gut-keybind-probe] GUT update err: %s", tostring(err)) end
end

_printf("[gut-keybind-probe] installed (#123 diagnostic). VMF side: open Esc -> Mod Options, click a keybind row, press a key to rebind -> grep '[gut-keybind-probe] VMF'. GUT side: open the Mod Tweaker on a mod tab that has a keybind -> grep '[gut-keybind-probe] GUT'. Diagnostic only; no settability implemented.")

return {}
