-- Pure call-boundary policy for the vanilla bot pose omission (#232).
local Policy = {}

function Policy.resolve_is_bot(spawn_depth, slot_name, is_bot)
    if (tonumber(spawn_depth) or 0) > 0 and slot_name == "slot_pose"
            and is_bot == nil then
        return true, true
    end
    return is_bot, false
end

return Policy
