return function(H, repo_root)
    local mod_root = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local owner_path = mod_root .. "_ct_diag_gargoyle1124.lua"
    local entry_path = mod_root .. "chaos_wastes_tweaker_dev.lua"

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count_plain(source, needle)
        local count, cursor = 0, 1
        while true do
            local at = source:find(needle, cursor, true)
            if not at then return count end
            count = count + 1
            cursor = at + #needle
        end
    end

    local function phase_count(logs, phase)
        local count = 0
        for _, line in ipairs(logs) do
            if line:find("phase=" .. phase, 1, true) then count = count + 1 end
        end
        return count
    end

    local function exercise_fixture(body)
        local saved = {
            LevelHelper = rawget(_G, "LevelHelper"),
            Managers = rawget(_G, "Managers"),
            ScriptUnit = rawget(_G, "ScriptUnit"),
            Unit = rawget(_G, "Unit"),
            printf = rawget(_G, "printf"),
        }
        local state = {
            injected = true,
            key = "dlc_portals_khorne_path1",
            logs = {},
            session = 1,
        }
        local hooks, checks = {}, {}
        local fake_mod = {}

        function fake_mod:hook(class_name, method_name, callback)
            local key = class_name .. "." .. method_name
            assert(hooks[key] == nil, "duplicate hook in fixture: " .. key)
            hooks[key] = callback
        end

        _G.LevelHelper = {
            current_level_settings = function()
                return { level_id = state.key }
            end,
        }
        _G.Managers = {
            level_transition_handler = {
                get_current_level_session_id = function()
                    return state.session
                end,
            },
            state = {
                unit_storage = {
                    go_id = function(_, unit)
                        return type(unit) == "table" and unit.go_id or nil
                    end,
                },
            },
        }
        _G.Unit = {
            get_data = function(unit, ...)
                if type(unit) ~= "table" then return nil end
                local value = unit.data
                for index = 1, select("#", ...) do
                    if type(value) ~= "table" then return nil end
                    value = value[select(index, ...)]
                end
                return value
            end,
        }
        _G.ScriptUnit = {
            has_extension = function(unit, extension_name)
                return type(unit) == "table" and type(unit.extensions) == "table"
                    and unit.extensions[extension_name] or nil
            end,
        }
        _G.printf = function(fmt, ...)
            state.logs[#state.logs + 1] = string.format(fmt, ...)
        end

        local installer = assert(loadfile(owner_path))()
        local ctx = {
            adventure_base_from_level_key = function(key)
                if type(key) == "string"
                    and key:find("^dlc_portals")
                then
                    return "dlc_portals"
                end
                return "dlc_bastion"
            end,
            on_injected_adventure_level = function()
                return state.injected
            end,
            rt_register = function(name, check)
                checks[#checks + 1] = { name = name, check = check }
            end,
        }

        local function run()
            local api = installer(fake_mod, ctx)
            body({
                api = api,
                checks = checks,
                ctx = ctx,
                hooks = hooks,
                installer = installer,
                logs = state.logs,
                mod = fake_mod,
                state = state,
            })
        end

        local ok, failure = xpcall(run, debug.traceback)
        _G.LevelHelper = saved.LevelHelper
        _G.Managers = saved.Managers
        _G.ScriptUnit = saved.ScriptUnit
        _G.Unit = saved.Unit
        _G.printf = saved.printf
        if not ok then error(failure, 0) end
    end

    H.test("CT #1124 owner is retained after injected-adventure identity", function()
        local owner = read(owner_path)
        local entry = read(entry_path)
        local manifest = read(repo_root .. "/qa/decomposition_contracts.psd1")
        local load_needle =
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_diag_gargoyle1124"
        H.equal(count_plain(entry, load_needle), 1)
        H.equal(count_plain(manifest, "'_ct_diag_gargoyle1124.lua'"), 1)
        H.equal(count_plain(owner, "mod:hook("), 6)
        H.equal(count_plain(owner, "mod:hook_safe("), 0)
        H.equal(count_plain(owner, "mod:network_register("), 0)
        H.equal(count_plain(owner, "mod:command("), 0)
        H.equal(count_plain(owner, "mod.update"), 0)

        local adventure_at = assert(entry:find(
            "local on_injected_adventure_level = _ct_adventure_runtime.on_injected_adventure_level",
            1, true))
        local diag_at = assert(entry:find(load_needle, 1, true))
        local next_owner_at = assert(entry:find(
            'mod:hook("GearUtils", "create_equipment"', diag_at, true))
        H.truthy(adventure_at < diag_at and diag_at < next_owner_at)

        for _, pair in ipairs({
            'mod:hook("LimitedItemTrackSystem", "on_add_extension"',
            'mod:hook("LimitedItemTrackSystem", "register_group"',
            'mod:hook("LimitedItemTrackSystem", "activate_group"',
            'mod:hook("LimitedItemTrackSpawner", "spawn_item"',
            'mod:hook("LimitedItemTrackSpawner", "socket_item"',
            'mod:hook("MissionSystem", "flow_callback_update_mission"',
        }) do
            H.equal(count_plain(owner, pair), 1, pair)
            H.equal(count_plain(entry, pair), 0, pair .. " must stay out of entry")
        end
    end)

    H.test("CT #1124 owner is strictly observation-only and bounded", function()
        local source = read(owner_path)
        H.truthy(source:find('MARKER = "CT_GARGOYLE1124_OBSERVATION_ONLY_V1"', 1, true))
        H.truthy(source:find('pcall(printf, "[ct:1124] %s", line)', 1, true))
        H.equal(source:find('rawget(_G, "printf")', 1, true), nil)
        H.truthy(source:find("RUN_RECORD_CAP = 96", 1, true))
        H.truthy(source:find("TOTAL_RECORD_CAP = 512", 1, true))
        H.truthy(source:find("mutation=false", 1, true))
        for _, forbidden in ipairs({
            "Unit.set_data(",
            "mark_for_deletion(",
            "spawn_network_unit(",
            "start_mission(",
            "update_mission(",
            "socketed_items[",
        }) do
            H.equal(source:find(forbidden, 1, true), nil,
                "diagnostic gained a mutation surface: " .. forbidden)
        end
    end)

    H.test("CT #1124 installer is idempotent and registers one runtime check", function()
        exercise_fixture(function(f)
            local hook_count = 0
            for _ in pairs(f.hooks) do hook_count = hook_count + 1 end
            H.equal(hook_count, 6)
            H.equal(#f.checks, 1)
            H.equal(f.checks[1].name, "issue1124_gargoyle_objective_diagnostic")
            H.equal(f.checks[1].check(), nil)
            local second = f.installer(f.mod, f.ctx)
            H.equal(second, f.api)
            local after = 0
            for _ in pairs(f.hooks) do after = after + 1 end
            H.equal(after, 6)
            H.equal(#f.checks, 1)
            H.equal(f.mod._ct_gargoyle1124, f.api)
            H.equal(f.api.MARKER, "CT_GARGOYLE1124_OBSERVATION_ONLY_V1")
        end)
    end)

    H.test("CT #1124 wrappers are inert outside injected Old Haunts", function()
        exercise_fixture(function(f)
            f.state.injected = false
            local unit = {
                data = {
                    group_name = "portals_gargoyles",
                    pickup_name = "",
                    template_name = "gargoyle_head_spawner_vs",
                },
                go_id = 41,
            }
            local extension = { pool = 1, template_name = "gargoyle_head_spawner_vs" }
            local extra = {}
            local called = 0
            local a, b, c = f.hooks["LimitedItemTrackSystem.on_add_extension"](
                function(self, world, got_unit, name, init, got_extra)
                    called = called + 1
                    H.equal(got_unit, unit)
                    H.equal(name, "LimitedItemTrackSpawner")
                    H.equal(got_extra, extra)
                    return extension, nil, "tail"
                end,
                {}, "world", unit, "LimitedItemTrackSpawner", {}, extra)
            H.equal(called, 1)
            H.equal(a, extension)
            H.equal(b, nil)
            H.equal(c, "tail")
            H.equal(#f.logs, 0)
            H.equal(f.api.snapshot(), nil)

            f.state.injected = true
            f.state.key = "dlc_bastion_khorne_path1"
            f.hooks["LimitedItemTrackSystem.on_add_extension"](
                function() return extension end,
                {}, "world", unit, "LimitedItemTrackSpawner", {})
            H.equal(#f.logs, 0)
            H.equal(f.api.snapshot(), nil)
        end)
    end)

    H.test("CT #1124 pre-snapshots are target-gated and fault-isolated", function()
        exercise_fixture(function(f)
            local reads = 0
            local poisoned = setmetatable({}, {
                __index = function(_, key)
                    reads = reads + 1
                    error("planted pre-read fault: " .. tostring(key))
                end,
            })
            local spawn = f.hooks["LimitedItemTrackSpawner.spawn_item"]
            local socket = f.hooks["LimitedItemTrackSpawner.socket_item"]
            local item = {}
            local extra = {}
            local calls = 0

            f.state.injected = false
            local a, b, c = spawn(function(got_self, got_extra)
                calls = calls + 1
                H.equal(got_self, poisoned)
                H.equal(got_extra, extra)
                return "non-target-spawn", nil, "tail"
            end, poisoned, extra)
            H.equal(a, "non-target-spawn")
            H.equal(b, nil)
            H.equal(c, "tail")

            local d, e, g = socket(function(got_self, got_item, got_extra)
                calls = calls + 1
                H.equal(got_self, poisoned)
                H.equal(got_item, item)
                H.equal(got_extra, extra)
                return "non-target-socket", nil, "tail"
            end, poisoned, item, extra)
            H.equal(d, "non-target-socket")
            H.equal(e, nil)
            H.equal(g, "tail")
            H.equal(reads, 0)
            H.equal(calls, 2)
            H.equal(#f.logs, 0)
            H.equal(f.api.snapshot(), nil)

            f.state.injected = true
            local h, i, j = spawn(function(got_self, got_extra)
                calls = calls + 1
                H.equal(got_self, poisoned)
                H.equal(got_extra, extra)
                return "target-spawn", nil, "tail"
            end, poisoned, extra)
            H.equal(h, "target-spawn")
            H.equal(i, nil)
            H.equal(j, "tail")

            local k, l, m = socket(function(got_self, got_item, got_extra)
                calls = calls + 1
                H.equal(got_self, poisoned)
                H.equal(got_item, item)
                H.equal(got_extra, extra)
                return "target-socket", nil, "tail"
            end, poisoned, item, extra)
            H.equal(k, "target-socket")
            H.equal(l, nil)
            H.equal(m, "tail")
            H.equal(reads, 2)
            H.equal(calls, 4)
            H.equal(#f.logs, 0)
            local snapshot = assert(f.api.snapshot())
            H.equal(snapshot.spawn_attempts, 0)
            H.equal(snapshot.spawned, 0)
            H.equal(snapshot.valid_pickups, 0)
        end)
    end)

    H.test("CT #1124 spawn evidence separates attempts confirmed units and valid pickups", function()
        exercise_fixture(function(f)
            local spawn = f.hooks["LimitedItemTrackSpawner.spawn_item"]
            local unit = {
                data = {
                    group_name = "portals_gargoyles",
                    pickup_name = "",
                    template_name = "gargoyle_head_spawner_vs",
                },
                go_id = 801,
            }
            local spawner = {
                items = {},
                num_items = 0,
                num_socketed_items = 0,
                pool = 1,
                template_name = "gargoyle_head_spawner_vs",
                unit = unit,
            }

            local a, b, c = spawn(function()
                return "no-delta", nil, "tail"
            end, spawner)
            H.equal(a, "no-delta")
            H.equal(b, nil)
            H.equal(c, "tail")
            local first = assert(f.api.snapshot())
            H.equal(first.spawn_attempts, 1)
            H.equal(first.spawned, 0)
            H.equal(first.valid_pickups, 0)
            H.truthy(f.logs[#f.logs]:find("confirmed=false", 1, true))
            H.truthy(f.logs[#f.logs]:find("valid=false", 1, true))

            local incomplete = {
                data = { pickup_name = "gargoyle_head" },
                extensions = {},
                go_id = 802,
            }
            local d, e, g = spawn(function(self)
                self.items[1] = incomplete
                self.num_items = self.num_items + 1
                return "ledger-only", nil, "tail"
            end, spawner)
            H.equal(d, "ledger-only")
            H.equal(e, nil)
            H.equal(g, "tail")
            local second = assert(f.api.snapshot())
            H.equal(second.spawn_attempts, 2)
            H.equal(second.spawned, 1)
            H.equal(second.valid_pickups, 0)
            H.truthy(f.logs[#f.logs]:find("confirmed=true", 1, true))
            H.truthy(f.logs[#f.logs]:find("pickup_extension=false", 1, true))
            H.truthy(f.logs[#f.logs]:find("valid=false", 1, true))
        end)
    end)

    H.test("CT #1124 production wrappers record all four native transitions", function()
        exercise_fixture(function(f)
            local add = f.hooks["LimitedItemTrackSystem.on_add_extension"]
            local spawn = f.hooks["LimitedItemTrackSpawner.spawn_item"]
            local socket = f.hooks["LimitedItemTrackSpawner.socket_item"]
            local spawners = {}

            for ordinal = 1, 4 do
                local unit = {
                    data = {
                        group_name = "portals_gargoyles",
                        pickup_name = ordinal == 4 and "gargoyle_head" or "",
                        template_name = "gargoyle_head_spawner_vs",
                    },
                    go_id = 100 + ordinal,
                }
                local extension = {
                    items = {},
                    num_items = 0,
                    num_socketed_items = 0,
                    pool = 1,
                    template_name = "gargoyle_head_spawner_vs",
                    unit = unit,
                }
                extension.find_item_id = function(self, item)
                    for id, value in pairs(self.items) do
                        if value == item then return id end
                    end
                end
                local extra = { ordinal = ordinal }
                local a, b, c = add(function(_, _, got_unit, name, _, got_extra)
                    H.equal(got_unit, unit)
                    H.equal(name, "LimitedItemTrackSpawner")
                    H.equal(got_extra, extra)
                    return extension, nil, "registered"
                end, {}, "world", unit, "LimitedItemTrackSpawner", {}, extra)
                H.equal(a, extension)
                H.equal(b, nil)
                H.equal(c, "registered")
                spawners[ordinal] = extension
            end

            local group_system = { active_groups = {}, active_groups_n = 0, groups = {} }
            local register_extra = {}
            local r1, r2, r3 = f.hooks["LimitedItemTrackSystem.register_group"](
                function(self, name, pool, got_extra)
                    H.equal(got_extra, register_extra)
                    self.groups[name] = {
                        pool_size = pool,
                        spawners = spawners,
                        spawners_n = #spawners,
                    }
                    return "register", nil, 17
                end,
                group_system, "portals_gargoyles", 4, register_extra)
            H.equal(r1, "register")
            H.equal(r2, nil)
            H.equal(r3, 17)

            local activate_extra = {}
            local a1, a2 = f.hooks["LimitedItemTrackSystem.activate_group"](
                function(self, name, pool, got_extra)
                    H.equal(got_extra, activate_extra)
                    self.groups[name].pool_size = pool
                    self.active_groups[1] = name
                    self.active_groups_n = 1
                    return "activate", "tail"
                end,
                group_system, "portals_gargoyles", 4, activate_extra)
            H.equal(a1, "activate")
            H.equal(a2, "tail")

            for ordinal, spawner in ipairs(spawners) do
                local item = {
                    data = { pickup_name = "gargoyle_head" },
                    extensions = {
                        pickup_system = { pickup_name = "gargoyle_head" },
                    },
                    go_id = 200 + ordinal,
                }
                local spawn_extra = {}
                local s1, s2, s3 = spawn(function(self, got_extra)
                    H.equal(got_extra, spawn_extra)
                    self.items[1] = item
                    self.num_items = self.num_items + 1
                    return "spawned", nil, ordinal
                end, spawner, spawn_extra)
                H.equal(s1, "spawned")
                H.equal(s2, nil)
                H.equal(s3, ordinal)

                local socket_extra = {}
                local k1, k2, k3 = socket(function(self, got_item, got_extra)
                    H.equal(got_item, item)
                    H.equal(got_extra, socket_extra)
                    self.num_socketed_items = self.num_socketed_items + 1
                    return "socketed", nil, ordinal
                end, spawner, item, socket_extra)
                H.equal(k1, "socketed")
                H.equal(k2, nil)
                H.equal(k3, ordinal)
            end

            local mission = {
                active_missions = {},
                completed_missions = {},
            }
            local data = {
                collect_amount = 4,
                current_amount = 0,
                get_current_amount = function(self) return self.current_amount end,
            }
            mission.active_missions.portals_survive = data
            local objective = f.hooks["MissionSystem.flow_callback_update_mission"]
            for ordinal = 1, 4 do
                local extra = {}
                local o1, o2, o3 = objective(function(self, name, got_extra)
                    H.equal(name, "portals_survive")
                    H.equal(got_extra, extra)
                    data.current_amount = data.current_amount + 1
                    if data.current_amount == data.collect_amount then
                        self.completed_missions[name] = data
                        self.active_missions[name] = nil
                    end
                    return "objective", nil, ordinal
                end, mission, "portals_survive", extra)
                H.equal(o1, "objective")
                H.equal(o2, nil)
                H.equal(o3, ordinal)
            end

            local snapshot = assert(f.api.snapshot())
            H.equal(snapshot.level_base, "dlc_portals")
            H.equal(snapshot.level_session_id, "1")
            H.equal(snapshot.spawner_count, 4)
            H.equal(snapshot.spawn_attempts, 4)
            H.equal(snapshot.spawned, 4)
            H.equal(snapshot.valid_pickups, 4)
            H.equal(snapshot.socketed, 4)
            H.equal(snapshot.objective_updates, 4)
            H.equal(snapshot.objective_amount, 4)
            H.equal(snapshot.objective_required, 4)
            H.equal(snapshot.objective_completed, true)
            H.equal(#snapshot.spawners, 4)
            for ordinal, record in ipairs(snapshot.spawners) do
                H.equal(record.ordinal, ordinal)
                H.equal(record.template_name, "gargoyle_head_spawner_vs")
                H.equal(record.final_pickup, "gargoyle_head")
            end

            H.equal(phase_count(f.logs, "authored"), 4)
            H.equal(phase_count(f.logs, "group_register"), 1)
            H.equal(phase_count(f.logs, "group_activate"), 1)
            H.equal(phase_count(f.logs, "spawn"), 4)
            H.equal(phase_count(f.logs, "socket"), 4)
            H.equal(phase_count(f.logs, "objective"), 4)
            H.truthy(f.logs[#f.logs]:find("progress_after=4/4", 1, true))
            H.truthy(f.logs[#f.logs]:find("completed=true", 1, true))
            H.truthy(f.logs[#f.logs]:find("spawn_attempts=4", 1, true))
            H.truthy(f.logs[#f.logs]:find("valid_pickups=4", 1, true))
            H.truthy(f.logs[#f.logs]:find("mutation=false", 1, true))
            H.equal(f.checks[1].check(), nil)
        end)
    end)

    H.test("CT #1124 ledger resets when a level key is reused next session", function()
        exercise_fixture(function(f)
            local add = f.hooks["LimitedItemTrackSystem.on_add_extension"]
            local function add_spawner(go_id)
                local unit = {
                    data = {
                        group_name = "portals_gargoyles",
                        pickup_name = "",
                        template_name = "gargoyle_head_spawner_vs",
                    },
                    go_id = go_id,
                }
                local extension = {
                    pool = 1,
                    template_name = "gargoyle_head_spawner_vs",
                    unit = unit,
                }
                add(function() return extension end,
                    {}, "world", unit, "LimitedItemTrackSpawner", {})
            end

            f.state.session = 41
            add_spawner(941)
            local first = assert(f.api.snapshot())
            H.equal(first.level_session_id, "41")
            H.equal(first.spawner_count, 1)

            f.state.session = 42
            add_spawner(942)
            local second = assert(f.api.snapshot())
            H.equal(second.level_session_id, "42")
            H.equal(second.spawner_count, 1)
            H.equal(#second.spawners, 1)
            H.equal(second.spawners[1].ordinal, 1)
        end)
    end)

    H.test("CT #1124 diagnostic faults cannot replace native success", function()
        exercise_fixture(function(f)
            _G.Unit.get_data = function() error("diagnostic read failed") end
            local unit = { go_id = 901 }
            local extension = {
                items = {},
                num_items = 0,
                num_socketed_items = 0,
                pool = 1,
                template_name = "gargoyle_head_spawner_vs",
                unit = unit,
            }
            local a, b, c = f.hooks["LimitedItemTrackSystem.on_add_extension"](
                function() return extension, nil, "native-tail" end,
                {}, "world", unit, "LimitedItemTrackSpawner", {})
            H.equal(a, extension)
            H.equal(b, nil)
            H.equal(c, "native-tail")

            local mission = setmetatable({}, {
                __index = function() error("diagnostic mission read failed") end,
            })
            local objective_extra = {}
            local o1, o2, o3 = f.hooks["MissionSystem.flow_callback_update_mission"](
                function(_, name, got_extra)
                    H.equal(name, "portals_survive")
                    H.equal(got_extra, objective_extra)
                    return "native-objective", nil, "tail"
                end,
                mission, "portals_survive", objective_extra)
            H.equal(o1, "native-objective")
            H.equal(o2, nil)
            H.equal(o3, "tail")

            local ok, failure = pcall(
                f.hooks["LimitedItemTrackSpawner.spawn_item"],
                function() error("native failure") end, extension)
            H.equal(ok, false)
            H.truthy(tostring(failure):find("native failure", 1, true))
        end)
    end)

    H.test("CT #1124 output caps are behavioral and never suppress vanilla", function()
        exercise_fixture(function(f)
            local register = f.hooks["LimitedItemTrackSystem.register_group"]
            local system = {
                active_groups = {},
                active_groups_n = 0,
                groups = {},
            }
            local calls = 0

            local function drive(session, ordinal)
                f.state.session = session
                local name = string.format("cap_%d_%d", session, ordinal)
                local a, b, c = register(function(self, group_name, pool_size)
                    calls = calls + 1
                    self.groups[group_name] = {
                        pool_size = pool_size,
                        spawners = {},
                        spawners_n = 0,
                    }
                    return "native", nil, calls
                end, system, name, 1)
                H.equal(a, "native")
                H.equal(b, nil)
                H.equal(c, calls)
            end

            for ordinal = 1, 100 do drive(1, ordinal) end
            H.equal(#f.logs, 96)

            for session = 2, 7 do
                for ordinal = 1, 100 do drive(session, ordinal) end
            end
            H.equal(calls, 700)
            H.equal(#f.logs, 512)
        end)
    end)

    H.test("CT #1124 direct engine output is fail-closed", function()
        exercise_fixture(function(f)
            local register = f.hooks["LimitedItemTrackSystem.register_group"]
            local system = {
                active_groups = {},
                active_groups_n = 0,
                groups = {},
            }
            local calls = 0
            local function native(self, group_name, pool_size)
                calls = calls + 1
                self.groups[group_name] = {
                    pool_size = pool_size,
                    spawners = {},
                    spawners_n = 0,
                }
                return "native", nil, calls
            end

            _G.printf = nil
            local a, b, c = register(native, system, "missing_printf", 1)
            H.equal(a, "native")
            H.equal(b, nil)
            H.equal(c, 1)

            _G.printf = function() error("engine logger failure") end
            a, b, c = register(native, system, "throwing_printf", 1)
            H.equal(a, "native")
            H.equal(b, nil)
            H.equal(c, 2)
        end)
    end)

    local source_roots = {
        repo_root .. "/../Vermintide-2-Source-Code/scripts/",
        repo_root .. "/../../../../source/repos/Vermintide-2-Source-Code/scripts/",
    }
    local source_root
    for _, candidate in ipairs(source_roots) do
        local probe = io.open(candidate
            .. "unit_extensions/limited_item_track/limited_item_track_spawner_templates.lua", "rb")
        if probe then probe:close(); source_root = candidate; break end
    end

    H.test_if(source_root ~= nil,
        "CT #1124 hooks match the current native gargoyle objective path", function()
        local templates = read(source_root
            .. "unit_extensions/limited_item_track/limited_item_track_spawner_templates.lua")
        local spawner = read(source_root
            .. "unit_extensions/limited_item_track/limited_item_track_spawner.lua")
        local system = read(source_root
            .. "entity_system/systems/limited_item_track/limited_item_track_system.lua")
        local socket = read(source_root
            .. "entity_system/systems/objective_socket/objective_socket_system.lua")
        local mission = read(source_root
            .. "entity_system/systems/mission/mission_system.lua")
        local settings = read(source_root
            .. "settings/dlcs/penny/penny_level_settings_part_1.lua")

        local template_at = assert(templates:find(
            "LimitedItemTrackSpawnerTemplates.gargoyle_head_spawner_vs = {", 1, true))
        local default_at = assert(templates:find(
            'pickup_name = pickup_name ~= "" and pickup_name or "gargoyle_head"',
            template_at, true))
        local network_at = assert(templates:find(
            "Managers.state.unit_spawner:spawn_network_unit", default_at, true))
        H.truthy(template_at < default_at and default_at < network_at)

        H.truthy(system:find(
            "LimitedItemTrackSystem.on_add_extension = function", 1, true))
        H.truthy(system:find(
            "LimitedItemTrackSystem.register_group = function", 1, true))
        H.truthy(system:find(
            "LimitedItemTrackSystem.activate_group = function", 1, true))
        H.truthy(spawner:find(
            "LimitedItemTrackSpawner.spawn_item = function", 1, true))
        H.truthy(spawner:find(
            "LimitedItemTrackSpawner.socket_item = function", 1, true))
        H.truthy(socket:find(
            "limited_item_track_spawner_extension:socket_item(unit)", 1, true))
        H.truthy(mission:find(
            "MissionSystem.flow_callback_update_mission = function", 1, true))
        local objective_at = assert(settings:find("portals_survive = {", 1, true))
        local amount_at = assert(settings:find("collect_amount = 4", objective_at, true))
        local text_at = assert(settings:find(
            'text = "mission_restore_the_gargoyle_heads"', amount_at, true))
        H.truthy(objective_at < amount_at and amount_at < text_at)
        end, "optional decompiled vanilla source is not present in this clone")
end
