-- _mod_tweaker_transaction.lua - bounded pending-setting commits.
--
-- Commits one owner's pending values through VMF. Owners that explicitly
-- provide `on_settings_batch_changed(ids)` receive silent persisted writes
-- followed by one completion callback; every other owner retains the stock
-- per-setting notification path. The module is engine-free so offline Lua 5.1
-- tests can lock the transaction contract.
--
-- Owned by: both Mod Tweaker view implementations. Consumed via: mod:dofile.

local Transaction = {}

function Transaction.commit(category, pending, owner, set_one)
    if type(pending) ~= "table" or next(pending) == nil then
        return 0, false, nil, true
    end

    local ids = {}
    local batch_owner
    local batch_capable = true
    for setting_id in pairs(pending) do
        local mod_obj = owner(category, setting_id)
        if not mod_obj or type(mod_obj.set) ~= "function"
                or type(mod_obj.on_settings_batch_changed) ~= "function" then
            batch_capable = false
            break
        end
        if batch_owner and batch_owner ~= mod_obj then
            batch_capable = false
            break
        end
        batch_owner = mod_obj
        ids[#ids + 1] = setting_id
    end

    if not batch_capable then
        local count = 0
        for setting_id, value in pairs(pending) do
            local ok, err = pcall(set_one, category, setting_id, value)
            if not ok then
                return count, false, tostring(err), false
            end
            count = count + 1
        end
        return count, false, nil, true
    end

    table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
    for i = 1, #ids do
        local setting_id = ids[i]
        -- VMFMod.set(..., false) still clones/persists the value and marks user
        -- settings dirty; it only suppresses the synchronous per-setting event.
        local ok, err = pcall(batch_owner.set, batch_owner,
            setting_id, pending[setting_id], false)
        if not ok then return i - 1, true, tostring(err), false end
    end
    -- VMF lifecycle callbacks use dot-style event functions (no implicit self).
    local ok, err = pcall(batch_owner.on_settings_batch_changed, ids)
    if not ok then
        return #ids, true, tostring(err), false
    end
    return #ids, true, nil, true
end

return Transaction
