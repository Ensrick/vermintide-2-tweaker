-- Lifecycle and composition owner for source-proven weapon history (#1436).
--
-- Installation happens before ordinary balance owners so the selected
-- historical state is their baseline. Reconciliation later reverts the
-- ordinary 1H-Axe overlay, reprojects history, then reapplies that overlay.
local M = {}

local function report(format, ...)
    local printer = rawget(_G, "printf")
    if type(printer) == "function" then
        pcall(printer, "[wt:1436] ERROR " .. format, ...)
    end
end

function M.install(config)
    local mod = assert(config.mod, "mod required")
    local module_root = assert(config.module_root, "module root required")
    local catalog_module = mod:dofile(module_root .. "_wt_history_catalog")
    local policy = mod:dofile(module_root .. "_wt_history_policy")
    local runtime_module = mod:dofile(module_root .. "_wt_history_runtime")
    local catalog, catalog_error = catalog_module.load(mod)
    local owner = {
        catalog_error = catalog_error,
        mod = mod,
        runtime = nil,
    }

    if catalog then
        owner.runtime = runtime_module.install({
            catalog = catalog,
            mod = mod,
            policy = policy,
            roots = function()
                return {
                    BuffTemplates = rawget(_G, "BuffTemplates"),
                    ExplosionTemplates = rawget(_G, "ExplosionTemplates"),
                    PlayerUnitStatusSettings = rawget(_G, "PlayerUnitStatusSettings"),
                    Weapons = rawget(_G, "Weapons"),
                }
            end,
        })
        mod._wt_history_runtime = owner.runtime
    else
        report("history runtime unavailable: %s", tostring(catalog_error))
    end

    function owner:reconcile(reason)
        if type(self.mod._wt_apply_axe_balance) == "function" then
            local ok, apply_error = pcall(self.mod._wt_apply_axe_balance, nil, true)
            if not ok then
                report("overlay revert failed (%s): %s",
                    tostring(reason), tostring(apply_error))
                return nil, apply_error
            end
        end
        if type(self.mod._wt_reset_axe_balance_baselines) == "function" then
            local ok, reset, reset_error = pcall(
                self.mod._wt_reset_axe_balance_baselines)
            if not ok or reset ~= true then
                local problem = ok and reset_error or reset
                report("overlay baseline reset failed (%s): %s",
                    tostring(reason), tostring(problem))
                return nil, problem
            end
        end

        local history_result = { refused = 0 }
        if self.runtime then
            local ok, result, history_error = pcall(
                self.runtime.reapply, self.runtime)
            if not ok or type(result) ~= "table" then
                local problem = ok and history_error or result
                report("baseline reprojection failed (%s): %s",
                    tostring(reason), tostring(problem))
                if type(self.mod._wt_apply_axe_balance) == "function" then
                    pcall(self.mod._wt_apply_axe_balance, nil, false)
                end
                return nil, problem
            end
            history_result = result
        end
        if type(self.mod._wt_apply_axe_balance) == "function" then
            local ok, apply_error = pcall(self.mod._wt_apply_axe_balance, nil, false)
            if not ok then
                report("overlay reapply failed (%s): %s",
                    tostring(reason), tostring(apply_error))
                return nil, apply_error
            end
        end
        if history_result.refused ~= 0 then
            return nil, tostring(history_result.refused) .. " history families refused"
        end
        return true, history_result
    end

    function owner:restore()
        local first_error
        if type(self.mod._wt_apply_axe_balance) == "function" then
            local ok, apply_error = pcall(self.mod._wt_apply_axe_balance, nil, true)
            if not ok then first_error = apply_error end
        end
        if type(self.mod._wt_reset_axe_balance_baselines) == "function" then
            local ok, reset, reset_error = pcall(
                self.mod._wt_reset_axe_balance_baselines)
            if not ok or reset ~= true then
                first_error = first_error or (ok and reset_error or reset)
            end
        end
        if self.runtime then
            local ok, restored, restore_error = pcall(
                self.runtime.restore, self.runtime)
            if not ok or not restored
                    or (type(restored) == "table" and restored.refused ~= 0) then
                first_error = first_error or (ok
                    and (restore_error or restored and restored.refused) or restored)
            end
        end
        if first_error then
            report("disable restore refused: %s", tostring(first_error))
            return nil, first_error
        end
        return true
    end

    mod._wt_reconcile_history_owner_stack = function(reason)
        return owner:reconcile(reason)
    end
    return owner
end

return M
