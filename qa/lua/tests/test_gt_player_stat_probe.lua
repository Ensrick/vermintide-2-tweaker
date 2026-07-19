return function(H, repo_root)
    local core = dofile(repo_root
        .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_player_stat_probe_core.lua")
    local function read(path)
        local file = assert(io.open(path, "rb"))
        local value = file:read("*a")
        file:close()
        return value
    end

    H.test("GT #797 census normalizes authoritative stat rows deterministically", function()
        local snapshot = core.normalize({
            critical_strike_chance = {
                [2] = { bonus = 0.05, multiplier = 0, proc_chance = 0.5 },
                [0] = { bonus = 0.10, multiplier = 0.20, proc_chance = 1 },
            },
            power_level = {
                [0] = { bonus = 0, multiplier = function() end, proc_chance = 1 },
            },
            empty = {},
        }, { critical_strike_chance = "stacking_bonus", power_level = "stacking_multiplier" })
        H.equal(#snapshot.rows, 2)
        H.equal(snapshot.rows[1].stat, "critical_strike_chance")
        H.truthy(math.abs(snapshot.rows[1].bonus - 0.15) < 0.000001)
        H.truthy(math.abs(snapshot.rows[1].multiplier - 0.20) < 0.000001)
        H.equal(snapshot.rows[2].dynamic, 1)
        H.equal(snapshot.rows[1].conditional, 1)
        H.equal(snapshot.contributions, 3)
        H.equal(snapshot.stat_types, 3)
        H.equal(snapshot.truncated, false)
        H.equal(core.fingerprint(snapshot), core.fingerprint(snapshot))
    end)

    H.test("GT #797 census bounds inspected stat types, including empty rows", function()
        local rows = {}
        for i = 1, core.MAX_STAT_TYPES + 10 do rows[string.format("stat_%04d", i)] = {} end
        local snapshot = core.normalize(rows, {})
        H.equal(snapshot.stat_types, core.MAX_STAT_TYPES)
        H.equal(#snapshot.rows, 0)
        H.equal(snapshot.truncated, true)
    end)

    H.test("GT #797 trace cadence and record count are hard bounded", function()
        local trace = core.new_trace(5)
        H.equal(core.take_due(trace, 4.99), nil)
        for i, offset in ipairs(core.TRACE_OFFSETS) do
            H.equal(core.take_due(trace, 5 + offset), offset)
            H.equal(core.record(trace, offset, "fp" .. i), true)
        end
        H.equal(core.take_due(trace, 100), nil)
        H.equal(core.record(trace, 99, "overflow"), false)
        H.equal(#trace.records, 5)
        H.equal(core.complete(trace), true)
    end)

    H.test("GT #797 production is read-only local and uses the shared update owner", function()
        local source = read(repo_root
            .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_diag_player_stats.lua")
        for _, marker in ipairs({
            'mod._gt_register_update("gt797_player_stat_probe", _update)',
            'mod:command("gt_stat_probe"',
            'mod:command("gt_stat_trace"',
            'issue797_player_stat_diagnostics_armed',
            'rawget(_G, "StatBuffApplicationMethods")',
        }) do
            H.truthy(source:find(marker, 1, true), marker)
        end
        H.equal(source:find("mod:network_", 1, true), nil)
        H.equal(source:find("mod:hook", 1, true), nil)
        H.equal(source:find("mod:echo", 1, true), nil)
        H.equal(source:find("apply_buffs_to_value", 1, true), nil)
        H.equal(source:find("mod.update =", 1, true), nil)
        H.truthy(source:find("ScriptUnit.has_extension", 1, true))
    end)

    H.test("GT #797 main loads the probe after the update and runtime-check owners", function()
        local main = read(repo_root
            .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/general_tweaker_dev.lua")
        local registry = assert(main:find("mod._gt_register_update = _register_update", 1, true))
        local checks = assert(main:find("mod._gt_rt_register = _rt_register", 1, true))
        local probe = assert(main:find('mod:dofile("scripts/mods/general_tweaker_dev/_gt_diag_player_stats")', 1, true))
        H.truthy(probe > registry and probe > checks)
    end)
end
