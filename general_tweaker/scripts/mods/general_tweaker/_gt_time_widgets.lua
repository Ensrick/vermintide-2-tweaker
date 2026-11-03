-- _gt_time_widgets.lua -- pure VMF time-control widget factory.
--
-- Consumes native-order preset rows from _gt_time_owner.presets and returns
-- fresh widget/options/default-key tables because VMF mutates dropdown labels.
-- The runtime owns authorization, recovery-key guards and transient freeze
-- resets; no unsupported persistence field is inferred from checkbox defaults.
-- Owned by: general_tweaker_data.lua. Consumed via: require.
local M = {}

local function keybind(id, callback, global)
    return {
        setting_id = id,
        type = "keybind",
        keybind_trigger = "pressed",
        keybind_type = "function_call",
        keybind_global = global == true,
        function_name = callback,
        default_value = {},
        tooltip = id .. "_tooltip",
    }
end

function M.build(presetRows)
    assert(type(presetRows) == "table" and #presetRows == 24, "time_presets_24_required")
    local options = {}
    for index = 1, 24 do
        local row = presetRows[index]
        assert(type(row) == "table" and row.index == index, "time_presets_native_order")
        options[index] = { text = "gt_time_preset_" .. index, value = row.index }
    end
    return {
        {
            setting_id = "time_scale_value",
            type = "dropdown",
            default_value = 13,
            options = options,
            tooltip = "time_scale_value_tooltip",
        },
        keybind("time_faster_hotkey", "gt_time_faster", false),
        keybind("time_slower_hotkey", "gt_time_slower", false),
        keybind("gt_time_normal_hotkey", "gt_time_normal", true),
        {
            setting_id = "gt_world_freeze_enabled",
            type = "checkbox",
            default_value = false,
            tooltip = "gt_world_freeze_enabled_tooltip",
        },
        keybind("pause_hotkey", "gt_pause_toggle", true),
    }
end

return M
