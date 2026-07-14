local function register(Harness, repo_root)
    local core = dofile(repo_root .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_disconnect_grace_core.lua")

    Harness.test("gt disconnect probe consumes one explicit arm", function()
        local state = core.new()
        Harness.equal(core.begin(state, "peer-a", 2, 0), nil)
        core.arm(state)
        local trace = core.begin(state, "peer-a", 2, 1)
        Harness.truthy(trace)
        Harness.equal(core.begin(state, "peer-b", 3, 2), nil)
        Harness.equal(state.armed, false)
    end)

    Harness.test("gt disconnect probe sample schedule is bounded", function()
        local state = core.new()
        core.arm(state)
        local trace = core.begin(state, "peer-a", 2, 10)
        core.record(trace, "pre", 10, {})
        core.record(trace, "post", 10, {})

        for _, offset in ipairs(core.SAMPLE_OFFSETS) do
            local due, actual = core.take_due(state, 10 + offset)
            Harness.equal(due, trace)
            Harness.equal(actual, offset)
            core.record(trace, "sample", 10 + offset, {})
        end

        Harness.equal(core.take_due(state, 100), nil)
        Harness.equal(#trace.records, 2 + #core.SAMPLE_OFFSETS)
        Harness.equal(core.finish_if_complete(state), trace)
        Harness.equal(state.active, nil)
    end)

    Harness.test("gt disconnect probe only correlates matching peer rejoin", function()
        local state = core.new()
        core.arm(state)
        local trace = core.begin(state, "peer-a", 2, 0)
        Harness.equal(core.note_rejoin(state, "peer-b", 1, {}), false)
        Harness.truthy(core.note_rejoin(state, "peer-a", 2, { player = true }))
        Harness.equal(trace.records[1].phase, "rejoin")
    end)
end

return register
