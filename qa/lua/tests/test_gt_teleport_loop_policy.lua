return function(H, repo_root)
    local policy = dofile(repo_root
        .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_teleport_loop_policy.lua")

    H.test("GT no-path unstick keeps first execution and bounds close repeats", function()
        H.equal(policy.should_suppress_no_path(2.8, 15, 100, nil), false)
        H.equal(policy.should_suppress_no_path(2.8, 15, 102, 100), true)
        H.equal(policy.should_suppress_no_path(14.9, 15, 104.9, 100), true)
        H.equal(policy.should_suppress_no_path(2.8, 15, 105, 100), false)
    end)

    H.test("GT no-path bound never suppresses outside leash or invalid state", function()
        H.equal(policy.should_suppress_no_path(15, 15, 102, 100), false)
        H.equal(policy.should_suppress_no_path(40, 15, 102, 100), false)
        H.equal(policy.should_suppress_no_path(nil, 15, 102, 100), false)
        H.equal(policy.should_suppress_no_path(2.8, 15, 99, 100), false)
    end)

    H.test("GT no-path reason classification excludes leash branches", function()
        H.equal(policy.is_no_path_reason("vanilla_no_path"), true)
        H.equal(policy.is_no_path_reason("backward_no_path"), true)
        H.equal(policy.is_no_path_reason("vanilla_40m"), false)
        H.equal(policy.is_no_path_reason("tighter_leash"), false)
    end)

    H.test("GT production stamps and reports exact no-path trigger", function()
        local fixes_path = repo_root
            .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua"
        local lab_path = repo_root
            .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_teleport_lab.lua"
        local f = assert(io.open(fixes_path, "rb")); local fixes = f:read("*a"); f:close()
        f = assert(io.open(lab_path, "rb")); local lab = f:read("*a"); f:close()
        H.truthy(fixes:find('blackboard._gt139_tp_reason = "vanilla_no_path"', 1, true))
        H.truthy(fixes:find("policy.should_suppress_no_path", 1, true))
        H.truthy(fixes:find('mod._gt385_should_suppress_no_path(blackboard, "backward_no_path")', 1, true))
        H.truthy(fixes:find("blackboard._gt385_last_no_path_t = t", 1, true))
        H.truthy(lab:find('decision_reason and decision_reason ~= "other"', 1, true))
        H.truthy(lab:find("decision_reason,", 1, true))
    end)
end
