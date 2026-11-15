local Policy = {}

-- Preserve the false member of the persistent true/false/nil override.  The
-- usual Lua `and`/`or` pseudo-ternary cannot return false from its true branch.
function Policy.parse_override_state(state)
    if state == "enable" then return true end
    if state == "disable" then return false end
    return nil
end

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

-- WP-COS-03 (#605): selection for a group that has an override, driving the
-- real index source the way vanilla's get_filtered_dialogue_event_index does
-- (dialogue_queries.lua:110-132). The FIRST draw passes no wrap argument, so a
-- fresh group (randomize_indexes_n = 0) builds its shuffle; with wrap_around =
-- true alone vanilla only resets the counter (:85-107) and every index is nil.
-- Explicit enable is accepted, explicit disable is never returned, inherited
-- lines use the vanilla filter. Returns the accepted index, else the first
-- non-disabled index seen, else nil (every line disabled or no index drawn).
function Policy.select_index(dialogue, overrides, queries, context, global_filters)
    local index, wrapped = queries.get_dialogue_event_index(dialogue)
    local accepted, fallback
    for _ = 1, dialogue.sound_events_n do
        local state = index and overrides[dialogue.sound_events[index]]
        if index and (state == true
                or (state == nil and queries.filter_sound_event(dialogue, index, context, global_filters))) then
            accepted = index
            break
        end
        if index and state ~= false then fallback = fallback or index end
        local did_wrap
        index, did_wrap = queries.get_dialogue_event_index(dialogue, true)
        wrapped = wrapped or did_wrap
    end
    if wrapped then queries.build_randomized_indexes(dialogue) end
    return accepted or fallback
end

return Policy
