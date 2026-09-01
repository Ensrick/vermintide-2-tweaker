return function(H, repo_root)
    local function read(relative)
        local file = assert(io.open(repo_root .. relative, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function capture(...)
        return select("#", ...), { ... }
    end

    local authority = assert(loadfile(
        repo_root .. "/tools/shared_lib/_lib_modded_realm_authority.lua"))()

    local function register_policy_cases(label, guard_relative)
        local guard = assert(loadfile(repo_root .. guard_relative))()

        H.test("GT #1509 " .. label ..
            " restores cached modded state from immutable launch authority", function()
            local state = { _booted_eac_untrusted = false }
            local skip, corrected = guard.reconcile(
                authority, state, { ["eac-untrusted"] = false },
                { application_parameter = { ["eac-untrusted"] = true } })
            H.equal(skip, true)
            H.equal(corrected, true)
            H.equal(state._booted_eac_untrusted, true)
        end)

        H.test("GT #1509 " .. label .. " accepts the exact raw modded flag", function()
            local state = {}
            local skip, corrected = guard.reconcile(
                authority, state, { ["eac-untrusted"] = true }, nil)
            H.equal(skip, true)
            H.equal(corrected, true)
            H.equal(state._booted_eac_untrusted, true)
        end)

        H.test("GT #1509 " .. label .. " preserves official reward generation", function()
            local state = { _booted_eac_untrusted = false }
            local skip, corrected = guard.reconcile(
                authority, state, { ["eac-untrusted"] = false },
                { application_parameter = {} })
            H.equal(skip, false)
            H.equal(corrected, false)
            H.equal(state._booted_eac_untrusted, false)
        end)

        H.test("GT #1509 " .. label ..
            " fails closed on malformed or throwing authority", function()
            local state = { _booted_eac_untrusted = false }
            H.equal(guard.reconcile(nil, state, {}, {}), false)
            H.equal(guard.reconcile({ is_modded = function() error("boom") end },
                state, {}, {}), false)
            H.equal(state._booted_eac_untrusted, false)
        end)
    end

    local stable_guard = "/general_tweaker/scripts/mods/general_tweaker/" ..
        "_gt_level_control_backend_guard.lua"
    local dev_guard = "/general_tweaker_dev/scripts/mods/general_tweaker_dev/" ..
        "_gt_level_control_backend_guard.lua"
    register_policy_cases("stable", stable_guard)
    register_policy_cases("Dev", dev_guard)

    H.test("GT #1509 stable and Dev guard policies are byte-identical", function()
        H.equal(read(stable_guard), read(dev_guard))
    end)

    local function register_runtime_install_case(label, stream)
        H.test("GT #1509 " .. label ..
            " installs its registrar and exercises the live reward hook", function()
            local main_source = read(stream.main)
            local scaffold_start = assert(main_source:find("local _RT_CHECKS = {}", 1, true))
            local scaffold_end_marker =
                'mod:info("[regression-test-command] registered as /gt_regression_test")'
            local scaffold_end_start = assert(main_source:find(
                scaffold_end_marker, scaffold_start, true))
            local scaffold_end = scaffold_end_start + #scaffold_end_marker - 1
            local load_start = assert(main_source:find(stream.load_line, scaffold_end, true))
            local load_end = main_source:find("\n", load_start, true) or (#main_source + 1)
            H.truthy(scaffold_end < load_start,
                label .. " level-control module loaded before registrar scaffold")

            local env
            local saw_registrar_at_level_control_load = false
            local mod = {
                commands = {},
                hooks = {},
                network_handlers = {},
            }

            function mod:command(name, _, fn)
                self.commands[name] = fn
            end
            function mod:info() end
            function mod:warning() end
            function mod:echo() end
            function mod:get() return false end
            function mod:hook(class_name, method_name, fn)
                self.hooks[class_name .. "." .. method_name] = fn
            end
            function mod:network_register(name, fn)
                self.network_handlers[name] = fn
            end
            function mod:network_send() end
            function mod:dofile(path)
                if path == stream.level_control then
                    saw_registrar_at_level_control_load =
                        type(self._gt_rt_register) == "function"
                end
                local chunk = assert(loadfile(
                    repo_root .. "/" .. stream.directory .. "/" .. path .. ".lua"))
                setfenv(chunk, env)
                return chunk()
            end

            env = setmetatable({
                _G = false,
                mod = mod,
                get_mod = function(id)
                    H.equal(id, stream.mod_id)
                    return mod
                end,
                script_data = {},
            }, { __index = _G })
            env._G = env

            local scaffold = assert(loadstring(
                main_source:sub(scaffold_start, scaffold_end),
                "@" .. label .. "_gt_runtime_scaffold.lua"))
            setfenv(scaffold, env)
            scaffold()
            H.equal(type(mod._gt_rt_register), "function")

            local registry
            for index = 1, 16 do
                local upvalue_name, value = debug.getupvalue(mod._gt_rt_register, index)
                if not upvalue_name then break end
                if upvalue_name == "_RT_CHECKS" then
                    registry = value
                    break
                end
            end
            H.equal(type(registry), "table",
                label .. " exported registrar did not retain its installed registry")

            local load_statement = assert(loadstring(
                main_source:sub(load_start, load_end - 1),
                "@" .. label .. "_gt_level_control_load.lua"))
            setfenv(load_statement, env)
            load_statement()
            H.equal(saw_registrar_at_level_control_load, true,
                label .. " level-control dofile ran without an exported registrar")

            local installed
            for i = 1, #registry do
                if registry[i].name == "issue1509_modded_level_control_reward_guard" then
                    installed = registry[i]
                    break
                end
            end
            H.truthy(installed ~= nil,
                label .. " did not install issue1509_modded_level_control_reward_guard")
            H.equal(type(installed.fn), "function")
            H.equal(installed.fn(), nil,
                label .. " installed issue1509 runtime check did not pass")

            local reward_hook = mod.hooks[
                "StateInGameRunning._award_end_of_level_rewards"]
            H.equal(type(reward_hook), "function",
                label .. " did not install the live end-of-level reward hook")

            local modded_delegate_calls = 0
            local function original_must_not_run()
                modded_delegate_calls = modded_delegate_calls + 1
            end

            env.script_data = { ["eac-untrusted"] = false }
            env.Development = {
                application_parameter = { ["eac-untrusted"] = true },
            }
            local launch_state = { _booted_eac_untrusted = false }
            local launch_count = capture(reward_hook(
                original_must_not_run, launch_state, "launch", nil, "authority"))
            H.equal(launch_count, 0,
                label .. " launch-authoritative modded path returned a value")
            H.equal(modded_delegate_calls, 0,
                label .. " delegated launch-authoritative modded rewards")
            H.equal(launch_state._booted_eac_untrusted, true,
                label .. " launch authority did not repair the cached modded bit")

            env.script_data = { ["eac-untrusted"] = true }
            env.Development = nil
            local raw_state = { _booted_eac_untrusted = false }
            local raw_count = capture(reward_hook(
                original_must_not_run, raw_state, "raw", nil, "authority"))
            H.equal(raw_count, 0,
                label .. " raw-modded path returned a value")
            H.equal(modded_delegate_calls, 0,
                label .. " delegated raw-modded rewards")
            H.equal(raw_state._booted_eac_untrusted, true,
                label .. " raw modded authority did not repair the cached bit")

            local function assert_delegates_once(authority_override, context)
                local authority_api = mod._gt_modded_realm_authority
                H.equal(type(authority_api), "table")
                local original_authority = rawget(authority_api, "is_modded")
                if authority_override ~= false then
                    rawset(authority_api, "is_modded", authority_override)
                end

                env.script_data = { ["eac-untrusted"] = false }
                env.Development = { application_parameter = {} }
                local state = { _booted_eac_untrusted = false }
                local calls = 0
                local received_self
                local received_count
                local received
                local function original(self_arg, ...)
                    calls = calls + 1
                    received_self = self_arg
                    received_count, received = capture(...)
                end

                local result_count = capture(reward_hook(
                    original, state, "alpha", nil, false, nil, "omega"))

                rawset(authority_api, "is_modded", original_authority)

                H.equal(calls, 1,
                    label .. " " .. context .. " did not delegate exactly once")
                H.equal(received_self, state,
                    label .. " " .. context .. " changed native self")
                H.equal(received_count, 5,
                    label .. " " .. context .. " lost nil-containing arguments")
                H.equal(received[1], "alpha")
                H.equal(received[2], nil)
                H.equal(received[3], false)
                H.equal(received[4], nil)
                H.equal(received[5], "omega")
                H.equal(result_count, 0,
                    label .. " " .. context .. " changed vanilla's nil return")
                H.equal(state._booted_eac_untrusted, false,
                    label .. " " .. context .. " mutated the official cache")
            end

            assert_delegates_once(false, "official authority")
            assert_delegates_once(nil, "malformed authority")
            assert_delegates_once(function() error("authority exploded") end,
                "throwing authority")
        end)
    end

    register_runtime_install_case("stable", {
        main = "/general_tweaker/scripts/mods/general_tweaker/general_tweaker.lua",
        directory = "general_tweaker",
        mod_id = "gt",
        level_control = "scripts/mods/general_tweaker/_gt_level_control",
        load_line = 'mod:dofile("scripts/mods/general_tweaker/_gt_level_control")',
    })
    register_runtime_install_case("Dev", {
        main = "/general_tweaker_dev/scripts/mods/general_tweaker_dev/general_tweaker_dev.lua",
        directory = "general_tweaker_dev",
        mod_id = "gt_dev",
        level_control = "scripts/mods/general_tweaker_dev/_gt_level_control",
        load_line = 'mod:dofile("scripts/mods/general_tweaker_dev/_gt_level_control")',
    })

    H.test("GT #1509 stable and Dev reward hooks retain the same contract", function()
        local streams = {
            {
                root = "/general_tweaker/scripts/mods/general_tweaker/",
                authority = "scripts/mods/general_tweaker/_lib_modded_realm_authority",
                guard = "scripts/mods/general_tweaker/_gt_level_control_backend_guard",
            },
            {
                root = "/general_tweaker_dev/scripts/mods/general_tweaker_dev/",
                authority = "scripts/mods/general_tweaker_dev/_lib_modded_realm_authority",
                guard = "scripts/mods/general_tweaker_dev/_gt_level_control_backend_guard",
            },
        }

        for i = 1, #streams do
            local stream = streams[i]
            local source = read(stream.root .. "_gt_level_control.lua")
            H.truthy(source:find(stream.authority, 1, true) ~= nil)
            H.truthy(source:find(stream.guard, 1, true) ~= nil)
            H.truthy(source:find("mod._gt_modded_realm_authority = RealmAuthority", 1, true) ~= nil)
            H.truthy(source:find("mod._gt_level_control_backend_guard = BackendGuard", 1, true) ~= nil)

            local hook = assert(source:find(
                'mod:hook("StateInGameRunning", "_award_end_of_level_rewards"',
                1, true))
            local reconcile = assert(source:find("BackendGuard.reconcile", hook, true))
            local delegate = assert(source:find(
                "local ok, err = pcall(func, self", reconcile, true))
            H.truthy(hook < reconcile)
            H.truthy(reconcile < delegate)
            H.truthy(source:find(
                "[gt:1509] corrected stale modded-realm reward state", hook, true) ~= nil)
            H.truthy(source:find(
                'mod._gt_rt_register("issue1509_modded_level_control_reward_guard"',
                delegate, true) ~= nil)
        end
    end)
end
