local mod = get_mod("gut_dev")

-- _mod_tweaker_view_interaction.lua - standalone Mod Tweaker input and draw surface.
--
-- Owns numeric/search editing, dialogue-row transport, dropdown interaction,
-- pointer dispatch, hover/tooltips, and the renderer pass for ModTweakerView.
-- The parent view installs this surface once through the explicit dependency
-- table below; no hooks or lifecycle callbacks are registered here.
--
-- Owned by: _mod_tweaker_view.lua. Consumed via: mod:dofile + install.

local M = {}

function M.install(ModTweakerView, deps)
    local defs = assert(deps.defs, "Mod Tweaker interaction requires defs")
    local DialogueUI = assert(deps.DialogueUI, "Mod Tweaker interaction requires DialogueUI")
    local UIRenderer = assert(deps.UIRenderer, "Mod Tweaker interaction requires UIRenderer")
    local UISceneGraph = assert(deps.UISceneGraph, "Mod Tweaker interaction requires UISceneGraph")
    local UIInverseScaleVectorToResolution = assert(deps.UIInverseScaleVectorToResolution,
        "Mod Tweaker interaction requires inverse resolution scaling")
    local math = assert(deps.math, "Mod Tweaker interaction requires math")
    local DD_FILTER_MIN = assert(deps.DD_FILTER_MIN, "Mod Tweaker interaction requires DD_FILTER_MIN")
    local _mt = assert(deps.mt, "Mod Tweaker interaction requires mt")
    local _resolve_step = assert(deps.resolve_step, "Mod Tweaker interaction requires resolve_step")
    local _format_keybind_value = assert(deps.format_keybind_value, "Mod Tweaker interaction requires keybind formatter")
    local _poll_keybind_combo = assert(deps.poll_keybind_combo, "Mod Tweaker interaction requires keybind poller")
    local _cat_set = assert(deps.cat_set, "Mod Tweaker interaction requires category setter")
    local _cat_get = assert(deps.cat_get, "Mod Tweaker interaction requires category getter")
    local _play_click = assert(deps.play_click, "Mod Tweaker interaction requires click sound")
    local _play_hover = assert(deps.play_hover, "Mod Tweaker interaction requires hover sound")
    local _printf = assert(deps.printf, "Mod Tweaker interaction requires printf")

