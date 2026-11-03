-- Focused composition-port tests: execute the actual controller and observe its
-- factory/setting/native-write bindings. These do not simulate VMF scheduling,
-- movement, physics or the C++ engine. Owner/core behavior has separate suites.
return function(H, repo_root)
    local path = repo_root .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/"
    local Owner = assert(loadfile(path .. "_gt_time_owner.lua"))()
    local function fixture(options)
        options = options or {}
        local settings = { time_scale_value = 13, pause_hotkey = {},
            gt_time_normal_hotkey = {}, gt_world_freeze_enabled = true }
        for key, value in pairs(options.settings or {}) do settings[key] = value end
        local calls = { apply = 0, normal = 0, resync = 0, cleanup = 0,
            native = 0, paused = 0, logs = 0, settings = {}, commands = {}, checks = {} }
        local env = { GLOBAL_TIME_SCALE = 1, GLOBAL_FRAME_INDEX = 7 }
        env._G = env
        setmetatable(env, { __index = _G })
        local allowed = options.allowed ~= false
        local effective = { index = 13, paused = false, multiplier = 1 }
        local world, timer, manager = {}, {}, { time_scale_list = {} }
        for _, row in ipairs(Owner.presets()) do manager.time_scale_list[row.index] = row.percent end
        function manager:set_time_scale(index, skip_sync)
            calls.native = calls.native + 1
            calls.last_native_index, calls.last_skip_sync = index, skip_sync
        end
        function manager:set_time_paused() calls.paused = calls.paused + 1 end
        local mod = { _gt_modded_realm_authority = {}, _gt_time_hooks_armed = true }
        function mod:get(id) return settings[id] end
        function mod:set(id, value, notify)
            calls.settings[#calls.settings + 1] = { id = id, value = value, notify = notify }
            settings[id] = value
        end
        function mod:command(id, _, callback) calls.commands[id] = callback end
        function mod._gt_rt_register(id, callback) calls.checks[id] = callback end
        local owner, freeze = {}, { active = false, pending = false, enable_ok = true }
        local owner_api, freeze_api, state_reader
        function owner:apply(index)
            calls.apply = calls.apply + 1
            calls.apply_index = index
            if not allowed then return false, "host_required" end
            if options.reentrant then
                calls.nested_ok, calls.nested_reason = mod.gt_time_slower()
            end
            mod:set("time_scale_value", index, false)
            effective.index, effective.multiplier = index, Owner.multiplier(index)
            return true
        end
        function owner:normal()
            calls.normal = calls.normal + 1
            if not allowed then return false, "host_required" end
            if freeze.active or freeze.pending then
                local ok = owner_api.request_freeze_stop({}, "normal")
                if not ok then return false, "freeze_stop_incomplete" end
            end
            effective.index, effective.multiplier = 13, 1
            mod:set("time_scale_value", 13, false)
            return true
        end
        function owner:resync()
            calls.resync = calls.resync + 1
            return allowed, allowed and nil or "host_required"
        end
        function owner:release(reason) calls.release_reason = reason; return true end
        function owner:begin_freeze() calls.begin = true; return {} end
        function owner:end_freeze() calls.ended = true; return true end
        function freeze:is_active() return self.active end
        function freeze:has_pending_cleanup() return self.pending end
        function freeze:enable()
            calls.enable = (calls.enable or 0) + 1
            if not allowed then return false, "host_required" end
            if self.enable_ok then self.active = true; return true end
            return false, "ordinary_player_state_required"
        end
        function freeze:cleanup(reason)
            calls.cleanup = calls.cleanup + 1
            calls.cleanup_reason = reason
            self.active = false
            if self.pending and options.cleanup_fails then return false, "cleanup_pending" end
            self.pending = false
            return true
        end
        function freeze:outer_dt(_, _, dt) return self.active and 1e-06 or dt end
        function freeze:on_entity_phase(_, phase) calls.phase = phase; return self.active end
        local context = {
            authorize = function() return allowed end,
            authorize_cleanup = function() return allowed and "synchronized" or "local_only" end,
            read_native = function() return manager, effective end,
            world_live = function(value) return value == world end,
            game_identity = function() return timer end,
            resolve_context = function() return { world = world, humans = 1, pending_peers = 0,
                time_manager = { local_scale = function() return 0 end } } end,
        }
        mod._gt_time_modules = {
            Owner = { NORMAL_INDEX = Owner.NORMAL_INDEX, multiplier = Owner.multiplier,
                presets = Owner.presets, new = function(_, api) owner_api = api; return owner end },
            Freeze = { new = function(_, api) freeze_api = api; return freeze end },
            Driver = { new = function() error("no engine movement in composition tests") end },
            Context = { new = function(_, _, get_state) state_reader = get_state; return context end },
        }
        env.get_mod = function() return mod end
        env.printf = function() calls.logs = calls.logs + 1 end
        env.World = { get_data = function(value, key)
            H.equal(value, world); H.equal(key, "paused"); return true
        end }
        env.ScriptWorld = { pause = function(value) calls.world_pause = value end,
            unpause = function(value) calls.world_unpause = value end }
        env.Application = { set_time_step_policy = function(policy, value)
            calls.policy, calls.multiplier = policy, value
        end }
        local chunk = assert(loadfile(path .. "_gt_time_control.lua"))
        setfenv(chunk, env)
        chunk()
        return { mod = mod, calls = calls, settings = settings, owner = owner,
            freeze = freeze, context = context, owner_api = owner_api, freeze_api = freeze_api,
            manager = manager, effective = effective, env = env, world = world,
            current_state = function() return state_reader() end }
    end
    H.test("GT controller clears persisted freeze and registers exact compatibility commands", function()
        local f = fixture()
        H.equal(f.settings.gt_world_freeze_enabled, false)
        H.equal(f.mod._gt_pause_active, false)
        H.equal(f.calls.native, 0)
        H.equal(f.calls.settings[1].notify, false)
        H.equal(f.calls.commands.pause, f.mod.gt_pause_toggle)
        H.equal(f.calls.commands.freeze, f.mod.gt_pause_toggle)
        H.equal(f.calls.commands.time_normal, f.mod.gt_time_normal)
        H.equal(type(f.calls.checks.issue1801_world_freeze_owner), "function")
        H.equal(type(f.calls.checks.issue1802_native_time_controls), "function")
    end)
    H.test("GT slow time accepts either global recovery binding but refuses neither", function()
        local pause = fixture({ settings = { pause_hotkey = { "p" } } })
        pause.settings.time_scale_value = 5
        H.equal(pause.mod.gt_time_apply(), true)
        H.equal(pause.calls.apply_index, 5)
        local normal = fixture({ settings = { gt_time_normal_hotkey = { "n" } } })
        normal.settings.time_scale_value = 5
        H.equal(normal.mod.gt_time_apply(), true)
        H.equal(normal.calls.apply_index, 5)
        local none = fixture()
        none.settings.time_scale_value = 5
        H.equal(none.mod.gt_time_apply(), false)
        H.equal(none.calls.apply, 0)
        H.equal(none.settings.time_scale_value, 13)
        none.settings.time_scale_value = 14
        H.equal(none.mod.gt_time_apply(), true)
    end)
    H.test("GT startup rejects an unbound saved slow target without advertising it as applied", function()
        local f = fixture({ settings = { time_scale_value = 1 } })
        f.mod._gt_time_on_state("enter", "StateIngame")
        f.mod._gt_time_outer_dt({}, "pre_update", 0.02)
        H.equal(f.settings.time_scale_value, 13)
        H.equal(f.effective.index, 13)
        H.equal(f.calls.apply, 0)
        H.equal(f.calls.native, 0)
    end)
    H.test("GT lone Freeze recovery key restores normal speed for an unsupported player state", function()
        local f = fixture({ settings = { pause_hotkey = { "p" } } })
        f.settings.time_scale_value = 5
        H.equal(f.mod.gt_time_apply(), true)
        f.freeze.enable_ok = false
        H.equal(f.mod.gt_pause_toggle(), true)
        H.equal(f.calls.normal, 1)
        H.equal(f.settings.time_scale_value, 13)
        H.equal(f.effective.index, 13)
        H.equal(f.settings.gt_world_freeze_enabled, false)
        H.equal(f.calls.apply, 1)
    end)
    H.test("GT Freeze fallback cannot override client authorization or pending cleanup", function()
        local client = fixture({ allowed = false, settings = { pause_hotkey = { "p" } } })
        client.effective.index = 5
        H.equal(client.mod.gt_pause_toggle(), false)
        H.equal(client.calls.normal, 1)
        H.equal(client.effective.index, 5)
        H.equal(client.calls.native, 0)
        local pending = fixture({ cleanup_fails = true, settings = { pause_hotkey = { "p" } } })
        pending.freeze.active, pending.freeze.pending = true, true
        H.equal(pending.mod.gt_pause_toggle(), false)
        H.equal(pending.calls.cleanup_reason, "toggle")
        H.equal(pending.calls.normal, 0)
        H.equal(pending.freeze.pending, true)
    end)
    H.test("GT installed phase dispatch retries pending cleanup and captures exact state", function()
        local f = fixture()
        f.freeze.pending = true
        local state = {}
        H.equal(f.mod._gt_time_outer_dt(state, "pre_update", 0.02), 0.02)
        H.equal(f.current_state(), state)
        H.equal(f.calls.cleanup, 1)
        H.equal(f.calls.cleanup_reason, "cleanup_retry")
        H.equal(f.freeze.pending, false)
        H.equal(f.mod._gt_time_entity_phase({}, "post_update", 0.02), false)
        H.equal(f.calls.phase, "post_update")
    end)
    H.test("GT hotjoin dispatch restores Freeze before admission and forces only owned resync afterward", function()
        local f = fixture()
        f.freeze.active = true
        H.equal(f.mod._gt_time_before_hotjoin(), true)
        H.equal(f.calls.cleanup_reason, "peer_arrival")
        H.equal(f.freeze.active, false)
        H.equal(f.mod._gt_time_after_hotjoin(), true)
        H.equal(f.calls.resync, 1)
        H.equal(f.calls.apply, 0)
        f.freeze.pending = true
        H.equal(f.mod._gt_time_after_hotjoin(), false)
        H.equal(f.calls.resync, 1)
    end)
    H.test("GT native cleanup bindings never broadcast through the local-only lane", function()
        local f = fixture()
        f.owner_api.write_native_local(f.manager, 7)
        H.equal(f.calls.native, 1)
        H.equal(f.calls.last_native_index, 7)
        H.equal(f.calls.last_skip_sync, true)
        f.owner_api.write_paused_local(f.manager)
        H.equal(f.calls.policy, "external_multiplier")
        H.equal(f.calls.multiplier, 1e-08)
        H.equal(f.env.GLOBAL_TIME_SCALE, 1e-08)
        H.equal(f.manager.time_paused, true)
        H.equal(f.calls.paused, 0)
        f.owner_api.write_native(f.manager, 9)
        H.equal(f.calls.last_skip_sync, nil)
    end)
    H.test("GT controller blocks synchronous setting reentry and malformed step values", function()
        local f = fixture({ reentrant = true })
        H.equal(f.mod.gt_time_apply(), true)
        H.equal(f.calls.nested_ok, false)
        H.equal(f.calls.nested_reason, "reentrant_control")
        H.equal(f.calls.apply, 1)
        f.settings.time_scale_value = "broken"
        H.equal(f.mod.gt_time_faster(), false)
        H.equal(f.mod.gt_time_slower(), false)
        H.equal(f.mod._gt_time_on_setting("pause_hotkey"), true)
        H.equal(f.mod._gt_time_on_setting("gt_time_normal_hotkey"), true)
        H.equal(f.calls.apply, 1)
    end)
    H.test("GT key removal and lifecycle dispatch release only through the owned controller", function()
        local f = fixture()
        f.freeze.active = true
        H.equal(f.mod._gt_time_on_setting("pause_hotkey"), true)
        H.equal(f.freeze.active, false)
        H.equal(f.calls.cleanup_reason, "recovery_key_removed")
        f.mod._gt_time_on_state("exit", "StateIngame")
        H.equal(f.calls.release_reason, "state_exit")
        H.equal(f.current_state(), nil)
        H.equal(f.mod._gt_time_on_setting("unrelated_setting"), false)
    end)
end
