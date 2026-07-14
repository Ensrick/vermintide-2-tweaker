return function(H, repo_root)
    local path = repo_root
        .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_dummy_collision_policy.lua"
    local Policy = assert(loadfile(path))()

    H.test("keep dummy collision policy is exact and default-safe", function()
        local dummy = { name = "training_dummy" }
        H.equal(Policy.should_remove_player_constraint(false, true, dummy), false)
        H.equal(Policy.should_remove_player_constraint(true, false, dummy), false)
        H.equal(Policy.should_remove_player_constraint(true, true, dummy), true)
        H.equal(Policy.should_remove_player_constraint(true, true, { name = "skaven_slave" }), false)
        H.equal(Policy.should_remove_player_constraint(true, true, nil), false)
    end)

    H.test("keep dummy collision runtime preserves authored actors", function()
        local runtime_path = repo_root
            .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_dummy_collision.lua"
        local file = assert(io.open(runtime_path, "rb"))
        local source = file:read("*a")
        file:close()

        H.truthy(source:find("extension.player_locomotion_constrain_radius = nil", 1, true))
        H.equal(source:find("Actor.set_collision_enabled", 1, true), nil)
        H.equal(source:find("Unit.set_unit_visibility", 1, true), nil)
    end)
end
