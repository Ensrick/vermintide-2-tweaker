-- Pure policy for issue 430's Cursed Adventure hot-join containment.
-- Kept engine-free so the pre-game-session boundary can be regression tested
-- without launching Vermintide 2.

local M = {}

-- nil means the host could not prove the pending-peer set. Callers must treat
-- that as unsafe; absence of evidence is not a session contract.
function M.has_pending_remote(peer_state_machines, local_peer_id, player_for_peer)
    if type(peer_state_machines) ~= "table"
       or type(local_peer_id) ~= "string"
       or type(player_for_peer) ~= "function" then
        return nil
    end

    for peer_id in pairs(peer_state_machines) do
        if peer_id ~= local_peer_id and not player_for_peer(peer_id) then
            return true, peer_id
        end
    end

    return false
end

function M.can_arm(parity_confirmed, pending_remote)
    return parity_confirmed == true and pending_remote == false
end

function M.allow_join(vanilla_joinable, curse_session_locked)
    return vanilla_joinable == true and curse_session_locked ~= true
end

return M
