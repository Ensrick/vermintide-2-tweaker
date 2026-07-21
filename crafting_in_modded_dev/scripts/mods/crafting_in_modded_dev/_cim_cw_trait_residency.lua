-- #947: CIM can persist Chaos Wastes (Morris) weapon traits and use them in
-- Adventure. `deus_ranged_crit_explosion` creates `fx/cw_enemy_explosion`
-- from a string at hit time, so the weapon unit does not pull the particle in
-- as a dependency. Every vanilla Chaos Wastes level explicitly loads the one
-- package below; Adventure levels do not. If it is absent, WorldApi asserts
-- below Lua and terminates the process -- pcall around the hit cannot help.
--
-- Keep one private, session-long reference. This is intentionally acquired at
-- CIM initialization/state transition, never from a weapon action or per-frame
-- path, and intentionally has no unload path: a persisted item may retain the
-- trait after a setting changes. Source provenance:
--   levels/honduras_dlcs/morris/deus_level_settings.lua
--   scripts/settings/dlcs/morris/morris_buff_settings.lua

local PACKAGE = "resource_packages/dlcs/morris_ingame"
local REFERENCE = "cim_dev_cw_trait_fx"

return function(context)
    context = context or {}
    local get_package_manager = assert(context.get_package_manager,
        "get_package_manager is required")
    local print_line = context.print_line or function() end
    local mod = context.mod
    local rt_register = context.rt_register

    local state = {
        attempts = 0,
        load_requests = 0,
        status = "uninitialized",
        last_error = nil,
    }
    local last_manager = nil
    local request_issued = false
    local last_reported = nil

    local function report(status, detail)
        state.status = status
        state.last_error = status == "load_failed" and tostring(detail) or nil
        local signature = status .. ":" .. tostring(detail or "")
        if signature ~= last_reported then
            last_reported = signature
            print_line("[cim:947] package=%s ref=%s state=%s detail=%s requests=%d",
                PACKAGE, REFERENCE, status, tostring(detail or "none"),
                state.load_requests)
        end
    end

    local function package_call(package_manager, method_name)
        local method = package_manager and package_manager[method_name]
        if type(method) ~= "function" then
            return true, false
        end
        return pcall(method, package_manager, PACKAGE, REFERENCE)
    end

    local controller = {
        PACKAGE = PACKAGE,
        REFERENCE = REFERENCE,
    }

    function controller.ensure()
        state.attempts = state.attempts + 1
        local package_manager = get_package_manager()
        if not package_manager then
            report("manager_unavailable")
            return false, state.status
        end

        if package_manager ~= last_manager then
            last_manager = package_manager
            request_issued = false
        end

        local ok_loaded, loaded = package_call(package_manager, "has_loaded")
        if not ok_loaded then
            report("load_failed", "has_loaded: " .. tostring(loaded))
            return false, state.status
        end
        if loaded then
            report("resident")
            return true, state.status
        end

        local ok_loading, loading = package_call(package_manager, "is_loading")
        if not ok_loading then
            report("load_failed", "is_loading: " .. tostring(loading))
            return false, state.status
        end
        if loading then
            report("loading")
            return false, state.status
        end

        -- Latch a successful request per PackageManager instance so repeated
        -- state callbacks cannot enqueue duplicate acquisitions before
        -- `is_loading` reflects the async request.
        if request_issued then
            report("requested")
            return false, state.status
        end

        state.load_requests = state.load_requests + 1
        -- resource-safety: cim947-morris-trait-particles
        local ok_load, load_error = pcall(function()
            package_manager:load(PACKAGE, REFERENCE, nil, true, true)
        end)
        if not ok_load then
            report("load_failed", load_error)
            return false, state.status
        end

        request_issued = true
        report("requested")
        return false, state.status
    end

    function controller.snapshot()
        return {
            attempts = state.attempts,
            load_requests = state.load_requests,
            status = state.status,
            last_error = state.last_error,
            package = PACKAGE,
            reference = REFERENCE,
        }
    end

    if type(rt_register) == "function" then
        rt_register("issue947_morris_trait_particle_package_resident", function()
            local resident, status = controller.ensure()
            if resident then return nil end
            if status == "manager_unavailable" or status == "loading"
                    or status == "requested" then
                return "skip: Morris trait package " .. tostring(status)
            end
            local snapshot = controller.snapshot()
            return string.format(
                "Morris trait package unavailable: status=%s error=%s",
                tostring(snapshot.status), tostring(snapshot.last_error))
        end)
    end

    if mod and type(mod.command) == "function" then
        mod:command("verify_cim_cw_trait_residency",
            "Report whether CIM's Chaos Wastes trait particle package is resident",
            function()
                local resident = controller.ensure()
                local snapshot = controller.snapshot()
                mod:echo("[cim:947] %s package=%s ref=%s requests=%d",
                    resident and "PASS resident" or string.upper(snapshot.status),
                    snapshot.package, snapshot.reference, snapshot.load_requests)
            end)
    end

    return controller
end
