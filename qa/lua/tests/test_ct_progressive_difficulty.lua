return function(H, repo_root)
    local policy = dofile(repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_progressive_difficulty.lua")

    local vanilla_difficulties = {
        "normal", "hard", "harder", "hardest", "cataclysm",
        "cataclysm_2", "cataclysm_3", "versus_base",
    }
    local vanilla_lookup = {}
    for i, key in ipairs(vanilla_difficulties) do
        vanilla_lookup[i], vanilla_lookup[key] = key, i
    end

    H.test("CT #460 difficulty steps only on maps three and five", function()
        H.equal(policy.step_count(0), 0)
        H.equal(policy.step_count(1), 0)
        H.equal(policy.step_count(2), 1)
        H.equal(policy.step_count(3), 1)
        H.equal(policy.step_count(4), 2)
        H.equal(policy.step_count(100), 2)
        H.equal(policy.difficulty("hardest", 1, vanilla_difficulties, vanilla_lookup), "hardest")
        H.equal(policy.difficulty("hardest", 2, vanilla_difficulties, vanilla_lookup), "cataclysm")
        H.equal(policy.difficulty("hardest", 3, vanilla_difficulties, vanilla_lookup), "cataclysm")
        H.equal(policy.difficulty("hardest", 4, vanilla_difficulties, vanilla_lookup), "cataclysm_2")
    end)

    H.test("CT #460 cap uses Cata 5 when registered and never Versus", function()
        local difficulties = {
            "normal", "hard", "harder", "hardest", "cataclysm",
            "cataclysm_2", "cataclysm_3", "cataclysm_4", "cataclysm_5", "versus_base",
        }
        local lookup = {}
        for i, key in ipairs(difficulties) do lookup[i], lookup[key] = key, i end
        H.equal(policy.difficulty("cataclysm_3", 2, difficulties, lookup), "cataclysm_4")
        H.equal(policy.difficulty("cataclysm_3", 4, difficulties, lookup), "cataclysm_5")
        H.equal(policy.difficulty("cataclysm_5", 100, difficulties, lookup), "cataclysm_5")
        H.equal(policy.difficulty("cataclysm_3", 100, vanilla_difficulties, vanilla_lookup), "cataclysm_3")
    end)

    H.test("CT #460 coin reduction begins on map three and clamps input", function()
        H.equal(policy.coin_multiplier(2, -25, 1), 2)
        H.equal(policy.coin_multiplier(2, -25, 2), 1.5)
        H.equal(policy.coin_multiplier(2, -25, 4), 1.5)
        H.equal(policy.coin_multiplier(2, -100, 2), 0)
        H.equal(policy.coin_multiplier(2, -200, 2), 0)
        H.equal(policy.coin_multiplier(2, 50, 2), 2)
    end)

    H.test("CT #460 production wires both advanced host-effective settings", function()
        local path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua"
        local f = assert(io.open(path, "rb"))
        local source = f:read("*a")
        f:close()
        H.truthy(source:find('effective_setting("progressive_difficulty_increase")', 1, true))
        H.truthy(source:find('effective_setting("progressive_coin_reduction")', 1, true))
        H.truthy(source:find("mod._ct_progressive_policy", 1, true))
        H.truthy(source:find("policy.coin_multiplier", 1, true))
        H.truthy(source:find("mod._ct_progressive_policy.difficulty", 1, true))
    end)
end
