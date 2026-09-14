-- _gut_simple_ui_dropdowns.lua - #314 phase 2: fitted Simple UI dropdown lists.
--
-- Simple UI (Workshop 1389872347, unlicensed) copies its widget prototype
-- functions into every widget instance when the widget is created
-- (simple_ui.lua:862-884 create_widget -> :1407-1432 setup/copy_widget_element)
-- and calls those instance fields every frame. Upstream's dropdown lays every
-- option one row below the previous one (:2128-2150) and extends its hit box by
-- the whole list (:2168-2176), so a list near the bottom of the screen or with
-- many options runs off-screen and its lower rows cannot be clicked.
--
-- This owner never copies upstream code and never touches a prototype. Per
-- live dropdown instance it:
--   * wraps that instance's own `update` to compute the fitted layout, keep
--     the scroll offset, and read the mouse wheel while the cursor is over the
--     open list (Mouse.axis / axis_index("wheel"), debug_manager.lua:289-296);
--   * replaces that instance's `extended_bounds` with the fitted hit box, which
--     upstream also uses to draw the dropdown background (:1527-1531) and to
--     decide which option receives a click/release (:2100-2126);
--   * chains each option's public `before_update` callback, which runs first
--     inside the option's update (:1433-1436) after the parent placed the row
--     downward, to place the row from the pure layout or to hide, disable and
--     park a scrolled-out row off-screen so no hit test can reach it.
-- Consumer callbacks and a consumer's own `disabled` flag are preserved.
-- Turning the option off returns every wrapped dropdown to upstream behavior.
-- Owned by: _gut_simple_ui_compat.lua (tail loader). Consumed via mod:dofile.
local mod = get_mod("gut_dev")
local Policy = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_simple_ui_bounds_policy")

local M = {
    policy = Policy,
    setting_id = "gut_simple_ui_fit_dropdowns",
    phase = 2,
}

local states = setmetatable({}, { __mode = "k" })
local NIL = {}            -- "the consumer's disabled flag was nil before we hid this row"
local OFFSCREEN = -1e7    -- parking spot for hidden rows; no cursor can reach it

function M.enabled()
    return mod:get(M.setting_id) ~= false
end

local function _screen_height()
    local resolution = rawget(_G, "UIResolution")
    if type(resolution) ~= "function" then return nil end
    local ok, _, height = pcall(resolution)
    return ok and type(height) == "number" and height or nil
end

-- Upstream scales the row gap by UIResolutionScale() (simple_ui.lua:2135).
local function _ui_scale()
    local scale_fn = rawget(_G, "UIResolutionScale")
    if type(scale_fn) == "function" then
        local ok, scale = pcall(scale_fn)
        if ok and type(scale) == "number" and scale > 0 then return scale end
    end
    return 1
end

-- Mouse axes arrive as engine Vector3 values (read with Vector3.x/y like the
-- vanilla callers); the offline host passes plain {x, y} tables.
local function _axis_xy(value)
    if value == nil then return nil, nil end
    local vector3 = rawget(_G, "Vector3")
    if type(vector3) == "table" and type(vector3.x) == "function" and type(vector3.y) == "function" then
        local ok, x, y = pcall(function() return vector3.x(value), vector3.y(value) end)
        if ok and type(x) == "number" and type(y) == "number" then return x, y end
    end
    if type(value) == "table" and type(value[1]) == "number" and type(value[2]) == "number" then
        return value[1], value[2]
    end
    return nil, nil
end

local function _wheel_y()
    local mouse = rawget(_G, "Mouse")
    if type(mouse) ~= "table" or type(mouse.axis) ~= "function"
            or type(mouse.axis_index) ~= "function" then
        return 0
    end
    local ok, value = pcall(function() return mouse.axis(mouse.axis_index("wheel")) end)
    if not ok then return 0 end
    local _, y = _axis_xy(value)
    return y or 0
end

-- Same cursor axis Simple UI and vanilla read (ui_scenegraph.lua:399).
local function _cursor()
    local mouse = rawget(_G, "Mouse")
    if type(mouse) ~= "table" or type(mouse.axis) ~= "function"
            or type(mouse.axis_id) ~= "function" then
        return nil, nil
    end
    local ok, value = pcall(function() return mouse.axis(mouse.axis_id("cursor")) end)
    if not ok then return nil, nil end
    return _axis_xy(value)