local _EDIT_MAX_LEN = 16
-- (#497) Max search query length (free text; the numeric editor's cap is _EDIT_MAX_LEN).
local _SEARCH_MAX_LEN = 40

-- (#572) Use the exact visible label of the active tab, including category overrides
-- such as CRAFTING/CWV/PROGRESSION. This keeps the empty-field prompt contextual without
-- introducing a second localization/name map that can drift from the tab chrome.
local function _search_placeholder(self)
    local tab = self and self._tabs and self._tabs[self._selected]
    local label = tab and tab.content and tab.content.text
    if label == nil or label == "" then
        local category = self and self._categories and self._categories[self._selected]
        label = category and (category.label or category.mod_id)
    end
    if label == nil or label == "" then label = "this tab" end
    return "Search " .. tostring(label)
end

-- (#497 / #505) Shared raw-keystroke reader. Applies this frame's Keyboard.keystrokes() to a
-- query string: Backspace erases the last char, printable ASCII (32-126) appends up to max_len.
-- Returns (new_str, changed). Reused by the per-tab search box (#497) and the open-dropdown
-- type-to-filter (#505) — the SAME raw path the numeric type-to-edit uses; Enter (13) / ESC (27)
-- are sub-32 so they are ignored here and handled by their own callers.
local function _apply_keystrokes(str, max_len)
    local keystrokes = Keyboard.keystrokes()
    if not keystrokes or #keystrokes == 0 then return str, false end
    local s = str or ""
    local changed = false
    for _, stroke in ipairs(keystrokes) do
        if stroke == Keyboard.BACKSPACE then
            if #s > 0 then s = s:sub(1, #s - 1); changed = true end
        elseif type(stroke) == "string" and #stroke == 1 and #s < (max_len or _SEARCH_MAX_LEN) then
            local b = string.byte(stroke)
            if b and b >= 32 and b <= 126 then s = s .. stroke; changed = true end
        end
    end
    return s, changed
end

local function _format_value(value, num_decimals)
    return string.format("%." .. (num_decimals or 0) .. "f", value or 0)
end

function ModTweakerView:_begin_edit(row, click_x)
    if self._editing_row and self._editing_row ~= row then
        -- Committing the previously-focused row keeps a single active editor.
        self:_commit_edit(self._editing_row)
    end
    local c = row.content
    self._editing_row = row
    c.editing = true
    c.edit_str = _format_value(c.value, c.num_decimals)
    c.caret_idx = #c.edit_str
    -- #575: choose the nearest measured insertion boundary when the editor was
    -- entered by clicking the value; keyboard-only focus still starts at End.
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
function ModTweakerView:_edit_apply_keystrokes(c)
    local keystrokes = Keyboard.keystrokes()
    if not keystrokes or #keystrokes == 0 then return false end
    local s   = c.edit_str or ""
    local idx = math.clamp(c.caret_idx or #s, 0, #s)   -- (#188) chars BEFORE the caret
    local nd  = c.num_decimals or 0
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
            -- Insert AT the caret; accept only if the result stays a valid partial number
            -- (optional single leading '-', digits, <=1 '.', <= nd digits after the dot).
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

-- (#497) Append/erase ONE batch of keystrokes into the search query. Mirrors the numeric
-- editor's Keyboard.keystrokes() capture but for FREE TEXT: printable ASCII (32..126) appends
-- at the end, Backspace erases the last char, capped at _SEARCH_MAX_LEN. The caret is always at
-- the end (no mid-string editing -- keeps the appended blink caret jitter-free), so no LEFT/
-- RIGHT/DELETE handling. Returns true if the query changed, so the caller re-filters only then.
function ModTweakerView:_search_apply_keystrokes()
    local s, changed = _apply_keystrokes(self._search_str or "", _SEARCH_MAX_LEN)
    if changed then
        self._search_str = s
        self._search_caret_t = 0
        self._search_last_ancestors = nil
        self._search_top_ancestors = nil
    end
    return changed
end

-- Live feedback for the active editor: mirror the typed string into value_text and tint
-- it red when the buffer is not a valid in-range number (a trailing bare "." is allowed
-- so the user can keep typing). Caret offset/alpha is driven by the definitions'
-- local_offset pass (it reads c._caret_renderer + c.caret_t, set/advanced here).
function ModTweakerView:_edit_live_feedback(row, dt)
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

function ModTweakerView:_commit_edit(row)
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

function ModTweakerView:_cancel_edit(row)
    local c = row.content
    -- Restore the displayed value from the (unchanged) committed value.
    c.value_text = _format_value(c.value, c.num_decimals)
    _play_click()
    self:_end_edit(row)
end

-- Shared teardown: clear edit flags + reset the value-text color to white so the next
-- frame's draw doesn't keep a red invalid-tint.
function ModTweakerView:_end_edit(row)
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

-- (#505) Recompute self._dd_visible = the array of ABSOLUTE option indices passing the current
-- filter (type-to-filter query AND active category chip). When neither is active this is the full
-- identity list, so the popup renders exactly like the unfiltered dropdown. Called on open and on
-- every query/chip change. Also re-clamps _dd_start into the (possibly shorter) filtered window.
function ModTweakerView:_recompute_dd_visible(row)
    local vals  = row._options_values or {}
    local texts = row._options_texts or {}
    local n = #texts
    local q = self._dd_query
    if type(q) == "string" then
        q = q:gsub("^%s+", ""):gsub("%s+$", "")
        q = (q == "") and nil or q:lower()
    else
        q = nil
    end
    local cat = (self._dd_cats and self._dd_cat) and self._dd_cats[self._dd_cat] or nil
    local vis = {}
    for i = 1, n do
        local keep = true
        if q then
            local t = texts[i]
            keep = type(t) == "string" and string.find(t:lower(), q, 1, true) ~= nil
        end
        if keep and cat and type(cat.match) == "function" then
            local ok, r = pcall(cat.match, vals[i], texts[i])
            keep = ok and r and true or false
        end
        if keep then vis[#vis + 1] = i end
    end
    self._dd_visible = vis
    local num_draws = math.min(#vis, 10)
    self._dd_start = math.clamp(self._dd_start or 1, 1, math.max(1, #vis - num_draws + 1))
    -- The option set changed, so drop the sticky hover index (#158b); it re-seeds to the selected
    -- (or first) option on the next _position_dropdown_highlight and can't point past the new list.
    self._dd_hl_k = nil
end

-- (#505) The chip descriptors for the open dropdown's header, or nil when it has no registered
-- categories (a length-only filterable dropdown shows just the search line, no chips). Chip 1 is
-- always the implicit "All" (clears the category), chips 2..n are the registered categories.
function ModTweakerView:_dd_chips()
    local cats = self._dd_cats
    if not (cats and #cats > 0) then return nil end
    local chips = { { label = "All", active = (self._dd_cat == nil) } }
    for i = 1, #cats do
        chips[#chips + 1] = { label = cats[i].label or ("Category " .. i), active = (self._dd_cat == i) }
    end
    return chips
end

-- (Re)build the popup overlay widget for the open dropdown at the current start_index. When the
-- dropdown is filterable (#505) the visible options are the filtered subset and a header band
-- (search line + chips) is attached; otherwise it is the full list with no header (unchanged path).
function ModTweakerView:_refresh_dropdown_list()
    local row = self._open_dropdown
    if not row then self._dd_list = nil; return end
    local start = self._dd_start or 1
    if not row._dd_filterable then
        -- Plain dropdown: full list, selected index in absolute space, no header.
        local ok, w = pcall(defs.create_dropdown_list, row._options_texts or {}, row._option_idx or 1,
                            row._list_y or 0, start)
        self._dd_list = (ok and w) or nil
        return
    end
    -- Filtered dropdown: map the visible subset to display texts + the selected option's FILTERED
    -- index (or -1 when the selection is filtered out, so nothing renders gold).
    local vis = self._dd_visible or {}
    local all_texts = row._options_texts or {}
    local texts, cur = {}, -1
    for fi = 1, #vis do
        texts[fi] = all_texts[vis[fi]] or ""
        if vis[fi] == row._option_idx then cur = fi end
    end
    self._dd_no_match = (#texts == 0)
    if self._dd_no_match then texts = { "(no matches)" }; cur = -1 end
    local header = { query = self._dd_query or "", chips = self:_dd_chips() }
    local ok, w = pcall(defs.create_dropdown_list, texts, cur, row._list_y or 0, start, header)
    self._dd_list = (ok and w) or nil
end

function ModTweakerView:_open_dropdown_popup(row)
    -- Committing any active type-edit first keeps a single modal surface.
    if self._editing_row then self:_commit_edit(self._editing_row) end
    self._open_dropdown = row
    self._dd_hl_k = nil   -- (#158b) reset the sticky highlight index for this open
    row.content.active = true
    -- (#505) Fresh per-open filter state. Look up any registered category chips for this
    -- (mod_id, setting_id); a dropdown is filterable when it is long OR has categories.
    self._dd_query = ""
    self._dd_cat = nil
    self._dd_cats = nil
    self._dd_no_match = false
    self._dd_caret_t = 0
    local mt = _mt()
    if mt and mt.get_dropdown_categories then
        local ok, cats = pcall(mt.get_dropdown_categories, mt, row._mod_id, row._setting_id)
        if ok and type(cats) == "table" and #cats > 0 then self._dd_cats = cats end
    end
    local n = #(row._options_texts or {})
    row._dd_filterable = (n >= DD_FILTER_MIN) or (self._dd_cats ~= nil)
    self._dd_start = 1
    if row._dd_filterable then
        self:_recompute_dd_visible(row)
        -- Scroll the FILTERED window so the selected option is visible (native start_index clamp).
        local vis, sel_fi = self._dd_visible, nil
        for fi = 1, #vis do if vis[fi] == row._option_idx then sel_fi = fi; break end end
        local num_draws = math.min(#vis, 10)
        if sel_fi then
            self._dd_start = math.clamp(sel_fi - num_draws + 1, 1, math.max(1, #vis - num_draws + 1))
            if sel_fi <= num_draws then self._dd_start = 1 end
        end
    else
        local num_draws = math.min(n, 10)
        self._dd_start = math.clamp((row._option_idx or 1) - num_draws + 1, 1, math.max(1, n - num_draws + 1))
        if (row._option_idx or 1) <= num_draws then self._dd_start = 1 end
    end
    self:_refresh_dropdown_list()
    _play_click()
end

function ModTweakerView:_close_dropdown_popup()
    local row = self._open_dropdown
    if row then row.content.active = false end
    self._open_dropdown = nil
    self._dd_list = nil
    -- (#505) Drop the per-open filter state so a later plain dropdown can't read a stale query/cat.
    self._dd_query = nil
    self._dd_cat = nil
    self._dd_cats = nil
    self._dd_visible = nil
    self._dd_no_match = false
    -- (#158) The closing click's on_release stays LATCHED on the shared mt_list_start node; block
    -- ALL row input until the next fresh left-press (read by _handle_input) so it can't bleed
    -- through to the row behind the just-closed popup, nor re-open the dropdown.
    self._dd_block_until_press = true
end

function ModTweakerView:_commit_dropdown(opt_i)
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
function ModTweakerView:_position_dropdown_highlight()
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
    -- (#158b) STICKY highlight. The bug: every frame the cursor's hover briefly dropped (crossing
    -- between rows, an is_hover flicker, or leaving the popup) the old code SNAPPED the highlight to
    -- the selected option — which for a top/None-selected dropdown is row 1 — i.e. the "flicker to
    -- the top". Fix: when an option IS hovered, remember it (_dd_hl_k); when nothing is hovered,
    -- KEEP the last index instead of snapping. Seed at the selected option only on the first frame
    -- after open (_dd_hl_k reset to nil in _open_dropdown_popup). The highlight only ever moves to a
    -- row the cursor actually hovered.
    if hovered_k then
        self._dd_hl_k = hovered_k
    elseif self._dd_hl_k == nil then
        -- (#505) Seed from the FILTERED-space selected index the popup was built with (w._dd_cur);
        -- for a plain dropdown that equals row._option_idx in absolute space (unchanged). -1 = the
        -- selection is filtered out, so no seed and the highlight stays hidden until a hover.
        local oi = w._dd_cur
        if oi and oi >= 1 then
            local sel_k = oi - (w._dd_start or 1) + 1
            if sel_k >= 1 and sel_k <= num_draws then self._dd_hl_k = sel_k end
        end
    end
    local k = self._dd_hl_k
    if k and k >= 1 and k <= num_draws and w.style and w.style.hl then
        w.style.hl.offset[2] = (w._dd_list_top or 0) - k * (w._dd_row_h or 24)
        c.hl_visible = true
    else
        c.hl_visible = false
    end
end

-- MODAL popup input. Returns true if it consumed the frame (caller returns early).
-- Handles: wheel-scroll of a long option list, per-option click (commit), and
-- click-away (close without committing). The popup widget's hotspots fire
-- on_left_release (shared-node semantics, same as the rows).
function ModTweakerView:_handle_dropdown_input(input_service)
    local row = self._open_dropdown
    if not row then return false end
    local w = self._dd_list
    if not w then self:_close_dropdown_popup(); return true end
    local c = w.content
    local n = w._dd_total or 0
    local num_draws = w._dd_num_draws or 0

    -- (#505) FILTER HEADER input (only for a filterable dropdown): category-chip clicks +
    -- type-to-filter keystrokes. Handled before wheel/option/click-away so a filtering keystroke
    -- or chip click is never also read as an option interaction. Chat input is blocked each frame
    -- so keys/Enter don't leak to game chat (the modal device block doesn't cover chat_input).
    if row._dd_filterable then
        if Managers.chat and Managers.chat.block_chat_input_for_one_frame then
            pcall(function() Managers.chat:block_chat_input_for_one_frame() end)
        end
        local chip_count = w._dd_chip_count or 0
        for ci = 1, chip_count do
            local hs = c["chip_" .. ci]
            if hs and (hs.on_release or hs.on_left_release) then
                -- Chip 1 = "All" (clear the category); chips 2..n = category (ci - 1).
                self._dd_cat = (ci == 1) and nil or (ci - 1)
                self._dd_start = 1
                self:_recompute_dd_visible(row)
                self:_refresh_dropdown_list()
                _play_click()
                return true
            end
        end
        local newq, changed = _apply_keystrokes(self._dd_query or "", _SEARCH_MAX_LEN)
        if changed then
            self._dd_query = newq
            self._dd_caret_t = 0
            self._dd_start = 1
            self:_recompute_dd_visible(row)
            self:_refresh_dropdown_list()
            return true
        end
    end

    -- Wheel scrolls the visible option window (only when the list overflows). n is the FILTERED
    -- option count (w._dd_total), so this clamps against what is actually shown.
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

    -- Per-option click -> commit. For a filtered dropdown, the visible row k maps through
    -- self._dd_visible back to the ABSOLUTE option index; for a plain dropdown _dd_visible is nil
    -- and the click is the absolute index directly (unchanged). A "(no matches)" placeholder row
    -- maps to nil and is ignored.
    for k = 1, num_draws do
        local hs = c["opt_" .. k]
        if hs and (hs.on_release or hs.on_left_release) then
            local fi = (w._dd_start or 1) + k - 1
            local abs
            if row._dd_filterable then
                abs = self._dd_visible and self._dd_visible[fi]   -- nil for the "(no matches)" row
            else
                abs = fi
            end
            if abs then self:_commit_dropdown(abs) else self:_close_dropdown_popup() end
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

function ModTweakerView:_handle_input(input_service)
    -- (v0.2.69-dev) MODAL dropdown popup: while a dropdown is open, the popup owns input
    -- (option click / wheel-scroll / click-away). Short-circuit so no other row reacts.
    if self._open_dropdown then
        if self:_handle_dropdown_input(input_service) then return end
    end

    -- (#158) After a dropdown popup closes, the closing click's on_release stays LATCHED on the
    -- shared mt_list_start node for an UNBOUNDED number of frames (the old 6-frame swallow was too
    -- short -> the row BEHIND got clicked, and clicking an open dropdown re-opened it). Block ALL
    -- row input until the next FRESH left-press begins a new click cycle; the stale latch always
    -- clears long before the user clicks again. Mouse.pressed(0) = a genuinely new press.
    if Mouse.pressed(0) then self._dd_block_until_press = false end
    if self._dd_block_until_press then return end

    -- (#497/#559) SEARCH BOX focus + typing. A left-press ON the box focuses it (committing any
    -- active numeric edit first). A press on a result leaves the transaction alive until that
    -- result acts; a neutral blank-area press clears search and restores the snapshot. While
    -- focused, printable keystrokes edit the query and the list re-filters live;
    -- chat input is blocked each frame so keys/Enter never leak to game chat (the numeric editor
    -- needs the same lever, ChatManager.block_chat_input_for_one_frame -- the modal device block
    -- does not cover the independent chat_input service), and Enter drops focus keeping the
    -- filter. Placed before the scroll/button/row handling so a filtering keystroke is never
    -- also read as a row interaction.
    do
        local sc = self._search and self._search.content
        local shs = sc and sc.hotspot
        if Mouse.pressed(0) then
            if shs and shs.is_hover then
                if not self._search_focused then
                    if self._editing_row then self:_commit_edit(self._editing_row) end
                    self._capturing_keybind = nil
                    self._kb_mouse_pending = nil   -- (issue 631) drop any deferred mouse hold when focusing search
                    self._search_focused = true
                    self._search_caret_t = 0
                    _play_click()
                end
            else
                self._search_focused = false
                if self._search_tx and not self:_search_pointer_over_result()
                   and not self:_search_pointer_over_chrome() then
                    self:_search_finish()
                    self._scroll_y = 0
                    self._dd_block_until_press = true
                    self:_build_rows(self._categories[self._selected])
                    return
                end
            end
        end
        if self._search_focused then
            if Managers.chat and Managers.chat.block_chat_input_for_one_frame then
                pcall(function() Managers.chat:block_chat_input_for_one_frame() end)
            end
            if Keyboard.released(13) then   -- Enter: keep the filter, drop focus
                self._search_focused = false
                _play_click()
                return
            end
            if self:_search_apply_keystrokes() then
                self._scroll_y = 0
                self:_build_rows(self._categories[self._selected])
                return
            end
        end
    end

    -- Scroll: mouse wheel (1 notch ~= 1 row) + scrollbar thumb drag. The wheel reads
    -- scroll_axis off the menu input service; the thumb drag tracks the cursor like
    -- the vanilla scrollbar held_function (inverse-scaled cursor vs the track top).
    if (self._max_scroll or 0) > 0 then
        local wheel = input_service and input_service:get("scroll_axis")
        if wheel and wheel.y and wheel.y ~= 0 then
            self._scroll_y = math.clamp((self._scroll_y or 0) - wheel.y * 46, 0, self._max_scroll)
        end
        -- Thumb drag (#91): the hotspot pass sets is_held while the LMB is held over
        -- the scrollbar (its own node, so unlike the shared-node rows this fires fine).
        --
        -- OLD bug: mapped the cursor's ABSOLUTE position on the track straight to
        -- scroll_value (`rel = (track_top - cursor)/visible_h`), with NO grab-offset and
        -- ignoring the thumb's own height. So grabbing the thumb anywhere snapped its TOP
        -- to the cursor — clicking the lower part of the thumb jumped it up to the top.
        --
        -- FIX: record a grab-offset on the first held frame (the scroll_value at grab +
        -- the cursor Y at grab), then track the cursor DELTA over the thumb's real travel
        -- (track_h * (1 - thumb_frac), the only distance the thumb top can move). +Y is up,
        -- so cursor moving DOWN (decreasing Y) increases scroll. This keeps the point you
        -- grabbed under the cursor and respects the thumb size.
        local hs = self._scrollbar and self._scrollbar.content.hotspot
        if hs and hs.is_held then
            local cursor = input_service and input_service:get("cursor")
            if cursor then
                local c = UIInverseScaleVectorToResolution(cursor)
                local track_h = math.max(1, self._visible_h or 700)
                local thumb_frac = (self._content_h and self._content_h > 0)
                    and math.clamp(track_h / self._content_h, 0.06, 1) or 1
                local travel = track_h * (1 - thumb_frac)   -- px the thumb top can move
                if not self._sb_dragging then
                    -- First held frame: anchor the grab so the thumb doesn't jump.
                    self._sb_dragging = true
                    self._sb_grab_cursor_y = c[2]
                    self._sb_grab_scroll_value = (self._max_scroll > 0)
                        and (self._scroll_y / self._max_scroll) or 0
                end
                if travel > 0 then
                    -- cursor DOWN (c[2] < grab) => positive delta => more scroll.
                    local dv = (self._sb_grab_cursor_y - c[2]) / travel
                    local sv = math.clamp((self._sb_grab_scroll_value or 0) + dv, 0, 1)
                    self._scroll_y = sv * self._max_scroll
                end
            end
        else
            -- Hold released: clear the grab anchor so the next press re-anchors.
            self._sb_dragging = false
        end
    end
    -- Recycle the bounded dialogue row pool when scrolling crosses a row.
    if DialogueUI.refresh_window(self) then return end

    -- Exit (X) button.
    if self._exit and self._exit.content.button_hotspot and self._exit.content.button_hotspot.on_release then
        _play_click()
        -- (#124) The X closes the whole menu -> return to the GAME (exit(true) ->
        -- "exit_menu"), same as the final ESC close. Origin capture stays exit()'s fallback.
        self:exit(true)
        return
    end

    -- (v0.2.70-dev) APPLY button: commit the active category's pending buffer. Only when
    -- ENABLED (the active category has staged edits) — a click on the greyed button is a
    -- no-op. This is the ONLY path that runs _cat_set on edit.
    do
        local ah = self._apply and self._apply.content.button_hotspot
        if ah and (ah.on_release or ah.on_left_release) and not self._apply.content.disabled then
            self:_search_finish()
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
            local search_cleared = self:_search_finish()
            if search_cleared then
                self._scroll_y = 0
                self:_build_rows(self._categories[self._selected])
            end
            self:_queue_reset_popup()
            return
        end
    end


    -- (#561) Profile switches auto-apply pending edits to the old slot, then
    -- restore the selected slot as one bounded per-owner transaction.
    for i = 1, #(self._profile_buttons or {}) do
        local ph = self._profile_buttons[i].content.hotspot
        if ph and (ph.on_release or ph.on_left_release) then
            self:_search_finish()
            self:_switch_profile(i)
            return
        end
    end

    -- Tab clicks. The "More" tab advances the page; mod tabs switch selection. (#151)
    -- Clicking a tab while drilled into an advanced/gear view EXITS the drill and switches —
    -- the old code disabled tabs mid-drill (it read as "the tabs are broken"). Clear _drill on
    -- any tab/page click so the new selection always opens on its normal list.
    for i = 1, #self._tabs do
        local bt = self._tabs[i].content.hotspot
        if bt and bt.on_release then
            _play_click()
            mod:debug("[mt:dump] input: tab[%d] clicked (was %d, drill=%s)", i, self._selected or -1, tostring(self._drill ~= nil))
            if self._more_tab_index and i == self._more_tab_index then
                if DialogueUI.is_category(self._categories[self._selected]) then DialogueUI.stop() end
                self:_search_finish()
                self._drill = nil
                self._search_str = ""; self._search_focused = false   -- (#497) fresh tab, fresh search
                self._page = ((self._page or 0) + 1) % math.max(1, self._page_count or 1)
                self._selected = 1
                self._scroll_y = 0
                self:_rebuild()
                return
            elseif (i ~= self._selected or self._drill) and self._categories[i] then
                if DialogueUI.is_category(self._categories[self._selected]) then DialogueUI.stop() end
                self:_search_finish()
                self._drill = nil
                self._search_str = ""; self._search_focused = false   -- (#497) fresh tab, fresh search
                self._selected = i
                self._scroll_y = 0
                self:_build_rows(self._categories[i])
                return
            end
        end
    end

    -- #605 deterministic controller focus: vertical navigation selects one
    -- logical virtual row; horizontal navigation selects State/Play/Pause.
    if DialogueUI.handle_controller(self, input_service) then
        _play_click()
        return
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

    -- (#slider-modal) Detect a slider being DRAGGED before processing rows, so the drag is MODAL:
    -- while held, no OTHER row reacts to clicks/releases (releasing over a checkbox was toggling
    -- it) and only the dragged row highlights. track_hs.is_held is set by the engine each frame.
    self._slider_dragging = nil
    for i = 1, #self._rows do
        local r = self._rows[i]
        local cc = r.content
        -- is_held = mid-drag. r._dragging stays true THROUGH the release frame (the slider branch
        -- below clears it), so the modal also covers the RELEASE frame — that release was landing
        -- on a checkbox behind the cursor and toggling it.
        if (cc and cc.track_hs and cc.track_hs.is_held) or r._dragging then self._slider_dragging = r; break end
    end

    -- Rows. Persist on change via _cat_set (routes to the real VMF mod object, or
    -- the gut controller for the dogfood category).
    for i = 1, #self._rows do
        local row = self._rows[i]
        -- Skip rows culled this frame (outside the list_mask) so a click on a scrolled-away row
        -- can't register. While a slider is dragging, ALSO skip every OTHER row (modal drag) so
        -- the cursor can't toggle/click anything else mid-drag.
        if not row._readonly and row._middle_visible ~= false
           and not (self._slider_dragging and row ~= self._slider_dragging) then
            local c = row.content
            if row._is_dialogue_group or row._is_dialogue_line then
                if DialogueUI.handle_row(self, row) then
                    _play_click()
                    return
                end
            elseif row._is_gear then
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
                    self._search_rebuild_pending = nil
                    return
                end
            elseif row._is_group then
                -- Collapsible group header: toggle expand/collapse, then rebuild.
                if c.hotspot and (c.hotspot.on_release or c.hotspot.on_left_release) then
                    _play_click()
                    local gid = row._group_key
                    local now_expanded = not self._expanded[gid]
                    self._expanded[gid] = now_expanded or nil
                    -- (#163) Auto-collapse (default ON): opening closes same-level siblings; closing
                    -- collapses nested descendants — one branch open per level.
                    if self:_auto_collapse_on() then
                        self:_auto_collapse_apply(gid, now_expanded)
                    end
                    self:_build_rows(self._categories[self._selected])
                    self._search_rebuild_pending = nil
                    return
                end
            elseif row._wtype == "radio" then
                local clicked = c.hotspot and (c.hotspot.on_release or c.hotspot.on_left_release)
                if clicked and not row._radio_armed then
                    row._radio_armed = true
                    -- Selecting the active bubble is intentionally a no-op. A different
                    -- choice stages one bounded group transaction, then rebuilds so the
                    -- filled marker moves immediately without touching unrelated settings.
                    if not c.selected then
                        local MT = mod.mod_tweaker
                        local members = MT and MT:get_exclusive_members(row._mt_radio_group)
                        if row._mt_radio_none then
                            for j = 1, #(members or {}) do
                                local member = members[j]
                                local live = _cat_get(row._category, member.setting_id)
                                if self:get_staged(row._category, member.setting_id, live) then
                                    self:stage_set(row._category, member.setting_id, false)
                                end
                            end
                        else
                            self:stage_set(row._category, row._setting_id, true)
                            self:_enforce_exclusive(row._category, row._setting_id)
                        end
                        _play_click()
                        self._dd_block_until_press = true
                        self:_build_rows(self._categories[self._selected])
                        return
                    end
                elseif not clicked then
                    row._radio_armed = false
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
                    -- (#446) Mutually-exclusive group: turning a member ON stages its
                    -- siblings OFF, then rebuild so the switched-off rows repaint (checkbox
                    -- display is cached -- only a row rebuild re-reads the staged flag). Same
                    -- rebuild+return shape as the group-header toggle above. Turning a member
                    -- OFF (c.flag=false) is the "select None" path and touches no sibling.
                    -- Block row input until the next FRESH press so this release's still-
                    -- latched on_left_release on the shared mt_list_start node can't re-toggle
                    -- the rebuilt rows next frame (same latch class as the dropdown #158 /
                    -- slider-modal guard).
                    if c.flag and self:_enforce_exclusive(row._category, row._setting_id) then
                        self._dd_block_until_press = true
                        self:_build_rows(self._categories[self._selected])
                        return
                    end
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
            elseif row._wtype == "action" then
                local clicked = c.hotspot and (c.hotspot.on_release or c.hotspot.on_left_release)
                if clicked and not row._action_armed then
                    row._action_armed = true
                    _play_click()
                    if type(row._action) == "function" then
                        local ok_action, action_err = pcall(row._action)
                        if not ok_action then
                            mod:warning("[mt] action failed for %s.%s: %s",
                                tostring(row._mod_id), tostring(row._setting_id), tostring(action_err))
                        end
                    end
                    return
                elseif not clicked then
                    row._action_armed = false
                end
            elseif row._wtype == "keybind" then
                -- (#123) Left-click -> capture; right-click -> clear (like native options);
                -- Esc-while-capturing clears via the top-level ESC handler. Chat is blocked
                -- while capturing so Enter / letters can't leak to the game chat box.
                if self._capturing_keybind == row then
                    if Managers.chat and Managers.chat.block_chat_input_for_one_frame then
                        pcall(function() Managers.chat:block_chat_input_for_one_frame() end)
                    end
                    local combo, primary_is_mouse = _poll_keybind_combo()
                    if combo and primary_is_mouse then
                        -- (issue 631) Mouse primary: HOLD, do not commit yet. Snapshot the combo
                        -- (modifiers re-read each frame) and show a live preview; commit only when
                        -- the button is released (the `combo == nil` branch below). This keeps the
                        -- capture branch active for the release frame so its `return` consumes the
                        -- click, so binding Mouse 1 can't re-enter capture and Mouse 2 can't hit the
                        -- right-click-clear below — the same release-committed model VMF uses.
                        self._kb_mouse_pending = combo
                        row.content.value_text = _format_keybind_value(combo)
                    elseif combo then
                        -- Keyboard primary: commit immediately (unchanged, verified path).
                        self._capturing_keybind = nil
                        self._kb_mouse_pending = nil
                        self:stage_set(row._category, row._setting_id, combo)   -- (#123) STAGE; registers on APPLY
                        row.content.value_text = _format_keybind_value(combo)
                        _play_click()
                        return
                    elseif self._kb_mouse_pending then
                        -- (issue 631) The held mouse primary was released this frame (poll no longer
                        -- sees it): commit the snapshot and consume the release.
                        local pending = self._kb_mouse_pending
                        self._kb_mouse_pending = nil
                        self._capturing_keybind = nil
                        self:stage_set(row._category, row._setting_id, pending)   -- (#123) STAGE; registers on APPLY
                        row.content.value_text = _format_keybind_value(pending)
                        _play_click()
                        return
                    end
                elseif c.hotspot and c.hotspot.is_hover and Mouse.released(1) then
                    -- RIGHT-CLICK -> clear the binding (unbind), like native options. STAGED; applies on APPLY.
                    self:stage_set(row._category, row._setting_id, {})
                    row.content.value_text = _format_keybind_value({})
                    _play_click()
                    return
                elseif c.hotspot and (c.hotspot.on_release or c.hotspot.on_left_release) then
                    if self._editing_row then self:_commit_edit(self._editing_row) end
                    self._capturing_keybind = row
                    self._kb_mouse_pending = nil   -- (issue 631) fresh capture, drop any stale mouse hold
                    row.content.value_text = "PRESS A KEY..."
                    _play_click()
                    return
                end
            elseif row._wtype == "slider" or row._wtype == "numeric" then
                local cur = (type(c.value) == "number") and c.value or (c.min or 0)
                local moved, commit, play_sound = false, false, false
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
                if ths and ths.is_held and c.track_w then
                    -- DRAG: follow the cursor ONLY while the LMB is HELD (visual; commit on release).
                    local cursor = input_service and input_service:get("cursor")
                    if cursor then
                        local anchor = UISceneGraph.get_world_position(self.ui_scenegraph, defs.list_sg)
                        local cx = UIInverseScaleVectorToResolution(cursor)[1]
                        local frac = math.clamp((cx - (anchor[1] + (c.track_x or 0))) / math.max(1, c.track_w), 0, 1)
                        cur = (c.min or 0) + frac * ((c.max or 1) - (c.min or 0))
                        -- (#164) snap the dragged value to the step grid (anchored at range
                        -- min), or to decimals when no step — the SAME math the arrow + text-
                        -- entry paths use, so drag/arrow/type all land on identical grid points.
                        cur = _snap_and_clamp(c, cur)
                        moved = true
                        row._dragging = true
                    end
                elseif row._dragging then
                    -- (#167) DRAG ENDED (is_held dropped): commit + play the sound EXACTLY ONCE,
                    -- edge-latched. The old code keyed off on_left_release, which stays LATCHED on
                    -- the shared node for several frames -> it re-ran the cursor math (slider kept
                    -- "following" after release) AND fired commit+_play_click each frame (the 3-6
                    -- machine-gun increment clicks). is_held is the live held state and drops cleanly.
                    -- (#slider-modal) Block other rows' input until the next fresh press, so the
                    -- release's still-LATCHED on_release on a checkbox behind the cursor can't toggle
                    -- it once the drag-modal disengages next frame (same latch class as dropdown #158).
                    self._dd_block_until_press = true
                    row._dragging = false
                    commit = true; play_sound = true
                end
                -- (#152) Arrow step = ONE natural increment per click (1 for ints, 10^-dec),
                -- NOT the old ~range/40. Edge-latched so the multi-frame on_release latch can't
                -- step more than once per physical click (the "single click moves too much" +
                -- "auto-moves" bug). A HELD arrow then repeats after a delay and accelerates,
                -- matching the vanilla feel. The hold path uses is_held: if the dec/inc hotspots
                -- don't expose it, it's simply inert and the click path still gives 1-per-click.
                local nd = c.num_decimals or 0
                local unit = c.step or ((nd > 0) and (10 ^ -nd) or 1)  -- (#164) honor the slider's declared step
                local rel_dir = (c.dec and (c.dec.on_release or c.dec.on_left_release) and -1)
                             or (c.inc and (c.inc.on_release or c.inc.on_left_release) and 1) or 0
                if rel_dir ~= 0 then
                    if not row._arrow_latched then
                        row._arrow_latched = true
                        cur = _snap_and_clamp(c, cur + rel_dir * unit); moved = true; commit = true; play_sound = true  -- (#164) step + snap to grid (min-anchored)
                        _printf("[gut:slider-arrow] %s CLICK dir=%d step=%s -> %s", tostring(row._setting_id), rel_dir, tostring(unit), tostring(cur))
                    end
                else
                    row._arrow_latched = false
                end
                local hold_dir = (c.dec and c.dec.is_held and -1) or (c.inc and c.inc.is_held and 1) or 0
                if hold_dir ~= 0 then
                    row._arrow_hf = (row._arrow_hf or 0) + 1
                    if row._arrow_hf >= (row._arrow_hnext or 22) then   -- ~0.37s delay before first repeat
                        cur = _snap_and_clamp(c, cur + hold_dir * unit); moved = true; commit = true  -- (#164) step + snap to grid (min-anchored)
                        row._arrow_hnext = row._arrow_hf + math.max(2, 11 - math.floor(row._arrow_hf / 20))  -- accelerate
                        _printf("[gut:slider-arrow] %s HOLD-REPEAT f=%d dir=%d -> %s", tostring(row._setting_id), row._arrow_hf, hold_dir, tostring(cur))
                    end
                else
                    row._arrow_hf, row._arrow_hnext = 0, 22
                end
                -- Visual tracks the value every frame (smooth drag); persistence waits.
                if moved and cur ~= c.value then
                    c.value = cur
                    local span = (c.max or 1) - (c.min or 0)
                    c.internal_value = (span > 0) and math.clamp((cur - c.min) / span, 0, 1) or 0
                    c.value_text = string.format("%." .. (c.num_decimals or 0) .. "f", cur)
                    -- PROBE: confirms the drag handler updates internal_value (drives the
                    -- thumb) every frame. If internal_value sweeps 0->1 here but the thumb
                    -- visually doesn't move, the defect is the thumb's offset_function /
                    -- material, NOT the input math. thumb_x is what the offset_function
                    -- should compute (TRACK_X + TRACK_W*internal).
                    mod:debug("[mt:slider] DRAG '%s' val=%s internal=%.3f thumb_x~=%.0f (track_x=%s track_w=%s)",
                        tostring(row._setting_id), tostring(cur), c.internal_value,
                        (c.track_x or 0) + (c.track_w or 0) * c.internal_value,
                        tostring(c.track_x), tostring(c.track_w))
                end
                if commit then
                    -- (#152b) Click sound on the CLICK / drag-release EDGE only, NEVER on every
                    -- hold-repeat increment (that was the "machine-gun click-click-click").
                    if play_sound then _play_click() end
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
-- settings_arrow_clicked on hover) was REMOVED. The vanilla options menu does NOT
-- hard-swap a stepper/slider arrow to its bright "clicked" sprite on mere hover —
-- it fades a soft glow overlay's alpha (on_stepper_arrow_hover, options_view.lua:
-- 4335-4351) and otherwise relies on the row highlight. gut's instant swap read as
-- a pressed-down button under the cursor. Hover feedback now comes solely from the
-- whole-row playerlist_hover highlight (kept below), which the user confirmed looks
-- right. The arrows therefore stay on settings_arrow_normal at all times (the
-- factory's default), so nothing here touches left_arrow/right_arrow anymore.
function ModTweakerView:_apply_row_hover(row)
    local c = row.content
    if not c then return end
    -- (#158 / #slider-modal) While a dropdown popup is OPEN, or a slider is being dragged, it's
    -- MODAL: suppress every OTHER row's hover highlight + hover sound, so the menu doesn't light up
    -- phantom rows behind the popup or under the cursor mid-drag.
    if self._open_dropdown or (self._slider_dragging and row ~= self._slider_dragging) then
        if c.is_highlighted ~= nil then c.is_highlighted = false end
        row._was_hovered = false
        return
    end
    -- (1) row highlight from whichever hotspot the row exposes.
    local row_hot = c.hotspot or c.track_hs
    local hovered = (row_hot and row_hot.is_hover) and true or false
    if (c.dec and c.dec.is_hover) or (c.inc and c.inc.is_hover) then hovered = true end
    -- (row highlight) Full-row hover hotspot (added in _append_highlight) so dropdown / slider /
    -- keybind rows highlight when the cursor is over their LABEL, not only the control.
    if c.row_hs and c.row_hs.is_hover then hovered = true end
    -- (Fix 4, v0.2.149-dev) An EXPANDED collapsible group stays lit (row highlight bar +
    -- arrow glow) even when not hovered, so the open section reads as active. Thread the LIVE
    -- expanded state (self._expanded[row._group_key] — the same source the row toggle uses)
    -- into content.expanded so create_group_header's glow driver sees it each frame.
    if row._is_group then
        local exp = row._display_expanded
        if exp == nil then exp = self._expanded[row._group_key] and true or false end
        c.expanded = exp
        if exp then hovered = true end
    end
    if c.is_highlighted ~= nil then c.is_highlighted = hovered end
    -- (#165) Collapsible arrow brightening now lives in create_group_header's local_offset driver
    -- (mutates the live ui_style at draw-time); the pre-draw row.style write here didn't render.
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
-- Drawn on the SAME borrowed renderer the rows use, inside the protected begin/end_pass.
local TT_WAIT, TT_SPEED = 0.1, 4
function ModTweakerView:_update_tooltip(dt, hover_row, hover_world_y, renderer)
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

function ModTweakerView:_draw(dt, input_service)
    -- Draw on ui_top_renderer (top_ingame_view world) — the SAME renderer OptionsView
    -- and IngameView use. The old code drew on ui_renderer (level_world / in-mission
    -- HUD renderer); gut was the ONLY ESC-flow view touching level_world, and the
    -- state it left there polluted IngameView's chrome on the next frame, so the ESC
    -- menu came back as flat "deprecated" buttons (root cause: workflow wf_8504e8ba).
    -- Our rows were already rebuilt to use only atlas-safe materials (matchmaking_
    -- checkbox / slider_thumb / rect / border), which resolve on ui_top_renderer, so
    -- the original reason for level_world (the raw OVD checkbox materials) no longer
    -- applies.
    local renderer = self.ui_top_renderer or self.ui_renderer
    local scenegraph = self.ui_scenegraph

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
            if tab.content.disabled then
                -- (VMF-disabled mod) tab greyed out: dim + low alpha, regardless of hover/selected.
                st.text_color[1] = 110; st.text_color[2] = 90; st.text_color[3] = 90; st.text_color[4] = 90
            elseif active then
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


    -- (#561) Active profile is gold; hover is white; inactive slots use the
    -- same warm native button colour as the tab strip.
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

    -- (v0.2.71-dev) hover-enter sound on the EXIT (X) button (was unwired). Edge-debounced
    -- on self._exit._was_hovered. Mirrors the tab/APPLY hover edges added this version.
    if self._exit then
        local xh = self._exit.content.button_hotspot
        local x_hov = xh and xh.is_hover
        if x_hov and not self._exit._was_hovered then _play_hover() end
        self._exit._was_hovered = x_hov
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
    -- the borrowed ui_renderer is left mid-pass and the ESC menu's own chrome (which
    -- draws on the SAME ui_renderer / level_world) renders without its background —
    -- that's the "main menu looks deprecated (just buttons)" after leaving here.
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

    -- (#497) SEARCH box: update its text (query + blink caret, or the placeholder) + focus
    -- emphasis, then draw it as fixed chrome above the list. Drawn every frame so its hotspot
    -- flags populate for _handle_input (which runs after _draw). It lives on mt_search (its own
    -- fixed node above list_mask), so it never overlaps or culls with the scrolling rows.
    if self._search then
        local sc  = self._search.content
        local sty = self._search.style
        local q = self._search_str or ""
        local focused = self._search_focused
        -- #572: the magnifier is an empty-field affordance. Keep the full-field
        -- hotspot unchanged, but suppress only its passive texture while focused.
        sc.search_focused = focused
        self._search_caret_t = (self._search_caret_t or 0) + (dt or 0)
        if q == "" and not focused then
            sc.text = _search_placeholder(self)
            if sty.text and sty.text.text_color then
                sty.text.text_color[1], sty.text.text_color[2], sty.text.text_color[3], sty.text.text_color[4] = 160, 120, 120, 120
            end
        else
            local blink = focused and (self._search_caret_t % 1.0) < 0.5
            sc.text = q .. (blink and "|" or "")
            if sty.text and sty.text.text_color then
                sty.text.text_color[1], sty.text.text_color[2], sty.text.text_color[3], sty.text.text_color[4] = 255, 255, 255, 255
            end
        end
        if sty.bg_inner and sty.bg_inner.color then
            local v = focused and 26 or 14
            sty.bg_inner.color[2], sty.bg_inner.color[3], sty.bg_inner.color[4] = v, v, v
        end
        UIRenderer.draw_widget(renderer, self._search)
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
            DialogueUI.refresh_row(row, self)
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
                if c.state_hotspot then c.state_hotspot.on_release = nil; c.state_hotspot.on_left_release = nil end
                if c.media_hotspot then c.media_hotspot.on_release = nil; c.media_hotspot.on_left_release = nil end
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
        -- (#505) Live search-line text + blink caret for a filterable popup's header (same
        -- per-frame update the fixed search box uses). content.search_text only exists when the
        -- popup was built with a header, so guard on it — a plain dropdown has no header band.
        local dc = self._dd_list.content
        if dc and dc.search_text ~= nil then
            self._dd_caret_t = (self._dd_caret_t or 0) + (dt or 0)
            local q = self._dd_query or ""
            if q == "" then
                dc.search_text = "Type to filter..."
            else
                local blink = (self._dd_caret_t % 1.0) < 0.5
                dc.search_text = q .. (blink and "|" or "")
            end
        end
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

-- (#164) Exposed for /gut_regression_test (mod_tweaker_step_resolution): the pure step-resolution
-- + grid-snap helpers, unit-testable without building a live view. Statics, not methods.
ModTweakerView._resolve_step = _resolve_step
ModTweakerView._snap_and_clamp = _snap_and_clamp
ModTweakerView._search_placeholder = _search_placeholder

    return ModTweakerView
end

return M
