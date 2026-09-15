-- _gut_loadout_paging.lua -- paged native loadout selector: thirty modded loadouts on six reusable buttons (#231)
--
-- In the modded realm (STORE mode, Adventure mirror) the hero-view loadout bar shows the
-- modded store's slots as five pages of six. The six physical buttons vanilla builds at
-- module load (hero_window_loadout_selection_console_definitions.lua:1101-1109) are
-- relabeled per page with text Roman numerals (no request for the absent VII-XXX icon atlas entries), the
-- strip gains Previous/Next page buttons plus a page label, and every window path that
-- indexed `_loadout_button_widgets` by a LOGICAL loadout index (selection frame, hover,
-- context menu, add, delete, bot designation, draw: hero_window_loadout_selection_console.lua
-- :186-202, :368-386, :420-459, :500, :529, :709, :778-780, :972, :985-987) now routes
-- through _gut_loadout_page_mapper.lua. While such a window is open the capacity policy
-- appends custom rows 7-30 to InventorySettings.loadouts and raises MAX_NUM_CUSTOM_LOADOUTS
-- to 30 (the mirror add hook in _gut_native_loadouts.lua and the window's add gate both
-- read that cap, playfab_mirror_base.lua:2045); on window exit the vanilla six-row table and
-- cap are restored, so official-realm, READONLY-mode and Versus windows never see them.
-- Keyboard: Left/Right arrow keys (`move_left_raw` / `move_right_raw`,
-- controller_settings.lua:5748-5757) flip pages while the mouse is active; gamepad bumpers
-- keep vanilla's cycle-by-one and the page auto-reveals the selected slot.
--
-- Hook census on HeroWindowLoadoutSelectionConsole (NON-NEGOTIABLE 8): `_save_bot_equipment`
-- lives in _gut_bot_loadout_snapshot.lua, `_populate_context_menu_loadout` in
-- _gut_native_loadouts.lua, `_show_context_menu` in _gut_mission_inventory.lua (the
-- consolidated site, which calls Paging.after_show_context_menu). This module hooks only
-- methods none of them touch; never add a hook on those three here.
--
-- Owned by: gui_tweaker_dev.lua entry point (loaded from the _gut_mission_inventory.lua tail
-- because the entry point and _gut_native_loadouts.lua are at their size ceilings).
-- Consumed via: mod:dofile("scripts/mods/gui_tweaker_dev/_gut_loadout_paging")
local mod = get_mod("gut_dev")

local Mapper = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_loadout_page_mapper")
local Capacity = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_loadout_capacity_policy")
local NLPolicy = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_native_loadout_policy")

local WINDOW = "HeroWindowLoadoutSelectionConsole"
local DEFINITIONS_PATH = "scripts/ui/views/hero_view/windows/definitions/hero_window_loadout_selection_console_definitions"

-- Every vanilla method this owner replaces or follows. The regression check proves each
-- still exists on the live class (a vanilla rename would silently orphan the hook).
local HOOKED_METHODS = {
    "on_enter", "on_exit", "_populate_loadout_buttons", "_handle_mouse_input",
    "_handle_gamepad_input", "_handle_add_loadout_gamepad_input", "_on_enter_add_loadout_gamepad",
    "_handle_context_menu_input", "_change_loadout", "_add_loadout", "_update_animations", "_draw",
}

local Paging = { MARKER = "loadout_paging_v1", mapper = Mapper, capacity = Capacity, HOOKED_METHODS = HOOKED_METHODS }
mod._gut_loadout_paging = Paging

local function _log(fmt, ...)
    local out = rawget(_G, "printf")
    if type(out) == "function" then pcall(out, fmt, ...) end
end

-- ------------------------------------------------------------------
-- Vanilla strip geometry + gamepad input-description tables, read from the live definitions
-- module so a vanilla retune follows. Resolved once; a failure keeps paging inert (vanilla).
-- ------------------------------------------------------------------
local _geometry_cache
local function _geometry()
    if _geometry_cache ~= nil then return _geometry_cache or nil end
    local req = rawget(_G, "local_require") or rawget(_G, "require")
    local ok, defs = pcall(req, DEFINITIONS_PATH)
    if ok and type(defs) == "table" and type(defs.button_size) == "table"
            and type(defs.generic_input_actions) == "table" then
        _geometry_cache = {
            size = defs.button_size,
            width = defs.button_size[1] or 48,
            height = defs.button_size[2] or 48,
            spacing = defs.button_spacing or 5,
            actions = defs.generic_input_actions,
        }
    else
        _geometry_cache = false
        _log("[gut:231] loadout paging inactive: definitions unavailable (%s)", tostring(defs))
    end
    return _geometry_cache or nil
end
Paging.geometry = _geometry

-- ------------------------------------------------------------------
-- Realm gate. Paging exists only in the modded realm, only in STORE mode, only on the
-- Adventure mirror (Mapper.should_page); every uncertainty resolves to vanilla.
-- ------------------------------------------------------------------
function Paging.runtime_gate()
    local guard = mod._gut_official_loadout_boot_guard
    local ok_realm, is_modded = pcall(function()
        return type(guard) == "table" and type(guard.in_modded_realm) == "function"
            and guard.in_modded_realm() == true
    end)
    is_modded = ok_realm and is_modded == true
    local mode = NLPolicy.mode(is_modded, mod:get("gut_use_non_modded_loadouts"))
    local ok_key, key = pcall(function()
        return Managers.backend:get_interface("items")._backend_mirror._characters_data_key
    end)
    key = ok_key and key or nil
    return Mapper.should_page(is_modded, mode, key), is_modded, mode, key
end

-- ------------------------------------------------------------------
-- Window-scoped capacity. Refcounted per live paged window so overlapping layouts cannot
-- strip the rows from under each other; restored to the vanilla six-row table at zero.
-- ------------------------------------------------------------------
local _expanded_windows = 0

local function _rows()
    local inv = rawget(_G, "InventorySettings")
    return type(inv) == "table" and type(inv.loadouts) == "table" and inv.loadouts or nil
end

local function _expand()
    _expanded_windows = _expanded_windows + 1
    local rows = _rows()
    if not rows then return end
    local added = Capacity.expand(rows, Mapper.TARGET)
    InventorySettings.MAX_NUM_CUSTOM_LOADOUTS = Capacity.custom_count(rows)
    _log("[gut:231] capacity expanded rows=+%d cap=%d windows=%d",
        added, InventorySettings.MAX_NUM_CUSTOM_LOADOUTS, _expanded_windows)
end

local function _contract()
    if _expanded_windows <= 0 then return end
    _expanded_windows = _expanded_windows - 1
    if _expanded_windows > 0 then return end
    local rows = _rows()
    if not rows then return end
    local removed = Capacity.contract(rows)
    InventorySettings.MAX_NUM_CUSTOM_LOADOUTS = Capacity.custom_count(rows)
    _log("[gut:231] capacity restored rows=-%d cap=%d", removed, InventorySettings.MAX_NUM_CUSTOM_LOADOUTS)
end

function Paging.expanded_windows() return _expanded_windows end

-- ------------------------------------------------------------------
-- Per-window state (`self._gut231`, nil = vanilla behavior for that window).
-- ------------------------------------------------------------------
local function _state(self)
    return self and self._gut231 or nil
end

local function _career_name(self)
    local profiles = rawget(_G, "SPProfiles")
    local profile = profiles and profiles[self._profile_index]
    local career = profile and profile.careers and profile.careers[self._career_index]
    return career and career.name
end

-- Hotspot flags are written by the hotspot pass only while a widget is DRAWN; a button that
-- leaves the page keeps stale flags, so every relabel clears them (UIUtils.is_button_* read
-- them, ui_utils.lua:381-450).
local HOTSPOT_FLAGS = {
    "is_hover", "on_hover_enter", "on_hover_exit", "is_clicked", "on_pressed", "on_release",
    "is_held", "on_right_click", "on_double_click", "cursor_hover",
}
local function _reset_hotspot(content)
    local hotspot = content.button_hotspot
    if type(hotspot) == "table" then
        for i = 1, #HOTSPOT_FLAGS do hotspot[HOTSPOT_FLAGS[i]] = nil end
    end
    content.hover_enter_time = nil
end

-- The tweaked button has three text passes sized for an icon button (size[1]-40 wide,
-- definitions.lua:912-975). Give them the full button as area and hide the icon texture
-- (alpha 0; the texture stays the resident vanilla icon of that button, nothing new is requested).
-- dynamic_font_size ratchets style.font_size DOWN in place (ui_renderer.lua:1522-1536), so
-- the base size is memoized and restored on every relabel.
local TEXT_STYLES = { "title_text", "title_text_disabled", "title_text_shadow" }
local function _prepare_text_button(widget, geometry)
    local style = widget.style
    for i = 1, #TEXT_STYLES do
        local text_style = style[TEXT_STYLES[i]]
        if type(text_style) == "table" then
            text_style.area_size = { geometry.width - 2, geometry.height }
            text_style.dynamic_font_size = true
            text_style._gut231_font_size = text_style._gut231_font_size or text_style.font_size or 24
        end
    end
    local background = style.background
    if type(background) == "table" and type(background.color) == "table" then
        background.color[1] = 0
    end
end

local function _relabel(widget, text)
    widget.content.title_text = text
    for i = 1, #TEXT_STYLES do
        local text_style = widget.style[TEXT_STYLES[i]]
        if type(text_style) == "table" and text_style._gut231_font_size then
            text_style.font_size = text_style._gut231_font_size
        end
    end
end

local function _create_controls(self, geometry)
    local step = geometry.width + geometry.spacing
    -- Same factory + argument shape as the vanilla add (+) button (definitions.lua:1134).
    local prev_def = UIWidgets.create_default_button("button", geometry.size, nil, nil, "<", 32,
        nil, nil, nil, false, true, nil, { -step, 0, 0 }, nil, geometry.size)
    local next_def = UIWidgets.create_default_button("add_loadout_button", geometry.size, nil, nil, ">", 32,
        nil, nil, nil, false, true, nil, { -step, 0, 0 }, nil, geometry.size)
    local label_style = {
        font_size = 18,
        font_type = "hell_shark",
        localize = false,
        upper_case = false,
        word_wrap = false,
        horizontal_alignment = "center",
        vertical_alignment = "center",
        text_color = Colors.get_color_table_with_alpha("font_default", 255),
        offset = { 0, geometry.height - 2, 2 },
    }
    local label_def = UIWidgets.create_simple_text("", "add_loadout_button", nil, nil, label_style)
    local st = self._gut231
    st.prev = UIWidget.init(prev_def)
    st.next = UIWidget.init(next_def)
    st.label = UIWidget.init(label_def)
end

-- Strip geometry, selection frame and page controls for the current page. Every physical
-- widget index used here comes from the mapper.
local function _layout(self)
    local st = self._gut231
    local layout = Mapper.layout(st.page, self._num_loadouts or 0, st.geometry.width, st.geometry.spacing)
    st.layout = layout
    local node = self._ui_scenegraph and self._ui_scenegraph.button
    if node and node.offset then node.offset[1] = layout.strip_offset end
    local names = self._widgets_by_name or {}
    local frame = names.loadout_frame
    local slot = Mapper.physical_slot(self._selected_loadout_index, st.page)
    local widget = slot and self._loadout_button_widgets[slot] or nil
    if frame then
        if widget then
            frame.offset[1] = widget.offset[1]
            frame.offset[3] = -10
            frame.content.visible = true
        else
            frame.content.visible = false
        end
    end
    if st.prev then
        st.prev.content.visible = layout.show_controls
        st.next.content.visible = layout.show_controls
        st.label.content.visible = layout.show_controls
        st.prev.content.button_hotspot.disable_button = not layout.has_previous
        st.next.content.button_hotspot.disable_button = not layout.has_next
        st.label.content.text = mod:localize("gut_loadout_page_label", layout.page, layout.page_count)
    end
    return layout
end

-- Bind the current page's logical slots onto the six physical buttons (replaces the direct
-- `for idx, widget in ipairs(self._loadout_button_widgets)` fill, :186-194).
local function _fill(self, career_loadouts, career_name)
    local st = self._gut231
    local selected = self._selected_loadout_index
    local widgets = self._loadout_button_widgets
    for slot = 1, #widgets do
        local widget = widgets[slot]
        local content = widget.content
        local logical = Mapper.logical_of(st.page, slot)
        local row = logical and career_loadouts[logical] or nil
        content.visible = row ~= nil
        content.is_selected = row ~= nil and logical == selected
        content.loadout = row
        content.loadout_index = row and logical or -1
        content.career_name = career_name
        _relabel(widget, row and Mapper.roman(logical) or "")
        _reset_hotspot(content)
    end