end

local function _inside(bounds, x, y)
    if type(bounds) ~= "table" or not x or not y then return false end
    return x >= bounds[1] and x <= bounds[2] and y >= bounds[3] and y <= bounds[4]
end

-- Upstream places rows by each option's own `index` (simple_ui.lua:2141), and
-- create_dropdown appends options in pairs() order (:835-838), so the highest
-- index, not the array length, bounds the list.
local function _option_count(dropdown)
    local options = dropdown.options
    if type(options) ~= "table" then return 0 end
    local count = #options
    for _, option in pairs(options) do
        local index = type(option) == "table" and option.index
        if type(index) == "number" and index > count then count = math.floor(index) end
    end
    return count
end

local function _layout(dropdown, state)
    local height = _screen_height()
    if not height or type(dropdown.position) ~= "table" or type(dropdown.size) ~= "table" then
        return nil
    end
    local layout = Policy.dropdown_layout(dropdown.position[2], dropdown.size[2], height,
        _option_count(dropdown), 2 * _ui_scale(), dropdown.index, state.scroll)
    if layout then state.scroll = layout.scroll end
    return layout
end

local function _hide(option, state)
    if state.hidden[option] == nil then
        local previous = rawget(option, "disabled")
        state.hidden[option] = previous == nil and NIL or previous
    end
    option.visible = false
    option.disabled = true
    option.position = { OFFSCREEN, OFFSCREEN }
end

local function _reveal(option, state)
    local previous = state.hidden[option]
    if previous ~= nil then
        state.hidden[option] = nil
        if previous == NIL then
            option.disabled = nil
        else
            option.disabled = previous
        end
    end
end

-- Upstream never updates options while the list is closed (simple_ui.lua:2138),
-- so parked rows are restored here, from the dropdown's own update, the moment
-- the list closes or the option is switched off.
local function _reveal_all(state)
    for option in pairs(state.hidden) do _reveal(option, state) end
end

-- Runs before the instance's own update for the frame: the layout drives the
-- fitted hit box (hover test inside update_base) and every row placement.
function M.prepare(dropdown, state)
    if not dropdown.dropped or not M.enabled() then
        state.layout = nil
        state.was_dropped = dropdown.dropped == true
        _reveal_all(state)
        return nil
    end
    if not state.was_dropped then state.scroll = nil end -- a fresh open reveals the selection
    state.was_dropped = true
    local layout = _layout(dropdown, state)
    if layout and layout.max_scroll > 0 then
        local ok, bounds = pcall(dropdown.bounds, dropdown)
        local box = ok and type(bounds) == "table"
            and Policy.dropdown_bounds(layout, bounds[1], bounds[2], true) or nil
        local x, y = _cursor()
        if box and _inside(box, x, y) then
            local step = Policy.wheel_step(_wheel_y())
            if step ~= 0 then
                state.scroll = Policy.scroll_step(layout.scroll, step, layout.max_scroll)
                layout = _layout(dropdown, state)
            end
        end
    end
    state.layout = layout
    return layout
end

-- Called from the option's chained before_update. Returns true when the row
-- was placed from the fitted layout, false when upstream placement stands or
-- the row is scrolled out.
function M.place_option(option, dropdown, state)
    local layout = dropdown.dropped and state.layout or nil
    if not layout then
        _reveal(option, state)
        return false
    end
    local bottom = Policy.row_bottom(layout, option.index)
    if not bottom then
        _hide(option, state)
        return false
    end
    _reveal(option, state)
    option.position = { dropdown.position[1], bottom }
    option.visible = true
    return true
end

local function _chain_option(option, dropdown, state)
    local current = rawget(option, "before_update")
    if current == state.chained[option] then return end
    local previous = current
    local chained = function(self, ...)
        if type(previous) == "function" then previous(self, ...) end
        M.place_option(self, dropdown, state)
    end
    option.before_update = chained
    state.chained[option] = chained
end

