-- _wt_mutation_registry.lua -- WP-WT-07: one ordered registry for the owners
-- that write weapon templates, damage profiles or settings tables.
--
-- Every lifecycle event (state change, re-enable, rework master, peer parity
-- flip, CWV transition, settings batch) calls reconcile(reason), which applies
-- every owner in ascending `order`; revert_all() runs the owners' reverts in
-- the reverse order. A raising owner is logged and reported, and the others
-- still run. Pure: the caller injects the log function and the owner closures.
--
-- spec = { id = string, order = number, apply = function(reason),
--          revert = function() | nil, restart_bound = boolean }
-- An owner without revert must say restart_bound = true (its change lasts
-- until the game restarts); revert_all lists those ids.

local M = {}

function M.new(log)
    local owners, by_id, seq = {}, {}, 0
    local registry = {}

    local function report(fmt, ...)
        if log then pcall(log, fmt, ...) end
    end

    function registry.register(spec)
        if type(spec) ~= "table" or type(spec.id) ~= "string" or spec.id == "" then
            error("mutation registry: spec.id must be a non-empty string", 2)
        end
        if by_id[spec.id] then
            error("mutation registry: duplicate owner id " .. spec.id, 2)
        end
        if type(spec.order) ~= "number" or type(spec.apply) ~= "function" then
            error("mutation registry: " .. spec.id .. " needs a numeric order and an apply function", 2)
        end
        if spec.revert ~= nil and type(spec.revert) ~= "function" then
            error("mutation registry: " .. spec.id .. " revert must be a function", 2)
        end
        if spec.revert == nil and spec.restart_bound ~= true then
            error("mutation registry: " .. spec.id .. " needs revert or restart_bound = true", 2)
        end
        seq = seq + 1
        local owner = { id = spec.id, order = spec.order, apply = spec.apply,
            revert = spec.revert, restart_bound = spec.restart_bound == true, seq = seq }
        by_id[spec.id] = owner
        owners[#owners + 1] = owner
        table.sort(owners, function(a, b)
            if a.order ~= b.order then return a.order < b.order end
            return a.seq < b.seq
        end)
        return owner
    end

    function registry.reconcile(reason)
        local failed = {}
        for _, owner in ipairs(owners) do
            local ok, err = pcall(owner.apply, reason)
            if not ok then
                failed[#failed + 1] = owner.id
                report("apply %s failed (reason=%s): %s", owner.id, tostring(reason), tostring(err))
            end
        end
        return #failed == 0, failed
    end

    function registry.revert_all()
        local failed, restart_bound = {}, {}
        for i = #owners, 1, -1 do
            local owner = owners[i]
            if owner.revert then
                local ok, err = pcall(owner.revert)
                if not ok then
                    failed[#failed + 1] = owner.id
                    report("revert %s failed: %s", owner.id, tostring(err))
                end
            else
                restart_bound[#restart_bound + 1] = owner.id
            end
        end
        return #failed == 0, restart_bound, failed
    end

    function registry.ids()
        local ids = {}
        for i, owner in ipairs(owners) do ids[i] = owner.id end
        return ids
    end

    return registry
end

return M
