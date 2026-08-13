return function(H, repo_root)
    local runtime_path = repo_root
        .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_dev_heal.lua"
    local readiness = dofile(repo_root
        .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_network_readiness.lua")

    local function load_runtime(options)
        options = options or {}
        local commands = {}
        local updates = {}
        local checks = {}
        local prints = {}
        local echoes = {}
        local debug_calls = {}
        local unit = {}
        local state = {
            current = options.current or 25,
            maximum = options.maximum or 100,
            wounded = options.wounded ~= false,
            unit_alive = options.unit_alive ~= false,
            health_alive = options.health_alive ~= false,
            disabled = options.disabled == true,
            dead = options.dead == true,
            knocked_down = options.knocked_down == true,
            wounded_mode = options.wounded_mode or "normal",
            disabled_mode = options.disabled_mode or "normal",
            health_alive_mode = options.health_alive_mode or "normal",
        }
        local function accessor(value_name, mode_name)
            return function()
                local mode = state[mode_name]
                if mode == "throw" then error(mode_name .. " unavailable") end
                if mode == "nonboolean" then return "unknown" end
                return state[value_name]
            end
        end
        local health = {
            current_permanent_health = function() return state.current end,
            get_max_health = function() return state.maximum end,
        }
        if not options.health_alive_method_missing then
            health.is_alive = accessor("health_alive", "health_alive_mode")
        end
        local status = {
            is_dead = function() return state.dead end,
            is_knocked_down = function() return state.knocked_down end,
        }
        if not options.wounded_method_missing then
            status.is_wounded = accessor("wounded", "wounded_mode")
        end
        if not options.disabled_method_missing then
            status.is_disabled = accessor("disabled", "disabled_mode")
        end
        local mod = {
            dofile = function(_, path)
                H.equal(path, "scripts/mods/general_tweaker_dev/_gt_network_readiness")
                return readiness
            end,
            command = function(_, name, _, fn) commands[name] = fn end,
            _gt_register_update = function(name, fn) updates[name] = fn end,
            _gt_rt_register = function(name, fn) checks[name] = fn end,
            echo = function(_, fmt, ...)
                echoes[#echoes + 1] = string.format(fmt, ...)
            end,
        }

        local old = {
            get_mod = _G.get_mod,
            Managers = _G.Managers,
            ScriptUnit = _G.ScriptUnit,
            Unit = _G.Unit,
            DamageUtils = _G.DamageUtils,
            NetworkLookup = _G.NetworkLookup,
            printf = _G.printf,
        }
        _G.get_mod = function() return mod end
        _G.Managers = {
            state = { network = { game = function() return {} end } },
            player = {
                is_server = options.is_server ~= false,
                local_player_safe = function()
                    if options.no_player then return nil end
                    return { player_unit = unit }
                end,
            },
        }
        _G.ScriptUnit = {
            has_extension = function(candidate, name)
                H.equal(candidate, unit)
                if name == "health_system" then return health end
                if name == "status_system" then return status end
                error("unexpected extension " .. tostring(name))
            end,
        }
        _G.Unit = {
            alive = function(candidate)
                H.equal(candidate, unit)
                return state.unit_alive
            end,
        }
        _G.DamageUtils = {
            debug_heal = function(candidate, amount)
                H.equal(candidate, unit)
                debug_calls[#debug_calls + 1] = amount
                if options.native_error then error("native failure") end
                if options.apply_immediately ~= false then
                    state.current = state.maximum
                    state.wounded = false
                end
            end,
        }
        _G.NetworkLookup = { heal_types = { debug = 17 } }
        _G.printf = function(fmt, ...)
            prints[#prints + 1] = string.format(fmt, ...)
        end

        local ok, err = pcall(assert(loadfile(runtime_path)))
        if not ok then
            _G.get_mod = old.get_mod
            _G.Managers = old.Managers
            _G.ScriptUnit = old.ScriptUnit
            _G.Unit = old.Unit
            _G.DamageUtils = old.DamageUtils
            _G.NetworkLookup = old.NetworkLookup
            _G.printf = old.printf
            error(err, 0)
        end

        local function restore()
            _G.get_mod = old.get_mod
            _G.Managers = old.Managers
            _G.ScriptUnit = old.ScriptUnit
            _G.Unit = old.Unit
            _G.DamageUtils = old.DamageUtils
            _G.NetworkLookup = old.NetworkLookup
            _G.printf = old.printf
        end

        return {
            commands = commands,
            updates = updates,
            checks = checks,
            prints = prints,
            echoes = echoes,
            debug_calls = debug_calls,
            state = state,
            reset = mod._gt_dev_heal_reset,
            restore = restore,
        }
    end

    H.test("GT #1143 host heal uses the native maximum and confirms both postconditions", function()
        local rt = load_runtime({ is_server = true })
        rt.commands.heal()
        rt.updates.gt1143_dev_heal_postcondition(0.1)
        H.equal(#rt.debug_calls, 1)
        H.equal(rt.debug_calls[1], 100)
        H.equal(rt.state.current, 100)
        H.equal(rt.state.wounded, false)
        H.equal(#rt.prints, 1)
        H.truthy(rt.prints[1]:find("[gt:1143] heal result=ok route=host", 1, true))
        H.truthy(rt.prints[1]:find("wounded_before=true wounded_after=false", 1, true))
        H.equal(rt.checks.issue1143_dev_heal_command(), nil)
        rt.restore()
    end)

    H.test("GT #1143 client heal waits for the native RPC result before passing", function()
        local rt = load_runtime({ is_server = false, apply_immediately = false })
        rt.commands.heal()
        rt.updates.gt1143_dev_heal_postcondition(0.1)
        H.equal(#rt.prints, 0)
        rt.state.current = rt.state.maximum
        rt.state.wounded = false
        rt.updates.gt1143_dev_heal_postcondition(0.1)
        H.equal(#rt.debug_calls, 1)
        H.equal(#rt.prints, 1)
        H.truthy(rt.prints[1]:find("result=ok route=client", 1, true))
        rt.restore()
    end)

    H.test("GT #1143 confirms against the observed post-heal maximum", function()
        local rt = load_runtime({ apply_immediately = false })
        rt.commands.heal()
        rt.state.maximum = 80
        rt.state.current = 80
        rt.state.wounded = false
        rt.updates.gt1143_dev_heal_postcondition(0.1)
        H.equal(#rt.prints, 1)
        H.truthy(rt.prints[1]:find("result=ok", 1, true))
        H.truthy(rt.prints[1]:find("after=80.00 max=80.00", 1, true))
        rt.restore()
    end)

    H.test("GT #1143 refuses missing or disabled local heroes before native healing", function()
        local missing = load_runtime({ no_player = true })
        missing.commands.heal()
        H.equal(#missing.debug_calls, 0)
        H.equal(#missing.prints, 1)
        H.truthy(missing.prints[1]:find("result=error", 1, true))
        missing.restore()

        local disabled = load_runtime({ disabled = true })
        disabled.commands.heal()
        H.equal(#disabled.debug_calls, 0)
        H.truthy(disabled.prints[1]:find("local_hero_disabled_or_dead", 1, true))
        disabled.restore()
    end)

    H.test("GT #1143 fails closed when disabled state is unavailable", function()
        local cases = {
            { disabled_method_missing = true },
            { disabled_mode = "throw" },
            { disabled_mode = "nonboolean" },
        }
        for _, options in ipairs(cases) do
            local rt = load_runtime(options)
            rt.commands.heal()
            H.equal(#rt.debug_calls, 0)
            H.equal(#rt.prints, 1)
            H.truthy(rt.prints[1]:find("status_state_unavailable", 1, true))
            rt.restore()
        end
    end)

    H.test("GT #1143 fails closed when health alive state is unavailable", function()
        local cases = {
            { health_alive_method_missing = true },
            { health_alive_mode = "throw" },
            { health_alive_mode = "nonboolean" },
        }
        for _, options in ipairs(cases) do
            local rt = load_runtime(options)
            rt.commands.heal()
            H.equal(#rt.debug_calls, 0)
            H.truthy(rt.prints[1]:find("health_alive_state_unavailable", 1, true))
            rt.restore()
        end
    end)

    H.test("GT #1143 never coerces unavailable wound state to cleared", function()
        local cases = {
            { wounded_method_missing = true },
            { wounded_mode = "throw" },
            { wounded_mode = "nonboolean" },
        }
        for _, options in ipairs(cases) do
            local rt = load_runtime(options)
            rt.commands.heal()
            H.equal(#rt.debug_calls, 0)
            H.equal(#rt.prints, 1)
            H.truthy(rt.prints[1]:find("wound_state_unavailable", 1, true))
            H.truthy(rt.prints[1]:find("wounded_after=unknown", 1, true))
            rt.restore()
        end

        local post = load_runtime({ apply_immediately = false })
        post.commands.heal()
        post.state.current = post.state.maximum
        post.state.wounded_mode = "nonboolean"
        post.updates.gt1143_dev_heal_postcondition(2)
        H.truthy(post.prints[1]:find("result=timeout", 1, true))
        H.truthy(post.prints[1]:find("wounded_after=unknown", 1, true))
        H.equal(post.prints[1]:find("result=ok", 1, true), nil)
        post.restore()
    end)

    H.test("GT #1143 times out without emitting a false success receipt", function()
        local rt = load_runtime({ apply_immediately = false })
        rt.commands.heal()
        rt.updates.gt1143_dev_heal_postcondition(2)
        H.equal(#rt.prints, 1)
        H.truthy(rt.prints[1]:find("result=timeout", 1, true))
        H.equal(rt.prints[1]:find("result=ok", 1, true), nil)
        rt.restore()
    end)

    H.test("GT #1143 emits receipts beyond the old session-wide cap", function()
        local rt = load_runtime({})
        for _ = 1, 12 do
            rt.state.current = 25
            rt.state.wounded = true
            rt.commands.heal()
            rt.updates.gt1143_dev_heal_postcondition(0.1)
        end
        H.equal(#rt.prints, 12)
        H.truthy(rt.prints[12]:find("result=ok", 1, true))
        H.truthy(rt.prints[12]:find("record=12", 1, true))
        rt.restore()
    end)

    H.test("GT #1143 lifecycle reset terminates and releases a pending request", function()
        local rt = load_runtime({ apply_immediately = false })
        rt.commands.heal()
        rt.reset("game_state_changed")
        H.equal(#rt.prints, 1)
        H.truthy(rt.prints[1]:find("result=error", 1, true))
        H.truthy(rt.prints[1]:find("request_cancelled_game_state_changed", 1, true))
        rt.reset("game_state_changed")
        H.equal(#rt.prints, 1)

        rt.commands.heal()
        rt.state.current = rt.state.maximum
        rt.state.wounded = false
        rt.updates.gt1143_dev_heal_postcondition(0.1)
        H.equal(#rt.prints, 2)
        H.truthy(rt.prints[2]:find("result=ok", 1, true))
        rt.restore()
    end)

    H.test("GT #1143 central lifecycle dispatchers cancel pending confirmation", function()
        local path = repo_root
            .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/general_tweaker_dev.lua"
        local handle = assert(io.open(path, "rb"))
        local source = handle:read("*a")
        handle:close()
        H.truthy(source:find(
            'mod._gt_dev_heal_reset("game_state_changed")', 1, true))
        H.truthy(source:find(
            'mod._gt_dev_heal_reset("mod_disabled")', 1, true))
    end)

    H.test("GT #1143 runtime check fails closed when the native owner drifts", function()
        local rt = load_runtime({})
        H.equal(rt.checks.issue1143_dev_heal_command(), nil)
        _G.DamageUtils.debug_heal = nil
        H.equal(rt.checks.issue1143_dev_heal_command(),
            "DamageUtils.debug_heal unavailable")
        _G.DamageUtils.debug_heal = function() end
        _G.NetworkLookup.heal_types.debug = nil
        H.equal(rt.checks.issue1143_dev_heal_command(),
            "debug heal network lookup unavailable")
        rt.restore()
    end)
end
