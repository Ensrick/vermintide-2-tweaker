local M = {}

function M.new_context(mod)
    local ctx = {
        mod = mod,
        state = {
            debug = mod:get("debug") == true,
            godmode = false,
            tp_enabled = false,
            tp_inst_patched = false,
            tp_offset_warned = false,
            tp_cam_dumped = false,
            granting_starting_coins = false,
            dump_boons = false,
            dump_chest_view = false,
            boon_loc_patched = false,
            all_trait_combos_cache = nil,
            modules = {},
        },
    }

    function ctx.feature_enabled(setting_id, default_value)
        local value = mod:get(setting_id)
        if value == nil then
            return default_value ~= false
        end

        return value == true
    end

    function ctx.module_enabled(setting_id)
        return ctx.feature_enabled(setting_id, true)
    end

    return ctx
end

return M
