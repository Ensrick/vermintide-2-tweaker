-- Pure numeric-editor caret geometry for Mod Tweaker (issue #575).
-- Engine-facing measurement stays in _mod_tweaker_definitions.lua; these
-- functions accept measured advances so Lua 5.1 host tests can cover every
-- digit/sign/decimal shape without a renderer.

local M = {}

function M.centered_text_left(box_x, box_w, full_width, origin_x)
    return box_x + (box_w - full_width) / 2 - (origin_x or 0)
end

function M.caret_x(box_x, box_w, full_width, origin_x, prefix_width)
    return M.centered_text_left(box_x, box_w, full_width, origin_x)
        + (prefix_width or 0)
end

-- advances = { width(""), width(first char), ..., width(full text) }.
-- Return the insertion index whose measured boundary is nearest to click_x.
function M.nearest_index(click_x, text_left, advances)
    if type(advances) ~= "table" or #advances == 0 then return 0 end
    local relative = (click_x or text_left or 0) - (text_left or 0)
    local best_index = 0
    local best_distance = math.abs(relative - (advances[1] or 0))
    for i = 2, #advances do
        local distance = math.abs(relative - (advances[i] or 0))
        if distance < best_distance then
            best_index = i - 1
            best_distance = distance
        end
    end
    return best_index
end

return M
