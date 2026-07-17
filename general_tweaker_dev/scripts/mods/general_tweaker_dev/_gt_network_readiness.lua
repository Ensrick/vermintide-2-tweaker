-- Network-lifecycle reads shared by update consumers that can tick while the
-- title/loading state is still constructing the network backend.

local M = {}

function M.local_player(managers)
    local player_manager = managers and managers.player
    if type(player_manager) ~= "table"
            or type(player_manager.local_player_safe) ~= "function" then
        return nil
    end

    local state = managers.state
    local network = state and state.network
    if type(network) ~= "table" or type(network.game) ~= "function" then
        return nil
    end

    local game_ok, game = pcall(network.game, network)
    if not game_ok or not game then return nil end

    -- `local_player_safe` still reaches Network.peer_id() after its game()
    -- guard. During backend hand-off that native call can throw even though a
    -- game object was briefly visible, so the final read must remain guarded.
    local player_ok, player = pcall(player_manager.local_player_safe, player_manager)
    if not player_ok then return nil end
    return player
end

return M
