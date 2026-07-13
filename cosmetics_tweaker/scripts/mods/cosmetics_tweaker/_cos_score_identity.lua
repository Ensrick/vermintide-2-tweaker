-- Pure score-lineup identity resolver (#513).
--
-- ScoreboardHelper gives bots their owning host's peer_id, so peer_id alone
-- identifies the network owner, not necessarily the cosmetic wearer. Only a
-- player-controlled row may bridge into the human-only per-peer LA store.
local M = {}

function M.resolve_snapshot(profile_index, career_index, scores)
    if profile_index == nil or career_index == nil or type(scores) ~= "table" then
        return nil, "score_snapshot_miss"
    end

    for _, player_data in pairs(scores) do
        if type(player_data) == "table"
            and player_data.profile_index == profile_index
            and player_data.career_index == career_index
        then
            if player_data.is_player_controlled ~= true then
                local source = player_data.is_player_controlled == false
                    and "score_snapshot_bot" or "score_snapshot_untrusted"
                return nil, source
            end
            if player_data.peer_id and player_data.local_player_id ~= nil then
                return player_data.peer_id, "score_snapshot"
            end
            return nil, "score_snapshot_untrusted"
        end
    end

    return nil, "score_snapshot_miss"
end

-- A cross-skeleton mismatch proves stale human state only when the spawned
-- player itself is human. Host-owned bots deliberately share the host peer;
-- their different skeleton must not invalidate the host's cosmetic store.
function M.should_purge_mismatch(is_player_controlled)
    return is_player_controlled == true
end

return M
