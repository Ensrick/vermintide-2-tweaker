return function(H, repo_root)
    local policy_path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_damage_numbers_policy.lua"
    local Policy = assert(loadfile(policy_path))()

    H.test("GUT issue 938 preserves ordinary vanilla damage-number scale", function()
        H.equal(Policy.font_override(1, 255.75), 1)
        H.equal(Policy.font_override(255.75, 255.75), 1)
        H.equal(Policy.vanilla_text_size(100, Policy.font_override(100, 255.75)), 115)
    end)

    H.test("GUT issue 938 bounds only high-damage visual scale", function()
        local maximum = 255.75
        local override = Policy.font_override(9999, maximum)
        H.truthy(math.abs(override - maximum / 9999) < 0.0000001)
        H.truthy(math.abs(Policy.vanilla_text_size(9999, override)
            - Policy.vanilla_text_size(maximum, 1)) < 0.0001)
    end)

    H.test("GUT issue 938 policy fails open when engine bound is unavailable", function()
        H.equal(Policy.font_override(9999, nil), 1)
        H.equal(Policy.font_override(9999, 0), 1)
        H.equal(Policy.font_override(nil, 255.75), 1)
        H.equal(Policy.font_override(-1, 255.75), 1)
    end)

    H.test("GUT issue 938 in-window burst chunks sum to one pending popup", function()
        -- The damage_utils.lua:1969-1981 split shape: N network-max chunks plus a
        -- remainder, all landing at the same instant.
        local maximum = 255.75
        local groups = {}
        local first = Policy.accumulate(groups, "k", maximum, false, 10)
        Policy.accumulate(groups, "k", maximum, false, 10)
        local merged, displaced = Policy.accumulate(groups, "k", 40.5, true, 10)
        H.equal(merged, first)
        H.equal(displaced, nil)
        H.truthy(math.abs(first.amount - (maximum * 2 + 40.5)) < 0.0001)
        H.equal(first.is_critical_strike, true,
            "a critical chunk must mark the aggregated popup critical")
        H.truthy(Policy.font_override(first.amount, maximum) < 1,
            "the summed above-boundary popup must engage the font bound")
    end)

    H.test("GUT issue 938 out-of-window chunk starts a new popup", function()
        local groups = {}
        local window = Policy.AGGREGATION_WINDOW
        H.truthy(type(window) == "number" and window > 0)
        local first = Policy.accumulate(groups, "k", 100, false, 10)
        H.equal(Policy.is_due(first, 10), false)
        -- window * 2 sidesteps the binary-float boundary at exactly t + window.
        H.equal(Policy.is_due(first, 10 + window * 2), true)
        local fresh, displaced = Policy.accumulate(groups, "k", 5, false, 10 + window * 2)
        H.truthy(fresh ~= first, "an expired group must not absorb a late chunk")
        H.equal(displaced, first,
            "the displaced popup must be handed back for emission")
        H.equal(fresh.amount, 5)
        H.equal(groups["k"], fresh)
    end)

    H.test("GUT issue 938 keys aggregate independently", function()
        local groups = {}
        Policy.accumulate(groups, "unit_a:cutting", 10, false, 10)
        local other = Policy.accumulate(groups, "unit_a:burn", 20, false, 10)
        H.equal(other.amount, 20, "a different damage type must not merge")
        H.equal(groups["unit_a:cutting"].amount, 10)
    end)

    H.test("GUT issue 938 runtime hooks the popup chokepoint and reads the engine bound", function()
        local path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_damage_numbers.lua"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()

        H.truthy(source:find('mod:hook("DamageUtils", "add_unit_floating_damage_numbers"', 1, true),
            "runtime must aggregate at the single popup chokepoint (#938 rework)")
        H.truthy(source:find("DamageNumberPolicy.accumulate(", 1, true),
            "runtime does not route chunks through the aggregation policy")
        H.truthy(source:find("DamageNumberPolicy.is_due(", 1, true),
            "runtime never flushes pending popups by window")
        H.truthy(source:find('"issue938_damage_number_burst_aggregation"', 1, true),
            "in-game regression check is missing")
        H.truthy(source:find("constants and constants.damage and constants.damage.max", 1, true),
            "runtime must read NetworkConstants.damage.max at runtime")
        H.equal(source:find("local max_damage = 255.75", 1, true), nil,
            "the regression check must not hard-code the network damage bound")
    end)
end
