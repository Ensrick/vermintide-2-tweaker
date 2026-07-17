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

    H.test("GT aid trace correlates one bot and ally inside bounded window", function()
        local bot_follow = {}
        local aid = {}
        local trace = policy.make_aid_veto_trace(100, aid, bot_follow, "vanilla_40m")
        H.truthy(trace)
        H.equal(trace.aid_unit, aid)
        H.equal(trace.follow_unit, bot_follow)
        H.equal(trace.reason, "vanilla_40m")

        local age, same = policy.correlate_aid_veto(trace, 102.5, aid)
        H.equal(age, 2.5)
        H.equal(same, true)

        age, same = policy.correlate_aid_veto(trace, 102.5, {})
        H.equal(age, 2.5)
        H.equal(same, false)
    end)

    H.test("GT aid trace expires and rejects malformed timestamps", function()
        local aid = {}
        local trace = policy.make_aid_veto_trace(100, aid, nil, "tighter_leash")
        local age, same = policy.correlate_aid_veto(trace, 103.01, aid)
        H.equal(age, nil)
        H.equal(same, nil)
        age, same = policy.correlate_aid_veto(trace, 99, aid)
        H.equal(age, nil)
        H.equal(same, nil)
        H.equal(policy.make_aid_veto_trace(nil, aid, nil, "x"), nil)
        H.equal(policy.make_aid_veto_trace(1, nil, nil, "x"), nil)
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
        H.truthy(fixes:find("GT_BOT139_CORRELATED_AID_TRACE_MARKER_v0_2_243", 1, true))
        H.truthy(fixes:find("_gt_trace_final_follow(bot_ai_data)", 1, true))
        H.truthy(fixes:find("[gt:139:chain] TELEPORT", 1, true))
        H.truthy(lab:find("[gt:139:chain] FOLLOW", 1, true))
        H.truthy(lab:find("local p = _live_pos(unit)", 1, true))
        H.equal(fixes:find("local post = POSITION_LOOKUP[unit]", 1, true), nil)
        H.equal(lab:find("local post     = POSITION_LOOKUP[unit]", 1, true), nil)
    end)
end
