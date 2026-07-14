return function(H, repo_root)
    local Policy = assert(loadfile(repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_modifier_stack_policy.lua"))()

    H.test("CT #289 modifier ramp is bounded and stage-based", function()
        H.equal(Policy.ramp_target(0, 1, 2, 3), 1)
        H.equal(Policy.ramp_target(1, 1, 2, 3), 1)
        H.equal(Policy.ramp_target(2, 1, 2, 3), 2)
        H.equal(Policy.ramp_target(4, 1, 2, 3), 3)
        H.equal(Policy.ramp_target(99, 1, 2, 3), 3)
    end)

    H.test("CT #289 audit classifies stack transport requirements", function()
        local result = Policy.inspect({
            completed = 4,
            node_curse = "curse_one",
            minor = { "minor_one" },
            events = { "event_one" },
            effective = { "minor_one", "curse_one", "event_one" },
            active = { curse_one = {}, minor_one = {}, event_one = {} },
            maximum = 3,
        }, {
            curse_one = { packages = { "package/curse" } },
            minor_one = {},
            event_one = {},
        }, { curse_one = 1, minor_one = 2, event_one = 3 })
        H.equal(result.target, 3)
        H.equal(result.node_curse, "curse_one")
        H.equal(#result.effective, 3)
        H.equal(#result.active, 3)
        H.equal(#result.package_names, 1)
        H.equal(#result.missing_template, 0)
        H.equal(#result.missing_wire, 0)
        H.equal(result.transport_ready, true)
        H.equal(result.singular_node_schema_blocks_ramp, true)
        H.equal(result.effective_signature, Policy.signature({ "event_one", "curse_one", "minor_one" }))
    end)

    H.test("CT #289 audit rejects duplicates and unregistered names", function()
        local result = Policy.inspect({
            effective = { "known", "known", "unknown" },
        }, { known = {} }, { known = 1 })
        H.equal(result.duplicate_count, 1)
        H.equal(table.concat(result.missing_template, ","), "unknown")
        H.equal(table.concat(result.missing_wire, ","), "unknown")
        H.equal(result.transport_ready, false)
    end)
end
