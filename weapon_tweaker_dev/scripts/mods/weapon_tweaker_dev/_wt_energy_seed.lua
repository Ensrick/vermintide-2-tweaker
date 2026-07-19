--[[
_wt_energy_seed.lua -- issues #374/#388: EnergyData rows for careers granted an
energy weapon (Moonfire Bow family). Engine-free policy module: pure helpers
plus a bounded apply/revert over tables the caller passes in; safe to dofile
offline (qa/lua/tests/test_wt_energy_seed.lua).

MECHANISM (decompile-cited). Energy state is initialized from the global
`EnergyData[career_name] or {}` read on the LOCAL machine at every spawn path:
  owner  scripts/managers/player/bulldozer_player.lua:207
  bot    scripts/managers/player/player_bot.lua:140
  husk   scripts/network/game_object_initializers_extractors.lua:2128,2296
and both extensions copy the row's fields at init
(player_unit_energy_extension.lua:14-20, player_husk_energy_extension.lua:13-20;
the husk row covers player_husk_energy_extension per #374's husk requirement).
Vanilla defines rows ONLY for the four Kerillian careers, each
{ depletion_cooldown = 5, max_value = 25, recharge_delay = 0.2,
  recharge_rate = 1.5 } (energy_data.lua:4-27). A missing row defaults
recharge_delay / recharge_rate to 0 (player_unit_energy_extension.lua:14-20),
so a cross-character Moonfire never recharges natively (#374), is_drainable
never transitions, and the on_energy_drainable / on_energy_not_drainable
equipment flow events never fire - weapon FX/sounds/HUD presentation dead
(#388, player_unit_energy_extension.lua:50-63). Energy weapons are recognized
by their action kinds "bow_energy" / "aim_energy" (we_deus_01.lua:27,110,180,258).

DESIGN:
 * Seed a PRIVATE row per granted career, cloned per career from SEED - never
   one shared table (shared-template mutation trap: a later per-career write
   through a shared row would hit every seeded career).
 * Only ADD missing rows. Never touch an existing row (the native we_ rows, or
   a row another mod owns). Rows we add carry the _wt374_seeded marker so
   revert removes exactly ours and nothing else.
 * Rows stay for the session once added (a mid-session removal could race a
   spawn back onto the {} default); mod.on_disabled reverts them.
 * WIRE SAFETY: EnergyData is a local table - nothing modded rides an RPC or
   NetworkLookup, so this is NOT peer-parity gated. The owner-authoritative
   game-object fields the extension syncs (energy_percentage /
   energy_max_value / is_on_depletion_cooldown,
   player_unit_energy_extension.lua:32-48) are vanilla fields, and max_value
   25 equals the vanilla Kerillian value inside NetworkConstants.max_energy
   bounds, so unmodded peers decode them exactly as they do for Kerillian.
 * #584 relationship: _wt_passive_charge's owner-side Moonfire regen plan
   self-gates on `native_rate ~= nil and native_rate ~= 0`
   (M.energy_update_plan), so a unit spawned AFTER seeding (extension
   _recharge_rate 1.5) makes the workaround return nil - no double regen. The
   workaround keeps covering owner units spawned before a seed existed; husks,
   bots, and the flow events needed the real row, which is this module.

Owned by: weapon_tweaker.lua entry point (mod._wt374_seed_energy_data /
mod._wt374_revert_energy_data). Consumed via: mod:dofile.
]]

local M = {}

-- Exact vanilla Kerillian row (energy_data.lua:4-27).
M.SEED = {
    depletion_cooldown = 5,
    max_value = 25,
    recharge_delay = 0.2,
    recharge_rate = 1.5,
}

M.ROW_MARKER = "_wt374_seeded"

-- "Does this weapon template drain the energy_system bar?" Marker is an action
-- of kind "bow_energy" or "aim_energy" (we_deus_01.lua:27,110,180,258) - the
-- same predicate shape _wt_passive_charge uses at the wielded-slot level; kept
-- here template-level so this module stays engine-free and self-contained.
function M.is_energy_weapon_template(item_template)
    if type(item_template) ~= "table" then
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

-- Pure: the set of careers currently allowed to wield ANY energy weapon,
-- derived from the FINAL can_wield state of the item list - so it covers
-- grants made by wt's own unlock toggles AND rows other mods (CWV) created or
-- extended, whoever granted them.
function M.energy_careers(item_master_list, weapons)
    local out = {}
    if type(item_master_list) ~= "table" or type(weapons) ~= "table" then
        return out
    end
    for _, entry in pairs(item_master_list) do
        if type(entry) == "table" and type(entry.template) == "string" then
            local template = weapons[entry.template]
            if template and M.is_energy_weapon_template(template) then
                local can_wield = entry.can_wield
                if type(can_wield) == "table" then
                    for _, career_name in ipairs(can_wield) do
                        if type(career_name) == "string" then
                            out[career_name] = true
                        end
                    end
                end
            end
        end
    end
    return out
end

-- Bounded apply: add a private row for every career in `careers` that has no
-- EnergyData row yet. Returns the number added and appends their names to
-- `added_names` (optional, for the caller's one-line printf).
function M.apply(energy_data, careers, added_names)
    local added = 0
    if type(energy_data) ~= "table" or type(careers) ~= "table" then
        return added
    end
    for career_name in pairs(careers) do
        if energy_data[career_name] == nil then
            -- Fresh table per career - never a shared reference.
            energy_data[career_name] = {
                depletion_cooldown = M.SEED.depletion_cooldown,
                max_value = M.SEED.max_value,
                recharge_delay = M.SEED.recharge_delay,
                recharge_rate = M.SEED.recharge_rate,
                [M.ROW_MARKER] = true,
            }
            added = added + 1
            if type(added_names) == "table" then
                added_names[#added_names + 1] = career_name
            end
        end
    end
    return added
end

-- Exact restore: remove only rows still carrying our marker. A row replaced by
-- someone else since we seeded it is theirs now - leave it.
function M.revert(energy_data)
    local removed = 0
    if type(energy_data) ~= "table" then
        return removed
    end
    for career_name, row in pairs(energy_data) do
        if type(row) == "table" and row[M.ROW_MARKER] == true then
            energy_data[career_name] = nil
            removed = removed + 1
        end
    end
    return removed
end

-- Defines the mod-table entry points and runs the initial seed. Called once
-- from weapon_tweaker_backend.lua M.install; the entry point re-runs
-- mod._wt374_seed_energy_data() at every availability seam
-- (on_game_state_changed, unlock setting changes, the backend deferred /
-- CWV-transition re-applies) and mod._wt374_revert_energy_data() from
-- on_disabled. Globals are read via rawget at CALL time, so the offline test
-- harness can stub _G.EnergyData / ItemMasterList / Weapons around each call.
function M.install(mod)
    mod._wt374_seed_energy_data = function()
        local energy_data = rawget(_G, "EnergyData")
        local iml = rawget(_G, "ItemMasterList")
        local weapons = rawget(_G, "Weapons")
        if type(energy_data) ~= "table" or type(iml) ~= "table" or type(weapons) ~= "table" then
            return 0
        end
        local careers = M.energy_careers(iml, weapons)
        local added_names = {}
        local added = M.apply(energy_data, careers, added_names)
        if added > 0 then
            table.sort(added_names)
            local _printf = rawget(_G, "printf")
            if _printf then
                pcall(_printf, "[wt:374] EnergyData seeded for %d career(s): %s (rate=%.1f delay=%.1f max=%d cooldown=%d)",
                    added, table.concat(added_names, ", "),
                    M.SEED.recharge_rate, M.SEED.recharge_delay,
                    M.SEED.max_value, M.SEED.depletion_cooldown)
            end
        end
        return added
    end
    mod._wt374_revert_energy_data = function()
        local energy_data = rawget(_G, "EnergyData")
        if type(energy_data) ~= "table" then
            return 0
        end
        local removed = M.revert(energy_data)
        if removed > 0 then
            local _printf = rawget(_G, "printf")
            if _printf then
                pcall(_printf, "[wt:374] EnergyData seed reverted (%d row(s) removed)", removed)
            end
        end
        return removed
    end
    -- Load-time seed (idempotent; a no-op until ItemMasterList/Weapons exist -
    -- the availability-seam re-runs cover late grants and CWV's late rows).
    mod._wt374_seed_energy_data()
    return M
end

return M
