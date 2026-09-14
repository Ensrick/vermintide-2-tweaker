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

    H.test("CT #289 documented ladder and the bounded proof cap", function()
        H.deep_equal(Policy.LADDER, { base_count = 1, levels_per_step = 2, maximum = 3 })
        H.equal(Policy.PROOF_MAX_TARGET, 2)
        H.equal(Policy.ladder_label(), "1/1/2/2/3")
        H.equal(Policy.extra_label(), "0/0/1/1/1")
        H.equal(Policy.ladder_target(0), 1)
        H.equal(Policy.ladder_target(2), 2)
        H.equal(Policy.ladder_target(4), 3)
        H.equal(Policy.ladder_target(400), 3)
        H.equal(Policy.extra_count(0), 0)
        H.equal(Policy.extra_count(1), 0)
        H.equal(Policy.extra_count(2), 1)
        H.equal(Policy.extra_count(3), 1)
        H.equal(Policy.extra_count(400), 1)
        H.equal(Policy.extra_count(nil), 0)
        H.equal(Policy.extra_count(-5), 0)
        H.equal(Policy.extra_count("2"), 1)
    end)

    H.test("CT #289 curated pair is exactly the two package-free Slaanesh pool curses", function()
        H.deep_equal(Policy.ALLOWLIST, { "curse_empathy", "curse_abundance_of_life" })
        H.equal(Policy.is_allowlisted("curse_empathy"), true)
        H.equal(Policy.is_allowlisted("curse_abundance_of_life"), true)
        H.equal(Policy.is_allowlisted("curse_monophobia"), false)
        H.equal(Policy.is_allowlisted("curse_skulls_of_fury"), false)
        H.equal(Policy.is_allowlisted(nil), false)
    end)

    local function input(overrides)
        local base = {
            node_curse = "curse_skulls_of_fury",
            vanilla = { "deus_more_hordes", "curse_skulls_of_fury", "no_sorcerers" },
            completed = 2,
            run_seed = "SEED_A",
            node_key = "node_3",
        }
        for key, value in pairs(overrides or {}) do base[key] = value end
        return base
    end

    H.test("CT #289 selector adds one allowlisted extra only above the ladder", function()
        for depth = 0, 1 do
            local extra, reason = Policy.select_extra(input({ completed = depth }))
            H.equal(extra, nil, "depth " .. depth)
            H.equal(reason, "below_ladder")
        end
        for depth = 2, 9 do
            local extra, reason = Policy.select_extra(input({ completed = depth }))
            H.equal(Policy.is_allowlisted(extra), true, "depth " .. depth)
            H.equal(reason, "selected")
        end
    end)

    H.test("CT #289 selector requires a live node curse and a numeric depth", function()
        local uncursed = input()
        uncursed.node_curse = nil
        local extra, reason = Policy.select_extra(uncursed)
        H.equal(extra, nil)
        H.equal(reason, "no_node_curse")
        extra, reason = Policy.select_extra(input({ node_curse = "" }))
        H.equal(extra, nil)
        H.equal(reason, "no_node_curse")
        -- A CT-disabled node curse is absent from vanilla's composed list.
        extra, reason = Policy.select_extra(input({ vanilla = { "deus_more_hordes" } }))
        H.equal(extra, nil)
        H.equal(reason, "node_curse_inactive")
        local no_depth = input()
        no_depth.completed = nil
        extra, reason = Policy.select_extra(no_depth)
        H.equal(extra, nil)
        H.equal(reason, "no_completed_count")
        extra, reason = Policy.select_extra(input({ completed = "2" }))
        H.equal(extra, nil)
        H.equal(reason, "no_completed_count")
        extra, reason = Policy.select_extra(nil)
        H.equal(extra, nil)
        H.equal(reason, "no_node_curse")
        extra, reason = Policy.select_extra(input({ vanilla = "not a list" }))
        H.equal(extra, nil)
        H.equal(reason, "node_curse_inactive")
    end)

    H.test("CT #289 selector never duplicates the node curse or an existing entry", function()
        local extra = Policy.select_extra(input({
            node_curse = "curse_empathy",
            vanilla = { "curse_empathy" },
        }))
        H.equal(extra, "curse_abundance_of_life")
        extra = Policy.select_extra(input({
            node_curse = "curse_abundance_of_life",
            vanilla = { "curse_abundance_of_life" },
        }))
        H.equal(extra, "curse_empathy")
        -- A weekly event that already carries one pair member leaves the other.
        extra = Policy.select_extra(input({
            vanilla = { "curse_skulls_of_fury", "curse_empathy" },
        }))
        H.equal(extra, "curse_abundance_of_life")
        local none, reason = Policy.select_extra(input({
            vanilla = { "curse_skulls_of_fury", "curse_empathy", "curse_abundance_of_life" },
        }))
        H.equal(none, nil)
        H.equal(reason, "no_candidate")
        -- Active-map shape (name -> data) is accepted as the vanilla list too.
        extra = Policy.select_extra(input({
            vanilla = { curse_skulls_of_fury = {}, curse_empathy = {} },
        }))
        H.equal(extra, "curse_abundance_of_life")
    end)

    H.test("CT #289 selector honors the exclusion callback and reports no candidate", function()
        local asked = {}
        local extra = Policy.select_extra(input(), function(name)
            asked[#asked + 1] = name
            return name == "curse_empathy"
        end)
        H.equal(extra, "curse_abundance_of_life")
        H.deep_equal(asked, { "curse_empathy", "curse_abundance_of_life" })
        local none, reason = Policy.select_extra(input(), function() return true end)
        H.equal(none, nil)
        H.equal(reason, "no_candidate")
        -- Only an explicit true excludes; truthy non-booleans do not.
        H.equal(Policy.select_extra(input(), function() return "yes" end) ~= nil, true)
    end)

    H.test("CT #289 selection is deterministic per mission and varies across missions", function()
        local first = Policy.select_extra(input())
        for _ = 1, 20 do
            H.equal(Policy.select_extra(input()), first)
        end
        local seen = {}
        for seed = 1, 40 do
            for key = 1, 5 do
                local extra = Policy.select_extra(input({
                    run_seed = "seed_" .. seed, node_key = "node_" .. key,
                }))
                H.equal(Policy.is_allowlisted(extra), true)
                seen[extra] = true
            end
        end
        H.equal(seen.curse_empathy, true, "hash never picks the first entry")
        H.equal(seen.curse_abundance_of_life, true, "hash never picks the second entry")
        H.equal(Policy.hash("a", "b"), Policy.hash("a", "b"))
        H.equal(Policy.hash("a", "b") ~= Policy.hash("ab"), true)
        H.equal(Policy.hash(nil, 2) ~= Policy.hash(2, nil), true)
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
        H.equal(result.proof_target, 2)
        H.equal(result.extra_count, 1)
        H.equal(result.node_curse, "curse_one")
        H.equal(#result.effective, 3)
        H.equal(#result.active, 3)
        H.equal(#result.package_names, 1)
        H.equal(#result.missing_template, 0)
        H.equal(#result.missing_wire, 0)
        H.equal(result.transport_ready, true)
        H.equal(result.singular_node_schema_blocks_ramp, true)
        H.equal(#result.unexpected_active, 0)
        H.equal(result.unexpected_allowlisted, true)
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
        H.equal(result.proof_target, 1)
        H.equal(result.singular_node_schema_blocks_ramp, false)
    end)

    H.test("CT #289 audit parity rule explains a client's extra only through the pair", function()
        -- Client: vanilla list is local, the CT extra arrives only via activation.
        local client = Policy.inspect({
            completed = 2,
            effective = { "curse_skulls_of_fury", "deus_more_hordes" },
            active = { curse_skulls_of_fury = {}, deus_more_hordes = {}, curse_empathy = {} },
        }, {}, {})
        H.deep_equal(client.unexpected_active, { "curse_empathy" })
        H.equal(client.unexpected_allowlisted, true)
        -- Host: the hooked list already carries the extra.
        local host = Policy.inspect({
            completed = 2,
            effective = { "curse_skulls_of_fury", "deus_more_hordes", "curse_empathy" },
            active = { curse_skulls_of_fury = {}, deus_more_hordes = {}, curse_empathy = {} },
        }, {}, {})
        H.deep_equal(host.unexpected_active, {})
        H.equal(host.unexpected_allowlisted, true)
        -- Level mutators and Twitch activations are explained, a stray curse is not.
        local explained = Policy.inspect({
            effective = { "curse_skulls_of_fury" },
            level_mutators = { "level_only" },
            twitch = { "twitch_only" },
            active = { curse_skulls_of_fury = {}, level_only = {}, twitch_only = {} },
        }, {}, {})
        H.deep_equal(explained.unexpected_active, {})
        H.equal(explained.unexpected_allowlisted, true)
        local stray = Policy.inspect({
            effective = { "curse_skulls_of_fury" },
            active = { curse_skulls_of_fury = {}, curse_monophobia = {} },
        }, {}, {})
        H.deep_equal(stray.unexpected_active, { "curse_monophobia" })
        H.equal(stray.unexpected_allowlisted, false)
        -- Two pair members at once exceed the proof cap even though both are allowlisted.
        local two = Policy.inspect({
            effective = { "curse_skulls_of_fury" },
            active = { curse_skulls_of_fury = {}, curse_empathy = {}, curse_abundance_of_life = {} },
        }, {}, {})
        H.equal(#two.unexpected_active, 2)
        H.equal(two.unexpected_allowlisted, false)
    end)
end
