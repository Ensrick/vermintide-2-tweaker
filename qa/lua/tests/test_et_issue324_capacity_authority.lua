-- #324: the #1413 registrar refuses et_skaven_warlord at mod load with
-- damage_source_cap_unavailable (12 of 12 tester logs on 0.7.64-dev). This
-- suite reproduces that refusal on a boot-shaped runtime (NetworkConstants
-- absent, Network.type_info yielding no capacity) and pins the bounded
-- diagnostic that records what the capacity readers see: the registrar's
-- read-only verdict seam, the probe's load and one-shot network samples, its
-- row bound, its in-game check, and its single load owner. No global is
-- written: the probe reads an injected globals table and emits through a
-- test-local seam.
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
        has(rows[1], "NetworkConstants=nil Network=table type_info=function")
        has(rows[2], "axis=damage_source_id constant=n/a call=ok result=nil result_max=n/a")
        has(rows[2], "verdict=damage_source_cap_unavailable lookup_rows=2")
        has(rows[3], "axis=statistics_path_lookup")
        has(rows[3], "verdict=statistics_path_cap_unavailable lookup_rows=1")
        has(rows[4], "axis=damage_hotjoin_sync")
        has(rows[4], "verdict=health_sync_cap_unavailable lookup_rows=n/a")

        H.equal(probe.poll(), false, "network sample fired before the authority existed")
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
        has(rows[6], "constant=table{bits=number:12,max=number:4095,min=number:0}")
        has(rows[6], "result_max=number:4095 verdict=cap:4095")
        has(rows[7], "verdict=cap:2047")
        has(rows[8], "verdict=cap:8191.75")

        H.equal(probe.poll(), false, "network sample is one-shot")
        H.equal(probe.sample("load"), 0, "a phase samples once")
        H.equal(probe.sample("extra"), 0, "the ledger is bounded")
        H.equal(#probe.rows(), Diag.MAX_ROWS)
        H.equal(#emitted, Diag.MAX_ROWS)
        H.equal(probe.check(), nil)
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
        has(boxed.rows()[2], "call=ok result=userdata{max=number:4095} result_max=number:4095")
        has(boxed.rows()[2], "verdict=damage_source_cap_unavailable",
            "the registrar's table-only reader would still refuse a userdata row")

        local _, absent = probe_fixture({})
        absent.sample("load", "x")
        has(absent.rows()[1], "NetworkConstants=nil Network=nil type_info=nil")
        has(absent.rows()[2], "call=skipped result=n/a")
    end)

    H.test("ET #324 probe in-game check and install wiring", function()
        local _, empty = probe_fixture({})
        H.truthy(type(empty.check()) == "string", "an unsampled probe passed its check")

        local Diag = fresh_diag()
        local registrar = fresh_registrar()
        local checks = {}
        local ET = { rt_register = function(name, fn) checks[name] = fn end }
        local probe = Diag.install(ET, registrar, "rejected:damage_source_cap_unavailable")
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
