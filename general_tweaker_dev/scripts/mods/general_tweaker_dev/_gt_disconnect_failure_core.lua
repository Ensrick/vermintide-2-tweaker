-- _gt_disconnect_failure_core.lua -- pure transition policy for issue #753.
--
-- Keeps the three observed service states and their change predicates free of
-- VMF/Stingray dependencies so bounded disconnect diagnostics can be tested
-- offline.  The labels describe measurements, not an inferred outage cause.
--
-- Owned by: _gt_diag_disconnect_failure.lua. Consumed via: mod:dofile.

local M = {}

function M.bool_label(value)
    if value == true then return "yes" end
    if value == false then return "no" end
    return "unknown"
end

function M.classify(steam_connected, backend_disconnected, network_failed)
    local observed = {}

    if steam_connected == false then
        observed[#observed + 1] = "steam_client_unavailable"
    end
    if backend_disconnected == true then
        observed[#observed + 1] = "playfab_backend_disconnected"
    end
    if network_failed then
        if steam_connected == true and backend_disconnected == false then
            observed[#observed + 1] = "p2p_failed_steam_backend_report_live"
        else
            observed[#observed + 1] = "p2p_failed"
        end
    end

    if #observed == 0 then
        return "insufficient_state"
    end

    return table.concat(observed, "+")
end

function M.steam_transition(previous, current)
    return current == false and previous ~= false
        or current == true and previous == false
end

function M.backend_disconnected_transition(previous, current)
    return previous ~= true and current == true
end

function M.network_failure_transition(before_reason, after_reason, before_channel, after_channel)
    -- NetworkClient.update can also assign unrelated failures such as
    -- eac_authorize_failed.  Do not report those as P2P evidence.  The two
    -- source-backed transport edges are a channel becoming disconnected and
    -- the connecting timeout assigning the exact broken_connection reason.
    if after_channel == "disconnected" and before_channel ~= "disconnected" then
        return true
    end

    return after_reason == "broken_connection" and after_reason ~= before_reason
end

return M
