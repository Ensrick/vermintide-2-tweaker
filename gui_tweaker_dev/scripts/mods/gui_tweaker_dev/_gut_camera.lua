local mod = get_mod("gut_dev")

-- _gut_camera.lua — Third-Person Camera
--
-- MIGRATED from general_tweaker (gt) 2026-06-29 (issue #191): this feature moved
-- out of gt and into gut. Behavior is UNCHANGED from gt's _gt_camera.lua; only the
-- gt->gut adaptations changed:
--   * setting ids tp_* -> gut_tp_* (mod-scoped, no collision with gt's tp_*)
--   * chat command stays /tp -- gut owns the bare /tp now that the feature lives
--     here (gt_dev dropped its /tp on migration #191). Stable gt still registers
--     /tp until its next promotion drops it.
--   * gt's central per-frame registry (mod._gt_register_update) -> gut has none, so
--     the tp re-apply timer CHAINS mod.update (capture-prev / call-prev-first), the
--     same idiom _hide_ui.lua / _gut_cutscenes.lua use.
--   * gt's extensions_ready hook also scheduled a godmode/noclip re-apply
--     (mod._gt_schedule_post_spawn_reapply). gut has NO godmode/noclip, so that call
--     is dropped — the hook here only re-arms the camera.
--   * the on_setting_changed / on_disabled / on_game_state_changed dispatch that
--     lived in gt's main file is CHAINED here, so the module is self-contained.
--
-- Development.set_parameter() is a no-op in release builds, so we write directly to
-- the _hardcoded_dev_params table so every system reading
-- Development.parameter("third_person_mode") sees the value (camera redirect, mesh
-- visibility, FP guard).
--
-- The set_first_person_mode guard (player_unit_first_person.lua:907) checks:
-- override OR NOT third_person_mode OR NOT attract_mode. Since attract_mode is nil,
-- the guard always passes — inspect and other systems can restore 1P even with
-- third_person_mode set. We hook set_first_person_mode to block 1P restore when tp
-- is on (yielding to cutscenes; see the cutscene-yield block below).
--
-- Camera distance: the over_shoulder node in CameraSettings has offset y=0.65 which
-- is too close. We patch it to a proper follow distance + height/side offsets from
-- the gut_tp_* sliders.
--
-- Hooks (PRE-FLIGHT verified disjoint from the rest of gut — a whole-mod grep before
-- migration found NO other gut hook on PlayerUnitFirstPerson):
--   * PlayerUnitFirstPerson.set_first_person_mode
--   * PlayerUnitFirstPerson.extensions_ready

-- ============================================================
-- Third-Person Camera
-- ============================================================

local _tp_enabled = false
local _tp_reapply_timer = nil

-- Vanilla over_shoulder uses x=0.75, y=0.65, z=0 (camera_settings.lua:273-278).
-- We override y (negative pulls camera back), z (height), and x (side offset).
-- Zoom variants are scaled at fixed ratios from the main slider so the transition
-- between unzoomed / zoom / increased_zoom remains perceptually consistent — full
-- distance for the wide view, ~60% for zoom, ~40% for increased_zoom.
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

mod._gut_patch_camera_offset = function()
    if not CameraSettings or not CameraSettings.first_person then return end
    _snapshot_camera_offsets()
    local distance = mod:get("gut_tp_distance") or 3.0
    local height   = mod:get("gut_tp_height")   or 1.0
    local side     = mod:get("gut_tp_side_offset") or 0.8
    -- When enabled, ADS / ranged-aim no longer pulls the 3P camera in close; both
    -- zoom-in modes use the same multipliers as `over_shoulder` so the view stays at
    -- the configured distance/height regardless of zoom state.
    local no_zoom_in = mod:get("gut_tp_disable_zoom_in")
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

mod._gut_restore_camera_offset = function()
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

mod._gut_patch_camera_offset()

mod._gut_apply_tp = function(enabled)
    _tp_enabled = enabled
    -- (#209) camera-transition receipt: list the ledger's live screen-particle
    -- ids at every 3P entry/exit. Resolved through the mod table because the
    -- receipt helper is defined later in this file (call-time lookup).
    if type(mod._gut209_transition_receipt) == "function" then
        mod._gut209_transition_receipt(enabled and "entry" or "exit")
    end
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

-- tp is forcibly cleared on every state change (level transition, etc.) because the
-- engine reinitializes the FP system. The extensions_ready hook below re-arms tp on
-- the next player spawn if gut_tp_camera_enabled is on.
mod._gut_tp_reset_enabled = function()
    local was_tp = _tp_enabled
    _tp_enabled = false
    if Development._hardcoded_dev_params then
        Development._hardcoded_dev_params.third_person_mode = nil
    end
    -- (#209) forced-exit receipt on state change, only when 3P was live.
    if was_tp and type(mod._gut209_transition_receipt) == "function" then
        mod._gut209_transition_receipt("reset-exit")
    end
end

-- A cutscene's END path calls CutsceneSystem:set_first_person_mode(true) ->
-- first_person_extension:set_first_person_mode(true) with override==nil to RESTORE
-- first-person (cutscene_system.lua:154, flow_cb_deactivate_cutscene_cameras). With
-- TP camera on, that restore matches this block's `active and not override`
-- condition, so we used to SWALLOW it and the camera was never restored after the
-- cutscene. `_tp_enabled` is only cleared on a game-state change, and a cutscene
-- start/end is NOT a state change, so the block stayed live across the whole cutscene.
--
-- Fix: while a cutscene owns the camera, YIELD the block so the restore goes through.
-- CutsceneSystem:is_active() == (self.active_camera ~= nil) (cutscene_system.lua:83-85).
-- The restore at deactivate runs BEFORE self.active_camera is niled (:154 then :156),
-- so is_active() is still true at the exact moment our hook fires for the 1P restore.
local function _gut_cutscene_owns_camera()
    local mgr_state = Managers and Managers.state
    local entity_mgr = mgr_state and mgr_state.entity
    if not entity_mgr then return false end
    local ok, cs = pcall(entity_mgr.system, entity_mgr, "cutscene_system")
    if not ok or not cs then return false end
    local ok2, active = pcall(cs.is_active, cs)
    return ok2 and active or false
end
mod:hook("PlayerUnitFirstPerson", "set_first_person_mode", function(func, self, active, override, unarmed)
    if _tp_enabled and active and not override and not _gut_cutscene_owns_camera() then
        return
    end
    return func(self, active, override, unarmed)
end)

-- (#209) Buff/ability SCREEN effects (create_screen_particles) render on the FIRST-person
-- view, so in the mod's 3P camera they still overlay the screen. Suppress while tp is active.
-- Safe: BuffExtension._stop_screen_effect guards `if effect_id`, so a nil id is a no-op; the
-- buff's continuous/deactivation tracking handles a nil effect_id.
--
-- (#209 INSTRUMENT, diagnostics only) The documented remaining edge is a
-- CONTINUOUS screen effect already active when ENTERING 3P: only new spawns
-- are suppressed, and the first-person extension has no general registry of
-- live screen-particle ids, so no universal sweep exists yet. To identify
-- which owners survive entry, every hooked lifecycle event on the surface
-- (create/stop_spawning/destroy_screen_particles,
-- player_unit_first_person.lua:1073/:1081/:1089) prints ONE bounded
-- [gut:209] row (effect name, callsite, particle id, camera mode; hard row
-- cap in the ledger), and every 3P entry/exit prints a receipt listing the
-- ledger's live ids. Ledger is pure + offline-tested
-- (_gut_screen_particle_ledger.lua). BLIND SPOT (by design, documented in the
-- ledger header): owners destroying via World.destroy_particles directly
-- (overcharge decay, player_unit_overcharge_extension.lua:155-159) bypass the
-- surface, so a listed id may already be dead - the receipt is evidence for
-- picking owner-specific handling, not a claim of liveness. The hook
-- callbacks are NAMED locals (registered once each; VMF drops a second hook
-- on the same (Class, method) pair) so the issue209 runtime check executes
-- the exact registered function objects against fake delegates.
local _SPLedger = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_screen_particle_ledger")
local _p209_state = _SPLedger.new()

-- Best-effort caller identification: first stack frame outside gut/VMF files.
-- The retail sandbox may not expose `debug`; degrade to "?" (never throw).
local function _p209_callsite()
    local dbg = rawget(_G, "debug")
    if not (dbg and dbg.getinfo) then return "?" end
    for level = 3, 8 do
        local ok, info = pcall(dbg.getinfo, level, "Sl")
        if not ok or not info then break end
        local src = tostring(info.short_src or info.source or "?")
        if not src:find("gui_tweaker", 1, true) and not src:find("vmf", 1, true) then
            return src .. ":" .. tostring(info.currentline)
        end
    end
    return "?"
end

local function _p209_row(kind, effect, id)
    local allowed, capped_now = _SPLedger.row_allowed(_p209_state)
    if not allowed then return end
    -- Keep the literal emitter directly visible to deployed-tree authority.
    -- The observation must remain fail-closed if engine logging is unavailable.
    pcall(printf, "[gut:209] %s | effect=%s id=%s tp=%s callsite=%s%s",
        kind, tostring(effect), tostring(id), tostring(_tp_enabled), _p209_callsite(),
        capped_now and " | ROW-CAP reached, further lifecycle rows suppressed" or "")
end

local function _p209_transition(kind)
    pcall(printf, "[gut:209] tp-%s | live=%s", kind, _SPLedger.snapshot(_p209_state))
end
mod._gut209_transition_receipt = _p209_transition

local _cb209_create = function(func, self, name, pos, ...)
    if _tp_enabled then
        _p209_row("create-suppressed-3p", name, nil)
        return nil
    end
    local id = func(self, name, pos, ...)
    if id ~= nil then
        _SPLedger.note_create(_p209_state, id, name)
    end
    _p209_row("create", name, id)
    return id
end
mod:hook("PlayerUnitFirstPerson", "create_screen_particles", _cb209_create)

-- (#216, crash GUID 0a41da66) The nil return above is NOT safe for every consumer, only
-- for BuffExtension. Two vanilla paths crash on a nil id:
--   * PlayerUnitOverchargeExtension._update_screen_effect lazily creates its overlay id,
--     then unconditionally calls World.set_particles_material_scalar with it every update
--     while overcharge > 0 (user-hit: Bolt Staff heat in 3P).
--   * player/enemy_character_state_in_vortex exit paths pass their stored id to
--     stop_spawning_screen_particles without a nil check.
-- Fix: skip the overcharge screen effect entirely while tp is active (no screen overlays
-- in 3P is this feature's intent; on the 3P->1P switch vanilla lazily recreates the
-- overlay), and nil-guard the two particle sinks so any unguarded vanilla caller is
-- covered.
mod:hook("PlayerUnitOverchargeExtension", "_update_screen_effect", function(func, self, ...)
    if _tp_enabled then
        if self.onscreen_particles_id or self.critical_onscreen_particles_id then
            -- (#209 instrument) these ids die inside the vanilla helper via
            -- World.destroy_particles (player_unit_overcharge_extension.lua:
            -- 155-159), bypassing the hooked destroy surface - report the
            -- gut-initiated destroys to the ledger here so the receipt stays
            -- honest for the overcharge owner.
            if self.onscreen_particles_id then
                _SPLedger.note_destroy(_p209_state, self.onscreen_particles_id)
                _p209_row("destroy-overcharge-3p", "overcharge", self.onscreen_particles_id)
            end
            if self.critical_onscreen_particles_id then
                _SPLedger.note_destroy(_p209_state, self.critical_onscreen_particles_id)
                _p209_row("destroy-overcharge-3p", "overcharge_critical", self.critical_onscreen_particles_id)
            end
            -- vanilla helper destroys and nils both id fields
            self:_destroy_all_screen_space_particles()
        end
        return
    end
    return func(self, ...)
end)
local _cb209_stop = function(func, self, id, ...)
    if id == nil then return end
    local entry = _p209_state.live[id]
    _SPLedger.note_stop(_p209_state, id)
    _p209_row("stop-spawning", entry and entry.effect or "?", id)
    return func(self, id, ...)
end
mod:hook("PlayerUnitFirstPerson", "stop_spawning_screen_particles", _cb209_stop)
local _cb209_destroy = function(func, self, id, ...)
    if id == nil then return end
    local entry = _p209_state.live[id]
    _SPLedger.note_destroy(_p209_state, id)
    _p209_row("destroy", entry and entry.effect or "?", id)
    return func(self, id, ...)
end
mod:hook("PlayerUnitFirstPerson", "destroy_screen_particles", _cb209_destroy)

-- (#209) Named runtime check: executes the CAPTURED lifecycle callbacks (the
-- exact function objects registered above) against fake engine delegates and
-- verifies ledger + suppression + the #216 nil-guards. Row budget and tp
-- state are saved/restored so repeated regression runs cannot drain the
-- in-mission diagnostic budget or flip the camera.
if type(mod._gut_rt_register) == "function" then
    mod._gut_rt_register("issue209_screen_particle_receipts", function()
        local saved_tp = _tp_enabled
        local saved_rows, saved_capped = _p209_state.rows, _p209_state.capped
        local ok, err = pcall(function()
            local calls = {}
            local fake_self = {}
            _tp_enabled = false
            local id = _cb209_create(function(self, name, pos)
                calls[#calls + 1] = "create:" .. tostring(name)
                return 90209
            end, fake_self, "fx/gut_rt209_probe", nil)
            assert(id == 90209, "create passthrough lost the particle id")
            assert(_p209_state.live[90209] ~= nil, "ledger missed the created id")
            assert(_SPLedger.snapshot(_p209_state)
                :find("90209=fx/gut_rt209_probe(live)", 1, true),
                "snapshot does not list the live id")
            _cb209_stop(function() calls[#calls + 1] = "stop" end, fake_self, 90209)
            assert(_p209_state.live[90209].status == "stopped", "stop did not mark the id")
            assert(calls[#calls] == "stop", "stop did not reach the engine delegate")
            -- #216 nil-guards must keep refusing without engine calls.
            _cb209_stop(function() calls[#calls + 1] = "stop-nil" end, fake_self, nil)
            _cb209_destroy(function() calls[#calls + 1] = "destroy-nil" end, fake_self, nil)
            assert(calls[#calls] == "stop", "nil-guard leaked a nil id to the engine")
            _cb209_destroy(function() calls[#calls + 1] = "destroy" end, fake_self, 90209)
            assert(_p209_state.live[90209] == nil, "destroy did not clear the ledger entry")
            assert(calls[#calls] == "destroy", "destroy did not reach the engine delegate")
            -- 3P suppression path never reaches the engine delegate.
            _tp_enabled = true
            local sid = _cb209_create(function()
                calls[#calls + 1] = "create-3p"
            end, fake_self, "fx/gut_rt209_probe2", nil)
            assert(sid == nil, "3P create was not suppressed")
            for i = 1, #calls do
                assert(calls[i] ~= "create-3p", "3P create reached the engine delegate")
            end
        end)
        _tp_enabled = saved_tp
        _p209_state.rows, _p209_state.capped = saved_rows, saved_capped
        if not ok then return tostring(err) end
    end)
end

-- gut_tp_disable_zoom_in (issue #202). Aim zoom-in in 3P is driven PER-WEAPON: the
-- weapon hands GenericStatusExtension a camera_name (zoom_in / increased_zoom_in /
-- zoom_in_trueflight / ...), the engine appends "_third_person" in 3P mode, then writes
-- it to the camera_follow_unit's "settings_node" (generic_status_extension.lua:1516-1523
-- on aim; :1563 in switch_variable_zoom for multi-level zoom like longbows). An earlier
-- attempt (v0.2.139) overrode the FOV of two specific zoom NODES, but that missed every
-- other weapon's zoom node AND never stopped the camera switching to a zoom node, so the
-- zoom (FOV + pull-in) still happened.
--
-- Robust fix: intercept BOTH node writers and, while the 3P camera is on AND the toggle is
-- on, force the node back to "over_shoulder". This disables the zoom for EVERY weapon
-- uniformly. Aim MECHANICS are untouched: is_zooming / accuracy / bow-charge key off
-- self.zooming (set by vanilla before our post-hook), not the camera node -- only the VIEW
-- changes. Gated on Development.parameter("third_person_mode") -- the SAME flag the engine
-- uses to decide the zoom node -- so it's a no-op outside the mod's 3P camera or with the
-- toggle off. hook_safe (post-callback, no return override); each method hooked once.
local function _gut_force_over_shoulder_if_no_zoom(self)
    if not (mod:get("gut_tp_disable_zoom_in") and Development.parameter("third_person_mode")) then
        return
    end
    local player = self.player
    local cfu = player and player.camera_follow_unit
    if cfu and Unit.alive(cfu) then
        Unit.set_data(cfu, "camera", "settings_node", "over_shoulder")
        self.zoom_mode = "over_shoulder"
    end
end
mod:hook_safe("GenericStatusExtension", "set_zooming", function(self, zooming, camera_name)
    if zooming then
        _gut_force_over_shoulder_if_no_zoom(self)
    end
end)
mod:hook_safe("GenericStatusExtension", "switch_variable_zoom", function(self, zoom_table)
    _gut_force_over_shoulder_if_no_zoom(self)
end)

-- On player spawn we temporarily flip OFF tp (clear third_person_mode, force 1P) so
-- the FP system can finish initialization, then re-enable tp shortly after via the
-- timer below. Without this defer, set_first_person_mode can run before extensions
-- are wired up and leave the camera in a half-state.
mod:hook("PlayerUnitFirstPerson", "extensions_ready", function(func, self, world, unit, ...)
    local result = func(self, world, unit, ...)
    if mod:get("gut_tp_camera_enabled") then
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
-- half-initialised state. gut has no central update registry, so we CHAIN mod.update
-- (capture-prev / call-prev-first) — never clobber another feature's tick.
local _gut_camera_prev_update = mod.update
mod.update = function(dt)
    if _gut_camera_prev_update then _gut_camera_prev_update(dt) end
    if _tp_reapply_timer then
        _tp_reapply_timer = _tp_reapply_timer - (dt or 0)
        if _tp_reapply_timer <= 0 then
            _tp_reapply_timer = nil
            mod._gut_apply_tp(true)
        end
    end
end

-- Dispatch wiring: chain the lifecycle callbacks (capture-prev / call-prev-first).
-- Dofile'd after the main file defines mod.on_setting_changed / mod.on_game_state_changed,
-- so `prev` captures them.
do
    local prev = mod.on_setting_changed
    mod.on_setting_changed = function(setting_id)
        if prev then prev(setting_id) end
        if setting_id == "gut_tp_camera_enabled" then
            mod._gut_apply_tp(mod:get("gut_tp_camera_enabled"))
        elseif setting_id == "gut_tp_distance" or setting_id == "gut_tp_height"
            or setting_id == "gut_tp_side_offset" or setting_id == "gut_tp_disable_zoom_in" then
            mod._gut_patch_camera_offset()
        end
    end
end

do
    local prev = mod.on_game_state_changed
    mod.on_game_state_changed = function(status, state_name)
        if prev then prev(status, state_name) end
        -- tp is forcibly cleared on every state change; the extensions_ready hook
        -- re-arms it on the next player spawn if gut_tp_camera_enabled is on.
        mod._gut_tp_reset_enabled()
    end
end

do
    local prev = mod.on_disabled
    mod.on_disabled = function(...)
        if prev then prev(...) end
        mod._gut_restore_camera_offset()
    end
end

mod:command("tp", "Toggle third-person camera", function()
    local new_val = not mod:get("gut_tp_camera_enabled")
    mod:set("gut_tp_camera_enabled", new_val)
    -- mod:set triggers on_setting_changed (which calls mod._gut_apply_tp); the
    -- explicit call here makes the toggle feel immediate either way.
    mod._gut_apply_tp(new_val)
    mod:echo("Third-person: " .. (new_val and "ON" or "OFF"))
end)
