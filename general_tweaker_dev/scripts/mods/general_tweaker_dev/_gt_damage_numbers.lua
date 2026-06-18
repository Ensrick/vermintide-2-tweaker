local mod = get_mod("gt_dev")

-- ============================================================================
-- Floating Damage Numbers  (client-side, networking-free)
-- ============================================================================
-- WHAT
--   Floating numbers pop over enemies YOU damage. This is a from-scratch,
--   crash-proof replacement for the third-party "damage numbers" mod that
--   crashed lobby members who didn't have it. It reuses the engine's own
--   machinery end-to-end:
--     * DamageNumbersUI            (scripts/ui/hud_ui/damage_numbers_ui.lua) --
--       the HUD component that projects world->screen and animates/fades the
--       text. Already listed in the ADVENTURE HUD component list
--       (hud_component_list_adventure.lua), but its validation_function only
--       activates it in a mission when `script_data.debug_show_damage_numbers`
--       is set, and nothing in Adventure feeds it for enemy hits.
--     * DamageUtils.add_unit_floating_damage_numbers (damage_utils.lua:3942) --
--       builds the color (crit / dot / damage-scaled), size and duration, then
--       triggers the "add_damage_number" event the component listens for.
--   So this module does the two missing pieces: (A) flip the activation flag,
--   and (B) feed the helper from the local player's damage hooks (those live in
--   the main file, merged into the EXISTING godmode add_damage_network /
--   add_damage_network_player hooks -- VMF drops a second hook on the same
--   Class.method, so we must not add new ones).
--
-- WHY IT CANNOT CRASH PLAYERS WHO LACK THE MOD
--   "Crashes when someone in the lobby doesn't have it" is the signature of a
--   mod that registers a VMF network event / sends RPCs to peers with no
--   matching handler. This feature registers NO network handlers and sends NO
--   RPCs. The damage value is one the local client already computes for itself:
--   in add_damage_network_player, DamageUtils.calculate_damage +
--   apply_buffs_to_damage run BEFORE the `is_server` branch, so a client knows
--   its own outgoing damage without asking the host. We only trigger a local
--   UI event. A non-modded lobby member is simply unaffected.
--
-- ACTIVATION TIMING
--   The component-list validation_function reads
--   `script_data.debug_show_damage_numbers` when the HUD builds its components
--   (mission load). We set the flag at mod load and re-assert on every
--   StateIngame enter, so it is live for the upcoming mission. Toggling the
--   setting mid-mission therefore takes effect on the NEXT map load.
-- ============================================================================

mod._gt_dn_enabled = false       -- read per-hit by the damage hooks in the main file
mod._gt_dn_include_dots = false  -- gate for the DoT/explosion (add_damage_network) path

local function _enabled()
    return mod:get("gt_damage_numbers_enabled") and true or false
end

-- Mirror our feature state onto the engine's activation gate. We only ever set
-- it to match our own setting; harmless even if the engine debug menu also uses
-- the flag (we are simply the last writer when our setting changes / a mission
-- starts).
local function _sync_activation()
    if rawget(_G, "script_data") then
        script_data.debug_show_damage_numbers = mod._gt_dn_enabled
    end
end

mod._gt_dn_refresh = function()
    mod._gt_dn_enabled = _enabled()
    mod._gt_dn_include_dots = mod:get("gt_damage_numbers_include_dots") and true or false
    _sync_activation()
end

-- Trigger one floating number on `hit_unit`. Reuses the vanilla helper so color,
-- crit emphasis, dot-vs-direct coloring, size scaling and the projected-text
-- event all match base-game behavior exactly. Pure UI: no state mutation, no
-- network. Wrapped in pcall so a single malformed hit can never interrupt the
-- damage pipeline (or the godmode logic sharing the host hook).
mod._gt_dn_show = function(hit_unit, damage_type, damage_amount, is_critical_strike)
    if not mod._gt_dn_enabled then return end
    if not (hit_unit and Unit.alive(hit_unit)) then return end
    if not (damage_amount and damage_amount > 0) then return end
    if not (Managers.state and Managers.state.event) then return end

    local du = rawget(_G, "DamageUtils")
    if not (du and du.add_unit_floating_damage_numbers) then return end

    pcall(du.add_unit_floating_damage_numbers, hit_unit, damage_type, damage_amount, is_critical_strike)
end

-- Wrap on_setting_changed (chain pattern -- never redefine the central handler).
do
    local prev = mod.on_setting_changed
    mod.on_setting_changed = function(setting_id)
        if prev then prev(setting_id) end
        if setting_id == "gt_damage_numbers_enabled" or setting_id == "gt_damage_numbers_include_dots" then
            mod._gt_dn_refresh()
        end
    end
end

-- Re-assert the activation flag on every StateIngame enter, so it is set before
-- the HUD builds its component list for the upcoming mission.
do
    local prev = mod.on_game_state_changed
    mod.on_game_state_changed = function(status, state_name)
        if prev then prev(status, state_name) end
        if status == "enter" and state_name == "StateIngame" then
            _sync_activation()
        end
    end
end

-- Initial sync at load (covers the first mission before any state change fires).
mod._gt_dn_refresh()
