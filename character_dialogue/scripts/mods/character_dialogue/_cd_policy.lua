local Policy = {}

function Policy.has_override(dialogue, overrides)
    for i = 1, dialogue and dialogue.sound_events_n or 0 do
        if overrides[dialogue.sound_events[i]] ~= nil then return true end
    end
    return false
end

function Policy.all_disabled(dialogue, overrides)
    local n = dialogue and dialogue.sound_events_n or 0
    if n < 1 then return false end
    for i = 1, n do
        if overrides[dialogue.sound_events[i]] ~= false then return false end
    end
    return true
end

-- Returns (index, used_override_path). next_index and vanilla_filter are
-- injected so the policy is engine-free and regression-testable.
function Policy.choose_index(dialogue, overrides, next_index, vanilla_filter)
    if not Policy.has_override(dialogue, overrides) then return nil, false end
    local fallback
    for _ = 1, dialogue.sound_events_n do
        local index = next_index()
        local state = overrides[dialogue.sound_events[index]]
        if state ~= false then
            fallback = fallback or index
            if state == true or vanilla_filter(index) then return index, true end
        end
    end
    return fallback, true
end

return Policy
