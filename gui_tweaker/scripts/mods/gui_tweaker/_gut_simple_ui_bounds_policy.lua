-- Pure screen-containment policy for the external Simple UI compatibility
-- layer (#314). Engine-free for the repository's Lua 5.1 host tests.
local Policy = {}

local function _number(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function _clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

function Policy.confine(position, size, screen_width, screen_height)
    if type(position) ~= "table" or type(size) ~= "table"
        or not _number(position[1]) or not _number(position[2])
        or not _number(size[1]) or not _number(size[2])
        or not _number(screen_width) or not _number(screen_height)
        or screen_width <= 0 or screen_height <= 0 then
        return nil
    end

    local x
    if size[1] <= screen_width then
        x = _clamp(position[1], 0, screen_width - size[1])
    else
        -- An over-wide window cannot fit; keep its left edge reachable.
        x = 0
    end

    local y
    if size[2] <= screen_height then
        y = _clamp(position[2], 0, screen_height - size[2])
    else
        -- Simple UI's title/drag handle is at the window's top edge. Pin that
        -- edge to the top of the screen so an over-tall window remains movable.
        y = screen_height - size[2]
    end

    return {
        x = x,
        y = y,
        changed = x ~= position[1] or y ~= position[2],
    }
end

-- #314 phase 2: fitted dropdown lists.
--
-- Simple UI geometry is screen pixels with y growing upward; a widget's
-- position is its bottom-left corner and bounds are {x1, x2, y1, y2}
-- (simple_ui.lua:148-155). Upstream lays every option one row height below
-- the previous one, starting `border` below the closed control, and extends
-- the hit box by the whole list (simple_ui.lua:2128-2150, 2168-2176), so a
-- list near the bottom of the screen or with many options runs off-screen.
--
-- `bottom`/`height`: the closed control's bottom edge and row height (already
-- scaled by Simple UI). `border`: the upstream gap between the control and the
-- first row (2 * UIResolutionScale()). `selected`: the current option index.
-- `scroll`: an explicit first-row offset; nil means "opening", which reveals
-- the selected option. Rows keep ascending index order from top to bottom in
-- both directions; an upward list ends adjacent to the control's top edge.
function Policy.dropdown_layout(bottom, height, screen_height, count, border, selected, scroll)
    if not _number(bottom) or not _number(height) or height <= 0
            or not _number(screen_height) or screen_height <= 0
            or not _number(count) or count < 0 or count ~= math.floor(count) then
        return nil
    end
    border = _number(border) and border >= 0 and border or 0
    local top = bottom + height
    local below = math.max(0, math.floor((bottom - border) / height))
    local above = math.max(0, math.floor((screen_height - top - border) / height))
    local direction, capacity
    if below >= count then
        direction, capacity = "down", count
    elseif above >= count then
        direction, capacity = "up", count
    elseif below >= above then
        direction, capacity = "down", math.max(1, below)
    else
        direction, capacity = "up", math.max(1, above)
    end
    local visible = math.min(count, capacity)
    local max_scroll = math.max(0, count - visible)
    local offset
    if _number(scroll) then
        offset = _clamp(math.floor(scroll), 0, max_scroll)
    else
        offset = 0
        if _number(selected) and selected > visible then
            offset = _clamp(math.floor(selected) - visible, 0, max_scroll)
        end
    end
    return {
        direction = direction,
        bottom = bottom,
        top = top,
        row = height,
        border = border,
        count = count,
        visible = visible,
        scroll = offset,
        max_scroll = max_scroll,
        first = offset + 1,
        last = offset + visible,
    }
end

-- Bottom edge of the option whose upstream index is `index`, or nil when that
-- row is scrolled out of the fitted list.
function Policy.row_bottom(layout, index)
    if type(layout) ~= "table" or not _number(index)
            or index < layout.first or index > layout.last then
        return nil
    end
    local slot = index - layout.scroll
    if layout.direction == "down" then
        return layout.bottom - layout.border - layout.row * slot
    end
    return layout.top + layout.border + layout.row * (layout.visible - slot)
end

-- Hit box covering the closed control plus exactly the rendered rows. Upstream
-- also draws the dropdown background from this box (simple_ui.lua:1527-1531),
-- so the hit box and the visible rows cannot diverge.
function Policy.dropdown_bounds(layout, x1, x2, dropped)
    if type(layout) ~= "table" or not _number(x1) or not _number(x2) then return nil end
    if not dropped or layout.visible < 1 then
        return { x1, x2, layout.bottom, layout.top }
    end
    local extent = layout.border + layout.row * layout.visible
    if layout.direction == "down" then
        return { x1, x2, layout.bottom - extent, layout.top }
    end
    return { x1, x2, layout.bottom, layout.top + extent }
end

function Policy.scroll_step(scroll, delta, max_scroll)
    if not _number(scroll) or not _number(delta) or not _number(max_scroll) then return 0 end
    return _clamp(math.floor(scroll + delta), 0, math.max(0, math.floor(max_scroll)))
end

-- Mouse wheel y is positive for wheel-up and negative for wheel-down
-- (scripts/managers/debug/debug_manager.lua:289-296). Wheel-up reveals earlier
-- rows (scroll offset shrinks); wheel-down reveals later rows.
function Policy.wheel_step(wheel_y)
    if not _number(wheel_y) or wheel_y == 0 then return 0 end
    return wheel_y > 0 and -1 or 1
end

return Policy
