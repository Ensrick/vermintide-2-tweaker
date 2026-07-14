return function(H, repo_root)
    local Policy = assert(loadfile(repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_weave_curse_policy.lua"))()

    H.test("CT Weave curse catalog separates bridge preload and objective tiers", function()
        local winds, templates, lookup = {}, {}, {}
        for _, row in ipairs(Policy.CATALOG) do
            winds[row.wind] = { mutator = row.mutator }
            templates[row.mutator] = {}
            lookup[row.mutator] = 1
        end
        local result = Policy.inspect(winds, templates, lookup, 4)
        H.equal(result.total, 8)
        H.equal(result.settings, 8)
        H.equal(result.templates, 8)
        H.equal(result.wire, 8)
        H.equal(result.context_required, 8)
        H.equal(result.objective_required, 2)
        H.equal(result.resource_required, 6)
        H.equal(table.concat(result.bridge_first, ","), "metal")
        H.equal(table.concat(result.objective, ","), "beasts,light")
        H.equal(result.resources_ready, 4)
    end)

    H.test("CT Weave curse audit detects catalog and package drift", function()
        local result = Policy.inspect({ metal = { mutator = "wrong" } }, {
            metal = { packages = { "new/package" } },
        }, { metal = 1 }, 0)
        H.equal(result.settings, 0)
        H.equal(result.templates, 1)
        H.equal(result.wire, 1)
        H.equal(result.declared_packages, 1)
    end)
end
