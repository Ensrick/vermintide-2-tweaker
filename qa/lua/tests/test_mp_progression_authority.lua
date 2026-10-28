return function(H, repo)
    local dir = "/modded_progression/scripts/mods/modded_progression/"
    local function read(path)
        local f = assert(io.open(path, "rb")); local text = f:read("*a"); f:close()
        return (text:gsub("\r\n", "\n"))
    end
    local entry = read(repo .. dir .. "modded_progression.lua")
    local Realm = assert(loadfile(repo .. dir .. "_lib_modded_realm_authority.lua"))()
    local QuestBoundary = assert(loadfile(repo .. dir .. "_mp_quest_boundary.lua"))()
    local function pack(...) return { n = select("#", ...), ... } end
    local targets = { "BackendInterfaceQuestsPlayfab.claim_quest_rewards",
        "BackendInterfaceQuestsPlayfab.claim_multiple_quest_rewards",
        "BackendInterfacePeddlerPlayFab.exchange_chips", "BackendInterfaceQuestsPlayfab.update_quests" }
    local function section(first, last)
        local at = assert(entry:find(first, 1, true), first)
        local stop = assert(entry:find(last, at, true), last)
        H.equal(entry:find(first, at + #first, true), nil, "duplicate source owner")
        return entry:sub(at, stop - 1)
    end
    -- The separately authorized old-source control supplies immutable 8d0
    -- entry bytes at this SAME VFS path; no historical checkout/fallback file.
    local query_name = entry:find("local function _progression_realm(", 1, true)
        and "_progression_realm" or "_login_realm"
    local query = section("local function " .. query_name .. "(",
        "local function _route_store_login_claim_for_realm(")
    local blocks = {}
    for _, target in ipairs(targets) do
        local class, method = target:match("^(.+)%.([^.]+)$")
        local at = assert(entry:find('mod:hook("' .. class .. '", "' .. method .. '"', 1, true))
        local stop = assert(entry:find("\nend)", at, true)) + 4
        blocks[#blocks + 1] = { at = at, source = entry:sub(at, stop) }
    end
    table.sort(blocks, function(a, b) return a.at < b.at end)
    local hook_source = {}
    for _, block in ipairs(blocks) do hook_source[#hook_source + 1] = block.source end
    local function installed(native, options)
        options = options or {}
        local s = { hooks = {}, order = {}, queue = {}, callbacks = {},
            fallback_calls = 0, local_calls = 0, local_args = nil, flag = {}, logs = 0, ensure_calls = 0 }
        rawset(s.flag, "eac-untrusted", options.flag)
        local env = setmetatable({}, { __index = _G }); env._G = env
        env.MODDED_REALM = native
        env.callback = function(self, method, ...)
            s.callbacks[#s.callbacks + 1] = { self = self, method = method, args = pack(...) }
            return function() error("recording queue must NEVER dispatch callbacks") end
        end
        local queue = {
            enqueue = function(_, request, cb, eac)
                s.queue[#s.queue + 1] = { kind = "cloud", request = request, cb = cb, eac = eac }
            end,
            enqueue_api_request = function(_, api, request, cb, err)
                s.queue[#s.queue + 1] = { kind = "api", api = api, request = request, cb = cb, err = err }
            end,
        }
        local mirror = { request_queue = function() return queue end }
        local q = assert(loadfile(repo .. "/qa/lua/fixtures/mp_quest_write_requests_native_6_13.lua"))
        setfenv(q, env); s.native_quests = q()
        local p = assert(loadfile(repo .. "/qa/lua/fixtures/mp_exchange_chips_native_6_13.lua"))
        setfenv(p, env); s.native_exchange = p()
        local refresh = assert(loadfile(repo .. "/qa/lua/fixtures/mp_quest_refresh_native_6_13.lua"))
        setfenv(refresh, env); s.native_refresh = refresh()
        s.quests = { _last_id = 40, _new_id = s.native_quests._new_id, _backend_mirror = mirror }
        s.peddler = { _backend_mirror = mirror }
        s.refresh_state = { _backend_mirror = mirror, _quests_updating = false,
            _quests = { event = {} }, _dirty = false, _quest_timer = 10,
            _daily_quest_update_time = 9, _event_quest_update_times = {},
            get_daily_quest_update_time = s.native_refresh.get_daily_quest_update_time,
            get_weekly_quest_update_time = s.native_refresh.get_weekly_quest_update_time,
            get_time_left_on_event_quest = s.native_refresh.get_time_left_on_event_quest }
        local function fallback()
            s.fallback_calls = s.fallback_calls + 1
            if options.reader then return options.reader() end
            return Realm.is_modded(s.flag, options.depth or 0, options.development, env)
        end
        local owner = { hook = function(_, class, method, fn)
            local name = class .. "." .. method
            H.equal(s.hooks[name], nil, "duplicate installed write hook")
            s.hooks[name] = fn; s.order[#s.order + 1] = name
        end }
        local loader = assert(loadstring("return function(mod, _is_mp_realm, Dailies, _mp577_local_exchange, _dbg_alert, QuestBoundary)\n"
            .. query .. "\n" .. table.concat(hook_source, "\n") .. "\nreturn " .. query_name .. "\nend",
            "@actual-mp-write-boundaries"))
        setfenv(loader, env)
        s.query = loader()(owner, fallback, { REWARD_KIND = "SM", ensure = function()
            s.ensure_calls = s.ensure_calls + 1
            if options.ensure then return options.ensure() end
        end }, function(...)
            -- Routing collaborator only; no Dailies ledger/grant is executed.
            s.local_calls = s.local_calls + 1; s.local_args = pack(...)
            if options.local_exchange then return options.local_exchange(...) end
            return "local", nil, s, nil
        end, function() s.logs = s.logs + 1 end, QuestBoundary)
        s.env = env
        function s:single(key, fn, ...)
            return self.hooks[targets[1]](fn or self.native_quests.claim_quest_rewards, self.quests, key, ...)
        end
        function s:multiple(keys, fn, ...)
            return self.hooks[targets[2]](fn or self.native_quests.claim_multiple_quest_rewards, self.quests, keys, ...)
        end
        function s:exchange(currency, cb, fn, ...)
            return self.hooks[targets[3]](fn or self.native_exchange, self.peddler,
                "opaque_item", currency, 7, cb, ...)
        end
        function s:refresh(cb, fn, ...)
            return self.hooks[targets[4]](fn or self.native_refresh.update_quests, self.refresh_state, cb, ...)
        end
        return s
    end
    local function refused(s)
        -- ONE SAME assertion for old-entry, query-handoff and unsupported-
        -- delegate controls. Never reinterpret parser/setup errors as red proof.
        H.equal(#s.queue, 0, "unauthorized authority reached native write queue")
        H.equal(s.quests._last_id, 40, "denial mutated native quest poll id")
        H.equal(#s.callbacks, 0, "denial constructed native callbacks")
        H.equal(s.local_calls, 0)
    end
    local function unchanged_refresh(s)
        H.equal(s.refresh_state._quests_updating, false)
        H.equal(s.refresh_state._quests_updated_cb, nil)
        H.equal(s.refresh_state._quest_timer, 10); H.equal(s.refresh_state._daily_quest_update_time, 9)
        H.equal(s.refresh_state._dirty, false)
    end
    local function deny_four(s)
        local result = pack(s:single("opaque_quest")); refused(s)
        H.equal(result.n, 1); H.equal(result[1], nil)
        result = pack(s:multiple({ "opaque_quest", "opaque_other" })); refused(s)
        H.equal(result.n, 1); H.equal(result[1], nil)
        local calls, args = 0, nil
        result = pack(s:exchange("SM", function(...) calls = calls + 1; args = pack(...) end))
        refused(s); H.equal(result.n, 1); H.equal(result[1], nil)
        H.equal(calls, 1); H.equal(args.n, 1); H.equal(args[1], false)
        calls = 0
        result = pack(s:refresh(function() calls = calls + 1 end)); refused(s)
        H.equal(result.n, 1); H.equal(result[1], nil); H.equal(calls, 0)
        H.equal(s.ensure_calls, 0); unchanged_refresh(s)
    end

    H.test("MP progression installs exactly four existing backend targets", function()
        local s = installed(true)
        H.equal(#s.order, 4)
        for i, name in ipairs({ targets[4], targets[3], targets[1], targets[2] }) do H.equal(s.order[i], name) end
        H.equal(type(s.query), "function"); H.equal(s.fallback_calls, 0)
        refused(s)
    end)
    H.test("MP writes actual queue oracle refuses malformed and unsupported authority", function()
        local s = installed("false", { flag = true }); deny_four(s)
        H.equal(s.fallback_calls, 0); H.equal(s.env.MODDED_REALM, "false")
        local unsupported = installed(true)
        local calls = 0
        H.equal(unsupported:exchange("VS", function(value) calls = calls + 1; H.equal(value, false) end), nil)
        refused(unsupported); H.equal(calls, 1)
    end)
    for _, spec in ipairs({ { name = "number", value = 0 }, { name = "table", value = {} } }) do
        local case = spec
        H.test("MP writes actual native queues refuse malformed " .. case.name, function()
            local s = installed(case.value, { flag = false }); deny_four(s)
            H.equal(s.fallback_calls, 0); H.equal(s.env.MODDED_REALM, case.value)
            H.equal(rawget(s.flag, "eac-untrusted"), false)
        end)
    end
    H.test("MP writes known official false reaches all complete native producers", function()
        local s = installed(false, { flag = true })
        H.equal(s:single("opaque_quest"), 41)
        H.equal(s:multiple({ "opaque_quest", "opaque_other" }), 42)
        local external = function() error("external callback must not dispatch") end
        H.equal(pack(s:exchange("SM", external)).n, 0)
        H.equal(pack(s:exchange("VS", external)).n, 0)
        H.equal(#s.queue, 4); H.equal(s.quests._last_id, 42)
        local single, multiple, purchase = s.queue[1], s.queue[2], s.queue[3]
        H.equal(single.kind, "cloud"); H.equal(single.request.FunctionName, "generateQuestRewards")
        H.equal(single.request.FunctionParameter.quest_key, "opaque_quest")
        H.equal(single.request.FunctionParameter.id, 41); H.equal(single.eac, true)
        H.equal(multiple.request.FunctionName, "generateQuestRewards"); H.equal(multiple.eac, true)
        H.equal(multiple.request.FunctionParameter.id, 42)
        H.equal(#multiple.request.FunctionParameter.quest_data, 2)
        H.equal(multiple.request.FunctionParameter.quest_data[2].quest_key, "opaque_other")
        H.equal(purchase.kind, "api"); H.equal(purchase.api, "PurchaseItem")
        H.equal(purchase.request.StoreId, "Store"); H.equal(purchase.request.ItemId, "opaque_item")
        H.equal(purchase.request.VirtualCurrency, "SM"); H.equal(purchase.request.Price, 7)
        H.equal(s.queue[4].request.VirtualCurrency, "VS")
        H.equal(type(purchase.cb), "function"); H.equal(type(purchase.err), "function")
        H.equal(s.callbacks[1].method, "quest_rewards_request_cb")
        H.equal(s.callbacks[2].method, "claim_multiple_quest_rewards_request_cb")
        H.equal(s.callbacks[3].method, "_exchange_chips_success_cb")
        H.equal(s.callbacks[3].args[1], external)
        H.equal(s.callbacks[4].method, "_exchange_chips_error_cb")
        H.equal(s.local_calls, 0); H.equal(s.fallback_calls, 0)
        H.equal(s.env.MODDED_REALM, false); H.equal(rawget(s.flag, "eac-untrusted"), true)
    end)
    H.test("MP writes modded quests refuse while SM preserves exact local exchange handoff", function()
        local s = installed(true)
        H.equal(s:single("opaque_quest"), nil); H.equal(s:multiple({}), nil); refused(s)
        local cb = function() end
        local result = pack(s:exchange("SM", cb))
        H.equal(result.n, 4); H.equal(result[1], "local"); H.equal(result[2], nil)
        H.equal(result[3], s); H.equal(result[4], nil); H.equal(s.local_calls, 1)
        H.equal(s.local_args.n, 4); H.equal(s.local_args[1], s.peddler)
        H.equal(s.local_args[2], "opaque_item"); H.equal(s.local_args[3], 7); H.equal(s.local_args[4], cb)
        H.equal(#s.queue, 0); H.equal(s.quests._last_id, 40)
        local failure = {}; local throwing = installed(true, { local_exchange = function() error(failure) end })
        local ok, err = pcall(function() throwing:exchange("SM", cb) end)
        H.equal(ok, false); H.equal(err, failure); H.equal(throwing.local_calls, 1)
        H.equal(#throwing.queue, 0); H.equal(throwing.quests._last_id, 40)
    end)
    for _, spec in ipairs({ { name = "true", value = true, queues = 0 },
            { name = "false", value = false, queues = 3 }, { name = "absent", queues = 3 } }) do
        local case = spec
        H.test("MP writes raw-absent native preserves legacy " .. case.name .. " fallback", function()
            local s = installed(nil, { flag = case.value })
            s:single("opaque_quest"); s:multiple({ "opaque_quest" }); s:exchange("VS", function() end)
            H.equal(#s.queue, case.queues); H.equal(s.fallback_calls, 3)
            H.equal(s.quests._last_id, case.queues == 0 and 40 or 42)
            H.equal(s.local_calls, 0); H.equal(rawget(s.env, "MODDED_REALM"), nil)
            H.equal(rawget(s.flag, "eac-untrusted"), case.value)
        end)
    end
    H.test("MP writes absent-native nil reader denies before all native effects", function()
        local s = installed(nil, { reader = function() return nil end }); deny_four(s)
        H.equal(s.fallback_calls, 4)
    end)
    H.test("MP writes reader throws preserve exact error before callbacks or native effects", function()
        local failure = {}; local s = installed(nil, { reader = function() error(failure) end })
        local calls = 0
        for _, invoke in ipairs({ function() s:single("opaque_quest") end,
                function() s:multiple({}) end,
                function() s:exchange("VS", function() calls = calls + 1 end) end,
                function() s:refresh(function() calls = calls + 1 end) end }) do
            local ok, err = pcall(invoke); H.equal(ok, false); H.equal(err, failure); refused(s)
        end
        H.equal(calls, 0); H.equal(s.fallback_calls, 4); H.equal(s.ensure_calls, 0); unchanged_refresh(s)
    end)
    H.test("MP writes official callbacks preserve exact arguments tuples zero returns and errors", function()
        local s = installed(false); local marker, tail, cb = {}, {}, function() end
        for i = 1, 3 do
            local target = targets[i]
            local self = i == 3 and s.peddler or s.quests
            local args = i == 3 and pack(marker, "SM", 7, cb, nil, tail, nil) or pack(marker, nil, tail, nil)
            local function invoke(fn) return s.hooks[target](fn, self, unpack(args, 1, args.n)) end
            local result = pack(invoke(function(got, ...)
                H.equal(got, self); local actual = pack(...); H.equal(actual.n, args.n)
                for j = 1, args.n do H.equal(actual[j], args[j]) end
                return marker, nil, tail, nil
            end))
            H.equal(result.n, 4); H.equal(result[1], marker); H.equal(result[2], nil)
            H.equal(result[3], tail); H.equal(result[4], nil)
            H.equal(pack(invoke(function() end)).n, 0)
            local failure = {}; local ok, err = pcall(invoke, function() error(failure) end)
            H.equal(ok, false); H.equal(err, failure)
        end
        refused(s)
    end)
    H.test("MP writes denied purchase callback is exactly once false and preserves throws", function()
        local s = installed(true); local calls, args = 0, nil
        local result = pack(s:exchange("VS", function(...) calls = calls + 1; args = pack(...); return "ignored", nil end))
        H.equal(calls, 1); H.equal(args.n, 1); H.equal(args[1], false)
        H.equal(result.n, 1); H.equal(result[1], nil); refused(s)
        local failure = {}; calls = 0
        local ok, err = pcall(function() s:exchange("VS", function() calls = calls + 1; error(failure) end) end)
        H.equal(ok, false); H.equal(err, failure); H.equal(calls, 1); refused(s)
    end)
    H.test("MP writes denied purchase ignores absent or nonfunction callbacks", function()
        for _, value in ipairs({ true, "false" }) do
            local s = installed(value); H.equal(s:exchange("VS", nil), nil); refused(s)
            for _, cb in ipairs({ false, 0, "not_callback", {} }) do
                H.equal(s:exchange("VS", cb), nil); refused(s)
            end
        end
    end)
    H.test("MP writes private authority is read dynamically for three writer callbacks", function()
        local s = installed(true); local original = s.query
        for _, value in ipairs({ "false", false, true }) do
            s.env.MODDED_REALM = value
            s:single("opaque_quest"); s:multiple({}); s:exchange("VS", function() end)
        end
        H.equal(#s.queue, 3); H.equal(s.quests._last_id, 42)
        H.equal(s.query, original); H.equal(s.local_calls, 0); H.equal(s.fallback_calls, 0)
    end)
    for _, spec in ipairs({ { name = "launch", development = { application_parameter = { ["eac-untrusted"] = true } } },
            { name = "depth", depth = 1 } }) do
        local case = spec
        H.test("MP writes absent-native real shared " .. case.name .. " authority refuses official writes", function()
            local s = installed(nil, case)
            s:single("opaque_quest"); s:multiple({}); s:exchange("VS", function() end)
            refused(s); H.equal(s.fallback_calls, 3); H.equal(rawget(s.env, "MODDED_REALM"), nil)
        end)
    end
    H.test("MP refresh official expired timer reaches complete native getQuests producer", function()
        local s = installed(false); local cb = function() error("must not dispatch") end
        H.equal(pack(s:refresh(cb)).n, 0)
        H.equal(#s.queue, 1); H.equal(s.queue[1].request.FunctionName, "getQuests")
        H.equal(s.queue[1].eac, false); H.equal(s.callbacks[1].method, "get_quests_cb")
        H.equal(s.refresh_state._quests_updating, true); H.equal(s.refresh_state._quests_updated_cb, cb)
        H.equal(s.refresh_state._quest_timer, 10); H.equal(s.ensure_calls, 0)
        local marker = {}
        local result = pack(s:refresh(cb, function(self, ...)
            H.equal(self, s.refresh_state); local args = pack(...)
            H.equal(args.n, 1); H.equal(args[1], cb); return marker, nil, 3, nil
        end, "unused", nil))
        H.equal(result.n, 4); H.equal(result[1], marker); H.equal(result[2], nil)
        H.equal(result[3], 3); H.equal(result[4], nil)
        H.equal(pack(s:refresh(cb, function() end)).n, 0)
        local failure = {}; local ok, err = pcall(function()
            s:refresh(cb, function() error(failure) end)
        end)
        H.equal(ok, false); H.equal(err, failure); H.equal(#s.queue, 1)
    end)
    H.test("MP refresh official updating or current timers keep native no-request behavior", function()
        for _, mode in ipairs({ "updating", "current" }) do
            local s = installed(false)
            if mode == "updating" then s.refresh_state._quests_updating = true
            else s.refresh_state._daily_quest_update_time = 11 end
            local calls = 0
            H.equal(pack(s:refresh(function() calls = calls + 1 end)).n, 0)
            H.equal(#s.queue, 0); H.equal(calls, 0); H.equal(s.ensure_calls, 0)
            H.equal(#s.callbacks, 0); H.equal(s.refresh_state._quest_timer, 10)
            H.equal(s.refresh_state._quests_updating, mode == "updating")
        end
    end)
    H.test("MP refresh modded true retains local ensure callback and exact errors", function()
        local s = installed(true); local calls = 0
        H.equal(s:refresh(function() calls = calls + 1 end), nil)
        H.equal(s.ensure_calls, 1); H.equal(calls, 1); refused(s); unchanged_refresh(s)
        local failure = {}; local bad = installed(true, { ensure = function() error(failure) end })
        calls = 0
        local ok, err = pcall(function() bad:refresh(function() calls = calls + 1 end) end)
        H.equal(ok, false); H.equal(err, failure); H.equal(bad.ensure_calls, 1); H.equal(calls, 0)
        refused(bad); unchanged_refresh(bad)
        calls = 0
        ok, err = pcall(function() s:refresh(function() calls = calls + 1; error(failure) end) end)
        H.equal(ok, false); H.equal(err, failure); H.equal(calls, 1); H.equal(s.ensure_calls, 2)
        refused(s); unchanged_refresh(s)
    end)
    H.test("MP refresh raw-absent legacy authority retains refresh ownership", function()
        for _, spec in ipairs({ { flag = true, queued = 0 }, { flag = false, queued = 1 }, { queued = 1 } }) do
            local s = installed(nil, spec); local calls = 0
            s:refresh(function() calls = calls + 1 end)
            H.equal(#s.queue, spec.queued); H.equal(s.fallback_calls, 1)
            H.equal(s.ensure_calls, spec.queued == 0 and 1 or 0)
            H.equal(calls, spec.queued == 0 and 1 or 0)
            H.equal(rawget(s.env, "MODDED_REALM"), nil); H.equal(rawget(s.flag, "eac-untrusted"), spec.flag)
            H.equal(s.refresh_state._quest_timer, 10)
        end
    end)
    H.test("MP refresh unknown legacy result leaves all native and local refresh state alone", function()
        for _, reader in ipairs({ function() return nil end, function() return "false" end,
                function() return 0 end, function() return {} end }) do
            local s = installed(nil, { reader = reader }); local calls = 0
            H.equal(s:refresh(function() calls = calls + 1 end), nil)
            refused(s); unchanged_refresh(s); H.equal(s.ensure_calls, 0); H.equal(calls, 0)
            H.equal(s.fallback_calls, 1)
            s.env.MODDED_REALM = false
            s:refresh(function() calls = calls + 1 end)
            H.equal(#s.queue, 1); H.equal(s.refresh_state._quests_updating, true)
            H.equal(s.fallback_calls, 1); H.equal(calls, 0)
        end
    end)
end
