return function(H, repo_root)
    local Policy = assert(loadfile(repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_progressive_elite_policy.lua"))()

    H.test("CT #323 elite modifier chance follows mission progression", function()
        H.equal(Policy.rate(0), 0)
        H.equal(Policy.rate(1), 5)
        H.equal(Policy.rate(2), 10)
        H.equal(Policy.rate(3), 15)
        H.equal(Policy.rate(4), 20)
        H.equal(Policy.rate(100), 20)
    end)

    H.test("CT #323 candidate classifier excludes monsters and trash", function()
        H.equal(Policy.classify_breed({ elite = true }), "elite")
        H.equal(Policy.classify_breed({ special = true }), "special")
        H.equal(Policy.classify_breed({ boss = true, elite = true }), "other")
        H.equal(Policy.classify_breed({}), "other")
        H.equal(Policy.classify_breed(nil), "other")
    end)

    H.test("CT #323 deterministic sampler respects exact rate boundaries", function()
        local bucket = Policy.bucket(42, "chaos_warrior")
        H.equal(bucket >= 0 and bucket < 100, true)
        H.equal(Policy.would_apply(42, "chaos_warrior", 0), false)
        H.equal(Policy.would_apply(42, "chaos_warrior", 100), bucket < 20)
        H.equal(Policy.bucket(42, "chaos_warrior"), bucket)
    end)

    H.test("CT #323 catalog separates boss-only from elite-proven modifiers", function()
        local enhancements, boss = {}, {}
        for _, row in ipairs(Policy.CATALOG) do
            enhancements[row.name] = {}
            if row.tier == "boss_unproven" then boss[row.name] = true end
        end
        local result = Policy.inspect_catalog(enhancements, boss)
        H.equal(result.total, 15)
        H.equal(result.templates, 15)
        H.equal(result.boss_catalog, 13)
        H.equal(result.boss_registered, 13)
        H.equal(result.elite_source_proven, 2)
        H.equal(#result.missing, 0)
    end)
end
