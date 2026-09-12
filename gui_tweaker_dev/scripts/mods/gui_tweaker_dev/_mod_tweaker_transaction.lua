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

-- A provider may consume a bounded subset before the legacy notification path.
-- Preparation is read-only; its commit closure owns private state and ordering.
function Transaction.prepare(category, pending, owner, context)
    local provider, owner_id
    for id in pairs(pending) do
        assert(type(id) == "string", "invalid pending setting")
        local candidate, mid = owner(category, id)
        if provider and provider ~= candidate then return nil end
        provider, owner_id = candidate, mid
    end
    local api = provider and provider.mod_tweaker_settings_owner
    if api == nil then
        assert(not (context and context.metadata ~= nil), "profile owner protocol unavailable")
        return nil
    end
    assert(type(api) == "table" and api.version == 1 and type(api.prepare) == "function"
        and type(api.capture) == "function", "unsupported settings-owner protocol")
    local input = {}
    for id, value in pairs(pending) do input[id] = value end
    local plan = api.prepare(input, {
        kind = context and context.kind or "edit", owner_id = owner_id,
        metadata = context and context.metadata,
    })
    if plan == nil then return nil end
    assert(type(plan) == "table" and type(plan.handled) == "table"
        and type(plan.commit) == "function", "invalid settings-owner plan")
    local handled, count = {}, 0
    for id, accepted in pairs(plan.handled) do
        assert(type(id) == "string" and accepted == true and pending[id] ~= nil,
            "settings-owner plan escaped pending set")
        handled[id], count = true, count + 1
    end
    assert(count > 0, "empty settings-owner plan")
    return { handled = handled, count = count, commit = plan.commit, input = input }
end

local function commit_legacy(category, pending, owner, set_one)
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

function Transaction.commit(category, pending, owner, set_one, context)
    if type(pending) ~= "table" or next(pending) == nil then return 0, false, nil, true end
    local ok, plan
    if context and context.prepared then ok, plan = true, context.plan
    else ok, plan = pcall(Transaction.prepare, category, pending, owner, context) end
    if not ok then return 0, true, tostring(plan), false end
    if not plan then return commit_legacy(category, pending, owner, set_one) end
    for id, value in pairs(pending) do
        if plan.input[id] ~= value then return 0, true, "prepared profile draft changed", false end
    end
    for id in pairs(plan.input) do
        if pending[id] == nil then return 0, true, "prepared profile draft changed", false end
    end
    local committed, err = pcall(plan.commit)
    if not committed or err == false then
        return 0, true, tostring(err or "owner commit rejected"), false
    end
    local remainder = {}
    for id, value in pairs(pending) do if not plan.handled[id] then remainder[id] = value end end
    local count, _, failure, complete = commit_legacy(category, remainder, owner, set_one)
    return plan.count + count, true, failure, complete
end

return Transaction
