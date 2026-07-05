local mod = get_mod("gut_dev")

-- _gut_freecam.lua -- Free Camera (detached fly-cam) -- issue #307
--
-- Detaches the camera so the player can pan around and view the level; the
-- character stops responding to input and stays put. Lives under the
-- 3rd-Person Camera group in gut; toggle with the checkbox, the /freecam chat
-- command, or the keybind. EXIT is F8 (see the input-block note below).
--
-- WHY THIS SHAPE (grounded in decompiled source + two prior failed attempts):
--
--  * A previous gt_dev Free Camera (removed at gt v0.2.113-dev, 2026-07-01) used
--    the right entry point but was missing the input-block hook, so WASD bled
--    through to the character; it then reached for a locomotion "set disabled"
--    call with a nil run_func, which crashes one frame later inside the engine's
--    `update_disabled_units` loop (locomotion_templates_player.lua:323 calls
--    `extension.run_func(unit, dt, extension)` with NO nil-check). We do NOT
--    touch locomotion at all -- that whole crash class is avoided by never
--    calling set_disabled.
--
--  * The proven mechanism (from the "Photo Mode" mod, workshop-decompiled) is the
--    engine's own FreeFlightManager: `_enter_free_flight` creates an overlay
--    viewport and renders from a detached camera while the player unit keeps
--    simulating (free_flight_manager.lua:584-617); `_exit_free_flight` tears it
--    down (:619-645). We call these directly.
--
--  * We do NOT lift `GameSettingsDevelopment.disable_free_flight`. That gate is
--    checked ONLY inside `FreeFlightManager.update` (free_flight_manager.lua:64),
--    which is the vanilla dispatcher that reads F8/F9/F10 and the
--    Enter=teleport-player key. Leaving the gate up means that dispatcher never
--    runs, so none of those keys can misfire. We drive the camera ourselves from
--    `mod.update` with a trimmed copy of the vanilla `_update_free_flight` camera
--    math (move/look/speed only -- free_flight_manager.lua:655-717), omitting the
--    drop-player / DOF / raycast keys (:719+). Pure "view the level".
--
--  * INPUT BLOCK: `_enter_free_flight` calls
--    `block_device_except_service("FreeFlight", ...)` on keyboard/mouse/gamepad
--    (:610-612), routing ALL input to the FreeFlight service. That stops the
--    character (the fix the old gt attempt lacked) -- but it ALSO means chat, VMF
--    keybinds and the ESC menu can't reach the user while active. So the ONLY way
--    out is a RAW keyboard poll (Keyboard.button, which reads hardware directly,
--    bypassing the service routing). Exit key = F8. Belt-and-suspenders: we also
--    hook `PlayerInputExtension.is_input_blocked -> true` for the local player, the
--    reliable per-frame block the device-routing empirically didn't guarantee.
--
--  * TRANSITION SAFETY NET (a gap the Photo Mode mod itself has): on a world
--    teardown mid-freecam the engine routes to `_clear_free_flight` (:531), which
--    does NOT call `_exit_free_flight` -- so our exit sequence never runs and, left
--    alone, `is_input_blocked` would keep returning true into the next state =
--    frozen input. `mod.on_game_state_changed` force-resets our flag so input is
--    never left blocked across a level load.
--
-- HOOKS (pre-flight verified disjoint from the rest of gut -- whole-mod grep found
-- NO other gut hook on either class):
--   * PlayerInputExtension.is_input_blocked   (anti-bleed; return true while active)
--   * FreeFlightManager._exit_free_flight     (hook_safe; sync our flag on engine exit)
--
-- Dofile'd AFTER _gut_camera (so mod.update / on_setting_changed / on_game_state_changed
-- already exist to chain) and self-contained: it chains those callbacks
-- capture-prev / call-prev-first, the same idiom _gut_camera.lua uses.

-- ============================================================
-- Free Camera
-- ============================================================

local _freecam_active = false
local _exit_key_was_down = false
-- Set when the checkbox flips ON while a menu/view is open: activation is DEFERRED
-- until the menu closes. Entering free flight re-routes every input device to the
-- FreeFlight service (free_flight_manager.lua:610-612), so activating under an open
-- view leaves that view unresponsive to all input - the soft-lock reported 2026-07-05
-- (gut_dev 0.2.189-dev log 17:14:49-17:15:12, forced close via Steam).
local _pending_menu_close = false
-- Saved so exit restores whatever owned third_person_mode before us (the 3P camera
-- in _gut_camera.lua also drives this flag; unconditionally clearing it on freecam
-- exit would break a co-active 3P camera).
local _prev_third_person = nil
local EXIT_KEY = "f8"

