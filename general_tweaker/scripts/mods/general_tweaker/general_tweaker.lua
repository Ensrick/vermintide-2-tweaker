local mod = get_mod("gt")

local MOD_VERSION = "0.2.32-alpha"

local function _write_dump(filename, lines)
    for _, line in ipairs(lines) do
        mod:info("[DUMP:%s] %s", tostring(filename), tostring(line))
    end
end

local _godmode = mod:get("godmode_enabled") or false
-- Forward declaration: _apply_godmode is defined further down (in the Godmode
-- section) but on_setting_changed (defined before it) needs to reference it.
-- Per feedback_lua_forward_reference.md, name resolution happens at function
-- compile time — without this `local` here, on_setting_changed would bind
-- _apply_godmode to a global (nil) and silently do nothing on UI toggles.
local _apply_godmode

-- Same forward-reference rule for the AI Takeover module further down. Both
-- on_game_state_changed and on_setting_changed reference these names before
-- the AI block's own `local` declarations execute; without these forward
-- declarations the closures bind to nil globals and the toggle silently no-ops
-- (the call to _ai_handle_toggle_change throws "attempt to call a nil value"
-- which VMF swallows).
local _ai_suppress_setting_callback = false
local _ai_saved_state = {}
local _ai_handle_toggle_change

-- Forward-declared so on_setting_changed (above the AI/no_enemies sections)
-- can reference the helper defined deeper in the file. Same rule as the AI
-- forward declarations — name resolution happens at function compile time, so
-- without this `local` the on_setting_changed closure would bind to a nil
-- global and the script_data flags would never flip from the VMF checkbox.
local _apply_script_data_no_enemies

-- Post-spawn re-apply timer. Set by PlayerUnitFirstPerson.extensions_ready
-- and consumed in mod.update (further down). BulldozerPlayer:spawn does
-- `assign_unit_ownership` AFTER the extensions are ready, so at extensions_ready
-- time `Managers.player:local_player().player_unit` still points at the OLD
-- (or nil) unit. Anything that needs to look up the local player unit on spawn
-- — godmode invisibility, noclip locomotion state — must defer past that gap.
local _post_spawn_reapply_timer = nil

mod:info("General Tweaker v%s loaded", MOD_VERSION)
mod:echo("General Tweaker v" .. MOD_VERSION)

-- ============================================================
-- Third-Person Camera
-- ============================================================
-- Development.set_parameter() is a no-op in release builds.
-- We write directly to the _hardcoded_dev_params table so that
-- all game systems reading Development.parameter("third_person_mode")
-- see the value (camera redirect, mesh visibility, FP guard).
--
-- The set_first_person_mode guard (player_unit_first_person.lua:907)
-- checks: override OR NOT third_person_mode OR NOT attract_mode.
-- Since attract_mode is nil, the guard always passes — inspect and
-- other systems can restore 1P even with third_person_mode set.
-- We hook set_first_person_mode to block 1P restore when tp is on.
--
-- Camera distance: the over_shoulder node in CameraSettings has
-- offset y=0.65 which is too close. We patch it to y=-2.5 for a
-- proper follow distance, and add z=0.5 for slight height offset.

local _tp_enabled = false
local _tp_reapply_timer = nil

-- Vanilla over_shoulder uses x=0.75, y=0.65, z=0 (camera_settings.lua:273-278).
-- We override y (negative pulls camera back), z (height), and x (side offset).
-- Zoom variants are scaled at fixed ratios from the main slider so the
-- transition between unzoomed / zoom / increased_zoom remains perceptually
-- consistent — full distance for the wide view, ~60% for zoom, ~40% for
-- increased_zoom.
local _camera_snapshots = nil

local function _find_camera_node(tree, name)
    if type(tree) ~= "table" then return nil end
    if tree._node and tree._node.name == name then return tree._node end
    for _, child in ipairs(tree) do
        local found = _find_camera_node(child, name)
        if found then return found end
    end
    return nil
end

-- Snapshot vanilla offsets before any mutation so on_disabled can restore.
local function _snapshot_camera_offsets()
    if _camera_snapshots or not CameraSettings or not CameraSettings.first_person then return end
    _camera_snapshots = {}
    for _, name in ipairs({ "over_shoulder", "zoom_in_third_person", "increased_zoom_in_third_person" }) do
        local node = _find_camera_node(CameraSettings.first_person, name)
        if node and node.offset_position then
            _camera_snapshots[name] = {
                x = node.offset_position.x,
                y = node.offset_position.y,
                z = node.offset_position.z,
            }
        end
    end
end

local function _patch_camera_offset()
    if not CameraSettings or not CameraSettings.first_person then return end
    _snapshot_camera_offsets()
    local distance = mod:get("tp_distance") or 3.0
    local height   = mod:get("tp_height")   or 1.0
    local side     = mod:get("tp_side_offset") or 0.8
    -- When enabled, ADS / ranged-aim no longer pulls the 3P camera in close;
    -- both zoom-in modes use the same multipliers as `over_shoulder` so the
    -- view stays at the configured distance/height regardless of zoom state.
    local no_zoom_in = mod:get("tp_disable_zoom_in")
    local zoom_dist_mul = no_zoom_in and 1.00 or 0.60
    local zoom_h_mul   = no_zoom_in and 1.00 or 0.60
    local izoom_dist_mul = no_zoom_in and 1.00 or 0.40
    local izoom_h_mul   = no_zoom_in and 1.00 or 0.60
    local function set_node(name, dist_mul, height_mul)
        local node = _find_camera_node(CameraSettings.first_person, name)
        if node and node.offset_position then
            node.offset_position.x = side
            node.offset_position.y = -distance * dist_mul
            node.offset_position.z = height * height_mul
        end
    end
    set_node("over_shoulder",                  1.00, 1.00)
    set_node("zoom_in_third_person",           zoom_dist_mul,  zoom_h_mul)
    set_node("increased_zoom_in_third_person", izoom_dist_mul, izoom_h_mul)
end

local function _restore_camera_offset()
    if not _camera_snapshots or not CameraSettings or not CameraSettings.first_person then return end
    for name, snap in pairs(_camera_snapshots) do
        local node = _find_camera_node(CameraSettings.first_person, name)
        if node and node.offset_position then
            node.offset_position.x = snap.x
            node.offset_position.y = snap.y
            node.offset_position.z = snap.z
        end
    end
end

_patch_camera_offset()

local function _apply_tp(enabled)
    _tp_enabled = enabled
    if Development._hardcoded_dev_params then
        Development._hardcoded_dev_params.third_person_mode = enabled or nil
    end
    local pm = Managers.player
    local player = pm and pm:local_player()
    if player and player.player_unit then
        local fp_ext = ScriptUnit.has_extension(player.player_unit, "first_person_system")
        if fp_ext then
            pcall(fp_ext.set_first_person_mode, fp_ext, not enabled, true)
        end
        pcall(CharacterStateHelper.change_camera_state, player, "follow")
    end
end

mod:hook("PlayerUnitFirstPerson", "set_first_person_mode", function(func, self, active, override, unarmed)
    if _tp_enabled and active and not override then
        return
    end
    return func(self, active, override, unarmed)
end)

