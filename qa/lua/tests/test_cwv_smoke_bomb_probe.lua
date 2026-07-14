return function(H, repo_root)
    local path = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_smoke_bomb_probe.lua"
    local Probe = assert(loadfile(path))()

    H.test("CWV smoke bomb probe classifies complete runtime prerequisites", function()
        local result = Probe.classify({
            grenade_template = true,
            grenade_projectile = true,
            ranger_template = true,
            ranger_item = true,
            smoke_explosion = true,
            ranger_area_buff = true,
            buff_area_position_contract = true,
            pool_count = 4,
            pool_sum = 1,
        })
        H.truthy(result.base_ready)
        H.truthy(result.area_ready)
        H.truthy(result.pool_healthy)
        H.equal(result.exact_z_scale_ready, false)
        H.truthy(result.registration_quarantined)
        H.equal(result.status, "runtime_prereqs_ready_exact_fx_and_registration_blocked")
    end)

    H.test("CWV smoke bomb probe rejects malformed pickup pool", function()
        local result = Probe.classify({ pool_count = 2, pool_sum = 0.5 })
        H.equal(result.base_ready, false)
        H.equal(result.area_ready, false)
        H.equal(result.pool_healthy, false)
        H.equal(result.status, "runtime_prereq_missing")
    end)

    H.test("CWV smoke bomb probe is observation-only and bounded", function()
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        H.equal(Probe.MAX_RUNS, 3)
        H.equal(type(Probe.auto_run), "function")
        H.equal(source:find("rawset", 1, true), nil)
        H.equal(source:find("spawn_network_unit", 1, true), nil)
        H.equal(source:find(":add_buff(", 1, true), nil)
        H.equal(source:find("NetworkLookup.", 1, true), nil)
    end)
end
