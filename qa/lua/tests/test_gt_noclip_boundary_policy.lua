return function(H, repo_root)
    local policy_path = repo_root
        .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_noclip_boundary_policy.lua"
    local Policy = assert(loadfile(policy_path))()

    H.test("gt noclip unit boundary routes are local and active only", function()
        local local_unit = {}
        H.truthy(Policy.should_suppress_unit_route(true, local_unit, local_unit))
        H.equal(Policy.should_suppress_unit_route(false, local_unit, local_unit), false)
        H.equal(Policy.should_suppress_unit_route(true, {}, local_unit), false)
        H.equal(Policy.should_suppress_unit_route(true, nil, nil), false)
    end)

    H.test("gt noclip client suicide RPC gate is exact", function()
        H.truthy(Policy.should_suppress_rpc(true, "rpc_suicide", 17, 17))
        H.equal(Policy.should_suppress_rpc(false, "rpc_suicide", 17, 17), false)
        H.equal(Policy.should_suppress_rpc(true, "rpc_suicide", 18, 17), false)
        H.equal(Policy.should_suppress_rpc(true, "rpc_request_insta_kill", 17, 17), false)
        H.equal(Policy.should_suppress_rpc(true, "rpc_suicide", nil, nil), false)
    end)

    H.test("gt noclip runtime covers all source death routes without die hook", function()
        local runtime_path = repo_root
            .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_noclip.lua"
        local file = assert(io.open(runtime_path, "rb"))
        local source = file:read("*a")
        file:close()

        H.truthy(source:find('mod:hook("HealthSystem", "suicide"', 1, true))
        H.truthy(source:find('mod:hook("PlayerUnitHealthExtension", "entered_kill_volume"', 1, true))
        H.truthy(source:find('mod._gt_noclip_server_rpc_guard = function', 1, true))
        H.equal(source:find('mod:hook("PlayerUnitHealthExtension", "die"', 1, true), nil)
    end)
end
