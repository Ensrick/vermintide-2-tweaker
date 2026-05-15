local mod = get_mod("gt")

local MOD_VERSION = "0.2.20-alpha"

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

-- Re-arm noclip when the local player's locomotion extension is wired up
-- on each spawn (mission entry, respawn). Without this, the persisted
-- VMF setting stays "on" while the actual locomotion state is whatever
-- the engine initialised it to — usually `script_driven` — and the user
-- would have to toggle the chat command before flight worked.
mod:hook_safe("PlayerUnitLocomotionExtension", "extensions_ready", function(self, world, unit)
    if not mod:get("noclip_enabled") then return end
    if unit ~= _local_player_unit() then return end
    _apply_noclip(true)
end)

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
local _orig_mod_update = mod.update
mod.update = function(dt)
    if _orig_mod_update then _orig_mod_update(dt) end
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

-- Re-apply invisibility on each player spawn — GenericStatusExtension.invisible is
-- reset to {} on extension init, so a level transition while godmode is on would
-- otherwise leave the new player unit visible to AI.
mod:hook_safe("GenericStatusExtension", "extensions_ready", function(self, world, unit)
    if not _godmode then return end
    local pm = Managers.player
    local player = pm and pm:local_player()
    if not player or player.player_unit ~= unit then return end
    pcall(self.set_invisible, self, true, false, _GODMODE_INVIS_REASON)
end)

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
-- Win (complete current map)
-- ============================================================

mod:command("win", "Complete the current map", function()
    if Managers.state and Managers.state.game_mode then
        Managers.state.game_mode:complete_level()
    else
        mod:echo("No active game mode.")
    end
end)

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
