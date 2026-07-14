local M = {}

function M.new(cap)
    return { cap = math.max(1, tonumber(cap) or 24), count = 0, seen = {} }
end

function M.accept(state, surface, subject, portrait, resolution)
    if type(state) ~= "table" or state.count >= state.cap then return false end
    local key = table.concat({ tostring(surface), tostring(subject), tostring(portrait), tostring(resolution) }, "|")
    if state.seen[key] then return false end
    state.seen[key] = true
    state.count = state.count + 1
    return true
end

return M
