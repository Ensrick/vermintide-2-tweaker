-- Pure policy for #659. Kept engine-free so the owner/setting matrix and the
-- extension mutation can be exercised by the offline Lua suite.

local M = {}

function M.should_clear(is_bot, bots_in_keep, pets_forbidden)
    return pets_forbidden == true and (is_bot ~= true or bots_in_keep == true)
end

function M.reconcile(extension, bots_in_keep)
    local player = extension and extension._player
    if not player then
        return false, nil, nil, "unknown"
    end

    local before = extension._pets_forbidden_in_level
    local is_bot = player.bot_player == true
    local changed = M.should_clear(is_bot, bots_in_keep, before)

    if changed then
        extension._pets_forbidden_in_level = false
    end

    return changed, before, extension._pets_forbidden_in_level,
        is_bot and "bot" or "human"
end

return M