end

-- Re-read the live rows (the interface rebuilds them on refresh, #379), pick the page
-- (auto-reveal the selected slot when `reveal`), fill and lay out.
local function _refresh(self, reveal)
    local st = self._gut231
    local career_name = _career_name(self)
    local iface = Managers.backend:get_interface("items")
    local career_loadouts = (career_name and iface and iface:get_career_loadouts(career_name)) or {}
    local total = #career_loadouts
    self._num_loadouts = total
    if reveal then
        st.page = Mapper.reveal_page(self._selected_loadout_index, total, st.page)
    else
        st.page = Mapper.clamp_page(st.page, total)
    end
    _fill(self, career_loadouts, career_name)
    return _layout(self)
end

local function _set_page(self, page)
    local st = self._gut231
    local target = Mapper.clamp_page(page, self._num_loadouts or 0)
    if target == st.page then return false end
    self:_hide_context_menu()
    st.page = target
    local layout = _refresh(self, false)
    self:_play_sound("Play_hud_hover")
    _log("[gut:231] page %d/%d visible=%d selected=%s", layout.page, layout.page_count,
        layout.visible, tostring(self._selected_loadout_index))
    return true
end
Paging.set_page = _set_page

-- The ONLY logical -> physical widget lookup. `reveal` flips to the slot's page first;
-- otherwise a slot on another page yields nil.
local function _widget_for(self, logical, reveal)
    local st = self._gut231
    local page = Mapper.page_of(logical)
    if not page or logical > (self._num_loadouts or 0) then return nil end
    if page ~= st.page then
        if not reveal then return nil end
        st.page = page
        _refresh(self, false)
    end
    return self._loadout_button_widgets[Mapper.slot_of(logical)]
end
Paging.widget_for = _widget_for

-- Called by the consolidated `_show_context_menu` hook (_gut_mission_inventory.lua) after
-- vanilla ran: vanilla raises the button whose PHYSICAL index equals the logical index
-- (:778-780) and localizes the per-slot custom title key (:833), which has no vanilla string
-- past VI, with the row's icon nil past VI (:832).
function Paging.after_show_context_menu(self, widget)
    local st = _state(self)
    if not st or type(widget) ~= "table" then return end
    local widgets = self._loadout_button_widgets or {}
    for i = 1, #widgets do
        widgets[i].offset[3] = widgets[i] == widget and -20 or -100
    end
    local logical = widget.content and widget.content.loadout_index
    local beyond = type(logical) == "number" and logical > Mapper.VANILLA_VISIBLE
    local names = self._widgets_by_name or {}
    if beyond and names.header then
        names.header.content.text = mod:localize("gut_loadout_slot_title", Mapper.roman(logical))
    end
    if names.icon then
        names.icon.content.visible = not beyond
    end
end

-- ==================================================================
-- Hooks. Pre-flight 2026-09-14: grepped gui_tweaker_dev for ("HeroWindowLoadoutSelectionConsole"
-- -> only _save_bot_equipment, _populate_context_menu_loadout, _show_context_menu exist; none of
-- the methods below. hook-test: issue231_loadout_paging
-- ==================================================================

mod:hook(WINDOW, "on_enter", function(func, self, params, offset)
    self._gut231 = nil
    local active, is_modded, mode, key = Paging.runtime_gate()
    local geometry = active and _geometry() or nil
    if active and geometry then
        self._gut231 = { page = 1, geometry = geometry }
        _expand()
    end
    func(self, params, offset)
    local st = self._gut231
    if not st then
        if is_modded then
            _log("[gut:231] paging inactive mode=%s mirror=%s", tostring(mode), tostring(key))
        end
        return
    end
    local ok, err = pcall(function()
        local widgets = self._loadout_button_widgets or {}
        for i = 1, #widgets do _prepare_text_button(widgets[i], geometry) end
        _create_controls(self, geometry)
        _layout(self)
    end)
    if not ok then
        _log("[gut:231] paging setup failed, window falls back to vanilla: %s", tostring(err))
        self._gut231 = nil
        _contract()
        return
    end
    _log("[gut:231] paging active loadouts=%d page=%d/%d cap=%d", self._num_loadouts or 0,
        st.page, st.layout and st.layout.page_count or 1, tostring(InventorySettings.MAX_NUM_CUSTOM_LOADOUTS))
end)

mod:hook_safe(WINDOW, "on_exit", function(self)
    if self._gut231 then
        self._gut231 = nil
        _contract()
    end
end)

mod:hook(WINDOW, "_populate_loadout_buttons", function(func, self)
    local st = _state(self)
    if not st then return func(self) end
    -- Vanilla bookkeeping (:149-184), unchanged; the cap counts the expanded rows.
    local career_name = _career_name(self)
    local item_interface = Managers.backend:get_interface("items")
    local career_loadouts = item_interface:get_career_loadouts(career_name)
    local selected_loadout_index = item_interface:get_selected_career_loadout(career_name)
    self._num_loadouts = #career_loadouts
    if selected_loadout_index > self._num_loadouts then
        selected_loadout_index = 1
    end
    self._max_loadouts = 0
    for _, loadout_setting in ipairs(InventorySettings.loadouts) do
        if loadout_setting.loadout_type == "custom" then
            self._max_loadouts = self._max_loadouts + 1
        end
    end
    local add_loadout_button = self._widgets_by_name.add_loadout_button
    add_loadout_button.content.button_hotspot.disable_button = self._num_loadouts >= self._max_loadouts
    self._selected_loadout_index = selected_loadout_index
    if InventorySettings.bot_loadout_allowed_game_modes[self._game_mode_key] then
        PlayerData.loadout_selection = PlayerData.loadout_selection or {}
        PlayerData.loadout_selection.bot_equipment = PlayerData.loadout_selection.bot_equipment or {}
        local bot_equipment_index = PlayerData.loadout_selection.bot_equipment[career_name]
        if not bot_equipment_index or bot_equipment_index > self._num_loadouts then
            PlayerData.loadout_selection.bot_equipment[career_name] = selected_loadout_index
        end
    end
    -- Paged fill + selection frame + strip offset replace :186-202.
    _refresh(self, true)
end)

mod:hook(WINDOW, "_handle_mouse_input", function(func, self, input_service, dt, t)
    local st = _state(self)
    if not st then return func(self, input_service, dt, t) end
    local hovered_logical
    self:_reset_hover_frame()
    local widgets = self._loadout_button_widgets
    for slot = 1, #widgets do
        local widget = widgets[slot]
        local logical = widget.content.visible and Mapper.logical_of(st.page, slot) or nil
        if logical then
            if UIUtils.is_button_hover_enter(widget) then
                widget.content.hover_enter_time = t + 0
                self:_play_sound("Play_hud_hover")
            elseif UIUtils.is_button_hover(widget) then
                self:_update_button_hover(widget, t)
                hovered_logical = logical
            end
            if UIUtils.is_button_pressed(widget) then
                self:_change_loadout(logical)
                return
            end
        end
    end
    local layout = st.layout
    if layout and layout.show_controls and st.prev then
        if UIUtils.is_button_hover_enter(st.prev) or UIUtils.is_button_hover_enter(st.next) then
            self:_play_sound("Play_hud_hover")
        end
        -- is_button_pressed consumes on_release even on a disabled button (ui_utils.lua:381-390).
        local prev_pressed = UIUtils.is_button_pressed(st.prev)
        local next_pressed = UIUtils.is_button_pressed(st.next)
        if prev_pressed and layout.has_previous then
            _set_page(self, st.page - 1)
            return
        elseif next_pressed and layout.has_next then
            _set_page(self, st.page + 1)
            return
        end
        if not self._context_menu_active and not self._on_add_loadout_button then
            if input_service:get("move_left_raw") and layout.has_previous then
                _set_page(self, st.page - 1)
                return
            elseif input_service:get("move_right_raw") and layout.has_next then
                _set_page(self, st.page + 1)
                return
            end
        end
    end
    -- Vanilla :388-404 with the hovered LOGICAL index.
    local context_menu_widget_hotspot = self._widgets_by_name.context_menu_hotspot
    if self._context_menu_active and UIUtils.is_button_hover(context_menu_widget_hotspot)
            or hovered_logical == self._context_menu_loadout_index then
        self:_handle_context_menu_input(input_service, dt, t)
        context_menu_widget_hotspot.content.hover_timer = t + 0.1
    elseif self._context_menu_active
            and (hovered_logical or t > (context_menu_widget_hotspot.content.hover_timer or 0)) then
        self:_hide_context_menu()
    end
    local add_loadout_button_widget = self._widgets_by_name.add_loadout_button
    if UIUtils.is_button_hover_enter(add_loadout_button_widget) then
        self:_play_sound("Play_hud_hover")
    elseif UIUtils.is_button_pressed(add_loadout_button_widget) then
        self:_add_loadout()
    end
end)

mod:hook(WINDOW, "_handle_gamepad_input", function(func, self, input_service, dt, t)
    local st = _state(self)
    if not st then return func(self, input_service, dt, t) end
    if self._inside_context_menu then
        self:_handle_context_menu_gamepad_input(input_service, dt, t)
    elseif self._on_add_loadout_button then
        self:_handle_add_loadout_gamepad_input(input_service, dt, t)
    elseif self._context_menu_active then
        if input_service:get("move_left") or input_service:get("trigger_cycle_previous") then
            local old_index = self._context_menu_loadout_index
            local new_index = math.max(old_index - 1, 1)
            if old_index ~= new_index then
                self:_hide_context_menu()
                local widget = _widget_for(self, new_index, true)
                if widget then
                    self:_show_context_menu(widget)
                    self:_update_selection_frame(widget)
                end
            end
        elseif input_service:get("move_right") or input_service:get("trigger_cycle_next") then
            local old_index = self._context_menu_loadout_index
            local new_index = math.min(old_index + 1, self._num_loadouts)
            if old_index ~= new_index then
                self:_hide_context_menu()
                local widget = _widget_for(self, new_index, true)
                if widget then
                    self:_show_context_menu(widget)
                    self:_update_selection_frame(widget)
                end
            elseif self._num_loadouts < self._max_loadouts then
                self:_on_enter_add_loadout_gamepad()
            end
        elseif input_service:get("special_1") then
            self:_enter_details_menu()
        elseif input_service:get("back") or input_service:get("right_stick_press") or input_service:get("toggle_menu") then
            self:_hide_context_menu()
        elseif input_service:get("confirm") then
            self:_change_loadout(self._context_menu_loadout_index)
        elseif input_service:get("left_stick_press") then
            if InventorySettings.bot_loadout_allowed_game_modes[self._game_mode_key] then
                local bot_checkbox_widget = self._widgets_by_name.bot_checkbox
                local content = bot_checkbox_widget.content
                content.button_hotspot.is_selected = true
                content.button_hotspot.disable_button = true
                self:_save_bot_equipment()
            end
        else
            self:_handle_delete_input(input_service, dt, t)
        end
    elseif input_service:get("right_stick_press") then
        local widget = _widget_for(self, self._selected_loadout_index, true)
        if not widget then
            return
        end
        self:_show_context_menu(widget)
        self:_update_selection_frame(widget)
        self:_update_gamepad_selections(true)
        self._inside_context_menu = false
        self._parent:block_input()
    elseif input_service:get("trigger_cycle_next") then
        self:_change_loadout(math.min(self._selected_loadout_index + 1, self._num_loadouts))
    elseif input_service:get("trigger_cycle_previous") then
        self:_change_loadout(math.max(self._selected_loadout_index - 1, 1))
    end
end)

mod:hook(WINDOW, "_handle_add_loadout_gamepad_input", function(func, self, input_service, dt, t)
    local st = _state(self)
    if not st then return func(self, input_service, dt, t) end
    local actions = st.geometry.actions
    if input_service:get("confirm") then
        self:_add_loadout()
        self:_update_gamepad_selections(true)
        self._inside_context_menu = false
        self:_hide_context_menu()
    elseif input_service:get("back") or input_service:get("right_stick_press") or input_service:get("toggle_menu") then
        self:_hide_context_menu()
    elseif input_service:get("move_left") or input_service:get("trigger_cycle_previous") then
        local widget = _widget_for(self, self._num_loadouts, true)
        if not widget then
            return
        end
        self:_show_context_menu(widget)
        self:_update_selection_frame(widget)
        self:_update_gamepad_selections(true)
        self._inside_context_menu = false
        if self._num_loadouts > 1 then
            self._menu_input_description:change_generic_actions(actions.default)
        else
            self._menu_input_description:change_generic_actions(actions.default_no_delete)
        end
        self._parent:block_input()
    end
end)

mod:hook(WINDOW, "_on_enter_add_loadout_gamepad", function(func, self)
    local st = _state(self)
    if not st then return func(self) end
    self:_hide_context_menu()
    self._on_add_loadout_button = true
    -- The add button conceptually follows the LAST slot: reveal the last page first, then
    -- park the hover frame where the mapper says the add button sits (replaces :529).
    st.page = Mapper.page_count(self._num_loadouts)
    local layout = _refresh(self, false)
    local hover_loadout_frame = self._widgets_by_name.hover_loadout_frame
    hover_loadout_frame.content.visible = true
    hover_loadout_frame.offset[1] = layout.add_hover_offset
    local actions = st.geometry.actions
    if self._num_loadouts >= self._max_loadouts then
        self._menu_input_description:change_generic_actions(actions.add_loadout_no_add)
    else
        self._menu_input_description:change_generic_actions(actions.add_loadout)
    end
    self._parent:block_input()
end)

mod:hook(WINDOW, "_handle_context_menu_input", function(func, self, input_service, dt, t)
    local st = _state(self)
    if not st then return func(self, input_service, dt, t) end
    local context_menu_hotspot = self._widgets_by_name.context_menu_hotspot
    if input_service:get("toggle_menu", true) then
        self:_hide_context_menu()
        return
    end
    local left_press = input_service:get("left_press")
    local right_press = input_service:get("right_press")
    local loadout_button = _widget_for(self, self._context_menu_loadout_index, false)
    if not UIUtils.is_button_hover(context_menu_hotspot) and (left_press or right_press)
            and not UIUtils.is_button_hover(loadout_button) then
        self:_hide_context_menu()
    else
        self:_handle_delete_input(input_service, dt, t)
        self:_handle_bot_checkbox_input(input_service, dt, t)
    end
end)

mod:hook(WINDOW, "_change_loadout", function(func, self, loadout_index)
    local st = _state(self)
    if not st then return func(self, loadout_index) end
    if loadout_index and loadout_index ~= self._selected_loadout_index then
        local career_name = _career_name(self)
        local item_interface = Managers.backend:get_interface("items")
        item_interface:set_loadout_index(career_name, loadout_index)
        local selected_loadout_index = item_interface:get_selected_career_loadout(career_name)
        if selected_loadout_index > self._num_loadouts then
            selected_loadout_index = 1
        end
        self._selected_loadout_index = selected_loadout_index
        -- Selection frame + auto-reveal through the mapper (replaces :971-975).
        _refresh(self, true)
        self._parent:update_full_loadout()
        self:_play_sound("Play_gui_loadout_select")
        self:_hide_context_menu()
        self._parent:set_loadout_dirty()
    end
end)

mod:hook(WINDOW, "_add_loadout", function(func, self)
    local st = _state(self)
    if not st then return func(self) end
    -- Vanilla gates on the PHYSICAL widget count (:985-987); paging gates on the live cap.
    if (self._num_loadouts or 0) < (self._max_loadouts or 0) then
        local career_name = _career_name(self)
        local item_interface = Managers.backend:get_interface("items")
        item_interface:add_loadout(career_name)
        self:_play_sound("Play_gui_loadout_add")
        self._parent:update_full_loadout()
        self:_populate_loadout_buttons()
    end
end)

mod:hook_safe(WINDOW, "_update_animations", function(self, dt)
    local st = _state(self)
    if st and st.layout and st.layout.show_controls and st.prev then
        UIWidgetUtils.animate_default_button(st.prev, dt)
        UIWidgetUtils.animate_default_button(st.next, dt)
    end
end)

mod:hook_safe(WINDOW, "_draw", function(self, dt)
    local st = _state(self)
    if not (st and st.layout and st.layout.show_controls and st.prev) then return end
    local ui_top_renderer = self._ui_top_renderer
    local ui_scenegraph = self._ui_scenegraph
    if not ui_top_renderer or not ui_scenegraph then return end
    -- Second pass on the same renderer/scenegraph/render settings vanilla just used (:1015).
    local input_service = self:_get_input_service()
    UIRenderer.begin_pass(ui_top_renderer, ui_scenegraph, input_service, dt, nil, self._render_settings)
    UIRenderer.draw_widget(ui_top_renderer, st.prev)
    UIRenderer.draw_widget(ui_top_renderer, st.next)
    UIRenderer.draw_widget(ui_top_renderer, st.label)
    UIRenderer.end_pass(ui_top_renderer)
end)

-- ==================================================================
-- Regression check (tier b): realm gating, mapper bijection across thirty slots, numerals,
-- the window-scoped cap, the consolidated context-menu site, and every hooked vanilla method.
-- ==================================================================
Paging.rt_checks = {
    { name = "issue231_loadout_paging", fn = function()
        if Mapper.should_page(false, "store", "characters_data") then return "official realm must not page" end
        if Mapper.should_page(true, "readonly", "characters_data") then return "READONLY mode must not page" end
        if Mapper.should_page(true, "store", "vs_characters_data") then return "Versus mirror must not page" end
        if not Mapper.should_page(true, "store", "characters_data") then return "modded STORE Adventure must page" end
        if NLPolicy.mode(true, false) ~= "store" or NLPolicy.mode(false, false) ~= "off" then
            return "native loadout mode policy drifted"
        end
        local err = Mapper.check_bijection(Mapper.TARGET)
        if err then return "mapper bijection: " .. err end
        if Mapper.page_count(Mapper.TARGET) ~= 5 or Mapper.PAGE_SIZE ~= 6 then
            return "thirty slots must be five pages of six"
        end
        local numerals = { [1] = "I", [4] = "IV", [6] = "VI", [7] = "VII", [9] = "IX", [14] = "XIV",
            [19] = "XIX", [24] = "XXIV", [29] = "XXIX", [30] = "XXX" }
        for n, want in pairs(numerals) do
            if Mapper.roman(n) ~= want then
                return string.format("roman(%d)=%s, expected %s", n, tostring(Mapper.roman(n)), want)
            end
        end
        if Mapper.roman(0) ~= "" or Mapper.roman(2.5) ~= "" then return "invalid numerals must be empty" end
        local inv = rawget(_G, "InventorySettings")
        if type(inv) ~= "table" or type(inv.loadouts) ~= "table" then return "InventorySettings unavailable" end
        local expected = _expanded_windows > 0 and Mapper.TARGET or Mapper.VANILLA_VISIBLE
        if inv.MAX_NUM_CUSTOM_LOADOUTS ~= expected then
            return string.format("cap %s, expected %d (paged windows=%d)",
                tostring(inv.MAX_NUM_CUSTOM_LOADOUTS), expected, _expanded_windows)
        end
        if Capacity.custom_count(inv.loadouts) ~= expected then
            return string.format("custom rows %d, expected %d", Capacity.custom_count(inv.loadouts), expected)
        end
        local rows = { { loadout_index = 1, loadout_type = "default" }, { loadout_index = 2, loadout_type = "default" } }
        for i = 1, Mapper.VANILLA_VISIBLE do rows[#rows + 1] = { loadout_index = i, loadout_type = "custom" } end
        if Capacity.expand(rows, Mapper.TARGET) ~= 24 or Capacity.custom_count(rows) ~= 30 or #rows ~= 32 then
            return "capacity expand did not yield thirty custom rows"
        end
        if Capacity.expand(rows, Mapper.TARGET) ~= 0 then return "capacity expand is not idempotent" end
        if Capacity.contract(rows) ~= 24 or Capacity.custom_count(rows) ~= 6 or #rows ~= 8 then
            return "capacity contract did not restore the vanilla table"
        end
        if mod._gut231_context_menu_merged ~= true then
            return "_show_context_menu consolidation site marker missing (_gut_mission_inventory.lua)"
        end
        local class = rawget(_G, WINDOW)
        if type(class) ~= "table" then return WINDOW .. " class missing" end
        for i = 1, #HOOKED_METHODS do
            if type(class[HOOKED_METHODS[i]]) ~= "function" then
                return "vanilla method missing: " .. HOOKED_METHODS[i]
            end
        end
        if not _geometry() then return "loadout selection definitions unavailable" end
    end },
}

local register = rawget(mod, "_gut_rt_register")
if type(register) == "function" then
    for _, check in ipairs(Paging.rt_checks) do register(check.name, check.fn) end
end

_log("[gut:231] loadout paging owner loaded (%s) target=%d page_size=%d", Paging.MARKER, Mapper.TARGET, Mapper.PAGE_SIZE)

return Paging
