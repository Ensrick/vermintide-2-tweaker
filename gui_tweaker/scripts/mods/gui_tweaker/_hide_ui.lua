local mod = get_mod("gut")

-- ============================================================
-- Hide UI (3 modes)  [migrated from general_tweaker (gt) 2026-06-20]
-- ============================================================
-- Replaces the "Hide UI" mod (Workshop 2007374303, removed from Workshop).
-- Three modes mirror the original:
--  * `off`      — HUD shown normally.
--  * `partial`  — hook GameModeBase.game_mode_hud_disabled to return true.
--                 Vanilla HUD visibility rules then auto-hide the bulk of the
--                 HUD (used by the "Act on Instinct" mutator). Subtitles,
--                 prompts, and twitch votes stay visible.
--  * `complete` — partial + iterate ingame_hud._components_array and force
--                 set_visible(false) on residual components (subtitle/prompt/etc).
--  * `camera`   — complete + hide first-person mesh (arms + weapon).
--
-- gut_hud cycles off → partial → complete → camera → off.

local HUD_MODE_OFF      = "off"
local HUD_MODE_PARTIAL  = "partial"
local HUD_MODE_COMPLETE = "complete"
local HUD_MODE_CAMERA   = "camera"

local _HUD_MODE_ORDER = {
    HUD_MODE_OFF, HUD_MODE_PARTIAL, HUD_MODE_COMPLETE, HUD_MODE_CAMERA,
}
local _HUD_MODE_LABEL = {
    [HUD_MODE_OFF]      = "Off",
    [HUD_MODE_PARTIAL]  = "Partial",
    [HUD_MODE_COMPLETE] = "Complete",
    [HUD_MODE_CAMERA]   = "Camera",
}

local function _gut_hud_mode()
    return mod:get("gut_hud_mode") or HUD_MODE_OFF
end

local function _gut_hud_is_hidden()
    return _gut_hud_mode() ~= HUD_MODE_OFF
end