-- CLARIFY: On player spawn we temporarily flip OFF tp (clear third_person_mode,
-- force 1P) so the FP system can finish initialization, then re-enable tp 30
-- ticks later via the timer below. Without this defer, set_first_person_mode
-- can run before extensions are wired up and leave the camera in a half-state.
mod:hook("PlayerUnitFirstPerson", "extensions_ready", function(func, self, world, unit, ...)
    local result = func(self, world, unit, ...)
    if mod:get("tp_camera_enabled") then
        _tp_enabled = false
        if Development._hardcoded_dev_params then
            Development._hardcoded_dev_params.third_person_mode = nil
        end
        pcall(self.set_first_person_mode, self, true, true)
        _tp_reapply_timer = 0.5
    end
    -- Schedule godmode/noclip re-apply too. PlayerUnitFirstPerson is the
    -- local-player FP extension (bots use PlayerBotUnitFirstPerson, husks
    -- don't have a 1P extension at all), so this only fires on the local
    -- player's own spawn. By 0.5s, BulldozerPlayer:spawn has run
    -- assign_unit_ownership and `Managers.player:local_player().player_unit`
    -- points at the new unit.
    _post_spawn_reapply_timer = 0.5
    return result
end)

-- _tp_reapply_timer is a time-based countdown (seconds). The 0.5s delay lets
-- PlayerUnitFirstPerson finish its post-extension setup before we flip the
-- third_person_mode flag again — flipping too early leaves the camera in a
-- half-initialised state.
mod.update = function(dt)
    if _tp_reapply_timer then
        _tp_reapply_timer = _tp_reapply_timer - (dt or 0)
        if _tp_reapply_timer <= 0 then
            _tp_reapply_timer = nil
            _apply_tp(true)
        end
    end
end

-- REVIEW: redundant `_apply_tp` call. `mod:set(...)` triggers
-- `on_setting_changed` (defined below), which already calls
-- `_apply_tp(mod:get("tp_camera_enabled"))`. So the explicit call here causes
-- _apply_tp to run twice with the same value. Pick one path; the
-- on_setting_changed path is sufficient.
mod:command("tp", "Toggle third-person camera", function()
    local new_val = not mod:get("tp_camera_enabled")
    mod:set("tp_camera_enabled", new_val)
    _apply_tp(new_val)
    mod:echo("Third-person: " .. (new_val and "ON" or "OFF"))
end)

-- ============================================================
-- Free Camera (detached fly-cam for inspecting the player model)
-- ============================================================
-- VT2 ships a FreeFlightManager in foundation, gated off in release
-- by `GameSettingsDevelopment.disable_free_flight = true`. We flip
-- that flag and call _enter_free_flight / _exit_free_flight directly
-- so the per-player F8-style cam works in mission.
--
-- Controls (FreeFlightKeymaps.win32): W/A/S/D move, Q/E down/up,
-- mouse look, scroll wheel = speed, +/- adjust FOV, Enter teleports
-- player to cam pos, F8 toggles off.
--
-- _enter_free_flight calls input_manager:block_device_except_service
-- which is SUPPOSED to stop WASD from reaching the Player input service
-- — empirically it doesn't, the player walks alongside the camera. We
-- belt-and-suspenders by also calling `set_disabled(true)` on the
-- player's locomotion extension, which yanks the unit out of the
-- locomotion update list entirely. Character state machine still ticks
-- (animation, etc.) but no movement can be applied.

local function _freecam_player_data()
    local ff = Managers.free_flight
    if not ff or not ff.data then return nil, nil end
    local pm = Managers.player
    local player = pm and pm:local_player()
    if not player then return nil, nil end
    local id = player:local_player_id()
    return player, ff.data[id]
end

local function _freecam_freeze_player(freeze)
    -- Lock the local player's locomotion so they can't walk while freecam moves.
    local pm = Managers.player
    local player = pm and pm:local_player()
    local unit = player and player.player_unit
    if not unit then return end
    local loco = ScriptUnit.has_extension(unit, "locomotion_system")
    if not loco then return end
    pcall(loco.set_disabled, loco, freeze, nil, nil, true)
end

local function _apply_freecam(enabled)
    if not GameSettingsDevelopment then return end
    if enabled then
        GameSettingsDevelopment.disable_free_flight = false
        local player, data = _freecam_player_data()
        if player and data and not data.active then
            -- Free flight only renders the local 3P body when third_person_mode is set;
            -- otherwise the player would be invisible from the detached cam.
            if Development._hardcoded_dev_params then
                Development._hardcoded_dev_params.third_person_mode = true
            end
            Managers.free_flight:_enter_free_flight(player, data)
            _freecam_freeze_player(true)
        end
    else
        local player, data = _freecam_player_data()
        if player and data and data.active then
            Managers.free_flight:_exit_free_flight(player, data)
        end
        _freecam_freeze_player(false)
        -- Restore the release-build gate so a stray F8 mid-fight doesn't activate the cam.
        GameSettingsDevelopment.disable_free_flight = true
    end
end

-- Sync the setting back to false when the engine itself exits free flight
-- (F8 press, level transition, cleanup). Also un-freeze the player — without
-- this, an F8-exit leaves the character with locomotion disabled and they'd
-- be stuck in place until you re-toggle freecam from the menu.
mod:hook_safe("FreeFlightManager", "_exit_free_flight", function(self, player, data)
    if mod:get("freecam_enabled") then mod:set("freecam_enabled", false) end
    _freecam_freeze_player(false)
end)

mod:command("freecam", "Toggle detached free-flight camera", function()
    local new_val = not mod:get("freecam_enabled")
    mod:set("freecam_enabled", new_val)
    mod:echo("Free camera: " .. (new_val
        and "ON (WASD move, mouse look, Q/E up/down, wheel = speed, F8 to exit)"
        or "OFF"))
end)

-- ============================================================
-- Noclip (player flies, ignores wall collision)
-- ============================================================
-- Unlike freecam (which detaches the camera and leaves the body),
-- noclip moves the PLAYER BODY through walls. Built on the engine's
-- `script_driven_no_mover` locomotion state (used by chaos-spawn-grab
-- and tentacle-grab), which teleports the unit by velocity_wanted * dt
-- each tick without touching the mover — so static geometry, props
-- and enemies are all bypassed.
--
-- Two pieces:
--   (1) Hook `update_script_driven_no_mover_movement` — when noclip is
--       on for the local player, ignore whatever velocity the character
--       state machine wrote (walking state writes ground-plane velocity,
--       falling writes gravity) and compute our own from W/A/S/D +
--       Space/Ctrl projected through the first-person camera rotation.
--       Shift applies a boost multiplier.
--   (2) Re-assert `self.state = "script_driven_no_mover"` every frame —
--       basic states (standing/walking/jumping/falling) don't touch
--       locomotion.state, but transitions into ledge-hang / ladder /
--       knockdown call `enable_script_driven_movement()` which would
--       hand us back to the wall-respecting mover update.

local _noclip_active = false

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

local function _apply_noclip(enabled)
    _noclip_active = enabled and true or false
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

-- Noclip re-arm on spawn lives in mod.update via _post_spawn_reapply_timer
-- (set by PlayerUnitFirstPerson.extensions_ready above). Don't hook
-- PlayerUnitLocomotionExtension.extensions_ready directly here — at that
-- timing `player.player_unit` isn't yet assigned (assign_unit_ownership
-- runs later in BulldozerPlayer:spawn), so `_apply_noclip` can't find
-- the new locomotion extension via _local_locomotion().

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

-- CLARIFY: `mod.update` runs each tick from VMF's main loop. We use it
-- as the heartbeat that re-asserts the locomotion state, so transient
-- character-state transitions can't drop us back into wall collision.
-- It also consumes _post_spawn_reapply_timer so godmode invisibility and
-- noclip locomotion state are re-applied after a level transition, since
-- both depend on `Managers.player:local_player().player_unit` which isn't
-- yet assigned at PlayerUnitFirstPerson.extensions_ready time.
local _orig_mod_update = mod.update
mod.update = function(dt)
    if _orig_mod_update then _orig_mod_update(dt) end
    if _post_spawn_reapply_timer then
        _post_spawn_reapply_timer = _post_spawn_reapply_timer - (dt or 0)
        if _post_spawn_reapply_timer <= 0 then
            _post_spawn_reapply_timer = nil
            -- Use the forward-declared `_apply_godmode` (line 17) — calling
            -- `_set_local_player_invisible` directly would be a forward-ref
            -- bug since it's defined far below this closure's parse point.
            if mod:get("noclip_enabled") then _apply_noclip(true) end
            if _godmode then _apply_godmode(true) end
        end
    end
    if _noclip_active then
        local loco = _local_locomotion()
        if loco and loco.state ~= "script_driven_no_mover" then
            loco.state = "script_driven_no_mover"
        end
    end
end

mod:command("noclip", "Toggle noclip (fly through walls)", function()
    local new_val = not mod:get("noclip_enabled")
    mod:set("noclip_enabled", new_val)
    -- Explicit apply mirrors tp's command (which works in production). Belt-and-
    -- suspenders against VMF versions that don't fire on_setting_changed on
    -- programmatic mod:set() calls.
    _apply_noclip(new_val)
    mod:echo("Noclip: " .. (new_val
        and "ON (WASD fly, Space/Ctrl up/down, Shift = boost)"
        or "OFF"))
end)

-- ============================================================
-- Keep Menus in Missions (inventory, talents, achievements, etc.)
-- ============================================================
-- The keep's menu hotkeys (I=inventory, H=hero, M=map, O=achievements,
-- C=loot, K=weave forge, J=weave play — all rebindable) feed into
-- `IngameUI.handle_menu_hotkeys`, which is only called with
-- `hotkeys_enabled = true` when `is_in_inn` is true. We hook the
-- function and force-flip the flag during missions so whatever key
-- the player has bound to each hotkey opens its menu in-mission too.
--
-- Three patches are needed:
--   (1) InventorySettings.inventory_loadout_access_supported_game_modes —
--       hero_view.lua:323 early-returns on adventure/deus and the loadout
--       panel never inits without this.
--   (2) IngameUI.handle_menu_hotkeys — flip `hotkeys_enabled` to true so
--       the I/H/M/O/C hotkeys actually fire transitions during a mission.
--   (3) menu_layouts.in_game.{alone,host,client} — adds an "Open Inventory"
--       entry to the ESC menu as a fallback for players who don't recall
--       the hotkey.
-- The legacy memory entry blamed `game_mode:menu_access_allowed_in_state()` in ingame_ui.lua,
-- but that method only exists on GameModeVersus and doesn't gate adventure/deus.
local _INVENTORY_BUTTON_ENTRY = {
    display_name = "interact_open_inventory_chest",
    fade = true,
    requires_player_unit = true,
    transition = "hero_view_force",
    transition_state = "overview",
}

local function _get_in_game_layouts()
    -- ingame_view_menu_layout is local_require'd, so its return table lives in
    -- package.loaded. Mutating that shared table affects the layouts seen by
    -- subsequently-created IngameView instances.
    local pkg = package and package.loaded
    local defs = pkg and pkg["scripts/ui/views/ingame_view_menu_layout"]
    return defs and defs.menu_layouts and defs.menu_layouts.in_game
end

local function _has_inventory_entry(layout)
    if type(layout) ~= "table" then return false end
    for _, entry in ipairs(layout) do
        if entry and entry.display_name == _INVENTORY_BUTTON_ENTRY.display_name then
            return true
        end
    end
    return false
