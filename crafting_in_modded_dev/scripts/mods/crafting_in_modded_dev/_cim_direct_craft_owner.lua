-- Shared adapter for CIM craft entry points that commit a new mirror item.
-- The Temper runtime owns the actual inject/persist/rollback transaction; this
-- module keeps every other UI path on that same fail-closed boundary.
-- Post-commit observers never vote on success: the local request must still
-- publish after persistence even if a diagnostic reader or logger throws.

return function(context)
    assert(type(context) == "table", "CIM direct craft owner requires context")
    local mod = assert(context.mod, "CIM direct craft owner requires mod")
    local contract = assert(context.contract,
        "CIM direct craft owner requires synthetic item contract")
    local M = {}

    function M.complete_standard_craft(backend_id, observe)
        local observed, reason = pcall(observe)
        -- #1141: this executes only AFTER commit returned success. Returning
        -- failure or rethrowing here strands a persisted item without a craft
        -- request and encourages duplicate retries. The observer is read-only.
        return { { backend_id, [3] = 1 } }, true, observed, reason
    end

    function M.observe_standard_craft(item_key, backend_id, weapon_data, career_name)
        local item_interface = Managers.backend:get_interface("items")
        local stored = item_interface and item_interface:get_item_from_id(backend_id)
        local stored_key = stored and (stored.key or (stored.data and stored.data.key)) or "<nil>"
        local stored_rarity = stored and stored.rarity or "<nil>"
        mod:echo("[cim] Crafted " .. item_key .. " (key=" .. tostring(stored_key)
            .. " rarity=" .. tostring(stored_rarity) .. " bid=" .. tostring(backend_id) .. ")")
        -- Keep the existing delayed visibility probe, shared with Athanor.
        if mod._cim_autodump_craft_synth_result then
            pcall(mod._cim_autodump_craft_synth_result, "standard_forge_synth",
                career_name, item_key, backend_id, weapon_data, true, nil)
        end
        local cwv_entry = item_key:sub(1, 4) == "cwv_" and rawget(ItemMasterList, item_key)
        if cwv_entry and cwv_entry.cwv_variant == true then
            local base_entry = cwv_entry.name and rawget(ItemMasterList, cwv_entry.name)
            printf("[cim:390] crafted CWV key=%s bid=%s base_name=%s | cwv rhu=%s lhu=%s | BASE rhu=%s lhu=%s",
                tostring(item_key), tostring(backend_id), tostring(cwv_entry.name),
                tostring(cwv_entry.right_hand_unit), tostring(cwv_entry.left_hand_unit),
                tostring(base_entry and base_entry.right_hand_unit),
                tostring(base_entry and base_entry.left_hand_unit))
        end
    end

    local observer_failures = 0
    function M.finish_standard_craft(item_key, backend_id, weapon_data, career_name)
        local result, committed, observed, reason = M.complete_standard_craft(
            backend_id, function()
                M.observe_standard_craft(item_key, backend_id, weapon_data, career_name)
            end)
        if not observed and observer_failures < 8 then
            observer_failures = observer_failures + 1
            local logger = rawget(_G, "printf")
            if type(logger) == "function" then
                -- Even an error object's __tostring or logger may be faulty;
                -- neither can revoke a durable craft or its completion row.
                local detail = type(reason) == "string" and reason:sub(1, 160)
                    or type(reason)
                pcall(logger, "[cim:1141] postcommit_observer_failed detail=%s receipt=%d/8",
                    detail, observer_failures)
            end
        end
        return result, committed
    end

    if type(context.rt_register) == "function" then
        context.rt_register("issue1141_postcommit_observation_boundary", function()
            local called = 0
            local result, committed, observed = M.complete_standard_craft(
                "issue1141-observer-check", function()
                    called = called + 1
                    error("expected observer exception", 0)
                end)
            if committed ~= true or observed ~= false or called ~= 1
                    or type(result) ~= "table" or #result ~= 1
                    or result[1][1] ~= "issue1141-observer-check"
                    or result[1][3] ~= 1 then
                return "committed craft was revoked by an observer failure"
            end
        end)
    end

    function M.commit(weapon_data, backend_id, evidence)
        local state = mod._cim_temper_runtime_state
        local commit = state and state.commit_craft
        if type(commit) ~= "function" then
            return false, "transaction_unavailable"
        end
        local called, committed, result = pcall(
            commit, weapon_data, backend_id, evidence)
        if not called then
            return false, "transaction_exception:" .. tostring(committed)
        end
        if committed ~= true then return false, result or "transaction_rejected" end
        return true, result
    end

    function M.validate_saved_occupant(item, backend_id, record, master)
        local called, valid, reason = pcall(
            contract.validate_temper_owned_instance,
            item, backend_id, record, master)
        if not called then return false, "identity_check_exception:" .. tostring(valid) end
        if valid ~= true then return false, reason or "identity_rejected" end
        return true, nil
    end

    return M
end
