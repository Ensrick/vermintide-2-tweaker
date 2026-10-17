return function(H, repo_root)
    local public_root = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/"
    local dev_root = repo_root .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/"

    local function install(root)
        local checks, commands = {}, {}
        local mod = {
            command = function(_, name)
                commands[#commands + 1] = name
            end,
        }
        local deps = {}
        if root == dev_root then
            deps.dev_hold_pose = {}
            deps.hold_pose_checks = dofile(
                root .. "_wt_runtime_checks_hold_pose.lua")
        end
        dofile(root .. "_wt_runtime_checks.lua").install(mod, function(name, check)
            H.equal(type(check), "function")
            checks[#checks + 1] = name
        end, deps)
        return checks, commands
    end

    -- Tests 1 and 2 are order-preservation guards: the registration surface they
    -- pin is identical before and after the #2 split, so they also pass on the
    -- inline source. Tests 3 to 6 are the ones that tell the split apart.
    H.test("WT common runtime-check extraction preserves beta registration surface", function()
        local checks, commands = install(public_root)
        H.equal(#checks, 61)
        H.equal(checks[1], "husk_extension_hooked")
        H.equal(checks[#checks], "issue943_fire_sword_heavy_contract")
        H.equal(#commands, 1)
        H.equal(commands[1], "verify_wt_availability_sort")
    end)

    H.test("WT dev runtime-check extraction keeps only its marked overlay additions", function()
        local checks, commands = install(dev_root)
        H.equal(#checks, 71)
        H.equal(checks[1], "husk_extension_hooked")
        H.equal(checks[#checks], "issue943_fire_sword_heavy_contract")
        H.equal(#commands, 1)
        H.equal(commands[1], "verify_wt_availability_sort")
        -- #2: the shipped Hold-Pose child registers in the historical slot,
        -- between the #569 Greathammer check and the #316 Longbow checks.
        local window = {
            "issue569_wp_hammer_remap_orientation_scope",
            "issue168_hold_pose_independent_hands",
            "issue569_hold_pose_composition",
            "issue616_hold_pose_channel_bypass_restore",
            "issue616_hold_pose_live_edit_delivery",
            "issue616_hold_pose_nonuniform_scale",
            "issue316_kruber_longbow_zoom_contract",
        }
        for i, name in ipairs(window) do
            H.equal(checks[47 + i], name)
        end
    end)

    H.test("WT dev Hold-Pose runtime-check owner preserves exact registration boundary", function()
        local owner = dofile(dev_root .. "_wt_runtime_checks_hold_pose.lua")
        local names, callbacks = {}, {}
        owner.install(function(name, callback)
            names[#names + 1] = name
            callbacks[#callbacks + 1] = callback
        end, nil)
        local expected = {
            "issue168_hold_pose_independent_hands",
            "issue569_hold_pose_composition",
            "issue616_hold_pose_channel_bypass_restore",
            "issue616_hold_pose_live_edit_delivery",
            "issue616_hold_pose_nonuniform_scale",
        }
        H.equal(#names, #expected)
        for i, name in ipairs(expected) do
            H.equal(names[i], name)
            H.equal(type(callbacks[i]), "function")
            H.truthy(type(callbacks[i]()) == "string",
                "missing Hold-Pose dependency did not fail closed")
        end
    end)

    H.test("WT dev common registrar invokes Hold-Pose owner once in place and propagates errors", function()
        local install_count, names = 0, {}
        local sentinel = {}
        local owner = {
            install = function(register, hold_pose)
                install_count = install_count + 1
                H.equal(hold_pose, sentinel)
                register("hold_pose_first", function() end)
                register("hold_pose_last", function() end)
            end,
        }
        dofile(dev_root .. "_wt_runtime_checks.lua").install({
            command = function() end,
        }, function(name)
            names[#names + 1] = name
        end, { dev_hold_pose = sentinel, hold_pose_checks = owner })
        H.equal(install_count, 1)
        local first, last, following
        for i, name in ipairs(names) do
            if name == "hold_pose_first" then first = i end
            if name == "hold_pose_last" then last = i end
            if name == "issue316_kruber_longbow_zoom_contract" then following = i end
        end
        H.truthy(first and last and following)
        H.equal(last, first + 1)
        H.equal(following, last + 1)

        local ok, err = pcall(function()
            dofile(dev_root .. "_wt_runtime_checks.lua").install({
                command = function() end,
            }, function() end, {
                dev_hold_pose = sentinel,
                hold_pose_checks = { install = function()
                    error("planted Hold-Pose owner failure")
                end },
            })
        end)
        H.equal(ok, false)
        H.truthy(tostring(err):find("planted Hold-Pose owner failure", 1, true))
    end)

    H.test("WT dev registrar turns a missing Hold-Pose owner into one failing check", function()
        -- mod:dofile returns nil when the child fails to load; registration must
        -- continue so the entry still reaches the dev tool installs after it.
        local names, callbacks = {}, {}
        local ok, err = pcall(function()
            dofile(dev_root .. "_wt_runtime_checks.lua").install({
                command = function() end,
            }, function(name, callback)
                names[#names + 1] = name
                callbacks[name] = callback
            end, { dev_hold_pose = {} })
        end)
        H.truthy(ok, "missing Hold-Pose owner aborted registration: " .. tostring(err))
        H.equal(#names, 67)
        local slot
        for i, name in ipairs(names) do
            if name == "issue2_hold_pose_runtime_check_owner" then slot = i end
        end
        H.truthy(slot, "missing-owner check was not registered")
        H.equal(names[slot - 1], "issue569_wp_hammer_remap_orientation_scope")
        H.equal(names[slot + 1], "issue316_kruber_longbow_zoom_contract")
        H.equal(names[#names], "issue943_fire_sword_heavy_contract")
        local verdict = callbacks.issue2_hold_pose_runtime_check_owner()
        H.equal(type(verdict), "string")
        H.truthy(verdict:sub(1, 5) ~= "skip:", "a missing owner must FAIL, not SKIP")
    end)

    H.test("WT dev Hold-Pose checks pass against the real Hold-Pose owner", function()
        local prior_get_mod = _G.get_mod
        _G.get_mod = function()
            return { get = function() return nil end }
        end
        local loaded, hold_pose = pcall(dofile, dev_root .. "wt_dev_hold_pose.lua")
        _G.get_mod = prior_get_mod
        H.truthy(loaded, "wt_dev_hold_pose.lua failed to load: " .. tostring(hold_pose))
        local registered = {}
        dofile(dev_root .. "_wt_runtime_checks_hold_pose.lua").install(function(name, callback)
            registered[#registered + 1] = { name = name, callback = callback }
        end, hold_pose)
        H.equal(#registered, 5)
        for _, entry in ipairs(registered) do
            local verdict = entry.callback()
            H.equal(verdict, nil, entry.name .. " did not PASS: " .. tostring(verdict))
        end
    end)
end
