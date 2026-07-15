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

return Policy