local function _install_dropdown(dropdown)
    local state = states[dropdown]
    if not state then
        state = {
            scroll = nil,
            layout = nil,
            was_dropped = false,
            hidden = setmetatable({}, { __mode = "k" }),
            chained = setmetatable({}, { __mode = "k" }),
        }
        states[dropdown] = state
        local update = rawget(dropdown, "update")
        if type(update) == "function" then
            dropdown.update = function(self, ...)
                M.prepare(self, state)
                return update(self, ...)
            end
        end
        local extended = rawget(dropdown, "extended_bounds")
        if type(extended) == "function" then
            dropdown.extended_bounds = function(self)
                local layout = self.dropped and state.layout or nil
                if not layout then return extended(self) end
                local bounds = self.bounds(self)
                return Policy.dropdown_bounds(layout, bounds[1], bounds[2], true) or extended(self)
            end
        end
    end
    for _, option in pairs(dropdown.options) do
        if type(option) == "table" then _chain_option(option, dropdown, state) end
    end
    return state
end

function M.state_of(dropdown)
    return states[dropdown]
end

-- Called by the compat tick with SimpleUI.windows.list. Installs the
-- per-instance owners once per live dropdown (and re-chains an option callback
-- a consumer reassigned). Nothing is installed while the option is off, so an
-- untouched Simple UI stays byte-for-byte upstream in that case.
function M.tick(windows)
    if type(windows) ~= "table" or not M.enabled() then return 0 end
    local installed = 0
    for _, window in pairs(windows) do
        local widgets = type(window) == "table" and window.widgets
        if type(widgets) == "table" then
            for _, widget in pairs(widgets) do
                if type(widget) == "table" and widget._type == "dropdown"
                        and type(widget.options) == "table" then
                    _install_dropdown(widget)
                    installed = installed + 1
                end
            end
        end
    end
    return installed
end

local runtime_reported = false
M.rt_checks = {
    {
        name = "issue314_simple_ui_phase2",
        fn = function()
            local compat = mod._gut_simple_ui_compat
            if type(compat) ~= "table" or compat.dropdowns ~= M or (compat.phase or 0) < 2 then
                return "#314 phase-2 dropdown owner is not wired into the Simple UI compatibility tick"
            end
            local down = Policy.dropdown_layout(900, 30, 1080, 5, 2, 1, nil)
            if not down or down.direction ~= "down" or down.visible ~= 5
                    or Policy.row_bottom(down, 1) ~= 868 or Policy.row_bottom(down, 5) ~= 748 then
                return "#314 a list that fits below no longer opens downward in upstream order"
            end
            local up = Policy.dropdown_layout(60, 30, 1080, 8, 2, 1, nil)
            if not up or up.direction ~= "up" or up.visible ~= 8
                    or Policy.row_bottom(up, 8) ~= 92 or Policy.row_bottom(up, 1) ~= 302 then
                return "#314 a low dropdown no longer opens upward in reading order"
            end
            local long = Policy.dropdown_layout(300, 30, 400, 20, 2, 18, nil)
            local box = long and Policy.dropdown_bounds(long, 0, 100, true)
            if not long or long.visible ~= 9 or long.first ~= 10 or long.last ~= 18
                    or not box or box[3] ~= Policy.row_bottom(long, long.last) or box[4] ~= long.top
                    or Policy.row_bottom(long, 9) ~= nil then
                return "#314 a long list no longer scrolls to the selection with a hit box equal to its rows"
            end
            if Policy.scroll_step(long.scroll, 99, long.max_scroll) ~= long.max_scroll
                    or Policy.scroll_step(long.scroll, -99, long.max_scroll) ~= 0
                    or Policy.wheel_step(1) ~= -1 or Policy.wheel_step(-1) ~= 1 or Policy.wheel_step(0) ~= 0 then
                return "#314 wheel scrolling no longer clamps to the list"
            end
            if not runtime_reported then
                runtime_reported = true
                pcall(printf, "[gut:314] runtime phase=2 verdict=PASS down=%d up=%d scroll=%d-%d enabled=%s",
                    down.visible, up.visible, long.first, long.last, tostring(M.enabled()))
            end
        end,
    },
}

local register = rawget(mod, "_gut_rt_register")
if type(register) == "function" then
    for _, check in ipairs(M.rt_checks) do register(check.name, check.fn) end
end

return M
