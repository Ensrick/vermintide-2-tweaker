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

    -- #1530: Mod Tweaker steps Base Power by 25 (#164/#389). The tooltip must
    -- attribute that grid to Mod Tweaker and must not repeat the stale 50-point
    -- claim. The craft-time reader only clamps to 0..950 and never quantizes,
    -- so an in-range live setting must come back unchanged. The registrar is
    -- bootstrap-owned; an offline harness without it simply skips registration.
    if type(mod._cim_rt_register) == "function" then
        mod._cim_rt_register("issue1530_base_power_step_wording", function()
            local ok, loc = pcall(mod.dofile, mod,
                "scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev_localization")
            if not ok or type(loc) ~= "table" then return end  -- loc unreachable; skip
            local entry = loc.base_power_level_description
            local text = type(entry) == "table" and entry.en or nil
            if type(text) ~= "string" then return "base_power_level_description is missing" end
            if not text:find("steps of 25 in Mod Tweaker", 1, true) then
                return "Base Power tooltip no longer attributes 25-point steps to Mod Tweaker"
            end
            if text:find("steps of 50", 1, true) then
                return "Base Power tooltip still claims 50-point steps"
            end
            if type(mod._cim_base_power) ~= "function" then return "_cim_base_power reader missing" end
            local setting, power = mod:get("base_power_level"), mod._cim_base_power()
            if type(power) ~= "number" or power < 0 or power > 950 then
                return "base power reader returned " .. tostring(power) .. " outside 0..950"
            end
            if type(setting) == "number" and setting >= 0 and setting <= 950 and power ~= setting then
                return string.format("reader quantized in-range setting %s to %s",
                    tostring(setting), tostring(power))
            end
        end)
    end
end

return M
