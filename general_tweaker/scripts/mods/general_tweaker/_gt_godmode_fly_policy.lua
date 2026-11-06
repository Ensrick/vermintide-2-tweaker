-- _gt_godmode_fly_policy.lua -- exact fly-swarm overpowered gate for #548.
--
-- The two authored fly attacks enter the shared overpowered status through
-- StatusUtils.set_overpowered_network with these reason names. Keep the
-- catalogue deliberately closed: the shared overpowered state also serves
-- unrelated mechanics that Godmode must not suppress.
local Policy = {}

local FLY_REASONS = {
    slow_bomb = true,
    fly_bomb = true,
}

function Policy.is_fly_reason(reason)
    return FLY_REASONS[reason] == true
end

function Policy.should_block_entry(godmode_active, overpowered, reason,
        is_authored_fly_blob)
    return godmode_active == true
        and overpowered == true
        and Policy.is_fly_reason(reason)
        and is_authored_fly_blob == true
end

return Policy
