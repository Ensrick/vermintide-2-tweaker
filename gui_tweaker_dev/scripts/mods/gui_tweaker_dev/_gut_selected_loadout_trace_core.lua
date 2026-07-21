-- Pure bounded trace policy for issue #375.  The engine-facing mirror module owns
-- caller discovery and printf; this helper owns deduplication and the hard memory cap.

local M = {}

local function _text(v)
    if v == nil then return "<nil>" end
    return tostring(v)
end

function M.new(capacity)
    local cap = math.max(1, tonumber(capacity) or 128)
    local seen = {}
    local order = {}

    local trace = {}

    function trace:record(snapshot)
        snapshot = snapshot or {}
        local key = table.concat({
            _text(snapshot.career),
            _text(snapshot.slot),
            _text(snapshot.requested_index),
            _text(snapshot.resolved_index),
            _text(snapshot.caller),
        }, "\0")
        local signature = table.concat({
            _text(snapshot.selected_index),
            _text(snapshot.row_melee),
            _text(snapshot.row_ranged),
            _text(snapshot.selected_melee),
            _text(snapshot.selected_ranged),
            _text(snapshot.served_value),
            _text(snapshot.source),
        }, "\0")

        if seen[key] == signature then return false end
        if seen[key] == nil then
            if #order >= cap then
                local oldest = table.remove(order, 1)
                seen[oldest] = nil
            end
            order[#order + 1] = key
        end
        seen[key] = signature
        return true
    end

    function trace:size()
        return #order
    end

    return trace
end

return M