-- Vanilla HUD component-visibility refresh runs every frame against the
-- active visibility group's whitelist. Force-hiding via set_visible(false)
-- in mod.update lets us stomp partial-mode residuals (subtitle/prompt) each
-- tick without fighting the visibility-group system.
local _gut_hud_force_hide_dbg = false
local function _gut_hud_force_hide_components()
    -- The live HUD is on the IngameUI instance (ingame_ui.lua:103
    -- `self.ingame_hud = IngameHud:new(...)`), reached via Managers.ui._ingame_ui
    -- (the path gt uses everywhere else) — NOT Managers.ui.ingame_hud, which is nil,
    -- so this silently no-op'd and complete/camera modes did nothing.
    local ingame_ui = Managers.ui and Managers.ui._ingame_ui
    local ingame_hud = ingame_ui and ingame_ui.ingame_hud
    if not (ingame_hud and ingame_hud._components_array) then return end
    if not _gut_hud_force_hide_dbg then
        _gut_hud_force_hide_dbg = true
        mod:debug("[gut:hud] force-hide active: %d HUD components", #ingame_hud._components_array)
    end
    for _, component in ipairs(ingame_hud._components_array) do
        if component and component.set_visible then
            pcall(component.set_visible, component, false)
        end
    end
end

-- ── Outline system (enemy/ally/pickup silhouettes) ──────────────────────────
-- Folded in from the original "Hide UI" mod (Workshop 2007374303). The outline
-- system is the entity-system that draws the colored silhouettes through walls;
-- hiding the HUD without it leaves those outlines glaringly visible, defeating a
-- clean screenshot/camera mode. Verified against current engine source:
--   * system handle:  Managers.state.entity:system("outline_system")
--                     (scripts/game_state/state_ingame_running.lua:94, others)
--   * disable method: OutlineSystem:set_disabled(disabled)  -- single boolean
--                     (scripts/entity_system/systems/outlines/outline_system.lua:478;
--                      the engine itself calls it the same way in
--                      debug_screen_config.lua:10097)
-- Realism guard (verified): the "realism" mutator's own client_start/stop_function
-- toggle set_disabled (scripts/settings/mutators/mutator_realism.lua:7-18), so when
-- realism is active the outline system is ALREADY disabled-by-mutator — we must NOT
-- re-enable on our way out, or we'd stomp realism's effect. Mutator key is exactly
-- "realism" (scripts/settings/dlcs/mutators_batch_01/.../common_settings.lua:9), and
-- Managers.state.game_mode:has_activated_mutator(name) checks _active_mutators[name]
-- (game_mode_manager.lua:264 -> mutator_handler.lua:220).
local function _gut_hud_set_outlines(disabled)
    local entity_mgr = Managers.state and Managers.state.entity
    if not entity_mgr then return end
    -- When re-enabling, defer to the realism mutator: if it's active, leave the
    -- outlines disabled (the mutator owns that state).
    if not disabled then
        local gm = Managers.state.game_mode
        if gm and gm.has_activated_mutator then
            local ok, active = pcall(gm.has_activated_mutator, gm, "realism")
            if ok and active then
                mod:debug("[gut:hud] skipping outline re-enable (realism mutator active)")
                return
            end
        end
    end
    local ok, outline_system = pcall(entity_mgr.system, entity_mgr, "outline_system")
    if not (ok and outline_system and outline_system.set_disabled) then return end
    pcall(outline_system.set_disabled, outline_system, disabled)
    mod:debug("[gut:hud] outlines %s", disabled and "disabled" or "enabled")
end

local function _gut_first_person_extension()
    local local_player = Managers.player and Managers.player:local_player()
    local unit = local_player and local_player.player_unit
    if not (unit and Unit.alive(unit)) then return nil end
    -- "first_person_system" resolves to PlayerUnitFirstPerson on the local player
    -- (scripts/network/unit_extension_templates.lua:20). Verified methods/fields on
    -- the current PlayerUnitFirstPerson (scripts/.../default_player_unit/
    -- player_unit_first_person.lua): hide_weapons(reason, hide_lights) /
    -- unhide_weapons(reason) (l.1016/1032), first_person_attachment_unit (l.49, the
    -- arms mesh), first_person_mode (l.54).
    return ScriptUnit.has_extension(unit, "first_person_system")
end

-- Reason key handed to hide_weapons / unhide_weapons. Must be identical on both
-- sides or the unhide won't clear our hide flag.
local _GUT_HIDE_WEAPONS_REASON = "gut_hide_ui"

local function _gut_hud_apply_camera_mode_visibility(want_visible)
    local fp_ext = _gut_first_person_extension()
    if not fp_ext then return end
    -- Preferred path (mirrors the original mod): use the FP extension's own
    -- weapon-hide bookkeeping for the held weapon(s), and toggle the arms mesh
    -- (first_person_attachment_unit) directly. Only flip the arms while actually
    -- in first-person mode, matching vanilla set_first_person_mode behaviour.
    if want_visible then
        if fp_ext.unhide_weapons then
            pcall(fp_ext.unhide_weapons, fp_ext, _GUT_HIDE_WEAPONS_REASON)
        end
        if fp_ext.first_person_mode and fp_ext.first_person_attachment_unit
           and Unit.alive(fp_ext.first_person_attachment_unit) then
            pcall(Unit.set_unit_visibility, fp_ext.first_person_attachment_unit, true)
        end
    else
        if fp_ext.hide_weapons then
            pcall(fp_ext.hide_weapons, fp_ext, _GUT_HIDE_WEAPONS_REASON, true)
        end
        if fp_ext.first_person_attachment_unit
           and Unit.alive(fp_ext.first_person_attachment_unit) then
            pcall(Unit.set_unit_visibility, fp_ext.first_person_attachment_unit, false)
        end
    end
    -- Belt-and-suspenders: also flip the linked per-slot 1p weapon meshes the FP
    -- rig carries. hide_weapons routes through inventory_extension:show_first_person_
    -- inventory, but if that path no-ops for any slot (mid-swap, custom weapon),
    -- stomp the units directly too. Cheap and idempotent.
    local local_player = Managers.player and Managers.player:local_player()
    local pu = local_player and local_player.player_unit
    if pu and Unit.alive(pu) then
        local inv = ScriptUnit.has_extension(pu, "inventory_system")
        if inv and inv._equipment and inv._equipment.slots then
            for _, slot_data in pairs(inv._equipment.slots) do
                for _, key in ipairs({"left_unit_1p", "right_unit_1p"}) do
                    local u = slot_data[key]
                    if u and Unit.alive(u) then
                        pcall(Unit.set_unit_visibility, u, want_visible)
                    end
                end
            end
        end
    end
end

-- Hook the GameMode HUD-disabled query so vanilla's HUD component list auto-hides
-- everything that opts into "game_mode_disable_hud" (partial mode).
-- MUST hook the DERIVED classes, NOT GameModeBase: VT2's class() copies parent
-- methods into each child AT DEFINITION TIME (class.lua), so the active mode
-- (GameModeAdventure/Versus/Deus/…) holds its OWN copy of game_mode_hud_disabled,
-- and the HUD component list calls instance:game_mode_hud_disabled() — a hook on
-- GameModeBase never fires. (This is the bug that made Hide UI do nothing.) Each
-- entry is a distinct (Class,method) pair, so no duplicate-hook collision.
for _, _gm_class in ipairs({
    "GameModeAdventure", "GameModeDeus", "GameModeWeave", "GameModeSurvival", "GameModeVersus",
}) do
    mod:hook(_gm_class, "game_mode_hud_disabled", function(func, self, ...)
        if _gut_hud_is_hidden() then return true end
        return func(self, ...)
    end)
end

-- Cycle order: off → partial → complete → camera → off.
mod.gut_hud_cycle = function()
    local current = _gut_hud_mode()
    local next_idx = 1
    for i, m in ipairs(_HUD_MODE_ORDER) do
        if m == current then
            next_idx = (i % #_HUD_MODE_ORDER) + 1
            break
        end
    end
    local new_mode = _HUD_MODE_ORDER[next_idx]
    mod:set("gut_hud_mode", new_mode)
    mod:echo("Hide UI: " .. _HUD_MODE_LABEL[new_mode])
end

mod:command("gut_hud", "Cycle Hide UI mode (off/partial/complete/camera)", function()
    mod.gut_hud_cycle()
end)

-- Outlines (silhouettes) are killed for the "immersive" modes — complete and
-- camera — and restored for off/partial. Mirrors the original mod, which dropped
-- outlines whenever the UI was hidden.
local function _gut_hud_mode_wants_outlines_off(m)
    return m == HUD_MODE_COMPLETE or m == HUD_MODE_CAMERA
end

-- Per-frame enforcement for complete + camera modes. Partial mode rides
-- entirely on the visibility-group hook above and needs no per-frame work.
-- gut has no central update registry, so we own mod.update directly (chaining
-- any pre-existing mod.update so we don't stomp another feature's tick).
local _gut_hud_last_applied_mode = HUD_MODE_OFF
local _gut_hud_prev_update = mod.update
mod.update = function(dt)
    if _gut_hud_prev_update then _gut_hud_prev_update(dt) end
    -- Out of mission the entity manager (and the local player unit) are gone, so
    -- our outline/arms state can't be applied and the live HUD doesn't exist.
    -- Reset the transition tracker to OFF so that re-entering a mission while a
    -- hide mode is still selected re-fires the apply transitions against the
    -- freshly-spawned OutlineSystem / FP rig (both start un-hidden on a new level).
    if not (Managers.state and Managers.state.entity) then
        _gut_hud_last_applied_mode = HUD_MODE_OFF
        return
    end
    local current = _gut_hud_mode()
    if current == HUD_MODE_COMPLETE or current == HUD_MODE_CAMERA then
        _gut_hud_force_hide_components()
    end
    -- Arms/weapons hide stays CAMERA-only.
    if current == HUD_MODE_CAMERA and _gut_hud_last_applied_mode ~= HUD_MODE_CAMERA then
        _gut_hud_apply_camera_mode_visibility(false)
    elseif current ~= HUD_MODE_CAMERA and _gut_hud_last_applied_mode == HUD_MODE_CAMERA then
        _gut_hud_apply_camera_mode_visibility(true)
    end
    -- Outline toggle: only on a transition that crosses the wants-outlines-off
    -- boundary (complete/camera <-> off/partial), so we don't hammer set_disabled
    -- every frame.
    local want_outlines_off = _gut_hud_mode_wants_outlines_off(current)
    if want_outlines_off ~= _gut_hud_mode_wants_outlines_off(_gut_hud_last_applied_mode) then
        _gut_hud_set_outlines(want_outlines_off)
    end
    _gut_hud_last_applied_mode = current
end

return {}
