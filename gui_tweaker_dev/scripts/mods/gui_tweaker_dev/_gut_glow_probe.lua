local mod = get_mod("gut_dev")

-- ============================================================================
-- HOVER-GLOW GROUND-TRUTH probe — NATIVE (vanilla Options) vs GUT (Mod Tweaker)
-- ============================================================================
-- The Mod Tweaker rebuilds the vanilla GAME OPTIONS menu's chrome on a borrowed
-- renderer. Two glow bugs are open against that rebuild:
--   * #92 — stepper/slider arrow hover-glow is too small + mispositioned.
--   * #99 — dropdown arrow flip/glow is broken.
-- This probe is a DIAGNOSTIC INSTRUMENT ONLY (no fix). It captures, in-game, the
-- exact texture_size / offset / color of the arrow + dropdown styles on BOTH:
--   * the LIVE vanilla Options menu (ground truth), tagged  [gut-glow-probe] NATIVE
--   * the gut Mod Tweaker's own rebuilt rows,        tagged  [gut-glow-probe] GUT
-- so the next build can diff size+offset+color side by side and set correct constants.
--
-- WHAT'S NEW vs the prior probe: the prior version logged only `color`, and only on a
-- single hover-state CHANGE (one snapshot). The native hover may ANIMATE the overlay
-- alpha (and possibly size/offset) over several frames — a single snapshot misses that.
-- This version SAMPLES ACROSS THE HOVER TRANSITION: on hover-enter (or a dropdown
-- opening) it logs EVERY FRAME for the next SAMPLE_FRAMES frames via a per-widget frame
-- counter, then stops until the hover/open state changes again (counter resets on
-- hover-exit / close). Each sampled line carries pass_type, style_id, resolved texture,
-- texture_size/size (all components), offset (all 3), and color (all 4).
--
-- WHAT'S NEW in v0.2.96-dev (close the MEASURED-vs-ASSUMED gap on GEOMETRY, #92/#99):
--   1. NATIVE AUTO geometry dump (NO manual hover needed). The moment the vanilla Options
--      menu builds a settings list, the draw_widgets hook one-shot-walks it, finds ONE
--      stepper/slider + ONE dropdown, and dumps EACH arrow style's texture_size/offset/
--      color for BOTH the BASE sprite AND the HOVER/GLOW sprite — tagged
--      `[gut-glow-probe] NATIVE AUTO`. This is the KEY measurement: if the native glow
--      sprite (settings_arrow_clicked / drop_down_menu_arrow_clicked) has a DIFFERENT
--      texture_size than the base (exactly like the slider thumb, where native
--      slider_thumb_hover is 34x25 vs base 14x27), that would explain "glow too small"
--      and we'd see it here instead of assuming 19x27. Fires once per widget-set (resets
--      when Options rebuilds its list, e.g. on open / category switch) — so the native
--      IDLE geometry baseline is captured automatically without hovering the vanilla menu.
--      NOTE: native scenegraph offsets are in NATIVE coords (NOT directly comparable to
--      gut's absolute offsets); texture_size IS directly comparable, and offset is
--      comparable RELATIVE to the row. The on-hover NATIVE capture below is KEPT (it still
--      catches any hover animation over the 20-frame sample).
--   2. GUT dropdown arrow DRAW-STATE. Each gut arrow pass's content_check_function is now
--      EVALUATED (pcall-guarded) and logged as `shown=true/false`, so we MEASURE which
--      arrow pass (arrow_down / arrow_up / arrow_glow) actually draws when the dropdown is
--      closed / open / hovered — instead of inferring the flip gating from reading code.
--
-- GREP: `[gut-glow-probe] NATIVE` for the vanilla menu, `[gut-glow-probe] GUT` for the
-- Mod Tweaker. Lines are frame-tagged `f=<n>` (1..SAMPLE_FRAMES) so any animated ramp
-- in size/offset/alpha is visible in order.
--
-- WHY a raw printf (not mod:info): the user runs with mod logging OFF most of the time;
-- `printf` is the Stingray engine global, written to console + game log regardless of any
-- mod log level.
--
-- WHY hook OptionsView.draw_widgets (NATIVE side, hook_safe / post-return): the hover
-- recolor / arrow flip lives in each widget's per-frame content_check / offset_function,
-- which run during draw_widgets. Reading post-return captures the real post-hover values
-- for THIS frame. self.selected_settings_list.widgets is the active per-setting widget
-- array (options_view.lua:3441 / :3632).
--
-- WHY hook IngameUI.update (GUT side) and NOT ModTweakerView._draw: `mod:dofile` is NOT a
-- singleton (memory reference_vmf_dofile_not_singleton) — each dofile of
-- _mod_tweaker_view re-executes `local ModTweakerView = class(ModTweakerView)`, producing
-- a DISTINCT class table. The live view instance resolves its methods through whichever
-- table _attach_view's dofile produced, so hooking a freshly-dofile'd ModTweakerView._draw
-- would never fire for the live instance. Instead we hook the GLOBAL IngameUI.update
-- (ingame_ui.lua:596-599 dispatches `views[current_view]:update` every frame), reach the
-- live view via self.views[self.current_view] when current_view == "mod_tweaker_view", and
-- read its already-drawn `_rows` styles (the view's own _draw ran synchronously inside the
-- wrapped IngameUI:update, so this frame's is_hover / ramped colors are populated). Pure
-- read-only — no behavior change, all probe work pcall-wrapped.

local _printf = rawget(_G, "printf") or function(fmt, ...) print(string.format(fmt, ...)) end

-- How many frames to sample after a hover-enter / open / state change.
local SAMPLE_FRAMES = 20

local function _col(c)
    if type(c) ~= "table" then return tostring(c) end
    return string.format("{%s,%s,%s,%s}", tostring(c[1]), tostring(c[2]), tostring(c[3]), tostring(c[4]))
end

-- Format a vector style field (texture_size / size / offset) with all its components.
local function _vec(v)
    if type(v) ~= "table" then return tostring(v) end
    local parts = {}
    for i = 1, #v do parts[i] = tostring(v[i]) end
    return "{" .. table.concat(parts, ",") .. "}"
end

-- Find the pass_type of the pass that draws `style_id` in a widget's element. Recurses
-- one level into list_pass children (the native dropdown nests its arrow passes there).
-- Returns "?" if not found.
local function _pass_type_for(element, style_id)
    local passes = element and element.passes
    if type(passes) ~= "table" then return "?" end
    local function scan(ps)
        for i = 1, #ps do
            local p = ps[i]
            if p.style_id == style_id then return p.pass_type end
            if p.pass_type == "list_pass" and type(p.passes) == "table" then
                local r = scan(p.passes)
                if r then return r end
            end
        end
        return nil
    end
    return scan(passes) or "?"
end

-- Return the PASS OBJECT (not just its pass_type) that draws `style_id`, so its
-- content_check_function can be read + evaluated. Same one-level list_pass recursion.
local function _find_pass(element, style_id)
    local passes = element and element.passes
    if type(passes) ~= "table" then return nil end
    local function scan(ps)
        for i = 1, #ps do
            local p = ps[i]
            if p.style_id == style_id then return p end
            if p.pass_type == "list_pass" and type(p.passes) == "table" then
                local r = scan(p.passes)
                if r then return r end
            end
        end
        return nil
    end
    return scan(passes)
end

-- Enhancement 2: MEASURE whether a pass actually draws this frame by EVALUATING its
-- content_check_function (instead of inferring the flip/glow gating from reading code).
-- A VT2 pass with no content_check_function always draws -> "true(no-check)". gut's checks
-- are simple (`not c.active` / `c.active` / `hover or active`) and take (content[, style]),
-- so this is cheap + safe; still pcall-guarded. Returns a string for the log line.
local function _pass_shown(element, style_id, content, style)
    local p = _find_pass(element, style_id)
    if not p then return "?" end
    local fn = p.content_check_function
    if type(fn) ~= "function" then return "true(no-check)" end
    local ok, res = pcall(fn, content, style)
    if not ok then return "err" end
    return res and "true" or "false"
end

-- The one canonical per-style line: pass_type, style_id, resolved texture, size, offset, color.
-- Optional `shown` (string) appends ` shown=<v>` — the evaluated content_check_function draw
-- state (Enhancement 2); nil for callers that don't measure draw state (back-compatible).
local function _log_style(prefix, pass_type, style_id, tex, st, shown)
    local shown_suffix = shown ~= nil and (" shown=" .. tostring(shown)) or ""
    if type(st) ~= "table" then
        _printf("%s pass=%s style_id=%s tex=%s (style absent)%s", prefix, tostring(pass_type), tostring(style_id), tostring(tex), shown_suffix)
        return
    end
    local size = st.texture_size or st.size
    _printf("%s pass=%s style_id=%s tex=%s size=%s offset=%s color=%s%s",
        prefix, tostring(pass_type), tostring(style_id), tostring(tex),
        _vec(size), _vec(st.offset), _col(st.color), shown_suffix)
end

-- Resolve the sprite a content key carries: a string sprite, or a sub-table's texture_id.
local function _resolve_tex(content, key)
    local v = content and content[key]
    if type(v) == "table" then return v.texture_id or v.texture or "table" end
    return v
end

-- ============================================================================
-- NATIVE side — vanilla OptionsView stepper / slider arrows + dropdown arrows
-- ============================================================================

-- Native stepper/slider: base settings_arrow_normal (full alpha) + settings_arrow_clicked
-- overlay alpha-ramped on hover. content.<key> holds the sprite STRING; style.<key> holds
-- texture_size/offset/color. (options_view_definitions.lua create_stepper_widget.)
local NATIVE_ARROW_KEYS = { "left_arrow", "right_arrow", "left_arrow_hover", "right_arrow_hover" }

local function _dump_native_arrows(w, content, style, frame_idx)
    local prefix = string.format("[gut-glow-probe] NATIVE STEPPER/SLIDER '%s' f=%d",
        tostring(content.text), frame_idx)
    for _, sid in ipairs(NATIVE_ARROW_KEYS) do
        local tex = content[sid]
        if type(tex) == "table" then tex = tex.texture_id end
        _log_style(prefix, _pass_type_for(w.element, sid), sid, tex, style[sid])
    end
end

local function _probe_stepper(w, content, style)
    local lh = content.left_hotspot
    local rh = content.right_hotspot
    local hovered = (lh and lh.is_hover) or (rh and rh.is_hover) or false
    local prev = w.__gut_probe_hover
    if hovered ~= prev then
        w.__gut_probe_hover = hovered
        w.__gut_probe_frames = hovered and SAMPLE_FRAMES or 0
        if hovered then
            _printf("[gut-glow-probe] NATIVE STEPPER/SLIDER '%s' HOVER-ENTER (sampling %d frames): left_hover=%s right_hover=%s",
                tostring(content.text), SAMPLE_FRAMES, tostring(lh and lh.is_hover), tostring(rh and rh.is_hover))
        end
    end
    local frames = w.__gut_probe_frames or 0
    if frames > 0 then
        _dump_native_arrows(w, content, style, SAMPLE_FRAMES - frames + 1)
        w.__gut_probe_frames = frames - 1
    end
end

-- Native dropdown: content.arrow / content.arrow_hover sub-tables carry the sprite; the
-- flip + glow is a style swap (style.arrow / style.arrow_hover / style.arrow_hover_flipped).
-- content.active = open. (options_view_definitions.lua create_drop_down_widget.)
local function _dump_native_dropdown(w, content, style, frame_idx)
    local prefix = string.format("[gut-glow-probe] NATIVE DROPDOWN '%s' f=%d",
        tostring(content.text), frame_idx)
    local arrow_tex = content.arrow and content.arrow.texture_id
    local hover_tex = content.arrow_hover and content.arrow_hover.texture_id
    _log_style(prefix, _pass_type_for(w.element, "arrow"), "arrow", arrow_tex, style.arrow)
    _log_style(prefix, _pass_type_for(w.element, "arrow_hover"), "arrow_hover", hover_tex, style.arrow_hover)
    _log_style(prefix, _pass_type_for(w.element, "arrow_hover_flipped"), "arrow_hover_flipped", hover_tex, style.arrow_hover_flipped)
    _log_style(prefix, _pass_type_for(w.element, "selected_option"), "selected_option", "(text)", style.selected_option)
end

local function _probe_dropdown(w, content, style)
    local hotspot = content.hotspot
    local hovered = (hotspot and hotspot.is_hover) or false
    local active  = content.active and true or false
    local prev_h  = w.__gut_probe_hover
    local prev_a  = w.__gut_probe_active

    if hovered ~= prev_h or active ~= prev_a then
        w.__gut_probe_hover = hovered
        w.__gut_probe_active = active
        if hovered or active then
            w.__gut_probe_frames = SAMPLE_FRAMES
            _printf("[gut-glow-probe] NATIVE DROPDOWN '%s' STATE-CHANGE (sampling %d frames): hover=%s active(open)=%s",
                tostring(content.text), SAMPLE_FRAMES, tostring(hovered), tostring(active))
        else
            w.__gut_probe_frames = 0
        end
    end
    local frames = w.__gut_probe_frames or 0
    if frames > 0 then
        _dump_native_dropdown(w, content, style, SAMPLE_FRAMES - frames + 1)
        w.__gut_probe_frames = frames - 1
    end

    -- EXTENDED (open) popup: each option's text stays font_default white; the hover cue is
    -- the playerlist_hover highlight sprite behind the row. Surface the hovered option's
    -- text default/hover color on the hovered-option CHANGE (bounded, one line per option).
    if active then
        local lc = content.list_content
        local ls = style.list_style
        if type(lc) == "table" then
            local hovered_opt
            for k, v in pairs(lc) do
                if type(v) == "table" and v.hotspot and v.hotspot.is_hover then hovered_opt = k; break end
            end
            if hovered_opt ~= w.__gut_probe_popup_opt then
                w.__gut_probe_popup_opt = hovered_opt
                if hovered_opt then
                    local ts = ls and ls.text
                    _printf("[gut-glow-probe] NATIVE EXTENDED-DROPDOWN option HOVER (list_content[%s]): text default_color=%s hover_color=%s",
                        tostring(hovered_opt), _col(ts and ts.default_color), _col(ts and ts.hover_color))
                end
            end
        end
    elseif w.__gut_probe_popup_opt ~= nil then
        w.__gut_probe_popup_opt = nil
    end
end

-- Dispatch one native widget by content shape (matches the vanilla widget layout).
local function _probe_native_widget(w)
    local content = w.content
    local style = w.style
    if type(content) ~= "table" or type(style) ~= "table" then return end
    if content.arrow ~= nil and content.active ~= nil then
        _probe_dropdown(w, content, style)
    elseif content.left_arrow ~= nil or content.right_arrow ~= nil then
        _probe_stepper(w, content, style)
    end
end

-- ----------------------------------------------------------------------------
-- Enhancement 1: NATIVE AUTO geometry dump (no manual hover). Dump EACH arrow style's
-- texture_size/offset/color for BOTH the BASE and the HOVER/GLOW sprite, so a glow sprite
-- that is a DIFFERENT SIZE than the base (the "glow too small" hypothesis) is MEASURED.
-- ----------------------------------------------------------------------------

-- Stepper/slider: base left_arrow / right_arrow + hover-overlay left_arrow_hover /
-- right_arrow_hover (native settings_arrow_clicked). Reuses NATIVE_ARROW_KEYS.
local function _auto_dump_native_stepper(w, content, style)
    local prefix = string.format("[gut-glow-probe] NATIVE AUTO STEPPER/SLIDER '%s'", tostring(content.text))
    for _, sid in ipairs(NATIVE_ARROW_KEYS) do
        local tex = content[sid]
        if type(tex) == "table" then tex = tex.texture_id end
        _log_style(prefix, _pass_type_for(w.element, sid), sid, tex, style[sid])
    end
end

-- Dropdown: base arrow + hover/flipped glow (native drop_down_menu_arrow_clicked). The
-- glow uses the content.arrow_hover sprite for both style.arrow_hover and arrow_hover_flipped.
local function _auto_dump_native_dropdown(w, content, style)
    local prefix = string.format("[gut-glow-probe] NATIVE AUTO DROPDOWN '%s'", tostring(content.text))
    local arrow_tex = content.arrow and content.arrow.texture_id
    local hover_tex = content.arrow_hover and content.arrow_hover.texture_id
    _log_style(prefix, _pass_type_for(w.element, "arrow"), "arrow", arrow_tex, style.arrow)
    _log_style(prefix, _pass_type_for(w.element, "arrow_hover"), "arrow_hover", hover_tex, style.arrow_hover)
    _log_style(prefix, _pass_type_for(w.element, "arrow_hover_flipped"), "arrow_hover_flipped", hover_tex, style.arrow_hover_flipped)
end

-- One-shot walk: find ONE stepper/slider + ONE dropdown and dump both. Fires once per
-- widget-set (caller gates on widget-table identity, which changes when Options rebuilds
-- its list on open / category switch — so this captures the native IDLE baseline with no
-- hover). texture_size is directly comparable to gut; offset only RELATIVE to the row
-- (native scenegraph offsets are in native coords).
local function _auto_dump_native_geometry(widgets, n)
    local found_stepper, found_dropdown = false, false
    for i = 1, (n or #widgets) do
        local w = widgets[i]
        if type(w) == "table" then
            local content, style = w.content, w.style
            if type(content) == "table" and type(style) == "table" then
                if not found_dropdown and content.arrow ~= nil and content.active ~= nil then
                    found_dropdown = true
                    _auto_dump_native_dropdown(w, content, style)
                elseif not found_stepper and (content.left_arrow ~= nil or content.right_arrow ~= nil) then
                    found_stepper = true
                    _auto_dump_native_stepper(w, content, style)
                end
            end
        end
        if found_stepper and found_dropdown then break end
    end
    _printf("[gut-glow-probe] NATIVE AUTO geometry dump complete (stepper found=%s, dropdown found=%s). texture_size directly comparable to GUT; offset comparable RELATIVE to the row only.",
        tostring(found_stepper), tostring(found_dropdown))
end

-- Identity of the last native widget-set we auto-dumped; reset triggers a fresh dump.
local _native_auto_widgets = nil

mod:hook_safe("OptionsView", "draw_widgets", function(self)
    mod._opt_view_ref = self
    local sl = self.selected_settings_list
    local widgets = sl and sl.widgets
    local n = sl and sl.widgets_n
    if type(widgets) ~= "table" then return end
    -- Enhancement 1: one-shot NATIVE AUTO geometry dump per widget-set (no hook on
    -- OptionsView.on_enter — gut already hooks that elsewhere; reset on widget-set identity
    -- change instead, which also fires once per Options open / category switch).
    if widgets ~= _native_auto_widgets then
        _native_auto_widgets = widgets
        local ok, err = pcall(_auto_dump_native_geometry, widgets, n)
        if not ok then
            _printf("[gut-glow-probe] NATIVE AUTO error: %s", tostring(err))
        end
    end
    for i = 1, (n or #widgets) do
        local w = widgets[i]
        if type(w) == "table" then
            local ok, err = pcall(_probe_native_widget, w)
            if not ok then
                _printf("[gut-glow-probe] NATIVE probe error: %s", tostring(err))
            end
        end
    end
end)

-- ============================================================================
-- GUT side — the Mod Tweaker's rebuilt stepper/slider arrows + dropdown arrows
-- ============================================================================

-- gut stepper/slider arrow styles (built by _mod_tweaker_definitions._append_arrows):
-- left_arrow / right_arrow (base) + left_arrow_hover / right_arrow_hover (overlay). The
-- sprite lives in content.<key>.texture_id; the size/offset/color in style.<key>.
local GUT_ARROW_KEYS = { "left_arrow", "right_arrow", "left_arrow_hover", "right_arrow_hover" }

local function _dump_gut_arrows(row, content, style, frame_idx)
    local prefix = string.format("[gut-glow-probe] GUT STEPPER/SLIDER '%s' f=%d",
        tostring(row._setting_id), frame_idx)
    local el = row.element
    for _, sid in ipairs(GUT_ARROW_KEYS) do
        -- shown= is cheap here too (these passes have no content_check -> true(no-check),
        -- they're alpha-driven not gated); included for parity with the dropdown.
        _log_style(prefix, _pass_type_for(el, sid), sid, _resolve_tex(content, sid), style[sid],
            _pass_shown(el, sid, content, style))
    end
end

-- gut dropdown arrow styles (built by _mod_tweaker_definitions.create_dropdown):
-- arrow_down (base, content.arrow_tex string) / arrow_up (content.arrow_up.texture_id) /
-- arrow_glow (content.arrow_glow.texture_id). content.active = open.
local function _dump_gut_dropdown(row, content, style, frame_idx)
    local prefix = string.format("[gut-glow-probe] GUT DROPDOWN '%s' f=%d",
        tostring(row._setting_id), frame_idx)
    local el = row.element
    -- Enhancement 2 (#99): log shown= (evaluated content_check) for each arrow pass so we
    -- MEASURE which of arrow_down (drawn closed) / arrow_up (drawn open) / arrow_glow
    -- (drawn hover|open) actually draws — instead of inferring the flip/glow gating from code.
    _log_style(prefix, _pass_type_for(el, "arrow_down"), "arrow_down", content.arrow_tex, style.arrow_down, _pass_shown(el, "arrow_down", content, style))
    _log_style(prefix, _pass_type_for(el, "arrow_up"), "arrow_up", _resolve_tex(content, "arrow_up"), style.arrow_up, _pass_shown(el, "arrow_up", content, style))
    _log_style(prefix, _pass_type_for(el, "arrow_glow"), "arrow_glow", _resolve_tex(content, "arrow_glow"), style.arrow_glow, _pass_shown(el, "arrow_glow", content, style))
end

local function _probe_gut_row(row)
    local content = row.content
    local style = row.style
    if type(content) ~= "table" or type(style) ~= "table" then return end
    if row._middle_visible == false then return end  -- skip rows culled this frame

    if style.arrow_down ~= nil and content.active ~= nil then
        -- DROPDOWN row: sample on a hover OR open state change.
        local hovered = (content.hotspot and content.hotspot.is_hover) and true or false
        local active  = content.active and true or false
        local cur = (hovered and "h" or "") .. (active and "a" or "")
        if cur ~= row.__gut_probe_state then
            row.__gut_probe_state = cur
            row.__gut_probe_frames = (cur ~= "") and SAMPLE_FRAMES or 0
            if cur ~= "" then
                _printf("[gut-glow-probe] GUT DROPDOWN '%s' STATE-CHANGE (sampling %d frames): hover=%s active(open)=%s",
                    tostring(row._setting_id), SAMPLE_FRAMES, tostring(hovered), tostring(active))
            end
        end
        local frames = row.__gut_probe_frames or 0
        if frames > 0 then
            _dump_gut_dropdown(row, content, style, SAMPLE_FRAMES - frames + 1)
            row.__gut_probe_frames = frames - 1
        end
    elseif style.left_arrow ~= nil then
        -- STEPPER/SLIDER row: sample on a dec/inc arrow hover-enter.
        local hovered = ((content.dec and content.dec.is_hover) or (content.inc and content.inc.is_hover)) and true or false
        if hovered ~= row.__gut_probe_hover then
            row.__gut_probe_hover = hovered
            row.__gut_probe_frames = hovered and SAMPLE_FRAMES or 0
            if hovered then
                _printf("[gut-glow-probe] GUT STEPPER/SLIDER '%s' HOVER-ENTER (sampling %d frames): dec_hover=%s inc_hover=%s",
                    tostring(row._setting_id), SAMPLE_FRAMES,
                    tostring(content.dec and content.dec.is_hover), tostring(content.inc and content.inc.is_hover))
            end
        end
        local frames = row.__gut_probe_frames or 0
        if frames > 0 then
            _dump_gut_arrows(row, content, style, SAMPLE_FRAMES - frames + 1)
            row.__gut_probe_frames = frames - 1
        end
    end
end

-- Global per-frame tick that ALSO fires while the Mod Tweaker view is current (ingame_ui
-- dispatches the current view's :update from inside IngameUI:update). hook_safe post-return
-- so the view's own _draw (called synchronously by ModTweakerView:update) has already
-- populated this frame's is_hover / ramped colors.
mod:hook_safe("IngameUI", "update", function(self, dt, t)
    if self.current_view ~= "mod_tweaker_view" then return end
    local view = self.views and self.views.mod_tweaker_view
    local rows = view and view._rows
    if type(rows) ~= "table" then return end
    for i = 1, #rows do
        local row = rows[i]
        if type(row) == "table" then
            local ok, err = pcall(_probe_gut_row, row)
            if not ok then
                _printf("[gut-glow-probe] GUT probe error: %s", tostring(err))
            end
        end
    end
end)

_printf("[gut-glow-probe] dual size+offset+color probe installed. NATIVE = vanilla Options (Esc -> Options): hover a stepper/slider arrow + a dropdown arrow, then click the dropdown OPEN to watch the flip+glow. GUT = open the Mod Tweaker (Esc -> Mod Tweaker) and hover the same control types + open a dropdown. Each captures pass_type/texture/texture_size/offset/color across the hover (sampled %d frames per state change). Grep '[gut-glow-probe] NATIVE' vs '[gut-glow-probe] GUT' to A/B-diff size+offset+color.", SAMPLE_FRAMES)

return {}
