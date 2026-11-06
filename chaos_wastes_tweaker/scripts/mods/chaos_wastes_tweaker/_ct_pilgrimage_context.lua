-- Shared, source-backed Pilgrimage Chamber context policy.
--
-- Vanilla DeusMechanism gives the chamber its own level (`morris_hub`) and
-- game mode (`inn_deus`).  The level key is the narrowest native signal: it is
-- false in Taal's Horn Keep (`inn_level`), on the route map
-- (`dlc_morris_map`), and in every playable mission.  Keep this module pure so
-- the boundary can be exercised by the offline Lua 5.1 suite.
local M = {
    LEVEL_KEY = "morris_hub",
}

function M.is_level(level_key)
    return level_key == M.LEVEL_KEY
end

function M.current_level_key(managers)
    local lth = managers and managers.level_transition_handler
    if not lth or type(lth.get_current_level_key) ~= "function" then
        return nil
    end
    local ok, level_key = pcall(lth.get_current_level_key, lth)
    if not ok or type(level_key) ~= "string" then
        return nil
    end
    return level_key
end

function M.is_current(managers, level_override)
    if level_override ~= nil then
        return M.is_level(level_override)
    end
    return M.is_level(M.current_level_key(managers))
end

return M
