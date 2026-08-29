return function(H, repo_root)
    local Identity = assert(loadfile(repo_root
        .. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_custom_breed_identity.lua"))()

    local function pair(lookup, id, name)
        lookup[id], lookup[name] = name, id
    end

    local function fixture(offset)
        offset = offset or 0
        local marker_key = "_et_custom_breed_registration"
        local breeds = {
            chaos_warrior = { name = "chaos_warrior" },
            skaven_storm_vermin_champion = { name = "skaven_storm_vermin_champion" },
        }
        local network_lookup = {
            breeds = {}, damage_sources = {}, statistics_path_names = {},
        }
        pair(network_lookup.breeds, 1 + offset, "chaos_warrior")
        pair(network_lookup.breeds, 2 + offset, "skaven_storm_vermin_champion")
        local ids = {
            et_chosen_greataxe = { 11 + offset, 31 + offset, 51 + offset },
            et_skaven_warlord = { 12 + offset, 32 + offset, 52 + offset },
        }
        for _, spec in ipairs(Identity.SPECS) do
            local row = ids[spec.name]
            local marker = {
                schema = 3,
                owner = spec.owner,
                fingerprint = spec.fingerprint,
                breed_index = row[1],
                damage_source_index = row[2],
                statistics_path_index = row[3],
            }
            breeds[spec.name] = { name = spec.name, [marker_key] = marker }
            pair(network_lookup.breeds, row[1], spec.name)
            pair(network_lookup.damage_sources, row[2], spec.name)
            pair(network_lookup.statistics_path_names, row[3], spec.name)
        end
        return {
            breeds = breeds,
            network_lookup = network_lookup,
            marker_key = marker_key,
            registrar_schema = 3,
        }
    end

    local function read(relative)
        local file = assert(io.open(repo_root .. "/" .. relative, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function install_no_replay_surface(method, resolver)
        local hooks, warnings, alerts, checks = {}, {}, {}, {}
        local mod = {
            _et = {
                rt_register = function(name, fn) checks[name] = fn end,
                dbg_alert = function(format, ...)
                    alerts[#alerts + 1] = string.format(format, ...)
                end,
                spawn_dbg = function() end,
                spawn_dbg_alert = function() end,
            },
            hook = function(_, class, hook_method, callback)
                hooks[class .. "." .. hook_method] = callback
            end,
            warning = function(_, format, ...)
                warnings[#warnings + 1] = string.format(format, ...)
            end,
            get = function() return nil end,
        }
        local env = setmetatable({
            get_mod = function() return mod end,
            printf = function() end,
        }, { __index = _G })
        local chunk = assert(loadfile(repo_root
            .. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_protect.lua"))
        setfenv(chunk, env)
        chunk()
        assert(type(mod._et.hook_resolve_first_once) == "function")
        mod._et.hook_resolve_first_once("ConflictDirector", method,
            "issue451_no_replay_probe", resolver, function(first)
                local name = type(first) == "table" and rawget(first, "name")
                return name == "et_chosen_greataxe"
                    or name == "et_skaven_warlord"
            end)
        return assert(hooks["ConflictDirector." .. method]), mod,
            warnings, alerts, checks
    end

    local function install_production_spawn_runtime()
        local ctx = fixture()
        local breeds = ctx.breeds
        for _, name in ipairs({
            "chaos_fanatic",
            "skaven_rat_ogre",
            "skaven_storm_vermin",
            "skaven_storm_vermin_with_shield",
            "skaven_storm_vermin_commander",
            "skaven_storm_vermin_warlord",
        }) do
            breeds[name] = breeds[name] or { name = name }
        end

        local hooks, checks, settings, warnings, alerts = {}, {}, {}, {}, {}
        local runtime = {
            ctx = ctx,
            hooks = hooks,
            checks = checks,
            settings = settings,
            warnings = warnings,
            alerts = alerts,
            exact_safe = true,
            floor_throw = false,
            get_throw = false,
        }
        local mod = {
            _et = {
                CustomBreedIdentity = Identity,
                rt_register = function(name, fn) checks[name] = fn end,
                dbg = function() end,
                dbg_alert = function(format, ...)
                    alerts[#alerts + 1] = string.format(format, ...)
                end,
                spawn_dbg = function() end,
                spawn_dbg_alert = function() end,
            },
            _et_warlord2_breed_name = "et_skaven_warlord",
            hook = function(_, class, method, callback)
                hooks[class .. "." .. method] = callback
            end,
            hook_safe = function() end,
            get = function(_, key)
                if runtime.get_throw then error("mod-get-threw:" .. tostring(key)) end
                return settings[key]
            end,
            warning = function(_, format, ...)
                warnings[#warnings + 1] = string.format(format, ...)
            end,
            info = function() end,
            echo = function() end,
        }
        runtime.mod = mod
        mod._et.custom_breed_spawn_floor = function(requested)
            if runtime.floor_throw then error("custom-floor-threw") end
            return Identity.resolve_spawn_breed(requested,
                runtime.exact_safe, breeds, ctx.network_lookup)
        end

        local env = setmetatable({
            get_mod = function() return mod end,
            Breeds = breeds,
            NetworkLookup = ctx.network_lookup,
            Managers = { player = { is_server = true } },
            ConflictDirector = {
                spawn_queued_unit = function() end,
                spawn_unit_immediate = function() end,
            },
            printf = function() end,
        }, { __index = _G })
        env._G = env
        for _, name in ipairs({ "_et_protect.lua", "_et_champion_warlord.lua" }) do
            local chunk = assert(loadfile(repo_root
                .. "/enemy_tweaker/scripts/mods/enemy_tweaker/" .. name))
            setfenv(chunk, env)
            chunk()
        end
        runtime.queued = assert(hooks[
            "ConflictDirector.spawn_queued_unit"])
        runtime.immediate = assert(hooks[
            "ConflictDirector.spawn_unit_immediate"])
        return runtime
    end

    local function pack(...)
        return { n = select("#", ...), ... }
    end

    local function queue_args(spawn_type, optional_data)
        return pack("boxed-pos", "boxed-rot", "spawn-category",
            "spawn-animation", spawn_type or "roam", optional_data or {},
            "group-data", "unit-data")
    end

    local function immediate_args()
        return pack("spawn-pos", "spawn-rot", "spawn-category",
            "spawn-animation", "spawn-type", "optional-data", "group-data")
    end

    local function invoke_surface(callback, native, breed, args)
        return callback(native, {}, breed, unpack(args, 1, args.n))
    end

    local function install_runtime(options)
        options = options or {}
        local hooks, safe_hooks, logs, sends = {}, {}, {}, {}
        local latest, receiver = {}, nil
        local ctx = fixture()
        local supplied_live = options.live_counts or {}
        local supplied_queued = options.queued_counts or {}
        local live_counts, queued_counts = {}, {}
        for i = 1, #Identity.SPECS do
            local name = Identity.SPECS[i].name
            live_counts[name] = supplied_live[name] or 0
            queued_counts[name] = supplied_queued[name] or 0
        end
        local roster = options.roster or {}
        local registrar = {
            marker_key = ctx.marker_key,
            schema = ctx.registrar_schema,
            validate_all_registered = function() return true end,
        }
        local mod = {
            _et = {
                CustomBreedIdentity = Identity,
                CustomBreedRegistrar = registrar,
                rpc_schema = 1,
                rt_register = function() end,
            },
            dofile = function(_, path)
                H.equal(path,
                    "scripts/mods/enemy_tweaker/_lib_peer_parity")
                if options.parity_unavailable then error("parity unavailable") end
                return assert(loadfile(repo_root
                    .. "/tools/shared_lib/_lib_peer_parity.lua"))()
            end,
            hook = function(_, class, method, callback)
                hooks[class .. "." .. method] = callback
            end,
            hook_safe = function(_, class, method, callback)
                safe_hooks[class .. "." .. method] = callback
            end,
            network_register = function(_, channel, callback)
                H.equal(channel, "et_custom_breeds_exact_v1")
                receiver = callback
            end,
            network_send = function(_, channel, recipient, schema, reply,
                    identity, epoch, query, echo)
                local row = {
                    channel = channel, recipient = recipient, schema = schema,
                    reply = reply, identity = identity, epoch = epoch,
                    query = query, echo = echo,
                }
                sends[#sends + 1] = row
                latest[recipient] = row
            end,
            debug = function() end,
            echo = function() end,
            get_name = function() return "enemy_tweaker" end,
        }
        local runtime = {
            ctx = ctx,
            mod = mod,
            hooks = hooks,
            safe_hooks = safe_hooks,
            logs = logs,
            sends = sends,
            latest = latest,
            live_counts = live_counts,
            queued_counts = queued_counts,
            roster = roster,
            managers = {
                player = {
                    human_players = function() return roster end,
                },
                state = {
                    conflict = {
                        num_queued_spawn_by_breed = queued_counts,
                        count_units_by_breed = function(_, name)
                            return live_counts[name]
                        end,
                    },
                },
            },
        }
        runtime.receiver = function(...)
            H.equal(type(receiver), "function", "parity receiver not installed")
            return receiver(...)
        end
        runtime.reply_exact = function(peer_id, epoch)
            local challenge = assert(latest[peer_id],
                "directed challenge missing for " .. tostring(peer_id))
            receiver(peer_id, 1, 1,
                assert(mod._et.CustomBreedIdentitySnapshot).identity,
                epoch or ("epoch-" .. peer_id), "", challenge.query)
        end
        runtime.reply_mismatch = function(peer_id, epoch)
            local challenge = assert(latest[peer_id],
                "directed challenge missing for " .. tostring(peer_id))
            receiver(peer_id, 1, 1, "wrong-identity",
                epoch or ("epoch-" .. peer_id), "", challenge.query)
        end
        return runtime
    end

    local function with_runtime(options, callback)
        local previous = {
            get_mod = rawget(_G, "get_mod"),
            Breeds = rawget(_G, "Breeds"),
            NetworkLookup = rawget(_G, "NetworkLookup"),
            Managers = rawget(_G, "Managers"),
            Network = rawget(_G, "Network"),
            printf = rawget(_G, "printf"),
        }
        local runtime = install_runtime(options)
        local ok, err = xpcall(function()
            get_mod = function() return runtime.mod end
            Breeds = runtime.ctx.breeds
            NetworkLookup = runtime.ctx.network_lookup
            Managers = runtime.managers
            Network = { peer_id = function() return "host" end }
            printf = function(fmt, ...)
                runtime.logs[#runtime.logs + 1] = string.format(fmt, ...)
            end
            assert(loadfile(repo_root
                .. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_custom_breed_parity.lua"))()
            callback(runtime)
        end, debug.traceback)
        get_mod = previous.get_mod
        Breeds = previous.Breeds
        NetworkLookup = previous.NetworkLookup
        Managers = previous.Managers
        Network = previous.Network
        printf = previous.printf
        if not ok then error(err, 0) end
    end

    H.test("ET #451 custom breed identity is deterministic across all three symmetric axes", function()
        local a = assert(Identity.capture(fixture()))
        local b = assert(Identity.capture(fixture()))
        H.equal(a.identity, b.identity)
        H.equal(#a.rows, 2)
        H.equal(#a.axes, 3)
        H.equal(#a.identity <= 64, true)
        H.equal(a.identity:match("^[%w_.:%-]+$") ~= nil, true)

        local shifted = assert(Identity.capture(fixture(100)))
        H.equal(shifted.identity == a.identity, false,
            "numeric ids on any process are part of exact identity")
        H.equal(Identity.intact(a, fixture()), false,
            "a lookalike root must not reuse a snapshot")
        local roots = fixture()
        local rooted = assert(Identity.capture(roots))
        H.equal(Identity.intact(rooted, roots), true)
    end)

    H.test("ET #451 custom breed identity rejects registrar and per-axis mutation", function()
        local cases = {
            function(ctx)
                ctx.breeds.et_chosen_greataxe[ctx.marker_key].fingerprint = "tampered"
            end,
            function(ctx) ctx.network_lookup.breeds.et_chosen_greataxe = 99 end,
            function(ctx) ctx.network_lookup.damage_sources[31] = "tampered" end,
            function(ctx) ctx.network_lookup.statistics_path_names.et_skaven_warlord = 99 end,
            function(ctx)
                ctx.breeds.et_skaven_warlord[ctx.marker_key].statistics_path_index = 99
            end,
        }
        for i = 1, #cases do
            local ctx = fixture()
            local snapshot = assert(Identity.capture(ctx))
            cases[i](ctx)
            local intact = Identity.intact(snapshot, ctx)
            H.equal(intact, false, "mutation case " .. i .. " was accepted")
        end

        local root_ctx = fixture()
        local root_snapshot = assert(Identity.capture(root_ctx))
        H.equal(Identity.intact(root_snapshot, {
            breeds = {}, network_lookup = root_ctx.network_lookup,
        }), false, "Breeds root replacement was accepted")
        H.equal(Identity.intact(root_snapshot, {
            breeds = root_ctx.breeds, network_lookup = {},
        }), false, "NetworkLookup root replacement was accepted")

        local ctx = fixture()
        ctx.breeds.et_chosen_greataxe[ctx.marker_key].schema = 2
        local captured, reason = Identity.capture(ctx)
        H.equal(captured, nil)
        H.equal(reason:find("registrar%-fingerprint%-mismatch") ~= nil, true)
    end)

    H.test("ET #451 sender floor preserves vanilla, exact custom, and validated donors", function()
        local ctx = fixture()
        local vanilla = { name = "chaos_fanatic" }
        local out, decision = Identity.resolve_spawn_breed(
            vanilla, false, ctx.breeds, ctx.network_lookup)
        H.equal(out, vanilla)
        H.equal(decision, "vanilla")

        for _, spec in ipairs(Identity.SPECS) do
            local custom = ctx.breeds[spec.name]
            out, decision = Identity.resolve_spawn_breed(
                custom, true, ctx.breeds, ctx.network_lookup)
            H.equal(out, custom)
            H.equal(decision, "exact-custom")

            out, decision = Identity.resolve_spawn_breed(
                custom, false, ctx.breeds, ctx.network_lookup)
            H.equal(out, ctx.breeds[spec.donor])
            H.equal(decision, "vanilla-donor")

            -- A fabricated/stale table bearing the custom name models a direct
            -- General Tweaker bypass. Even with a globally safe lobby it cannot
            -- ride the custom id because it is not canonical Breeds[name].
            out, decision = Identity.resolve_spawn_breed(
                { name = spec.name }, true, ctx.breeds, ctx.network_lookup)
            H.equal(out, ctx.breeds[spec.donor])
            H.equal(decision, "vanilla-donor")
        end

        ctx.network_lookup.breeds.chaos_warrior = nil
        out, decision = Identity.resolve_spawn_breed(
            ctx.breeds.et_chosen_greataxe, false, ctx.breeds, ctx.network_lookup)
        H.equal(out, nil)
        H.equal(decision, "donor-invalid:chaos_warrior")
    end)

    H.test("ET #451 queued and immediate donor floors preserve native return tuples", function()
        local ctx = fixture()
        local function native(_, breed, tag)
            return "native:" .. tag, breed.name, false
        end
        local function invoke(surface, requested, safe, tag)
            local breed = assert(Identity.resolve_spawn_breed(
                requested, safe, ctx.breeds, ctx.network_lookup))
            return native({}, breed, tag or surface)
        end

        local q1, q2, q3 = invoke("queued",
            ctx.breeds.et_chosen_greataxe, false, "queue-id-77")
        H.equal(q1, "native:queue-id-77")
        H.equal(q2, "chaos_warrior")
        H.equal(q3, false)

        local i1, i2, i3 = invoke("immediate",
            ctx.breeds.et_skaven_warlord, false, "unit-go")
        H.equal(i1, "native:unit-go")
        H.equal(i2, "skaven_storm_vermin_champion")
        H.equal(i3, false)

        local e1, e2 = invoke("queued",
            ctx.breeds.et_skaven_warlord, true, "exact")
        H.equal(e1, "native:exact")
        H.equal(e2, "et_skaven_warlord")
    end)

    H.test("ET #451 surface guard fails custom closed without disturbing vanilla", function()
        local ctx = fixture()
        local custom = ctx.breeds.et_chosen_greataxe
        local vanilla = { name = "chaos_fanatic" }
        local calls = 0
        local out, decision = Identity.guard_spawn_surface(
            vanilla, "queued", function() calls = calls + 1; error("boom") end)
        H.equal(out, vanilla)
        H.equal(decision, "vanilla")
        H.equal(calls, 0, "ordinary breeds paid the parity-floor cost")

        out, decision = Identity.guard_spawn_surface(custom, "queued", nil)
        H.equal(out, nil)
        H.equal(decision, "floor-unavailable")
        out, decision = Identity.guard_spawn_surface(
            custom, "queued", function() error("mutate-then-throw") end)
        H.equal(out, nil)
        H.equal(decision, "floor-threw")
        out, decision = Identity.guard_spawn_surface(
            custom, "queued", function() return nil, "donor-invalid" end)
        H.equal(out, nil)
        H.equal(decision, "donor-invalid")
        out, decision = Identity.guard_spawn_surface(
            custom, "queued", function() return ctx.breeds.chaos_warrior,
                "vanilla-donor" end)
        H.equal(out, ctx.breeds.chaos_warrior)
        H.equal(decision, "vanilla-donor")
    end)

    H.test("ET #451 actual no-replay hook never re-emits an original custom breed", function()
        local ctx = fixture()
        local requested = ctx.breeds.et_chosen_greataxe
        local native_calls, seen = 0, {}
        local callback, mod, warnings, alerts = install_no_replay_surface(
            "spawn_queued_unit", function(breed)
                return Identity.guard_spawn_surface(breed, "queued",
                    function()
                        return ctx.breeds.chaos_warrior, "vanilla-donor"
                    end)
            end)
        local function native(_, breed)
            native_calls = native_calls + 1
            seen[native_calls] = breed
            error("native-mutated-then-threw")
        end
        local ok, err = pcall(callback, native, {}, requested)
        H.equal(ok, false, "native sender error was swallowed")
        H.equal(tostring(err):find("native%-mutated%-then%-threw") ~= nil, true)
        H.equal(native_calls, 1, "native sender was replayed after its error")
        H.equal(seen[1], ctx.breeds.chaos_warrior,
            "validated donor did not reach the single native attempt")
        H.equal(seen[2], nil,
            "original custom payload was replayed through vanilla fallback")
        H.equal(#warnings, 0, "native errors belong to native, not planner logging")
        H.equal(#alerts, 0)
        H.equal(mod._et.wrap_registry.once[
            "ConflictDirector.spawn_queued_unit"], true)
        H.equal(mod._et.wrap_registry.plain[
            "ConflictDirector.spawn_queued_unit"], nil)
    end)

    H.test("ET #451 no-replay hook preserves success tuples and fails pre-native closed", function()
        local calls = 0
        local callback = install_no_replay_surface(
            "spawn_unit_immediate", function(breed)
                if breed.fail then error("floor-threw") end
                return breed
            end)
        local function native(_, breed)
            calls = calls + 1
            return breed.name, false, "go-id", 0
        end
        local a, b, c, d = callback(native, {}, { name = "chaos_warrior" })
        H.equal(a, "chaos_warrior")
        H.equal(b, false)
        H.equal(c, "go-id")
        H.equal(d, 0)
        H.equal(calls, 1)
        local rejected = callback(native, {}, { name = "et_chosen_greataxe", fail = true })
        H.equal(rejected, nil)
        H.equal(calls, 1, "pre-native failure reached or replayed native")
        local va, vb = callback(native, {}, { name = "chaos_fanatic", fail = true })
        H.equal(va, "chaos_fanatic")
        H.equal(vb, false)
        H.equal(calls, 2,
            "ordinary vanilla planner failure must invoke native once unchanged")
    end)

    H.test("ET #451 production queued hook preserves vanilla and plans both pool swaps", function()
        local runtime = install_production_spawn_runtime()
        local seen = {}
        local function native(_, breed, ...)
            seen[#seen + 1] = { breed = breed, args = pack(...) }
            return "queue-id", false, "third", 0, "fifth"
        end

        local args = queue_args("roam", {})
        local a, b, c, d, e = invoke_surface(runtime.queued, native,
            runtime.ctx.breeds.chaos_fanatic, args)
        H.equal(a, "queue-id")
        H.equal(b, false)
        H.equal(c, "third")
        H.equal(d, 0)
        H.equal(e, "fifth")
        H.equal(#seen, 1)
        H.equal(seen[1].breed, runtime.ctx.breeds.chaos_fanatic)
        H.equal(seen[1].args.n, args.n)
        for i = 1, args.n do H.equal(seen[1].args[i], args[i]) end

        runtime.settings.warlord_in_monster_pool = true
        runtime.settings.warlord_monster_chance = 100
        runtime.exact_safe = true
        invoke_surface(runtime.queued, native,
            runtime.ctx.breeds.skaven_rat_ogre, queue_args("boss", {}))
        H.equal(seen[2].breed, runtime.ctx.breeds.et_skaven_warlord)

        runtime.exact_safe = false
        invoke_surface(runtime.queued, native,
            runtime.ctx.breeds.skaven_rat_ogre, queue_args("boss", {}))
        H.equal(seen[3].breed,
            runtime.ctx.breeds.skaven_storm_vermin_champion,
            "unsafe Warlord pool swap did not use its validated donor")

        invoke_surface(runtime.queued, native,
            runtime.ctx.breeds.skaven_rat_ogre,
            queue_args("boss", { et_boss_balance_no_pool_swap = true }))
        H.equal(seen[4].breed, runtime.ctx.breeds.skaven_rat_ogre,
            "explicit no-pool marker was ignored")

        runtime.settings.warlord_in_monster_pool = false
        runtime.settings.champion_in_elite_pool = true
        runtime.settings.champion_elite_chance = 100
        invoke_surface(runtime.queued, native,
            runtime.ctx.breeds.skaven_storm_vermin, queue_args("roam", {}))
        H.equal(seen[5].breed,
            runtime.ctx.breeds.skaven_storm_vermin_champion)
    end)

    H.test("ET #451 production hooks floor direct custom intent on both surfaces", function()
        local runtime = install_production_spawn_runtime()
        local seen = {}
        local function native(_, breed)
            seen[#seen + 1] = breed
            return breed.name
        end
        local surfaces = {
            { runtime.queued, queue_args("roam", {}) },
            { runtime.immediate, immediate_args() },
        }
        for i = 1, #surfaces do
            runtime.exact_safe = false
            local before = #seen
            local chosen_name = invoke_surface(surfaces[i][1], native,
                runtime.ctx.breeds.et_chosen_greataxe, surfaces[i][2])
            H.equal(chosen_name, "chaos_warrior")
            H.equal(seen[before + 1], runtime.ctx.breeds.chaos_warrior)

            local warlord_name = invoke_surface(surfaces[i][1], native,
                runtime.ctx.breeds.et_skaven_warlord, surfaces[i][2])
            H.equal(warlord_name, "skaven_storm_vermin_champion")
            H.equal(seen[before + 2],
                runtime.ctx.breeds.skaven_storm_vermin_champion)

            runtime.exact_safe = true
            local exact_name = invoke_surface(surfaces[i][1], native,
                runtime.ctx.breeds.et_chosen_greataxe, surfaces[i][2])
            H.equal(exact_name, "et_chosen_greataxe")
            H.equal(seen[before + 3], runtime.ctx.breeds.et_chosen_greataxe)

            local fabricated_name = invoke_surface(surfaces[i][1], native,
                { name = "et_chosen_greataxe" }, surfaces[i][2])
            H.equal(fabricated_name, "chaos_warrior")
            H.equal(seen[before + 4], runtime.ctx.breeds.chaos_warrior)
        end
    end)

    H.test("ET #451 production hooks hold invalid custom plans and fail vanilla open once", function()
        local runtime = install_production_spawn_runtime()
        runtime.exact_safe = false
        local native_calls, seen = 0, {}
        local function native(_, breed)
            native_calls = native_calls + 1
            seen[native_calls] = breed
            return "native"
        end

        local donor_id = runtime.ctx.network_lookup.breeds.chaos_warrior
        runtime.ctx.network_lookup.breeds.chaos_warrior = nil
        local held = invoke_surface(runtime.queued, native,
            runtime.ctx.breeds.et_chosen_greataxe, queue_args("roam", {}))
        H.equal(held, nil)
        H.equal(native_calls, 0)
        runtime.ctx.network_lookup.breeds.chaos_warrior = donor_id

        runtime.floor_throw = true
        held = invoke_surface(runtime.immediate, native,
            runtime.ctx.breeds.et_chosen_greataxe, immediate_args())
        H.equal(held, nil)
        H.equal(native_calls, 0)
        runtime.floor_throw = false

        runtime.get_throw = true
        held = invoke_surface(runtime.queued, native,
            runtime.ctx.breeds.et_chosen_greataxe, queue_args("roam", {}))
        H.equal(held, nil)
        H.equal(native_calls, 0,
            "custom original survived a throwing queued planner")
        local result = invoke_surface(runtime.queued, native,
            runtime.ctx.breeds.chaos_fanatic, queue_args("roam", {}))
        H.equal(result, "native")
        H.equal(native_calls, 1)
        H.equal(seen[1], runtime.ctx.breeds.chaos_fanatic,
            "ordinary vanilla planner failure did not preserve its original breed")
    end)

    H.test("ET #451 production native failures propagate after one resolved attempt", function()
        local runtime = install_production_spawn_runtime()
        runtime.exact_safe = false
        local surfaces = {
            { runtime.queued, queue_args("roam", {}) },
            { runtime.immediate, immediate_args() },
        }
        for i = 1, #surfaces do
            local calls, observed = 0, nil
            local function native(_, breed)
                calls = calls + 1
                observed = breed
                error("native-mutated-then-threw:" .. i)
            end
            local ok, err = pcall(invoke_surface, surfaces[i][1], native,
                runtime.ctx.breeds.et_chosen_greataxe, surfaces[i][2])
            H.equal(ok, false, "native error was swallowed on surface " .. i)
            H.equal(tostring(err):find(
                "native%-mutated%-then%-threw:" .. i) ~= nil, true)
            H.equal(calls, 1, "native was retried on surface " .. i)
            H.equal(observed, runtime.ctx.breeds.chaos_warrior,
                "surface " .. i .. " observed original unsafe custom identity")
        end
    end)

    H.test("ET #451 exact parity covers solo exact mismatch replay hotjoin and disconnect", function()
        local previous_managers, previous_network = Managers, Network
        local roster = {}
        Managers = { player = { human_players = function() return roster end } }
        Network = { peer_id = function() return "host" end }
        local ok, err = xpcall(function()
            local factory = assert(loadfile(repo_root
                .. "/tools/shared_lib/_lib_peer_parity.lua"))()
            local ctx = fixture()
            local identity = assert(Identity.capture(ctx)).identity
            local receiver, latest = nil, {}
            local mod = {
                network_register = function(_, channel, callback)
                    H.equal(channel, "et_custom_breeds_exact_v1")
                    receiver = callback
                end,
                network_send = function(_, channel, recipient, schema, reply,
                        sent_identity, epoch, query, echo)
                    latest[recipient] = {
                        channel = channel, schema = schema, reply = reply,
                        identity = sent_identity, epoch = epoch,
                        query = query, echo = echo,
                    }
                end,
                debug = function() end,
                echo = function() end,
                get_name = function() return "enemy_tweaker" end,
            }
            local parity = assert(factory(mod, {
                channel = "et_custom_breeds_exact_v1",
                schema = 1,
                wire_identity = identity,
                session_epoch = "host-e1",
                poll_interval = 0,
                settle_enable = 0,
            }))
            H.equal(parity:install(), true)
            parity:tick(0)
            H.equal(parity:applied_state(), "enabled", "solo must be usable")

            H.equal(parity:require_peer("joiner"), false,
                "unacknowledged hotjoin must close synchronously")
            H.equal(parity:applied_state(), "disabled")
            local first_query = latest.joiner.query
            receiver("joiner", 1, 1, "wrong-identity", "joiner-e1", "", first_query)
            H.equal(parity:peer_has("joiner"), false)

            parity:require_peer("joiner")
            local exact_query = latest.joiner.query
            receiver("joiner", 1, 1, identity, "joiner-e1", "", exact_query)
            H.equal(parity:peer_has("joiner"), true)
            H.equal(parity:require_peer("joiner"), true,
                "exact pre-ack must pass the hotjoin fence")

            parity:forget_peer("joiner")
            H.equal(parity:peer_has("joiner"), false)
            H.equal(parity:require_peer("joiner"), false)
            local rejoin_query = latest.joiner.query
            receiver("joiner", 1, 1, identity, "joiner-e1", "", exact_query)
            H.equal(parity:peer_has("joiner"), false,
                "disconnect plus replayed challenge must not authorize rejoin")
            receiver("joiner", 1, 1, identity, "joiner-e2", "", rejoin_query)
            H.equal(parity:peer_has("joiner"), true)
        end, debug.traceback)
        Managers, Network = previous_managers, previous_network
        if not ok then error(err, 0) end
    end)

    H.test("ET #451 no-live absent mismatch unavailable peers sync donor-safe", function()
        local cases = {
            { name = "absent" },
            { name = "mismatch", mismatch = true },
            { name = "unavailable", parity_unavailable = true },
        }
        for i = 1, #cases do
            local case = cases[i]
            with_runtime({ parity_unavailable = case.parity_unavailable },
                function(runtime)
                    local sync = assert(runtime.hooks[
                        "GameNetworkManager.set_peer_synchronizing"])
                    local synced = assert(runtime.hooks[
                        "NetworkServer.is_network_state_fully_synced_for_peer"])
                    local native_calls, kicks = 0, 0
                    local manager = { network_server = {
                        kick_peer = function() kicks = kicks + 1 end,
                    } }
                    local function native(_, peer_id)
                        native_calls = native_calls + 1
                        return "native:" .. peer_id
                    end

                    local occupied, occupied_reason =
                        runtime.mod._et.custom_breed_state_live()
                    H.equal(occupied, false, occupied_reason)
                    local result = sync(native, manager, case.name)
                    H.equal(result, "native:" .. case.name)
                    H.equal(native_calls, 1)
                    H.equal(kicks, 0,
                        "first canonical false initiated a kick for " .. case.name)
                    H.equal(runtime.mod._et.custom_breed_hot_join_phase(case.name),
                        "admitted")

                    if case.mismatch then
                        runtime.reply_mismatch(case.name)
                    end
                    H.equal(synced(function() return true end, {}, case.name), true)
                    H.equal(kicks, 0, "no-live mismatch initiated a kick")

                    local donor, decision = runtime.mod._et.custom_breed_spawn_floor(
                        runtime.ctx.breeds.et_chosen_greataxe, "no-live-test")
                    H.equal(donor, runtime.ctx.breeds.chaos_warrior)
                    H.equal(decision, "vanilla-donor")
                end)
        end
    end)

    H.test("ET #451 live delayed exact ack holds then admits without kick", function()
        with_runtime({ live_counts = { et_chosen_greataxe = 1 } },
            function(runtime)
                local sync = assert(runtime.hooks[
                    "GameNetworkManager.set_peer_synchronizing"])
                local synced = assert(runtime.hooks[
                    "NetworkServer.is_network_state_fully_synced_for_peer"])
                local native_calls, kicks = 0, 0
                local manager = { network_server = {
                    kick_peer = function() kicks = kicks + 1 end,
                } }
                local function native()
                    native_calls = native_calls + 1
                    return "native"
                end

                H.equal(sync(native, manager, "delayed"), nil)
                H.equal(native_calls, 0)
                H.equal(kicks, 0,
                    "first require_peer(false) must hold without kicking")
                H.equal(runtime.mod._et.custom_breed_hot_join_phase("delayed"),
                    "pending")
                local live, live_reason = runtime.mod._et.custom_breed_state_live()
                H.equal(live, true, live_reason)
                H.equal(runtime.mod._et.CustomBreedParity:peer_has("delayed"),
                    false)
                H.equal(synced(function() return true end, {}, "delayed"), false)
                H.equal(kicks, 0)

                runtime.reply_exact("delayed")
                H.equal(synced(function() return true end, {}, "delayed"), true)
                H.equal(native_calls, 1)
                H.equal(kicks, 0)
                H.equal(runtime.mod._et.custom_breed_hot_join_phase("delayed"),
                    "admitted")
                sync(native, manager, "delayed")
                H.equal(native_calls, 1, "delayed ACK ran native sync twice")
            end)
    end)

    H.test("ET #451 queued custom state holds then delayed exact ack admits", function()
        with_runtime({ queued_counts = { et_skaven_warlord = 1 } },
            function(runtime)
                local occupied, reason = runtime.mod._et.custom_breed_state_live()
                H.equal(occupied, true)
                H.equal(reason, "queued:et_skaven_warlord")
                H.equal(runtime.live_counts.et_chosen_greataxe, 0)
                H.equal(runtime.live_counts.et_skaven_warlord, 0)

                local sync = assert(runtime.hooks[
                    "GameNetworkManager.set_peer_synchronizing"])
                local synced = assert(runtime.hooks[
                    "NetworkServer.is_network_state_fully_synced_for_peer"])
                local native_calls, kicks = 0, 0
                local manager = { network_server = {
                    kick_peer = function() kicks = kicks + 1 end,
                } }
                local function native()
                    native_calls = native_calls + 1
                    return "native"
                end

                H.equal(sync(native, manager, "queued-delayed"), nil)
                H.equal(native_calls, 0)
                H.equal(kicks, 0,
                    "queued first challenge started an irreversible kick")
                H.equal(synced(function() return true end, {},
                    "queued-delayed"), false)
                H.equal(kicks, 0)

                runtime.reply_exact("queued-delayed")
                H.equal(synced(function() return true end, {},
                    "queued-delayed"), true)
                H.equal(native_calls, 1)
                H.equal(kicks, 0)
            end)
    end)

    H.test("ET #451 queued custom state timeout kicks exactly once", function()
        with_runtime({ queued_counts = { et_chosen_greataxe = 1 } },
            function(runtime)
                local sync = assert(runtime.hooks[
                    "GameNetworkManager.set_peer_synchronizing"])
                local synced = assert(runtime.hooks[
                    "NetworkServer.is_network_state_fully_synced_for_peer"])
                local native_calls, kicks = 0, 0
                local manager = { network_server = {
                    kick_peer = function() kicks = kicks + 1 end,
                } }
                local function native() native_calls = native_calls + 1 end

                sync(native, manager, "queued-timeout")
                H.equal(kicks, 0,
                    "queued first challenge started an irreversible kick")
                H.equal(synced(function() return true end, {},
                    "queued-timeout"), false)
                runtime.mod.update(
                    runtime.mod._et.CUSTOM_BREED_HOT_JOIN_TIMEOUT + 0.01)
                H.equal(synced(function() return true end, {},
                    "queued-timeout"), false)
                H.equal(kicks, 1)
                H.equal(native_calls, 0)
                sync(native, manager, "queued-timeout")
                H.equal(synced(function() return true end, {},
                    "queued-timeout"), false)
                H.equal(kicks, 1)
                H.equal(native_calls, 0)
            end)
    end)

    H.test("ET #451 unreadable custom census holds without first-call kick", function()
        local cases = {
            function(runtime)
                runtime.managers.state.conflict.num_queued_spawn_by_breed = nil
            end,
            function(runtime)
                runtime.live_counts.et_chosen_greataxe = "invalid"
            end,
            function(runtime)
                runtime.queued_counts.et_chosen_greataxe = nil
            end,
        }
        for i = 1, #cases do
            with_runtime({}, function(runtime)
                cases[i](runtime)
                local occupied = runtime.mod._et.custom_breed_state_live()
                H.equal(occupied, true, "invalid census case was guessed empty")
                local sync = assert(runtime.hooks[
                    "GameNetworkManager.set_peer_synchronizing"])
                local synced = assert(runtime.hooks[
                    "NetworkServer.is_network_state_fully_synced_for_peer"])
                local native_calls, kicks = 0, 0
                local manager = { network_server = {
                    kick_peer = function() kicks = kicks + 1 end,
                } }
                sync(function() native_calls = native_calls + 1 end,
                    manager, "invalid-" .. i)
                H.equal(native_calls, 0)
                H.equal(kicks, 0)
                H.equal(synced(function() return true end, {},
                    "invalid-" .. i), false)
            end)
        end
    end)

    H.test("ET #451 live timeout kicks once holds and bounds logs", function()
        with_runtime({ live_counts = { et_skaven_warlord = 1 } },
            function(runtime)
                local sync = assert(runtime.hooks[
                    "GameNetworkManager.set_peer_synchronizing"])
                local synced = assert(runtime.hooks[
                    "NetworkServer.is_network_state_fully_synced_for_peer"])
                local native_calls, kicks = 0, 0
                local manager = { network_server = {
                    kick_peer = function() kicks = kicks + 1 end,
                } }
                local function native() native_calls = native_calls + 1 end

                sync(native, manager, "timeout")
                H.equal(kicks, 0, "first false initiated irreversible kick timer")
                runtime.mod.update(
                    runtime.mod._et.CUSTOM_BREED_HOT_JOIN_TIMEOUT + 0.01)
                H.equal(synced(function() return true end, {}, "timeout"), false)
                H.equal(kicks, 1)
                H.equal(native_calls, 0)
                H.equal(runtime.mod._et.custom_breed_hot_join_phase("timeout"),
                    "kicked")

                runtime.reply_exact("timeout", "late-epoch")
                sync(native, manager, "timeout")
                H.equal(synced(function() return true end, {}, "timeout"), false)
                H.equal(kicks, 1, "kicked peer was kicked twice")
                H.equal(native_calls, 0, "late ACK revived a kicked peer")

                for i = 1, 20 do
                    sync(native, manager, "hostile-" .. i)
                end
                local rows = 0
                for i = 1, #runtime.logs do
                    if runtime.logs[i]:find("hot-join sync ", 1, true) then
                        rows = rows + 1
                    end
                end
                H.equal(rows, runtime.mod._et.CUSTOM_BREED_HOT_JOIN_LOG_CAP,
                    "hot-join diagnostics were not bounded")
                H.equal(kicks, 1,
                    "a first pending false kicked one of the hostile fixtures")
            end)
    end)

    H.test("ET #451 definitive live mismatch kicks exactly once", function()
        with_runtime({ live_counts = { et_chosen_greataxe = 1 } },
            function(runtime)
                local parity = assert(runtime.mod._et.CustomBreedParity)
                H.equal(parity:require_peer("mismatch"), false)
                runtime.reply_exact("mismatch", "mismatch-e1")
                H.equal(parity:peer_has("mismatch"), true)

                local sync = assert(runtime.hooks[
                    "GameNetworkManager.set_peer_synchronizing"])
                local synced = assert(runtime.hooks[
                    "NetworkServer.is_network_state_fully_synced_for_peer"])
                local native_calls, kicks = 0, 0
                local manager = { network_server = {
                    kick_peer = function() kicks = kicks + 1 end,
                } }
                local function native()
                    native_calls = native_calls + 1
                    return "native"
                end
                H.equal(sync(native, manager, "mismatch"), "native")
                H.equal(native_calls, 1)
                H.equal(kicks, 0)

                runtime.receiver("mismatch", 1, 0, "wrong-identity",
                    "mismatch-e1", "bad-query", "")
                H.equal(parity:peer_has("mismatch"), false)
                H.equal(synced(function() return true end, {}, "mismatch"), false)
                H.equal(kicks, 1)
                H.equal(synced(function() return true end, {}, "mismatch"), false)
                H.equal(kicks, 1, "definitive mismatch kicked twice")
            end)
    end)

    H.test("ET #451 exact preack runs one native sync", function()
        with_runtime({ live_counts = { et_skaven_warlord = 1 } },
            function(runtime)
                local parity = assert(runtime.mod._et.CustomBreedParity)
                H.equal(parity:require_peer("preack"), false)
                runtime.reply_exact("preack", "preack-e1")

                local sync = assert(runtime.hooks[
                    "GameNetworkManager.set_peer_synchronizing"])
                local synced = assert(runtime.hooks[
                    "NetworkServer.is_network_state_fully_synced_for_peer"])
                local native_calls, kicks = 0, 0
                local manager = { network_server = {
                    kick_peer = function() kicks = kicks + 1 end,
                } }
                local function native()
                    native_calls = native_calls + 1
                    return "native"
                end
                H.equal(sync(native, manager, "preack"), "native")
                sync(native, manager, "preack")
                H.equal(native_calls, 1)
                H.equal(kicks, 0)
                H.equal(synced(function() return true end, {}, "preack"), true)
            end)
    end)

    H.test("ET #451 disconnect clears pending hold and retires epoch", function()
        with_runtime({ live_counts = { et_chosen_greataxe = 1 } },
            function(runtime)
                local parity = assert(runtime.mod._et.CustomBreedParity)
                local sync = assert(runtime.hooks[
                    "GameNetworkManager.set_peer_synchronizing"])
                local synced = assert(runtime.hooks[
                    "NetworkServer.is_network_state_fully_synced_for_peer"])
                local remove = assert(runtime.safe_hooks[
                    "GameNetworkManager.remove_peer"])
                local native_calls, kicks = 0, 0
                local manager = { network_server = {
                    kick_peer = function() kicks = kicks + 1 end,
                } }
                local function native() native_calls = native_calls + 1 end

                sync(native, manager, "disconnect")
                local old_query = assert(runtime.latest.disconnect).query
                local identity = assert(runtime.mod._et.CustomBreedIdentitySnapshot).identity
                runtime.receiver("disconnect", 1, 0, identity,
                    "disconnect-e1", "remote-query", "")
                H.equal(parity:peer_has("disconnect"), true)
                H.equal(runtime.mod._et.custom_breed_hot_join_phase("disconnect"),
                    "pending")

                remove({}, "disconnect")
                H.equal(runtime.mod._et.custom_breed_hot_join_phase("disconnect"), nil)
                H.equal(parity:peer_has("disconnect"), false)
                H.equal(parity:is_epoch_retired("disconnect", "disconnect-e1"), true)
                H.equal(synced(function() return true end, {}, "disconnect"), true)
                H.equal(native_calls, 0)
                H.equal(kicks, 0)

                runtime.receiver("disconnect", 1, 1, identity,
                    "disconnect-e1", "", old_query)
                H.equal(parity:peer_has("disconnect"), false,
                    "replayed pre-disconnect proof authorized the peer")
            end)
    end)

    H.test("ET #451 runtime wiring installs parity before hotjoin and keeps one queued hook", function()
        local entry = read("enemy_tweaker/scripts/mods/enemy_tweaker/enemy_tweaker.lua")
        local register_warlord = assert(entry:find("_et_skaven_warlord_breed", 1, true))
        local register_chosen = assert(entry:find("_et_boss_ideas", register_warlord, true))
        local install_parity = assert(entry:find("_et_custom_breed_parity", register_chosen, true))
        local spawn_hooks = assert(entry:find("_et_champion_warlord", install_parity, true))
        H.equal(register_warlord < register_chosen and register_chosen < install_parity
            and install_parity < spawn_hooks, true)

        local parity = read("enemy_tweaker/scripts/mods/enemy_tweaker/_et_custom_breed_parity.lua")
        local install_at = assert(parity:find("pcall(instance.install, instance)", 1, true))
        local hotjoin_at = assert(parity:find(
            'mod:hook("GameNetworkManager", "set_peer_synchronizing"', install_at, true))
        local require_at = assert(parity:find("pcall(instance.require_peer", hotjoin_at, true))
        local native_at = assert(parity:find(
            '_call_native_once(record, "exact")', require_at, true))
        local pending_at = assert(parity:find(
            "First false is pending. Hold only; never kick here.", native_at, true))
        local held_at = assert(parity:find(
            'mod:hook("NetworkServer", "is_network_state_fully_synced_for_peer"',
            pending_at, true))
        local forget_at = assert(parity:find(
            'mod:hook_safe("GameNetworkManager", "remove_peer"', held_at, true))
        H.equal(install_at < hotjoin_at and hotjoin_at < require_at
            and require_at < native_at and native_at < pending_at
            and pending_at < held_at
            and held_at < forget_at, true)
        H.equal(parity:find("local FALLBACK_LOG_CAP = 8", 1, true) ~= nil, true)
        H.equal(parity:find("local HOT_JOIN_LOG_CAP = 8", 1, true) ~= nil, true)
        H.equal(parity:find("local HOT_JOIN_TIMEOUT = 10", 1, true) ~= nil, true)

        local spawns = read("enemy_tweaker/scripts/mods/enemy_tweaker/_et_champion_warlord.lua")
        local _, queued_hooks = spawns:gsub(
            '_hook_resolve_first_once%("ConflictDirector", "spawn_queued_unit"', "")
        local _, immediate_hooks = spawns:gsub(
            '_hook_resolve_first_once%("ConflictDirector", "spawn_unit_immediate"', "")
        H.equal(queued_hooks, 1, "#451B must extend the consolidated queued hook")
        H.equal(immediate_hooks, 1, "immediate path must have one floor")
        H.equal(spawns:find(
            '_hook_wrap%("ConflictDirector", "spawn_queued_unit"') == nil,
            true, "queued custom sender must not use replaying hook_wrap")
        H.equal(spawns:find(
            '_hook_wrap%("ConflictDirector", "spawn_unit_immediate"') == nil,
            true, "immediate custom sender must not use replaying hook_wrap")
        local final_floor = assert(spawns:find(
            '_custom_breed_floor(breed, "spawn_queued_unit")', 1, true))
        local planned_return = assert(spawns:find("return breed", final_floor, true))
        local install_queue = assert(spawns:find(
            '_hook_resolve_first_once("ConflictDirector", "spawn_queued_unit"',
            planned_return, true))
        H.equal(final_floor < planned_return and planned_return < install_queue, true)

        local protect = read(
            "enemy_tweaker/scripts/mods/enemy_tweaker/_et_protect.lua")
        local plan_at = assert(protect:find(
            "local ok, resolved = pcall(resolver, first, ...)", 1, true))
        local native_once = assert(protect:find(
            "return func(self, resolved, ...)", plan_at, true))
        H.equal(plan_at < native_once, true,
            "native must be outside the protected planning call")

        local chosen = read("enemy_tweaker/scripts/mods/enemy_tweaker/_et_boss_ideas.lua")
        local gate_at = assert(chosen:find("ET.custom_breeds_exact_safe", 1, true))
        local command_spawn = assert(chosen:find(
            "conflict:spawn_queued_unit", gate_at, true))
        H.equal(gate_at < command_spawn, true,
            "/et_spawn_chosen must gate before emitting its custom breed")
    end)
end