local function _set_third_person(v)
    if Development._hardcoded_dev_params then
        Development._hardcoded_dev_params.third_person_mode = v
    end
end
local function _get_third_person()
    return Development._hardcoded_dev_params and Development._hardcoded_dev_params.third_person_mode
end

local function _local_player()
    local pm = Managers.player
    return pm and pm:local_player()
end

-- True while any menu/view owns the screen: a vanilla view or menu state
-- (IngameUI.menu_active, ingame_ui.lua:228) or any transitioned-in view including
-- VMF/mod views (IngameUI.current_view; vanilla treats "in a view" as the OR of the
-- two, ingame_ui.lua:765). Live instance via Managers.ui._ingame_ui (ui_manager.lua:26).
local function _menu_open()
    local iui = Managers.ui and Managers.ui._ingame_ui
    return iui and (iui.menu_active or iui.current_view ~= nil) or false
end

-- Resolve the local player + its per-player FreeFlight data slot. The slot is
-- created by FreeFlightManager.register_player on spawn (free_flight_manager.lua:537),
-- fully initialised (acceleration, current_translation_max_speed=10,
-- rotation_accumulation/current_translation_speed Vector3Boxes, dof_* etc.), so we
-- never have to init any of it. Returns nil,nil outside a mission.
local function _player_and_data()
    local ff = Managers.free_flight
    if not ff or not ff.data then return nil, nil end
    local player = _local_player()
    if not player then return nil, nil end
    local id = player:local_player_id()
    return player, ff.data[id]
end

-- Trimmed faithful copy of FreeFlightManager._update_free_flight
-- (free_flight_manager.lua:655-717): reads the FreeFlight input service for
-- move/look/speed and writes the camera pose. Deliberately OMITS the vanilla
-- drop-player-at-camera (Enter), raycast, FOV and DOF key handling at :719+ so the
-- camera is view-only. Quaternion/Vector3/Matrix4x4 values are frame-local stack
-- temporaries; the persistent accumulators live in the data slot's Vector3Boxes.
local function _drive_free_cam(dt, player, data)
    local ff = Managers.free_flight
    local world = Managers.world:world(data.viewport_world_name)
    if not world then return end
    local viewport = ScriptWorld.free_flight_viewport(world, data.viewport_name)
    if not viewport then return end
    local cam = data.frustum_freeze_camera or ScriptViewport.camera(viewport)
    local input = ff.input_manager and ff.input_manager:get_service("FreeFlight")
    if not input then return end

    -- speed scaling (mouse wheel)
    local translation_change_speed = data.current_translation_max_speed * 0.5
    local speed_change = Vector3.y(input:get("speed_change") or Vector3(0, 0, 0))
    data.current_translation_max_speed = math.max(
        data.current_translation_max_speed + speed_change * translation_change_speed, 0.01)

    local cm = Camera.local_pose(cam)
    local trans = Matrix4x4.translation(cm)
    Matrix4x4.set_translation(cm, Vector3(0, 0, 0))

    -- look (mouse), smoothed through the accumulator box
    local mouse = input:get("look")
    local rotation_accumulation = data.rotation_accumulation:unbox() + mouse
    local rotation = rotation_accumulation * math.min(dt, 1) * (player.free_flight_movement_filter_speed or 15)
    data.rotation_accumulation:store(rotation_accumulation - rotation)

    local q1 = Quaternion(Vector3(0, 0, 1), -Vector3.x(rotation) * data.rotation_speed)
    local q2 = Quaternion(Matrix4x4.x(cm), -Vector3.y(rotation) * data.rotation_speed)
    local q = Quaternion.multiply(q1, q2)
    cm = Matrix4x4.multiply(cm, Matrix4x4.from_quaternion(q))

    -- move (WASD + E/Q up/down), accelerated toward wanted speed
    local wanted_speed = input:get("move") * data.current_translation_max_speed
    local current_speed = data.current_translation_speed:unbox()
    local speed_difference = wanted_speed - current_speed
    local speed_distance = Vector3.length(speed_difference)
    local speed_difference_direction = Vector3.normalize(speed_difference)
    if speed_change ~= 0 then
        data.acceleration = (player.free_flight_acceleration_factor or 5) * Vector3.length(speed_difference)
    end
    local acceleration = data.acceleration
    local new_speed = current_speed + speed_difference_direction * math.min(speed_distance, acceleration * dt)
    data.current_translation_speed:store(new_speed)

    local rot = Matrix4x4.rotation(cm)
    local offset = (Quaternion.forward(rot) * new_speed.y
                  + Quaternion.right(rot) * new_speed.x
                  + Quaternion.up(rot) * new_speed.z) * dt
    trans = Vector3.add(trans, offset)
    Matrix4x4.set_translation(cm, trans)
    ScriptCamera.set_local_pose(cam, cm)

    -- keep the audio listener + world observers with the camera (vanilla :709-717)
    local wwise_world = Managers.world:wwise_world(world)
    if wwise_world then WwiseWorld.set_listener(wwise_world, 0, cm) end
    if ff._has_terrain and data.terrain_decoration_observer then
        TerrainDecoration.move_observer(world, data.terrain_decoration_observer, trans)
    end
    if data.scatter_system_observer then
        ScatterSystem.move_observer(World.scatter_system(world), data.scatter_system_observer, trans, rot)
    end
