local mod = get_mod("gut")

-- _mod_tweaker_state_interaction.lua - keep-state Mod Tweaker input and draw surface.
--
-- Owns numeric editing, dropdown interaction, pointer dispatch, hover/tooltips,
-- and the renderer pass for HeroViewStateModTweaker. The parent state installs
-- this surface once through an explicit dependency table; no hooks or lifecycle
-- callbacks are registered here.
--
-- Owned by: _mod_tweaker_state.lua. Consumed via: mod:dofile + install.

local M = {}

function M.install(HeroViewStateModTweaker, deps)
    local defs = assert(deps.defs, "Mod Tweaker state interaction requires defs")
    local UIRenderer = assert(deps.UIRenderer, "Mod Tweaker state interaction requires UIRenderer")
    local UISceneGraph = assert(deps.UISceneGraph, "Mod Tweaker state interaction requires UISceneGraph")
    local UIInverseScaleVectorToResolution = assert(deps.UIInverseScaleVectorToResolution,
        "Mod Tweaker state interaction requires inverse resolution scaling")
    local math = assert(deps.math, "Mod Tweaker state interaction requires math")
    local _cat_set = assert(deps.cat_set, "Mod Tweaker state interaction requires category setter")
    local _play_click = assert(deps.play_click, "Mod Tweaker state interaction requires click sound")
    local _play_hover = assert(deps.play_hover, "Mod Tweaker state interaction requires hover sound")

local _EDIT_MAX_LEN = 16

local function _format_value(value, num_decimals)
    return string.format("%." .. (num_decimals or 0) .. "f", value or 0)
end

function HeroViewStateModTweaker:_begin_edit(row, click_x)
    if self._editing_row and self._editing_row ~= row then
        -- Committing the previously-focused row keeps a single active editor.
        self:_commit_edit(self._editing_row)
    end
    local c = row.content
    self._editing_row = row
    c.editing = true
    c.edit_str = _format_value(c.value, c.num_decimals)
    c.caret_idx = #c.edit_str
    if click_x and defs.numeric_caret_index then
        local renderer = self.ui_top_renderer or self.ui_renderer
        local ok, idx = pcall(defs.numeric_caret_index, renderer,
            row.style and row.style.value, c.edit_str, c._caret_box_w or 64, click_x)
        if ok and type(idx) == "number" then c.caret_idx = idx end
    end
    c.caret_t = 0
    c.value_text = c.edit_str
    _play_click()
end

