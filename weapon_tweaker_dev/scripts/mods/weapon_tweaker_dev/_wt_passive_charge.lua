--[[
============================================================================
 _wt_passive_charge.lua — restore passive overcharge-vent / energy-regen for
 cross-character overcharge weapons (Sienna staves) and the Moonfire Bow when
 wielded on a career that does NOT natively have the mechanic.
============================================================================

WHY THIS EXISTS
  Both mechanics are read from a CAREER-KEYED data table at player spawn, not
  from the weapon template:

   * Overcharge passive decay rate comes from `OverchargeData[career_name]`
     (`bulldozer_player.lua:206`). The overcharge extension stores it as
     `self.overcharge_value_decrease_rate` (`player_unit_overcharge_extension
     .lua:25`) and its stock `update` loop only vents when that field > 0
     (rate is used at line 290). A non-Sienna career has no OverchargeData
     entry -> rate 0 -> a cross-character Sienna staff never passively vents.
     The staff's OWN `weapon_template.overcharge_data.overcharge_value_decrease
     _rate` is vestigial (never read by the extension).

   * Moonfire Bow ("charge"/energy) regen comes from `EnergyData[career_name]`
     (`bulldozer_player.lua:207`), stored as `self._recharge_rate`
     (`player_unit_energy_extension.lua:18`). Only the four Kerillian careers
     have an EnergyData entry (rate 1.5/s). On any other career the lookup
     falls back to `{}` -> recharge_rate 0 -> the bow drains and never refills,
     so it bricks after ~8 shots.

WHAT THIS DOES
  Each frame, for the LOCAL OWNED player ONLY, drive a cross-character staff
  when wielded or Moonfire when equipped in slot_ranged, on careers lacking
  the native rate, via the vanilla CONSUMPTION-SIDE APIs:
   * STAVES   -> overcharge_ext:remove_charge(STAFF_VENT_RATE * dt)   (vent)
   * MOONFIRE -> energy_ext:add_energy(MOONFIRE_REGEN_RATE * dt)      (regen)

HARD CONSTRAINTS HONORED
  (a) CONSUMPTION SIDE ONLY. We call `remove_charge` / `add_energy`, both of
      which clamp internally. We NEVER write `_max_overcharge` / `max_value` /
      `_max_energy` (engine NetworkConstants cap -> fassert crash; see memory
      `feedback_vt2_max_resource_consumption_side`).
  (b) NETWORKING. Overcharge and energy are OWNER-AUTHORITATIVE (the owning
      peer simulates and broadcasts the value via the game object; husks are
      read-only). We drive ONLY `Managers.player:local_player().player_unit`,
      so the local human's own value is corrected on the peer that owns it and
      replicated automatically. Remotes and bots are never touched here (a bot
      is owned by the host, but bots can't wield cross-character mod weapons
      anyway, and host-side bot loadouts are out of scope for this local tick).
  (c) CROSS-CHARACTER ONLY. We gate on the LIVE native rate being 0/absent
      (`overcharge_value_decrease_rate == 0` / `_recharge_rate == 0` or nil),
      so any career that NATIVELY vents/regens (every Sienna career, the four
      Kerillian careers, drakefire dwarves, etc.) is left completely untouched.
  (e) nil/type-safe. `ScriptUnit.has_extension` (never fatals) for every
      extension; weapon-may-not-be-wielded guarded; the whole per-unit body is
      wrapped in pcall so an unexpected engine fatal can't take the frame down.

NOT A HOOK. This module exposes a single `tick(dt)` that is called from the
existing `mod.update` in weapon_tweaker_backend.lua (the one per-frame surface
VMF schedules). No `mod:hook` is added, so there is no duplicate-hook concern.
============================================================================
]]

local mod = get_mod("wt_dev")

local M = {}

-- v0.12.151-dev: the former `wt_passive_charge_restore` VMF toggle was REMOVED.
-- The behavior is now implicit/always-on (it just mirrors native-career function;
-- see M.tick). No SETTING_ID is read anymore — the widget + loc keys were deleted
-- from weapon_tweaker_data.lua / weapon_tweaker_localization.lua in the same change.

-- STAVES: matches the native Sienna-staff career rate
-- (`overcharge_data.lua:41/52/63` = 1 for bw_scholar/bw_adept/bw_unchained;
-- the staves' own template overcharge_value_decrease_rate is also 1). We drive
-- the base rate directly; the stock loop's 0.6 above-threshold multiplier and
-- post-shot start-decreasing delay are deliberately NOT reproduced (consumption
-- -side simplicity — vent is steady and faithful to the base rate).
local STAFF_VENT_RATE = 1.0

-- MOONFIRE BOW: matches the native Kerillian energy regen rate
-- (`energy_data.lua:4-27` recharge_rate = 1.5 energy/sec).
local MOONFIRE_REGEN_RATE = 1.5

-- ScriptUnit / Managers are engine globals; cache the table lookups we touch
-- every frame to keep the hot path cheap (PROJECT_STANDARDS § 3.6 allows
-- per-frame mod:get, but bare global churn is still avoidable).
local ScriptUnit = ScriptUnit

-- Resolve one inventory slot's item_template. Returns nil if the slot/template
-- can't be resolved. Keeping this slot-based is important for Moonfire: native
-- energy recharge follows the equipped ranged item while melee is wielded.
-- All accessors guarded because mid-swap / mid-spawn the slot data can be
-- transiently absent.
local function _slot_item_template(inv, slot_name)
    if not inv or not slot_name or not inv.get_slot_data then
        return nil
    end
    local slot_data = inv:get_slot_data(slot_name)
    if not slot_data then
        return nil
    end

    if not inv.get_item_template then
        return nil
    end

    -- get_item_template -> BackendUtils.get_item_template(item_data); can
    -- error on a malformed slot_data, so isolate it.
    local ok, item_template = pcall(inv.get_item_template, inv, slot_data)
    if not ok then
        return nil
    end

    return item_template
end

local function _wielded_item_template(inv)
    if not inv or not inv.get_wielded_slot_name then
        return nil
    end

    return _slot_item_template(inv, inv:get_wielded_slot_name())
end

-- "Is this an overcharge weapon?" The marker is the weapon template carrying an
-- `overcharge_data` table (staves, drakefire, etc.). The extension's rate is
-- read from OverchargeData[career], NOT this table, so its presence is purely
-- a "this weapon uses the overcharge bar" flag.
local function _is_overcharge_weapon(item_template)
    return item_template ~= nil and item_template.overcharge_data ~= nil
end

-- "Is this an energy-charge weapon (Moonfire / energy bow)?" The marker is an
-- action of kind "bow_energy" or "aim_energy" (we_deus_01 template), i.e. the
-- weapon drains/uses the energy_system bar rather than real ammo.
local function _is_energy_weapon(item_template)
    if item_template == nil then
        return false
    end

    local actions = item_template.actions
    if type(actions) ~= "table" then
        return false
    end

    for _, action in pairs(actions) do
        if type(action) == "table" then
            for _, sub_action in pairs(action) do
                if type(sub_action) == "table" then
                    local kind = sub_action.kind
                    if kind == "bow_energy" or kind == "aim_energy" then
                        return true
                    end
                end
            end
        end
    end

    return false
end

-- #584 regression seam and runtime predicate. This deliberately ignores the
-- wielded slot: Moonfire's vanilla Kerillian energy system recharges while the
-- bow is stowed, so cross-character parity must be keyed to slot_ranged too.
-- A slot swap immediately changes the returned value and there is only one
-- caller in _drive_local_player, preventing wielded+equipped double application.
function M.energy_weapon_in_ranged_slot(inv)
    return _is_energy_weapon(_slot_item_template(inv, "slot_ranged"))
end

-- Pure owner-side planner used by the driver and regression coverage. One
-- ranged-slot read selects exactly one action, making recharge/reset mutually
-- exclusive and preserving #584's no-double-application invariant.
function M.energy_update_plan(inv, native_rate, dt, energy, max_energy)
    if native_rate ~= nil and native_rate ~= 0 then
        return nil
    end

    if M.energy_weapon_in_ranged_slot(inv) then
        if not dt or dt <= 0 then
            return nil
        end
        return "recharge", MOONFIRE_REGEN_RATE * dt
    end

    if type(energy) ~= "number" or type(max_energy) ~= "number"
        or energy >= max_energy
    then
        return nil
    end

    return "reset_stale_hud", max_energy - energy
end

function M.energy_regen_delta(inv, native_rate, dt)
    local action, delta = M.energy_update_plan(inv, native_rate, dt)
    return action == "recharge" and delta or nil
end

-- Vanilla EnergyBarUI has no item eligibility check: it draws whenever the
-- always-present energy extension is below full. A non-Kerillian career has a
-- zero native recharge rate, so removing Moonfire would otherwise strand that
-- value below max and leave the bar visible forever (#585). Return a one-shot
-- consumption-side delta only after slot_ranged ceases to be an energy weapon.
function M.stale_energy_hud_reset_delta(inv, native_rate, energy, max_energy)
    local action, delta = M.energy_update_plan(
        inv, native_rate, nil, energy, max_energy
    )
    return action == "reset_stale_hud" and delta or nil
end

-- Per-unit body. Resolves the wielded weapon for staff venting and the equipped
-- ranged weapon for Moonfire, then drives the missing mechanic if (and only if)
-- the career lacks the native rate.
-- Returns silently on any nil — this runs every frame, so it must be cheap and
-- must never fatal.
local function _drive_local_player(player_unit, dt)
    if not Unit.alive(player_unit) then
        return
    end

    local inv = ScriptUnit.has_extension(player_unit, "inventory_system")
    if not inv then
        return
    end

    local item_template = _wielded_item_template(inv)

    -- --- STAVES: passive vent (decrease overcharge) ---
    if item_template and _is_overcharge_weapon(item_template) then
        local oc = ScriptUnit.has_extension(player_unit, "overcharge_system")
        -- Gate (c): only when the career has NO native decay rate. A career
        -- that natively vents (any Sienna career, etc.) has a non-zero rate
        -- and is left entirely untouched -- its stock update loop handles it.
        if oc and oc.overcharge_value_decrease_rate ~= nil
            and oc.overcharge_value_decrease_rate == 0
        then
            -- Only vent when there's something to vent (mirrors the vanilla
            -- decay-loop gate at player_unit_overcharge_extension.lua:270;
            -- also avoids firing the on_overcharge_lost proc with 0 each frame).
            local overcharge_value = oc.overcharge_value
            if overcharge_value and overcharge_value > 0 and oc.remove_charge then
                pcall(oc.remove_charge, oc, STAFF_VENT_RATE * dt)
            end
        end
    end

    -- --- MOONFIRE BOW: passive energy regen ---
    local energy_ext = ScriptUnit.has_extension(player_unit, "energy_system")
    local energy_action, energy_delta
    if energy_ext then
        energy_action, energy_delta = M.energy_update_plan(
            inv,
            energy_ext._recharge_rate,
            dt,
            energy_ext._energy,
            energy_ext._max_energy
        )
    end
    if energy_action == "recharge" then
        -- Gate (c): only when the career has NO native regen rate. The four
        -- Kerillian careers carry _recharge_rate = 1.5 and are left untouched.
        local energy = energy_ext._energy
        local max_energy = energy_ext._max_energy
        -- Only add when below max (add_energy clamps anyway, but this skips
        -- the pointless call). Refill at the native rate.
        if energy and max_energy and energy < max_energy and energy_ext.add_energy then
            pcall(energy_ext.add_energy, energy_ext, energy_delta)
        end
    elseif energy_action == "reset_stale_hud" then
        if energy_ext.add_energy then
            local ok = pcall(energy_ext.add_energy, energy_ext, energy_delta)
            if ok then
                -- Bounded naturally: after the successful max-energy delta,
                -- the predicate returns nil until Moonfire is drained again
                -- and subsequently removed.
                mod:info("[wt:585] cleared stale energy HUD after ranged-slot replacement")
            end
        end
    end
end

-- Public entry: called from weapon_tweaker_backend.lua's mod.update each frame.
-- Drives ONLY the local owned player unit (owner-authoritative networking).
function M.tick(dt)
    if not dt or dt <= 0 then
        return
    end

    -- v0.12.151-dev: ALWAYS ON (toggle removed). This was never meant to be a
    -- user choice — it just mirrors how these weapons natively function on their
    -- own career: a Sienna staff vents overcharge and the Moonfire Bow regens
    -- its charge. On a cross-character wielder the career-keyed native rate is 0
    -- (gate (c) in _drive_local_player), so without this the weapon would be
    -- permanently broken (staff never vents / bow bricks after ~8 shots). Making
    -- it implicit restores parity with the native career instead of leaving a
    -- toggle that, off, ships an unusable weapon. The cross-character gate inside
    -- _drive_local_player still leaves NATIVE wielders entirely untouched.

    local pm = Managers and Managers.player
    if not pm or not pm.local_player then
        return
    end

    local ok_pl, player = pcall(pm.local_player, pm)
    if not ok_pl or not player then
        return
    end

    local player_unit = player.player_unit
    if not player_unit then
        return
    end

    -- Whole per-unit body in pcall: a Stingray *.node-class fatal would bypass
    -- the inner pcalls; this is the outer safety net so the feature can never
    -- take down the frame loop.
    pcall(_drive_local_player, player_unit, dt)
end

return M
