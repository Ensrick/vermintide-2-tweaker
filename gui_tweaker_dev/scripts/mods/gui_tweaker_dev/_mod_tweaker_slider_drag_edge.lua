-- _mod_tweaker_slider_drag_edge.lua - pure slider held/released transition policy.
--
-- Both Mod Tweaker presentations consume this owner. It deliberately knows
-- nothing about widgets, cursors, persistence, or sounds: adapters supply the
-- live held/cursor facts and consume the one-shot release edge.

local M = {}

function M.step(was_dragging, is_held, can_follow_cursor)
    local was = not not was_dragging
    local held = not not is_held
    local can_follow = held and not not can_follow_cursor

    local released = was and not held
    local next_dragging = held and (was or can_follow)

    -- `modal` intentionally includes the first released frame. That prevents
    -- the shared hotspot's stale release from reaching a different row.
    local modal = held or was
    return next_dragging, can_follow, released, modal
end

function M.is_modal(was_dragging, is_held)
    return not not (was_dragging or is_held)
end

return M
