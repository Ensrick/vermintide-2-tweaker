-- Material-Hijack package-reference lifecycle (issue #282).
--
-- These packages back materials used by player, preview, and renderer objects
-- whose native lifetime extends beyond Lua's StateIngame teardown callbacks.
-- Own exactly one PackageManager reference per path for the process session;
-- PackageManager.destroy is the sole release owner. Manual level-exit or
-- mod-unload release can race PatchedResourcePackage/renderer retirement even
-- when PackageManager.can_unload reports true.

local M = {}

function M.new(package_manager, reference_name, emit)
    assert(package_manager, "package_manager is required")
    assert(type(reference_name) == "string" and reference_name ~= "",
        "reference_name is required")

    local ledger = {
        registry = {},
        reference_name = reference_name,
    }

    local function _emit(event, path, reason, detail)
        if emit then emit(event, path, reason, detail) end
    end

    local function _reference_count(path)
        if type(package_manager.reference_count) ~= "function" then
            return nil
        end
        local ok, count = pcall(package_manager.reference_count,
            package_manager, path, reference_name)
        if not ok then return nil end
        return tonumber(count) or 0
    end

    function ledger:load(path)
        if self.registry[path] == "held" then
            return true, "dedupe"
        end

        -- If this Lua ledger is reinitialized while PackageManager keeps the
        -- process-owned reference, adopt it instead of incrementing it again.
        -- (Cosmetics hot reload itself remains unsupported.) A pre-existing
        -- count above one is preserved for PackageManager.destroy to drain;
        -- never try to repair it while a native consumer may still be alive.
        local existing = _reference_count(path)
        if existing and existing > 0 then
            self.registry[path] = "held"
            _emit("adopted", path, nil, existing)
            return true, "adopted"
        end

        local ok, err = pcall(package_manager.load, package_manager, path,
            self.reference_name)
        if not ok then
            _emit("load_failed", path, nil, err)
            return false, err
        end

        self.registry[path] = "held"
        _emit("first_load", path)
        return true, "loaded"
    end

    function ledger:held_paths()
        local paths = {}
        for path, state in pairs(self.registry) do
            if state == "held" then
                paths[#paths + 1] = path
            end
        end
        table.sort(paths)
        return paths
    end

    function ledger:reference_summary()
        local summary = { held = 0, exact = 0, over = 0, missing = 0 }
        for path, state in pairs(self.registry) do
            if state == "held" then
                summary.held = summary.held + 1
                local count = _reference_count(path)
                if count == nil then
                    -- Fail the health summary closed if the API drifts or
                    -- throws. Never report exact ownership without evidence.
                    summary.missing = summary.missing + 1
                elseif count == 1 then
                    summary.exact = summary.exact + 1
                elseif count > 1 then
                    summary.over = summary.over + 1
                else
                    summary.missing = summary.missing + 1
                end
            end
        end
        return summary
    end

    return ledger
end

return M
