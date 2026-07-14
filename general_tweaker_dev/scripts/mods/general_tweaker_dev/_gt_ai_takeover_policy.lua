-- _gt_ai_takeover_policy.lua -- pure validation/state policy for issue #247.
--
-- Runtime orchestration remains in _gt_ai_takeover.lua.  Keeping the admission
-- and request-authentication rules here makes the dangerous edges executable
-- under the vendored Lua 5.1 test host without simulating Stingray objects.

local Policy = {}

Policy.SUPPORTED_MODES = {
    adventure = true,
    deus = true,
    weave = true,
}

function Policy.mode_supported(mode_key)
    return type(mode_key) == "string" and Policy.SUPPORTED_MODES[mode_key] == true
end

function Policy.has_free_slot(num_used_slots, num_slots)
    return type(num_used_slots) == "number"
        and type(num_slots) == "number"
        and num_used_slots >= 0
        and num_slots > 0
        and num_used_slots < num_slots
end

function Policy.has_takeover_capacity(num_used_slots, num_slots, has_displaceable_bot)
    return Policy.has_free_slot(num_used_slots, num_slots) or has_displaceable_bot == true
end

function Policy.validate_begin(context)
    context = context or {}

    if not context.is_server then return false, "must run on host" end
    if not Policy.mode_supported(context.mode_key) then return false, "unsupported game mode" end
    if not context.player_exists then return false, "player not found" end
    if context.is_bot then return false, "player is already a bot" end
    if not context.unit_alive then return false, "player unit is not alive" end
    if not context.has_party_slot then return false, "no party slot" end
    if not Policy.has_takeover_capacity(context.num_used_slots, context.num_slots,
        context.has_displaceable_bot) then
        return false, "party has no free or replaceable bot slot"
    end
    if not context.has_profile then return false, "no synchronized profile" end
    if not context.has_game_mode_api then return false, "game mode takeover API unavailable" end

    return true
end

-- A request can only address the authenticated VMF sender.  local_player_id 1
-- is the only VT2 network player used by this feature; rejecting every other
-- value prevents a client from targeting another local player record.
function Policy.authenticate_request(sender_peer_id, claimed_peer_id, local_player_id)
    if sender_peer_id == nil then return false, "missing sender" end
    if claimed_peer_id ~= nil and claimed_peer_id ~= sender_peer_id then
        return false, "peer claim does not match sender"
    end
    if local_player_id ~= nil and local_player_id ~= 1 then
        return false, "unsupported local player id"
    end
    return true, sender_peer_id, 1
end

function Policy.validate_intent(want_bot)
    if type(want_bot) ~= "boolean" then
        return false, "want_bot must be boolean"
    end
    return true
end

return Policy
