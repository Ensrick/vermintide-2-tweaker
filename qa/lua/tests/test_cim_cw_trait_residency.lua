-- #947 regression lock for the native Morris particle-package crash.
-- resource-safety: cim947-morris-trait-particles
return function(H, repo_root)
    local module_path = repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
        .. "_cim_cw_trait_residency.lua"

    local function new_manager()
        local manager = { loaded = false, loading = false, loads = {} }
        function manager:has_loaded(package, reference)
            self.last_has_loaded = { package, reference }
            return self.loaded
        end
        function manager:is_loading(package, reference)
            self.last_is_loading = { package, reference }
            return self.loading
        end
        function manager:load(package, reference, callback, async, prioritize)
            self.loads[#self.loads + 1] = {
                package, reference, callback, async, prioritize,
            }
        end
        return manager
    end

    local function new_controller(manager_getter, lines)
        return assert(loadfile(module_path))()({
            get_package_manager = manager_getter,
            print_line = function(fmt, ...)
                lines[#lines + 1] = string.format(fmt, ...)
            end,
        })
    end

    H.test("CIM #947 requests exact Morris package once and asynchronously", function()
        local manager = new_manager()
        local controller = new_controller(function() return manager end, {})

        local resident, status = controller.ensure()
        H.equal(resident, false)
        H.equal(status, "requested")
        H.equal(#manager.loads, 1)
        H.equal(manager.loads[1][1], "resource_packages/dlcs/morris_ingame")
        H.equal(manager.loads[1][2], "cim_dev_cw_trait_fx")
        H.equal(manager.loads[1][3], nil)
        H.equal(manager.loads[1][4], true)
        H.equal(manager.loads[1][5], true)

        controller.ensure()
        controller.ensure()
        H.equal(#manager.loads, 1, "repeated lifecycle calls duplicated the lease")
        H.equal(controller.snapshot().load_requests, 1)
    end)

    H.test("CIM #947 observes loading and resident without duplicate loads", function()
        local manager = new_manager()
        manager.loading = true
        local controller = new_controller(function() return manager end, {})

        local resident, status = controller.ensure()
        H.equal(resident, false)
        H.equal(status, "loading")
        H.equal(#manager.loads, 0)

        manager.loading = false
        manager.loaded = true
        resident, status = controller.ensure()
        H.equal(resident, true)
        H.equal(status, "resident")
        H.equal(#manager.loads, 0)
        H.equal(manager.last_has_loaded[1], controller.PACKAGE)
        H.equal(manager.last_has_loaded[2], controller.REFERENCE)
    end)

    H.test("CIM #947 retries when PackageManager appears on a later lifecycle edge", function()
        local manager = nil
        local controller = new_controller(function() return manager end, {})
        local resident, status = controller.ensure()
        H.equal(resident, false)
        H.equal(status, "manager_unavailable")

        manager = new_manager()
        resident, status = controller.ensure()
        H.equal(resident, false)
        H.equal(status, "requested")
        H.equal(#manager.loads, 1)
    end)

    H.test("CIM #947 installs one runtime check and one explicit report command", function()
        local manager = new_manager()
        manager.loaded = true
        local checks = {}
        local commands = {}
        local fake_mod = { echo = function() end }
        function fake_mod:command(name, description, callback)
            commands[name] = { description = description, callback = callback }
        end
        local controller = assert(loadfile(module_path))()({
            mod = fake_mod,
            rt_register = function(name, callback) checks[name] = callback end,
            get_package_manager = function() return manager end,
        })
        H.truthy(controller)
        H.equal(type(checks.issue947_morris_trait_particle_package_resident), "function")
        H.equal(checks.issue947_morris_trait_particle_package_resident(), nil)
        H.equal(type(commands.verify_cim_cw_trait_residency.callback), "function")
    end)

    H.test("CIM #947 controller owns no unload or action-hook path", function()
        local file = assert(io.open(module_path, "rb"))
        local source = file:read("*a")
        file:close()
        H.equal(source:find(":unload", 1, true), nil)
        H.equal(source:find("mod:hook", 1, true), nil)
        H.equal(source:find("on_hit", 1, true), nil)
        H.truthy(source:find("resource-safety: cim947-morris-trait-particles", 1, true))
    end)
end
