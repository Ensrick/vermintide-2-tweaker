-- _cim_salvage_local_boundary.lua -- local-only CIM salvage dispatch.
--
-- This module accepts only exact ownership, saved-craft lookup, and the one
-- local deletion transaction. Owned and foreign rows cross that boundary
-- together so a later failure can compensate the entire selected set.

local M = {
    MARKER = "cim_salvage_local_only_v1",
}

function M.execute(deps, backend_ids)
    deps = type(deps) == "table" and deps or {}
    local contract = deps.contract
    if type(contract) ~= "table"
            or type(contract.partition_exact_ids) ~= "function"
            or type(deps.get_record) ~= "function"
            or type(deps.delete_owned_ids) ~= "function" then
        return nil, "local salvage boundary is unavailable"
    end

    local records = {}
    for i = 1, #(backend_ids or {}) do
        local backend_id = backend_ids[i]
        records[backend_id] = deps.get_record(backend_id)
    end
    local owned, foreign = contract.partition_exact_ids(backend_ids, records)

    local ok, deleted, err = pcall(deps.delete_owned_ids, owned, foreign)
    if not ok then return nil, "local deletion failed: " .. tostring(deleted) end
    if err then return nil, "local deletion failed: " .. tostring(err) end
    return {
        selected = #(backend_ids or {}),
        owned = #owned,
        deleted = deleted,
        foreign = #foreign,
    }
end

return M
