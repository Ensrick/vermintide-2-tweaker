-- WP-GT-05 (audit finding A6-F03): every global nil-guard gt_dev installs lives
-- in _gt_engine_guards.lua, counts each firing, logs the first one, and can be
-- switched off at run time so the rig can test other mods with the guards off.
-- Loads the real module under stubs (pattern: test_gt_official_verify_rollup.lua)
-- and drives the captured hook closures.
return function(H, repo_root)
    local folder = repo_root .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/"

    local function load_guards(settings)
        settings = settings or {}
        local hooks, commands, printed = {}, {}, {}
        local state = { can_get = true }
        local env = setmetatable({}, { __index = _G })
        env._G = env
        env.World = {}
        env.Unit = { alive = function(unit) return unit ~= nil and unit.alive ~= false end }
        env.EnemyPackageLoader = {}
        env.AiUtils = {}
        env.BTConditions = {}
        env.VolumetricsFlowCallbacks = { unregister_fog_volume = function() end }
        env.AICommanderExtension = {}
        env.Application = { can_get = function() return state.can_get end }
        env.POSITION_LOOKUP = {}
        env.printf = function(fmt, ...) printed[#printed + 1] = string.format(fmt, ...) end
        local names = {
            [env.World] = "World", [env.Unit] = "Unit", [env.EnemyPackageLoader] = "EnemyPackageLoader",
            [env.AiUtils] = "AiUtils", [env.BTConditions] = "BTConditions",
            [env.VolumetricsFlowCallbacks] = "VolumetricsFlowCallbacks",
        }
        local mod = {}
        function mod:get(key) return settings[key] end
        function mod:set(key, value) settings[key] = value end
        function mod:hook(target, method, fn)
            local key = (type(target) == "string" and target or names[target]) .. "." .. method
            assert(not hooks[key], "duplicate hook " .. key)
            hooks[key] = fn
        end
        function mod:command(name, _, fn) commands[name] = fn end
        function mod:echo(fmt, ...) printed[#printed + 1] = string.format(fmt, ...) end
        env.get_mod = function() return mod end
        setfenv(assert(loadfile(folder .. "_gt_engine_guards.lua")), env)()
        return { hooks = hooks, commands = commands, printed = printed, state = state,
            mod = mod, env = env, settings = settings }
    end

    local function recorder()
        local seen = {}
        local fn = function(...)
            seen[#seen + 1] = { n = select("#", ...), ... }
            return "orig-ret"
        end
        return fn, seen
    end

    H.test("GT A6-F03 world_spawn_unit substitutes the empty unit and counts, then passes through when off", function()
        local g = load_guards()
        g.state.can_get = false
        local orig, seen = recorder()
        H.equal(g.hooks["World.spawn_unit"](orig, "world", "missing"), "orig-ret")
        H.equal(seen[1][2], "units/hub_elements/empty")
        H.equal(g.mod._gt_guard_counts.world_spawn_unit, 1)
        H.equal(#g.printed, 1, "the first firing is logged")
        H.truthy(g.printed[1]:find("[gt:guard] world_spawn_unit fired", 1, true))
        g.mod.gt_set_engine_guards(false)
        H.equal(g.settings.gt_engine_guards_enabled, false, "the switch is saved")
        g.hooks["World.spawn_unit"](orig, "world", "missing")
        H.equal(seen[2][2], "missing", "guards off: the caller's unit name reaches the engine")
        H.equal(g.mod._gt_guard_counts.world_spawn_unit, 1, "guards off: no count")
    end)

    H.test("GT A6-F03 with guards off every guard returns exactly what the original returns", function()
        local g = load_guards({ gt_engine_guards_enabled = false })
        local function orig() return "a", nil, "c" end
        local unit = { alive = false }
        local calls = {
            { "World.spawn_unit", { "world", "missing" } },
            { "Unit.get_data", { nil, "breed" } },
            { "Unit.create_actor", { "unit", -1 } },
            { "EnemyPackageLoader.request_breed", { {}, "skaven_slave", false } },
            { "AiUtils.update_aggro", { "unit", {}, {}, 1, 0.1 } },
            { "BTConditions.at_half_health", { {} } },
            { "BTConditions.less_than_one_health", { {} } },
            { "VolumetricsFlowCallbacks.unregister_fog_volume", { { unit = unit } } },
            { "PlayerWhereaboutsExtension.update", { {}, unit } },
            { "RoundStartedSystem._players_left_start_area", { { _units = { [unit] = true } } } },
            { "AICommanderExtension._update_units", { { _unit = unit }, 0.1, 1 } },
        }
        for _, call in ipairs(calls) do
            local hook = g.hooks[call[1]]
            H.truthy(hook, call[1] .. " is not owned by the guard module")
            local args = call[2]
            local results = { n = 0 }
            local function capture(...) results = { n = select("#", ...), ... } end
            capture(hook(orig, unpack(args, 1, table.maxn(args))))
            H.equal(results.n, 3, call[1] .. " must return all three values when off")
            H.equal(results[1], "a", call[1])
            H.equal(results[2], nil, call[1])
            H.equal(results[3], "c", call[1])
        end
        for name, count in pairs(g.mod._gt_guard_counts) do
            H.equal(count, 0, name .. " counted while guards were off")
        end
    end)

    H.test("GT A6-F03 Unit.get_data skips a nil unit and counts; off, the original runs", function()
        local g = load_guards()
        local orig, seen = recorder()
        H.equal(g.hooks["Unit.get_data"](orig, nil, "breed"), nil)
        H.equal(#seen, 0, "the original is not called for a nil unit")
        H.equal(g.mod._gt_guard_counts.unit_get_data, 1)
        g.mod.gt_set_engine_guards(false)
        g.hooks["Unit.get_data"](orig, nil, "breed")
        H.equal(#seen, 1, "guards off: the original runs")
    end)

    H.test("GT A6-F03 request_breed forces ignore_breed_limits only with guards on", function()
        local g = load_guards()
        local orig, seen = recorder()
        g.hooks["EnemyPackageLoader.request_breed"](orig, {}, "skaven_slave", false)
        H.equal(seen[1][3], true)
        g.mod.gt_set_engine_guards(false)
        g.hooks["EnemyPackageLoader.request_breed"](orig, {}, "skaven_slave", false)
        H.equal(seen[2][3], false, "guards off: the caller's value")
    end)

    H.test("GT A6-F03 the gt_guards command switches and reports", function()
        local g = load_guards()
        g.commands.gt_guards("off")
        H.equal(g.mod._gt_guards_on(), false)
        g.commands.gt_guards("on")
        H.equal(g.mod._gt_guards_on(), true)
        H.truthy(g.printed[#g.printed]:find("enabled=true", 1, true))
    end)

    H.test("GT A6-F03 the guard hooks live only in the guard module", function()
        local function read(name)
            local file = assert(io.open(folder .. name, "rb"))
            local text = file:read("*a")
            file:close()
            return text
        end
        for _, name in ipairs({ "_gt_creature_spawner.lua", "_gt_hacks.lua", "general_tweaker_dev.lua" }) do
            local text = read(name)
            for _, needle in ipairs({ "mod:hook(Unit, ", "mod:hook(World, ", '"request_breed"', '"update_aggro"',
                    '"unregister_fog_volume"', '"_players_left_start_area"', '"_update_units"' }) do
                H.equal(text:find(needle, 1, true), nil, name .. " still has " .. needle)
            end
        end
    end)
end
