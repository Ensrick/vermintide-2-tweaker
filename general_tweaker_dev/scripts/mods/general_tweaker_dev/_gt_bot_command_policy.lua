-- Pure policy for issue #359's host-side bot command wheel.
-- Engine-free so event decoding and time bounds can be tested offline.

local P = {}

P.EVENTS = {
    vs_social_wheel_dark_pact_general_attack = "attack_pinged",
    vs_social_wheel_dark_pact_general_group_up = "group_up",
    vs_social_wheel_dark_pact_general_cover_me = "cover_me",
    vs_social_wheel_dark_pact_general_wait = "hold_here",
}

P.ATTACK_DURATION_S = 10
P.GROUP_DURATION_S = 8
P.COVER_DURATION_S = 12
P.HOLD_DURATION_S = 30
P.HOLD_RADIUS_M = 4

function P.command_for_event(event_name)
    return type(event_name) == "string" and P.EVENTS[event_name] or nil
end

function P.is_active(now, until_t)
    return type(now) == "number" and type(until_t) == "number" and now < until_t
end

function P.is_host_sender(sender_peer_id, local_peer_id)
    return sender_peer_id ~= nil and local_peer_id ~= nil and sender_peer_id == local_peer_id
end

function P.nearest(entries)
    local best
    for i = 1, #(entries or {}) do
        local entry = entries[i]
        if entry and type(entry.distance_sq) == "number"
                and (not best or entry.distance_sq < best.distance_sq) then
            best = entry
        end
    end
    return best and best.unit or nil
end

return P
