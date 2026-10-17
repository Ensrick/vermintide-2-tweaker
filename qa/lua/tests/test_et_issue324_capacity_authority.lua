-- #324: the #1413 registrar refuses et_skaven_warlord at mod load with
-- damage_source_cap_unavailable (12 of 12 tester logs on 0.7.64-dev). This
-- suite pins the bounded diagnostic that records what the capacity readers
-- see: the registrar's read-only verdict seam, the probe's load and one-shot
-- network samples, its per-phase and row bounds, its metatable-aware reader
-- report, its literal printf route, its in-game check, and its single load
-- owner. No global is written: the probe reads an injected globals table and
-- emits through a test-local seam (the route case runs the chunk in a
-- test-local environment).
--
-- CHARACTERIZATION, not fix proof: the first case ("boot-shaped runtime
-- reproduces ...") describes the UNCHANGED registrar and passes on the base
-- commit too. It pins the live refusal so a later fix flips it on purpose.
return function(H, repo_root)
    local base = repo_root .. "/enemy_tweaker/scripts/mods/enemy_tweaker/"
    local registrar_path = base .. "_et_custom_breed_registrar.lua"
    local diag_path = base .. "_et_diag_capacity_authority.lua"
    local Lookup = assert(loadfile(base .. "_lib_network_lookup.lua"))()

    local function read(path)
        local handle = assert(io.open(path, "rb"))
        local text = handle:read("*a")
        handle:close()
        return text
    end

    local function count_plain(text, needle)
        local count, at = 0, 1
        while true do
            local found = text:find(needle, at, true)
            if not found then return count end
            count, at = count + 1, found + #needle
        end
    end

    local function fresh_registrar()
        local registrar = assert(loadfile(registrar_path))()
        registrar.lookup_lib = Lookup
        return registrar
    end

    local function fresh_diag()
        return assert(loadfile(diag_path))()
    end

    local STAT_NAMES = {
        "kills_per_breed", "kills_per_breed_persistent",
        "kill_assists_per_breed", "damage_dealt_per_breed",
        "kills_per_breed_difficulty", "kill_assists_per_breed_difficulty",
    }
    local SOURCE = "skaven_storm_vermin_champion"
    local NAME = "et_skaven_warlord"

    local function pair(first)
        return { [1] = first, [first] = 1 }
    end

    -- Everything the planner validates before its first capacity read, with
    -- the two capacity authorities supplied by the caller.
    local function runtime_with(network_constants, network)
        local player = {}
        for i = 1, #STAT_NAMES do player[STAT_NAMES[i]] = {} end
        player.weapon_kills_per_breed = {}
        local writes = {}
        local runtime = {
            breeds = { [SOURCE] = { name = SOURCE, race = "skaven", boss = true,
                threat_value = 32, max_health = { 300, 800 } } },
            actions = { [SOURCE] = { attack = { damage = 1 } } },
            network_lookup = {
                breeds = pair(SOURCE), damage_sources = pair(SOURCE),
                statistics_path_names = pair("kills_per_breed"),
            },
            network_constants = network_constants,
            network = network,
            clone = function(value) return value end,
            conflict_director = { set_threat_value = function()
                writes[#writes + 1] = "threat"
            end },
            statistics = { player = player },
            difficulties = { normal = true },
            package_settings = { alias_to_breed = {}, breed_to_aliases = {} },
            dismemberments = { [SOURCE] = { head = { "head" } } },
            race_sets = { beastmen = {}, chaos = {}, critter = {}, skaven = {}, undead = {} },
            elites = {},
            hit_zones = {},
            raw_set = function(target, key, value)
                writes[#writes + 1] = key
                rawset(target, key, value)
            end,
            lookup_lib = Lookup,
        }
        return runtime, writes
    end

    local function spec()
        return {
            owner = "enemy_tweaker.skaven_warlord", name = NAME,
            source_breed = SOURCE, race = "skaven",
            fingerprint = "et-custom-breed:test:issue324",
        }
    end

    local function network_returning(by_kind)
        return { type_info = function(kind) return by_kind[kind] end }
    end

    local NETWORK_ROWS = {
        damage_source_id = { bits = 12, max = 4095, min = 0 },
        statistics_path_lookup = { bits = 11, max = 2047, min = 0 },
        damage_hotjoin_sync = { max = 8191.75, tolerance = 0.25 },
    }

    -- Characterization of the unchanged registrar (passes on the base too).
    H.test("ET #324 boot-shaped runtime reproduces damage_source_cap_unavailable", function()
        local boot_shapes = {
            { label = "type_info returns nil", network = network_returning({}) },
            { label = "type_info throws", network = { type_info = function()
                error("network config not loaded")
            end } },
            { label = "Network absent", network = nil },
        }
        for i = 1, #boot_shapes do
            local shape = boot_shapes[i]
            local registrar = fresh_registrar()
            local runtime, writes = runtime_with(nil, shape.network)
            local ok, reason = registrar.register(spec(), runtime)
            H.equal(ok, nil, shape.label)
            H.equal(reason, "damage_source_cap_unavailable", shape.label)
            H.equal(#writes, 0, shape.label .. ": the refusal wrote state")
            H.equal(rawget(runtime.breeds, NAME), nil, shape.label)
            H.equal(rawget(runtime.network_lookup.damage_sources, NAME), nil, shape.label)
        end

        -- A NetworkConstants-only damage authority moves the refusal to the
        -- statistics reader, which never consults NetworkConstants.
        local registrar = fresh_registrar()
        local runtime = runtime_with(
            { damage_source_id = NETWORK_ROWS.damage_source_id }, network_returning({}))
        local ok, reason = registrar.register(spec(), runtime)
        H.equal(ok, nil)
        H.equal(reason, "statistics_path_cap_unavailable")
    end)

    H.test("ET #324 registrar capacity_verdicts reports every reader read-only", function()
        local registrar = fresh_registrar()
        H.equal(type(registrar.capacity_verdicts), "function",
            "registrar exposes no read-only capacity verdict seam")
        local boot = registrar.capacity_verdicts({
            network_constants = nil, network = network_returning({}),
        })
        H.deep_equal(boot, {
            damage_source_id = "damage_source_cap_unavailable",
            statistics_path_lookup = "statistics_path_cap_unavailable",
            damage_hotjoin_sync = "health_sync_cap_unavailable",
        })
        local live = registrar.capacity_verdicts({
            network_constants = {
                damage_source_id = NETWORK_ROWS.damage_source_id,
                damage_hotjoin_sync = NETWORK_ROWS.damage_hotjoin_sync,
            },
            network = network_returning(NETWORK_ROWS),
        })
        H.deep_equal(live, {
            damage_source_id = "cap:4095",
            statistics_path_lookup = "cap:2047",
            damage_hotjoin_sync = "cap:8191.75",
        })
        -- Reading verdicts is not registration: nothing is declared.
        H.equal(#registrar.declared_specs(), 0)
    end)

    local function probe_fixture(globals)
        local Diag = fresh_diag()
        local registrar = fresh_registrar()
        local emitted = {}
        local probe = Diag.new({
            globals = globals,
            emit = function(row) emitted[#emitted + 1] = row end,
            verdicts = function()
                return registrar.capacity_verdicts({
                    network_constants = rawget(globals, "NetworkConstants"),
                    network = rawget(globals, "Network"),
                })
            end,
        })
        return Diag, probe, emitted
    end

    local function has(row, needle, message)
        H.truthy(type(row) == "string" and row:find(needle, 1, true) ~= nil,
            (message or "row") .. " lacks '" .. needle .. "': " .. tostring(row))
    end

    H.test("ET #324 probe records the boot sample and exactly one network sample", function()
        local globals = {
            Network = network_returning({}),
            NetworkLookup = { damage_sources = { "a", "b" },
                statistics_path_names = { "kills_per_breed" } },
        }
        local Diag, probe, emitted = probe_fixture(globals)
        H.equal(Diag.MAX_ROWS, 8)
        H.equal(probe.sample("load", "rejected:damage_source_cap_unavailable"), 4)
        local rows = probe.rows()
        H.deep_equal(emitted, rows, "every ledger row is emitted once")
        for i = 1, #rows do has(rows[i], "[et:324] cap-probe phase=load ") end
        has(rows[1], "note=rejected:damage_source_cap_unavailable")
        has(rows[1], "NetworkConstants=nil Network=table type_info=function indexed=function meta=false via=raw")
        -- Deciding fields precede the shape dumps.
        has(rows[2], "axis=damage_source_id call=ok result_max=n/a verdict=damage_source_cap_unavailable lookup_rows=2 constant=n/a result=nil")
        has(rows[3], "axis=statistics_path_lookup")
        has(rows[3], "verdict=statistics_path_cap_unavailable lookup_rows=1")
        has(rows[4], "axis=damage_hotjoin_sync")
        has(rows[4], "verdict=health_sync_cap_unavailable lookup_rows=n/a")

        -- The per-phase guard, checked while the row bound is still far away.
        H.equal(probe.sample("load"), 0, "a phase samples once")
        H.equal(#probe.rows(), 4, "a repeated phase added rows")
        H.equal(#emitted, 4)

        H.equal(probe.poll(), false, "network sample fired before the authority existed")
        H.equal(#probe.rows(), 4)
        globals.NetworkConstants = {}
        H.equal(probe.poll(), false, "network sample fired without damage_source_id")
        H.equal(#probe.rows(), 4)

        globals.NetworkConstants = {
            damage_source_id = NETWORK_ROWS.damage_source_id,
            statistics_path_lookup = NETWORK_ROWS.statistics_path_lookup,
            damage_hotjoin_sync = NETWORK_ROWS.damage_hotjoin_sync,
        }
        globals.Network = network_returning(NETWORK_ROWS)
        H.equal(probe.poll(), true)
        rows = probe.rows()
        H.equal(#rows, 8)
        has(rows[5], "phase=network note=authority_appeared NetworkConstants=table")
        has(rows[6], "result_max=number:4095 verdict=cap:4095")
        has(rows[6], "constant=table{bits=number:12,max=number:4095,min=number:0}")
        has(rows[7], "verdict=cap:2047")
        has(rows[8], "verdict=cap:8191.75")

        H.equal(probe.poll(), false, "network sample is one-shot")
        H.equal(probe.sample("extra"), 0, "the ledger is bounded")
        H.equal(#probe.rows(), Diag.MAX_ROWS)
        H.equal(#emitted, Diag.MAX_ROWS)
        H.equal(probe.check(), nil)
    end)

    H.test("ET #324 probe check requires the network sample once the authority exists", function()
        local live = {
            NetworkConstants = { damage_source_id = NETWORK_ROWS.damage_source_id },
            Network = network_returning(NETWORK_ROWS),
        }
        -- check() drives the one-shot network sample itself.
        local _, polled = probe_fixture(live)
        polled.sample("load", "x")
        H.equal(polled.sampled("network"), false)
        H.equal(polled.check(), nil)
        H.equal(polled.sampled("network"), true)
        H.equal(#polled.rows(), 8)

        -- An authority that exists while the network rows are absent fails.
        local globals = { Network = network_returning({}) }
        local _, starved = probe_fixture(globals)
        starved.sample("load", "x")
        starved.sample("filler", "x")
        globals.NetworkConstants = live.NetworkConstants
        local failure = starved.check()
        H.truthy(type(failure) == "string" and failure:find("network sample has 0 rows", 1, true) ~= nil,
            "a missing network sample passed: " .. tostring(failure))
    end)

    H.test("ET #324 probe distinguishes thrown and userdata type_info results", function()
        -- Level 0: engine C errors carry no Lua source position.
        local thrown_globals = { Network = { type_info = function()
            error("network config not loaded", 0)
        end } }
        local _, thrown = probe_fixture(thrown_globals)
        thrown.sample("load", "x")
        has(thrown.rows()[2], "call=error:")
        has(thrown.rows()[2], "network config not loaded")
        has(thrown.rows()[2], "verdict=damage_source_cap_unavailable")

        local proxy = newproxy(true)
        getmetatable(proxy).__index = { max = 4095 }
        local userdata_globals = { Network = { type_info = function() return proxy end } }
        local _, boxed = probe_fixture(userdata_globals)
        boxed.sample("load", "x")
        has(boxed.rows()[2], "call=ok result_max=number:4095 verdict=damage_source_cap_unavailable",
            "the registrar's table-only reader would still refuse a userdata row")
        has(boxed.rows()[2], "result=userdata{max=number:4095}")

        local _, absent = probe_fixture({})
        absent.sample("load", "x")
        has(absent.rows()[1], "NetworkConstants=nil Network=nil type_info=nil indexed=n/a meta=n/a via=none")
        has(absent.rows()[2], "call=skipped result_max=n/a")
        has(absent.rows()[2], "result=n/a")

        -- Present only through __index: rawget misses it (as the registrar
        -- does), the normal index reaches it, and the rows say so.
        local hidden = setmetatable({}, { __index = {
            type_info = function(kind) return NETWORK_ROWS[kind] end,
        } })
        local _, meta = probe_fixture({ Network = hidden })
        meta.sample("load", "x")
        has(meta.rows()[1], "Network=table type_info=nil indexed=function meta=true via=index")
        has(meta.rows()[2], "call=ok result_max=number:4095 verdict=damage_source_cap_unavailable")
        has(meta.rows()[3], "call=ok result_max=number:2047 verdict=statistics_path_cap_unavailable")

        -- A throwing __index is reported, never raised.
        local trap = setmetatable({}, { __index = function() error("no field", 0) end })
        local _, trapped = probe_fixture({ Network = trap })
        H.equal(trapped.sample("load", "x"), 4)
        has(trapped.rows()[1], "type_info=nil indexed=index_error meta=true via=none")
        has(trapped.rows()[2], "call=skipped")
    end)

    H.test("ET #324 probe emits through a literal raw-printf route", function()
        local diag = read(diag_path)
        H.truthy(diag:find('pcall(printf, "[et:324] cap-probe %s", body)', 1, true) ~= nil,
            "the cap-probe rows lost their literal printf route")
        H.equal(diag:find('rawget(_G, "printf")', 1, true), nil,
            "a rawget printf helper hides the route from the live-test authority")
        -- Run the chunk in a test-local environment; the real printf global
        -- is never touched.
        local printed = {}
        local env = setmetatable({}, { __index = _G })
        env._G = env
        env.printf = function(fmt, ...)
            printed[#printed + 1] = { fmt = fmt, text = string.format(fmt, ...) }
        end
        local chunk = assert(loadfile(diag_path))
        setfenv(chunk, env)
        local Diag = chunk()
        local ET = { rt_register = function() end }
        local probe = Diag.install(ET, nil, "x")
        local rows = probe.rows()
        H.equal(#rows, 4)
        H.equal(#printed, 4)
        for i = 1, #rows do
            H.equal(printed[i].fmt, "[et:324] cap-probe %s")
            H.equal(printed[i].text, rows[i], "printed row differs from the ledger")
        end
    end)

    H.test("ET #324 probe in-game check and install wiring", function()
        local _, empty = probe_fixture({})
        H.truthy(type(empty.check()) == "string", "an unsampled probe passed its check")

        local Diag = fresh_diag()
        local registrar = fresh_registrar()
        local checks, at_register, poll_at_register = {}, nil, nil
        local ET = {}
        ET.rt_register = function(name, fn)
            checks[name] = fn
            -- Registered before the load sample: run now it must FAIL, so a
            -- broken sample is a FAIL line, never a missing check.
            at_register = fn()
            poll_at_register = type(ET.capacity_diag_poll)
        end
        local probe = Diag.install(ET, registrar, "rejected:damage_source_cap_unavailable")
        H.truthy(type(at_register) == "string" and at_register:find("load sample has 0 rows", 1, true) ~= nil,
            "the check was registered after the load sample: " .. tostring(at_register))
        H.equal(poll_at_register, "function", "the poll hook is wired after the check")
        H.equal(type(ET.capacity_diag_poll), "function")
        H.equal(type(checks[Diag.CHECK_NAME]), "function")
        H.equal(Diag.CHECK_NAME, "issue324_capacity_authority_probe")
        H.equal(#probe.rows(), 4, "install takes the load sample")
        has(probe.rows()[1], "phase=load note=rejected:damage_source_cap_unavailable")
        H.equal(checks[Diag.CHECK_NAME](), nil)
    end)

    H.test("ET #324 probe has one load owner and never writes printf or chats", function()
        local warlord = read(base .. "_et_skaven_warlord_breed.lua")
        local entry = read(base .. "enemy_tweaker.lua")
        local diag = read(diag_path)
        H.equal(count_plain(warlord, '"scripts/mods/enemy_tweaker/_et_diag_capacity_authority"'), 1)
        H.truthy(warlord:find("pcall(CapacityDiag.install, ET, Registrar,", 1, true) ~= nil)
        local update_at = assert(warlord:find("ET.warlord_diag_update = function()", 1, true))
        local poll_at = warlord:find("if ET.capacity_diag_poll then ET.capacity_diag_poll() end",
            update_at, true)
        H.truthy(poll_at ~= nil, "the #324 update dispatch does not drive the network sample")
        H.equal(entry:find("_et_diag_capacity_authority", 1, true), nil,
            "the entry manifest loads the probe a second time")
        H.equal(diag:find("printf%s*="), nil)
        H.equal(diag:find("rawset(_G", 1, true), nil)
        H.equal(diag:find("setfenv", 1, true), nil)
        H.equal(diag:find(":echo(", 1, true), nil)
        H.equal(diag:find(":chat", 1, true), nil)
        H.truthy(diag:find("M.MAX_ROWS = 8", 1, true) ~= nil)
        local ownership = read(repo_root .. "/qa/diagnostic_ownership.psd1")
        H.truthy(ownership:find(
            "Path='enemy_tweaker/scripts/mods/enemy_tweaker/_et_diag_capacity_authority.lua'",
            1, true) ~= nil, "probe is absent from the diagnostic ownership registry")
    end)
end
