-- Exact-item, per-hand customization session state.
--
-- This owner deliberately contains no rendering, persistence, or networking.
-- It only tracks the pending offhand choice shown by one customization screen,
-- the baseline to restore when Apply was not pressed, and the Apply marker.
-- Keeping those maps together prevents item-type keyed state from leaking a
-- choice between two weapon instances while preserving the existing callers.
local M = {}

local function _copy_hands(value)
    if type(value) ~= "table" then return false end
    local copy = {}
    for hand, option in pairs(value) do copy[hand] = option end
    return copy
end

function M.new(existing)
    existing = existing or {}

    local state = {
        selections = existing.selections or {},
        baselines = existing.baselines or {},
        committed = existing.committed or {},
    }

    -- Pre-v0.9.9.4 stored an option record directly at [backend_id]. Convert
    -- that one legacy shape in place while leaving the option record itself
    -- shared with the stable catalog, exactly as the historical code did.
    function state.migrate_legacy(backend_id)
        local value = backend_id and state.selections[backend_id]
        if type(value) ~= "table" then return false end
        if value.unit or value.intended_unit or value.la_armoury_key then
            state.selections[backend_id] = { left_hand_unit = value }
            return true
        end
        return false
    end

    -- `false` is intentional: it distinguishes a captured empty baseline from
    -- `nil`, which means no customization session was opened for this item.
    function state.snapshot(backend_id)
        if not backend_id then return nil end
        return _copy_hands(state.selections[backend_id])
    end

    function state.restore(backend_id, snapshot)
        if not backend_id then return false end
        if snapshot == false or snapshot == nil then
            state.selections[backend_id] = nil
        else
            state.selections[backend_id] = _copy_hands(snapshot)
        end
        return true
    end

    return state
end

return M
