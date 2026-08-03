-- Pure decision policy for issue 413's Adventure Shadow adapter.
-- Engine-free so sender-side wire safety can be tested without launching VT2.

local M = {}

M.ADVENTURE_RADIUS = 6

-- Vanilla Ulgu wind value: WindSettings.shadow.damage_taken is -0.8 at every
-- difficulty and wind strength (wind_settings.lua:1615+). The adapter applies
-- this only for the lifetime of an Adventure Shadow session (issue 1123).
M.ADVENTURE_DAMAGE_TAKEN = -0.8

function M.plan(is_shadow, weave_wind_active, capability_parity, adapter_ready)
    if not is_shadow then
        return "passthrough"
    end
    if weave_wind_active == true then
        return "native_weave"
    end
    if adapter_ready ~= true then
        return "drop_adapter_unavailable"
    end
    if capability_parity ~= true then
        return "drop_peer_capability"
    end
    return "adventure_adapter"
end

return M
