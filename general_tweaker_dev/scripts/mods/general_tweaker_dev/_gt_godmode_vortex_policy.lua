-- _gt_godmode_vortex_policy.lua -- pure Blightstorm capture gate for #1009.
--
-- This owns only the exact Godmode/entry/source truth table. Engine source
-- classification stays in the caller so the policy remains deterministic and
-- directly testable under the repository's Lua 5.1 runner.
local Policy = {}

function Policy.should_block_entry(godmode_active, in_vortex, is_blightstorm)
    return godmode_active == true
        and in_vortex == true
        and is_blightstorm == true
end

return Policy
