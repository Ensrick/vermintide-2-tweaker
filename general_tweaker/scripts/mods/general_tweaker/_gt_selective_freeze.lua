-- _gt_selective_freeze.lua - Own selective world stasis and exact cleanup leases.
--
-- Stops normal entity/world progression while a bounded local movement driver runs
-- in native entity phases. World/timer restoration is verified on exact live
-- identities; unconfirmed cleanup keeps its lease and blocks another freeze.
-- Native seams: EntitySystem.system_update:494-509; ScriptWorld:17-22,316-340;
-- TimeManager:155-165 and Timer.update:15-28 (game scale 0 still yields epsilon).
--
-- Owned by: general_tweaker.lua manifest. Consumed via:
-- scripts/mods/general_tweaker/_gt_time_control (#1801/#1802).
local M = {}
local EPSILON, MAX_DT = 1e-06, 0.05
local PHASES = { pre_update = true, update = true, post_update = true }

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

function M.new(_mod, api, timeOwner)
    local owner = { _saved = nil, _pending_restore = nil }
    local function report(event, reason)
        if type(api.report) == "function" then pcall(api.report, event, reason) end
    end
    local function resolve()
        local ok, ctx = pcall(api.resolve_context)
        return ok and type(ctx) == "table" and ctx or nil
    end
    local function validate(ctx)
        if not ctx then return false, "context_unavailable" end
        if ctx.modded ~= true then return false, "modded_realm_required" end
        if ctx.host ~= true then return false, "host_required" end
        if ctx.humans ~= 1 then return false, "solo_required" end
        if ctx.pending_peers ~= nil and ctx.pending_peers ~= 0 then
            return false, "pending_peer"
        end
        if ctx.state ~= "StateIngame" or not ctx.state_object then
            return false, "ingame_required"
        end
        if not (ctx.world and ctx.time_manager and ctx.game_timer
                and ctx.unit and ctx.player and ctx.entity) then
            return false, "identity_unavailable"
        end
        if ctx.alive ~= true or ctx.disabled ~= false then
            return false, "living_enabled_player_required"
        end
        -- Paused smart-targeting retains raw target_position; do not feed it to
        -- controller aim assist. Source: smart_targeting extension:188-192,416-418.
        if ctx.gamepad ~= false or ctx.motion_controls ~= false then
            return false, "keyboard_mouse_required"
        end
        if ctx.csm_state ~= "standing" and ctx.csm_state ~= "walking" then
            return false, "ordinary_player_state_required"
        end
        if ctx.loco_state ~= "script_driven" then
            return false, "script_driven_required"
        end
        if ctx.camera_state ~= "follow" or ctx.camera_transition == true then
            return false, "follow_camera_required"
        end
        if not api.world_live(ctx.world) then return false, "world_not_live" end
        if api.game_identity(ctx.time_manager) ~= ctx.game_timer then
            return false, "game_timer_changed"
        end
        return true
    end
    local function restore(saved, reason)
        -- Disarm first, but retain the lease until local restoration is observed.
        owner._saved = nil
        owner._pending_restore = nil
        local pending = false
        if saved.driver and type(saved.driver.clear) == "function" then
            pcall(saved.driver.clear, saved.driver)
        end
        local live = resolve()
        -- Never call world-native functions until exact current-world proof.
        local ok, world_live = pcall(api.world_live, saved.world)
        if saved.world_attempted and not ok then
            pending = true
            report("restore_world_identity_unknown", tostring(world_live))
        elseif saved.world_attempted and not world_live then
            saved.world_attempted = false -- positively retired; never touch old handle
        elseif saved.world_attempted then
            local read_ok, paused = pcall(api.world_paused, saved.world)
            if read_ok and paused == saved.paused then
                saved.world_attempted = false
            elseif read_ok and paused == true then
                local wrote, result = pcall(api.set_world_paused,
                    saved.world, saved.paused)
                local still_ok, still_live = pcall(api.world_live, saved.world)
                local post_ok, observed = false, nil
                if still_ok and still_live then
                    post_ok, observed = pcall(api.world_paused, saved.world)
                end
                if wrote and result ~= false and post_ok and observed == saved.paused then
                    saved.world_attempted = false
                else
                    pending = true
                    report("restore_world_unconfirmed", tostring(result))
                end
            else pending = true; report("restore_world_read_failed", tostring(paused))
            end
        end
        -- Timer is Lua-owned, but current manager AND exact private timer must match.
        if saved.timer_attempted and not live then
            pending = true
        elseif saved.timer_attempted and live.time_manager ~= saved.time_manager then
            saved.timer_attempted = false
        elseif saved.timer_attempted then
            local id_ok, identity = pcall(api.game_identity, saved.time_manager)
            if not id_ok then pending = true
            elseif identity ~= saved.game_timer then saved.timer_attempted = false
            else
                local read_ok, scale = pcall(api.local_scale, saved.time_manager)
                if read_ok and scale == saved.scale then
                    saved.timer_attempted = false
                elseif read_ok and scale == 0 then
                    local wrote, result = pcall(api.set_local_scale,
                        saved.time_manager, saved.scale)
                    local post_live = resolve()
                    local post_ok, observed = false, nil
                    if post_live and post_live.time_manager == saved.time_manager then
                        local same_ok, same = pcall(api.game_identity, saved.time_manager)
                        if same_ok and same == saved.game_timer then
                            post_ok, observed = pcall(api.local_scale, saved.time_manager)
                        end
                    end
                    if wrote and result ~= false and post_ok and observed == saved.scale then
                        saved.timer_attempted = false
                    else
                        pending = true
                        report("restore_timer_unconfirmed", tostring(result))
                    end
                elseif not read_ok or not finite(scale) or scale < 0 then
                    pending = true
                    report("restore_timer_read_failed", tostring(scale))
                else saved.timer_attempted = false end -- foreign nonzero owner
            end
        end
        if not pending and saved.lease ~= nil then
            local ended, accepted, err = pcall(timeOwner.end_freeze, saved.lease)
            if not ended or accepted ~= true then
                pending = true
                report("restore_time_owner_failed", tostring(ended and err or accepted))
            else saved.lease = nil end
        end
        if pending then owner._pending_restore = saved end
        report(pending and "cleanup_pending" or "disabled", reason or "requested")
    end
    local function current()
        local saved = owner._saved
        if not saved then return nil end
        local ctx = resolve()
        local ok, valid, reason = pcall(validate, ctx)
        if not ok then reason = "validation_error:" .. tostring(valid) end
        if not ok or not valid then restore(saved, reason); return nil end
        if ctx.world ~= saved.world or ctx.time_manager ~= saved.time_manager
                or ctx.game_timer ~= saved.game_timer or ctx.unit ~= saved.unit
                or ctx.player ~= saved.player or ctx.entity ~= saved.entity
                or ctx.state_object ~= saved.state_object then
            restore(saved, "identity_changed")
            return nil
        end
        local read_ok, paused = pcall(api.world_paused, saved.world)
        local scale_ok, scale = pcall(api.local_scale, saved.time_manager)
        if not read_ok or paused ~= true or not scale_ok or scale ~= 0 then
            restore(saved, "ownership_lost")
            return nil
        end
        return saved, ctx
    end
    local function game_time(ctx)
        local t = ctx.game_t
        if t == nil and type(api.game_time) == "function" then
            t = api.game_time(ctx.time_manager)
        end
        if not finite(t) then error("game_time_unavailable", 0) end
        return t
    end
    local function sample_frame(saved)
        local frame = api.frame_id()
        if frame == nil then error("frame_unavailable", 0) end
        if saved.sampled_frame ~= frame then
            local now = api.wall_time()
            if not finite(now) then error("wall_time_unavailable", 0) end
            local delta = saved.wall_time and now - saved.wall_time or EPSILON
            saved.wall_time, saved.sampled_frame = now, frame
            saved.real_dt = finite(delta) and math.max(EPSILON, math.min(delta, MAX_DT))
                or EPSILON
            saved.updated_frame, saved.posted_frame = nil, nil
        end
    end
    local function drive_phase(saved, ctx, phase)
        local frame = api.frame_id()
        if saved.sampled_frame ~= frame then return false end
        if phase == "update" then
            if saved.updated_frame == frame then return true end
            local worked = saved.driver:update(ctx, saved.real_dt, game_time(ctx))
            if worked == false then error("driver_rejected", 0) end
            saved.updated_frame = frame
        else
            if saved.updated_frame ~= frame then return false end
            if saved.posted_frame == frame then return true end
            local worked = saved.driver:post(ctx, saved.real_dt, game_time(ctx))
            if worked == false then error("camera_rejected", 0) end
            saved.posted_frame = frame
        end
        return true
    end
    function owner:enable()
        if self._saved then return true end
        if self._pending_restore then return false, "cleanup_pending" end
        local ctx = resolve()
        local checked, valid, reason = pcall(validate, ctx)
        if not checked then return false, "validation_error:" .. tostring(valid) end
        if not valid then return false, reason end
        local saved = {
            world = ctx.world, time_manager = ctx.time_manager, game_timer = ctx.game_timer,
            unit = ctx.unit, player = ctx.player, entity = ctx.entity,
            state_object = ctx.state_object, real_dt = EPSILON,
        }
        local ok, err = pcall(function()
            saved.paused = api.world_paused(saved.world)
            if saved.paused ~= false then error("world_already_paused", 0) end
            saved.scale = api.local_scale(saved.time_manager)
            if not finite(saved.scale) or saved.scale < 0 then
                error("timer_scale_unavailable", 0)
            end
            saved.driver = api.driver_factory(ctx)
            if type(saved.driver) ~= "table" or type(saved.driver.update) ~= "function"
                    or type(saved.driver.post) ~= "function" then
                error("driver_unavailable", 0)
            end
            saved.lease = timeOwner.begin_freeze()
            if saved.lease == nil or saved.lease == false then
                saved.lease = nil
                error("time_lease_unavailable", 0)
            end
            -- Publish ownership before attempted writes so partial writes can unwind.
            self._saved = saved
            saved.timer_attempted = true
            api.set_local_scale(saved.time_manager, 0)
            saved.world_attempted = true
            api.set_world_paused(saved.world, true)
            if api.local_scale(saved.time_manager) ~= 0
                    or api.world_paused(saved.world) ~= true then
                error("freeze_write_not_observed", 0)
            end
        end)
        if not ok then restore(saved, "enable_error:" .. tostring(err)); return false, tostring(err) end
        report("enabled", "movement_inspection")
        return true
    end
    function owner:disable(reason)
        local saved = self._saved or self._pending_restore
        if not saved then return false end
        restore(saved, reason)
        return true
    end
    function owner:toggle()
        if self._saved then return self:disable("toggle") end
        return self:enable()
    end
    function owner:is_active() return self._saved ~= nil end
    function owner:has_pending_cleanup() return self._pending_restore ~= nil end
    function owner:cleanup(reason)
        self:disable(reason)
        if self._saved or self._pending_restore then return false, "cleanup_pending" end
        return true
    end
    function owner:outer_dt(state, phase, dt)
        local saved = current()
        if not saved or state ~= saved.state_object or not PHASES[phase] then return dt end
        if phase == "pre_update" then
            local ok, err = pcall(sample_frame, saved)
            if not ok then restore(saved, "clock_error:" .. tostring(err)); return dt end
        end
        return EPSILON
    end
    function owner:on_entity_phase(entity, phase, _dt)
        local saved, ctx = current()
        if not saved or entity ~= saved.entity then return false end
        if phase ~= "update" and phase ~= "post_update" then return false end
        local ok, result = pcall(drive_phase, saved, ctx, phase)
        if not ok then restore(saved, "driver_error:" .. tostring(result)); return false end
        return result
    end
    function owner:on_state(status, state)
        if not self._saved then return end
        if (status == "exit" and state == "StateIngame")
                or (status == "enter" and state ~= "StateIngame") then
            self:disable("state_transition")
        end
    end
    return owner
end

M.EPSILON, M.MAX_DT = EPSILON, MAX_DT
return M
