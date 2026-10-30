return function(H, repo_root)
    local Census = dofile(repo_root
        .. "/modded_progression/scripts/mods/modded_progression/_mp_diag_fresh_profile.lua")
    local source_root = repo_root .. "/../Vermintide-2-Source-Code/scripts/"
    local manager_path = source_root .. "managers/backend_playfab/backend_manager_playfab.lua"

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function exists(path)
        local file = io.open(path, "rb")
        if file then file:close() end
        return file ~= nil
    end

    local function interface(spec, mirror)
        local value = { [spec.mirror_field] = mirror }
        for _, method in ipairs(spec.methods) do value[method] = function() end end
        return value
    end
    local function complete_backend()
        local mirror, backend = {}, { _interfaces = {} }
        backend._backend_mirror = mirror
        for _, method in ipairs(Census.MANAGER_METHODS) do backend[method] = function() end end
        for _, spec in ipairs(Census.PROFILE_INTERFACES) do
            backend._interfaces[spec.name] = interface(spec, mirror)
        end
        return backend
    end

    H.test("MP #840 census catalog is closed and source-slice explicit", function()
        H.equal(Census.validate_catalog(), true)
        H.equal(#Census.PROFILE_INTERFACES, 9)
        H.equal(Census.PROFILE_INTERFACES[1].name, "items")
        H.equal(Census.PROFILE_INTERFACES[4].name, "peddler")
        H.equal(Census.PROFILE_INTERFACES[6].name, "quests")
        H.equal(Census.PROFILE_INTERFACES[9].name, "keep_decorations")
    end)

    H.test_if(exists(manager_path),
        "MP #840 census retains the decompiled manager override and mirror contract", function()
        local manager = read(manager_path)
        H.truthy(manager:find("BackendManagerPlayFab.add_loadout_interface_override", 1, true))
        H.truthy(manager:find("BackendManagerPlayFab.add_talents_interface_override", 1, true))
        H.truthy(manager:find("BackendManagerPlayFab.set_total_power_level_interface_for_game_mode", 1, true))
        H.truthy(manager:find("return self._interfaces[interface_name]", 1, true))
        H.truthy(manager:find("BackendManagerPlayFab.get_read_only_data", 1, true))
        H.truthy(manager:find("BackendManagerPlayFab.get_backend_mirror", 1, true))

        local statistics = read(source_root
            .. "managers/backend_playfab/backend_interface_statistics_playfab.lua")
        local peddler = read(source_root
            .. "managers/backend_playfab/backend_interface_peddler_playfab.lua")
        local store = read(source_root .. "settings/dlcs/store/store_common_settings.lua")
        H.truthy(statistics:find("self._mirror = mirror", 1, true))
        H.truthy(peddler:find("self._backend_mirror = backend_mirror", 1, true))
        H.truthy(store:find('playfab_class = "BackendInterfacePeddlerPlayFab"', 1, true))
        end, "optional decompiled vanilla source is not present in this clean clone")

    H.test("MP #840 complete interfaces retain canonical mirror identity", function()
        local report = Census.audit(complete_backend())
        local summary = Census.summary(report)
        H.equal(summary.present, 9)
        H.equal(summary.methods_missing, 0)
        H.equal(summary.manager_methods_missing, 0)
        H.equal(summary.mirror_mismatch, 0)
        H.equal(summary.topology_complete, true)
        H.equal(summary.all_share_canonical, true)
    end)

    H.test("MP #840 census exposes missing and split interface boundaries", function()
        local backend = complete_backend()
        backend._interfaces.items.get_loadout = nil
        backend._interfaces.peddler._backend_mirror = {}
        backend._interfaces.statistics = nil
        backend.get_read_only_data = nil
        local summary = Census.summary(Census.audit(backend))
        H.equal(summary.present, 8)
        H.equal(summary.methods_missing, 1)
        H.equal(summary.manager_methods_missing, 1)
        H.equal(summary.mirror_mismatch, 1)
        H.equal(summary.topology_complete, false)
        H.equal(summary.all_share_canonical, false)
    end)

    H.test("MP #840 census fails closed when a mirror field is absent", function()
        local backend = complete_backend()
        backend._interfaces.statistics._mirror = nil
        local summary = Census.summary(Census.audit(backend))
        H.equal(summary.present, 9)
        H.equal(summary.methods_missing, 0)
        H.equal(summary.mirror_mismatch, 1)
        H.equal(summary.topology_complete, false)
        H.equal(summary.all_share_canonical, false)
    end)

    H.test("MP #840 production remains read-only and emits bounded engine diagnostics", function()
        local path = repo_root
            .. "/modded_progression/scripts/mods/modded_progression/modded_progression.lua"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find('mod:command("mp_fresh_profile_census"', 1, true))
        H.truthy(source:find("_mp840_capture_when_backend_ready", 1, true))
        H.equal(source:find("FreshProfileCensus.audit", 1, true) ~= nil, true)
        H.truthy(source:find('printf("[mp:840]', 1, true))
        H.equal(source:find('mod:echo("#840', 1, true), nil)

        local module_path = repo_root
            .. "/modded_progression/scripts/mods/modded_progression/_mp_diag_fresh_profile.lua"
        local module_file = assert(io.open(module_path, "rb"))
        local module_source = module_file:read("*a")
        module_file:close()
        H.equal(module_source:find("Managers", 1, true), nil)
        H.equal(module_source:find("mod:", 1, true), nil)
    end)
    -- #1684: load the actual pure owner inside each selected body, not through
    -- the file-local #840 instance, so source controls consume it exactly once.
    local function login_owner()
        return assert(loadfile(repo_root
            .. "/modded_progression/scripts/mods/modded_progression/_mp_diag_fresh_profile.lua"))()
    end
    local function login_payload(schema)
        return { event_type = schema or "personal_time_strike", total_claims = 2,
            next_claim_timestamp = 1000, end_of_claim_timestamp = 2000,
            start_time = 3000, total_rewards = 28, num_allowed_old_segments_to_claim = 2,
            claimed_rewards = { [1] = 0, [2] = 1 },
            rewards = { [1] = { { reward_type = "currency", currency_code = "SM", amount = 15 } },
                [2] = { { reward_type = "item", item_id = "test_catalogue_key" } } } }
    end
    local function login_backend(payload)
        return { _interfaces = { peddler = { _login_rewards = payload } } }
    end
    local function login_command(owner, backend, options, printer)
        options = options or {}
        local source = read(repo_root
            .. "/modded_progression/scripts/mods/modded_progression/modded_progression.lua"):gsub("\r\n", "\n")
        local first = assert(source:find('mod:command("mp_login_diag"', 1, true))
        H.equal(source:find('mod:command("mp_login_diag"', first + 1, true), nil)
        local last = assert(source:find("\nlocal _mp840_census_backend", first, true))
        local query_at = assert(source:find("local function _progression_realm(", 1, true))
        local query_end = assert(source:find("local function _route_store_login_claim_for_realm(", query_at, true))
        local env = setmetatable({}, { __index = _G }); env._G = env
        env.MODDED_REALM = options.native
        env.Managers = { backend = backend }
        env.GameSettingsDevelopment = { read_only_backend = true, achievements_disabled = true }
        local out = { lines = {}, queries = 0, fallbacks = 0 }
        env.rawget = function(t, key)
            if t == env and key == "MODDED_REALM" then out.queries = out.queries + 1 end
            return rawget(t, key)
        end
        env.printf = printer or function(format, ...)
            out.lines[#out.lines + 1] = string.format(format, ...)
        end
        local mod = { command = function(_, name, help, fn)
            H.equal(name, "mp_login_diag"); H.equal(out.command, nil)
            H.truthy(help:find("<day/index>", 1, true)); out.command = fn
        end }
        local chunk = assert(loadstring("return function(mod, FreshProfileCensus, _is_mp_realm)\n"
            .. source:sub(query_at, query_end - 1) .. source:sub(first, last - 1)
            .. "\nend", "@actual-mp1684-cached-command"))
        setfenv(chunk, env)
        chunk()(mod, owner, function()
            out.fallbacks = out.fallbacks + 1
            if options.throws then error(options.throws) end
            return options.legacy
        end)
        out.env = env
        return out
    end

    H.test("MP1684 actual cache owner keeps rolling and calendar metadata distinct", function()
        local actual, payload = login_owner(), login_payload()
        local backend = login_backend(payload)
        local original_row = payload.rewards[1]
        local calls = 0
        local function poison() calls = calls + 1; error("diagnostic called a backend method") end
        backend.get_interface = poison
        local peddler = backend._interfaces.peddler
        peddler.get_login_rewards, peddler.refresh_login_rewards, peddler.claim_login_rewards = poison, poison, poison
        peddler._backend_mirror = { request_queue = poison, add_item = poison }
        local lines, count = actual.login_cache_lines(backend, true, "1")
        H.equal(count, 11); H.truthy(lines[1]:find("status=observed_cache", 1, true))
        H.equal(lines[2], "total_claims=n:2 next_claim_timestamp=n:1000 end_of_claim_timestamp=n:2000")
        H.truthy(lines[3]:find("currency_code=s:SM amount=n:15", 1, true))
        H.equal(lines[11], "sampled_slots=1-8 slot9_present=false tail=unscanned")
        payload.event_type = "calendar"
        lines, count = actual.login_cache_lines(backend, true, 2)
        H.equal(count, 11)
        H.equal(lines[2], "start_time=n:3000 total_rewards=n:28 old_segments=n:2 claimed_raw_counter=n:1")
        H.truthy(lines[3]:find("catalog_item_key=s:test_catalogue_key", 1, true))
        H.equal(lines[2]:find("total_claims", 1, true), nil)
        H.equal(calls, 0); H.equal(peddler._login_rewards, payload)
        H.equal(payload.rewards[1], original_row); H.equal(original_row[1].amount, 15)
    end)

    H.test("MP1684 cache absence unsupported schema and invalid indices are non-success", function()
        local actual = login_owner()
        local lines, count = actual.login_cache_lines({}, true, 1)
        H.equal(count, 1); H.truthy(lines[1]:find("status=cache_unavailable", 1, true))
        for _, index in ipairs({ "0", "-1", "1.5", "1e2", "2147483648", {}, false, math.huge }) do
            lines, count = actual.login_cache_lines(login_backend(login_payload()), true, index)
            H.equal(count, 1); H.truthy(lines[1]:find("status=invalid_index", 1, true))
        end
        for _, realm in ipairs({ false, "true", 1, {} }) do
            lines, count = actual.login_cache_lines(login_backend(login_payload()), realm, 1)
            H.equal(count, 1); H.truthy(lines[1]:find("status=realm_unavailable", 1, true))
        end
        lines = actual.login_cache_lines(login_backend({ event_type = "new_unsupported_schema" }), true, 1)
        H.truthy(lines[1]:find("status=unsupported_schema", 1, true))
        local payload = login_payload(); payload.next_claim_timestamp = {}
        lines = actual.login_cache_lines(login_backend(payload), true, 1)
        H.truthy(lines[1]:find("status=unsupported_data", 1, true))
        H.truthy(lines[2]:find("next_claim_timestamp=type:table", 1, true))
        lines = actual.login_cache_lines(login_backend(login_payload()), true, 200)
        H.truthy(lines[1]:find("status=unsupported_data", 1, true))
        H.truthy(lines[1]:find("eligibility=unproven grant=none", 1, true))
        for _, malformed in ipairs({ false, 17, "not_a_row" }) do
            local absent = login_payload()
            absent.rewards[1] = malformed
            lines, count = actual.login_cache_lines(login_backend(absent), true, 1)
            H.equal(count, 11)
            H.truthy(lines[1]:find("status=unsupported_data", 1, true),
                "non-table reward rows must report data status, not throw in type()")
        end
        local sparse = login_payload()
        sparse.rewards[1] = { [2] = { reward_type = "currency", currency_code = "SM", amount = 1 } }
        lines, count = actual.login_cache_lines(login_backend(sparse), true, 1)
        H.equal(count, 11)
        H.truthy(lines[1]:find("status=unsupported_data", 1, true))
        H.truthy(lines[4]:find("currency_code=s:SM amount=n:1", 1, true))
    end)

    H.test("MP1684 raw cache reads ignore inherited fields and opaque object behavior", function()
        local actual, reads = login_owner(), 0
        local payload = login_payload()
        local mt = { __index = function(_, key) reads = reads + 1; return payload end,
            __len = function() reads = reads + 1; return 500 end,
            __tostring = function() reads = reads + 1; return "OPAQUE_PRIVATE_ID" end }
        local inherited = setmetatable({}, mt)
        local lines, count = actual.login_cache_lines(inherited, true, 1)
        H.equal(count, 1); H.truthy(lines[1]:find("status=cache_unavailable", 1, true))
        local backend = login_backend(payload)
        for _, t in ipairs({ backend, backend._interfaces, backend._interfaces.peddler, payload,
                payload.rewards, payload.rewards[1], payload.rewards[1][1] }) do setmetatable(t, mt) end
        payload.rewards[1][1].amount = setmetatable({}, mt)
        lines = actual.login_cache_lines(backend, true, 1)
        H.truthy(lines[3]:find("amount=type:table", 1, true))
        H.equal(table.concat(lines, "\n"):find("OPAQUE_PRIVATE_ID", 1, true), nil)
        H.equal(reads, 0, "raw login-cache census must not invoke inherited/object behavior")
    end)

    H.test("MP1684 eight-slot output sanitizes catalogue keys and excludes owned identifiers", function()
        local actual, payload = login_owner(), login_payload()
        local row = payload.rewards[1]
        for i = 1, 9 do row[i] = { reward_type = "item", item_id = string.rep("k", 120) .. "\n",
            ItemInstanceId = "OWNED_INSTANCE_SECRET", backend_id = "BACKEND_SECRET",
            player_id = "PLAYER_SECRET", steam_backend_unique_id = "STEAM_SECRET" } end
        row[1].currency_code = "SM\r\ninjected"
        row[2].amount = math.huge
        row[3].item_id = "x request=write value"
        row[9].item_id = "NINTH_SECRET"
        payload.account_id = "ACCOUNT_SECRET"
        local lines, count = actual.login_cache_lines(login_backend(payload), true, 1)
        H.equal(count, 11, "login cache output must remain exactly eleven bounded rows")
        H.truthy(lines[1]:find("status=unsupported_data", 1, true))
        local text = table.concat(lines, "\n")
        for i = 1, count do
            H.truthy(#lines[i] <= 700); H.equal(lines[i]:find("[^ -~]"), nil)
        end
        H.truthy(lines[3]:find("currency_code=s:SM??injected", 1, true))
        H.truthy(lines[4]:find("amount=n:nonfinite", 1, true))
        H.truthy(lines[3]:find("catalog_item_key=s:" .. string.rep("k", 95) .. "~", 1, true),
            "catalogue projection must retain the native catalog item key")
        H.truthy(lines[5]:find("catalog_item_key=s:x?request?write?value", 1, true))
        H.equal(text:find("request=write", 1, true), nil)
        H.truthy(lines[11]:find("slot9_present=true tail=unscanned", 1, true))
        H.equal(text:find("SECRET", 1, true), nil, "only catalogue keys, never owned/account identifiers")
        H.truthy(#text + 11 * 11 < 8192)
    end)

    H.test("MP1684 actual command uses one native-first query without backend operations", function()
        local actual, payload = login_owner(), login_payload()
        local backend = login_backend(payload)
        local calls = 0
        local function poison() calls = calls + 1; error("request operation reached") end
        backend.get_interface = poison
        backend._interfaces.peddler.refresh_login_rewards = poison
        backend._interfaces.peddler.claim_login_rewards = poison
        for _, spec in ipairs({
            { native = true, expected = "status=observed_cache", n = 11, fallback = 0 },
            { native = false, expected = "status=realm_unavailable", n = 1, fallback = 0 },
            { native = "false", expected = "status=realm_unavailable", n = 1, fallback = 0 },
            { legacy = true, expected = "status=observed_cache", n = 11, fallback = 1 },
            { legacy = false, expected = "status=realm_unavailable", n = 1, fallback = 1 },
            { throws = {}, expected = "status=realm_unavailable", n = 1, fallback = 1 },
        }) do
            local s = login_command(actual, backend, spec)
            s.command("1")
            H.equal(#s.lines, spec.n, "native-first realm denial must not sample login cache")
            H.truthy(s.lines[1]:find(spec.expected, 1, true))
            H.equal(s.queries, 1, "new command must query mutable realm exactly once")
            H.equal(s.fallbacks, spec.fallback)
            H.equal(s.env.MODDED_REALM, spec.native)
            H.equal(s.env.GameSettingsDevelopment.read_only_backend, true)
            H.equal(s.env.GameSettingsDevelopment.achievements_disabled, true)
        end
        H.equal(calls, 0); H.equal(backend._interfaces.peddler._login_rewards, payload)
    end)

    H.test("MP1684 actual command validates every row before output and never retries logger failure", function()
        local actual = login_owner()
        local original = actual.login_cache_lines
        actual.login_cache_lines = function()
            local rows = {}
            for i = 1, 12 do rows[i] = "must_not_emit" end
            return rows, 12
        end
        local overflow = login_command(actual, {}, { native = true })
        overflow.command("1")
        H.equal(#overflow.lines, 1, "command must refuse more than eleven projected rows")
        H.truthy(overflow.lines[1]:find("status=projection_unavailable", 1, true))
        actual.login_cache_lines = function() return { "must_not_emit", string.rep("x", 701) }, 2 end
        local s = login_command(actual, login_backend(login_payload()), { native = true })
        s.command("1")
        H.equal(#s.lines, 1, "all rows must be validated before any projected output")
        H.truthy(s.lines[1]:find("reason=invalid_rows", 1, true))
        H.equal(s.lines[1]:find("must_not_emit", 1, true), nil)
        actual.login_cache_lines = function() error({}) end
        s = login_command(actual, {}, { native = true }); s.command("1")
        H.equal(#s.lines, 1); H.truthy(s.lines[1]:find("status=projection_unavailable", 1, true))
        actual.login_cache_lines = original
        local failure, prints = {}, 0
        s = login_command(actual, login_backend(login_payload()), { native = true }, function()
            prints = prints + 1; error(failure)
        end)
        local ok, err = pcall(s.command, "1")
        H.equal(ok, false); H.equal(err, failure); H.equal(prints, 1)
    end)
    -- Required portable source fixture: no external checkout or SKIP path.
    local function native_login_cache()
        local s = { queued = {}, bindings = {}, order = {} }
        local loader = assert(loadfile(repo_root .. "/qa/lua/fixtures/mp_login_cache_native_6_13.lua"))
        local env = setmetatable({ HAS_STEAM = true }, { __index = _G }); env._G = env
        env.callback = function(owner, method, external)
            local binding = { owner = owner, method = method, external = external, token = {} }
            s.bindings[#s.bindings + 1] = binding
            return binding.token -- opaque recording token, never callable/dispatched
        end
        setfenv(loader, env)
        s.native = loader()
        s.queue = { enqueue = function(queue, request, callback_token, eac)
            H.equal(queue, s.queue)
            s.queued[#s.queued + 1] = { request = request, callback_token = callback_token, eac = eac }
            s.order[#s.order + 1] = "enqueue:" .. request.FunctionName
        end }
        s.mirror = { request_queue = function(mirror)
            H.equal(mirror, s.mirror); return s.queue
        end }
        local function other_refresh(name)
            return function(owner, flag)
                H.equal(owner, s.owner)
                H.equal(flag, name == "refresh_layout_override" and true or nil)
                s.order[#s.order + 1] = name
            end
        end
        s.owner = setmetatable({
            refresh_stock = other_refresh("refresh_stock"),
            refresh_chips = other_refresh("refresh_chips"),
            refresh_layout_override = other_refresh("refresh_layout_override"),
            refresh_app_prices = other_refresh("refresh_app_prices"),
            refresh_platform_item_prices = other_refresh("refresh_platform_item_prices"),
        }, { __index = s.native.peddler })
        s.manager = { _interfaces_created = true, _interfaces = { peddler = s.owner } }
        return s
    end

    H.test("MP1684 complete native init requires cached login response before interface readiness", function()
        local s = native_login_cache()
        s.native.peddler.init(s.owner, s.mirror)
        local expected = { "refresh_stock", "refresh_chips", "refresh_layout_override",
            "refresh_app_prices", "refresh_platform_item_prices", "enqueue:getStoreRewards" }
        H.equal(#s.order, #expected)
        for i, name in ipairs(expected) do H.equal(s.order[i], name) end
        H.equal(#s.queued, 1, "actual init must reach the native login-cache request producer")
        H.equal(s.queued[1].request.FunctionName, "getStoreRewards")
        H.equal(s.queued[1].request.FunctionParameter, nil)
        H.equal(s.queued[1].eac, false, "native cached login refresh must not request an EAC challenge")
        H.equal(#s.bindings, 1); H.equal(s.bindings[1].owner, s.owner)
        H.equal(s.bindings[1].method, "_refresh_login_rewards_cb")
        H.equal(s.bindings[1].external, nil)
        H.equal(s.queued[1].callback_token, s.bindings[1].token)
        H.equal(s.owner._backend_mirror, s.mirror)
        H.equal(s.owner._is_done_claiming, true); H.equal(s.owner._stock_ready, false)
        H.equal(s.native.peddler.get_login_rewards(s.owner), nil)
        H.equal(s.native.peddler.ready(s.owner), nil)
        H.equal(s.native.interfaces_ready(s.manager), false)
        -- The other readiness fields are explicit private preconditions, not
        -- modeled refresh/service results. The REAL cache gate is still absent.
        s.owner._stock_ready, s.owner._steam_stock_ready = true, true
        s.owner._chips_ready, s.owner._app_prices_ready = true, true
        H.equal(s.native.peddler.ready(s.owner), nil)
        s.native.peddler._refresh_login_rewards_cb(s.owner, nil, { FunctionResult = {} })
        H.equal(s.native.peddler.ready(s.owner), true)
        H.equal(s.native.interfaces_ready(s.manager), true)
        -- Native truthiness readiness does NOT establish a complete payload.
        s.manager._interfaces_created = false
        H.equal(s.native.interfaces_ready(s.manager), false)
        s.manager._interfaces_created = true; s.manager._interfaces = nil
        H.equal(s.native.interfaces_ready(s.manager), false)
        H.equal(#s.queued, 1, "readiness and cache callback must not enqueue or dispatch anything")
    end)

    H.test("MP1684 native cache callback and getter feed actual cached-only command without dispatch", function()
        local actual, s = login_owner(), native_login_cache()
        s.native.peddler.init(s.owner, s.mirror)
        local payload, external_calls = login_payload(), 0
        local external = function(got)
            external_calls = external_calls + 1
            H.equal(got, payload)
            H.equal(rawget(s.owner, "_login_rewards"), payload,
                "native callback must publish exact response identity before its external callback")
        end
        -- Exercise the complete native producer only against the private
        -- recording boundary; never invoke a captured queue callback token.
        s.native.peddler.refresh_login_rewards(s.owner, external)
        H.equal(#s.queued, 2); H.equal(external_calls, 0)
        H.equal(s.bindings[2].method, "_refresh_login_rewards_cb")
        H.equal(s.bindings[2].external, external)
        H.equal(s.queued[2].eac, false)
        s.native.peddler._refresh_login_rewards_cb(s.owner, external, { FunctionResult = payload })
        H.equal(external_calls, 1)
        H.equal(s.native.peddler.get_login_rewards(s.owner), payload)
        local backend = { _interfaces = { peddler = s.owner } }
        local command = login_command(actual, backend, { native = true })
        command.command("1")
        H.equal(#command.lines, 11)
        H.truthy(command.lines[1]:find("status=observed_cache", 1, true))
        H.truthy(command.lines[3]:find("currency_code=s:SM amount=n:15", 1, true))
        H.equal(#s.queued, 2, "actual cached-only command must add no native refresh/request")
        H.equal(s.native.peddler.get_login_rewards(s.owner), payload)
        local replacement, failure = login_payload("calendar"), {}
        local ok, err = pcall(s.native.peddler._refresh_login_rewards_cb, s.owner,
            function() error(failure) end, { FunctionResult = replacement })
        H.equal(ok, false); H.equal(err, failure)
        H.equal(s.native.peddler.get_login_rewards(s.owner), replacement)
        s.native.peddler._refresh_login_rewards_cb(s.owner, nil, { FunctionResult = false })
        H.equal(s.native.peddler.get_login_rewards(s.owner), false)
        H.equal(s.native.peddler.ready(s.owner), false)
        s.native.peddler._refresh_login_rewards_cb(s.owner, nil, {})
        H.equal(s.native.peddler.get_login_rewards(s.owner), nil)
        H.equal(#s.queued, 2); H.equal(external_calls, 1)
    end)

    H.test("MP1684 actual command refuses official unknown and reader errors before raw cache reads", function()
        local payload = login_payload()
        local backend = login_backend(payload)
        local interfaces, peddler = backend._interfaces, backend._interfaces.peddler
        local watched = { [backend] = "backend", [interfaces] = "interfaces",
            [peddler] = "peddler", [payload] = "payload" }
        local reads = { backend = 0, interfaces = 0, peddler = 0, payload = 0 }
        local env = setmetatable({}, { __index = _G }); env._G = env
        env.rawget = function(t, key)
            local slot = watched[t]
            if slot then reads[slot] = reads[slot] + 1 end
            return rawget(t, key)
        end
        local loader = assert(loadfile(repo_root
            .. "/modded_progression/scripts/mods/modded_progression/_mp_diag_fresh_profile.lua"))
        setfenv(loader, env)
        local actual = loader()
        for _, spec in ipairs({
            { native = false, legacy = true }, { native = "false" }, { native = 1 },
            { legacy = false }, {}, { throws = {} },
        }) do
            local s = login_command(actual, backend, spec)
            s.command("1")
            H.equal(#s.lines, 1)
            H.truthy(s.lines[1]:find("status=realm_unavailable", 1, true))
            H.equal(reads.backend, 0, "refused realm must not read raw backend cache route")
            H.equal(reads.interfaces, 0, "refused realm must not read raw interface map")
            H.equal(reads.peddler, 0, "refused realm must not read raw peddler cache")
            H.equal(reads.payload, 0, "refused realm must not read cached payload fields")
        end
        local positive = login_command(actual, backend, { native = true })
        positive.command("1")
        H.equal(#positive.lines, 11)
        H.equal(reads.backend, 1); H.equal(reads.interfaces, 1); H.equal(reads.peddler, 1)
        H.truthy(reads.payload > 0, "positive actual cache sampling must reach the private rawget spy")
        H.equal(rawget(peddler, "_login_rewards"), payload)
    end)
end
