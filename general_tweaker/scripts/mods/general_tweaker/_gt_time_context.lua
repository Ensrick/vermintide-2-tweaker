-- Native identity adapter for General's time controls (#1801/#1802).
-- Pure factory; no hooks, settings writes, retained engine vectors or clocks.
-- Public: M.new(mod, realm, current_state, environment?) -> native adapter.
-- Loaded once by the main factory manifest before _gt_time_control.
-- Source: StateIngame:804-832,2356-2388; EntitySystem:195-207;
-- PlayerManager:477-490,588-595; GenericStateMachine:89-91;
-- CameraSystem:178; GameNetworkManager:53,832-835; LobbyMembers:109-111.
local M = {}

local function method(value, name)
    return value ~= nil and type(value[name]) == "function"
end

function M.new(mod, realm, current_state, environment)
    local env = environment or _G
    -- Reused reference/scalar scratch only. No engine Vector3/Quaternion survives
    -- a frame and repeated phase validation makes no new Lua context tables.
    local ctx, driver_context, native_state, empty = {}, {}, {}, {}
    local function managers() return env.Managers or empty end
    local function enabled()
        return method(mod, "is_enabled") and mod:is_enabled() == true
    end
    local function modded()
        return realm.sibling_is_modded(env.script_data, env.get_mod,
            env.Development, env) == true
    end
    local function game_identity(tm)
        return type(tm) == "table" and type(rawget(tm, "_timers")) == "table"
            and rawget(rawget(tm, "_timers"), "game") or nil
    end
    local function world_live(world)
        local wm = managers().world
        return world ~= nil and method(wm, "has_world") and wm:has_world("level_world")
            and wm:world("level_world") == world
    end
    local function authorize()
        local all = managers()
        local state = current_state()
        local debug = all.state and all.state.debug
        if not enabled() then return false, "mod_disabled" end
        if not modded() then return false, "modded_realm_required" end
        if not (all.player and all.player.is_server == true and debug
                and debug.is_server == true) then return false, "host_required" end
        if not (state and state.NAME == "StateIngame" and state.is_server == true
                and world_live(state.world)) then return false, "ingame_required" end
        return true
    end
    local function authorize_cleanup(manager)
        local all = managers()
        if not (all.state and all.state.debug == manager) then
            return false, "manager_not_current"
        end
        local network = all.state.network
        if modded() and all.player and all.player.is_server == true
                and manager.is_server == true and network
                and network.is_server == true and network.network_transmit
                and method(network, "in_game_session") and network:in_game_session() == true then
            return "synchronized"
        end
        return "local_only"
    end
    local function read_native()
        local all = managers()
        local debug = all.state and all.state.debug
        if not debug then return nil end
        native_state.index, native_state.paused = debug.time_scale_index, debug.time_paused
        native_state.multiplier = rawget(env, "GLOBAL_TIME_SCALE")
        return debug, native_state
    end
    local function pending_peers(network)
        if not (network and type(network._object_synchronizing_clients) == "table"
                and method(network, "lobby") and env.Network) then return nil end
        local lobby = network:lobby()
        if not method(lobby, "members") then return nil end
        local member_owner = lobby:members()
        if not method(member_owner, "get_members") then return nil end
        local members = member_owner:get_members()
        if type(members) ~= "table" then return nil end
        local local_peer, count = env.Network.peer_id(), 0
        if local_peer == nil then return nil end
        for _, peer in pairs(members) do
            if peer ~= local_peer then count = count + 1 end
        end
        for _ in pairs(network._object_synchronizing_clients) do count = count + 1 end
        return count
    end
    local function resolve()
        local all = managers()
        local state, tm = current_state(), all.time
        for key in pairs(ctx) do ctx[key] = nil end
        for key in pairs(driver_context) do driver_context[key] = nil end
        -- Keep teardown identities available even with no player/realm/authority.
        ctx.time_manager, ctx.game_timer = tm, game_identity(tm)
        if all.world and method(all.world, "has_world")
                and all.world:has_world("level_world") then
            ctx.world = all.world:world("level_world")
        end
        local allowed = authorize()
        ctx.modded, ctx.host = modded(), all.player and all.player.is_server == true
        if not allowed then return ctx end
        ctx.state, ctx.state_object, ctx.entity = state.NAME, state, state.entity_system
        if not (ctx.entity and ctx.entity.world == ctx.world
                and all.state and ctx.entity.entity_manager == all.state.entity) then return ctx end
        local pm, network = all.player, all.state.network
        ctx.humans = method(pm, "num_human_players") and pm:num_human_players() or nil
        ctx.pending_peers = pending_peers(network)
        -- Unknown admission state is not evidence of being alone.
        if ctx.pending_peers == nil then ctx.pending_peers = -1 end
        local player = method(pm, "local_player_safe") and pm:local_player_safe(1) or nil
        ctx.player, ctx.unit = player, player and player.player_unit
        if not (ctx.unit and env.Unit and env.Unit.alive(ctx.unit)
                and env.ScriptUnit and method(all.state.entity, "system")) then return ctx end
        local unit = ctx.unit
        local input = env.ScriptUnit.has_extension(unit, "input_system")
        local fp = env.ScriptUnit.has_extension(unit, "first_person_system")
        local loco = env.ScriptUnit.has_extension(unit, "locomotion_system")
        local status = env.ScriptUnit.has_extension(unit, "status_system")
        local health = env.ScriptUnit.has_extension(unit, "health_system")
        local inventory = env.ScriptUnit.has_extension(unit, "inventory_system")
        local character = env.ScriptUnit.has_extension(unit, "character_state_machine_system")
        if not (status and method(status, "is_disabled") and method(status, "is_dead")
                and health and method(health, "is_alive")) then return ctx end
        ctx.alive = health:is_alive() == true and status:is_dead() == false
        ctx.disabled = not not status:is_disabled()
        local csm = character and character.state_machine
        ctx.csm_state = csm and method(csm, "current_state") and csm.state_next == nil
            and csm:current_state() or nil
        ctx.loco_state = loco and loco.state
        if not method(all.input, "is_device_active") then return ctx end
        ctx.gamepad = all.input:is_device_active("gamepad") == true
        ctx.motion_controls = env.MotionControlSettings
            and env.MotionControlSettings.use_motion_controls == true or false
        local camera_system = all.state.entity:system("camera_system")
        local camera_unit = camera_system and camera_system.camera_units
            and camera_system.camera_units[player]
        if not (camera_unit and env.Unit.alive(camera_unit)) then return ctx end
        local camera_csm = env.ScriptUnit.has_extension(camera_unit, "camera_state_machine_system")
        local machine = camera_csm and camera_csm.state_machine
        ctx.camera_state = machine and method(machine, "current_state") and machine:current_state()
        ctx.camera_transition = not machine or machine.state_next ~= nil
        ctx.game_t = game_identity(tm) and tm:time("game") or nil
        driver_context.unit, driver_context.player = unit, player
        driver_context.world, driver_context.viewport = ctx.world, player.viewport_name
        driver_context.input, driver_context.fp, driver_context.loco = input, fp, loco
        driver_context.status, driver_context.inventory = status, inventory
        driver_context.camera_unit, driver_context.camera_csm = camera_unit, camera_csm
        driver_context.camera_manager, driver_context.camera_state = all.state.camera, ctx.camera_state
        driver_context.camera_transition, driver_context.entity_manager = ctx.camera_transition, all.state.entity
        driver_context.network_transmit = ctx.entity.network_transmit
        driver_context.statistics_db, driver_context.dice_keeper = ctx.entity.statistics_db, ctx.entity.dice_keeper
        ctx.driver_context = driver_context
        return ctx
    end
    return { authorize = authorize, authorize_cleanup = authorize_cleanup,
        read_native = read_native, resolve_context = resolve,
        world_live = world_live, game_identity = game_identity }
end

return M
