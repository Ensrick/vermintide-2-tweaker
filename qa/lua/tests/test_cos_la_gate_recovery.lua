return function(H, repo_root)
    local Module = assert(loadfile(repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
        .. "_cos_la_gate_recovery.lua"))()

    local SAFE_OWNER = "units/weapons/player/wpn_empire_handgun_02_t2/wpn_empire_handgun_02_t2"

    local function fixture(options)
        options = options or {}
        local state = { loads = {}, logs = {} }
        local manager = {
            load = function(self, name, reference, callback, asynchronous, prioritize)
                if options.load_error then error("simulated enqueue failure") end
                state.loads[#state.loads + 1] = {
                    self = self, name = name, reference = reference,
                    callback = callback, asynchronous = asynchronous,
                    prioritize = prioritize,
                }
            end,
        }
        local owners = options.owners or { ["la-shield"] = SAFE_OWNER }
        local api = Module.new({
            owner_package = function(key) return owners[key] end,
            package_manager = function()
                if options.no_manager then return nil end
                return manager
            end,
            log = function(fmt, ...)
                state.logs[#state.logs + 1] = string.format(fmt, ...)
            end,
        })
        return api, state, manager
    end

    H.test("cos gate recovery leases a declared vanilla owner exactly once (#481)", function()
        local api, state, manager = fixture()
        local verdict, owner = api.recover(
            "parent-not-loaded", "la-shield", "cim_preview", "parent-not-loaded")
        H.equal(verdict, "lease-queued")
        H.equal(owner, SAFE_OWNER)
        H.equal(#state.loads, 1)
        local lease = state.loads[1]
        H.equal(lease.self, manager, "lease must be a method call on the manager")
        H.equal(lease.name, SAFE_OWNER)
        H.equal(lease.reference, Module.LEASE_REF)
        H.equal(lease.callback, nil)
        H.equal(lease.asynchronous, true)
        H.equal(lease.prioritize, true,
            "cwv donor-lease argument shape (name, ref, nil, async, prioritize)")

        -- Boundedness: a second refusal for the same owner never re-loads,
        -- even from a different gate.
        verdict = api.recover(
            "unit-materials", "la-shield", "loot_previewer", "material_null_0_0")
        H.equal(verdict, "lease-held")
        H.equal(#state.loads, 1)
    end)

    H.test("cos gate recovery never leases unsafe or undeclared owners", function()
        local api, state = fixture({ owners = {
            ["la-mod-owned"] = "units/loremasters_armoury/shield_custom",
            ["resource-pkg"] = "resource_packages/Loremasters-Armoury/Loremasters-Armoury",
        } })
        local verdict, owner = api.recover(
            "parent-not-loaded", "la-mod-owned", "cim_preview", "parent-not-loaded")
        H.equal(verdict, "unsafe-owner",
            "a mod-bundled unit path must never be force-loaded (#403)")
        H.equal(owner, "units/loremasters_armoury/shield_custom")
        verdict = api.recover(
            "parent-not-loaded", "resource-pkg", "cim_preview", "parent-not-loaded")
        H.equal(verdict, "unsafe-owner",
            "a third-party mod package must never be force-loaded")
        verdict, owner = api.recover(
            "parent-not-loaded", "unknown-key", "cim_preview", "parent-not-loaded")
        H.equal(verdict, "no-owner")
        H.equal(owner, nil)
        H.equal(#state.loads, 0, "no unsafe/undeclared owner may reach load()")
    end)

    H.test("cos gate recovery marker-only gates take no lease", function()
        local api, state = fixture()
        local verdict, owner = api.recover(
            "texture-set", "la-shield", "ingame", "not_resident", false)
        H.equal(verdict, "lease-not-applicable")
        H.equal(owner, SAFE_OWNER,
            "the considered owner is still reported for the log marker")
        H.equal(#state.loads, 0)
        -- A later lease-eligible refusal of the same variant still recovers.
        H.equal(api.recover(
            "unit-materials", "la-shield", "ingame", "material_null_0_0"),
            "lease-queued")
        H.equal(#state.loads, 1)
    end)

    H.test("cos gate recovery markers name the gate and stay bounded", function()
        local api, state = fixture()
        api.recover("parent-not-loaded", "la-shield", "cim_preview", "parent-not-loaded")
        api.recover("parent-not-loaded", "la-shield", "cim_preview", "parent-not-loaded")
        H.equal(#state.logs, 1, "one marker per (gate, key)")
        H.truthy(state.logs[1]:find("gate=parent-not-loaded", 1, true))
        H.truthy(state.logs[1]:find("key=la-shield", 1, true))
        H.truthy(state.logs[1]:find("ctx=cim_preview", 1, true))
        H.truthy(state.logs[1]:find("recovery=lease-queued", 1, true))
        api.recover("unit-materials", "la-shield", "ingame", "material_null_0_0")
        H.equal(#state.logs, 2, "a different gate for the same key marks again")
        H.truthy(state.logs[2]:find("gate=unit-materials", 1, true))
        H.truthy(state.logs[2]:find("recovery=lease-held", 1, true))

        -- Marker cap: unbounded distinct keys cannot spam the session log.
        local capped, capped_state = fixture({ owners = {} })
        for i = 1, Module.MAX_MARKERS + 10 do
            capped.recover("gate", "key-" .. i, "ctx", "reason", false)
        end
        H.equal(#capped_state.logs, Module.MAX_MARKERS)
        local marked = 0
        for _ in pairs(capped.debug_state().marked) do marked = marked + 1 end
        H.equal(marked, Module.MAX_MARKERS)
    end)

    H.test("cos gate recovery degrades without a package manager", function()
        local api, state = fixture({ no_manager = true })
        local verdict = api.recover(
            "parent-not-loaded", "la-shield", "cim_preview", "parent-not-loaded")
        H.equal(verdict, "no-manager")
        H.equal(#state.loads, 0)
        -- The manager appearing later still allows the one bounded lease.
        local late, late_state = fixture()
        H.equal(late.recover(
            "parent-not-loaded", "la-shield", "cim_preview", "parent-not-loaded"),
            "lease-queued")
        H.equal(#late_state.loads, 1)
    end)

    H.test("cos gate recovery survives a throwing enqueue", function()
        local api, state = fixture({ load_error = true })
        local verdict = api.recover(
            "parent-not-loaded", "la-shield", "cim_preview", "parent-not-loaded")
        H.equal(verdict, "lease-error")
        H.equal(#state.loads, 0)
        H.equal(api.recover(
            "unit-materials", "la-shield", "ingame", "material_null_0_0"),
            "lease-held",
            "a throwing enqueue still consumes the single bounded attempt")
    end)
end
