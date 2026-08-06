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
            self._references[package_name] = self._references[package_name] or {}
            local refs = self._references[package_name]
            refs[reference_name] = (refs[reference_name] or 0) + 1
        end
        function pm:unload(package_name, reference_name)
            local refs = assert(self._references[package_name])
            H.truthy((refs[reference_name] or 0) > 0)
            self.unloads = self.unloads + 1
            refs[reference_name] = refs[reference_name] - 1
            if refs[reference_name] == 0 then refs[reference_name] = nil end
            if next(refs) == nil then self._references[package_name] = nil end
        end
        function pm:reference_count(package_name, reference_name)
            local refs = self._references[package_name]
            return refs and refs[reference_name] or 0
        end
        function pm:destroy()
            local owned = {}
            for package_name, refs in pairs(self._references) do
                for reference_name, count in pairs(refs) do
                    owned[#owned + 1] = { package_name, reference_name, count }
                end
            end
            for _, entry in ipairs(owned) do
                for _ = 1, entry[3] do self:unload(entry[1], entry[2]) end
            end
        end
        return pm
    end

    H.test("MH packages remain exactly-once resident across transitions", function()
        local pm = manager()
        local ledger = Lifecycle.new(pm, "cosmetics_tweaker_mh")
        for _ = 1, 3 do
            H.truthy(ledger:load("skin/package"))
            H.truthy(ledger:load("skin/package")) -- same-transition dedupe
        end
        H.equal(pm.loads, 1)
        H.equal(pm.unloads, 0)
        H.deep_equal(ledger:held_paths(), { "skin/package" })
        H.deep_equal(ledger:reference_summary(), {
            held = 1, exact = 1, over = 0, missing = 0,
        })
    end)

    H.test("MH ledger reinitialization adopts the existing session reference", function()
        local pm = manager()
        local first = Lifecycle.new(pm, "cosmetics_tweaker_mh")
        H.equal(select(2, first:load("skin/package")), "loaded")
        local reloaded = Lifecycle.new(pm, "cosmetics_tweaker_mh")
        H.equal(select(2, reloaded:load("skin/package")), "adopted")
        H.equal(pm.loads, 1)
        H.equal(pm:reference_count("skin/package", "cosmetics_tweaker_mh"), 1)
    end)

    H.test("MH summary exposes inherited over-reference without mutating it", function()
        local pm = manager()
        pm:load("skin/package", "cosmetics_tweaker_mh")
        pm:load("skin/package", "cosmetics_tweaker_mh")
        local ledger = Lifecycle.new(pm, "cosmetics_tweaker_mh")
        H.equal(select(2, ledger:load("skin/package")), "adopted")
        H.deep_equal(ledger:reference_summary(), {
            held = 1, exact = 0, over = 1, missing = 0,
        })
        H.equal(pm.loads, 2)
        H.equal(pm.unloads, 0)
    end)

    H.test("MH summary fails closed when reference evidence is unavailable", function()
        local pm = manager()
        pm.reference_count = nil
        local ledger = Lifecycle.new(pm, "cosmetics_tweaker_mh")
        H.equal(select(2, ledger:load("skin/package")), "loaded")
        H.deep_equal(ledger:reference_summary(), {
            held = 1, exact = 0, over = 0, missing = 1,
        })
    end)

    H.test("MH release is owned only by PackageManager destroy", function()
        local pm = manager()
        local ledger = Lifecycle.new(pm, "cosmetics_tweaker_mh")
        ledger:load("skin/package")
        H.equal(ledger.release_all, nil)
        H.equal(ledger.reconcile, nil)
        H.equal(ledger.pending_paths, nil)
        H.equal(pm.unloads, 0)
        pm:destroy()
        H.equal(pm.unloads, 1)
        H.equal(pm:reference_count("skin/package", "cosmetics_tweaker_mh"), 0)
    end)

    H.test("Cosmetics has no StateIngame or mod-unload MH release boundary", function()
        local entry_path = repo_root ..
            "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua"
        local file = assert(io.open(entry_path, "rb"))
        local source = file:read("*a")
        file:close()
        local lifecycle_path = repo_root ..
            "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_mod_lifecycle.lua"
        file = assert(io.open(lifecycle_path, "rb"))
        source = source .. "\n" .. file:read("*a")
        file:close()
        local _, hook_count = source:gsub(
            'mod:hook_safe%("StateIngame", "on_exit"', "")
        H.equal(hook_count, 0)
        H.equal(source:find("MH_EMBED.release_packages", 1, true), nil)
        H.equal(source:find("MH_EMBED.reconcile_packages", 1, true), nil)
        H.truthy(source:find("teardown_owner=PackageManager.destroy", 1, true))

        local embed_path = repo_root ..
            "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_material_hijack_embedded.lua"
        local embed_file = assert(io.open(embed_path, "rb"))
        local embed_source = embed_file:read("*a")
        embed_file:close()
        H.equal(embed_source:find("manager_package.unload", 1, true), nil)
        H.equal(embed_source:find("manager_package:unload", 1, true), nil)
    end)
end
