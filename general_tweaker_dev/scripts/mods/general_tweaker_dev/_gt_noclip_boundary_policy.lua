-- Pure boundary-death policy for #241. Engine-free so host/client routing can
-- be pinned by the offline Lua 5.1 harness.
local Policy = {}

function Policy.should_suppress_unit_route(active, unit, local_unit)
    return active == true and unit ~= nil and unit == local_unit
end

function Policy.should_suppress_rpc(active, rpc_name, go_id, local_go_id)
    return active == true
        and rpc_name == "rpc_suicide"
        and go_id ~= nil
        and go_id == local_go_id
end

return Policy
