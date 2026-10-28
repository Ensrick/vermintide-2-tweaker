return function(H, repo)
    local dir = "/modded_progression/scripts/mods/modded_progression/"
    local function read(path)
        local f = assert(io.open(path, "rb")); local text = f:read("*a"); f:close()
        return (text:gsub("\r\n", "\n"))
    end
    local entry = read(repo .. dir .. "modded_progression.lua")
    local Realm = assert(loadfile(repo .. dir .. "_lib_modded_realm_authority.lua"))()
    local Calendar = assert(loadfile(repo .. dir .. "_mp_calendar_login_guard.lua"))()
    local native_path = repo .. "/qa/lua/fixtures/mp_login_request_native_6_13.lua"
    local function pack(...) return { n = select("#", ...), ... } end
    local function section(source, first, last)
        local at = assert(source:find(first, 1, true), first)
        local stop = assert(source:find(last, at, true), last)
        H.equal(source:find(first, at + #first, true), nil, "duplicate source owner")
        return source:sub(at, stop - 1)
    end
    local function installed(native, options)
        options = options or {}
        -- source_override is used only by the separately selected old-source
        -- same-oracle control. No historical checkout/external-source fallback.
        local source = options.source_override or entry
        local query_at = source:find("local function _login_realm(", 1, true)
        local helpers = section(source, query_at and "local function _login_realm("
            or "local function _route_store_login_claim_for_realm(",
            '\n_rt_register("mp589_store_login_claim_request_boundary"')
        local backend_at = assert(source:find('mod:hook("BackendInterfacePeddlerPlayFab", "claim_login_rewards"', 1, true))
        local backend_stop = assert(source:find("\nend)", backend_at, true)) + 4
        local popup = section(source, 'mod:hook("StoreLoginRewardsPopup", "_create_ui_elements"',
            "-- Vanilla keep crafting bench:")
        local runtime_at = source:find('_rt_register("issue1684_login_request_authority"', 1, true)
        local runtime = runtime_at and section(source, '_rt_register("issue1684_login_request_authority"',
            '\n_rt_register("modded_daily_realm_boundary"') or ""
        local s = { hooks = {}, order = {}, checks = {}, queue = {}, logs = 0,
            fallback_calls = 0, flag = {}, native_calls = 0 }
        rawset(s.flag, "eac-untrusted", options.flag)
        local env = setmetatable({}, { __index = _G }); env._G = env
        env.MODDED_REALM = native
        env.printf = function() s.logs = s.logs + 1 end
        env.callback = function(self, method, external, offset)
            H.equal(self, s.peddler); H.equal(method, "_claim_store_rewards_cb")
            s.callback_external, s.callback_offset = external, offset
            return function() error("recording queue must not dispatch callbacks") end
        end
        local mod = {
            hook = function(_, class, method, fn)
                local name = class .. "." .. method
                H.equal(s.hooks[name], nil, "duplicate installed login hook")
                s.hooks[name] = fn; s.order[#s.order + 1] = name
            end,
            dofile = function(_, path)
                H.equal(path, "scripts/mods/modded_progression/_mp_calendar_login_guard")
                return { install = function(owner, deps)
                    s.calendar_query = deps.is_modded_realm
                    return Calendar.install(owner, deps)
                end }
            end,
        }
        local load_native = assert(loadfile(native_path)); setfenv(load_native, env)
        s.native = load_native()
        local queue = { enqueue = function(_, request, callback, eac)
            s.queue[#s.queue + 1] = { request = request, callback = callback, eac = eac }
        end }
        s.peddler = { _is_done_claiming = true,
            _backend_mirror = { request_queue = function() return queue end } }
        local function fallback()
            s.fallback_calls = s.fallback_calls + 1
            if options.reader then return options.reader() end
            return Realm.is_modded(s.flag, 0, options.development, env)
        end
        local result = query_at and "return _login_realm" or "return nil"
        local loader = assert(loadstring("return function(mod, _is_mp_realm, _capture, _dbg_alert, _rt_register)\n"
            .. helpers .. "\n" .. source:sub(backend_at, backend_stop) .. "\n"
            .. popup .. "\n" .. runtime .. "\n" .. result .. "\nend", "@actual-mp-login-boundaries"))
        setfenv(loader, env)
        s.query = loader()(mod, fallback, function(...) return select("#", ...), { ... } end,
            function() s.logs = s.logs + 1 end, function(name, fn)
                H.equal(s.checks[name], nil); s.checks[name] = fn
            end)
        s.env = env
        function s:claim(fn, ...)
            return self.hooks["BackendInterfacePeddlerPlayFab.claim_login_rewards"](
                fn or self.native, self.peddler, ...)
        end
        function s:popup()
            return { _widgets_by_name = { claim_button = {
                content = { button_hotspot = { disable_button = false } } } } }
        end
        return s
    end

    H.test("MP login entry shares one private query across all four existing targets", function()
        local s = installed(true)
        local expected = { "BackendInterfacePeddlerPlayFab.claim_login_rewards",
            "StoreLoginRewardsPopup._create_ui_elements", "StoreLoginRewardsPopup._claim_rewards",
            "HeroWindowGotwfOverview._claim_daily_reward" }
        H.equal(#s.order, #expected)
        for i, name in ipairs(expected) do H.equal(s.order[i], name) end
        H.equal(type(s.query), "function"); H.equal(s.calendar_query, s.query)
        H.equal(type(s.checks.issue1684_login_request_authority), "function")
        H.equal(s.checks.issue1684_login_request_authority(), nil)
        H.equal(#s.queue, 0); H.equal(s.env.MODDED_REALM, true)
        H.equal(rawget(s.flag, "eac-untrusted"), nil)
    end)

    H.test("MP login known official false reaches complete native claim and recording queue", function()
        local s = installed(false, { flag = true })
        local external = {}; local result = pack(s:claim(nil, external, -1))
        H.equal(result.n, 0); H.equal(#s.queue, 1)
        local row = s.queue[1]
        H.equal(row.request.FunctionName, "claimStoreRewards")
        H.equal(row.request.FunctionParameter.offset, -1)
        H.equal(row.eac, true); H.equal(type(row.callback), "function")
        H.equal(s.callback_external, external); H.equal(s.callback_offset, -1)
        H.equal(s.peddler._is_done_claiming, false); H.equal(s.fallback_calls, 0)
        H.equal(s.env.MODDED_REALM, false); H.equal(rawget(s.flag, "eac-untrusted"), true)
    end)

    H.test("MP login native modded true refuses exact native request before enqueue", function()
        local s = installed(true)
        H.equal(s:claim(nil, {}, 0), nil); H.equal(#s.queue, 0)
        H.equal(s.peddler._is_done_claiming, true); H.equal(s.fallback_calls, 0)
    end)

    for _, spec in ipairs({ { name = "string", value = "false" },
            { name = "number", value = 0 }, { name = "table", value = {} } }) do
        local case = spec
        H.test("MP login actual request guard refuses malformed native " .. case.name, function()
            local s = installed(case.value, { flag = true })
            H.equal(s:claim(nil, {}, 0), nil)
            H.equal(#s.queue, 0, "malformed authority reached native claimStoreRewards")
            H.equal(s.peddler._is_done_claiming, true); H.equal(s.fallback_calls, 0)
            local popup, calls = s:popup(), 0
            local result = s.hooks["StoreLoginRewardsPopup._claim_rewards"](
                function() calls = calls + 1 end, popup, {})
            H.equal(result, nil); H.equal(calls, 0)
            H.equal(popup._widgets_by_name.claim_button.content.button_hotspot.disable_button, true)
            s.hooks["HeroWindowGotwfOverview._claim_daily_reward"](
                function() calls = calls + 1 end, {}, 0)
            H.equal(calls, 0); H.equal(s.env.MODDED_REALM, case.value)
        end)
    end

    for _, spec in ipairs({ { name = "true", value = true, queues = 0 },
            { name = "false", value = false, queues = 1 }, { name = "absent", queues = 1 } }) do
        local case = spec
        H.test("MP login raw-absent native preserves real legacy " .. case.name .. " fallback", function()
            local s = installed(nil, { flag = case.value })
            s:claim(nil, {}, 0)
            H.equal(#s.queue, case.queues); H.equal(s.fallback_calls, 1)
            H.equal(rawget(s.env, "MODDED_REALM"), nil)
            H.equal(rawget(s.flag, "eac-untrusted"), case.value)
        end)
    end

    H.test("MP login absent-native nil reader refuses but legacy reader throw preserves exact error", function()
        local unknown = installed(nil, { reader = function() return nil end })
        H.equal(unknown:claim(nil, {}, 0), nil); H.equal(#unknown.queue, 0)
        local failure = {}; local s = installed(nil, { reader = function() error(failure) end })
        local ok, err = pcall(function() s:claim(nil, {}, 0) end)
        H.equal(ok, false); H.equal(err, failure); H.equal(#s.queue, 0)
        local popup, calls = s:popup(), 0
        ok, err = pcall(s.hooks["StoreLoginRewardsPopup._claim_rewards"],
            function() calls = calls + 1 end, popup)
        H.equal(ok, false); H.equal(err, failure); H.equal(calls, 0)
        -- The existing calendar policy intentionally catches the SAME reader.
        H.equal(s.hooks["HeroWindowGotwfOverview._claim_daily_reward"](
            function() calls = calls + 1 end, {}, 0), nil)
        H.equal(calls, 0); H.equal(#s.queue, 0)
    end)

    H.test("MP login official installed boundaries preserve varargs nil holes zero returns and errors", function()
        local s = installed(false)
        local popup, marker, tail = s:popup(), {}, {}
        for _, name in ipairs({ "BackendInterfacePeddlerPlayFab.claim_login_rewards",
                "StoreLoginRewardsPopup._create_ui_elements", "StoreLoginRewardsPopup._claim_rewards",
                "HeroWindowGotwfOverview._claim_daily_reward" }) do
            local receiver = name:find("BackendInterface", 1, true) and s.peddler or popup
            local callback = s.hooks[name]
            local result = pack(callback(function(self, ...)
                H.equal(self, receiver); local args = pack(...)
                H.equal(args.n, 4); H.equal(args[1], marker); H.equal(args[2], nil)
                H.equal(args[3], tail); H.equal(args[4], nil)
                return marker, nil, tail, nil
            end, receiver, marker, nil, tail, nil))
            H.equal(result.n, 4); H.equal(result[1], marker); H.equal(result[2], nil)
            H.equal(result[3], tail); H.equal(result[4], nil)
            H.equal(pack(callback(function() end, receiver)).n, 0)
            local failure = {}; local ok, err = pcall(callback, function() error(failure) end, receiver)
            H.equal(ok, false); H.equal(err, failure)
        end
        H.equal(#s.queue, 0); H.equal(popup._widgets_by_name.claim_button.content.button_hotspot.disable_button, false)
    end)

    H.test("MP login popup creation retains post-native query timing and malformed disable", function()
        local s = installed("false")
        local popup, marker, calls = s:popup(), {}, 0
        local result = pack(s.hooks["StoreLoginRewardsPopup._create_ui_elements"](function(self)
            calls = calls + 1; H.equal(self, popup)
            H.equal(popup._widgets_by_name.claim_button.content.button_hotspot.disable_button, false)
            return marker, nil
        end, popup))
        H.equal(calls, 1); H.equal(result.n, 2); H.equal(result[1], marker); H.equal(result[2], nil)
        H.equal(popup._widgets_by_name.claim_button.content.button_hotspot.disable_button, true)
        local failure = {}; local throwing = installed(nil, { reader = function() error(failure) end })
        local ok, err = pcall(throwing.hooks["StoreLoginRewardsPopup._create_ui_elements"],
            function() calls = calls + 1 end, throwing:popup())
        H.equal(ok, false); H.equal(err, failure); H.equal(calls, 2)
        H.equal(#s.queue, 0); H.equal(#throwing.queue, 0)
    end)

    H.test("MP login shared private query reads changing native authority without rebinding", function()
        local s = installed(true)
        local query = s.query
        s:claim(nil, {}, 0); H.equal(#s.queue, 0)
        s.env.MODDED_REALM = "false"; s:claim(nil, {}, 0); H.equal(#s.queue, 0)
        s.env.MODDED_REALM = false; s:claim(nil, {}, 0); H.equal(#s.queue, 1)
        H.equal(s.query, query); H.equal(s.calendar_query, query); H.equal(s.fallback_calls, 0)
    end)
end
