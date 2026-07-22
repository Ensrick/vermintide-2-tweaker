-- Issue #299: bounded lifecycle policy for Chest-of-Trials rescue ordering.
--
-- Engine-free on purpose. Runtime owns unit/network operations; this module pins
-- the only safe order:
--   1. wait until a dead player has spawned at an assisted-respawn beacon;
--   2. move the still-disabled player to the living team;
--   3. only after that move succeeds, begin assisted-respawn recovery;
--   4. after the server reports the player alive, verify retention once and
--      allow one corrective move if the recovery transition displaced them.
local M = {}

M.MARKER = "ct299:move_before_free_v1"
M.TIMEOUT_SECONDS = 30
M.MAX_ERRORS = 4
M.MAX_CORRECTIONS = 1
M.RETAIN_DISTANCE_SQ = 9 -- within three metres of the chosen teammate

function M.key(peer_id, local_player_id)
    if peer_id == nil or local_player_id == nil then return nil end
    return tostring(peer_id) .. "/" .. tostring(local_player_id)
end

function M.new_entry(peer_id, local_player_id, player, anchor, now)
    local key = M.key(peer_id, local_player_id)
    if not key or type(anchor) ~= "table"
        or type(anchor.x) ~= "number" or type(anchor.y) ~= "number"
        or type(anchor.z) ~= "number" then
        return nil
    end
    local deadline = type(now) == "number" and now + M.TIMEOUT_SECONDS or nil
    return {
        key = key,
        peer_id = peer_id,
        lpid = local_player_id,
        player = player,
        anchor = { x = anchor.x, y = anchor.y, z = anchor.z },
        deadline = deadline,
        elapsed = 0,
        errors = 0,
        corrections = 0,
        moved = false,
        freed = false,
    }
end

-- Snapshot fields: alive, awaiting, health_alive, retained, timed_out.
-- `move_then_free` is deliberately atomic from the policy's perspective: the
-- runtime may set moved/freed only after each corresponding operation succeeds.
function M.next_action(entry, snapshot)
    if type(entry) ~= "table" or type(snapshot) ~= "table" then return "drop" end
    if snapshot.timed_out or (entry.errors or 0) >= M.MAX_ERRORS then return "drop" end
    if not snapshot.alive then return "wait_unit" end
    if not entry.moved then
        return snapshot.awaiting and "move_then_free" or "wait_awaiting"
    end
    if not entry.freed then return "free" end
    if not snapshot.health_alive then return "wait_recovery" end
    if snapshot.retained == false and (entry.corrections or 0) < M.MAX_CORRECTIONS then
        return "correct_once"
    end
    return "complete"
end

return M
