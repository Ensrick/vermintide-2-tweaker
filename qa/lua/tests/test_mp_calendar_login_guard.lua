return function(H, repo_root)
    local dir = "/modded_progression/scripts/mods/modded_progression/"
    local Guard = assert(loadfile(repo_root .. dir .. "_mp_calendar_login_guard.lua"))()
    local function read(path)
        local f = assert(io.open(path, "rb")); local text = f:read("*a"); f:close()
        return (text:gsub("\r\n", "\n"))
    end
    local entry = read(repo_root .. dir .. "modded_progression.lua")
    local fixture_path = repo_root .. "/qa/lua/fixtures/mp_calendar_login_native_6_13.lua"
    local function pack(...) return { n = select("#", ...), ... } end
    local function installed(query, logger)
        local hooks, checks, logs = {}, {}, {}
        local owner = Guard.install({ hook = function(_, class, method, fn)
            hooks[#hooks + 1] = { class, method, fn }
        end }, { is_modded_realm = query, rt_register = function(name, fn)
            H.equal(checks[name], nil, "duplicate calendar registration"); checks[name] = fn
        end, print_log = logger or function(fmt, ...) logs[#logs + 1] = string.format(fmt, ...) end })
        H.equal(#hooks, 1); H.equal(hooks[1][1], "HeroWindowGotwfOverview")
        H.equal(hooks[1][2], "_claim_daily_reward")
        H.equal(hooks[1][3], owner.claim_callback)
        H.equal(checks[Guard.CHECK_NAME], Guard.runtime_check)
        return hooks[1][3], logs, checks
    end
    local function current_backend(query)
        -- Execute the exact current MP helper and installed backend callback,
        -- not a hand-written fake suppression policy.
        local first = assert(entry:find("local function _route_store_login_claim_for_realm(", 1, true))
        local last = assert(entry:find('\n_rt_register("mp589_store_login_claim_request_boundary"', first, true))
        local hook_first = assert(entry:find('mod:hook("BackendInterfacePeddlerPlayFab", "claim_login_rewards"', 1, true))
        local hook_last = assert(entry:find("\nend)", hook_first, true)) + 4
        local source = "return function(mod, _is_mp_realm, _capture, _dbg_alert)\n"
            .. entry:sub(first, last - 1) .. "\n" .. entry:sub(hook_first, hook_last) .. "\nend"
        local callback
        assert(loadstring(source, "@actual-mp-login-backend"))()({
            hook = function(_, class, method, fn)
                H.equal(class, "BackendInterfacePeddlerPlayFab")
                H.equal(method, "claim_login_rewards"); callback = fn
            end,
        }, query, function(...) return select("#", ...), { ... } end, function() end)
        return assert(callback)
    end
    local function native_scenario(query)
        local s = { blocks = 0, unblocks = 0, sounds = 0, original_claims = 0,
            backend_reads = 0, callbacks = 0, transitions = 0 }
        local backend_callback = current_backend(query)
        local peddler = { _is_done_claiming = true }
        function peddler:claim_login_rewards(cb, offset)
            return backend_callback(function(_, got_cb, got_offset)
                s.original_claims = s.original_claims + 1
                s.pending_callback, s.offset = got_cb, got_offset
            end, self, cb, offset)
        end
        s.peddler = peddler
        local env = setmetatable({}, { __index = _G }); env._G = env
        env.Managers = { backend = { get_interface = function(_, name)
            H.equal(name, "peddler"); s.backend_reads = s.backend_reads + 1; return peddler
        end }, ui = { handle_transition = function() s.transitions = s.transitions + 1 end } }
        env.callback = function(self, method, index)
            return function(data)
                s.callbacks = s.callbacks + 1
                return self[method](self, index, data)
            end
        end
        local chunk = assert(loadfile(fixture_path)); setfenv(chunk, env)
        s.native = chunk()
        s.window = {
            _login_rewards = { num_allowed_old_segments_to_claim = 1,
                rewards = { {} }, claimed_rewards = { 0 } },
            _ui_animator = {},
            _parent = { block_input = function() s.blocks = s.blocks + 1 end,
                unblock_input = function() s.unblocks = s.unblocks + 1 end },
            _play_sound = function() s.sounds = s.sounds + 1 end,
            _claim_reward_result_cb = s.native._claim_reward_result_cb,
        }
        return s
    end

    H.test("MP calendar exact native action exposes the suppressed-callback input lock", function()
        local s = native_scenario(function() return true end)
        s.native._claim_daily_reward(s.window, 0)
        H.equal(s.original_claims, 0, "existing backend guard must not enqueue")
        H.equal(s.pending_callback, nil); H.equal(s.callbacks, 0)
        H.equal(s.peddler._is_done_claiming, true, "poller flag is not the calendar callback")
        H.equal(s.window._awaiting_result, true); H.equal(s.window._force_index, 1)
        H.equal(s.blocks, 1); H.equal(s.unblocks, 0); H.equal(s.sounds, 1)
    end)

    H.test("MP calendar installed guard stops exact native action before every UI/backend effect", function()
        local s = native_scenario(function() return true end)
        local callback, logs = installed(function() return true end)
        local before = s.window._login_rewards
        H.equal(callback(s.native._claim_daily_reward, s.window, 0), nil)
        H.equal(s.window._login_rewards, before)
        H.equal(s.window._awaiting_result, nil); H.equal(s.window._force_index, nil)
        H.equal(s.blocks, 0); H.equal(s.unblocks, 0); H.equal(s.sounds, 0)
        H.equal(s.backend_reads, 0); H.equal(s.original_claims, 0); H.equal(s.callbacks, 0)
        H.equal(s.peddler._is_done_claiming, true)
        H.equal(#logs, 1)
    end)

    H.test("MP calendar official exact native sequence still waits and completes normally", function()
        local s = native_scenario(function() return false end)
        local callback = installed(function() return false end)
        callback(s.native._claim_daily_reward, s.window, 0)
        H.equal(s.original_claims, 1); H.equal(s.offset, 0)
        H.equal(s.window._awaiting_result, true); H.equal(s.blocks, 1)
        H.equal(s.unblocks, 0); H.equal(s.sounds, 1)
        H.equal(type(s.pending_callback), "function")
        s.pending_callback({ event_type = "calendar", rewards = { {} } })
        H.equal(s.callbacks, 1); H.equal(s.window._awaiting_result, false)
        H.equal(s.unblocks, 1); H.equal(s.transitions, 0)
    end)

    for _, case in ipairs({
        { name = "modded", read = function() return true end },
        { name = "absent", read = function() return nil end },
        { name = "string", read = function() return "false" end },
        { name = "number", read = function() return 0 end },
        { name = "table", read = function() return {} end },
        { name = "throw", read = function() error("realm unavailable") end },
    }) do
        H.test("MP calendar " .. case.name .. " authority touches no hostile UI state", function()
            local callback = installed(case.read)
            local reads, writes, calls = 0, 0, 0
            local poison = setmetatable({}, { __index = function()
                reads = reads + 1; error("UI read")
            end, __newindex = function() writes = writes + 1; error("UI write") end })
            for _ = 1, 3 do
                H.equal(callback(function() calls = calls + 1 end, poison, "invalid-offset"), nil)
            end
            H.equal(reads, 0); H.equal(writes, 0); H.equal(calls, 0)
            H.equal(next(poison), nil)
        end)
    end

    H.test("MP calendar denial cannot release another pending input owner", function()
        local callback = installed(function() return true end)
        local s = native_scenario(function() return true end)
        s.window._awaiting_result, s.window._force_index = true, 7
        callback(s.native._claim_daily_reward, s.window, 0)
        H.equal(s.window._awaiting_result, true); H.equal(s.window._force_index, 7)
        H.equal(s.unblocks, 0); H.equal(s.blocks, 0); H.equal(s.backend_reads, 0)
    end)

    H.test("MP calendar official delegation preserves arguments tuple holes and exact exception", function()
        local callback, logs = installed(function() return false end)
        local self, tail, calls = {}, {}, 0
        local values = pack(callback(function(got_self, offset, a, b, c)
            calls = calls + 1; H.equal(got_self, self); H.equal(offset, -1)
            H.equal(a, "head"); H.equal(b, nil); H.equal(c, tail)
            return 1, nil, tail, nil
        end, self, -1, "head", nil, tail))
        H.equal(calls, 1); H.equal(values.n, 4)
        H.equal(values[1], 1); H.equal(values[2], nil); H.equal(values[3], tail)
        H.equal(values[4], nil); H.equal(#logs, 0)
        local failure = {}; local ok, err = pcall(callback, function() error(failure) end, self, 0)
        H.equal(ok, false); H.equal(err, failure)
    end)

    H.test("MP calendar denial logging is bounded before reentry and contains logger errors", function()
        local mode, calls, callback = true, 0, nil
        callback = installed(function() return mode end, function()
            calls = calls + 1
            if calls > 3 then error("unbounded log reentry") end
            callback(function() error("native reentry") end, {}, 0)
            error("logger unavailable")
        end)
        callback(function() error("native") end, {}, 0)
        callback(function() error("native") end, {}, 0)
        H.equal(calls, 1)
        mode = nil
        callback(function() error("native") end, {}, 0)
        callback(function() error("native") end, {}, 0)
        H.equal(calls, 2)
    end)

    H.test("MP calendar actual entry supplies native-first tri-state authority and named check", function()
        local first = assert(entry:find('local CalendarLoginGuard = mod:dofile(', 1, true))
        local last = assert(entry:find("-- Vanilla keep crafting bench:", first, true))
        local block = entry:sub(first, last - 1)
        for _, case in ipairs({
            { native = true, legacy = false, calls = 0 },
            { native = false, legacy = true, calls = 1 },
            { native = "false", legacy = false, calls = 0 },
            { legacy = true, calls = 0 },
            { legacy = false, calls = 1 },
            { throws = true, calls = 0 },
        }) do
            local env = setmetatable({}, { __index = _G }); env._G = env
            env.MODDED_REALM = case.native; env.printf = function() end
            local hooks, checks, native_calls, fallback_calls = {}, {}, 0, 0
            local mod = { dofile = function(_, path)
                H.equal(path, "scripts/mods/modded_progression/_mp_calendar_login_guard")
                return Guard
            end, hook = function(_, class, method, fn) hooks[class .. "." .. method] = fn end }
            local chunk = assert(loadstring("return function(mod, _is_mp_realm, _rt_register)\n"
                .. block .. "\nend", "@calendar-actual-entry"))
            setfenv(chunk, env)
            chunk()(mod, function()
                fallback_calls = fallback_calls + 1
                if case.throws then error("fallback unreadable") end
                return case.legacy
            end, function(name, fn) checks[name] = fn end)
            local callback = assert(hooks["HeroWindowGotwfOverview._claim_daily_reward"])
            callback(function() native_calls = native_calls + 1 end, {}, 0)
            H.equal(native_calls, case.calls)
            H.equal(fallback_calls, case.native ~= nil and 0 or 1)
            H.equal(checks[Guard.CHECK_NAME], Guard.runtime_check)
            H.equal(env.MODDED_REALM, case.native)
        end
    end)

    H.test("MP calendar named check exercises the same installed guard", function()
        local _, _, checks = installed(function() return true end)
        H.equal(checks[Guard.CHECK_NAME](), nil)
    end)

    H.test("MP calendar mandatory dependencies fail visibly rather than silently omit protection", function()
        for _, deps in ipairs({ {}, { is_modded_realm = function() return true end } }) do
            local ok = pcall(Guard.install, { hook = function() error("should not install") end }, deps)
            H.equal(ok, false)
        end
    end)

    local native_path = (os.getenv("VT2_DECOMPILE_ROOT") or (repo_root .. "/../Vermintide-2-Source-Code"))
        .. "/scripts/ui/views/hero_view/windows/hero_window_gotwf_overview.lua"
    local f = io.open(native_path, "rb")
    local native = f and f:read("*a"); if f then f:close() end
    if native then native = native:gsub("\r\n", "\n") end
    H.test_if(native ~= nil, "MP calendar frozen action/completion match exact native 6.13 source", function()
        local fixture = read(fixture_path)
        local first = assert(native:find("HeroWindowGotwfOverview._claim_daily_reward = function", 1, true))
        local last = assert(native:find("\nHeroWindowGotwfOverview._trigger_replacement_rewards = function", first, true))
        local bodies = native:sub(first, last - 1):gsub("\n+$", "")
        H.truthy(fixture:find(bodies, 1, true), "portable native bodies drifted")
        H.truthy(native:find('self:_claim_daily_reward(reward_offset)', 1, true))
        local _, producers = native:gsub('self:_claim_daily_reward%(reward_offset%)', "")
        H.equal(producers, 2, "mouse/controller common action changed")
    end, "optional native 6.13 source unavailable; portable exact fixture still executed")
end
