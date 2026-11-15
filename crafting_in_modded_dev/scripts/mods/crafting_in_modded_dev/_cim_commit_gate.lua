--[[
#80 (WP-CIM-02): the BackendManagerPlayFab.commit gate.

While either forge is open, commits stay suppressed so simulated forge
mutations do not reach PlayFab (OD-CIM-05). A commit that carries a
completion callback always reaches vanilla: vanilla registers the callback
and fires it from _check_current_commit
(Vermintide-2-Source-Code/scripts/managers/backend_playfab/backend_manager_playfab.lua:933-937,
playfab_mirror_base.lua:2714-2752, :1847-1868). The end-of-mission screen
(scripts/game_state/state_ingame_running.lua:718-737) and the mechanism switch
(scripts/managers/game_mode/game_mechanism_manager.lua:523-528) are activated
inside such callbacks, so dropping one soft-locks the game.

Pure: no engine globals, no hooks. The entry owns the single commit hook.
]]

local M = {}

function M.should_suppress(forge_active, commit_complete_callback)
    return forge_active == true and commit_complete_callback == nil
end

function M.hook(func, self, skip_queue, commit_complete_callback, forge_active)
    if M.should_suppress(forge_active, commit_complete_callback) then
        return
    end
    return func(self, skip_queue, commit_complete_callback)
end

-- Body of the rt check issue_cim_commit_callback_preserved: drives M.hook with
-- a recording function for the three cases. nil = pass, else an error string.
function M.self_check()
    local calls = 0
    local function record(_, _, cb)
        calls = calls + 1
        return cb and "with-callback" or "no-callback"
    end
    local cb = function() end
    if M.hook(record, nil, true, cb, true) ~= "with-callback" or calls ~= 1 then
        return "forge open: a commit with a callback did not reach vanilla"
    end
    if M.hook(record, nil, true, nil, true) ~= nil or calls ~= 1 then
        return "forge open: a callback-less commit was not suppressed"
    end
    if M.hook(record, nil, true, nil, false) ~= "no-callback" or calls ~= 2 then
        return "forge closed: a commit did not reach vanilla"
    end
    return nil
end

return M
