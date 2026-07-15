-- _wt_bolt_staff_overcharge.lua -- Issue #341 Bolt Staff primary heat option.
--
-- Vanilla's two rapid primary sub-actions are the only actions in the decompile
-- that use overcharge_type="spark" (staff_spark_spear.lua:24,108). The charged
-- projectile utility resolves that key through PlayerUnitStatusSettings at fire
-- time (action_charged_projectile.lua:41-58), so this needs no action hook and no
-- weapon-template mutation.

local M = {}

M.SETTING_ID = "wt_bolt_staff_primary_overcharge_reduction"
M.MULTIPLIER = 0.6

function M.desired_value(baseline, enabled)
    if type(baseline) ~= "number" then return nil end
    return enabled and baseline * M.MULTIPLIER or baseline
end

function M.new_runtime(mod, status_settings, print_fn)
    local runtime = {}
    local snapshot_set = false
    local baseline

    local function values()
        local settings = status_settings or rawget(_G, "PlayerUnitStatusSettings")
        return settings and settings.overcharge_values
    end

    local function emit(fmt, ...)
        local output = print_fn or rawget(_G, "printf")
        if type(output) == "function" then pcall(output, fmt, ...) end
    end

    function runtime.apply()
        local overcharge_values = values()
        if type(overcharge_values) ~= "table" then return false end
        if not snapshot_set then
            if type(overcharge_values.spark) ~= "number" then return false end
            baseline = overcharge_values.spark
            snapshot_set = true
        end
        local enabled = mod:get(M.SETTING_ID) == true
        local desired = M.desired_value(baseline, enabled)
        if overcharge_values.spark ~= desired then
            overcharge_values.spark = desired
            emit("[wt:341] Bolt Staff primary overcharge state=%s baseline=%.3f applied=%.3f",
                enabled and "reduced" or "vanilla", baseline, desired)
        end
        return true
    end

    function runtime.revert()
        local overcharge_values = values()
        if not snapshot_set or type(overcharge_values) ~= "table" then return false end
        if overcharge_values.spark ~= baseline then
            overcharge_values.spark = baseline
            emit("[wt:341] Bolt Staff primary overcharge reverted=%.3f", baseline)
        end
        return true
    end

    function runtime.baseline()
        return snapshot_set and baseline or nil
    end

    return runtime
end

return M
