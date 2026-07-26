-- VMF single-setting and GUI Tweaker owner-batch lifecycle.

local M = {}

function M.install(mod, hats, gk_set, tpe)
    mod.on_setting_changed = function(setting_id)
        if setting_id == "cos_encarmine_hat_enabled" and hats then hats.sync_toggle() end
        if gk_set and (gk_set.is_availability_setting(setting_id)
                or setting_id == "cos_fk_reikland_griffin_enabled") then
            gk_set.sync_toggle()
        end
        if setting_id and setting_id:sub(1, 11) == "cos_unlock_" then
            mod._cos.apply_cosmetic_unlocks()
        end
        if setting_id and setting_id:sub(1, 5) == "glow_"
                and mod._on_glow_setting_changed then
            mod._on_glow_setting_changed()
        end
        if tpe and tpe.on_setting_changed then tpe.on_setting_changed(setting_id) end
    end

    -- #1002: coalesce each Cosmetics side effect across Equipment DEFAULT.
    mod.on_settings_batch_changed = function(setting_ids)
        local hat, gk, unlocks, glow, flush = false, false, false, false, false
        for i = 1, #(setting_ids or {}) do
            local id = setting_ids[i]
            if id == "cos_encarmine_hat_enabled" then hat = true end
            if gk_set and (gk_set.is_availability_setting(id)
                    or id == "cos_fk_reikland_griffin_enabled") then gk = true end
            if type(id) == "string" and id:sub(1, 11) == "cos_unlock_" then unlocks = true end
            if type(id) == "string" and id:sub(1, 5) == "glow_" then glow = true end
            if id == "tpe_enable" or id == "tpe_downscale_big_weapons"
                    or id == "tpe_show_self_in_3p" then flush = true end
        end
        if hat and hats then hats.sync_toggle() end
        if gk and gk_set then gk_set.sync_toggle() end
        if unlocks then mod._cos.apply_cosmetic_unlocks() end
        if glow and mod._on_glow_setting_changed then mod._on_glow_setting_changed() end
        if flush and tpe and tpe.flush then tpe.flush() end
        pcall(printf, "[cos:1002] settings=%d side_effects=%d",
            #(setting_ids or {}), (hat and 1 or 0) + (gk and 1 or 0)
                + (unlocks and 1 or 0) + (glow and 1 or 0) + (flush and 1 or 0))
    end
end

return M
