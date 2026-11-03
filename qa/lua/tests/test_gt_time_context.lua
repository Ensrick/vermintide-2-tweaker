-- The identity adapter is tested on ordinary Lua references and scalar flags.
-- These cases do not simulate a mover, native physics or VMF scheduling.
return function(H, repo_root)
    local root = repo_root .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/"
    local Context = assert(loadfile(root .. "_gt_time_context.lua"))()
    local Realm = assert(loadfile(repo_root .. "/tools/shared_lib/_lib_modded_realm_authority.lua"))()
    local function fixture()
        local world, unit, camera_unit, game_timer = {}, {}, {}, {}
        local player = { player_unit = unit, viewport_name = "player_1" }
        local camera_machine = { current_state = function() return "follow" end }
        local status = { is_dead = function() return false end,
            is_disabled = function() return false end }
        local extensions = {
            input_system = {}, first_person_system = {},
            locomotion_system = { state = "script_driven" }, status_system = status,
            inventory_system = {}, health_system = { is_alive = function() return true end },
            character_state_machine_system = {
                state_machine = { current_state = function() return "standing" end },
            },
        }
        local members, pending = { "local" }, {}
        local member_owner = { get_members = function() return members end }
        local lobby = { members = function() return member_owner end }
        local network = { is_server = true, network_transmit = {},
            _object_synchronizing_clients = pending, lobby = function() return lobby end,
            in_game_session = function() return true end }
        local entity_manager = { system = function(_, name)
            if name == "camera_system" then return { camera_units = { [player] = camera_unit } } end
        end }
        local debug = { is_server = true, time_scale_index = 13, time_paused = false }
        local tm = { _timers = { game = game_timer }, time = function() return 42 end }
        local state = { NAME = "StateIngame", is_server = true, world = world,
            entity_system = { world = world, entity_manager = entity_manager } }
        local env = { MODDED_REALM = true, GLOBAL_TIME_SCALE = 1, script_data = {},
            Network = { peer_id = function() return "local" end },
            Unit = { alive = function(value) return value == unit or value == camera_unit end },
            ScriptUnit = { has_extension = function(value, name)
                if value == unit then return extensions[name] end
                if value == camera_unit and name == "camera_state_machine_system" then
                    return { unit = camera_unit, state_machine = camera_machine }
                end
            end },
            Managers = {
                player = { is_server = true, num_human_players = function() return 1 end,
                    local_player_safe = function() return player end },
                world = { has_world = function(_, name) return name == "level_world" end,
                    world = function() return world end },
                input = { is_device_active = function() return false end }, time = tm,
                state = { debug = debug, entity = entity_manager, camera = {}, network = network },
            },
        }
        local active = true
        local mod = { is_enabled = function() return active end }
        local adapter = Context.new(mod, Realm, function() return state end, env)
        return { adapter = adapter, env = env, state = state, extensions = extensions,
            world = world, unit = unit, tm = tm, game_timer = game_timer, debug = debug,
            members = members, pending = pending, camera_machine = camera_machine,
            disable = function() active = false end }
    end
    H.test("GT time context proves current native identities", function()
        local f = fixture()
        H.equal(f.adapter.authorize(), true)
        local ctx = f.adapter.resolve_context()
        H.equal(ctx.world, f.world)
        H.equal(ctx.time_manager, f.tm)
        H.equal(ctx.game_timer, f.game_timer)
        H.equal(ctx.state_object, f.state)
        H.equal(ctx.entity, f.state.entity_system)
        H.equal(ctx.unit, f.unit)
        H.equal(ctx.alive, true)
        H.equal(ctx.disabled, false)
        H.equal(ctx.humans, 1)
        H.equal(ctx.pending_peers, 0)
        H.equal(ctx.camera_state, "follow")
        H.equal(ctx.camera_transition, false)
        H.equal(ctx.csm_state, "standing")
        H.equal(ctx.driver_context.unit, f.unit)
        H.equal(ctx.driver_context.world, f.world)
    end)
    H.test("GT cleanup retains world and timer after control authority is lost", function()
        local f = fixture()
        f.disable()
        H.equal(f.adapter.authorize(), false)
        local ctx = f.adapter.resolve_context()
        H.equal(ctx.time_manager, f.tm)
        H.equal(ctx.game_timer, f.game_timer)
        H.equal(ctx.world, f.world)
        H.equal(ctx.player, nil)
        H.equal(f.adapter.authorize_cleanup(f.debug), "synchronized")
        f.env.Managers.state.network.in_game_session = function() return false end
        H.equal(f.adapter.authorize_cleanup(f.debug), "local_only")
        f.env.Managers.state.network.in_game_session = function() return true end
        f.env.Managers.player.is_server = false
        H.equal(f.adapter.authorize_cleanup(f.debug), "local_only")
        f.env.Managers.state.debug = {}
        H.equal(f.adapter.authorize_cleanup(f.debug), false)
    end)
    H.test("GT freeze admission observes lobby and syncing peers before player creation", function()
        local f = fixture()
        f.members[2] = "joining"
        H.equal(f.adapter.resolve_context().pending_peers, 1)
        f.pending.joining = true
        H.equal(f.adapter.resolve_context().pending_peers, 2)
        f.env.Managers.state.network._object_synchronizing_clients = nil
        H.equal(f.adapter.resolve_context().pending_peers, -1)
    end)
    H.test("GT context never infers ready from missing identities or transitions", function()
        local f = fixture()
        f.camera_machine.state_next = "idle"
        H.equal(f.adapter.resolve_context().camera_transition, true)
        f.extensions.character_state_machine_system.state_machine.state_next = "jumping"
        H.equal(f.adapter.resolve_context().csm_state, nil)
        f.env.Managers.input = nil
        H.equal(f.adapter.resolve_context().gamepad, nil)
        f.env.Managers.world.has_world = function() return false end
        f.env.Managers.world.world = function() error("must not read a missing world") end
        H.equal(f.adapter.world_live(f.world), false)
        H.equal(f.adapter.authorize(), false)
    end)
    H.test("GT native readback includes exact effective scale and native pause", function()
        local f = fixture()
        local manager, read = f.adapter.read_native()
        H.equal(manager, f.debug)
        H.equal(read.index, 13)
        H.equal(read.paused, false)
        H.equal(read.multiplier, 1)
        f.env.GLOBAL_TIME_SCALE = 0.25
        H.equal(select(2, f.adapter.read_native()).multiplier, 0.25)
        f.env.MODDED_REALM = false
        H.equal(f.adapter.authorize(), false)
        H.equal(f.adapter.authorize_cleanup(f.debug), "local_only")
    end)
    H.test("GT context reuses phase scratch and drops retired player references", function()
        local f = fixture()
        local first = f.adapter.resolve_context()
        local driver = first.driver_context
        H.equal(driver.unit, f.unit)
        H.equal(f.adapter.resolve_context(), first)
        H.equal(first.driver_context, driver)
        f.env.Managers.player.local_player_safe = function() return nil end
        local missing = f.adapter.resolve_context()
        H.equal(missing, first)
        H.equal(missing.player, nil)
        H.equal(missing.driver_context, nil)
        H.equal(driver.unit, nil)
        H.equal(driver.world, nil)
        H.equal(missing.time_manager, f.tm)
        H.equal(missing.world, f.world)
    end)
    H.test("GT explicit context clear releases cached capability graphs without replacing scratch", function()
        local f = fixture()
        local ctx = f.adapter.resolve_context()
        local driver = ctx.driver_context
        local _, native = f.adapter.read_native()
        H.equal(ctx.state_object, f.state)
        H.equal(driver.unit, f.unit)
        H.equal(native.index, 13)
        f.adapter.clear()
        H.equal(next(ctx), nil)
        H.equal(next(driver), nil)
        H.equal(next(native), nil)
        local fresh = f.adapter.resolve_context()
        H.equal(fresh, ctx)
        H.equal(fresh.driver_context, driver)
        H.equal(fresh.state_object, f.state)
        H.equal(fresh.driver_context.unit, f.unit)
    end)
end
