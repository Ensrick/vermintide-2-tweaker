local mod = get_mod("gt_dev")
local BoundaryPolicy = mod:dofile("scripts/mods/general_tweaker_dev/_gt_noclip_boundary_policy")

-- _gt_noclip.lua — Noclip (player body flies through walls)
--
-- Moves the PLAYER BODY through walls via the engine's
-- `script_driven_no_mover` locomotion state (the same state used by
-- chaos-spawn-grab / tentacle-grab), which teleports the unit by
-- velocity_wanted * dt each tick without touching the mover — so static
-- geometry, props and enemies are all bypassed.
--
-- Two pieces:
--   (1) Hook `PlayerUnitLocomotionExtension.update_script_driven_no_mover_movement`
--       — when noclip is on for the local player, ignore whatever velocity the
--       character state machine wrote and compute our own from W/A/S/D +
--       Space/Ctrl projected through the first-person camera rotation. Shift
--       applies a boost multiplier.
--   (2) Re-assert `self.state = "script_driven_no_mover"` every frame — basic
--       states (standing/walking/jumping/falling) don't touch locomotion.state,
--       but transitions into ledge-hang / ladder / knockdown call
--       `enable_script_driven_movement()` which would hand us back to the
--       wall-respecting mover update.
--
-- DISPATCH WIRING (no behavior change after extraction):
--   * The apply-fn is exposed as `mod._gt_apply_noclip(enabled)` so the
--     main-file `on_setting_changed` branch (setting_id == "noclip_enabled")
--     still resolves it at call time.
--   * The shared `post_spawn_reapply` mod.update consumer in the main file
--     (which re-arms BOTH noclip and godmode after a level transition, since
--     godmode is NOT moved) calls `mod._gt_apply_noclip(true)` on re-arm and
--     `mod._gt_noclip_heartbeat()` once per frame to re-assert the locomotion
--     state. Both are exposed below. The post_spawn_reapply consumer + the
--     shared `_post_spawn_reapply_timer` stay in the main file (godmode owns
--     part of them).
--
-- Extracted from general_tweaker_dev.lua (v0.2.133-dev, "refactor: extract
-- single-hook self-contained features to modules — no behavior change").
-- Owned by: general_tweaker_dev.lua entry point. Consumed via: mod:dofile
-- (runs after the main chunk, so any mod._* fields are already set).

-- ============================================================
-- Noclip (player flies, ignores wall collision)
-- ============================================================

local _noclip_active = false
-- Issue #241: latch so the out-of-bounds-suicide suppression logs once per fly
-- episode. The z<-240 check re-fires every frame while the body is below the
-- world, so an unlatched printf would spam the console log.
local _boundary_route_logged = {}

local function _log_boundary_suppression(route, detail)
    if _boundary_route_logged[route] then return end
    _boundary_route_logged[route] = true
    printf("[gt][noclip] issue #241: suppressed %s for local player (%s)", route, detail)
end

local function _local_player_unit()
    local pm = Managers.player
    local player = pm and pm:local_player()
    return player and player.player_unit
end

local function _local_locomotion()
    local unit = _local_player_unit()
    if not unit then return nil end
    return ScriptUnit.has_extension(unit, "locomotion_system"), unit
end

-- Exposed as mod._gt_apply_noclip so the main-file on_setting_changed branch
-- and the shared post_spawn_reapply consumer (godmode + noclip) resolve it.
mod._gt_apply_noclip = function(enabled)
    _noclip_active = enabled and true or false
    _boundary_route_logged = {}  -- fresh episode: log each #241 route at most once
    local loco, unit = _local_locomotion()
    if not loco then
        mod:info("[noclip] no locomotion extension yet (not in a level?) — flag stored, will re-arm on player spawn via extensions_ready hook")
        return
    end
    if _noclip_active then
        loco:enable_script_driven_no_mover_movement()
        mod:info("[noclip] ON — loco.state now '%s' on unit %s", tostring(loco.state), tostring(unit))
    else
        -- Snap the mover to the player's current position before handing
        -- control back, otherwise the mover is still at the entry point
        -- and the next Mover.move() will yank the player back there.
        local mover = unit and Unit.mover(unit)
        if mover then
            Mover.set_position(mover, Unit.local_position(unit, 0))
        end
        loco:enable_script_driven_movement()
        loco:set_wanted_velocity(Vector3.zero())
        mod:info("[noclip] OFF — restored script_driven; loco.state '%s'", tostring(loco.state))
    end
end

local _NOCLIP_KEYS = {
    fwd     = "w",
    back    = "s",
    left    = "a",
    right   = "d",
    up      = "space",
    down    = "left ctrl",
    boost   = "left shift",
}

local function _key_held(name)
    local idx = Keyboard.button_index(name)
    return idx and Keyboard.button(idx) > 0
end

-- Noclip re-arm on spawn lives in the main file's mod.update via
-- _post_spawn_reapply_timer (set by PlayerUnitFirstPerson.extensions_ready in
-- the main file). Don't hook PlayerUnitLocomotionExtension.extensions_ready
-- directly here — at that timing `player.player_unit` isn't yet assigned
-- (assign_unit_ownership runs later in BulldozerPlayer:spawn), so
-- `mod._gt_apply_noclip` can't find the new locomotion extension via
-- _local_locomotion().

mod:hook("PlayerUnitLocomotionExtension", "update_script_driven_no_mover_movement",
function(func, self, unit, dt, t)
    if not _noclip_active or unit ~= _local_player_unit() then
        return func(self, unit, dt, t)
    end
    local fp = ScriptUnit.has_extension(unit, "first_person_system")
    if not fp then return func(self, unit, dt, t) end

    local rotation = fp:current_rotation()
    local forward  = Quaternion.forward(rotation)
    local right    = Quaternion.right(rotation)

    local fwd_axis   = (_key_held(_NOCLIP_KEYS.fwd)  and 1 or 0) - (_key_held(_NOCLIP_KEYS.back) and 1 or 0)
    local right_axis = (_key_held(_NOCLIP_KEYS.right) and 1 or 0) - (_key_held(_NOCLIP_KEYS.left) and 1 or 0)
    local up_axis    = (_key_held(_NOCLIP_KEYS.up)    and 1 or 0) - (_key_held(_NOCLIP_KEYS.down) and 1 or 0)

    local speed = mod:get("noclip_speed") or 15.0
    if _key_held(_NOCLIP_KEYS.boost) then
        speed = speed * (mod:get("noclip_boost_multiplier") or 3.0)
    end

    local velocity = forward * fwd_axis + right * right_axis + Vector3(0, 0, up_axis)
    local len = Vector3.length(velocity)
    if len > 0.001 then
        velocity = velocity / len * speed
    else
        velocity = Vector3.zero()
    end

    self.velocity_wanted:store(velocity)

    -- Replicate the original body: teleport, sync network, sync current.
    local current_position = POSITION_LOOKUP[unit]
    local final_position = current_position + velocity * dt
    Unit.set_local_position(unit, 0, final_position)
    self.velocity_network:store(velocity)
    self.velocity_current:store(velocity)
end)

-- ============================================================
-- Issue #241: decouple the local player from world-boundary safety
-- mechanics WHILE noclip is active, so free-flying past the playable
-- edge or below the map no longer yanks you out of noclip or kills you.
-- Three mechanics, five hooks, ALL gated on (_noclip_active AND the unit
-- is the local player), so they are completely inert with noclip off or
-- for any other unit:
--
--   (1) Forced LEDGE-GRAB. Both PlayerCharacterStateFalling.update
--       (falling.lua:254) and ...Catapulted.update (catapulted.lua:95)
--       call CharacterStateHelper.is_ledge_hanging(world, unit, params)
--       by direct table access (no upvalue capture), so one table hook
--       covers both; will_be_ledge_hanging covers the predictive
--       jumping/leaping path. Returning false stops the change_state
--       into "ledge_hanging" -- which is also what lerp-snaps you onto
--       the ledge (the "teleport-back" in the report).
--   (2) Authored KILL VOLUMES. PlayerUnitHealthExtension.entered_kill_volume
--       sends rpc_request_insta_kill even for the listen host. Suppress the
--       local callback before it queues/sends that request.
--   (3) "Fell out of the world" DEATH. The z < -240 check inlined in
--       both states routes through HealthSystem.suicide(self, unit) on
--       the host; suppress it for the local player. A client sends the exact
--       rpc_suicide/go-id pair instead, so the NetworkTransmit hook drops only
--       that local request before it leaves the client. No remote state is
--       needed and other players' death traffic is untouched.
--
-- Pre-flight (2026-07-13): grepped general_tweaker_dev for existing hooks
-- on these five (Class, method) pairs -- none. gt's bot code uses the
-- status-extension method get_is_ledge_hanging(), a distinct symbol, not
-- CharacterStateHelper.is_ledge_hanging.
-- ============================================================

local function _is_local_noclip_unit(unit)
    return BoundaryPolicy.should_suppress_unit_route(
        _noclip_active, unit, _local_player_unit())
end

mod:hook("CharacterStateHelper", "is_ledge_hanging", function(func, world, unit, params)
    if _is_local_noclip_unit(unit) then
        return false
    end
    return func(world, unit, params)
end)

mod:hook("CharacterStateHelper", "will_be_ledge_hanging", function(func, world, unit, params)
    if _is_local_noclip_unit(unit) then
        return false
    end
    return func(world, unit, params)
end)

mod:hook("HealthSystem", "suicide", function(func, self, unit)
    if _is_local_noclip_unit(unit) then
        _log_boundary_suppression("host out-of-bounds suicide", "z<-240 while noclipping")
        return
    end
    return func(self, unit)
end)

mod:hook("PlayerUnitHealthExtension", "entered_kill_volume", function(func, self, t)
    if _is_local_noclip_unit(self and self.unit) then
        _log_boundary_suppression("kill-volume instant death", "rpc_request_insta_kill blocked")
        return
    end
    return func(self, t)
end)

mod._gt_noclip_server_rpc_guard = function(rpc_name, ...)
    if rpc_name == "rpc_suicide" and _noclip_active then
        local go_id = ...
        local unit = _local_player_unit()
        local state = Managers.state
        local storage = state and state.unit_storage
        local local_go_id = unit and storage and storage:go_id(unit)

        if BoundaryPolicy.should_suppress_rpc(
                _noclip_active, rpc_name, go_id, local_go_id) then
            _log_boundary_suppression("client out-of-bounds suicide RPC", "local rpc_suicide blocked")
            return true
        end
    end
    return false
end

mod._gt241_boundary_suppression_wired = true
printf("[gt][noclip] issue #241: boundary-safety suppression armed (ledge-grab + kill-volume + host/client out-of-bounds death)")

-- Called from the main file's on_game_state_changed: locomotion extensions are
-- torn down across level transitions; the next player spawn comes back in
-- vanilla `script_driven` mode. Reset the active flag so a stale noclip setting
-- from the previous mission doesn't re-arm before the player has a body to fly.
mod._gt_noclip_reset_active = function()
    _noclip_active = false
end

-- Per-frame state re-assert, called from the main file's shared
-- post_spawn_reapply mod.update consumer (kept there because it also drives
-- godmode). Re-asserts the locomotion state so transient character-state
-- transitions can't drop us back into wall collision.
mod._gt_noclip_heartbeat = function()
    if not _noclip_active then return end
    local loco = _local_locomotion()
    if loco and loco.state ~= "script_driven_no_mover" then
        loco.state = "script_driven_no_mover"
    end
end

-- Shared toggle helper. `mod:command` and the VMF keybind widget both invoke
-- this through `mod.gt_noclip_toggle` so they stay in lockstep.
mod.gt_noclip_toggle = function()
    local new_val = not mod:get("noclip_enabled")
    mod:set("noclip_enabled", new_val)
    -- Explicit apply mirrors tp's command (which works in production). Belt-and-
    -- suspenders against VMF versions that don't fire on_setting_changed on
    -- programmatic mod:set() calls.
    mod._gt_apply_noclip(new_val)
    mod:echo("Noclip: " .. (new_val
        and "ON (WASD fly, Space/Ctrl up/down, Shift = boost)"
        or "OFF"))
end

mod:command("noclip", "Toggle noclip (fly through walls)", function() mod.gt_noclip_toggle() end)