end

-- Enter / exit. Exposed as mod._gut_apply_freecam so on_setting_changed resolves it.
mod._gut_apply_freecam = function(enabled)
    local player, data = _player_and_data()
    if enabled then
        if not (player and data and player.player_unit) then
            mod:echo("Free camera: unavailable here (need to be in a level).")
            -- revert the setting so the checkbox reflects reality
            if mod:get("gut_freecam_enabled") then mod:set("gut_freecam_enabled", false) end
            return
        end
        if _freecam_active or data.active then return end   -- already flying
        -- MENU GATE: never enter free flight while a menu/view is open - the device
        -- re-route would cut all input to it (soft-lock class). Defer: mod.update
        -- completes the activation on the first frame after the menu closes.
        if _menu_open() then
            if not _pending_menu_close then
                _pending_menu_close = true
                printf("[gut_dev:FC] activation deferred: menu/view open")
                mod:echo("Free camera: starts when you close the menu. F8 turns it off.")
            end
            return
        end
        _pending_menu_close = false
        -- Render the 3P body so the detached camera has something to look at (free
        -- flight leaves the player unit simulating; without third_person_mode the
        -- local body renders as 1P-only and is invisible from the free cam). Save the
        -- prior value so exit restores it (the 3P camera may already own this flag).
        _prev_third_person = _get_third_person()
        _set_third_person(true)
        local ok, err = pcall(Managers.free_flight._enter_free_flight, Managers.free_flight, player, data)
        if not ok then
            mod:echo("Free camera: failed to activate (%s).", tostring(err))
            _set_third_person(_prev_third_person)
            if mod:get("gut_freecam_enabled") then mod:set("gut_freecam_enabled", false) end
            return
        end
        _exit_key_was_down = true   -- swallow the keypress that toggled us on
        _freecam_active = true
        printf("[gut_dev:FC] activated")
        -- apply() owns ALL activation feedback so every entry path (checkbox,
        -- keybind, /freecam, deferred menu-close) shows the exit key.
        mod:echo("Free camera: ON. WASD move, mouse look, E/Q up/down, wheel speed. F8 to exit.")
    else
        local was_on = _freecam_active or _pending_menu_close
        _pending_menu_close = false
        if player and data and data.active then
            pcall(Managers.free_flight._exit_free_flight, Managers.free_flight, player, data)
        end
        _set_third_person(_prev_third_person)
        _prev_third_person = nil
        _freecam_active = false
        if was_on then
            printf("[gut_dev:FC] deactivated")
            mod:echo("Free camera: OFF")
        end
    end
end

-- Raw hardware poll (bypasses the device-service routing that free flight sets up,
-- which is what lets us read the exit key at all while active). Rising-edge only.
local function _exit_key_pressed()
    local idx = Keyboard.button_index(EXIT_KEY)
    local down = idx and Keyboard.button(idx) > 0
    local pressed = down and not _exit_key_was_down
    _exit_key_was_down = down and true or false
    return pressed
