-- Execute the complete freecam owner with detached engine/VMF collaborators.
-- #1796 baseline reproduction: idle OFF and repeated release erased true/false;
-- a missing manager entered twice and left native data active. These are host
-- state/ordering checks, not gameplay, camera rendering or input-device proof.
return function(H, repo_root)
    for _, stream in ipairs({
        { dir = "gui_tweaker", id = "gut" },
        { dir = "gui_tweaker_dev", id = "gut_dev" },
    }) do
    local base = H
    local H = setmetatable({
        test = function(name, callback) base.test(stream.id .. ": " .. name, callback) end,
    }, { __index = base })
    local path = repo_root .. "/" .. stream.dir .. "/scripts/mods/" .. stream.dir .. "/_gut_freecam.lua"
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()

    local function fixture(options)
        options = options or {}
        local h = {
            settings = { gut_freecam_enabled = false },
            hooks = {}, safe_hooks = {}, commands = {}, trace = {}, logs = {},
            enters = 0, exits = 0, clears = 0, created = 0, destroyed = 0,
            blocks = 0, unblocks = 0, world_reads = 0,
            prev_updates = 0, prev_settings = 0, prev_states = 0,
            live_world = true, viewport = false, key_down = false,
            player_available = true,
        }
        local env = setmetatable({}, { __index = _G })
        env._G = env
        h.env = env
        h.player = {
            player_unit = {}, viewport_world_name = "level_world", viewport_name = "player_1",
            local_player_id = function() return 1 end,
        }
        h.data = { active = false }
        local mod = {}
        h.mod = mod
        function mod:get(key) return h.settings[key] end
        function mod:set(key, value)
            local changed = h.settings[key] ~= value
            h.settings[key] = value
            if options.callback and changed then self.on_setting_changed(key) end
        end
        function mod:echo(...) end
        function mod:hook(class, method, callback)
            local key = class .. "." .. method
            assert(not h.hooks[key], "duplicate hook: " .. key)
            h.hooks[key] = callback
        end
        function mod:hook_safe(class, method, callback)
            local key = class .. "." .. method
            assert(not h.safe_hooks[key], "duplicate safe hook: " .. key)
            h.safe_hooks[key] = callback
        end
        function mod:command(name, description, callback) h.commands[name] = callback end
        mod.update = function(dt)
            h.prev_updates = h.prev_updates + 1
            h.trace[#h.trace + 1] = "previous-update"
            H.equal(dt, 0)
        end
        mod.on_setting_changed = function()
            h.prev_settings = h.prev_settings + 1
            h.trace[#h.trace + 1] = "previous-setting"
        end
        mod.on_game_state_changed = function(status, state)
            h.prev_states = h.prev_states + 1
            h.trace[#h.trace + 1] = "previous-state"
            H.equal(status, "exit")
            H.equal(state, "StateIngame")
        end
        env.get_mod = function(id) H.equal(id, stream.id); return mod end
        env.printf = function(format, ...)
            h.logs[#h.logs + 1] = string.format(format, ...)
        end
        env.Development = { _hardcoded_dev_params = { third_person_mode = options.previous } }
        env.Keyboard = {
            button_index = function() return 1 end,
            button = function() return h.key_down and 1 or 0 end,
        }
        env.ScriptWorld = {
            has_viewport = function() return h.viewport end,
            free_flight_viewport = function() assert(h.viewport); return {} end,
        }
        local input = {
            block_device_except_service = function(self, service, device)
                H.equal(service, "FreeFlight")
                H.truthy(device == "keyboard" or device == "mouse" or device == "gamepad")
                h.blocks = h.blocks + 1
            end,
            device_unblock_all_services = function(self, device)
                H.truthy(device == "keyboard" or device == "mouse" or device == "gamepad")
                h.unblocks = h.unblocks + 1
            end,
        }
        local ff = { data = { [1] = h.data }, input_manager = input }
        h.ff = ff
        if options.missing_input then ff.input_manager = nil end
        function ff:register_input_manager() error("must not repair another mod's manager") end
        function ff:_enter_free_flight(player, data)
            h.enters = h.enters + 1
            h.trace[#h.trace + 1] = "native-enter"
            H.equal(player, h.player)
            env.Managers.world:world(player.viewport_world_name)
            data.active = true
            data.viewport_world_name, data.viewport_name = player.viewport_world_name, player.viewport_name
            h.viewport, h.created = true, h.created + 1
            -- Native sets active and creates viewport/observers before input use.
            if options.enter_error then error("entry failed after viewport creation") end
            self.input_manager:block_device_except_service("FreeFlight", "keyboard")
            self.input_manager:block_device_except_service("FreeFlight", "mouse")
            self.input_manager:block_device_except_service("FreeFlight", "gamepad")
        end
        function ff:_exit_free_flight(player, data)
            h.exits = h.exits + 1
            h.trace[#h.trace + 1] = "native-exit"
            env.Managers.world:world(data.viewport_world_name)
            data.active, data.viewport_world_name, data.viewport_name = false, nil, nil
            h.viewport, h.destroyed = false, h.destroyed + 1
            if options.exit_error then error("exit failed after viewport destruction") end
            self.input_manager:device_unblock_all_services("keyboard")
            self.input_manager:device_unblock_all_services("mouse")
            self.input_manager:device_unblock_all_services("gamepad")
            h.safe_hooks["FreeFlightManager._exit_free_flight"](self, player, data)
        end
        function ff:_clear_free_flight(data)
            h.clears = h.clears + 1
            h.trace[#h.trace + 1] = "native-clear"
            data.active, data.viewport_world_name, data.viewport_name = false, nil, nil
        end
        env.Managers = {
            free_flight = ff,
            player = { local_player = function() return h.player_available and h.player or nil end },
            world = {
                has_world = function(self, name) return h.live_world and name == "level_world" end,
                world = function(self, name)
                    assert(h.live_world and name == "level_world", "ungated dead-world lookup")
                    h.world_reads = h.world_reads + 1
                    return {}
                end,
            },
            ui = {},
            input = setmetatable({}, { __index = function() error("must not replace free-flight input") end }),
        }
        local chunk = assert(loadstring(options.source or source, "@" .. path))
        setfenv(chunk, env)()
        function h:toggle() self.mod.gut_freecam_toggle() end
        function h:checkbox(value)
            self.settings.gut_freecam_enabled = value
            self.mod.on_setting_changed("gut_freecam_enabled")
        end
        function h:third_person() return self.env.Development._hardcoded_dev_params.third_person_mode end
        function h:blocked(player)
            return self.hooks["PlayerInputExtension.is_input_blocked"](
                function() return "vanilla" end, { player = player or self.player })
        end
        return h
    end

    local baselines = { { name = "nil" }, { name = "false", value = false }, { name = "true", value = true } }
    local scenarios = {
        { "idle OFF", function(h) h.mod._gut_apply_freecam(false) end, 0, 0 },
        { "checkbox exit", function(h) h:checkbox(true); h:checkbox(false) end, 1, 1 },
        { "toggle exit", function(h) h:toggle(); h:toggle() end, 1, 1 },
        { "external engine exit", function(h) h:toggle(); h.ff:_exit_free_flight(h.player, h.data) end, 1, 1 },
        { "lost player data", function(h) h:toggle(); h.ff.data[1] = nil; h.mod.update(0) end, 1, 0 },
        { "state transition", function(h) h:toggle(); h.mod.on_game_state_changed("exit", "StateIngame") end, 1, 1 },
        { "missing input", function(h) h:toggle() end, 0, 0, missing_input = true },
        { "pending menu cancel", function(h)
            h.env.Managers.ui._ingame_ui = { menu_active = true }
            h:toggle(); h:toggle()
        end, 0, 0 },
        { "unavailable level", function(h) h.player_available = false; h:toggle() end, 0, 0 },
        { "F8 exit", function(h)
            h:toggle()
            -- The activating key is swallowed; release it before the rising edge.
            h.live_world = false
            h.mod.update(0)
            h.live_world, h.key_down = true, true
            h.mod.update(0)
        end, 1, 1 },
    }
    for _, baseline in ipairs(baselines) do
        for _, callback in ipairs({ false, true }) do
            for _, scenario in ipairs(scenarios) do
                local previous, sync, case = baseline.value, callback, scenario
                H.test("GUT freecam " .. case[1] .. " restores " .. baseline.name .. " callback=" .. tostring(sync), function()
                    local h = fixture({ previous = previous, callback = sync, missing_input = case.missing_input })
                    case[2](h)
                    H.equal(h:third_person(), previous)
                    H.equal(h:blocked(), "vanilla", "local input ownership must be released")
                    H.equal(h.settings.gut_freecam_enabled, false)
                    H.equal(h.enters, case[3])
                    H.equal(h.exits, case[4])
                    -- Repeated fallback/setting releases must never rewrite an unowned flag.
                    h.env.Development._hardcoded_dev_params.third_person_mode = "later-owner"
                    h.mod._gut_apply_freecam(false)
                    h:checkbox(false)
                    H.equal(h:third_person(), "later-owner")
                    H.equal(h.exits, case[4])
                end)
            end
        end
    end

    for _, callback in ipairs({ false, true }) do
        local sync = callback
        H.test("GUT freecam partial entry rolls back once callback=" .. tostring(sync), function()
            local h = fixture({ previous = true, callback = sync, enter_error = true })
            h:toggle()
            H.equal(h.enters, 1, "toggle fallback must not retry a denied entry")
            H.equal(h.exits, 1)
            H.equal(h.created, 1)
            H.equal(h.destroyed, 1)
            H.equal(h.data.active, false)
            H.equal(h.viewport, false)
            H.equal(h.settings.gut_freecam_enabled, false)
            H.equal(h:third_person(), true)
            H.equal(h:blocked(), "vanilla")
        end)
        H.test("GUT freecam throwing rollback restores once callback=" .. tostring(sync), function()
            local h = fixture({ previous = false, callback = sync, enter_error = true, exit_error = true })
            h:toggle()
            H.equal(h.enters, 1)
            H.equal(h.exits, 1)
            H.equal(h.data.active, false)
            H.equal(h:third_person(), false)
            H.equal(h:blocked(), "vanilla")
            H.equal(h.settings.gut_freecam_enabled, false)
            h.env.Development._hardcoded_dev_params.third_person_mode = "later-owner"
            h.mod._gut_apply_freecam(false)
            H.equal(h:third_person(), "later-owner")
            H.equal(h.exits, 1)
        end)
    end

    H.test("GUT freecam idle OFF does not tear down foreign Flight", function()
        local h = fixture({ previous = true, callback = true })
        h.data.active, h.viewport = true, true
        h.data.viewport_world_name, h.data.viewport_name = "level_world", "player_1"
        h.mod._gut_apply_freecam(false)
        h:checkbox(false)
        H.equal(h.data.active, true)
        H.equal(h.viewport, true)
        H.equal(h.enters, 0)
        H.equal(h.exits, 0)
        H.equal(h.clears, 0)
        H.equal(h:third_person(), true)
    end)

    H.test("GUT freecam remote exit cannot consume the local snapshot", function()
        local h = fixture({ previous = false, callback = true })
        h:toggle()
        h.safe_hooks["FreeFlightManager._exit_free_flight"](h.ff, {}, { active = false })
        H.equal(h:third_person(), true)
        H.equal(h:blocked(), true)
        H.equal(h.settings.gut_freecam_enabled, true)
        H.equal(h.data.active, true)
        h:toggle()
        H.equal(h:third_person(), false)
        H.equal(h.exits, 1)
    end)

    H.test("GUT freecam input is local-only and retains HUD suspension", function()
        local h = fixture({ callback = true })
        H.equal(h:blocked(), "vanilla")
        h.mod._gut_hud_customizer = { should_suspend_input = function() return true end }
        H.equal(h:blocked(), true)
        H.equal(h:blocked({}), "vanilla")
        h.mod._gut_hud_customizer.should_suspend_input = function() return false end
        h:toggle()
        H.equal(h:blocked(), true)
        H.equal(h:blocked({}), "vanilla")
        H.equal(h.blocks, 3)
        H.equal(h.unblocks, 3, "entry must immediately return all devices")
        h:toggle()
        H.equal(h:blocked(), "vanilla")
        H.equal(h.unblocks, 6)
    end)

    H.test("GUT freecam dead-world exit clears without an ungated native exit", function()
        local h = fixture({ previous = true, callback = true })
        h:toggle()
        local reads = h.world_reads
        h.live_world = false
        h:toggle()
        H.equal(h.world_reads, reads)
        H.equal(h.exits, 0)
        H.equal(h.clears, 1)
        H.equal(h.data.active, false)
        H.equal(h:third_person(), true)
        H.equal(h:blocked(), "vanilla")
        H.equal(h.mod._gut_fc_live_world("level_world"), nil)
    end)

    H.test("GUT freecam missing manager can retry after engine registration", function()
        local h = fixture({ previous = true, callback = true, missing_input = true })
        h:toggle()
        H.equal(h.enters, 0)
        H.equal(h.created, 0)
        H.equal(h.data.active, false)
        H.equal(h.ff.input_manager, nil, "denial must not repair the manager")
        h.ff.input_manager = {
            block_device_except_service = function() end,
            device_unblock_all_services = function() end,
        }
        h:toggle()
        H.equal(h.enters, 1)
        H.equal(h:blocked(), true)
        h:toggle()
        H.equal(h:third_person(), true)
    end)

    H.test("GUT freecam preserves callback chains, menu deferral and singleton hooks", function()
        local h = fixture({ previous = true, callback = true })
        h.env.Managers.ui._ingame_ui = { current_view = "vmf_options_view" }
        h:toggle()
        H.equal(h.enters, 0)
        H.equal(h:blocked(), "vanilla")
        H.equal(h:third_person(), true)
        h.mod.update(0)
        H.equal(h.enters, 0)
        h.env.Managers.ui._ingame_ui = nil
        -- Avoid raw camera math: the deferred entry has no base viewport this frame.
        h.env.ScriptWorld.has_viewport = function() return false end
        h.mod.update(0)
        H.equal(h.enters, 1)
        H.equal(h.prev_updates, 2)
        H.equal(h.trace[1], "previous-setting")
        H.equal(h.trace[2], "previous-update")
        H.equal(h.trace[3], "previous-update")
        H.equal(h.trace[4], "native-enter")
        h.mod.on_game_state_changed("exit", "StateIngame")
        H.equal(h.prev_states, 1)
        H.truthy(h.prev_settings >= 2)
        H.equal(h.trace[5], "previous-state")
        local hook_count, safe_count = 0, 0
        for _ in pairs(h.hooks) do hook_count = hook_count + 1 end
        for _ in pairs(h.safe_hooks) do safe_count = safe_count + 1 end
        H.equal(hook_count, 1)
        H.equal(safe_count, 1)
        H.truthy(h.commands.freecam)
    end)

    H.test("GUT freecam regression oracle detects an unowned restore", function()
        local mutant, count = source:gsub("if not _owns_third_person then return end", "-- planted missing ownership guard", 1)
        H.equal(count, 1)
        local h = fixture({ previous = true, callback = true, source = mutant })
        h.mod._gut_apply_freecam(false)
        H.equal(h:third_person(), nil, "negative control must recreate idle-OFF state loss")
    end)
    end
end