-- Append/filter ONE batch of keystrokes into c.edit_str (VMF rule set). Returns true if
-- the buffer changed this call (so live feedback only recomputes on change).
function HeroViewStateModTweaker:_edit_apply_keystrokes(c)
    local keystrokes = Keyboard.keystrokes()
    if not keystrokes or #keystrokes == 0 then return false end
    local s = c.edit_str or ""
    local idx = math.clamp(c.caret_idx or #s, 0, #s)
    local nd = c.num_decimals or 0
    local allow_neg = (c.min or 0) < 0
    local changed = false
    for _, stroke in ipairs(keystrokes) do
        if stroke == Keyboard.LEFT then
            if idx > 0 then idx = idx - 1; changed = true end
        elseif stroke == Keyboard.RIGHT then
            if idx < #s then idx = idx + 1; changed = true end
        elseif stroke == Keyboard.HOME then
            if idx ~= 0 then idx = 0; changed = true end
        elseif stroke == Keyboard.END then
            if idx ~= #s then idx = #s; changed = true end
        elseif stroke == Keyboard.BACKSPACE then
            if idx > 0 then s = s:sub(1, idx - 1) .. s:sub(idx + 1); idx = idx - 1; changed = true end
        elseif stroke == Keyboard.DELETE then
            if idx < #s then s = s:sub(1, idx) .. s:sub(idx + 2); changed = true end
        elseif type(stroke) == "string" and #s < _EDIT_MAX_LEN then
            local cand = s:sub(1, idx) .. stroke .. s:sub(idx + 1)
            local ok = false
            if stroke == "-" then
                ok = allow_neg and idx == 0 and not s:find("-", 1, true)
            elseif stroke == "." then
                ok = nd > 0 and not s:find(".", 1, true)
            elseif tonumber(stroke) then
                local dot = cand:find("%.")
                ok = (not dot) or (#cand - dot <= nd)
            end
            if ok then s = cand; idx = idx + 1; changed = true end
        end
    end
    if changed then c.edit_str = s; c.caret_idx = idx end
    return changed
end

-- Live feedback for the active editor: mirror the typed string into value_text and tint
-- it red when the buffer is not a valid in-range number (a trailing bare "." is allowed
-- so the user can keep typing). Caret offset/alpha is driven by the definitions'
-- local_offset pass (it reads c._caret_renderer + c.caret_t, set/advanced here).
function HeroViewStateModTweaker:_edit_live_feedback(row, dt)
    local c = row.content
    c.caret_t = (c.caret_t or 0) + (dt or 0)
    c._caret_renderer = self.ui_top_renderer or self.ui_renderer
    c.value_text = c.edit_str or ""
    local vs = row.style and row.style.value
    if vs and vs.text_color then
        local n = tonumber(c.edit_str)
        local bad = (n == nil) or (n < (c.min or 0)) or (n > (c.max or 1))
        vs.text_color[1] = 255
        vs.text_color[2] = 255
        vs.text_color[3] = bad and 70 or 255
        vs.text_color[4] = bad and 70 or 255
    end
end

-- Snap n to the slider's step grid (same math the drag/arrow paths use), then clamp.
local function _snap_and_clamp(c, n)
    n = math.clamp(n, c.min or 0, c.max or 1)
    local nd = c.num_decimals or 0
    if c.step and c.step > 0 then
        local base = c.min or 0
        n = base + math.floor((n - base) / c.step + 0.5) * c.step
    else
        local m = (nd > 0) and (10 ^ nd) or 1
        n = math.floor(n * m + 0.5) / m
    end
    return math.clamp(n, c.min or 0, c.max or 1)
end

function HeroViewStateModTweaker:_commit_edit(row)
    local c = row.content
    local n = tonumber(c.edit_str)
    if n == nil then
        -- not a number -> treat as cancel (restore the live value).
        self:_cancel_edit(row)
        return
    end
    n = _snap_and_clamp(c, n)
    -- (v0.2.70-dev) STAGE the typed value (was a live _cat_set + re-read). Nothing is
    -- written live until APPLY, so there's no mod-side on_setting_changed snap to re-read
    -- here — the snapped/clamped typed value IS the staged value, and the row reflects it.
    c.value = n
    _play_click()
    self:stage_set(row._category, row._setting_id, n)
    local span = (c.max or 1) - (c.min or 0)
    c.internal_value = (span > 0) and math.clamp((n - (c.min or 0)) / span, 0, 1) or 0
    c.value_text = _format_value(n, c.num_decimals)
    self:_end_edit(row)
end

function HeroViewStateModTweaker:_cancel_edit(row)
    local c = row.content
    -- Restore the displayed value from the (unchanged) committed value.
    c.value_text = _format_value(c.value, c.num_decimals)
    _play_click()
    self:_end_edit(row)
end

-- Shared teardown: clear edit flags + reset the value-text color to white so the next
-- frame's draw doesn't keep a red invalid-tint.
function HeroViewStateModTweaker:_end_edit(row)
    local c = row.content
    c.editing = false
    c.edit_str = ""
    c._caret_renderer = nil
    local vs = row.style and row.style.value
    if vs and vs.text_color then vs.text_color[1] = 255; vs.text_color[2] = 255; vs.text_color[3] = 255; vs.text_color[4] = 255 end
    if self._editing_row == row then self._editing_row = nil end
end

-- ---------------------------------------------------------------
-- REAL DROPDOWN open/select/close (v0.2.69-dev). One dropdown is open at a time
-- (self._open_dropdown = the collapsed row). While open it's MODAL: _handle_input
-- short-circuits to the popup so other rows don't react. The popup widget itself
-- (self._dd_list) is rebuilt by _refresh_dropdown_list whenever the visible window
-- (start_index) changes, and drawn in _draw after the rows so it overlays everything.
-- ---------------------------------------------------------------

-- (Re)build the popup overlay widget for the open dropdown at the current start_index.
function HeroViewStateModTweaker:_refresh_dropdown_list()
    local row = self._open_dropdown
    if not row then self._dd_list = nil; return end
    local texts = row._options_texts or {}
    local cur   = row._option_idx or 1
    local start = self._dd_start or 1
    local ok, w = pcall(defs.create_dropdown_list, texts, cur, row._list_y or 0, start)
    self._dd_list = (ok and w) or nil
end

function HeroViewStateModTweaker:_open_dropdown_popup(row)
    -- Committing any active type-edit first keeps a single modal surface.
    if self._editing_row then self:_commit_edit(self._editing_row) end
    self._open_dropdown = row
    row.content.active = true
    local n = #(row._options_texts or {})
    local num_draws = math.min(n, 10)
    -- Scroll the window so the selected option is visible (native start_index clamp).
    self._dd_start = math.clamp((row._option_idx or 1) - num_draws + 1, 1, math.max(1, n - num_draws + 1))
    if (row._option_idx or 1) <= num_draws then self._dd_start = 1 end
    self:_refresh_dropdown_list()
    _play_click()
end

function HeroViewStateModTweaker:_close_dropdown_popup()
    local row = self._open_dropdown
    if row then row.content.active = false end
    self._open_dropdown = nil
    self._dd_list = nil
end

function HeroViewStateModTweaker:_commit_dropdown(opt_i)
    local row = self._open_dropdown
    if not row then return end
    local vals = row._options_values or {}
    if vals[opt_i] ~= nil then
        row._option_idx = opt_i
        row.content.value_text = (row._options_texts or {})[opt_i] or ""
        -- (v0.2.70-dev) STAGE the selection (was a live _cat_set). Commits on APPLY.
        self:stage_set(row._category, row._setting_id, vals[opt_i])
        _play_click()
        mod:debug("[mt:dump] input: dropdown '%s' -> %s (staged)", tostring(row._setting_id), tostring(vals[opt_i]))
    end
    self:_close_dropdown_popup()
end

-- Position the popup's single highlight sprite under the hovered option (or the
-- currently-selected one if nothing is hovered) and show/hide it. Runs each draw frame.
function HeroViewStateModTweaker:_position_dropdown_highlight()
    local w = self._dd_list
    local row = self._open_dropdown
    if not (w and row) then return end
    local c = w.content
    local num_draws = w._dd_num_draws or 0
    local hovered_k = nil
    for k = 1, num_draws do
        local hs = c["opt_" .. k]
        if hs and hs.is_hover then hovered_k = k; break end
    end
    -- Fall back to the selected option's slot (if it's in the visible window).
    if not hovered_k then
        local sel_k = (row._option_idx or 1) - (w._dd_start or 1) + 1
        if sel_k >= 1 and sel_k <= num_draws then hovered_k = sel_k end
    end
    if hovered_k and w.style and w.style.hl then
        local row_h = w._dd_row_h or 24
        w.style.hl.offset[2] = (w._dd_list_top or 0) - hovered_k * row_h
        c.hl_visible = true
    else
        c.hl_visible = false
    end
