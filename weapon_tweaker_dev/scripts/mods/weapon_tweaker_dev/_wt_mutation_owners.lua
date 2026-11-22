-- _wt_mutation_owners.lua -- WP-WT-07: wt's weapon-table owners and their one
-- order, registered into the ordered registry (_wt_mutation_registry.lua).
--
-- Every lifecycle event calls registry.reconcile(reason): game_state and
-- re-enable (_wt_apply_all in the entry), rework_master (entry), peer_parity
-- (_wt431_damage_profile_parity.lua), cwv_transition (weapon_tweaker_backend.lua)
-- and settings_batch (_wt_settings_runtime.lua). on_disabled calls
-- registry.revert_all(), which runs the reverts in the reverse order.
--
-- Order rationale (what each owner writes):
--   10 availability    ItemMasterList[*].can_wield
--   20 career_actions  career ability rows in Weapons[*].actions
--   30 energy          EnergyData only, so its position is free
--   40 history_and_axe history reprojection plus the axe/cog/executioner/
--                      mace-sword overlay and its damage-profile clones; it also
--                      writes the Bret template, so it runs before order 60
--   50 priest_punch    two_handed_hammer_priest_template punch repoint
--   60 bret            one_handed_sword_shield_template_2 repoints
--   70 brace_repoint   Brace of Pistols repoint (mod field absent today: no-op)
--   80 bolt_staff      PlayerUnitStatusSettings spark overcharge only
--   90 fire_sword      flaming_sword_template_1; installed on top of the axe
--                      policy (_wt_fire_sword_owner), so after history
-- The profile repoints (50-70) read mod._wt431_profiles_allowed(), which is
-- false while wt is disabled, so the same call applies or reverts them.
--
-- Not registered, applied once at load and not revertible: authentic brace
-- (_wt_weapon_balance_patches.lua:371), the #348 Empire 1H sword push-combo
-- revert, the cross-character template patches
-- (_wt_cross_char_template_patches.lua) and the Deepwood guard.
--
-- Pure: every owner is a late-bound closure over `mod` fields or the entry
-- handles passed in `deps`, checked before each call.

local M = {}

-- deps = { apply_weapon_unlocks, clear_weapon_unlocks, patch_career_actions,
--          clear_career_actions, history_owner, bolt_runtime }
function M.register(reg, mod, deps)
    deps = deps or {}
    local function call(name, ...)
        local fn = mod[name]
        if fn then return fn(...) end
    end
    local function late(name) return function() call(name) end end
    local function dep(name, method)
        return function()
            local handle = deps[name]
            if not handle then return end
            if method then return handle[method](handle) end
            return handle()
        end
    end

    reg.register({ id = "availability", order = 10,
        apply = dep("apply_weapon_unlocks"), revert = dep("clear_weapon_unlocks") })
    reg.register({ id = "career_actions", order = 20,
        apply = dep("patch_career_actions"), revert = dep("clear_career_actions") })
    reg.register({ id = "energy", order = 30,
        apply = late("_wt374_seed_energy_data"), revert = late("_wt374_revert_energy_data") })
    reg.register({ id = "history_and_axe", order = 40,
        apply = function(reason)
            if mod._wt_reconcile_history_owner_stack then
                local ok, problem = mod._wt_reconcile_history_owner_stack(reason)
                if ok ~= true then error("history reconcile: " .. tostring(problem), 0) end
            elseif mod._wt_apply_axe_balance then
                mod._wt_apply_axe_balance(nil, false)
            end
        end,
        revert = function()
            local owner = deps.history_owner
            if owner then owner:restore() end
        end })
    reg.register({ id = "priest_punch", order = 50,
        apply = late("wt_apply_priest_punch_buff"), revert = late("wt_apply_priest_punch_buff") })
    reg.register({ id = "bret", order = 60,
        apply = late("wt_apply_brett_buff"), revert = late("wt_apply_brett_buff") })
    reg.register({ id = "brace_repoint", order = 70,
        apply = late("_wt431_brace_repoint"), revert = late("_wt431_brace_repoint") })
    reg.register({ id = "bolt_staff", order = 80,
        apply = function() local r = deps.bolt_runtime; if r then r.apply() end end,
        revert = function() local r = deps.bolt_runtime; if r then r.revert() end end })
    reg.register({ id = "fire_sword", order = 90,
        apply = function() call("_wt_apply_fire_sword", nil, false) end,
        revert = function() call("_wt_apply_fire_sword", nil, true) end })
    return reg
end

return M
