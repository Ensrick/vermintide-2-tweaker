-- VMF single-setting and GUI Tweaker owner-batch lifecycle.

local M = {}

function M.install(c)
    local mod = c.mod
    mod.on_setting_changed = function(setting_id)
        if c.rework_runtime:is_batching() then return end
        if c.rework_runtime:on_master_changed(setting_id) then return end
        if setting_id == "enable_weapon_backend_hooks" then
            c.backend.clear_loadout_cache("backend-hook-setting-changed")
        elseif setting_id and setting_id:find("^wtmaster_") then
            c.master_toggles.on_master_changed(mod, setting_id)
            c.apply_weapon_unlocks()
            c.patch_career_actions()
            if mod._wt374_seed_energy_data then mod._wt374_seed_energy_data() end
            c.backend.refresh_on_setting_change(mod)
        elseif setting_id and (setting_id:find("^unlock_") or setting_id == "debug") then
            c.apply_weapon_unlocks()
            c.patch_career_actions()
            if mod._wt374_seed_energy_data then mod._wt374_seed_energy_data() end
            c.backend.refresh_on_setting_change(mod)
            if setting_id:find("^unlock_") then
                c.master_toggles.on_child_changed(mod, setting_id)
            end
        elseif setting_id and (setting_id:find("^trait_") or setting_id:find("^cw_trait_")) then
            c.apply_trait_filters()
        elseif c.extra_setting and c.extra_setting(setting_id) then
            -- Friends-only dev controls retain their isolated owner.
        elseif setting_id == "wt_priest_punch_buff" then
            if mod.wt_apply_priest_punch_buff then mod.wt_apply_priest_punch_buff() end
        elseif setting_id == "wt_brett_sword_shield_buff" then
            if mod.wt_apply_brett_buff then mod.wt_apply_brett_buff() end
        elseif setting_id == c.bolt_policy.SETTING_ID then
            c.bolt_runtime.apply()
        elseif setting_id == c.balance_policy.GREATAXE_LIGHT_CRIT_SETTING
                or setting_id == c.balance_policy.DUAL_AXES_LIGHT_CRIT_SETTING
                or setting_id == c.balance_policy.DUAL_AXES_CLEAVE_SETTING
                or setting_id == c.balance_policy.ONE_HAND_AXE_CLEAVE_SETTING
                or setting_id == c.balance_policy.COG_HAMMER_HEAVY_SPEED_SETTING
                or setting_id == c.balance_policy.MACE_SWORD_SPEED_SETTING
                or setting_id == c.balance_policy.EXECUTIONER_LIGHT_HEADSHOT_SETTING then
            mod._wt_apply_axe_balance(setting_id, false)
        elseif c.fire_sword_policy
                and (setting_id == c.fire_sword_policy.SWEEP_OPENER_SETTING
                or setting_id == c.fire_sword_policy.NOVA_SLOWDOWN_SETTING) then
            mod._wt_apply_fire_sword(setting_id, false)
        end
        c.rework_runtime:sync_for_leaf(setting_id)
    end

    -- #1002: N silent persisted writes, master reconciliation, one live apply.
    mod.on_settings_batch_changed = function(setting_ids)
        for _, setting_id in ipairs(setting_ids or {}) do
            if setting_id == "enable_weapon_backend_hooks" then
                c.backend.clear_loadout_cache("backend-hook-setting-batch")
                break
            end
        end
        c.master_toggles.reconcile_batch(mod, setting_ids)
        if not c.rework_runtime:prepare_batch(setting_ids) then
            error("WT rework master batch reconciliation failed")
        end
        c.apply_weapon_unlocks()
        c.patch_career_actions()
        if mod._wt374_seed_energy_data then mod._wt374_seed_energy_data() end
        c.backend.refresh_on_setting_change(mod)
        c.apply_trait_filters()
        if mod.wt_apply_priest_punch_buff then mod.wt_apply_priest_punch_buff() end
        if mod.wt_apply_brett_buff then mod.wt_apply_brett_buff() end
        c.bolt_runtime.apply()
        if mod._wt_apply_axe_balance then mod._wt_apply_axe_balance(nil, false) end
        if mod._wt_apply_fire_sword then mod._wt_apply_fire_sword(nil, false) end
        if c.extra_batch then c.extra_batch(setting_ids) end
        pcall(printf, "[wt:1002] settings=%d availability_applies=1 action_applies=1",
            type(setting_ids) == "table" and #setting_ids or 0)
    end
end

return M
