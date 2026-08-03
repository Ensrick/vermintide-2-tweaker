return function(H, repo_root)
    local policy = dofile(repo_root .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_resume_policy.lua")

    local function object_with(names, values)
        local object = {}
        for _, name in ipairs(names) do
            object[name] = function() return values and values[name] or true end
        end
        return object
    end

    H.test("CT #141 inventories complete run and progress surfaces", function()
        local state = object_with(policy.PROGRESS_GETTERS)
        state.is_server = function() return true end
        state.get_player_power_ups = function() end
        state.get_player_soft_currency = function() end
        state.get_player_loadout = function() end
        state.set_player_power_ups = function() end
        state.set_player_soft_currency = function() end
        state.set_player_loadout = function() end
        state._shared_state = { full_sync = function() end }
        local controller = object_with(policy.CONFIG_GETTERS)
        controller._run_state = state
        local result = policy.inspect(controller)
        H.equal(result.config_methods, 7)
        H.equal(result.progress_methods, 4)
        H.truthy(result.server)
        H.truthy(result.full_sync)
        H.truthy(result.player_loadout and result.set_loadout)
    end)

    H.test("CT #141 distinguishes absent runtime from partial readiness", function()
        local absent = policy.inspect(nil)
        H.equal(absent.config_methods, 0)
        H.equal(absent.progress_methods, 0)
        local partial = policy.inspect({ get_run_id = function() return "run" end, _run_state = {} })
        H.equal(partial.config_methods, 1)
        H.equal(partial.config_values, 1)
        H.equal(partial.progress_methods, 0)
    end)

    H.test("CT #141 runtime audit remains observation only", function()
        local file = assert(io.open(repo_root .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_resume_audit.lua", "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find("mutation=false", 1, true))
        H.equal(source:find("mod:set(", 1, true), nil)
        H.equal(source:find("set_player_", 1, true), nil)
    end)

    -- #141 audit repair (2026-08-03): CAP=2 was fully consumed by the automatic
    -- StateIngame report, so manual /ct_resume_audit calls no-op'd; and the
    -- printf carried only counts, not the missing getter NAMES the issue card
    -- expects. Locks: names helpers are pure and bounded; the audit reserves
    -- manual budget and prints the names.
    H.test("CT #141 missing-getter helpers name absentees, bounded", function()
        H.equal(policy.joined_missing(object_with(policy.CONFIG_GETTERS), policy.CONFIG_GETTERS), "none")
        local partial = { get_run_id = function() end }
        local missing = policy.missing(partial, policy.CONFIG_GETTERS)
        H.equal(#missing, #policy.CONFIG_GETTERS - 1)
        H.equal(policy.missing(nil, policy.PROGRESS_GETTERS)[1], "get_current_node_key")
        local joined = policy.joined_missing(nil, policy.CONFIG_GETTERS)
        H.truthy(joined:find("get_run_seed", 1, true))
        H.truthy(joined:find("+1 more", 1, true),
            "7 missing config getters must be bounded to MISSING_NAME_CAP + '+N more'")
    end)

    H.test("CT #141 audit reserves manual capture budget and prints missing names", function()
        local file = assert(io.open(repo_root .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_resume_audit.lua", "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find("local CAP, MANUAL_RESERVE, captures = 6, 2, 0", 1, true),
            "CAP raise + manual reserve missing: auto StateIngame reports would starve /ct_resume_audit again")
        H.truthy(source:find('report("command", true)', 1, true),
            "manual command must draw from the reserved budget")
        H.truthy(source:find("config_missing=%s progress_missing=%s", 1, true),
            "printf must name the missing getters, not just count them")
        H.truthy(source:find("joined_missing", 1, true))
    end)
end
