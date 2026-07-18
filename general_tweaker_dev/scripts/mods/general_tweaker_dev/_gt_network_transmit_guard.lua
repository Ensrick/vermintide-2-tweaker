local mod = get_mod("gt_dev")
local VoipPolicy = mod:dofile("scripts/mods/general_tweaker_dev/_gt_voip_disconnect_policy")
local voip_warned = false

local function warn_voip_once(reason)
    if voip_warned then
        return
    end

    voip_warned = true
    mod:info("[gt:731][WARN] Dropped stale VOIP leave-room RPC after the server channel closed (%s).", reason)
end

-- Single owner for GT's client-to-server transmit decisions. Feature modules
-- publish narrow predicates; they do not stack hooks on this engine seam.
mod:hook("NetworkTransmit", "send_rpc_server", function(func, self, rpc_name, ...)
    local noclip_guard = mod._gt_noclip_server_rpc_guard
    if noclip_guard and noclip_guard(rpc_name, ...) then
        return
    end

    if rpc_name ~= "rpc_voip_room_request" then
        return func(self, rpc_name, ...)
    end

    local peer_to_channel = rawget(_G, "PEER_ID_TO_CHANNEL")

    if VoipPolicy.should_drop_server_rpc(
        rpc_name,
        self and self.is_server,
        self and self.server_peer_id,
        peer_to_channel
    ) then
        warn_voip_once(self and self.server_peer_id and "channel_missing" or "server_peer_missing")
        return
    end

    -- The channel can close between the preflight read and the engine RPC call.
    -- Limit the race guard to this teardown-only VOIP message and rethrow every
    -- unrelated failure unchanged.
    local result = { pcall(func, self, rpc_name, ...) }

    if result[1] then
        -- NetworkTransmit.send_rpc_server has no return contract.
        return
    end

    if VoipPolicy.is_closed_channel_error(tostring(result[2])) then
        warn_voip_once("channel_closed_during_send")
        return
    end

    error(result[2], 0)
end)
