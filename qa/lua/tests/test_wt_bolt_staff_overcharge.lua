return function(H, repo_root)
    local Bolt = assert(loadfile(repo_root
        .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_bolt_staff_overcharge.lua"))()

    H.test("WT Bolt Staff primary heat reduction is exactly forty percent", function()
        H.equal(Bolt.desired_value(1, true), 0.6)
        H.equal(Bolt.desired_value(2.5, true), 1.5)
        H.equal(Bolt.desired_value(1, false), 1)
        H.equal(Bolt.desired_value(nil, true), nil)
    end)

    H.test("WT Bolt Staff toggle applies live and restores captured baseline", function()
        local enabled = false
        local mod = { get = function(_, id)
            H.equal(id, Bolt.SETTING_ID)
            return enabled
        end }
        local settings = { overcharge_values = { spark = 1, spear = 4 } }
        local rows = {}
        local runtime = Bolt.new_runtime(mod, settings, function(fmt, ...)
            rows[#rows + 1] = string.format(fmt, ...)
        end)
        H.truthy(runtime.apply())
        H.equal(settings.overcharge_values.spark, 1)
        enabled = true
        H.truthy(runtime.apply())
        H.equal(settings.overcharge_values.spark, 0.6)
        H.equal(settings.overcharge_values.spear, 4)
        enabled = false
        H.truthy(runtime.apply())
        H.equal(settings.overcharge_values.spark, 1)
        enabled = true
        runtime.apply()
        H.truthy(runtime.revert())
        H.equal(settings.overcharge_values.spark, 1)
        H.equal(#rows, 4)
    end)

    H.test("WT Bolt Staff heat runtime fails closed before settings exist", function()
        local runtime = Bolt.new_runtime({ get = function() return true end }, {}, function() end)
        H.equal(runtime.apply(), false)
        H.equal(runtime.revert(), false)
        H.equal(runtime.baseline(), nil)
    end)
end
