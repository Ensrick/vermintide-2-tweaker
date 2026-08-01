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

    H.test("GUT issue 938 feed keeps full text and supplies only font override", function()
        local path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_damage_numbers.lua"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()

        H.truthy(source:find("DamageNumberPolicy.font_override(damage_amount, max_network_damage)",
            1, true), "runtime does not resolve the bounded visual scale")
        H.truthy(source:find("is_critical_strike, nil, nil, font_override)", 1, true),
            "runtime must pass the original damage and alter only the vanilla font override")
        H.truthy(source:find('"issue938_damage_number_visual_bound"', 1, true),
            "in-game regression check is missing")
    end)
end
