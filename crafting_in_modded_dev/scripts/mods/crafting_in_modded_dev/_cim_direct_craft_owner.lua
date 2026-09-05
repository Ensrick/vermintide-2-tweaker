-- Shared adapter for CIM craft entry points that commit a new mirror item.
-- The Temper runtime owns the actual inject/persist/rollback transaction; this
-- module keeps every other UI path on that same fail-closed boundary.

return function(context)
    assert(type(context) == "table", "CIM direct craft owner requires context")
    local mod = assert(context.mod, "CIM direct craft owner requires mod")
    local contract = assert(context.contract,
        "CIM direct craft owner requires synthetic item contract")
    local M = {}

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
