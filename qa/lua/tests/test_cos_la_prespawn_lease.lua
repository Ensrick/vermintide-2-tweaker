return function(H, repo_root)
    local Module = assert(loadfile(repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
        .. "_cos_la_prespawn_lease.lua"))()

    local function fixture(options)
        options = options or {}
        local state = { loads = {}, logs = {}, gettable = options.gettable }
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
        local api = Module.new({
            package_manager = function()
                if options.no_manager then return nil end
                return manager
            end,
            can_get = function(kind, path)
                if state.gettable == nil then return true end
                return state.gettable[path] == true
            end,
            has_loaded = function(pkg)
                return options.loaded and options.loaded[pkg] == true
            end,
            la_present = function()
                if options.la_absent then return false end
                return true
            end,
            log = function(fmt, ...)
                state.logs[#state.logs + 1] = string.format(fmt, ...)
            end,
        })
        return api, state, manager
    end

    H.test("cos prespawn lease map keys the exact #940-traced unit paths", function()
        local expected = {
            ["units/decorations/LA_message_board_mesh"] = Module.BRETON_SKIN_PACKAGE,
            ["units/decorations/LA_message_board_back_board"] = Module.BRETON_SKIN_PACKAGE,
            ["units/decorations/letters/LA_quest_message_stage01_visable"] = Module.BRETON_SKIN_PACKAGE,
            ["units/empire_shield/Kruber_Empire_shield02_mesh"] =
                "units/weapons/player/wpn_empire_handgun_02_t2/wpn_empire_handgun_02_t2",
            ["units/empire_shield/Kruber_Empire_shield02_mesh_3p"] =
                "units/weapons/player/wpn_empire_handgun_02_t2/wpn_empire_handgun_02_t2_3p",
        }
        local count = 0
        for unit_path, packages in pairs(Module.UNIT_PARENT_PACKAGES) do
            count = count + 1
            H.equal(#packages, 1, "one declared parent per traced unit")
            H.equal(packages[1], expected[unit_path],
                "parent package for " .. tostring(unit_path))
        end
        H.equal(count, 5, "exactly the five traced unit paths (letter + board + back board + shield pair)")
    end)

    H.test("cos prespawn lease safety: only declared vanilla packages", function()
        for _, packages in pairs(Module.UNIT_PARENT_PACKAGES) do
            for _, pkg in ipairs(packages) do
                local weapon_class = pkg:find("units/weapons/player/", 1, true) == 1
                local declared_skin = pkg == Module.BRETON_SKIN_PACKAGE
                H.equal(weapon_class or declared_skin, true,
                    "unsafe lease target: " .. tostring(pkg))
                H.equal(pkg:find("units/cwv_", 1, true), nil,
                    "mod-bundled path must never be leased")
            end
        end
    end)

    H.test("cos prespawn lease queues one bounded lease per distinct package", function()
        local api, state, manager = fixture()
        local verdicts, status = api.lease_all()
        H.equal(status, "leased")
        -- 3 distinct packages: breton skin + shield 1p + shield 3p.
        H.equal(#state.loads, 3)
        local seen = {}
        for _, lease in ipairs(state.loads) do
            H.equal(seen[lease.name], nil, "duplicate lease for " .. tostring(lease.name))
            seen[lease.name] = true
            H.equal(lease.self, manager, "lease must be a method call on the manager")
            H.equal(lease.reference, Module.LEASE_REF)
            H.equal(lease.callback, nil)
            H.equal(lease.asynchronous, true)
            H.equal(lease.prioritize, true,
                "cwv donor-lease argument shape (name, ref, nil, async, prioritize)")
        end
        H.equal(verdicts[Module.BRETON_SKIN_PACKAGE], "queued")
        -- Second pass: session-bounded, no re-lease.
        api.lease_all()
        H.equal(#state.loads, 3, "second lease_all must not re-queue")
    end)

    H.test("cos prespawn lease fails closed on preflight and absent LA", function()
        local api, state = fixture({ gettable = {} })  -- nothing gettable
        local verdicts = api.lease_all()
        H.equal(#state.loads, 0, "non-gettable packages must never be enqueued")
        H.equal(verdicts[Module.BRETON_SKIN_PACKAGE], "not-gettable")

        local api2, state2 = fixture({ la_absent = true })
        local _, status = api2.lease_all()
        H.equal(status, "la-absent")
        H.equal(#state2.loads, 0, "no lease without Loremaster's Armoury present")

        local api3, state3 = fixture({ load_error = true })
        local verdicts3 = api3.lease_all()
        H.equal(verdicts3[Module.BRETON_SKIN_PACKAGE], "error",
            "enqueue faults must be caught, never propagate")
        H.equal(#state3.loads, 0)
    end)

    H.test("cos prespawn observe records residency once per traced path", function()
        local api, state = fixture({
            loaded = { [Module.BRETON_SKIN_PACKAGE] = true },
        })
        api.lease_all()
        H.equal(api.observe_spawn("units/keep/some_untraced_unit"), nil)
        H.equal(api.observe_spawn("units/decorations/LA_message_board_mesh"), "recorded")
        H.equal(api.observe_spawn("units/decorations/LA_message_board_mesh"), "observed",
            "re-spawn of the same path must not add receipts")
        local observed_line
        for _, line in ipairs(state.logs) do
            if line:find("pre-spawn observe", 1, true) then observed_line = line end
        end
        H.equal(type(observed_line), "string", "observe receipt missing")
        H.equal(observed_line:find("resident=true", 1, true) ~= nil, true,
            "observe receipt must carry the has_loaded verdict")
        H.equal(observed_line:find("[cos:696]", 1, true), 1,
            "receipts stay on the bounded [cos:696] channel")
    end)

    H.test("cos prespawn observe late-heals a missed boot lease", function()
        local api, state = fixture()
        -- No lease_all yet (boot path missed): observing a traced spawn must
        -- queue the lease for the rest of the session.
        api.observe_spawn("units/empire_shield/Kruber_Empire_shield02_mesh_3p")
        H.equal(#state.loads, 1)
        H.equal(state.loads[1].name,
            "units/weapons/player/wpn_empire_handgun_02_t2/wpn_empire_handgun_02_t2_3p")
    end)
end
