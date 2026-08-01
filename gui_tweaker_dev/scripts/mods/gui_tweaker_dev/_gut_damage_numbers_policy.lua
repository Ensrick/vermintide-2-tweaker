-- Pure presentation policy for floating damage numbers.
--
-- The vanilla helper derives font size directly from damage:
--   40 + damage * 0.75 * font_override
-- NetworkConstants.damage.max is the largest single damage value the engine
-- transports.  Preserve vanilla scaling through that boundary, then hold the
-- damage-derived part of the font size at the boundary while leaving the text
-- value untouched.

local M = {}

function M.font_override(damage_amount, max_network_damage)
    if type(damage_amount) ~= "number" or damage_amount <= 0 then
        return 1
    end
    if type(max_network_damage) ~= "number" or max_network_damage <= 0 then
        return 1
    end
    if damage_amount <= max_network_damage then
        return 1
    end
    return max_network_damage / damage_amount
end

function M.vanilla_text_size(damage_amount, font_override)
    return 40 + damage_amount * 0.75 * (font_override or 1)
end

return M
