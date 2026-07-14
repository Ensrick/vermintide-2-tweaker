-- Pure layout/visibility policy for issue #381. Kept engine-free for offline QA.
local Policy = {}

Policy.CANVAS_WIDTH = 1920
Policy.RIGHT_MARGIN = 20
Policy.TOP_Y = 1035
Policy.PADDING = 8
Policy.MAX_TEXT_WIDTH = 600

function Policy.visible(godmode_enabled)
    return godmode_enabled == true
end

function Policy.layout(text_width)
    text_width = tonumber(text_width) or 0
    if text_width < 0 then text_width = 0 end
    if text_width > Policy.MAX_TEXT_WIDTH then text_width = Policy.MAX_TEXT_WIDTH end

    local text_x = Policy.CANVAS_WIDTH - Policy.RIGHT_MARGIN - text_width
    return {
        text_x = text_x,
        text_y = Policy.TOP_Y,
        background_x = text_x - Policy.PADDING,
        background_y = Policy.TOP_Y - Policy.PADDING,
        background_width = text_width + Policy.PADDING * 2,
        background_height = 40,
    }
end

return Policy
