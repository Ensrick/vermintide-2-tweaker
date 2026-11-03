-- _gt_freeze_movement.lua - Move and look with only the local body during stasis.
--
-- Reuses the native one-unit mover and follow-camera paths without updating the
-- full player CSM, weapons, interactions, global moods or actors. Supports only
-- solo keyboard/mouse standing/walking inspection; native C++ collision and
-- paused-scene behavior remain explicit in-game acceptance gates.
--
-- Owned by: general_tweaker_dev.lua manifest. Consumed via:
-- scripts/mods/general_tweaker_dev/_gt_time_control (#1801/#1802).
local M = {}

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end
local function method(object, name)
    return object and type(object[name]) == "function"
end

function M.new(api)
    local engine = assert(api.engine, "engine adapter required")
    local helper = assert(engine.CharacterStateHelper, "CharacterStateHelper required")
    local template = assert(engine.PlayerLocomotionTemplate, "player template required")
    local unit_api = assert(engine.Unit, "Unit required")
    local lookup = assert(engine.POSITION_LOOKUP, "POSITION_LOOKUP required")
    local movement = assert(engine.PlayerUnitMovementSettings, "movement settings required")
    local owner = { dummy = {}, context = {}, one_unit = { all_update_units = {} } }
    local function validate(ctx)
        local d = ctx and ctx.driver_context
        if type(d) ~= "table" then error("driver_context_unavailable", 0) end
        if not d.unit or d.unit ~= ctx.unit or not d.player or d.player ~= ctx.player then
            error("driver_identity_changed", 0)
        end
        if ctx.gamepad ~= false or ctx.motion_controls ~= false then
            error("keyboard_mouse_required", 0)
        end
        if not (method(d.input, "update") and method(d.input, "get")
                and method(d.fp, "update_rotation") and method(d.fp, "update_position")
                and method(d.loco, "set_wanted_velocity")
                and method(d.status, "current_move_speed_multiplier")
                and method(d.camera_csm, "update") and method(d.camera_manager, "post_update")) then
            error("driver_method_unavailable", 0)
        end
        if d.loco.state ~= "script_driven" or d.fp.unit ~= d.unit
                or d.loco.unit ~= d.unit or d.input.unit ~= d.unit
                or d.status.unit ~= d.unit or d.fp.world ~= ctx.world
                or d.loco.world ~= ctx.world or d.camera_csm.world ~= ctx.world
                or not d.camera_unit or not d.viewport or d.world ~= ctx.world
                or d.player.viewport_name ~= d.viewport
                or d.camera_csm.unit ~= d.camera_unit then
            error("driver_extension_mismatch", 0)
        end
        if d.camera_state ~= "follow" or d.camera_transition == true then
            error("driver_camera_not_follow", 0)
        end
        if not unit_api.alive(d.unit) or not unit_api.alive(d.camera_unit)
                or not unit_api.mover(d.unit) then
            error("driver_native_unit_unavailable", 0)
        end
        return d
    end
    local function speed(d)
        -- Ordinary ground speed only. No synthetic CSM/acceleration or state swaps.
        local settings = movement.get_movement_settings_table(d.unit)
        if type(settings) ~= "table" then error("movement_settings_unavailable", 0) end
        local base = settings.move_speed
        if method(d.status, "is_crouching") and d.status:is_crouching() then
            base = settings.crouch_move_speed
        elseif d.input:get("walk") then
            base = settings.walk_move_speed
        end
        local scale = d.status:current_move_speed_multiplier()
        local player_scale = settings.player_speed_scale
        if not finite(base) or base < 0 or not finite(scale) or scale < 0
                or not finite(player_scale) or player_scale < 0 then
            error("movement_speed_invalid", 0)
        end
        local value = base * scale * player_scale
        if not finite(value) or value > 100 then error("movement_speed_out_of_bound", 0) end
        return value
    end
    function owner:update(ctx, real_dt, game_t)
        -- Discard the preceding frame's unit map even if the new context is bad.
        self:clear()
        if not finite(real_dt) or real_dt <= 0 or real_dt > 0.05 or not finite(game_t) then
            error("driver_delta_invalid", 0)
        end
        local d = validate(ctx)
        local context = self.context
        context.world, context.dt, context.t = ctx.world, real_dt, game_t
        context.entity_manager, context.network_transmit = d.entity_manager, d.network_transmit
        context.statistics_db, context.dice_keeper = d.statistics_db, d.dice_keeper
        -- PlayerInputExtension.update:73-123 preserves game-t based housekeeping.
        d.input:update(d.unit, self.dummy, 1e-06, context, game_t)
        -- CharacterStateHelper.look:567-586; first_person.update_rotation:586-680.
        helper.look(d.input, d.viewport, d.fp, d.status, d.inventory)
        d.fp:update_rotation(game_t, real_dt)
        local move = helper.get_movement_input(d.input) -- helper:7-18, analog preserved
        helper.move_on_ground(d.fp, d.input, d.loco, move, speed(d), d.unit)
        -- Source-native template:119-187; mover path:371-568 retains collision/gravity.
        self.unit, self.viewport, self.world = d.unit, d.viewport, ctx.world
        self.one_unit.all_update_units[d.unit] = d.loco
        template.update_movement(self.one_unit, game_t, real_dt)
        -- Fresh phase-local value only: never retain raw Vector3 in this driver.
        lookup[d.unit] = unit_api.world_position(d.unit, 0)
        template.update_rotation(self.one_unit, game_t, real_dt)
        d.fp:update_position() -- first_person:724-732
        -- Camera-only CSM, NOT the player's character-state-machine extension.
        d.camera_csm:update(d.camera_unit, self.dummy, real_dt, context, game_t)
        if type(api.sync_local_player) == "function" then
            -- Optional local-only native template.update_network adapter. Not co-op proof.
            api.sync_local_player(self.one_unit, real_dt)
        end
        return true
    end
    function owner:post(ctx, real_dt, game_t)
        if not finite(real_dt) or real_dt <= 0 or real_dt > 0.05 or not finite(game_t) then
            self:clear()
            error("driver_delta_invalid", 0)
        end
        if not ctx or ctx.unit ~= self.unit or ctx.world ~= self.world then
            self:clear()
            error("driver_post_identity_changed", 0)
        end
        local checked, d = pcall(validate, ctx)
        if not checked then self:clear(); error(d, 0) end
        if d.unit ~= self.unit or d.viewport ~= self.viewport then
            self:clear()
            error("driver_post_identity_changed", 0)
        end
        -- CameraManager.post_update:594-610. No global mood/environment update.
        d.camera_manager:post_update(real_dt, game_t, d.viewport)
        return true
    end
    function owner:clear()
        for unit in pairs(self.one_unit.all_update_units) do
            self.one_unit.all_update_units[unit] = nil
        end
        self.unit, self.viewport, self.world = nil, nil, nil
        local context = self.context
        context.world, context.dt, context.t = nil, nil, nil
        context.entity_manager, context.network_transmit = nil, nil
        context.statistics_db, context.dice_keeper = nil, nil
    end
    return owner
end

return M
