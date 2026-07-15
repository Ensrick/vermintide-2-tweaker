local mod = get_mod("gut")

-- _gut_damage_numbers.lua — Floating Damage Numbers
--
-- MIGRATED from general_tweaker (gt) 2026-06-29: this feature moved out of gt and
-- into gut. Behavior is UNCHANGED from gt's _gt_damage_numbers.lua (same engine
-- machinery, same crash-proof / networking-free design); only the gt->gut
-- namespacing changed (setting ids gt_damage_numbers_* -> gut_damage_numbers_*).
--
-- WHAT
--   Floating numbers pop over enemies YOU damage. Reuses the engine's own
--   machinery end-to-end:
--     * DamageNumbersUI (scripts/ui/hud_ui/damage_numbers_ui.lua) — the HUD
--       component that projects world->screen and animates/fades the text.
--       Already listed in the ADVENTURE HUD component list, but its
--       validation_function only activates it when
--       `script_data.debug_show_damage_numbers` is set, and nothing in Adventure
--       feeds it for enemy hits.
--     * DamageUtils.add_unit_floating_damage_numbers (damage_utils.lua:3942) —
--       builds the color (crit / dot / damage-scaled), size and duration, then
--       triggers the "add_damage_number" event the component listens for.
--   So this module does the two missing pieces: (A) flip the activation flag,
--   and (B) feed the helper from the local player's own DamageUtils hooks below.
--
-- WHY IT CANNOT CRASH PLAYERS WHO LACK THE MOD
--   "Crashes when someone in the lobby doesn't have it" is the signature of a mod
--   that registers a VMF network event / sends RPCs to peers with no matching
--   handler. This feature registers NO network handlers and sends NO RPCs. The
--   damage value is one the local client already computes for itself
--   (add_damage_network_player runs calculate_damage + apply_buffs_to_damage
--   BEFORE the `is_server` branch), so a client knows its own outgoing damage
--   without asking the host. We only trigger a local UI event. A non-modded lobby
--   member is simply unaffected.
--
-- WHY ITS OWN HOOKS HERE (vs gt's consolidated godmode hook)
--   In gt these two DamageUtils methods were ALSO hooked by godmode, and VMF
--   drops a 2nd hook on the same (mod, Class, method), so gt fed the numbers from
--   inside the godmode hook. gut has NO godmode and (pre-flight grep verified) NO
--   other hook on DamageUtils.add_damage_network / add_damage_network_player, so
--   this module registers its own clean, self-contained hooks. VMF chains hooks
--   ACROSS mods, so coexisting with gt's godmode hook (different mod) is fine.
--
-- ACTIVATION TIMING
--   The component-list validation_function reads
--   `script_data.debug_show_damage_numbers` when the HUD builds its components
--   (mission load). We set the flag at mod load and re-assert on every StateIngame
--   enter, so it is live for the upcoming mission. Toggling the setting
--   mid-mission therefore takes effect on the NEXT map load.

mod._gut_dn_enabled = false       -- read per-hit by the DamageUtils hooks below
mod._gut_dn_include_dots = false  -- gate for the DoT/explosion (add_damage_network) path

local function _enabled()
    return mod:get("gut_damage_numbers_enabled") and true or false
end

-- Mirror our feature state onto the engine's activation gate. We only ever set it
-- to match our own setting; harmless even if the engine debug menu also uses the
-- flag (we are simply the last writer when our setting changes / a mission starts).
local function _sync_activation()
    if rawget(_G, "script_data") then
        script_data.debug_show_damage_numbers = mod._gut_dn_enabled
    end
end

mod._gut_dn_refresh = function()
    mod._gut_dn_enabled = _enabled()
    mod._gut_dn_include_dots = mod:get("gut_damage_numbers_include_dots") and true or false
    _sync_activation()
end

local function _is_local_player_unit(unit)
    local pm = Managers.player
    local player = pm and pm:local_player()
    return player and player.player_unit == unit
end

-- Trigger one floating number on `hit_unit`. Reuses the vanilla helper so color,
-- crit emphasis, dot-vs-direct coloring, size scaling and the projected-text event
-- all match base-game behavior exactly. Pure UI: no state mutation, no network.
-- Wrapped in pcall so a single malformed hit can never interrupt the damage
-- pipeline.
mod._gut_dn_show = function(hit_unit, damage_type, damage_amount, is_critical_strike)
    if not mod._gut_dn_enabled then return end
    if not (hit_unit and Unit.alive(hit_unit)) then return end
    if not (damage_amount and damage_amount > 0) then return end
    if not (Managers.state and Managers.state.event) then return end

    local du = rawget(_G, "DamageUtils")
    if not (du and du.add_unit_floating_damage_numbers) then return end

    pcall(du.add_unit_floating_damage_numbers, hit_unit, damage_type, damage_amount, is_critical_strike)
end

-- add_damage_network carries DoTs, explosions (bombs) and other already-final
-- damage values; gated behind the include-dots sub-toggle. damage_amount is the
-- function's single return value.
mod:hook("DamageUtils", "add_damage_network", function(func, attacked_unit, attacker_unit, original_damage_amount, hit_zone_name, damage_type, ...)
    local damage_amount = func(attacked_unit, attacker_unit, original_damage_amount, hit_zone_name, damage_type, ...)
    if mod._gut_dn_enabled and mod._gut_dn_include_dots
       and _is_local_player_unit(attacker_unit) then
        mod._gut_dn_show(attacked_unit, damage_type, damage_amount, nil)
    end
    return damage_amount
end)

-- add_damage_network_player is the player-weapon path: damage_amount is computed
-- locally on host AND client (via calculate_damage + apply_buffs_to_damage, before
-- the is_server branch), so the numbers are accurate either way with zero
-- networking. damage_type=nil tells the vanilla helper to treat it as a normal
-- (non-dot) direct hit. Single return.
mod:hook("DamageUtils", "add_damage_network_player", function(func, damage_profile, target_index, power_level, attacked_unit, attacker_unit, hit_zone_name, hit_position, attack_direction, damage_source, hit_ragdoll_actor, boost_curve_multiplier, is_critical_strike, ...)
    local damage_amount = func(damage_profile, target_index, power_level, attacked_unit, attacker_unit, hit_zone_name, hit_position, attack_direction, damage_source, hit_ragdoll_actor, boost_curve_multiplier, is_critical_strike, ...)
    if mod._gut_dn_enabled
       and _is_local_player_unit(attacker_unit) then
        mod._gut_dn_show(attacked_unit, nil, damage_amount, is_critical_strike)
    end
    return damage_amount
end)

-- Chain on_setting_changed (capture-prev / call-prev-first — never clobber another
-- feature's handler). This module dofile's AFTER the main file defines
-- mod.on_setting_changed, so `prev` captures it.
do
    local prev = mod.on_setting_changed
    mod.on_setting_changed = function(setting_id)
        if prev then prev(setting_id) end
        if setting_id == "gut_damage_numbers_enabled" or setting_id == "gut_damage_numbers_include_dots" then
            mod._gut_dn_refresh()
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
mod._gut_dn_refresh()
