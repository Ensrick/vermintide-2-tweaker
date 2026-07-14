-- Pure bounded deduplication for the issue #354 WT/GUT loadout lifecycle trace.
local Core = {}

function Core.new(cap)
    return { cap = cap or 24, count = 0, seen = {} }
end

function Core.take(state, fields)
    if type(state) ~= "table" or state.count >= state.cap then return false end
    local key = table.concat({
        tostring(fields.phase), tostring(fields.career), tostring(fields.slot),
        tostring(fields.index), tostring(fields.backend_id), tostring(fields.item_key),
        tostring(fields.can_wield), tostring(fields.result),
    }, "|")
    if state.seen[key] then return false end
    state.seen[key] = true
    state.count = state.count + 1
    return true
end

return Core
