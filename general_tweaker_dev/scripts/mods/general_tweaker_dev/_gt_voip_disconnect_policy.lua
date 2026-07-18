local Policy = {}

function Policy.should_drop_server_rpc(rpc_name, is_server, server_peer_id, peer_to_channel)
    if rpc_name ~= "rpc_voip_room_request" or is_server then
        return false
    end

    if server_peer_id == nil then
        return true
    end

    if type(peer_to_channel) ~= "table" then
        return false
    end

    return type(rawget(peer_to_channel, server_peer_id)) ~= "number"
end

function Policy.is_closed_channel_error(message)
    return type(message) == "string"
        and message:find("Channel must be an integer", 1, true) ~= nil
end

return Policy
