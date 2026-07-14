-- Pure policy for issue #365. This module deliberately has no engine globals so
-- the all-team gate can be exercised by the offline Lua harness.
local Policy = {}

function Policy.team_ready(observations, max_stacks, minimum_remaining_fraction)
    if type(observations) ~= "table" or #observations == 0 then
        return false
    end

    max_stacks = tonumber(max_stacks)
    minimum_remaining_fraction = tonumber(minimum_remaining_fraction)
    if not max_stacks or not minimum_remaining_fraction then
        return false
    end

    for i = 1, #observations do
        local member = observations[i]
        local defence_remaining = type(member) == "table"
            and tonumber(member.defence_remaining_fraction) or -1
        local attack_remaining = type(member) == "table"
            and tonumber(member.attack_remaining_fraction) or -1
        if type(member) ~= "table"
                or tonumber(member.defence_stacks) ~= max_stacks
                or tonumber(member.attack_stacks) ~= max_stacks
                or defence_remaining <= minimum_remaining_fraction
                or attack_remaining <= minimum_remaining_fraction then
            return false
        end
    end

    return true
end

return Policy