end

local function _patch_in_game_menu(enabled)
    local in_game = _get_in_game_layouts()
    if not in_game then return end
    for _, key in ipairs({ "alone", "host", "client" }) do
        local layout = in_game[key]
        if type(layout) == "table" then
            local has = _has_inventory_entry(layout)
            if enabled and not has then
                -- Insert just before "options_menu_button_name" (slot 2 in vanilla in_game
                -- layouts) so the order matches the lobby layout: Return, Inventory, Options...
                table.insert(layout, 2, table.clone(_INVENTORY_BUTTON_ENTRY))
            elseif (not enabled) and has then
                for i = #layout, 1, -1 do
                    if layout[i] and layout[i].display_name == _INVENTORY_BUTTON_ENTRY.display_name then
                        table.remove(layout, i)
                    end
                end
            end
        end
    end
end

local function _patch_inventory_access()
    local enabled = mod:get("mission_inventory_enabled") and true or false
    if InventorySettings then
        local modes = InventorySettings.inventory_loadout_access_supported_game_modes
        if modes then
            modes.adventure = enabled or nil
            modes.survival  = enabled or nil
            modes.deus      = enabled or nil
        end
    end
    _patch_in_game_menu(enabled)
end

_patch_inventory_access()

-- ingame_ui.lua:660 calls handle_menu_hotkeys with
-- `enable_hotkeys = is_in_inn and not disable_ingame_ui and not in_score_screen`.
-- Force the `hotkeys_enabled` arg true so the keep hotkeys (whatever the
-- player has them bound to) fire during missions too. The function still
-- bails on a missing player_unit, score-screen, or pending transition,
-- so end-of-level and respawn states remain protected.
mod:hook("IngameUI", "handle_menu_hotkeys", function(func, self, dt, input_service, hotkeys_enabled, menu_active)
    if mod:get("mission_inventory_enabled") then
        hotkeys_enabled = true
    end
    return func(self, dt, input_service, hotkeys_enabled, menu_active)
end)

-- CLARIFY: tp is forcibly cleared on every state change (level transition,
-- etc.) because the engine reinitializes the FP system. The
-- PlayerUnitFirstPerson.extensions_ready hook above will re-arm tp on the
-- next player spawn if tp_camera_enabled is on. _patch_inventory_access is
-- re-applied here in case InventorySettings was reloaded.
mod.on_game_state_changed = function(status, state_name)
    _tp_enabled = false
    if Development._hardcoded_dev_params then
        Development._hardcoded_dev_params.third_person_mode = nil
    end
    -- Locomotion extensions are torn down across level transitions; the
    -- next player spawn comes back in vanilla `script_driven` mode. Reset
    -- the active flag so a stale noclip setting from the previous mission
    -- doesn't re-arm before the player has a body to fly.
    _noclip_active = false
    _patch_inventory_access()
    -- AI takeover is a per-run intent — the saved state on the host doesn't
    -- survive a level/state change cleanly, and persisting the checkbox would
    -- show "on" across runs where no swap actually happened. Suppress the
    -- callback because we don't want to fire an RPC swap-back when leaving.
    if mod:get("ai_takeover_enabled") then
        _ai_suppress_setting_callback = true
        mod:set("ai_takeover_enabled", false)
        _ai_suppress_setting_callback = false
    end
    -- Clear host-side saved state too — it's keyed on peer_id which may
    -- not survive a session/lobby change.
    _ai_saved_state = {}
    -- Vanilla wipes the engine time scale on level transition. Re-apply the
    -- user's slider value if it differs from normal (13 = 1.0x). Also clear
    -- the pause flag so the toggle remembers we're now unpaused.
    _pause_active = false
    if status == "enter" and state_name == "StateIngame" then
        local v = mod:get("time_scale_value")
        if v and v ~= 13 then
            local debug_mgr = Managers.state and Managers.state.debug
            if debug_mgr and debug_mgr.set_time_scale then
                debug_mgr:set_time_scale(v)
            end
        end
    end
end

mod.on_setting_changed = function(setting_id)
    if setting_id == "mission_inventory_enabled" then
        _patch_inventory_access()
    elseif setting_id == "tp_camera_enabled" then
        _apply_tp(mod:get("tp_camera_enabled"))
    elseif setting_id == "godmode_enabled" then
        _apply_godmode(mod:get("godmode_enabled") or false)
    elseif setting_id == "tp_distance" or setting_id == "tp_height" or setting_id == "tp_side_offset" or setting_id == "tp_disable_zoom_in" then
        _patch_camera_offset()
    elseif setting_id == "freecam_enabled" then
        _apply_freecam(mod:get("freecam_enabled"))
    elseif setting_id == "noclip_enabled" then
        _apply_noclip(mod:get("noclip_enabled"))
    elseif setting_id == "skip_intro_enabled" then
        _apply_skip_intro(mod:get("skip_intro_enabled"))
        mod:echo("Skip intro: " .. (mod:get("skip_intro_enabled") and "ON" or "OFF") .. " (takes effect on next game launch).")
    elseif setting_id == "disable_enemy_spawns" then
        _apply_script_data_no_enemies(mod:get("disable_enemy_spawns"))
    elseif setting_id == "time_scale_value" then
        mod.gt_time_apply()
    elseif setting_id == "base_crit_chance" then
        mod.gt_apply_crit_chance()
    elseif setting_id == "movement_speed" then
        mod.gt_apply_move_speed()
    elseif setting_id == "ai_takeover_enabled" then
        if _ai_suppress_setting_callback then return end
        local want_bot = mod:get("ai_takeover_enabled") and true or false
        local ok, err = _ai_handle_toggle_change(want_bot)
        if not ok then
            _ai_suppress_setting_callback = true
            mod:set("ai_takeover_enabled", not want_bot)
            _ai_suppress_setting_callback = false
            mod:echo("AI toggle: " .. err)
        else
            mod:echo("AI " .. (want_bot and "ON" or "OFF") .. " (requested from host).")
        end
    end
end

mod.on_disabled = function()
    _restore_camera_offset()
end

-- ============================================================
-- Game Glossary Dump
-- ============================================================

