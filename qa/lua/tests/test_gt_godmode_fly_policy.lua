return function(H, repo_root)
    local policy_path = repo_root
        .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_godmode_fly_policy.lua"
    local Policy = assert(loadfile(policy_path))()

    H.test("GT Godmode blocks exactly the two authored fly entering reasons", function()
        H.equal(Policy.should_block_entry(true, true, "slow_bomb", true), true)
        H.equal(Policy.should_block_entry(true, true, "fly_bomb", true), true)

        for _, reason in ipairs({ "slow_bomb", "fly_bomb" }) do
            H.equal(Policy.should_block_entry(false, true, reason, true), false)
            H.equal(Policy.should_block_entry(nil, true, reason, true), false)
            H.equal(Policy.should_block_entry(1, true, reason, true), false)
            H.equal(Policy.should_block_entry(true, false, reason, true), false)
            H.equal(Policy.should_block_entry(true, nil, reason, true), false)
            H.equal(Policy.should_block_entry(true, 1, reason, true), false)
            H.equal(Policy.should_block_entry(true, true, reason, false), false)
            H.equal(Policy.should_block_entry(true, true, reason, nil), false)
            H.equal(Policy.should_block_entry(true, true, reason, 1), false)
        end

        H.equal(Policy.should_block_entry(true, true, "charged", true), false)
        H.equal(Policy.should_block_entry(true, true, "overpowered", true), false)
        H.equal(Policy.should_block_entry(true, true, "Slow_Bomb", true), false)
        H.equal(Policy.should_block_entry(true, true, nil, true), false)
    end)

    H.test("GT installed fly wrappers preserve exact vanilla boundaries", function()
        local runtime_path = repo_root
            .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_godmode_fly_runtime.lua"
        local Runtime = assert(loadfile(runtime_path))()
        local captured = {}
        local fake_mod = {}

        function fake_mod:hook(class_name, method_name, callback)
            local key = class_name .. "." .. method_name
            H.equal(captured[key], nil)
            captured[key] = callback
        end

        local godmode_units = {}
        local authored_blobs = {}
        local log_count = 0
        local throw_logs = false
        local installation = Runtime.install(fake_mod, {
            godmode_active = function(unit)
                return godmode_units[unit] == true
            end,
            is_authored_fly_blob = function(blob, target)
                return authored_blobs[blob] == target
            end,
            log = function()
                log_count = log_count + 1
                if throw_logs then error("diagnostic failure") end
            end,
            policy = Policy,
        })
        local status_wrapper = captured[
            "StatusUtils.set_overpowered_network"]
        local destroy_wrapper = captured[
            "OverpoweredBlobHealthExtension.destroy"]

        H.truthy(status_wrapper)
        H.truthy(destroy_wrapper)
        H.equal(status_wrapper, installation.status_wrapper)
        H.equal(destroy_wrapper, installation.destroy_wrapper)
        H.equal(log_count, 1)

        local function pack(...)
            return { n = select("#", ...), ... }
        end

        local status_calls = {}
        local function vanilla_status(...)
            status_calls[#status_calls + 1] = pack(...)
            return "status-head", nil, "status-tail"
        end
        local target = {}
        local other_target = {}
        local slow_blob = {}
        local fly_blob = {}
        local ordinary_source = {}

        local function assert_status_forward(overpowered, reason, source)
            local before = #status_calls
            local result = pack(status_wrapper(vanilla_status, target,
                overpowered, reason, source))
            H.equal(#status_calls, before + 1)
            H.equal(status_calls[#status_calls].n, 4)
            H.equal(status_calls[#status_calls][1], target)
            H.equal(status_calls[#status_calls][2], overpowered)
            H.equal(status_calls[#status_calls][3], reason)
            H.equal(status_calls[#status_calls][4], source)
            H.equal(result.n, 3)
            H.equal(result[1], "status-head")
            H.equal(result[2], nil)
            H.equal(result[3], "status-tail")
        end

        godmode_units[target] = true
        authored_blobs[slow_blob] = target
        authored_blobs[fly_blob] = target
        assert_status_forward(true, "slow_bomb", ordinary_source)
        godmode_units[target] = false
        assert_status_forward(true, "slow_bomb", slow_blob)
        godmode_units[target] = true
        assert_status_forward(false, "fly_bomb", fly_blob)
        assert_status_forward(true, "charged", slow_blob)

        throw_logs = true
        local before_block = #status_calls
        local slow_result = pack(status_wrapper(vanilla_status, target, true,
            "slow_bomb", slow_blob))
        local fly_result = pack(status_wrapper(vanilla_status, target, true,
            "fly_bomb", fly_blob))
        H.equal(#status_calls, before_block)
        H.equal(slow_result.n, 0)
        H.equal(fly_result.n, 0)
        H.equal(installation.blocked_blobs[slow_blob], target)
        H.equal(installation.blocked_blobs[fly_blob], target)
        H.equal(log_count, 3)

        local destroy_calls = {}
        local function vanilla_destroy(...)
            destroy_calls[#destroy_calls + 1] = pack(...)
            return "destroy-head", nil, "destroy-tail"
        end
        local exact_self = { unit = slow_blob, target_unit = target }
        local exact_result = pack(destroy_wrapper(
            vanilla_destroy, exact_self))
        H.equal(exact_result.n, 0)
        H.equal(#destroy_calls, 0)
        H.equal(installation.blocked_blobs[slow_blob], nil)

        local mismatch_self = {
            unit = fly_blob,
            target_unit = other_target,
        }
        local mismatch_result = pack(destroy_wrapper(
            vanilla_destroy, mismatch_self))
        H.equal(#destroy_calls, 1)
        H.equal(destroy_calls[1].n, 1)
        H.equal(destroy_calls[1][1], mismatch_self)
        H.equal(mismatch_result.n, 3)
        H.equal(mismatch_result[1], "destroy-head")
        H.equal(mismatch_result[2], nil)
        H.equal(mismatch_result[3], "destroy-tail")
        H.equal(installation.blocked_blobs[fly_blob], target)

        local ordinary_self = { unit = ordinary_source, target_unit = target }
        local ordinary_result = pack(destroy_wrapper(
            vanilla_destroy, ordinary_self))
        H.equal(#destroy_calls, 2)
        H.equal(destroy_calls[2].n, 1)
        H.equal(destroy_calls[2][1], ordinary_self)
        H.equal(ordinary_result.n, 3)
        H.equal(ordinary_result[1], "destroy-head")
        H.equal(ordinary_result[2], nil)
        H.equal(ordinary_result[3], "destroy-tail")

        local throwing_mod = { hook = function() end }
        local install_ok, second_install = pcall(Runtime.install,
            throwing_mod, {
                godmode_active = function() return false end,
                is_authored_fly_blob = function() return false end,
                log = function() error("install diagnostic failure") end,
                policy = Policy,
            })
        H.equal(install_ok, true)
        H.truthy(second_install)
    end)

    H.test("GT owns exactly the two fly-overpowered engine hooks", function()
        local main_path = repo_root
            .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/general_tweaker_dev.lua"
        local runtime_path = repo_root
            .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_godmode_fly_runtime.lua"
        local main_file = assert(io.open(main_path, "rb"))
        local main_source = main_file:read("*a")
        main_file:close()
        local runtime_file = assert(io.open(runtime_path, "rb"))
        local runtime_source = runtime_file:read("*a")
        runtime_file:close()
        local combined = main_source .. runtime_source

        local _, hook_count = combined:gsub(
            'mod:hook%("StatusUtils", "set_overpowered_network"', "")
        H.equal(hook_count, 1)
        local _, cleanup_hook_count = combined:gsub(
            'mod:hook%("OverpoweredBlobHealthExtension", "destroy"', "")
        H.equal(cleanup_hook_count, 1)
        H.equal(combined:find(
            'mod:hook%("GenericStatusExtension", "set_overpowered"'), nil)
        H.truthy(main_source:find(
            "gt-548-godmode-fly-overpowered-boundary", 1, true))
        H.truthy(main_source:find(
            "_gt548_fly_runtime.install(mod", 1, true))
        H.truthy(runtime_source:find(
            "[gt:548] fly overpowered gate installed entry=true cleanup=true reasons=slow_bomb,fly_bomb",
            1, true))
        H.truthy(main_source:find(
            'mod:command%("verify_godmode_flies"'))
    end)
end
