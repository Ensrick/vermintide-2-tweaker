return function(H, repo_root)
    local policy_path = repo_root
        .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_command_policy.lua"
    local P = assert(loadfile(policy_path))()

    H.test("GT #359 decodes only four existing Versus events", function()
        H.equal(P.command_for_event("vs_social_wheel_dark_pact_general_attack"), "attack_pinged")
        H.equal(P.command_for_event("vs_social_wheel_dark_pact_general_group_up"), "group_up")
        H.equal(P.command_for_event("vs_social_wheel_dark_pact_general_cover_me"), "cover_me")
        H.equal(P.command_for_event("vs_social_wheel_dark_pact_general_wait"), "hold_here")
        H.equal(P.command_for_event("social_wheel_general_yes"), nil)
        H.equal(P.command_for_event(nil), nil)
    end)

    H.test("GT #359 command windows are strict and bounded", function()
        H.equal(P.is_active(9.999, 10), true)
        H.equal(P.is_active(10, 10), false)
        H.equal(P.is_active(11, 10), false)
        H.equal(P.is_active(nil, 10), false)
        H.equal(P.ATTACK_DURATION_S, 10)
        H.equal(P.GROUP_DURATION_S, 8)
        H.equal(P.COVER_DURATION_S, 12)
        H.equal(P.HOLD_DURATION_S, 30)
        H.equal(P.HOLD_RADIUS_M, 4)
    end)

    H.test("GT #359 accepts only the local host sender", function()
        H.equal(P.is_host_sender("host", "host"), true)
        H.equal(P.is_host_sender("client", "host"), false)
        H.equal(P.is_host_sender(nil, "host"), false)
    end)

    H.test("GT #359 nearest selection is deterministic and nil-safe", function()
        H.equal(P.nearest({
            { unit = "far", distance_sq = 25 },
            { unit = "near", distance_sq = 4 },
            { unit = "mid", distance_sq = 9 },
        }), "near")
        H.equal(P.nearest({}), nil)
        H.equal(P.nearest(nil), nil)
    end)

    H.test("GT #359 reuses lookup and singleton follow hook", function()
        local wheel_path = repo_root
            .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_command_wheel.lua"
        local f = assert(io.open(wheel_path, "rb"))
        local wheel = f:read("*a")
        f:close()
        local fixes_path = repo_root
            .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua"
        f = assert(io.open(fixes_path, "rb"))
        local fixes = f:read("*a")
        f:close()

        local _, open_hooks = wheel:gsub('mod:hook%("SocialWheelUI", "_open_menu"', "")
        local _, chat_hooks = wheel:gsub('mod:hook_safe%("PingSystem", "_handle_chat"', "")
        local _, assign_hooks = fixes:gsub('"AIBotGroupSystem", "_assign_destination_points"', "")
        H.equal(open_hooks, 1)
        H.equal(chat_hooks, 1)
        H.equal(assign_hooks, 1)
        H.truthy(wheel:find("no custom RPC", 1, true) ~= nil)
        H.equal(wheel:find("network_register", 1, true), nil)
        H.equal(wheel:find("NetworkLookup.social_wheel_events%[.*%]%s*=", 1), nil)
        H.truthy(fixes:find("_gt359_apply_follow_override", 1, true) ~= nil)
    end)

    H.test("GT #600 Wait captures wheel aim without player-position fallback", function()
        local wheel_path = repo_root
            .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_command_wheel.lua"
        local f = assert(io.open(wheel_path, "rb"))
        local wheel = f:read("*a")
        f:close()

        H.truthy(wheel:find("gt-600-wheel-context-position-not-player-origin", 1, true) ~= nil)
        H.truthy(wheel:find("Vector3Box(current_context.position:unbox())", 1, true) ~= nil)
        H.truthy(wheel:find("_wait_aim_by_pinger[pinger_unit] = nil", 1, true) ~= nil)
        H.equal(wheel:find("Unit.world_position(pinger_unit, 0)", 1, true), nil)
        H.truthy(wheel:find("issue600_wait_aim_and_duration", 1, true) ~= nil)
    end)
end