end

-- MODAL popup input. Returns true if it consumed the frame (caller returns early).
-- Handles: wheel-scroll of a long option list, per-option click (commit), and
-- click-away (close without committing). The popup widget's hotspots fire
-- on_left_release (shared-node semantics, same as the rows).
function HeroViewStateModTweaker:_handle_dropdown_input(input_service)
    local row = self._open_dropdown
    if not row then return false end
    local w = self._dd_list
    if not w then self:_close_dropdown_popup(); return true end
    local c = w.content
    local n = w._dd_total or 0
    local num_draws = w._dd_num_draws or 0

    -- Wheel scrolls the visible option window (only when the list overflows).
    if n > num_draws then
        local wheel = input_service and input_service:get("scroll_axis")
        if wheel and wheel.y and wheel.y ~= 0 then
            local new_start = math.clamp((self._dd_start or 1) - (wheel.y > 0 and 1 or -1),
                                         1, math.max(1, n - num_draws + 1))
            if new_start ~= self._dd_start then
                self._dd_start = new_start
                self:_refresh_dropdown_list()
            end
            return true
        end
    end

    -- Per-option click -> commit that absolute option index.
    for k = 1, num_draws do
        local hs = c["opt_" .. k]
        if hs and (hs.on_release or hs.on_left_release) then
            self:_commit_dropdown((w._dd_start or 1) + k - 1)
            return true
        end
    end

    -- Click-away (LMB released, not on any option row) closes WITHOUT committing.
    if Mouse.released(0) then
        self:_close_dropdown_popup()
        _play_click()
        return true
    end
    return true   -- modal: swallow all other row input while the popup is open
end

