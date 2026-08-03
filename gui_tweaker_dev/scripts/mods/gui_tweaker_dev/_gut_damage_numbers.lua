local mod = get_mod("gut_dev")
local DamageNumberPolicy = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_damage_numbers_policy")

-- _gut_damage_numbers.lua — Floating Damage Numbers
--
-- MIGRATED from general_tweaker (gt) 2026-06-29: this feature moved out of gt and
-- into gut with the same engine machinery and networking-free design. Issue #938
-- (REWORKED 2026-08-03): the engine splits an above-boundary hit into a same-frame
-- burst of network-max chunks BEFORE any value reaches the popup helper, so the
-- earlier font-scale-only fix never saw an above-boundary value. The helper hook
-- below aggregates one burst back into a single popup carrying the summed value,
-- and the font-scale policy then bounds that real total. Colors, duration, and
-- the event path remain vanilla.
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
-- crit emphasis, dot-vs-direct coloring and the projected-text event stay on the
-- base-game path. The table lookup resolves the HOOKED helper below, so this
-- feed routes through the same burst aggregation as the engine's own callers;
-- the bounded font scale is applied there, at emission, on the summed value.
-- Pure UI: no state mutation, no network.
-- Wrapped in pcall so a single malformed hit can never interrupt the damage
-- pipeline.
mod._gut_dn_show = function(hit_unit, damage_type, damage_amount, is_critical_strike)
    if not mod._gut_dn_enabled then return end
    if not (hit_unit and Unit.alive(hit_unit)) then return end
    if not (damage_amount and damage_amount > 0) then return end
    if not (Managers.state and Managers.state.event) then return end

    local du = rawget(_G, "DamageUtils")
    if not (du and du.add_unit_floating_damage_numbers) then return end

    pcall(du.add_unit_floating_damage_numbers, hit_unit, damage_type, damage_amount,
        is_critical_strike)
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

