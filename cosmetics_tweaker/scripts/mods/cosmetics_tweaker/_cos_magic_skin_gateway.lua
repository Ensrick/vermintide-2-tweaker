-- Issue #48: pure visibility policy for the custom-glow gateway.
-- Magic-family skins stay hidden by default, but one explicit setting can
-- reveal them so the player can select one and use the contextual Edit Glow
-- control. The currently equipped skin always remains visible.

local M = {}

M.FAMILIES = { weaves = true, shyish = true }

function M.filter(widgets, current_skin_key, family_for_skin, show_magic)
    if type(widgets) ~= "table" then return widgets, 0 end
    if show_magic == true then return widgets, 0 end

    local kept, removed = {}, 0
    for _, widget in ipairs(widgets) do
        local skin_key = widget and widget.content and widget.content.skin_key
        local family = skin_key and type(family_for_skin) == "function"
            and family_for_skin(skin_key) or nil
        if skin_key ~= current_skin_key and M.FAMILIES[family] then
            removed = removed + 1
        else
            kept[#kept + 1] = widget
        end
    end

    if removed > 0 then
        -- Vanilla HeroWindowItemCustomization illusion-row geometry.
        local width, spacing = 51, -5
        local total_width = #kept > 0 and (-spacing + #kept * (width + spacing)) or 0
        local x_offset = width / 2
        for _, widget in ipairs(kept) do
            if widget.offset then
                widget.offset[1] = -total_width / 2 + x_offset
                x_offset = x_offset + width + spacing
            end
        end
    end
    return kept, removed
end

return M
