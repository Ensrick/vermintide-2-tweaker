return function(H, repo_root)
    local P = dofile(repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_miasma_policy.lua")

    H.test("CT #361 Miasma sliders preserve vanilla defaults and clamp", function()
        H.equal(P.radius(nil), 8)
        H.equal(P.radius(1), 2)
        H.equal(P.radius(31), 30)
        H.equal(P.interval(nil), 1.3)
        H.equal(P.interval(0), 0.1)
        H.equal(P.interval(6), 5)
    end)

    H.test("CT #361 permanent owner changes only on pickup or death", function()
        local alive = { old = true, new = true }
        local owner, changed = P.select_owner("old", {}, function(u) return alive[u] end)
        H.equal(owner, "old")
        H.equal(changed, false)
        owner, changed = P.select_owner("old", { "new" }, function(u) return alive[u] end)
        H.equal(owner, "new")
        H.equal(changed, true)
        alive.old = false
        owner, changed = P.select_owner("old", {}, function(u) return alive[u] end)
        H.equal(owner, nil)
        H.equal(changed, true)
    end)

    H.test("CT #361 production composes one native safe area", function()
        local path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_miasma.lua"
        local f = assert(io.open(path, "rb"))
        local source = f:read("*a")
        f:close()
        H.truthy(source:find("CT_MIASMA361_CONSOLIDATED_SERVER_UPDATE", 1, true))
        H.truthy(source:find('mod:hook(server, "update"', 1, true))
        H.truthy(source:find("func(context, data, dt, t)", 1, true))
        H.truthy(source:find("data.rotten_miasma_safe_area", 1, true))
        H.equal(source:find("spawn_network_unit", 1, true), nil)
        local _, count = source:gsub('mod:hook%(server, "update"', "")
        H.equal(count, 1)
    end)
end
