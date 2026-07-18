return function(H, repo_root)
    local path = repo_root ..
        "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_mh_package_lifecycle.lua"
    local Lifecycle = assert(loadfile(path))()

    local function manager()
        local pm = {
            _references = {},
            _delayed_packages_to_remove = {},
            live_consumers = false,
            loads = 0,
            unloads = 0,
        }
        function pm:load(package_name, reference_name)
            self.loads = self.loads + 1
            self._delayed_packages_to_remove[package_name] = nil
            self._references[package_name] = reference_name
        end
        function pm:unload(package_name, reference_name)
            H.equal(self._references[package_name], reference_name)
            self.unloads = self.unloads + 1
            self._references[package_name] = nil
            if self.live_consumers then
                self._delayed_packages_to_remove[package_name] = {}
            end
        end
        return pm
    end

    H.test("MH packages release after consumers die across repeated transitions", function()
        local pm = manager()
        local ledger = Lifecycle.new(pm, "cosmetics_tweaker_mh")
        for _ = 1, 3 do
            H.truthy(ledger:load("skin/package"))
            H.truthy(ledger:load("skin/package")) -- same-transition dedupe
            pm.live_consumers = false -- StateIngame.on_exit destroyed units/world
            H.equal(ledger:release_all("StateIngame.on_exit post"), 1)
            H.deep_equal(ledger:pending_paths(), {})
        end
        H.equal(pm.loads, 3)
        H.equal(pm.unloads, 3)
    end)

    H.test("MH immediate shutdown release leaves no delayed package", function()
        local pm = manager()
        local ledger = Lifecycle.new(pm, "cosmetics_tweaker_mh")
        ledger:load("skin/package")

        -- Boot.shutdown runs StateIngame.on_exit and then Managers:destroy with
        -- no PackageManager.update frame between them.
        pm.live_consumers = false
        ledger:release_all("StateIngame.on_exit post shutdown=true")
        H.equal(pm._delayed_packages_to_remove["skin/package"], nil)
        H.deep_equal(ledger:pending_paths(), {})
    end)

    H.test("MH ledger retains an engine-delayed release until completion", function()
        local pm = manager()
        local ledger = Lifecycle.new(pm, "cosmetics_tweaker_mh")
        ledger:load("skin/package")
        pm.live_consumers = true
        ledger:release_all("unexpected early boundary")
        H.equal(ledger.registry["skin/package"], "release_pending")
        H.deep_equal(ledger:pending_paths(), { "skin/package" })

        pm._delayed_packages_to_remove["skin/package"] = nil
        H.equal(ledger:reconcile("PackageManager.update"), 1)
        H.equal(ledger.registry["skin/package"], nil)
    end)

    H.test("Cosmetics owns one post-StateIngame release boundary", function()
        local entry_path = repo_root ..
            "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua"
        local file = assert(io.open(entry_path, "rb"))
        local source = file:read("*a")
        file:close()
        local _, hook_count = source:gsub(
            'mod:hook_safe%("StateIngame", "on_exit"', "")
        H.equal(hook_count, 1)
        H.equal(source:find('MH_EMBED.release_packages("StateIngame exit")',
            1, true), nil)
        H.truthy(source:find("StateIngame.on_exit post shutdown=", 1, true))
    end)
end
