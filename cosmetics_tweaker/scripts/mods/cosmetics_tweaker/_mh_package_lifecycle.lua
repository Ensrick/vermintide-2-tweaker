-- Material-Hijack package-reference lifecycle (issue #282).
--
-- PackageManager.unload removes its public reference immediately, but may keep
-- the resource handle in `_delayed_packages_to_remove` while a unit still uses
-- the package. The caller therefore needs two distinct states: `held` and
-- `release_pending`. Keep the latter until the engine queue actually clears.

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

    local function _is_delayed(path)
        local queue = package_manager._delayed_packages_to_remove
        return type(queue) == "table" and queue[path] ~= nil
    end

    function ledger:reconcile(reason)
        local completed = 0
        for path, state in pairs(self.registry) do
            if state == "release_pending" and not _is_delayed(path) then
                self.registry[path] = nil
                completed = completed + 1
                _emit("release_complete", path, reason)
            end
        end
        return completed
    end

    function ledger:load(path)
        self:reconcile("before_load")
        if self.registry[path] == "held" then
            return true, "dedupe"
        end

        -- Loading while the prior handle is pending is valid: PackageManager
        -- cancels delayed removal before establishing the fresh reference.
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

    function ledger:release_all(reason)
        self:reconcile("before_release")
        local requested = 0
        for path, state in pairs(self.registry) do
            if state == "held" then
                local ok, err = pcall(package_manager.unload, package_manager,
                    path, self.reference_name)
                if ok then
                    requested = requested + 1
                    if _is_delayed(path) then
                        self.registry[path] = "release_pending"
                        _emit("release_delayed", path, reason)
                    else
                        self.registry[path] = nil
                        _emit("release_complete", path, reason)
                    end
                else
                    -- Retain ownership when unload fails so a later lifecycle
                    -- boundary can retry; never erase a failed request.
                    _emit("release_failed", path, reason, err)
                end
            end
        end
        return requested
    end

    function ledger:pending_paths()
        self:reconcile("pending_query")
        local paths = {}
        for path, state in pairs(self.registry) do
            if state == "release_pending" or _is_delayed(path) then
                paths[#paths + 1] = path
            end
        end
        table.sort(paths)
        return paths
    end

    return ledger
end

return M
