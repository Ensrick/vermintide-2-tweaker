return function(H, repo_root)
    local policy_path = repo_root
        .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_godmode_ledge_policy.lua"
    local Policy = assert(loadfile(policy_path))()

    H.test("GT Godmode ledge recovery requires every safety precondition", function()
        local safe = { x = 1, y = 2, z = 3 }
        H.equal(Policy.should_restore(true, true, true, safe), true)
        H.equal(Policy.should_restore(false, true, true, safe), false)
        H.equal(Policy.should_restore(true, false, true, safe), false)
        H.equal(Policy.should_restore(true, true, false, safe), false)
        H.equal(Policy.should_restore(true, true, true, nil), false)
    end)

    H.test("GT Godmode ledge recovery prefers last on-ground navmesh sample", function()
        local onground = { id = "onground" }
        local navmesh = { id = "navmesh" }
        H.equal(Policy.choose_recovery_position(onground, navmesh), onground)
        H.equal(Policy.choose_recovery_position(nil, navmesh), navmesh)
        H.equal(Policy.choose_recovery_position(nil, nil), nil)
    end)

    H.test("GT Godmode ledge behavior composes through the singleton noclip hook", function()
        local module_path = repo_root
            .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_noclip.lua"
        local file = assert(io.open(module_path, "rb"))
        local source = file:read("*a")
        file:close()

        local _, hook_count = source:gsub(
            'mod:hook%("CharacterStateHelper", "is_ledge_hanging"', "")
        H.equal(hook_count, 1)
        H.truthy(source:find("last_position_onground_on_navmesh", 1, true))
        H.truthy(source:find("return vanilla_is_ledge", 1, true))
        H.truthy(source:find("_GT_939_GODMODE_LEDGE_MARKER", 1, true))
    end)
end
