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
--    `mod.update` (_drive_free_cam) using the vanilla free-fly camera math, reading
--    RAW Keyboard/Mouse for move/look/speed (see _drive_free_cam) rather than the
--    "FreeFlight" input service - that service is starved once we unblock the devices.
--    Omits the drop-player / DOF / raycast keys. Pure "view the level".
--
--  * INPUT BLOCK -- and why we IMMEDIATELY undo it (the #307 hard-lock root cause):
--    `_enter_free_flight` calls `block_device_except_service("FreeFlight", ...)` on
--    keyboard/mouse/gamepad (:610-612), which set_blocked's EVERY input service except
--    FreeFlight. That froze the character but ALSO cut ESC, chat, VMF keybinds, the
--    checkbox and /freecam -- leaving a single raw-F8 poll as the only exit. That poll
--    empirically NEVER fired (no `deactivated` across 4 builds; users force-closed via
--    Steam). So the moment we enter, we call `device_unblock_all_services` on all three
--    devices to hand input back. We don't need the block to stop the character: the
--    `PlayerInputExtension.is_input_blocked -> true` hook below nullifies every player
--    read (player_input_extension.lua:146-157) -- the reliable freeze the old gt attempt
--    lacked. FreeFlight was the block exception and stays mapped to the devices, so the
--    camera still flies; and now ESC / keybind / checkbox / /freecam ALL work as exits,
--    with the F8 raw poll kept as one more belt-and-suspenders route.
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

-- has_world-gated world lookup (BUG_CLASSES class 32, issue 459 family). WorldManager.world()
-- FASSERTS on a missing name (world_manager.lua:111-115), and _drive_free_cam runs from
-- mods_update, which keeps ticking through StateIngame teardown -- so a nil check placed
-- AFTER a bare world() call is dead code. Every world lookup in this module routes through
-- here. No world HANDLE is ever cached in this module (resolved fresh per call from the
-- engine's own data.viewport_world_name), so no identity comparison is needed on top.
local function _live_world(name)
    local wm = Managers.world
    if not (wm and name and wm:has_world(name)) then return nil end
    return wm:world(name)
end
mod._gut_fc_live_world = _live_world   -- exported for the /gut_regression_test gate check

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

-- Drives the detached camera every frame from RAW Keyboard/Mouse input.
--
-- WHY RAW INPUT (not the "FreeFlight" input service): the vanilla camera driver reads
-- `input_manager:get_service("FreeFlight"):get("move"/"look"/...)`, but that service only
-- receives device input while free flight BLOCKS every device to it. We deliberately
-- unblock the devices on enter (so ESC/keybind/chat stay usable - the #307 hard-lock
-- fix), which starves that service = camera won't move ("no cam", reported on
-- v0.2.196-dev). Raw `Keyboard.button`/`Mouse.axis` read hardware directly and are
-- unaffected by service blocking, so the camera flies regardless. Pattern is vanilla
-- `scripts/freeflight.lua:17-60` (the engine's own raw free-fly), adapted to drive the
-- free-flight viewport camera. Quaternion/Vector3/Matrix4x4 are frame-local temporaries.
local _drive_err_logged = false
local function _drive_free_cam(dt, player, data)
    local world = _live_world(data.viewport_world_name)   -- gated: bare lookup fasserts on Leave Game
    if not world then return end
    if not ScriptWorld.has_viewport(world, data.viewport_name) then return end
    local viewport = ScriptWorld.free_flight_viewport(world, data.viewport_name)
    if not viewport then return end
    local cam = data.frustum_freeze_camera or ScriptViewport.camera(viewport)

    -- Raw device reads (see WHY above). move = (d-a, w-s, e-q); pan = mouse delta;
    -- wheel.y = speed change. All bypass the blocked FreeFlight input service.
    local pan = Mouse.axis(Mouse.axis_index("mouse")) or Vector3(0, 0, 0)
    local wheel = Mouse.axis(Mouse.axis_index("wheel")) or Vector3(0, 0, 0)
    local speed_change = Vector3.y(wheel)
    local move = Vector3(
        Keyboard.button(Keyboard.button_index("d")) - Keyboard.button(Keyboard.button_index("a")),
        Keyboard.button(Keyboard.button_index("w")) - Keyboard.button(Keyboard.button_index("s")),
        Keyboard.button(Keyboard.button_index("e")) - Keyboard.button(Keyboard.button_index("q")))

    -- speed scaling (mouse wheel); current_translation_max_speed seeded to 10 by
    -- register_player (free_flight_manager.lua:543).
    local max_speed = data.current_translation_max_speed or 10
    max_speed = math.max(max_speed + speed_change * (max_speed * 0.5), 0.01)
    data.current_translation_max_speed = max_speed

    local cm = Camera.local_pose(cam)
    local trans = Matrix4x4.translation(cm)
    Matrix4x4.set_translation(cm, Vector3(0, 0, 0))

    -- look (mouse pan is already a per-frame delta, so no dt term). rotation_speed
    -- seeded to 0.003 by register_player.
    local rot_speed = data.rotation_speed or 0.003
    local q1 = Quaternion(Vector3(0, 0, 1), -Vector3.x(pan) * rot_speed)
    local q2 = Quaternion(Matrix4x4.x(cm), -Vector3.y(pan) * rot_speed)
    local q = Quaternion.multiply(q1, q2)
    cm = Matrix4x4.multiply(cm, Matrix4x4.from_quaternion(q))

    -- move in the camera's local frame, scaled by speed (units/sec) * dt.
    local offset = Matrix4x4.transform(cm, move * (max_speed * dt))
    trans = Vector3.add(trans, offset)
    Matrix4x4.set_translation(cm, trans)
    ScriptCamera.set_local_pose(cam, cm)

    -- keep the audio listener + world observers with the camera (vanilla :709-717)
    local rot = Matrix4x4.rotation(cm)
    local wwise_world = Managers.world:wwise_world(world)
    if wwise_world then WwiseWorld.set_listener(wwise_world, 0, cm) end
    if Managers.free_flight._has_terrain and data.terrain_decoration_observer then
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
        if not (player and data and player.player_unit and _live_world(player.viewport_world_name)) then
            -- The live-world probe also covers the enter path: _enter_free_flight does its
            -- own ungated world lookup (free_flight_manager.lua:587), which would fassert
            -- in a no-world window even under our pcall.
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
        -- ROOT-CAUSE FIX for the #307 hard input lock. `_enter_free_flight` runs
        -- `block_device_except_service("FreeFlight", <device>)` on keyboard/mouse/gamepad
        -- (free_flight_manager.lua:610-612), which set_blocked's EVERY input service except
        -- FreeFlight - killing ESC, chat, VMF keybinds, the checkbox AND /freecam, so the
        -- fragile raw-F8 poll became the ONLY way out. That poll empirically never fired
        -- (no `deactivated` across 4 builds / multiple sessions; users force-closed via
        -- Steam - console-2026-07-05-18.05.37 ends at `activated` with no exit). We do NOT
        -- need that block: the is_input_blocked hook below already freezes the character
        -- (PlayerInputExtension.get nullifies every read, player_input_extension.lua:146-157;
        -- the memory note calls it "the reliable stop"). So immediately hand the devices
        -- back. FreeFlight was the block exception and stays mapped to the devices
        -- (register_input_manager, :49-51), so the camera still flies from _drive_free_cam;
        -- meanwhile ESC / keybind / checkbox / /freecam all work again as exits. Vanilla
        -- itself unblocks these exact services on exit (:642-644), so this is a safe call.
        local im = Managers.free_flight.input_manager
        if im then
            pcall(im.device_unblock_all_services, im, "keyboard")
            pcall(im.device_unblock_all_services, im, "mouse")
            pcall(im.device_unblock_all_services, im, "gamepad")
        end
        _exit_key_was_down = true   -- swallow the keypress that toggled us on
        _drive_err_logged = false   -- re-arm the one-shot drive-error diagnostic
        _freecam_active = true
        printf("[gut_dev:FC] activated (input devices unblocked; character held by is_input_blocked)")
        -- Render-state diagnostic (#307 "no cam" triage): confirm the free-flight
        -- viewport was created in the ON-SCREEN world/viewport. If base_viewport is
        -- false or the world is wrong, the detached cam renders off-screen.
        do
            local dw = _live_world(data.viewport_world_name)
            local base_ok = dw and ScriptWorld.has_viewport(dw, data.viewport_name) or false
            local ff_ok = false
            if dw then ff_ok = pcall(ScriptWorld.free_flight_viewport, dw, data.viewport_name) end
            printf("[gut_dev:FC] render-state: world=%s vp=%s base_viewport=%s ff_viewport=%s active=%s",
                tostring(data.viewport_world_name), tostring(data.viewport_name),
                tostring(base_ok), tostring(ff_ok), tostring(data.active))
        end
        -- apply() owns ALL activation feedback so every entry path (checkbox,
        -- keybind, /freecam, deferred menu-close) shows the exit routes.
        mod:echo("Free camera: ON. WASD move, mouse look, E/Q up/down, wheel speed. F8, or turn Free Camera off in the menu, to exit.")
    else
        local was_on = _freecam_active or _pending_menu_close
        _pending_menu_close = false
        if player and data and data.active then
            if _live_world(data.viewport_world_name) then
                pcall(Managers.free_flight._exit_free_flight, Managers.free_flight, player, data)
            else
                -- Class 32: the owning world is already gone, so the free-flight viewport and
                -- observers died with it -- dropping the references IS the teardown. The engine
                -- exit would fassert inside its own ungated world lookup
                -- (free_flight_manager.lua:620); its dead-world path is _clear_free_flight
                -- (:531-535, exactly what vanilla's dispatcher runs at :516-517), so run that.
                pcall(Managers.free_flight._clear_free_flight, Managers.free_flight, data)
                printf("[gut_dev:FC] skipped engine exit - free-flight world already destroyed (cleared flags instead)")
            end
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
    local ok, err = pcall(_drive_free_cam, dt, player, data)
    if not ok and not _drive_err_logged then
        _drive_err_logged = true   -- one-shot so we don't spam every frame
        printf("[gut_dev:FC] drive error (camera not moving): %s", tostring(err))
    end
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
        -- Force-exit on state transition (BUG_CLASSES class 32). While freecam is active the
        -- only event that can arrive is ("exit","StateIngame"), and it fires from
        -- GameStateMachine._change_state BEFORE the old state's on_exit teardown runs
        -- (game_state_machine.lua:17-21 -> state_ingame.lua:1939 _teardown_world) -- the last
        -- point the free-flight viewport can be released into a LIVE world. The engine's own
        -- dead-world cleanup (_update_player -> _clear_free_flight,
        -- free_flight_manager.lua:516-517) never runs for us because we leave the
        -- disable_free_flight gate up, so without this the engine slot keeps active=true with
        -- a stale world name. apply(false) resolves the world through the _live_world gate,
        -- so this is safe even if the world is somehow already gone.
        if _freecam_active then
            local ok_exit = pcall(mod._gut_apply_freecam, false)
            if not ok_exit then
                -- apply failed mid-exit: still restore what we can by hand below
                _set_third_person(_prev_third_person)
            end
            if mod:get("gut_freecam_enabled") then mod:set("gut_freecam_enabled", false) end
            printf("[gut_dev:FC] force-exited on game state change (%s %s)", tostring(status), tostring(state_name))
            -- Belt-and-suspenders: apply(false) already dropped these, but never let
            -- is_input_blocked stay true into the next state.
            _freecam_active = false
            _exit_key_was_down = false
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
