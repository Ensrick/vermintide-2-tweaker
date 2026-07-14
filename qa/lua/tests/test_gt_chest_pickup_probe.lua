local function register(Harness, repo_root)
    local core = dofile(repo_root .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_chest_pickup_probe_core.lua")

    Harness.test("gt chest probe requires one explicit arm", function()
        local state = core.new()
        Harness.equal(core.take_classification(state, "pickup-a"), false)
        Harness.equal(core.record(state, "pickup-a", "available", {}), false)
        core.arm(state)
        Harness.truthy(core.take_classification(state, "pickup-a"))
        Harness.equal(core.take_classification(state, "pickup-a"), false)
    end)

    Harness.test("gt chest probe deduplicates lifecycle phases", function()
        local state = core.new()
        core.arm(state)
        Harness.truthy(core.record(state, "pickup-a", "nav", { result = false }))
        Harness.equal(core.record(state, "pickup-a", "nav", { result = true }), false)
        Harness.truthy(core.record(state, "pickup-a", "loot", { result = true }))
        Harness.equal(state.count, 2)
    end)

    Harness.test("gt chest probe caps records and classifications", function()
        local state = core.new()
        core.arm(state)
        for i = 1, core.MAX_CLASSIFICATIONS do
            Harness.truthy(core.take_classification(state, "pickup-" .. i))
        end
        Harness.equal(core.take_classification(state, "overflow"), false)

        for i = 1, core.MAX_RECORDS do
            Harness.truthy(core.record(state, "pickup-" .. i, "phase", {}))
        end
        Harness.equal(state.armed, false)
        Harness.equal(state.count, core.MAX_RECORDS)
        Harness.equal(core.record(state, "extra", "phase", {}), false)
    end)
end

return register
