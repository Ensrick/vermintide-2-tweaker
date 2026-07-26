local M = {}

function M.install(mod, apply_movespeed, printf)
    mod.on_setting_changed = function(setting_id)
        if setting_id == "movespeed_2pct_mode" then
            apply_movespeed()
        end
    end

    mod.on_settings_batch_changed = function(setting_ids)
        for i = 1, #(setting_ids or {}) do
            if setting_ids[i] == "movespeed_2pct_mode" then
                apply_movespeed()
                break
            end
        end
        pcall(printf, "[cim:1002] settings=%d notifications=1",
            #(setting_ids or {}))
    end
end

return M
