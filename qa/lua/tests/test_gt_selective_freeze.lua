-- Engine-free selective-freeze core/driver tests against the active DEV source.
-- Runtime collision, world stepping and visual behavior still require game acceptance.
return function(H, repo_root)
    local production = repo_root .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/"
    local Core = dofile(production .. "_gt_selective_freeze.lua")
    local NativeMovement = dofile(repo_root .. "/qa/lua/fixtures/gt_native_player_movement.lua")
    local EPS = 1e-06

    local function eq(actual, expected, label)
        assert(actual == expected, (label or "equality") .. ": expected "
            .. tostring(expected) .. ", got " .. tostring(actual))
    end
    local function near(actual, expected, label)
        assert(type(actual) == "number" and math.abs(actual - expected) < 1e-09,
            (label or "near") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual))
    end
    local function fixture()
        local f = { frame = 1, wall = 10, paused = false, scale = 0.75,
            reads = 0, writes = 0, wall_reads = 0, timer_reads = 0,
            timer_writes = 0, begins = 0, ends = 0, reports = 0,
            updates = 0, posts = 0, clears = 0, stale_calls = 0, ended_leases = {} }
        local world, tm, timer, unit, player, entity, state = {}, {}, {}, {}, {}, {}, {}
        f.live_world, f.live_tm, f.live_timer = world, tm, timer
        f.ctx = { modded = true, host = true, humans = 1,
            world = world, time_manager = tm, game_timer = timer,
            unit = unit, player = player, entity = entity, state_object = state,
            state = "StateIngame", csm_state = "standing", loco_state = "script_driven",
            camera_state = "follow", alive = true, disabled = false,
            gamepad = false, motion_controls = false,
            game_t = 100, driver_context = {} }
        local api = {}
        f.api = api
        api.resolve_context = function() return f.ctx end
        api.world_live = function(w) return w == f.live_world end
        local function require_world(w)
            if w ~= f.live_world then f.stale_calls = f.stale_calls + 1; error("stale world") end
        end
        local function require_tm(t)
            if t ~= f.live_tm then f.stale_calls = f.stale_calls + 1; error("stale timer manager") end
        end
        api.world_paused = function(w)
            require_world(w); f.reads = f.reads + 1
            if f.restore_readfail_world then error("world restoration read failed") end
            if f.restore_postreadfail_world and f.world_restore_written then
                error("world restoration post-read failed")
            end
            return f.paused
        end
        api.set_world_paused = function(w, value)
            require_world(w); f.writes = f.writes + 1
            if value == false and f.restore_only_noop_world then return end
            if value == false and f.restore_only_false_world then return false, "world restore refused" end
            if f.fail_world_before then f.fail_world_before = false; error("world before mutation") end
            f.paused = value
            if value == false then f.world_restore_written = true end
            if f.fail_world_after then f.fail_world_after = false; error("world after mutation") end
        end
        api.game_identity = function(t)
            require_tm(t); return f.live_timer
        end
        api.local_scale = function(t)
            require_tm(t); f.timer_reads = f.timer_reads + 1
            if f.restore_readfail_timer then error("timer restoration read failed") end
            if f.restore_postreadfail_timer and f.timer_restore_written then
                error("timer restoration post-read failed")
            end
            return f.scale
        end
        api.set_local_scale = function(t, value)
            require_tm(t); f.timer_writes = f.timer_writes + 1
            if value ~= 0 and f.restore_only_noop_timer then return end
            if value ~= 0 and f.restore_only_false_timer then return false, "timer restore refused" end
            if f.fail_timer_before then f.fail_timer_before = false; error("timer before mutation") end
            f.scale = value
            if value ~= 0 then f.timer_restore_written = true end
            if f.fail_timer_after then f.fail_timer_after = false; error("timer after mutation") end
        end
        api.wall_time = function() f.wall_reads = f.wall_reads + 1; return f.wall end
        api.frame_id = function() return f.frame end
        api.game_time = function(t) require_tm(t); return 100 end
        api.report = function() f.reports = f.reports + 1 end
        api.driver_factory = function(ctx)
            assert(ctx == f.ctx, "driver receives validated context")
            if f.fail_factory then error("driver factory failed") end
            return {
                update = function(_, current, dt, t)
                    eq(current, f.ctx, "driver update context")
                    f.updates = f.updates + 1; f.last_dt, f.last_t = dt, t
                    if f.fail_update then error("driver update failed") end
                end,
                post = function(_, current, dt, t)
                    eq(current, f.ctx, "driver post context")
                    f.posts = f.posts + 1; f.post_dt, f.post_t = dt, t
                    if f.fail_post then error("driver post failed") end
                end,
                clear = function() f.clears = f.clears + 1 end,
            }
        end
        local time_owner = {
            begin_freeze = function()
                f.begins = f.begins + 1
                if f.fail_begin then error("begin failed") end
                f.lease = {}; return f.lease
            end,
            end_freeze = function(lease)
                eq(lease, f.lease, "exact lease restoration")
                f.ends = f.ends + 1
                f.ended_leases[#f.ended_leases + 1] = lease
                if f.fail_end then error("end failed") end
                if f.false_end then return false, "simulated" end
                return true
            end,
        }
        f.owner = Core.new({}, api, time_owner)
        function f:pre(dt)
            return self.owner:outer_dt(self.ctx.state_object, "pre_update", dt or 0.016)
        end
        function f:step(dt)
            self.frame = self.frame + 1; self.wall = self.wall + (dt or 0.016)
            self:pre(dt)
            self.owner:on_entity_phase(self.ctx.entity, "update", dt or 0.016)
            self.owner:on_entity_phase(self.ctx.entity, "post_update", dt or 0.016)
        end
        return f
    end

    local sibling_source = repo_root .. "/../Vermintide-2-Source-Code/scripts/settings/player_movement_settings.lua"
    local native_file = io.open(sibling_source, "rb")
    local has_native_source = native_file ~= nil
    if native_file then native_file:close() end
    H.test_if(has_native_source, "gt selective freeze: retained defaults match native source", function()
        H.equal(NativeMovement.verify_optional_source(sibling_source), true)
    end, "sibling native source unavailable")


    H.test("gt selective freeze: valid enable obtains lease and owns both controls", function()
        local f = fixture(); eq(f.owner:enable(), true)
        eq(f.owner:is_active(), true); eq(f.begins, 1)
        eq(f.paused, true); eq(f.scale, 0)
        eq(f.owner:enable(), true); eq(f.begins, 1, "idempotent enable")
    end)

    H.test("gt selective freeze: disable restores snapshots and releases lease exactly once", function()
        local f = fixture(); assert(f.owner:enable())
        eq(f.owner:disable("test"), true); eq(f.owner:is_active(), false)
        eq(f.paused, false); near(f.scale, 0.75); eq(f.ends, 1)
        eq(f.owner:disable("again"), false); eq(f.ends, 1)
    end)

    H.test("gt selective freeze: cleanup predicate is exact for idle and active ownership", function()
        local f = fixture()
        eq(f.owner:has_pending_cleanup(), false)
        eq(f.owner:cleanup("idle"), true); eq(f.begins, 0); eq(f.ends, 0)
        assert(f.owner:enable()); eq(f.owner:has_pending_cleanup(), false)
        eq(f.owner:cleanup("active"), true)
        eq(f.owner:is_active(), false); eq(f.owner:has_pending_cleanup(), false)
        eq(f.paused, false); near(f.scale, 0.75); eq(f.ends, 1)
    end)

    for _, injection in ipairs({ "restore_postreadfail_world", "restore_postreadfail_timer" }) do
        H.test("gt selective freeze: cleanup retries " .. injection .. " until observed", function()
            local f = fixture(); assert(f.owner:enable()); f[injection] = true
            local lease = f.lease
            local clean, reason = f.owner:cleanup("unconfirmed local restoration")
            eq(clean, false); eq(reason, "cleanup_pending")
            eq(f.owner:is_active(), false); eq(f.owner:has_pending_cleanup(), true)
            eq(f.ends, 0, "lease held until local post-read succeeds")
            f[injection] = false
            eq(f.owner:cleanup("retry local restoration"), true)
            eq(f.owner:has_pending_cleanup(), false); eq(f.owner:is_active(), false)
            eq(f.paused, false); near(f.scale, 0.75)
            eq(f.ends, 1); eq(f.ended_leases[1], lease); eq(f.stale_calls, 0)
        end)
    end

    for _, denial in ipairs({
        { "official realm", "modded", false }, { "client", "host", false },
        { "additional human", "humans", 2 }, { "dead", "alive", false },
        { "disabled", "disabled", true }, { "ladder", "loco_state", "script_driven_ladder" },
        { "jumping", "csm_state", "jumping" }, { "observer", "camera_state", "observer" },
        { "gamepad", "gamepad", true }, { "unknown input device", "gamepad", nil },
        { "motion controls", "motion_controls", true },
        { "unknown motion controls", "motion_controls", nil },
        { "wrong state", "state", "StateLoading" },
    }) do
        H.test("gt selective freeze: reject " .. denial[1] .. " before mutation", function()
            local f = fixture(); f.ctx[denial[2]] = denial[3]
            eq(f.owner:enable(), false); eq(f.owner:is_active(), false)
            eq(f.begins, 0); eq(f.writes, 0); eq(f.timer_writes, 0)
        end)
    end

    H.test("gt selective freeze: prepaused world is not adopted", function()
        local f = fixture(); f.paused = true
        eq(f.owner:enable(), false); eq(f.begins, 0); eq(f.paused, true)
    end)

    H.test("gt selective freeze: missing context fails closed", function()
        local f = fixture(); f.ctx = nil
        eq(f.owner:enable(), false); eq(f.begins, 0)
    end)

    for _, injection in ipairs({ "fail_timer_before", "fail_timer_after",
        "fail_world_before", "fail_world_after", "fail_factory" }) do
        H.test("gt selective freeze: rollback " .. injection, function()
            local f = fixture(); f[injection] = true
            eq(f.owner:enable(), false); eq(f.owner:is_active(), false)
            eq(f.paused, false); near(f.scale, 0.75)
            eq(f.ends, f.begins, "every obtained lease is released")
        end)
    end

    H.test("gt selective freeze: begin failure is contained without controls mutation", function()
        local f = fixture(); f.fail_begin = true
        eq(f.owner:enable(), false); eq(f.paused, false); near(f.scale, 0.75)
        eq(f.ends, 0)
    end)

    H.test("gt selective freeze: other owner changes are not overwritten", function()
        local f = fixture(); assert(f.owner:enable())
        f.scale, f.paused = 0.25, false
        local writes, timer_writes = f.writes, f.timer_writes
        f.owner:disable("external change")
        near(f.scale, 0.25); eq(f.paused, false)
        eq(f.writes, writes); eq(f.timer_writes, timer_writes); eq(f.ends, 1)
    end)

    H.test("gt selective freeze: replacement world is never touched through old handle", function()
        local f = fixture(); assert(f.owner:enable())
        f.live_world = {}; f.ctx.world = f.live_world
        f:pre(); eq(f.owner:is_active(), false); eq(f.stale_calls, 0); eq(f.ends, 1)
    end)

    H.test("gt selective freeze: replacement time manager is never called through old handle", function()
        local f = fixture(); assert(f.owner:enable())
        f.live_tm = {}; f.ctx.time_manager = f.live_tm
        f:pre(); eq(f.owner:is_active(), false); eq(f.stale_calls, 0); eq(f.ends, 1)
    end)

    H.test("gt selective freeze: replacement private game timer prevents restoring old scale", function()
        local f = fixture(); assert(f.owner:enable())
        f.live_timer = {}; f.ctx.game_timer = f.live_timer
        local timer_writes = f.timer_writes
        f:pre(); eq(f.owner:is_active(), false)
        eq(f.timer_writes, timer_writes); eq(f.stale_calls, 0)
    end)

    H.test("gt selective freeze: peer arrival releases before another frozen phase", function()
        local f = fixture(); assert(f.owner:enable()); f.ctx.humans = 2
        near(f:pre(0.02), 0.02); eq(f.owner:is_active(), false)
        eq(f.paused, false); near(f.scale, 0.75); eq(f.updates, 0)
    end)

    H.test("gt selective freeze: all exact StateIngame phases receive positive epsilon", function()
        local f = fixture(); assert(f.owner:enable())
        for _, phase in ipairs({ "pre_update", "update", "post_update" }) do
            near(f.owner:outer_dt(f.ctx.state_object, phase, 0.02), EPS)
        end
        near(f.owner:outer_dt({}, "update", 0.02), 0.02)
    end)

    H.test("gt selective freeze: wall sampling and body camera dispatch are once per frame", function()
        local f = fixture(); assert(f.owner:enable())
        f:pre(); local reads = f.wall_reads; f:pre(); eq(f.wall_reads, reads)
        f.owner:on_entity_phase(f.ctx.entity, "update", 0.016)
        f.owner:on_entity_phase(f.ctx.entity, "update", 0.016)
        f.owner:on_entity_phase(f.ctx.entity, "post_update", 0.016)
        f.owner:on_entity_phase(f.ctx.entity, "post_update", 0.016)
        eq(f.updates, 1); eq(f.posts, 1); near(f.last_dt, EPS)
        f:step(0.02); eq(f.updates, 2); near(f.last_dt, 0.02); near(f.last_t, 100)
        near(f.post_dt, f.last_dt); near(f.post_t, 100)
    end)

    H.test("gt selective freeze: long wall interval is clamped without synthetic game time", function()
        local f = fixture(); assert(f.owner:enable()); f:pre(); f:step(12)
        near(f.last_dt, 0.05); near(f.last_t, 100)
    end)

    H.test("gt selective freeze: foreign entity cannot drive local exception", function()
        local f = fixture(); assert(f.owner:enable()); f:pre()
        f.owner:on_entity_phase({}, "update", 0.02)
        f.owner:on_entity_phase({}, "post_update", 0.02)
        eq(f.updates, 0); eq(f.posts, 0)
    end)

    H.test("gt selective freeze: post phase does not run before body update", function()
        local f = fixture(); assert(f.owner:enable()); f:pre()
        f.owner:on_entity_phase(f.ctx.entity, "post_update", 0.02)
        eq(f.posts, 0)
    end)

    for _, injection in ipairs({ "fail_update", "fail_post" }) do
        H.test("gt selective freeze: driver " .. injection .. " unwinds owned state", function()
            local f = fixture(); assert(f.owner:enable()); f[injection] = true
            f:pre(); f.owner:on_entity_phase(f.ctx.entity, "update", 0.02)
            if injection == "fail_post" then
                f.owner:on_entity_phase(f.ctx.entity, "post_update", 0.02)
            end
            eq(f.owner:is_active(), false); eq(f.paused, false); near(f.scale, 0.75)
            eq(f.ends, 1); assert(f.reports > 0, "failure should be reported")
        end)
    end

    H.test("gt selective freeze: StateIngame exit restores without next update", function()
        local f = fixture(); assert(f.owner:enable())
        f.owner:on_state("exit", "StateIngame")
        eq(f.owner:is_active(), false); eq(f.paused, false); near(f.scale, 0.75)
    end)

    H.test("gt selective freeze: entering another game state releases", function()
        local f = fixture(); assert(f.owner:enable())
        f.owner:on_state("enter", "StateLoading")
        eq(f.owner:is_active(), false); eq(f.ends, 1)
    end)

    H.test("gt selective freeze: lease restoration errors do not leave local state armed", function()
        local f = fixture(); assert(f.owner:enable()); f.fail_end = true
        f.owner:disable("test")
        eq(f.owner:is_active(), false); eq(f.paused, false); near(f.scale, 0.75)
        assert(f.reports > 0, "end failure should be reported")
    end)

    for _, injection in ipairs({ "fail_end", "false_end" }) do
        H.test("gt selective freeze: pending " .. injection .. " blocks new freeze and retries exact lease", function()
            local f = fixture(); assert(f.owner:enable()); f[injection] = true
            local lease = f.lease
            f.owner:disable("test pending cleanup")
            eq(f.owner:is_active(), false); eq(f.paused, false); near(f.scale, 0.75)
            assert(f.owner._pending_restore ~= nil, "failed lease cleanup must remain pending")
            local enabled, reason = f.owner:enable()
            eq(enabled, false); eq(reason, "cleanup_pending"); eq(f.begins, 1)
            eq(f.ends, 1); eq(f.ended_leases[1], lease)
            f[injection] = false
            eq(f.owner:disable("retry pending cleanup"), true)
            eq(f.owner._pending_restore, nil); eq(f.ends, 2)
            eq(f.ended_leases[2], lease, "retry keeps original unique lease")
            eq(f.owner:enable(), true); eq(f.begins, 2)
            assert(f.lease ~= lease, "new freeze obtains a new lease only after cleanup")
            f.owner:disable("finish test")
        end)
    end

    for _, injection in ipairs({ "restore_only_noop_world", "restore_only_false_world",
        "restore_only_noop_timer", "restore_only_false_timer",
        "restore_readfail_world", "restore_readfail_timer",
        "restore_postreadfail_world", "restore_postreadfail_timer",
        "fail_world_before", "fail_timer_before", "fail_world_after", "fail_timer_after" }) do
        H.test("gt selective freeze: local restoration " .. injection .. " retains lease until observed restore", function()
            local f = fixture(); assert(f.owner:enable()); f[injection] = true
            local lease = f.lease
            f.owner:disable("local cleanup test")
            eq(f.owner:is_active(), false)
            assert(f.owner._pending_restore ~= nil, "unobserved local restore stays pending")
            eq(f.ends, 0, "time lease must remain while local controls are not restored")
            local enabled, reason = f.owner:enable()
            eq(enabled, false); eq(reason, "cleanup_pending"); eq(f.begins, 1)
            f[injection] = false
            eq(f.owner:disable("local cleanup retry"), true)
            eq(f.owner._pending_restore, nil); eq(f.paused, false); near(f.scale, 0.75)
            eq(f.ends, 1); eq(f.ended_leases[1], lease)
        end)
    end

    local Driver = dofile(production .. "_gt_freeze_movement.lua")
    local function driver_fixture()
        local f = { calls = {}, move = {}, unit = {}, camera = {}, mover = {}, lookup = {} }
        local function record(name) f.calls[#f.calls + 1] = name end
        local d = { unit = f.unit, player = { viewport_name = "player_1" },
            inventory = {}, camera_unit = f.camera,
            camera_state = "follow", viewport = "player_1" }
        f.ctx = { unit = f.unit, player = d.player, world = {}, driver_context = d,
            gamepad = false, motion_controls = false }
        d.world = f.ctx.world
        d.input = {
            unit = f.unit,
            update = function(_, u, _, dt, context, t)
                if f.context_seen then eq(context, f.context_seen, "reuse frame context") end
                f.context_seen = context
                eq(u, f.unit); near(dt, EPS); near(t, 100); record("input")
            end,
            get = function(_, key) if key == "walk" then return f.walk end end,
        }
        d.fp = {
            unit = f.unit, world = f.ctx.world,
            update_rotation = function(_, t, dt)
                near(t, 100); near(dt, 0.02); record("look_rotation")
            end,
            update_position = function() record("fp_position") end,
        }
        d.loco = { unit = f.unit, world = f.ctx.world, state = "script_driven",
            set_wanted_velocity = function() end }
        d.status = {
            unit = f.unit,
            move_speed_multiplier = 1, move_speed_multiplier_timer = 1,
            current_move_speed_multiplier = NativeMovement.current_move_speed_multiplier,
            is_crouching = function() return f.crouch == true end,
        }
        d.camera_csm = { unit = f.camera, world = f.ctx.world, update = function(_, u, _, dt, _, t)
            eq(u, f.camera); near(dt, 0.02); near(t, 100); record("camera_follow")
        end }
        d.camera_manager = { post_update = function(_, dt, t, viewport)
            near(dt, 0.02); near(t, 100); eq(viewport, "player_1"); record("camera_post")
        end }
        local native_settings = NativeMovement.new_settings_api()
        f.settings = native_settings.get_movement_settings_table(f.unit)
        local api = { engine = {
            Unit = {
                alive = function(u) return u == f.unit or u == f.camera end,
                mover = function(u) if u == f.unit then return f.mover end end,
                world_position = function(u, index)
                    eq(u, f.unit); eq(index, 0); f.fresh_position = {}; return f.fresh_position
                end,
            },
            POSITION_LOOKUP = f.lookup,
            PlayerUnitMovementSettings = { get_movement_settings_table = function(u)
                eq(u, f.unit)
                return native_settings.get_movement_settings_table(u)
            end },
            CharacterStateHelper = {
                look = function(input, viewport, fp, status, inventory)
                    eq(input, d.input); eq(viewport, d.viewport); eq(fp, d.fp)
                    eq(status, d.status); eq(inventory, d.inventory); record("look_input")
                end,
                get_movement_input = function(input) eq(input, d.input); return f.move end,
                move_on_ground = function(fp, input, loco, move, speed, u)
                    eq(fp, d.fp); eq(input, d.input); eq(loco, d.loco)
                    eq(move, f.move, "analog vector passed unchanged"); eq(u, f.unit)
                    f.applied_speed = speed; record("wanted_movement")
                end,
            },
            PlayerLocomotionTemplate = {
                update_movement = function(one, t, dt)
                    eq(one.all_update_units[f.unit], d.loco)
                    local n = 0; for _ in pairs(one.all_update_units) do n = n + 1 end
                    eq(n, 1, "only local unit moved"); near(t, 100); near(dt, 0.02)
                    record("native_mover")
                    if f.fail_native then error("native mover test failure") end
                end,
                update_rotation = function(one, t, dt)
                    eq(one.all_update_units[f.unit], d.loco); near(t, 100); near(dt, 0.02)
                    eq(f.lookup[f.unit], f.fresh_position, "fresh lookup before rotation")
                    record("body_rotation")
                end,
            },
        } }
        f.api, f.d = api, d
        f.driver = Driver.new(api)
        return f
    end

    H.test("gt selective freeze: native-shaped driver preserves source call order and analog input", function()
        local f = driver_fixture()
        eq(f.driver:update(f.ctx, 0.02, 100), true)
        eq(f.driver:post(f.ctx, 0.02, 100), true); near(f.applied_speed, 4)
        eq(table.concat(f.calls, ","), "input,look_input,look_rotation,wanted_movement,"
            .. "native_mover,body_rotation,fp_position,camera_follow,camera_post")
    end)

    H.test("gt selective freeze: native-shaped driver honors grounded crouch and walk speed modifiers", function()
        local f = driver_fixture(); f.crouch = true
        f.d.status.move_speed_multiplier, f.d.status.move_speed_multiplier_timer = 0.5, 0
        f.driver:update(f.ctx, 0.02, 100); near(f.applied_speed, 0.7)
        f.crouch, f.walk = false, true
        f.driver:update(f.ctx, 0.02, 100); near(f.applied_speed, 0.95)
    end)

    H.test("gt selective freeze: driver reuses and clears its scalar reference context", function()
        local f = driver_fixture()
        f.driver:update(f.ctx, 0.02, 100)
        local context = f.context_seen
        f.driver:update(f.ctx, 0.02, 100)
        eq(f.context_seen, context)
        for _, value in pairs(context) do
            assert(value ~= f.fresh_position, "raw position retained in driver context")
        end
        f.driver:clear()
        eq(next(context), nil, "old-world frame references cleared")
    end)

    H.test("gt selective freeze: native-shaped speed composes status timer and per-unit player scale", function()
        local f = driver_fixture()
        f.d.status.move_speed_multiplier, f.d.status.move_speed_multiplier_timer = 0.5, 0.25
        f.settings.player_speed_scale = 2
        f.driver:update(f.ctx, 0.02, 100)
        near(f.applied_speed, 4.4140625) -- independent quintic smoothstep value at1/4
    end)

    H.test("gt selective freeze: native settings fixture caches each unit without changing global defaults", function()
        local settings = NativeMovement.new_settings_api()
        local first, second = {}, {}
        local a = settings.get_movement_settings_table(first)
        eq(settings.get_movement_settings_table(first), a)
        a.move_speed = 9
        eq(settings.get_movement_settings_table(second).move_speed, 4)
        eq(NativeMovement.defaults.move_speed, 4)
    end)

    H.test("gt selective freeze: driver never sends zero or unbounded dt to mover", function()
        for _, bad in ipairs({ 0, -0.1, 0.051, math.huge }) do
            local f = driver_fixture()
            eq(pcall(f.driver.update, f.driver, f.ctx, bad, 100), false)
            eq(#f.calls, 0)
        end
    end)

    H.test("gt selective freeze: driver rejects unsupported movement before source calls", function()
        local f = driver_fixture(); f.d.loco.state = "linked_movement"
        eq(pcall(f.driver.update, f.driver, f.ctx, 0.02, 100), false)
        eq(#f.calls, 0)
    end)

    for _, mutation in ipairs({ "input_unit", "fp_unit", "loco_unit", "camera_unit", "status_unit", "fp_world",
        "loco_world", "camera_world", "viewport", "world", "gamepad", "motion_controls" }) do
        H.test("gt selective freeze: driver rejects mismatched " .. mutation .. " before source calls", function()
            local f = driver_fixture()
            if mutation == "input_unit" then f.d.input.unit = {}
            elseif mutation == "fp_unit" then f.d.fp.unit = {}
            elseif mutation == "loco_unit" then f.d.loco.unit = {}
            elseif mutation == "camera_unit" then f.d.camera_csm.unit = {}
            elseif mutation == "status_unit" then f.d.status.unit = {}
            elseif mutation == "fp_world" then f.d.fp.world = {}
            elseif mutation == "loco_world" then f.d.loco.world = {}
            elseif mutation == "camera_world" then f.d.camera_csm.world = {}
            elseif mutation == "viewport" then f.d.player.viewport_name = "other"
            elseif mutation == "world" then f.d.world = {}
            elseif mutation == "gamepad" then f.ctx.gamepad = true
            elseif mutation == "motion_controls" then f.ctx.motion_controls = true end
            eq(pcall(f.driver.update, f.driver, f.ctx, 0.02, 100), false)
            eq(#f.calls, 0)
        end)
    end

    H.test("gt selective freeze: driver cleanup drops local unit map after native failure", function()
        local f = driver_fixture(); f.fail_native = true
        eq(pcall(f.driver.update, f.driver, f.ctx, 0.02, 100), false)
        f.driver:clear()
        eq(next(f.driver.one_unit.all_update_units), nil)
    end)

    H.test("gt selective freeze: next update validation failure drops preceding unit map", function()
        local f = driver_fixture(); f.driver:update(f.ctx, 0.02, 100)
        f.ctx.unit = {}
        eq(pcall(f.driver.update, f.driver, f.ctx, 0.02, 100), false)
        eq(next(f.driver.one_unit.all_update_units), nil)
    end)

    H.test("gt selective freeze: post identity failure drops preceding unit map", function()
        local f = driver_fixture(); f.driver:update(f.ctx, 0.02, 100)
        f.ctx.world = {}
        eq(pcall(f.driver.post, f.driver, f.ctx, 0.02, 100), false)
        eq(next(f.driver.one_unit.all_update_units), nil)
    end)

    H.test("gt selective freeze: post extension validation failure drops preceding unit map", function()
        local f = driver_fixture(); f.driver:update(f.ctx, 0.02, 100)
        f.d.camera_csm.unit = {}
        eq(pcall(f.driver.post, f.driver, f.ctx, 0.02, 100), false)
        eq(next(f.driver.one_unit.all_update_units), nil)
    end)

end