mod:command("dump_glossary", "Dump localized names for heroes, careers, and weapons to log", function()
    if not SPProfiles then
        mod:echo("SPProfiles not loaded (load a level first).")
        return
    end

    local lines = {}
    local function add(line)
        lines[#lines + 1] = line
    end

    local function safe_localize(key)
        if not key then return "?" end
        local ok, result = pcall(Localize, key)
        return ok and result or key
    end

    add("=== HEROES & CAREERS ===")
    for _, profile in ipairs(SPProfiles) do
        local hero_key = profile.display_name
        if hero_key == "empire_soldier_tutorial" then goto continue_hero end
        local hero_name = safe_localize(profile.ingame_display_name or hero_key)
        add(string.format("HERO  %-25s  %s", hero_key, hero_name))
        if profile.careers then
            for _, career in ipairs(profile.careers) do
                local career_key = career.display_name or career.name
                local career_name = safe_localize(career_key)
                add(string.format("  CAREER  %-23s  %s", career_key, career_name))
            end
        end
        ::continue_hero::
    end

    add("")
    add("=== WEAPONS ===")
    if ItemMasterList then
        local weapons = {}
        for key, item in pairs(ItemMasterList) do
            local st = item.slot_type
            if st == "melee" or st == "ranged" then
                local name = item.display_name and safe_localize(item.display_name) or "?"
                local wield = "none"
                if item.can_wield and #item.can_wield > 0 then
                    wield = table.concat(item.can_wield, ", ")
                end
                weapons[#weapons + 1] = {
                    key = key,
                    slot = st,
                    name = name,
                    careers = wield,
                    template = item.template or "",
                }
            end
        end
        table.sort(weapons, function(a, b)
            if a.slot ~= b.slot then return a.slot < b.slot end
            return a.key < b.key
        end)

        local cur_slot = nil
        for _, w in ipairs(weapons) do
            if w.slot ~= cur_slot then
                cur_slot = w.slot
                add(string.format("--- %s ---", cur_slot:upper()))
            end
            add(string.format("  %-45s  %-30s  can_wield=[%s]", w.key, w.name, w.careers))
        end

        add("")
        add(string.format("Total: %d weapons", #weapons))
    else
        add("ItemMasterList not loaded.")
    end

    _write_dump("glossary.txt", lines)
    mod:echo(string.format("dump_glossary: %d lines written to log", #lines))
end)

-- ============================================================
-- Cosmetic / Item Dump Commands
-- ============================================================

mod:command("dump_cosmetics", "Dump all hats, skins, and frames from ItemMasterList to log", function(filter)
    if not ItemMasterList then
        mod:echo("ItemMasterList not loaded (load a level first).")
        return
    end

    local slot_types = { hat = {}, skin = {}, frame = {} }
    for key, item in pairs(ItemMasterList) do
        local st = item.slot_type
        if slot_types[st] then
            local wield = item.can_wield
            local careers = "none"
            if wield and #wield > 0 then
                careers = table.concat(wield, ", ")
            end
            if not filter or key:find(filter, 1, true) or careers:find(filter, 1, true) then
                -- REVIEW: `icon` is captured but never written to output (the
                -- inner formatter below only uses key + careers). Remove this
                -- field or include it in the dump line.
                slot_types[st][#slot_types[st] + 1] = {
                    key = key,
                    careers = careers,
                    icon = item.inventory_icon or "?",
                }
            end
        end
    end

    local total = 0
    local lines = {}
    for slot_type, items in pairs(slot_types) do
        table.sort(items, function(a, b) return a.key < b.key end)
        local header = string.format("=== %s (%d items) ===", slot_type:upper(), #items)
        mod:echo(header)
        lines[#lines + 1] = header
        for _, item in ipairs(items) do
            local line = string.format("  %-50s  can_wield=[%s]", item.key, item.careers)
            mod:echo(line)
            lines[#lines + 1] = line
            total = total + 1
        end
    end

    local summary = string.format("dump_cosmetics: %d total (%d hats, %d skins, %d frames)",
        total, #slot_types.hat, #slot_types.skin, #slot_types.frame)
    mod:echo(summary)
    lines[#lines + 1] = summary
    _write_dump("cosmetics.txt", lines)
end)

-- ============================================================
-- Unstuck (teleport to nearest living teammate)
-- ============================================================

mod:command("unstuck", "Teleport to nearest living teammate", function()
    local pm = Managers.player
    if not pm then mod:echo("Not in a level.") return end
    local player = pm:local_player()
    if not player then mod:echo("No local player.") return end
    local unit = player.player_unit
    if not unit then mod:echo("No player unit (dead?).") return end

    local target_pos = nil
    for _, p in pairs(pm:players()) do
        if p ~= player and p.player_unit and HEALTH_ALIVE[p.player_unit] then
            target_pos = Unit.local_position(p.player_unit, 0)
            break
        end
    end

    if target_pos then
        local mover = Unit.mover(unit)
        if mover then
            Mover.set_position(mover, target_pos + Vector3(0.5, 0, 0))
        end
        mod:echo("Unstuck!")
    else
        mod:echo("No living teammate found.")
    end
end)

-- ============================================================
-- Godmode
-- ============================================================

-- Invisibility: use the engine's own canonical signal so AI perception treats us as
-- "skip this target" (perception_utils.lua:381 explicitly checks status_ext:is_invisible()).
-- `reason = "gt_godmode"` namespaces our flag so it doesn't clobber other invisibility
-- sources (Shade's Shadowfall ult, Pact Sworn ghost mode, etc.).
local _GODMODE_INVIS_REASON = "gt_godmode"

local function _set_local_player_invisible(invisible)
    local pm = Managers.player
    local player = pm and pm:local_player()
    local unit = player and player.player_unit
    if not unit then return end
    local status_ext = ScriptUnit.has_extension(unit, "status_system")
    if not status_ext or not status_ext.set_invisible then return end
    -- skip_third_person=false → fade the 3P body so user has a visual cue godmode is on.
    -- 1P weapon arms are unaffected (they're a separate unit), so first-person view stays normal.
    pcall(status_ext.set_invisible, status_ext, invisible, false, _GODMODE_INVIS_REASON)
end

-- NOTE: NOT `local function _apply_godmode(...)` — the local was forward-declared
-- at the top of the file so on_setting_changed can reference it. Re-declaring
-- local here would shadow the forward decl and reintroduce the forward-ref bug.
_apply_godmode = function(on)
    _godmode = on and true or false
    _set_local_player_invisible(_godmode)
end

mod:command("god", "Toggle godmode (invincibility + invisibility to enemies)", function()
    local new_val = not _godmode
    mod:set("godmode_enabled", new_val)
    -- Belt-and-suspenders apply in case on_setting_changed doesn't fire on programmatic set.
    _apply_godmode(new_val)
    mod:echo("Godmode " .. (new_val and "ON" or "OFF"))
end)

-- Godmode invisibility re-arm on spawn lives in mod.update via
-- _post_spawn_reapply_timer (set by PlayerUnitFirstPerson.extensions_ready
-- above). Don't hook GenericStatusExtension.extensions_ready here — that
-- check (`player.player_unit ~= unit`) is unreliable at extension-ready
-- timing because BulldozerPlayer:spawn calls assign_unit_ownership AFTER
-- extensions have already been wired up, so player.player_unit still
-- points at the OLD (or nil) unit and the check always early-returns.

-- Both DamageUtils paths must be blocked for full invincibility:
--   * add_damage_network         — used by direct damage sources (most attacks)
--   * add_damage_network_player  — used by player-vs-player damage profiles
--                                  (area effects, certain weapon profiles)
-- Both are static functions (called with `.`), so the hook signatures
-- intentionally omit `self`.
local function _is_local_player_unit(unit)
    local pm = Managers.player
    local player = pm and pm:local_player()
    return player and player.player_unit == unit
end

-- Block fall damage at the source on the local player when godmode is on.
-- The server-side `add_damage_network` hook below covers the host-self case,
-- but NOT the client-self case: fall damage RPCs from a client get processed
-- on the host where `_is_local_player_unit(attacked_unit)` returns false for
-- a remote-player's unit. Setting `ignore_next_fall_damage` on the client's
-- own status extension before `update_falling` checks the flag prevents the
-- RPC from being sent in the first place — works as host AND client.
mod:hook("GenericStatusExtension", "update_falling", function(func, self, t)
    if _godmode and _is_local_player_unit(self.unit) then
        self.ignore_next_fall_damage = true
    end
    return func(self, t)
end)

mod:hook("DamageUtils", "add_damage_network", function(func, attacked_unit, ...)
    if _godmode and _is_local_player_unit(attacked_unit) then return 0 end
    return func(attacked_unit, ...)
end)

mod:hook("DamageUtils", "add_damage_network_player", function(func, damage_profile, target_index, power_level, attacked_unit, ...)
    if _godmode and _is_local_player_unit(attacked_unit) then return 0 end
    return func(damage_profile, target_index, power_level, attacked_unit, ...)
end)

-- Block disabler-state transitions on the local player while godmode is on.
-- The DamageUtils hooks above stop hp damage but disablers (packmaster hook,
-- pounce, chaos-spawn / corruptor / tentacle grabs, hanging cage) bypass the
-- damage pipeline and transition the character state machine directly. To
-- catch all of them in one place we hook GenericStateMachine.change_state
-- (the chokepoint every csm:change_state call funnels through) and drop the
-- transition before the new state's on_enter runs.
--
-- Set of states we treat as "disabled":
--   pounced_down              — gutter runner / assassin pin
--   grabbed_by_pack_master    — hook drag
--   grabbed_by_chaos_spawn    — chaos spawn grab
--   grabbed_by_corruptor      — corruptor grab
--   grabbed_by_tentacle       — beastman bestigor tentacle, etc.
--   in_hanging_cage           — Citadel of Eternity hanging cage objective
--
-- NOT blocked (these are normal gameplay states even with godmode):
--   stunned / staggered, ledge_hanging, overpowered, knocked_down, dead.
local _DISABLER_STATES = {
    pounced_down           = true,
    grabbed_by_pack_master = true,
    grabbed_by_chaos_spawn = true,
    grabbed_by_corruptor   = true,
    grabbed_by_tentacle    = true,
    in_hanging_cage        = true,
}

mod:hook("GenericStateMachine", "change_state", function(func, self, state_next, state_next_params)
    if _godmode and _DISABLER_STATES[state_next] and _is_local_player_unit(self.unit) then
        return
    end
    return func(self, state_next, state_next_params)
end)

-- ============================================================
-- Disable Enemy Spawns
-- ============================================================
-- Every enemy unit in VT2 — hordes, specials, bosses, patrols, and the
-- pre-placed level-load spawns — funnels through ConflictDirector's two
-- public entry points: spawn_queued_unit (the deferred queue used by the
-- pacing system) and spawn_unit_immediate (synchronous, used by terror
-- events and some scripted triggers). Hook both and refuse when the
-- setting is on.
--
-- Existing enemies are NOT despawned — refusing the spawn affects future
-- enemies only. Pair with `gt god` if you want existing enemies to ignore
-- you while you reach a cleaner area.

mod:hook("ConflictDirector", "spawn_queued_unit", function(func, self, ...)
    if mod:get("disable_enemy_spawns") then return end
    return func(self, ...)
end)

mod:hook("ConflictDirector", "spawn_unit_immediate", function(func, self, ...)
    if mod:get("disable_enemy_spawns") then return nil, nil end
    return func(self, ...)
end)

-- Belt-and-suspenders: the two ConflictDirector hooks above catch every spawn
-- *call*, but Janoti's "Hacks" also flips a fuller set of `script_data.ai_*`
-- flags that abort earlier in the pacing/intervention pipelines so the spawner
-- doesn't even queue the work. Mirror that set in sync with the VMF toggle.
-- Per `feedback_redundant_safeguards_ok` redundancy is welcome here — the cost
-- is a couple of boolean writes per toggle and the missed-path failure (an
-- enemy slipping through) is silent.
local _AI_SPAWN_FLAGS = {
    "ai_mini_patrol_disabled",
    "ai_critter_spawning_disabled",
    "ai_horde_spawning_disabled",
    "ai_roaming_spawning_disabled",
    "ai_boss_spawning_disabled",
    "ai_rush_intervention_disabled",
    "ai_specials_spawning_disabled",
    "ai_pacing_disabled",
    "ai_outside_navmesh_intervention_disabled",
}

_apply_script_data_no_enemies = function(enabled)
    script_data = script_data or {}
    for _, name in ipairs(_AI_SPAWN_FLAGS) do
        script_data[name] = enabled or nil
    end
end

_apply_script_data_no_enemies(mod:get("disable_enemy_spawns"))

mod:command("no_enemies", "Toggle blocking all enemy spawns", function()
    local new_val = not mod:get("disable_enemy_spawns")
    mod:set("disable_enemy_spawns", new_val)
    _apply_script_data_no_enemies(new_val)
    mod:echo("Enemy spawns: " .. (new_val and "BLOCKED" or "normal"))
end)

-- ============================================================
-- Friendly Fire Toggle
-- ============================================================
-- On Champion+, ranged FF is on by default. Hook the two gate
-- functions that everything else calls through to suppress it.

mod:hook("DamageUtils", "allow_friendly_fire_ranged", function(func, ...)
    if mod:get("disable_friendly_fire") then return false end
    return func(...)
end)

mod:hook("DamageUtils", "allow_friendly_fire_melee", function(func, ...)
    if mod:get("disable_friendly_fire") then return false end
    return func(...)
end)

-- ============================================================
-- Level Control (win / fail / restart / kill_bots / die / fix_sound)
-- ============================================================
-- All five commands also have keybind widgets in the Level Control settings
-- group; VMF's `keybind_type = "function_call"` resolves the bound function via
-- the function_name string against the mod table, so every callable must live
-- on `mod.` (not just a local). The keep-guards mirror Janoti's Hacks mod:
-- complete/fail/restart all no-op in the inn with a friendly echo, so a
-- mis-press while sorting loadout doesn't accidentally yank you out of the
-- keep state machine.

mod.gt_win_level = function()
    if DamageUtils and DamageUtils.is_in_inn then
        mod:echo("Can't win in the keep.")
        return
    end
    if Managers.state and Managers.state.game_mode then
        Managers.state.game_mode:complete_level()
    else
        mod:echo("No active game mode.")
    end
end

mod.gt_fail_level = function()
    if DamageUtils and DamageUtils.is_in_inn then
        mod:echo("Can't fail in the keep.")
        return
    end
    if Managers.state and Managers.state.game_mode then
        Managers.state.game_mode:fail_level()
    else
        mod:echo("No active game mode.")
    end
end

mod.gt_restart_level = function()
    if DamageUtils and DamageUtils.is_in_inn then
        mod:echo("Can't restart in the keep.")
        return
    end
    if Managers.state and Managers.state.game_mode then
        Managers.state.game_mode:retry_level()
    else
        mod:echo("No active game mode.")
    end
end

-- Mirrors Hacks's EAC-secure guard: only allowed pre-round on official servers,
-- unrestricted on untrusted (modded) realm. Vanilla bot_status_extension.set_dead
-- handles the actual cleanup; we just iterate Managers.player:bots().
mod.gt_kill_bots = function()
    if EAC and EAC.state and EAC.state() ~= "untrusted" then
        local gm = Managers.state and Managers.state.game_mode
        if gm and gm.is_round_started and gm:is_round_started() then
            mod:echo("Bots may only be killed at the start of the map on official realm.")
            return
        end
    end
    local bots = Managers.player and Managers.player:bots() or {}
    local killed = 0
    for _, bot in ipairs(bots) do
        local unit = bot.player_unit
        if unit and Unit.alive(unit) then
            local status_ext = ScriptUnit.has_extension(unit, "status_system")
            if status_ext and not status_ext:is_ready_for_assisted_respawn() then
                status_ext:set_dead(true)
                killed = killed + 1
            end
        end
    end
    mod:echo(string.format("Killed %d bot(s).", killed))
end

mod.gt_die = function()
    if DamageUtils and DamageUtils.is_in_inn then
        mod:echo("Can't die in the keep.")
        return
    end
    local local_player = Managers.player and Managers.player:local_player()
    local unit = local_player and local_player.player_unit
    if not (unit and Unit.alive(unit)) then
        mod:echo("No local player unit.")
        return
    end
    local death_system = Managers.state.entity:system("death_system")
    death_system:kill_unit(unit, {})
end

-- Restart-in-storm leaves a vortex SFX looping; canonical fix is to fire the
-- "false" event for the same sound which un-mutes/clears the wwise state.
mod.gt_fix_sound = function()
    local gm = Managers.state and Managers.state.game_mode
    local level_key = gm and gm._level_key
    if level_key and string.find(level_key, "inn_level") then
        mod:echo("Can't fix sound in the keep — must be in a mission.")
        return
    end
    local local_player = Managers.player and Managers.player:local_player()
    local unit = local_player and local_player.player_unit
    if not (unit and Unit.alive(unit)) then
        mod:echo("No local player unit.")
        return
    end
    local fp_ext = ScriptUnit.has_extension(unit, "first_person_system")
    if fp_ext and fp_ext.play_hud_sound_event then
        fp_ext:play_hud_sound_event("sfx_player_in_vortex_false")
        mod:echo("Vortex sound stopped.")
    end
end

-- Names are gt-prefixed to avoid colliding with Janoti's "Hacks" mod which
-- also registers `win` / `fail` / `restart` / `kill_bots` / `die` (and others
-- below). VMF only allows one registration per global slot; whichever mod
-- loads first wins it and the other's registration is silently dropped, so
-- coexistence requires unique names.
mod:command("gt_win",       "Complete the current map",           function() mod.gt_win_level()     end)
mod:command("gt_fail",      "Fail the current map",               function() mod.gt_fail_level()    end)
mod:command("gt_restart",   "Restart the current map",            function() mod.gt_restart_level() end)
mod:command("gt_killbots",  "Kill all bots (pre-round on EAC-secure realm only)", function() mod.gt_kill_bots() end)
mod:command("gt_die",       "Kill your character",                function() mod.gt_die()           end)
mod:command("fix_sound",    "Stop the looping vortex SFX bug (post-restart in a storm)", function() mod.gt_fix_sound() end)

-- ============================================================
-- Duplicate Careers
-- ============================================================

mod:hook("ProfileSynchronizer", "get_profile_index_reservation", function(func, self, party_id, profile_index)
    if mod:get("allow_duplicate_careers") then return nil, nil end
    return func(self, party_id, profile_index)
end)

mod:hook("ProfileSynchronizer", "try_reserve_profile_for_peer", function(func, self, party_id, peer_id, profile_index, career_index)
    local result = func(self, party_id, peer_id, profile_index, career_index)
    if result then return true end
    if mod:get("allow_duplicate_careers") then return true end
    return false
end)

-- CLARIFY: `is_free_in_lobby` is a STATIC function (no `self` arg — see
-- profile_synchronizer.lua:860). Hook signature intentionally omits self.
mod:hook("ProfileSynchronizer", "is_free_in_lobby", function(func, profile_index, lobby_data, optional_party_id)
    if mod:get("allow_duplicate_careers") then return true end
    return func(profile_index, lobby_data, optional_party_id)
end)

-- ============================================================
-- Item Dump Commands
-- ============================================================

mod:command("dump_items_by_slot", "Dump all ItemMasterList slot_type values and counts", function()
    if not ItemMasterList then
        mod:echo("ItemMasterList not loaded (load a level first).")
        return
    end

    local counts = {}
    for key, item in pairs(ItemMasterList) do
        local st = item.slot_type or "nil"
        counts[st] = (counts[st] or 0) + 1
    end

    local sorted = {}
    for st, count in pairs(counts) do
        sorted[#sorted + 1] = { slot_type = st, count = count }
    end
    table.sort(sorted, function(a, b) return a.count > b.count end)

    local lines = { "=== ItemMasterList slot_type counts ===" }
    mod:echo(lines[1])
    for _, entry in ipairs(sorted) do
        local line = string.format("  %-30s %d items", entry.slot_type, entry.count)
        mod:echo(line)
        lines[#lines + 1] = line
    end
    _write_dump("items_by_slot.txt", lines)
end)

-- ============================================================
-- Skip Intro Splash Screens
-- ============================================================
-- StateSplashScreen.on_enter (state_splash_screen.lua:92-110) checks a set of
-- Development.parameter flags including "skip_splash" — if any are set,
-- self._skip_splash = true and the entire splash sequence is bypassed.
-- Same mechanism as the "-skip-splash" launch arg. We write the flag into
-- Development._hardcoded_dev_params (Development.set_parameter is a no-op in
-- release) at mod load time, which is BEFORE StateSplashScreen runs, so the
-- check on line 105 succeeds and the splash is skipped on this boot too.
--
-- Changing the setting mid-session has no immediate effect — the splash for
-- the current boot already ran. The dev param is still updated so the next
-- boot reflects the latest setting.

local function _apply_skip_intro(enabled)
    if Development._hardcoded_dev_params then
        Development._hardcoded_dev_params.skip_splash = enabled and true or nil
    end
end

_apply_skip_intro(mod:get("skip_intro_enabled"))

-- ============================================================
-- AI Toggle (hand off control to a bot)
-- ============================================================
-- VT2 has no hot-swap path between human and bot units — they use different
-- go_types with incompatible extension stacks (PlayerInputExtension vs
-- PlayerBotInput, GenericCharacterStateMachineExtension vs PlayerBotBase,
-- etc.). So toggling means despawn-human + add-bot, or remove-bot +
-- re-add-human. Both halves of the dance exist in vanilla and we compose
-- them: see GameModeBase._add_bot_to_party / _remove_bot_instant and
-- GameModeAdventure.player_entered_game_session.
--
-- Server-driven: only the host can perform the swap (ProfileSynchronizer
-- and PartyManager APIs assert is_server). Clients send a VMF network
-- request and the host validates + executes.
--
-- v1 scope:
--   * client (remote peer) self-toggle: supported
--   * host self-toggle: refused — destroying the local Player object mid-
--     mission would tear down camera/HUD/input bindings that aren't trivial
--     to recreate
--   * versus / keep: refused (no hero bot AI / no spawning)

local _AI_RPC = "gt_ai_toggle_request"
-- _ai_saved_state and _ai_suppress_setting_callback are forward-declared at
-- the top of the file (on_game_state_changed / on_setting_changed reference
-- them before this point). Assign here, do NOT redeclare with `local`, or the
-- early callbacks would still bind to nil globals.

local function _ai_state_key(peer_id, local_player_id)
    return tostring(peer_id) .. ":" .. tostring(local_player_id)
end

local function _ai_game_mode_key()
    local gm = Managers.state and Managers.state.game_mode
    if not (gm and gm.game_mode) then return nil end
    local mode = gm:game_mode()
    if not (mode and mode.settings) then return nil end
    return mode:settings().key
end

local function _ai_can_swap_in_current_mode()
    local key = _ai_game_mode_key()
    if not key then return false, "no active game mode" end
    if key:find("versus") or key:find("_vs") then
        return false, "versus is not supported (heroes have no bot AI)"
    end
    if key == "inn" or key == "inn_deus" or key:find("^inn") then
        return false, "must be in a mission"
    end
    return true
end

local function _ai_find_bot_in_slot(party_id, slot_id)
    local pm = Managers.player
    local bots = pm and pm:bots() or {}
    for _, bot in ipairs(bots) do
        local bp = bot:network_id()
        local bl = bot:local_player_id()
        local status = Managers.party and Managers.party:get_player_status(bp, bl)
        if status and status.party_id == party_id and status.slot_id == slot_id then
            return bot
        end
    end
    return nil
end

local function _ai_swap_human_to_bot(peer_id, local_player_id)
    local pm = Managers.player
    if not pm.is_server then return false, "must run on host" end
    local player = pm:player(peer_id, local_player_id)
    if not player then return false, "player not found" end
    if player.bot_player then return false, "already a bot" end

    local status = Managers.party:get_player_status(peer_id, local_player_id)
    if not (status and status.party_id and status.slot_id) then
        return false, "no party slot"
    end
    local party_id = status.party_id
    local slot_id = status.slot_id
    local profile_synchronizer = pm.network_manager and pm.network_manager.profile_synchronizer
    if not profile_synchronizer then return false, "no profile_synchronizer" end
    local profile_index, career_index = profile_synchronizer:profile_by_peer(peer_id, local_player_id)
    if not (profile_index and career_index) then
        return false, "no profile/career"
    end

    -- Save enough metadata to recreate the human Player on toggle-back. For
    -- a remote (client) player we need peer/clan/account; for the host's
    -- local player we'd need input_source/viewport (not supported in v1).
    local saved = {
        peer_id = peer_id,
        local_player_id = local_player_id,
        profile_index = profile_index,
        career_index = career_index,
        party_id = party_id,
        slot_id = slot_id,
        is_remote = player.remote and true or false,
    }
    if player.remote then
        saved.remote = {
            player_controlled = player._player_controlled,
            clan_tag = player._clan_tag,
            account_id = player._account_id,
        }
    else
        saved.local_data = {
            input_source = player.input_source,
            viewport_name = player.viewport_name,
            viewport_world_name = player.viewport_world_name,
        }
    end
    _ai_saved_state[_ai_state_key(peer_id, local_player_id)] = saved

    if player.player_unit then
        player:despawn()
    end
    profile_synchronizer:unassign_profiles_of_peer(peer_id, local_player_id)
    Managers.party:remove_peer_from_party(peer_id, local_player_id, party_id)
    pm:remove_player(peer_id, local_player_id)

    local game_mode = Managers.state.game_mode:game_mode()
    if not (game_mode and game_mode._add_bot_to_party) then
        return false, "current game mode does not support bots"
    end
    game_mode:_add_bot_to_party(party_id, profile_index, career_index, slot_id)

    return true
end

local function _ai_swap_bot_to_human(peer_id, local_player_id)
    local pm = Managers.player
    if not pm.is_server then return false, "must run on host" end
    local saved = _ai_saved_state[_ai_state_key(peer_id, local_player_id)]
    if not saved then return false, "no saved state (toggle to bot first)" end

    local bot = _ai_find_bot_in_slot(saved.party_id, saved.slot_id)
    if bot then
        local game_mode = Managers.state.game_mode:game_mode()
        if game_mode and game_mode._remove_bot_instant then
            game_mode:_remove_bot_instant(bot)
        end
    end

    if saved.is_remote and saved.remote then
        pm:add_remote_player(peer_id, saved.remote.player_controlled, local_player_id,
            saved.remote.clan_tag, saved.remote.account_id)
    elseif saved.local_data then
        pm:add_player(saved.local_data.input_source, saved.local_data.viewport_name,
            saved.local_data.viewport_world_name, local_player_id)
    else
        return false, "saved state missing player kind"
    end

    Managers.party:assign_peer_to_party(peer_id, local_player_id, saved.party_id, saved.slot_id, false)
    pm.network_manager.profile_synchronizer:assign_full_profile(peer_id, local_player_id,
        saved.profile_index, saved.career_index, false)

    _ai_saved_state[_ai_state_key(peer_id, local_player_id)] = nil
    return true
end

mod:network_register(_AI_RPC, function(sender_peer_id, payload)
    local pm = Managers.player
    if not (pm and pm.is_server) then return end
    local peer_id, local_player_id = sender_peer_id, 1
    local want_bot
    if type(payload) == "table" then
        peer_id = payload.peer_id or peer_id
        local_player_id = payload.local_player_id or local_player_id
        want_bot = payload.want_bot
    end

    local ok, err = _ai_can_swap_in_current_mode()
    if not ok then
        mod:info("[ai_toggle] refused for %s: %s", tostring(peer_id), tostring(err))
        return
    end

    -- want_bot is the client's explicit intent (from their checkbox state).
    -- Saved state is the host's view of truth — used to no-op stale requests.
    local has_saved = _ai_saved_state[_ai_state_key(peer_id, local_player_id)] ~= nil
    if want_bot == nil then want_bot = not has_saved end

    if want_bot and not has_saved then
        local s_ok, s_err = _ai_swap_human_to_bot(peer_id, local_player_id)
        mod:info("[ai_toggle] human->bot for %s: %s", tostring(peer_id), s_ok and "ok" or tostring(s_err))
    elseif (not want_bot) and has_saved then
        local s_ok, s_err = _ai_swap_bot_to_human(peer_id, local_player_id)
        mod:info("[ai_toggle] bot->human for %s: %s", tostring(peer_id), s_ok and "ok" or tostring(s_err))
    else
        mod:info("[ai_toggle] no-op for %s (want_bot=%s has_saved=%s)",
            tostring(peer_id), tostring(want_bot), tostring(has_saved))
    end
end)

-- Returns (ok, err_msg). Caller is responsible for reverting the checkbox on
-- failure — _ai_suppress_setting_callback must be true while doing so.
-- Assigns to the forward-declared upvalue (see top of file); MUST NOT use
-- `local function` here or on_setting_changed would call nil.
_ai_handle_toggle_change = function(want_bot)
    local ok, err = _ai_can_swap_in_current_mode()
    if not ok then return false, err end

    local pm = Managers.player
    if pm and pm.is_server then
        return false, "host self-toggle not supported in v1 (would tear down local UI/input). Run from a client."
    end

    mod:network_send(_AI_RPC, "server", {
        peer_id = Network.peer_id(),
        local_player_id = 1,
        want_bot = want_bot and true or false,
    })
    return true
end

mod:command("ai", "Toggle AI takeover for your character (bot controls it; toggle again to resume)", function()
    -- Flipping the setting fires on_setting_changed which runs the RPC.
    -- Keeps the chat command and the VMF checkbox in lockstep.
    if _ai_suppress_setting_callback then return end
    mod:set("ai_takeover_enabled", not mod:get("ai_takeover_enabled"))
end)

-- ============================================================
-- Time & Pause (Group B — Janoti "Hacks" port)
-- ============================================================
-- Two related features sharing the same engine primitive:
-- `Managers.state.debug:set_time_scale(index)`. The index is into
-- `time_scale_list` in debug_manager.lua:18 — a 24-entry table of
-- multipliers. Index 13 = 1.0x (normal). Lower = slower, higher = faster.
-- Settings persist for the session; vanilla wipes them on level transition,
-- so on_game_state_changed re-applies the slider value on each StateIngame
-- entry.
--
-- Pause: host-only. Toggles between the configured "pause speed" index
-- (default 1 = slowest possible) and normal (13). VT2 has no true pause
-- primitive — set_time_scale(1) is the closest thing and still lets the UI
-- update. Don't confuse with the time slider: the two write to the same
-- engine setter, so if both are used simultaneously the last write wins.
-- We keep them as separate features matching Hacks's UX.

local _pause_active = false

mod.gt_pause_toggle = function()
    if not (Managers.player and Managers.player.is_server) then
        mod:echo("Only the host can pause the game.")
        return
    end
    local debug_mgr = Managers.state and Managers.state.debug
    if not (debug_mgr and debug_mgr.set_time_scale) then
        mod:echo("Time scale manager not available yet.")
        return
    end
    if _pause_active then
        debug_mgr:set_time_scale(mod:get("time_scale_value") or 13)
        _pause_active = false
        mod:echo("Game unpaused.")
    else
        debug_mgr:set_time_scale(mod:get("pause_value") or 1)
        _pause_active = true
        mod:echo("Game paused.")
    end
end

mod.gt_time_apply = function()
    if _pause_active then
        -- While paused, slider edits update the post-unpause target but don't
        -- override the active pause speed. Matches Hacks's behaviour.
        return
    end
    local debug_mgr = Managers.state and Managers.state.debug
    if debug_mgr and debug_mgr.set_time_scale then
        debug_mgr:set_time_scale(mod:get("time_scale_value") or 13)
    end
end

mod.gt_time_faster = function()
    local cur = mod:get("time_scale_value") or 13
    if cur >= 24 then
        mod:echo("Already at maximum time speed.")
        return
    end
    mod:set("time_scale_value", cur + 1)
    mod.gt_time_apply()
    mod:echo(string.format("Time scale: %d", cur + 1))
end

mod.gt_time_slower = function()
    local cur = mod:get("time_scale_value") or 13
    if cur <= 1 then
        mod:echo("Already at minimum time speed.")
        return
    end
    mod:set("time_scale_value", cur - 1)
    mod.gt_time_apply()
    mod:echo(string.format("Time scale: %d", cur - 1))
end

mod:command("gt_pause",    "Toggle game pause (host-only time slowdown to the configured pause speed)", function() mod.gt_pause_toggle() end)
mod:command("time_faster", "Increase game time scale by one step", function() mod.gt_time_faster() end)
mod:command("time_slower", "Decrease game time scale by one step", function() mod.gt_time_slower() end)

-- ============================================================
-- Ult Controls (Group C — Janoti "Hacks" port)
-- ============================================================
-- Three independent features, all driven through CareerExtension:
--
--  1. `gt ult_reset` (+ hotkey) — one-shot, sets every active-ability cooldown
--     to 0 via :reduce_activated_ability_cooldown_percent(charge_index, 1).
--     ThePageMan's "No Ult Cooldown" primitive.
--
--  2. Player ult cooldown cap (toggle + slider 0-120s) — every
--     CareerExtension.update tick, if self.player is human-controlled, clamp
--     each ability's cooldowns[k] down to the configured max. Smooths the
--     "set ult to 5s for testing" workflow without burning a talent slot.
--
--  3. Bot ult cooldown cap — same idea but for AI-controlled units. Useful
--     to make bots ult more aggressively in solo-with-bots testing.
--
-- Both caps share a helper (mod._gt_clamp_cooldowns) that walks every ability
-- on the extension and trims each charge's cooldown if it exceeds the target.
-- Borrowed from Hacks 1:1 since the iteration pattern (decaying-charge index,
-- cooldown_paused unblock, set_activated_ability_cooldown_unpaused) is what
-- the engine expects and replicating it any other way would desync the ability
-- HUD overlay.

mod.gt_ult_reset = function()
    local local_player = Managers.player and Managers.player:local_player()
    local unit = local_player and local_player.player_unit
    if not (unit and Unit.alive(unit)) then
        mod:echo("No local player unit.")
        return
    end
    local career_ext = ScriptUnit.has_extension(unit, "career_system")
    if not career_ext then
        mod:echo("No career extension on local player.")
        return
    end
    for i = 1, career_ext._num_abilities or 1, 1 do
        career_ext:reduce_activated_ability_cooldown_percent(i, 1)
    end
    mod:echo("Ult reset.")
end

mod._gt_clamp_cooldowns = function(career_ext, max_seconds)
    for i = 1, career_ext._num_abilities or 1, 1 do
        local ability = career_ext._abilities[i]
        if ability and ability.cooldowns then
            local charge_idx = career_ext:_currently_decaying_cooldown(i)
            if charge_idx then
                for k = charge_idx, 1, -1 do
                    if ability.cooldowns[k] and ability.cooldowns[k] > max_seconds then
                        ability.cooldowns[k] = max_seconds
                    end
                end
            end
            local is_ready = career_ext:_cooldown_charge_ready(i)
            if not is_ready then
                ability.cooldown_paused = false
            end
            if is_ready then
                career_ext:set_activated_ability_cooldown_unpaused(i)
            end
        end
    end
end

mod:hook_safe(CareerExtension, "update", function(self, unit, input, dt, context, t)
    if mod:get("ult_player_cap_enabled") and self.player and self.player:is_player_controlled() then
        mod._gt_clamp_cooldowns(self, mod:get("ult_player_cap_value") or 0)
    end
    if mod:get("ult_bot_cap_enabled") and self.player and not self.player:is_player_controlled() then
        mod._gt_clamp_cooldowns(self, mod:get("ult_bot_cap_value") or 0)
    end
end)

mod:command("gt_ultreset", "Reset your ultimate (set cooldown to 0)", function() mod.gt_ult_reset() end)

-- ============================================================
-- Buffs & Stat Tweaks (Group D — Janoti "Hacks" port)
-- ============================================================
-- Five independent toggles/sliders:
--
--  1. `gt infinite_ammo`  — applies the vanilla `twitch_no_overcharge_no_ammo_reloads`
--     buff to the local player (and host-side to every player, since the buff
--     is server-controlled). Periodic re-apply every second keeps the buff
--     refreshed in case it gets stripped.
--  2. `gt infinite_stamina` — hooks GenericStatusExtension.add_fatigue_points
--     and short-circuits it so stamina-cost calls never deplete the bar.
--  3. `gt giga_power`     — multiplies BuffTemplates.power_level_unbalance
--     (Enhanced Power talent) by 1000x. Echoes that the talent must be
--     re-equipped for the buff to refresh.
--  4. Base crit chance slider (1–100%) — rewrites
--     CareerSettings[current_career].attributes.base_critical_strike_chance.
--     Auto-resets to the career's vanilla value when you switch career
--     (ProfileRequester.request_profile + GameModeInn._cb_start_menu_closed
--     hooks).
--  5. Movement speed slider (0–30 m/s) — rewrites PlayerUnitMovementSettings.move_speed
--     and walks the per-unit settings table (via the closed-upvalue trick
--     debug.getupvalue(PlayerUnitMovementSettings.unregister_unit, 1)) so
--     already-spawned units get the new speed too.
--
-- All five settings reset on game restart (we don't try to persist them past
-- session) — matches Hacks. The infinite-ammo periodic refresher rides on
-- mod.update which gt already uses for tp/freecam/noclip reapply.

-- ---------- 5.1 Infinite Ammo & 0 Heat -----------------------

local _gt_infinite_ammo_active = false
local _gt_infinite_ammo_refresh_t = 0

local function _gt_apply_infinite_ammo_buff(unit)
    if not (unit and Unit.alive(unit)) then return end
    local buff_ext = ScriptUnit.has_extension(unit, "buff_system")
    if not buff_ext then return end
    if buff_ext:has_buff_type("twitch_no_overcharge_no_ammo_reloads") then return end
    if Managers.player and Managers.player.is_server then
        local bs = Managers.state.entity:system("buff_system")
        bs:add_buff(unit, "twitch_no_overcharge_no_ammo_reloads", unit, false)
    else
        buff_ext:add_buff("twitch_no_overcharge_no_ammo_reloads")
    end
end

local function _gt_remove_infinite_ammo_buff(unit)
    if not (unit and Unit.alive(unit)) then return end
    local buff_ext = ScriptUnit.has_extension(unit, "buff_system")
    if not buff_ext then return end
    if not buff_ext:has_buff_type("twitch_no_overcharge_no_ammo_reloads") then return end
    local buff = buff_ext:get_non_stacking_buff("twitch_no_overcharge_no_ammo_reloads")
    if buff then buff_ext:remove_buff(buff.id) end
end

local function _gt_refresh_infinite_ammo()
    local lp = Managers.player and Managers.player:local_player()
    if lp and lp.player_unit then _gt_apply_infinite_ammo_buff(lp.player_unit) end
    if Managers.player and Managers.player.is_server then
        for _, p in pairs(Managers.player:human_and_bot_players() or {}) do
            _gt_apply_infinite_ammo_buff(p.player_unit)
        end
    end
end

local function _gt_clear_infinite_ammo()
    local lp = Managers.player and Managers.player:local_player()
    if lp and lp.player_unit then _gt_remove_infinite_ammo_buff(lp.player_unit) end
    if Managers.player and Managers.player.is_server then
        for _, p in pairs(Managers.player:human_and_bot_players() or {}) do
            _gt_remove_infinite_ammo_buff(p.player_unit)
        end
    end
end

mod.gt_infinite_ammo_toggle = function()
    _gt_infinite_ammo_active = not _gt_infinite_ammo_active
    if _gt_infinite_ammo_active then
        _gt_refresh_infinite_ammo()
        mod:echo("Infinite ammo & heat: ON.")
    else
        _gt_clear_infinite_ammo()
        mod:echo("Infinite ammo & heat: OFF.")
    end
end

mod:command("infinite_ammo", "Toggle infinite ammo and zero overheat for all players (host applies to clients too)", function()
    mod.gt_infinite_ammo_toggle()
end)

-- ---------- 5.2 Infinite Stamina -----------------------------

local _gt_stamina_active = false

mod.gt_infinite_stamina_toggle = function()
    _gt_stamina_active = not _gt_stamina_active
    mod:echo(_gt_stamina_active and "Infinite stamina: ON." or "Infinite stamina: OFF.")
end

-- Always-on wrapper. When the flag is off, the closure passes through to the
-- original; when on, it short-circuits so fatigue cost calls never deplete
-- the stamina bar. Avoids re-registering hooks (VMF errors on duplicates).
mod:hook(GenericStatusExtension, "add_fatigue_points", function(func, ...)
    if _gt_stamina_active then return end
    return func(...)
end)

mod:command("gt_stamina", "Toggle infinite stamina (zero fatigue cost on blocks/dodges/pushes)", function()
    mod.gt_infinite_stamina_toggle()
end)

-- ---------- 5.3 Giga Power -----------------------------------

local _gt_giga_power_active = false
local _gt_giga_power_original = nil

mod.gt_giga_power_toggle = function()
    if not (BuffTemplates and BuffTemplates.power_level_unbalance and BuffTemplates.power_level_unbalance.buffs[1]) then
        mod:echo("BuffTemplates.power_level_unbalance not available.")
        return
    end
    local buff_row = BuffTemplates.power_level_unbalance.buffs[1]
    if _gt_giga_power_active then
        if _gt_giga_power_original ~= nil then
            buff_row.multiplier = _gt_giga_power_original
        end
        _gt_giga_power_active = false
        mod:echo("Giga power: OFF (re-equip the Enhanced Power talent).")
    else
        _gt_giga_power_original = buff_row.multiplier
        buff_row.multiplier = 1000
        _gt_giga_power_active = true
        mod:echo("Giga power: ON (re-equip the Enhanced Power talent).")
    end
end

mod:command("gt_gigapower", "Multiply the Enhanced Power talent buff by 1000x (re-equip the talent to refresh)", function()
    mod.gt_giga_power_toggle()
end)

-- ---------- 5.4 Base Crit Chance Slider ----------------------

local _gt_current_career_for_crit = nil

local function _gt_get_local_career_name()
    local lp = Managers.player and Managers.player:local_player()
    if not lp then return nil end
    local profile_idx = lp:profile_index()
    local career_idx  = lp:career_index()
    if not (profile_idx and career_idx) then return nil end
    local profile = SPProfiles and SPProfiles[profile_idx]
    if not (profile and profile.careers and profile.careers[career_idx]) then return nil end
    return profile.careers[career_idx].name
end

mod.gt_apply_crit_chance = function()
    local name = _gt_get_local_career_name()
    if not (name and CareerSettings[name] and CareerSettings[name].attributes) then return end
    local pct = mod:get("base_crit_chance") or 5
    CareerSettings[name].attributes.base_critical_strike_chance = pct / 100
end

-- On career switch, snap the slider to that career's vanilla value so toggling
-- back and forth doesn't carry over an unintended override.
mod.gt_sync_crit_default_for_career = function()
    local name = _gt_get_local_career_name()
    if not (name and CareerSettings[name] and CareerSettings[name].attributes) then return end
    if name == _gt_current_career_for_crit then return end
    _gt_current_career_for_crit = name
    local pct = (CareerSettings[name].attributes.base_critical_strike_chance or 0.05) * 100
    mod:set("base_crit_chance", pct)
end

mod:hook_safe(ProfileRequester, "request_profile", function() mod.gt_sync_crit_default_for_career() end)
mod:hook_safe(GameModeInn,      "_cb_start_menu_closed", function() mod.gt_sync_crit_default_for_career() end)

-- ---------- 5.5 Movement Speed Slider -----------------------

mod.gt_apply_move_speed = function()
    local v = mod:get("movement_speed")
    if not (v and PlayerUnitMovementSettings) then return end
    PlayerUnitMovementSettings.move_speed = v
    -- The per-unit settings table is closed over inside unregister_unit. Reach
    -- in via debug.getupvalue so already-spawned units pick up the new speed.
    local _, units_settings = debug.getupvalue(PlayerUnitMovementSettings.unregister_unit, 1)
    if type(units_settings) == "table" then
        for _, settings in pairs(units_settings) do
            settings.move_speed = v
        end
    end
end

-- Chain a 1Hz infinite-ammo refresher onto the existing update closure.
do
    local _orig = mod.update
    mod.update = function(dt)
        if _orig then _orig(dt) end
        if _gt_infinite_ammo_active then
            _gt_infinite_ammo_refresh_t = _gt_infinite_ammo_refresh_t + (dt or 0)
            if _gt_infinite_ammo_refresh_t >= 1.0 then
                _gt_infinite_ammo_refresh_t = 0
                _gt_refresh_infinite_ammo()
            end
        end
    end
end

-- ============================================================
-- Player-state toggles (Group E — Janoti "Hacks" port)
-- ============================================================
-- Three small toggles that don't fit the other groups, all kept distinct
-- from gt's existing `god` toggle on purpose:
--
--  * `inn_dmg`   — host-only flip of `DamageUtils.is_in_inn`. When the
--    inn flag is OFF, the keep behaves like a mission (damage taken,
--    enemies could spawn, etc.). Useful for sparring with bots.
--  * `cloak`     — visual cloak that hides the player model. gt's `god`
--    already cloaks via `status_system:set_invisible(true, false,
--    "gt_godmode")`, but `god` is a multi-feature umbrella. `cloak` is a
--    standalone cosmetic toggle using a separate reason namespace so it
--    doesn't clobber god's invisibility state.
--  * `unkillable`— flips `script_data.player_unkillable`. Unlike `god`
--    you DO still take damage (and disablers still grab you) but you
--    can't be dropped below 1 HP. Mostly a "let me actually feel hits
--    while testing" mode.

mod.gt_inn_dmg_toggle = function()
    if not (Managers.player and Managers.player.is_server) then
        mod:echo("Only the host can toggle inn-damage.")
        return
    end
    if DamageUtils.is_in_inn then
        DamageUtils.is_in_inn = false
        mod:echo("Damage in keep: ENABLED.")
    else
        DamageUtils.is_in_inn = true
        mod:echo("Damage in keep: disabled (vanilla).")
    end
end

mod:command("gt_inndmg", "Toggle whether the keep takes damage (host-only)", function()
    mod.gt_inn_dmg_toggle()
end)

-- Visual cloak: distinct from gt god's invisibility (separate reason namespace
-- so neither clobbers the other on toggle-off). The 3P body and 1P weapon
-- arms both hide because skip_first_person=false. AI perception ignores the
-- player too (same set_invisible primitive).
local _gt_cloak_active = false

mod.gt_cloak_toggle = function()
    local lp = Managers.player and Managers.player:local_player()
    local unit = lp and lp.player_unit
    if not (unit and Unit.alive(unit)) then
        mod:echo("No local player unit.")
        return
    end
    local status_ext = ScriptUnit.has_extension(unit, "status_system")
    if not (status_ext and status_ext.set_invisible) then
        mod:echo("No status extension on local player.")
        return
    end
    _gt_cloak_active = not _gt_cloak_active
    status_ext:set_invisible(_gt_cloak_active, false, "gt_cloak")
    mod:echo(_gt_cloak_active and "Cloak: ON (invisible)." or "Cloak: OFF.")
end

mod:command("cloak", "Toggle visual invisibility (separate from godmode)", function()
    mod.gt_cloak_toggle()
end)

-- Unkillable: take damage normally, but the engine refuses to drop you below
-- 1 HP while the flag is on. Vanilla globals `script_data` controls this; we
-- just flip the flag and announce.
mod.gt_unkillable_toggle = function()
    script_data = script_data or {}
    script_data.player_unkillable = not script_data.player_unkillable
    mod:echo(script_data.player_unkillable and "Unkillable: ON (still take damage)." or "Unkillable: OFF.")
end

mod:command("gt_unkillable", "Toggle take-damage-but-never-die mode", function()
    mod.gt_unkillable_toggle()
end)

-- ============================================================
-- Engine error nil-guards (Group F — Janoti "Hacks" port)
-- ============================================================
-- Two well-known places where vanilla code occasionally dereferences a unit
-- that's mid-cleanup, producing red [Engine Error] spam (and sometimes a
-- silent fatal during long sessions). Hacks ships these guards too — they're
-- cheap and we'd rather suppress the error than have it leak into our crash
-- triage. Both are pure no-op-if-unit-dead pre-guards; the original function
-- is called normally when the unit is alive.

if VolumetricsFlowCallbacks and VolumetricsFlowCallbacks.unregister_fog_volume then
    mod:hook(VolumetricsFlowCallbacks, "unregister_fog_volume", function(func, params, ...)
        if not (params and params.unit and Unit.alive(params.unit)) then return end
        return func(params, ...)
    end)
end

mod:hook(Unit, "get_data", function(func, unit, ...)
    if not unit then return end
    return func(unit, ...)
end)