-- (#938 REWORK) Burst aggregation at the single popup chokepoint.
-- WHY HERE: DamageUtils.add_damage_network_player transports at most
-- NetworkConstants.damage.max per health-extension call — an above-boundary hit
-- becomes a same-frame burst of max-size add_damage chunks plus one remainder
-- (damage_utils.lua:1969-1981) and RETURNS only the post-split remainder — and
-- TrainingDummyHealthExtension.add_damage feeds each PRE-SPLIT chunk straight
-- into this helper (training_dummy_health_extension.lua:70). So no caller ever
-- hands the popup path an above-boundary value, and the font-scale policy was a
-- no-op. Aggregating one burst (same unit + damage type inside a tiny window)
-- restores the real total: ONE popup with the summed value, whose font scale
-- the policy then genuinely bounds.
-- DISPLAY-ONLY: the vanilla add_damage/RPC pipeline is untouched; we only defer
-- and coalesce the local "add_damage_number" UI event. With the toggle off the
-- helper is called through untouched.
-- PRE-FLIGHT (NON-NEGOTIABLE 8): gut's only other DamageUtils hooks are the two
-- feed hooks above (grep-verified; everything else only READS is_in_inn).
local dn_pending = {}     -- [unit] = { [damage_type_key] = pending popup }
local dn_original         -- vanilla helper, captured from the hook's func arg

local function _dn_now()
    local time_manager = Managers and Managers.time
    if time_manager and time_manager.time then
        local ok, t = pcall(time_manager.time, time_manager, "game")
        if ok and type(t) == "number" then return t end
    end
    return nil
end

-- Emit one aggregated popup through the ORIGINAL helper (bypassing the hook),
-- applying the bounded font scale to the summed value.
local function _dn_emit(unit, type_key, entry)
    if not dn_original then return end
    if not (unit and Unit.alive(unit)) then return end
    local constants = rawget(_G, "NetworkConstants")
    local max_network_damage = constants and constants.damage and constants.damage.max
    local font_override = DamageNumberPolicy.font_override(entry.amount, max_network_damage)
    pcall(dn_original, unit, type_key ~= "" and type_key or nil, entry.amount,
        entry.is_critical_strike, nil, nil, font_override)
end

-- Emit every due pending popup; force=true emits regardless of window (used on
-- disable so nothing earned while the toggle was on is dropped).
local function _dn_flush(t, force)
    for unit, groups in pairs(dn_pending) do
        local remaining = false
        for type_key, entry in pairs(groups) do
            if force or (t and DamageNumberPolicy.is_due(entry, t)) then
                groups[type_key] = nil
                _dn_emit(unit, type_key, entry)
            else
                remaining = true
            end
        end
        if not remaining then dn_pending[unit] = nil end
    end
end

mod:hook("DamageUtils", "add_unit_floating_damage_numbers", function(func, unit, damage_type, damage_amount, is_critical_strike, streak_damage, z_offset_override, damage_numbers_font_override, data)
    dn_original = func
    -- Toggle off, or a caller shape we never aggregate (streak/z-offset/font/data
    -- carriers are the incoming-player-damage path, player_unit_health_extension
    -- .lua:628, whose per-breed presentation we must not disturb): call through
    -- untouched.
    if not mod._gut_dn_enabled
            or streak_damage ~= nil or z_offset_override ~= nil
            or damage_numbers_font_override ~= nil or data ~= nil
            or type(damage_amount) ~= "number" or damage_amount <= 0
            or not (unit and Unit.alive(unit)) then
        return func(unit, damage_type, damage_amount, is_critical_strike,
            streak_damage, z_offset_override, damage_numbers_font_override, data)
    end
    local t = _dn_now()
    if not t then
        -- No game clock (no aggregation possible): emit immediately, still with
        -- the bounded font scale on this single value.
        local constants = rawget(_G, "NetworkConstants")
        local max_network_damage = constants and constants.damage and constants.damage.max
        return func(unit, damage_type, damage_amount, is_critical_strike, nil, nil,
            DamageNumberPolicy.font_override(damage_amount, max_network_damage))
    end
    local groups = dn_pending[unit]
    if not groups then
        groups = {}
        dn_pending[unit] = groups
    end
    local type_key = damage_type or ""
    local _, displaced = DamageNumberPolicy.accumulate(groups, type_key,
        damage_amount, is_critical_strike, t)
    if displaced then _dn_emit(unit, type_key, displaced) end
    -- The pending popup emits from the update flush once its window elapses.
end)
mod._gut_dn_aggregation_hooked = true

-- Chain mod.update for the window flush (capture-prev / call-prev-first).
do
    local prev = mod.update
    mod.update = function(dt)
        if prev then prev(dt) end
        if next(dn_pending) then
            local t = _dn_now()
            if t then _dn_flush(t) end
        end
    end
end

-- Chain on_setting_changed (capture-prev / call-prev-first — never clobber another
-- feature's handler). This module dofile's AFTER the main file defines
-- mod.on_setting_changed, so `prev` captures it. Disabling force-flushes the
-- pending popups so none are silently dropped.
do
    local prev = mod.on_setting_changed
    mod.on_setting_changed = function(setting_id)
        if prev then prev(setting_id) end
        if setting_id == "gut_damage_numbers_enabled" or setting_id == "gut_damage_numbers_include_dots" then
            mod._gut_dn_refresh()
            if not mod._gut_dn_enabled then
                _dn_flush(nil, true)
            end
        end
    end
end

-- Re-assert the activation flag on every StateIngame enter, so it is set before
-- the HUD builds its component list for the upcoming mission. Also drop pending
-- popups from the previous level (their units are gone).
do
    local prev = mod.on_game_state_changed
    mod.on_game_state_changed = function(status, state_name)
        if prev then prev(status, state_name) end
        if status == "enter" and state_name == "StateIngame" then
            _sync_activation()
            for unit in pairs(dn_pending) do
                dn_pending[unit] = nil
            end
        end
    end
end

-- Initial sync at load (covers the first mission before any state change fires).
mod._gut_dn_refresh()

if type(mod._gut_rt_register) == "function" then
    mod._gut_rt_register("issue938_damage_number_burst_aggregation", function()
        if mod._gut_dn_aggregation_hooked ~= true then
            return "popup-chokepoint aggregation hook missing"
        end
        -- Engine bound read at runtime (NetworkConstants.damage is
        -- Network.type_info("damage"), network_constants.lua:19). Offline or
        -- pre-init it is unavailable: fall back so the policy shape is still
        -- exercised, and say so.
        local constants = rawget(_G, "NetworkConstants")
        local max_damage = constants and constants.damage and constants.damage.max
        if type(max_damage) ~= "number" or max_damage <= 0 then
            max_damage = 255.75
            pcall(printf,
                "[gut:938] rt skip: NetworkConstants.damage.max unavailable; policy checked against fallback %.2f",
                max_damage)
        end
        local ordinary = DamageNumberPolicy.font_override(max_damage / 2, max_damage)
        if ordinary ~= 1 then
            return "ordinary damage scaling changed"
        end
        local large = DamageNumberPolicy.font_override(max_damage * 40, max_damage)
        local actual = DamageNumberPolicy.vanilla_text_size(max_damage * 40, large)
        local expected = DamageNumberPolicy.vanilla_text_size(max_damage, 1)
        if math.abs(actual - expected) > 0.0001 then
            return "large damage visual size is not bounded at network maximum"
        end
        -- Aggregation policy: an in-window burst (N max chunks + remainder, the
        -- damage_utils.lua:1969-1981 split shape) sums to ONE pending popup...
        local groups = {}
        local window = DamageNumberPolicy.AGGREGATION_WINDOW
        local first = DamageNumberPolicy.accumulate(groups, "k", max_damage, false, 10)
        DamageNumberPolicy.accumulate(groups, "k", max_damage, false, 10)
        local merged, displaced = DamageNumberPolicy.accumulate(groups, "k", 40.5, true, 10)
        if merged ~= first or displaced ~= nil then
            return "in-window chunks did not merge into one pending popup"
        end
        if math.abs(first.amount - (max_damage * 2 + 40.5)) > 0.0001 then
            return "aggregated popup does not carry the summed damage"
        end
        if first.is_critical_strike ~= true then
            return "crit flag lost while aggregating a burst"
        end
        if DamageNumberPolicy.font_override(first.amount, max_damage) >= 1 then
            return "summed above-boundary popup does not engage the font bound"
        end
        if DamageNumberPolicy.is_due(first, 10) then
            return "popup came due before its aggregation window elapsed"
        end
        -- window * 2 sidesteps the binary-float boundary at exactly t + window.
        if not DamageNumberPolicy.is_due(first, 10 + window * 2) then
            return "popup never comes due"
        end
        -- ...and an out-of-window chunk starts a NEW popup, displacing the old
        -- one for emission.
        local fresh, old = DamageNumberPolicy.accumulate(groups, "k", 5, false, 10 + window * 2)
        if old ~= first or fresh == first or fresh.amount ~= 5 then
            return "out-of-window chunk did not start a new popup"
        end
    end)
end
