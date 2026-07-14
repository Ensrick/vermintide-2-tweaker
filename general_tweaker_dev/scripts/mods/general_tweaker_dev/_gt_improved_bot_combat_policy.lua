local M = {}

-- Nil means the VMF default has not materialized yet. Treat it as enabled so
-- adding #298's advanced controls preserves the old all-in-one behavior.
function M.feature_enabled(master, feature)
    return master == true and feature ~= false
end

function M.distance_sq(value, fallback)
    local distance = tonumber(value) or fallback
    if distance < 0 then distance = fallback end
    return distance * distance
end

return M