end

-- Per-frame: poll the exit key, drive the camera, and self-heal if the world went
-- away underneath us. Chain mod.update (capture-prev / call-prev-first) so we never
-- clobber another gut feature's tick (same idiom as _gut_camera.lua).
local _gut_freecam_prev_update = mod.update
mod.update = function(dt)
    if _gut_freecam_prev_update then _gut_freecam_prev_update(dt) end

    -- Deferred activation: the checkbox was flipped ON inside a menu. Complete the
    -- entry on the first frame the menu is gone (setting may have been flipped back
    -- off meanwhile - then just drop the pending flag).
    if _pending_menu_close and not _freecam_active then
        if not mod:get("gut_freecam_enabled") then
            _pending_menu_close = false
        elseif not _menu_open() then
            _pending_menu_close = false
            printf("[gut_dev:FC] menu closed, completing deferred activation")
            mod._gut_apply_freecam(true)
        end
    end

    if not _freecam_active then return end

    if _exit_key_pressed() then
        mod:set("gut_freecam_enabled", false)   -- fires on_setting_changed -> apply(false)
        mod._gut_apply_freecam(false)           -- explicit, in case VMF skips the programmatic set
        return
    end

    local player, data = _player_and_data()
    if not (player and data and data.active) then
        -- world torn down / player despawned mid-freecam: reset so input isn't left blocked
        _freecam_active = false
        if mod:get("gut_freecam_enabled") then mod:set("gut_freecam_enabled", false) end
        _set_third_person(_prev_third_person)
        _prev_third_person = nil
        return
    end
    pcall(_drive_free_cam, dt, player, data)
end

-- Anti-bleed: while freecam owns the local player, block every input the character
-- reads. is_input_blocked is checked in PlayerInputExtension.get
-- (player_input_extension.lua:149) which then nullifies the value -- this is the
-- reliable stop the old gt attempt was missing. Local-player-only so remote peers
-- (husk extensions) are untouched. Pre-flight: no other gut hook on this class.
mod:hook("PlayerInputExtension", "is_input_blocked", function(func, self)
    if _freecam_active and self.player and self.player == _local_player() then
        return true
    end
    return func(self)
end)

-- Sync our flag if the engine exits free flight for any reason we didn't drive
-- (defensive: e.g. another mod, or a future path that lifts the gate). hook_safe,
-- post-callback. Pre-flight: no other gut hook on FreeFlightManager.
mod:hook_safe("FreeFlightManager", "_exit_free_flight", function(self, player, data)
    if _freecam_active then
        _freecam_active = false
        if mod:get("gut_freecam_enabled") then mod:set("gut_freecam_enabled", false) end
        _set_third_person(_prev_third_person)
        _prev_third_person = nil
    end
end)

-- Dispatch wiring: chain on_setting_changed + on_game_state_changed (capture-prev /
-- call-prev-first). Dofile'd after the main file + _gut_camera define them.
do
    local prev = mod.on_setting_changed
    mod.on_setting_changed = function(setting_id)
        if prev then prev(setting_id) end
        if setting_id == "gut_freecam_enabled" then
            mod._gut_apply_freecam(mod:get("gut_freecam_enabled"))
        end
    end
end

do
    local prev = mod.on_game_state_changed
    mod.on_game_state_changed = function(status, state_name)
        if prev then prev(status, state_name) end
        -- Transition safety net: the engine's world teardown routes to
        -- _clear_free_flight (NOT _exit_free_flight), so our exit never runs. Force
        -- the flag off here so is_input_blocked can't stay true into the next state.
        if _freecam_active then
            _freecam_active = false
            _exit_key_was_down = false
            _set_third_person(_prev_third_person)
            _prev_third_person = nil
        end
        -- A deferred activation must not survive a level change either.
        _pending_menu_close = false
    end
end

-- Shared toggle helper; /freecam and the VMF keybind both route through it.
mod.gut_freecam_toggle = function()
    local new_val = not mod:get("gut_freecam_enabled")
    mod:set("gut_freecam_enabled", new_val)
    mod._gut_apply_freecam(new_val)   -- apply() owns the ON/OFF feedback
end

mod:command("freecam", "Toggle the detached free camera (F8 to exit)", function()
    mod.gut_freecam_toggle()
end)
