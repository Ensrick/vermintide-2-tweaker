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

-- (#938) Burst aggregation. The engine transports at most
-- NetworkConstants.damage.max per health-extension call: an above-boundary hit
-- is split into a same-frame burst of max-size add_damage chunks plus one
-- remainder (damage_utils.lua:1969-1981), and TrainingDummyHealthExtension
-- .add_damage feeds each PRE-SPLIT chunk straight into
-- add_unit_floating_damage_numbers (training_dummy_health_extension.lua:70).
-- So the popup chokepoint only ever sees post-split values and the font bound
-- above never engages. These helpers fold one burst (same key = same unit and
-- damage type, inside the window) back into a single popup carrying the summed
-- value; the caller emits it once the window elapses.
M.AGGREGATION_WINDOW = 0.1

-- One aggregation step over `groups` (key -> pending popup). A chunk inside the
-- window merges into the pending popup; a chunk outside it starts a fresh popup
-- and returns the displaced one so the caller can emit it first.
function M.accumulate(groups, key, damage_amount, is_critical_strike, t, window)
    window = window or M.AGGREGATION_WINDOW
    local entry = groups[key]
    if entry and (t - entry.first_t) < window then
        entry.amount = entry.amount + damage_amount
        entry.is_critical_strike = entry.is_critical_strike
            or (is_critical_strike and true or false)
        return entry, nil
    end
    local fresh = {
        amount = damage_amount,
        is_critical_strike = is_critical_strike and true or false,
        first_t = t,
    }
    groups[key] = fresh
    return fresh, entry
end

-- True when a pending popup's aggregation window elapsed and it should emit.
function M.is_due(entry, t, window)
    window = window or M.AGGREGATION_WINDOW
    return (t - entry.first_t) >= window
end

return M
