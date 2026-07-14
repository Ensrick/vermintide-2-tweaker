return function(H, repo_root)
    local policy_path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_bot_pose_policy.lua"
    local Policy = assert(loadfile(policy_path))()

    H.test("GUT #232 restores is_bot only for pose lookup inside bot spawn", function()
        local value, repaired = Policy.resolve_is_bot(1, "slot_pose", nil)
        H.equal(value, true)
        H.equal(repaired, true)

        value, repaired = Policy.resolve_is_bot(2, "slot_pose", nil)
        H.equal(value, true)
        H.equal(repaired, true)
    end)

    H.test("GUT #232 preserves explicit and non-pose lookups", function()
        local value, repaired = Policy.resolve_is_bot(1, "slot_pose", false)
        H.equal(value, false)
        H.equal(repaired, false)

        value, repaired = Policy.resolve_is_bot(1, "slot_skin", nil)
        H.equal(value, nil)
        H.equal(repaired, false)

        value, repaired = Policy.resolve_is_bot(0, "slot_pose", nil)
        H.equal(value, nil)
        H.equal(repaired, false)
    end)

    H.test("GUT #232 production owns a bounded synchronous call context", function()
        local runtime_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_bot_pose.lua"
        local file = assert(io.open(runtime_path, "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find('mod:hook(player_bot, "spawn"', 1, true) ~= nil)
        H.truthy(source:find('mod:hook(backend_utils, "get_loadout_item"', 1, true) ~= nil)
        H.truthy(source:find('Policy.resolve_is_bot(spawn_depth, slot_name, is_bot)', 1, true) ~= nil)
        H.truthy(source:find('return func(career_name, slot_name, resolved, ...)', 1, true) ~= nil)
    end)
end