function HeroViewStateModTweaker:_handle_input(input_service)
    -- (v0.2.69-dev) MODAL dropdown popup: while a dropdown is open, the popup owns input
    -- (option click / wheel-scroll / click-away). Short-circuit so no other row reacts.
    if self._open_dropdown then
        if self:_handle_dropdown_input(input_service) then return end
    end

    -- Scroll: mouse wheel (1 notch ~= 1 row) + scrollbar thumb drag. The wheel reads
    -- scroll_axis off the menu input service; the thumb drag tracks the cursor like
    -- the vanilla scrollbar held_function (inverse-scaled cursor vs the track top).
    if (self._max_scroll or 0) > 0 then
        local wheel = input_service and input_service:get("scroll_axis")
        if wheel and wheel.y and wheel.y ~= 0 then
            self._scroll_y = math.clamp((self._scroll_y or 0) - wheel.y * 46, 0, self._max_scroll)
        end
        -- Thumb drag: the hotspot pass sets is_held while the LMB is held over the
        -- scrollbar (its own node, so unlike the shared-node rows this fires fine).
        local hs = self._scrollbar and self._scrollbar.content.hotspot
        if hs and hs.is_held then
            local cursor = input_service and input_service:get("cursor")
            if cursor then
                local sb_pos = UISceneGraph.get_world_position(self.ui_scenegraph, defs.scrollbar_sg)
                local c = UIInverseScaleVectorToResolution(cursor)
                local rel = math.clamp((sb_pos[2] - c[2]) / math.max(1, self._visible_h or 700), 0, 1)
                self._scroll_y = math.clamp(rel * self._max_scroll, 0, self._max_scroll)
            end
        end
    end

    -- Exit (X) button.
    if self._exit and self._exit.content.button_hotspot and self._exit.content.button_hotspot.on_release then
        _play_click()
        self:close_menu()
        return
    end

    -- (v0.2.70-dev) APPLY button: commit the active category's pending buffer. Only when
    -- ENABLED (the active category has staged edits) — a click on the greyed button is a
    -- no-op. This is the ONLY path that runs _cat_set on edit.
    do
        local ah = self._apply and self._apply.content.button_hotspot
        if ah and (ah.on_release or ah.on_left_release) and not self._apply.content.disabled then
            self:apply_pending(self._categories[self._selected])
            return
        end
    end

    -- (Fix 3, v0.2.151-dev) RESTORE DEFAULTS button: show a native confirm popup FIRST.
    -- Only the CONFIRM result runs reset_to_defaults (current tab only); the result is
    -- polled in update() via _check_reset_popup.
    do
        local rh = self._reset and self._reset.content.button_hotspot
        if rh and (rh.on_release or rh.on_left_release) then
            self:_queue_reset_popup()
            return
        end
    end


    for i = 1, #(self._profile_buttons or {}) do
        local ph = self._profile_buttons[i].content.hotspot
        if ph and (ph.on_release or ph.on_left_release) then
            self:_switch_profile(i)
            return
        end
    end

    -- Tab clicks. The "More" tab advances the page; mod tabs switch selection.
    -- GUARDED while drilled: tab/page switching is disabled inside an advanced view so
    -- the player can't half-switch mods mid-drill (use Back / ESC to exit the drill first).
    if not self._drill then
        for i = 1, #self._tabs do
            local bt = self._tabs[i].content.hotspot
            if bt and bt.on_release then
                _play_click()
                mod:debug("[mt:dump] input: tab[%d] clicked (was %d)", i, self._selected or -1)
                if self._more_tab_index and i == self._more_tab_index then
                    self._page = ((self._page or 0) + 1) % math.max(1, self._page_count or 1)
                    self._selected = 1
                    self._scroll_y = 0
                    self:_rebuild()
                    return
                elseif i ~= self._selected and self._categories[i] then
                    self._selected = i
                    self._scroll_y = 0
                    self:_build_rows(self._categories[i])
                    return
                end
            end
        end
    end

    -- Diagnostic for "can't change any option": are row hotspots receiving cursor
    -- input at all? Logs the hovered / clicked row index (and visible count) so the
    -- next log shows whether the cursor reaches the rows or the click never fires.
    do
        local hov, rel, mv = -1, -1, 0
        for i = 1, #self._rows do
            local r = self._rows[i]
            if r._middle_visible then mv = mv + 1 end
            local c = r.content
            if c then
                local h = c.hotspot or c.dec or c.inc
                if h and h.is_hover then hov = i end
                if (c.hotspot and c.hotspot.on_release) or (c.dec and c.dec.on_release)
                   or (c.inc and c.inc.on_release) then rel = i end
            end
        end
        if hov >= 0 or rel >= 0 then
            mod:debug("[mt:dbg] row input: hover=%d release=%d visible=%d/%d", hov, rel, mv, #self._rows)
        end
    end

    -- Rows. Persist on change via _cat_set (routes to the real VMF mod object, or
    -- the gut controller for the dogfood category).
    for i = 1, #self._rows do
        local row = self._rows[i]
        -- Skip rows culled this frame (outside the list_mask) so a click on a
        -- scrolled-away row can't register.
        if not row._readonly and row._middle_visible ~= false then
            local c = row.content
            if row._is_gear then
                -- GEAR click: drill INTO this setting's advanced sub-options. Captures
                -- the parent setting_id + label, resets scroll, and rebuilds the list as
                -- Back + parent + children (see _build_rows' _drill branch).
                if c.hotspot and (c.hotspot.on_release or c.hotspot.on_left_release) then
                    _play_click()
                    self._drill = { setting_id = row._drill_setting, label = row._drill_label }
                    self._scroll_y = 0
                    self:_build_rows(self._categories[self._selected])
                    mod:debug("[mt:dump] input: gear drill into '%s'", tostring(row._drill_setting))
                    return
                end
            elseif row._is_back then
                -- BACK row click: drill OUT to the normal list (same as the first ESC).
                if c.hotspot and (c.hotspot.on_release or c.hotspot.on_left_release) then
                    _play_click()
                    self._drill = nil
                    self._scroll_y = 0
                    self:_build_rows(self._categories[self._selected])
                    return
                end
            elseif row._is_group then
                -- Collapsible group header: toggle expand/collapse, then rebuild.
                if c.hotspot and (c.hotspot.on_release or c.hotspot.on_left_release) then
                    _play_click()
                    self._expanded[row._group_key] = not self._expanded[row._group_key]
                    self:_build_rows(self._categories[self._selected])
                    return
                end
            elseif row._wtype == "checkbox" or row._wtype == "boolean" then
                -- on_left_release (not on_release): rows share the mt_list_start node,
                -- which doesn't persist the hotspot input_pressed state, so on_release
                -- never fires for them; on_left_release fires on release-over-widget.
                -- The ON/OFF switch's two arrow hotspots (dec/inc) are alternate hit
                -- zones over the same row — either toggles the flag.
                local row_click = c.hotspot and (c.hotspot.on_release or c.hotspot.on_left_release)
                local arrow_click = (c.dec and (c.dec.on_release or c.dec.on_left_release))
                                 or (c.inc and (c.inc.on_release or c.inc.on_left_release))
                local clicked = row_click or arrow_click
                -- (v0.2.71-dev) ON/OFF FLICKER FIX — edge-latch the toggle so it fires ONCE
                -- per physical release. The rows share the mt_list_start node, which keeps
                -- on_release/on_left_release latched true for SEVERAL consecutive draw frames;
                -- the old unconditional `c.flag = not c.flag` re-inverted the flag on each of
                -- those frames (on->off->on->off), the visible "negotiating" flicker. The
                -- displayed word follows content.flag directly (defs on_text/off_text passes),
                -- so each extra toggle is visible. row._toggle_armed gates the flip to the
                -- press edge and clears when all three hotspots' release flags drop. Mirrors
                -- the row._was_hovered hover debounce.
                if clicked and not row._toggle_armed then
                    row._toggle_armed = true
                    c.flag = not c.flag
                    _play_click()
                    -- (v0.2.70-dev) STAGE the toggle (was a live _cat_set). Commits on APPLY.
                    self:stage_set(row._category, row._setting_id, c.flag)
                    mod:debug("[mt:dump] input: checkbox '%s' -> %s (staged)", tostring(row._setting_id), tostring(c.flag))
                elseif not clicked then
                    row._toggle_armed = false
                end
            elseif row._wtype == "dropdown" then
                -- (v0.2.69-dev) Click the collapsed row -> OPEN the popup option list. The
                -- modal popup (handled at the top of _handle_input) does select/close.
                local vals = row._options_values
                if vals and #vals > 0 and c.hotspot
                   and (c.hotspot.on_release or c.hotspot.on_left_release) then
                    self:_open_dropdown_popup(row)
                    mod:debug("[mt:dump] input: dropdown '%s' opened", tostring(row._setting_id))
                    return
                end
            elseif row._wtype == "slider" or row._wtype == "numeric" then
                local cur = (type(c.value) == "number") and c.value or (c.min or 0)
                local moved, commit = false, false
                -- TYPE-TO-EDIT focus (v0.2.66-dev): a click on the value box enters edit
                -- mode for this row. Checked even when not currently editing; the value_hs
                -- hotspot is separate from track_hs/dec/inc so it never triggers a drag.
                local vhs = c.value_hs
                local vhs_clicked = vhs and (vhs.on_release or vhs.on_left_release)
                if c.editing then
                    -- ACTIVE EDITOR branch — suppress drag/arrows entirely (spec §6.6).
                    if vhs_clicked and defs.numeric_caret_index then
                        local cursor = input_service and input_service:get("cursor")
                        if cursor then
                            local anchor = UISceneGraph.get_world_position(self.ui_scenegraph, defs.list_sg)
                            local click_x = UIInverseScaleVectorToResolution(cursor)[1] - anchor[1]
                            local ok, idx = pcall(defs.numeric_caret_index,
                                self.ui_top_renderer or self.ui_renderer,
                                row.style and row.style.value, c.edit_str or "",
                                c._caret_box_w or 64, click_x)
                            if ok and type(idx) == "number" then c.caret_idx = idx end
                        end
                    end
                    self:_edit_apply_keystrokes(c)
                    -- CONSUME Enter / stray keys so they COMMIT and never open game chat
                    -- (v0.2.67-dev). Chat reads keyboard Enter on the INDEPENDENT chat_input
                    -- service, which gut's own Keyboard.released(13) commit can't block. The
                    -- engine-sanctioned lever is ChatManager.block_chat_input_for_one_frame()
                    -- (chat_manager.lua:390-397 -> chat_gui.lua:541-543/560), re-asserted EVERY
                    -- frame the edit is active (it auto-clears each frame). This blocks chat
                    -- activation for the whole edit (Enter-commit AND stray y/letters), self-
                    -- clears when editing ends, and is ChatGuiNull-safe via pcall.
                    if Managers.chat and Managers.chat.block_chat_input_for_one_frame then
                        pcall(function() Managers.chat:block_chat_input_for_one_frame() end)
                    end
                    if Keyboard.released(13) then            -- Enter -> commit
                        self:_commit_edit(row)
                        return
                    elseif Keyboard.released(27) then        -- Escape -> cancel
                        self:_cancel_edit(row)
                        return
                    elseif Mouse.released(0) and not vhs_clicked then
                        -- Click outside this value box = focus-loss -> commit (Enter-equiv).
                        self:_commit_edit(row)
                        return
                    end
                    -- Still editing: skip the drag/arrow handling for this row this frame.
                elseif vhs_clicked then
                    local click_x
                    local cursor = input_service and input_service:get("cursor")
                    if cursor then
                        local anchor = UISceneGraph.get_world_position(self.ui_scenegraph, defs.list_sg)
                        click_x = UIInverseScaleVectorToResolution(cursor)[1] - anchor[1]
                    end
                    self:_begin_edit(row, click_x)
                    return
                else
                -- Draggable track. During the HOLD we only move the VISUAL; we COMMIT
                -- (mod:set -> the mod's on_setting_changed) ONLY on release. Some
                -- handlers are heavy — ct's `starting_coins` broadcasts the entire
                -- ~18KB config to clients — so firing it every drag frame floods the
                -- network and crashes. One commit on release matches VMF's behaviour.
                local ths = c.track_hs
                if ths and (ths.is_held or ths.on_left_release) and c.track_w then
                    local cursor = input_service and input_service:get("cursor")
                    if cursor then
                        local anchor = UISceneGraph.get_world_position(self.ui_scenegraph, defs.list_sg)
                        local cx = UIInverseScaleVectorToResolution(cursor)[1]
                        local frac = math.clamp((cx - (anchor[1] + (c.track_x or 0))) / math.max(1, c.track_w), 0, 1)
                        cur = (c.min or 0) + frac * ((c.max or 1) - (c.min or 0))
                        local nd = c.num_decimals or 0
                        local m = (nd > 0) and (10 ^ nd) or 1
                        cur = math.floor(cur * m + 0.5) / m
                        moved = true
                        if ths.on_left_release then commit = true end  -- drag ended
                    end
                end
                if c.dec and (c.dec.on_release or c.dec.on_left_release) then cur = math.clamp(cur - (c.step or 1), c.min, c.max); moved = true; commit = true end
                if c.inc and (c.inc.on_release or c.inc.on_left_release) then cur = math.clamp(cur + (c.step or 1), c.min, c.max); moved = true; commit = true end
                -- Visual tracks the value every frame (smooth drag); persistence waits.
                if moved and cur ~= c.value then
                    c.value = cur
                    local span = (c.max or 1) - (c.min or 0)
                    c.internal_value = (span > 0) and math.clamp((cur - c.min) / span, 0, 1) or 0
                    c.value_text = string.format("%." .. (c.num_decimals or 0) .. "f", cur)
                    mod:debug("[mt:slider] DRAG '%s' val=%s internal=%.3f thumb_x~=%.0f (track_x=%s track_w=%s)",
                        tostring(row._setting_id), tostring(cur), c.internal_value,
                        (c.track_x or 0) + (c.track_w or 0) * c.internal_value,
                        tostring(c.track_x), tostring(c.track_w))
                end
                if commit then
                    _play_click()
                    -- (v0.2.70-dev) STAGE the slider value (was a live _cat_set + re-read).
                    -- Nothing is written live until APPLY, so there's no mod-side
                    -- on_setting_changed snap to re-read here — the dragged/stepped value
                    -- (already grid-snapped above) IS the staged value, and the bar shows it.
                    self:stage_set(row._category, row._setting_id, c.value)
                    mod:debug("[mt:dump] input: slider '%s' -> %s (staged)", tostring(row._setting_id), tostring(c.value))
                end
                end  -- close the `else` (not-editing) drag/arrow branch
            end
        end
    end
end

-- Per-frame hover polish for one visible row: (1) whole-row highlight
-- ("playerlist_hover") gated on content.is_highlighted, set from the row hotspot's
-- is_hover; (2) Play_hud_hover sound on the hover-enter EDGE only. The factories
-- created the passes/content; the view just flips the per-frame flags.
--
-- (v0.2.82-dev — ITEM 4) The inc/dec arrow texture-swap (settings_arrow_normal ->
-- settings_arrow_clicked on hover) was REMOVED — see the standalone-view twin's
-- _apply_row_hover for the full rationale. Vanilla never hard-swaps a stepper/slider
-- arrow to its bright "clicked" sprite on mere hover; gut's swap read as a pressed-
-- down button. Hover feedback now comes solely from the whole-row playerlist_hover
-- highlight (kept below). The arrows stay on settings_arrow_normal at all times.
function HeroViewStateModTweaker:_apply_row_hover(row)
    local c = row.content
    if not c then return end
    -- (1) row highlight from whichever hotspot the row exposes.
    local row_hot = c.hotspot or c.track_hs
    local hovered = (row_hot and row_hot.is_hover) and true or false
    if (c.dec and c.dec.is_hover) or (c.inc and c.inc.is_hover) then hovered = true end
    -- (Fix 4, v0.2.149-dev) An EXPANDED collapsible group stays lit (row highlight bar +
    -- arrow glow) even when not hovered, so the open section reads as active. Thread the LIVE
    -- expanded state (self._expanded[row._group_key] — the same source the row toggle uses)
    -- into content.expanded so create_group_header's glow driver sees it each frame.
    if row._is_group then
        local exp = self._expanded[row._group_key] and true or false
        c.expanded = exp
        if exp then hovered = true end
    end
    if c.is_highlighted ~= nil then c.is_highlighted = hovered end
    -- (2) hover-enter edge sound (debounced on the row's own _was_hovered flag).
    if hovered and not row._was_hovered then _play_hover() end
    row._was_hovered = hovered
end

-- (#207) HOVER INFO POPUP fade + draw. Replicates the native option-tooltip fade EXACTLY
-- (ui_settings.lua:22-23 -> tooltip_wait_duration = 0.1, tooltip_fade_in_speed = 4): on a
-- tooltip'd row becoming hovered, wait 0.1s (alpha 0), then ramp progress by dt*4 and set
-- alpha = math.easeOutCubic(progress); on no-hover OR a different row, reset progress = 0 +
-- wait = 0.1 -> alpha 0 -> instant disappear. `hover_row` is the hovered tooltip row this
-- frame (or nil); `hover_world_y` its bottom-edge world Y (for layout's on-screen flip).
-- TWIN of ModTweakerView:_update_tooltip — keep both in sync.
local TT_WAIT, TT_SPEED = 0.1, 4
function HeroViewStateModTweaker:_update_tooltip(dt, hover_row, hover_world_y, renderer)
    -- Modal suppression: no tooltip while a dropdown popup is open, a slider is being
    -- dragged, or a numeric field is being edited (matches _apply_row_hover's suppression).
    if self._open_dropdown or self._slider_dragging or self._editing_row then hover_row = nil end

    if hover_row and hover_row == self._tt_row then
        if (self._tt_wait or 0) > 0 then
            self._tt_wait = self._tt_wait - dt
            self._tt_alpha = 0
        else
            self._tt_progress = math.min((self._tt_progress or 0) + dt * TT_SPEED, 1)
            self._tt_alpha = math.easeOutCubic(self._tt_progress)
        end
    else
        -- De-hover OR moved to a different row: reset (instant disappear) + adopt the new row.
        self._tt_progress = 0
        self._tt_wait = TT_WAIT
        self._tt_alpha = 0
        self._tt_row = hover_row
    end

    local row = self._tt_row
    if not (row and (self._tt_alpha or 0) > 0 and self._tooltip) then return end
    local ok = pcall(defs.layout_tooltip, self._tooltip, renderer,
        row._tip_title or (row.content and row.content.label) or "", row._tip_desc or "",
        row._list_y or 0, hover_world_y or 0, self._tt_alpha)
    if ok then UIRenderer.draw_widget(renderer, self._tooltip) end
end

-- ---------------------------------------------------------------
-- Draw (single begin_pass/end_pass on the borrowed top renderer)
-- ---------------------------------------------------------------

function HeroViewStateModTweaker:_draw(dt, input_service)
    -- Draw on ui_top_renderer (top_ingame_view world) — the SAME renderer OptionsView
    -- and the hero menu use. Our rows use only atlas-safe materials (matchmaking_
    -- checkbox / slider_thumb / rect / border), which resolve on this renderer.
    local renderer = self.ui_top_renderer or self.ui_renderer
    local scenegraph = self.ui_scenegraph
    if not (renderer and scenegraph and self._chrome) then return end

    -- (Fix 2) Tab text color matches the VANILLA options tabs (UIWidgets.create_text_button,
    -- ui_widgets.lua:9200-9229): NORMAL = font_button_normal {255,160,146,101}; SELECTED OR
    -- HOVERED = white {255,255,255,255} (native text_hover fires on is_hover OR is_selected).
    for i = 1, #self._tabs do
        local tab = self._tabs[i]
        local st = tab.style and tab.style.text
        -- (v0.2.71-dev) hover-enter sound on TABS (was unwired — _play_hover only fired
        -- for rows via _apply_row_hover). Edge-debounced on the tab's own _was_hovered.
        local hov = tab.content.hotspot and tab.content.hotspot.is_hover
        if hov and not tab._was_hovered then _play_hover() end
        tab._was_hovered = hov
        if st and st.text_color then
            local active = (i == self._selected) or hov
            if active then
                -- selected OR hovered -> white (vanilla text_hover).
                st.text_color[1], st.text_color[2], st.text_color[3], st.text_color[4] = 255, 255, 255, 255
            else
                -- idle -> font_button_normal (vanilla text).
                st.text_color[1], st.text_color[2], st.text_color[3], st.text_color[4] = 255, 160, 146, 101
            end
        end
    end

    -- (v0.2.70-dev) APPLY button per-frame styling. Recompute the disabled flag from the
    -- active category's buffer (cheap; keeps it correct even if a rebuild changed the
    -- active category). Gold text ("cheeseburger") + brighter border when enabled; dim
    -- grey + faint border when disabled. Hover brightens the bg fill when enabled.
    self:_update_apply_button()
    if self._apply then
        local ac = self._apply.content
        local asty = self._apply.style
        local enabled = not ac.disabled
        local hovered = ac.button_hotspot and ac.button_hotspot.is_hover
        -- (v0.2.71-dev) hover-enter sound on the APPLY button (was unwired). Edge-debounced
        -- on self._apply._was_hovered. Gated on `enabled` so the greyed (no-pending-edits)
        -- button stays silent — only an actionable hover plays.
        if enabled and hovered and not self._apply._was_hovered then _play_hover() end
        self._apply._was_hovered = hovered
        if asty.text and asty.text.text_color then
            local t = asty.text.text_color
            -- (v0.2.157-dev) EXACT vanilla colours FARMED from the live game's ready Apply
            -- button ([opt-apply] probe, OptionsView.update_apply_button): ready = cheeseburger
            -- {255,255,168,0}, hover = white {255,255,255,255}, disabled = gray a50
            -- {50,128,128,128}. (Format is {A,R,G,B}.) The prior font_button_normal/font_default
            -- values were a wrong guess -- vanilla's Apply is cheeseburger when ready, NOT the tab
            -- colour; and disabled is gray a50, NOT font_default a75.
            if not enabled then
                t[1], t[2], t[3], t[4] = 50, 128, 128, 128            -- gray a50 (vanilla disabled)
            elseif hovered then
                t[1], t[2], t[3], t[4] = 255, 255, 255, 255           -- white on hover
            else
                t[1], t[2], t[3], t[4] = 255, 255, 168, 0             -- cheeseburger (vanilla ready)
            end
        end
        if asty.bg and asty.bg.color then
            asty.bg.color[1] = (enabled and hovered) and 235 or 200
            local v = (enabled and hovered) and 28 or 10
            asty.bg.color[2], asty.bg.color[3], asty.bg.color[4] = v, v, v
        end
        if asty.border and asty.border.color then
            local b = enabled and 130 or 50
            asty.border.color[1] = 255
            asty.border.color[2], asty.border.color[3], asty.border.color[4] = b, b, b
        end
    end

    -- (v0.2.148-dev) RESTORE DEFAULTS button per-frame styling. Always enabled; brighten the
    -- text to white on hover (else font_default grey), and play the hover-enter sound edge-
    -- debounced on self._reset._was_hovered — mirroring the APPLY button feedback.
    if self._reset then
        local rc = self._reset.content
        local rsty = self._reset.style
        local r_hov = rc.button_hotspot and rc.button_hotspot.is_hover
        if r_hov and not self._reset._was_hovered then _play_hover() end
        self._reset._was_hovered = r_hov
        if rsty.text and rsty.text.text_color then
            local t = rsty.text.text_color
            -- (Fix 3, v0.2.149-dev) Match the TAB / Apply create_text_button scheme:
            -- idle = font_button_normal {255,160,146,101} (was font_default {255,181,181,181}),
            -- white {255,255,255,255} on hover. Always enabled.
            if r_hov then
                t[1], t[2], t[3], t[4] = 255, 255, 255, 255         -- white on hover
            else
                t[1], t[2], t[3], t[4] = 255, 160, 146, 101         -- font_button_normal (idle)
            end
        end
    end

    -- (v0.2.71-dev) hover-enter sound on the EXIT (X) button (was unwired). Edge-debounced
    -- on self._exit._was_hovered. Mirrors the tab/APPLY hover edges added this version.
    if self._exit then
        local xh = self._exit.content.button_hotspot
        local x_hov = xh and xh.is_hover
        if x_hov and not self._exit._was_hovered then _play_hover() end
        self._exit._was_hovered = x_hov
    end


    for i = 1, #(self._profile_buttons or {}) do
        local button = self._profile_buttons[i]
        local hov = button.content.hotspot and button.content.hotspot.is_hover
        if hov and not button._was_hovered then _play_hover() end
        button._was_hovered = hov
        local c = button.style.text.text_color
        if hov then c[1], c[2], c[3], c[4] = 255, 255, 255, 255
        elseif i == (self._profile_slot or 1) then c[1], c[2], c[3], c[4] = 255, 255, 168, 0
        else c[1], c[2], c[3], c[4] = 255, 160, 146, 101 end
    end

    -- Apply scroll: translate the list container node; all rows move with it.
    -- Positive Y shifts the stack up (reveals lower rows) — same sign convention as
    -- OptionsView.update_scrollbar. Set BEFORE begin_pass so world positions (used
    -- for culling below) reflect the scroll this frame.
    local list_node = scenegraph[defs.list_node]
    if list_node then
        list_node.offset = list_node.offset or { 0, 0, 0 }
        list_node.offset[2] = self._scroll_y or 0
    end

    UIRenderer.begin_pass(renderer, scenegraph, input_service, dt, nil, self.render_settings)

    -- Protect end_pass: if any draw_widget below errors, end_pass MUST still run, or
    -- the borrowed renderer is left mid-pass and HeroView's own chrome (which draws on
    -- the SAME renderer on its next pass) renders without its background — that's the
    -- "menu looks deprecated (just buttons)" symptom. CRITICAL on a borrowed renderer.
    local _draw_ok, _draw_err = pcall(function()

    for i = 1, #(self._chrome or {}) do
        UIRenderer.draw_widget(renderer, self._chrome[i])
    end
    -- (Fix 5, v0.2.149-dev) bottom hint widget removed — nothing to draw here.
    for i = 1, #self._tabs do
        UIRenderer.draw_widget(renderer, self._tabs[i])
    end
    -- v0.2.65-dev: no title to draw — removed to match native Options (tabs span the
    -- full top band).
    if self._exit then UIRenderer.draw_widget(renderer, self._exit) end
    -- (v0.2.70-dev) APPLY button (bottom-right of the bottom panel). Drawn with the chrome
    -- so it's never culled by the list_mask (it lives outside the scrolling list).
    if self._apply then UIRenderer.draw_widget(renderer, self._apply) end
    -- (v0.2.148-dev) RESTORE DEFAULTS button (to the LEFT of Apply). Same render path.
    if self._reset then UIRenderer.draw_widget(renderer, self._reset) end
    if self._profiles_label then UIRenderer.draw_widget(renderer, self._profiles_label) end
    for i = 1, #(self._profile_buttons or {}) do
        UIRenderer.draw_widget(renderer, self._profile_buttons[i])
    end

    -- Cull + draw rows against the list_mask box (CPU position-cull; no GPU mask).
    -- World positions are valid here because begin_pass re-evaluated the scenegraph
    -- with the scroll offset set above.
    local mask_pos  = UISceneGraph.get_world_position(scenegraph, defs.list_mask_sg)
    local mask_size = UISceneGraph.get_size(scenegraph, defs.list_mask_sg)
    local anchor    = UISceneGraph.get_world_position(scenegraph, defs.list_sg)  -- mt_list_start (scrolled)
    -- (#207) The hovered row that carries a tooltip becomes the active popup target.
    local tt_hover_row, tt_hover_world_y
    for i = 1, #self._rows do
        local row = self._rows[i]
        local ry = row._list_y or 0
        local px, py = anchor[1], anchor[2] + ry
        -- Draw a row only when its CENTRE is inside the mask. Since we don't GPU-clip,
        -- a "lower-or-top" test would overdraw half-rows past the panel edges; centre-
        -- only keeps rows fully (or nearly) inside, so the list fits the window.
        local middle = math.point_is_inside_2d_box({ px, py + 23 }, mask_pos, mask_size)  -- ROW_H/2
        row._middle_visible = middle
        if middle then
            self:_apply_row_hover(row)
            -- (#207) Capture the hovered tooltip'd row (+ its bottom-edge world Y for the
            -- on-screen flip test). Either the full-row hover hotspot (row_hs, added by
            -- _append_highlight) or the row's own hotspot counts as "hovered".
            if row._tip_desc and row._tip_desc ~= "" then
                local rc = row.content
                if (rc.row_hs and rc.row_hs.is_hover) or (rc.hotspot and rc.hotspot.is_hover) then
                    tt_hover_row, tt_hover_world_y = row, py
                end
            end
            -- TYPE-TO-EDIT live feedback (v0.2.66-dev): advance the caret pulse + mirror
            -- the typed buffer into the value text + red-tint on invalid, for the active
            -- editor row only. Runs in draw so it ticks every frame regardless of input.
            if row.content and row.content.editing then self:_edit_live_feedback(row, dt) end
            UIRenderer.draw_widget(renderer, row)
        else
            -- Culled: clear stale click flags so a scrolled-away row can't fire.
            local c = row.content
            if c then
                if c.hotspot then c.hotspot.on_release = nil; c.hotspot.on_left_release = nil end
                if c.dec then c.dec.on_release = nil; c.dec.on_left_release = nil end
                if c.inc then c.inc.on_release = nil; c.inc.on_left_release = nil end
            end
        end
    end

    -- Scrollbar — only when the content overflows the window.
    if self._scrollbar and (self._max_scroll or 0) > 0 then
        local c = self._scrollbar.content
        c.scroll_value = (self._max_scroll > 0) and (self._scroll_y / self._max_scroll) or 0
        c.thumb_frac = (self._content_h > 0) and ((self._visible_h or 700) / self._content_h) or 1
        UIRenderer.draw_widget(renderer, self._scrollbar)
    end

    -- (v0.2.69-dev) OPEN DROPDOWN POPUP — drawn LAST (over the rows + scrollbar), and
    -- OUTSIDE the cull loop so it's never clipped by the list_mask. It anchors to the
    -- mt_dropdown node (same scroll as the rows) at the collapsed row's Y, so it tracks
    -- the row if the list scrolls under it. Position the hover/selected highlight before
    -- drawing: highlight the option row under the cursor, else the currently-selected one.
    if self._dd_list then
        self:_position_dropdown_highlight()
        UIRenderer.draw_widget(renderer, self._dd_list)
    end

    -- (#207) HOVER INFO POPUP — fade + draw last (over the rows; suppressed while a
    -- dropdown popup is open). Mutually exclusive with the dropdown popup in practice.
    self:_update_tooltip(dt, tt_hover_row, tt_hover_world_y, renderer)

    end)  -- close pcall(function()
    UIRenderer.end_pass(renderer)  -- ALWAYS runs, even if a draw above errored
    if not _draw_ok then
        mod:warning("[mt] draw error (end_pass protected so the menu chrome survives): %s", tostring(_draw_err))
    end
end

    return HeroViewStateModTweaker
end

return M
