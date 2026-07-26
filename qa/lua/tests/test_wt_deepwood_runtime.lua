return function(H, repo_root)
    local public_root = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/"
    local dev_root = repo_root .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/"

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function load_policy(root)
        return dofile(root .. "_wt_deepwood_runtime.lua")
    end

    local function fixture(policy, options)
        options = options or {}
        local loaded = options.loaded or {}
        local load_calls = {}
        local fail_count = options.fail_count or 0
        local package_manager = {
            has_loaded = function(_, path)
                return loaded[path] == true
            end,
            load = function(_, path, reference, callback, prioritize, async)
                load_calls[#load_calls + 1] = {
                    path = path,
                    reference = reference,
                    callback = callback,
                    prioritize = prioritize,
                    async = async,
                }
                if #load_calls <= fail_count then error("synthetic load failure") end
            end,
        }
        local unlock_manager = {
            dlc_exists = function() return options.dlc_exists == true end,
            is_dlc_unlocked = function() return options.dlc_owned == true end,
        }
        local runtime = policy.new({
            package_manager = function() return package_manager end,
            unlock_manager = function() return unlock_manager end,
        })
        return runtime, loaded, load_calls
    end

    H.test("WT #201 Deepwood runtime is owner-gated and fail-closed", function()
        local policy = load_policy(public_root)
        local runtime, _, calls = fixture(policy)
        local ready, reason = runtime.ensure()
        H.equal(ready, false)
        H.equal(reason, "not_owned_or_unresolved")
        H.equal(#calls, 0)
        H.equal(runtime.ready(), false)
    end)

    H.test("WT #201 Woods boot package is an early ownership proxy", function()
        local policy = load_policy(public_root)
        local runtime, loaded, calls = fixture(policy, {
            loaded = { [policy.DLC_BOOT_PACKAGE] = true },
        })
        local ready, reason = runtime.ensure()
        H.equal(ready, false)
        H.equal(reason, "loading")
        H.equal(#calls, 1)
        H.equal(calls[1].path, policy.CAREER_PACKAGE)
        H.equal(calls[1].reference, policy.REFERENCE_NAME)

        runtime.ensure()
        H.equal(#calls, 1, "an in-flight request must not add package references")

        loaded[policy.CAREER_PACKAGE] = true
        ready, reason = runtime.ensure()
        H.equal(ready, true)
        H.equal(reason, "resident")
        H.equal(#calls, 1)
    end)

    H.test("WT #201 failed synchronous package request remains retryable", function()
        local policy = load_policy(public_root)
        local runtime, _, calls = fixture(policy, {
            dlc_exists = true,
            dlc_owned = true,
            fail_count = 1,
        })
        local ready, reason = runtime.ensure()
        H.equal(ready, false)
        H.equal(reason, "load_failed")
        H.truthy(runtime.status().last_error:find("synthetic load failure", 1, true))

        ready, reason = runtime.ensure()
        H.equal(ready, false)
        H.equal(reason, "loading")
        H.equal(#calls, 2)
        H.equal(runtime.status().attempts, 2)
    end)

    H.test("WT #201 state transition retries a stalled asynchronous request", function()
        local policy = load_policy(public_root)
        local runtime, _, calls = fixture(policy, {
            dlc_exists = true,
            dlc_owned = true,
        })
        runtime.ensure()
        runtime.ensure()
        H.equal(#calls, 1)
        runtime.retry()
        local ready, reason = runtime.ensure()
        H.equal(ready, false)
        H.equal(reason, "loading")
        H.equal(#calls, 2,
            "one state transition may retry with the same bounded package reference")
    end)

    H.test("WT #201 cast and availability reopen only for the complete package", function()
        local policy = load_policy(public_root)
        local loaded = {
            [policy.DLC_BOOT_PACKAGE] = true,
        }
        local load_calls = {}
        local hook
        local transitions = {}
        local delegates = 0
        local fake_mod = {
            hook = function(_, _, method, callback)
                H.equal(method, "_summon_vortex")
                hook = callback
            end,
            info = function() end,
            warning = function() end,
        }
        policy.install(fake_mod, {
            package_manager = function()
                return {
                    has_loaded = function(_, path) return loaded[path] == true end,
                    load = function(_, path)
                        load_calls[#load_calls + 1] = path
                    end,
                }
            end,
            unlock_manager = function() return nil end,
            on_residency_changed = function(ready)
                transitions[#transitions + 1] = ready
            end,
        })
        local delegate = function()
            delegates = delegates + 1
            return "spawned"
        end

        H.equal(hook(delegate, {}, {}, {}, {}), nil)
        H.equal(delegates, 0,
            "a visible vortex unit or partial graph must never bypass the package")
        loaded[policy.CAREER_PACKAGE] = true
        fake_mod.update(0.016)
        H.equal(#transitions, 1)
        H.equal(transitions[1], true)
        H.equal(hook(delegate, {}, {}, {}, {}), "spawned")
        H.equal(delegates, 1)
    end)

    H.test("WT #201 public beta and dev use the same residency policy", function()
        H.equal(read(public_root .. "_wt_deepwood_runtime.lua"),
            read(dev_root .. "_wt_deepwood_runtime.lua"))
        for _, root in ipairs({ public_root, dev_root }) do
            local entry_name = root:find("weapon_tweaker_dev", 1, true)
                and "weapon_tweaker_dev.lua" or "weapon_tweaker.lua"
            local entry = read(root .. entry_name)
            local availability = read(root .. "_wt_availability.lua")
            local runtime_source = read(root .. "_wt_deepwood_runtime.lua")
            H.truthy(entry:find(").install(mod, {", 1, true))
            H.truthy(runtime_source:find("Deepwood runtime package state=", 1, true))
            H.truthy(runtime_source:find(
                'mod:hook("WeaponSystem", "_summon_vortex"', 1, true))
            H.equal(runtime_source:find("Application.can_get", 1, true), nil)
            H.truthy(runtime_source:find(
                "if runtime.ready() then", 1, true))
            H.truthy(runtime_source:find(
                "deps.on_residency_changed(now_ready)", 1, true))
            local state_change = assert(entry:find("mod.on_game_state_changed = function", 1, true))
            local ensure = assert(entry:find(
                "mod._force_load_deepwood_runtime_package(true)", state_change, true))
            local apply = assert(entry:find("apply_weapon_unlocks()", state_change, true))
            H.truthy(ensure < apply, "residency request must precede availability")
            H.truthy(availability:find(
                'if weapon_key ~= "we_life_staff" then return true end', 1, true))
            H.truthy(availability:find(
                'return nil, "runtime_package_not_ready"', 1, true))
        end
    end)
end
