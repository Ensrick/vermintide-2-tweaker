-- _wt_deepwood_runtime.lua
--
-- Owner-gated residency policy for the Deepwood Staff's native Sister of the
-- Thorn runtime assets. The weapon unit alone is insufficient: its secondary
-- action asks WeaponSystem to spawn the native plague-vortex unit, which is
-- supplied by the complete we_thornsister career package.

local M = {
    CAREER_PACKAGE = "resource_packages/careers/we_thornsister",
    DLC_KEY = "woods",
    DLC_BOOT_PACKAGE = "resource_packages/dlcs/woods",
    REFERENCE_NAME = "wt_deepwood_runtime",
    VORTEX_UNIT = "units/weapons/enemy/wpn_chaos_plague_vortex/wpn_chaos_plague_vortex",
}
local _printf = rawget(_G, "printf") or function() end

function M.new(deps)
    deps = deps or {}
    local state = {
        requested = false,
        attempts = 0,
        last_error = nil,
    }

    local function package_manager()
        return deps.package_manager and deps.package_manager() or nil
    end

    local function has_loaded(path)
        local manager = package_manager()
        if not (manager and manager.has_loaded) then return false end
        local ok, loaded = pcall(manager.has_loaded, manager, path)
        return ok and loaded == true
    end

    local function is_loading(path, reference_name)
        local manager = package_manager()
        if not (manager and manager.is_loading) then return false end
        local ok, loading = pcall(manager.is_loading, manager, path,
            reference_name)
        return ok and loading and true or false
    end

    local function reference_count(path, reference_name)
        local manager = package_manager()
        if not (manager and manager.reference_count) then return nil end
        local ok, count = pcall(manager.reference_count, manager, path,
            reference_name)
        if not ok or type(count) ~= "number" then return nil end
        return count
    end

    local function owned()
        local unlock = deps.unlock_manager and deps.unlock_manager() or nil
        if unlock and unlock.dlc_exists and unlock.is_dlc_unlocked then
            local ok_exists, exists = pcall(unlock.dlc_exists, unlock, M.DLC_KEY)
            local ok_owned, is_owned = pcall(
                unlock.is_dlc_unlocked, unlock, M.DLC_KEY)
            if ok_exists and exists and ok_owned and is_owned then
                return true
            end
        end
        return has_loaded(M.DLC_BOOT_PACKAGE)
    end

    local function ready()
        return has_loaded(M.CAREER_PACKAGE)
    end

    local function ensure()
        if ready() then return true, "resident" end
        if not owned() then return false, "not_owned_or_unresolved" end
        if state.requested then return false, "loading" end

        local manager = package_manager()
        if not (manager and manager.load) then
            return false, "package_manager_unavailable"
        end

        state.attempts = state.attempts + 1
        local ok, err = pcall(manager.load, manager, M.CAREER_PACKAGE,
            M.REFERENCE_NAME, nil, true, true)
        if not ok then
            state.last_error = tostring(err)
            return false, "load_failed"
        end
        state.requested = true
        state.last_error = nil
        local is_ready = ready()

        return is_ready, is_ready and "resident" or "loading"
    end

    local function retry()
        if ready() then return true end

        -- PackageManager.load increments the named reference immediately,
        -- including when the package is already in the async/queued set. A
        -- state transition during that flight must preserve the request latch
        -- or the following ensure() adds another reference and callback.
        if is_loading(M.CAREER_PACKAGE, M.REFERENCE_NAME) then
            state.requested = true
            return false
        end

        state.requested = false
        return false
    end

    local function status()
        return {
            owned = owned(),
            ready = ready(),
            requested = state.requested,
            loading = is_loading(M.CAREER_PACKAGE, M.REFERENCE_NAME),
            reference_count = reference_count(M.CAREER_PACKAGE,
                M.REFERENCE_NAME),
            attempts = state.attempts,
            last_error = state.last_error,
        }
    end

    return {
        owned = owned,
        ready = ready,
        ensure = ensure,
        retry = retry,
        status = status,
    }
end

function M.install(mod, deps)
    local runtime = M.new(deps)
    local last_reason = nil
    local vortex_block_logged = false
    local residency_ready = runtime.ready()

    function mod._force_load_deepwood_runtime_package(retry)
        if retry then runtime.retry() end
        local is_ready, reason = runtime.ensure()
        if reason ~= last_reason then
            last_reason = reason
            local status = runtime.status()
            if reason == "load_failed" then
                _printf("[wt:282] Deepwood runtime package load failed: %s",
                    tostring(status.last_error))
            else
                _printf("[wt:282] Deepwood package lease state=%s ready=%s loading=%s references=%s attempts=%s",
                    tostring(reason), tostring(is_ready),
                    tostring(status.loading), tostring(status.reference_count),
                    tostring(status.attempts))
            end
        end
        return is_ready
    end

    mod._force_load_deepwood_runtime_package()
    mod:hook("WeaponSystem", "_summon_vortex",
        function(func, self, position, target_unit, owner_unit)
            if runtime.ready() then
                return func(self, position, target_unit, owner_unit)
            end
            mod._force_load_deepwood_runtime_package()
            if not vortex_block_logged then
                vortex_block_logged = true
                _printf("[wt:201] blocked Deepwood vortex spawn while native runtime unit was non-resident")
            end
            return nil
        end)

    local previous_update = mod.update
    mod.update = function(dt)
        if previous_update then previous_update(dt) end
        local now_ready = runtime.ready()
        if now_ready ~= residency_ready then
            residency_ready = now_ready
            if deps.on_residency_changed then
                deps.on_residency_changed(now_ready)
            end
        end
    end

    return runtime
end

return M
