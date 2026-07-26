-- Bounded VMF setting transaction for Weapon Tweaker issue #445.
-- The policy owns membership; this adapter owns persistence and one apply.

local M = {}

function M.new(mod, policy, apply_live)
    local runtime = { _batch = false }

    local function snapshot()
        local current = {}
        for i = 1, #policy.LEAF_IDS do
            local id = policy.LEAF_IDS[i]
            current[id] = mod:get(id) and true or false
        end
        current[policy.MASTER_ID] = mod:get(policy.MASTER_ID) and true or false
        return current
    end

    local function write(changes)
        runtime._batch = true
        local ok, err = pcall(function()
            for i = 1, #changes do
                mod:set(changes[i].id, changes[i].value, false)
            end
        end)
        runtime._batch = false
        if not ok then
            mod:warning("[wt:445] family setting batch failed: %s", tostring(err))
            return false
        end
        return true
    end

    function runtime:is_batching()
        return self._batch == true
    end

    function runtime:on_master_changed(setting_id)
        if setting_id ~= policy.MASTER_ID then return false end
        local enabled = mod:get(setting_id) and true or false
        local changes = policy.plan(enabled, snapshot())
        if write(changes) then
            apply_live()
            pcall(printf,
                "[wt:445] family=ensrick enabled=%s writes=%d members=%d restart_required=true",
                tostring(enabled), #changes, #policy.LEAF_IDS)
        end
        return true
    end

    function runtime:sync()
        local desired = policy.derive_master(snapshot())
        if (mod:get(policy.MASTER_ID) and true or false) ~= desired then
            write({ { id = policy.MASTER_ID, value = desired } })
        end
    end

    function runtime:sync_for_leaf(setting_id)
        if policy.is_member(setting_id) then self:sync() end
    end

    -- Preserve master-checkbox semantics across an owner-level bulk commit.
    -- A complete master+leaf snapshot (DEFAULT/profile restore) keeps the
    -- committed leaf values and derives the indicator. A master-only edit
    -- retains select-all semantics but deliberately defers `apply_live` to the
    -- owner's one final batch apply.
    function runtime:prepare_batch(changed_ids)
        local changed = {}
        for key, value in pairs(changed_ids or {}) do
            local id = type(key) == "number" and value or key
            if type(id) == "string" then changed[id] = true end
        end

        if changed[policy.MASTER_ID] then
            local complete_leaf_snapshot = true
            for i = 1, #policy.LEAF_IDS do
                if not changed[policy.LEAF_IDS[i]] then
                    complete_leaf_snapshot = false
                    break
                end
            end
            if not complete_leaf_snapshot then
                local desired = mod:get(policy.MASTER_ID) and true or false
                if not write(policy.plan(desired, snapshot())) then return false end
            end
        end
        self:sync()
        return true
    end

    return runtime
end

return M
