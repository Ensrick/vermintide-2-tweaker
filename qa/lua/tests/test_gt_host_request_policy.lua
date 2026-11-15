-- WP-GT-01 (audit finding A6-F01): a host refuses a peer's request to win,
-- fail or restart the level, respawn, be invulnerable, or spawn or clear
-- enemies unless the host ticked "Allow Client Requests"; the two formerly
-- unversioned requests carry a schema number.
return function(H, root)
    local folder = "general_tweaker_dev/scripts/mods/general_tweaker_dev/"
    local P = assert(loadfile(root .. "/" .. folder .. "_gt_host_request_policy.lua"))()

    H.test("GT A6-F01 policy refuses unless host, schema and opt-in all agree", function()
        H.equal(P.SCHEMA, 1)
        H.equal(P.SETTING, "gt_host_allow_client_requests")
        H.equal(P.refuse(true, true, 1, 1), false)
        H.deep_equal({ P.refuse(true, false, 1, 1) }, { true, "host_opt_in_off" })
        H.deep_equal({ P.refuse(true, nil, 1, 1) }, { true, "host_opt_in_off" })
        H.deep_equal({ P.refuse(true, true, "fail", 1) }, { true, "schema_mismatch" })
        H.deep_equal({ P.refuse(false, true, 1, 1) }, { true, "not_host" })
        H.equal(P.ignore_remote_godmode(true, false), true)
        H.equal(P.ignore_remote_godmode(true, true), false)
        H.equal(P.ignore_remote_godmode(false, false), false)
    end)

    -- Stub loader (pattern: test_gt_official_verify_rollup.lua): run the real
    -- level-control module, capture its network handlers by name.
    local function load_level_control(allow)
        local handlers, infos = {}, {}
        local calls = { fail_level = 0, complete_level = 0, retry_level = 0 }
        local game_mode = {}
        for name in pairs(calls) do
            game_mode[name] = function() calls[name] = calls[name] + 1 end
        end
        local env = setmetatable({
            Managers = { player = { is_server = true, players = function() return {} end },
                state = { game_mode = game_mode } },
        }, { __index = _G })
        env._G = env
        local mod = {}
        function mod:get(key) if key == "gt_host_allow_client_requests" then return allow end end
        function mod:dofile(path)
            return setfenv(assert(loadfile(root .. "/general_tweaker_dev/" .. path .. ".lua")), env)()
        end
        function mod:network_register(name, fn) handlers[name] = fn end
        function mod:hook() end
        function mod:command() end
        function mod:info(fmt, ...) infos[#infos + 1] = string.format(fmt, ...) end
        function mod:echo() end
        function mod:warning() end
        env.get_mod = function(id) if id == "gt_dev" then return mod end end
        setfenv(assert(loadfile(root .. "/" .. folder .. "_gt_level_control.lua")), env)()
        return handlers, calls, infos, mod
    end

    H.test("GT A6-F01 host runs a peer's level request only with the opt-in on", function()
        local handlers, calls, infos = load_level_control(false)
        handlers.gt_level_control("peer-x", 1, "fail")
        H.equal(calls.fail_level, 0, "opt-in off: refused")
        H.truthy(infos[#infos]:find("[gt:host-request] refused kind=level peer=peer-x reason=host_opt_in_off", 1, true))
        handlers, calls = load_level_control(true)
        handlers.gt_level_control("peer-x", 1, "fail")
        H.equal(calls.fail_level, 1, "opt-in on: performed")
        handlers.gt_level_control("peer-x", "fail")
        H.equal(calls.fail_level, 1, "the old unversioned payload is refused")
    end)

    H.test("GT A6-F01 host refuses a peer's respawn request with the opt-in off", function()
        local handlers, _, infos = load_level_control(false)
        handlers.gt_respawn_request("peer-y", 1, 1)
        H.truthy(infos[#infos]:find("[gt:host-request] refused kind=respawn peer=peer-y reason=host_opt_in_off", 1, true))
    end)
end
